## Why

The current implementation of the tax retry automation relies on PowerShell Core (`pwsh`) for its core business logic execution. However, the target production server is running SUSE Linux Enterprise Server (SLES) 12 SP5, an OS past its general end-of-support that does not officially support PowerShell. Installing and maintaining `.NET` dependencies on this legacy, restricted, live production box poses significant operational risks and friction. A native Bash + `curl` implementation eliminates this runtime dependency while preserving the exact business logic that was already validated.

## What Changes

- Port the business logic currently inside `v2_tax_retry_production.ps1` into a native Bash/POSIX shell script utilizing `curl` for SOAP API calls and `awk` for decimal arithmetic.
- Remove all dependencies on `pwsh` / PowerShell Core from the orchestrator (`retry.sh`).
- Implement proper exit codes: script will exit with error codes when rows fail to ensure the orchestrator doesn't falsely assume success (Fixes F-03).
- Implement a concurrency lock using `flock` to prevent multiple engineers from submitting the same CSV simultaneously (Fixes F-04).
- Add session persistence documentation (`tmux`/`screen`/`nohup`) to survive SSH disconnects (Fixes F-05).
- Add strict non-interactive TTY guards to prevent the script from failing open when run via cron or SSH without a TTY (Fixes F-11).
- Add a confirmation prompt with row count visibility and a max-row safety cap.
- Enhance security by moving the hardcoded `SessionId` and `API_URL` into `config.sh` and ensuring `runs.log` attribution.

## Capabilities

### New Capabilities
- `bash-soap-execution`: Handling XML SOAP requests and parsing XML responses directly in Bash using `curl` and POSIX tools.

### Modified Capabilities
- `orchestrate-tax-retry`: Updated to include concurrency locks (`flock`), non-interactive execution guards (TTY check), and strict exit-code propagation based on individual row failures.
- `dynamic-csv-support`: Updated to enforce the 14-digit `TRANSACTION_DATE` format constraint before execution and ensure locale-invariant parsing (`LC_NUMERIC=C`) for decimal values.

## Impact

- **Dependencies**: Eliminates the need to install PowerShell Core, .NET, and specific OpenSSL/ICU versions on the SLES 12 production server.
- **Code**: `v2_tax_retry_production.ps1` will be deprecated and replaced by a pure Bash equivalent. `retry.sh` will be heavily refactored to support the new Bash script and new safety guards.
- **Operations**: Engineers will have a safer, lock-protected, and fully auditable tool native to the Linux environment.
