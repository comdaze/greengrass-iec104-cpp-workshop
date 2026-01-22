#!/bin/bash
set -e

COMPONENT_NAME="com.example.ConfigDemo"
COMPONENT_VERSION="1.0.0"

echo "Packaging ${COMPONENT_NAME} v${COMPONENT_VERSION}..."

rm -rf artifacts
mkdir -p artifacts/config_demo

cp build/config_demo artifacts/config_demo/

cd artifacts
zip -r ${COMPONENT_NAME}-${COMPONENT_VERSION}.zip config_demo/
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
echo "  - artifacts/${COMPONENT_NAME}-${COMPONENT_VERSION}.zip"
echo "  - artifacts/recipe.json"
