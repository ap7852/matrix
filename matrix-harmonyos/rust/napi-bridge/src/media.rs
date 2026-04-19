//! NAPI Media 模块
//!
//! 导出图片上传下载的 NAPI 函数供 ArkTS 调用

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 下载图片并返回 Base64 编码数据
///
/// 支持 E2EE 加密图片自动解密
/// encrypted_file_json 是 JSON 序列化的 EncryptedFileData
#[napi]
pub async fn napi_download_image(
    mxc_url: String,
    encrypted_file_json: Option<String>,
) -> Result<String> {
    tracing::info!("NAPI: download_image called for: {}", mxc_url);

    // 解析加密文件数据
    let encrypted_file = encrypted_file_json.and_then(|json| {
        serde_json::from_str::<sdk_wrapper::timeline::EncryptedFileData>(&json)
            .map_err(|e| tracing::warn!("Failed to parse encrypted_file JSON: {}", e))
            .ok()
    });

    get_runtime()
        .spawn(async move {
            let result = sdk_wrapper::media::download_media(mxc_url, encrypted_file)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(result)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
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
    tracing::info!("NAPI: send_image called for room: {}, filename: {}", room_id, filename);

    get_runtime()
        .spawn(async move {
            let result = sdk_wrapper::media::upload_and_send_image(room_id, filename, mimetype, data_base64)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(result)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}