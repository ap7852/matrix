//! NAPI 房间列表模块
//!
//! 使用 ThreadsafeFunction 实现实时房间列表更新

use napi_ohos::bindgen_prelude::*;
use napi_ohos::threadsafe_function::{ThreadsafeFunctionCallMode, ThreadsafeCallContext};
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 初始化 RoomListService
///
/// 登录成功后调用
#[napi]
pub async fn napi_init_room_list_service() -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::room_list::init_room_list_service()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}

/// 启动房间列表同步
///
/// 使用 ThreadsafeFunction 实现实时更新推送
#[napi]
pub fn napi_subscribe_room_list(
    callback: Function<'static>,
) -> Result<()> {
    // 使用 build_threadsafe_function + build_callback，让 Rust 推断类型
    let tsfn = callback
        .build_threadsafe_function::<String>()
        .build_callback(|ctx: ThreadsafeCallContext<String>| Ok(ctx.value))?;

    // 启动同步任务
    let runtime = get_runtime();
    runtime.spawn(async move {
        // 调用 sdk-wrapper 的同步函数
        let result = sdk_wrapper::room_list::start_room_list_sync(move |json| {
            // 通过 ThreadsafeFunction 推送更新到 ArkTS
            tsfn.call(json, ThreadsafeFunctionCallMode::NonBlocking);
        }).await;

        if let Err(e) = result {
            tracing::error!("Room list sync error: {:?}", e);
        }
    });

    Ok(())
}

/// 停止房间列表同步
#[napi]
pub async fn napi_stop_room_list_sync() -> Result<()> {
    get_runtime()
        .spawn(async move {
            sdk_wrapper::room_list::stop_room_list_sync()
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;
            Ok(())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}