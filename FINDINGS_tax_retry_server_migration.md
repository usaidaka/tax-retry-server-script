# Findings Report — Tax Retry Automation, Server Migration

**Prepared for:** Engineering handoff
**Date:** 2026-07-09
**Scope:** Migration of `tax_retry` from per-engineer Windows laptops to shared Linux server
**Decision taken:** Target implementation is **Bash / POSIX shell + `curl`**. PowerShell (`pwsh`) is to be removed as a runtime dependency.

---

## 1. Executive Summary

The existing PowerShell script (`v2_tax_retry_production.ps1`) has a **clean, verified production run**: 473 rows submitted, 473 `ResultCode 200 / Success`, zero failures, zero skips. Its business logic is correct and must be preserved exactly.

The new orchestrator (`retry.sh` + `config.sh` + folder structure) is a sound *idea* but **has never successfully executed** — it passes a parameter the PowerShell script does not accept. Separately, the target server runs an operating system on which `pwsh` is not officially supported and probably will not install without significant effort.

**Conclusion:** Rather than fight the `pwsh` dependency on an EOL distro, port the business logic to Bash + `curl`. This report documents (a) every defect found, (b) the exact logic that must be carried across, and (c) the environment constraints the new implementation must respect.

**Nothing in this report should be actioned against production until Section 8 (Open Questions) is answered.**

---

## 2. Target Environment (as surveyed)

| Property | Value | Note |
|---|---|---|
| Hostname | `mobomdw03` | **See Open Question Q1** — is this the right box? |
| IP | `10.49.120.179` | Same subnet as prod API `10.49.120.220` |
| OS | SUSE Linux Enterprise Server 12 SP5 | **Past general end-of-support** |
| CPU | 8 cores | Adequate |
| RAM | 30G total, ~16G actually available (2G free + 14G cached) | Adequate |
| `/tmp` | **288M free (97% used)** | Problem — see F-07 |
| `/opt` | 8.3G free | Viable install target |
| `/home` | 149G free | Recommended location for the tool |
| Co-tenant | WebLogic `SaldoMOBO`, `-Xmx10g` | **This is a live production app server** |
| Timezone | WIB (UTC+7) | Must be preserved for SOAP timestamps |
| Survey date | 2026-06-03 | **~5 weeks stale — re-verify disk before deploying** |

---

## 3. The `pwsh` Problem (why we are porting to Bash)

| Factor | Finding |
|---|---|
| Microsoft support matrix | Officially supported SUSE target is **SLES 15**. SLES 12 is not on the supported list; it falls under community support at best. |
| EOL status | Microsoft does not officially support PowerShell on Linux distributions that have reached end-of-life. SLES 12 SP5 has. |
| Dependency: OpenSSL | PowerShell 7.x is built on .NET 6+, which requires **OpenSSL 1.1+**. SLES 12 SP5 ships **OpenSSL 1.0.2**. |
| Dependency: ICU | `libicu` required; presence on this box is unverified. |
| Package repo | No Microsoft repo for SLES 12. Installation would be tarball + manual dependency resolution, on a box that may be network-restricted. |
| Development environment | The script was developed and "simulated" on **macOS**, where `pwsh` is fully supported and installs in seconds. **This gave zero signal about SLES 12 viability.** |

### Cost/benefit of porting

| | Keep `pwsh` | Port to Bash + `curl` |
|---|---|---|
| Install on SLES 12 SP5 | EOL distro, OpenSSL mismatch, no repo, offline dependency chase | Everything already present |
| Runtime footprint on a WebLogic prod box | .NET runtime, ~150–200MB RSS, `/tmp` pressure | Negligible |
| Decimal `×100` arithmetic | `[decimal]` — exact | `awk` with `LC_NUMERIC=C` — also exact, **locale must be pinned** |
| Existing production validation | Earned on **Windows PS 5.1**, does **not** transfer unchanged to `pwsh` 7 on Linux | Must be re-validated |
| Team/server fit | Foreign runtime on the box | Native |

**Key point:** the 473/473 clean run was achieved on Windows PowerShell 5.1. Running the same `.ps1` under `pwsh` 7 on Linux is a *different runtime* with different exception types and different default encodings (see Section 6). **Re-validation is required either way.** Given that, re-validate onto the stack that does not require fighting an EOL distro.

---

## 4. Defects Found

### 4.1 Blockers

| ID | File | Finding | Evidence | Impact | Fix |
|---|---|---|---|---|---|
| **F-01** | `retry.sh` + `.ps1` | `retry.sh` invokes `pwsh -File "$PS_SCRIPT" -ManualRetrySuffix "$SUFFIX" -CsvPath "$CSV_FILE"`, but the `.ps1` `param()` block declares **only** `-ManualRetrySuffix`. `$CSV_PATH` remains hardcoded on line 7. | `grep -n "param(\|CsvPath" v2_tax_retry_production.ps1` → no `CsvPath` | Parameter-binding error → pwsh exits 1 → orchestrator aborts. **The orchestrator has never run successfully.** Fails loudly, so no data was harmed. | Moot if porting to Bash. If not porting: add `[Parameter(Mandatory=$true)][string]$CsvPath`, delete the hardcoded line 7, replace all references. **Do not leave a default fallback** — a typo would silently reprocess a stale CSV. |
| **F-02** | `README.md` | README states TRANSACTION_DATE is auto-validated as exactly 14 digits and that execution *"digagalkan otomatis oleh sistem"* if not. **No such validation exists in any file.** | `grep -n "14" retry.sh v2_tax_retry_production.ps1` → nothing | Malformed date reaches production. **Worse: the operator relaxes because the docs promise a guardrail that isn't there.** | Implement the check (see §5, Rule 5). Do not ship the README as-is. |
| **F-03** | `.ps1` | Script always exits `0` on row failures. `exit 1` fires only for missing CSV / missing columns. | `grep -n "exit" v2_tax_retry_production.ps1` → lines 15, 22, 38 only | If **all rows fail**, `EXEC_EXIT_CODE=0` → `retry.sh` archives the CSV as if the run succeeded. The archive-move is the *de facto* rerun protection, and it currently triggers on catastrophe. **Severity is higher on a server than a laptop**, where you can no longer watch rows scroll by. | Exit `2` if `failCount > 0`; exit `3` if `successCount == 0`. In `retry.sh`, do **not** archive on non-zero exit. |
| **F-04** | `retry.sh` | `02-csv-for-execute/` is a shared mutable directory with **no locking**. Multiple engineers can drop CSVs or launch runs concurrently. | Code inspection | Engineer A launches; B drops a CSV mid-run → A's archive step moves B's file. Or both launch → both see "1 CSV" → **the same rows submitted to production twice.** | `flock` on a lockfile. **Note: `flock` does not exist on macOS** — this cannot be tested on the dev machine. |
| **F-05** | Ops / `retry.sh` | An SSH disconnect sends `SIGHUP` and kills a running job. | Environmental | Killed at row 300/473: 300 rows already submitted to prod, CSV never archived, no summary printed. Operator cannot determine what landed without parsing the partial log. | Mandate `tmux`/`screen`, or wrap in `setsid`/`nohup`. **`setsid` also does not exist on macOS.** Document in SOP. |

### 4.2 High

| ID | File | Finding | Impact | Fix |
|---|---|---|---|---|
| **F-06** | `.ps1` | Hardcoded prod `$API_URL` and hardcoded `SessionId` (`AG_20260602_10101dbf3a83763c5c70`) in the payload. | (a) Testing requires editing the prod script — someone will forget to revert. (b) A probable credential is heading into version control, now on a **multi-user box**. | Move both to `config.sh`; `chmod 600`; `.gitignore` it; commit `config.sh.example`. **Rotate the SessionId** — it has been sitting in a `Downloads` folder and likely in git. |
| **F-07** | Server | `/tmp` at **97% (288M free)**. | Any tool that stages to `/tmp` may fail. Lockfiles conventionally live there too. | Clear `/tmp`, or pin `TMPDIR=/home/<svc>/tmp`. **Re-check first — the survey is 5 weeks old.** |
| **F-08** | Server | Batch runs on the same host as production WebLogic `SaldoMOBO` (`-Xmx10g`). | Resource contention against a live production application. | Confirm with the SaldoMOBO owner before scheduling any batch. Bash+`curl` makes this materially safer than a .NET runtime. |
| **F-09** | `retry.sh` | No suffix format validation or normalization. `--suffix mr1` → `_mr1`. | Lowercase `_mr1` mismatches every `_MR%` in the database and **silently defeats the SQL `NOT EXISTS` guard** on the next round → duplicate submission. | Uppercase, then enforce `^_MR[0-9]+$`. Use `tr '[:lower:]' '[:upper:]'` (portable), **not** `${VAR^^}` (bash 4+, fails on macOS bash 3.2). |
| **F-10** | `retry.sh` | No confirmation prompt, no dry-run, no row cap. | 473 rows fired at production with zero friction. A wrong export with 500k rows has nothing standing in its way. | Print row count + suffix + target; require typed `YES`. Add `MAX_ROWS` cap requiring explicit `--force`. |
| **F-11** | `retry.sh` | If a confirmation prompt is added via bare `read -r -p`, it breaks under non-interactive invocation (cron, `ssh host './retry.sh ...'`). | Script hangs, or — depending on how the guard is written — `$CONFIRM` is empty and it **fails open**, firing unattended. | Guard with `[[ -t 0 ]]`. If stdin is not a TTY, **refuse to run** unless an explicit `--yes` flag is passed. **Never fail open.** |
| **F-12** | `.ps1` | No orchestrator run log / attribution. | On a laptop, "who ran this" was self-evident. On a shared server it is unanswerable. | Append one line per run to `runs.log`: timestamp, `whoami` (or `$SUDO_USER`), suffix, CSV filename, row count, exit code. |
| **F-13** | `.ps1` | The "already has this suffix" guard (`-match "_MR1$"`) is **dead code** — the CSV always contains bare receipt numbers, so it never matches. | It cannot prevent running `--suffix MR1` twice on the same data. Real protection comes from the SQL `NOT EXISTS` guard + the CSV archive move, both *outside* the script. | Do not count it as a control. Fix F-03 and F-04 instead. Carry the guard across anyway as defense-in-depth. |

### 4.3 Medium / Low

| ID | File | Finding | Fix |
|---|---|---|---|
| F-14 | `retry.sh` | No `set -euo pipefail`. A failing `tr`, `mkdir`, or `source` silently continues. | Add at top. |
| F-15 | `retry.sh` | `mv retry_*.log ... 2>/dev/null` suppresses errors. Failed archive moves go unnoticed; next run may sweep the previous run's logs. | Drop `2>/dev/null`; guard with a glob-existence check. |
| F-16 | `.ps1` | Log filenames omit the suffix (`retry_success_20260708_140957.log`). | `retry_success_${SUFFIX}_$(whoami)_<timestamp>_$$.log` |
| F-17 | `.ps1` | Log files are written CWD-relative; `retry.sh` then `mv`s from CWD. Breaks under cron or absolute-path invocation. | Pass an explicit `--log-dir` resolved from `SCRIPT_ROOT`. Stop relying on CWD. |
| F-18 | `retry.sh` | `tr -d '\r'` mutates the operator's input CSV **in place, before any validation runs**. | Write the cleaned copy to a temp path; leave the original untouched until archive time. |
| F-19 | `retry.sh` | `$(dirname "$0")` re-resolved 5 times. Breaks under symlink / `sh retry.sh` / unusual CWD. | Resolve once: `SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` |
| F-20 | `retry.sh` | `shopt -u nullglob` assumes nullglob was off initially. | Check with `shopt -q nullglob` first, or save/restore. |
| F-21 | `retry.sh` | Glob `*.csv` + `*.CSV` behaves differently on case-insensitive (macOS/APFS) vs case-sensitive (SLES) filesystems. | Verify empirically on the server; do not reason about it. |
| F-22 | `config.sh` | `SERVER_HOST` / `SERVER_USER` / `REMOTE_PATH` are empty and read by nothing. | Implement or delete. Dead config invites someone to fill it in and expect behavior. |
| F-23 | Ops | `03-csv-after-execute/` and `04-log-retry-manual/` grow unbounded on a shared box. | Retention policy: compress + prune after N days. |
| F-24 | `README.md` | Instructs `chmod +x config.sh`, but it is `source`d, not executed. | Remove. (Signals the docs were never tested.) |

---

## 5. Logic Contract — MUST be preserved exactly in the Bash port

These are not suggestions. Each was established through production testing or explicit confirmation from the API developer. **Any deviation is a financial or data-integrity defect.**

| # | Rule | Rationale | Bash implementation note |
|---|---|---|---|
| **1** | `AMOUNT` is multiplied by **100** before being sent as `PrincipleTransactionAmount`. | Confirmed by the API developer: the sender multiplies by 100; the API divides by 100 on receipt. Verified end-to-end (CSV `100` → API `10000` → DB `100`). | Bash has no float arithmetic. Use `awk`. |
| **2** | **The decimal parse MUST be locale-invariant.** | The server locale is Indonesian (`id_ID`), which uses `,` as the decimal separator. The `.ps1` correctly pins `InvariantCulture`. Real values in the last export include `175.5` and `117.6`. **A locale-aware parse turns `175.5` into `1755` — a 10× overcharge.** | `LC_NUMERIC=C awk '{ printf "%.0f", $1 * 100 }'` — **pin `LC_NUMERIC=C` explicitly.** Add a loud comment. |
| **3** | A non-numeric `AMOUNT` must cause the row to be **skipped and logged**, never sent. | A corrupted amount must never reach production. | Validate with a regex before the `awk` call. |
| **4** | The CSV `RECEIPT_NUMBER` is the **bare** original number. The script **appends** the suffix; it never strips or replaces. | The SQL selects `orig.RECEIPT_NUMBER`. Feeding a suffixed number would produce stacked receipts (`..._R01_MR2`). | Simple string concat. |
| **5** | `TRANSACTION_DATE` must be exactly **14 digits** (`YYYYMMDDHHmmss`). | Promised by the README, implemented nowhere (F-02). | `[[ "$TRANSACTION_DATE" =~ ^[0-9]{14}$ ]]` |
| **6** | `BRAND` and `TRANSACTION_TYPE` may be **blank**. All other columns are mandatory. | Confirmed. Empty `<Value></Value>` is valid business logic for `OriginalTransactionType`. | Blank check must exclude these two. |
| **7** | Column **headers** must all be present, including `BRAND` and `TRANSACTION_TYPE`, even when their values are blank. | Distinguish "header must exist" from "value must be non-empty". | Two separate lists. |
| **8** | The SOAP `Timestamp` (`$curr_ts`) is generated **at the moment of the API call**, in server-local time (WIB). | Preserved behavior. | `date +%Y%m%d%H%M%S`. **Verify the server TZ is WIB, not UTC** — a UTC box shifts every timestamp by 7 hours. |
| **9** | HTTP 200 does **not** mean success. The SOAP response body must be inspected. | Verified: successful responses contain `<ns2:ResultCode>200</ns2:ResultCode><ns2:ResultDesc>Success</ns2:ResultDesc>`. | **Improvement opportunity:** the Bash port should *parse* this and branch, rather than only logging it. The `.ps1` only ever logged it. |
| **10** | Throttle between requests (500ms in the last prod run). | 473 rows / ~5 minutes, no rate-limit failures. Known-good pacing. | `sleep 0.5` |
| **11** | Field values are **not** XML-escaped today. | Accepted risk, previously declined. **Re-evaluate.** If `BRAND` or `TRANSACTION_TYPE` ever contains `&`, `<`, or `>`, the payload becomes invalid XML. | Consider adding escaping during the port — the cost is one `sed`. |

---

## 6. Runtime Behavior Deltas (Windows PS 5.1 → Linux)

Relevant if any PowerShell is retained, and useful context for what "re-validation" means.

| Behavior | Windows PS 5.1 (proven) | `pwsh` 7 on Linux | Note |
|---|---|---|---|
| `-UseBasicParsing` | Required (avoids IE-parsing prompt) | No-op | Harmless |
| `-Body` string encoding | System default codepage | UTF-8 | Silently fixes a previously-declined finding |
| Exception on non-2xx | `WebException` | `HttpResponseException` | **`$_.Exception.Message` text differs** — failed-log format changes |
| `Add-Content` default encoding | ANSI / default codepage | UTF-8 no BOM | Cosmetic, but breaks diffs against old logs |

---

## 7. Cross-Platform Traps (macOS dev → SLES 12 prod)

The script was developed and "simulated" on macOS. These items **cannot be validated there**:

| Item | macOS | SLES 12 | Consequence |
|---|---|---|---|
| `flock` | ❌ absent | ✅ present | F-04's fix cannot be developed or tested on the dev machine |
| `setsid` | ❌ absent | ✅ present | Same for F-05 |
| `readlink -f` | ❌ (BSD, no `-f`) | ✅ GNU | Any `SCRIPT_ROOT` resolution using it breaks on one side |
| `sed -i` | needs `sed -i ''` | `sed -i` | Not currently used — **keep it that way**, or branch on OS |
| `/bin/bash` | 3.2 (2007), or Homebrew 5.x | 4.3 | Testing on Homebrew bash 5 gives false confidence (`${var@U}` etc. fail on 4.3). Testing on system bash 3.2 gives false failures. **Either direction is a bad signal.** |
| Filesystem case sensitivity | insensitive (APFS) | sensitive | Affects the `*.csv`/`*.CSV` dual glob (F-21) |
| `wc -l` output | leading whitespace | no padding | Safe inside `$(( ))`, unsafe in string comparison |

**Recommendation:** development and testing must happen in an environment matching the target — a SLES 12 container, or directly on a non-prod box. macOS is not a substitute.

---

## 8. Open Questions — answer before writing code

| # | Question | Why it matters |
|---|---|---|
| **Q1** | Is `10.49.120.179` (`mobomdw03`) actually the deployment target? Previous discussion referenced `mobo@10.49.120.219`, and the prod API is at `10.49.120.220` (MDW08). **Three hosts on this subnet.** | Everything in Section 2 is scoped to `.179`. |
| **Q2** | During "simulation" on macOS, was `$API_URL` pointed at a mock, or at `10.49.120.220`? | If the latter, those were **real production transactions**, not a simulation. Needs immediate audit against `T_TAX_REQUEST`. |
| **Q3** | Does `retry.sh` run as the invoking engineer, or as a dedicated service user via `sudo`? | Service user = secret is locked to one account + `sudo` gives a tamper-resistant audit trail in `auth.log`, but `whoami` then returns the service user (capture `$SUDO_USER`). Engineer = free attribution, but `config.sh` (and the SessionId) must be readable by everyone. **Service user is correct for a production tax system.** |
| **Q4** | Can the box reach the internet / internal package mirrors? | Determines whether *any* dependency can be added. Reinforces the Bash-only decision. |
| **Q5** | Is the `SessionId` a credential? Does it need rotating? | It has lived in a `Downloads` folder and probably in git. |
| **Q6** | Has the SaldoMOBO owner approved running a batch on this host? | F-08. |
| **Q7** | What is the retry ceiling? After N failed manual retries, does a transaction get escalated rather than retried again? | Currently unbounded. The cycle can run forever on a systemic fault. |

---

## 9. Verification Commands (run on the target box, paste output back)

```bash
# --- Is this the right box? ---
hostname; hostname -I
curl -sI --connect-timeout 3 http://10.49.120.220:7001/TaxFacade/ws/tax | head -1

# --- Disk reality check (survey is 5 weeks stale) ---
df -h /tmp /opt /home /var

# --- What shell and tools are actually available? ---
bash --version | head -1
command -v flock setsid awk curl tr sed || echo "MISSING TOOL ABOVE"

# --- Locale and timezone: critical for Rule 2 and Rule 8 ---
locale | grep -E 'LC_NUMERIC|LANG'
date +'%Z %z'

# --- Confirms the pwsh decision (informational) ---
pwsh --version 2>/dev/null || echo "PWSH NOT INSTALLED (expected)"
openssl version   # expect 1.0.2 -> confirms the .NET 6+ incompatibility
```

---

## 10. Recommended Fix Order

| # | Item | Why here |
|---|---|---|
| 1 | Answer Q1, Q2, Q4 | Q2 in particular may require a production data audit before anything else proceeds |
| 2 | Port core logic to Bash + `curl`, honoring **every rule in Section 5** | Removes the `pwsh`/SLES 12 blocker entirely |
| 3 | F-03 — honest exit codes; do not archive on failure | On a server this is your **only** success signal |
| 4 | F-04 — `flock` concurrency lock | Two engineers = double submission to production |
| 5 | F-05 — `tmux`/`setsid` + SOP update | SSH drop mid-run is now a routine failure mode |
| 6 | F-02 / Rule 5 — 14-digit date validation | The README currently lies about a control that does not exist |
| 7 | F-11 — TTY guard; **never fail open** | Non-interactive invocation must refuse, not proceed |
| 8 | F-09 — suffix regex + uppercase normalization | `_mr1` silently defeats the SQL guard |
| 9 | F-06 / Q5 — secrets to `chmod 600` config; rotate SessionId | Multi-user box |
| 10 | F-10 — row cap + typed confirmation | Prevents the 500k-row accident |
| 11 | F-12 — `runs.log` with attribution | Audit trail |
| 12 | F-07, F-08, F-14 → F-24 | Environment prep, hardening, polish |

**Items 1–5 are non-negotiable before this touches production.**
Items 6–11 are the difference between "a script that works" and "a script a colleague can run at 2am without waking you up."

---

## 11. Test Plan (before any production batch)

1. **Never test against `10.49.120.220` (prod).** Obtain a non-prod TaxFacade endpoint, or a local mock that echoes the SOAP envelope.
2. Validate **Rule 2** explicitly: feed a CSV containing `175.5` and `117.6` under `LANG=id_ID.UTF-8` and assert the payload contains `17550` and `11760`, **not** `1755`/`1176` and not `175500`/`117600`.
3. Validate **Rule 5**: feed a row with a 13-digit and a 15-digit `TRANSACTION_DATE`; assert both are skipped and logged.
4. Validate **Rule 6**: feed a row with blank `BRAND` and blank `TRANSACTION_TYPE`; assert it is **submitted**, not skipped.
5. Validate **F-03**: force every row to fail (point at a dead endpoint); assert the exit code is non-zero and the CSV is **not** archived.
6. Validate **F-04**: launch two runs concurrently; assert the second refuses to start.
7. Validate **F-11**: run via `ssh host './retry.sh --suffix MR9'` with no TTY; assert it **refuses**, does not hang, does not proceed.
8. Only then: a **single-row** batch against production, verified in `T_TAX_REQUEST` before any larger run.
