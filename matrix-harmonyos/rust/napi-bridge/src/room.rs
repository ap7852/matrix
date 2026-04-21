//! NAPI Room 模块
//!
//! 导出 Room 相关的 NAPI 函数供 ArkTS 调用

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 获取房间详情（包括实时名称）
/// 返回 JSON 字符串
#[napi]
pub async fn napi_get_room_details(room_id: String) -> Result<String> {
    tracing::info!("NAPI: get_room_details called for: {}", room_id);

    get_runtime()
        .spawn(async move {
            let details = sdk_wrapper::room::get_room_details(&room_id)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;

            let json = serde_json::to_string(&details)
                .map_err(|e| Error::from_reason(e.to_string()))?;

            tracing::info!("NAPI: get_room_details returned: {}", json);
            Ok(json)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 获取房间成员列表
/// 返回 JSON 字符串
#[napi]
pub async fn napi_get_room_members(room_id: String) -> Result<String> {
    tracing::info!("NAPI: get_room_members called for: {}", room_id);

    get_runtime()
        .spawn(async move {
            let members = sdk_wrapper::room::get_room_members(&room_id)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;

            // 将整个数组转换为单个 JSON 字符串
            let json = serde_json::to_string(&members)
                .map_err(|e| Error::from_reason(e.to_string()))?;

            tracing::info!("NAPI: get_room_members returned {} bytes", json.len());
            Ok(json)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}