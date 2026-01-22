# AWS Greengrass Workshop - IEC104数据采集系统

欢迎参加AWS Greengrass Workshop！本Workshop将带你从零开始，逐步构建一个完整的IEC104数据采集系统。

## Workshop概览

通过本Workshop，你将学习：
- AWS IoT Greengrass核心概念
- 组件开发和部署流程
- 边缘计算最佳实践
- IEC104工业协议集成
- 云边协同架构设计

## 实验列表

### Lab 1: 部署第一个Greengrass组件 ⭐
**时长**: 30分钟  
**难度**: 入门

学习Greengrass组件的基本结构，创建并部署一个简单的Hello World组件。

**你将学到**：
- Greengrass组件结构
- Recipe文件编写
- 组件构建和打包
- 部署和配置管理

[开始Lab 1 →](./lab1-hello-world/)

### Lab 2: 配置管理和日志 ⭐⭐
**时长**: 45分钟  
**难度**: 中级

学习如何管理组件配置，实现动态配置更新，以及多级日志系统。

**你将学到**：
- 多级日志系统（DEBUG/INFO/WARN/ERROR）
- 动态配置更新
- 日志文件管理
- 配置验证和默认值

[开始Lab 2 →](./lab2-config-logging/)

### Lab 3: IEC104模拟器组件 ⭐⭐
**时长**: 60分钟  
**难度**: 中级

部署IEC104协议模拟器，模拟风电和储能设备数据。

**你将学到**：
- IEC 60870-5-104协议基础
- TCP服务器实现
- 模拟数据生成
- 工业协议组件开发

[开始Lab 3 →](./lab3-iec104-simulator/)

### Lab 4: IEC104数据采集组件 ⭐⭐⭐
**时长**: 90分钟  
**难度**: 高级

部署完整的数据采集程序，实现与模拟器的通信和数据处理。

**你将学到**：
- IEC104客户端实现
- 组件间依赖管理
- 数据采集和处理
- 本地数据存储

[开始Lab 4 →](./lab4-iec104-collector/)

### Lab 5: AWS IoT Core集成 ⭐⭐⭐
**时长**: 60分钟  
**难度**: 高级

将采集的数据发送到AWS IoT Core，实现云边数据同步。

**你将学到**：
- Greengrass IPC通信
- MQTT消息发布
- IoT Core集成
- 云边协同架构

[开始Lab 5 →](./lab5-iot-integration/)

## 前置条件

### 必需
- AWS账号（具有IoT和Greengrass权限）
- Linux环境（Ubuntu 20.04+推荐）
- 基本的Linux命令行知识
- 基本的C++编程知识

### 推荐
- Docker基础知识
- AWS CLI使用经验
- 工业协议基础了解

## 环境准备

### 1. 安装AWS CLI

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### 2. 配置AWS凭证

```bash
aws configure
```

### 3. 安装Greengrass Core

参考[官方文档](https://docs.aws.amazon.com/greengrass/v2/developerguide/getting-started.html)安装Greengrass Core v2。

快速安装：
```bash
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > greengrass-nucleus-latest.zip
unzip greengrass-nucleus-latest.zip -d GreengrassInstaller
sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
  -jar ./GreengrassInstaller/lib/Greengrass.jar \
  --aws-region us-east-1 \
  --thing-name MyGreengrassCore \
  --thing-group-name MyGreengrassCoreGroup \
  --component-default-user ggc_user:ggc_group \
  --provision true \
  --setup-system-service true
```

### 4. 安装开发工具

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake git python3-pip
pip3 install pyyaml
```

### 5. 创建S3存储桶

```bash
export COMPONENT_BUCKET=my-greengrass-components-$(date +%s)
aws s3 mb s3://${COMPONENT_BUCKET}
```

## 验证环境

```bash
# 检查Greengrass状态
sudo systemctl status greengrass

# 检查Greengrass CLI
sudo /greengrass/v2/bin/greengrass-cli component list

# 检查AWS CLI
aws sts get-caller-identity
```

## 获取Workshop代码

```bash
cd /home/ubuntu/iec104-greengrass/workshop
ls -la
```

## 学习路径

```
Lab 1 (Hello World)
    ↓
Lab 2 (配置和日志)
    ↓
Lab 3 (IEC104模拟器)
    ↓
Lab 4 (数据采集)
    ↓
Lab 5 (IoT Core集成)
```

## 故障排除

### Greengrass无法启动

```bash
# 查看日志
sudo journalctl -u greengrass -f

# 检查配置
sudo cat /greengrass/v2/config/effectiveConfig.yaml
```

### 权限问题

```bash
# 确保Greengrass用户有正确权限
sudo usermod -aG docker ggc_user
```

### 网络问题

确保设备可以访问：
- AWS IoT Core endpoint
- S3 endpoint
- Greengrass服务endpoint

## 资源

- [AWS IoT Greengrass文档](https://docs.aws.amazon.com/greengrass/)
- [IEC 60870-5-104协议](https://en.wikipedia.org/wiki/IEC_60870-5)
- [Workshop反馈](https://github.com/your-repo/issues)

## 支持

遇到问题？
- 查看各Lab的故障排除章节
- 提交Issue到GitHub
- 联系Workshop讲师

---

准备好了吗？[开始Lab 1 →](./lab1-hello-world/)
