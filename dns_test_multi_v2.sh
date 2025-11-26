#!/bin/bash
set -euo pipefail

INPUT_FILE="${1:?Please provide input file}"
BASE_NAME="${INPUT_FILE%.*}"
OUTPUT_FILE="${BASE_NAME}-output.csv"
LOG_FILE="${BASE_NAME}.log"

DNS_SERVERS=("10.0.0.1" "10.0.10.1" "10.0.20.1")
DNS_NAMES=("OLD" "NEW_PROD" "NEW_PREPROD")

MAX_JOBS=50       # Safe upper limit
LOCK_FD=200       # File descriptor for flock

# Create output CSV with header
echo "Record_Type,Record,${DNS_NAMES[*]}" | sed 's/ /,/g' > "$OUTPUT_FILE"
echo "Starting DNS check on $(date)" > "$LOG_FILE"

# Open output file for locking
exec {LOCK_FD}>>"$OUTPUT_FILE"

# ---- FUNCTION: CLEANLY PARSE RECORD ----
parse_line() {
    local line="$1"

    # Remove leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Ignore empty or malformed lines
    if [[ -z "$line" || "$line" != *:* ]]; then
        echo ""
        return
    fi

    # Safely split on first colon ONLY
    local type="${line%%:*}"
    local record="${line#*:}"

    # Trim whitespace
    type="$(echo "$type" | sed 's/^[ \t]*//;s/[ \t]*$//')"
    record="$(echo "$record" | sed 's/^[ \t]*//;s/[ \t]*$//')"

    echo "$type:$record"
}

# ---- FUNCTION: PER-RECORD CHECK ----
check_record() {
    local line_raw="$1"

    # Safely parse line
    local parsed
    parsed=$(parse_line "$line_raw")
    [[ -z "$parsed" ]] && return

    local type="${parsed%%:*}"
    local record="${parsed#*:}"

    echo "START $record ($type)" >> "$LOG_FILE"

    local results=()

    for server in "${DNS_SERVERS[@]}"; do
        local output status

        # Run dig (never let it kill the subshell)
        output=$(dig @"$server" "$record" "$type" +short +tries=1 +time=5 2>&1) || true
        status=$?

        # Classification
        if [[ $status -ne 0 ]]; then
            results+=("ERROR")
            echo "ERROR $record ($type) on $server: exit code $status / $output" >> "$LOG_FILE"

        elif [[ -z "$output" ]]; then
            results+=("FAIL")
            echo "FAIL $record ($type) on $server: no answer" >> "$LOG_FILE"

        elif echo "$output" | grep -qiE 'timed out|servfail|refused|no servers|connection timed'; then
            results+=("ERROR")
            echo "ERROR $record ($type) on $server: $output" >> "$LOG_FILE"

        else
            results+=("OK")
            echo "SUCCESS $record ($type) on $server: $output" >> "$LOG_FILE"
        fi
    done

    # ---- SAFE CSV WRITE ----
    flock "$LOCK_FD"
    {
        IFS=','; echo "$type,$record,${results[*]}"
        unset IFS
    } >&$LOCK_FD

    echo "END $record ($type)" >> "$LOG_FILE"
}

# ---- JOB CONTROL ----
jobs_running() { jobs -rp | wc -l; }

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip totally empty lines
    [[ -z "$line" ]] && continue

    check_record "$line" &

    # throttle
    while [[ "$(jobs_running)" -ge "$MAX_JOBS" ]]; do
        sleep 0.1
    done
done < "$INPUT_FILE"

wait

echo "DNS check finished at $(date)" >> "$LOG_FILE"
