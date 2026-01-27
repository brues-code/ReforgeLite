#!/bin/bash
# Extract all L["..."] and L['...'] localization strings from lua files
# Usage: ./extract_localization.sh [directory] [output_file]
# Output: L["string"] = true (one per line)

DIR="${1:-.}"
OUTPUT="${2:-localization_strings.lua}"

{
    grep -rhoP 'L\["[^"]+"\]' --include="*.lua" --exclude-dir=dev "$DIR" 2>/dev/null
    grep -rhoP "L\['[^']+'\]" --include="*.lua" --exclude-dir=dev "$DIR" 2>/dev/null | sed "s/L\['/L[\"/g; s/'\]/\"]/g"
} | sort -u | sed 's/$/ = true/' > "$OUTPUT"

echo "Saved $(wc -l < "$OUTPUT") strings to $OUTPUT"
