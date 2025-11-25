#!/bin/bash
set -euo pipefail

# Ensure an input file was provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

INPUT_FILE="$1"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Input file '$INPUT_FILE' not found."
    exit 1
fi

# Build output filename: records.txt → records_output.csv
BASENAME="${INPUT_FILE%.*}"
OUTPUT_FILE="${BASENAME}_output.csv"

# DNS servers to test
DNS_SERVERS=("10.0.0.1" "10.0.10.1" "10.0.20.1")   # replace with your actual servers
DNS_NAMES=("OLD" "NEW_PROD" "NEW_PREPROD")

# Write header
echo "Record_Type,Record,${DNS_NAMES[*]}" | sed 's/ /,/g' > "$OUTPUT_FILE"

while IFS=: read -r type record; do
    type=$(echo "$type" | xargs)
    record=$(echo "$record" | xargs)

    [[ -z "$type" || -z "$record" ]] && continue

    results=()
    for server in "${DNS_SERVERS[@]}"; do
        if dig @"$server" "$record" "$type" +short | grep -q .; then
            results+=("OK")
        else
            results+=("FAIL")
        fi
    done

    echo "$type,$record,${results[*]}" | sed 's/ /,/g' >> "$OUTPUT_FILE"
done < "$INPUT_FILE"

echo "Done! Results saved to $OUTPUT_FILE"