#!/bin/bash
set -e

# Configuration
IMAGE_NAME="iec104-simulator"
IMAGE_TAG="1.0.0"
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"

# Build Docker image
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

echo "✅ Docker image built successfully"
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"

# Show image info
docker images ${IMAGE_NAME}:${IMAGE_TAG}
