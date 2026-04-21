//! Media 模块 - 图片上传下载实现
//!
//! 使用 matrix-sdk 的 Media API 处理图片

use base64::{Engine as _, engine::general_purpose::STANDARD};
use matrix_sdk::ruma::{OwnedMxcUri, OwnedRoomId};
use matrix_sdk::ruma::events::room::{MediaSource, EncryptedFile, EncryptedFileInit, JsonWebKey, JsonWebKeyInit};
use matrix_sdk::ruma::serde::Base64;
use matrix_sdk::attachment::{AttachmentConfig, AttachmentInfo, BaseImageInfo};
use tracing::{debug, info, warn, error};
use std::time::Duration;

use crate::client::get_client;
use crate::error::{BridgeError, ErrorCode};
use crate::timeline::EncryptedFileData;

/// 下载超时时间 (30秒)
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(30);

/// 下载媒体文件并返回 Base64 编码数据
///
/// 支持 E2EE 加密图片自动解密
pub async fn download_media(
    mxc_url: String,
    encrypted_file: Option<EncryptedFileData>,
) -> Result<String, BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    info!("download_media START: mxc_url={}", mxc_url);

    // 解析 MXC URI
    info!("download_media: parsing MXC URI");
    let mxc_uri: OwnedMxcUri = OwnedMxcUri::try_from(mxc_url.as_str())
        .map_err(|e| {
            warn!("download_media: MXC URI parse failed: {}", e);
            BridgeError::new(ErrorCode::InvalidParameter, format!("Invalid MXC URI: {}", e))
        })?;

    info!("download_media: building media request");

    // 构建媒体请求参数
    info!("download_media: encrypted_file={:?}", encrypted_file.is_some());
    let media_request = if let Some(encrypted) = encrypted_file {
        // 加密媒体 - 构建 EncryptedFile
        info!("download_media: building encrypted file request");
        // 解析 Base64 参数
        let key = Base64::parse(&encrypted.key)
            .map_err(|e| {
                warn!("download_media: key parse failed: {}", e);
                BridgeError::new(ErrorCode::InvalidParameter, format!("Invalid key: {}", e))
            })?;

        let iv = Base64::parse(&encrypted.iv)
            .map_err(|e| {
                warn!("download_media: iv parse failed: {}", e);
                BridgeError::new(ErrorCode::InvalidParameter, format!("Invalid iv: {}", e))
            })?;

        // 构建 hashes
        let hashes = if let Some(hash) = encrypted.hashes {
            let mut map = std::collections::BTreeMap::new();
            map.insert(
                "sha256".to_string(),
                Base64::parse(&hash)
                    .map_err(|e| {
                        warn!("download_media: hash parse failed: {}", e);
                        BridgeError::new(ErrorCode::InvalidParameter, format!("Invalid hash: {}", e))
                    })?,
            );
            map
        } else {
            std::collections::BTreeMap::new()
        };

        // 使用 JsonWebKeyInit 构造器
        let jwk = JsonWebKey::from(JsonWebKeyInit {
            kty: "oct".to_owned(),
            key_ops: vec!["decrypt".to_owned()],
            alg: "A256CTR".to_owned(),
            k: key,
            ext: true,
        });

        let encrypted_file = EncryptedFile::from(EncryptedFileInit {
            url: mxc_uri.clone(),
            key: jwk,
            iv,
            hashes,
            v: "v2".to_owned(),
        });

        info!("download_media: encrypted file structure built");
        matrix_sdk::media::MediaRequestParameters {
            source: MediaSource::Encrypted(Box::new(encrypted_file)),
            format: matrix_sdk::media::MediaFormat::File,
        }
    } else {
        // 普通媒体
        info!("download_media: building plain media request");
        matrix_sdk::media::MediaRequestParameters {
            source: MediaSource::Plain(mxc_uri),
            format: matrix_sdk::media::MediaFormat::File,
        }
    };

    // 下载媒体 - 使用超时包装
    info!("download_media: calling get_media_content");
    let media = client.media();
    let download_result = tokio::time::timeout(DOWNLOAD_TIMEOUT, media.get_media_content(&media_request, true)).await;

    info!("download_media: get_media_content returned");

    let data = download_result
        .map_err(|_| {
            error!("download_media: TIMEOUT after {}s", DOWNLOAD_TIMEOUT.as_secs());
            BridgeError::new(ErrorCode::MediaDownloadFailed, "Download timeout")
        })?
        .map_err(|e| {
            error!("download_media: download failed: {}", e);
            BridgeError::new(ErrorCode::MediaDownloadFailed, e.to_string())
        })?;

    // 转换为 Base64
    info!("download_media: encoding to base64");
    let base64_data = STANDARD.encode(&data);
    info!("download_media SUCCESS: size={} bytes, base64_len={}", data.len(), base64_data.len());

    Ok(base64_data)
}

/// 上传图片并发送到房间
///
/// 返回发送成功的 event_id
pub async fn upload_and_send_image(
    room_id: String,
    filename: String,
    mimetype: String,
    data_base64: String,
) -> Result<String, BridgeError> {
    let client = get_client()
        .ok_or_else(|| BridgeError::new(ErrorCode::SessionExpired, "No client session"))?;

    let room_id_obj = OwnedRoomId::try_from(room_id.as_str())
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, e.to_string()))?;

    let room = client.get_room(&room_id_obj)
        .ok_or_else(|| BridgeError::new(ErrorCode::RoomNotFound, "Room not found"))?;

    debug!("Uploading image to room: {}, filename: {}", room_id, filename);

    // 解码 Base64
    let data = STANDARD.decode(&data_base64)
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, format!("Invalid base64: {}", e)))?;

    debug!("Image decoded, size: {} bytes", data.len());

    // 构建 MIME 类型
    let mime_type: mime::Mime = mimetype.parse()
        .map_err(|e| BridgeError::new(ErrorCode::InvalidParameter, format!("Invalid mimetype: {}", e)))?;

    // 使用 Room::send_attachment 发送图片
    // E2EE 加密由 matrix-sdk 自动处理
    // 基本的附件信息
    let attachment_info = AttachmentInfo::Image(BaseImageInfo::default());

    let config = AttachmentConfig::new()
        .info(attachment_info);

    let response = room.send_attachment(&filename, &mime_type, data.into(), config).await
        .map_err(|e| {
            debug!("Image send failed: {}", e);
            BridgeError::new(ErrorCode::NetworkError, e.to_string())
        })?;

    // 从响应中提取 event_id
    let event_id = response.event_id.to_string();
    debug!("Image sent, event_id: {}", event_id);

    Ok(event_id)
}