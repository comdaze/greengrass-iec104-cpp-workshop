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
echo "[2/8] 安装基础开发工具..."
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    netcat \
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

# 6. 配置用户权限
echo ""
echo "[6/8] 配置用户权限..."
CURRENT_USER=${SUDO_USER:-$USER}
sudo usermod -aG docker $CURRENT_USER
echo "已将 $CURRENT_USER 添加到 docker 组"

# 7. 创建 Greengrass 目录
echo ""
echo "[7/8] 创建 Greengrass 目录..."
sudo mkdir -p /greengrass/v2
sudo chown -R $CURRENT_USER:$CURRENT_USER /greengrass
echo "Greengrass 目录创建完成"

# 8. 验证安装
echo ""
echo "[8/8] 验证安装..."
echo "----------------------------------------"
echo "✓ GCC: $(gcc --version | head -n 1)"
echo "✓ CMake: $(cmake --version | head -n 1)"
echo "✓ Git: $(git --version)"
echo "✓ AWS CLI: $(aws --version)"
echo "✓ Docker: $(docker --version)"
echo "✓ Java: $(java -version 2>&1 | head -n 1)"
echo "----------------------------------------"

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
