#!/bin/bash
set -e

echo "Testing HelloWorld component locally..."

# 构建
./build.sh

# 创建测试配置
cat > /tmp/test-config.json << EOF
{
  "message": "Testing locally!",
  "interval": 2
}
EOF

echo ""
echo "Starting component (Press Ctrl+C to stop)..."
echo ""

# 运行
./build/hello_world /tmp/test-config.json
