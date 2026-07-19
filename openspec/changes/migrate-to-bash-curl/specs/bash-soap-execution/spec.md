## ADDED Requirements

### Requirement: Native POSIX Execution
The system SHALL execute all business logic, including SOAP API requests and CSV parsing, entirely within a native Bash/POSIX shell environment without any dependencies on .NET or PowerShell Core.

#### Scenario: SLES 12 Environment
- **WHEN** the script is executed on the target SLES 12 SP5 server
- **THEN** it completes successfully using only pre-installed POSIX utilities (`bash`, `curl`, `awk`, `sed`, `grep`, `tr`) without requiring external package installations.

### Requirement: Locale-Invariant Decimal Arithmetic
The system SHALL multiply the `AMOUNT` by 100 exactly, irrespective of the host server's locale settings (e.g., `id_ID`).

#### Scenario: Floating Point Amount
- **WHEN** the `AMOUNT` is `175.5`
- **THEN** the system MUST use `LC_NUMERIC=C awk` to compute the payload amount as exactly `17550` and send it to the API.

### Requirement: XML Content Escaping
The system SHALL sanitize CSV fields that contain special XML characters (`&`, `<`, `>`) before injecting them into the SOAP payload.

#### Scenario: Brand contains ampersand
- **WHEN** the `BRAND` column contains `A&W`
- **THEN** the system MUST convert it to `A&amp;W` in the generated XML body to prevent malformed XML errors.

### Requirement: SOAP Response Parsing
The system SHALL parse the XML response body from `curl` to determine the true success or failure of the transaction, rather than relying solely on the HTTP 200 OK status code.

#### Scenario: Logical Failure in API
- **WHEN** the API returns HTTP 200 OK but the XML body contains `<ns2:ResultCode>500</ns2:ResultCode>`
- **THEN** the script MUST mark the row as FAILED and write it to the `retry_failed.log`.
