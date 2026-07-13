param(
    [Parameter(Mandatory=$true)]
    [string]$ManualRetrySuffix,
    
    [Parameter(Mandatory=$true)]
    [string]$CsvPath
)

$API_URL = "http://10.49.120.220:7001/TaxFacade/ws/tax" # NOW POINTING AT PROD; MDW08
$CSV_PATH = $CsvPath # Dynamic CSV path
$LOG_SUCCESS = "retry_success_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$LOG_FAILED = "retry_failed_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

Write-Host "Manual retry suffix for this run: $ManualRetrySuffix" -ForegroundColor Cyan

if (-not (Test-Path $CSV_PATH)) {
    Write-Host "CSV file not found: $CSV_PATH" -ForegroundColor Red
    exit 1
}

$data = Import-Csv $CSV_PATH

if ($data.Count -eq 0) {
    Write-Host "CSV file is empty, nothing to process." -ForegroundColor Yellow
    exit 0
}

# --- Required column validation ---
# Catch a missing/misspelled/reordered column up front, before looping through
# every row and failing halfway (or worse, silently sending blank values).
$requiredColumns = @("TRANSACTION_DATE","RECEIPT_NUMBER","SHORTCODE","AMOUNT","BRAND","REASON_TYPE","TRANSACTION_TYPE")

# Fields that must have an actual value (TRANSACTION_TYPE excluded — confirmed blank is valid business logic)
$mandatoryValueColumns = @("TRANSACTION_DATE","RECEIPT_NUMBER","SHORTCODE","AMOUNT","REASON_TYPE")

$csvColumns = ($data | Get-Member -MemberType NoteProperty).Name
$missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }

if ($missingColumns.Count -gt 0) {
    Write-Host "CSV is missing required column(s): $($missingColumns -join ', ')" -ForegroundColor Red
    exit 1
}

$invalidDates = $data | Where-Object { $_.TRANSACTION_DATE -notmatch '^\d{14}$' }
if ($invalidDates.Count -gt 0) {
    Write-Host "CSV contains invalid TRANSACTION_DATE format. It must be exactly 14 digits (YYYYMMDDHHmmss)." -ForegroundColor Red
    exit 1
}

$total = $data.Count
$i = 0
$successCount = 0
$failCount = 0
$skipCount = 0

foreach ($row in $data) {
    $i++
    Write-Host "[$i/$total] Processing $($row.RECEIPT_NUMBER)..." -NoNewline

    # Row-level validation: skip rows with blank required fields instead of
    # silently sending an incomplete payload to the API.
    $blankFields = $mandatoryValueColumns | Where-Object { [string]::IsNullOrWhiteSpace($row.$_) }
    if ($blankFields.Count -gt 0) {
        Write-Host " SKIPPED (blank: $($blankFields -join ', '))" -ForegroundColor Yellow
        Add-Content -Path $LOG_FAILED -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') SKIPPED - Row $i - Blank field(s): $($blankFields -join ', ')"
        $skipCount++
        continue
    }

    $curr_ts = Get-Date -Format "yyyyMMddHHmmss"

    # Guard against double-marking with the SAME suffix this run is using
    # (e.g. script re-run on the same file, or a resubmitted row).
    # The CSV is expected to contain the BARE original receipt number (no
    # suffix at all) — this only protects against accidental re-runs.
    if ($row.RECEIPT_NUMBER -match ([regex]::Escape($ManualRetrySuffix) + "$")) {
        Add-Content -Path $LOG_FAILED -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') SKIPPED - $($row.RECEIPT_NUMBER) - Already marked as $ManualRetrySuffix, not retried again"
        Write-Host " SKIPPED (already $ManualRetrySuffix)" -ForegroundColor Yellow
        $skipCount++
        continue
    }

    # Append this round's manual-retry suffix to the bare receipt number
    # (e.g. round 1 -> _MR1, round 2 -> _MR2, round 3 -> _MR3, ...)
    $newReceipt = "$($row.RECEIPT_NUMBER)$ManualRetrySuffix"

    # Business rule: AMOUNT must be multiplied by 100 before hitting the API.
    # Validate it's a real number first — a bad/non-numeric AMOUNT must never
    # silently reach the API as a corrupted value.
    $parsedAmount = 0
    if (-not [decimal]::TryParse($row.AMOUNT, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsedAmount)) {
        Write-Host " SKIPPED (invalid AMOUNT: '$($row.AMOUNT)')" -ForegroundColor Yellow
        Add-Content -Path $LOG_FAILED -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') SKIPPED - $($row.RECEIPT_NUMBER) - Invalid AMOUNT value: '$($row.AMOUNT)'"
        $skipCount++
        continue
    }
    $amountForApi = $parsedAmount * 100

    $payload = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><soapenv:Envelope xmlns:soapenv=`"http://schemas.xmlsoap.org/soap/envelope/`"><soapenv:Header><cps:HeaderInfo xmlns:cps=`"http://cps.huawei.com/`" soapenv:mustUnderstand=`"0`"><cps:SessionId>AG_20260602_10101dbf3a83763c5c70</cps:SessionId><cps:Timestamp></cps:Timestamp><cps:LoginID xsi:nil=`"true`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`"/><cps:Password/></cps:HeaderInfo></soapenv:Header><soapenv:Body><cps:RequestInfo xmlns:cps=`"http://cps.huawei.com/`"><cps:Msisdn>&lt;PublishNotificationRequest>&lt;Header>&lt;CommandID>TransactionNotification&lt;/CommandID>&lt;Version>1.0&lt;/Version>&lt;SessionId>AG_20260602_10101dbf3a83763c5c70&lt;/SessionId>&lt;Timestamp>$curr_ts&lt;/Timestamp>&lt;LoginID>&lt;/LoginID>&lt;Password>&lt;/Password>&lt;/Header>&lt;Body>&lt;Parameters>&lt;Parameter>&lt;Key>CreditShortCode&lt;/Key>&lt;Value>$($row.SHORTCODE)&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>ReasonType&lt;/Key>&lt;Value>$($row.REASON_TYPE)&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>Date/Timestamp&lt;/Key>&lt;Value>$($row.TRANSACTION_DATE)&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>PrincipleTransactionAmount&lt;/Key>&lt;Value>$amountForApi&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>ReceiptNumber&lt;/Key>&lt;Value>$newReceipt&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Tax Information][NPWP ID]&lt;/Key>&lt;Value>&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Tax Information][NPWP Type]&lt;/Key>&lt;Value>&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Tax Information][NPWP Status]&lt;/Key>&lt;Value>&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Organization Details][Brand]&lt;/Key>&lt;Value>$($row.BRAND)&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>OriginalTransactionType&lt;/Key>&lt;Value>$($row.TRANSACTION_TYPE)&lt;/Value>&lt;/Parameter>&lt;/Parameters>&lt;/Body>&lt;/PublishNotificationRequest></cps:Msisdn></cps:RequestInfo></soapenv:Body></soapenv:Envelope>"

    try {
        $response = Invoke-WebRequest -Uri $API_URL -Method Post -ContentType "text/xml; charset=utf-8" -Headers @{SOAPAction="`"Calculate`""} -Body $payload -TimeoutSec 15 -UseBasicParsing
        Add-Content -Path $LOG_SUCCESS -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') SUCCESS - $newReceipt - Code: $($response.StatusCode) - Response: $($response.Content -replace '\s+',' ')"
        Write-Host " OK ($($response.StatusCode))"
        $successCount++
    } catch {
        Add-Content -Path $LOG_FAILED -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') FAILED - $newReceipt - $($_.Exception.Message)"
        Write-Host " FAILED" -ForegroundColor Red
        $failCount++
    }

    Start-Sleep -Milliseconds 500   # optional: uncomment if you want a small delay between requests to avoid hammering the API across ~1,000 rows
}
Write-Host "Retry processing finished."
Write-Host "`nDone. Success: $successCount | Failed: $failCount | Skipped: $skipCount"

## HOW TO RUN
##  Open PowerShell in the script folder and run:
##
##      .\v2_tax_retry_production.ps1 -ManualRetrySuffix "_MR1"
##
##  Use the NEXT round number each time:
##      1st manual retry  -> -ManualRetrySuffix "_MR1"
##      2nd manual retry  -> -ManualRetrySuffix "_MR2"
##      3rd manual retry  -> -ManualRetrySuffix "_MR3"
##      (and so on)

# sample format csv
# "TRANSACTION_DATE","RECEIPT_NUMBER","SHORTCODE","AMOUNT","BRAND","REASON_TYPE","TRANSACTION_TYPE"
# "20260703122111","04201700037241475697","1083718",10000,IM3,6275,