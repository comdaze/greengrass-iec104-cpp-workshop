#!/bin/bash
set -e

IMAGE_NAME="iec104-simulator"
IMAGE_TAG="1.0.0"

echo "Testing Docker image locally..."

# Stop existing container if running
docker stop iec104-simulator-test 2>/dev/null || true
docker rm iec104-simulator-test 2>/dev/null || true

# Run container
echo "Starting container..."
docker run -d \
  --name iec104-simulator-test \
  -p 2404:2404 \
  ${IMAGE_NAME}:${IMAGE_TAG}

echo "Container started. Waiting for initialization..."
sleep 3

# Check container status
echo ""
echo "=== Container Status ==="
docker ps | grep iec104-simulator-test

# Check logs
echo ""
echo "=== Container Logs ==="
docker logs iec104-simulator-test

# Test connection
echo ""
echo "=== Testing Connection ==="
nc -zv localhost 2404 || echo "Connection test failed"

echo ""
echo "Container is running. Press Ctrl+C to stop and cleanup."
echo "To view logs: docker logs -f iec104-simulator-test"
echo ""

# Cleanup function
cleanup() {
  echo ""
  echo "Stopping and removing container..."
  docker stop iec104-simulator-test
  docker rm iec104-simulator-test
  echo "Cleanup complete"
}

trap cleanup EXIT

# Keep script running
docker logs -f iec104-simulator-test
