## Context

The `tax_retry` automation script is transitioning from individual developer workstations (macOS/Windows) to a shared production server (`mobomdw03` at `10.49.120.179`) running SUSE Linux Enterprise Server (SLES) 12 SP5. The initial iteration relied on PowerShell Core (`pwsh`). However, SLES 12 is past general end-of-support and its underlying libraries (like OpenSSL 1.0.2) are fundamentally incompatible with `.NET 6+` requirements of modern PowerShell. Maintaining `pwsh` on this server introduces unacceptable operational risks, complexity, and resource contention on a host that also runs the live WebLogic `SaldoMOBO` application.

## Goals / Non-Goals

**Goals:**
- Eliminate the `pwsh` and `.NET` runtime dependencies completely.
- Migrate the exact, proven business logic of the SOAP API submissions to a pure Bash/POSIX shell implementation.
- Introduce robust concurrency control (`flock`) to prevent accidental duplicate submissions by multiple engineers.
- Improve attribution and logging for multi-user auditability.

**Non-Goals:**
- Modifying the XML SOAP payload structure or the downstream database logic.
- Rewriting the orchestrator's directory structure (the 01, 02, 03, 04 folder flow will remain identical).

## Decisions

1. **Bash + `curl` over Python or PowerShell**:
   - *Rationale*: `bash`, `curl`, and `awk` are guaranteed to exist on SLES 12 without external repositories or compile-time dependencies. It has virtually zero memory footprint, ensuring no resource contention with WebLogic.

2. **Decimal Arithmetic via `awk` with `LC_NUMERIC=C`**:
   - *Rationale*: Bash cannot natively perform floating-point arithmetic. `awk` handles this perfectly, but it is heavily locale-dependent. Since SLES defaults to Indonesian locales (`id_ID`) which use a comma `,` for decimals, we MUST explicitly pin `LC_NUMERIC=C` so `175.5 * 100` computes to `17550`, not `175500`.

3. **Concurrency Control via `flock`**:
   - *Rationale*: Bash will use `/tmp/tax_retry.lock` to ensure only one instance of the script can run at a time. This prevents race conditions on the `02-csv-for-execute/` directory.

4. **Honest Exit Codes**:
   - *Rationale*: The Bash script will exit with code `2` if any row failed, and code `3` if all rows failed. This ensures the orchestrator does not move the CSV to the "Success/Archived" folder unless it was a 100% clean run.

## Risks / Trade-offs

- **[Risk] Float arithmetic bugs in `awk`** → Mitigation: Use strict `printf "%.0f"` to discard floating-point noise and pin `LC_NUMERIC=C` to ignore server locale settings.
- **[Risk] XML escaping vulnerabilities** → Mitigation: Use `sed` to sanitize the CSV fields (e.g., converting `&` to `&amp;` and `<` to `&lt;`) before interpolating them into the SOAP payload.
- **[Risk] Script hanging on SSH disconnect** → Mitigation: Document that operators should use `nohup`, `tmux`, or `screen` to prevent `SIGHUP` terminations mid-run.
- **[Risk] `flock` missing on macOS for local testing** → Mitigation: Implement a fallback mechanism or conditional execution (`if command -v flock`) to allow local macOS development while strictly enforcing it on Linux.
