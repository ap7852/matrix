#!/bin/bash
# 配置 HarmonyOS 自动签名
# 生成调试签名文件

set -e

CONFIG_DIR="$HOME/.ohos/config"
PROJECT_DIR="/vol2/1000/workspace/matrix/matrix-harmonyos"

echo "=== HarmonyOS 签名配置 ==="

mkdir -p "$CONFIG_DIR"

# 检查是否已有签名文件
if [ -f "$CONFIG_DIR/debug_profile.p7b" ]; then
    echo "签名文件已存在"
    exit 0
fi

echo ""
echo "自动签名需要以下文件："
echo "  - debug_certificate.cer  (已存在)"
echo "  - debug_keystore.p12     (已存在)"
echo "  - debug_profile.p7b      (缺失)"
echo ""
echo "生成 debug_profile.p7b 需要华为开发者账号授权。"
echo ""
echo "方案 1: 使用 DevEco Studio 自动签名"
echo "  - 打开 DevEco Studio"
echo "  - File > Project Structure > Signing Configs"
echo "  - 选择 'Automatically generate signature'"
echo "  - 签名后，复制 ~/.ohos/config/ 文件到 Linux"
echo ""
echo "方案 2: 从 Windows 复制签名文件"
echo "  - 如果 Windows 上已配置签名，复制这些文件到 Linux:"
echo "    scp user@windows:.ohos/config/* ~/.ohos/config/"
echo ""
echo "当前可用签名文件："
ls -la "$CONFIG_DIR/" 2>&1