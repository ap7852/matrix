//! NAPI 房间列表模块
//!
//! Phase 0: 简化版，使用异步函数返回初始房间列表

use napi_ohos::bindgen_prelude::*;
use napi_derive_ohos::napi;
use crate::runtime::get_runtime;

/// 启动房间列表同步（Phase 0 简化版）
///
/// 返回空数组表示同步启动成功
/// Phase 1 将使用 ThreadSafeFunction 实现实时更新
#[napi]
pub async fn napi_start_room_list_sync() -> Result<String> {
    get_runtime()
        .spawn(async move {
            // 启动同步（使用占位回调）
            sdk_wrapper::room_list::start_room_list_sync(|_| {})
                .await
                .map_err(|e| Error::from_reason(e.to_json()))?;

            // 返回空房间列表表示启动成功
            Ok("[]".to_string())
        })
        .await
        .map_err(|e| Error::from_reason(e.to_string()))?
}