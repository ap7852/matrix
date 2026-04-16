//! 房间列表模块 - Phase 0 占位版
//!
//! Phase 1 将实现完整的 RoomListService

use serde::{Deserialize, Serialize};

use crate::client::get_client;
use crate::error::{BridgeError, ErrorCode};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomSummary {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub last_message: Option<String>,
    pub timestamp: Option<String>,
    pub unread_count: u32,
    pub is_encrypted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum RoomListDiff {
    Insert { index: usize, item: RoomSummary },
    Update { index: usize, item: RoomSummary },
    Remove { index: usize },
    Clear,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomListUpdate {
    pub diffs: Vec<RoomListDiff>,
}

/// 启动房间列表同步（Phase 0 占位版）
///
/// Phase 1 将使用 RoomListService 的 Sliding Sync API
pub async fn start_room_list_sync(
    update_callback: impl Fn(String) + Send + 'static,
) -> Result<(), BridgeError> {
    let _client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No session"))?;

    // Phase 0: 仅发送一个空更新表示同步启动
    tokio::spawn(async move {
        // 等待一小段时间模拟初始化
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        let update = RoomListUpdate { diffs: vec![] };
        let json = serde_json::to_string(&update).unwrap_or_default();
        update_callback(json);
    });

    Ok(())
}