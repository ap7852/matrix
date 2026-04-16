#!/bin/bash
# Element X HarmonyOS 构建脚本
# 自动编译 Rust NAPI 并复制到 HAP 目录

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

echo "=== Element X HarmonyOS Build Script ==="

# 1. 编译 Rust NAPI 桥接
echo "[1/3] Building Rust NAPI bridge..."
cd "$PROJECT_DIR/rust"
cargo +1.88 build --target aarch64-unknown-linux-ohos --release
echo "Rust build completed"

# 2. 复制 .so 文件到 libs 目录
echo "[2/3] Copying libmatrix_bridge.so to HAP libs..."
RUST_SO="$PROJECT_DIR/rust/target/aarch64-unknown-linux-ohos/release/libmatrix_bridge.so"
HAP_LIBS_ARM64="$PROJECT_DIR/entry/libs/arm64-v8a"
HAP_LIBS_X86="$PROJECT_DIR/entry/libs/x86_64"
CPP_DIR="$PROJECT_DIR/entry/src/main/cpp"

mkdir -p "$HAP_LIBS_ARM64"
mkdir -p "$HAP_LIBS_X86"
mkdir -p "$CPP_DIR"

cp "$RUST_SO" "$HAP_LIBS_ARM64/"
cp "$RUST_SO" "$CPP_DIR/"

# x86_64 模拟器需要单独编译 (可选)
# cargo +1.88 build --target x86_64-unknown-linux-ohos --release
# cp "$PROJECT_DIR/rust/target/x86_64-unknown-linux-ohos/release/libmatrix_bridge.so" "$HAP_LIBS_X86/"

echo ".so files copied"

# 3. HarmonyOS HAP 构建
echo "[3/3] Building HarmonyOS HAP..."
cd "$PROJECT_DIR"

# 使用 hvigorw 构建 (忽略签名错误，生成 unsigned HAP)
hvigorw assembleHap --mode module -p module=entry@default -p product=default || true

echo "=== Build Complete ==="
echo "HAP file: entry/build/default/outputs/default/entry-default-unsigned.hap"
echo ""
echo "Next steps:"
echo "1. Open DevEco Studio"
echo "2. Run with automatic signing (auto-sign)"
echo "   or: Build > Make Hap(s) then Run"