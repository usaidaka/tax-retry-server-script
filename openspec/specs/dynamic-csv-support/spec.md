## ADDED Requirements

### Requirement: Accept CSV Path as Parameter
The PowerShell script `v2_tax_retry_production.ps1` MUST accept a `-CsvPath` parameter in addition to the existing `-ManualRetrySuffix`.

#### Scenario: Script Invocation
- **WHEN** the script is invoked with `-CsvPath <path>` and `-ManualRetrySuffix <suffix>`
- **THEN** it MUST read and parse the CSV from the specified path rather than the hardcoded string

### Requirement: Maintain Existing Business Logic
The PowerShell script MUST NOT change any of its core processing logic (SOAP API call, column validation, log generation).

#### Scenario: Existing Output Consistency
- **WHEN** the script processes a row from the dynamic CSV
- **THEN** it MUST perform the exact same validation, API request, and logging format as previously designed
