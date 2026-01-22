#!/bin/bash
set -e

echo "Building IoT Publisher..."

rm -rf build
mkdir -p build

cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

echo "Build completed successfully!"
echo "Binary location: build/iot_publisher"
