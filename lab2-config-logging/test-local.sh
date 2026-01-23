#!/bin/bash
set -e

echo "Testing ConfigDemo component locally..."

cat > /tmp/test-config-demo.json << EOF
{
  "message": "Testing Lab 2 locally!",
  "interval": 2,
  "logLevel": "DEBUG",
  "logToConsole": true,
  "logToFile": true,
  "logFilePath": "/tmp/lab2-test.log",
  "counterThreshold": 5
}
EOF

echo ""
echo "Starting component (Press Ctrl+C to stop)..."
echo "Log file: /tmp/lab2-test.log"
echo ""

./build/config_demo /tmp/test-config-demo.json
