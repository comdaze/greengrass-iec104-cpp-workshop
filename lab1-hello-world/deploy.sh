#!/bin/bash
set -e

# 配置
COMPONENT_NAME="com.example.HelloWorld"
COMPONENT_VERSION="1.0.0"
AWS_REGION="${AWS_REGION:-us-east-1}"
COMPONENT_BUCKET="${COMPONENT_BUCKET:-}"

if [ -z "$COMPONENT_BUCKET" ]; then
    echo "Error: COMPONENT_BUCKET environment variable is not set"
    echo "Usage: export COMPONENT_BUCKET=your-bucket-name"
    exit 1
fi

echo "Deploying ${COMPONENT_NAME} v${COMPONENT_VERSION}..."

# 上传到S3
echo "Uploading to S3..."
aws s3 cp artifacts/${COMPONENT_NAME}-${COMPONENT_VERSION}.zip \
  s3://${COMPONENT_BUCKET}/${COMPONENT_NAME}/${COMPONENT_VERSION}/ \
  --region ${AWS_REGION}

# 更新recipe中的S3 URI
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" artifacts/recipe.json > artifacts/recipe-updated.json

# 创建组件版本
echo "Creating component version..."
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-updated.json \
  --region ${AWS_REGION}

echo "Component version created successfully!"
echo "You can now deploy it through AWS Console or CLI"
