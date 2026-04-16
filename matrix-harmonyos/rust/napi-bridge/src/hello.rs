//! Hello World NAPI 测试函数
//!
//! 用于验证 NAPI 桥接层正常工作

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;
use sdk_wrapper::verify_ring;

/// Hello World - 同步测试函数
/// 返回字符串验证 NAPI 桥接成功
#[napi]
pub fn hello() -> String {
    "Hello from Element X HarmonyOS Rust bridge!".to_string()
}

/// 异步 Hello World - 返回 Promise
/// 验证 tokio 运行时与异步 NAPI 函数工作正常
#[napi]
pub async fn hello_async(name: String) -> String {
    get_runtime().spawn(async move {
        format!("Hello, {}! Welcome to Element X HarmonyOS.", name)
    }).await.unwrap_or_else(|e| format!("Error: {}", e))
}

/// 验证 ring 编译成功
/// 返回 SHA256 哈希值的前 8 字节（十六进制字符串）
#[napi]
pub fn verify_ring_compile() -> String {
    let hash = verify_ring();
    hash[..8].iter().map(|b| format!("{:02x}", b)).collect::<Vec<_>>().join("")
}

/// 计算两个数的和 - 简单测试
/// 替代原有 C++ NAPI 的 add 函数
#[napi]
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

/// 带错误处理的测试函数
#[napi]
pub fn test_error() -> Result<String> {
    Err(Error::from_reason(
        serde_json::to_string(&sdk_wrapper::error::BridgeError::new(
            sdk_wrapper::error::ErrorCode::UnknownError,
            "This is a test error"
        )).unwrap_or_default()
    ))
}