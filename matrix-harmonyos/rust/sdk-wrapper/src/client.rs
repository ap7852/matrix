//! Client 单例与初始化
//!
//! 提供全局 Matrix Client 单例。
//! Phase 1: 使用 SQLite 持久化存储
//!
//! 使用 std::sync::Mutex<Option<Client>> 而非 OnceLock，
//! 以支持 logout 后重新登录时重置 Client。

use std::path::Path;
use std::sync::Mutex;

use crate::error::{BridgeError, ErrorCode};

/// 全局 Client 单例（使用 Mutex<Option> 支持重置）
pub static CLIENT: Mutex<Option<matrix_sdk::Client>> = Mutex::new(None);

/// SQLite store 文件名前缀（参考 Element X Android）
const SQLITE_STORE_FILES: [&str; 6] = [
    "matrix-sdk-state.sqlite3",
    "matrix-sdk-state.sqlite3-shm",
    "matrix-sdk-state.sqlite3-wal",
    "matrix-sdk-crypto.sqlite3",
    "matrix-sdk-crypto.sqlite3-shm",
    "matrix-sdk-crypto.sqlite3-wal",
];

/// 清理 SQLite store 数据
/// 用于登录前清除旧账户数据，避免 crypto store 账户冲突
pub fn clear_sqlite_store(data_dir: &Path) -> Result<(), BridgeError> {
    if !data_dir.exists() {
        return Ok(());
    }

    for file_name in SQLITE_STORE_FILES {
        let file_path = data_dir.join(file_name);
        if file_path.exists() {
            std::fs::remove_file(&file_path)
                .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                    format!("Failed to remove {}: {}", file_name, e)))?;
        }
    }

    Ok(())
}

/// 获取当前 Client
pub fn get_client() -> Option<matrix_sdk::Client> {
    CLIENT.lock().unwrap().clone()
}

/// 设置全局 Client
pub fn set_client(client: matrix_sdk::Client) {
    let mut guard = CLIENT.lock().unwrap();
    *guard = Some(client);
}

/// 清除全局 Client（用于 logout）
pub fn clear_client() {
    let mut guard = CLIENT.lock().unwrap();
    *guard = None;
}

/// 构建 Client 实例（Phase 1 SQLite 持久化版本）
///
/// # Arguments
/// * `homeserver_url` - Matrix 服务器地址
/// * `data_dir` - 数据目录（用于 SQLite 存储）
/// * `passphrase` - 加密密码（用于 SQLite 加密）
pub async fn build_client(
    homeserver_url: &str,
    data_dir: &Path,
    passphrase: Option<&str>,
) -> Result<matrix_sdk::Client, BridgeError> {
    // 确保数据目录存在
    if !data_dir.exists() {
        std::fs::create_dir_all(data_dir)
            .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    }

    // Phase 1: 使用 SQLite 持久化存储
    let client = matrix_sdk::Client::builder()
        .homeserver_url(homeserver_url)
        .sqlite_store(data_dir, passphrase)
        .build()
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    Ok(client)
}