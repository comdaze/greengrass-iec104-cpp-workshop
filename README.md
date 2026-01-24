# AWS Greengrass Workshop - IEC104 边缘到云数据管道

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Greengrass](https://img.shields.io/badge/AWS%20Greengrass-v2.16.1-orange.svg)](https://aws.amazon.com/greengrass/)
[![IEC104](https://img.shields.io/badge/IEC%2060870--5--104-lib60870-green.svg)](https://github.com/mz-automation/lib60870)

完整的工业物联网数据采集系统,使用真实的 IEC 60870-5-104 协议实现,通过 AWS IoT Greengrass 将边缘设备数据安全地传输到 AWS IoT Core。

## 📚 目录

- [项目概览](#项目概览)
- [快速开始](#快速开始)
- [实验列表](#实验列表)
- [架构说明](#架构说明)
- [技术栈](#技术栈)
- [安装指南](#安装指南)
- [Workshop 向导](#workshop-向导)
- [故障排查](#故障排查)
- [参考资料](#参考资料)

## 🎯 项目概览

本项目展示了如何构建一个生产级的边缘到云数据管道:

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

- ✅ **真实协议实现**: 使用 lib60870-C 库,完整实现 IEC 60870-5-104 标准
- ✅ **边缘计算**: 在 Greengrass 边缘运行时处理和过滤数据
- ✅ **IPC 通信**: 组件间使用 Greengrass IPC pubsub 解耦通信
- ✅ **云端集成**: 安全地将数据发送到 AWS IoT Core
- ✅ **容器化部署**: 模拟器使用 Docker 容器,易于部署和管理
- ✅ **生产就绪**: 包含错误处理、日志记录、配置管理


## 📚 实验列表

本 Workshop 包含 5 个循序渐进的实验,从基础组件开发到完整的边缘到云数据管道:

### Lab 1: 部署第一个 Greengrass 组件 ⭐
**时长**: 60 分钟 | **难度**: 初级

学习 Greengrass 组件的基本概念、构建、打包和部署流程。

**你将学到**:
- Greengrass 组件架构和生命周期
- C++ 组件开发和 CMake 构建
- Recipe 配置文件编写
- S3 存储和组件注册
- 动态配置更新

📖 **[Lab 1 Workshop 向导](./lab1-hello-world/WORKSHOP.md)** | 📄 [详细文档](./lab1-hello-world/README.md)

---

### Lab 2: 配置管理和日志系统 ⭐⭐
**时长**: 90 分钟 | **难度**: 中级

实现多级日志系统,学习配置管理和 CloudWatch Logs 集成。

**你将学到**:
- 多级日志系统 (DEBUG/INFO/WARN/ERROR)
- Logger 类设计和实现
- 本地日志文件管理
- LogManager 组件部署
- CloudWatch Logs 集成和查询

📖 **[Lab 2 Workshop 向导](./lab2-config-logging/WORKSHOP.md)** | 📄 [详细文档](./lab2-config-logging/README.md)

---

### Lab 3: IEC104 模拟器 - Docker 容器化部署 ⭐⭐⭐
**时长**: 90 分钟 | **难度**: 中高级

使用 Docker 容器化部署 IEC104 协议模拟器,学习工业协议和容器化边缘应用。

**你将学到**:
- IEC 60870-5-104 工业协议基础
- Dockerfile 编写和多阶段构建
- Amazon ECR 镜像管理
- Greengrass Docker 组件开发
- lib60870 协议库使用

📖 **[Lab 3 Workshop 向导](./lab3-iec104-simulator/WORKSHOP.md)** | 📄 [详细文档](./lab3-iec104-simulator/README.md)

---

### Lab 4: IEC104 数据采集器 ⭐⭐⭐
**时长**: 90 分钟 | **难度**: 高级

实现 IEC104 客户端采集数据,通过 Greengrass IPC 发布到本地 topic。

**你将学到**:
- IEC104 客户端实现
- lib60870 库的客户端 API
- Greengrass IPC PublishToTopic
- AccessControl 权限配置
- 数据过滤和 JSON 转换

📖 **[Lab 4 Workshop 向导](./lab4-iec104-collector/WORKSHOP.md)** | 📄 [详细文档](./lab4-iec104-collector/README.md)

---

### Lab 5: AWS IoT Core 集成 ⭐⭐⭐
**时长**: 90 分钟 | **难度**: 高级

订阅 IPC topic 并将数据转发到 AWS IoT Core,完成边缘到云的完整数据管道。

**你将学到**:
- IPC SubscribeToTopic 订阅
- PublishToIoTCore 发布到云端
- 异步消息处理模式
- 消息队列和线程安全
- IoT Core MQTT 集成

📖 **[Lab 5 Workshop 向导](./lab5-iot-integration/WORKSHOP.md)** | 📄 [详细文档](./lab5-iot-integration/README.md)

---

## 🎯 学习路径

```
Lab 1: Hello World
  ↓ 掌握基础组件开发
Lab 2: 配置和日志
  ↓ 掌握配置管理和日志系统
Lab 3: IEC104 模拟器
  ↓ 掌握 Docker 容器化和工业协议
Lab 4: IEC104 采集器
  ↓ 掌握 IPC 通信和数据采集
Lab 5: IoT Core 集成
  ↓ 完成边缘到云数据管道
✅ 完整的工业物联网解决方案
```

## 📐 架构说明

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Cloud                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  AWS IoT Core                                          │    │
│  │  - MQTT Broker                                         │    │
│  │  - Topic: wind-farm/data                               │    │
│  └────────────────────────────────────────────────────────┘    │
│                              ▲                                   │
│                              │ MQTT over TLS                     │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│         Greengrass Core Device                                   │
│                              │                                   │
│  ┌──────────────────────────┴─────────────────────────────┐    │
│  │  IoT Publisher (Lab 5)                                  │    │
│  │  - SubscribeToTopic (iec104/data)                       │    │
│  │  - PublishToIoTCore (wind-farm/data)                    │    │
│  └──────────────────────┬─────────────────────────────────┘    │
│                         │ IPC Pubsub                            │
│  ┌──────────────────────▼─────────────────────────────────┐    │
│  │  IEC104 Collector (Lab 4)                               │    │
│  │  - IEC104 Client                                        │    │
│  │  - Data Filtering                                       │    │
│  │  - PublishToTopic (iec104/data)                         │    │
│  └──────────────────────┬─────────────────────────────────┘    │
│                         │ IEC104 Protocol                       │
│  ┌──────────────────────▼─────────────────────────────────┐    │
│  │  IEC104 Simulator (Lab 3)                               │    │
│  │  - Docker Container                                     │    │
│  │  - IEC104 Server (Port 2404)                            │    │
│  │  - Simulate 6 data points                               │    │
│  └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 数据流

```
IEC104 Simulator
  ↓ IEC 60870-5-104 Protocol (TCP/IP)
  ↓ TypeID=11 (MeasuredValueScaled)
  ↓ 6 个数据点 (风机、储能、变电站)
IEC104 Collector
  ↓ 过滤 IOA 1001, 2001
  ↓ 转换为 JSON
  ↓ Greengrass IPC Pubsub (iec104/data)
IoT Publisher
  ↓ 订阅 IPC topic
  ↓ 消息队列缓冲
  ↓ MQTT over TLS (wind-farm/data)
AWS IoT Core
  ↓ Rules Engine (可选)
  ↓ DynamoDB / S3 / Lambda
```

## 🛠️ 技术栈

### 边缘端

- **AWS IoT Greengrass v2.16.1**: 边缘运行时
- **C++ 17**: 组件开发语言
- **lib60870-C**: IEC 60870-5-104 协议库
- **AWS IoT Device SDK for C++ v2**: IPC 和 IoT Core 通信
- **nlohmann/json**: JSON 处理
- **Docker**: 容器化部署
- **CMake**: 构建系统

### 云端

- **AWS IoT Core**: MQTT 消息代理
- **Amazon ECR**: 容器镜像仓库
- **Amazon S3**: 组件存储
- **CloudWatch Logs**: 日志聚合和分析


## 📚 参考资料

### AWS 官方文档
- [AWS IoT Greengrass V2 开发者指南](https://docs.aws.amazon.com/greengrass/v2/developerguide/)
- [组件 Recipe 参考](https://docs.aws.amazon.com/greengrass/v2/developerguide/component-recipe-reference.html)
- [IPC 通信](https://docs.aws.amazon.com/greengrass/v2/developerguide/interprocess-communication.html)
- [AWS IoT Core](https://docs.aws.amazon.com/iot/)

### 工具和库
- [lib60870](https://github.com/mz-automation/lib60870) - IEC 60870-5-104 协议库
- [AWS IoT Device SDK for C++ v2](https://github.com/aws/aws-iot-device-sdk-cpp-v2)
- [nlohmann/json](https://github.com/nlohmann/json) - C++ JSON 库
- [Docker 官方文档](https://docs.docker.com/)

### 相关资源
- [IEC 60870-5-104 标准](https://en.wikipedia.org/wiki/IEC_60870-5)
- [MQTT 协议](https://mqtt.org/)
- [CMake 文档](https://cmake.org/documentation/)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request!

## 📄 许可证

MIT License

## 👥 作者

Kiro and Sean
