# Lab 5: AWS IoT Core集成

## 目标

- 将采集的数据发送到AWS IoT Core
- 使用boto3 SDK发布MQTT消息
- 实现云边数据同步
- 监控和可视化数据

## 架构

```
┌─────────────────────────────────────┐
│   AWS IoT Core                      │
│  - MQTT Broker                      │
│  - Topic: wind-farm/data            │
└──────────────┬──────────────────────┘
               │ MQTT (boto3)
               ▼
┌─────────────────────────────────────┐
│   Greengrass Core Device            │
│  ┌───────────────────────────────┐  │
│  │  IEC104 Collector (Lab 4)     │  │
│  │  - 采集数据                   │  │
│  │  - 保存到文件                 │  │
│  └───────────┬───────────────────┘  │
│              │ 读取文件              │
│              ▼                       │
│  ┌───────────────────────────────┐  │
│  │  IoT Publisher (Lab 5)        │  │
│  │  - 读取采集数据               │  │
│  │  - 发布到IoT Core             │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab5-iot-integration

# 本地测试（需要先运行Lab 3和Lab 4）
./test-local.sh

# 打包和部署
./package.sh
./deploy.sh
```

## 前置条件

1. Lab 3 (模拟器) 正在运行
2. Lab 4 (采集器) 正在运行并生成数据
3. AWS凭证已配置
4. IoT Core endpoint可访问

## 配置参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| region | string | "cn-north-1" | AWS区域 |
| topic | string | "wind-farm/data" | IoT Core主题 |
| dataFile | string | "/tmp/iec104-data.json" | 数据文件路径 |
| publishInterval | int | 5 | 发布间隔（秒） |

## 部署完整系统

部署所有三个组件：

```bash
export THING_NAME='GreengrassQuickStartCore-19be3781cbc'
export AWS_REGION='cn-north-1'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "Complete-IEC104-System" \
  --components '{
    "com.example.IEC104Simulator": {
      "componentVersion": "1.0.0"
    },
    "com.example.IEC104Collector": {
      "componentVersion": "1.0.0"
    },
    "com.example.IoTPublisher": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"region\":\"cn-north-1\",\"topic\":\"wind-farm/data\",\"publishInterval\":5}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

## 验证数据

### 方法1: AWS IoT Console

1. 访问 [AWS IoT Console](https://console.amazonaws.cn/iot/)
2. 导航到 **Test** > **MQTT test client**
3. 订阅主题: `wind-farm/data`
4. 查看实时数据

### 方法2: AWS CLI

```bash
# 订阅主题（需要另一个终端）
aws iot-data subscribe \
  --topic "wind-farm/data" \
  --region cn-north-1
```

### 方法3: 查看日志

```bash
# 查看发布器日志
sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log
```

## 发布的数据格式

```json
{
  "timestamp": "2026-01-22T02:30:00Z",
  "publishedAt": "2026-01-22T02:30:05Z",
  "deviceId": "iec104-collector-001",
  "dataPoints": [
    {
      "address": 1001,
      "name": "wind_turbine_1_active_power",
      "value": 1523.45,
      "unit": "kW",
      "quality": "GOOD"
    },
    {
      "address": 1002,
      "name": "wind_turbine_1_reactive_power",
      "value": 215.3,
      "unit": "kVar",
      "quality": "GOOD"
    }
  ]
}
```

## 故障排除

### boto3未安装

```bash
pip3 install boto3
```

### 权限问题

确保Greengrass Token Exchange Role有IoT发布权限：

```json
{
  "Effect": "Allow",
  "Action": [
    "iot:Publish"
  ],
  "Resource": "arn:aws-cn:iot:cn-north-1:*:topic/wind-farm/*"
}
```

### 数据文件不存在

确保Lab 4采集器正在运行：
```bash
ls -la /tmp/iec104-data.json
```

## 总结

🎉 恭喜！你已完成整个Workshop：

- ✅ **Lab 1**: Hello World组件
- ✅ **Lab 2**: 配置管理和日志
- ✅ **Lab 3**: IEC104模拟器组件
- ✅ **Lab 4**: IEC104数据采集组件
- ✅ **Lab 5**: AWS IoT Core集成

### 你现在已经掌握了：

**Greengrass开发**：
- 组件开发和部署
- 配置管理
- 组件依赖
- 生命周期管理

**工业协议集成**：
- IEC104协议
- 数据采集
- 协议模拟

**云边协同**：
- 边缘数据采集
- 云端数据发布
- MQTT通信
- IoT Core集成

### 下一步

- 添加数据持久化（数据库）
- 实现数据分析和告警
- 添加OTA更新
- 集成更多工业协议
