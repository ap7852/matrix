//! SDK Wrapper 错误类型

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// 统一错误码枚举
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Error)]
pub enum ErrorCode {
    #[error("网络错误")]
    NetworkError = 1001,
    #[error("服务器错误")]
    ServerError = 1002,
    #[error("参数无效")]
    InvalidParameter = 1003,
    #[error("认证失败")]
    AuthenticationFailed = 2001,
    #[error("会话已过期")]
    SessionExpired = 2002,
    #[error("用户已停用")]
    UserDeactivated = 2003,
    #[error("房间不存在")]
    RoomNotFound = 3001,
    #[error("未加入房间")]
    RoomNotJoined = 3002,
    #[error("时间线未初始化")]
    TimelineNotInitialized = 3003,
    #[error("解密失败")]
    DecryptionFailed = 4001,
    #[error("验证失败")]
    VerificationFailed = 4002,
    #[error("备份恢复失败")]
    BackupRestoreFailed = 4003,
    #[error("存储错误")]
    StorageError = 5001,
    #[error("存储锁超时")]
    StorageLockTimeout = 5002,
    #[error("媒体下载失败")]
    MediaDownloadFailed = 6001,
    #[error("文件过大")]
    MediaTooLarge = 6002,
    #[error("未知错误")]
    UnknownError = 9999,
}

/// 结构化错误
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeError {
    pub code: ErrorCode,
    pub message: String,
}

impl BridgeError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }

    pub fn unknown(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::UnknownError, message)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            format!("{{\"code\":{},\"message\":\"serialization error\"}}", ErrorCode::UnknownError as i32)
        })
    }
}

impl From<anyhow::Error> for BridgeError {
    fn from(e: anyhow::Error) -> Self {
        BridgeError::unknown(e.to_string())
    }
}