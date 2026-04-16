//! SDK Wrapper placeholder (待 Phase 2 实现)

pub mod error;

/// 验证 ring 编译成功
pub fn verify_ring() -> [u8; 32] {
    use ring::digest;
    let hash = digest::digest(&digest::SHA256, b"Element X HarmonyOS");
    let mut result = [0u8; 32];
    result.copy_from_slice(hash.as_ref());
    result
}