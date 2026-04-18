//! NAPI 认证模块

use std::path::PathBuf;
use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;
use crate::error::bridge_error_to_napi;

use sdk_wrapper::auth::{login_with_password, logout, has_session};
use sdk_wrapper::session::{save_session, load_session, restore_session, delete_session};
use sdk_wrapper::client::clear_client;
use sdk_wrapper::encryption::clear_sync_service;
use sdk_wrapper::room_list::clear_room_list_service;

/// 清除所有全局状态
/// 用于 logout 时重置状态，以便下次登录时可以重新设置
#[napi]
pub async fn napi_clear_state() {
    get_runtime()
        .spawn(async move {
            clear_client();
            clear_sync_service().await;
            clear_room_list_service().await;
            tracing::info!("All global state cleared");
        })
        .await
        .map_err(|e| tracing::error!("Clear state failed: {:?}", e));
}

/// 密码登录
#[napi]
pub async fn napi_login_password(
    homeserver: String,
    username: String,
    password: String,
    data_dir: String,
) -> Result<String> {
    get_runtime()
        .spawn(async move {
            let path = PathBuf::from(data_dir);

            let session = login_with_password(&homeserver, &username, &password, &path)
                .await
                .map_err(bridge_error_to_napi)?;

            save_session(&session, &path)
                .await
                .map_err(bridge_error_to_napi)?;

            Ok(serde_json::to_string(&session)
                .map_err(|e| Error::from_reason(e.to_string()))?)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 检查是否有会话
#[napi]
pub fn napi_has_session() -> bool {
    has_session()
}

/// 恢复会话
#[napi]
pub async fn napi_restore_session(data_dir: String) -> Result<String> {
    get_runtime()
        .spawn(async move {
            let path = PathBuf::from(data_dir);

            let session = load_session(&path)
                .await
                .map_err(bridge_error_to_napi)?;

            match session {
                Some(session) => {
                    restore_session(&session, &path)
                        .await
                        .map_err(bridge_error_to_napi)?;

                    Ok(serde_json::to_string(&session)
                        .map_err(|e| Error::from_reason(e.to_string()))?)
                }
                None => {
                    Err(bridge_error_to_napi(
                        sdk_wrapper::error::BridgeError::new(
                            sdk_wrapper::error::ErrorCode::SessionExpired,
                            "No saved session"
                        )
                    ))
                }
            }
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 登出
/// 参考 Element X Android: 删除整个 session 目录并移除 session 记录
/// 清除全局状态以便下次登录时可以重新设置
#[napi]
pub async fn napi_logout(data_dir: String) -> Result<()> {
    get_runtime()
        .spawn(async move {
            let path = PathBuf::from(data_dir);

            // 加载 session 数据（获取 session_path 和 cache_path）
            let session = load_session(&path)
                .await
                .map_err(bridge_error_to_napi)?;

            // 调用 SDK logout（可能失败，但继续清理本地状态）
            if let Err(e) = logout().await {
                tracing::warn!("SDK logout failed (continuing with local cleanup): {:?}", e);
            }

            // 删除 session 目录和 cache 目录
            if let Some(session) = session {
                delete_session(&session).await.map_err(bridge_error_to_napi)?;
            }

            // 删除 session.json 文件
            let session_file = path.join("session.json");
            if session_file.exists() {
                tokio::fs::remove_file(&session_file).await
                    .map_err(|e| Error::from_reason(e.to_string()))?;
            }

            // 清除全局状态（必须在最后执行，确保下次登录可以重新设置）
            clear_client();
            clear_sync_service().await;
            clear_room_list_service().await;
            tracing::info!("All global state cleared on logout");

            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}