//! NAPI 认证模块

use std::path::PathBuf;
use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;
use crate::error::bridge_error_to_napi;

use sdk_wrapper::auth::{login_with_password, logout, has_session};
use sdk_wrapper::session::{save_session, load_session, restore_session, delete_session};

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
#[napi]
pub async fn napi_logout(data_dir: String) -> Result<()> {
    get_runtime()
        .spawn(async move {
            let path = PathBuf::from(data_dir);

            logout().await.map_err(bridge_error_to_napi)?;

            delete_session(&path).await.map_err(bridge_error_to_napi)?;

            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}