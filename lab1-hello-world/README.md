# Lab 1: 部署第一个Greengrass组件

## 学习目标

完成本实验后，你将能够：
- ✅ 理解Greengrass组件的基本结构和生命周期
- ✅ 编写简单的C++组件代码
- ✅ 使用CMake构建C++项目
- ✅ 创建和理解Greengrass Recipe配置文件
- ✅ 将组件打包并上传到S3
- ✅ 通过AWS CLI部署组件到设备
- ✅ 查看和调试组件日志
- ✅ 动态更新组件配置

## 前置条件

### 必需
- ✅ AWS账号（具有IoT和Greengrass权限）
- ✅ 已安装并运行AWS Greengrass Core v2
- ✅ 已配置AWS CLI并设置凭证
- ✅ 基本的Linux命令行知识
- ✅ 基本的C++编程知识

### 验证环境
```bash
# 检查Greengrass状态
sudo systemctl status greengrass

# 检查AWS CLI
aws sts get-caller-identity

# 检查构建工具
cmake --version
g++ --version

# 检查Python（用于YAML转JSON）
python3 --version
```

## 架构概览

```
┌─────────────────────────────────────────────────────────┐
│          AWS IoT Core / Greengrass Cloud                │
│                                                          │
│  ┌──────────────┐         ┌─────────────────┐          │
│  │  S3 Bucket   │         │  Component      │          │
│  │  - Artifacts │◄────────│  Registry       │          │
│  └──────────────┘         └─────────────────┘          │
└────────────────────────────────┬────────────────────────┘
                                 │
                                 │ 1. 部署指令
                                 │ 2. 下载组件
                                 ▼
┌─────────────────────────────────────────────────────────┐
│              Greengrass Core Device                     │
│                                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │  Greengrass Nucleus (核心服务)                 │    │
│  │  - 管理组件生命周期                            │    │
│  │  - 处理配置更新                                │    │
│  │  - 收集日志                                    │    │
│  └──────────────────┬─────────────────────────────┘    │
│                     │                                    │
│                     │ 启动和管理                         │
│                     ▼                                    │
│  ┌────────────────────────────────────────────────┐    │
│  │  com.example.HelloWorld Component              │    │
│  │                                                 │    │
│  │  配置:                                          │    │
│  │  - message: "Hello from Greengrass!"           │    │
│  │  - interval: 5                                 │    │
│  │                                                 │    │
│  │  行为:                                          │    │
│  │  - 每5秒打印一次消息                           │    │
│  │  - 响应配置更新                                │    │
│  │  - 优雅关闭                                    │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
│  日志输出: /greengrass/v2/logs/                         │
└─────────────────────────────────────────────────────────┘
```

## 步骤 1: 理解组件代码结构

### 1.1 进入Lab目录并查看结构

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab1-hello-world
tree -L 2
```

**目录结构说明**：
```
lab1-hello-world/
├── src/
│   └── hello_world.cpp      # C++源代码 - 组件的核心逻辑
├── CMakeLists.txt            # CMake构建配置 - 定义如何编译
├── recipe.yaml               # Greengrass组件配置 - 定义组件行为
├── config.json               # 示例配置文件 - 本地测试用
├── build.sh                  # 构建脚本 - 自动化编译过程
├── package.sh                # 打包脚本 - 创建部署包
├── deploy.sh                 # 部署脚本 - 一键部署（可选）
├── test-local.sh             # 本地测试脚本 - 不依赖Greengrass
└── README.md                 # 本文档
```

### 1.2 深入理解源代码

```bash
cat src/hello_world.cpp
```

**逐段代码解析**：

**1. 头文件和依赖**：
```cpp
#include <iostream>          // 标准输入输出
#include <fstream>           // 文件操作
#include <thread>            // 线程和睡眠
#include <csignal>           // 信号处理
#include <atomic>            // 原子操作
#include <nlohmann/json.hpp> // JSON解析库
```

**2. 全局运行标志**：
```cpp
std::atomic<bool> g_running{true};
```
- 使用`atomic`确保线程安全
- 用于控制主循环的运行状态
- 信号处理函数会修改这个值

**3. 信号处理函数**：
```cpp
void signalHandler(int signal) {
    std::cout << "\n[INFO] Received signal " << signal 
              << ", shutting down gracefully..." << std::endl;
    g_running = false;
}
```
- 捕获SIGINT (Ctrl+C) 和 SIGTERM (kill命令)
- 实现优雅关闭，而不是强制终止
- Greengrass在停止组件时会发送SIGTERM

**4. 配置结构体**：
```cpp
struct Config {
    std::string message;
    int interval;
};
```
- 封装配置参数
- 便于传递和管理

**5. 配置加载函数**：
```cpp
Config loadConfig(const std::string& configPath) {
    std::ifstream file(configPath);
    nlohmann::json j;
    file >> j;
    
    Config config;
    config.message = j.value("message", "Hello World!");
    config.interval = j.value("interval", 5);
    return config;
}
```
- 从JSON文件读取配置
- 使用`value()`提供默认值
- 如果配置文件缺少某个字段，使用默认值

**6. 主函数逻辑**：
```cpp
int main(int argc, char* argv[]) {
    // 注册信号处理
    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);
    
    // 加载配置
    Config config = loadConfig(configPath);
    
    // 主循环
    int seconds = 0;
    while (g_running) {
        std::cout << "[INFO] " << config.message << std::endl;
        std::cout << "[INFO] Component running for " 
                  << seconds << " seconds" << std::endl;
        
        std::this_thread::sleep_for(
            std::chrono::seconds(config.interval)
        );
        seconds += config.interval;
    }
    
    return 0;
}
```

### 1.3 本地测试（不依赖Greengrass）

在构建之前，先理解本地测试流程：

```bash
# 查看测试脚本
cat test-local.sh
```

**思考问题**：
1. 为什么要使用`std::atomic<bool>`而不是普通的`bool`？
   - 提示：考虑信号处理函数在不同线程中执行

2. 如果不处理SIGTERM信号会怎样？
   - 提示：Greengrass如何停止组件？

3. 配置文件的路径是如何传递给程序的？
   - 提示：查看`main`函数的参数处理

## 步骤 2: 手动构建组件

### 2.1 理解CMake配置

```bash
cat CMakeLists.txt
```

**逐行解析CMakeLists.txt**：

```cmake
# 1. 设置最低CMake版本
cmake_minimum_required(VERSION 3.10)

# 2. 定义项目名称
project(HelloWorld)

# 3. 设置C++标准为C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 4. 查找nlohmann/json库
find_package(nlohmann_json QUIET)

# 5. 如果找不到，使用FetchContent下载
if(NOT nlohmann_json_FOUND)
    include(FetchContent)
    FetchContent_Declare(json
        URL https://github.com/nlohmann/json/releases/download/v3.11.2/json.tar.xz
    )
    FetchContent_MakeAvailable(json)
endif()

# 6. 创建可执行文件
add_executable(hello_world src/hello_world.cpp)

# 7. 链接库
target_link_libraries(hello_world 
    nlohmann_json::nlohmann_json  # JSON库
    pthread                        # POSIX线程库
)
```

**关键概念**：
- `find_package`: 查找系统已安装的库
- `FetchContent`: 如果找不到，自动下载
- `target_link_libraries`: 链接依赖库

### 2.2 手动执行构建步骤

```bash
# 步骤1: 创建构建目录（out-of-source build）
mkdir -p build
cd build

# 步骤2: 运行CMake配置阶段
cmake .. -DCMAKE_BUILD_TYPE=Release

# 观察输出，CMake会：
# - 检测C++编译器
# - 查找nlohmann/json库
# - 如果找不到，下载并配置
# - 生成Makefile
```

**预期输出**：
```
-- The C compiler identification is GNU 11.4.0
-- The CXX compiler identification is GNU 11.4.0
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Check for working C compiler: /usr/bin/cc - skipped
-- Detecting C compile features
-- Detecting C compile features - done
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Check for working CXX compiler: /usr/bin/c++ - skipped
-- Detecting CXX compile features
-- Detecting CXX compile features - done
-- Configuring done
-- Generating done
-- Build files have been written to: /home/ubuntu/iec104-greengrass/workshop/lab1-hello-world/build
```

```bash
# 步骤3: 编译代码
make -j$(nproc)

# -j$(nproc) 使用所有CPU核心并行编译
```

**预期输出**：
```
[ 50%] Building CXX object CMakeFiles/hello_world.dir/src/hello_world.cpp.o
[100%] Linking CXX executable hello_world
[100%] Built target hello_world
```

```bash
# 步骤4: 查看生成的二进制文件
ls -lh hello_world
file hello_world
ldd hello_world  # 查看依赖的动态库

# 返回项目根目录
cd ..
```

**或使用提供的脚本**：
```bash
./build.sh
```

### 2.3 验证构建结果

```bash
# 查看构建产物
ls -lh build/

# 检查二进制文件类型
file build/hello_world

# 查看符号表（可选）
nm build/hello_world | grep main

# 查看文件大小
du -h build/hello_world
```

### 2.4 本地测试（不使用Greengrass）

```bash
# 方法1: 直接运行（使用默认配置）
./build/hello_world config.json

# 观察输出，按Ctrl+C停止
```

**预期输出**：
```
[INFO] HelloWorld component starting...
[INFO] Configuration loaded from config.json
[INFO] Configuration:
[INFO]   Message: Hello from Greengrass!
[INFO]   Interval: 5 seconds
[INFO] Hello from Greengrass!
[INFO] Component running for 0 seconds
[INFO] Hello from Greengrass!
[INFO] Component running for 5 seconds
^C
[INFO] Received signal 2, shutting down gracefully...
[INFO] Component stopped
```

```bash
# 方法2: 使用测试脚本（后台运行10秒）
./test-local.sh
```

**思考问题**：
1. 为什么要使用单独的build目录？
2. Release和Debug构建模式有什么区别？
3. 如果编译失败，如何查看详细错误信息？

## 步骤 3: 深入理解Recipe文件

### 3.1 查看Recipe配置

```bash
cat recipe.yaml
```

### 3.2 逐段解析Recipe

Recipe是Greengrass组件的"配方"，定义了组件的所有行为。

#### 3.2.1 基本元数据

```yaml
---
RecipeFormatVersion: "2020-01-25"
ComponentName: "com.example.HelloWorld"
ComponentVersion: "1.0.0"
ComponentDescription: "A simple Hello World component"
ComponentPublisher: "Workshop"
```

**字段说明**：
- `RecipeFormatVersion`: Recipe格式版本（固定值）
- `ComponentName`: 组件唯一标识符
  - 使用反向域名格式（com.example.XXX）
  - 确保全局唯一性
- `ComponentVersion`: 语义化版本号（主.次.修订）
- `ComponentDescription`: 组件描述
- `ComponentPublisher`: 发布者名称

#### 3.2.2 默认配置

```yaml
ComponentConfiguration:
  DefaultConfiguration:
    message: "Hello from Greengrass!"
    interval: 5
```

**配置机制**：
- 这些是默认值，可以在部署时覆盖
- 组件代码通过配置文件读取这些值
- 支持配置合并（merge）和重置（reset）

**配置注入路径**：
```
Recipe DefaultConfiguration 
  → Greengrass配置管理 
  → 生成/tmp/config.json 
  → 组件读取
```

#### 3.2.3 生命周期脚本

Greengrass组件有三个生命周期阶段：

**1. Install阶段**（首次安装时执行一次）：

```yaml
Manifests:
  - Platform:
      os: linux
    Lifecycle:
      Install:
        Script: |
          echo "Installing HelloWorld component..."
          chmod +x {artifacts:decompressedPath}/hello_world/hello_world
```

**作用**：
- 设置文件权限
- 创建必要的目录
- 初始化资源

**变量说明**：
- `{artifacts:decompressedPath}`: Greengrass解压artifact的路径
  - 实际路径：`/greengrass/v2/packages/artifacts/com.example.HelloWorld/1.0.0/`

**2. Run阶段**（组件运行的主要逻辑）：

```yaml
      Run:
        Script: |
          cat > /tmp/config.json << EOF
          {
            "message": "{configuration:/message}",
            "interval": {configuration:/interval}
          }
          EOF
          {artifacts:decompressedPath}/hello_world/hello_world /tmp/config.json
```

**详细解析**：

第1-6行：创建配置文件
```bash
cat > /tmp/config.json << EOF
{
  "message": "{configuration:/message}",
  "interval": {configuration:/interval}
}
EOF
```
- 使用Here Document创建JSON文件
- `{configuration:/message}` 会被Greengrass替换为实际配置值
- 例如：`{configuration:/message}` → `"Hello from Greengrass!"`

第7行：启动组件
```bash
{artifacts:decompressedPath}/hello_world/hello_world /tmp/config.json
```
- 运行二进制文件
- 传递配置文件路径作为参数
- 这个进程会一直运行，直到收到停止信号

**3. Shutdown阶段**（组件停止时执行）：

```yaml
      Shutdown:
        Script: |
          echo "Shutting down HelloWorld component..."
          pkill -TERM hello_world || true
```

**作用**：
- 发送SIGTERM信号给进程
- `|| true` 确保即使进程不存在也不会失败
- 组件的信号处理函数会捕获SIGTERM并优雅关闭

#### 3.2.4 Artifacts（制品）

```yaml
Artifacts:
  - URI: "s3://your-bucket/com.example.HelloWorld/1.0.0/com.example.HelloWorld-1.0.0.zip"
    Unarchive: ZIP
```

**字段说明**：
- `URI`: S3上的组件包位置
- `Unarchive: ZIP`: 自动解压ZIP文件
- Greengrass会下载并解压到本地

**下载流程**：
```
S3 Bucket 
  → Greengrass下载 
  → 解压到/greengrass/v2/packages/artifacts/ 
  → 执行Install脚本
```

### 3.3 配置变量替换机制

Greengrass支持在Recipe中使用变量：

| 变量 | 说明 | 示例 |
|------|------|------|
| `{configuration:/key}` | 读取配置值 | `{configuration:/message}` |
| `{artifacts:path}` | Artifact根路径 | `/greengrass/v2/packages/artifacts/...` |
| `{artifacts:decompressedPath}` | 解压后的路径 | `/greengrass/v2/packages/artifacts/.../hello_world/` |
| `{work:path}` | 工作目录 | `/greengrass/v2/work/com.example.HelloWorld` |

### 3.4 思考问题

1. **为什么要将配置写入临时文件而不是直接传递参数？**
   - 提示：考虑配置复杂度和安全性

2. **如果组件崩溃，Greengrass会如何处理？**
   - 提示：查看Recipe中是否有重启策略

3. **如何修改配置而不重新部署组件？**
   - 提示：配置更新 vs 组件更新

4. **Install脚本什么时候会再次执行？**
   - 提示：考虑组件版本升级的场景

## 步骤 4: 手动打包组件

### 4.1 理解打包过程

打包的目的是将二进制文件和相关资源打包成ZIP文件，上传到S3供Greengrass下载。

**打包流程**：
```
build/hello_world (二进制)
  → 复制到artifacts/hello_world/
  → 打包成ZIP
  → 上传到S3
  → Greengrass下载并解压
```

### 4.2 手动执行打包步骤

```bash
# 步骤1: 清理旧的artifacts
rm -rf artifacts
mkdir -p artifacts

# 步骤2: 创建目录结构
mkdir -p artifacts/hello_world

# 步骤3: 复制二进制文件
cp build/hello_world artifacts/hello_world/

# 步骤4: 验证文件权限
ls -lh artifacts/hello_world/hello_world
chmod +x artifacts/hello_world/hello_world

# 步骤5: 创建ZIP包
cd artifacts
zip -r com.example.HelloWorld-1.0.0.zip hello_world/
cd ..

# 步骤6: 验证ZIP包
ls -lh artifacts/com.example.HelloWorld-1.0.0.zip
```

**预期输出**：
```
  adding: hello_world/ (stored 0%)
  adding: hello_world/hello_world (deflated 65%)
```

### 4.3 将YAML Recipe转换为JSON

Greengrass API需要JSON格式的Recipe：

```bash
# 方法1: 使用Python转换
python3 << 'EOF'
import yaml
import json

# 读取YAML
with open('recipe.yaml', 'r') as f:
    recipe = yaml.safe_load(f)

# 写入JSON
with open('artifacts/recipe.json', 'w') as f:
    json.dump(recipe, f, indent=2)
    
print("✅ Recipe converted to JSON")
EOF
```

```bash
# 方法2: 使用yq工具（如果已安装）
yq eval -o=json recipe.yaml > artifacts/recipe.json
```

### 4.4 验证打包内容

```bash
# 查看ZIP包内容（不解压）
unzip -l artifacts/com.example.HelloWorld-1.0.0.zip
```

**预期输出**：
```
Archive:  artifacts/com.example.HelloWorld-1.0.0.zip
  Length      Date    Time    Name
---------  ---------- -----   ----
        0  2026-01-22 02:00   hello_world/
    45678  2026-01-22 02:00   hello_world/hello_world
---------                     -------
    45678                     2 files
```

```bash
# 查看Recipe JSON（前30行）
head -30 artifacts/recipe.json

# 检查文件大小
du -h artifacts/com.example.HelloWorld-1.0.0.zip
```

### 4.5 使用自动化脚本

```bash
# 查看打包脚本内容
cat package.sh

# 执行打包脚本
./package.sh

# 验证结果
ls -lh artifacts/
```

### 4.6 思考问题

1. **为什么要保持特定的目录结构（hello_world/hello_world）？**
   - 提示：查看Recipe中的`{artifacts:decompressedPath}`路径

2. **ZIP包的大小主要取决于什么？**
   - 提示：二进制文件的编译选项（Debug vs Release）

3. **如果忘记设置可执行权限会怎样？**
   - 提示：Install脚本中的chmod命令

## 步骤 5: 上传组件到S3

### 5.1 理解S3在Greengrass中的作用

```
开发环境                    S3 Bucket                  Greengrass设备
┌─────────┐               ┌──────────┐               ┌──────────┐
│ 组件ZIP │  ──上传──>    │ Artifact │  ──下载──>    │ 本地解压 │
└─────────┘               └──────────┘               └──────────┘
```

**为什么使用S3？**
- ✅ 集中存储组件包
- ✅ 支持版本管理
- ✅ 高可用性和持久性
- ✅ 支持大规模设备部署

### 5.2 创建S3存储桶（如果还没有）

```bash
# 设置环境变量
export AWS_REGION="cn-north-1"  # 根据你的区域修改
export COMPONENT_BUCKET="iec104-greengrass-components-$(date +%s)"

# 创建S3存储桶
aws s3 mb s3://${COMPONENT_BUCKET} --region ${AWS_REGION}

# 保存存储桶名称供后续使用
echo ${COMPONENT_BUCKET} > /tmp/component_bucket.txt
echo "✅ Created bucket: ${COMPONENT_BUCKET}"
```

**预期输出**：
```
make_bucket: iec104-greengrass-components-1737518400
✅ Created bucket: iec104-greengrass-components-1737518400
```

**或使用现有存储桶**：
```bash
# 列出现有存储桶
aws s3 ls --region ${AWS_REGION}

# 使用现有存储桶
export COMPONENT_BUCKET="your-existing-bucket-name"
```

### 5.3 配置S3存储桶权限（重要）

Greengrass设备需要权限从S3下载组件：

```bash
# 获取Greengrass设备的IAM角色
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"  # 替换为你的Thing名称

# 查看Thing关联的角色
aws iot describe-thing --thing-name ${THING_NAME} --region ${AWS_REGION}

# 获取Token Exchange Role ARN
aws greengrassv2 get-core-device \
  --core-device-thing-name ${THING_NAME} \
  --region ${AWS_REGION} \
  --query 'coreDeviceThingName' \
  --output text
```

**添加S3读取权限**（如果还没有）：
```bash
# 创建策略文档
cat > /tmp/s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws-cn:s3:::${COMPONENT_BUCKET}/*"
    }
  ]
}
EOF

# 注意：实际环境中，应该将此策略附加到Greengrass Token Exchange Role
# 这里仅作演示，具体操作请参考AWS文档
```

### 5.4 上传组件包到S3

```bash
# 上传ZIP包到S3
aws s3 cp artifacts/com.example.HelloWorld-1.0.0.zip \
  s3://${COMPONENT_BUCKET}/com.example.HelloWorld/1.0.0/ \
  --region ${AWS_REGION}

# 验证上传成功
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.HelloWorld/1.0.0/ \
  --region ${AWS_REGION}
```

**预期输出**：
```
upload: artifacts/com.example.HelloWorld-1.0.0.zip to s3://iec104-greengrass-components-1737518400/com.example.HelloWorld/1.0.0/com.example.HelloWorld-1.0.0.zip

2026-01-22 02:00:00      45678 com.example.HelloWorld-1.0.0.zip
```

### 5.5 更新Recipe中的S3路径

```bash
# 方法1: 使用sed替换
sed "s|s3://your-bucket|s3://${COMPONENT_BUCKET}|g" \
  artifacts/recipe.json > artifacts/recipe-updated.json

# 方法2: 手动编辑
nano artifacts/recipe-updated.json
# 找到 "URI" 字段，替换为实际的S3路径
```

**验证替换结果**：
```bash
# 查看更新后的URI
grep "URI" artifacts/recipe-updated.json
```

**预期输出**：
```json
"URI": "s3://iec104-greengrass-components-1737518400/com.example.HelloWorld/1.0.0/com.example.HelloWorld-1.0.0.zip"
```

### 5.6 验证S3对象可访问性

```bash
# 获取对象元数据
aws s3api head-object \
  --bucket ${COMPONENT_BUCKET} \
  --key com.example.HelloWorld/1.0.0/com.example.HelloWorld-1.0.0.zip \
  --region ${AWS_REGION}

# 检查对象大小
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.HelloWorld/1.0.0/ \
  --region ${AWS_REGION} \
  --human-readable
```

### 5.7 思考问题

1. **为什么要使用S3而不是直接从本地部署？**
   - 提示：考虑多设备部署场景

2. **如何确保S3存储桶的安全性？**
   - 提示：IAM策略、存储桶策略、加密

3. **如果S3上传失败，可能是什么原因？**
   - 提示：权限、网络、存储桶策略

4. **组件包的S3路径有什么命名规范？**
   - 提示：查看URI中的路径结构

## 步骤 6: 在Greengrass中注册组件

### 6.1 理解组件注册

**注册过程**：
```
Recipe JSON 
  → AWS Greengrass API 
  → 验证格式 
  → 创建组件版本 
  → 可用于部署
```

**注册做了什么？**
- ✅ 验证Recipe格式和字段
- ✅ 在AWS账户中创建组件版本记录
- ✅ 关联S3 Artifact位置
- ✅ 使组件在部署时可选择

### 6.2 创建组件版本

```bash
# 确保环境变量已设置
echo "Bucket: ${COMPONENT_BUCKET}"
echo "Region: ${AWS_REGION}"

# 创建组件版本
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-updated.json \
  --region ${AWS_REGION}
```

**预期输出**：
```json
{
    "arn": "arn:aws-cn:greengrass:cn-north-1:123456789012:components:com.example.HelloWorld:versions:1.0.0",
    "componentName": "com.example.HelloWorld",
    "componentVersion": "1.0.0",
    "creationTimestamp": "2026-01-22T02:00:00.000000+00:00",
    "status": {
        "componentState": "REQUESTED",
        "message": "NONE",
        "errors": {}
    }
}
```

**状态说明**：
- `REQUESTED`: 组件版本已请求创建
- `DEPLOYABLE`: 组件可以部署（稍后会变成此状态）
- `FAILED`: 创建失败

### 6.3 验证组件已注册

```bash
# 方法1: 列出所有组件
aws greengrassv2 list-components --region ${AWS_REGION}

# 方法2: 列出特定组件的所有版本
aws greengrassv2 list-component-versions \
  --arn "arn:aws-cn:greengrass:cn-north-1:$(aws sts get-caller-identity --query Account --output text):components:com.example.HelloWorld" \
  --region ${AWS_REGION}
```

**预期输出**：
```json
{
    "componentVersions": [
        {
            "componentName": "com.example.HelloWorld",
            "componentVersion": "1.0.0",
            "arn": "arn:aws-cn:greengrass:cn-north-1:123456789012:components:com.example.HelloWorld:versions:1.0.0"
        }
    ]
}
```

```bash
# 方法3: 查看特定组件版本详情
aws greengrassv2 describe-component \
  --arn "arn:aws-cn:greengrass:cn-north-1:$(aws sts get-caller-identity --query Account --output text):components:com.example.HelloWorld:versions:1.0.0" \
  --region ${AWS_REGION}
```

**详细输出包含**：
- Recipe内容
- 创建时间
- 状态信息
- 平台要求

### 6.4 常见错误及解决方法

**错误1: AccessDeniedException**
```
An error occurred (AccessDeniedException) when calling the CreateComponentVersion operation
```

**解决方法**：
```bash
# 检查IAM权限
aws iam get-user --query 'User.Arn' --output text

# 需要的权限：
# - greengrass:CreateComponentVersion
# - greengrass:DescribeComponent
# - s3:GetObject (用于验证artifact)
```

**错误2: InvalidRecipeException**
```
Recipe validation failed: ...
```

**解决方法**：
```bash
# 验证JSON格式
cat artifacts/recipe-updated.json | jq '.'

# 检查必需字段
jq '.ComponentName, .ComponentVersion, .Manifests' artifacts/recipe-updated.json
```

**错误3: ResourceNotFoundException (S3)**
```
Unable to download artifact from S3
```

**解决方法**：
```bash
# 验证S3对象存在
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.HelloWorld/1.0.0/

# 检查Recipe中的URI
grep "URI" artifacts/recipe-updated.json
```

### 6.5 思考问题

1. **组件注册后可以修改吗？**
   - 提示：版本不可变性

2. **如果需要修改组件，应该怎么做？**
   - 提示：创建新版本

3. **组件注册和部署的区别是什么？**
   - 提示：注册是在云端，部署是到设备

## 步骤 7: 部署组件到设备

### 7.1 理解部署流程

```
AWS Cloud                          Greengrass Device
┌──────────────┐                  ┌──────────────┐
│ 创建部署请求  │ ────────────>    │ Nucleus接收  │
└──────────────┘                  └──────┬───────┘
                                         │
┌──────────────┐                  ┌──────▼───────┐
│ S3 Artifact  │ <────下载────    │ 下载组件包   │
└──────────────┘                  └──────┬───────┘
                                         │
                                  ┌──────▼───────┐
                                  │ 解压并安装   │
                                  └──────┬───────┘
                                         │
                                  ┌──────▼───────┐
                                  │ 启动组件     │
                                  └──────────────┘
```

### 7.2 获取目标设备信息

```bash
# 列出所有IoT Things
aws iot list-things --region ${AWS_REGION} --query 'things[*].thingName'

# 设置你的Thing名称（根据实际情况修改）
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"

# 获取账户ID
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 验证Thing存在
aws iot describe-thing --thing-name ${THING_NAME} --region ${AWS_REGION}
```

**预期输出**：
```json
{
    "defaultClientId": "GreengrassQuickStartCore-19be3781cbc",
    "thingName": "GreengrassQuickStartCore-19be3781cbc",
    "thingId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111",
    "thingArn": "arn:aws-cn:iot:cn-north-1:123456789012:thing/GreengrassQuickStartCore-19be3781cbc",
    "attributes": {},
    "version": 1
}
```

### 7.3 方法1: 通过CLI部署（推荐学习）

```bash
# 创建部署
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Lab1-$(date +%s)" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"Hello from Greengrass!\",\"interval\":5}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**命令解析**：
- `--target-arn`: 目标设备的ARN
- `--deployment-name`: 部署名称（建议包含时间戳）
- `--components`: JSON格式的组件配置
  - `componentVersion`: 要部署的版本
  - `configurationUpdate.merge`: 合并配置（覆盖默认值）

**预期输出**：
```json
{
    "deploymentId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE11111",
    "iotJobId": "a1b2c3d4-5678-90ab-cdef-EXAMPLE22222",
    "iotJobArn": "arn:aws-cn:iot:cn-north-1:123456789012:job/a1b2c3d4-5678-90ab-cdef-EXAMPLE22222"
}
```

```bash
# 保存部署ID
export DEPLOYMENT_ID="<your-deployment-id>"
```

### 7.4 检查部署状态

```bash
# 方法1: 查看部署状态
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'deploymentStatus' \
  --output text
```

**可能的状态**：
- `ACTIVE`: 部署成功并激活
- `IN_PROGRESS`: 正在部署中
- `COMPLETED`: 部署完成
- `FAILED`: 部署失败
- `CANCELED`: 部署已取消

```bash
# 方法2: 查看详细部署信息
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION}
```

**详细输出包含**：
- 部署状态
- 组件列表
- 失败原因（如果失败）
- 创建时间

```bash
# 方法3: 持续监控部署状态（每5秒刷新）
watch -n 5 "aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'deploymentStatus' \
  --output text"
```

### 7.5 方法2: 通过AWS控制台部署（可视化）

**步骤详解**：

1. **打开AWS IoT Console**
   ```
   https://console.amazonaws.cn/iot/home?region=cn-north-1
   ```

2. **导航到Greengrass组件**
   - 左侧菜单：**Manage** → **Greengrass devices** → **Components**

3. **找到你的组件**
   - 搜索：`com.example.HelloWorld`
   - 点击组件名称查看详情

4. **创建部署**
   - 点击右上角 **Deploy** 按钮
   - 选择 **Deploy to core device**

5. **选择目标设备**
   - 选择你的Core device（Thing名称）
   - 点击 **Next**

6. **选择组件**
   - 已自动选中 `com.example.HelloWorld`
   - 版本：`1.0.0`
   - 点击 **Next**

7. **配置组件**（可选）
   - 展开 `com.example.HelloWorld`
   - 修改配置值：
     ```json
     {
       "message": "Hello from Greengrass Workshop!",
       "interval": 5
     }
     ```
   - 点击 **Next**

8. **审查并部署**
   - 检查所有配置
   - 点击 **Deploy**

9. **监控部署状态**
   - 等待状态变为 **Completed**
   - 通常需要1-2分钟

### 7.6 在设备上监控部署

```bash
# 在Greengrass设备上执行

# 方法1: 查看Greengrass主日志
sudo tail -f /greengrass/v2/logs/greengrass.log

# 方法2: 过滤HelloWorld相关日志
sudo tail -f /greengrass/v2/logs/greengrass.log | grep HelloWorld

# 方法3: 使用Greengrass CLI
sudo /greengrass/v2/bin/greengrass-cli component list
```

**预期输出**：
```
Component Name: com.example.HelloWorld
    Version: 1.0.0
    State: RUNNING
    Configuration: {"message":"Hello from Greengrass!","interval":5}
```

### 7.7 常见部署问题

**问题1: 部署卡在IN_PROGRESS**
```bash
# 检查设备连接状态
aws iot describe-thing \
  --thing-name ${THING_NAME} \
  --region ${AWS_REGION}

# 检查设备上的Greengrass服务
sudo systemctl status greengrass
```

**问题2: 部署失败**
```bash
# 查看失败原因
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'components.*.componentStatusDetails'

# 查看设备日志
sudo tail -100 /greengrass/v2/logs/greengrass.log
```

**问题3: 组件无法下载artifact**
```bash
# 检查S3权限
aws s3 ls s3://${COMPONENT_BUCKET}/com.example.HelloWorld/1.0.0/

# 检查Greengrass Token Exchange Role权限
# 需要包含 s3:GetObject 权限
```

### 7.8 思考问题

1. **部署和配置更新有什么区别？**
   - 提示：是否重新下载artifact

2. **如果多个设备需要部署，如何批量操作？**
   - 提示：Thing Group

3. **部署失败后如何回滚？**
   - 提示：部署历史版本

## 步骤 8: 验证组件运行

### 8.1 理解Greengrass日志系统

```
/greengrass/v2/logs/
├── greengrass.log              # Nucleus主日志
├── com.example.HelloWorld.log  # 组件专用日志
├── ComponentManager.log        # 组件管理器日志
└── DeploymentService.log       # 部署服务日志
```

### 8.2 查看组件日志

```bash
# 方法1: 查看组件专用日志（推荐）
sudo tail -f /greengrass/v2/logs/com.example.HelloWorld.log
```

**预期输出**：
```
2026-01-22T02:00:00.000Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] HelloWorld component starting.... {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:00.100Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] Configuration loaded from /tmp/config.json. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:00.200Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] Configuration:. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:00.300Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO]   Message: Hello from Greengrass!. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:00.400Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO]   Interval: 5 seconds. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:00.500Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] Hello from Greengrass!. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:00.600Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] Component running for 0 seconds. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:05.500Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] Hello from Greengrass!. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
2026-01-22T02:00:05.600Z [INFO] (Copier) com.example.HelloWorld: stdout. [INFO] Component running for 5 seconds. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=RUNNING}
```

**日志格式解析**：
- `2026-01-22T02:00:00.000Z`: 时间戳（UTC）
- `[INFO]`: 日志级别
- `(Copier)`: Greengrass内部组件
- `com.example.HelloWorld: stdout.`: 组件标准输出
- `{scriptName=..., serviceName=..., currentState=...}`: 上下文信息

```bash
# 方法2: 查看Greengrass主日志
sudo tail -f /greengrass/v2/logs/greengrass.log | grep HelloWorld

# 方法3: 查看最近100行日志
sudo tail -100 /greengrass/v2/logs/com.example.HelloWorld.log

# 方法4: 搜索特定内容
sudo grep "Hello from" /greengrass/v2/logs/com.example.HelloWorld.log
```

### 8.3 检查组件状态

```bash
# 使用Greengrass CLI
sudo /greengrass/v2/bin/greengrass-cli component list
```

**预期输出**：
```
Components currently running in Greengrass:
Component Name: aws.greengrass.Nucleus
    Version: 2.12.0
    State: RUNNING
    Configuration: {...}
Component Name: com.example.HelloWorld
    Version: 1.0.0
    State: RUNNING
    Configuration: {"message":"Hello from Greengrass!","interval":5}
```

```bash
# 查看特定组件详情
sudo /greengrass/v2/bin/greengrass-cli component details \
  --name com.example.HelloWorld
```

### 8.4 检查进程状态

```bash
# 查看组件进程
ps aux | grep hello_world | grep -v grep
```

**预期输出**：
```
ggc_user  12345  0.0  0.1  12345  6789 ?  Sl  02:00  0:00 /greengrass/v2/packages/artifacts/com.example.HelloWorld/1.0.0/hello_world/hello_world /tmp/config.json
```

**字段说明**：
- `ggc_user`: Greengrass运行用户
- `12345`: 进程ID (PID)
- `Sl`: 进程状态（S=sleeping, l=multi-threaded）
- `/greengrass/v2/packages/artifacts/...`: 二进制文件路径

```bash
# 查看进程详细信息
sudo lsof -p <PID>  # 替换为实际PID

# 查看进程打开的文件
sudo ls -l /proc/<PID>/fd/
```

### 8.5 检查配置文件

```bash
# 查看Greengrass生成的配置文件
cat /tmp/config.json
```

**预期内容**：
```json
{
  "message": "Hello from Greengrass!",
  "interval": 5
}
```

### 8.6 验证组件自动重启

Greengrass会自动重启崩溃的组件：

```bash
# 实验1: 手动终止组件进程
sudo pkill hello_world

# 等待几秒
sleep 5

# 检查进程是否自动重启
ps aux | grep hello_world | grep -v grep

# 查看日志中的重启记录
sudo tail -20 /greengrass/v2/logs/greengrass.log | grep HelloWorld
```

**预期看到**：
```
[INFO] (pool-2-thread-12) com.example.HelloWorld: shell-runner-start. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=STARTING}
[INFO] (Copier) com.example.HelloWorld: Run script exited. {exitCode=143, serviceName=com.example.HelloWorld, currentState=RUNNING}
[INFO] (pool-2-thread-12) com.example.HelloWorld: shell-runner-start. {scriptName=services.com.example.HelloWorld.lifecycle.Run, serviceName=com.example.HelloWorld, currentState=STARTING}
```

### 8.7 常见问题排查

**问题1: 组件未启动**

```bash
# 检查组件状态
sudo /greengrass/v2/bin/greengrass-cli component list

# 如果状态是ERRORED或BROKEN
sudo /greengrass/v2/bin/greengrass-cli component details \
  --name com.example.HelloWorld

# 查看错误日志
sudo grep ERROR /greengrass/v2/logs/greengrass.log | grep HelloWorld
```

**问题2: 找不到日志文件**

```bash
# 列出所有日志文件
sudo ls -lh /greengrass/v2/logs/

# 等待组件启动（可能需要1-2分钟）
sleep 60

# 再次检查
sudo ls -lh /greengrass/v2/logs/com.example.HelloWorld.log
```

**问题3: 权限错误**

```bash
# 检查artifact文件权限
sudo ls -la /greengrass/v2/packages/artifacts/com.example.HelloWorld/1.0.0/

# 检查Greengrass用户
id ggc_user

# 检查文件所有者
sudo ls -l /greengrass/v2/packages/artifacts/com.example.HelloWorld/1.0.0/hello_world/hello_world
```

**问题4: 配置文件未生成**

```bash
# 检查/tmp/config.json
ls -l /tmp/config.json

# 如果不存在，检查Run脚本是否正确执行
sudo grep "cat > /tmp/config.json" /greengrass/v2/logs/greengrass.log
```

### 8.8 日志分析技巧

```bash
# 按时间范围查看日志
sudo grep "2026-01-22T02:0[0-5]" /greengrass/v2/logs/com.example.HelloWorld.log

# 统计日志行数
sudo wc -l /greengrass/v2/logs/com.example.HelloWorld.log

# 查看日志文件大小
sudo du -h /greengrass/v2/logs/com.example.HelloWorld.log

# 实时监控多个日志文件
sudo tail -f /greengrass/v2/logs/greengrass.log \
             /greengrass/v2/logs/com.example.HelloWorld.log
```

### 8.9 思考问题

1. **为什么组件日志会包含Greengrass的上下文信息？**
   - 提示：Greengrass如何捕获组件的stdout/stderr

2. **如果组件频繁重启，可能是什么原因？**
   - 提示：检查组件代码的退出条件

3. **日志文件会无限增长吗？**
   - 提示：Greengrass的日志轮转机制

## 步骤 9: 动态更新配置（无需重新部署）

### 9.1 理解配置更新机制

**配置更新 vs 组件更新**：

| 操作 | 配置更新 | 组件更新 |
|------|----------|----------|
| 是否重新下载artifact | ❌ 否 | ✅ 是 |
| 是否重启组件 | ✅ 是 | ✅ 是 |
| 速度 | 快（秒级） | 慢（分钟级） |
| 适用场景 | 调整参数 | 代码变更 |

**配置更新流程**：
```
创建部署（仅配置）
  → Greengrass接收
  → 停止组件
  → 更新配置文件
  → 重启组件
  → 新配置生效
```

### 9.2 实验1: 修改消息内容和间隔

```bash
# 创建配置更新部署
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Config-Update-$(date +%s)" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"Configuration updated!\",\"interval\":3}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**观察配置更新效果**：

```bash
# 终端1: 实时查看日志
sudo tail -f /greengrass/v2/logs/com.example.HelloWorld.log

# 你应该看到：
# 1. 组件停止的日志
# 2. 组件重启的日志
# 3. 新的消息内容："Configuration updated!"
# 4. 新的间隔：3秒（而不是5秒）
```

**预期日志输出**：
```
[INFO] Received signal 15, shutting down gracefully...
[INFO] Component stopped
[INFO] HelloWorld component starting...
[INFO] Configuration loaded from /tmp/config.json
[INFO] Configuration:
[INFO]   Message: Configuration updated!
[INFO]   Interval: 3 seconds
[INFO] Configuration updated!
[INFO] Component running for 0 seconds
[INFO] Configuration updated!
[INFO] Component running for 3 seconds
```

```bash
# 终端2: 验证配置文件
cat /tmp/config.json
```

**预期内容**：
```json
{
  "message": "Configuration updated!",
  "interval": 3
}
```

### 9.3 实验2: 快速输出模式

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Fast-Mode-$(date +%s)" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"Fast mode!\",\"interval\":1}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**观察效果**：
- 消息每1秒输出一次
- 日志文件增长速度加快

### 9.3 实验3: 慢速输出模式

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Slow-Mode-$(date +%s)" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"Slow mode\",\"interval\":10}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**观察效果**：
- 消息每10秒输出一次
- 适合长时间运行的场景

### 9.4 实验4: 部分配置更新（配置合并）

只更新一个字段，其他字段保持不变：

```bash
# 只更新消息，保持间隔不变
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Partial-Update-$(date +%s)" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"Only message changed\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**验证结果**：
```bash
cat /tmp/config.json
```

**预期**：
```json
{
  "message": "Only message changed",
  "interval": 10  // 保持上一次的值
}
```

### 9.5 实验5: 重置为默认配置

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "HelloWorld-Reset-Default-$(date +%s)" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "reset": ["/"]
      }
    }
  }' \
  --region ${AWS_REGION}
```

**效果**：
- 所有配置恢复为Recipe中的DefaultConfiguration
- `message`: "Hello from Greengrass!"
- `interval`: 5

### 9.6 通过控制台更新配置

**步骤**：

1. 打开AWS IoT Console
2. 导航到 **Greengrass devices** → **Core devices**
3. 选择你的设备
4. 点击 **Deployments** 标签
5. 点击当前部署的 **Revise** 按钮
6. 展开 `com.example.HelloWorld`
7. 修改配置：
   ```json
   {
     "message": "Updated from console",
     "interval": 7
   }
   ```
8. 点击 **Deploy**

### 9.7 监控配置更新过程

```bash
# 方法1: 监控部署状态
watch -n 2 "aws greengrassv2 list-effective-deployments \
  --core-device-thing-name ${THING_NAME} \
  --region ${AWS_REGION} \
  --query 'effectiveDeployments[0].deploymentStatus' \
  --output text"

# 方法2: 监控组件状态
watch -n 2 "sudo /greengrass/v2/bin/greengrass-cli component list | grep -A 3 HelloWorld"

# 方法3: 实时查看日志
sudo tail -f /greengrass/v2/logs/greengrass.log | grep -E "HelloWorld|configuration"
```

### 9.8 配置更新最佳实践

**1. 验证配置值**：
```bash
# 在更新前验证JSON格式
echo '{"message":"Test","interval":5}' | jq '.'
```

**2. 记录配置历史**：
```bash
# 保存配置快照
aws greengrassv2 get-deployment \
  --deployment-id ${DEPLOYMENT_ID} \
  --region ${AWS_REGION} \
  --query 'components."com.example.HelloWorld".configurationUpdate' \
  > config-snapshot-$(date +%s).json
```

**3. 渐进式更新**：
- 先在测试设备上验证
- 再推送到生产设备

**4. 监控更新影响**：
- 观察组件重启时间
- 检查是否有错误日志

### 9.9 思考问题

1. **配置更新会导致数据丢失吗？**
   - 提示：组件重启时的状态保存

2. **如何实现配置的版本控制？**
   - 提示：部署历史和回滚

3. **大规模设备如何批量更新配置？**
   - 提示：Thing Group部署

4. **配置更新失败如何回滚？**
   - 提示：部署上一个成功的配置

## 步骤 10: 停止组件

```bash
# 移除组件
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):thing/${THING_NAME}" \
  --deployment-name "Remove-HelloWorld" \
  --components '{}' \
  --region ${AWS_REGION}
```

## 故障排除

### 组件无法启动

```bash
# 检查组件状态
sudo /greengrass/v2/bin/greengrass-cli component details -n com.example.HelloWorld

# 查看详细日志
sudo cat /greengrass/v2/logs/com.example.HelloWorld.log
```

### 权限问题

确保Greengrass有执行权限：
```bash
sudo chmod +x /greengrass/v2/packages/artifacts/com.example.HelloWorld/1.0.0/hello_world
```

### S3访问问题

确保Greengrass Token Exchange Role有S3读取权限：
```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject"
  ],
  "Resource": "arn:aws:s3:::your-bucket/*"
}
```

## 清理资源

```bash
# 删除部署
aws greengrassv2 cancel-deployment --deployment-id <deployment-id>

# 删除组件版本（可选）
aws greengrassv2 delete-component \
  --arn "arn:aws:greengrass:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):components:com.example.HelloWorld:versions:1.0.0"
```

## 关键概念总结

### 1. 组件（Component）
- Greengrass的基本部署单元
- 包含代码、配置、依赖关系和生命周期定义
- 可以独立版本管理和部署
- 支持跨平台（通过Platform字段）

### 2. Recipe
- 组件的"配方"文件，定义组件的所有行为
- 包含元数据、配置、生命周期脚本、依赖关系
- 支持YAML和JSON格式
- 版本不可变（修改需要创建新版本）

### 3. Artifact（制品）
- 组件的实际文件（二进制、脚本、配置等）
- 存储在S3，按需下载到设备
- 支持自动解压（ZIP、TAR等）

### 4. 生命周期（Lifecycle）

| 阶段 | 执行时机 | 典型用途 |
|------|----------|----------|
| **Install** | 首次安装或版本升级 | 设置权限、创建目录 |
| **Run** | 每次启动 | 启动主进程 |
| **Shutdown** | 停止或更新前 | 优雅关闭、清理资源 |

### 5. 配置（Configuration）
- 在Recipe中定义DefaultConfiguration
- 可在部署时动态覆盖
- 支持配置合并（merge）和重置（reset）
- 无需重新打包即可更新

### 6. 部署（Deployment）
- 将组件推送到一个或多个设备的过程
- 支持单设备部署和Thing Group批量部署
- 支持回滚和失败处理

## 实验总结

通过本实验，你已经：
- ✅ 创建了第一个C++ Greengrass组件
- ✅ 理解了组件的完整生命周期
- ✅ 掌握了构建、打包、部署的完整流程
- ✅ 学会了查看日志和调试组件
- ✅ 实践了动态配置更新

## 常见问题 (FAQ)

**Q1: 如何查看组件的所有版本？**
```bash
aws greengrassv2 list-component-versions \
  --arn "arn:aws-cn:greengrass:${AWS_REGION}:${ACCOUNT_ID}:components:com.example.HelloWorld" \
  --region ${AWS_REGION}
```

**Q2: 配置更新和组件更新有什么区别？**
- 配置更新：只修改配置，不重新下载artifact，速度快
- 组件更新：修改代码或Recipe，需要重新下载artifact

**Q3: 组件崩溃后会自动重启吗？**
是的，Greengrass会自动重启ERRORED状态的组件。

## 下一步

完成Lab 1后，继续：
- **[Lab 2: 配置管理和日志](../lab2-config-logging/README.md)** - 学习多级日志系统
- **Lab 3**: 部署IEC104模拟器组件
- **Lab 4**: 部署IEC104数据采集组件
- **Lab 5**: AWS IoT Core集成

## 参考资料

- [AWS IoT Greengrass V2 文档](https://docs.aws.amazon.com/greengrass/v2/developerguide/)
- [组件Recipe参考](https://docs.aws.amazon.com/greengrass/v2/developerguide/component-recipe-reference.html)
- [Greengrass CLI命令](https://docs.aws.amazon.com/greengrass/v2/developerguide/greengrass-cli-component.html)

---

**🎉 恭喜完成Lab 1！**
