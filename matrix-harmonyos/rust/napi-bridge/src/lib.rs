//! NAPI Bridge - Rust to ArkTS FFI 导出层
//!
//! 此模块通过 ohos-rs (napi-ohos) 导出异步函数供 ArkTS 调用。
//! 所有导出函数返回 Promise<String> (JSON 序列化)。
//!
//! 职责边界：
//! - 将 ArkTS 调用转换为 Rust 异步任务
//! - 将 Rust 事件通过 ThreadSafeFunction 回调到 ArkTS
//! - Rust 类型与 ArkTS 类型之间的 JSON 序列化/反序列化
//!
//! 禁止在此层包含任何业务逻辑！

// 增加递归限制，解决 matrix-sdk 编译时的深度限制问题
// matrix-sdk 的 async 函数嵌套深度很高，需要较大的限制
#![recursion_limit = "4096"]

mod runtime;
mod error;
mod hello;
mod auth;
mod room_list;
mod timeline;
mod encryption;
mod media;

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;

/// NAPI 模块初始化入口
/// 在 ArkTS 加载模块时自动调用
#[napi]
pub fn init() {
    // 初始化 tokio 运行时
    runtime::init_runtime();
    // 初始化日志 (待实现)
}

// 导出测试函数
pub use hello::*;

// 导出认证函数
pub use auth::*;

// 导出房间列表函数
pub use room_list::*;

// 导出 Timeline 函数
pub use timeline::*;

// 导出加密同步函数
pub use encryption::*;

// 导出媒体函数
pub use media::*;