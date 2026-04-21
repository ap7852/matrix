//! Account 模块 - 用户账户管理
//!
//! 提供个人资料修改、设备管理等功能

use serde::{Deserialize, Serialize};
use tracing::debug;

use crate::client::get_client;
use crate::error::{BridgeError, ErrorCode};

/// 用户资料
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserProfile {
    pub user_id: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
}

/// 设备信息
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceInfo {
    pub device_id: String,
    pub display_name: Option<String>,
    pub last_seen_ts: Option<String>,
    pub last_seen_ip: Option<String>,
    pub is_own: bool,
}

/// 获取当前用户资料
pub async fn get_profile() -> Result<UserProfile, BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let user_id = client.user_id()
        .map(|id| id.to_string())
        .unwrap_or_default();

    // 获取显示名称
    let display_name = client.account()
        .get_display_name()
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    // 获取头像 URL
    let avatar_url = client.account()
        .get_avatar_url()
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?
        .map(|u| u.to_string());

    debug!("Profile retrieved: display_name={:?}, avatar_url={:?}", display_name, avatar_url);

    Ok(UserProfile {
        user_id,
        display_name,
        avatar_url,
    })
}

/// 设置显示名称
pub async fn set_display_name(name: String) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    if name.is_empty() {
        return Err(BridgeError::new(ErrorCode::InvalidParameter, "Display name cannot be empty"));
    }

    debug!("Setting display name to: {}", name);

    // API 接受 Option<&str>
    client.account()
        .set_display_name(Some(&name))
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Display name set successfully");
    Ok(())
}

/// 设置头像 URL (需要先通过媒体上传获取 mxc:// URL)
pub async fn set_avatar_url(url: String) -> Result<(), BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    if !url.starts_with("mxc://") {
        return Err(BridgeError::new(ErrorCode::InvalidParameter, "Avatar URL must be mxc:// format"));
    }

    debug!("Setting avatar URL to: {}", url);

    // 直接从字符串创建 OwnedMxcUri
    let owned_uri = matrix_sdk::ruma::OwnedMxcUri::from(url);

    client.account()
        .set_avatar_url(Some(&owned_uri))
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    debug!("Avatar URL set successfully");
    Ok(())
}

/// 获取设备列表
/// 注意：matrix-sdk 0.16.0 的设备管理 API 需要通过 encryption 模块
pub async fn get_devices() -> Result<Vec<DeviceInfo>, BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let own_device_id = client.device_id()
        .map(|id| id.to_string())
        .unwrap_or_default();

    debug!("Getting devices, own device: {}", own_device_id);

    // 使用 encryption 模块获取设备信息
    let encryption = client.encryption();

    // 获取用户设备列表
    let user_devices = encryption
        .get_user_devices(client.user_id().unwrap())
        .await
        .map_err(|e| BridgeError::new(ErrorCode::NetworkError, e.to_string()))?;

    // devices() 返回 Iterator，直接 collect
    let result: Vec<DeviceInfo> = user_devices
        .devices()
        .map(|device| {
            let device_id = device.device_id().to_string();
            DeviceInfo {
                device_id: device_id.clone(),
                display_name: device.display_name().map(|n| n.to_string()),
                last_seen_ts: None, // matrix-sdk 0.16.0 的 Device 不提供 last_seen_ts
                last_seen_ip: None,
                is_own: device_id == own_device_id,
            }
        })
        .collect();

    debug!("Found {} devices", result.len());
    Ok(result)
}

/// 删除设备
/// 注意：需要先验证身份才能删除其他设备
pub async fn delete_device(_device_id: String) -> Result<(), BridgeError> {
    // matrix-sdk 0.16.0 的设备删除需要通过复杂的身份验证流程
    // 简化实现：暂时返回错误，提示用户需要验证身份
    Err(BridgeError::new(
        ErrorCode::NotImplemented,
        "Device deletion requires identity verification. Please use Element Web/Desktop to manage devices."
    ))
}