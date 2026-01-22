# Lab 5: IPC订阅与AWS IoT Core集成 (Part 2)

## Part 4: 构建和部署

### 步骤 7: 安装AWS IoT Device SDK

```bash
# 检查SDK是否已安装
ls /usr/local/lib/libaws-crt-cpp.so 2>/dev/null || echo "需要安装SDK"

# 如果需要安装（参考Lab 4步骤6）
cd /tmp
git clone --recursive https://github.com/aws/aws-iot-device-sdk-cpp-v2.git
cd aws-iot-device-sdk-cpp-v2
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_DEPS=ON
make -j$(nproc)
sudo make install
sudo ldconfig
```

### 步骤 8: 构建Lab 5组件

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab5-iot-integration

# 使用IPC版本的CMakeLists
cp CMakeLists-IPC.txt CMakeLists.txt

# 创建构建目录
mkdir -p build && cd build

# 配置CMake
cmake .. -DCMAKE_BUILD_TYPE=Release

# 编译
make -j$(nproc)

# 验证
ls -lh iot_publisher
ldd iot_publisher | grep -E "aws|Greengrass"
```

**预期输出**：
```
libaws-crt-cpp.so => /usr/local/lib/libaws-crt-cpp.so
libGreengrassIpc-cpp.so => /usr/local/lib/libGreengrassIpc-cpp.so
libIotDeviceCommon-cpp.so => /usr/local/lib/libIotDeviceCommon-cpp.so
```

### 步骤 9: 本地测试（模拟环境）

**注意**：本地测试时IPC和IoT连接会失败（正常），主要验证代码编译。

```bash
# 创建测试配置
cat > /tmp/iot-publisher-test-config.json << 'EOF'
{
  "ipcTopic": "iec104/data",
  "iotTopic": "wind-farm/data",
  "region": "cn-north-1",
  "endpoint": "xxx.iot.cn-north-1.amazonaws.com.cn",
  "certPath": "/tmp/test.crt",
  "keyPath": "/tmp/test.key",
  "caPath": "/tmp/ca.pem"
}
EOF

# 运行（会失败，但验证代码逻辑）
timeout 5 ./build/iot_publisher /tmp/iot-publisher-test-config.json 2>&1 || true
```

### 步骤 10: 打包组件

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab5-iot-integration

# 创建打包脚本
cat > package-ipc.sh << 'EOF'
#!/bin/bash
set -e

echo "Packaging IoT Publisher with IPC..."

# 清理旧文件
rm -rf artifacts
mkdir -p artifacts/iot_publisher

# 复制二进制文件
cp build/iot_publisher artifacts/iot_publisher/

# 创建ZIP包
cd artifacts
zip -r com.example.IoTPublisher-1.0.0.zip iot_publisher/
cd ..

# 转换Recipe为JSON
python3 << 'PYTHON'
import yaml
import json

with open('recipe-ipc.yaml', 'r') as f:
    recipe = yaml.safe_load(f)

with open('artifacts/recipe-ipc.json', 'w') as f:
    json.dump(recipe, f, indent=2)

print("✅ Recipe converted to JSON")
PYTHON

echo "✅ Packaging complete"
ls -lh artifacts/
EOF

chmod +x package-ipc.sh

# 执行打包
./package-ipc.sh
```

### 步骤 11: 上传到S3

```bash
export COMPONENT_BUCKET="iec104-greengrass-components-1737518400"
export AWS_REGION="cn-north-1"

# 上传组件包
aws s3 cp artifacts/com.example.IoTPublisher-1.0.0.zip \
  s3://${COMPONENT_BUCKET}/com.example.IoTPublisher/1.0.0/ \
  --region ${AWS_REGION}

# 验证上传
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.IoTPublisher/1.0.0/
```

### 步骤 12: 更新Recipe并创建组件

```bash
# 更新S3路径
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" \
  artifacts/recipe-ipc.json > artifacts/recipe-ipc-updated.json

# 创建组件版本
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-ipc-updated.json \
  --region ${AWS_REGION}
```

**预期输出**：
```json
{
    "arn": "arn:aws-cn:greengrass:cn-north-1:123456789012:components:com.example.IoTPublisher:versions:1.0.0",
    "componentName": "com.example.IoTPublisher",
    "componentVersion": "1.0.0",
    "creationTimestamp": "2026-01-22T03:50:00.000000+00:00",
    "status": {
        "componentState": "REQUESTED"
    }
}
```

---

## Part 5: 端到端部署和测试

### 步骤 13: 部署完整系统

```bash
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="cn-north-1"

# 部署Lab 3 + Lab 4 + Lab 5
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "Complete-IEC104-System-$(date +%s)" \
  --components '{
    "com.example.IEC104SimulatorDocker": {
      "componentVersion": "1.0.0"
    },
    "com.example.IEC104Collector": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"serverHost\":\"localhost\",\"serverPort\":2404,\"ipcTopic\":\"iec104/data\"}"
      }
    },
    "com.example.IoTPublisher": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"ipcTopic\":\"iec104/data\",\"iotTopic\":\"wind-farm/data\",\"region\":\"cn-north-1\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**部署说明**：
- **Lab 3**: IEC104模拟器（Docker容器）
- **Lab 4**: 数据采集器（IPC发布）
- **Lab 5**: IoT发布器（IPC订阅 + IoT发布）

### 步骤 14: 验证部署状态

```bash
# 查看部署状态
aws greengrassv2 list-effective-deployments \
  --core-device-thing-name ${THING_NAME} \
  --region ${AWS_REGION}

# 查看组件状态
sudo /greengrass/v2/bin/greengrass-cli component list
```

**预期输出**：
```
Component Name: com.example.IEC104SimulatorDocker
    Version: 1.0.0
    State: RUNNING

Component Name: com.example.IEC104Collector
    Version: 1.0.0
    State: RUNNING

Component Name: com.example.IoTPublisher
    Version: 1.0.0
    State: RUNNING
```

### 步骤 15: 验证数据流

#### 15.1 验证Lab 3模拟器

```bash
# 检查Docker容器
docker ps | grep iec104-simulator

# 查看模拟器日志
docker logs iec104-simulator | tail -20

# 测试端口
nc -zv localhost 2404
```

#### 15.2 验证Lab 4采集器

```bash
# 查看Collector日志
sudo tail -30 /greengrass/v2/logs/com.example.IEC104Collector.log

# 应该看到：
# [INFO] Connected to IEC104 server localhost:2404
# [INFO] Published 2 data points to IPC topic: iec104/data
```

#### 15.3 验证Lab 5发布器

```bash
# 查看Publisher日志
sudo tail -30 /greengrass/v2/logs/com.example.IoTPublisher.log

# 应该看到：
# [INFO] Connected to Greengrass IPC
# [INFO] Connected to IoT Core
# [INFO] Subscribed to IPC topic: iec104/data
# [INFO] Received IPC message: [{"address":1001,...}]
# [INFO] Published to IoT Core, packet ID: 1
```

### 步骤 16: 在IoT Core验证消息

#### 16.1 使用AWS IoT Console

1. 打开IoT Console：
   ```
   https://console.amazonaws.cn/iot/home?region=cn-north-1
   ```

2. 导航到 **Test** → **MQTT test client**

3. 订阅主题：
   - Topic: `wind-farm/data`
   - 点击 **Subscribe**

4. 观察实时消息：
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

#### 16.2 使用AWS CLI订阅

```bash
# 安装mosquitto客户端
sudo apt-get install -y mosquitto-clients

# 获取IoT endpoint
IOT_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --region ${AWS_REGION} --query 'endpointAddress' --output text)

# 订阅主题（需要证书）
mosquitto_sub \
  --host ${IOT_ENDPOINT} \
  --port 8883 \
  --topic "wind-farm/data" \
  --cafile /greengrass/v2/rootCA.pem \
  --cert /greengrass/v2/thingCert.crt \
  --key /greengrass/v2/privKey.key
```

---

## Part 6: 调试和故障排查

### 步骤 17: 常见问题排查

#### 问题1: IPC订阅失败

**错误**：
```
[ERROR] IPC subscribe failed: UNAUTHORIZED
```

**排查**：
```bash
# 检查Recipe权限配置
cat artifacts/recipe-ipc-updated.json | jq '.Manifests[0].ComponentConfiguration.accessControl'

# 验证包含SubscribeToTopic权限
# 应该看到：
# "operations": ["aws.greengrass#SubscribeToTopic"]
# "resources": ["iec104/data"]
```

**解决方法**：
- 确认Recipe中有IPC订阅权限
- 重新创建组件版本
- 重新部署

#### 问题2: IoT Core连接失败

**错误**：
```
[ERROR] Failed to connect to IoT Core: -1
```

**排查**：
```bash
# 检查证书文件
ls -la /greengrass/v2/thingCert.crt
ls -la /greengrass/v2/privKey.key
ls -la /greengrass/v2/rootCA.pem

# 检查IoT endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS --region ${AWS_REGION}

# 测试网络连接
telnet ${IOT_ENDPOINT} 8883
```

**解决方法**：
- 验证证书文件存在且可读
- 检查网络连接
- 验证IoT Core策略权限

#### 问题3: 未收到IPC消息

**排查**：
```bash
# 检查Lab 4是否在运行
sudo /greengrass/v2/bin/greengrass-cli component list | grep IEC104Collector

# 查看Lab 4日志
sudo tail -50 /greengrass/v2/logs/com.example.IEC104Collector.log

# 检查IPC topic名称是否匹配
# Lab 4发布: "iec104/data"
# Lab 5订阅: "iec104/data"
```

#### 问题4: IoT Core未收到消息

**排查**：
```bash
# 检查IoT Core策略
aws iot list-attached-policies \
  --target "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --region ${AWS_REGION}

# 查看策略内容
aws iot get-policy \
  --policy-name <policy-name> \
  --region ${AWS_REGION}
```

**需要的IoT策略**：
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws-cn:iot:cn-north-1:*:topic/wind-farm/*"
    }
  ]
}
```

### 步骤 18: 性能监控

```bash
# 查看组件资源使用
sudo /greengrass/v2/bin/greengrass-cli get-component-details \
  --name com.example.IoTPublisher

# 查看系统资源
top -p $(pgrep iot_publisher)

# 查看网络连接
sudo netstat -anp | grep iot_publisher
```

### 步骤 19: 日志分析

```bash
# 统计IPC消息接收数量
sudo grep "Received IPC message" /greengrass/v2/logs/com.example.IoTPublisher.log | wc -l

# 统计IoT发布成功数量
sudo grep "Published to IoT Core" /greengrass/v2/logs/com.example.IoTPublisher.log | wc -l

# 查看错误日志
sudo grep ERROR /greengrass/v2/logs/com.example.IoTPublisher.log

# 实时监控
sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log | grep -E "Received|Published|ERROR"
```

---

## Part 7: 高级主题

### 步骤 20: 配置更新实验

#### 实验1: 修改IoT Topic

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IoTPublisher-Update-Topic-$(date +%s)" \
  --components '{
    "com.example.IoTPublisher": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"iotTopic\":\"wind-farm/data/v2\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**验证**：在IoT Console订阅新topic `wind-farm/data/v2`

#### 实验2: 修改IPC Topic

```bash
# 需要同时更新Lab 4和Lab 5
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "Update-IPC-Topic-$(date +%s)" \
  --components '{
    "com.example.IEC104Collector": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"ipcTopic\":\"iec104/data/v2\"}"
      }
    },
    "com.example.IoTPublisher": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"ipcTopic\":\"iec104/data/v2\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

### 步骤 21: 添加数据处理逻辑

可以在Lab 5中添加数据过滤、聚合等逻辑：

```cpp
// 在streamHandler中添加
auto streamHandler = [this](SubscriptionResponseMessage* message) {
    auto payload = message->GetBinaryMessage()->GetMessage();
    std::string payloadStr(payload.begin(), payload.end());
    json data = json::parse(payloadStr);
    
    // 数据过滤：只发送有功功率大于1400kW的数据
    json filtered = json::array();
    for (const auto& item : data) {
        if (item["name"] == "wind_turbine_1_active_power" && 
            item["value"].get<double>() > 1400.0) {
            filtered.push_back(item);
        }
    }
    
    if (!filtered.empty()) {
        iotPublisher_.publish(filtered);
    }
};
```

### 步骤 22: 添加IoT Rules集成

在IoT Core中创建规则处理数据：

```bash
# 创建IoT Rule
aws iot create-topic-rule \
  --rule-name WindFarmDataRule \
  --topic-rule-payload '{
    "sql": "SELECT * FROM \"wind-farm/data\" WHERE value > 1500",
    "actions": [
      {
        "lambda": {
          "functionArn": "arn:aws-cn:lambda:cn-north-1:123456789012:function:ProcessWindData"
        }
      }
    ]
  }' \
  --region ${AWS_REGION}
```

---

## 关键概念总结

### 1. IPC订阅机制

**核心概念**：
- 异步流式接收
- 回调函数处理
- 持续监听

**与发布的区别**：
| 特性 | 发布 | 订阅 |
|------|------|------|
| 操作 | PublishToTopic | SubscribeToTopic |
| 模式 | 推送 | 拉取 |
| 回调 | 无 | 必需 |
| 生命周期 | 一次性 | 持续 |

### 2. IoT Core MQTT

**连接要素**：
- Endpoint: IoT Core地址
- Port: 8883 (MQTT over TLS)
- 证书: 双向TLS认证
- Client ID: 设备标识

**QoS级别**：
- QoS 0: 最多一次
- QoS 1: 至少一次（本Lab使用）
- QoS 2: 恰好一次

### 3. 双重权限配置

**IPC Pub/Sub权限**：
```yaml
aws.greengrass.ipc.pubsub:
  operations: ["aws.greengrass#SubscribeToTopic"]
  resources: ["iec104/data"]
```

**IoT Core发布权限**：
```yaml
aws.greengrass.ipc.mqttproxy:
  operations: ["aws.greengrass#PublishToIoTCore"]
  resources: ["wind-farm/data"]
```

### 4. 完整数据流

```
IEC104 Simulator (Lab 3)
    ↓ TCP/IEC104
IEC104 Collector (Lab 4)
    ↓ IPC Publish (iec104/data)
Greengrass IPC Router
    ↓ IPC Subscribe
IoT Publisher (Lab 5)
    ↓ MQTT Publish (wind-farm/data)
AWS IoT Core
    ↓ IoT Rules
Lambda / DynamoDB / S3 / etc.
```

## 实验总结

通过本实验，你已经：
- ✅ 掌握了IPC订阅机制和回调处理
- ✅ 实现了与AWS IoT Core的MQTT集成
- ✅ 配置了双重IPC权限
- ✅ 完成了端到端的数据流
- ✅ 学会了调试和故障排查
- ✅ 理解了完整的边缘到云端架构

## 最佳实践

### 1. 错误处理
- 在回调函数中使用try-catch
- 记录详细的错误日志
- 实现重连机制

### 2. 性能优化
- 批量发送消息
- 使用异步操作
- 控制发送频率

### 3. 安全性
- 使用TLS加密
- 定期轮换证书
- 最小权限原则

### 4. 可维护性
- 清晰的日志输出
- 配置参数化
- 模块化设计

## 扩展实验

### 实验1: 添加消息缓存
在网络断开时缓存消息，恢复后重发

### 实验2: 实现数据聚合
每10秒聚合一次数据再发送

### 实验3: 添加告警功能
当数据超过阈值时发送告警消息

### 实验4: 集成DynamoDB
通过IoT Rules将数据存储到DynamoDB

## 下一步

完成整个Workshop后，你可以：
1. 将系统应用到实际项目
2. 添加更多数据源
3. 实现复杂的数据处理逻辑
4. 集成更多AWS服务

## 参考资料

- [Greengrass IPC订阅](https://docs.aws.amazon.com/greengrass/v2/developerguide/ipc-publish-subscribe.html)
- [AWS IoT Core MQTT](https://docs.aws.amazon.com/iot/latest/developerguide/mqtt.html)
- [IoT Device SDK C++](https://github.com/aws/aws-iot-device-sdk-cpp-v2)
- [IoT Rules](https://docs.aws.amazon.com/iot/latest/developerguide/iot-rules.html)

---

**🎉 恭喜完成Lab 5和整个Workshop！**

你已经掌握了：
- ✅ Greengrass组件开发
- ✅ Docker容器化部署
- ✅ Greengrass IPC通信
- ✅ AWS IoT Core集成
- ✅ CloudWatch日志管理
- ✅ 完整的工业IoT解决方案

**这是一个生产级的边缘到云端数据流系统！**
