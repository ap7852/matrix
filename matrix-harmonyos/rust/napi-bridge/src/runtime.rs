//! Tokio 运行时单例
//!
//! tokio 运行时在 NAPI 模块加载时初始化，整个应用生命周期内只初始化一次。
//! 所有异步 NAPI 函数通过此运行时执行。

use std::sync::OnceLock;
use tokio::runtime::Runtime;

/// 全局 tokio 运行时单例
static TOKIO_RUNTIME: OnceLock<Runtime> = OnceLock::new();

/// 获取 tokio 运行时引用
pub fn get_runtime() -> &'static Runtime {
    TOKIO_RUNTIME
        .get_or_init(|| Runtime::new().expect("Failed to create tokio runtime"))
}

/// 初始化运行时（由 NAPI init 函数调用）
pub fn init_runtime() {
    let _ = get_runtime();
    tracing::info!("tokio runtime initialized for Element X HarmonyOS");
}