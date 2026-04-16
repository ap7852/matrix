# Element X HarmonyOS Native Build Configuration
#
# 集成 Rust NAPI 桥接层 (libmatrix_bridge.so)
#
cmake_minimum_required(VERSION 3.5.0)
project(matrix_harmonyos)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

# Rust NAPI 库路径 - 使用 release 构建
set(RUST_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../rust/target/aarch64-unknown-linux-ohos/release)
set(RUST_LIB_PATH ${RUST_LIB_DIR}/libmatrix_bridge.so)

# 检查 Rust 库是否存在
if(EXISTS ${RUST_LIB_PATH})
    message(STATUS "Found Rust NAPI library: ${RUST_LIB_PATH}")
else()
    message(WARNING "Rust NAPI library not found at ${RUST_LIB_PATH}")
    message(STATUS "Please build Rust library first:")
    message(STATUS "  cd rust && cargo build --target aarch64-unknown-linux-ohos --release")
endif()

# 保留原有的 C++ NAPI 模块作为备选/测试
add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so)