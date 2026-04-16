#!/bin/bash
# Element X HarmonyOS 自动化调试脚本
# 在 Linux 上完成：编译 → 构建 → 部署 → 日志监控

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

DEVICE_IP="192.168.1.4"
DEVICE_PORT="39929"

echo "=== Element X HarmonyOS 自动调试 ==="

# ============================================
# Step 1: 连接设备
# ============================================
echo "[1/5] 连接设备..."
hdc tconn ${DEVICE_IP}:${DEVICE_PORT} 2>&1 || {
    echo "警告: 设备连接失败，尝试继续..."
}

# ============================================
# Step 2: 编译 Rust NAPI
# ============================================
echo "[2/5] 编译 Rust NAPI bridge..."
cd "$PROJECT_DIR/rust"
cargo +1.88 build --target aarch64-unknown-linux-ohos --release

# 复制 .so 到 cpp 目录
RUST_SO="$PROJECT_DIR/rust/target/aarch64-unknown-linux-ohos/release/libmatrix_bridge.so"
CPP_DIR="$PROJECT_DIR/entry/src/main/cpp"
cp "$RUST_SO" "$CPP_DIR/"
echo "  ✓ libmatrix_bridge.so 已复制"

# ============================================
# Step 3: 构建 HAP (使用自动签名)
# ============================================
echo "[3/5] 构建 HAP..."
cd "$PROJECT_DIR"

# 清理旧构建
rm -rf .hvigor entry/build

# 构建 (自动签名需要在 DevEco Studio 配置过)
# 如果没有签名，生成 unsigned HAP
hvigorw assembleHap --mode module -p module=entry@default -p product=default 2>&1 || {
    echo "警告: 签名失败，尝试安装 unsigned HAP..."
}

HAP_FILE="$PROJECT_DIR/entry/build/default/outputs/default/entry-default-signed.hap"
if [ ! -f "$HAP_FILE" ]; then
    # 如果签名版不存在，尝试 unsigned 版
    HAP_FILE="$PROJECT_DIR/entry/build/default/outputs/default/entry-default-unsigned.hap"
fi
if [ -f "$HAP_FILE" ]; then
    echo "  ✓ HAP 已生成"
else
    echo "  ✗ HAP 构建失败"
    exit 1
fi

# ============================================
# Step 4: 部署到设备
# ============================================
echo "[4/5] 部署到设备..."

# 先卸载旧版本
hdc uninstall org.matrix.chen 2>&1 || true

# 安装新版本
hdc install "$HAP_FILE" 2>&1 || {
    echo "  ✗ 安装失败 (可能需要签名)"
    echo "  提示: 在 DevEco Studio 中配置自动签名后重试"
    exit 1
}
echo "  ✓ 应用已安装"

# ============================================
# Step 5: 启动应用并监控日志
# ============================================
echo "[5/5] 启动应用..."
hdc shell aa start -a EntryAbility -b org.matrix.chen 2>&1

echo ""
echo "=== 部署完成 ==="
echo ""
echo "监控日志 (Ctrl+C 退出):"
echo "---"
hdc shell hilog -x 2>&1 | grep --line-buffered -E "(org.matrix.chen|MatrixBridge|AuthService|LoginPage)"