//! Client 单例与初始化
//!
//! 提供全局 Matrix Client 单例。
//! Phase 0: 不使用 SQLite store（简化版）
//! Phase 1: 添加 SQLite store 和 Asset Store Kit 密钥

use std::path::Path;
use std::sync::OnceLock;

use crate::error::{BridgeError, ErrorCode};

/// 全局 Client 单例
pub static CLIENT: OnceLock<matrix_sdk::Client> = OnceLock::new();

/// 获取当前 Client
pub fn get_client() -> Option<matrix_sdk::Client> {
    CLIENT.get().cloned()
}

/// 设置全局 Client
pub fn set_client(client: matrix_sdk::Client) {
    let _ = CLIENT.set(client);
}

/// 构建 Client 实例（Phase 0 简化版）
///
/// # Arguments
/// * `homeserver_url` - Matrix 服务器地址
/// * `data_dir` - 数据目录（Phase 1 用于 SQLite）
/// * `passphrase` - 加密密码（Phase 1 使用）
pub async fn build_client(
    homeserver_url: &str,
    _data_dir: &Path,
    _passphrase: Option<&str>,
) -> Result<matrix_sdk::Client, BridgeError> {
    // Phase 0: 使用基本 Client 创建（无持久化）
    // Phase 1: 添加 sqlite_store
    let client = matrix_sdk::Client::builder()
        .homeserver_url(homeserver_url)
        .build()
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    Ok(client)
}