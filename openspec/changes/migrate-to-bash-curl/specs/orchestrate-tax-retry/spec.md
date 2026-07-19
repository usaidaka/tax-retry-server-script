## ADDED Requirements

### Requirement: Execution Concurrency Lock
The automation script MUST use `flock` to ensure only one instance of the script can run at any given time.

#### Scenario: Concurrent Execution Attempt
- **WHEN** an operator attempts to run `retry.sh` while another instance is already running
- **THEN** the script MUST fail immediately and inform the operator that another run is in progress.

### Requirement: Interactive TTY Guard
The automation script MUST prevent accidental unattended execution by verifying it is running in an interactive terminal.

#### Scenario: Cron or Non-Interactive Execution
- **WHEN** the script is executed without a TTY attached
- **THEN** the script MUST refuse to run unless an explicit override flag is provided.

### Requirement: Execution Confirmation Prompt
The automation script MUST display the target suffix and row count, and require explicit typed confirmation from the operator before submitting to production.

#### Scenario: User Approves Execution
- **WHEN** prompted to confirm the execution of X rows
- **THEN** the script MUST require the user to type `YES` to proceed.

### Requirement: Honest Exit Codes
The automation script MUST exit with a non-zero exit code if the underlying business logic fails for any row.

#### Scenario: Partial or Complete Row Failures
- **WHEN** the business logic completes but records 1 or more row failures
- **THEN** the script MUST exit with a non-zero exit code (e.g., 2) and MUST NOT move the CSV to the completion archive folder.

## MODIFIED Requirements

### Requirement: PowerShell Script Execution
The automation script MUST wrap the execution of the main business logic script, passing the correct arguments.

#### Scenario: Execute with PowerShell
- **WHEN** all validations pass
- **THEN** it MUST execute the native Bash business logic script (previously `v2_tax_retry_production.ps1`) with the dynamic CSV path and the transformed suffix (e.g. `_MR1`).
