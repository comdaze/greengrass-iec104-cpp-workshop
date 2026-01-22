#!/bin/bash
set -e

COMPONENT_NAME="com.example.IoTPublisher"
COMPONENT_VERSION="1.0.4"

echo "Packaging ${COMPONENT_NAME} v${COMPONENT_VERSION}..."

rm -rf artifacts
mkdir -p artifacts/iot_publisher

cp build/iot_publisher artifacts/iot_publisher/

cd artifacts
zip -r ${COMPONENT_NAME}-${COMPONENT_VERSION}.zip iot_publisher/
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
