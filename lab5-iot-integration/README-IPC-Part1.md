# Lab 5: IPC订阅与AWS IoT Core集成

## 学习目标

完成本实验后，你将能够：
- ✅ 使用IPC订阅消息（SubscribeToTopic）
- ✅ 处理IPC回调函数和流式数据
- ✅ 连接到AWS IoT Core MQTT Broker
- ✅ 发布消息到IoT Core
- ✅ 实现完整的边缘到云端数据流
- ✅ 配置双重IPC权限（订阅+IoT发布）

## 前置条件

- ✅ 完成Lab 1-4
- ✅ Lab 4的IEC104 Collector正在运行并发布IPC消息
- ✅ 理解异步编程和回调函数
- ✅ 了解MQTT协议基础

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS IoT Core                              │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  MQTT Broker                                       │    │
│  │  Topic: wind-farm/data                             │    │
│  │  QoS: AT_LEAST_ONCE                                │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────▲────────────────────────────────────┘
                         │
                         │ MQTT Publish
                         │ (学习重点2)
                         │
┌────────────────────────┴────────────────────────────────────┐
│         Greengrass Core Device                               │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Lab 5: IoT Publisher (本Lab)                      │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────┐     │    │
│  │  │  Part 1: IPC订阅 (学习重点1)             │     │    │
│  │  │  - SubscribeToTopic                      │     │    │
│  │  │  - 回调函数处理                          │     │    │
│  │  │  - 消息反序列化                          │     │    │
│  │  └──────────────────────────────────────────┘     │    │
│  │                     ↓                               │    │
│  │  ┌──────────────────────────────────────────┐     │    │
│  │  │  Part 2: IoT Core集成 (学习重点2)        │     │    │
│  │  │  - MQTT Client初始化                     │     │    │
│  │  │  - 连接IoT Core                          │     │    │
│  │  │  - 发布MQTT消息                          │     │    │
│  │  └──────────────────────────────────────────┘     │    │
│  └────────────────────────────────────────────────────┘    │
│                     ▲                                        │
│                     │ Greengrass IPC                        │
│                     │ Topic: iec104/data                    │
│  ┌──────────────────┴─────────────────────────────────┐    │
│  │  Lab 4: IEC104 Collector                           │    │
│  │  - 发布IPC消息                                     │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

# Part 1: IPC订阅

## 步骤 1: 理解IPC订阅机制

### 1.1 订阅 vs 发布

| 特性 | 发布 (Lab 4) | 订阅 (Lab 5) |
|------|-------------|-------------|
| 操作 | PublishToTopic | SubscribeToTopic |
| 模式 | 主动推送 | 被动接收 |
| 数据流 | 单向 | 流式（持续接收） |
| 回调 | 无 | 需要回调函数 |
| 生命周期 | 一次性 | 持续监听 |

### 1.2 订阅流程

```
1. 创建SubscribeToTopic请求
   ↓
2. 定义回调函数（处理接收的消息）
   ↓
3. 激活订阅操作
   ↓
4. 等待订阅建立
   ↓
5. 持续接收消息（通过回调）
   ↓
6. 保持订阅活跃（阻塞主线程）
```

## 步骤 2: 查看订阅代码

### 2.1 IPCSubscriber类结构

```cpp
class IPCSubscriber {
private:
    GreengrassCoreIpcClient& ipcClient_;
    std::string topic_;
    IoTPublisher& iotPublisher_;
    
public:
    IPCSubscriber(GreengrassCoreIpcClient& client, 
                  const std::string& topic, 
                  IoTPublisher& publisher);
    
    void subscribe();  // 订阅并保持活跃
};
```

### 2.2 订阅函数详解

```cpp
void subscribe() {
    // 1. 创建订阅请求
    SubscribeToTopicRequest request;
    request.SetTopic(topic_.c_str());
    
    // 2. 定义消息处理回调
    auto streamHandler = [this](SubscriptionResponseMessage* message) {
        try {
            // 2.1 获取二进制消息
            auto payload = message->GetBinaryMessage()->GetMessage();
            
            // 2.2 转换为字符串
            std::string payloadStr(payload.begin(), payload.end());
            std::cout << "[INFO] Received IPC message: " << payloadStr << std::endl;
            
            // 2.3 解析JSON
            json data = json::parse(payloadStr);
            
            // 2.4 转发到IoT Core
            iotPublisher_.publish(data);
            
        } catch (const std::exception& e) {
            std::cerr << "[ERROR] Message processing failed: " 
                      << e.what() << std::endl;
        }
    };
    
    // 3. 定义错误回调
    auto onStreamError = [](RpcError error) {
        std::cerr << "[ERROR] IPC stream error: " 
                  << error.StatusToString() << std::endl;
    };
    
    // 4. 定义关闭回调
    auto onStreamClosed = []() {
        std::cout << "[INFO] IPC stream closed" << std::endl;
    };
    
    // 5. 创建订阅操作
    auto operation = ipcClient_.NewSubscribeToTopic(streamHandler);
    
    // 6. 激活订阅
    auto activate = operation->Activate(request, onStreamError, onStreamClosed);
    activate.wait();
    
    // 7. 获取响应
    auto responseFuture = operation->GetResult();
    if (responseFuture.wait_for(std::chrono::seconds(5)) == 
        std::future_status::timeout) {
        std::cerr << "[ERROR] IPC subscribe timeout" << std::endl;
        return;
    }
    
    auto response = responseFuture.get();
    if (!response) {
        std::cerr << "[ERROR] IPC subscribe failed" << std::endl;
        return;
    }
    
    std::cout << "[INFO] Subscribed to IPC topic: " << topic_ << std::endl;
    
    // 8. 保持订阅活跃
    while (g_running) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}
```

### 2.3 关键点解析

**回调函数（Lambda表达式）**：
```cpp
auto streamHandler = [this](SubscriptionResponseMessage* message) {
    // 每次收到消息时调用
    // [this] 捕获当前对象指针
};
```

**消息反序列化**：
```cpp
// Binary → String → JSON
auto payload = message->GetBinaryMessage()->GetMessage();  // Vector<uint8_t>
std::string payloadStr(payload.begin(), payload.end());    // String
json data = json::parse(payloadStr);                       // JSON
```

**保持订阅活跃**：
```cpp
while (g_running) {
    std::this_thread::sleep_for(std::chrono::seconds(1));
}
```
- 订阅是异步的，需要保持主线程运行
- 否则程序退出，订阅也会关闭

## 步骤 3: 理解回调执行流程

```
主线程                          IPC线程
  │                               │
  ├─ 创建订阅                     │
  ├─ 激活订阅 ──────────────────> │
  ├─ 等待响应 <────────────────── │
  ├─ 订阅成功                     │
  │                               │
  ├─ while(g_running) {           │
  │    sleep(1)                   │
  │  }                            │
  │                               │
  │                               ├─ 收到消息
  │                               ├─ 调用streamHandler
  │                               ├─ 处理消息
  │                               ├─ 发布到IoT Core
  │                               │
  │                               ├─ 收到下一条消息
  │                               ├─ 调用streamHandler
  │                               └─ ...
```

---

# Part 2: AWS IoT Core集成

## 步骤 4: 理解IoT Core连接

### 4.1 IoTPublisher类结构

```cpp
class IoTPublisher {
private:
    std::shared_ptr<MqttClient> mqttClient_;
    std::shared_ptr<MqttConnection> mqttConnection_;
    std::string iotTopic_;
    std::atomic<bool> connected_{false};
    
public:
    IoTPublisher(Io::ClientBootstrap& bootstrap, const Config& config);
    bool publish(const json& data);
    ~IoTPublisher();
};
```

### 4.2 MQTT连接初始化

```cpp
IoTPublisher(Io::ClientBootstrap& bootstrap, const Config& config) 
    : iotTopic_(config.iot_topic) {
    
    // 1. 配置TLS选项
    Io::TlsContextOptions tlsOptions = Io::TlsContextOptions::InitDefaultClient();
    
    // 1.1 设置CA证书
    if (!config.ca_path.empty()) {
        tlsOptions.OverrideDefaultTrustStore(nullptr, config.ca_path.c_str());
    }
    
    // 1.2 设置客户端证书和私钥
    if (!config.cert_path.empty() && !config.key_path.empty()) {
        tlsOptions.InitClientWithMtls(
            config.cert_path.c_str(), 
            config.key_path.c_str()
        );
    }
    
    // 2. 创建TLS上下文
    Io::TlsContext tlsContext(tlsOptions, Io::TlsMode::CLIENT);
    
    // 3. 配置Socket选项
    Io::SocketOptions socketOptions;
    socketOptions.SetConnectTimeoutMs(3000);
    
    // 4. 创建MQTT客户端
    mqttClient_ = std::make_shared<MqttClient>(bootstrap);
    
    // 5. 构建连接选项
    auto connectionOptions = MqttConnectionOptionsBuilder(
        config.endpoint.c_str(),  // IoT Core endpoint
        8883,                     // MQTT over TLS端口
        socketOptions, 
        tlsContext
    ).WithClientId("iec104-publisher").Build();
    
    // 6. 创建连接
    mqttConnection_ = mqttClient_->NewConnection(connectionOptions);
    
    // 7. 连接回调
    auto onConnectionCompleted = [this](MqttConnection&, int errorCode, 
                                        ReturnCode returnCode, bool) {
        if (errorCode == 0) {
            std::cout << "[INFO] Connected to IoT Core" << std::endl;
            connected_ = true;
        } else {
            std::cerr << "[ERROR] Failed to connect to IoT Core: " 
                      << errorCode << std::endl;
        }
    };
    
    // 8. 执行连接
    mqttConnection_->Connect(onConnectionCompleted);
}
```

### 4.3 关键配置说明

**TLS/SSL配置**：
- **CA证书**: 验证IoT Core服务器身份
- **客户端证书**: 设备身份认证
- **私钥**: 加密通信

**证书路径**（Greengrass自动管理）：
```
/greengrass/v2/thingCert.crt  # 客户端证书
/greengrass/v2/privKey.key    # 私钥
/greengrass/v2/rootCA.pem     # CA证书
```

**IoT Endpoint**：
```bash
# 获取IoT Core endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS --region cn-north-1
# 输出: xxx.iot.cn-north-1.amazonaws.com.cn
```

## 步骤 5: MQTT消息发布

### 5.1 发布函数

```cpp
bool publish(const json& data) {
    if (!connected_) {
        std::cerr << "[ERROR] Not connected to IoT Core" << std::endl;
        return false;
    }
    
    try {
        // 1. 序列化JSON为字符串
        std::string payload = data.dump();
        
        // 2. 转换为ByteBuf
        ByteBuf payloadBuf = ByteBufFromArray(
            (const uint8_t*)payload.data(), 
            payload.length()
        );
        
        // 3. 发布回调
        auto onPublishComplete = [](MqttConnection&, uint16_t packetId, 
                                     int errorCode) {
            if (errorCode == 0) {
                std::cout << "[INFO] Published to IoT Core, packet ID: " 
                          << packetId << std::endl;
            } else {
                std::cerr << "[ERROR] Publish failed: " 
                          << errorCode << std::endl;
            }
        };
        
        // 4. 发布消息
        mqttConnection_->Publish(
            iotTopic_.c_str(),              // Topic
            AWS_MQTT_QOS_AT_LEAST_ONCE,     // QoS 1
            false,                          // Retain
            payloadBuf,                     // Payload
            onPublishComplete               // Callback
        );
        
        return true;
        
    } catch (const std::exception& e) {
        std::cerr << "[ERROR] Publish exception: " << e.what() << std::endl;
        return false;
    }
}
```

### 5.2 MQTT QoS级别

| QoS | 说明 | 保证 | 性能 |
|-----|------|------|------|
| 0 | At most once | 最多一次，可能丢失 | 最快 |
| 1 | At least once | 至少一次，可能重复 | 中等 |
| 2 | Exactly once | 恰好一次 | 最慢 |

**本Lab使用QoS 1**：平衡可靠性和性能

---

# Part 3: Recipe双重权限配置

## 步骤 6: 理解双重权限

Lab 5需要两种IPC权限：

### 6.1 IPC订阅权限

```yaml
accessControl:
  aws.greengrass.ipc.pubsub:
    "com.example.IoTPublisher:pubsub:1":
      policyDescription: "Allow subscribing to iec104/data topic"
      operations:
        - "aws.greengrass#SubscribeToTopic"
      resources:
        - "iec104/data"
```

**说明**：
- 允许订阅`iec104/data` topic
- 接收Lab 4发布的消息

### 6.2 IoT Core发布权限

```yaml
  aws.greengrass.ipc.mqttproxy:
    "com.example.IoTPublisher:mqttproxy:1":
      policyDescription: "Allow publishing to IoT Core"
      operations:
        - "aws.greengrass#PublishToIoTCore"
      resources:
        - "wind-farm/data"
```

**说明**：
- 允许通过IPC发布到IoT Core
- Topic: `wind-farm/data`

### 6.3 完整Recipe示例

```yaml
ComponentConfiguration:
  accessControl:
    # IPC订阅权限
    aws.greengrass.ipc.pubsub:
      "com.example.IoTPublisher:pubsub:1":
        operations:
          - "aws.greengrass#SubscribeToTopic"
        resources:
          - "iec104/data"
    
    # IoT Core发布权限
    aws.greengrass.ipc.mqttproxy:
      "com.example.IoTPublisher:mqttproxy:1":
        operations:
          - "aws.greengrass#PublishToIoTCore"
        resources:
          - "wind-farm/data"
```

---

继续创建文档的后半部分...
