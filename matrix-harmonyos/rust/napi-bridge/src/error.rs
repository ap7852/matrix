//! NAPI Bridge 错误处理
//!
//! 将 sdk-wrapper 的 BridgeError 转换为 napi::Error

use napi_ohos::bindgen_prelude::Error;
use sdk_wrapper::error::BridgeError;

/// 将 BridgeError 转换为 napi::Error 的辅助函数
pub fn bridge_error_to_napi(e: BridgeError) -> Error {
    // 错误消息为 JSON 格式，便于 ArkTS 解析
    Error::from_reason(e.to_json())
}

/// 从 napi::Error 尝试解析 BridgeError
pub fn try_parse_bridge_error(error: &Error) -> Option<BridgeError> {
    let message = error.to_string();
    serde_json::from_str(&message).ok()
}