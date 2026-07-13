## ADDED Requirements

### Requirement: Validate Script Arguments
The automation script MUST validate that the operator provides exactly the `--csv` and `--suffix` arguments with valid values.

#### Scenario: Missing Arguments
- **WHEN** the script is executed without required arguments
- **THEN** it MUST print usage help and exit with code 1

#### Scenario: Valid Arguments
- **WHEN** the script is executed with `--csv sample.csv --suffix MR1`
- **THEN** it MUST proceed to the next validation steps

### Requirement: Validate CSV File
The automation script MUST validate the existence, non-emptiness, and extension of the provided CSV file.

#### Scenario: File Not Found
- **WHEN** the operator provides a CSV file that does not exist
- **THEN** it MUST print an error message and exit with code 1

#### Scenario: File Extension Not CSV
- **WHEN** the operator provides a file that does not have `.csv` extension
- **THEN** it MUST print an error message and exit with code 1

#### Scenario: Empty File
- **WHEN** the operator provides an empty file
- **THEN** it MUST print an error message and exit with code 1

### Requirement: Convert CSV to UNIX Format
The automation script MUST convert the file endings from CRLF (DOS) to LF (UNIX) to prevent parsing errors.

#### Scenario: Convert DOS file
- **WHEN** a valid CSV file is passed
- **THEN** it MUST be processed using `dos2unix` or equivalent to ensure UNIX line endings before execution

### Requirement: CSV File Routing and Backup
The automation script MUST copy the processed CSV to a staging folder and move it to a completion folder after execution.

#### Scenario: Pre-Execution Copy
- **WHEN** the CSV file passes validation
- **THEN** it MUST be copied to `02-csv-for-execute`

#### Scenario: Post-Execution Move
- **WHEN** the PowerShell script finishes execution
- **THEN** the CSV file MUST be moved from `02-csv-for-execute` to `03-csv-after-execute`

### Requirement: Log Routing
The automation script MUST move the generated success and failed logs from the script execution directory to the log archive folder.

#### Scenario: Move Logs
- **WHEN** the PowerShell script finishes execution
- **THEN** any `retry_success_*.log` and `retry_failed_*.log` files MUST be moved to `04-log-retry-manual`

### Requirement: PowerShell Script Execution
The automation script MUST wrap the execution of the main business logic PowerShell script, passing the correct arguments.

#### Scenario: Execute with PowerShell
- **WHEN** all validations pass
- **THEN** it MUST execute `pwsh automation/01-script/v2_tax_retry_production.ps1` with the dynamic CSV path and the transformed suffix (e.g. `_MR1`)
