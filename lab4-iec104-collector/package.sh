#!/bin/bash
set -e

COMPONENT_NAME="com.example.IEC104Collector"
COMPONENT_VERSION="${VERSION:-1.0.1}"

echo "Packaging ${COMPONENT_NAME} v${COMPONENT_VERSION}..."

rm -rf artifacts
mkdir -p artifacts/iec104_collector

cp build/iec104_collector artifacts/iec104_collector/

cd artifacts
zip -r ${COMPONENT_NAME}-${COMPONENT_VERSION}.zip iec104_collector/
cd ..

python3 -c "
import yaml
import json

with open('recipe.yaml', 'r') as f:
    recipe = yaml.safe_load(f)

with open('artifacts/recipe.json', 'w') as f:
    json.dump(recipe, f, indent=2)
"

echo "Package created successfully!"
