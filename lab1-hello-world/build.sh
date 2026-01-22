#!/bin/bash
set -e

echo "Building HelloWorld component..."

# 清理旧的构建
rm -rf build
mkdir -p build

# 构建
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

echo "Build completed successfully!"
echo "Binary location: build/hello_world"
