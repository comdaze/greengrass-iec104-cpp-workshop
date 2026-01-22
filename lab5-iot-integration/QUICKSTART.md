# Lab 5 快速参考

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab5-iot-integration

# 构建
./build.sh

# 本地测试
./test-local.sh

# 打包和部署
./package.sh
./deploy.sh
```

## 部署完整系统

```bash
export THING_NAME='GreengrassQuickStartCore-19be3781cbc'
export AWS_REGION='cn-north-1'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --components '{
    "com.example.IEC104Simulator": {"componentVersion": "1.0.0"},
    "com.example.IEC104Collector": {"componentVersion": "1.0.0"},
    "com.example.IoTPublisher": {"componentVersion": "1.0.0"}
  }' \
  --region ${AWS_REGION}
```

## 验证

```bash
# 查看日志
sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log

# AWS IoT Console订阅主题
# Topic: wind-farm/data
```
