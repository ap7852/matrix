//! Timeline 模块 - 消息时间线实现
//!
//! 使用 matrix-sdk-ui 的 Timeline 进行消息管理

use std::collections::HashMap;
use std::sync::{Arc, LazyLock};

use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId};
use matrix_sdk::ruma::events::room::message::{RoomMessageEventContent, RoomMessageEventContentWithoutRelation};
use matrix_sdk::room::edit::EditedContent;
use matrix_sdk_ui::eyeball_im::VectorDiff;
use matrix_sdk_ui::timeline::{
    EncryptedMessage, EventSendState, EventTimelineItem, MsgLikeKind, RoomExt,
    TimelineDetails, TimelineItem, TimelineItemContent, TimelineEventItemId, Timeline,
};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use tracing::debug;

use crate::client::get_client;
use crate::error::{BridgeError, ErrorCode};

/// 全局 Timeline 存储
/// 每个房间一个 Timeline 实例，避免重复创建
static TIMELINES: LazyLock<RwLock<HashMap<String, Arc<Timeline>>>> = LazyLock::new(|| RwLock::new(HashMap::new()));

/// 时间线消息数据
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelineMessage {
    pub event_id: Option<String>,
    pub sender_id: String,
    pub sender_name: String,
    pub sender_avatar_url: Option<String>,
    pub content: MessageContent,
    pub timestamp: String,
    pub is_own: bool,
    pub send_state: SendState,
    pub in_reply_to: Option<ReplyPreview>,
}

/// 回复引用预览
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReplyPreview {
    pub event_id: String,
    pub sender_id: String,
    pub sender_name: Option<String>,
    pub content_body: String,
}

/// 加密文件元数据 (用于 E2EE 图片)
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EncryptedFileData {
    pub key: String,
    pub iv: String,
    pub hashes: Option<String>,
}

/// 消息内容类型
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum MessageContent {
    Text { body: String },
    Image {
        mxc_url: String,
        encrypted_file: Option<EncryptedFileData>,
        body: String,
        filename: Option<String>,
        width: Option<u64>,
        height: Option<u64>,
        mimetype: Option<String>,
        thumbnail_url: Option<String>,
    },
    Video {
        mxc_url: String,
        encrypted_file: Option<EncryptedFileData>,
        body: String,
        filename: Option<String>,
        width: Option<u64>,
        height: Option<u64>,
        duration: Option<u64>,
        mimetype: Option<String>,
        thumbnail_url: Option<String>,
    },
    File {
        mxc_url: String,
        encrypted_file: Option<EncryptedFileData>,
        body: String,
        filename: Option<String>,
        mimetype: Option<String>,
        size: Option<u64>,
    },
    Audio {
        mxc_url: String,
        encrypted_file: Option<EncryptedFileData>,
        body: String,
        filename: Option<String>,
        duration: Option<u64>,
        mimetype: Option<String>,
    },
    UnableToDecrypt { reason: String },
    Redacted,
    Unsupported,
}

/// 发送状态
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SendState {
    Sending,
    Sent,
    Failed,
}

/// 时间线更新消息
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum TimelineUpdate {
    Reset { items: Vec<TimelineMessage> },
    Append { items: Vec<TimelineMessage> },
    Insert { index: usize, item: TimelineMessage },
    Update { index: usize, item: TimelineMessage },
    Remove { index: usize },
}

/// 初始化房间 Timeline
///
/// 创建并存储 Timeline 实例，后续操作使用同一实例
pub async fn init_timeline(room_id: &str) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let room = client.get_room(&room_id)
        .ok_or_else(|| BridgeError::new(ErrorCode::RoomNotFound, "Room not found"))?;

    debug!("Creating Timeline for room: {}", room_id);

    let timeline = room.timeline().await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    // 存储 Timeline 实例
    let mut timelines = TIMELINES.write().await;
    timelines.insert(room_id.to_string(), Arc::new(timeline));

    debug!("Timeline created and stored for room: {}", room_id);

    Ok(())
}

/// 获取已存储的 Timeline 实例
async fn get_timeline(room_id: &str) -> Result<Arc<Timeline>, BridgeError> {
    let timelines = TIMELINES.read().await;
    timelines.get(room_id)
        .cloned()
        .ok_or_else(|| BridgeError::new(ErrorCode::TimelineNotInitialized, "Timeline not initialized, call init_timeline first"))
}

/// 订阅 Timeline 更新
///
/// 使用已存储的 Timeline 实例订阅更新
/// 初始化时会自动加载初始批次的历史消息
pub async fn subscribe_timeline(
    room_id: &str,
    update_callback: impl Fn(String) + Send + 'static,
) -> Result<(), BridgeError> {
    debug!("Subscribing to Timeline for room: {}", room_id);

    // 使用已存储的 Timeline
    let timeline = get_timeline(room_id).await?;

    let (items, stream) = timeline.subscribe().await;

    // 发送初始消息列表
    let initial: Vec<TimelineMessage> = items
        .iter()
        .filter_map(|item| item.as_event().map(map_event_item))
        .collect();

    let initial_len = initial.len();
    debug!("Initial timeline items: {}", initial_len);

    if !initial.is_empty() {
        let update = TimelineUpdate::Reset { items: initial };
        let json = serde_json::to_string(&update).unwrap_or_default();
        debug!("Sending initial timeline reset");
        update_callback(json);
    }

    // 如果初始消息太少，自动加载更多
    if initial_len < 20 {
        debug!("Auto-paginating backwards for room: {}", room_id);
        let more = timeline.paginate_backwards(20).await
            .map_err(|e| {
                debug!("Auto-pagination failed: {}", e);
                BridgeError::new(ErrorCode::NetworkError, e.to_string())
            })?;
        debug!("Auto-pagination complete: more={}", more);
    }

    // 监听更新流 - paginate 产生的新消息会通过 stream 推送
    let room_id_str = room_id.to_string();
    let callback = update_callback;
    tokio::spawn(async move {
        use matrix_sdk::stream::StreamExt;
        let mut stream = Box::pin(stream);

        debug!("Timeline stream started for room: {}", room_id_str);

        while let Some(diffs) = stream.next().await {
            debug!("Received {} diffs for room: {}", diffs.len(), room_id_str);
            let converted: Vec<TimelineUpdate> = diffs
                .into_iter()
                .flat_map(|diff| convert_timeline_diff(diff))
                .collect();

            for update in converted {
                let json = serde_json::to_string(&update).unwrap_or_default();
                debug!("Sending timeline update via callback");
                callback(json);
            }
        }

        debug!("Timeline stream ended for room: {}", room_id_str);
    });

    Ok(())
}

/// 发送文本消息
///
/// 通过房间发送消息，E2EE 自动加密
pub async fn send_text_message(
    room_id: &str,
    text: &str,
    _reply_to: Option<&str>,
) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let room = client.get_room(&room_id)
        .ok_or_else(|| BridgeError::new(ErrorCode::RoomNotFound, "Room not found"))?;

    debug!("Sending text message to room: {}", room_id);

    let content = RoomMessageEventContent::text_plain(text);

    // E2EE 加密在 room.send() 中自动完成
    room.send(content).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Text message sent");
    Ok(())
}

/// 分页加载历史消息
///
/// 使用已存储的 Timeline 实例分页加载
pub async fn paginate_backwards(room_id: &str) -> Result<bool, BridgeError> {
    debug!("Paginating backwards for room: {}", room_id);

    // 使用已存储的 Timeline
    let timeline = get_timeline(room_id).await?;

    let more_messages = timeline
        .paginate_backwards(20)
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Pagination complete, more messages available: {}", more_messages);
    Ok(more_messages)
}

/// 发送已读回执
pub async fn send_read_receipt(room_id: &str, event_id: &str) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let room = client.get_room(&room_id)
        .ok_or_else(|| BridgeError::new(ErrorCode::RoomNotFound, "Room not found"))?;

    let event_id = OwnedEventId::try_from(event_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    debug!("Sending read receipt for event: {}", event_id);

    room.send_single_receipt(
        matrix_sdk::ruma::api::client::receipt::create_receipt::v3::ReceiptType::Read,
        matrix_sdk::ruma::events::receipt::ReceiptThread::Main,
        event_id,
    ).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Read receipt sent");
    Ok(())
}

/// 编辑消息
pub async fn edit_message(
    room_id: &str,
    event_id: &str,
    new_text: &str,
) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let event_id = OwnedEventId::try_from(event_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    debug!("Editing message {} in room {}", event_id, room_id);

    // 使用 Timeline 编辑
    let timeline = get_timeline(room_id.as_str()).await?;
    let item_id = TimelineEventItemId::EventId(event_id);
    let content = EditedContent::RoomMessage(RoomMessageEventContentWithoutRelation::text_plain(new_text));
    timeline.edit(&item_id, content).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Message edited");
    Ok(())
}

/// 删除消息 (Redact)
pub async fn redact_message(
    room_id: &str,
    event_id: &str,
    reason: Option<&str>,
) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let event_id = OwnedEventId::try_from(event_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    debug!("Redacting message {} in room {}", event_id, room_id);

    // 使用 Timeline 删除
    let timeline = get_timeline(room_id.as_str()).await?;
    let item_id = TimelineEventItemId::EventId(event_id);
    timeline.redact(&item_id, reason).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Message redacted");
    Ok(())
}

/// 回复消息
pub async fn reply_to_message(
    room_id: &str,
    event_id: &str,
    text: &str,
) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let event_id = OwnedEventId::try_from(event_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    debug!("Replying to message {} in room {}", event_id, room_id);

    // 使用 Timeline 回复
    let timeline = get_timeline(room_id.as_str()).await?;

    // 构造回复内容
    let content = RoomMessageEventContentWithoutRelation::text_plain(text);
    timeline.send_reply(content, event_id).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Reply sent");
    Ok(())
}

/// 添加/移除表情反应
pub async fn toggle_reaction(
    room_id: &str,
    event_id: &str,
    key: &str,
) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let event_id = OwnedEventId::try_from(event_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    debug!("Toggling reaction {} on message {} in room {}", key, event_id, room_id);

    // 使用 Timeline 反应
    let timeline = get_timeline(room_id.as_str()).await?;
    let item_id = TimelineEventItemId::EventId(event_id);
    timeline.toggle_reaction(&item_id, key).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Reaction toggled");
    Ok(())
}

/// 将 EventTimelineItem 转换为 TimelineMessage
fn map_event_item(event_item: &EventTimelineItem) -> TimelineMessage {
    let timestamp = event_item.timestamp();
    let timestamp_str = format_timestamp(timestamp);

    // 获取发送者信息
    let sender_id = event_item.sender().to_string();
    let (sender_name, sender_avatar_url) = match event_item.sender_profile() {
        TimelineDetails::Ready(profile) => {
            let name = profile.display_name.clone().unwrap_or_else(|| sender_id.clone());
            let avatar = profile.avatar_url.clone().map(|u| u.to_string());
            (name, avatar)
        }
        _ => (sender_id.clone(), None),
    };

    // 解析消息内容
    let content = parse_content(event_item.content());

    // 解析发送状态
    let send_state = match event_item.send_state() {
        Some(state) => {
            match state {
                EventSendState::NotSentYet { .. } => SendState::Sending,
                EventSendState::Sent { .. } => SendState::Sent,
                EventSendState::SendingFailed { .. } => SendState::Failed,
            }
        }
        None => SendState::Sent,
    };

    // 提取回复引用信息
    let in_reply_to = extract_reply_preview(event_item);

    TimelineMessage {
        event_id: event_item.event_id().map(|id| id.to_string()),
        sender_id,
        sender_name,
        sender_avatar_url,
        content,
        timestamp: timestamp_str,
        is_own: event_item.is_own(),
        send_state,
        in_reply_to,
    }
}

/// 提取回复引用预览
fn extract_reply_preview(event_item: &EventTimelineItem) -> Option<ReplyPreview> {
    // 从 content 中获取 in_reply_to
    match event_item.content() {
        TimelineItemContent::MsgLike(msg_like) => {
            // 检查是否有回复关系 - in_reply_to 是字段
            if let Some(reply) = msg_like.in_reply_to.as_ref() {
                let event_id = reply.event_id.to_string();

                // 从 event 字段获取详细信息
                match &reply.event {
                    TimelineDetails::Ready(embedded_event) => {
                        let sender_id = embedded_event.sender.to_string();
                        let sender_name = match &embedded_event.sender_profile {
                            TimelineDetails::Ready(profile) => profile.display_name.clone(),
                            _ => None,
                        };

                        // 获取内容预览 - content 是字段
                        let content_body = match &embedded_event.content {
                            TimelineItemContent::MsgLike(inner_msg) => {
                                match &inner_msg.kind {
                                    MsgLikeKind::Message(message) => {
                                        match message.msgtype() {
                                            matrix_sdk::ruma::events::room::message::MessageType::Text(t) => t.body.clone(),
                                            matrix_sdk::ruma::events::room::message::MessageType::Image(i) => format!("📷 {}", i.body),
                                            matrix_sdk::ruma::events::room::message::MessageType::Video(v) => format!("🎬 {}", v.body),
                                            matrix_sdk::ruma::events::room::message::MessageType::File(f) => format!("📎 {}", f.body),
                                            matrix_sdk::ruma::events::room::message::MessageType::Audio(a) => format!("🎵 {}", a.body),
                                            _ => "消息".to_string(),
                                        }
                                    }
                                    _ => "消息".to_string(),
                                }
                            }
                            _ => "消息".to_string(),
                        };

                        Some(ReplyPreview {
                            event_id,
                            sender_id,
                            sender_name,
                            content_body,
                        })
                    }
                    // 如果 event 未准备好，使用基本信息
                    _ => {
                        Some(ReplyPreview {
                            event_id,
                            sender_id: "未知".to_string(),
                            sender_name: None,
                            content_body: "消息".to_string(),
                        })
                    }
                }
            } else {
                None
            }
        }
        _ => None,
    }
}

/// 解析 TimelineItemContent
fn parse_content(content: &TimelineItemContent) -> MessageContent {
    match content {
        TimelineItemContent::MsgLike(msg_like) => {
            match &msg_like.kind {
                MsgLikeKind::Message(message) => {
                    use matrix_sdk::ruma::events::room::message::MessageType;
                    match message.msgtype() {
                        MessageType::Text(text) => {
                            MessageContent::Text { body: text.body.clone() }
                        }
                        MessageType::Emote(emote) => {
                            // emote 格式化为 *用户名 内容
                            MessageContent::Text { body: format!("* {}", emote.body) }
                        }
                        MessageType::Notice(notice) => {
                            MessageContent::Text { body: notice.body.clone() }
                        }
                        MessageType::Image(image) => {
                            // 从 source 获取 URL 和加密信息
                            use matrix_sdk::ruma::events::room::MediaSource;
                            let (mxc_url, encrypted_file) = match &image.source {
                                MediaSource::Plain(uri) => (uri.to_string(), None),
                                MediaSource::Encrypted(encrypted) => {
                                    (
                                        encrypted.url.to_string(),
                                        Some(EncryptedFileData {
                                            key: encrypted.key.k.to_string(),
                                            iv: encrypted.iv.to_string(),
                                            hashes: encrypted.hashes.get("sha256")
                                                .map(|h| h.to_string()),
                                        }),
                                    )
                                }
                            };

                            // 获取缩略图 URL
                            let thumbnail_url = image.info.as_ref().and_then(|i| {
                                match &i.thumbnail_source {
                                    Some(MediaSource::Plain(uri)) => Some(uri.to_string()),
                                    Some(MediaSource::Encrypted(e)) => Some(e.url.to_string()),
                                    None => None,
                                }
                            });

                            MessageContent::Image {
                                mxc_url,
                                encrypted_file,
                                body: image.body.clone(),
                                filename: image.filename.clone(),
                                width: image.info.as_ref().and_then(|i| i.width.map(|w| u64::from(w))),
                                height: image.info.as_ref().and_then(|i| i.height.map(|h| u64::from(h))),
                                mimetype: image.info.as_ref().and_then(|i| i.mimetype.clone()),
                                thumbnail_url,
                            }
                        }
                        MessageType::Video(video) => {
                            use matrix_sdk::ruma::events::room::MediaSource;
                            let (mxc_url, encrypted_file) = match &video.source {
                                MediaSource::Plain(uri) => (uri.to_string(), None),
                                MediaSource::Encrypted(encrypted) => {
                                    (
                                        encrypted.url.to_string(),
                                        Some(EncryptedFileData {
                                            key: encrypted.key.k.to_string(),
                                            iv: encrypted.iv.to_string(),
                                            hashes: encrypted.hashes.get("sha256")
                                                .map(|h| h.to_string()),
                                        }),
                                    )
                                }
                            };

                            let thumbnail_url = video.info.as_ref().and_then(|i| {
                                match &i.thumbnail_source {
                                    Some(MediaSource::Plain(uri)) => Some(uri.to_string()),
                                    Some(MediaSource::Encrypted(e)) => Some(e.url.to_string()),
                                    None => None,
                                }
                            });

                            MessageContent::Video {
                                mxc_url,
                                encrypted_file,
                                body: video.body.clone(),
                                filename: video.filename.clone(),
                                width: video.info.as_ref().and_then(|i| i.width.map(|w| u64::from(w))),
                                height: video.info.as_ref().and_then(|i| i.height.map(|h| u64::from(h))),
                                duration: video.info.as_ref().and_then(|i| i.duration.map(|d| d.as_millis() as u64)),
                                mimetype: video.info.as_ref().and_then(|i| i.mimetype.clone()),
                                thumbnail_url,
                            }
                        }
                        MessageType::File(file) => {
                            use matrix_sdk::ruma::events::room::MediaSource;
                            let (mxc_url, encrypted_file) = match &file.source {
                                MediaSource::Plain(uri) => (uri.to_string(), None),
                                MediaSource::Encrypted(encrypted) => {
                                    (
                                        encrypted.url.to_string(),
                                        Some(EncryptedFileData {
                                            key: encrypted.key.k.to_string(),
                                            iv: encrypted.iv.to_string(),
                                            hashes: encrypted.hashes.get("sha256")
                                                .map(|h| h.to_string()),
                                        }),
                                    )
                                }
                            };

                            MessageContent::File {
                                mxc_url,
                                encrypted_file,
                                body: file.body.clone(),
                                filename: file.filename.clone(),
                                mimetype: file.info.as_ref().and_then(|i| i.mimetype.clone()),
                                size: file.info.as_ref().and_then(|i| i.size.map(|s| u64::from(s))),
                            }
                        }
                        MessageType::Audio(audio) => {
                            use matrix_sdk::ruma::events::room::MediaSource;
                            let (mxc_url, encrypted_file) = match &audio.source {
                                MediaSource::Plain(uri) => (uri.to_string(), None),
                                MediaSource::Encrypted(encrypted) => {
                                    (
                                        encrypted.url.to_string(),
                                        Some(EncryptedFileData {
                                            key: encrypted.key.k.to_string(),
                                            iv: encrypted.iv.to_string(),
                                            hashes: encrypted.hashes.get("sha256")
                                                .map(|h| h.to_string()),
                                        }),
                                    )
                                }
                            };

                            MessageContent::Audio {
                                mxc_url,
                                encrypted_file,
                                body: audio.body.clone(),
                                filename: audio.filename.clone(),
                                duration: audio.info.as_ref().and_then(|i| i.duration.map(|d| d.as_millis() as u64)),
                                mimetype: audio.info.as_ref().and_then(|i| i.mimetype.clone()),
                            }
                        }
                        MessageType::Location(loc) => {
                            MessageContent::Text { body: format!("[位置] {}", loc.body) }
                        }
                        _ => {
                            // 对于其他已知类型，尝试获取 body
                            MessageContent::Text { body: "未知消息类型".to_string() }
                        }
                    }
                }
                MsgLikeKind::Redacted => MessageContent::Redacted,
                MsgLikeKind::UnableToDecrypt(encrypted) => {
                    // 从 EncryptedMessage 获取原因
                    let reason = match encrypted {
                        EncryptedMessage::MegolmV1AesSha2 { cause, .. } => {
                            format!("{:?}", cause)
                        }
                        EncryptedMessage::OlmV1Curve25519AesSha2 { .. } => {
                            "OlmV1".to_string()
                        }
                        EncryptedMessage::Unknown => {
                            "Unknown algorithm".to_string()
                        }
                    };
                    MessageContent::UnableToDecrypt { reason }
                }
                MsgLikeKind::Sticker(_sticker) => {
                    MessageContent::Text { body: "[贴纸]".to_string() }
                }
                _ => MessageContent::Unsupported,
            }
        }
        TimelineItemContent::ProfileChange(profile) => {
            MessageContent::Text { body: format!("{} 更新了资料", profile.user_id()) }
        }
        TimelineItemContent::MembershipChange(membership) => {
            MessageContent::Text { body: format!("成员变更: {}", membership.user_id()) }
        }
        _ => MessageContent::Unsupported,
    }
}

/// 格式化时间戳
fn format_timestamp(ts: matrix_sdk::ruma::MilliSecondsSinceUnixEpoch) -> String {
    use chrono::{DateTime, Local, TimeZone};

    let millis: i64 = ts.0.into();
    let datetime: DateTime<Local> = Local.timestamp_millis_opt(millis).single().unwrap_or_else(|| Local::now());

    let now = Local::now();
    let diff = now.signed_duration_since(datetime);

    if diff.num_minutes() < 1 {
        "刚刚".to_string()
    } else if diff.num_hours() < 1 {
        format!("{}分钟前", diff.num_minutes())
    } else if diff.num_days() == 0 {
        datetime.format("%H:%M").to_string()
    } else if diff.num_days() < 7 {
        datetime.format("%a %H:%M").to_string()
    } else {
        datetime.format("%m/%d %H:%M").to_string()
    }
}

/// 将 VectorDiff<Arc<TimelineItem>> 转换为 TimelineUpdate
fn convert_timeline_diff(diff: VectorDiff<Arc<TimelineItem>>) -> Vec<TimelineUpdate> {
    match diff {
        VectorDiff::Reset { values } => {
            let items: Vec<TimelineMessage> = values
                .iter()
                .filter_map(|item| item.as_event().map(map_event_item))
                .collect();
            vec![TimelineUpdate::Reset { items }]
        }
        VectorDiff::Append { values } => {
            let items: Vec<TimelineMessage> = values
                .iter()
                .filter_map(|item| item.as_event().map(map_event_item))
                .collect();
            vec![TimelineUpdate::Append { items }]
        }
        VectorDiff::Insert { index, value } => {
            if let Some(event_item) = value.as_event() {
                vec![TimelineUpdate::Insert {
                    index,
                    item: map_event_item(event_item),
                }]
            } else {
                vec![]
            }
        }
        VectorDiff::Set { index, value } => {
            if let Some(event_item) = value.as_event() {
                vec![TimelineUpdate::Update {
                    index,
                    item: map_event_item(event_item),
                }]
            } else {
                vec![]
            }
        }
        VectorDiff::Remove { index } => {
            vec![TimelineUpdate::Remove { index }]
        }
        VectorDiff::Clear { .. } => {
            vec![TimelineUpdate::Reset { items: vec![] }]
        }
        VectorDiff::PushFront { value } => {
            if let Some(event_item) = value.as_event() {
                vec![TimelineUpdate::Insert {
                    index: 0,
                    item: map_event_item(event_item),
                }]
            } else {
                vec![]
            }
        }
        VectorDiff::PushBack { value } => {
            if let Some(event_item) = value.as_event() {
                vec![TimelineUpdate::Append { items: vec![map_event_item(event_item)] }]
            } else {
                vec![]
            }
        }
        VectorDiff::PopFront => {
            vec![TimelineUpdate::Remove { index: 0 }]
        }
        VectorDiff::PopBack => {
            vec![TimelineUpdate::Reset { items: vec![] }]
        }
        VectorDiff::Truncate { .. } => {
            vec![TimelineUpdate::Reset { items: vec![] }]
        }
    }
}

/// 清理所有 Timeline 实例
///
/// 退出登录时调用，释放资源
pub async fn clear_all_timelines() {
    let mut timelines = TIMELINES.write().await;
    timelines.clear();
    debug!("All timelines cleared");
}