#!/bin/bash
set -e

export COMPONENT_BUCKET="${COMPONENT_BUCKET:-iec104-greengrass-components-1769048317}"
export AWS_REGION="${AWS_REGION:-cn-north-1}"
COMPONENT_NAME="com.example.ConfigDemo"
COMPONENT_VERSION="1.0.0"

echo "Deploying ${COMPONENT_NAME} v${COMPONENT_VERSION}..."

echo "Uploading to S3..."
aws s3 cp artifacts/${COMPONENT_NAME}-${COMPONENT_VERSION}.zip \
  s3://${COMPONENT_BUCKET}/${COMPONENT_NAME}/${COMPONENT_VERSION}/ \
  --region ${AWS_REGION}

sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" artifacts/recipe.json > artifacts/recipe-updated.json

echo "Creating component version..."
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-updated.json \
  --region ${AWS_REGION} 2>&1 || echo "Component may already exist"

echo "Component ready for deployment!"
