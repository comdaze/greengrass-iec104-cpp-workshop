#!/bin/bash
set -e

export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export THING_NAME="${THING_NAME:-MyGreengrassCore}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Deploying All Workshop Components ==="
echo "Thing: ${THING_NAME}"
echo "Region: ${AWS_REGION}"
echo ""

# 定义所有组件
COMPONENTS='{
  "aws.greengrass.Cli": {
    "componentVersion": "2.12.0"
  },
  "aws.greengrass.LogManager": {
    "componentVersion": "2.3.11",
    "configurationUpdate": {
      "merge": "{\"logsUploaderConfiguration\":{\"systemLogsConfiguration\":{\"uploadToCloudWatch\":\"true\",\"minimumLogLevel\":\"INFO\"}}}"
    }
  },
  "com.example.HelloWorld": {
    "componentVersion": "1.0.0",
    "configurationUpdate": {
      "merge": "{\"message\":\"Hello from Lab 1!\",\"interval\":5}"
    }
  },
  "com.example.ConfigDemo": {
    "componentVersion": "1.0.0",
    "configurationUpdate": {
      "merge": "{\"message\":\"Lab 2 is working!\",\"interval\":5,\"logLevel\":\"INFO\"}"
    }
  },
  "com.example.IEC104SimulatorDocker": {
    "componentVersion": "1.0.3"
  },
  "com.example.IEC104Collector": {
    "componentVersion": "1.0.1"
  },
  "com.example.IoTPublisher": {
    "componentVersion": "1.0.1"
  }
}'

echo "Components to deploy:"
echo "$COMPONENTS" | jq -r 'keys[]' | sed 's/^/  - /'
echo ""

read -p "Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "Workshop-All-Labs-$(date +%Y%m%d-%H%M%S)" \
  --components "$COMPONENTS" \
  --region ${AWS_REGION}

echo ""
echo "✅ Deployment created successfully!"
echo ""
echo "To check status:"
echo "  sudo /greengrass/v2/bin/greengrass-cli component list"
echo ""
echo "To view logs:"
echo "  sudo tail -f /greengrass/v2/logs/*.log"
