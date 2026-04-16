# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Element X HarmonyOS is a Matrix protocol instant messaging client for HarmonyOS native platform. It is a 1:1 feature replica of Element X Android 25.10.0, using a three-layer architecture:

- **UI Layer**: ArkUI (ArkTS) with Compound design system
- **Bridge Layer**: ohos-rs NAPI bridge (Rust-ArkTS FFI)
- **SDK Layer**: matrix-rust-sdk 0.16.0 (protocol logic, E2EE, storage)

Target platform: HarmonyOS API 22 (HarmonyOS 6.0.2).

## Build Commands

This is a HarmonyOS project using Hvigor build system. Run commands from `matrix-harmonyos/` directory:

```bash
# Build the HAP package
hvigorw assembleHap --mode module -p module=entry@default

# Clean build
hvigorw clean

# Build for release
hvigorw assembleHap --mode module -p module=entry@default -p product=default
```

In DevEco Studio, use the standard build/run buttons or:
- Build > Make Hap(s) to build
- Run > Run 'entry' to deploy

## Testing

Uses `@ohos/hypium` test framework. Test files should be placed in `entry/src/ohosTest/ets/`.

```bash
# Run tests via DevEco Studio or hvigorw
hvigorw testHap --mode module -p module=entry@ohosTest
```

## Project Structure

```
matrix-harmonyos/
├── AppScope/               # App-level configuration (app.json5)
├── entry/                  # Main entry module
│   ├── src/main/
│   │   ├── ets/            # ArkTS source code
│   │   │   ├── entryability/  # EntryAbility (app lifecycle)
│   │   │   ├── pages/         # UI pages
│   │   │   ├── components/    # UI components (to be created)
│   │   │   ├── services/      # NAPI service wrappers (to be created)
│   │   │   └── models/        # Data models (to be created)
│   │   ├── cpp/            # Native C++ code (will become Rust via ohos-rs)
│   │   └── module.json5    # Module configuration
│   ├── build-profile.json5 # Module build config
│   └── hvigorfile.ts       # Module Hvigor config
├── oh-package.json5        # OHPM dependencies
├── build-profile.json5     # Project build config
└── hvigorfile.ts           # Root Hvigor config
```

## Key Architecture Decisions

### NAPI Bridge Pattern
All Rust-to-ArkTS communication follows this pattern:

1. **Async NAPI functions**: Return `Promise`, execute on tokio runtime
2. **ThreadSafeFunction**: Push events from Rust to ArkTS main thread
3. **JSON serialization**: All cross-layer data uses JSON (serde_json)
4. **Error handling**: Structured `BridgeError` with error codes (see docs)

### SQLite Concurrency
All SQLite operations must go through a single Mutex-protected tokio task to avoid lock contention crashes (matrix-sdk-sqlite Issue #5160).

### Security Storage
- Access tokens: Store in HarmonyOS Asset Store Kit (TEE-protected)
- SQLite passphrase: Store in Asset Store Kit
- Never store sensitive data in Preferences or plain files

## Native Code Development

Currently uses basic C++ NAPI. Will transition to ohos-rs (Rust) for matrix-rust-sdk integration:

1. Install Rust with target `aarch64-unknown-linux-ohos`
2. Configure `.cargo/config.toml` with OHOS NDK paths
3. Use `ring` crate requires explicit `TARGET_CC` and `TARGET_AR` env vars

### Critical Cargo Version Locking
Always use exact version syntax for matrix-rust-sdk:
```toml
matrix-sdk = { version = "=0.16.0", features = ["sqlite", "rustls-tls", "e2e-encryption"] }
```

Never use `^0.16.0` or `0.16` - loose constraints cause build instability.

## API 22 Specific Features

- `onVisibilityChange`: Track message visibility for read receipts
- `RichEditor.maxLength`: Input length limits
- `napi_create_strong_reference`: NAPI callback lifecycle management
- HybridStack debugging: Rust + ArkTS mixed call stack

## Code Style

Follow DevEco Studio linting rules in `code-linter.json5`. Key rules:
- TypeScript ESLint recommended
- Performance linting enabled
- Security rules for crypto operations (AES, RSA, etc.)

## Logging

Use HarmonyOS `hilog` with domain codes:
- `0x0001`: Authentication
- `0x0002`: Room list
- `0x0003`: Timeline
- `0x0004`: Encryption
- `0x0005`: NAPI bridge
- `0x0006`: Storage
- `0x0007`: Notifications

## Performance Requirements

- Cold start: ≤ 2000ms
- Room list scroll: ≥ 60fps (500 rooms)
- Timeline first load: ≤ 800ms (5000 messages)
- Message send delay (Local Echo): ≤ 200ms
- Memory: ≤ 300MB

Use `LazyForEach` + `@Reusable` for all list rendering. Never use `ForEach` for large lists.

## Documentation References

See `Element X HarmonyOS 技术文档 v1.0.0.md` and `项目需求文档.md` for:
- Complete NAPI function reference (Appendix A)
- Error code mapping (Appendix B)
- Boilerplate templates (Appendix C)
- Feature requirements with MoSCoW priority