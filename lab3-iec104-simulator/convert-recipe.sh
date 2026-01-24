#!/bin/bash
set -e

INPUT_FILE="${1:-recipe-updated.yaml}"
OUTPUT_FILE="${2:-recipe.json}"

echo "Converting ${INPUT_FILE} to ${OUTPUT_FILE}..."

python3 << EOF
import yaml
import json

with open('${INPUT_FILE}', 'r') as f:
    recipe = yaml.safe_load(f)

with open('${OUTPUT_FILE}', 'w') as f:
    json.dump(recipe, f, indent=2)

print("✅ Recipe converted to JSON: ${OUTPUT_FILE}")
EOF
