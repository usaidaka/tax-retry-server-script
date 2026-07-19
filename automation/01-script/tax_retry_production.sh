#!/bin/bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_ROOT}/config.sh"

SUFFIX=""
CSV_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --suffix) SUFFIX="$2"; shift 2 ;;
    --csv) CSV_FILE="$2"; shift 2 ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
done

if [[ -z "$SUFFIX" || -z "$CSV_FILE" ]]; then
  echo "Error: Missing --suffix or --csv"
  exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_USER=${SUDO_USER:-$(whoami)}
LOG_SUCCESS="${SCRIPT_ROOT}/retry_success_${SUFFIX}_${RUN_USER}_${TIMESTAMP}_$$.log"
LOG_FAILED="${SCRIPT_ROOT}/retry_failed_${SUFFIX}_${RUN_USER}_${TIMESTAMP}_$$.log"
RUNS_LOG="${SCRIPT_ROOT}/runs.log"

echo "Manual retry suffix for this run: $SUFFIX"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "CSV file not found: $CSV_FILE"
  exit 1
fi

TOTAL_ROWS=$(($(wc -l < "$CSV_FILE") - 1))
if [[ $TOTAL_ROWS -le 0 ]]; then
  echo "CSV file is empty, nothing to process."
  exit 0
fi

# Extract headers and validate
IFS=',' read -r -a HEADERS < "$CSV_FILE"
REQUIRED_COLS=("TRANSACTION_DATE" "RECEIPT_NUMBER" "SHORTCODE" "AMOUNT" "BRAND" "REASON_TYPE" "TRANSACTION_TYPE")

get_col_idx() {
  local target="$1"
  for i in "${!HEADERS[@]}"; do
    local col_name=$(echo "${HEADERS[$i]}" | tr -d '\r\n"')
    if [[ "$col_name" == "$target" ]]; then
      echo "$i"
      return 0
    fi
  done
  echo ""
}

for col in "${REQUIRED_COLS[@]}"; do
  idx=$(get_col_idx "$col")
  if [[ -z "$idx" ]]; then
    echo "CSV is missing required column: $col"
    exit 1
  fi
done

IDX_RECEIPT=$(get_col_idx "RECEIPT_NUMBER")
IDX_DATE=$(get_col_idx "TRANSACTION_DATE")
IDX_SHORTCODE=$(get_col_idx "SHORTCODE")
IDX_AMOUNT=$(get_col_idx "AMOUNT")
IDX_BRAND=$(get_col_idx "BRAND")
IDX_REASON=$(get_col_idx "REASON_TYPE")
IDX_TXTYPE=$(get_col_idx "TRANSACTION_TYPE")

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

escape_xml() {
  echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# Process rows
i=0
while IFS=',' read -r -a ROW; do
  ((i++)) || true
  if [[ $i -eq 1 ]]; then continue; fi # Skip header
  
  RECEIPT_NUMBER=$(echo "${ROW[$IDX_RECEIPT]:-}" | tr -d '"')
  TRANSACTION_DATE=$(echo "${ROW[$IDX_DATE]:-}" | tr -d '"')
  SHORTCODE=$(echo "${ROW[$IDX_SHORTCODE]:-}" | tr -d '"')
  AMOUNT=$(echo "${ROW[$IDX_AMOUNT]:-}" | tr -d '"')
  BRAND=$(echo "${ROW[$IDX_BRAND]:-}" | tr -d '"')
  REASON_TYPE=$(echo "${ROW[$IDX_REASON]:-}" | tr -d '"')
  TRANSACTION_TYPE=$(echo "${ROW[$IDX_TXTYPE]:-}" | tr -d '"')

  echo -n "[$((i-1))/$TOTAL_ROWS] Processing ${RECEIPT_NUMBER}..."

  # Mandatory fields check
  BLANK_FIELDS=""
  for col_idx in "$IDX_DATE" "$IDX_RECEIPT" "$IDX_SHORTCODE" "$IDX_AMOUNT" "$IDX_REASON"; do
    VAL=$(echo "${ROW[$col_idx]:-}" | tr -d '"')
    if [[ -z "$VAL" ]]; then
      BLANK_FIELDS="yes"
    fi
  done

  if [[ -n "$BLANK_FIELDS" ]]; then
    echo " SKIPPED (blank mandatory fields)"
    echo "$(date +"%Y-%m-%d %H:%M:%S") SKIPPED - Row $((i-1)) - Blank mandatory field(s)" >> "$LOG_FAILED"
    ((SKIP_COUNT++))
    continue
  fi

  if [[ ! "$TRANSACTION_DATE" =~ ^[0-9]{14}$ ]]; then
    echo " SKIPPED (invalid date: $TRANSACTION_DATE)"
    echo "$(date +"%Y-%m-%d %H:%M:%S") SKIPPED - Row $((i-1)) - Invalid date format" >> "$LOG_FAILED"
    ((SKIP_COUNT++))
    continue
  fi

  if [[ ! "$RECEIPT_NUMBER" =~ ^[a-zA-Z0-9]{20}$ ]]; then
    echo " SKIPPED (invalid receipt: $RECEIPT_NUMBER)"
    echo "$(date +"%Y-%m-%d %H:%M:%S") SKIPPED - Row $((i-1)) - Invalid receipt format (must be 20 chars alphanumeric)" >> "$LOG_FAILED"
    ((SKIP_COUNT++))
    continue
  fi

  if [[ "$RECEIPT_NUMBER" == *"$SUFFIX" ]]; then
    echo " SKIPPED (already $SUFFIX)"
    echo "$(date +"%Y-%m-%d %H:%M:%S") SKIPPED - $RECEIPT_NUMBER - Already marked as $SUFFIX" >> "$LOG_FAILED"
    ((SKIP_COUNT++))
    continue
  fi

  NEW_RECEIPT="${RECEIPT_NUMBER}${SUFFIX}"
  
  if ! [[ "$AMOUNT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo " SKIPPED (invalid AMOUNT: '$AMOUNT')"
    echo "$(date +"%Y-%m-%d %H:%M:%S") SKIPPED - $RECEIPT_NUMBER - Invalid AMOUNT: '$AMOUNT'" >> "$LOG_FAILED"
    ((SKIP_COUNT++))
    continue
  fi
  
  AMOUNT_FOR_API=$(LC_NUMERIC=C awk -v amt="$AMOUNT" 'BEGIN { printf "%.0f", amt * 100 }')

  CURR_TS=$(date +"%Y%m%d%H%M%S")
  
  BRAND_ESC=$(escape_xml "$BRAND")
  TX_TYPE_ESC=$(escape_xml "$TRANSACTION_TYPE")
  SHORTCODE_ESC=$(escape_xml "$SHORTCODE")
  REASON_TYPE_ESC=$(escape_xml "$REASON_TYPE")
  NEW_RECEIPT_ESC=$(escape_xml "$NEW_RECEIPT")

  PAYLOAD="<?xml version=\"1.0\" encoding=\"UTF-8\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\"><soapenv:Header><cps:HeaderInfo xmlns:cps=\"http://cps.huawei.com/\" soapenv:mustUnderstand=\"0\"><cps:SessionId>${SESSION_ID}</cps:SessionId><cps:Timestamp></cps:Timestamp><cps:LoginID xsi:nil=\"true\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"/><cps:Password/></cps:HeaderInfo></soapenv:Header><soapenv:Body><cps:RequestInfo xmlns:cps=\"http://cps.huawei.com/\"><cps:Msisdn>&lt;PublishNotificationRequest>&lt;Header>&lt;CommandID>TransactionNotification&lt;/CommandID>&lt;Version>1.0&lt;/Version>&lt;SessionId>${SESSION_ID}&lt;/SessionId>&lt;Timestamp>${CURR_TS}&lt;/Timestamp>&lt;LoginID>&lt;/LoginID>&lt;Password>&lt;/Password>&lt;/Header>&lt;Body>&lt;Parameters>&lt;Parameter>&lt;Key>CreditShortCode&lt;/Key>&lt;Value>${SHORTCODE_ESC}&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>ReasonType&lt;/Key>&lt;Value>${REASON_TYPE_ESC}&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>Date/Timestamp&lt;/Key>&lt;Value>${TRANSACTION_DATE}&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>PrincipleTransactionAmount&lt;/Key>&lt;Value>${AMOUNT_FOR_API}&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>ReceiptNumber&lt;/Key>&lt;Value>${NEW_RECEIPT_ESC}&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Tax Information][NPWP ID]&lt;/Key>&lt;Value>&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Tax Information][NPWP Type]&lt;/Key>&lt;Value>&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Tax Information][NPWP Status]&lt;/Key>&lt;Value>&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>[Credit][Organization Details][Brand]&lt;/Key>&lt;Value>${BRAND_ESC}&lt;/Value>&lt;/Parameter>&lt;Parameter>&lt;Key>OriginalTransactionType&lt;/Key>&lt;Value>${TX_TYPE_ESC}&lt;/Value>&lt;/Parameter>&lt;/Parameters>&lt;/Body>&lt;/PublishNotificationRequest></cps:Msisdn></cps:RequestInfo></soapenv:Body></soapenv:Envelope>"

  set +e
  RESPONSE=$(curl -s -S -X POST -H "Content-Type: text/xml; charset=utf-8" -H "SOAPAction: \"Calculate\"" -d "$PAYLOAD" --connect-timeout 15 -m 30 "$API_URL" 2>&1)
  CURL_EXIT=$?
  set -e
  
  if [[ $CURL_EXIT -eq 0 ]] && echo "$RESPONSE" | grep -q "<ns2:ResultCode>200</ns2:ResultCode>"; then
    RESP_CLEAN=$(echo "$RESPONSE" | tr '\n' ' ' | tr -s ' ')
    echo "$(date +"%Y-%m-%d %H:%M:%S") SUCCESS - $NEW_RECEIPT - Code: 200 - Response: $RESP_CLEAN" >> "$LOG_SUCCESS"
    echo " OK (200)"
    ((SUCCESS_COUNT++))
  else
    ERR_MSG="CURL EXIT: $CURL_EXIT"
    if [[ $CURL_EXIT -eq 0 ]]; then
      ERR_MSG="API ERROR: $(echo "$RESPONSE" | grep -o "<ns2:ResultDesc>[^<]*</ns2:ResultDesc>" || echo "$RESPONSE")"
    else
      ERR_MSG="NETWORK ERROR: $RESPONSE"
    fi
    echo "$(date +"%Y-%m-%d %H:%M:%S") FAILED - $NEW_RECEIPT - $ERR_MSG" >> "$LOG_FAILED"
    echo " FAILED"
    ((FAIL_COUNT++))
  fi

  sleep 0.5
done < "$CSV_FILE"

echo "Retry processing finished."
echo ""
echo "Done. Success: $SUCCESS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT"

EXIT_CODE=0
if [[ $FAIL_COUNT -gt 0 ]]; then
  EXIT_CODE=2
fi
if [[ $SUCCESS_COUNT -eq 0 && $FAIL_COUNT -gt 0 ]]; then
  EXIT_CODE=3
fi

echo "$(date +"%Y-%m-%d %H:%M:%S") | User: $RUN_USER | Suffix: $SUFFIX | Rows: $TOTAL_ROWS | Success: $SUCCESS_COUNT | Failed: $FAIL_COUNT | Skipped: $SKIP_COUNT | Exit: $EXIT_CODE | File: $(basename "$CSV_FILE")" >> "$RUNS_LOG"

exit $EXIT_CODE
