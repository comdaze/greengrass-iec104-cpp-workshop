# Lab 2: 配置管理和日志系统

## 学习目标

完成本实验后，你将能够：
- ✅ 实现多级日志系统（DEBUG/INFO/WARN/ERROR）
- ✅ 管理本地日志文件（输出、轮转、格式化）
- ✅ 理解Greengrass配置管理机制
- ✅ 使用LogManager组件上传日志到CloudWatch
- ✅ 在CloudWatch控制台实时查看和分析日志
- ✅ 配置日志过滤和搜索
- ✅ 设置CloudWatch日志告警

## 前置条件

- ✅ 完成Lab 1
- ✅ 理解C++类和对象
- ✅ 了解日志系统的基本概念
- ✅ 有CloudWatch Logs的基本了解（可选）

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Cloud                                     │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              CloudWatch Logs                            │    │
│  │  ┌──────────────────────────────────────────────────┐  │    │
│  │  │  Log Group: /aws/greengrass/UserComponent/       │  │    │
│  │  │             ap-northeast-1/com.example.ConfigDemo    │  │    │
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
│  │  - 定期上传到CloudWatch                                │    │
│  │  - 管理本地日志轮转                                     │    │
│  └──────────────────────────┬─────────────────────────────┘    │
│                              │ 读取日志                          │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  com.example.ConfigDemo (用户组件)                     │    │
│  │                                                         │    │
│  │  ┌──────────────────────────────────────────────┐     │    │
│  │  │  Logger类                                     │     │    │
│  │  │  - 输出到stdout (被Greengrass捕获)           │     │    │
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

## Lab 2 分为两个部分

### Part 1: 本地日志系统（步骤1-6）
- 实现Logger类
- 多级日志管理
- 本地文件输出
- 配置动态更新

### Part 2: 云端日志集成（步骤7-10）
- 部署LogManager组件
- 配置CloudWatch上传
- 实时查看云端日志
- 日志分析和告警

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab2-config-logging

# 本地测试
./test-local.sh

# 构建、打包、部署
./build.sh
./package.sh
```

---

# Part 1: 本地日志系统

## 步骤 1: 理解Logger类实现

### 1.1 查看源代码结构

```bash
cat src/config_demo.cpp | head -100
```

### 1.2 Logger类设计解析

**核心组件**：

```cpp
class Logger {
private:
    LogLevel level_;           // 当前日志级别
    bool console_enabled_;     // 是否输出到控制台
    bool file_enabled_;        // 是否输出到文件
    std::ofstream file_stream_; // 文件流

public:
    // 构造函数
    Logger(LogLevel level, bool console, bool file, const std::string& path);
    
    // 核心日志方法
    void log(LogLevel level, const std::string& message);
    
    // 便捷方法
    void debug(const std::string& msg);
    void info(const std::string& msg);
    void warn(const std::string& msg);
    void error(const std::string& msg);
};
```

**日志级别过滤机制**：
```cpp
void log(LogLevel level, const std::string& message) {
    if (level < level_) return;  // 过滤低于当前级别的日志
    
    // 格式化：[时间戳] [级别] 消息
    std::string log_line = "[" + getTimestamp() + "] [" + 
                          levelToString(level) + "] " + message;
    
    // 输出到控制台
    if (console_enabled_) {
        std::cout << log_line << std::endl;
    }
    
    // 输出到文件
    if (file_enabled_ && file_stream_.is_open()) {
        file_stream_ << log_line << std::endl;
        file_stream_.flush();  // 立即写入磁盘
    }
}
```

**思考问题**：
1. 为什么要调用`flush()`立即写入磁盘？
2. 如果不过滤日志级别会有什么问题？

## 步骤 2: 本地构建和测试

### 2.1 构建组件

```bash
./build.sh

# 查看生成的二进制
ls -lh build/config_demo
```

### 2.2 本地测试（不使用Greengrass）

```bash
# 方法1: 使用测试脚本
./test-local.sh
```

**预期输出**：
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

```bash
# 方法2: 手动运行
./build/config_demo config.json

# 查看日志文件
tail -f /tmp/lab2-test.log
```

### 2.3 实验：修改日志级别

```bash
# 编辑配置文件
nano config.json

# 修改logLevel为"WARN"
{
  "logLevel": "WARN",
  ...
}

# 重新运行
./build/config_demo config.json

# 观察：只看到WARN和ERROR级别的日志
```

## 步骤 3: 理解配置参数

### 3.1 查看配置文件

```bash
cat config.json | jq '.'
```

### 3.2 配置参数详解

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| message | string | "Hello from Lab 2!" | 输出的消息内容 |
| interval | int | 5 | 输出间隔（秒） |
| logLevel | string | "INFO" | 日志级别：DEBUG/INFO/WARN/ERROR |
| logToConsole | bool | true | 是否输出到控制台 |
| logToFile | bool | true | 是否输出到文件 |
| logFilePath | string | "/tmp/lab2-config-demo.log" | 日志文件路径 |
| counterThreshold | int | 10 | 计数器阈值（触发WARN） |

### 3.3 配置加载代码

```cpp
Config loadConfig(const std::string& configPath) {
    std::ifstream file(configPath);
    json j;
    file >> j;
    
    Config config;
    config.message = j.value("message", "Hello from Lab 2!");
    config.interval = j.value("interval", 5);
    
    // 日志级别字符串转枚举
    std::string level_str = j.value("logLevel", "INFO");
    if (level_str == "DEBUG") config.log_level = LogLevel::DEBUG;
    else if (level_str == "INFO") config.log_level = LogLevel::INFO;
    else if (level_str == "WARN") config.log_level = LogLevel::WARN;
    else if (level_str == "ERROR") config.log_level = LogLevel::ERROR;
    
    return config;
}
```

## 步骤 4: 打包和上传组件

### 4.1 理解组件版本和ZIP文件结构 ⚠️ 重要

**关键概念**：Greengrass组件的版本必须在Recipe和ZIP文件结构中保持一致。

#### 版本号的三个位置

1. **Recipe中的ComponentVersion**
```yaml
ComponentVersion: "1.0.3"
```

2. **Recipe中的Artifacts URI**
```yaml
Artifacts:
  - URI: "s3://bucket/com.example.ConfigDemo/1.0.3/com.example.ConfigDemo-1.0.3.zip"
```

3. **ZIP文件内部的目录结构**
```
com.example.ConfigDemo-1.0.3.zip
└── config_demo/
    └── config_demo (二进制文件)
```

#### ZIP文件结构规则 ⚠️

**错误示例**（会导致路径不匹配）：
```
❌ com.example.ConfigDemo-1.0.3.zip
   └── com.example.ConfigDemo-1.0.3/    # 多余的顶层目录
       └── config_demo/
           └── config_demo
```

**正确示例**：
```
✅ com.example.ConfigDemo-1.0.3.zip
   └── config_demo/                     # 直接包含内容
       └── config_demo
```

#### Greengrass解压路径

Greengrass会将ZIP文件解压到：
```
/greengrass/v2/packages/artifacts-unarchived/
  └── com.example.ConfigDemo/
      └── 1.0.3/
          └── com.example.ConfigDemo-1.0.3/  # 以ZIP文件名创建目录
              └── config_demo/                # ZIP内容
                  └── config_demo
```

因此Recipe中的路径应该是：
```yaml
{artifacts:decompressedPath}/com.example.ConfigDemo-1.0.3/config_demo/config_demo
```

### 4.2 打包组件（正确方法）

```bash
# 设置版本号
export VERSION="1.0.3"
export COMPONENT_NAME="com.example.ConfigDemo"

# 创建临时目录（不包含版本号前缀）
mkdir -p ${COMPONENT_NAME}-${VERSION}/config_demo

# 复制二进制文件
cp build/config_demo ${COMPONENT_NAME}-${VERSION}/config_demo/

# 设置执行权限
chmod +x ${COMPONENT_NAME}-${VERSION}/config_demo/config_demo

# 进入目录内部打包（关键步骤）
cd ${COMPONENT_NAME}-${VERSION}
zip -r ../${COMPONENT_NAME}-${VERSION}.zip .
cd ..

# 验证ZIP结构
unzip -l ${COMPONENT_NAME}-${VERSION}.zip
```

**预期输出**：
```
Archive:  com.example.ConfigDemo-1.0.3.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  2026-01-22 04:19   config_demo/
   132928  2026-01-22 04:19   config_demo/config_demo
---------                     -------
   132928                     2 files
```

### 4.3 上传到S3

```bash
# 使用之前创建的存储桶
export COMPONENT_BUCKET="iec104-greengrass-components-1769054416"
export AWS_REGION="ap-northeast-1"
export VERSION="1.0.3"

# 上传（注意路径包含版本号）
aws s3api put-object \
  --bucket ${COMPONENT_BUCKET} \
  --key ${COMPONENT_NAME}/${VERSION}/${COMPONENT_NAME}-${VERSION}.zip \
  --body ${COMPONENT_NAME}-${VERSION}.zip \
  --region ${AWS_REGION}

# 验证
aws s3 ls s3://${COMPONENT_BUCKET}/${COMPONENT_NAME}/${VERSION}/
```

### 4.4 更新Recipe版本

确保Recipe中的所有版本号一致：

```yaml
ComponentVersion: "1.0.3"  # ← 版本1

Lifecycle:
  Install:
    Script: |
      chmod +x {artifacts:decompressedPath}/com.example.ConfigDemo-1.0.3/config_demo/config_demo
                                                                    # ↑ 版本2
  Run:
    Script: |
      {artifacts:decompressedPath}/com.example.ConfigDemo-1.0.3/config_demo/config_demo
                                                        # ↑ 版本3

Artifacts:
  - URI: "s3://bucket/com.example.ConfigDemo/1.0.3/com.example.ConfigDemo-1.0.3.zip"
                                           # ↑ 版本4              ↑ 版本5
```

### 4.5 创建组件版本

```bash
# 创建组件版本
aws greengrassv2 create-component-version \
  --inline-recipe fileb://recipe.yaml \
  --region ${AWS_REGION} \
  --query '{ComponentName: componentName, ComponentVersion: componentVersion}' \
  --output json
```

**预期输出**：
```json
{
    "ComponentName": "com.example.ConfigDemo",
    "ComponentVersion": "1.0.3"
}
```

### 4.6 常见错误和解决方法

#### 错误1: Permission denied (exitCode=126)

**原因**：Recipe中的路径与实际文件路径不匹配

**症状**：
```
chmod: cannot access '/greengrass/v2/packages/artifacts-unarchived/
  com.example.ConfigDemo/1.0.3/com.example.ConfigDemo-1.0.3/config_demo/config_demo': 
  No such file or directory
```

**解决**：
1. 检查ZIP文件结构：`unzip -l com.example.ConfigDemo-1.0.3.zip`
2. 确保ZIP内容直接是`config_demo/config_demo`
3. 更新Recipe中的路径匹配实际结构

#### 错误2: 版本号不一致

**症状**：部署失败或找不到文件

**检查清单**：
- [ ] Recipe中的`ComponentVersion`
- [ ] S3 URI中的版本号（两处）
- [ ] Recipe中`{artifacts:decompressedPath}`后的路径
- [ ] ZIP文件名中的版本号

#### 错误3: ZIP文件双重嵌套

**错误的打包方式**：
```bash
# ❌ 错误：在外部打包，会包含顶层目录
zip -r com.example.ConfigDemo-1.0.3.zip com.example.ConfigDemo-1.0.3/
```

**正确的打包方式**：
```bash
# ✅ 正确：进入目录内部打包
cd com.example.ConfigDemo-1.0.3
zip -r ../com.example.ConfigDemo-1.0.3.zip .
cd ..
```

## 步骤 5: 部署到Greengrass

### 5.1 部署ConfigDemo组件

```bash
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VERSION="1.0.3"

aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-Lab2-v${VERSION}-$(date +%s)" \
  --components "{
    \"com.example.ConfigDemo\": {
      \"componentVersion\": \"${VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"message\\\":\\\"Lab 2 is working!\\\",\\\"interval\\\":5,\\\"logLevel\\\":\\\"DEBUG\\\"}\"
      }
    }
  }" \
  --region ${AWS_REGION} \
  --query 'deploymentId' \
  --output text
```

### 5.2 验证部署

```bash
# 等待部署完成（约30-60秒）
export DEPLOYMENT_ID="<上一步返回的ID>"

# 检查部署状态
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'deploymentStatus' \
  --output text

# 查看组件日志
sudo tail -f /greengrass/v2/logs/com.example.ConfigDemo.log
```

**预期日志输出**：
```
[2026-01-22 04:22:33] [DEBUG] Debug: Loop iteration 7
[2026-01-22 04:22:33] [INFO] Lab 2 is working!
[2026-01-22 04:22:33] [INFO] Counter: 7/10
```

### 5.3 验证文件路径

```bash
# 查看实际部署的文件
sudo ls -la /greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/${VERSION}/

# 查看二进制文件
sudo find /greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/${VERSION}/ \
  -name config_demo -type f
```

**预期路径**：
```
/greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/1.0.3/
  com.example.ConfigDemo-1.0.3/config_demo/config_demo
```

## 步骤 6: 配置更新实验

### 实验1: 修改日志级别为WARN

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-LogLevel-WARN-$(date +%s)" \
  --components "{
    \"com.example.ConfigDemo\": {
      \"componentVersion\": \"${VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"logLevel\\\":\\\"WARN\\\"}\"
      }
    }
  }" \
  --region ${AWS_REGION}
```

**观察效果**：
- 只显示WARN和ERROR级别的日志
- DEBUG和INFO日志被过滤

### 实验2: 修改输出间隔

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-Interval-10s-$(date +%s)" \
  --components "{
    \"com.example.ConfigDemo\": {
      \"componentVersion\": \"${VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"interval\\\":10,\\\"logLevel\\\":\\\"INFO\\\"}\"
      }
    }
  }" \
  --region ${AWS_REGION}
```

**观察效果**：
- 日志输出间隔从5秒变为10秒
- 无需重启组件，配置动态生效

---

# Part 2: 云端日志集成

## 步骤 7: 理解Greengrass LogManager组件

### 7.1 LogManager组件的作用

**LogManager**是Greengrass的系统组件，负责：
- 📤 自动上传组件日志到CloudWatch Logs
- 🔄 管理本地日志轮转（防止磁盘占满）
- 📊 支持配置每个组件的日志级别和上传策略
- 🎯 无需修改组件代码

### 7.2 日志上传流程

```
组件输出日志 (stdout/stderr)
  ↓
Greengrass捕获并写入本地文件
  ↓
/greengrass/v2/logs/com.example.ConfigDemo.log
  ↓
LogManager监控并读取
  ↓
批量上传到CloudWatch Logs
  ↓
CloudWatch Log Group/Stream
```

### 7.3 LogManager配置结构

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

**字段说明**：
- `uploadToCloudWatch`: 是否上传到CloudWatch
- `minimumLogLevel`: 最低日志级别（DEBUG/INFO/WARN/ERROR）
- `diskSpaceLimit`: 本地日志磁盘限制
- `deleteLogFileAfterCloudUpload`: 上传后是否删除本地日志

## 步骤 8: 部署LogManager组件

### 8.1 检查IAM权限

LogManager需要权限上传日志到CloudWatch。检查Token Exchange Role是否有以下权限：

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
```bash
sudo tail -f /greengrass/v2/logs/com.example.ConfigDemo.log
# 现在可以看到DEBUG级别的日志
```

### 实验2: 修改消息和间隔

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-Update-Message-$(date +%s)" \
  --components '{
    "com.example.ConfigDemo": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"Configuration updated!\",\"interval\":3}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

### 实验3: 修改计数器阈值

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "ConfigDemo-Threshold-$(date +%s)" \
  --components '{
    "com.example.ConfigDemo": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"counterThreshold\":5}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**观察效果**：WARN日志出现频率增加（从每10次变为每5次）

---

## 查看日志

```bash
# Greengrass组件日志
sudo tail -f /greengrass/v2/logs/com.example.ConfigDemo.log

# 应用日志文件
sudo tail -f /tmp/lab2-config-demo.log
```

---

# Part 2: 云端日志集成

## 步骤 7: 理解Greengrass LogManager组件

### 7.1 LogManager组件的作用

**LogManager**是Greengrass的系统组件，负责：
- 📤 自动上传组件日志到CloudWatch Logs
- 🔄 管理本地日志轮转（防止磁盘占满）
- 📊 支持配置每个组件的日志级别和上传策略
- 🎯 无需修改组件代码

### 7.2 日志上传流程

```
组件输出日志 (stdout/stderr)
  ↓
Greengrass捕获并写入本地文件
  ↓
/greengrass/v2/logs/com.example.ConfigDemo.log
  ↓
LogManager监控并读取
  ↓
批量上传到CloudWatch Logs
  ↓
CloudWatch Log Group/Stream
```

### 7.3 LogManager配置结构

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

**字段说明**：
- `uploadToCloudWatch`: 是否上传到CloudWatch
- `minimumLogLevel`: 最低日志级别（DEBUG/INFO/WARN/ERROR）
- `diskSpaceLimit`: 本地日志磁盘限制
- `deleteLogFileAfterCloudUpload`: 上传后是否删除本地日志

## 步骤 8: 部署LogManager组件

### 8.1 检查IAM权限

LogManager需要权限上传日志到CloudWatch：

```bash
# 查看Greengrass Token Exchange Role
aws iot describe-role-alias \
  --role-alias GreengrassV2TokenExchangeRoleAlias \
  --region ${AWS_REGION}

# 需要的权限：
# - logs:CreateLogGroup
# - logs:CreateLogStream
# - logs:PutLogEvents
# - logs:DescribeLogStreams
```

**添加CloudWatch Logs权限**（如果还没有）：

```bash
# 创建策略文档
cat > /tmp/cloudwatch-logs-policy.json << 'EOF'
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
      "Resource": "arn:aws:logs:*:*:log-group:/aws/greengrass/*"
    }
  ]
}
EOF

# 注意：实际环境中需要将此策略附加到Token Exchange Role
# 这里仅作演示，具体操作请参考AWS文档
```

### 8.2 部署ConfigDemo + LogManager

**重要提示**：LogManager版本需要与Greengrass Nucleus版本兼容。

#### 检查Nucleus版本

```bash
# 查看当前Nucleus版本
sudo cat /greengrass/v2/config/effectiveConfig.yaml | grep "componentVersion" | head -1
```

#### LogManager版本兼容性

| Nucleus版本 | 推荐LogManager版本 | 说明 |
|------------|-------------------|------|
| 2.16.x | 2.3.11 | 最新稳定版 |
| 2.15.x | 2.3.7 | 稳定版 |
| 2.14.x | 2.3.0 | 旧版本 |
| 2.13.x | 2.2.8 | 需要特殊权限 |

**本实验使用的版本**：
- Nucleus: 2.16.1
- LogManager: 2.3.11 ✅

#### 部署命令

```bash
# 设置环境变量
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export AWS_REGION="ap-northeast-1"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export VERSION="1.0.3"

# 创建部署（同时部署ConfigDemo和LogManager）
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "Lab2-ConfigDemo-with-LogManager-v${VERSION}" \
  --components "{
    \"aws.greengrass.LogManager\": {
      \"componentVersion\": \"2.3.11\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"logsUploaderConfiguration\\\":{\\\"systemLogsConfiguration\\\":{\\\"uploadToCloudWatch\\\":\\\"true\\\",\\\"minimumLogLevel\\\":\\\"INFO\\\"},\\\"componentLogsConfigurationMap\\\":{\\\"com.example.ConfigDemo\\\":{\\\"minimumLogLevel\\\":\\\"DEBUG\\\",\\\"diskSpaceLimit\\\":\\\"10\\\",\\\"diskSpaceLimitUnit\\\":\\\"MB\\\",\\\"deleteLogFileAfterCloudUpload\\\":\\\"false\\\"}}}}\"
      }
    },
    \"com.example.ConfigDemo\": {
      \"componentVersion\": \"${VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"message\\\":\\\"Lab 2 with CloudWatch!\\\",\\\"interval\\\":5,\\\"logLevel\\\":\\\"DEBUG\\\"}\"
      }
    }
  }" \
  --region ${AWS_REGION} \
  --query 'deploymentId' \
  --output text
```

**配置说明**：
- LogManager版本：2.3.11（与Nucleus 2.16.1兼容）
- ConfigDemo版本：1.0.3（使用正确的ZIP结构）
- ConfigDemo日志级别：DEBUG（上传所有日志）
- 本地日志限制：10MB
- 上传后保留本地日志

### 8.3 验证部署状态

```bash
# 保存部署ID
export DEPLOYMENT_ID="<上一步返回的ID>"

# 等待部署完成（约60秒）
sleep 60

# 查看部署状态
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'deploymentStatus' \
  --output text

# 预期输出: COMPLETED
```

### 8.4 常见部署错误

#### 错误1: UNAUTHORIZED_NUCLEUS_MINOR_VERSION_UPDATE

**原因**：LogManager版本需要更新Nucleus，但没有权限

**解决**：使用与当前Nucleus兼容的LogManager版本（如2.3.11）

#### 错误2: USER_COMPONENT_ERROR

**原因**：ConfigDemo组件路径错误或权限问题

**检查**：
```bash
# 查看组件日志
sudo tail -50 /greengrass/v2/logs/com.example.ConfigDemo.log

# 查看错误详情
sudo tail -50 /greengrass/v2/logs/greengrass.log | grep ERROR
```

#### 错误3: FAILED_ROLLBACK_COMPLETE

**原因**：部署失败并回滚到之前的版本

**解决**：
1. 检查ZIP文件结构是否正确
2. 验证Recipe中的路径
3. 确认版本号一致性
4. 重新打包并部署

### 8.5 验证LogManager运行

```bash
# 查看Greengrass日志中的LogManager信息
sudo grep -i "logmanager.*running\|cloudwatch" /greengrass/v2/logs/greengrass.log | tail -10
```

**预期输出**：
```
[INFO] aws.greengrass.LogManager: service-set-state. {currentState=STARTING, newState=RUNNING}
[INFO] CloudWatchLogsUploader: Unable to find log group... Creating them now..
```

## 步骤 9: 查看CloudWatch Logs

### 9.1 CloudWatch日志组结构

LogManager会自动创建以下日志组：

**用户组件日志**：
```
/aws/greengrass/UserComponent/<region>/<component-name>
```

**系统日志**：
```
/aws/greengrass/GreengrassSystemComponent/<region>/System
```

**本实验的日志组**：
- `/aws/greengrass/UserComponent/ap-northeast-1/com.example.ConfigDemo`
- `/aws/greengrass/GreengrassSystemComponent/ap-northeast-1/System`

### 9.2 在控制台查看日志

1. 打开AWS CloudWatch控制台
2. 导航到 **Logs** > **Log groups**
3. 搜索 `/aws/greengrass/UserComponent`
4. 点击 `com.example.ConfigDemo` 日志组
5. 选择最新的日志流（格式：`/YYYY/MM/DD/thing/<thing-name>`）

**预期看到的日志**：
```
[2026-01-22 04:22:33] [DEBUG] Debug: Loop iteration 7
[2026-01-22 04:22:33] [INFO] Lab 2 with CloudWatch!
[2026-01-22 04:22:33] [INFO] Counter: 7/10
[2026-01-22 04:22:38] [DEBUG] Debug: Loop iteration 8
[2026-01-22 04:22:38] [INFO] Lab 2 with CloudWatch!
[2026-01-22 04:22:38] [WARN] Counter threshold reached! Resetting counter.
```

### 9.3 使用AWS CLI查看日志（可选）

```bash
# 列出日志组
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/greengrass/UserComponent" \
  --region ${AWS_REGION}

# 列出日志流
export LOG_GROUP="/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo"
aws logs describe-log-streams \
  --log-group-name "${LOG_GROUP}" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --region ${AWS_REGION}

# 获取最新日志
export LOG_STREAM="<从上一步获取的日志流名称>"
aws logs get-log-events \
  --log-group-name "${LOG_GROUP}" \
  --log-stream-name "${LOG_STREAM}" \
  --limit 20 \
  --region ${AWS_REGION}
```

### 9.4 日志延迟说明

- LogManager默认每5秒检查一次日志文件
- 批量上传到CloudWatch（通常1-2分钟延迟）
- 可以在LogManager配置中调整上传频率

## 步骤 10: 日志分析和告警（可选）

### 10.1 创建日志过滤器

在CloudWatch控制台：
1. 选择日志组
2. 点击 **Create metric filter**
3. 设置过滤模式：`[timestamp, level="WARN", ...]`
4. 创建指标

### 10.2 设置告警

1. 在CloudWatch控制台，导航到 **Alarms**
2. 点击 **Create alarm**
3. 选择刚创建的指标
4. 设置阈值（例如：5分钟内超过10个WARN日志）
5. 配置SNS通知

### 10.3 日志查询示例

使用CloudWatch Logs Insights查询：

```sql
# 查询所有WARN级别的日志
fields @timestamp, @message
| filter @message like /WARN/
| sort @timestamp desc
| limit 20

# 统计每分钟的日志数量
fields @timestamp
| stats count() by bin(5m)

# 查询特定消息
fields @timestamp, @message
| filter @message like /Counter threshold/
| sort @timestamp desc
```

---

## 总结

### 你学到了什么

✅ **本地日志系统**：
- 实现多级日志（DEBUG/INFO/WARN/ERROR）
- 日志输出到控制台和文件
- 日志格式化和时间戳

✅ **配置管理**：
- 从JSON文件加载配置
- Recipe中的配置参数
- 动态配置更新（无需重启）

✅ **CloudWatch集成**：
- 部署LogManager组件
- 自动上传日志到云端
- 实时查看和分析日志

✅ **版本管理**：
- 组件版本号的一致性
- ZIP文件结构的正确打包
- Recipe路径与实际文件的匹配

### 关键要点

1. **版本一致性至关重要**：Recipe、S3 URI、ZIP文件名、内部路径必须匹配
2. **ZIP文件结构**：避免双重嵌套，从目录内部打包
3. **LogManager版本兼容性**：选择与Nucleus版本兼容的LogManager
4. **日志级别控制**：组件和LogManager都可以过滤日志级别
5. **配置动态更新**：通过部署更新配置，无需重新构建组件

### 最佳实践

1. **本地测试优先**：在部署到Greengrass前先本地测试
2. **版本号规范**：使用语义化版本（major.minor.patch）
3. **日志级别**：生产环境使用INFO，调试时使用DEBUG
4. **磁盘空间管理**：设置合理的diskSpaceLimit
5. **错误处理**：检查部署状态，查看日志排查问题

### 下一步

- Lab 3: Docker容器化部署
- Lab 4: IPC进程间通信
- Lab 5: AWS IoT Core集成

---

## FAQ

### Q1: 为什么部署失败显示"Permission denied"？

**A**: 通常是Recipe中的路径与实际文件路径不匹配。检查：
1. ZIP文件结构：`unzip -l <zip-file>`
2. Recipe中的路径是否包含正确的版本号
3. 是否在Install脚本中设置了执行权限

### Q2: LogManager部署失败，显示UNAUTHORIZED_NUCLEUS_MINOR_VERSION_UPDATE？

**A**: LogManager版本与Nucleus不兼容。解决方法：
- 使用兼容的LogManager版本（如2.3.11 for Nucleus 2.16.x）
- 或者更新Nucleus到最新版本

### Q3: CloudWatch中看不到日志？

**A**: 检查以下几点：
1. Token Exchange Role是否有CloudWatch Logs权限
2. LogManager是否处于RUNNING状态
3. 等待1-2分钟（日志上传有延迟）
4. 检查LogManager配置中的minimumLogLevel

### Q4: 如何修改日志上传频率？

**A**: 在LogManager配置中添加：
```json
{
  "periodicUploadIntervalSec": "300"  // 默认300秒
}
```

### Q5: 组件版本更新后，旧版本还在运行？

**A**: 部署可能失败并回滚。检查：
```bash
# 查看部署状态
aws greengrassv2 get-deployment --deployment-id <id> --region ${AWS_REGION}

# 查看错误日志
sudo tail -100 /greengrass/v2/logs/greengrass.log | grep ERROR
```

### Q6: 如何删除旧的组件版本？

**A**: 
```bash
aws greengrassv2 delete-component \
  --arn "arn:aws:greengrass:${AWS_REGION}:${ACCOUNT_ID}:components:com.example.ConfigDemo:versions:1.0.0" \
  --region ${AWS_REGION}
```

### Q7: ZIP文件应该包含什么结构？

**A**: 正确的结构（以1.0.3为例）：
```
com.example.ConfigDemo-1.0.3.zip
└── config_demo/
    └── config_demo (binary)
```

打包命令：
```bash
cd com.example.ConfigDemo-1.0.3
zip -r ../com.example.ConfigDemo-1.0.3.zip .
```

### Q8: Recipe中的{artifacts:decompressedPath}指向哪里？

**A**: 指向：
```
/greengrass/v2/packages/artifacts-unarchived/<ComponentName>/<Version>/
```

例如：
```
/greengrass/v2/packages/artifacts-unarchived/com.example.ConfigDemo/1.0.3/
```

然后Greengrass会在这个目录下创建一个以ZIP文件名命名的子目录。

## 步骤 9: 在CloudWatch控制台查看日志

### 9.1 打开CloudWatch Logs控制台

```
https://console.amazonaws.cn/cloudwatch/home?region=ap-northeast-1#logsV2:log-groups
```

### 9.2 找到日志组

**日志组命名规则**：
```
/aws/greengrass/UserComponent/<region>/<component-name>
```

**示例**：
```
/aws/greengrass/UserComponent/ap-northeast-1/com.example.ConfigDemo
```

**操作步骤**：
1. 在Log groups列表中搜索：`com.example.ConfigDemo`
2. 点击日志组名称
3. 查看Log streams列表

### 9.3 查看日志流

**日志流命名规则**：
```
<thing-name>_<year>_<month>_<day>
```

**示例**：
```
GreengrassQuickStartCore-19be3781cbc_2026_01_22
```

**操作步骤**：
1. 点击最新的日志流
2. 查看实时日志输出

**预期看到的日志**：
```
2026-01-22T03:20:00.000Z [INFO] (Copier) com.example.ConfigDemo: stdout. [2026-01-22 03:20:00] [INFO] Hello from Lab 2 with CloudWatch!
2026-01-22T03:20:00.100Z [INFO] (Copier) com.example.ConfigDemo: stdout. [2026-01-22 03:20:00] [DEBUG] Debug: Loop iteration 1
2026-01-22T03:20:05.000Z [INFO] (Copier) com.example.ConfigDemo: stdout. [2026-01-22 03:20:05] [INFO] Hello from Lab 2 with CloudWatch!
```

### 9.4 实时查看日志（Live Tail）

CloudWatch Logs支持实时查看：

1. 在日志流页面，点击 **Start Live Tail**
2. 实时观察日志输出
3. 可以看到组件的每条日志几乎实时出现

### 9.5 使用CLI查看CloudWatch日志

```bash
# 列出日志组
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/greengrass/UserComponent" \
  --region ${AWS_REGION}

# 列出日志流
aws logs describe-log-streams \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --order-by LastEventTime \
  --descending \
  --max-items 5 \
  --region ${AWS_REGION}

# 获取最新日志流名称
export LOG_STREAM_NAME=$(aws logs describe-log-streams \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --query 'logStreams[0].logStreamName' \
  --output text \
  --region ${AWS_REGION})

echo "Log Stream: ${LOG_STREAM_NAME}"

# 查看最新50条日志
aws logs get-log-events \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --log-stream-name "${LOG_STREAM_NAME}" \
  --limit 50 \
  --region ${AWS_REGION} \
  --query 'events[*].message' \
  --output text
```

## 步骤 10: 日志过滤和分析

### 10.1 使用CloudWatch Logs Insights查询

**打开Logs Insights**：
```
CloudWatch Console → Logs → Insights
```

**选择日志组**：
```
/aws/greengrass/UserComponent/ap-northeast-1/com.example.ConfigDemo
```

**查询示例**：

**1. 查询所有WARN级别日志**：
```
fields @timestamp, @message
| filter @message like /\[WARN\]/
| sort @timestamp desc
| limit 100
```

**2. 统计每个日志级别的数量**：
```
fields @message
| parse @message /\[(?<level>DEBUG|INFO|WARN|ERROR)\]/
| stats count() by level
```

**3. 查询包含特定关键词的日志**：
```
fields @timestamp, @message
| filter @message like /threshold/
| sort @timestamp desc
```

**4. 查询最近5分钟的日志**：
```
fields @timestamp, @message
| filter @timestamp > ago(5m)
| sort @timestamp desc
```

**5. 统计每分钟的日志数量**：
```
fields @timestamp
| stats count() by bin(5m)
```

### 10.2 创建日志过滤器（Metric Filter）

将日志转换为CloudWatch指标：

```bash
# 创建Metric Filter - 统计WARN日志数量
aws logs put-metric-filter \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --filter-name "WarnLogCount" \
  --filter-pattern "[WARN]" \
  --metric-transformations \
    metricName=WarnLogCount,\
metricNamespace=Greengrass/ConfigDemo,\
metricValue=1,\
defaultValue=0 \
  --region ${AWS_REGION}

# 创建Metric Filter - 统计ERROR日志数量
aws logs put-metric-filter \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --filter-name "ErrorLogCount" \
  --filter-pattern "[ERROR]" \
  --metric-transformations \
    metricName=ErrorLogCount,\
metricNamespace=Greengrass/ConfigDemo,\
metricValue=1,\
defaultValue=0 \
  --region ${AWS_REGION}
```

### 10.3 创建CloudWatch告警

基于日志指标创建告警：

```bash
# 创建告警 - ERROR日志超过阈值
aws cloudwatch put-metric-alarm \
  --alarm-name "ConfigDemo-HighErrorRate" \
  --alarm-description "Alert when error log count exceeds threshold" \
  --metric-name ErrorLogCount \
  --namespace Greengrass/ConfigDemo \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --region ${AWS_REGION}

# 查看告警状态
aws cloudwatch describe-alarms \
  --alarm-names "ConfigDemo-HighErrorRate" \
  --region ${AWS_REGION}
```

### 10.4 配置告警通知（可选）

```bash
# 创建SNS主题
aws sns create-topic \
  --name greengrass-log-alerts \
  --region ${AWS_REGION}

# 订阅邮箱
aws sns subscribe \
  --topic-arn "arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:greengrass-log-alerts" \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region ${AWS_REGION}

# 更新告警添加SNS通知
aws cloudwatch put-metric-alarm \
  --alarm-name "ConfigDemo-HighErrorRate" \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:greengrass-log-alerts" \
  --metric-name ErrorLogCount \
  --namespace Greengrass/ConfigDemo \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --region ${AWS_REGION}
```

## 关键概念总结

### Part 1: 本地日志系统

1. **Logger类设计**
   - 封装日志功能
   - 支持多个输出目标（控制台、文件）
   - 日志级别过滤

2. **日志级别**
   | 级别 | 用途 | 生产环境 |
   |------|------|----------|
   | DEBUG | 详细调试信息 | ❌ 不推荐 |
   | INFO | 常规信息 | ✅ 推荐 |
   | WARN | 警告信息 | ✅ 推荐 |
   | ERROR | 错误信息 | ✅ 必须 |

3. **配置管理**
   - 配置合并（merge）策略
   - 配置更新触发组件重启
   - 支持部分配置更新

### Part 2: 云端日志集成

4. **LogManager组件**
   - Greengrass系统组件
   - 自动上传日志到CloudWatch
   - 管理本地日志轮转
   - 无需修改组件代码

5. **CloudWatch Logs**
   - 集中式日志管理
   - 实时查看和搜索
   - 日志保留策略
   - 支持日志分析

6. **日志流向**
   ```
   组件stdout → Greengrass捕获 → 本地日志文件 
                                    ↓
                              LogManager读取
                                    ↓
                            CloudWatch Logs
   ```

7. **CloudWatch Logs Insights**
   - 强大的查询语言
   - 实时日志分析
   - 可视化展示
   - 支持复杂过滤

8. **Metric Filter和告警**
   - 将日志转换为指标
   - 基于日志内容创建告警
   - 集成SNS通知

## 实验总结

通过本实验，你已经：
- ✅ 实现了完整的多级日志系统
- ✅ 掌握了本地日志文件管理
- ✅ 理解了Greengrass配置管理机制
- ✅ 部署了LogManager组件
- ✅ 实现了日志自动上传到CloudWatch
- ✅ 学会了在CloudWatch控制台查看和分析日志
- ✅ 创建了日志过滤器和告警

## 最佳实践

### 日志级别选择
- **开发环境**：DEBUG（查看所有细节）
- **测试环境**：INFO（常规信息）
- **生产环境**：WARN（只记录警告和错误）

### 日志轮转配置
```json
{
  "diskSpaceLimit": "10",
  "diskSpaceLimitUnit": "MB",
  "deleteLogFileAfterCloudUpload": "false"
}
```
- 根据设备存储空间调整限制
- 生产环境建议上传后删除本地日志
- 测试环境保留本地日志便于调试

### CloudWatch日志保留
```bash
# 设置日志保留期（30天）
aws logs put-retention-policy \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --retention-in-days 30 \
  --region ${AWS_REGION}
```

### 成本优化
- 只上传必要的日志级别
- 设置合理的日志保留期
- 使用日志过滤减少存储量
- 考虑使用S3归档旧日志

## 常见问题 (FAQ)

**Q1: 日志没有出现在CloudWatch中？**

检查清单：
```bash
# 1. 验证LogManager运行
sudo /greengrass/v2/bin/greengrass-cli component list | grep LogManager

# 2. 查看LogManager日志
sudo tail -50 /greengrass/v2/logs/aws.greengrass.LogManager.log

# 3. 检查IAM权限
# Token Exchange Role需要logs:PutLogEvents权限

# 4. 验证网络连接
# 设备需要能访问CloudWatch Logs API
```

**Q2: 如何减少CloudWatch日志成本？**

策略：
- 提高minimumLogLevel（只上传WARN和ERROR）
- 减少日志保留期
- 使用日志采样（不上传所有日志）
- 配置deleteLogFileAfterCloudUpload为true

**Q3: 本地日志和CloudWatch日志不一致？**

原因：
- LogManager有上传延迟（通常几秒到几分钟）
- minimumLogLevel过滤了部分日志
- 网络问题导致上传失败

**Q4: 如何查看历史日志？**

```bash
# 使用CloudWatch Logs API
aws logs filter-log-events \
  --log-group-name "/aws/greengrass/UserComponent/${AWS_REGION}/com.example.ConfigDemo" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region ${AWS_REGION}
```

**Q5: 如何实现多设备日志聚合查询？**

使用CloudWatch Logs Insights跨日志组查询：
```
fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| sort @timestamp desc
```

**Q6: LogManager占用太多磁盘空间？**

调整配置：
```json
{
  "diskSpaceLimit": "5",
  "diskSpaceLimitUnit": "MB",
  "deleteLogFileAfterCloudUpload": "true"
}
```

## 故障排查清单

### 日志未上传到CloudWatch
- [ ] LogManager组件状态为RUNNING
- [ ] Token Exchange Role有CloudWatch Logs权限
- [ ] 设备网络正常，可访问CloudWatch API
- [ ] LogManager配置中uploadToCloudWatch为true
- [ ] 查看LogManager日志是否有错误

### 日志级别不生效
- [ ] 确认配置更新已部署
- [ ] 组件已重启
- [ ] 检查Recipe中的DefaultConfiguration
- [ ] 验证配置文件内容

### CloudWatch日志查询慢
- [ ] 缩小时间范围
- [ ] 使用更具体的过滤条件
- [ ] 考虑使用Metric Filter预聚合

## 下一步

完成Lab 2后，继续：
- **[Lab 3: IEC104模拟器](../lab3-iec104-simulator/README.md)** - 模拟工业设备数据
- **Lab 4**: IEC104数据采集组件
- **Lab 5**: AWS IoT Core集成

## 参考资料

- [AWS IoT Greengrass LogManager](https://docs.aws.amazon.com/greengrass/v2/developerguide/log-manager-component.html)
- [CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/)
- [CloudWatch Logs Insights查询语法](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Metric Filters](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/MonitoringLogData.html)

---

**🎉 恭喜完成Lab 2！你已经掌握了完整的日志管理系统！**
