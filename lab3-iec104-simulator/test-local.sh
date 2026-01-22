#!/bin/bash
set -e

echo "Testing IEC104 Simulator locally..."

./build.sh

echo ""
echo "Starting simulator (Press Ctrl+C to stop)..."
echo "Port: 2404"
echo ""

timeout 15 ./build/iec104_simulator config.json || true
