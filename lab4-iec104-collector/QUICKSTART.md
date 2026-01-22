# Lab 4 快速参考

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab4-iec104-collector

# 构建和部署
./build.sh
./package.sh
./deploy.sh
```

## 同时部署模拟器和采集器

```bash
export THING_NAME='GreengrassQuickStartCore-19be3781cbc'
export AWS_REGION='cn-north-1'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --components '{
    "com.example.IEC104Simulator": {"componentVersion": "1.0.0"},
    "com.example.IEC104Collector": {"componentVersion": "1.0.0"}
  }' \
  --region ${AWS_REGION}
```

## 查看数据

```bash
# 查看日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log

# 查看采集的数据
cat /tmp/iec104-data.json | jq
```
