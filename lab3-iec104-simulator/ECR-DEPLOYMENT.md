# Lab 3 Docker版本 - ECR部署指南

## 前置条件

需要以下IAM权限：

### ECR权限
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
        "ecr:CompleteLayerUpload",
        "ecr:CreateRepository",
        "ecr:DescribeRepositories",
        "ecr:DescribeImages"
      ],
      "Resource": "*"
    }
  ]
}
```

### Greengrass Token Exchange Role权限
Greengrass设备需要从ECR拉取镜像，需要添加以下权限到Token Exchange Role：

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
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```

## 部署步骤

### 1. 推送镜像到ECR

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab3-iec104-simulator

# 执行推送脚本
./push-to-ecr.sh
```

脚本会：
- 创建ECR仓库（如果不存在）
- 登录ECR
- 标记镜像
- 推送镜像到ECR
- 验证推送结果

### 2. 更新Recipe

编辑 `recipe-docker-ecr.yaml`，替换 `imageUri`：

```yaml
ComponentConfiguration:
  DefaultConfiguration:
    imageUri: "{account-id}.dkr.ecr.cn-north-1.amazonaws.com.cn/iec104-simulator:1.0.0"
    port: 2404
```

### 3. 创建Greengrass组件

```bash
export AWS_REGION="cn-north-1"

aws greengrassv2 create-component-version \
  --inline-recipe fileb://recipe-docker-ecr.yaml \
  --region ${AWS_REGION}
```

### 4. 部署到Greengrass

```bash
export THING_NAME="GreengrassQuickStartCore-19be3781cbc"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_IMAGE_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com.cn/iec104-simulator:1.0.0"

aws greengrassv2 create-deployment \
  --target-arn "arn:aws-cn:iot:${AWS_REGION}:${ACCOUNT_ID}:thing/${THING_NAME}" \
  --deployment-name "IEC104-Simulator-Docker-ECR-$(date +%s)" \
  --components "{
    \"com.example.IEC104SimulatorDocker\": {
      \"componentVersion\": \"1.0.2\",
      \"configurationUpdate\": {
        \"merge\": \"{\\\"imageUri\\\":\\\"${ECR_IMAGE_URI}\\\",\\\"port\\\":2404}\"
      }
    }
  }" \
  --region ${AWS_REGION}
```

### 5. 验证部署

```bash
# 查看容器状态
sudo docker ps | grep iec104-simulator

# 查看容器日志
sudo docker logs iec104-simulator

# 测试端口
nc -zv localhost 2404

# 查看Greengrass日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104SimulatorDocker.log
```

## 本地镜像 vs ECR镜像

### 本地镜像（当前使用）
- ✅ 优点：无需网络，部署快速
- ❌ 缺点：需要在每个设备上构建，无法集中管理

### ECR镜像
- ✅ 优点：集中管理，版本控制，多设备部署
- ✅ 优点：自动拉取最新版本
- ❌ 缺点：需要网络连接，需要ECR权限

## 故障排查

### 问题1: ECR登录失败
```
Error: Cannot perform an interactive login from a non TTY device
```

**解决**：确保有 `ecr:GetAuthorizationToken` 权限

### 问题2: 镜像拉取失败
```
Error response from daemon: pull access denied
```

**解决**：
1. 检查Token Exchange Role是否有ECR读取权限
2. 确认镜像URI正确
3. 检查网络连接

### 问题3: 容器启动失败
```
docker: Error response from daemon: Conflict
```

**解决**：停止并删除旧容器
```bash
docker stop iec104-simulator
docker rm iec104-simulator
```

## 文件说明

- `Dockerfile` - Docker镜像构建文件
- `CMakeLists-docker.txt` - Docker专用构建配置
- `recipe-docker-local.yaml` - 本地镜像Recipe（v1.0.1）
- `recipe-docker-ecr.yaml` - ECR镜像Recipe模板（v1.0.2）
- `push-to-ecr.sh` - ECR推送脚本
- `nlohmann/` - JSON库头文件

## 当前状态

✅ 本地Docker镜像构建成功（70MB）
✅ 本地部署到Greengrass成功（v1.0.1）
✅ Shutdown权限问题已修复
⏳ ECR推送待执行（需要ECR权限）

## 下一步

1. 获取ECR权限后执行 `./push-to-ecr.sh`
2. 更新 `recipe-docker-ecr.yaml` 中的imageUri
3. 部署ECR版本（v1.0.2）
4. 继续Lab 4 - IEC104数据采集器
