# Lab 2 Workshop 向导: 配置管理和日志系统

## 🎯 实验目标

通过本实验,你将学习:
- 实现多级日志系统 (DEBUG/INFO/WARN/ERROR)
- 管理本地日志文件输出和格式化
- 理解 Greengrass 配置管理机制
- 使用 LogManager 组件上传日志到 CloudWatch
- 在 CloudWatch 控制台实时查看和分析日志

**预计时间**: 90 分钟  
**难度级别**: ⭐⭐⭐ 中级

## 📋 前置条件

### 必需环境
- ✅ 完成 Lab 1
- ✅ 理解 C++ 类和对象
- ✅ 了解日志系统的基本概念
- ✅ AWS 账号具有 CloudWatch Logs 权限

### 验证环境

```bash
# 检查 Greengrass 状态
sudo systemctl status greengrass

# 检查 CloudWatch Logs 权限
aws logs describe-log-groups --region ${AWS_REGION} --max-items 1
```

## 🏗️ 架构概览

### 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Cloud                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              CloudWatch Logs                            │    │
│  │  ┌──────────────────────────────────────────────────┐  │    │
│  │  │  Log Group: /aws/greengrass/UserComponent/       │  │    │
│  │  │             cn-north-1/com.example.ConfigDemo    │  │    │
│  │  │                                                   │  │    │
│  │  │  Log Streams:                                    │  │    │
│  │  │  - GreengrassQuickStartCore-xxx_2026_01_22      │  │    │
│  │  │                                                   │  │    │
│  │  │  [DEBUG] Loop iteration 1                       │  │    │
│  │  │  [INFO] Hello from Lab 2!                       │  │    │
│  │  │  [WARN] Counter reached threshold               │  │    │
│  │  └──────────────────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────────────────┘    │
│                              ▲                                   │
│                              │ 上传日志                          │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│         Greengrass Core Device                                   │
│                              │                                   │
│  ┌──────────────────────────┴─────────────────────────────┐    │
│  │  aws.greengrass.LogManager (系统组件)                  │    │
│  │  - 监控组件日志文件                                     │    │
│  │  - 定期上传到 CloudWatch                               │    │
│  │  - 管理本地日志轮转                                     │    │
│  └──────────────────────────┬─────────────────────────────┘    │
│                              │ 读取日志                          │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  com.example.ConfigDemo (用户组件)                     │    │
│  │                                                         │    │
│  │  ┌──────────────────────────────────────────────┐     │    │
│  │  │  Logger 类                                    │     │    │
│  │  │  - 输出到 stdout (被 Greengrass 捕获)        │     │    │
│  │  │  - 输出到本地文件                            │     │    │
│  │  └──────────────────────────────────────────────┘     │    │
│  │                                                         │    │
│  │  日志输出:                                              │    │
│  │  → stdout → /greengrass/v2/logs/                      │    │
│  │             com.example.ConfigDemo.log                 │    │
│  │  → 本地文件 → /tmp/lab2-config-demo.log               │    │
│  └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 核心概念

#### 1. 日志级别 (Log Level)

| 级别 | 数值 | 用途 | 示例 |
|------|------|------|------|
| **DEBUG** | 0 | 详细调试信息 | 循环迭代、变量值 |
| **INFO** | 1 | 一般信息 | 组件启动、正常操作 |
| **WARN** | 2 | 警告信息 | 阈值达到、潜在问题 |
| **ERROR** | 3 | 错误信息 | 异常、失败操作 |

**日志过滤机制**:
- 设置级别为 INFO: 只显示 INFO、WARN、ERROR
- 设置级别为 WARN: 只显示 WARN、ERROR
- 设置级别为 DEBUG: 显示所有日志

#### 2. Logger 类设计

```
Logger 类
├── 日志级别管理
│   └── 过滤低于当前级别的日志
├── 双输出通道
│   ├── 控制台输出 (stdout)
│   └── 文件输出
├── 时间戳格式化
│   └── [YYYY-MM-DD HH:MM:SS]
└── 便捷方法
    ├── debug()
    ├── info()
    ├── warn()
    └── error()
```

#### 3. Greengrass 日志管理

```
组件输出 (stdout/stderr)
  ↓
Greengrass Nucleus 捕获
  ↓
写入本地日志文件
  /greengrass/v2/logs/<ComponentName>.log
  ↓
LogManager 组件监控
  ↓
上传到 CloudWatch Logs
```

## 📁 项目结构

```
lab2-config-logging/
├── src/
│   └── config_demo.cpp       # C++ 源代码 (包含 Logger 类)
├── CMakeLists.txt             # CMake 构建配置
├── recipe.yaml                # Greengrass 组件配置
├── config.json                # 示例配置文件
├── build.sh                   # 构建脚本
├── package.sh                 # 打包脚本
├── deploy.sh                  # 部署脚本
└── test-local.sh              # 本地测试脚本
```

## 实验分为两个部分

### Part 1: 本地日志系统 (步骤 1-6)
- 理解 Logger 类实现
- 本地构建和测试
- 配置参数管理
- 部署到 Greengrass

### Part 2: 云端日志集成 (步骤 7-10)
- 部署 LogManager 组件
- 配置 CloudWatch 上传
- 实时查看云端日志
- 日志分析和搜索


---

# Part 1: 本地日志系统

## 🔧 实验步骤

### 步骤 1: 准备实验环境

#### 1.1 进入实验目录

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab2-config-logging
```

#### 1.2 设置环境变量

```bash
# 设置 AWS 区域
export AWS_REGION="cn-north-1"

# 使用之前创建的 S3 存储桶
export COMPONENT_BUCKET="iec104-greengrass-components-<your-timestamp>"

# 设置 Greengrass Thing 名称
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"

# 获取账户 ID
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 设置组件版本
export VERSION="1.0.1"
export COMPONENT_NAME="com.example.ConfigDemo"
```

---

### 步骤 2: 理解 Logger 类实现

#### 2.1 Logger 类核心设计

Logger 类提供了一个简单但功能完整的日志系统:

**主要特性**:
- ✅ 多级日志 (DEBUG/INFO/WARN/ERROR)
- ✅ 日志级别过滤
- ✅ 双输出通道 (控制台 + 文件)
- ✅ 时间戳格式化
- ✅ 自动刷新到磁盘

**日志格式**:
```
[2026-01-22 03:20:00] [INFO] Hello from Lab 2!
 ↑ 时间戳              ↑ 级别  ↑ 消息内容
```

#### 2.2 日志级别过滤机制

```
设置级别: INFO
         ↓
┌────────┴────────┐
│  过滤规则:       │
│  DEBUG → 丢弃   │
│  INFO  → 输出   │
│  WARN  → 输出   │
│  ERROR → 输出   │
└─────────────────┘
```

**工作原理**:
1. 每个日志级别有一个数值 (DEBUG=0, INFO=1, WARN=2, ERROR=3)
2. 只输出级别 >= 当前设置级别的日志
3. 例如: 设置为 INFO(1), 则 DEBUG(0) 被过滤, INFO/WARN/ERROR 被输出

#### 2.3 查看源代码结构

```bash
# 查看 Logger 类定义
grep -A 20 "class Logger" src/config_demo.cpp

# 查看日志输出方法
grep -A 10 "void log(" src/config_demo.cpp
```

---

### 步骤 3: 本地构建和测试

#### 3.1 构建组件

```bash
# 使用构建脚本
./build.sh

# 验证构建结果
ls -lh build/config_demo
file build/config_demo
```

**预期输出**:
```
build/config_demo: ELF 64-bit LSB executable, ARM aarch64
```

#### 3.2 本地测试

**使用测试脚本**:

```bash
# 运行测试脚本 (后台运行 30 秒)
./test-local.sh
```

**预期输出**:
```
[2026-01-22 03:20:00] [INFO] ConfigDemo component starting...
[2026-01-22 03:20:00] [INFO] Configuration loaded from config.json
[2026-01-22 03:20:00] [DEBUG] Debug: Loop iteration 1
[2026-01-22 03:20:00] [INFO] Hello from Lab 2!
[2026-01-22 03:20:00] [INFO] Component running for 0 seconds
[2026-01-22 03:20:05] [DEBUG] Debug: Loop iteration 2
[2026-01-22 03:20:05] [INFO] Hello from Lab 2!
[2026-01-22 03:20:05] [WARN] Counter reached threshold: 10
```

**手动测试**:

```bash
# 前台运行 (按 Ctrl+C 停止)
./build/config_demo config.json

# 查看日志文件
tail -f /tmp/lab2-test.log
```

#### 3.3 实验: 修改日志级别

**实验 1: 设置为 WARN 级别**

```bash
# 编辑配置文件
nano config.json

# 修改 logLevel
{
  "logLevel": "WARN",
  "message": "Testing WARN level",
  "interval": 5
}

# 运行
./build/config_demo config.json
```

**观察结果**:
- ❌ DEBUG 日志不显示
- ❌ INFO 日志不显示
- ✅ WARN 日志显示
- ✅ ERROR 日志显示

**实验 2: 设置为 DEBUG 级别**

```bash
# 修改配置
{
  "logLevel": "DEBUG",
  "message": "Testing DEBUG level",
  "interval": 3
}

# 运行
./build/config_demo config.json
```

**观察结果**:
- ✅ 所有级别的日志都显示
- ✅ 可以看到详细的调试信息

---

### 步骤 4: 理解配置参数

#### 4.1 查看配置文件

```bash
cat config.json | jq '.'
```

**配置文件示例**:
```json
{
  "message": "Hello from Lab 2!",
  "interval": 5,
  "logLevel": "INFO",
  "logToConsole": true,
  "logToFile": true,
  "logFilePath": "/tmp/lab2-config-demo.log",
  "counterThreshold": 10
}
```

#### 4.2 配置参数详解

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `message` | string | "Hello from Lab 2!" | 输出的消息内容 |
| `interval` | int | 5 | 输出间隔 (秒) |
| `logLevel` | string | "INFO" | 日志级别: DEBUG/INFO/WARN/ERROR |
| `logToConsole` | bool | true | 是否输出到控制台 (stdout) |
| `logToFile` | bool | true | 是否输出到文件 |
| `logFilePath` | string | "/tmp/lab2-config-demo.log" | 日志文件路径 |
| `counterThreshold` | int | 10 | 计数器阈值 (触发 WARN) |

#### 4.3 配置与日志输出的关系

```
配置文件 (config.json)
  ↓
loadConfig() 函数读取
  ↓
创建 Logger 对象
  ├── logLevel → 设置过滤级别
  ├── logToConsole → 启用/禁用控制台输出
  ├── logToFile → 启用/禁用文件输出
  └── logFilePath → 设置文件路径
  ↓
Logger 根据配置输出日志
```

---

### 步骤 5: 打包和上传组件

#### 5.1 理解组件版本管理 ⚠️ 重要

**版本号必须在多个位置保持一致**:

1. **Recipe 中的 ComponentVersion**
```yaml
ComponentVersion: "1.0.1"
```

2. **Recipe 中的 Artifacts URI** (两处)
```yaml
Artifacts:
  - URI: "s3://bucket/com.example.ConfigDemo/1.0.1/com.example.ConfigDemo-1.0.1.zip"
         #                                  ↑ 版本1                            ↑ 版本2
```

3. **Recipe 中的执行路径**
```yaml
Install:
  Script: |
    chmod +x {artifacts:decompressedPath}/com.example.ConfigDemo-1.0.1/config_demo/config_demo
                                                                # ↑ 版本3
Run:
  Script: |
    {artifacts:decompressedPath}/com.example.ConfigDemo-1.0.1/config_demo/config_demo
                                                      # ↑ 版本4
```

#### 5.2 理解 ZIP 文件结构 ⚠️ 关键

**正确的 ZIP 结构**:
```
com.example.ConfigDemo-1.0.1.zip
└── config_demo/              ← 直接包含内容目录
    └── config_demo           ← 二进制文件
```

**错误的 ZIP 结构** (会导致路径不匹配):
```
com.example.ConfigDemo-1.0.1.zip
└── com.example.ConfigDemo-1.0.1/    ← 多余的顶层目录
    └── config_demo/
        └── config_demo
```

**Greengrass 解压后的路径**:
```
/greengrass/v2/packages/artifacts-unarchived/
└── com.example.ConfigDemo/
    └── 1.0.1/
        └── com.example.ConfigDemo-1.0.1/    ← ZIP 文件名作为目录
            └── config_demo/                  ← ZIP 内容
                └── config_demo               ← 二进制文件
```

因此 Recipe 中的路径应该是:
```
{artifacts:decompressedPath}/com.example.ConfigDemo-1.0.1/config_demo/config_demo
```

#### 5.3 执行打包

```bash
# 使用打包脚本
./package.sh
```

**打包脚本做了什么**:
1. 创建临时目录结构
2. 复制二进制文件
3. 设置执行权限
4. 创建 ZIP 包 (正确的结构)
5. 转换 Recipe 为 JSON

#### 5.4 验证打包结果

```bash
# 查看 ZIP 包内容
unzip -l artifacts/com.example.ConfigDemo-${VERSION}.zip
```

**预期输出**:
```
Archive:  artifacts/com.example.ConfigDemo-1.0.1.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  2026-01-22 04:19   config_demo/
   132928  2026-01-22 04:19   config_demo/config_demo
---------                     -------
   132928                     2 files
```

✅ **正确**: 直接是 `config_demo/` 目录  
❌ **错误**: 如果看到 `com.example.ConfigDemo-1.0.1/config_demo/`

#### 5.5 上传到 S3

**使用 AWS CLI**:

```bash
# 上传 ZIP 包
aws s3 cp artifacts/com.example.ConfigDemo-${VERSION}.zip \
  s3://${COMPONENT_BUCKET}/com.example.ConfigDemo/${VERSION}/ \
  --region ${AWS_REGION}

# 验证上传成功
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.ConfigDemo/${VERSION}/ \
  --region ${AWS_REGION}
```

**预期输出**:
```
2026-01-22 04:20:00     132928 com.example.ConfigDemo-1.0.1.zip
```

**使用 AWS 管理控制台**:

1. 打开 [S3 控制台](https://console.amazonaws.cn/s3/)
2. 点击你的存储桶
3. 创建文件夹: `com.example.ConfigDemo/1.0.1/`
4. 上传 `artifacts/com.example.ConfigDemo-1.0.1.zip`

![上传到 S3](images/s3-upload-configdemo.png)
*截图位置: 上传 ConfigDemo 组件*

#### 5.6 更新 Recipe 中的 S3 路径

```bash
# 使用 sed 替换 S3 路径
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" \
  artifacts/recipe.json > artifacts/recipe-updated.json

# 验证替换结果
grep "URI" artifacts/recipe-updated.json
```

---

### 步骤 6: 注册和部署组件

#### 6.1 注册组件版本

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
    "arn": "arn:aws-cn:greengrass:cn-north-1:123456789012:components:com.example.ConfigDemo:versions:1.0.1",
    "componentName": "com.example.ConfigDemo",
    "componentVersion": "1.0.1",
    "creationTimestamp": "2026-01-22T04:22:00.000000+00:00",
    "status": {
        "componentState": "REQUESTED"
    }
}
```

**使用 AWS 管理控制台**:

1. 打开 [AWS IoT 控制台](https://console.amazonaws.cn/iot/)
2. 左侧菜单: **Manage** → **Greengrass devices** → **Components**
3. 点击 **Create component**
4. 选择 **Enter recipe as JSON**
5. 粘贴 `artifacts/recipe-updated.json` 的内容
6. 点击 **Create component**

![创建 ConfigDemo 组件](images/create-configdemo.png)
*截图位置: 创建组件界面*

#### 6.2 部署组件

**使用 AWS CLI**:

```bash
# 创建部署
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-Lab2-$(date +%s)" \
  --components '{
    "com.example.ConfigDemo": {
      "componentVersion": "'"${VERSION}"'",
      "configurationUpdate": {
        "merge": "{\"message\":\"Lab 2 is working!\",\"interval\":5,\"logLevel\":\"DEBUG\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**预期输出**:
```json
{
    "deploymentId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111",
    "iotJobId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE22222"
}
```

```bash
# 保存部署 ID
export DEPLOYMENT_ID="<your-deployment-id>"
```

**使用 AWS 管理控制台**:

1. 在 **Core devices** 页面,点击你的设备
2. 点击 **Deploy** 按钮
3. 选择 **Revise deployment**
4. 添加组件: `com.example.ConfigDemo`
5. 选择版本: `1.0.1`
6. 配置组件:
```json
{
  "message": "Lab 2 is working!",
  "interval": 5,
  "logLevel": "DEBUG"
}
```
7. 点击 **Deploy**

![部署 ConfigDemo](images/deploy-configdemo.png)
*截图位置: 部署配置界面*

#### 6.3 监控部署状态

**使用 AWS CLI**:

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

**使用 AWS 管理控制台**:

1. 在设备详情页面
2. 点击 **Deployments** 标签
3. 查看最新部署状态

![部署状态](images/deployment-status-configdemo.png)
*截图位置: 部署状态监控*

#### 6.4 验证组件运行

```bash
# 查看组件日志
sudo tail -f /greengrass/v2/logs/com.example.ConfigDemo.log
```

**预期输出**:
```
2026-01-22T04:22:33.000Z [INFO] (Copier) com.example.ConfigDemo: stdout. [INFO] ConfigDemo component starting...
2026-01-22T04:22:33.100Z [INFO] (Copier) com.example.ConfigDemo: stdout. [INFO] Configuration loaded from /tmp/config.json
2026-01-22T04:22:33.200Z [INFO] (Copier) com.example.ConfigDemo: stdout. [DEBUG] Debug: Loop iteration 1
2026-01-22T04:22:33.300Z [INFO] (Copier) com.example.ConfigDemo: stdout. [INFO] Lab 2 is working!
2026-01-22T04:22:33.400Z [INFO] (Copier) com.example.ConfigDemo: stdout. [INFO] Component running for 0 seconds
```

```bash
# 检查组件状态
sudo /greengrass/v2/bin/greengrass-cli component list | grep -A 3 ConfigDemo
```

**预期输出**:
```
Component Name: com.example.ConfigDemo
    Version: 1.0.1
    State: RUNNING
    Configuration: {"message":"Lab 2 is working!","interval":5,"logLevel":"DEBUG"}
```

#### 6.5 验证文件路径

```bash
# 查看实际部署的文件
sudo ls -la /greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/${VERSION}/

# 查看二进制文件
sudo find /greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/${VERSION}/ \
  -name config_demo -type f
```

**预期路径**:
```
/greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/1.0.1/
  com.example.ConfigDemo-1.0.1/config_demo/config_demo
```

#### 6.6 配置更新实验

**实验 1: 修改日志级别为 WARN**

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-LogLevel-WARN-$(date +%s)" \
  --components '{
    "com.example.ConfigDemo": {
      "componentVersion": "'"${VERSION}"'",
      "configurationUpdate": {
        "merge": "{\"logLevel\":\"WARN\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**观察效果**:
```bash
sudo tail -f /greengrass/v2/logs/com.example.ConfigDemo.log
```

- ❌ DEBUG 日志不再显示
- ❌ INFO 日志不再显示
- ✅ 只显示 WARN 和 ERROR 级别

**实验 2: 修改输出间隔**

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-Interval-10s-$(date +%s)" \
  --components '{
    "com.example.ConfigDemo": {
      "componentVersion": "'"${VERSION}"'",
      "configurationUpdate": {
        "merge": "{\"interval\":10,\"logLevel\":\"INFO\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**观察效果**:
- 日志输出间隔从 5 秒变为 10 秒
- 无需重启组件,配置动态生效


---

# Part 2: 云端日志集成

### 步骤 7: 理解 Greengrass LogManager 组件

#### 7.1 LogManager 组件的作用

**LogManager** 是 Greengrass 的系统组件,负责:
- 📤 自动上传组件日志到 CloudWatch Logs
- 🔄 管理本地日志轮转 (防止磁盘占满)
- 📊 支持配置每个组件的日志级别和上传策略
- 🎯 无需修改组件代码

#### 7.2 日志上传流程

```
组件输出日志 (stdout/stderr)
  ↓
Greengrass 捕获并写入本地文件
  ↓
/greengrass/v2/logs/com.example.ConfigDemo.log
  ↓
LogManager 监控并读取
  ↓
批量上传到 CloudWatch Logs
  ↓
CloudWatch Log Group/Stream
```

#### 7.3 LogManager 配置结构

```json
{
  "logsUploaderConfiguration": {
    "systemLogsConfiguration": {
      "uploadToCloudWatch": "true",
      "minimumLogLevel": "INFO"
    },
    "componentLogsConfigurationMap": {
      "com.example.ConfigDemo": {
        "minimumLogLevel": "DEBUG",
        "diskSpaceLimit": "10",
        "diskSpaceLimitUnit": "MB",
        "deleteLogFileAfterCloudUpload": "false"
      }
    }
  }
}
```

**字段说明**:

| 字段 | 类型 | 说明 |
|------|------|------|
| `uploadToCloudWatch` | string | "true" 或 "false" |
| `minimumLogLevel` | string | DEBUG/INFO/WARN/ERROR |
| `diskSpaceLimit` | string | 本地日志磁盘限制 |
| `diskSpaceLimitUnit` | string | KB/MB/GB |
| `deleteLogFileAfterCloudUpload` | string | 上传后是否删除本地日志 |

---

### 步骤 8: 部署 LogManager 组件

#### 8.1 检查 IAM 权限

LogManager 需要权限上传日志到 CloudWatch:

**所需权限**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws-cn:logs:*:*:log-group:/aws/greengrass/*"
    }
  ]
}
```

**检查当前权限**:

```bash
# 查看 Greengrass Token Exchange Role
aws iot describe-role-alias \
  --role-alias GreengrassV2TokenExchangeRoleAlias \
  --region ${AWS_REGION} \
  --query 'roleAliasDescription.roleArn' \
  --output text
```

> **注意**: 在生产环境中,需要将 CloudWatch Logs 权限附加到 Token Exchange Role。

#### 8.2 检查 Nucleus 版本兼容性

```bash
# 查看当前 Nucleus 版本
sudo /greengrass/v2/bin/greengrass-cli component list | grep Nucleus
```

**LogManager 版本兼容性**:

| Nucleus 版本 | 推荐 LogManager 版本 |
|-------------|---------------------|
| 2.16.x | 2.3.11 |
| 2.15.x | 2.3.7 |
| 2.14.x | 2.3.0 |

#### 8.3 部署 ConfigDemo + LogManager

**使用 AWS CLI**:

```bash
# 创建部署 (同时部署 ConfigDemo 和 LogManager)
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "Lab2-ConfigDemo-with-LogManager-$(date +%s)" \
  --components '{
    "aws.greengrass.LogManager": {
      "componentVersion": "2.3.11",
      "configurationUpdate": {
        "merge": "{\"logsUploaderConfiguration\":{\"systemLogsConfiguration\":{\"uploadToCloudWatch\":\"true\",\"minimumLogLevel\":\"INFO\"},\"componentLogsConfigurationMap\":{\"com.example.ConfigDemo\":{\"minimumLogLevel\":\"DEBUG\",\"diskSpaceLimit\":\"10\",\"diskSpaceLimitUnit\":\"MB\",\"deleteLogFileAfterCloudUpload\":\"false\"}}}}"
      }
    },
    "com.example.ConfigDemo": {
      "componentVersion": "'"${VERSION}"'",
      "configurationUpdate": {
        "merge": "{\"message\":\"Lab 2 with CloudWatch!\",\"interval\":5,\"logLevel\":\"DEBUG\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**配置说明**:
- LogManager 版本: 2.3.11
- ConfigDemo 日志级别: DEBUG (上传所有日志)
- 本地日志限制: 10MB
- 上传后保留本地日志

**使用 AWS 管理控制台**:

1. 在 Core device 详情页面,点击 **Deploy**
2. 选择 **Revise deployment**
3. 添加组件: `aws.greengrass.LogManager`
   - 版本: `2.3.11`
   - 配置:
```json
{
  "logsUploaderConfiguration": {
    "systemLogsConfiguration": {
      "uploadToCloudWatch": "true",
      "minimumLogLevel": "INFO"
    },
    "componentLogsConfigurationMap": {
      "com.example.ConfigDemo": {
        "minimumLogLevel": "DEBUG",
        "diskSpaceLimit": "10",
        "diskSpaceLimitUnit": "MB",
        "deleteLogFileAfterCloudUpload": "false"
      }
    }
  }
}
```
4. 确保 `com.example.ConfigDemo` 也在部署中
5. 点击 **Deploy**

![部署 LogManager](images/deploy-logmanager.png)
*截图位置: 部署 LogManager 配置*

#### 8.4 验证部署状态

```bash
# 查看组件状态
sudo /greengrass/v2/bin/greengrass-cli component list
```

**预期输出**:
```
Component Name: aws.greengrass.LogManager
    Version: 2.3.11
    State: RUNNING
Component Name: com.example.ConfigDemo
    Version: 1.0.1
    State: RUNNING
```

```bash
# 查看 LogManager 日志
sudo tail -f /greengrass/v2/logs/aws.greengrass.LogManager.log
```

**预期看到**:
```
Uploading logs to CloudWatch...
Successfully uploaded log stream...
```

---

### 步骤 9: 在 CloudWatch 查看日志

#### 9.1 理解 CloudWatch Logs 结构

```
Log Group (日志组)
  /aws/greengrass/UserComponent/cn-north-1/com.example.ConfigDemo
    ↓
  Log Stream (日志流)
    GreengrassQuickStartCore-xxx_2026_01_22
      ↓
    Log Events (日志事件)
      [2026-01-22 04:30:00] [DEBUG] Loop iteration 1
      [2026-01-22 04:30:00] [INFO] Lab 2 with CloudWatch!
```

**命名规则**:
- Log Group: `/aws/greengrass/UserComponent/<region>/<component-name>`
- Log Stream: `<thing-name>_<date>`

#### 9.2 使用 AWS CLI 查看日志

**列出 Log Groups**:

```bash
# 查看所有 Greengrass 日志组
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/greengrass" \
  --region ${AWS_REGION} \
  --query 'logGroups[*].logGroupName' \
  --output table
```

**预期输出**:
```
-----------------------------------------------------------------
|                      DescribeLogGroups                        |
+---------------------------------------------------------------+
|  /aws/greengrass/UserComponent/cn-north-1/com.example.ConfigDemo  |
|  /aws/greengrass/GreengrassSystemComponent/cn-north-1/System  |
+---------------------------------------------------------------+
```

**列出 Log Streams**:

```bash
# 设置 Log Group 名称
export LOG_GROUP="/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo"

# 查看 Log Streams
aws logs describe-log-streams \
  --log-group-name "${LOG_GROUP}" \
  --region ${AWS_REGION} \
  --order-by LastEventTime \
  --descending \
  --max-items 5 \
  --query 'logStreams[*].[logStreamName,lastEventTime]' \
  --output table
```

**获取最新日志**:

```bash
# 获取最新的 Log Stream 名称
export LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name "${LOG_GROUP}" \
  --region ${AWS_REGION} \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text)

echo "Log Stream: ${LOG_STREAM}"

# 查看最新 20 条日志
aws logs get-log-events \
  --log-group-name "${LOG_GROUP}" \
  --log-stream-name "${LOG_STREAM}" \
  --region ${AWS_REGION} \
  --limit 20 \
  --query 'events[*].message' \
  --output text
```

**预期输出**:
```
[2026-01-22 04:30:00] [DEBUG] Debug: Loop iteration 1
[2026-01-22 04:30:00] [INFO] Lab 2 with CloudWatch!
[2026-01-22 04:30:00] [INFO] Component running for 0 seconds
[2026-01-22 04:30:05] [DEBUG] Debug: Loop iteration 2
[2026-01-22 04:30:05] [INFO] Lab 2 with CloudWatch!
[2026-01-22 04:30:05] [WARN] Counter reached threshold: 10
```

#### 9.3 使用 AWS 管理控制台查看日志

**步骤**:

1. 打开 [CloudWatch 控制台](https://console.amazonaws.cn/cloudwatch/)
2. 左侧菜单: **Logs** → **Log groups**
3. 搜索: `/aws/greengrass/UserComponent`
4. 点击: `/aws/greengrass/UserComponent/cn-north-1/com.example.ConfigDemo`

![CloudWatch Log Groups](images/cloudwatch-log-groups.png)
*截图位置: CloudWatch Log Groups 列表*

5. 点击最新的 Log Stream (按时间排序)
6. 查看实时日志

![CloudWatch Log Stream](images/cloudwatch-log-stream.png)
*截图位置: CloudWatch Log Stream 详情*

**实时查看日志**:

1. 在 Log Stream 页面
2. 点击右上角的 **Actions** → **View in Logs Insights**
3. 或者启用 **Live tail** 功能实时查看

![CloudWatch Live Tail](images/cloudwatch-live-tail.png)
*截图位置: CloudWatch Live Tail 功能*

---

### 步骤 10: 日志分析和搜索

#### 10.1 使用 CloudWatch Logs Insights

**CloudWatch Logs Insights** 提供强大的日志查询和分析功能。

**打开 Logs Insights**:

1. 在 CloudWatch 控制台
2. 左侧菜单: **Logs** → **Logs Insights**
3. 选择 Log Group: `/aws/greengrass/UserComponent/cn-north-1/com.example.ConfigDemo`
4. 设置时间范围: 最近 1 小时

![CloudWatch Logs Insights](images/cloudwatch-logs-insights.png)
*截图位置: Logs Insights 界面*

#### 10.2 常用查询示例

**查询 1: 查看所有 WARN 级别的日志**

```
fields @timestamp, @message
| filter @message like /\[WARN\]/
| sort @timestamp desc
| limit 20
```

**查询 2: 统计各日志级别的数量**

```
fields @message
| parse @message /\[(?<level>DEBUG|INFO|WARN|ERROR)\]/
| stats count() by level
```

**查询 3: 查看特定时间范围的日志**

```
fields @timestamp, @message
| filter @timestamp >= 1737518400000 and @timestamp <= 1737522000000
| sort @timestamp desc
```

**查询 4: 搜索包含特定关键字的日志**

```
fields @timestamp, @message
| filter @message like /threshold/
| sort @timestamp desc
| limit 50
```

**查询 5: 计算日志输出频率**

```
fields @timestamp
| stats count() by bin(5m)
```

#### 10.3 使用 AWS CLI 执行查询

```bash
# 启动查询
export QUERY_ID=$(aws logs start-query \
  --log-group-name "${LOG_GROUP}" \
  --region ${AWS_REGION} \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /\[WARN\]/ | sort @timestamp desc | limit 20' \
  --query 'queryId' \
  --output text)

echo "Query ID: ${QUERY_ID}"

# 等待查询完成
sleep 5

# 获取查询结果
aws logs get-query-results \
  --query-id ${QUERY_ID} \
  --region ${AWS_REGION}
```

#### 10.4 创建日志过滤器和告警

**创建 Metric Filter** (统计 ERROR 日志数量):

```bash
# 创建 Metric Filter
aws logs put-metric-filter \
  --log-group-name "${LOG_GROUP}" \
  --filter-name "ConfigDemo-ErrorCount" \
  --filter-pattern "[ERROR]" \
  --metric-transformations \
    metricName=ConfigDemoErrors,metricNamespace=Greengrass/ConfigDemo,metricValue=1 \
  --region ${AWS_REGION}
```

**使用控制台创建告警**:

1. 在 CloudWatch 控制台
2. 左侧菜单: **Alarms** → **All alarms**
3. 点击 **Create alarm**
4. 选择 Metric: `Greengrass/ConfigDemo` → `ConfigDemoErrors`
5. 设置条件: 当 ERROR 数量 > 5 时触发
6. 配置通知: SNS Topic
7. 点击 **Create alarm**

![CloudWatch Alarm](images/cloudwatch-alarm.png)
*截图位置: 创建 CloudWatch 告警*

#### 10.5 导出日志

**导出到 S3**:

1. 在 Log Group 页面
2. 点击 **Actions** → **Export data to Amazon S3**
3. 选择时间范围
4. 选择 S3 存储桶
5. 点击 **Export**

**使用 CLI 导出**:

```bash
# 创建导出任务
aws logs create-export-task \
  --log-group-name "${LOG_GROUP}" \
  --from $(date -d '1 day ago' +%s)000 \
  --to $(date +%s)000 \
  --destination ${COMPONENT_BUCKET} \
  --destination-prefix "greengrass-logs/" \
  --region ${AWS_REGION}
```


---

## 📚 核心概念总结

### 1. 日志级别层次

```
DEBUG (0)  ← 最详细
  ↓
INFO (1)   ← 一般信息
  ↓
WARN (2)   ← 警告
  ↓
ERROR (3)  ← 错误 (最严重)
```

**过滤规则**: 设置级别为 X, 则只输出级别 >= X 的日志

### 2. Logger 类关键方法

| 方法 | 说明 | 示例 |
|------|------|------|
| `debug(msg)` | 输出 DEBUG 级别日志 | `logger.debug("Loop iteration " + i)` |
| `info(msg)` | 输出 INFO 级别日志 | `logger.info("Component started")` |
| `warn(msg)` | 输出 WARN 级别日志 | `logger.warn("Threshold reached")` |
| `error(msg)` | 输出 ERROR 级别日志 | `logger.error("Failed to connect")` |

### 3. 日志输出路径

| 输出目标 | 路径 | 说明 |
|---------|------|------|
| **Greengrass 日志** | `/greengrass/v2/logs/<ComponentName>.log` | Nucleus 捕获的 stdout/stderr |
| **应用日志文件** | `/tmp/lab2-config-demo.log` | Logger 类直接写入 |
| **CloudWatch Logs** | `/aws/greengrass/UserComponent/<region>/<component>` | LogManager 上传 |

### 4. LogManager 配置参数

| 参数 | 类型 | 说明 | 推荐值 |
|------|------|------|--------|
| `uploadToCloudWatch` | string | 是否上传 | "true" |
| `minimumLogLevel` | string | 最低级别 | "DEBUG" (开发), "INFO" (生产) |
| `diskSpaceLimit` | string | 磁盘限制 | "10" |
| `diskSpaceLimitUnit` | string | 单位 | "MB" |
| `deleteLogFileAfterCloudUpload` | string | 上传后删除 | "false" (保留本地) |

### 5. CloudWatch Logs 查询语法

| 操作 | 语法 | 示例 |
|------|------|------|
| **过滤** | `filter @message like /pattern/` | `filter @message like /\[ERROR\]/` |
| **解析** | `parse @message /regex/` | `parse @message /\[(?<level>\w+)\]/` |
| **统计** | `stats count() by field` | `stats count() by level` |
| **排序** | `sort field desc` | `sort @timestamp desc` |
| **限制** | `limit N` | `limit 100` |

## 🎓 实验总结

通过本实验,你已经学会:

### ✅ 核心技能
- 实现多级日志系统 (DEBUG/INFO/WARN/ERROR)
- 管理本地日志文件输出和格式化
- 使用 Greengrass 配置管理动态更新参数
- 部署 LogManager 组件上传日志到 CloudWatch
- 在 CloudWatch 控制台查看和分析日志
- 使用 Logs Insights 进行高级日志查询
- 创建日志过滤器和告警

### ✅ 关键概念
- 日志级别过滤机制
- Logger 类的设计和实现
- Greengrass 日志管理流程
- CloudWatch Logs 的结构和查询
- 组件版本和 ZIP 文件结构的重要性

### ✅ 最佳实践
- 在开发环境使用 DEBUG 级别,生产环境使用 INFO 级别
- 使用结构化日志格式 (时间戳 + 级别 + 消息)
- 配置合理的本地日志磁盘限制
- 使用 CloudWatch Logs Insights 进行日志分析
- 为关键错误设置 CloudWatch 告警

## 🔍 常见问题

### Q1: 为什么 CloudWatch 中看不到日志?

**检查步骤**:

1. 验证 LogManager 组件状态
```bash
sudo /greengrass/v2/bin/greengrass-cli component list | grep LogManager
```

2. 检查 LogManager 日志
```bash
sudo tail -100 /greengrass/v2/logs/aws.greengrass.LogManager.log
```

3. 验证 IAM 权限
```bash
# Token Exchange Role 需要 CloudWatch Logs 权限
aws iot describe-role-alias \
  --role-alias GreengrassV2TokenExchangeRoleAlias \
  --region ${AWS_REGION}
```

4. 检查网络连接
```bash
# 测试到 CloudWatch Logs 的连接
curl -I https://logs.${AWS_REGION}.amazonaws.com.cn
```

### Q2: 如何修改日志上传频率?

LogManager 默认每 5 秒检查一次日志文件。可以通过配置调整:

```json
{
  "periodicUploadIntervalSec": "300"
}
```

### Q3: 本地日志文件占用太多磁盘空间怎么办?

**方法 1**: 减小 diskSpaceLimit
```json
{
  "diskSpaceLimit": "5",
  "diskSpaceLimitUnit": "MB"
}
```

**方法 2**: 上传后删除本地日志
```json
{
  "deleteLogFileAfterCloudUpload": "true"
}
```

**方法 3**: 提高日志级别 (减少日志量)
```json
{
  "minimumLogLevel": "WARN"
}
```

### Q4: 如何查看历史日志?

**CloudWatch Logs 保留期限**:
- 默认: 永久保留
- 可配置: 1 天到 10 年

**设置保留期限**:
```bash
aws logs put-retention-policy \
  --log-group-name "${LOG_GROUP}" \
  --retention-in-days 7 \
  --region ${AWS_REGION}
```

### Q5: 组件部署失败,路径错误怎么办?

**常见原因**: ZIP 文件结构不正确

**检查步骤**:

1. 验证 ZIP 结构
```bash
unzip -l artifacts/com.example.ConfigDemo-${VERSION}.zip
```

2. 确保直接包含内容目录
```
✅ 正确:
com.example.ConfigDemo-1.0.1.zip
└── config_demo/
    └── config_demo

❌ 错误:
com.example.ConfigDemo-1.0.1.zip
└── com.example.ConfigDemo-1.0.1/
    └── config_demo/
        └── config_demo
```

3. 检查 Recipe 中的路径
```yaml
{artifacts:decompressedPath}/com.example.ConfigDemo-1.0.1/config_demo/config_demo
```

4. 验证实际部署路径
```bash
sudo find /greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/ -name config_demo -type f
```

### Q6: 如何批量查询多个组件的日志?

使用 Logs Insights 跨多个 Log Groups 查询:

```
fields @timestamp, @logStream, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

在查询界面选择多个 Log Groups。

## 📖 参考资料

### AWS 官方文档
- [AWS IoT Greengrass V2 日志管理](https://docs.aws.amazon.com/greengrass/v2/developerguide/monitor-logs.html)
- [LogManager 组件](https://docs.aws.amazon.com/greengrass/v2/developerguide/log-manager-component.html)
- [CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [CloudWatch Logs Insights 查询语法](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)

### 相关 Workshop
- [Lab 1: 部署第一个 Greengrass 组件](../lab1-hello-world/WORKSHOP.md) - 基础组件开发
- [Lab 3: IEC104 模拟器](../lab3-iec104-simulator/WORKSHOP.md) - Docker 组件部署
- [Lab 4: IEC104 数据采集器](../lab4-iec104-collector/WORKSHOP.md) - IPC 通信
- [Lab 5: IoT Core 集成](../lab5-iot-integration/WORKSHOP.md) - 云端集成

### 工具和库
- [nlohmann/json](https://github.com/nlohmann/json) - C++ JSON 库
- [AWS CLI 参考](https://docs.aws.amazon.com/cli/latest/reference/greengrassv2/)
- [CloudWatch Logs CLI](https://docs.aws.amazon.com/cli/latest/reference/logs/)

## 🎯 下一步

完成 Lab 2 后,建议继续:

1. **Lab 3: IEC104 模拟器**
   - 学习 Docker 组件部署
   - 理解容器化边缘应用
   - 实践工业协议模拟

2. **Lab 4: IEC104 数据采集器**
   - 学习 Greengrass IPC 通信
   - 实践组件间消息传递
   - 掌握数据采集和过滤

3. **Lab 5: IoT Core 集成**
   - 学习边缘到云数据传输
   - 实践 MQTT 消息发布
   - 掌握异步消息处理

## 📝 实验检查清单

完成以下检查项,确保实验成功:

- [ ] 成功构建 ConfigDemo 组件
- [ ] 本地测试日志输出正常
- [ ] 理解日志级别过滤机制
- [ ] 成功打包组件 (正确的 ZIP 结构)
- [ ] 成功上传到 S3
- [ ] 成功注册组件到 AWS Greengrass
- [ ] 成功部署组件到设备
- [ ] 能够动态更新配置 (日志级别、间隔等)
- [ ] 成功部署 LogManager 组件
- [ ] 在 CloudWatch 中看到日志
- [ ] 能够使用 Logs Insights 查询日志
- [ ] 理解 CloudWatch Logs 的结构和查询语法

---

**🎉 恭喜完成 Lab 2!**

你已经掌握了 Greengrass 组件的配置管理和日志系统,包括本地日志和云端日志集成。继续下一个实验,探索更多高级功能!

**问题反馈**: 如有问题,请联系 Workshop 讲师或查阅 [AWS 支持](https://aws.amazon.com/support/)。
