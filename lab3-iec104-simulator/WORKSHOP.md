# Lab 3 Workshop 向导: IEC104 模拟器 - Docker 容器化部署

## 🎯 实验目标

通过本实验,你将学习:
- 理解 IEC 60870-5-104 工业协议基础
- 编写 Dockerfile 实现应用容器化
- 使用多阶段构建优化镜像大小
- 将 Docker 镜像推送到 Amazon ECR
- 在 Greengrass 中运行 Docker 容器
- 理解 Greengrass Docker 应用管理

**预计时间**: 90 分钟  
**难度级别**: ⭐⭐⭐ 中高级

## 📋 前置条件

### 必需环境
- ✅ 完成 Lab 1 和 Lab 2
- ✅ 了解 Docker 基础概念
- ✅ Greengrass 设备已安装 Docker
- ✅ 理解 TCP/IP 网络编程基础

### 验证环境

```bash
# 检查 Docker 安装
docker --version
docker ps

# 检查 Docker 服务状态
sudo systemctl status docker

# 检查 ECR 访问权限
aws ecr describe-repositories --region ${AWS_REGION}
```

### 配置 Docker 权限 ⚠️ 重要

```bash
# 添加用户到 docker 组
sudo usermod -aG docker ggc_user
sudo usermod -aG docker ubuntu

# 验证
groups ggc_user
groups ubuntu

# 重启 Docker 服务
sudo systemctl restart docker
```

## 🏗️ 架构概览

### 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Cloud                                 │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Amazon ECR (Elastic Container Registry)           │    │
│  │                                                     │    │
│  │  Repository: iec104-simulator                      │    │
│  │  Image: xxx.dkr.ecr.ap-northeast-1.amazonaws.com/  │    │
│  │         iec104-simulator:1.0.0                     │    │
│  └────────────────────────────────────────────────────┘    │
│                              ▲                               │
│                              │ docker push                   │
│                              │                               │
└──────────────────────────────┼───────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  开发环境            │
                    │  docker build       │
                    └──────────┬──────────┘
                               │
┌──────────────────────────────┼───────────────────────────────┐
│         Greengrass Core Device                               │
│                              │ docker pull                   │
│                              ▼                               │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Docker Engine                                     │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────┐     │    │
│  │  │  Container: iec104-simulator             │     │    │
│  │  │                                           │     │    │
│  │  │  ┌────────────────────────────────┐     │     │    │
│  │  │  │  IEC104 Simulator Binary       │     │     │    │
│  │  │  │  - TCP Server on port 2404     │     │     │    │
│  │  │  │  - Simulate 6 data points      │     │     │    │
│  │  │  └────────────────────────────────┘     │     │    │
│  │  │                                           │     │    │
│  │  │  Network: host mode (共享主机网络)       │     │    │
│  │  └──────────────────────────────────────────┘     │    │
│  │                                                     │    │
│  └────────────────────────────────────────────────────┘    │
│                              ▲                               │
│                              │ 管理容器生命周期              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Greengrass Component                              │    │
│  │  com.example.IEC104SimulatorDocker                 │    │
│  │  - 拉取镜像                                         │    │
│  │  - 启动容器                                         │    │
│  │  - 监控状态                                         │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### 核心概念

#### 1. Docker 容器化

**传统部署 vs Docker 部署**:

| 特性 | 传统部署 | Docker 部署 |
|------|----------|------------|
| 依赖管理 | 手动安装 | 镜像包含所有依赖 |
| 环境一致性 | 难以保证 | 完全一致 |
| 隔离性 | 进程级 | 容器级 (更强) |
| 资源限制 | 难以控制 | 易于配置 |
| 版本管理 | 复杂 | 镜像标签 |
| 回滚 | 困难 | 切换镜像版本 |

**Greengrass 中的 Docker 优势**:
- ✅ **隔离性**: 容器之间互不影响
- ✅ **可移植性**: 同一镜像可在不同设备运行
- ✅ **资源控制**: 限制 CPU、内存使用
- ✅ **快速部署**: 拉取镜像即可运行
- ✅ **版本管理**: 通过镜像标签管理版本

#### 2. IEC 60870-5-104 协议

**IEC104** 是电力系统中广泛使用的通信协议:
- **应用场景**: SCADA 系统、变电站自动化、风电场监控
- **传输层**: 基于 TCP/IP
- **默认端口**: 2404
- **数据类型**: 遥测 (模拟量)、遥信 (开关量)、遥控

**本 Lab 模拟的数据点**:

| 地址 | 名称 | 设备 | 基准值 | 变化范围 | 单位 |
|------|------|------|--------|----------|------|
| 1001 | wind_turbine_1_active_power | 风机 | 1500 | ±200 | kW |
| 1002 | wind_turbine_1_reactive_power | 风机 | 200 | ±50 | kVar |
| 1003 | wind_turbine_1_wind_speed | 风机 | 8.5 | ±2.0 | m/s |
| 2001 | energy_storage_soc | 储能 | 75 | ±10 | % |
| 2002 | energy_storage_charge_power | 储能 | 500 | ±100 | kW |
| 3001 | substation_voltage | 变电站 | 35 | ±1.0 | kV |

#### 3. Amazon ECR

**ECR (Elastic Container Registry)** 是 AWS 的容器镜像仓库:
- 完全托管的 Docker 镜像仓库
- 与 IAM 集成的访问控制
- 镜像加密和扫描
- 高可用性和持久性

#### 4. 多阶段构建

```
Stage 1: Builder
  ├── 安装编译工具
  ├── 编译源代码
  └── 生成二进制文件
       ↓
Stage 2: Runtime
  ├── 使用轻量级基础镜像
  ├── 只复制二进制文件
  └── 最小化镜像大小
```

**优势**:
- 减小最终镜像大小 (可减少 80%)
- 不包含编译工具和源代码
- 提高安全性
- 加快镜像拉取速度

## 📁 项目结构

```
lab3-iec104-simulator/
├── src/
│   └── simulator.cpp          # IEC104 模拟器源代码
├── lib60870/                   # IEC104 协议库
│   └── lib60870-C/
├── nlohmann/                   # JSON 库头文件
│   ├── json.hpp
│   ├── adl_serializer.hpp
│   └── detail/
├── Dockerfile                  # Docker 镜像构建文件
├── CMakeLists.txt              # CMake 构建配置
├── config.json                 # 模拟器配置
├── recipe.yaml                 # Greengrass 组件配置
├── docker-build.sh             # Docker 构建脚本
├── push-to-ecr.sh              # ECR 推送脚本
└── deploy.sh                   # 部署脚本
```

## 实验分为三个部分

### Part 1: Docker 镜像构建 (步骤 1-4)
- 理解 Dockerfile 和多阶段构建
- 本地构建 Docker 镜像
- 测试容器运行

### Part 2: 推送到 ECR (步骤 5-6)
- 创建 ECR 仓库
- 配置 IAM 权限
- 推送镜像到 ECR

### Part 3: Greengrass 部署 (步骤 7-9)
- 创建 Greengrass Docker 组件
- 部署到设备
- 验证和测试


---

# Part 1: Docker 镜像构建

## 🔧 实验步骤

### 步骤 1: 准备实验环境

#### 1.1 进入实验目录

```bash
/home/ubuntu/greengrass-iec104-cpp-workshop/lab3-iec104-simulator
```

#### 1.2 设置环境变量

```bash
# 设置 AWS 区域
export AWS_REGION="ap-northeast-1"

# 设置镜像信息
export IMAGE_NAME="iec104-simulator"
export IMAGE_TAG="1.0.0"

# 获取账户 ID
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 设置 ECR 仓库 URI
export ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}"

# 验证环境变量
echo "AWS Region: ${AWS_REGION}"
echo "Account ID: ${ACCOUNT_ID}"
echo "ECR Repo: ${ECR_REPO}"
```

---

### 步骤 2: 理解 Dockerfile

#### 2.1 查看 Dockerfile

```bash
cat Dockerfile
```

#### 2.2 多阶段构建解析

**Dockerfile 结构**:

```dockerfile
# ============================================
# Stage 1: Builder (构建阶段)
# ============================================
FROM public.ecr.aws/ubuntu/ubuntu:22.04 AS builder

# 安装编译工具
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# 复制源代码和依赖
WORKDIR /build
COPY lib60870/ lib60870/
COPY nlohmann/ /usr/local/include/nlohmann/
COPY src/ src/
COPY CMakeLists.txt .

# 编译
RUN mkdir build && cd build && \
    cmake .. && \
    make

# ============================================
# Stage 2: Runtime (运行阶段)
# ============================================
FROM public.ecr.aws/ubuntu/ubuntu:22.04

# 只安装运行时依赖
RUN apt-get update && apt-get install -y \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# 从 builder 阶段复制二进制文件
COPY --from=builder /build/build/iec104_simulator /usr/local/bin/
COPY config.json /etc/iec104/config.json

# 暴露端口
EXPOSE 2404

# 启动命令
CMD ["/usr/local/bin/iec104_simulator", "/etc/iec104/config.json"]
```

#### 2.3 关键设计点

**1. 使用 AWS Public ECR 基础镜像**

```dockerfile
FROM public.ecr.aws/ubuntu/ubuntu:22.04
```

**为什么?**
- ✅ 避免 Docker Hub 在中国访问不稳定
- ✅ 更快的下载速度
- ✅ 与 AWS 服务集成更好

**2. 多阶段构建**

```
Builder Stage (大镜像)
  - 包含编译工具 (gcc, cmake)
  - 包含源代码
  - 大小: ~500MB
       ↓ 只复制二进制
Runtime Stage (小镜像)
  - 只包含运行时依赖
  - 只包含二进制文件
  - 大小: ~80MB
```

**3. 清理 apt 缓存**

```dockerfile
RUN apt-get update && apt-get install -y ... \
    && rm -rf /var/lib/apt/lists/*
```

**为什么?**
- 减小镜像大小
- 删除不必要的缓存文件

**4. 复制完整的 nlohmann 目录**

```dockerfile
COPY nlohmann/ /usr/local/include/nlohmann/
```

**为什么?**
- nlohmann/json 不是单文件库
- 需要 adl_serializer.hpp, detail/, thirdparty/ 等依赖

#### 2.4 镜像大小对比

| 构建方式 | 镜像大小 | 说明 |
|---------|---------|------|
| 单阶段构建 | ~500MB | 包含编译工具 |
| 多阶段构建 | ~80MB | 只包含运行时 |
| 优化比例 | **84% 减少** | 显著提升 |

---

### 步骤 3: 本地构建 Docker 镜像

#### 3.1 执行构建

**使用构建脚本**:

```bash
# 查看构建脚本
cat docker-build.sh

# 执行构建
./docker-build.sh
```

**手动构建**:

```bash
# 构建镜像
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

# 查看构建过程
# - Stage 1: Builder
#   [1/5] 安装编译工具
#   [2/5] 复制源代码
#   [3/5] 编译
# - Stage 2: Runtime
#   [4/5] 安装运行时依赖
#   [5/5] 复制二进制文件
```

**预期输出**:
```
[+] Building 120.5s (15/15) FINISHED
 => [internal] load build definition from Dockerfile
 => [internal] load .dockerignore
 => [builder 1/5] FROM public.ecr.aws/ubuntu/ubuntu:22.04
 => [builder 2/5] RUN apt-get update && apt-get install -y build-essential cmake
 => [builder 3/5] COPY lib60870/ lib60870/
 => [builder 4/5] COPY nlohmann/ /usr/local/include/nlohmann/
 => [builder 5/5] RUN mkdir build && cd build && cmake .. && make
 => [stage-1 1/3] FROM public.ecr.aws/ubuntu/ubuntu:22.04
 => [stage-1 2/3] RUN apt-get update && apt-get install -y libstdc++6
 => [stage-1 3/3] COPY --from=builder /build/build/iec104_simulator /usr/local/bin/
 => exporting to image
 => => naming to docker.io/library/iec104-simulator:1.0.0
```

#### 3.2 验证镜像

```bash
# 查看镜像列表
docker images | grep iec104-simulator
```

**预期输出**:
```
iec104-simulator   1.0.0   a1b2c3d4e5f6   2 minutes ago   78.5MB
```

```bash
# 查看镜像详细信息
docker inspect ${IMAGE_NAME}:${IMAGE_TAG}

# 查看镜像层
docker history ${IMAGE_NAME}:${IMAGE_TAG}
```

---

### 步骤 4: 本地测试容器

#### 4.1 启动容器

```bash
# 启动容器 (前台运行)
docker run --rm --name iec104-simulator-test \
  -p 2404:2404 \
  ${IMAGE_NAME}:${IMAGE_TAG}
```

**预期输出**:
```
[INFO] IEC104 Simulator starting...
[INFO] Configuration loaded from /etc/iec104/config.json
[INFO] Listening on port 2404
[INFO] Simulating 6 data points
[INFO] Server started successfully
```

**后台运行**:

```bash
# 启动容器 (后台运行)
docker run -d --name iec104-simulator-test \
  -p 2404:2404 \
  ${IMAGE_NAME}:${IMAGE_TAG}

# 查看容器状态
docker ps | grep iec104-simulator

# 查看容器日志
docker logs -f iec104-simulator-test
```

#### 4.2 测试 IEC104 连接

**使用 telnet 测试端口**:

```bash
# 测试端口是否开放
telnet localhost 2404
```

**预期输出**:
```
Trying 127.0.0.1...
Connected to localhost.
Escape character is '^]'.
```

**使用 nc (netcat) 测试**:

```bash
# 测试 TCP 连接
nc -zv localhost 2404
```

**预期输出**:
```
Connection to localhost 2404 port [tcp/*] succeeded!
```

#### 4.3 查看容器资源使用

```bash
# 查看容器资源使用情况
docker stats iec104-simulator-test --no-stream
```

**预期输出**:
```
CONTAINER ID   NAME                      CPU %   MEM USAGE / LIMIT   MEM %   NET I/O     BLOCK I/O
a1b2c3d4e5f6   iec104-simulator-test     0.01%   2.5MiB / 7.6GiB     0.03%   1.2kB / 0B  0B / 0B
```

#### 4.4 进入容器调试

```bash
# 进入容器
docker exec -it iec104-simulator-test /bin/bash

# 在容器内执行命令
ps aux | grep iec104
netstat -tlnp | grep 2404
cat /etc/iec104/config.json

# 退出容器
exit
```

#### 4.5 停止和清理容器

```bash
# 停止容器
docker stop iec104-simulator-test

# 删除容器
docker rm iec104-simulator-test

# 或者一步完成
docker rm -f iec104-simulator-test
```

---

# Part 2: 推送到 ECR

### 步骤 5: 创建 ECR 仓库

#### 5.1 理解 ECR 仓库结构

```
AWS Account
  └── ECR Registry
      └── Repository: iec104-simulator
          ├── Image: 1.0.0
          ├── Image: 1.0.1
          └── Image: latest
```

**ECR URI 格式**:
```
<account-id>.dkr.ecr.<region>.amazonaws.com/<repository-name>:<tag>
```

**示例**:
```
123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator:1.0.0
```

#### 5.2 创建 ECR 仓库

**使用 AWS CLI**:

```bash
# 创建仓库
aws ecr create-repository \
  --repository-name ${IMAGE_NAME} \
  --region ${AWS_REGION} \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256
```

**预期输出**:
```json
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:ap-northeast-1:123456789012:repository/iec104-simulator",
        "registryId": "123456789012",
        "repositoryName": "iec104-simulator",
        "repositoryUri": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator",
        "createdAt": "2026-01-23T10:00:00+00:00"
    }
}
```

**使用 AWS 管理控制台**:

1. 打开 [ECR 控制台](https://console.amazonaws.cn/ecr/)
2. 点击 **创建仓库**
3. 输入仓库名称: `iec104-simulator`
4. 启用 **扫描推送时扫描**
5. 选择加密: **AES-256**
6. 点击 **创建仓库**

![创建 ECR 仓库](images/ecr-create-repository.png)
*截图位置: 创建 ECR 仓库界面*

#### 5.3 验证仓库创建

```bash
# 列出所有仓库
aws ecr describe-repositories \
  --region ${AWS_REGION} \
  --query 'repositories[*].[repositoryName,repositoryUri]' \
  --output table
```

**预期输出**:
```
----------------------------------------------------------------------------------
|                           DescribeRepositories                                 |
+-------------------+-----------------------------------------------------------+
|  iec104-simulator |  123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator  |
+-------------------+-----------------------------------------------------------+
```

---

### 步骤 6: 推送镜像到 ECR

#### 6.1 配置 IAM 权限 ⚠️ 重要

**所需权限**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
```

**检查当前权限**:

```bash
# 测试 ECR 访问
aws ecr describe-repositories --region ${AWS_REGION}

# 如果成功,说明权限已配置
```

> **注意**: 在生产环境中,需要将 ECR 权限附加到 IAM 用户或角色。

#### 6.2 登录到 ECR

```bash
# 获取登录密码并登录
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

**预期输出**:
```
Login Succeeded
```

**登录原理**:
1. `aws ecr get-login-password` 获取临时密码 (12 小时有效)
2. `docker login` 使用密码登录到 ECR
3. 凭证保存在 `~/.docker/config.json`

#### 6.3 标记镜像

```bash
# 为镜像添加 ECR 标签
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REPO}:${IMAGE_TAG}

# 验证标记
docker images | grep iec104-simulator
```

**预期输出**:
```
iec104-simulator   1.0.0   a1b2c3d4e5f6   10 minutes ago   78.5MB
123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator   1.0.0   a1b2c3d4e5f6   10 minutes ago   78.5MB
```

#### 6.4 推送镜像

```bash
# 推送镜像到 ECR
docker push ${ECR_REPO}:${IMAGE_TAG}
```

**预期输出**:
```
The push refers to repository [123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator]
5f70bf18a086: Pushed
e16c52e9c8e5: Pushed
1.0.0: digest: sha256:abc123... size: 1234
```

**使用推送脚本**:

(以上手动执行了推送，可忽略)

```bash
# 查看推送脚本
cat push-to-ecr.sh

# 执行推送
./push-to-ecr.sh
```

#### 6.5 验证镜像推送

**使用 AWS CLI**:

```bash
# 列出仓库中的镜像
aws ecr list-images \
  --repository-name ${IMAGE_NAME} \
  --region ${AWS_REGION} \
  --query 'imageIds[*].[imageTag,imageDigest]' \
  --output table
```

**预期输出**:
```
---------------------------------------------------------
|                     ListImages                        |
+-------+-----------------------------------------------+
|  1.0.0|  sha256:abc123...                             |
+-------+-----------------------------------------------+
```

**使用 AWS 管理控制台**:

1. 打开 [ECR 控制台](https://console.amazonaws.cn/ecr/)
2. 点击仓库名称: `iec104-simulator`
3. 查看镜像列表

![ECR 镜像列表](images/ecr-image-list.png)
*截图位置: ECR 镜像列表*

**查看镜像详情**:

```bash
# 查看镜像详细信息
aws ecr describe-images \
  --repository-name ${IMAGE_NAME} \
  --image-ids imageTag=${IMAGE_TAG} \
  --region ${AWS_REGION}
```


---

# Part 3: Greengrass 部署

### 步骤 7: 创建 Greengrass Docker 组件

#### 7.1 理解 Docker 组件 Recipe

**Docker 组件的特殊之处**:

- Greengrass v2 中运行 Docker 容器**不需要特殊的组件类型**
- 使用标准 Recipe 格式,在 Lifecycle 脚本中手动管理 Docker 容器
- 依赖 `aws.greengrass.DockerApplicationManager` 组件来管理 Docker 镜像下载

**为什么不使用 aws.greengrass.docker?**
- `aws.greengrass.docker` 类型在 Greengrass v2 中已弃用
- 现在使用标准 Recipe + Lifecycle 脚本提供更大灵活性
- 可以自定义容器启动参数和网络配置

#### 7.2 查看 Recipe 配置

```bash
cat recipe.yaml
```

**Recipe 关键部分解析**:

**1. 组件元数据**:
```yaml
RecipeFormatVersion: "2020-01-25"
ComponentName: "com.example.IEC104SimulatorDocker"
ComponentVersion: "1.0.0"
ComponentDescription: "IEC104 Simulator running in Docker container"
# 注意:不需要 ComponentType 字段
```

**2. 配置参数**:
```yaml
ComponentConfiguration:
  DefaultConfiguration:
    ImageUri: "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator:1.0.0"
    ContainerName: "iec104-simulator"
    HostPort: "2404"
```

**3. Install 脚本** (ECR 登录):
```yaml
Install:
  Script: |
    IMAGE_URI="{configuration:/ImageUri}"
    
    # 检查是否是 ECR 镜像
    if echo "${IMAGE_URI}" | grep -q "ecr"; then
      echo "ECR image detected, logging in..."
      AWS_REGION=$(echo ${IMAGE_URI} | cut -d'.' -f4)
      
      # 登录到 ECR
      aws ecr get-login-password --region ${AWS_REGION} | \
        docker login --username AWS --password-stdin \
        $(echo ${IMAGE_URI} | cut -d'/' -f1)
      
      # 拉取镜像
      docker pull ${IMAGE_URI}
    fi
```

**4. Run 脚本** (启动容器):
```yaml
Run:
  Script: |
    IMAGE_URI="{configuration:/ImageUri}"
    CONTAINER_NAME="{configuration:/ContainerName}"
    HOST_PORT="{configuration:/HostPort}"
    
    # 停止并删除旧容器
    docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
    
    # 启动新容器
    docker run -d \
      --name ${CONTAINER_NAME} \
      --network host \
      --restart unless-stopped \
      ${IMAGE_URI}
    
    echo "Container ${CONTAINER_NAME} started"
    
    # 监控容器状态 (保持脚本运行)
    while docker ps | grep -q ${CONTAINER_NAME}; do
      sleep 10
    done
    
    echo "Container stopped unexpectedly"
```

**5. Shutdown 脚本** (停止容器):
```yaml
Shutdown:
  Script: |
    CONTAINER_NAME="{configuration:/ContainerName}"
    
    echo "Stopping container ${CONTAINER_NAME}..."
    docker stop ${CONTAINER_NAME} || true
    docker rm ${CONTAINER_NAME} || true
    
    echo "Container ${CONTAINER_NAME} stopped"
```

#### 7.3 关键设计点 ⚠️

**1. 使用 sh 兼容语法**

```bash
# ❌ 错误 - bash 语法
if [[ ${IMAGE_URI} == *"ecr"* ]]; then
  echo "ECR image"
fi

# ✅ 正确 - sh 兼容语法
if echo "${IMAGE_URI}" | grep -q "ecr"; then
  echo "ECR image"
fi
```

**为什么?**
- Greengrass 使用 `sh` 执行脚本
- `[[` 是 bash 特性,在 sh 中不可用

**2. 保持 Run 脚本运行**

```bash
# 监控容器状态
while docker ps | grep -q ${CONTAINER_NAME}; do
  sleep 10
done
```

**为什么?**
- Greengrass 认为 Run 脚本退出 = 组件停止
- 需要保持脚本运行,监控容器状态
- 如果容器意外停止,脚本也会退出

**3. 使用 host 网络模式**

```bash
docker run -d --network host ...
```

**为什么?**
- 简化网络配置
- 容器直接使用主机网络
- 其他组件可以通过 localhost:2404 访问

**4. 容器重启策略**

```bash
docker run -d --restart unless-stopped ...
```

**为什么?**
- 容器崩溃时自动重启
- 除非手动停止,否则一直运行

#### 7.4 更新 Recipe 中的镜像 URI

```bash
# 使用 sed 替换镜像 URI
sed "s|IMAGE_URI_PLACEHOLDER|${ECR_REPO}:${IMAGE_TAG}|g" \
  recipe.yaml > recipe-updated.yaml

# 验证替换结果
grep "ImageUri" recipe-updated.yaml
```

**预期输出**:
```yaml
ImageUri: "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator:1.0.0"
```

#### 7.5 转换 Recipe 为 JSON

```bash
# 使用 Python 转换
python3 << 'EOF'
import yaml
import json

with open('recipe-updated.yaml', 'r') as f:
    recipe = yaml.safe_load(f)

with open('recipe.json', 'w') as f:
    json.dump(recipe, f, indent=2)

print("✅ Recipe converted to JSON")
EOF
```

---

### 步骤 8: 注册和部署组件

#### 8.1 注册组件版本

**使用 AWS CLI**:

```bash
# 创建组件版本
aws greengrassv2 create-component-version \
  --inline-recipe fileb://recipe.json \
  --region ${AWS_REGION}
```

**预期输出**:
```json
{
    "arn": "arn:aws:greengrass:ap-northeast-1:123456789012:components:com.example.IEC104SimulatorDocker:versions:1.0.0",
    "componentName": "com.example.IEC104SimulatorDocker",
    "componentVersion": "1.0.0",
    "creationTimestamp": "2026-01-23T10:30:00.000000+00:00",
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
5. 粘贴 `recipe.json` 的内容
6. 点击 **Create component**

![创建 Docker 组件](images/create-docker-component.png)
*截图位置: 创建 Docker 组件界面*

#### 8.2 部署组件

**使用 AWS CLI**:

```bash
# 设置环境变量
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export COMPONENT_VERSION="1.0.0"

# 创建部署
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Simulator-Docker-$(date +%s)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"${COMPONENT_VERSION}\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"ImageUri\\\":\\\"${ECR_REPO}:${IMAGE_TAG}\\\",\\\"ContainerName\\\":\\\"iec104-simulator\\\",\\\"HostPort\\\":\\\"2404\\\"}\"
      }
    }
  }" \
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
4. 添加组件: `com.example.IEC104SimulatorDocker`
5. 选择版本: `1.0.0`
6. 配置组件:
```json
{
  "ImageUri": "123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator:1.0.0",
  "ContainerName": "iec104-simulator",
  "HostPort": "2404"
}
```
7. 点击 **Deploy**

![部署 Docker 组件](images/deploy-docker-component.png)
*截图位置: 部署 Docker 组件配置*

#### 8.3 监控部署状态

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

![部署状态](images/deployment-status-docker.png)
*截图位置: Docker 组件部署状态*

---

### 步骤 9: 验证和测试

#### 9.1 查看组件状态

```bash
# 查看组件列表
sudo /greengrass/v2/bin/greengrass-cli component list | grep -A 3 IEC104
```

**预期输出**:
```
Component Name: com.example.IEC104SimulatorDocker
    Version: 1.0.0
    State: RUNNING
    Configuration: {"ImageUri":"...","ContainerName":"iec104-simulator","HostPort":"2404"}
```

#### 9.2 查看组件日志

```bash
# 查看组件日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104SimulatorDocker.log
```

**预期输出**:
```
2026-01-23T10:35:00.000Z [INFO] (Copier) com.example.IEC104SimulatorDocker: stdout. ECR image detected, logging in...
2026-01-23T10:35:05.000Z [INFO] (Copier) com.example.IEC104SimulatorDocker: stdout. Login Succeeded
2026-01-23T10:35:10.000Z [INFO] (Copier) com.example.IEC104SimulatorDocker: stdout. 1.0.0: Pulling from iec104-simulator
2026-01-23T10:35:15.000Z [INFO] (Copier) com.example.IEC104SimulatorDocker: stdout. Status: Downloaded newer image
2026-01-23T10:35:20.000Z [INFO] (Copier) com.example.IEC104SimulatorDocker: stdout. Container iec104-simulator started
```

#### 9.3 查看 Docker 容器状态

```bash
# 查看运行中的容器
docker ps | grep iec104-simulator
```

**预期输出**:
```
a1b2c3d4e5f6   123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/iec104-simulator:1.0.0   "/usr/local/bin/iec1…"   2 minutes ago   Up 2 minutes   iec104-simulator
```

```bash
# 查看容器详细信息
docker inspect iec104-simulator

# 查看容器日志
docker logs iec104-simulator
```

**预期容器日志**:
```
[INFO] IEC104 Simulator starting...
[INFO] Configuration loaded from /etc/iec104/config.json
[INFO] Listening on port 2404
[INFO] Simulating 6 data points:
[INFO]   - 1001: wind_turbine_1_active_power (1500 kW)
[INFO]   - 1002: wind_turbine_1_reactive_power (200 kVar)
[INFO]   - 1003: wind_turbine_1_wind_speed (8.5 m/s)
[INFO]   - 2001: energy_storage_soc (75 %)
[INFO]   - 2002: energy_storage_charge_power (500 kW)
[INFO]   - 3001: substation_voltage (35 kV)
[INFO] Server started successfully
```

#### 9.4 测试 IEC104 端口

```bash
# 测试端口连接
nc -zv localhost 2404
```

**预期输出**:
```
Connection to localhost 2404 port [tcp/*] succeeded!
```

```bash
# 查看端口监听
sudo netstat -tlnp | grep 2404
```

**预期输出**:
```
tcp        0      0 0.0.0.0:2404            0.0.0.0:*               LISTEN      12345/iec104_simula
```

#### 9.5 查看容器资源使用

```bash
# 查看容器资源使用情况
docker stats iec104-simulator --no-stream
```

**预期输出**:
```
CONTAINER ID   NAME               CPU %   MEM USAGE / LIMIT   MEM %   NET I/O       BLOCK I/O
a1b2c3d4e5f6   iec104-simulator   0.01%   2.5MiB / 7.6GiB     0.03%   1.2kB / 0B    0B / 0B
```

#### 9.6 测试容器重启

```bash
# 手动停止容器
docker stop iec104-simulator

# 等待几秒
sleep 5

# 检查容器是否自动重启
docker ps | grep iec104-simulator
```

**预期结果**:
- 容器应该自动重启 (因为 `--restart unless-stopped`)
- 或者 Greengrass 检测到容器停止,重新启动组件


---

## 📚 核心概念总结

### 1. Docker 多阶段构建

```
┌─────────────────────────────────────┐
│  Stage 1: Builder                   │
│  - 基础镜像: ubuntu:22.04           │
│  - 安装: gcc, cmake, build-essential│
│  - 编译源代码                        │
│  - 大小: ~500MB                     │
└──────────────┬──────────────────────┘
               │ COPY --from=builder
               ▼
┌─────────────────────────────────────┐
│  Stage 2: Runtime                   │
│  - 基础镜像: ubuntu:22.04           │
│  - 安装: 只有运行时依赖             │
│  - 复制: 只有二进制文件             │
│  - 大小: ~80MB (减少 84%)           │
└─────────────────────────────────────┘
```

**优势**:
- ✅ 减小镜像大小
- ✅ 提高安全性 (不包含编译工具)
- ✅ 加快镜像拉取速度
- ✅ 减少攻击面

### 2. ECR 镜像管理

| 操作 | 命令 | 说明 |
|------|------|------|
| **登录** | `aws ecr get-login-password \| docker login` | 获取临时凭证 (12 小时) |
| **标记** | `docker tag <local> <ecr-uri>` | 为镜像添加 ECR 标签 |
| **推送** | `docker push <ecr-uri>` | 上传镜像到 ECR |
| **拉取** | `docker pull <ecr-uri>` | 从 ECR 下载镜像 |
| **列出** | `aws ecr list-images` | 查看仓库中的镜像 |

### 3. Greengrass Docker 组件生命周期

```
Install 阶段
  ├── ECR 登录
  ├── 拉取镜像
  └── 验证镜像
       ↓
Run 阶段
  ├── 停止旧容器
  ├── 启动新容器
  └── 监控容器状态 (保持脚本运行)
       ↓
Shutdown 阶段
  ├── 停止容器
  └── 删除容器
```

### 4. Docker 网络模式

| 模式 | 说明 | 使用场景 |
|------|------|----------|
| **bridge** | 默认模式,容器有独立 IP | 容器间通信 |
| **host** | 共享主机网络 | 需要主机网络性能 |
| **none** | 无网络 | 完全隔离 |
| **container** | 共享其他容器网络 | 容器间紧密协作 |

**本 Lab 使用 host 模式**:
- 容器直接使用主机网络
- 其他组件可以通过 localhost:2404 访问
- 简化网络配置

### 5. sh vs bash 语法差异

| 特性 | bash | sh (POSIX) |
|------|------|-----------|
| `[[` 条件 | ✅ 支持 | ❌ 不支持 |
| `[` 条件 | ✅ 支持 | ✅ 支持 |
| `==` 字符串比较 | ✅ 支持 | ✅ 支持 (在 `[` 中) |
| `=~` 正则匹配 | ✅ 支持 | ❌ 不支持 |
| 数组 | ✅ 支持 | ❌ 不支持 |

**Greengrass 使用 sh**,因此必须使用 POSIX 兼容语法。

## 🎓 实验总结

通过本实验,你已经学会:

### ✅ 核心技能
- 编写 Dockerfile 实现应用容器化
- 使用多阶段构建优化镜像大小
- 将 Docker 镜像推送到 Amazon ECR
- 在 Greengrass 中运行 Docker 容器
- 管理容器生命周期 (启动、监控、停止)
- 调试容器化应用

### ✅ 关键概念
- Docker 多阶段构建原理和优势
- ECR 镜像仓库的使用和管理
- Greengrass Docker 组件的设计模式
- 容器网络模式和端口映射
- sh 脚本的 POSIX 兼容性

### ✅ 最佳实践
- 使用 AWS Public ECR 基础镜像避免网络问题
- 使用多阶段构建减小镜像大小
- 在 Recipe 中处理 ECR 登录
- 使用 sh 兼容语法编写脚本
- 保持 Run 脚本运行监控容器状态
- 使用 host 网络模式简化配置
- 配置容器重启策略提高可靠性

## 🔍 常见问题

### Q1: Docker 构建失败,无法下载依赖怎么办?

**症状**:
```
ERROR: failed to solve: failed to fetch ...
```

**解决方案**:

1. 使用 AWS Public ECR 基础镜像
```dockerfile
FROM public.ecr.aws/ubuntu/ubuntu:22.04
```

2. 配置 Docker 代理 (如果需要)
```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo cat > /etc/systemd/system/docker.service.d/http-proxy.conf << EOF
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### Q2: 容器启动后立即停止怎么办?

**检查步骤**:

1. 查看容器日志
```bash
docker logs iec104-simulator
```

2. 查看容器退出代码
```bash
docker inspect iec104-simulator --format='{{.State.ExitCode}}'
```

3. 尝试交互式运行
```bash
docker run -it --rm ${IMAGE_NAME}:${IMAGE_TAG} /bin/bash
```

4. 检查配置文件
```bash
docker run --rm ${IMAGE_NAME}:${IMAGE_TAG} cat /etc/iec104/config.json
```

### Q3: ECR 推送失败,认证错误怎么办?

**症状**:
```
denied: Your authorization token has expired. Reauthenticate and try again.
```

**解决方案**:

1. 重新登录 ECR
```bash
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin \
  ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

2. 检查 IAM 权限
```bash
aws ecr describe-repositories --region ${AWS_REGION}
```

3. 等待 IAM 策略生效
```bash
sleep 30
```

### Q4: Greengrass 组件无法拉取 ECR 镜像怎么办?

**症状**:
```
Error response from daemon: pull access denied
```

**解决方案**:

1. 检查 Token Exchange Role 权限
```bash
# 需要包含 ecr:GetAuthorizationToken 等权限
```

2. 验证 Recipe 中的 ECR 登录逻辑
```bash
# 确保 Install 脚本中有 ECR 登录代码
```

3. 检查镜像 URI 是否正确
```bash
# 验证 ImageUri 配置
sudo /greengrass/v2/bin/greengrass-cli component details \
  --name com.example.IEC104SimulatorDocker
```

### Q5: 容器使用本地缓存而非 ECR 镜像怎么办?

**症状**: docker pull 失败但容器仍然启动

**解决方案**:

1. 在 Recipe Install 脚本中检查 pull 结果
```bash
if ! docker pull ${IMAGE_URI}; then
  echo "Failed to pull image from ECR"
  exit 1
fi
```

2. 删除本地镜像强制拉取
```bash
docker rmi ${IMAGE_NAME}:${IMAGE_TAG}
```

3. 验证容器使用的镜像
```bash
docker inspect iec104-simulator --format='{{.Config.Image}}'
```

### Q6: 如何更新容器镜像版本?

**方法 1**: 更新配置 (推荐)

```bash
# 推送新版本镜像到 ECR
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REPO}:1.0.1
docker push ${ECR_REPO}:1.0.1

# 更新组件配置
aws greengrassv2 create-deployment \
  --target-arn "..." \
  --components '{
    "com.example.IEC104SimulatorDocker": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"ImageUri\":\"'${ECR_REPO}':1.0.1\"}"
      }
    }
  }' \
  --region ${AWS_REGION}
```

**方法 2**: 创建新组件版本

```bash
# 更新 Recipe 中的 ImageUri
# 创建新的组件版本 1.0.1
# 部署新版本
```

## 📖 参考资料

### AWS 官方文档
- [AWS IoT Greengrass V2 开发者指南](https://docs.aws.amazon.com/greengrass/v2/developerguide/)
- [Amazon ECR 用户指南](https://docs.aws.amazon.com/ecr/)
- [Docker 组件最佳实践](https://docs.aws.amazon.com/greengrass/v2/developerguide/run-docker-container.html)
- [IEC 60870-5-104 协议](https://en.wikipedia.org/wiki/IEC_60870-5)

### 相关 Workshop
- [Lab 1: 部署第一个 Greengrass 组件](../lab1-hello-world/WORKSHOP.md) - 基础组件开发
- [Lab 2: 配置管理和日志系统](../lab2-config-logging/WORKSHOP.md) - 日志管理
- [Lab 4: IEC104 数据采集器](../lab4-iec104-collector/WORKSHOP.md) - IPC 通信
- [Lab 5: IoT Core 集成](../lab5-iot-integration/WORKSHOP.md) - 云端集成

### 工具和库
- [Docker 官方文档](https://docs.docker.com/)
- [lib60870](https://github.com/mz-automation/lib60870) - IEC 60870-5-104 协议库
- [AWS CLI 参考](https://docs.aws.amazon.com/cli/latest/reference/)
- [nlohmann/json](https://github.com/nlohmann/json) - C++ JSON 库

## 🎯 下一步

完成 Lab 3 后,建议继续:

1. **Lab 4: IEC104 数据采集器**
   - 学习 Greengrass IPC 通信
   - 实践组件间消息传递
   - 掌握数据采集和过滤
   - 连接到 IEC104 模拟器

2. **Lab 5: IoT Core 集成**
   - 学习边缘到云数据传输
   - 实践 MQTT 消息发布
   - 掌握异步消息处理
   - 完整的数据管道

## 📝 实验检查清单

完成以下检查项,确保实验成功:

- [ ] 成功构建 Docker 镜像
- [ ] 镜像大小合理 (< 100MB)
- [ ] 本地测试容器运行正常
- [ ] 成功创建 ECR 仓库
- [ ] 成功推送镜像到 ECR
- [ ] 成功注册 Greengrass Docker 组件
- [ ] 成功部署组件到设备
- [ ] 容器在 Greengrass 中正常运行
- [ ] 端口 2404 可以访问
- [ ] 理解多阶段构建的优势
- [ ] 理解 ECR 登录和权限配置
- [ ] 理解 Greengrass Docker 组件的生命周期管理

---

**🎉 恭喜完成 Lab 3!**

你已经掌握了 Docker 容器化和 Greengrass Docker 组件的开发部署。继续下一个实验,学习如何采集 IEC104 数据!

**问题反馈**: 如有问题,请联系 Workshop 讲师或查阅 [AWS 支持](https://aws.amazon.com/support/)。
