#!/bin/bash
set -e

export COMPONENT_BUCKET="${COMPONENT_BUCKET:-iec104-components-1769083050}"
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export THING_NAME="${THING_NAME:-MyGreengrassCore}"

COMPONENT_NAME="com.example.IoTPublisher"
COMPONENT_VERSION="1.0.4"
SIMULATOR_VERSION="1.0.3"
COLLECTOR_VERSION="1.0.16"

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

# 3. Deploy complete system (simulator + collector + publisher)
echo ""
echo "=== Deploying Complete IEC104 System to: ${THING_NAME} ==="
echo "Components:"
echo "  - com.example.IEC104SimulatorDocker: ${SIMULATOR_VERSION}"
echo "  - com.example.IEC104Collector: ${COLLECTOR_VERSION}"
echo "  - com.example.IoTPublisher: ${COMPONENT_VERSION}"
echo ""

aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Complete-Lab5-$(date +%Y%m%d-%H%M%S)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"${SIMULATOR_VERSION}\"
    },
    \"com.example.IEC104Collector\": {
      \"componentVersion\": \"${COLLECTOR_VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"serverHost\\\":\\\"127.0.0.1\\\",\\\"serverPort\\\":2404,\\\"reconnectInterval\\\":5000,\\\"ipcTopic\\\":\\\"iec104/data\\\",\\\"accessControl\\\":{\\\"aws.greengrass.ipc.pubsub\\\":{\\\"com.example.IEC104Collector:pubsub:1\\\":{\\\"policyDescription\\\":\\\"Allow publishing to iec104/data topic\\\",\\\"operations\\\":[\\\"aws.greengrass#PublishToTopic\\\"],\\\"resources\\\":[\\\"iec104/data\\\"]}}}}\"
      }
    },
    \"com.example.IoTPublisher\": {
      \"componentVersion\": \"${COMPONENT_VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"ipcTopic\\\":\\\"iec104/data\\\",\\\"iotTopic\\\":\\\"wind-farm/data\\\",\\\"accessControl\\\":{\\\"aws.greengrass.ipc.pubsub\\\":{\\\"com.example.IoTPublisher:pubsub:1\\\":{\\\"policyDescription\\\":\\\"Allow subscribing to iec104/data topic\\\",\\\"operations\\\":[\\\"aws.greengrass#SubscribeToTopic\\\"],\\\"resources\\\":[\\\"iec104/data\\\"]}},\\\"aws.greengrass.ipc.mqttproxy\\\":{\\\"com.example.IoTPublisher:mqttproxy:1\\\":{\\\"policyDescription\\\":\\\"Allow publishing to IoT Core\\\",\\\"operations\\\":[\\\"aws.greengrass#PublishToIoTCore\\\"],\\\"resources\\\":[\\\"wind-farm/data\\\"]}}}}\"
      }
    }
  }" \
  --region ${AWS_REGION}

echo ""
echo "✅ Complete system deployed successfully!"
echo ""
echo "To check status:"
echo "  sudo /greengrass/v2/bin/greengrass-cli component list"
echo ""
echo "To view logs:"
echo "  sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log"
echo "  sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log"
echo ""
echo "To monitor IoT Core messages:"
echo "  aws iot-data get-thing-shadow --thing-name ${THING_NAME} --region ${AWS_REGION}"
echo "  # Or use AWS IoT Console MQTT test client"
