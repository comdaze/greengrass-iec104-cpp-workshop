# Lab 4: IEC104数据采集与Greengrass IPC发布

## 学习目标

完成本实验后，你将能够：
- ✅ 理解Greengrass IPC（进程间通信）机制
- ✅ 使用IPC Pub/Sub模式发布消息
- ✅ 配置Recipe中的IPC权限
- ✅ 实现工业数据采集并实时发布
- ✅ 调试IPC通信问题

## 前置条件

- ✅ 完成Lab 1、Lab 2、Lab 3
- ✅ Lab 3的IEC104模拟器正在运行
- ✅ 理解C++基础和异步编程
- ✅ 了解Pub/Sub消息模式

## 什么是Greengrass IPC？

### IPC概念

**IPC (Inter-Process Communication)** 是Greengrass组件之间通信的核心机制。

```
┌─────────────────────────────────────────────────────┐
│         Greengrass Nucleus (核心服务)                │
│                                                      │
│         ┌─────────────────────┐                     │
│         │   IPC Router        │                     │
│         │   - 消息路由        │                     │
│         │   - 权限验证        │                     │
│         │   - Topic管理       │                     │
│         └──────┬──────▲───────┘                     │
│                │      │                              │
└────────────────┼──────┼──────────────────────────────┘
                 │      │
        Publish  │      │  Subscribe
                 │      │
    ┌────────────▼──────┴────────────┐
    │  Component A    Component B    │
    │  (Publisher)    (Subscriber)   │
    └────────────────────────────────┘
```

### 为什么使用IPC？

| 特性 | 文件共享 | IPC |
|------|----------|-----|
| 实时性 | ❌ 需要轮询 | ✅ 事件驱动 |
| 性能 | ❌ 磁盘I/O | ✅ 内存传递 |
| 解耦 | ❌ 文件路径依赖 | ✅ Topic订阅 |
| 扩展性 | ❌ 1对1 | ✅ 1对多 |
| 可靠性 | ❌ 文件锁问题 | ✅ 消息队列 |

### IPC支持的操作

Greengrass IPC提供多种操作：

| 操作类型 | 说明 | 使用场景 |
|---------|------|----------|
| **Pub/Sub** | 发布/订阅消息 | 组件间数据传递 |
| **MQTT Proxy** | 发布到IoT Core | 云端集成 |
| **Configuration** | 读取配置 | 动态配置管理 |
| **Secret Manager** | 读取密钥 | 安全凭证管理 |
| **Component Lifecycle** | 管理组件 | 组件控制 |

**本Lab重点**：Pub/Sub - PublishToTopic

---

## 架构概览

```
┌─────────────────────────────────────────────────────────┐
│  Lab 3: IEC104 Simulator (Docker)                       │
│  - TCP Server on port 2404                              │
│  - 模拟6个数据点                                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ TCP/IEC104协议
                 │
┌────────────────▼────────────────────────────────────────┐
│  Lab 4: IEC104 Collector (本Lab)                        │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  1. 连接IEC104模拟器                           │    │
│  │  2. 采集数据 (TCP Socket)                      │    │
│  │  3. 解析数据 (简化的IEC104)                    │    │
│  │  4. 序列化为JSON                               │    │
│  │  5. 通过IPC发布 ← 学习重点                     │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
│  IPC Topic: "iec104/data"                               │
│  Message: JSON array of data points                     │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ Greengrass IPC Pub/Sub
                 │
┌────────────────▼────────────────────────────────────────┐
│  Lab 5: IoT Publisher (订阅者)                          │
│  - 订阅IPC topic                                        │
│  - 转发到IoT Core                                       │
└─────────────────────────────────────────────────────────┘
```

---

# Part 1: 理解IPC发布代码

## 步骤 1: 查看完整代码结构

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab4-iec104-collector
cat src/collector.cpp | head -50
```

### 1.1 关键头文件

```cpp
#include <aws/crt/Api.h>                          // AWS CRT基础
#include <aws/greengrass/GreengrassCoreIpcClient.h> // IPC客户端

using namespace Aws::Crt;
using namespace Aws::Greengrass;
```

**说明**：
- `aws/crt/Api.h`: AWS Common Runtime，提供基础设施
- `GreengrassCoreIpcClient.h`: IPC客户端接口

### 1.2 配置结构

```cpp
struct Config {
    std::string server_host = "localhost";
    int server_port = 2404;
    int reconnect_interval = 5000;
    std::string ipc_topic = "iec104/data";  // IPC主题
};
```

**新增字段**：
- `ipc_topic`: IPC发布的主题名称

## 步骤 2: IPC客户端初始化

### 2.1 初始化AWS CRT

```cpp
// 初始化AWS CRT
ApiHandle apiHandle;
Io::EventLoopGroup eventLoopGroup(1);
Io::DefaultHostResolver defaultHostResolver(eventLoopGroup, 1, 5);
Io::ClientBootstrap clientBootstrap(eventLoopGroup, defaultHostResolver);
```

**逐行解析**：

1. **ApiHandle**: 
   - AWS CRT的全局初始化
   - 管理内存分配器、日志系统
   - 必须在使用任何CRT功能前创建

2. **EventLoopGroup**:
   - 事件循环组，处理异步I/O
   - 参数`1`表示使用1个线程
   - 类似于Node.js的事件循环

3. **DefaultHostResolver**:
   - DNS解析器
   - 参数：事件循环组、最大主机数、TTL

4. **ClientBootstrap**:
   - 客户端引导程序
   - 管理连接和I/O操作

### 2.2 创建IPC客户端

```cpp
// 创建IPC客户端
GreengrassCoreIpcClient ipcClient(clientBootstrap);

// 连接到Greengrass IPC服务
auto connectionStatus = ipcClient.Connect().get();
if (!connectionStatus) {
    std::cerr << "[ERROR] Failed to connect to Greengrass IPC" << std::endl;
    return 1;
}
std::cout << "[INFO] Connected to Greengrass IPC" << std::endl;
```

**关键点**：
- `Connect()`: 返回Future对象
- `.get()`: 阻塞等待连接完成
- 连接到Unix Domain Socket: `/greengrass/v2/ipc.socket`

## 步骤 3: IPC发布函数详解

### 3.1 完整的发布函数

```cpp
bool publishToIPC(GreengrassCoreIpcClient& ipcClient, 
                  const std::string& topic, 
                  const json& data) {
    try {
        // 1. 创建发布请求
        PublishToTopicRequest request;
        request.SetTopic(topic.c_str());
        
        // 2. 序列化JSON为字节数组
        std::string payload = data.dump();
        Vector<uint8_t> payloadBytes(payload.begin(), payload.end());
        request.SetPublishMessage(payloadBytes);
        
        // 3. 创建发布操作
        auto operation = ipcClient.NewPublishToTopic();
        
        // 4. 激活操作
        auto activate = operation->Activate(request);
        activate.wait();
        
        // 5. 获取结果
        auto responseFuture = operation->GetResult();
        if (responseFuture.wait_for(std::chrono::seconds(5)) == 
            std::future_status::timeout) {
            std::cerr << "[ERROR] IPC publish timeout" << std::endl;
            return false;
        }
        
        auto response = responseFuture.get();
        if (!response) {
            std::cerr << "[ERROR] IPC publish failed" << std::endl;
            return false;
        }
        
        std::cout << "[INFO] Published to IPC topic: " << topic << std::endl;
        return true;
        
    } catch (const std::exception& e) {
        std::cerr << "[ERROR] IPC publish exception: " << e.what() << std::endl;
        return false;
    }
}
```

### 3.2 逐步解析

**步骤1: 创建请求对象**
```cpp
PublishToTopicRequest request;
request.SetTopic(topic.c_str());
```
- 指定要发布到的主题名称
- 主题名称必须与Recipe中的权限配置匹配

**步骤2: 消息序列化**
```cpp
std::string payload = data.dump();  // JSON → String
Vector<uint8_t> payloadBytes(payload.begin(), payload.end());  // String → Bytes
request.SetPublishMessage(payloadBytes);
```
- IPC消息必须是字节数组
- JSON对象先转为字符串，再转为字节

**步骤3-4: 创建并激活操作**
```cpp
auto operation = ipcClient.NewPublishToTopic();
auto activate = operation->Activate(request);
activate.wait();
```
- `NewPublishToTopic()`: 创建发布操作
- `Activate()`: 激活操作，返回Future
- `wait()`: 等待激活完成

**步骤5: 获取结果**
```cpp
auto responseFuture = operation->GetResult();
responseFuture.wait_for(std::chrono::seconds(5));  // 超时控制
auto response = responseFuture.get();
```
- 异步操作，使用Future模式
- 设置5秒超时，避免无限等待
- 检查响应状态

### 3.3 错误处理

```cpp
if (!response) {
    std::cerr << "[ERROR] IPC publish failed: " 
              << response.GetResultType() << std::endl;
    return false;
}
```

**常见错误**：
- `UNAUTHORIZED`: 权限不足（Recipe配置问题）
- `INVALID_ARGUMENT`: 参数错误（Topic名称等）
- `SERVICE_ERROR`: IPC服务错误

## 步骤 4: 主循环集成

```cpp
while (g_running) {
    // 1. 连接IEC104服务器
    if (sock < 0) {
        connectToServer(config.server_host, config.server_port, sock);
    }
    
    // 2. 采集数据
    json data = collectData(sock);
    
    if (!data.empty()) {
        // 3. 发布到IPC
        if (!publishToIPC(ipcClient, config.ipc_topic, data)) {
            std::cerr << "[ERROR] Failed to publish to IPC" << std::endl;
        }
        
        // 4. 备份到文件（可选）
        std::ofstream file("/tmp/iec104-data.json");
        file << data.dump(2);
        file.close();
    }
    
    std::this_thread::sleep_for(std::chrono::seconds(5));
}
```

**数据流**：
1. 从IEC104模拟器采集数据
2. 解析为JSON格式
3. 通过IPC发布（主要路径）
4. 同时保存到文件（备份）

---

# Part 2: Recipe配置详解

## 步骤 5: 理解IPC权限配置

### 5.1 查看Recipe

```bash
cat recipe.yaml
```

### 5.2 IPC权限配置结构

```yaml
ComponentConfiguration:
  accessControl:
    aws.greengrass.ipc.pubsub:
      "com.example.IEC104Collector:pubsub:1":
        policyDescription: "Allow publishing to iec104/data topic"
        operations:
          - "aws.greengrass#PublishToTopic"
        resources:
          - "iec104/data"
```

### 5.3 配置字段详解

| 字段 | 说明 | 示例 |
|------|------|------|
| `aws.greengrass.ipc.pubsub` | IPC服务类型 | Pub/Sub消息服务 |
| `com.example.IEC104Collector:pubsub:1` | 策略ID | 组件名:类型:序号 |
| `policyDescription` | 策略描述 | 便于理解和维护 |
| `operations` | 允许的操作 | PublishToTopic |
| `resources` | 允许的资源 | Topic名称 |

### 5.4 权限验证流程

```
组件调用PublishToTopic
    ↓
Greengrass Nucleus验证
    ↓
检查Recipe中的accessControl
    ↓
匹配operations和resources
    ↓
允许/拒绝操作
```

**如果权限不足**：
```
[ERROR] IPC publish failed: UNAUTHORIZED
```

### 5.5 通配符支持

```yaml
resources:
  - "iec104/*"      # 允许iec104/开头的所有topic
  - "*"             # 允许所有topic（不推荐）
```

---

# Part 3: 构建和部署

## 步骤 6: 安装AWS IoT Device SDK

### 6.1 检查SDK是否已安装

```bash
# 检查SDK
ls /usr/local/lib/libaws-* 2>/dev/null || echo "SDK not installed"
```

### 6.2 安装SDK（如果需要）

```bash
# 安装依赖
sudo apt-get update
sudo apt-get install -y cmake g++ git libssl-dev

# 克隆SDK
cd /tmp
git clone --recursive https://github.com/aws/aws-iot-device-sdk-cpp-v2.git
cd aws-iot-device-sdk-cpp-v2

# 构建和安装
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_DEPS=ON
make -j$(nproc)
sudo make install
sudo ldconfig
```

## 步骤 7: 构建Lab 4组件

### 7.1 手动构建

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab4-iec104-collector

# 创建构建目录
mkdir -p build && cd build

# 配置CMake
cmake .. -DCMAKE_BUILD_TYPE=Release

# 编译
make -j$(nproc)

# 验证
ls -lh iec104_collector
ldd iec104_collector | grep aws
```

**预期输出**：
```
libaws-crt-cpp.so => /usr/local/lib/libaws-crt-cpp.so
libGreengrassIpc-cpp.so => /usr/local/lib/libGreengrassIpc-cpp.so
```

### 7.2 使用构建脚本

```bash
./build.sh
```

## 步骤 8: 本地测试（不使用Greengrass）

### 8.1 准备测试环境

```bash
# 确保Lab 3模拟器正在运行
docker ps | grep iec104-simulator

# 如果没有运行，启动它
cd ../lab3-iec104-simulator
./docker-test.sh &
```

### 8.2 创建测试配置

```bash
cat > /tmp/collector-test-config.json << 'EOF'
{
  "serverHost": "localhost",
  "serverPort": 2404,
  "reconnectInterval": 5000,
  "ipcTopic": "iec104/data"
}
EOF
```

### 8.3 本地运行（模拟IPC）

**注意**：本地测试时IPC连接会失败（正常），主要测试数据采集逻辑。

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab4-iec104-collector

# 运行采集器
timeout 15 ./build/iec104_collector /tmp/collector-test-config.json 2>&1 || true

# 查看采集的数据
cat /tmp/iec104-data.json | jq '.'
```

**预期输出**：
```json
[
  {
    "address": 1001,
    "name": "wind_turbine_1_active_power",
    "value": 1523.45,
    "unit": "kW",
    "timestamp": 1737518400
  },
  {
    "address": 2001,
    "name": "energy_storage_soc",
    "value": 78.5,
    "unit": "%",
    "timestamp": 1737518400
  }
]
```

## 步骤 9: 打包和上传

### 9.1 打包组件

```bash
./package.sh

# 查看打包结果
ls -lh artifacts/
```

### 9.2 上传到S3

```bash
export COMPONENT_BUCKET="iec104-greengrass-components-1737518400"
export AWS_REGION="cn-north-1"

# 上传
aws s3 cp artifacts/com.example.IEC104Collector-1.0.0.zip \
  s3://${COMPONENT_BUCKET}/com.example.IEC104Collector/1.0.0/ \
  --region ${AWS_REGION}
```

### 9.3 更新Recipe并创建组件

```bash
# 更新S3路径
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" \
  artifacts/recipe.json > artifacts/recipe-updated.json

# 创建组件版本
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-updated.json \
  --region ${AWS_REGION}
```

## 步骤 10: 部署到Greengrass

### 10.1 部署Lab 3和Lab 4

```bash
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Collector-IPC-$(date +%s)" \
  --components '{
    "com.example.IEC104SimulatorDocker": {
      "componentVersion": "1.0.0"
    },
    "com.example.IEC104Collector": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"serverHost\":\"localhost\",\"serverPort\":2404,\"ipcTopic\":\"iec104/data\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

### 10.2 验证部署

```bash
# 查看组件状态
sudo /greengrass/v2/bin/greengrass-cli component list

# 查看Collector日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log
```

**预期日志**：
```
[INFO] IEC104 Collector with IPC starting...
[INFO] Configuration loaded
[INFO] Connected to Greengrass IPC
[INFO] Connected to IEC104 server localhost:2404
[INFO] Published 2 data points to IPC topic: iec104/data
```

---

# Part 4: 调试和验证

## 步骤 11: 验证IPC发布

### 11.1 使用Greengrass CLI监控

```bash
# 查看IPC统计
sudo /greengrass/v2/bin/greengrass-cli get-component-details \
  --name com.example.IEC104Collector
```

### 11.2 查看IPC日志

```bash
# Greengrass主日志
sudo tail -f /greengrass/v2/logs/greengrass.log | grep -i ipc

# 组件日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log
```

### 11.3 验证数据发布

由于Lab 5还未部署，我们可以创建一个简单的测试订阅者：

```bash
# 创建测试订阅脚本
cat > /tmp/test-ipc-subscriber.py << 'EOF'
import json
import time
import awsiot.greengrasscoreipc
from awsiot.greengrasscoreipc.model import SubscribeToTopicRequest

ipc_client = awsiot.greengrasscoreipc.connect()

def on_stream_event(event):
    message = str(event.binary_message.message, 'utf-8')
    print(f"[INFO] Received: {message}")
    data = json.loads(message)
    print(f"[INFO] Data points: {len(data)}")

request = SubscribeToTopicRequest(topic="iec104/data")
operation = ipc_client.new_subscribe_to_topic()
operation.activate(request)
future = operation.get_response()
future.result(timeout=5)

while True:
    time.sleep(1)
EOF

# 运行测试（需要Python IPC SDK）
# python3 /tmp/test-ipc-subscriber.py
```

## 步骤 12: 常见问题排查

### 问题1: IPC连接失败

**错误**：
```
[ERROR] Failed to connect to Greengrass IPC
```

**排查**：
```bash
# 检查IPC socket
ls -la /greengrass/v2/ipc.socket

# 检查Greengrass服务
sudo systemctl status greengrass

# 查看Greengrass日志
sudo tail -50 /greengrass/v2/logs/greengrass.log
```

### 问题2: 权限被拒绝

**错误**：
```
[ERROR] IPC publish failed: UNAUTHORIZED
```

**排查**：
```bash
# 检查Recipe配置
cat artifacts/recipe-updated.json | jq '.Manifests[0].ComponentConfiguration.accessControl'

# 验证组件版本
aws greengrassv2 describe-component \
  --arn "arn:aws-cn:greengrass:${AWS_REGION}:${ACCOUNT_ID}:components:com.example.IEC104Collector:versions:1.0.0" \
  --region ${AWS_REGION}
```

**解决方法**：
- 确认Recipe中有正确的accessControl配置
- 确认operations包含"aws.greengrass#PublishToTopic"
- 确认resources包含正确的topic名称

### 问题3: 数据未发布

**排查**：
```bash
# 检查IEC104连接
sudo netstat -tlnp | grep 2404

# 检查数据采集
cat /tmp/iec104-data.json

# 查看详细日志
sudo tail -100 /greengrass/v2/logs/com.example.IEC104Collector.log
```

---

## 关键概念总结

### 1. Greengrass IPC

**核心概念**：
- 组件间通信的标准机制
- 基于Unix Domain Socket
- 支持多种操作类型（Pub/Sub、MQTT Proxy等）

**优势**：
- 实时性：事件驱动，无需轮询
- 性能：内存传递，无磁盘I/O
- 解耦：通过Topic订阅，组件独立
- 扩展性：支持1对多通信

### 2. IPC Pub/Sub模式

```
Publisher (Lab 4)
    ↓ PublishToTopic
IPC Router (Greengrass Nucleus)
    ↓ Topic: "iec104/data"
Subscriber (Lab 5)
    ↓ SubscribeToTopic
```

### 3. 权限模型

**Recipe配置**：
```yaml
accessControl:
  aws.greengrass.ipc.pubsub:
    "PolicyID":
      operations: ["aws.greengrass#PublishToTopic"]
      resources: ["iec104/data"]
```

**验证流程**：
1. 组件调用IPC操作
2. Nucleus检查Recipe配置
3. 匹配operations和resources
4. 允许或拒绝

### 4. 异步编程模式

**Future模式**：
```cpp
auto operation = ipcClient.NewPublishToTopic();
auto activate = operation->Activate(request);  // 返回Future
activate.wait();  // 等待完成
auto response = operation->GetResult().get();  // 获取结果
```

## 实验总结

通过本实验，你已经：
- ✅ 理解了Greengrass IPC的工作原理
- ✅ 实现了IPC消息发布功能
- ✅ 配置了Recipe中的IPC权限
- ✅ 掌握了IPC调试方法
- ✅ 完成了工业数据的实时采集和发布

## 下一步

继续 **[Lab 5: IPC订阅与IoT Core集成](../lab5-iot-integration/README-IPC.md)**，学习：
- IPC消息订阅
- 回调函数处理
- IoT Core MQTT集成
- 完整的边缘到云端数据流

## 参考资料

- [Greengrass IPC文档](https://docs.aws.amazon.com/greengrass/v2/developerguide/interprocess-communication.html)
- [IPC Pub/Sub](https://docs.aws.amazon.com/greengrass/v2/developerguide/ipc-publish-subscribe.html)
- [Recipe权限配置](https://docs.aws.amazon.com/greengrass/v2/developerguide/component-recipe-reference.html#component-recipe-access-control)

---

**🎉 恭喜完成Lab 4！你已经掌握了Greengrass IPC发布！**
