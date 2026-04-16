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

# Rust NAPI 库路径 (由 cargo build 生成)
set(RUST_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../rust/target/aarch64-unknown-linux-ohos/release)
set(RUST_LIB_DEBUG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../rust/target/aarch64-unknown-linux-ohos/debug)

# 优先使用 release 构建，debug 时使用 debug 目录
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(RUST_LIB_PATH ${RUST_LIB_DEBUG_DIR}/libmatrix_bridge.so)
else()
    set(RUST_LIB_PATH ${RUST_LIB_DIR}/libmatrix_bridge.so)
endif()

# 检查 Rust 库是否存在
if(EXISTS ${RUST_LIB_PATH})
    message(STATUS "Found Rust NAPI library: ${RUST_LIB_PATH}")

    # 将 Rust 库复制到输出目录 (HarmonyOS 需要特定路径)
    add_custom_command(
        OUTPUT ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libmatrix_bridge.so
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${RUST_LIB_PATH}
        ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libmatrix_bridge.so
        DEPENDS ${RUST_LIB_PATH}
        COMMENT "Copying Rust NAPI library to output directory"
    )

    # 创建目标用于复制
    add_custom_target(copy_rust_lib ALL
        DEPENDS ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libmatrix_bridge.so
    )
else()
    message(WARNING "Rust NAPI library not found at ${RUST_LIB_PATH}")
    message(STATUS "Please build Rust library first:")
    message(STATUS "  cd rust && cargo build --target aarch64-unknown-linux-ohos --release")
endif()

# 保留原有的 C++ NAPI 模块作为备选/测试
# 最终将被 Rust NAPI 模块完全替代
add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so)

# 确保输出目录存在
set_target_properties(entry PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}
)