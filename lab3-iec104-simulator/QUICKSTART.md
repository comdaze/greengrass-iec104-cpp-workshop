# Lab 3 快速参考

## 快速开始

```bash
cd /home/ubuntu/iec104-greengrass/workshop/lab3-iec104-simulator

# 本地测试
./test-local.sh

# 构建和部署
./build.sh
./package.sh
./deploy.sh
```

## 验证

```bash
# 查看日志
sudo tail -f /greengrass/v2/logs/com.example.IEC104Simulator.log

# 检查端口
sudo netstat -tlnp | grep 2404
```

## 数据点

- 1001: 风机有功功率 (1500±200 kW)
- 1002: 风机无功功率 (200±50 kVar)
- 1003: 风速 (8.5±2.0 m/s)
- 2001: 储能SOC (75±10 %)
- 2002: 储能充电功率 (500±100 kW)
- 3001: 变电站电压 (35±1.0 kV)
