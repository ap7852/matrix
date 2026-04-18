//! 加密同步模块 - 使用 SyncService 统一管理
//!
//! 使用 matrix-sdk-ui 的 SyncService 同时运行 EncryptionSyncService 和 RoomListService
//!
//! 使用 tokio::sync::Mutex 以支持 async 任务中的跨线程发送

use tokio::sync::Mutex;

use tracing::debug;

use crate::client::get_client;
use crate::error::{BridgeError, ErrorCode};

/// 全局 SyncService 单例（使用 tokio::sync::Mutex 支持异步任务）
pub static SYNC_SERVICE: Mutex<Option<matrix_sdk_ui::sync_service::SyncService>> = Mutex::const_new(None);

/// 初始化 SyncService（同时包含 EncryptionSyncService 和 RoomListService）
pub async fn init_sync_service() -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    debug!("Creating SyncService (includes EncryptionSyncService and RoomListService)...");

    // 使用 builder 创建 SyncService
    let service = matrix_sdk_ui::sync_service::SyncService::builder(client)
        .build()
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    // 使用 Mutex 存储
    {
        let mut guard = SYNC_SERVICE.lock().await;
        *guard = Some(service);
    }

    debug!("SyncService created");

    Ok(())
}

/// 获取 RoomListService（用于房间列表订阅）
/// 返回 Arc，因为 RoomListService 可以被共享
/// 注意：此函数是 async 因为 tokio::sync::Mutex::lock() 需要 await
pub async fn get_room_list_service() -> Option<std::sync::Arc<matrix_sdk_ui::room_list_service::RoomListService>> {
    let guard = SYNC_SERVICE.lock().await;
    guard.as_ref().map(|s| s.room_list_service())
}

/// 启动同步（同时启动加密同步和房间列表同步）
pub async fn start_sync() -> Result<(), BridgeError> {
    let guard = SYNC_SERVICE.lock().await;
    let service = guard.as_ref()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "SyncService not initialized"))?;

    // 启动同步
    service.start().await;

    debug!("SyncService started");

    Ok(())
}

/// 停止同步
pub async fn stop_sync() -> Result<(), BridgeError> {
    let guard = SYNC_SERVICE.lock().await;
    let service = guard.as_ref()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "SyncService not initialized"))?;

    service.stop().await;

    debug!("SyncService stopped");

    Ok(())
}

/// 清除 SyncService（用于 logout）
/// 注意：此函数是 async 因为 tokio::sync::Mutex::lock() 需要 await
pub async fn clear_sync_service() {
    let mut guard = SYNC_SERVICE.lock().await;
    *guard = None;
    debug!("SyncService cleared");
}