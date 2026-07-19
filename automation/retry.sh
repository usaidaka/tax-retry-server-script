#!/bin/bash
set -euo pipefail

# Safe directory resolution
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
source "${SCRIPT_ROOT}/config.sh"

echo "Retry Manual Tax Automation"
echo "--------------------------------"

# Default values
SUFFIX=""
FORCE=0

# Parse CLI parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    --suffix)
      SUFFIX="$2"
      shift 2
      ;;
    --force|--yes)
      FORCE=1
      shift
      ;;
    --help)
      echo "Usage: ./retry.sh --suffix <SUFFIX> [--force]"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

if [[ ! -t 0 && $FORCE -eq 0 ]]; then
  echo "Error: Non-interactive execution without --force is refused."
  exit 1
fi

if [[ -z "$SUFFIX" ]]; then
  echo "Error: Missing required parameters."
  echo "Usage: ./retry.sh --suffix <SUFFIX>"
  exit 1
fi

# Suffix Automation
if [[ "${SUFFIX:0:1}" != "_" ]]; then
  SUFFIX="_${SUFFIX}"
fi
SUFFIX=$(echo "$SUFFIX" | tr '[:lower:]' '[:upper:]')

if [[ ! "$SUFFIX" =~ ^_MR[0-9]+$ ]]; then
  echo "Error: Invalid suffix format. Must be like _MR1 or MR1"
  exit 1
fi

echo "Parameter Validation Passed:"
echo "- Suffix   : $SUFFIX"
echo "--------------------------------"

# Concurrency Lock (if flock is available)
if command -v flock >/dev/null 2>&1; then
  exec 9> "/tmp/tax_retry.lock"
  if ! flock -n 9; then
    echo "Error: Another instance of this script is already running."
    exit 1
  fi
fi

# Check CSV files in folder 02
EXEC_CSV_DIR="${SCRIPT_ROOT}/${DIR_CSV_EXECUTE}"
# Create dir if not exist
mkdir -p "$EXEC_CSV_DIR"

# Read all CSV files in the folder
shopt -s nullglob
CSV_FILES=("$EXEC_CSV_DIR"/*.csv "$EXEC_CSV_DIR"/*.CSV)
shopt -u nullglob

FILE_COUNT=${#CSV_FILES[@]}

if [[ $FILE_COUNT -eq 0 ]]; then
  echo "Error: Tidak ada file CSV yang ditemukan di dalam folder ${DIR_CSV_EXECUTE}."
  exit 1
elif [[ $FILE_COUNT -gt 1 ]]; then
  echo "Error: Terdapat lebih dari 1 file CSV di folder ${DIR_CSV_EXECUTE}."
  echo "Harap pastikan hanya ada tepat 1 file CSV pada folder tersebut."
  exit 1
fi

CSV_FILE="${CSV_FILES[0]}"
echo "Detected CSV File: $(basename "$CSV_FILE")"

# CSV Preparation (DOS to UNIX In-Place)
TMP_CSV="${CSV_FILE}.tmp"
tr -d '\r' < "$CSV_FILE" > "$TMP_CSV"
mv "$TMP_CSV" "$CSV_FILE"

echo "CSV Preparation Completed:"
echo "- Converted to UNIX format in-place"
echo "--------------------------------"

# Confirmation Prompt
ROW_COUNT=$(($(wc -l < "$CSV_FILE") - 1))
if [[ $ROW_COUNT -lt 0 ]]; then ROW_COUNT=0; fi

echo "Target Suffix: $SUFFIX"
echo "Row Count    : $ROW_COUNT"
if [[ $FORCE -eq 0 ]]; then
  read -r -p "Type YES to confirm execution: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "Execution cancelled by operator."
    exit 0
  fi
fi

# 4.1 Execution
SCRIPT_DIR="${SCRIPT_ROOT}/${DIR_SCRIPT}"
BASH_SCRIPT="${SCRIPT_DIR}/tax_retry_production.sh"

echo "Executing Business Logic Script..."
if [[ ! -f "$BASH_SCRIPT" ]]; then
  echo "Error: Business logic script not found at $BASH_SCRIPT"
  exit 1
fi

set +e # allow script to return non-zero
bash "$BASH_SCRIPT" --suffix "$SUFFIX" --csv "$CSV_FILE"
EXEC_EXIT_CODE=$?
set -e

if [[ $EXEC_EXIT_CODE -ne 0 ]]; then
  echo "Error: Business logic failed with exit code $EXEC_EXIT_CODE."
  echo "CSV will NOT be archived."
  exit $EXEC_EXIT_CODE
fi

# 4.2 Move CSV post-execution
ARCHIVE_CSV_DIR="${SCRIPT_ROOT}/${DIR_CSV_ARCHIVE}"
mkdir -p "$ARCHIVE_CSV_DIR"
mv "$CSV_FILE" "${ARCHIVE_CSV_DIR}/"

# 4.3 Move logs
LOG_ARCHIVE_DIR="${SCRIPT_ROOT}/${DIR_LOG}"
mkdir -p "$LOG_ARCHIVE_DIR"

# The bash script writes logs to the script root directory.
# We will move them using a safe glob pattern.
shopt -s nullglob
SUCCESS_LOGS=("${SCRIPT_ROOT}"/retry_success*.log)
FAILED_LOGS=("${SCRIPT_ROOT}"/retry_failed*.log)
shopt -u nullglob

if [ ${#SUCCESS_LOGS[@]} -gt 0 ]; then
  mv "${SUCCESS_LOGS[@]}" "$LOG_ARCHIVE_DIR/"
fi
if [ ${#FAILED_LOGS[@]} -gt 0 ]; then
  mv "${FAILED_LOGS[@]}" "$LOG_ARCHIVE_DIR/"
fi

echo "Routing Completed:"
echo "- CSV moved to $ARCHIVE_CSV_DIR"
echo "- Logs moved to $LOG_ARCHIVE_DIR"
echo "--------------------------------"
echo "Done."