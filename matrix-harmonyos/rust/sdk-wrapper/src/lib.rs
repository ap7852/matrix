//! SDK Wrapper - matrix-rust-sdk 封装层
//!
//! 提供业务逻辑实现，不包含 NAPI 相关代码

// 增加递归限制，解决 matrix-sdk 编译时的深度限制问题
// matrix-sdk 的 async 函数嵌套深度很高，需要较大的限制
#![recursion_limit = "4096"]

pub mod error;
pub mod client;
pub mod auth;
pub mod session;
pub mod room_list;
pub mod timeline;
pub mod encryption;
pub mod media;

/// 验证 ring 编译成功
pub fn verify_ring() -> [u8; 32] {
    use ring::digest;
    let hash = digest::digest(&digest::SHA256, b"Element X HarmonyOS");
    let mut result = [0u8; 32];
    result.copy_from_slice(hash.as_ref());
    result
}