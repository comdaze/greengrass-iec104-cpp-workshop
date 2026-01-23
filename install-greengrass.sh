#!/bin/bash
set -e

echo "=========================================="
echo "安装 AWS IoT Greengrass Core"
echo "=========================================="

# 检查 AWS CLI 配置
if ! aws sts get-caller-identity &> /dev/null; then
    echo "错误: AWS CLI 未配置，请先运行 'aws configure'"
    exit 1
fi

# 获取配置
read -p "输入 AWS Region [ap-northeast-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-ap-northeast-1}

read -p "输入 Thing Name [MyGreengrassCore]: " THING_NAME
THING_NAME=${THING_NAME:-MyGreengrassCore}

echo ""
echo "配置信息:"
echo "  Region: $AWS_REGION"
echo "  Thing Name: $THING_NAME"
echo ""
read -p "确认安装? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# 下载 Greengrass
echo ""
echo "[1/3] 下载 Greengrass Core..."
cd /tmp
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > greengrass-nucleus-latest.zip
unzip -q greengrass-nucleus-latest.zip -d GreengrassInstaller

# 安装 Greengrass
echo ""
echo "[2/3] 安装 Greengrass Core..."
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
  -jar ./GreengrassInstaller/lib/Greengrass.jar \
  --aws-region $AWS_REGION \
  --thing-name $THING_NAME \
  --provision true \
  --setup-system-service true

# 配置 ggc_user 权限
echo ""
echo "[3/3] 配置权限..."
sudo usermod -aG docker ggc_user

# 清理
rm -rf /tmp/GreengrassInstaller /tmp/greengrass-nucleus-latest.zip

echo ""
echo "=========================================="
echo "✅ Greengrass Core 安装完成！"
echo "=========================================="
echo ""
echo "验证安装:"
echo "  sudo /greengrass/v2/bin/greengrass-cli component list"
echo ""
echo "查看日志:"
echo "  sudo tail -f /greengrass/v2/logs/greengrass.log"
echo ""
