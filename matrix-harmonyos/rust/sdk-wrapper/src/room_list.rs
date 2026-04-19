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

        debug!("Filter set, stream should start yielding diffs");

        // 使用 SDK 提供的过滤器排除 spaces（空间房间）
        use matrix_sdk_ui::room_list_service::filters;
        controller.set_filter(Box::new(
            filters::new_filter_not(Box::new(filters::new_filter_space()))
        ));

        // 使用 Box::pin 来 pin stream
        let mut sync_stream = Box::pin(sync_stream);
        let mut stream = Box::pin(stream);

        loop {
            select! {
                // 处理房间列表更新
                Some(diffs) = stream.next() => {
                    debug!("Received {} diffs from room list stream", diffs.len());

                    // 异步处理每个 diff
                    let converted_diffs = convert_diffs_async(diffs).await;

                    if !converted_diffs.is_empty() {
                        let update = RoomListUpdate { diffs: converted_diffs };
                        let json = serde_json::to_string(&update).unwrap_or_default();
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

/// 异步处理多个 VectorDiff，转换为 RoomListDiff
async fn convert_diffs_async(diffs: Vec<VectorDiff<matrix_sdk_ui::room_list_service::RoomListItem>>) -> Vec<RoomListDiff> {
    let mut result = Vec::with_capacity(diffs.len());

    for diff in diffs {
        match diff {
            VectorDiff::Reset { values } => {
                debug!("VectorDiff::Reset with {} items", values.len());
                // 异步处理每个房间
                let mut items = Vec::with_capacity(values.len());
                for room in values {
                    items.push(room_to_summary_async(room).await);
                }
                debug!("Converted to {} RoomSummary items", items.len());
                result.push(RoomListDiff::Reset { items });
            }
            VectorDiff::Append { values } => {
                let mut items = Vec::with_capacity(values.len());
                for room in values {
                    items.push(room_to_summary_async(room).await);
                }
                result.push(RoomListDiff::Append { items });
            }
            VectorDiff::Insert { index, value } => {
                result.push(RoomListDiff::Insert {
                    index,
                    item: room_to_summary_async(value).await,
                });
            }
            VectorDiff::Set { index, value } => {
                result.push(RoomListDiff::Update {
                    index,
                    item: room_to_summary_async(value).await,
                });
            }
            VectorDiff::Remove { index } => {
                result.push(RoomListDiff::Remove { index });
            }
            VectorDiff::Clear { .. } => {
                result.push(RoomListDiff::Reset { items: vec![] });
            }
            VectorDiff::PushFront { value } => {
                result.push(RoomListDiff::Insert {
                    index: 0,
                    item: room_to_summary_async(value).await,
                });
            }
            VectorDiff::PushBack { .. } => {
                // 无法获取确切位置，发送 Reset（需要重新获取所有房间）
                // 这里暂时跳过，因为 Sliding Sync 通常不会产生此 diff
                debug!("VectorDiff::PushBack received, skipping");
            }
            VectorDiff::PopFront => {
                result.push(RoomListDiff::Remove { index: 0 });
            }
            VectorDiff::PopBack => {
                debug!("VectorDiff::PopBack received, skipping");
            }
            VectorDiff::Truncate { .. } => {
                debug!("VectorDiff::Truncate received, sending empty reset");
                result.push(RoomListDiff::Reset { items: vec![] });
            }
        }
    }

    result
}

/// 将 RoomListItem 转换为 RoomSummary (异步版本)
/// 使用 display_name().await 强制计算房间名称
async fn room_to_summary_async(room: matrix_sdk_ui::room_list_service::RoomListItem) -> RoomSummary {
    let room_id = room.room_id().to_string();

    // 1. 首先尝试 room.name()（群房间的 m.room.name 事件）
    if let Some(name) = room.name() {
        if !name.is_empty() && !name.starts_with('!') {
            return build_room_summary(room, name);
        }
    }

    // 2. 尝试 canonical_alias（房间别名，如 #room:server）
    if let Some(alias) = room.canonical_alias() {
        let alias_str = alias.to_string();
        if !alias_str.is_empty() && !alias_str.starts_with('!') {
            return build_room_summary(room, alias_str);
        }
    }

    // 3. 尝试从 heroes 和 direct_targets 获取名称（DM 房间）
    let heroes_name = extract_name_from_heroes(&room);
    if !heroes_name.is_empty() && !heroes_name.starts_with('!') && heroes_name != "Unknown Room" {
        return build_room_summary(room, heroes_name);
    }

    // 4. 尝试 SDK 的 display_name（计算名称）
    let cached_name = room.cached_display_name();
    let sdk_name = if let Some(n) = cached_name {
        n.to_string()
    } else {
        match room.display_name().await {
            Ok(display_name) => display_name.to_string(),
            Err(_) => String::new(),
        }
    };

    // 检查 SDK 名称是否有效
    if !sdk_name.is_empty() && !sdk_name.starts_with('!') && sdk_name != "Empty Room" {
        return build_room_summary(room, sdk_name);
    }

    // 5. 尝试 alt_aliases
    if let Some(alias) = room.alt_aliases().first() {
        let alias_str = alias.to_string();
        if !alias_str.starts_with('!') {
            return build_room_summary(room, alias_str);
        }
    }

    // 6. 最后兜底：简化 room_id（去掉 ! 和 server 部分）
    let fallback = simplify_room_id(&room_id);
    build_room_summary(room, fallback)
}

/// 简化 room_id：去掉 ! 和 server 部分
fn simplify_room_id(room_id: &str) -> String {
    if room_id.starts_with('!') {
        // !roomid:server -> roomid
        room_id.split(':')
            .next()
            .unwrap_or(room_id)
            .trim_start_matches('!')
            .to_string()
    } else {
        room_id.to_string()
    }
}

/// 构建 RoomSummary（确保名称不以 ! 开头）
fn build_room_summary(room: matrix_sdk_ui::room_list_service::RoomListItem, name: String) -> RoomSummary {
    use matrix_sdk::EncryptionState;
    let encryption_state = room.encryption_state();
    let is_encrypted = matches!(encryption_state, EncryptionState::Encrypted);

    // 最终过滤：如果名称以 ! 开头，去掉 ! 和 :server 部分
    let final_name = if name.starts_with('!') {
        simplify_room_id(&name)
    } else {
        name
    };

    RoomSummary {
        room_id: room.room_id().to_string(),
        name: final_name,
        avatar_url: room.avatar_url().map(|u| u.to_string()),
        last_message: None,
        timestamp: room.new_latest_event_timestamp()
            .map(|ts| {
                let millis: i64 = ts.0.into();
                format_timestamp(millis)
            }),
        unread_count: room.num_unread_notifications() as u32,
        is_encrypted,
    }
}

/// 房间名称 fallback：当 display_name() 失败时使用
fn fallback_room_name(room: &matrix_sdk_ui::room_list_service::RoomListItem) -> String {
    // 尝试多种来源获取名称
    room.name()
        .or_else(|| room.canonical_alias().map(|a| a.to_string()))
        .or_else(|| {
            room.alt_aliases()
                .first()
                .map(|a| a.to_string())
        })
        .unwrap_or_else(|| {
            // 使用更友好的名称
            "Unknown Room".to_string()
        })
}

/// 从 heroes 提取房间名称（用于 DM 房间）
fn extract_name_from_heroes(room: &matrix_sdk_ui::room_list_service::RoomListItem) -> String {
    // 尝试从 heroes 获取名称
    let heroes = room.heroes();
    if !heroes.is_empty() {
        // 对于 DM 房间，heroes[0] 是对方用户
        let hero = &heroes[0];
        if let Some(display_name) = &hero.display_name {
            return display_name.clone();
        }
        // 如果 hero 没有 display_name，使用 user_id 的本地部分
        let user_id = hero.user_id.to_string();
        if user_id.starts_with('@') {
            return user_id.split(':').next().unwrap_or(&user_id)
                .trim_start_matches('@')
                .to_string();
        }
        return user_id;
    }

    // 尝试 direct_targets（DM 房间的对方用户）
    let targets = room.direct_targets();
    if !targets.is_empty() {
        let target_id = targets.iter().next().unwrap().to_string();
        if target_id.starts_with('@') {
            return target_id.split(':').next().unwrap_or(&target_id)
                .trim_start_matches('@')
                .to_string();
        }
        return target_id;
    }

    // 最后返回一个默认名称
    "Unknown Room".to_string()
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