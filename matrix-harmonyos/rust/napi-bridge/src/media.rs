//! NAPI Media 模块
//!
//! 导出图片上传下载的 NAPI 函数供 ArkTS 调用

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;
use std::sync::atomic::{AtomicU64, Ordering};

/// 下载计数器 (用于调试)
static DOWNLOAD_COUNTER: AtomicU64 = AtomicU64::new(0);

/// 下载图片并返回 Base64 编码数据
///
/// 支持 E2EE 加密图片自动解密
/// encrypted_file_json 是 JSON 序列化的 EncryptedFileData
#[napi]
pub async fn napi_download_image(
    mxc_url: String,
    encrypted_file_json: Option<String>,
) -> Result<String> {
    let download_id = DOWNLOAD_COUNTER.fetch_add(1, Ordering::Relaxed);
    tracing::info!("NAPI[{download_id}]: download_image START: mxc_url={mxc_url}, encrypted={}",
        encrypted_file_json.is_some());

    // 解析加密文件数据
    let encrypted_file = encrypted_file_json.and_then(|json| {
        tracing::info!("NAPI[{download_id}]: parsing encrypted_file JSON");
        serde_json::from_str::<sdk_wrapper::timeline::EncryptedFileData>(&json)
            .map_err(|e| tracing::warn!("NAPI[{download_id}]: Failed to parse encrypted_file JSON: {}", e))
            .ok()
    });

    tracing::info!("NAPI[{download_id}]: spawning download task on tokio");

    let result = get_runtime()
        .spawn(async move {
            tracing::info!("NAPI[{download_id}]: inside tokio spawn, calling download_media");
            let result = sdk_wrapper::media::download_media(mxc_url.clone(), encrypted_file)
                .await
                .map_err(|e| {
                    tracing::error!("NAPI[{download_id}]: download_media failed: {}", e.message);
                    Error::from_reason(e.to_json())
                })?;
            tracing::info!("NAPI[{download_id}]: download_media SUCCESS, base64_len={}", result.len());
            Ok(result)
        })
        .await
        .map_err(|e| {
            tracing::error!("NAPI[{download_id}]: tokio spawn error: {}", e);
            Error::from_reason(e.to_string())
        })?;

    tracing::info!("NAPI[{download_id}]: download_image COMPLETE");
    result
}

/// 上传图片并发送到房间
///
/// 返回发送成功的 event_id
#[napi]
pub async fn napi_send_image(
    room_id: String,
    filename: String,
    mimetype: String,
    data_base64: String,
) -> Result<String> {
    tracing::info!("NAPI: send_image START for room: {}, filename: {}, size: {} bytes",
        room_id, filename, data_base64.len());

    get_runtime()
        .spawn(async move {
            tracing::info!("NAPI: inside tokio spawn, calling upload_and_send_image");
            let result = sdk_wrapper::media::upload_and_send_image(room_id, filename, mimetype, data_base64)
                .await
                .map_err(|e| {
                    tracing::error!("NAPI: upload_and_send_image failed: {}", e.message);
                    Error::from_reason(e.to_json())
                })?;
            tracing::info!("NAPI: upload_and_send_image SUCCESS, event_id={}", result);
            Ok(result)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}