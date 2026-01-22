#!/bin/bash
set -e

export COMPONENT_BUCKET="${COMPONENT_BUCKET:-iec104-components-1769083050}"
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export THING_NAME="${THING_NAME:-MyGreengrassCore}"

COMPONENT_NAME="com.example.IEC104SimulatorDocker"
COMPONENT_VERSION="1.0.3"
ECR_IMAGE="429058178429.dkr.ecr.${AWS_REGION}.amazonaws.com/iec104-simulator:1.0.0"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Pre-deployment Checks ==="

# 确保 ggc_user 有 docker 权限
echo "Checking docker permissions for ggc_user..."
if ! groups ggc_user 2>/dev/null | grep -q docker; then
  echo "Adding ggc_user to docker group..."
  sudo usermod -aG docker ggc_user
  echo "⚠️  ggc_user added to docker group. Greengrass needs restart:"
  echo "   sudo systemctl restart greengrass"
else
  echo "✅ ggc_user already in docker group"
fi

echo ""
echo "=== Deploying ${COMPONENT_NAME} v${COMPONENT_VERSION} ==="

# Note: Docker image should already be in ECR
echo "Using ECR image: ${ECR_IMAGE}"

# Create component version (no artifact upload needed for Docker components)
echo "Creating component version..."
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe.json \
  --region ${AWS_REGION} 2>&1 || echo "Component version may already exist"

# Deploy to Greengrass
echo ""
echo "=== Deploying to Greengrass Thing: ${THING_NAME} ==="
echo "Component: ${COMPONENT_NAME} v${COMPONENT_VERSION}"
echo ""

aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Lab3-$(date +%Y%m%d-%H%M%S)" \
  --components "{
    \"${COMPONENT_NAME}\": {
      \"componentVersion\": \"${COMPONENT_VERSION}\"
    }
  }" \
  --region ${AWS_REGION}

echo ""
echo "✅ Deployment created successfully!"
echo ""
echo "To check status:"
echo "  sudo /greengrass/v2/bin/greengrass-cli component list"
echo "  sudo docker ps | grep iec104"
echo ""
echo "To view logs:"
echo "  sudo tail -f /greengrass/v2/logs/com.example.IEC104SimulatorDocker.log"
echo "  sudo docker logs -f iec104-simulator"
