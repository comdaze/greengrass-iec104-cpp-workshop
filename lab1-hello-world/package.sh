#!/bin/bash
set -e

COMPONENT_NAME="com.example.HelloWorld"
COMPONENT_VERSION="1.0.0"

echo "Packaging ${COMPONENT_NAME} v${COMPONENT_VERSION}..."

# 创建artifacts目录
rm -rf artifacts
mkdir -p artifacts/hello_world

# 复制二进制文件
cp build/hello_world artifacts/hello_world/

# 创建ZIP包
cd artifacts
zip -r ${COMPONENT_NAME}-${COMPONENT_VERSION}.zip hello_world/
cd ..

# 转换recipe为JSON格式
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
