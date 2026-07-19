## 1. Safety and Orchestrator Hardening (`retry.sh`)

- [x] 1.1 Implement non-interactive TTY guard to refuse execution without a terminal or explicit override
- [x] 1.2 Implement `flock` concurrency lock on the staging folder
- [x] 1.3 Add a confirmation prompt displaying the suffix and row count before execution
- [x] 1.4 Refactor `retry.sh` to call the new Bash business logic script instead of `pwsh`
- [x] 1.5 Update orchestrator's exit status handling to respect honest exit codes from the business logic script (do not archive CSV on failures)

## 2. Business Logic Porting (`v2_tax_retry_production.ps1` -> `tax_retry_production.sh`)

- [x] 2.1 Create new native Bash script `tax_retry_production.sh` inside `automation/01-script/`
- [x] 2.2 Port CSV parsing logic using `awk` or `while read` loop
- [x] 2.3 Port `TRANSACTION_DATE` exact 14-digit regex validation
- [x] 2.4 Port decimal multiplication (`AMOUNT * 100`) using `awk` with strict `LC_NUMERIC=C`
- [x] 2.5 Implement XML payload generation and `curl` execution for the SOAP endpoint
- [x] 2.6 Implement XML response parsing using `grep` or `sed` to verify `<ns2:ResultCode>200</ns2:ResultCode>`
- [x] 2.7 Port the log generation logic (`retry_success.log` and `retry_failed.log`)

## 3. Configuration and Secrets (`config.sh`)

- [x] 3.1 Extract hardcoded `$API_URL` and `SessionId` into `config.sh`
- [x] 3.2 Add `chmod 600` instruction for `config.sh` to the README/SOP
- [x] 3.3 Add `runs.log` attribution (writing timestamp, user, suffix, rows, exit code)

## 4. Cleanup and Documentation

- [x] 4.1 Delete the deprecated `v2_tax_retry_production.ps1`
- [x] 4.2 Update `automation/README.md` to remove `pwsh` from prerequisites and add `tmux`/`screen` recommendations
- [x] 4.3 Add documentation to README highlighting the new confirmation prompt and TTY guards
