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

# 原有 C++ NAPI 模块
add_library(entry SHARED napi_init.cpp)
target_link_libraries(entry PUBLIC libace_napi.z.so)

# Rust NAPI 库 - 复制到输出目录
set(RUST_LIB_SRC ${CMAKE_CURRENT_SOURCE_DIR}/libmatrix_bridge.so)

if(EXISTS ${RUST_LIB_SRC})
    message(STATUS "Found Rust NAPI library: ${RUST_LIB_SRC}")
    message(STATUS "Copying to: ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")

    # 复制到库输出根目录（不嵌套 ABI）
    add_custom_command(
        TARGET entry POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${RUST_LIB_SRC}
        ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/libmatrix_bridge.so
    )
else()
    message(WARNING "Rust NAPI library not found at ${RUST_LIB_SRC}")
endif()