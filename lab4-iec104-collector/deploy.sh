#!/bin/bash
set -e

export COMPONENT_BUCKET="${COMPONENT_BUCKET:-iec104-components-1769083050}"
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export THING_NAME="${THING_NAME:-MyGreengrassCore}"

COMPONENT_NAME="com.example.IEC104Collector"
COMPONENT_VERSION="1.0.0"
SIMULATOR_VERSION="1.0.0"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Deploying ${COMPONENT_NAME} v${COMPONENT_VERSION} ==="

# 1. Upload to S3
echo "Uploading to S3..."
aws s3 cp artifacts/${COMPONENT_NAME}-${COMPONENT_VERSION}.zip \
  s3://${COMPONENT_BUCKET}/${COMPONENT_NAME}/${COMPONENT_VERSION}/ \
  --region ${AWS_REGION}

# 2. Create component version
echo "Creating component version..."
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" artifacts/recipe.json > artifacts/recipe-updated.json

aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-updated.json \
  --region ${AWS_REGION} 2>&1 || echo "Component version may already exist"

# 3. Deploy to Greengrass (include both simulator and collector)
echo ""
echo "=== Deploying to Greengrass Thing: ${THING_NAME} ==="
echo "Components:"
echo "  - com.example.IEC104SimulatorDocker: ${SIMULATOR_VERSION}"
echo "  - com.example.IEC104Collector: ${COMPONENT_VERSION}"
echo ""

aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Lab4-$(date +%Y%m%d-%H%M%S)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"${SIMULATOR_VERSION}\"
    },
    \"com.example.IEC104Collector\": {
      \"componentVersion\": \"${COMPONENT_VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"serverHost\\\":\\\"127.0.0.1\\\",\\\"serverPort\\\":2404,\\\"reconnectInterval\\\":5000,\\\"ipcTopic\\\":\\\"iec104/data\\\",\\\"accessControl\\\":{\\\"aws.greengrass.ipc.pubsub\\\":{\\\"com.example.IEC104Collector:pubsub:1\\\":{\\\"policyDescription\\\":\\\"Allow publishing to iec104/data topic\\\",\\\"operations\\\":[\\\"aws.greengrass#PublishToTopic\\\"],\\\"resources\\\":[\\\"iec104/data\\\"]}}}}\"
      }
    }
  }" \
  --region ${AWS_REGION}

echo ""
echo "✅ Deployment created successfully!"
echo ""
echo "To check status:"
echo "  sudo /greengrass/v2/bin/greengrass-cli component list"
echo ""
echo "To view logs:"
echo "  sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log"
echo "  sudo tail -f /greengrass/v2/logs/com.example.IEC104SimulatorDocker.log"
