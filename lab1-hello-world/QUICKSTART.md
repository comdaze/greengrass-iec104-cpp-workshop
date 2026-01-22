# Lab 1 快速参考

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab1-hello-world

# 1. 本地测试
./test-local.sh

# 2. 构建
./build.sh

# 3. 打包
./package.sh

# 4. 设置环境变量
export COMPONENT_BUCKET=your-bucket-name
export AWS_REGION=us-east-1

# 5. 部署
./deploy.sh
```

## 常用命令

```bash
# 查看组件列表
sudo /greengrass/v2/bin/greengrass-cli component list

# 查看组件详情
sudo /greengrass/v2/bin/greengrass-cli component details -n com.example.HelloWorld

# 查看日志
sudo tail -f /greengrass/v2/logs/com.example.HelloWorld.log

# 重启Greengrass
sudo systemctl restart greengrass
```

## 配置更新

修改消息内容：
```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):thing/${THING_NAME}" \
  --components '{
    "com.example.HelloWorld": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"message\":\"New message!\",\"interval\":3}"
      }
    }
  }'
```

## 故障排除

| 问题 | 解决方案 |
|------|---------|
| 组件无法启动 | 检查日志：`sudo cat /greengrass/v2/logs/com.example.HelloWorld.log` |
| 权限错误 | 确保二进制有执行权限：`chmod +x` |
| S3访问失败 | 检查Token Exchange Role的S3权限 |
| 配置不生效 | 等待30秒让配置同步，或重启组件 |

## 文件结构

```
lab1-hello-world/
├── src/
│   └── hello_world.cpp      # 源代码
├── CMakeLists.txt            # 构建配置
├── recipe.yaml               # Greengrass Recipe
├── build.sh                  # 构建脚本
├── package.sh                # 打包脚本
├── deploy.sh                 # 部署脚本
├── test-local.sh             # 本地测试脚本
└── README.md                 # 详细文档
```
