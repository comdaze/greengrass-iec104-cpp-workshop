#!/bin/bash
set -e

echo "Building ConfigDemo component..."

rm -rf build
mkdir -p build

cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

echo "Build completed successfully!"
echo "Binary location: build/config_demo"
