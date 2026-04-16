//! 认证模块 - 密码登录

use std::path::Path;
use serde::{Deserialize, Serialize};

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
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionData {
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
    pub homeserver_url: String,
}

/// 密码登录
pub async fn login_with_password(
    homeserver: &str,
    username: &str,
    password: &str,
    data_dir: &Path,
) -> Result<SessionData, BridgeError> {
    let homeserver_url = format_homeserver_url(homeserver);
    let client = build_client(&homeserver_url, data_dir, None).await?;

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