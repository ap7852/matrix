//! NAPI Timeline 模块
//!
//! 导出 Timeline 相关的 NAPI 函数供 ArkTS 调用

use napi_ohos::bindgen_prelude::*;
use napi_ohos::threadsafe_function::{ThreadsafeFunctionCallMode, ThreadsafeCallContext};
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 初始化房间 Timeline
///
/// 进入房间时调用，创建 Timeline 实例
#[napi]
pub async fn napi_init_timeline(room_id: String) -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::timeline::init_timeline(&room_id)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 订阅 Timeline 更新
///
/// 使用 ThreadsafeFunction 实现实时消息更新推送
#[napi]
pub fn napi_subscribe_timeline(
    room_id: String,
    callback: Function<'static>,
) -> Result<()> {
    tracing::info!("NAPI: subscribe_timeline called for room: {}", room_id);

    // 使用 build_threadsafe_function + build_callback，让 Rust 推断类型
    let tsfn = callback
        .build_threadsafe_function::<String>()
        .build_callback(|ctx: ThreadsafeCallContext<String>| Ok(ctx.value))?;

    // 启动订阅任务
    let runtime = get_runtime();
    runtime.spawn(async move {
        // 调用 sdk-wrapper 的订阅函数
        let result = sdk_wrapper::timeline::subscribe_timeline(&room_id, move |json| {
            // 通过 ThreadsafeFunction 推送更新到 ArkTS
            tsfn.call(json, ThreadsafeFunctionCallMode::NonBlocking);
        }).await;

        if let Err(e) = result {
            tracing::error!("Timeline subscribe error for room {}: {:?}", room_id, e);
        } else {
            tracing::info!("NAPI: Timeline subscribed successfully for room: {}", room_id);
        }
    });

    Ok(())
}

/// 发送文本消息
///
/// 发送文本消息到指定房间，支持可选的回复
#[napi]
pub async fn napi_send_text(
    room_id: String,
    text: String,
    reply_to: Option<String>,
) -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::timeline::send_text_message(&room_id, &text, reply_to.as_deref())
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 分页加载历史消息
///
/// 加载更早的消息，返回是否有更多消息可加载
#[napi]
pub async fn napi_paginate_backwards(room_id: String) -> Result<bool> {
    tracing::info!("NAPI: paginate_backwards called for room: {}", room_id);
    let result = get_runtime()
        .spawn(async move {
            let result = sdk_wrapper::timeline::paginate_backwards(&room_id)
                .await
                .map_err(|e| {
                    tracing::error!("Pagination failed: {}", e.to_json());
                    Error::from_reason(e.to_json())
                })?;
            tracing::info!("NAPI: Pagination result: more={}", result);
            Ok(result)
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?;
    result
}

/// 发送已读回执
///
/// 标记消息为已读
#[napi]
pub async fn napi_send_read_receipt(room_id: String, event_id: String) -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::timeline::send_read_receipt(&room_id, &event_id)
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}