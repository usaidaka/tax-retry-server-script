## MODIFIED Requirements

### Requirement: Accept CSV Path as Parameter
The business logic script MUST accept a `-CsvPath` parameter (or read implicitly from the environment) in addition to the existing suffix.

#### Scenario: Script Invocation
- **WHEN** the script is invoked with the CSV path
- **THEN** it MUST read and parse the CSV from the specified path rather than the hardcoded string

### Requirement: Maintain Existing Business Logic
The business logic script MUST NOT change any of its core processing logic (SOAP API call, column validation, log generation), despite the migration from PowerShell to Bash.

#### Scenario: Existing Output Consistency
- **WHEN** the script processes a row from the dynamic CSV
- **THEN** it MUST perform the exact same validation, API request, and logging format as previously designed

## ADDED Requirements

### Requirement: Validate TRANSACTION_DATE Format
The script MUST validate that the `TRANSACTION_DATE` column in the CSV is precisely a 14-digit string (`YYYYMMDDHHmmss`) before attempting execution.

#### Scenario: Invalid Date Format
- **WHEN** the script encounters a `TRANSACTION_DATE` with hyphens or incorrect length
- **THEN** it MUST skip the row or exit with an error, preventing malformed data from reaching the API.
