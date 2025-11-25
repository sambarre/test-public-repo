#!/bin/bash
set -euo pipefail

INPUT_FILE="${1:?Please provide input file}"
BASE_NAME="${INPUT_FILE%.*}"
OUTPUT_FILE="${BASE_NAME}-output.csv"
LOG_FILE="${BASE_NAME}.log"

DNS_SERVERS=("10.0.0.1" "10.0.10.1" "10.0.20.1")
DNS_NAMES=("OLD" "NEW_PROD" "NEW_PREPROD")

# Write CSV header
echo "Record_Type,Record,${DNS_NAMES[*]}" | sed 's/ /,/g' > "$OUTPUT_FILE"

echo "Starting DNS check on $(date)" > "$LOG_FILE"

check_record() {
    local line="$1"
    local type record
    type=$(echo "$line" | cut -d: -f1 | xargs)
    record=$(echo "$line" | cut -d: -f2 | xargs)

    local results=()
    for server in "${DNS_SERVERS[@]}"; do
        local output
        output=$(dig @"$server" "$record" "$type" +short +tries=1 +time=5 2>&1)
        if [[ $? -ne 0 ]]; then
            results+=("ERROR")
            echo "ERROR querying $record ($type) on $server: $output" >> "$LOG_FILE"
        elif [[ -n "$output" ]]; then
            results+=("OK")
            echo "SUCCESS $record ($type) on $server: $output" >> "$LOG_FILE"
        else
            results+=("FAIL")
            echo "FAIL $record ($type) on $server: no answer" >> "$LOG_FILE"
        fi
    done

    # Write the result directly to CSV
    IFS=','; echo "$type,$record,${results[*]}" >> "$OUTPUT_FILE"; unset IFS
}

# Sequential processing
while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" ]] && continue
    check_record "$line"
done < "$INPUT_FILE"

echo "DNS check finished at $(date)" >> "$LOG_FILE"