#!/bin/bash
# 推送Docker镜像到AWS ECR
# 需要ECR权限: ecr:GetAuthorizationToken, ecr:BatchCheckLayerAvailability, 
#              ecr:PutImage, ecr:InitiateLayerUpload, ecr:UploadLayerPart, 
#              ecr:CompleteLayerUpload

set -e

# 配置
export AWS_REGION="${AWS_REGION:-ap-northeast-1}"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export IMAGE_NAME="iec104-simulator"
export IMAGE_TAG="1.0.0"
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export ECR_REPOSITORY="${ECR_REGISTRY}/${IMAGE_NAME}"

echo "=== 配置信息 ==="
echo "AWS Region: ${AWS_REGION}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR Registry: ${ECR_REGISTRY}"
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# 1. 创建ECR仓库（如果不存在）
echo "=== 步骤1: 创建ECR仓库 ==="
aws ecr create-repository \
  --repository-name ${IMAGE_NAME} \
  --region ${AWS_REGION} 2>/dev/null || echo "仓库已存在"
echo ""

# 2. 登录ECR
echo "=== 步骤2: 登录ECR ==="
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${ECR_REGISTRY}
echo ""

# 3. 标记镜像
echo "=== 步骤3: 标记镜像 ==="
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REPOSITORY}:${IMAGE_TAG}
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REPOSITORY}:latest
echo "✅ 镜像已标记"
echo ""

# 4. 推送镜像
echo "=== 步骤4: 推送镜像到ECR ==="
docker push ${ECR_REPOSITORY}:${IMAGE_TAG}
docker push ${ECR_REPOSITORY}:latest
echo ""

# 5. 验证
echo "=== 步骤5: 验证镜像 ==="
aws ecr describe-images \
  --repository-name ${IMAGE_NAME} \
  --region ${AWS_REGION} \
  --query 'imageDetails[*].[imageTags[0],imageSizeInBytes,imagePushedAt]' \
  --output table
echo ""

echo "✅ 镜像推送成功！"
echo ""
echo "ECR镜像URI:"
echo "  ${ECR_REPOSITORY}:${IMAGE_TAG}"
echo "  ${ECR_REPOSITORY}:latest"
echo ""
echo "在Greengrass Recipe中使用:"
echo "  imageUri: \"${ECR_REPOSITORY}:${IMAGE_TAG}\""
