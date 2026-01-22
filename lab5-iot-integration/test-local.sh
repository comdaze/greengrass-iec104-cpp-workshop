#!/bin/bash
set -e

echo "Testing IoT Publisher locally..."

./build.sh

echo ""
echo "Starting IoT Publisher (Press Ctrl+C to stop)..."
echo "Make sure Lab 4 collector is running to generate data..."
echo ""

timeout 15 ./build/iot_publisher config.json || true
