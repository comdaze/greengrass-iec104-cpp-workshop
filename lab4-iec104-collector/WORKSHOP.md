# Lab 4 Workshop 向导: IEC104 数据采集器

## 🎯 实验目标

通过本实验,你将学习:
- 实现 IEC104 客户端连接到模拟器
- 使用 lib60870-C 库采集工业数据
- 通过 Greengrass IPC PublishToTopic 发布数据
- 配置 AccessControl 权限
- 数据过滤和 JSON 转换
- 组件间通信机制

**预计时间**: 90 分钟  
**难度级别**: ⭐⭐⭐ 高级

## 📋 前置条件

### 必需环境
- ✅ 完成 Lab 1, Lab 2, Lab 3
- ✅ Lab 3 的 IEC104 Simulator 已部署并运行
- ✅ 理解 C++ 编程和异步编程
- ✅ 了解 IEC104 协议基础

### 验证环境

```bash
# 检查 IEC104 Simulator 是否运行
docker ps | grep iec104-simulator

# 测试端口连接
nc -zv localhost 2404

# 检查 Greengrass 状态
sudo systemctl status greengrass
```

## 🏗️ 架构概览

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Greengrass Core Device                                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IEC104 Simulator (Lab 3)                                │  │
│  │  - Docker Container                                      │  │
│  │  - TCP Port 2404                                         │  │
│  │  - lib60870 CS104_Slave                                  │  │
│  │  - 模拟 6 个数据点                                        │  │
│  └────────────────────┬─────────────────────────────────────┘  │
│                       │                                         │
│                       │ IEC 60870-5-104 Protocol               │
│                       │ TCP/IP Connection                       │
│                       │ TypeID=11 (MeasuredValueScaled)        │
│                       │                                         │
│                       ↓                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  IEC104 Collector (Lab 4)                                │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────┐    │  │
│  │  │  IEC104 Client (lib60870)                       │    │  │
│  │  │  - CS104_Connection                             │    │  │
│  │  │  - 发送总召唤命令                                │    │  │
│  │  │  - 接收 ASDU 数据                               │    │  │
│  │  └──────────────────┬──────────────────────────────┘    │  │
│  │                     │                                     │  │
│  │  ┌──────────────────▼──────────────────────────────┐    │  │
│  │  │  数据处理                                        │    │  │
│  │  │  - 过滤目标数据点 (IOA 1001, 2001)             │    │  │
│  │  │  - 转换为 JSON 格式                             │    │  │
│  │  │  - 添加时间戳和元数据                           │    │  │
│  │  └──────────────────┬──────────────────────────────┘    │  │
│  │                     │                                     │  │
│  │  ┌──────────────────▼──────────────────────────────┐    │  │
│  │  │  IPC Publisher                                   │    │  │
│  │  │  - PublishToTopic                                │    │  │
│  │  │  - Topic: iec104/data                            │    │  │
│  │  │  - AccessControl 权限                            │    │  │
│  │  └──────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                       │                                         │
│                       │ Greengrass IPC Pubsub                  │
│                       │ Topic: iec104/data                     │
│                       │                                         │
│                       ↓                                         │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  其他订阅组件 (Lab 5)                                     │  │
│  │  - 订阅 iec104/data topic                                │  │
│  │  - 处理数据并发送到云端                                  │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 核心概念

#### 1. IEC104 客户端通信流程

```
客户端                          服务器
  │                              │
  ├──── TCP Connect ────────────>│
  │<──── TCP Accept ─────────────┤
  │                              │
  ├──── STARTDT (启动数据传输) ──>│
  │<──── STARTDT ACK ────────────┤
  │                              │
  ├──── Interrogation (总召唤) ──>│
  │<──── ASDU (数据点 1) ────────┤
  │<──── ASDU (数据点 2) ────────┤
  │<──── ASDU (数据点 3) ────────┤
  │<──── ... ────────────────────┤
  │<──── Interrogation ACK ──────┤
  │                              │
  ├──── TESTFR (测试帧) ─────────>│
  │<──── TESTFR ACK ─────────────┤
  │                              │
```

**关键步骤**:
1. **TCP 连接**: 建立到服务器的 TCP 连接
2. **STARTDT**: 启动数据传输
3. **总召唤**: 请求所有数据点的当前值
4. **接收 ASDU**: 处理接收到的数据
5. **心跳**: 定期发送测试帧保持连接

#### 2. ASDU (Application Service Data Unit)

**ASDU 结构**:
```
ASDU
├── TypeID: 数据类型 (11 = MeasuredValueScaled)
├── COT: 传输原因 (Cause of Transmission)
├── CA: 公共地址 (Common Address)
└── Information Objects
    ├── IOA: 信息对象地址 (1001, 1002, ...)
    ├── Value: 数据值
    └── Quality: 质量描述符
```

**本 Lab 使用的数据类型**:
- **TypeID 11** (M_ME_NB_1): MeasuredValueScaled - 标度化测量值
- 适用于模拟量数据 (功率、电压、频率等)

#### 3. Greengrass IPC Pubsub

**IPC Pubsub 机制**:
```
发布者组件                      订阅者组件
     │                              │
     ├── PublishToTopic ────────────>│
     │   Topic: iec104/data          │
     │   Payload: JSON               │
     │                              │
     │                         SubscriptionStreamHandler
     │                              │
     │                         OnStreamEvent(message)
```

**优势**:
- ✅ 组件间解耦
- ✅ 本地通信,低延迟
- ✅ 无需网络连接
- ✅ 支持多个订阅者

#### 4. AccessControl 权限模型

```
组件: com.example.IEC104Collector
  ↓
AccessControl 策略
  ├── 操作: aws.greengrass#PublishToTopic
  └── 资源: iec104/data
       ↓
允许发布到 iec104/data topic
```

**权限配置位置**:
1. Recipe 的 `ComponentConfiguration.DefaultConfiguration.accessControl`
2. 部署时的 `configurationUpdate.merge`

## 📁 项目结构

```
lab4-iec104-collector/
├── src/
│   └── collector.cpp           # IEC104 采集器源代码
├── aws-iot-device-sdk-cpp-v2/  # AWS IoT SDK (submodule)
├── CMakeLists.txt              # CMake 构建配置
├── recipe.yaml                 # Greengrass 组件配置
├── config.json                 # 示例配置文件
├── build.sh                    # 构建脚本
├── package.sh                  # 打包脚本
└── deploy.sh                   # 部署脚本
```

## 实验分为三个部分

### Part 1: 本地开发和测试 (步骤 1-4)
- 理解 IEC104 客户端实现
- 理解 IPC PublishToTopic
- 本地构建和测试

### Part 2: 打包和部署 (步骤 5-7)
- 打包组件
- 配置 AccessControl
- 部署到 Greengrass

### Part 3: 验证和调试 (步骤 8-9)
- 验证数据采集
- 查看 IPC 消息
- 故障排查


---

# Part 1: 本地开发和测试

## 🔧 实验步骤

### 步骤 1: 准备实验环境

#### 1.1 进入实验目录

```bash
/home/ubuntu/greengrass-iec104-cpp-workshop/lab4-iec104-collector
```

#### 1.2 下载并编译 AWS IoT SDK

AWS IoT Device SDK for C++ v2 需要先编译安装,才能在 build.sh 中使用。

**步骤 1: 下载 SDK**

```bash
# 下载 AWS IoT C++ SDK (如果还没有)
git clone --recursive https://github.com/aws/aws-iot-device-sdk-cpp-v2.git

# 验证 SDK 已下载
ls -la aws-iot-device-sdk-cpp-v2/
```

**步骤 2: 编译并安装 SDK**

```bash
cd aws-iot-device-sdk-cpp-v2

# 创建构建目录
mkdir -p build
cd build

# 配置 CMake
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_DEPS=ON \
  -DCMAKE_INSTALL_PREFIX=/usr/local

# 编译 (使用所有 CPU 核心)
make -j$(nproc)

# 安装到系统目录
sudo make install

# 更新动态链接库缓存
sudo ldconfig

cd ../..
```

**步骤 3: 验证安装**

```bash
# 检查头文件
ls /usr/local/include/aws/greengrass/

# 检查库文件
ls /usr/local/lib/libGreengrassIpc-cpp.* 2>/dev/null || \
ls /usr/local/lib64/libGreengrassIpc-cpp.* 2>/dev/null
```

**预期输出**:
```
/usr/local/include/aws/greengrass/
├── GreengrassCoreIpcClient.h
├── GreengrassCoreIpcModel.h
└── ...

/usr/local/lib/libGreengrassIpc-cpp.so
/usr/local/lib/libaws-crt-cpp.so
```

**注意**: 
- 编译过程可能需要 5-10 分钟
- 需要至少 2GB 可用内存
- 如果编译失败,检查是否安装了所有依赖 (gcc, cmake, libssl-dev 等)

#### 1.3 设置环境变量

```bash
# 设置 AWS 区域
export AWS_REGION="ap-northeast-1"

# 使用之前创建的 S3 存储桶
export COMPONENT_BUCKET="iec104-greengrass-components-<your-timestamp>"

# 设置 Greengrass Thing 名称
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"

# 获取账户 ID
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 设置组件版本
export VERSION="1.0.1"
export COMPONENT_NAME="com.example.IEC104Collector"
```

#### 1.4 验证 IEC104 Simulator 运行

```bash
# 检查 Docker 容器
docker ps | grep iec104-simulator

# 测试端口连接
nc -zv localhost 2404
```

**预期输出**:
```
Connection to localhost 2404 port [tcp/*] succeeded!
```

---

### 步骤 2: 理解 IEC104 客户端实现

#### 2.1 IEC104 客户端核心流程

**1. 创建连接**:
```cpp
// 创建 IEC104 连接
CS104_Connection connection = CS104_Connection_create(host, port);

// 设置连接参数
CS104_Connection_setConnectTimeout(connection, 5000);  // 5 秒超时

// 设置 ASDU 接收处理函数
CS104_Connection_setASDUReceivedHandler(
    connection, 
    asduReceivedHandler,  // 回调函数
    userData              // 用户数据指针
);
```

**2. 建立连接**:
```cpp
// 连接到服务器
if (CS104_Connection_connect(connection)) {
    std::cout << "Connected to IEC104 server" << std::endl;
    
    // 启动数据传输
    CS104_Connection_sendStartDT(connection);
    
    // 发送总召唤命令
    CS104_Connection_sendInterrogationCommand(
        connection,
        CS101_COT_ACTIVATION,  // 传输原因: 激活
        1,                      // 公共地址
        IEC60870_QOI_STATION   // 召唤限定词: 站召唤
    );
} else {
    std::cerr << "Failed to connect" << std::endl;
}
```

**3. 处理接收到的数据**:
```cpp
bool asduReceivedHandler(void* parameter, int address, CS101_ASDU asdu) {
    // 获取 TypeID
    TypeID typeId = CS101_ASDU_getTypeID(asdu);
    
    // 只处理 TypeID=11 (MeasuredValueScaled)
    if (typeId == M_ME_NB_1) {
        int numElements = CS101_ASDU_getNumberOfElements(asdu);
        
        for (int i = 0; i < numElements; i++) {
            // 获取信息对象
            MeasuredValueScaled io = (MeasuredValueScaled)
                CS101_ASDU_getElement(asdu, i);
            
            // 获取 IOA 和值
            int ioa = InformationObject_getObjectAddress((InformationObject)io);
            int value = MeasuredValueScaled_getValue(io);
            
            // 过滤目标数据点
            if (ioa == 1001 || ioa == 2001) {
                // 处理数据...
                processDataPoint(ioa, value);
            }
        }
    }
    
    return true;  // 继续接收
}
```

#### 2.2 数据点映射

**模拟器提供的数据点**:

| IOA | 名称 | 基准值 | 单位 | 说明 |
|-----|------|--------|------|------|
| 1001 | wind_turbine_1_active_power | 1500 | kW | 风机有功功率 |
| 1002 | wind_turbine_1_reactive_power | 200 | kVar | 风机无功功率 |
| 1003 | wind_turbine_1_wind_speed | 8.5 | m/s | 风速 |
| 2001 | energy_storage_soc | 75 | % | 储能 SOC |
| 2002 | energy_storage_charge_power | 500 | kW | 储能充电功率 |
| 3001 | substation_voltage | 35 | kV | 变电站电压 |

**采集器过滤的数据点**:
- **IOA 1001**: 风机有功功率
- **IOA 2001**: 储能 SOC

**数据点映射表**:
```cpp
std::map<int, DataPointInfo> dataPointMap = {
    {1001, {"wind_turbine_1_active_power", "kW"}},
    {2001, {"energy_storage_soc", "%"}}
};
```

#### 2.3 JSON 数据格式

**输入** (IEC104 原始数据):
```
TypeID: 11 (M_ME_NB_1)
IOA: 1001, Value: 1500
IOA: 2001, Value: 75
```

**输出** (JSON 格式):
```json
[
  {
    "address": 1001,
    "name": "wind_turbine_1_active_power",
    "value": 1500.0,
    "unit": "kW",
    "timestamp": 1737622800
  },
  {
    "address": 2001,
    "name": "energy_storage_soc",
    "value": 75.0,
    "unit": "%",
    "timestamp": 1737622800
  }
]
```

---

### 步骤 3: 理解 IPC PublishToTopic

#### 3.1 IPC 初始化流程

**关键步骤**:

**1. 初始化 ApiHandle** ⚠️ 重要:
```cpp
// 必须传递 g_allocator
ApiHandle apiHandle(g_allocator);
```

**为什么?**
- `g_allocator` 是 AWS SDK 的全局内存分配器
- 不传递会导致 IPC 连接失败

**2. 创建事件循环和客户端**:
```cpp
// 创建事件循环组
Io::EventLoopGroup eventLoopGroup(1);

// 创建 DNS 解析器
Io::DefaultHostResolver socketResolver(eventLoopGroup, 64, 30);

// 创建客户端引导程序
Io::ClientBootstrap bootstrap(eventLoopGroup, socketResolver);

// 创建 IPC 客户端
GreengrassCoreIpcClient ipcClient(bootstrap);
```

**3. 连接到 Greengrass IPC**:
```cpp
// 创建生命周期处理器
auto lifecycleHandler = std::make_shared<IpcClientLifecycleHandler>();

// 连接
auto connectionStatus = ipcClient.Connect(lifecycleHandler).get();

// 检查连接状态
if (!connectionStatus) {  // 注意: !connectionStatus 表示失败
    std::cerr << "Failed to connect to Greengrass IPC" << std::endl;
    return 1;
}

std::cout << "Connected to Greengrass IPC" << std::endl;
```

#### 3.2 发布消息到 IPC Topic

**完整流程**:

```cpp
bool publishToIPC(const std::string& topic, const nlohmann::json& data) {
    // 1. 创建请求
    PublishToTopicRequest request;
    request.SetTopic(topic);
    
    // 2. 准备消息内容
    BinaryMessage binaryMessage;
    std::string payload = data.dump();  // JSON to string
    Vector<uint8_t> payloadBytes(payload.begin(), payload.end());
    binaryMessage.SetMessage(payloadBytes);
    
    // 3. 设置发布消息
    PublishMessage message;
    message.SetBinaryMessage(binaryMessage);
    request.SetPublishMessage(message);
    
    // 4. 创建操作
    auto operation = ipcClient.NewPublishToTopic();
    
    // 5. 激活操作 (必须传 nullptr)
    auto activate = operation->Activate(request, nullptr).get();
    if (!activate) {
        std::cerr << "Failed to activate operation" << std::endl;
        return false;
    }
    
    // 6. 获取结果
    auto responseFuture = operation->GetResult();
    
    // 7. 等待响应 (带超时)
    if (responseFuture.wait_for(std::chrono::seconds(5)) == 
        std::future_status::timeout) {
        std::cerr << "IPC publish timeout" << std::endl;
        return false;
    }
    
    auto response = responseFuture.get();
    if (response) {
        std::cout << "Published successfully to topic: " << topic << std::endl;
        return true;
    } else {
        std::cerr << "Failed to publish: " << response.GetResultError().GetMessage() 
                  << std::endl;
        return false;
    }
}
```

#### 3.3 关键注意事项 ⚠️

**1. ApiHandle 初始化**:
```cpp
// ❌ 错误
ApiHandle apiHandle;

// ✅ 正确
ApiHandle apiHandle(g_allocator);
```

**2. 连接状态检查**:
```cpp
// ❌ 错误
if (connectionStatus) {  // 成功时为 false!
    std::cerr << "Failed" << std::endl;
}

// ✅ 正确
if (!connectionStatus) {  // 失败时为 true
    std::cerr << "Failed" << std::endl;
}
```

**3. Activate 参数**:
```cpp
// ❌ 错误
auto activate = operation->Activate(request).get();

// ✅ 正确
auto activate = operation->Activate(request, nullptr).get();
```

**4. 超时处理**:
```cpp
// 添加超时避免无限等待
if (responseFuture.wait_for(std::chrono::seconds(5)) == 
    std::future_status::timeout) {
    std::cerr << "Timeout" << std::endl;
    return false;
}
```

---

### 步骤 4: 本地构建和测试

#### 4.1 构建组件

```bash
# 使用构建脚本
./build.sh
```

**构建脚本做了什么**:
1. 创建 `build/` 目录
2. 运行 CMake 配置
3. 编译 C++ 代码
4. 链接 lib60870 和 AWS SDK
5. 生成可执行文件

**预期输出**:
```
-- The C compiler identification is GNU 11.4.0
-- The CXX compiler identification is GNU 11.4.0
-- Configuring done
-- Generating done
-- Build files have been written to: .../build
[ 50%] Building CXX object CMakeFiles/iec104_collector.dir/src/collector.cpp.o
[100%] Linking CXX executable iec104_collector
[100%] Built target iec104_collector
```

#### 4.2 验证构建结果

```bash
# 查看生成的二进制文件
ls -lh build/iec104_collector

# 检查文件类型
file build/iec104_collector

# 查看依赖库
ldd build/iec104_collector | grep -E "lib60870|aws"
```

#### 4.3 本地测试 (不使用 Greengrass)

**准备测试配置**:

```bash
# 创建测试配置文件
cat > /tmp/collector-config.json << 'EOF'
{
  "serverHost": "localhost",
  "serverPort": 2404,
  "reconnectInterval": 5000,
  "ipcTopic": "iec104/data",
  "outputFile": "/tmp/iec104-data.json"
}
EOF
```

**启动测试**:

```bash
# 确保 IEC104 Simulator 正在运行
docker ps | grep iec104-simulator

# 运行采集器 (前台)
./build/iec104_collector /tmp/collector-config.json
```

**预期输出**:
```
[INFO] IEC104 Collector starting...
[INFO] Configuration loaded from /tmp/collector-config.json
[INFO] Server: localhost:2404
[INFO] IPC Topic: iec104/data
[INFO] Connecting to IEC104 server...
[INFO] Connected to IEC104 server localhost:2404
[INFO] Sending interrogation command...
[DEBUG] Received ASDU, TypeID=11, Elements=6
[DEBUG] IOA=1001, value=1500
[DEBUG] IOA=1002, value=200
[DEBUG] IOA=1003, value=8
[DEBUG] IOA=2001, value=75
[DEBUG] IOA=2002, value=500
[DEBUG] IOA=3001, value=35
[INFO] Filtered 2 data points (IOA: 1001, 2001)
[INFO] Saved 2 data points to /tmp/iec104-data.json
```

**查看采集的数据**:

```bash
# 查看 JSON 文件
cat /tmp/iec104-data.json | jq '.'
```

**预期内容**:
```json
[
  {
    "address": 1001,
    "name": "wind_turbine_1_active_power",
    "value": 1500.0,
    "unit": "kW",
    "timestamp": 1737622800
  },
  {
    "address": 2001,
    "name": "energy_storage_soc",
    "value": 75.0,
    "unit": "%",
    "timestamp": 1737622800
  }
]
```

#### 4.4 测试重连机制

**实验: 模拟器重启**

```bash
# 终端 1: 运行采集器
./build/iec104_collector /tmp/collector-config.json

# 终端 2: 重启模拟器
docker restart iec104-simulator

# 观察终端 1 的输出
```

**预期行为**:
```
[INFO] Connected to IEC104 server
[INFO] Connection lost
[INFO] Reconnecting in 5 seconds...
[INFO] Connected to IEC104 server
```

---

# Part 2: 打包和部署

### 步骤 5: 打包组件

#### 5.1 执行打包

```bash
# 使用打包脚本
./package.sh
```

**打包脚本做了什么**:
1. 创建 `artifacts/` 目录结构
2. 复制二进制文件
3. 设置执行权限
4. 创建 ZIP 包
5. 转换 Recipe 为 JSON

#### 5.2 验证打包结果

```bash
# 查看 ZIP 包内容
unzip -l artifacts/com.example.IEC104Collector-${VERSION}.zip
```

**预期输出**:
```
Archive:  artifacts/com.example.IEC104Collector-1.0.1.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  2026-01-23 10:00   iec104_collector/
  2616343  2026-01-23 10:00   iec104_collector/iec104_collector
---------                     -------
  2616343                     2 files
```

#### 5.3 上传到 S3

```bash
# 上传 ZIP 包
aws s3 cp artifacts/com.example.IEC104Collector-${VERSION}.zip \
  s3://${COMPONENT_BUCKET}/com.example.IEC104Collector/${VERSION}/ \
  --region ${AWS_REGION}

# 验证上传成功
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.IEC104Collector/${VERSION}/ \
  --region ${AWS_REGION}
```

#### 5.4 更新 Recipe 中的 S3 路径

```bash
# 使用 sed 替换 S3 路径
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" \
  artifacts/recipe.json > artifacts/recipe-updated.json

# 验证替换结果
grep "URI" artifacts/recipe-updated.json
```

---

### 步骤 6: 配置 AccessControl ⚠️ 关键

#### 6.1 理解 AccessControl 配置

**AccessControl 必须在两个地方配置**:

**1. Recipe 的 DefaultConfiguration**:
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

**2. 部署时的 configurationUpdate.merge**:
```json
{
  "accessControl": {
    "aws.greengrass.ipc.pubsub": {
      "com.example.IEC104Collector:pubsub:1": {
        "policyDescription": "Allow publishing to iec104/data topic",
        "operations": ["aws.greengrass#PublishToTopic"],
        "resources": ["iec104/data"]
      }
    }
  }
}
```

#### 6.2 AccessControl 配置详解

**字段说明**:

| 字段 | 说明 | 示例 |
|------|------|------|
| `aws.greengrass.ipc.pubsub` | IPC 服务类型 | 固定值 |
| `com.example.IEC104Collector:pubsub:1` | 策略 ID | `<组件名>:<类型>:<序号>` |
| `policyDescription` | 策略描述 | 便于理解 |
| `operations` | 允许的操作 | `PublishToTopic`, `SubscribeToTopic` |
| `resources` | 允许的资源 | Topic 名称或通配符 |

**通配符支持**:
```json
{
  "resources": [
    "iec104/*",      // 匹配 iec104/ 开头的所有 topic
    "*/data",        // 匹配以 /data 结尾的所有 topic
    "*"              // 匹配所有 topic (不推荐)
  ]
}
```

#### 6.3 常见权限错误

**错误 1**: 未配置 AccessControl
```
[ERROR] IPC publish failed: UNAUTHORIZED
```

**解决**: 在部署时包含 accessControl 配置

**错误 2**: 策略 ID 重复
```
[ERROR] Duplicate policy ID
```

**解决**: 使用唯一的策略 ID (如添加序号)

**错误 3**: 资源不匹配
```
[ERROR] Access denied for topic: iec104/data
```

**解决**: 确保 resources 包含实际使用的 topic


---

### 步骤 7: 注册和部署组件

#### 7.1 注册组件版本

**使用 AWS CLI**:

```bash
# 创建组件版本
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-updated.json \
  --region ${AWS_REGION}
```

**预期输出**:
```json
{
    "arn": "arn:aws:greengrass:ap-northeast-1:123456789012:components:com.example.IEC104Collector:versions:1.0.0",
    "componentName": "com.example.IEC104Collector",
    "componentVersion": "1.0.0",
    "creationTimestamp": "2026-01-23T11:00:00.000000+00:00",
    "status": {
        "componentState": "REQUESTED"
    }
}
```

#### 7.2 部署组件 (包含 Simulator 和 Collector)

**使用 AWS CLI**:

```bash
# 创建部署 (同时部署 Simulator 和 Collector)
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Full-Stack-$(date +%s)" \
  --components '{
    "aws.greengrass.Cli": {
      "componentVersion": "2.16.0"
    },
    "com.example.IEC104SimulatorDocker": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"ImageUri\":\"'${ACCOUNT_ID}'.dkr.ecr.'${AWS_REGION}'.amazonaws.com/iec104-simulator:1.0.0\",\"ContainerName\":\"iec104-simulator\",\"HostPort\":\"2404\"}"
      }
    },
    "com.example.IEC104Collector": {
      "componentVersion": "'"${VERSION}"'",
      "configurationUpdate": {
        "merge": "{\"serverHost\":\"localhost\",\"serverPort\":2404,\"ipcTopic\":\"iec104/data\",\"accessControl\":{\"aws.greengrass.ipc.pubsub\":{\"com.example.IEC104Collector:pubsub:1\":{\"policyDescription\":\"Allow publishing to iec104/data topic\",\"operations\":[\"aws.greengrass#PublishToTopic\"],\"resources\":[\"iec104/data\"]}}}}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**配置说明**:
- 同时部署 Simulator (Lab 3) 和 Collector (Lab 4)
- Collector 连接到 localhost:2404
- 配置 AccessControl 权限
- 发布到 iec104/data topic

**预期输出**:
```json
{
    "deploymentId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
}
```

```bash
# 保存部署 ID
export DEPLOYMENT_ID="<your-deployment-id>"
```

#### 7.3 监控部署状态

```bash
# 查看部署状态
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'deploymentStatus' \
  --output text

# 持续监控
watch -n 5 "aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'deploymentStatus' \
  --output text"
```

---

# Part 3: 验证和调试

### 步骤 8: 验证组件运行

#### 8.1 查看组件状态

```bash
# 查看所有组件
sudo /greengrass/v2/bin/greengrass-cli component list
```

**预期输出**:
```
Component Name: com.example.IEC104SimulatorDocker
    Version: 1.0.0
    State: RUNNING
Component Name: com.example.IEC104Collector
    Version: 1.0.1
    State: RUNNING
    Configuration: {"serverHost":"localhost","serverPort":2404,"ipcTopic":"iec104/data",...}
```

#### 8.2 查看 Collector 日志

```bash
# 实时查看日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log
```

**预期日志**:
```
2026-01-23T11:05:00.000Z [INFO] (Copier) com.example.IEC104Collector: stdout. [INFO] IEC104 Collector starting...
2026-01-23T11:05:00.100Z [INFO] (Copier) com.example.IEC104Collector: stdout. [INFO] Configuration loaded
2026-01-23T11:05:00.200Z [INFO] (Copier) com.example.IEC104Collector: stdout. [INFO] Connected to Greengrass IPC
2026-01-23T11:05:00.300Z [INFO] (Copier) com.example.IEC104Collector: stdout. [INFO] Connected to IEC104 server localhost:2404
2026-01-23T11:05:00.400Z [INFO] (Copier) com.example.IEC104Collector: stdout. [INFO] Sending interrogation command...
2026-01-23T11:05:00.500Z [INFO] (Copier) com.example.IEC104Collector: stdout. [DEBUG] Received ASDU, TypeID=11
2026-01-23T11:05:00.600Z [INFO] (Copier) com.example.IEC104Collector: stdout. [DEBUG] IOA=1001, value=1500
2026-01-23T11:05:00.700Z [INFO] (Copier) com.example.IEC104Collector: stdout. [DEBUG] IOA=2001, value=75
2026-01-23T11:05:00.800Z [INFO] (Copier) com.example.IEC104Collector: stdout. [INFO] Published 2 data points to IPC topic: iec104/data
```

#### 8.3 查看 Simulator 日志

```bash
# 查看 Docker 容器日志
docker logs iec104-simulator
```

**预期日志**:
```
[INFO] IEC104 Simulator starting...
[INFO] Listening on port 2404
[INFO] Client connected from 127.0.0.1
[INFO] Received STARTDT
[INFO] Received Interrogation command
[INFO] Sending 6 data points...
```

#### 8.4 验证 IPC 消息发布

**方法 1**: 查看日志中的发布记录

```bash
# 搜索发布成功的日志
sudo grep "Published" /greengrass/v2/logs/com.example.IEC104Collector.log
```

**方法 2**: 使用 Greengrass CLI 测试订阅

```bash
# 订阅 IPC topic (需要在另一个终端运行)
sudo /greengrass/v2/bin/greengrass-cli pubsub sub \
  --topic iec104/data
```

**预期输出**:
```
Subscribed to topic: iec104/data
Received message:
[
  {
    "address": 1001,
    "name": "wind_turbine_1_active_power",
    "value": 1500.0,
    "unit": "kW",
    "timestamp": 1737622800
  },
  {
    "address": 2001,
    "name": "energy_storage_soc",
    "value": 75.0,
    "unit": "%",
    "timestamp": 1737622800
  }
]
```

---

### 步骤 9: 故障排查

#### 9.1 常见问题 1: IPC 发布失败

**症状**:
```
[ERROR] IPC publish failed: UNAUTHORIZED
```

**原因**: AccessControl 权限未配置或配置错误

**解决方案**:

1. 检查组件配置
```bash
sudo /greengrass/v2/bin/greengrass-cli component details \
  --name com.example.IEC104Collector
```

2. 验证 accessControl 配置存在
```bash
# 应该看到 accessControl 字段
```

3. 重新部署并包含 accessControl
```bash
# 确保 configurationUpdate.merge 包含完整的 accessControl 配置
```

#### 9.2 常见问题 2: 无法连接到 IEC104 Simulator

**症状**:
```
[ERROR] Failed to connect to IEC104 server localhost:2404
```

**检查步骤**:

1. 验证 Simulator 运行
```bash
docker ps | grep iec104-simulator
```

2. 测试端口连接
```bash
nc -zv localhost 2404
```

3. 查看 Simulator 日志
```bash
docker logs iec104-simulator
```

4. 检查网络模式
```bash
# Simulator 应该使用 host 网络模式
docker inspect iec104-simulator --format='{{.HostConfig.NetworkMode}}'
# 应该输出: host
```

#### 9.3 常见问题 3: 收不到数据

**症状**: 连接成功但没有数据

**检查步骤**:

1. 查看 Collector 日志中的 ASDU 接收记录
```bash
sudo grep "Received ASDU" /greengrass/v2/logs/com.example.IEC104Collector.log
```

2. 检查数据点过滤逻辑
```bash
# 确认 IOA 1001 和 2001 在过滤列表中
```

3. 手动触发总召唤
```bash
# 重启 Collector 组件会重新发送总召唤
sudo /greengrass/v2/bin/greengrass-cli component restart \
  --name com.example.IEC104Collector
```

#### 9.4 常见问题 4: IPC 连接失败

**症状**:
```
[ERROR] Failed to connect to Greengrass IPC
```

**原因**: ApiHandle 初始化错误

**检查代码**:
```cpp
// ❌ 错误
ApiHandle apiHandle;

// ✅ 正确
ApiHandle apiHandle(g_allocator);
```

#### 9.5 常见问题 5: 组件频繁重启

**症状**: 组件状态在 RUNNING 和 STARTING 之间切换

**检查步骤**:

1. 查看崩溃日志
```bash
sudo grep "ERRORED\|BROKEN" /greengrass/v2/logs/greengrass.log | grep IEC104Collector
```

2. 检查内存使用
```bash
# 查看组件进程
ps aux | grep iec104_collector
```

3. 查看段错误
```bash
dmesg | grep iec104_collector
```

#### 9.6 调试技巧

**1. 增加日志级别**:
```cpp
// 在代码中添加更多调试日志
std::cout << "[DEBUG] Variable value: " << value << std::endl;
```

**2. 使用 gdb 调试**:
```bash
# 本地调试
gdb ./build/iec104_collector
(gdb) run /tmp/collector-config.json
(gdb) bt  # 查看堆栈
```

**3. 检查 IPC 权限**:
```bash
# 查看 IPC socket 权限
ls -la /greengrass/v2/ipc.socket
```

**4. 测试 IPC 连接**:
```bash
# 使用 Greengrass CLI 测试发布
sudo /greengrass/v2/bin/greengrass-cli pubsub publish \
  --topic iec104/data \
  --message '{"test": "message"}'
```

---

## 📚 核心概念总结

### 1. IEC104 客户端通信流程

```
1. 创建连接
   CS104_Connection_create()
   ↓
2. 设置回调
   CS104_Connection_setASDUReceivedHandler()
   ↓
3. 建立连接
   CS104_Connection_connect()
   ↓
4. 启动数据传输
   CS104_Connection_sendStartDT()
   ↓
5. 发送总召唤
   CS104_Connection_sendInterrogationCommand()
   ↓
6. 接收数据
   asduReceivedHandler() 回调
   ↓
7. 处理数据
   过滤、转换、发布
```

### 2. IPC PublishToTopic 关键步骤

| 步骤 | 操作 | 关键点 |
|------|------|--------|
| 1 | 初始化 ApiHandle | 必须传递 `g_allocator` |
| 2 | 创建 IPC 客户端 | 使用 EventLoopGroup 和 Bootstrap |
| 3 | 连接 IPC | 检查 `!connectionStatus` |
| 4 | 创建请求 | 设置 topic 和 payload |
| 5 | 激活操作 | 传递 `nullptr` 作为第二个参数 |
| 6 | 获取结果 | 添加超时处理 |

### 3. AccessControl 配置要点

| 配置项 | 说明 | 示例 |
|--------|------|------|
| **服务类型** | IPC 服务 | `aws.greengrass.ipc.pubsub` |
| **策略 ID** | 唯一标识 | `<组件名>:pubsub:1` |
| **操作** | 允许的 IPC 操作 | `PublishToTopic`, `SubscribeToTopic` |
| **资源** | Topic 名称 | `iec104/data`, `iec104/*` |

### 4. 数据流

```
IEC104 Simulator (Docker)
  ↓ IEC104 Protocol (TCP/IP)
IEC104 Collector
  ├── 接收 ASDU
  ├── 过滤数据点 (IOA 1001, 2001)
  ├── 转换为 JSON
  └── 发布到 IPC
       ↓ Greengrass IPC Pubsub
订阅者组件 (Lab 5)
  └── 处理并发送到云端
```

## 🎓 实验总结

通过本实验,你已经学会:

### ✅ 核心技能
- 实现 IEC104 客户端连接和数据采集
- 使用 lib60870-C 库处理工业协议
- 通过 Greengrass IPC PublishToTopic 发布数据
- 配置 AccessControl 权限
- 数据过滤和 JSON 转换
- 组件间通信和调试

### ✅ 关键概念
- IEC104 协议的客户端实现
- ASDU 数据结构和处理
- Greengrass IPC Pubsub 机制
- AccessControl 权限模型
- 组件生命周期管理

### ✅ 最佳实践
- 正确初始化 ApiHandle (传递 g_allocator)
- 检查 IPC 连接状态 (!connectionStatus)
- 在 Activate 时传递 nullptr
- 添加超时处理避免阻塞
- 在 Recipe 和部署时都配置 AccessControl
- 使用数据点映射表管理元数据
- 实现重连机制提高可靠性

## 🔍 常见问题

### Q1: 为什么 ApiHandle 必须传递 g_allocator?

**原因**: AWS SDK 使用自定义内存分配器管理内存。不传递会导致内存分配失败,IPC 连接无法建立。

**正确用法**:
```cpp
ApiHandle apiHandle(g_allocator);
```

### Q2: 为什么连接状态检查是 !connectionStatus?

**原因**: AWS SDK 的设计,成功时返回空的 RpcError (false),失败时返回错误对象 (true)。

**正确检查**:
```cpp
if (!connectionStatus) {  // 失败
    std::cerr << "Failed" << std::endl;
}
```

### Q3: AccessControl 配置在哪里生效?

**两个位置都需要**:
1. Recipe 的 `ComponentConfiguration.DefaultConfiguration.accessControl`
2. 部署时的 `configurationUpdate.merge`

**如果只在 Recipe 中配置**: 部署时会被覆盖  
**如果只在部署时配置**: 下次部署可能丢失

### Q4: 如何调试 IPC 发布失败?

**步骤**:
1. 检查 AccessControl 配置
2. 查看组件日志中的错误信息
3. 使用 Greengrass CLI 测试发布
4. 验证 topic 名称匹配

### Q5: 如何处理 IEC104 连接断开?

**实现重连机制**:
```cpp
while (running) {
    if (!CS104_Connection_connect(connection)) {
        std::cerr << "Connection failed, retrying..." << std::endl;
        std::this_thread::sleep_for(std::chrono::seconds(5));
        continue;
    }
    // 处理数据...
}
```

### Q6: 如何验证数据是否正确发布到 IPC?

**方法 1**: 查看日志
```bash
sudo grep "Published" /greengrass/v2/logs/com.example.IEC104Collector.log
```

**方法 2**: 使用 CLI 订阅
```bash
sudo /greengrass/v2/bin/greengrass-cli pubsub sub --topic iec104/data
```

**方法 3**: 部署订阅者组件 (Lab 5)

## 📖 参考资料

### AWS 官方文档
- [AWS IoT Greengrass V2 开发者指南](https://docs.aws.amazon.com/greengrass/v2/developerguide/)
- [IPC PublishToTopic](https://docs.aws.amazon.com/greengrass/v2/developerguide/ipc-publish-subscribe.html)
- [AccessControl 配置](https://docs.aws.amazon.com/greengrass/v2/developerguide/interprocess-communication.html#ipc-authorization-policies)
- [AWS IoT Device SDK for C++ v2](https://github.com/aws/aws-iot-device-sdk-cpp-v2)

### 相关 Workshop
- [Lab 1: 部署第一个 Greengrass 组件](../lab1-hello-world/WORKSHOP.md) - 基础组件开发
- [Lab 2: 配置管理和日志系统](../lab2-config-logging/WORKSHOP.md) - 日志管理
- [Lab 3: IEC104 模拟器](../lab3-iec104-simulator/WORKSHOP.md) - Docker 组件
- [Lab 5: IoT Core 集成](../lab5-iot-integration/WORKSHOP.md) - 云端集成

### 工具和库
- [lib60870](https://github.com/mz-automation/lib60870) - IEC 60870-5-104 协议库
- [nlohmann/json](https://github.com/nlohmann/json) - C++ JSON 库
- [AWS CLI 参考](https://docs.aws.amazon.com/cli/latest/reference/greengrassv2/)

## 🎯 下一步

完成 Lab 4 后,建议继续:

**Lab 5: IoT Core 集成**
- 订阅 IPC topic (iec104/data)
- 将数据转发到 AWS IoT Core
- 实践 MQTT 消息发布
- 掌握异步消息处理
- 完成完整的边缘到云数据管道

## 📝 实验检查清单

完成以下检查项,确保实验成功:

- [ ] 成功构建 IEC104 Collector 组件
- [ ] 本地测试连接到 Simulator 成功
- [ ] 能够接收和解析 IEC104 数据
- [ ] 数据点过滤正确 (只保留 IOA 1001, 2001)
- [ ] JSON 格式转换正确
- [ ] 成功打包和上传到 S3
- [ ] 成功注册组件到 AWS Greengrass
- [ ] 成功部署组件到设备
- [ ] AccessControl 权限配置正确
- [ ] 能够发布消息到 IPC topic
- [ ] 使用 CLI 能够订阅到消息
- [ ] 理解 IEC104 协议和 IPC 通信机制

---

**🎉 恭喜完成 Lab 4!**

你已经掌握了 IEC104 数据采集和 Greengrass IPC 通信。继续下一个实验,学习如何将数据发送到 AWS IoT Core!

**问题反馈**: 如有问题,请联系 Workshop 讲师或查阅 [AWS 支持](https://aws.amazon.com/support/)。
