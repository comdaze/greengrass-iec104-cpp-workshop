# Lab 4: IEC104数据采集组件

## 目标

- 连接到IEC104模拟器
- 采集风电和储能数据
- 数据处理和缓存
- 组件间通信

## 架构

```
┌─────────────────────────────────────┐
│   Greengrass Core Device            │
│                                     │
│  ┌───────────────────────────────┐  │
│  │  IEC104 Simulator (Lab 3)     │  │
│  │  Port: 2404                   │  │
│  └───────────┬───────────────────┘  │
│              │ TCP/IEC104           │
│              ▼                       │
│  ┌───────────────────────────────┐  │
│  │  IEC104 Collector (Lab 4)     │  │
│  │  - 连接模拟器                 │  │
│  │  - 数据采集                   │  │
│  │  - 数据处理                   │  │
│  │  - 本地存储                   │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab4-iec104-collector

# 本地测试（需要先启动Lab 3模拟器）
./test-local.sh

# 构建、打包、部署
./build.sh
./package.sh
./deploy.sh
```

## 部署（同时部署模拟器和采集器）

```bash
export THING_NAME='GreengrassQuickStartCore-19be3781cbc'
export AWS_REGION='cn-north-1'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Complete-Lab4" \
  --components '{
    "com.example.IEC104Simulator": {
      "componentVersion": "1.0.0"
    },
    "com.example.IEC104Collector": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"serverHost\":\"localhost\",\"serverPort\":2404,\"reconnectInterval\":5000}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

## 验证

```bash
# 查看采集器日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log

# 查看采集的数据
cat /tmp/iec104-data.json
```

## 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| serverHost | string | "localhost" | IEC104服务器地址 |
| serverPort | int | 2404 | IEC104服务器端口 |
| reconnectInterval | int | 5000 | 重连间隔（毫秒） |
| dataTimeout | int | 30000 | 数据超时（毫秒） |
| maxReconnectAttempts | int | 10 | 最大重连次数 |

## 采集的数据格式

```json
{
  "timestamp": "2026-01-22T02:30:00Z",
  "deviceId": "iec104-collector-001",
  "dataPoints": [
    {
      "address": 1001,
      "name": "wind_turbine_1_active_power",
      "value": 1523.45,
      "unit": "kW",
      "quality": "GOOD"
    }
  ]
}
```

## 下一步

- **Lab 5**: 将采集的数据发送到AWS IoT Core
