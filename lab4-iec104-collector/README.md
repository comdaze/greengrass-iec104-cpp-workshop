# Lab 4: IEC104 数据采集器

## 🎯 目标

实现 IEC104 客户端，连接到模拟器采集数据，并通过 Greengrass IPC pubsub 发布到本地 topic。

**学习要点**：
- IEC104 客户端实现（使用 lib60870-C）
- Greengrass IPC PublishToTopic 操作
- 数据过滤和 JSON 转换
- AccessControl 权限配置

## 📐 架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Greengrass Core Device                                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IEC104 Simulator (Lab 3)                                │  │
│  │  - Docker Container                                      │  │
│  │  - TCP Port 2404                                         │  │
│  │  - lib60870 CS104_Slave                                  │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │ IEC 60870-5-104 Protocol               │
│                       │ TypeID=11 (MeasuredValueScaled)        │
│                       ↓                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IEC104 Collector (Lab 4)                                │  │
│  │  - lib60870 CS104_Connection                             │  │
│  │  - 发送总召唤命令                                         │  │
│  │  - 接收 6 个数据点                                        │  │
│  │  - 过滤目标数据点 (IOA 1001, 2001)                       │  │
│  │  - 转换为 JSON 格式                                       │  │
│  │  - 发布到 IPC topic: iec104/data                         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 🔑 关键技术点

### 1. lib60870 客户端实现

```cpp
// 创建连接
CS104_Connection connection = CS104_Connection_create(host, port);
CS104_Connection_setASDUReceivedHandler(connection, asduReceivedHandler, NULL);

// 连接并启动数据传输
if (CS104_Connection_connect(connection)) {
    CS104_Connection_sendStartDT(connection);
    
    // 发送总召唤命令
    CS104_Connection_sendInterrogationCommand(
        connection, 
        CS101_COT_ACTIVATION, 
        1, 
        IEC60870_QOI_STATION
    );
}

// 处理接收到的数据
bool asduReceivedHandler(void* parameter, int address, CS101_ASDU asdu) {
    if (CS101_ASDU_getTypeID(asdu) == M_ME_NB_1) {  // TypeID=11
        for (int i = 0; i < CS101_ASDU_getNumberOfElements(asdu); i++) {
            MeasuredValueScaled io = (MeasuredValueScaled)CS101_ASDU_getElement(asdu, i);
            int ioa = InformationObject_getObjectAddress((InformationObject)io);
            int value = MeasuredValueScaled_getValue(io);
            // 处理数据...
        }
    }
    return true;
}
```

### 2. IPC PublishToTopic

```cpp
// 正确的初始化
ApiHandle apiHandle(g_allocator);  // 必须传递 g_allocator
Io::EventLoopGroup eventLoopGroup(1);
Io::DefaultHostResolver socketResolver(eventLoopGroup, 64, 30);
Io::ClientBootstrap bootstrap(eventLoopGroup, socketResolver);

GreengrassCoreIpcClient ipcClient(bootstrap);

// 连接
auto connectionStatus = ipcClient.Connect(lifecycleHandler).get();
if (!connectionStatus) {  // 注意：!connectionStatus 表示失败
    std::cerr << "Failed to connect" << std::endl;
    return 1;
}

// 发布消息
PublishToTopicRequest request;
request.SetTopic("iec104/data");

BinaryMessage binaryMessage;
std::string payload = data.dump();  // JSON to string
Vector<uint8_t> payloadBytes(payload.begin(), payload.end());
binaryMessage.SetMessage(payloadBytes);

PublishMessage message;
message.SetBinaryMessage(binaryMessage);
request.SetPublishMessage(message);

auto operation = ipcClient.NewPublishToTopic();
auto activate = operation->Activate(request, nullptr).get();  // 必须传 nullptr
if (!activate) {
    std::cerr << "Activate failed" << std::endl;
    return false;
}

auto responseFuture = operation->GetResult();
auto response = responseFuture.get();
if (response) {
    std::cout << "Published successfully" << std::endl;
}
```

### 3. AccessControl 配置

**Recipe 中的配置**：
```yaml
ComponentConfiguration:
  DefaultConfiguration:
    serverHost: "localhost"
    serverPort: 2404
    ipcTopic: "iec104/data"
    accessControl:
      aws.greengrass.ipc.pubsub:
        "com.example.IEC104Collector:pubsub:1":
          policyDescription: "Allow publishing to iec104/data topic"
          operations:
            - "aws.greengrass#PublishToTopic"
          resources:
            - "iec104/data"
```

**部署时必须包含**：
```bash
aws greengrassv2 create-deployment \
  --components '{
    "com.example.IEC104Collector": {
      "componentVersion": "1.0.16",
      "configurationUpdate": {
        "merge": "{\"accessControl\":{...}}"  # 必须包含！
      }
    }
  }'
```

## 🚀 快速开始

### 前置条件

- Lab 3 (IEC104 Simulator) 已部署并运行
- lib60870-C 库已安装
- AWS IoT Device SDK for C++ v2

### 构建

```bash
cd /home/participant/workshop/lab4-iec104-collector

# 下载 AWS SDK（首次）
git submodule update --init --recursive

# 构建
./build.sh
```

### 本地测试

```bash
# 启动模拟器（如果还没运行）
cd ../lab3-iec104-simulator/build
./iec104_simulator ../config.json &

# 运行采集器
cd ../../lab4-iec104-collector/build
./iec104_collector /tmp/collector-config.json

# 查看输出
cat /tmp/iec104-data.json
```

### 打包和部署

```bash
# 设置环境变量
export COMPONENT_BUCKET=your-s3-bucket
export AWS_REGION=ap-northeast-1

# 打包
./package.sh

# 部署（包含 Simulator 和 Collector）
./deploy.sh
```

## 📝 配置说明

### config.json

```json
{
  "serverHost": "localhost",
  "serverPort": 2404,
  "reconnectInterval": 5000,
  "ipcTopic": "iec104/data"
}
```

### 数据点映射

| IOA | 名称 | 单位 | 说明 |
|-----|------|------|------|
| 1001 | wind_turbine_1_active_power | kW | 风机有功功率 |
| 1002 | wind_turbine_1_reactive_power | kVar | 风机无功功率 |
| 1003 | wind_turbine_1_wind_speed | m/s | 风速 |
| 2001 | energy_storage_soc | % | 储能 SOC |
| 2002 | energy_storage_power | kW | 储能功率 |
| 3001 | grid_frequency | Hz | 电网频率 |

**过滤后的目标数据点**：IOA 1001, 2001

## 📊 数据格式

### IEC104 原始数据

```
TypeID: 11 (M_ME_NB_1 - MeasuredValueScaled)
IOA: 1001, Value: 1500
IOA: 2001, Value: 75
```

### JSON 输出

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

## 🔍 验证

### 1. 检查组件状态

```bash
sudo /greengrass/v2/bin/greengrass-cli component list | grep IEC104Collector
```

预期输出：
```
Component Name: com.example.IEC104Collector
    Version: 1.0.16
    State: RUNNING
```

### 2. 查看日志

```bash
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log
```

预期日志：
```
[INFO] IEC104 Collector (lib60870) starting...
[INFO] Connected to Greengrass IPC
[INFO] Connected to IEC104 server localhost:2404
[INFO] Sending interrogation command...
[DEBUG] IOA=1001, value=1500
[DEBUG] IOA=2001, value=75
[INFO] Published 2 data points to IPC topic: iec104/data
[INFO] Saved 2 data points
```

### 3. 查看采集的数据

```bash
cat /tmp/iec104-data.json | jq
```

### 4. 测试 IPC 订阅

```bash
# 使用 Greengrass CLI 订阅
sudo /greengrass/v2/bin/greengrass-cli pubsub sub --topic iec104/data
```

## 🐛 故障排除

### 问题 1: IPC 发布超时

**症状**：
```
[ERROR] IPC publish timeout
```

**原因**：
1. ApiHandle 未使用 g_allocator
2. accessControl 配置未生效
3. 连接状态检查错误

**解决**：
```cpp
// 1. 正确初始化
ApiHandle apiHandle(g_allocator);  // 不是 ApiHandle apiHandle;

// 2. 正确检查连接
auto status = ipcClient.Connect(handler).get();
if (!status) {  // 不是 if (status)
    // 失败处理
}

// 3. Activate 传递 nullptr
auto activate = operation->Activate(request, nullptr).get();
```

### 问题 2: 无法连接到模拟器

**症状**：
```
[ERROR] Failed to connect
```

**检查**：
```bash
# 检查模拟器是否运行
sudo /greengrass/v2/bin/greengrass-cli component list | grep Simulator

# 检查端口
netstat -an | grep 2404

# 查看模拟器日志
sudo docker logs $(sudo docker ps -q --filter ancestor=*iec104-simulator*)
```

### 问题 3: 收不到数据

**症状**：日志显示连接成功，但没有数据

**检查**：
```cpp
// 确保发送了 StartDT
CS104_Connection_sendStartDT(connection);

// 确保发送了总召唤
CS104_Connection_sendInterrogationCommand(
    connection, 
    CS101_COT_ACTIVATION, 
    1, 
    IEC60870_QOI_STATION
);

// 检查 ASDU handler 是否正确注册
CS104_Connection_setASDUReceivedHandler(connection, handler, NULL);
```

## 📚 参考资料

- [lib60870 文档](https://github.com/mz-automation/lib60870)
- [IEC 60870-5-104 标准](https://en.wikipedia.org/wiki/IEC_60870-5)
- [Greengrass IPC 文档](https://docs.aws.amazon.com/greengrass/v2/developerguide/ipc-publish-subscribe.html)

## 🎓 关键经验

1. **ApiHandle 必须使用 g_allocator** - 否则 IPC 连接失败
2. **连接状态检查是反的** - `!connectionStatus` 表示失败
3. **accessControl 必须在部署时包含** - 不能只在 recipe 中定义
4. **Activate 需要 nullptr 参数** - `Activate(request, nullptr)`
5. **发送 StartDT 启动数据传输** - 连接后必须调用

## ✅ 完成标志

- [ ] 组件成功部署并运行
- [ ] 日志显示 "Published to IPC topic"
- [ ] `/tmp/iec104-data.json` 包含正确的数据
- [ ] 可以使用 CLI 订阅到 IPC 消息

---

**下一步**：进入 [Lab 5](../lab5-iot-integration/) 将数据发布到 AWS IoT Core
