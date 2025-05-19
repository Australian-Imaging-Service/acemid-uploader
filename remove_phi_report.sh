#!/bin/bash

# Input and output dermx report files
INPUT_PDF="input_dermx_report.pdf"
TEXT_FILE="output_dermx_report.txt"
REDACTED_TEXT="redacted_dermx_report.txt"
OUTPUT_PDF="redacted_dermx_report_output.pdf"

# Step 1: Extract text from input dermx report PDF
pdftotext "$INPUT_PDF" "$TEXT_FILE"

# Step 2: Remove the patient name of report
sed -E '
s/(report for )([A-Z][a-z]+ [A-Z][a-z]+)/\1[PATIENT NAME]/g;
' "$TEXT_FILE" > "$REDACTED_TEXT"

# Step 3: Convert redacted text back to PDF
enscript "$REDACTED_TEXT" -o - | ps2pdf - "$OUTPUT_PDF"

echo "Redacted PDF created: $OUTPUT_PDF"
