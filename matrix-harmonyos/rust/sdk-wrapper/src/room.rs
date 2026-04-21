//! Room 模块 - 房间成员等功能

use serde::{Deserialize, Serialize};
use tracing::debug;

use crate::client::get_client;
use crate::error::{BridgeError, ErrorCode};

use matrix_sdk::ruma::OwnedRoomId;
use matrix_sdk::RoomMemberships;

/// 房间成员数据
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RoomMember {
    pub user_id: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
    pub membership: String,
    pub is_own: bool,
}

/// 房间详情数据
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RoomDetails {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub is_encrypted: bool,
    pub is_direct: bool,
}

/// 获取房间详情（包括实时名称）
pub async fn get_room_details(room_id: &str) -> Result<RoomDetails, BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let room = client.get_room(&room_id)
        .ok_or_else(|| BridgeError::new(ErrorCode::RoomNotFound, "Room not found"))?;

    debug!("Getting details for room: {}", room_id);

    // 获取房间名称 - 使用 display_name 计算
    let name = room.display_name().await
        .map(|n| n.to_string())
        .unwrap_or_else(|_| {
            // Fallback: 尝试各种来源
            room.name()
                .or_else(|| room.canonical_alias().map(|a| a.to_string()))
                .unwrap_or_else(|| simplify_room_id(&room_id.to_string()))
        });

    // 检查加密状态 - Room 使用 encryption_settings
    let is_encrypted = room.encryption_settings().is_some();

    // 检查是否是 DM 房间 - Room 使用 is_direct() 方法 (async)
    let is_direct = room.is_direct().await
        .unwrap_or(false);

    debug!("Room details: name={}, is_direct={}", name, is_direct);

    Ok(RoomDetails {
        room_id: room_id.to_string(),
        name,
        avatar_url: room.avatar_url().map(|u| u.to_string()),
        is_encrypted,
        is_direct,
    })
}

/// 简化 room_id：去掉 ! 和 server 部分
fn simplify_room_id(room_id: &str) -> String {
    if room_id.starts_with('!') {
        room_id.split(':')
            .next()
            .unwrap_or(room_id)
            .trim_start_matches('!')
            .to_string()
    } else {
        room_id.to_string()
    }
}

/// 获取房间成员列表
pub async fn get_room_members(room_id: &str) -> Result<Vec<RoomMember>, BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id = OwnedRoomId::try_from(room_id)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let room = client.get_room(&room_id)
        .ok_or_else(|| BridgeError::new(ErrorCode::RoomNotFound, "Room not found"))?;

    debug!("Getting members for room: {}", room_id);

    // 获取成员列表 (只获取已加入的成员)
    let members = room.members(RoomMemberships::JOIN).await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    let own_user_id = client.user_id()
        .map(|id| id.to_string())
        .unwrap_or_default();

    // 转换为 RoomMember
    let result: Vec<RoomMember> = members
        .into_iter()
        .map(|member| {
            let user_id = member.user_id().to_string();
            RoomMember {
                user_id: user_id.clone(),
                display_name: member.display_name().map(|n| n.to_string()),
                avatar_url: member.avatar_url().map(|u| u.to_string()),
                membership: member.membership().to_string(),
                is_own: user_id == own_user_id,
            }
        })
        .collect();

    debug!("Got {} members for room {}", result.len(), room_id);
    Ok(result)
}