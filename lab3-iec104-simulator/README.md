# Lab 3: IEC104模拟器 - Docker容器化部署

## 学习目标

完成本实验后，你将能够：
- ✅ 理解IEC 60870-5-104工业协议基础
- ✅ 编写Dockerfile实现应用容器化
- ✅ 使用多阶段构建优化镜像大小
- ✅ 将Docker镜像推送到Amazon ECR
- ✅ 在Greengrass中运行Docker容器
- ✅ 理解Greengrass Docker应用管理器组件
- ✅ 调试容器化应用

## 前置条件

- ✅ 完成Lab 1和Lab 2
- ✅ 了解Docker基础概念
- ✅ Greengrass设备已安装Docker
- ✅ 理解TCP/IP网络编程基础

### 验证环境

```bash
# 检查Docker安装
docker --version
docker ps

# 添加用户到docker组（重要！）
sudo usermod -aG docker ggc_user
sudo usermod -aG docker ubuntu

# 检查ECR访问权限
aws ecr describe-repositories --region cn-north-1
```

## 常见问题和解决方案（实战经验）

### 问题1: Docker网络连接超时

**症状**：
```
Get "https://registry-1.docker.io/v2/": net/http: request canceled
```

**原因**：Docker Hub在中国访问不稳定

**解决方案**：使用AWS Public ECR作为基础镜像
```dockerfile
# 替换
FROM ubuntu:22.04
# 为
FROM public.ecr.aws/ubuntu/ubuntu:22.04
```

### 问题2: nlohmann/json头文件依赖不完整

**症状**：
```
fatal error: nlohmann/adl_serializer.hpp: No such file or directory
```

**原因**：只复制了json.hpp单文件，缺少其他依赖头文件

**解决方案**：复制完整的nlohmann目录
```bash
# 错误做法
cp /usr/local/include/nlohmann/json.hpp .

# 正确做法
cp -r /usr/local/include/nlohmann .

# 验证目录结构
ls nlohmann/
# 应该看到: json.hpp, adl_serializer.hpp, detail/, thirdparty/
```

### 问题3: CMake FetchContent无法下载依赖

**症状**：
```
CMake Error: could not find git for clone of nlohmann_json-populate
```

**原因**：Dockerfile中没有安装git，且网络可能不通

**解决方案**：创建Docker专用的CMakeLists.txt，直接使用系统提供的头文件
```cmake
# CMakeLists-docker.txt
include_directories(/usr/local/include)
add_executable(iec104_simulator src/simulator.cpp)
target_link_libraries(iec104_simulator pthread)
```

### 问题4: Greengrass Shutdown权限错误

**症状**：
```
permission denied while trying to connect to the Docker daemon socket
```

**原因**：ggc_user不在docker组，无法访问Docker socket

**解决方案**：
```bash
# 添加ggc_user到docker组
sudo usermod -aG docker ggc_user

# 验证
groups ggc_user
# 输出应包含: ggc_user ggc_group docker

# 注意：组更改后需要重新部署组件才能生效
```

### 问题5: ECR认证失败

**症状**：
```
Error response from daemon: Head "https://xxx.ecr.xxx/v2/xxx/manifests/1.0.0": 
no basic auth credentials
```

**原因**：
1. IAM角色缺少ECR权限
2. Recipe中没有ECR登录逻辑

**解决方案**：

**步骤1**: 添加ECR权限到IAM角色
```bash
# 创建ECR策略
cat > /tmp/ecr-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
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
  }]
}
EOF

# 创建并附加策略
aws iam create-policy --policy-name ECRFullAccessPolicy \
  --policy-document file:///tmp/ecr-policy.json

aws iam attach-role-policy --role-name <your-role> \
  --policy-arn <policy-arn>

# 等待策略生效（重要！）
sleep 30
```

**步骤2**: 在Recipe中添加ECR登录
```bash
# 在Run脚本中添加
if echo "${IMAGE_URI}" | grep -q "ecr"; then
  AWS_REGION=$(echo ${IMAGE_URI} | cut -d'.' -f4)
  aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin \
    $(echo ${IMAGE_URI} | cut -d'/' -f1)
  docker pull ${IMAGE_URI}
fi
```

### 问题6: Recipe Run脚本立即退出导致容器被停止

**症状**：容器启动成功，但几秒后被Shutdown脚本停止

**原因**：Greengrass认为Run脚本退出=组件停止，自动执行Shutdown

**解决方案**：在Run脚本末尾添加监控循环，保持脚本运行
```bash
# 启动容器
docker run -d --name iec104-simulator ${IMAGE_URI}

# 监控容器（保持脚本运行）
while docker ps | grep -q iec104-simulator; do
  sleep 10
done
echo "Container stopped unexpectedly"
```

### 问题7: Shell语法不兼容 - `[[: not found`

**症状**：
```
sh: 13: [[: not found
```

**原因**：Greengrass使用sh执行脚本，而`[[`是bash特性

**解决方案**：使用POSIX兼容的sh语法
```bash
# ❌ 错误 - bash语法
if [[ ${IMAGE_URI} == *"ecr"* ]]; then
  echo "ECR image"
fi

# ✅ 正确 - sh兼容语法
if echo "${IMAGE_URI}" | grep -q "ecr"; then
  echo "ECR image"
fi
```

### 问题8: IAM策略生效延迟

**症状**：策略已附加但仍然报权限错误

**原因**：IAM策略需要时间传播（通常30秒）

**解决方案**：
```bash
# 附加策略后等待
aws iam attach-role-policy --role-name xxx --policy-arn xxx
sleep 30  # 等待策略生效

# 或者测试权限直到成功
while ! aws ecr describe-repositories --region cn-north-1 2>/dev/null; do
  echo "Waiting for IAM policy to take effect..."
  sleep 10
done
```

### 问题9: 容器使用本地缓存而非ECR镜像

**症状**：docker pull失败但容器仍然启动（使用旧的本地镜像）

**原因**：Docker在pull失败时会fallback到本地缓存

**解决方案**：
```bash
# 方法1: 先删除本地镜像
docker rmi ${IMAGE_NAME}:${IMAGE_TAG}

# 方法2: 在Recipe中检查pull结果
if ! docker pull ${IMAGE_URI}; then
  echo "Failed to pull image from ECR"
  exit 1
fi

# 方法3: 验证容器使用的镜像
docker inspect iec104-simulator --format='{{.Config.Image}}'
# 应该显示完整的ECR URI
```

### 问题10: ubuntu用户无Docker权限

**症状**：ubuntu用户执行docker命令时报权限错误

**解决方案**：
```bash
# 添加ubuntu用户到docker组
sudo usermod -aG docker ubuntu

# 方法1: 重新登录使组生效
exit  # 退出并重新登录

# 方法2: 使用sudo执行docker命令
sudo docker ps

# 方法3: 使用newgrp临时切换组
newgrp docker
```

## 最佳实践总结

基于实战经验的关键要点：

1. **✅ 使用AWS Public ECR基础镜像** - 避免Docker Hub网络问题
2. **✅ 复制完整依赖目录** - 不要只复制单个文件
3. **✅ 创建Docker专用构建配置** - 避免网络依赖
4. **✅ 配置用户组权限** - ggc_user和ubuntu都需要docker组
5. **✅ 添加完整ECR权限** - 包括GetAuthorizationToken等
6. **✅ 在Recipe中处理ECR登录** - 不依赖外部认证
7. **✅ 使用sh兼容语法** - 避免bash特性
8. **✅ 保持Run脚本运行** - 使用监控循环
9. **✅ 等待IAM策略生效** - 附加策略后等待30秒
10. **✅ 验证镜像来源** - 确认使用ECR镜像而非本地缓存

## 为什么使用Docker？

### 传统部署 vs Docker部署

| 特性 | 传统部署 | Docker部署 |
|------|----------|------------|
| 依赖管理 | 手动安装 | 镜像包含所有依赖 |
| 环境一致性 | 难以保证 | 完全一致 |
| 隔离性 | 进程级 | 容器级（更强） |
| 资源限制 | 难以控制 | 易于配置 |
| 版本管理 | 复杂 | 镜像标签 |
| 回滚 | 困难 | 切换镜像版本 |

### Greengrass中的Docker优势

- ✅ **隔离性**：容器之间互不影响
- ✅ **可移植性**：同一镜像可在不同设备运行
- ✅ **资源控制**：限制CPU、内存使用
- ✅ **快速部署**：拉取镜像即可运行
- ✅ **版本管理**：通过镜像标签管理版本

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Cloud                                 │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Amazon ECR (Elastic Container Registry)           │    │
│  │                                                     │    │
│  │  Repository: iec104-simulator                      │    │
│  │  Image: xxx.dkr.ecr.cn-north-1.amazonaws.com.cn/  │    │
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

## IEC 60870-5-104协议简介

### 什么是IEC104？

IEC 60870-5-104是电力系统中广泛使用的通信协议：
- **应用场景**：SCADA系统、变电站自动化、风电场监控
- **传输层**：基于TCP/IP
- **默认端口**：2404
- **数据类型**：遥测（模拟量）、遥信（开关量）、遥控

### 本Lab模拟的数据点

| 地址 | 名称 | 设备 | 基准值 | 变化范围 | 单位 |
|------|------|------|--------|----------|------|
| 1001 | wind_turbine_1_active_power | 风机 | 1500 | ±200 | kW |
| 1002 | wind_turbine_1_reactive_power | 风机 | 200 | ±50 | kVar |
| 1003 | wind_turbine_1_wind_speed | 风机 | 8.5 | ±2.0 | m/s |
| 2001 | energy_storage_soc | 储能 | 75 | ±10 | % |
| 2002 | energy_storage_charge_power | 储能 | 500 | ±100 | kW |
| 3001 | substation_voltage | 变电站 | 35 | ±1.0 | kV |

---

# Part 1: Docker镜像构建

## 步骤 1: 理解Dockerfile

### 1.1 查看Dockerfile

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab3-iec104-simulator
cat Dockerfile
```

### 1.2 多阶段构建解析

**为什么使用多阶段构建？**
- 减小最终镜像大小（不包含编译工具）
- 分离构建环境和运行环境
- 提高安全性（运行时不需要编译器）

**Stage 1: Builder（构建阶段）**
```dockerfile
FROM ubuntu:22.04 AS builder

# 安装构建依赖
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget

# 下载nlohmann/json库
RUN wget -O /usr/local/include/json.hpp \
    https://github.com/nlohmann/json/releases/download/v3.11.2/json.hpp

# 编译应用
WORKDIR /build
COPY src/ ./src/
COPY CMakeLists.txt ./
RUN cmake . && make
```

**Stage 2: Runtime（运行阶段）**
```dockerfile
FROM ubuntu:22.04

# 只安装运行时依赖
RUN apt-get update && apt-get install -y libstdc++6

# 从builder复制二进制文件
COPY --from=builder /build/iec104_simulator /app/

# 创建非root用户（安全最佳实践）
RUN useradd -m -u 1000 simulator
USER simulator

# 暴露端口
EXPOSE 2404

# 启动命令
CMD ["/app/iec104_simulator", "/app/config.json"]
```

### 1.3 Dockerfile最佳实践

1. **使用多阶段构建**：减小镜像大小
2. **非root用户运行**：提高安全性
3. **最小化层数**：合并RUN命令
4. **清理缓存**：`rm -rf /var/lib/apt/lists/*`
5. **明确指定版本**：避免使用`latest`标签

## 步骤 2: 构建Docker镜像

### 2.1 准备nlohmann/json库

**重要**：需要完整的nlohmann目录，不只是json.hpp

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab3-iec104-simulator

# 复制完整的nlohmann目录
cp -r /usr/local/include/nlohmann .

# 验证目录结构
ls -la nlohmann/
# 应该看到: json.hpp, adl_serializer.hpp, detail/, thirdparty/等
```

### 2.2 创建Docker专用CMakeLists.txt

由于Dockerfile中无法使用FetchContent下载依赖，创建简化版本：

```bash
cat > CMakeLists-docker.txt << 'EOF'
cmake_minimum_required(VERSION 3.10)
project(iec104_simulator VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 使用系统提供的nlohmann/json
include_directories(/usr/local/include)

add_executable(iec104_simulator src/simulator.cpp)
target_link_libraries(iec104_simulator pthread)

install(TARGETS iec104_simulator DESTINATION bin)
EOF
```

### 2.3 构建镜像

```bash
export IMAGE_NAME="iec104-simulator"
export IMAGE_TAG="1.0.0"

# 构建镜像
sudo docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .

# 查看镜像
sudo docker images ${IMAGE_NAME}:${IMAGE_TAG}
```

**预期输出**：
```
REPOSITORY         TAG       IMAGE ID       CREATED         SIZE
iec104-simulator   1.0.0     1dde0a5cb2c8   2 minutes ago   70MB
```

### 2.4 本地测试

```bash
# 运行容器测试
sudo docker run --rm -d \
  --name iec104-test \
  --network host \
  ${IMAGE_NAME}:${IMAGE_TAG}

# 查看日志
sudo docker logs iec104-test

# 测试端口
nc -zv localhost 2404

# 停止容器
sudo docker stop iec104-test
```
# 构建镜像
docker build -t iec104-simulator:1.0.0 .

# 观察构建过程
# - 下载基础镜像
# - 安装依赖
# - 编译代码
# - 创建最终镜像
```

**预期输出**：
```
[+] Building 45.2s (18/18) FINISHED
 => [internal] load build definition from Dockerfile
 => [internal] load .dockerignore
 => [builder 1/8] FROM docker.io/library/ubuntu:22.04
 => [builder 2/8] RUN apt-get update && apt-get install -y build-essential cmake
 => [builder 3/8] RUN wget -O /usr/local/include/json.hpp ...
 => [builder 4/8] WORKDIR /build
 => [builder 5/8] COPY src/ ./src/
 => [builder 6/8] COPY CMakeLists.txt ./
 => [builder 7/8] COPY config.json ./
 => [builder 8/8] RUN mkdir build && cd build && cmake .. && make
 => [stage-1 1/5] FROM docker.io/library/ubuntu:22.04
 => [stage-1 2/5] RUN apt-get update && apt-get install -y libstdc++6
 => [stage-1 3/5] RUN useradd -m -u 1000 simulator
 => [stage-1 4/5] COPY --from=builder /build/build/iec104_simulator /app/
 => [stage-1 5/5] COPY --from=builder /build/config.json /app/
 => exporting to image
 => => naming to docker.io/library/iec104-simulator:1.0.0
```

### 2.2 使用构建脚本

```bash
# 查看构建脚本
cat docker-build.sh

# 执行构建
./docker-build.sh
```

### 2.3 查看镜像信息

```bash
# 列出镜像
docker images iec104-simulator:1.0.0

# 查看镜像详细信息
docker inspect iec104-simulator:1.0.0

# 查看镜像大小
docker images iec104-simulator:1.0.0 --format "{{.Size}}"

# 查看镜像层
docker history iec104-simulator:1.0.0
```

**预期镜像大小**：约80-100MB（多阶段构建后）
**对比**：如果不使用多阶段构建，镜像大小约500MB+

## 步骤 3: 本地测试Docker容器

### 3.1 手动运行容器

```bash
# 运行容器
docker run -d \
  --name iec104-simulator-test \
  -p 2404:2404 \
  iec104-simulator:1.0.0

# 查看容器状态
docker ps | grep iec104-simulator-test

# 查看容器日志
docker logs iec104-simulator-test
```

**预期日志输出**：
```
[INFO] IEC104 Simulator starting...
[INFO] Loaded 6 data points
[INFO] IEC104 server started on port 2404
[INFO] Waiting for connections...
[INFO] Updated 6 data points (cycle 1)
[DATA] wind_turbine_1_active_power = 1523.45 kW
[DATA] wind_turbine_1_reactive_power = 215.32 kVar
...
```

### 3.2 测试连接

```bash
# 方法1: 使用netcat测试端口
nc -zv localhost 2404

# 方法2: 使用telnet
telnet localhost 2404

# 方法3: 查看监听端口
sudo netstat -tlnp | grep 2404
```

### 3.3 使用测试脚本

```bash
# 运行测试脚本（自动启动、测试、清理）
./docker-test.sh

# 按Ctrl+C停止
```

### 3.4 容器管理命令

```bash
# 查看容器日志（实时）
docker logs -f iec104-simulator-test

# 进入容器（调试）
docker exec -it iec104-simulator-test /bin/bash

# 查看容器资源使用
docker stats iec104-simulator-test

# 停止容器
docker stop iec104-simulator-test

# 删除容器
docker rm iec104-simulator-test
```

### 3.5 思考问题

1. 为什么使用`--network host`模式？
2. 如果容器崩溃，如何自动重启？
3. 如何限制容器的CPU和内存使用？

---

# Part 2: 推送镜像到Amazon ECR

## 步骤 4: 创建ECR仓库并推送镜像

### 4.1 理解Amazon ECR

**Amazon ECR (Elastic Container Registry)**：
- AWS托管的Docker镜像仓库
- 与IAM集成，安全可控
- 支持镜像扫描和生命周期策略
- 高可用性和持久性

### 4.2 配置环境变量

```bash
export AWS_REGION="cn-north-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_NAME="iec104-simulator"
export IMAGE_TAG="1.0.0"
export REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com.cn"

echo "Registry: ${REGISTRY}"
echo "Full Image URI: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
```

### 4.3 登录到ECR

```bash
# 获取登录密码并登录
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${REGISTRY}
```

**预期输出**：
```
Login Succeeded
```

### 4.4 创建ECR仓库

```bash
# 创建仓库
aws ecr create-repository \
  --repository-name ${IMAGE_NAME} \
  --region ${AWS_REGION}

# 查看仓库信息
aws ecr describe-repositories \
  --repository-names ${IMAGE_NAME} \
  --region ${AWS_REGION}
```

**预期输出**：
```json
{
    "repositories": [
        {
            "repositoryArn": "arn:aws-cn:ecr:cn-north-1:123456789012:repository/iec104-simulator",
            "registryId": "123456789012",
            "repositoryName": "iec104-simulator",
            "repositoryUri": "123456789012.dkr.ecr.cn-north-1.amazonaws.com.cn/iec104-simulator",
            "createdAt": "2026-01-22T03:30:00+00:00"
        }
    ]
}
```

### 4.5 标记并推送镜像

```bash
# 标记镜像
docker tag iec104-simulator:1.0.0 ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}

# 推送镜像
docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
```

**预期输出**：
```
The push refers to repository [123456789012.dkr.ecr.cn-north-1.amazonaws.com.cn/iec104-simulator]
5f70bf18a086: Pushed
e16c52083d88: Pushed
1.0.0: digest: sha256:abc123... size: 1234
```

### 4.6 使用推送脚本

```bash
# 查看脚本
cat docker-push.sh

# 执行推送
./docker-push.sh

# 保存镜像URI
cat /tmp/iec104-simulator-image-uri.txt
```

### 4.7 验证镜像已推送

```bash
# 列出仓库中的镜像
aws ecr list-images \
  --repository-name ${IMAGE_NAME} \
  --region ${AWS_REGION}

# 查看镜像详情
aws ecr describe-images \
  --repository-name ${IMAGE_NAME} \
  --image-ids imageTag=${IMAGE_TAG} \
  --region ${AWS_REGION}
```

---

# Part 3: 在Greengrass中运行Docker容器

## 步骤 5: 配置Greengrass Docker支持

### 5.1 验证Docker安装

在Greengrass设备上：

```bash
# 检查Docker版本
docker --version

# 检查Docker服务状态
sudo systemctl status docker

# 测试Docker运行
docker run hello-world
```

### 5.2 配置Greengrass用户权限

Greengrass需要权限运行Docker命令：

```bash
# 将ggc_user添加到docker组
sudo usermod -aG docker ggc_user

# 验证
groups ggc_user

# 重启Greengrass服务
sudo systemctl restart greengrass
```

### 5.3 配置ECR访问权限

Greengrass Token Exchange Role需要ECR权限：

```bash
# 创建策略文档
cat > /tmp/ecr-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# 注意：实际环境中需要将此策略附加到Token Exchange Role
```

## 步骤 6: 理解Docker Recipe

### 6.1 查看Docker Recipe

```bash
cat recipe-docker.yaml
```

### 6.2 Recipe关键配置

**配置参数**：
```yaml
ComponentConfiguration:
  DefaultConfiguration:
    imageUri: "123456789012.dkr.ecr.cn-north-1.amazonaws.com.cn/iec104-simulator:1.0.0"
    port: 2404
```

**Run脚本**：
```yaml
Run:
  RequiresPrivilege: true  # 需要root权限运行Docker
  Script: |
    IMAGE_URI="{configuration:/imageUri}"
    
    # 停止旧容器
    docker stop iec104-simulator 2>/dev/null || true
    docker rm iec104-simulator 2>/dev/null || true
    
    # 运行新容器
    docker run -d \
      --name iec104-simulator \
      --network host \
      --restart unless-stopped \
      ${IMAGE_URI}
```

**Shutdown脚本**：
```yaml
Shutdown:
  Script: |
    docker stop iec104-simulator || true
    docker rm iec104-simulator || true
```

### 6.3 关键配置说明

| 配置 | 说明 |
|------|------|
| `RequiresPrivilege: true` | 需要root权限运行Docker命令 |
| `--network host` | 使用主机网络，容器直接监听2404端口 |
| `--restart unless-stopped` | 容器崩溃自动重启 |
| `-d` | 后台运行 |

## 步骤 7: 部署Docker组件到Greengrass

### 7.1 准备Recipe

```bash
# 获取镜像URI
export IMAGE_URI=$(cat /tmp/iec104-simulator-image-uri.txt)
echo "Image URI: ${IMAGE_URI}"

# 转换Recipe为JSON
python3 << EOF
import yaml
import json

with open('recipe-docker.yaml', 'r') as f:
    recipe = yaml.safe_load(f)

# 更新imageUri
recipe['ComponentConfiguration']['DefaultConfiguration']['imageUri'] = '${IMAGE_URI}'

with open('artifacts/recipe-docker.json', 'w') as f:
    json.dump(recipe, f, indent=2)

print("✅ Recipe converted and updated")
EOF
```

### 7.2 创建组件版本

```bash
# 创建组件（无需上传artifact，因为使用Docker镜像）
aws greengrassv2 create-component-version \
  --inline-recipe fileb://artifacts/recipe-docker.json \
  --region ${AWS_REGION}
```

### 7.3 部署到设备

```bash
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Simulator-Docker-$(date +%s)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"1.0.0\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"imageUri\\\":\\\"${IMAGE_URI}\\\",\\\"port\\\":2404}\"
      }
    }
  }" \
  --region ${AWS_REGION}
```

## 步骤 8: 验证Docker容器运行

### 8.1 查看Greengrass日志

```bash
# 查看组件日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104SimulatorDocker.log
```

**预期输出**：
```
[INFO] Starting IEC104 Simulator Docker container
[INFO] Image: 123456789012.dkr.ecr.cn-north-1.amazonaws.com.cn/iec104-simulator:1.0.0
[INFO] Port: 2404
[INFO] IEC104 Simulator container started
```

### 8.2 查看Docker容器状态

```bash
# 查看运行的容器
docker ps | grep iec104-simulator

# 查看容器日志
docker logs iec104-simulator

# 实时查看容器日志
docker logs -f iec104-simulator
```

### 8.3 测试IEC104连接

```bash
# 测试端口
nc -zv localhost 2404

# 查看监听端口
sudo netstat -tlnp | grep 2404
```

### 8.4 查看容器资源使用

```bash
# 实时资源监控
docker stats iec104-simulator

# 查看容器详细信息
docker inspect iec104-simulator
```

---

继续创建文档的后半部分...

# Part 4: 高级主题

## 步骤 9: Docker容器调试

### 9.1 进入运行中的容器

```bash
# 进入容器shell
docker exec -it iec104-simulator /bin/bash

# 在容器内执行命令
docker exec iec104-simulator ps aux
docker exec iec104-simulator cat /app/config.json
```

### 9.2 查看容器网络

```bash
# 查看容器网络配置
docker inspect iec104-simulator --format='{{.NetworkSettings.Networks}}'

# 查看容器IP（如果不使用host模式）
docker inspect iec104-simulator --format='{{.NetworkSettings.IPAddress}}'

# 查看端口映射
docker port iec104-simulator
```

### 9.3 容器日志管理

```bash
# 查看最近100行日志
docker logs --tail 100 iec104-simulator

# 查看最近5分钟的日志
docker logs --since 5m iec104-simulator

# 查看带时间戳的日志
docker logs -t iec104-simulator

# 保存日志到文件
docker logs iec104-simulator > /tmp/simulator-logs.txt
```

### 9.4 容器故障排查

**问题1: 容器无法启动**
```bash
# 查看容器状态
docker ps -a | grep iec104-simulator

# 查看容器退出代码
docker inspect iec104-simulator --format='{{.State.ExitCode}}'

# 查看错误日志
docker logs iec104-simulator
```

**问题2: 端口冲突**
```bash
# 检查端口占用
sudo netstat -tlnp | grep 2404

# 停止占用端口的进程
sudo kill <PID>
```

**问题3: 镜像拉取失败**
```bash
# 检查ECR登录
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin ${REGISTRY}

# 手动拉取镜像
docker pull ${IMAGE_URI}

# 查看镜像
docker images | grep iec104-simulator
```

## 步骤 10: 容器资源限制

### 10.1 限制CPU和内存

修改Recipe，添加资源限制：

```yaml
Run:
  Script: |
    docker run -d \
      --name iec104-simulator \
      --network host \
      --restart unless-stopped \
      --memory="256m" \
      --memory-swap="256m" \
      --cpus="0.5" \
      ${IMAGE_URI}
```

**资源限制说明**：
- `--memory="256m"`: 限制内存使用256MB
- `--memory-swap="256m"`: 禁用swap
- `--cpus="0.5"`: 限制使用0.5个CPU核心

### 10.2 验证资源限制

```bash
# 查看容器资源限制
docker inspect iec104-simulator --format='{{.HostConfig.Memory}}'
docker inspect iec104-simulator --format='{{.HostConfig.NanoCpus}}'

# 实时监控资源使用
docker stats iec104-simulator --no-stream
```

### 10.3 配置日志轮转

防止容器日志占满磁盘：

```yaml
Run:
  Script: |
    docker run -d \
      --name iec104-simulator \
      --network host \
      --restart unless-stopped \
      --log-driver json-file \
      --log-opt max-size=10m \
      --log-opt max-file=3 \
      ${IMAGE_URI}
```

**日志配置说明**：
- `max-size=10m`: 单个日志文件最大10MB
- `max-file=3`: 保留最多3个日志文件

## 步骤 11: 镜像版本管理

### 11.1 构建新版本

```bash
# 修改代码后重新构建
docker build -t iec104-simulator:1.0.1 .

# 推送新版本
docker tag iec104-simulator:1.0.1 ${REGISTRY}/${IMAGE_NAME}:1.0.1
docker push ${REGISTRY}/${IMAGE_NAME}:1.0.1
```

### 11.2 更新Greengrass组件

```bash
# 更新配置，使用新镜像版本
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Simulator-Update-$(date +%s)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"1.0.0\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"imageUri\\\":\\\"${REGISTRY}/${IMAGE_NAME}:1.0.1\\\"}\"
      }
    }
  }" \
  --region ${AWS_REGION}
```

### 11.3 回滚到旧版本

```bash
# 回滚到1.0.0版本
aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Simulator-Rollback-$(date +%s)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"1.0.0\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"imageUri\\\":\\\"${REGISTRY}/${IMAGE_NAME}:1.0.0\\\"}\"
      }
    }
  }" \
  --region ${AWS_REGION}
```

### 11.4 清理旧镜像

```bash
# 在设备上清理未使用的镜像
docker image prune -a

# 删除特定镜像
docker rmi ${REGISTRY}/${IMAGE_NAME}:1.0.0

# 在ECR中删除镜像
aws ecr batch-delete-image \
  --repository-name ${IMAGE_NAME} \
  --image-ids imageTag=1.0.0 \
  --region ${AWS_REGION}
```

---

## 关键概念总结

### 1. Docker容器化

**优势**：
- 环境一致性
- 依赖隔离
- 快速部署
- 易于版本管理

**最佳实践**：
- 使用多阶段构建
- 非root用户运行
- 最小化镜像大小
- 明确指定版本

### 2. Amazon ECR

**特点**：
- AWS托管的容器镜像仓库
- 与IAM集成
- 支持镜像扫描
- 高可用性

**使用场景**：
- 存储私有镜像
- 版本管理
- 跨区域复制

### 3. Greengrass Docker支持

**工作原理**：
```
Greengrass Component
  → 执行docker命令
  → 拉取ECR镜像
  → 启动容器
  → 监控容器状态
```

**关键配置**：
- `RequiresPrivilege: true`
- Docker用户权限
- ECR访问权限

### 4. 容器生命周期管理

| 阶段 | 操作 | Greengrass行为 |
|------|------|----------------|
| Install | 无需操作 | 准备环境 |
| Run | docker run | 启动容器 |
| Shutdown | docker stop | 停止容器 |
| 崩溃 | 自动重启 | 重新执行Run脚本 |

### 5. 网络模式

| 模式 | 说明 | 使用场景 |
|------|------|----------|
| host | 共享主机网络 | 需要监听特定端口 |
| bridge | 桥接网络 | 容器间通信 |
| none | 无网络 | 完全隔离 |

## 实验总结

通过本实验，你已经：
- ✅ 编写了Dockerfile实现应用容器化
- ✅ 使用多阶段构建优化镜像大小
- ✅ 将镜像推送到Amazon ECR
- ✅ 在Greengrass中部署和运行Docker容器
- ✅ 掌握了容器调试和故障排查
- ✅ 理解了容器资源限制和日志管理
- ✅ 学会了镜像版本管理和回滚

## 最佳实践

### Docker镜像构建
- ✅ 使用多阶段构建减小镜像大小
- ✅ 使用非root用户运行应用
- ✅ 合并RUN命令减少层数
- ✅ 清理apt缓存和临时文件
- ✅ 使用.dockerignore排除不必要的文件

### ECR镜像管理
- ✅ 使用语义化版本标签（1.0.0, 1.0.1）
- ✅ 配置生命周期策略自动清理旧镜像
- ✅ 启用镜像扫描检测漏洞
- ✅ 使用IAM策略控制访问权限

### Greengrass部署
- ✅ 配置容器资源限制
- ✅ 使用`--restart unless-stopped`自动重启
- ✅ 配置日志轮转防止磁盘占满
- ✅ 使用配置参数管理镜像URI

### 安全性
- ✅ 使用私有ECR仓库
- ✅ 定期更新基础镜像
- ✅ 扫描镜像漏洞
- ✅ 最小化容器权限

## 常见问题 (FAQ)

**Q1: Docker镜像和传统部署有什么区别？**

| 特性 | 传统部署 | Docker部署 |
|------|----------|------------|
| 依赖管理 | 手动安装 | 镜像包含 |
| 环境一致性 | 难保证 | 完全一致 |
| 部署速度 | 慢 | 快 |
| 回滚 | 困难 | 切换镜像 |

**Q2: 为什么使用多阶段构建？**

减小镜像大小：
- 构建阶段：包含编译工具（500MB+）
- 运行阶段：只包含运行时（80MB）

**Q3: 如何查看容器占用的资源？**

```bash
docker stats iec104-simulator --no-stream
```

**Q4: 容器崩溃后会自动重启吗？**

会，因为使用了`--restart unless-stopped`参数。

**Q5: 如何更新容器镜像？**

1. 构建新镜像并推送到ECR
2. 更新Greengrass组件配置中的imageUri
3. Greengrass会自动停止旧容器，启动新容器

**Q6: 如何限制容器的资源使用？**

在docker run命令中添加：
```bash
--memory="256m" --cpus="0.5"
```

**Q7: ECR镜像拉取失败怎么办？**

检查：
- Token Exchange Role是否有ECR权限
- 网络连接是否正常
- 镜像URI是否正确

**Q8: 如何查看容器内的文件？**

```bash
docker exec iec104-simulator ls -la /app
docker exec iec104-simulator cat /app/config.json
```

## 故障排查清单

### 容器无法启动
- [ ] 检查Docker服务状态：`sudo systemctl status docker`
- [ ] 检查ggc_user是否在docker组：`groups ggc_user`
- [ ] 查看容器日志：`docker logs iec104-simulator`
- [ ] 检查端口是否被占用：`sudo netstat -tlnp | grep 2404`

### 镜像拉取失败
- [ ] 检查ECR登录：`docker login`
- [ ] 验证IAM权限：ecr:GetAuthorizationToken, ecr:BatchGetImage
- [ ] 检查网络连接
- [ ] 验证镜像URI正确

### 容器运行但无法连接
- [ ] 检查容器状态：`docker ps`
- [ ] 查看容器日志：`docker logs iec104-simulator`
- [ ] 测试端口：`nc -zv localhost 2404`
- [ ] 检查防火墙规则

### Greengrass组件错误
- [ ] 查看组件日志：`sudo tail -f /greengrass/v2/logs/com.example.IEC104SimulatorDocker.log`
- [ ] 检查Recipe配置
- [ ] 验证RequiresPrivilege设置为true

## 性能优化

### 镜像大小优化

**优化前**：500MB+
**优化后**：80-100MB

**优化技巧**：
1. 使用多阶段构建
2. 使用Alpine Linux基础镜像（可选）
3. 清理apt缓存
4. 合并RUN命令

### 容器启动速度

**影响因素**：
- 镜像大小
- 网络速度（拉取镜像）
- 应用初始化时间

**优化方法**：
- 预拉取镜像到设备
- 使用本地镜像缓存
- 优化应用启动逻辑

### 资源使用

**监控命令**：
```bash
docker stats iec104-simulator
```

**优化建议**：
- 设置合理的资源限制
- 监控内存泄漏
- 优化应用性能

## 扩展实验

### 实验1: 使用Alpine Linux基础镜像

修改Dockerfile使用更小的基础镜像：
```dockerfile
FROM alpine:3.18 AS builder
RUN apk add --no-cache build-base cmake wget
...

FROM alpine:3.18
RUN apk add --no-cache libstdc++
...
```

### 实验2: 添加健康检查

在Dockerfile中添加：
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s \
  CMD nc -zv localhost 2404 || exit 1
```

### 实验3: 使用Docker Compose（本地测试）

创建docker-compose.yml：
```yaml
version: '3'
services:
  simulator:
    build: .
    ports:
      - "2404:2404"
    restart: unless-stopped
```

### 实验4: 多容器部署

部署多个模拟器实例：
```bash
docker run -d --name sim1 -p 2404:2404 iec104-simulator:1.0.0
docker run -d --name sim2 -p 2405:2404 iec104-simulator:1.0.0
```

## 下一步

完成Lab 3后，继续：
- **[Lab 4: IEC104数据采集器](../lab4-iec104-collector/README.md)** - 连接模拟器并采集数据
- **Lab 5**: AWS IoT Core集成

## 参考资料

- [Docker官方文档](https://docs.docker.com/)
- [Amazon ECR用户指南](https://docs.aws.amazon.com/ecr/)
- [Greengrass Docker应用管理器](https://docs.aws.amazon.com/greengrass/v2/developerguide/docker-application-manager-component.html)
- [Dockerfile最佳实践](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [多阶段构建](https://docs.docker.com/build/building/multi-stage/)

---

**🎉 恭喜完成Lab 3！你已经掌握了Docker容器化部署！**
