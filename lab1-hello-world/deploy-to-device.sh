#!/bin/bash
# Lab 1 部署脚本 - 完整版

set -e

export THING_NAME='GreengrassQuickStartCore-19be3781cbc'
export AWS_REGION='ap-northeast-1'
export COMPONENT_BUCKET='iec104-greengrass-components-1769048317'

echo "🚀 Lab 1 部署脚本"
echo "================="
echo ""

# 获取账号ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✓ AWS Account: ${ACCOUNT_ID}"
echo "✓ Region: ${AWS_REGION}"
echo "✓ Thing Name: ${THING_NAME}"
echo "✓ S3 Bucket: ${COMPONENT_BUCKET}"
echo ""

# 尝试创建部署
echo "📦 创建部署..."
DEPLOYMENT_ID=$(aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Lab1-$(date +%s)" \
  --components '{"com.example.HelloWorld":{"componentVersion":"1.0.0","configurationUpdate":{"merge":"{\"message\":\"Hello from Greengrass Workshop!\",\"interval\":5}"}}}' \
  --region ${AWS_REGION} \
  --query 'deploymentId' \
  --output text 2>&1)

if [ $? -eq 0 ]; then
    echo "✅ 部署创建成功!"
    echo "   Deployment ID: ${DEPLOYMENT_ID}"
    echo ""
    echo "📊 查看部署状态:"
    echo "   aws greengrassv2 get-deployment --deployment-id ${DEPLOYMENT_ID} --region ${AWS_REGION}"
    echo ""
    echo "📝 查看组件日志:"
    echo "   sudo tail -f /greengrass/v2/logs/com.example.HelloWorld.log"
else
    echo "❌ 部署失败: ${DEPLOYMENT_ID}"
    echo ""
    echo "可能的原因:"
    echo "1. IAM权限还在传播中（等待1-5分钟）"
    echo "2. 使用AWS控制台部署: https://console.amazonaws.cn/iot/home?region=ap-northeast-1#/greengrass/v2/components"
fi
