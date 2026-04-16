#!/bin/bash
# Element X HarmonyOS 构建脚本
# 自动编译 Rust NAPI 并复制到 HAP 目录

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

echo "=== Element X HarmonyOS Build Script ==="

# 1. 编译 Rust NAPI 桥接
echo "[1/2] Building Rust NAPI bridge..."
cd "$PROJECT_DIR/rust"
cargo +1.88 build --target aarch64-unknown-linux-ohos --release
echo "Rust build completed"

# 2. 复制 .so 文件到 cpp 目录 (CMake 会自动打包)
echo "[2/2] Copying libmatrix_bridge.so to cpp directory..."
RUST_SO="$PROJECT_DIR/rust/target/aarch64-unknown-linux-ohos/release/libmatrix_bridge.so"
CPP_DIR="$PROJECT_DIR/entry/src/main/cpp"

mkdir -p "$CPP_DIR"
cp "$RUST_SO" "$CPP_DIR/"

echo ".so file copied to cpp directory"

# 注意: 不要复制到 entry/libs/ 目录，会导致重复文件错误
# CMake 会自动从 cpp/ 目录打包到 HAP

echo "=== Build Complete ==="
echo ""
echo "Next steps in DevEco Studio:"
echo "1. Clean Project (Build > Clean Project)"
echo "2. Rebuild and Run"