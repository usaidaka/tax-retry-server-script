#!/bin/bash

# Source configuration
source "$(dirname "$0")/config.sh"

echo "Retry Manual Tax Automation"
echo "--------------------------------"

# Default values
SUFFIX=""

# Parse CLI parameters
while [[ $# -gt 0 ]]; do
  case $1 in
    --suffix)
      SUFFIX="$2"
      shift 2
      ;;
    --help)
      echo "Usage: ./retry.sh --suffix <SUFFIX>"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$SUFFIX" ]]; then
  echo "Error: Missing required parameters."
  echo "Usage: ./retry.sh --suffix <SUFFIX>"
  exit 1
fi

# Suffix Automation
if [[ "${SUFFIX:0:1}" != "_" ]]; then
  SUFFIX="_${SUFFIX}"
fi

echo "Parameter Validation Passed:"
echo "- Suffix   : $SUFFIX"
echo "--------------------------------"

# Check CSV files in folder 02
EXEC_CSV_DIR="$(dirname "$0")/${DIR_CSV_EXECUTE}"
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

# 4.1 Execution
SCRIPT_DIR="$(dirname "$0")/${DIR_SCRIPT}"
PS_SCRIPT="${SCRIPT_DIR}/v2_tax_retry_production.ps1"

echo "Executing Business Logic Script..."
if command -v pwsh &> /dev/null; then
  pwsh -File "$PS_SCRIPT" -ManualRetrySuffix "$SUFFIX" -CsvPath "$CSV_FILE"
elif command -v powershell &> /dev/null; then
  powershell -File "$PS_SCRIPT" -ManualRetrySuffix "$SUFFIX" -CsvPath "$CSV_FILE"
else
  echo "Error: 'pwsh' or 'powershell' not found in PATH."
  echo "Please install PowerShell Core to run this script."
  # For testing purposes, we don't exit 1 if this is a CI/CD environment without pwsh, 
  # but in production, we should.
  exit 1
fi
EXEC_EXIT_CODE=$?

if [[ $EXEC_EXIT_CODE -ne 0 ]]; then
  echo "Error: Execution failed with exit code $EXEC_EXIT_CODE"
  exit $EXEC_EXIT_CODE
fi

# 4.2 Move CSV post-execution
ARCHIVE_CSV_DIR="$(dirname "$0")/${DIR_CSV_ARCHIVE}"
mkdir -p "$ARCHIVE_CSV_DIR"
mv "$CSV_FILE" "${ARCHIVE_CSV_DIR}/"

# 4.3 Move logs
LOG_ARCHIVE_DIR="$(dirname "$0")/${DIR_LOG}"
mkdir -p "$LOG_ARCHIVE_DIR"

# The PowerShell script writes logs to the current working directory, 
# or maybe to SCRIPT_DIR depending on where it's run from.
# Let's move any retry_* logs from both locations just in case.
mv retry_success*.log "$LOG_ARCHIVE_DIR" 2>/dev/null
mv retry_failed*.log "$LOG_ARCHIVE_DIR" 2>/dev/null
mv "${SCRIPT_DIR}"/retry_success*.log "$LOG_ARCHIVE_DIR" 2>/dev/null
mv "${SCRIPT_DIR}"/retry_failed*.log "$LOG_ARCHIVE_DIR" 2>/dev/null

echo "Routing Completed:"
echo "- CSV moved to $ARCHIVE_CSV_DIR"
echo "- Logs moved to $LOG_ARCHIVE_DIR"
echo "--------------------------------"
echo "Done."