//! 房间列表模块 - RoomListService 实现
//!
//! 使用 matrix-sdk-ui 的 SyncService 提供的 RoomListService 进行 Sliding Sync
//!
//! 注意：RoomListService 来自 SyncService（encryption.rs），返回 Arc，可用于 async 任务

use serde::{Deserialize, Serialize};
use tracing::{debug, error};

use crate::encryption::get_room_list_service;
use crate::error::{BridgeError, ErrorCode};

// 使用 matrix_sdk_ui 重导出的 eyeball_im 类型
use matrix_sdk_ui::eyeball_im::VectorDiff;

/// 房间摘要数据
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RoomSummary {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub last_message: Option<String>,
    pub timestamp: Option<String>,
    pub unread_count: u32,
    pub is_encrypted: bool,
}

/// 房间列表增量更新
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum RoomListDiff {
    #[serde(rename = "reset")]
    Reset { items: Vec<RoomSummary> },
    #[serde(rename = "insert")]
    Insert { index: usize, item: RoomSummary },
    #[serde(rename = "update")]
    Update { index: usize, item: RoomSummary },
    #[serde(rename = "remove")]
    Remove { index: usize },
    #[serde(rename = "append")]
    Append { items: Vec<RoomSummary> },
}

/// 房间列表更新消息
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RoomListUpdate {
    pub diffs: Vec<RoomListDiff>,
}

/// 初始化 RoomListService
/// 注意：实际 RoomListService 由 SyncService（encryption.rs）管理
/// 此函数检查 SyncService 是否已初始化
pub async fn init_room_list_service() -> Result<(), BridgeError> {
    // RoomListService 由 SyncService 管理，此处无需初始化
    // 仅检查 SyncService 是否已初始化
    if get_room_list_service().await.is_none() {
        return Err(BridgeError::new(ErrorCode::SessionExpired, "SyncService not initialized"));
    }
    debug!("RoomListService ready (from SyncService)");
    Ok(())
}

/// 启动 Sliding Sync 并订阅房间列表更新
/// 使用 SyncService 提供的 RoomListService（Arc 类型）
pub async fn start_room_list_sync(
    update_callback: impl Fn(String) + Send + 'static,
) -> Result<(), BridgeError> {
    // 获取 Arc<RoomListService>（可以克隆并用于 async 任务）
    let service = get_room_list_service().await
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "RoomListService not initialized"))?;

    // 克隆 Arc 用于 async 任务（确保 RoomListService 在 async 任务中存活）
    let service_for_spawn = service.clone();

    debug!("RoomListService sync started");

    tokio::spawn(async move {
        use matrix_sdk::stream::StreamExt;
        use tokio::select;

        // 在 async block 内创建 room_list 和 sync_stream
        // 这样它们可以借用 service_for_spawn（Arc，'static）
        let page_size = 20;

        let room_list = match service_for_spawn.all_rooms().await {
            Ok(rl) => rl,
            Err(e) => {
                error!("Failed to get room list: {:?}", e);
                return;
            }
        };

        let (stream, controller) = room_list.entries_with_dynamic_adapters(page_size);
        let sync_stream = service_for_spawn.sync();

        // 设置空过滤器（显示所有房间）- 这会触发初始 reset
        controller.set_filter(Box::new(|_| true));

        debug!("Filter set, stream should start yielding diffs");

        // 使用 Box::pin 来 pin stream
        let mut sync_stream = Box::pin(sync_stream);
        let mut stream = Box::pin(stream);

        loop {
            select! {
                // 处理房间列表更新
                Some(diffs) = stream.next() => {
                    debug!("Received {} diffs from room list stream", diffs.len());
                    let converted_diffs: Vec<RoomListDiff> = diffs
                        .into_iter()
                        .flat_map(convert_vector_diff)
                        .collect();

                    if !converted_diffs.is_empty() {
                        let update = RoomListUpdate { diffs: converted_diffs };
                        let json = serde_json::to_string(&update).unwrap_or_default();
                        debug!("Sending room list update: {} diffs", update.diffs.len());
                        update_callback(json);
                    }
                }

                // 处理同步状态
                result = sync_stream.next() => {
                    match result {
                        Some(Ok(())) => {
                            debug!("Sync iteration complete");
                        }
                        Some(Err(e)) => {
                            error!("Sync error: {:?}", e);
                        }
                        None => {
                            debug!("Sync stream ended");
                            break;
                        }
                    }
                }
            }
        }
    });

    Ok(())
}

/// 将 VectorDiff<RoomListItem> 转换为 RoomListDiff
fn convert_vector_diff(diff: VectorDiff<matrix_sdk_ui::room_list_service::RoomListItem>) -> Vec<RoomListDiff> {
    match diff {
        VectorDiff::Reset { values } => {
            debug!("VectorDiff::Reset with {} items", values.len());
            let items: Vec<RoomSummary> = values
                .into_iter()
                .map(room_to_summary)
                .collect();
            debug!("Converted to {} RoomSummary items", items.len());
            vec![RoomListDiff::Reset { items }]
        }
        VectorDiff::Append { values } => {
            let items: Vec<RoomSummary> = values
                .into_iter()
                .map(room_to_summary)
                .collect();
            vec![RoomListDiff::Append { items }]
        }
        VectorDiff::Insert { index, value } => {
            vec![RoomListDiff::Insert {
                index,
                item: room_to_summary(value),
            }]
        }
        VectorDiff::Set { index, value } => {
            vec![RoomListDiff::Update {
                index,
                item: room_to_summary(value),
            }]
        }
        VectorDiff::Remove { index } => {
            vec![RoomListDiff::Remove { index }]
        }
        VectorDiff::Clear { .. } => {
            vec![RoomListDiff::Reset { items: vec![] }]
        }
        VectorDiff::PushFront { value } => {
            vec![RoomListDiff::Insert {
                index: 0,
                item: room_to_summary(value),
            }]
        }
        VectorDiff::PushBack { .. } => {
            // 无法获取确切位置，发送 Reset
            vec![RoomListDiff::Reset { items: vec![] }]
        }
        VectorDiff::PopFront => {
            vec![RoomListDiff::Remove { index: 0 }]
        }
        VectorDiff::PopBack => {
            vec![RoomListDiff::Reset { items: vec![] }]
        }
        VectorDiff::Truncate { .. } => {
            vec![RoomListDiff::Reset { items: vec![] }]
        }
    }
}

/// 将 RoomListItem 转换为 RoomSummary
/// 1:1 复刻 Element X Android RoomInfoMapper:
/// - displayName 优先使用 cached_display_name
/// - fallback 到 name 或 canonical_alias
fn room_to_summary(room: matrix_sdk_ui::room_list_service::RoomListItem) -> RoomSummary {
    // 优先使用 cached_display_name（已计算的名字）
    let name = room.cached_display_name()
        .map(|n| n.to_string())
        // Fallback: 使用 Room.name()（状态事件中的名字）
        .or_else(|| room.name())
        // Fallback: 使用 canonical_alias
        .or_else(|| room.canonical_alias().map(|a| a.to_string()))
        // 最后 fallback: 使用 room_id
        .unwrap_or_else(|| room.room_id().to_string());

    RoomSummary {
        room_id: room.room_id().to_string(),
        name,
        avatar_url: room.avatar_url().map(|u| u.to_string()),
        last_message: None,
        timestamp: room.new_latest_event_timestamp()
            .map(|ts| {
                let millis: i64 = ts.0.into();
                format_timestamp(millis)
            }),
        unread_count: room.num_unread_notifications() as u32,
        is_encrypted: false,
    }
}

/// 格式化时间戳为可读字符串
fn format_timestamp(millis: i64) -> String {
    use std::time::{UNIX_EPOCH};

    let duration = UNIX_EPOCH + std::time::Duration::from_millis(millis as u64);
    let datetime: chrono::DateTime<chrono::Local> = duration.into();

    let now = chrono::Local::now();
    let diff = now.signed_duration_since(datetime);

    if diff.num_days() == 0 {
        datetime.format("%H:%M").to_string()
    } else if diff.num_days() < 7 {
        datetime.format("%a").to_string()
    } else {
        datetime.format("%m/%d").to_string()
    }
}

/// 停止房间列表同步
pub async fn stop_room_list_sync() -> Result<(), BridgeError> {
    let service = get_room_list_service().await
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "RoomListService not initialized"))?;

    service.stop_sync()
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Room list sync stopped");

    Ok(())
}

/// 清除 RoomListService（用于 logout）
/// 注意：RoomListService 由 SyncService 管理，此处无需操作
pub async fn clear_room_list_service() {
    // RoomListService 由 SyncService 管理，清除 SyncService 会同时清除 RoomListService
    debug!("RoomListService clear (handled by SyncService)");
}