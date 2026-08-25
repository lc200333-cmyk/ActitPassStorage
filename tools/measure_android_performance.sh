#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ID="${PACKAGE_ID:-com.example.actit_pass_storage}"
SAMPLES="${SAMPLES:-10}"
OUTPUT_DIR="${OUTPUT_DIR:-build/performance}"
mkdir -p "$OUTPUT_DIR"
OUTPUT="$OUTPUT_DIR/android-memory.txt"
: > "$OUTPUT"
for ((sample = 1; sample <= SAMPLES; sample++)); do
  printf '\n===== sample %s %s =====\n' "$sample" "$(date -u +%FT%TZ)" >> "$OUTPUT"
  adb shell dumpsys meminfo "$PACKAGE_ID" >> "$OUTPUT"
  sleep 1
done
echo "Android memory report: $OUTPUT"
