#!/bin/bash
set -e

echo "=========================================="
echo "AWS Greengrass IEC104 Workshop 环境安装"
echo "=========================================="

# 检查是否为 root 或有 sudo 权限
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then 
    echo "错误: 需要 sudo 权限"
    exit 1
fi

# 检测架构
ARCH=$(uname -m)
echo "检测到架构: $ARCH"

# 1. 更新系统
echo ""
echo "[1/8] 更新系统包..."
sudo apt-get update
sudo apt-get upgrade -y

# 2. 安装基础开发工具
echo ""
echo "[2/11] 安装基础开发工具..."
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    zip \
    netcat-openbsd \
    jq \
    vim

# 3. 安装 AWS CLI v2
echo ""
echo "[3/8] 安装 AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    if [ "$ARCH" = "x86_64" ]; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    elif [ "$ARCH" = "aarch64" ]; then
        curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
    else
        echo "不支持的架构: $ARCH"
        exit 1
    fi
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    echo "AWS CLI 安装完成"
else
    echo "AWS CLI 已安装: $(aws --version)"
fi

# 4. 安装 Docker
echo ""
echo "[4/8] 安装 Docker..."
if ! command -v docker &> /dev/null; then
    sudo apt-get install -y \
        ca-certificates \
        gnupg \
        lsb-release
    
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # 启动 Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    echo "Docker 安装完成"
else
    echo "Docker 已安装: $(docker --version)"
fi

# 5. 安装 Java (Greengrass 需要)
echo ""
echo "[5/8] 安装 Java 11..."
if ! command -v java &> /dev/null; then
    sudo apt-get install -y openjdk-11-jdk
    echo "Java 安装完成"
else
    echo "Java 已安装: $(java -version 2>&1 | head -n 1)"
fi

# 6. 安装 C++ 依赖库
echo ""
echo "[6/11] 安装 C++ 依赖库..."

# 6.1 安装 nlohmann/json (JSON 库)
echo "  - 安装 nlohmann/json..."
if [ ! -f "/usr/local/include/nlohmann/json.hpp" ]; then
    cd /tmp
    wget -q https://github.com/nlohmann/json/releases/download/v3.11.2/json.tar.xz
    tar -xf json.tar.xz
    cd json
    sudo mkdir -p /usr/local/include/nlohmann
    sudo cp -r include/nlohmann/* /usr/local/include/nlohmann/
    cd /tmp
    rm -rf json json.tar.xz
    echo "    ✓ nlohmann/json 安装完成"
else
    echo "    ✓ nlohmann/json 已安装"
fi

# 6.2 安装 lib60870 (IEC104 协议库)
echo "  - 安装 lib60870..."
if [ ! -f "/usr/local/lib/liblib60870.a" ] && [ ! -f "/usr/local/lib/liblib60870.so" ]; then
    cd /tmp
    git clone --depth 1 https://github.com/mz-automation/lib60870.git
    cd lib60870/lib60870-C
    mkdir -p build
    cd build
    cmake ..
    make -j$(nproc)
    sudo make install
    sudo ldconfig
    cd /tmp
    rm -rf lib60870
    echo "    ✓ lib60870 安装完成"
else
    echo "    ✓ lib60870 已安装"
fi

# 6.3 安装 AWS IoT Device SDK for C++ v2 依赖
echo "  - 安装 AWS IoT SDK 依赖..."
sudo apt-get install -y \
    libssl-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    uuid-dev

# 注意: AWS IoT SDK 本身通过 git submodule 在各 lab 中下载
echo "    ✓ AWS IoT SDK 依赖安装完成"
echo "    (SDK 本身将在各 lab 中通过 git submodule 下载)"

# 7. 配置用户权限
echo ""
echo "[7/11] 配置用户权限..."
CURRENT_USER=${SUDO_USER:-$USER}
sudo usermod -aG docker $CURRENT_USER
echo "已将 $CURRENT_USER 添加到 docker 组"

# 8. 创建 Greengrass 目录
echo ""
echo "[8/11] 创建 Greengrass 目录..."
sudo mkdir -p /greengrass/v2
sudo chown -R $CURRENT_USER:$CURRENT_USER /greengrass
echo "Greengrass 目录创建完成"

# 9. 下载并编译 AWS IoT Device SDK
echo ""
echo "[9/12] 下载并编译 AWS IoT Device SDK..."

# 检查是否已安装
if [ -f "/usr/local/lib/libGreengrassIpc-cpp.so" ] || [ -f "/usr/local/lib64/libGreengrassIpc-cpp.so" ]; then
    echo "  ✓ AWS IoT SDK 已安装,跳过"
else
    SDK_BUILD_DIR="/tmp/aws-iot-device-sdk-cpp-v2"
    
    echo "  - 下载 AWS IoT Device SDK for C++ v2..."
    if [ -d "$SDK_BUILD_DIR" ]; then
        rm -rf "$SDK_BUILD_DIR"
    fi
    
    git clone --recursive https://github.com/aws/aws-iot-device-sdk-cpp-v2.git "$SDK_BUILD_DIR"
    
    echo "  - 开始编译 (这可能需要 5-10 分钟)..."
    cd "$SDK_BUILD_DIR"
    mkdir -p build
    cd build
    
    echo "  - 配置 CMake..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_DEPS=ON \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        > /dev/null 2>&1
    
    echo "  - 编译中 (使用 $(nproc) 个 CPU 核心)..."
    make -j$(nproc) > /dev/null 2>&1
    
    echo "  - 安装到系统目录..."
    sudo make install > /dev/null 2>&1
    sudo ldconfig
    
    echo "  ✓ AWS IoT SDK 编译安装完成"
    
    # 清理临时文件
    cd /tmp
    rm -rf "$SDK_BUILD_DIR"
fi

# 10. 复制 nlohmann/json 到各 lab 目录
echo ""
echo "[10/10] 复制依赖库到 lab 目录..."
WORKSHOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$WORKSHOP_DIR" ]; then
    # Lab 1
    if [ -d "$WORKSHOP_DIR/lab1-hello-world" ] && [ ! -d "$WORKSHOP_DIR/lab1-hello-world/nlohmann" ]; then
        cp -r /usr/local/include/nlohmann "$WORKSHOP_DIR/lab1-hello-world/"
        echo "  ✓ 复制 nlohmann 到 lab1"
    fi
    
    # Lab 2
    if [ -d "$WORKSHOP_DIR/lab2-config-logging" ] && [ ! -d "$WORKSHOP_DIR/lab2-config-logging/nlohmann" ]; then
        cp -r /usr/local/include/nlohmann "$WORKSHOP_DIR/lab2-config-logging/"
        echo "  ✓ 复制 nlohmann 到 lab2"
    fi
    
    # Lab 3
    if [ -d "$WORKSHOP_DIR/lab3-iec104-simulator" ] && [ ! -d "$WORKSHOP_DIR/lab3-iec104-simulator/nlohmann" ]; then
        cp -r /usr/local/include/nlohmann "$WORKSHOP_DIR/lab3-iec104-simulator/"
        echo "  ✓ 复制 nlohmann 到 lab3"
    fi
    
    echo "  ✓ 依赖库复制完成"
else
    echo "  ⚠ Workshop 目录未找到,跳过"
fi

# 11. 验证安装
echo ""
echo "[11/11] 验证安装..."
echo "=========================================="
echo "系统工具:"
echo "  ✓ GCC: $(gcc --version | head -n 1)"
echo "  ✓ CMake: $(cmake --version | head -n 1)"
echo "  ✓ Git: $(git --version)"
echo "  ✓ AWS CLI: $(aws --version)"
echo "  ✓ Docker: $(docker --version)"
echo "  ✓ Java: $(java -version 2>&1 | head -n 1)"
echo ""
echo "C++ 依赖库:"
if [ -f "/usr/local/include/nlohmann/json.hpp" ]; then
    echo "  ✓ nlohmann/json: 已安装"
else
    echo "  ✗ nlohmann/json: 未安装"
fi
if [ -f "/usr/local/lib/liblib60870.a" ] || [ -f "/usr/local/lib/liblib60870.so" ]; then
    echo "  ✓ lib60870: 已安装"
else
    echo "  ✗ lib60870: 未安装"
fi
if [ -f "/usr/local/lib/libGreengrassIpc-cpp.so" ] || [ -f "/usr/local/lib64/libGreengrassIpc-cpp.so" ]; then
    echo "  ✓ AWS IoT SDK: 已编译安装"
else
    echo "  ⚠ AWS IoT SDK: 未安装 (Lab4/Lab5 需要)"
fi
echo "=========================================="

echo ""
echo "=========================================="
echo "✅ 环境安装完成！"
echo "=========================================="
echo ""
echo "下一步操作："
echo "1. 配置 AWS 凭证:"
echo "   aws configure"
echo ""
echo "2. 安装 AWS IoT Greengrass Core:"
echo "   cd /home/$CURRENT_USER/workshop"
echo "   ./install-greengrass.sh"
echo ""
echo "3. 重新登录以使 docker 组权限生效:"
echo "   exit"
echo "   # 然后重新 SSH 登录"
echo ""
