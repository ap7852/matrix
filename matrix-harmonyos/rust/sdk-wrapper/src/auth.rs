//! 认证模块 - 密码登录
//! 1:1 复刻 Element X Android: 使用 UUID 作为 session 目录名

use std::path::Path;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::{build_client, set_client, get_client};
use crate::error::{BridgeError, ErrorCode};

/// 格式化 homeserver URL
/// 如果没有协议前缀，自动添加 https://
fn format_homeserver_url(homeserver: &str) -> String {
    let trimmed = homeserver.trim();
    if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
        trimmed.to_string()
    } else {
        format!("https://{}", trimmed)
    }
}

/// 会话数据
/// 参考 Element X Android: 每个用户有独立的 sessionPath 和 cachePath
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionData {
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
    pub homeserver_url: String,
    /// 会话数据目录路径（SQLite store）
    pub session_path: String,
    /// 缓存目录路径
    pub cache_path: String,
}

/// 创建 UUID-based session 目录
/// 参考 Element X Android SessionPathsFactory.create():
/// 使用 UUID.randomUUID().toString() 作为目录名，确保每次登录都是全新目录
fn create_session_paths(base_dir: &Path) -> (std::path::PathBuf, std::path::PathBuf) {
    // 1:1 复刻 Element X Android: 使用 UUID 作为子目录名
    let sub_path = Uuid::new_v4().to_string();

    let session_path = base_dir.join("sessions").join(&sub_path);
    let cache_path = base_dir.join("cache").join(&sub_path);

    (session_path, cache_path)
}

/// 删除所有旧的 session 目录
/// 参考 Element X Android: 登录前清理所有旧 session 数据
fn delete_all_session_dirs(base_dir: &Path) -> Result<(), BridgeError> {
    let sessions_dir = base_dir.join("sessions");
    let cache_dir = base_dir.join("cache");

    // 删除所有 sessions 子目录
    if sessions_dir.exists() {
        std::fs::remove_dir_all(&sessions_dir)
            .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                format!("Failed to remove sessions dir: {}", e)))?;
    }

    // 删除所有 cache 子目录
    if cache_dir.exists() {
        std::fs::remove_dir_all(&cache_dir)
            .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                format!("Failed to remove cache dir: {}", e)))?;
    }

    // 删除旧的 session.json 文件
    let session_file = base_dir.join("session.json");
    if session_file.exists() {
        std::fs::remove_file(&session_file)
            .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                format!("Failed to remove session.json: {}", e)))?;
    }

    // 删除 base 目录中的旧 SQLite 文件（旧代码遗留）
    let old_sqlite_files = [
        "matrix-sdk-state.sqlite3",
        "matrix-sdk-state.sqlite3-shm",
        "matrix-sdk-state.sqlite3-wal",
        "matrix-sdk-crypto.sqlite3",
        "matrix-sdk-crypto.sqlite3-shm",
        "matrix-sdk-crypto.sqlite3-wal",
        "matrix-sdk-event-cache.sqlite3",
        "matrix-sdk-event-cache.sqlite3-shm",
        "matrix-sdk-event-cache.sqlite3-wal",
        "matrix-sdk-media.sqlite3",
        "matrix-sdk-media.sqlite3-shm",
        "matrix-sdk-media.sqlite3-wal",
    ];

    for file_name in old_sqlite_files {
        let file_path = base_dir.join(file_name);
        if file_path.exists() {
            std::fs::remove_file(&file_path)
                .map_err(|e| BridgeError::new(ErrorCode::StorageError,
                    format!("Failed to remove {}: {}", file_name, e)))?;
        }
    }

    Ok(())
}

/// 密码登录
/// 1:1 复刻 Element X Android RustMatrixAuthenticationService.login():
/// 1. 清理所有旧 session 目录（rotateSessionPath）
/// 2. 创建新 UUID session 目录
/// 3. 创建 Client 使用新的 session 目录
/// 4. 登录并保存 session
pub async fn login_with_password(
    homeserver: &str,
    username: &str,
    password: &str,
    data_dir: &Path,
) -> Result<SessionData, BridgeError> {
    let homeserver_url = format_homeserver_url(homeserver);

    // 1:1 复刻 Element X Android: 登录前清理所有旧 session 目录
    delete_all_session_dirs(data_dir)?;

    // 创建新的 UUID-based session 目录
    let (session_path, cache_path) = create_session_paths(data_dir);

    // 确保目录存在
    std::fs::create_dir_all(&session_path)
        .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;
    std::fs::create_dir_all(&cache_path)
        .map_err(|e| BridgeError::new(ErrorCode::StorageError, e.to_string()))?;

    // 使用新的 session 目录创建 client
    let client = build_client(&homeserver_url, &session_path, None).await?;

    // 使用 matrix_auth 模块登录
    let auth = client.matrix_auth();
    auth.login_username(username, password)
        .initial_device_display_name("Element X HarmonyOS")
        .await
        .map_err(|e| BridgeError::new(ErrorCode::AuthenticationFailed, e.to_string()))?;

    // 获取会话
    let session = auth.session()
        .ok_or_else(|| BridgeError::new(ErrorCode::AuthenticationFailed, "No session"))?;

    set_client(client);

    // MatrixSession 结构: meta.user_id, meta.device_id, tokens.access_token
    Ok(SessionData {
        user_id: session.meta.user_id.to_string(),
        device_id: session.meta.device_id.to_string(),
        access_token: session.tokens.access_token.clone(),
        homeserver_url: homeserver_url,
        session_path: session_path.to_string_lossy().to_string(),
        cache_path: cache_path.to_string_lossy().to_string(),
    })
}

/// 检查是否有活跃会话
pub fn has_session() -> bool {
    get_client().is_some()
}

/// 登出
pub async fn logout() -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No session"))?;

    client.matrix_auth().logout().await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    Ok(())
}