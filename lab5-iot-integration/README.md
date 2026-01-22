# Lab 5: AWS IoT Core 集成

## 🎯 目标

将 IEC104 采集的数据通过 Greengrass IPC 订阅，并转发到 AWS IoT Core，实现完整的边缘到云数据管道。

**学习要点**：
- Greengrass IPC SubscribeToTopic 操作
- PublishToIoTCore 操作
- 异步消息处理模式
- 避免回调阻塞的最佳实践

## 📐 架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Greengrass Core Device                                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IEC104 Collector (Lab 4)                                │  │
│  │  - 采集 IEC104 数据                                       │  │
│  │  - 发布到 IPC topic: iec104/data                         │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │ IPC Pubsub                              │
│                       ↓                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IoT Publisher (Lab 5)                                   │  │
│  │  - 订阅 IPC topic: iec104/data                           │  │
│  │  - 消息队列缓冲                                           │  │
│  │  - 主线程发布到 IoT Core                                  │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │ MQTT over TLS                           │
└───────────────────────┼─────────────────────────────────────────┘
                        │
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  AWS IoT Core                                                   │
│  - Topic: wind-farm/data                                        │
│  - QoS: AT_LEAST_ONCE                                           │
└─────────────────────────────────────────────────────────────────┘
```

## 🔑 关键技术点

### 1. 异步消息处理

**问题**：在 `OnStreamEvent` 回调中直接调用 `PublishToIoTCore` 会阻塞事件循环。

**解决方案**：使用消息队列在主线程中处理发布。

```cpp
// 在回调中只接收消息，放入队列
void OnStreamEvent(SubscriptionResponseMessage *response) override {
    auto messageBytes = response->GetBinaryMessage().value().GetMessage().value();
    std::string payload(messageBytes.begin(), messageBytes.end());
    
    std::lock_guard<std::mutex> lock(g_queueMutex);
    g_messageQueue.push(payload);  // 只放入队列，不阻塞
}

// 在主线程中处理队列
while (g_running) {
    std::string payload;
    {
        std::lock_guard<std::mutex> lock(g_queueMutex);
        if (!g_messageQueue.empty()) {
            payload = g_messageQueue.front();
            g_messageQueue.pop();
        }
    }
    
    if (!payload.empty()) {
        // 在主线程中发布到 IoT Core
        publishToIoTCore(payload);
    }
    
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
}
```

### 2. AccessControl 配置

需要两个权限：
- `aws.greengrass.ipc.pubsub` - 订阅 IPC topic
- `aws.greengrass.ipc.mqttproxy` - 发布到 IoT Core

```yaml
ComponentConfiguration:
  DefaultConfiguration:
    ipcTopic: "iec104/data"
    iotTopic: "wind-farm/data"
    accessControl:
      aws.greengrass.ipc.pubsub:
        "com.example.IoTPublisher:pubsub:1":
          policyDescription: "Allow subscribing to iec104/data topic"
          operations:
            - "aws.greengrass#SubscribeToTopic"
          resources:
            - "iec104/data"
      aws.greengrass.ipc.mqttproxy:
        "com.example.IoTPublisher:mqttproxy:1":
          policyDescription: "Allow publishing to IoT Core"
          operations:
            - "aws.greengrass#PublishToIoTCore"
          resources:
            - "wind-farm/data"
```

### 3. 正确的 IPC 初始化

```cpp
// 1. 使用 g_allocator
ApiHandle apiHandle(g_allocator);

// 2. 创建 EventLoopGroup 和 ClientBootstrap
Io::EventLoopGroup eventLoopGroup(1);
Io::DefaultHostResolver socketResolver(eventLoopGroup, 64, 30);
Io::ClientBootstrap bootstrap(eventLoopGroup, socketResolver);

// 3. 连接并检查状态
GreengrassCoreIpcClient ipcClient(bootstrap);
auto connectionStatus = ipcClient.Connect(lifecycleHandler).get();
if (!connectionStatus) {
    std::cerr << "Failed to connect" << std::endl;
    return 1;
}
```

## 🚀 快速开始

### 前置条件

- Lab 3 (IEC104 Simulator) 已部署
- Lab 4 (IEC104 Collector) 已部署
- AWS IoT Core 已配置

### 构建

```bash
cd /home/participant/workshop/lab5-iot-integration

# 安装依赖（如果还没有）
git submodule update --init --recursive

# 构建
./build.sh
```

### 打包

```bash
# 设置环境变量
export COMPONENT_BUCKET=your-s3-bucket
export AWS_REGION=ap-northeast-1

# 打包
./package.sh
```

### 部署

```bash
# 部署所有组件（Simulator + Collector + Publisher）
./deploy.sh
```

## 📝 配置说明

### recipe.yaml

```yaml
ComponentName: "com.example.IoTPublisher"
ComponentVersion: "1.0.4"

ComponentConfiguration:
  DefaultConfiguration:
    ipcTopic: "iec104/data"      # 订阅的 IPC topic
    iotTopic: "wind-farm/data"   # 发布到 IoT Core 的 topic
    accessControl:
      # ... 权限配置
```

### 部署配置

在 `deploy.sh` 中，必须在 `configurationUpdate.merge` 中包含 `accessControl`：

```json
{
  "ipcTopic": "iec104/data",
  "iotTopic": "wind-farm/data",
  "accessControl": {
    "aws.greengrass.ipc.pubsub": { ... },
    "aws.greengrass.ipc.mqttproxy": { ... }
  }
}
```

## 🔍 验证

### 1. 检查组件状态

```bash
sudo /greengrass/v2/bin/greengrass-cli component list | grep IoTPublisher
```

预期输出：
```
Component Name: com.example.IoTPublisher
    Version: 1.0.4
    State: RUNNING
```

### 2. 查看日志

```bash
sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log
```

预期日志：
```
[INFO] IoT Publisher starting...
[INFO] IPC Connected
[INFO] Subscribed to IPC topic: iec104/data
[INFO] Will publish to IoT Core topic: wind-farm/data
[INFO] Received IPC message
[INFO] Publishing to IoT Core...
[INFO] Published to IoT Core: wind-farm/data
```

### 3. 测试 IoT Core 发布

使用 Greengrass CLI 测试：
```bash
sudo /greengrass/v2/bin/greengrass-cli iotcore pub \
  --topic wind-farm/data \
  --message '{"test":"message"}'
```

### 4. 监控 IoT Core 消息

在 AWS Console 中：
1. 进入 AWS IoT Core
2. 点击 "Test" -> "MQTT test client"
3. 订阅 topic: `wind-farm/data`
4. 查看接收到的消息

## 📊 数据流示例

**接收到的 IPC 消息**：
```json
[
  {
    "address": 1001,
    "name": "wind_turbine_1_active_power",
    "value": 1500.0,
    "unit": "kW",
    "timestamp": 1769090540
  },
  {
    "address": 2001,
    "name": "energy_storage_soc",
    "value": 75.0,
    "unit": "%",
    "timestamp": 1769090540
  }
]
```

**发布到 IoT Core 的消息**：相同的 JSON 数据

## 🐛 故障排除

### 问题 1: IPC 订阅失败

**症状**：
```
[ERROR] Subscribe failed
```

**解决**：
1. 检查 accessControl 配置是否包含 `aws.greengrass.ipc.pubsub`
2. 确认 topic 名称正确：`iec104/data`
3. 检查 Lab 4 是否正在发布数据

### 问题 2: IoT Core 发布超时

**症状**：
```
[ERROR] Publish timeout
```

**解决**：
1. 检查 accessControl 配置是否包含 `aws.greengrass.ipc.mqttproxy`
2. 确认 Greengrass 设备有网络连接
3. 检查 IoT Core 策略是否允许发布

### 问题 3: 回调阻塞

**症状**：程序卡住，没有日志输出

**原因**：在 `OnStreamEvent` 回调中执行了阻塞操作

**解决**：使用消息队列，在主线程中处理（参考本 Lab 的实现）

## 📚 参考资料

- [AWS IoT Greengrass IPC 文档](https://docs.aws.amazon.com/greengrass/v2/developerguide/interprocess-communication.html)
- [PublishToIoTCore API](https://docs.aws.amazon.com/greengrass/v2/developerguide/ipc-iot-core-mqtt.html#ipc-operation-publishtoiotcore)
- [SubscribeToTopic API](https://docs.aws.amazon.com/greengrass/v2/developerguide/ipc-publish-subscribe.html#ipc-operation-subscribetotopic)

## 🎓 学到的经验

1. **不要在回调中执行阻塞操作** - 使用队列和主线程处理
2. **accessControl 必须在部署时包含** - 不能只在 recipe 中定义
3. **ApiHandle 需要 g_allocator** - 否则 IPC 连接失败
4. **检查 Activate 返回值** - 及早发现错误

## ✅ 完成标志

- [ ] 组件成功部署并运行
- [ ] 日志显示 "Published to IoT Core"
- [ ] AWS IoT Core MQTT 测试客户端收到消息
- [ ] 数据格式正确，包含所有字段

---

**下一步**：可以添加 IoT Core Rules Engine 将数据路由到其他 AWS 服务（S3、DynamoDB、Lambda 等）
