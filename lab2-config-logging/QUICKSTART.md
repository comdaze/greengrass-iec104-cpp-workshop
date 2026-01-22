# Lab 2 快速参考

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab2-config-logging

# 本地测试
./test-local.sh

# 构建和部署
./build.sh
./package.sh
./deploy.sh
```

## 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| message | string | "Hello from Lab 2!" | 输出消息 |
| interval | int | 5 | 间隔秒数 |
| logLevel | string | "INFO" | DEBUG/INFO/WARN/ERROR |
| logToConsole | bool | true | 控制台输出 |
| logToFile | bool | true | 文件输出 |
| logFilePath | string | "/tmp/lab2-config-demo.log" | 日志文件路径 |
| counterThreshold | int | 10 | 计数器阈值 |

## 配置更新示例

### 修改日志级别为DEBUG
```bash
export THING_NAME='GreengrassQuickStartCore-19be3781cbc'
export AWS_REGION='cn-north-1'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --components '{"com.example.ConfigDemo":{"componentVersion":"1.0.0","configurationUpdate":{"merge":"{\"logLevel\":\"DEBUG\"}"}}}' \
  --region ${AWS_REGION}
```

### 修改消息和间隔
```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --components '{"com.example.ConfigDemo":{"componentVersion":"1.0.0","configurationUpdate":{"merge":"{\"message\":\"Updated!\",\"interval\":3}"}}}' \
  --region ${AWS_REGION}
```

## 查看日志

```bash
# Greengrass组件日志
sudo tail -f /greengrass/v2/logs/com.example.ConfigDemo.log

# 应用日志文件
sudo tail -f /tmp/lab2-config-demo.log
```
