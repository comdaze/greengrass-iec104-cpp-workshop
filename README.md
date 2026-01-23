# AWS Greengrass Workshop - IEC104 边缘到云数据管道

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Greengrass](https://img.shields.io/badge/AWS%20Greengrass-v2.16.1-orange.svg)](https://aws.amazon.com/greengrass/)
[![IEC104](https://img.shields.io/badge/IEC%2060870--5--104-lib60870-green.svg)](https://github.com/mz-automation/lib60870)

完整的工业物联网数据采集系统，使用真实的 IEC 60870-5-104 协议实现，通过 AWS IoT Greengrass 将边缘设备数据安全地传输到 AWS IoT Core。

## 🎯 项目概览

本项目展示了如何构建一个生产级的边缘到云数据管道：

```
IEC104 设备模拟器 (lib60870)
    ↓ TCP/IP - IEC 60870-5-104 协议
IEC104 数据采集器
    ↓ Greengrass IPC Pubsub
IoT 数据发布器
    ↓ MQTT over TLS
AWS IoT Core
```

### 核心特性

- ✅ **真实协议实现**：使用 lib60870-C 库，完整实现 IEC 60870-5-104 标准
- ✅ **边缘计算**：在 Greengrass 边缘运行时处理和过滤数据
- ✅ **IPC 通信**：组件间使用 Greengrass IPC pubsub 解耦通信
- ✅ **云端集成**：安全地将数据发送到 AWS IoT Core
- ✅ **容器化部署**：模拟器使用 Docker 容器，易于部署和管理
- ✅ **生产就绪**：包含错误处理、日志记录、配置管理

## 📚 实验列表

### Lab 3: IEC104 模拟器 ⭐⭐
**时长**: 60分钟 | **难度**: 中级

使用 lib60870-C 库实现真实的 IEC104 协议服务器，模拟风电和储能设备数据。

**技术栈**：
- C++ 17
- lib60870-C (IEC 60870-5-104)
- Docker
- AWS Greengrass Docker Component

**你将学到**：
- IEC 60870-5-104 协议基础
- lib60870 库的使用
- Docker 容器化部署
- Greengrass Docker 组件开发

[查看 Lab 3 详情 →](./lab3-iec104-simulator/)

### Lab 4: IEC104 数据采集器 ⭐⭐⭐
**时长**: 90分钟 | **难度**: 高级

实现 IEC104 客户端，采集数据并通过 Greengrass IPC pubsub 发布。

**技术栈**：
- C++ 17
- lib60870-C (IEC 60870-5-104 Client)
- AWS IoT Device SDK for C++ v2
- Greengrass IPC

**你将学到**：
- IEC104 客户端实现
- Greengrass IPC pubsub 发布
- 数据过滤和转换
- 组件间通信

**关键代码**：
```cpp
// IPC 发布示例
PublishToTopicRequest request;
request.SetTopic("iec104/data");
auto operation = ipcClient.NewPublishToTopic();
auto activate = operation->Activate(request, nullptr).get();
```

[查看 Lab 4 详情 →](./lab4-iec104-collector/)

### Lab 5: IoT Core 集成 ⭐⭐⭐
**时长**: 60分钟 | **难度**: 高级

订阅 IPC topic 并将数据转发到 AWS IoT Core。

**技术栈**：
- C++ 17
- AWS IoT Device SDK for C++ v2
- Greengrass IPC (pubsub + mqttproxy)
- 异步消息队列

**你将学到**：
- IPC topic 订阅
- PublishToIoTCore 操作
- 异步消息处理（避免回调阻塞）
- IoT Core MQTT 集成

**架构亮点**：
- 使用消息队列解耦 IPC 回调和 IoT Core 发布
- 避免在 StreamHandler 回调中执行阻塞操作
- 主线程处理消息队列，确保事件循环不被阻塞

[查看 Lab 5 详情 →](./lab5-iot-integration/)

## 🚀 快速开始

### 全新环境一键安装

如果你是在全新的 Ubuntu 服务器上部署，使用一键安装脚本：

```bash
git clone https://github.com/comdaze/greengrass-iec104-cpp-workshop.git workshop
cd workshop
./setup-environment.sh
```

**详细安装指南**: [INSTALLATION.md](./INSTALLATION.md)

### 前置条件

- AWS 账号（具有 IoT 和 Greengrass 权限）
- Linux 环境（Ubuntu 20.04+ 或 Amazon Linux 2）
- Docker（用于 Lab 3 模拟器）
- AWS CLI v2
- CMake 3.10+
- GCC 7+ 或 Clang 6+

### 环境准备

1. **安装 AWS CLI**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws configure
```

2. **安装 Greengrass Core**
```bash
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > greengrass-nucleus-latest.zip
unzip greengrass-nucleus-latest.zip -d GreengrassInstaller
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
  -jar ./GreengrassInstaller/lib/Greengrass.jar \
  --aws-region ap-northeast-1 \
  --thing-name MyGreengrassCore \
  --provision true \
  --setup-system-service true
```

3. **创建 S3 存储桶**
```bash
export COMPONENT_BUCKET=iec104-components-$(date +%s)
export AWS_REGION=ap-northeast-1
aws s3 mb s3://${COMPONENT_BUCKET} --region ${AWS_REGION}
```

### 部署完整系统

```bash
# 1. 构建并部署 Lab 3 (IEC104 Simulator)
cd lab3-iec104-simulator
./docker-build.sh
./deploy.sh

# 2. 构建并部署 Lab 4 (IEC104 Collector)
cd ../lab4-iec104-collector
./build.sh
./package.sh
./deploy.sh

# 3. 构建并部署 Lab 5 (IoT Publisher)
cd ../lab5-iot-integration
./build.sh
./package.sh
./deploy.sh
```

### 验证部署

```bash
# 检查组件状态
sudo /greengrass/v2/bin/greengrass-cli component list

# 查看日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log
sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log

# 测试 IoT Core 发布
sudo /greengrass/v2/bin/greengrass-cli iotcore pub \
  --topic test/topic \
  --message '{"test":"message"}'
```

## 📊 数据流

### 完整数据流程

```
┌─────────────────────────────────────────────────────────────────┐
│  IEC104 Simulator (Docker Container)                           │
│  - lib60870 CS104_Slave                                         │
│  - TCP Port 2404                                                │
│  - 模拟 6 个数据点 (风电 + 储能)                                  │
└────────────────────┬────────────────────────────────────────────┘
                     │ IEC 60870-5-104 Protocol
                     │ TypeID=11 (MeasuredValueScaled)
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│  IEC104 Collector                                               │
│  - lib60870 CS104_Connection                                    │
│  - 过滤目标数据点 (IOA 1001, 2001)                               │
│  - 转换为 JSON 格式                                              │
└────────────────────┬────────────────────────────────────────────┘
                     │ Greengrass IPC Pubsub
                     │ Topic: iec104/data
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│  IoT Publisher                                                  │
│  - 订阅 IPC topic                                                │
│  - 消息队列缓冲                                                   │
│  - 主线程异步发布                                                 │
└────────────────────┬────────────────────────────────────────────┘
                     │ MQTT over TLS
                     │ Topic: wind-farm/data
                     │ QoS: AT_LEAST_ONCE
                     ↓
┌─────────────────────────────────────────────────────────────────┐
│  AWS IoT Core                                                   │
│  - MQTT Broker                                                  │
│  - Rules Engine                                                 │
│  - 可连接到其他 AWS 服务                                          │
└─────────────────────────────────────────────────────────────────┘
```

### 数据格式

**IEC104 原始数据**：
```
TypeID: 11 (M_ME_NB_1 - MeasuredValueScaled)
IOA: 1001, Value: 1500 (风机有功功率)
IOA: 2001, Value: 75   (储能 SOC)
```

**JSON 输出**：
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

## 🔧 技术细节

### IEC 60870-5-104 协议

IEC 60870-5-104 是电力系统中广泛使用的通信协议，基于 TCP/IP。

**关键特性**：
- 面向连接的 TCP 通信
- 支持多种数据类型（遥测、遥信、遥控）
- 时间戳和质量标识
- 总召唤（Interrogation）机制

**本项目使用的数据类型**：
- TypeID 11 (M_ME_NB_1): MeasuredValueScaled - 标度化测量值

### Greengrass IPC

**IPC Pubsub**：
- 组件间本地消息传递
- 无需网络连接
- 低延迟、高吞吐

**IPC MQTTProxy**：
- 将消息发布到 AWS IoT Core
- 自动处理连接和重试
- 支持 QoS 0 和 QoS 1

### 关键设计决策

1. **异步消息处理**
   - 问题：在 IPC StreamHandler 回调中直接调用 PublishToIoTCore 会阻塞事件循环
   - 解决：使用消息队列，在主线程中处理发布

2. **AccessControl 配置**
   - 必须在 ComponentConfiguration.DefaultConfiguration 中定义
   - 部署时需要在 configurationUpdate.merge 中包含
   - 否则权限不会生效

3. **ApiHandle 初始化**
   - 必须传递 `g_allocator`：`ApiHandle apiHandle(g_allocator)`
   - 否则 IPC 连接会失败

## 📖 文档

- [Lab 3 - IEC104 Simulator](./lab3-iec104-simulator/README.md)
- [Lab 4 - IEC104 Collector](./lab4-iec104-collector/README.md)
- [Lab 5 - IoT Publisher](./lab5-iot-integration/README.md)
- [IPC Pubsub 详解](./lab4-iec104-collector/README-IPC.md)

## 🐛 故障排除

### IPC 发布超时

**症状**：`[ERROR] IPC publish timeout`

**原因**：
1. accessControl 配置未生效
2. ApiHandle 未正确初始化
3. 在回调中执行阻塞操作

**解决**：
```cpp
// 1. 正确初始化
ApiHandle apiHandle(g_allocator);

// 2. 检查连接状态
auto connectionStatus = ipcClient.Connect(lifecycleHandler).get();
if (!connectionStatus) {
    // 处理错误
}

// 3. 在主线程发布，不在回调中
```

### 组件无法启动

**症状**：组件状态为 BROKEN

**检查**：
```bash
# 查看详细日志
sudo tail -100 /greengrass/v2/logs/greengrass.log
sudo tail -100 /greengrass/v2/logs/com.example.*.log

# 检查权限
ls -la /greengrass/v2/packages/artifacts-unarchived/
```

### Docker 容器无法启动

**症状**：IEC104SimulatorDocker 组件 BROKEN

**检查**：
```bash
# 检查 Docker 服务
sudo systemctl status docker

# 检查镜像
docker images | grep iec104-simulator

# 手动运行测试
docker run -p 2404:2404 <image-id>
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 🔗 相关资源

- [AWS IoT Greengrass 文档](https://docs.aws.amazon.com/greengrass/)
- [lib60870 GitHub](https://github.com/mz-automation/lib60870)
- [IEC 60870-5-104 标准](https://en.wikipedia.org/wiki/IEC_60870-5)
- [AWS IoT Device SDK for C++ v2](https://github.com/aws/aws-iot-device-sdk-cpp-v2)

## 👥 作者

Workshop Participant

---

**永不妥协的实现** - 使用真实的工业协议，构建生产级的边缘到云数据管道。
