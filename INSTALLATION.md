# 全新环境快速部署指南

## 系统要求

- Ubuntu 20.04 / 22.04 LTS
- 架构: x86_64 或 aarch64 (ARM64)
- 至少 2GB RAM
- 至少 10GB 磁盘空间
- 有 sudo 权限

## 一键安装

### 步骤 1: 克隆项目

```bash
cd ~
git clone https://github.com/comdaze/greengrass-iec104-cpp-workshop.git workshop
cd workshop
```

### 步骤 2: 安装依赖环境

```bash
./setup-environment.sh
```

这个脚本会自动安装：
- ✅ 基础开发工具 (gcc, cmake, git, etc.)
- ✅ AWS CLI v2
- ✅ Docker
- ✅ Java 11 (Greengrass 需要)
- ✅ 配置用户权限

**重要**: 安装完成后需要重新登录以使 docker 组权限生效！

```bash
exit
# 重新 SSH 登录
```

### 步骤 3: 配置 AWS 凭证

```bash
aws configure
```

输入：
- AWS Access Key ID
- AWS Secret Access Key
- Default region: `ap-northeast-1`
- Default output format: `json`

### 步骤 4: 安装 Greengrass Core

```bash
./install-greengrass.sh
```

按提示输入：
- AWS Region (默认: ap-northeast-1)
- Thing Name (默认: MyGreengrassCore)

### 步骤 5: 创建 S3 存储桶

```bash
export COMPONENT_BUCKET=iec104-components-$(date +%s)
export AWS_REGION=ap-northeast-1
aws s3 mb s3://${COMPONENT_BUCKET} --region ${AWS_REGION}

# 保存到环境变量
echo "export COMPONENT_BUCKET=${COMPONENT_BUCKET}" >> ~/.bashrc
echo "export AWS_REGION=${AWS_REGION}" >> ~/.bashrc
source ~/.bashrc
```

### 步骤 6: 部署组件

```bash
# Lab 3: IEC104 Simulator
cd lab3-iec104-simulator
./docker-build.sh
./deploy.sh

# Lab 4: IEC104 Collector
cd ../lab4-iec104-collector
./build.sh
./package.sh
./deploy.sh

# Lab 5: IoT Publisher
cd ../lab5-iot-integration
./build.sh
./package.sh
./deploy.sh
```

### 步骤 7: 验证部署

```bash
# 检查组件状态
sudo /greengrass/v2/bin/greengrass-cli component list

# 查看日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Collector.log
sudo tail -f /greengrass/v2/logs/com.example.IoTPublisher.log
```

## 快速命令参考

```bash
# 查看所有组件
sudo /greengrass/v2/bin/greengrass-cli component list

# 重启 Greengrass
sudo systemctl restart greengrass

# 查看 Greengrass 状态
sudo systemctl status greengrass

# 查看 Docker 容器
docker ps

# 测试 IEC104 端口
nc -zv localhost 2404

# 测试 IoT Core 发布
sudo /greengrass/v2/bin/greengrass-cli iotcore pub \
  --topic test/topic \
  --message '{"test":"message"}'
```

## 故障排查

### Docker 权限问题

```bash
# 确认用户在 docker 组
groups

# 如果没有，添加并重新登录
sudo usermod -aG docker $USER
exit
# 重新登录
```

### Greengrass 无法启动

```bash
# 查看日志
sudo tail -100 /greengrass/v2/logs/greengrass.log

# 检查 Java
java -version

# 检查权限
ls -la /greengrass/v2
```

### 组件部署失败

```bash
# 查看组件日志
sudo tail -100 /greengrass/v2/logs/com.example.*.log

# 检查 S3 存储桶
aws s3 ls s3://${COMPONENT_BUCKET}

# 重新部署
cd lab4-iec104-collector
./deploy.sh
```

## 完整安装时间

- 环境安装: ~10 分钟
- Greengrass 安装: ~5 分钟
- 组件构建和部署: ~15 分钟
- **总计: ~30 分钟**

## 卸载

```bash
# 停止 Greengrass
sudo systemctl stop greengrass
sudo systemctl disable greengrass

# 删除 Greengrass
sudo rm -rf /greengrass

# 删除 Docker 容器
docker stop $(docker ps -aq)
docker rm $(docker ps -aq)

# 删除项目
rm -rf ~/workshop
```
