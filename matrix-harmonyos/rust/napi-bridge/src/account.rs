//! NAPI Account 模块
//!
//! 导出用户账户相关的 NAPI 函数供 ArkTS 调用

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 获取当前用户资料
#[napi]
pub async fn napi_get_profile() -> Result<String> {
    tracing::info!("NAPI: get_profile called");

    get_runtime()
        .spawn(async move {
            let profile = sdk_wrapper::account::get_profile()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;

            let json = serde_json::to_string(&profile)
                .map_err(|e| Error::from_reason(e.to_string()))?;

            tracing::info!("NAPI: get_profile returned: {}", json);
            Ok(json)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 设置显示名称
#[napi]
pub async fn napi_set_display_name(name: String) -> Result<()> {
    tracing::info!("NAPI: set_display_name called: {}", name);

    get_runtime()
        .spawn(async move {
            sdk_wrapper::account::set_display_name(name)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 设置头像 URL
#[napi]
pub async fn napi_set_avatar_url(url: String) -> Result<()> {
    tracing::info!("NAPI: set_avatar_url called: {}", url);

    get_runtime()
        .spawn(async move {
            sdk_wrapper::account::set_avatar_url(url)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 获取设备列表
#[napi]
pub async fn napi_get_devices() -> Result<String> {
    tracing::info!("NAPI: get_devices called");

    get_runtime()
        .spawn(async move {
            let devices = sdk_wrapper::account::get_devices()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;

            let json = serde_json::to_string(&devices)
                .map_err(|e| Error::from_reason(e.to_string()))?;

            tracing::info!("NAPI: get_devices returned {} bytes", json.len());
            Ok(json)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 删除设备
#[napi]
pub async fn napi_delete_device(device_id: String) -> Result<()> {
    tracing::info!("NAPI: delete_device called: {}", device_id);

    get_runtime()
        .spawn(async move {
            sdk_wrapper::account::delete_device(device_id)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}