//! NAPI 加密同步模块
//!
//! SyncService 的 NAPI 封装（同时管理 EncryptionSyncService 和 RoomListService）

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 初始化 SyncService（包含 EncryptionSyncService）
///
/// 登录成功后调用，替代单独的 RoomListService 初始化
#[napi]
pub async fn napi_init_sync_service() -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::encryption::init_sync_service()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 启动同步（同时启动加密同步）
///
/// 在订阅房间列表之前调用
#[napi]
pub async fn napi_start_sync() -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::encryption::start_sync()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 停止同步
#[napi]
pub async fn napi_stop_sync() -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::encryption::stop_sync()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}