//! 会话持久化

use std::path::{Path, PathBuf};
use matrix_sdk::authentication::matrix::MatrixSession;

use crate::client::{build_client, set_client};
use crate::error::{BridgeError, ErrorCode};
use crate::auth::SessionData;

fn session_file_path(data_dir: &Path) -> PathBuf {
    data_dir.join("session.json")
}

pub async fn save_session(session: &SessionData, data_dir: &Path) -> Result<(), BridgeError> {
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

pub async fn delete_session(data_dir: &Path) -> Result<(), BridgeError> {
    let path = session_file_path(data_dir);
    if path.exists() {
        tokio::fs::remove_file(&path).await
            .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    }
    Ok(())
}

pub async fn restore_session(session: &SessionData, data_dir: &Path) -> Result<(), BridgeError> {
    let client = build_client(&session.homeserver_url, data_dir, None).await?;

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