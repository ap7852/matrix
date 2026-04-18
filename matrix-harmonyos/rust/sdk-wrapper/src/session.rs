//! 会话持久化
//!
//! 参考 Element X Android:
//! - 每个用户有独立的 sessionPath 和 cachePath
//! - logout 时删除整个 session 目录

use std::path::{Path, PathBuf};
use matrix_sdk::authentication::matrix::MatrixSession;

use crate::client::{build_client, set_client};
use crate::error::{BridgeError, ErrorCode};
use crate::auth::SessionData;

fn session_file_path(data_dir: &Path) -> PathBuf {
    data_dir.join("session.json")
}

/// 确保数据目录存在
async fn ensure_data_dir(data_dir: &Path) -> Result<(), BridgeError> {
    if !data_dir.exists() {
        tokio::fs::create_dir_all(data_dir).await
            .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    }
    Ok(())
}

pub async fn save_session(session: &SessionData, data_dir: &Path) -> Result<(), BridgeError> {
    ensure_data_dir(data_dir).await?;
    let path = session_file_path(data_dir);
    let json = serde_json::to_string(session)
        .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    tokio::fs::write(&path, json).await
        .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    Ok(())
}

pub async fn load_session(data_dir: &Path) -> Result<Option<SessionData>, BridgeError> {
    let path = session_file_path(data_dir);
    if !path.exists() { return Ok(None); }
    let json = tokio::fs::read_to_string(&path).await
        .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    let session: SessionData = serde_json::from_str(&json)
        .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    Ok(Some(session))
}

/// 删除会话
/// 参考 Element X Android: 删除整个 sessionPath 和 cachePath 目录
pub async fn delete_session(session: &SessionData) -> Result<(), BridgeError> {
    // 删除 session 目录（包含 SQLite store）
    let session_path = PathBuf::from(&session.session_path);
    if session_path.exists() {
        tokio::fs::remove_dir_all(&session_path).await
            .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                format!("Failed to remove session_path: {}", e)))?;
    }

    // 删除 cache 目录
    let cache_path = PathBuf::from(&session.cache_path);
    if cache_path.exists() {
        tokio::fs::remove_dir_all(&cache_path).await
            .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                format!("Failed to remove cache_path: {}", e)))?;
    }

    Ok(())
}

/// 恢复会话
/// 使用 SessionData 中的 session_path 作为 SQLite store 目录
pub async fn restore_session(session: &SessionData, _data_dir: &Path) -> Result<(), BridgeError> {
    // 使用 session.session_path 作为 SQLite store 目录
    let session_path = PathBuf::from(&session.session_path);
    let client = build_client(&session.homeserver_url, &session_path, None).await?;

    // 解析 user_id
    let user_id = session.user_id.parse::<matrix_sdk::ruma::OwnedUserId>()
        .map_err(|e| BridgeError::new(ErrorCode::AuthenticationFailed, format!("Invalid user ID: {}", e)))?;

    // 构造 MatrixSession - 使用正确的字段结构
    let matrix_session = MatrixSession {
        meta: matrix_sdk::SessionMeta {
            user_id,
            device_id: session.device_id.as_str().try_into()
                .map_err(|e| BridgeError::new(ErrorCode::AuthenticationFailed, format!("Invalid device ID: {}", e)))?,
        },
        tokens: matrix_sdk::SessionTokens {
            access_token: session.access_token.clone(),
            refresh_token: None,
        },
    };

    client.restore_session(matrix_session).await
        .map_err(|e| BridgeError::new(ErrorCode::AuthenticationFailed, e.to_string()))?;

    set_client(client);
    Ok(())
}