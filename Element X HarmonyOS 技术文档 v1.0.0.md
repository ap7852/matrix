# Element X HarmonyOS 技术文档 v1.0.0

**文档版本**：v1.0.0 | **日期**：2026-04-16 | **目标平台**：HarmonyOS API 22 (HarmonyOS 6.0.2)

---

## **第一章 项目概述**

Element X HarmonyOS 是基于 Matrix 协议的鸿蒙原生即时通讯客户端，以 Element X Android 25.10.0 为 1:1 功能复刻标的。项目采用三层异构架构：ArkUI 负责原生 UI 渲染，ohos-rs 提供 Rust-ArkTS 跨语言 NAPI 桥接，matrix-rust-sdk 0.16.0 承载全部协议逻辑与端到端加密。整个项目由单人开发者驱动，辅以 Claude Code 进行代码生成与重构。

项目的核心技术挑战在于将一个深度依赖 JVM 生态（Kotlin + Jetpack Compose）的 Android 客户端，移植到以 ArkTS + ArkUI 为主语言的鸿蒙原生环境中，同时维持与 matrix-rust-sdk Rust 核心的高效集成。这一过程要求在跨语言 FFI、异步运行时调度、端到端加密密钥生命周期管理三个维度上做出精确的架构决策。

---

## **第二章 系统架构**

### **2.1 整体分层架构**

```
┌──────────────────────────────────────────────────────────┐
│                    Layer 1: UI 层                         │
│           ArkUI (ArkTS) + Compound 设计系统               │
│   LazyForEach / @Reusable / Navigation / @ohos/web       │
├──────────────────────────────────────────────────────────┤
│                  Layer 2: 状态管理层                       │
│         ArkTS State (AppStorage / @State / @Link)        │
│              TaskPool / Worker Thread 调度                │
├──────────────────────────────────────────────────────────┤
│               Layer 3: NAPI 桥接层                        │
│          ohos-rs (napi-rs fork) + tokio runtime          │
│   ThreadSafeFunction / Promise / API 22 强引用接口         │
├──────────────────────────────────────────────────────────┤
│                Layer 4: SDK 核心层                        │
│           matrix-rust-sdk 0.16.0 (Rust)                  │
│  RoomListService / Timeline / matrix_sdk_crypto          │
│         vodozemac / matrix-sdk-sqlite / rustls           │
└──────────────────────────────────────────────────────────┘
```

各层之间的数据流向遵循单向原则：UI 层通过 ArkTS 调用 NAPI 导出函数触发 Rust 侧逻辑，Rust 侧通过 `ThreadSafeFunction` 将事件异步推送回 ArkTS 主线程，状态变更后由 ArkUI 响应式框架驱动 UI 重新渲染。任何层均不得跨层直接访问，严禁 UI 层持有 Rust 原始指针或 ArkTS 层接触明文密钥材料。

### **2.2 进程与线程模型**

鸿蒙应用运行在单进程多线程模型下，ArkTS 主线程承载 UI 渲染与事件处理，严禁执行任何阻塞操作。tokio 异步运行时在独立的 Worker 线程中初始化，与主线程完全隔离，通过 `ThreadSafeFunction` 进行跨线程回调。

```
主线程 (Main Thread)
  ├── ArkUI 渲染引擎
  ├── ArkTS 事件循环
  └── NAPI 函数调用入口 (同步返回 Promise)

Worker 线程 (tokio Runtime)
  ├── matrix-rust-sdk 异步任务
  ├── RoomListService (Sliding Sync 长连接)
  ├── Timeline 消息处理
  └── SQLite I/O (单线程化保护)

TaskPool (可选)
  └── 媒体文件处理 (图片解码/视频转码)
```

所有 SQLite 数据库操作必须通过单一 `Mutex<()>` 保护的 tokio 任务串行执行，这是规避 matrix-sdk-sqlite Issue #5160 锁竞争崩溃的强制约束，不得以任何理由绕过。

### **2.3 数据流架构**

消息接收的完整数据流路径如下：

```
Matrix 服务器 (Synapse/Conduit)
    │  HTTPS/WSS (rustls TLS 1.2+)
    ▼
matrix-rust-sdk SlidingSync (MSC4186)
    │  tokio async stream
    ▼
RoomListService / Timeline (Rust)
    │  事件处理 / E2EE 解密 (vodozemac)
    ▼
ThreadSafeFunction 回调
    │  JSON 序列化 (serde_json)
    ▼
ArkTS 事件处理器
    │  @State / AppStorage 状态更新
    ▼
ArkUI 响应式重渲染
    │  LazyForEach diff 更新
    ▼
用户界面
```

消息发送的路径方向相反，从 ArkTS 调用 NAPI 函数，经 tokio 任务队列，由 `Room::send()` 完成 E2EE 加密后上传至服务器，同时通过 Local Echo 机制立即在本地时间线插入乐观更新条目，确保发送延迟感知不超过 200ms。

---

## **第三章 核心依赖与工具链**

### **3.1 依赖版本清单**

| 依赖                     | 版本                     | 用途                   | 风险等级 |
| :----------------------- | :----------------------- | :--------------------- | :------: |
| matrix-rust-sdk          | **0.16.0 (严格锁定)**    | 协议核心 / E2EE / 存储 |   🔴 高   |
| ohos-rs                  | 最新开发版 (MSRV 1.88.0) | NAPI 桥接层            |   🟠 中   |
| vodozemac                | 随 matrix-rust-sdk 传递  | Olm/Megolm 加密        |   🟢 低   |
| matrix-sdk-sqlite        | 随 matrix-rust-sdk 传递  | 本地持久化存储         |   🟠 中   |
| tokio                    | 随 ohos-rs 传递          | 异步运行时             |   🟢 低   |
| rustls                   | 0.23.x                   | TLS 实现               |   🟢 低   |
| rustls-platform-verifier | 最新版                   | 证书验证               |   🟢 低   |
| serde / serde_json       | 1.x                      | 跨层数据序列化         |   🟢 低   |
| ring                     | 0.17.x                   | 密码学原语 (间接依赖)  |   🔴 高   |

`ring` 的风险评级为高，原因是其在 `aarch64-unknown-linux-ohos` 目标上需要手动配置编译环境变量，是目前已知的最高优先级编译风险点，必须在 P0 阶段最先验证。

### **3.2 Cargo 工作区配置**

项目采用 Cargo Workspace 结构，将 NAPI 桥接层与业务逻辑层分离：

```toml
# Cargo.toml (workspace root)
[workspace]
members = [
    "rust/napi-bridge",   # ohos-rs NAPI 导出层
    "rust/sdk-wrapper",   # matrix-rust-sdk 封装层
]
resolver = "2"

[workspace.dependencies]
matrix-sdk = { version = "=0.16.0", features = [
    "sqlite",
    "rustls-tls",
    "e2e-encryption",
] }
matrix-sdk-ui = { version = "=0.16.0" }
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

**强制约束**：`matrix-sdk` 版本必须使用 `=0.16.0` 精确锁定语法，禁止使用 `^0.16.0` 或 `0.16` 宽松约束，以防止因 crates.io 新版本发布导致的隐式升级破坏构建稳定性（参考 0.15.0 被整体 yanked 的历史教训）。

### **3.3 交叉编译工具链配置**

目标平台为 `aarch64-unknown-linux-ohos`，需在 `.cargo/config.toml` 中显式配置鸿蒙 NDK 工具链路径：

```toml
# .cargo/config.toml
[target.aarch64-unknown-linux-ohos]
linker = "aarch64-linux-ohos-clang"
ar = "aarch64-linux-ohos-ar"

[env]
TARGET_CC = "/path/to/ohos-sdk/native/llvm/bin/aarch64-linux-ohos-clang"
TARGET_AR = "/path/to/ohos-sdk/native/llvm/bin/llvm-ar"
OHOS_NDK_HOME = "/path/to/ohos-sdk"
```

`TARGET_CC` 和 `TARGET_AR` 的配置是 `ring` crate 成功编译的必要条件，缺失任一变量将导致 `ring` 在链接阶段报 `undefined reference` 错误（参见 [ring Issue #2122](https://github.com/briansmith/ring/issues/2122)）。实际路径需替换为本机 DevEco Studio 安装的 HarmonyOS SDK 路径。

---

## **第四章 NAPI 桥接层设计**

### **4.1 桥接层职责边界**

NAPI 桥接层（`rust/napi-bridge`）是整个架构中最关键的边界层，其职责严格限定为：

- 将 ArkTS 的函数调用转换为 Rust 异步任务并提交至 tokio 运行时
- 将 Rust 侧的异步事件通过 `ThreadSafeFunction` 回调到 ArkTS 主线程
- 完成 Rust 类型与 ArkTS 类型之间的 JSON 序列化/反序列化
- 管理 NAPI 对象的生命周期（使用 API 22 强引用接口）

桥接层**不得**包含任何业务逻辑，所有协议处理、加密操作、状态管理均由 `rust/sdk-wrapper` 层负责。

### **4.2 tokio 运行时初始化**

tokio 运行时必须在 NAPI 模块加载时在独立 Worker 线程中初始化，且整个应用生命周期内只初始化一次：

```rust
// rust/napi-bridge/src/runtime.rs
use std::sync::OnceLock;
use tokio::runtime::Runtime;

static TOKIO_RUNTIME: OnceLock<Runtime> = OnceLock::new();

pub fn get_runtime() -> &'static Runtime {
    TOKIO_RUNTIME.get_or_init(|| {
        Runtime::new().expect("Failed to create tokio runtime")
    })
}

/// NAPI 模块初始化入口，由 ohos-rs 在模块加载时自动调用
#[napi]
pub fn init_runtime() {
    let _ = get_runtime(); // 触发 OnceLock 初始化
}
```

### **4.3 异步函数导出模式**

所有耗时操作（网络请求、数据库读写、加密运算）必须导出为返回 `Promise` 的异步 NAPI 函数，禁止在 NAPI 调用中执行同步阻塞：

```rust
// rust/napi-bridge/src/auth.rs
use napi_derive::napi;
use crate::runtime::get_runtime;
use crate::sdk_wrapper::client::login_with_password;

#[napi]
pub async fn napi_login_password(
    homeserver: String,
    username: String,
    password: String,
) -> napi::Result<String> {  // 返回 JSON 序列化的 LoginResult
    get_runtime()
        .spawn(async move {
            login_with_password(&homeserver, &username, &password)
                .await
                .map_err(|e| napi::Error::from_reason(e.to_string()))
        })
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?
}
```

对应的 ArkTS 调用方式：

```typescript
// entry/src/main/ets/services/AuthService.ets
import { napiLogin } from 'libentry.so';

async function loginWithPassword(
    homeserver: string,
    username: string,
    password: string
): Promise<LoginResult> {
    const json = await napiLogin(homeserver, username, password);
    return JSON.parse(json) as LoginResult;
}
```

### **4.4 事件推送（ThreadSafeFunction）**

对于持续推送的事件流（如房间列表更新、新消息到达），使用 `ThreadSafeFunction` 建立从 Rust 到 ArkTS 的回调通道：

```rust
// rust/napi-bridge/src/room_list.rs
use napi::{threadsafe_function::{ThreadsafeFunction, ThreadSafeCallContext}, JsFunction};
use napi_derive::napi;

#[napi]
pub fn napi_subscribe_room_list(
    callback: JsFunction,
) -> napi::Result<()> {
    // 使用 API 22 强引用接口创建 ThreadsafeFunction
    // 防止 ArkTS GC 在 Rust 持有回调期间提前回收 JsFunction
    let tsfn: ThreadsafeFunction<String> = callback
        .create_threadsafe_function(0, |ctx: ThreadSafeCallContext<String>| {
            Ok(vec![ctx.env.create_string(&ctx.value)?])
        })?;

    get_runtime().spawn(async move {
        let mut service = RoomListService::new().await?;
        let mut stream = service.entries().await;
        
        while let Some(update) = stream.next().await {
            let json = serde_json::to_string(&update)
                .map_err(|e| napi::Error::from_reason(e.to_string()))?;
            // 将更新推送到 ArkTS 主线程
            tsfn.call(Ok(json), ThreadsafeFunctionCallMode::NonBlocking);
        }
        Ok(())
    });
    Ok(())
}
```

**API 22 强引用约束**：在 `ThreadsafeFunction` 持有 `JsFunction` 的整个生命周期内，必须通过 API 22 新增的 `napi_create_strong_reference` 接口维持对该 ArkTS 对象的强引用，防止 GC 提前回收导致野指针崩溃。ohos-rs 框架在 `ThreadsafeFunction` 的实现中已默认利用此接口，开发者无需手动调用，但必须确保使用的 ohos-rs 版本不低于 MSRV 1.88.0。

### **4.5 错误处理规范**

Rust 层所有错误必须转换为包含结构化信息的 `napi::Error`，禁止直接 `unwrap()` 或 `expect()` 导致进程崩溃：

```rust
// rust/napi-bridge/src/error.rs

/// 统一错误码枚举，与 ArkTS 侧 ErrorCode 枚举一一对应
#[derive(Debug, serde::Serialize)]
pub enum BridgeErrorCode {
    NetworkError,
    AuthenticationFailed,
    DecryptionFailed,
    StorageError,
    UnknownError,
}

#[derive(Debug, serde::Serialize)]
pub struct BridgeError {
    pub code: BridgeErrorCode,
    pub message: String,
}

impl From<matrix_sdk::Error> for BridgeError {
    fn from(e: matrix_sdk::Error) -> Self {
        // 根据错误类型映射到对应错误码
        // ...
    }
}
```

---

## **第五章 matrix-rust-sdk 集成**

### **5.1 Client 初始化**

`Client` 是 matrix-rust-sdk 的核心入口，必须在 tokio 运行时内异步初始化，并在整个应用生命周期内保持单例：

```rust
// rust/sdk-wrapper/src/client.rs
use matrix_sdk::{
    Client, config::StoreConfig,
    matrix_auth::MatrixSession,
};
use matrix_sdk_sqlite::SqliteCryptoStore;

pub async fn build_client(homeserver_url: &str, data_dir: &Path) -> Result<Client> {
    // SQLite 存储路径位于应用沙箱目录
    let db_path = data_dir.join("matrix.db");
    
    Client::builder()
        .homeserver_url(homeserver_url)
        // 强制使用 rustls，禁止 native-tls
        .with_encryption_settings(EncryptionSettings {
            auto_enable_backups: true,
            ..Default::default()
        })
        .sqlite_store(&db_path, Some(passphrase))  // 启用 StoreCipher 加密
        .build()
        .await
}
```

`passphrase` 必须从鸿蒙 `Asset Store Kit` 读取，禁止硬编码或存储于 `Preferences`。

### **5.2 认证模块**

#### **5.2.1 密码登录（Legacy Auth）**

```rust
// rust/sdk-wrapper/src/auth.rs
use matrix_sdk::matrix_auth::MatrixAuth;

pub async fn login_with_password(
    homeserver: &str,
    username: &str,
    password: &str,
) -> Result<SessionData> {
    let client = build_client(homeserver, &get_data_dir()).await?;
    
    client
        .matrix_auth()
        .login_username(username, password)
        .initial_device_display_name("Element X HarmonyOS")
        .await?;
    
    // 持久化 session 到 Asset Store Kit
    let session = client.session().ok_or(Error::NoSession)?;
    persist_session(&session).await?;
    
    Ok(session.into())
}
```

#### **5.2.2 OAuth/OIDC 登录（MSC3861）**

注意：0.16.0 中 `Oidc` 已完全重命名为 `OAuth`，模块路径为 `authentication::oauth`，原有 `authentication::oidc` 路径已被移除：

```rust
// rust/sdk-wrapper/src/oauth.rs
use matrix_sdk::authentication::oauth::OAuth;

pub async fn start_oauth_login(client: &Client) -> Result<OAuthLoginData> {
    let oauth = client.oauth();
    
    // 生成授权 URL，通过 Deep Link 回调
    let login_url = oauth
        .login(redirect_uri, None)
        .build()
        .await?;
    
    Ok(OAuthLoginData {
        authorization_url: login_url.to_string(),
    })
}

pub async fn complete_oauth_login(
    client: &Client,
    callback_url: &str,
) -> Result<()> {
    client
        .oauth()
        .finish_login(Url::parse(callback_url)?)
        .await?;
    Ok(())
}
```

### **5.3 RoomListService**

`RoomListService` 是房间列表的核心驱动，基于 MSC4186 Native Sliding Sync 协议实现增量同步。注意：MSC3575 代理 Sliding Sync 已于 2025 年 1 月 17 日起被 matrix.org 移除，所有服务器必须原生支持 MSC4186：

```rust
// rust/sdk-wrapper/src/room_list.rs
use matrix_sdk_ui::room_list_service::{RoomListService, SyncIndicator};

pub async fn start_room_list_sync(
    client: &Client,
    update_tx: ThreadsafeFunction<String>,
) -> Result<()> {
    let room_list_service = RoomListService::new(client.clone()).await?;
    
    // 获取房间列表条目流
    let (entries, stream) = room_list_service
        .all_rooms()
        .await?
        .entries_with_dynamic_adapters(50, client.roominfo_update_receiver())
        .await;
    
    // 监听增量更新
    tokio::spawn(async move {
        pin_mut!(stream);
        while let Some(diffs) = stream.next().await {
            let update = RoomListUpdate::from_diffs(diffs);
            let json = serde_json::to_string(&update)?;
            update_tx.call(Ok(json), ThreadsafeFunctionCallMode::NonBlocking);
        }
    });
    
    // 启动同步
    room_list_service.sync().await?;
    Ok(())
}
```

### **5.4 Timeline 模块**

时间线通过 `matrix_sdk_ui::timeline::Timeline` 管理，提供统一的消息条目抽象：

```rust
// rust/sdk-wrapper/src/timeline.rs
use matrix_sdk_ui::timeline::{Timeline, TimelineItemContent};

pub async fn load_timeline(
    room: &Room,
    event_tx: ThreadsafeFunction<String>,
) -> Result<Arc<Timeline>> {
    let timeline = room
        .timeline_builder()
        .with_focus(TimelineFocus::Live)
        .build()
        .await?;
    
    // 订阅时间线更新
    let (items, stream) = timeline.subscribe().await;
    
    tokio::spawn(async move {
        pin_mut!(stream);
        while let Some(diffs) = stream.next().await {
            let update = TimelineUpdate::from_diffs(&diffs);
            let json = serde_json::to_string(&update)?;
            event_tx.call(Ok(json), ThreadsafeFunctionCallMode::NonBlocking);
        }
    });
    
    Ok(timeline)
}

/// 向上分页加载历史消息
pub async fn paginate_backwards(timeline: &Timeline) -> Result<bool> {
    timeline.paginate_backwards(PaginationOptions::until_num_items(20, 50)).await
}
```

### **5.5 消息发送**

```rust
// rust/sdk-wrapper/src/send.rs
use matrix_sdk::room::Room;
use ruma::events::room::message::RoomMessageEventContent;

pub async fn send_text_message(
    room: &Room,
    text: &str,
    reply_to: Option<&str>,  // 被回复消息的 EventId
) -> Result<()> {
    let content = if let Some(event_id) = reply_to {
        // 构造回复消息
        let replied_to = room.event(event_id.try_into()?).await?;
        RoomMessageEventContent::text_plain(text)
            .make_reply_to(&replied_to, ForwardThread::Yes, AddMentions::No)
    } else {
        RoomMessageEventContent::text_plain(text)
    };
    
    // room.send() 在加密房间中自动触发 E2EE 加密
    room.send(content).await?;
    Ok(())
}
```

---

## **第六章 ArkUI 层实现规范**

### **6.1 项目目录结构**

```
entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets          # UIAbility 入口，初始化 NAPI 运行时
├── pages/
│   ├── LoginPage.ets              # 登录页面
│   ├── RoomListPage.ets           # 房间列表主页
│   └── TimelinePage.ets           # 消息时间线页面
├── components/
│   ├── room/
│   │   ├── RoomListItem.ets       # 房间列表条目组件 (@Reusable)
│   │   └── RoomAvatar.ets         # 房间头像组件
│   ├── timeline/
│   │   ├── MessageBubble.ets      # 消息气泡基础组件 (@Reusable)
│   │   ├── TextMessage.ets        # 文本消息渲染
│   │   ├── ImageMessage.ets       # 图片消息渲染
│   │   └── DateDivider.ets        # 日期分割线
│   └── composer/
│       └── MessageComposer.ets    # 消息输入框
├── services/
│   ├── AuthService.ets            # 认证服务 (NAPI 调用封装)
│   ├── RoomListService.ets        # 房间列表服务
│   └── TimelineService.ets        # 时间线服务
├── models/
│   ├── RoomModel.ets              # 房间数据模型
│   ├── MessageModel.ets           # 消息数据模型
│   └── UserModel.ets              # 用户数据模型
└── utils/
    ├── NapiLoader.ets             # NAPI 模块加载与初始化
    └── DateFormatter.ets          # 时间格式化工具
```

### **6.2 房间列表高性能渲染**

房间列表必须使用 `LazyForEach` + `@Reusable` 组合实现虚拟化渲染，禁止使用 `ForEach` 渲染大量条目：

```typescript
// components/room/RoomListItem.ets
@Reusable
@Component
struct RoomListItem {
    @State item: RoomSummary = {} as RoomSummary;
    
    // @Reusable 组件复用时的状态重置
    aboutToReuse(params: Record<string, ESObject>): void {
        this.item = params['item'] as RoomSummary;
    }
    
    build() {
        Row() {
            RoomAvatar({ name: this.item.name, avatarUrl: this.item.avatarUrl })
            Column() {
                Text(this.item.name).fontSize(16).fontWeight(FontWeight.Medium)
                Text(this.item.lastMessage).fontSize(14).opacity(0.6).maxLines(1)
            }
            .layoutWeight(1)
            .margin({ left: 12 })
            
            Column() {
                Text(this.item.timestamp).fontSize(12).opacity(0.4)
                if (this.item.unreadCount > 0) {
                    Badge({ count: this.item.unreadCount, style: {} })
                }
            }
        }
        .height(72)
        .padding({ left: 16, right: 16 })
    }
}
```

```typescript
// pages/RoomListPage.ets
class RoomDataSource implements IDataSource {
    private rooms: RoomSummary[] = [];
    private listeners: DataChangeListener[] = [];
    
    totalCount(): number { return this.rooms.length; }
    getData(index: number): RoomSummary { return this.rooms[index]; }
    
    applyDiffs(diffs: RoomListDiff[]): void {
        // 应用增量更新，避免全量重渲染
        for (const diff of diffs) {
            if (diff.type === 'Insert') {
                this.rooms.splice(diff.index, 0, diff.item);
                this.notifyDataAdd(diff.index);
            } else if (diff.type === 'Remove') {
                this.rooms.splice(diff.index, 1);
                this.notifyDataDelete(diff.index);
            } else if (diff.type === 'Update') {
                this.rooms[diff.index] = diff.item;
                this.notifyDataChange(diff.index);
            }
        }
    }
    // ... DataChangeListener 管理方法
}

@Entry
@Component
struct RoomListPage {
    private dataSource = new RoomDataSource();
    
    build() {
        List() {
            LazyForEach(this.dataSource, (item: RoomSummary) => {
                ListItem() {
                    RoomListItem({ item: item })
                }
            }, (item: RoomSummary) => item.roomId)  // key 必须唯一且稳定
        }
        .cachedCount(5)  // 预渲染视口外 5 个条目
    }
}
```

### **6.3 时间线已读回执追踪**

利用 API 22 新增的 `onVisibilityChange` 回调精确追踪消息可见状态，替代原有基于滚动位置的估算逻辑：

```typescript
// components/timeline/MessageBubble.ets
@Reusable
@Component
struct MessageBubble {
    @Prop item: TimelineItem;
    onVisible?: (eventId: string) => void;
    
    build() {
        Column() {
            // 消息内容渲染...
        }
        .onVisibilityChange((isVisible: boolean) => {
            if (isVisible && this.item.eventId && this.onVisible) {
                this.onVisible(this.item.eventId);
            }
        })
    }
}
```

已读回执的上报通过防抖处理，避免快速滑动时产生大量 NAPI 调用：

```typescript
// services/TimelineService.ets
class ReadReceiptTracker {
    private pendingEventId: string | null = null;
    private debounceTimer: number = -1;
    
    markVisible(eventId: string): void {
        this.pendingEventId = eventId;
        clearTimeout(this.debounceTimer);
        // 停止滑动 800ms 后再上报，减少无效 RPC
        this.debounceTimer = setTimeout(() => {
            if (this.pendingEventId) {
                napiSendReadReceipt(this.pendingEventId);
                this.pendingEventId = null;
            }
        }, 800);
    }
}
```

### **6.4 消息输入框（Composer）**

Composer 是消息编辑区域，API 22 为 `RichEditor` 新增了 `maxLength` 属性与输入拦截回调，直接满足消息长度限制与 Markdown 预览需求：

```typescript
// components/composer/MessageComposer.ets
@Component
struct MessageComposer {
    @State inputText: string = '';
    @State isSending: boolean = false;
    private richEditorController = new RichEditorController();
    onSend?: (text: string) => void;
    
    build() {
        Row() {
            RichEditor({ controller: this.richEditorController })
                .maxLength(32768)           // API 22 新增属性
                .placeholder('发送消息...')
                .layoutWeight(1)
                .maxLines(6)
                .onChange((value: RichEditorChangeValue) => {
                    this.inputText = value.previewText ?? '';
                })
            
            Button({ type: ButtonType.Circle }) {
                Image($r('app.media.ic_send'))
                    .width(20).height(20)
            }
            .width(40).height(40)
            .enabled(!this.isSending && this.inputText.trim().length > 0)
            .onClick(() => this.handleSend())
        }
        .padding(12)
        .backgroundColor('#F5F5F5')
    }
    
    private async handleSend(): Promise<void> {
        const text = this.inputText.trim();
        if (!text || this.isSending) return;
        this.isSending = true;
        try {
            await this.onSend?.(text);
            this.richEditorController.deleteSpans();
            this.inputText = '';
        } finally {
            this.isSending = false;
        }
    }
}
```

### **6.5 Navigation 路由管理**

使用 API 22 的 `Navigation` 组件管理页面栈，利用新增的拦截回调处理返回键行为（如 Composer 有未发送内容时弹出确认框）：

```typescript
// entryability/EntryAbility.ets
@Entry
@Component
struct MainPage {
    @Provide('navPathStack') navPathStack: NavPathStack = new NavPathStack();
    
    build() {
        Navigation(this.navPathStack) {
            RoomListPage()
        }
        .navDestination(AppRoutes.builder)
        .onNavBarStateChange((isVisible) => {
            // 侧边栏状态变化处理
        })
        // API 22 新增：返回拦截回调
        .onBackPressed(() => {
            return ComposerStateManager.hasUnsavedContent();
        })
    }
}

// 路由表
class AppRoutes {
    static readonly TIMELINE = 'TimelinePage';
    static readonly SETTINGS = 'SettingsPage';
    static readonly ROOM_DETAILS = 'RoomDetailsPage';
    
    @Builder
    static builder(name: string, param: ESObject) {
        if (name === AppRoutes.TIMELINE) {
            TimelinePage({ roomId: param as string })
        } else if (name === AppRoutes.SETTINGS) {
            SettingsPage()
        }
    }
}
```

---

## **第七章 端到端加密实现**

### **7.1 加密架构概述**

E2EE 功能完全由 matrix-rust-sdk 内置的 `matrix_sdk_crypto` 模块承载，底层密码学实现为 `vodozemac`（纯 Rust 的 Olm/Megolm 实现，已通过第三方安全审计）。ArkTS 层对加密过程完全透明，无需感知任何密钥材料，所有加密/解密操作均在 Rust 层自动完成。

```
消息发送路径（加密房间）：
  ArkTS: room.send("Hello")
      ↓ NAPI 调用
  Rust: room.send(RoomMessageEventContent::text_plain("Hello"))
      ↓ matrix_sdk_crypto 自动加密
  Megolm 会话加密 → m.room.encrypted 事件
      ↓ HTTPS 上传
  Matrix 服务器（服务器无法解密）

消息接收路径：
  Matrix 服务器推送 m.room.encrypted 事件
      ↓ Sliding Sync
  matrix_sdk_crypto 自动解密
      ↓ vodozemac Megolm 解密
  TimelineItemContent::Message（明文）
      ↓ ThreadSafeFunction 回调
  ArkTS 渲染明文消息
```

### **7.2 设备验证**

设备验证通过 SAS（Short Authentication String）表情符号比对流程实现，与 Element X Android 保持一致的 7 个表情符号展示方式：

```rust
// rust/sdk-wrapper/src/verification.rs
use matrix_sdk::encryption::verification::{
    SasVerification, VerificationRequest,
};

pub async fn start_sas_verification(
    client: &Client,
    user_id: &UserId,
    device_id: &DeviceId,
) -> Result<SasVerificationData> {
    let device = client
        .encryption()
        .get_device(user_id, device_id)
        .await?
        .ok_or(Error::DeviceNotFound)?;
    
    let verification = device.request_verification().await?;
    
    // 等待对方接受并协商 SAS 方法
    let sas = verification
        .start_sas()
        .await?
        .ok_or(Error::SasNotSupported)?;
    
    // 获取表情符号列表（7 个）用于展示给用户比对
    let emojis = sas.emoji()
        .ok_or(Error::EmojiNotReady)?
        .iter()
        .map(|e| EmojiData { symbol: e.symbol.to_string(), description: e.description.to_string() })
        .collect();
    
    Ok(SasVerificationData { emojis, sas_handle: sas })
}

pub async fn confirm_sas(sas: SasVerification) -> Result<()> {
    sas.confirm().await?;
    Ok(())
}
```

### **7.3 密钥备份（Key Backup）**

matrix-rust-sdk 0.16.0 支持自动启用密钥备份（`auto_enable_backups: true`），密钥备份到服务器端使用 Curve25519 加密，恢复时需要用户输入安全密钥或安全短语：

```rust
// rust/sdk-wrapper/src/backup.rs

/// 检查密钥备份状态
pub async fn get_backup_state(client: &Client) -> Result<BackupState> {
    let backup_state = client
        .encryption()
        .backups()
        .state();
    Ok(backup_state.into())
}

/// 用安全密钥恢复历史消息密钥
pub async fn recover_with_key(
    client: &Client,
    recovery_key: &str,
) -> Result<()> {
    client
        .encryption()
        .recovery()
        .recover(recovery_key)
        .await?;
    Ok(())
}
```

### **7.4 未解密消息处理**

当消息因缺少 Megolm 会话密钥无法解密时，`TimelineItemContent` 会返回 `UnableToDecrypt` 变体。ArkTS 层必须处理此状态并展示友好提示，同时触发密钥请求：

```rust
// rust/sdk-wrapper/src/timeline.rs
fn map_timeline_content(content: &TimelineItemContent) -> MessageContent {
    match content {
        TimelineItemContent::Message(msg) => {
            MessageContent::Text(msg.body().to_string())
        }
        TimelineItemContent::UnableToDecrypt(utd) => {
            // 自动触发向其他设备的密钥请求
            MessageContent::DecryptionPending {
                reason: utd.cause().to_string(),
            }
        }
        // 其他消息类型...
        _ => MessageContent::Unsupported,
    }
}
```

---

## **第八章 数据持久化与安全存储**

### **8.1 存储分层策略**

| 数据类型                     | 存储方案                         | 加密方式                  |
| :--------------------------- | :------------------------------- | :------------------------ |
| Matrix 事件 / 房间状态       | matrix-sdk-sqlite                | StoreCipher (AES-256-GCM) |
| 加密密钥材料                 | matrix-sdk-sqlite (crypto store) | StoreCipher               |
| Session Token / Access Token | 鸿蒙 Asset Store Kit             | 硬件级 TEE 保护           |
| SQLite 数据库密码            | 鸿蒙 Asset Store Kit             | 硬件级 TEE 保护           |
| 用户偏好设置                 | ArkTS Preferences                | 明文（非敏感数据）        |
| 媒体文件缓存                 | 应用沙箱 files/ 目录             | 无（依赖系统沙箱隔离）    |

### **8.2 Asset Store Kit 集成**

Access Token 和 SQLite 数据库密码必须通过鸿蒙 Asset Store Kit 存储，利用设备 TEE（可信执行环境）提供硬件级保护：

```typescript
// utils/SecureStorage.ets
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';

export class SecureStorage {
    private static readonly ACCESS_TOKEN_ALIAS = 'matrix_access_token';
    private static readonly DB_PASSPHRASE_ALIAS = 'matrix_db_passphrase';
    
    static async saveAccessToken(token: string): Promise<void> {
        const encoder = new util.TextEncoder();
        const tokenBytes = encoder.encodeInto(token);
        
        await asset.add({
            [asset.Tag.ALIAS]: SecureStorage.ACCESS_TOKEN_ALIAS,
            [asset.Tag.SECRET]: tokenBytes,
            [asset.Tag.ACCESSIBILITY]: asset.Accessibility.DEVICE_UNLOCKED,
            [asset.Tag.AUTH_TYPE]: asset.AuthType.NONE,
        });
    }
    
    static async getAccessToken(): Promise<string | null> {
        try {
            const result = await asset.query({
                [asset.Tag.ALIAS]: SecureStorage.ACCESS_TOKEN_ALIAS,
                [asset.Tag.RETURN_TYPE]: asset.ReturnType.ALL,
            });
            if (result.length === 0) return null;
            const decoder = new util.TextDecoder();
            return decoder.decodeWithStream(
                result[0].value as Uint8Array
            );
        } catch {
            return null;
        }
    }
    
    static async deleteAccessToken(): Promise<void> {
        await asset.remove({
            [asset.Tag.ALIAS]: SecureStorage.ACCESS_TOKEN_ALIAS,
        });
    }
}
```

### **8.3 SQLite 单线程化约束**

针对 matrix-sdk-sqlite Issue #5160 的锁竞争问题，所有数据库操作必须通过单一 Mutex 串行化：

```rust
// rust/sdk-wrapper/src/storage.rs
use tokio::sync::Mutex;
use std::sync::Arc;

/// 全局 SQLite 操作锁，确保同一时刻只有一个 tokio 任务执行数据库操作
static DB_LOCK: OnceLock<Arc<Mutex<()>>> = OnceLock::new();

pub fn get_db_lock() -> Arc<Mutex<()>> {
    DB_LOCK.get_or_init(|| Arc::new(Mutex::new(()))).clone()
}

/// 所有数据库操作必须通过此宏包装
macro_rules! with_db_lock {
    ($body:expr) => {{
        let lock = get_db_lock();
        let _guard = lock.lock().await;
        $body
    }};
}

// 使用示例
pub async fn load_rooms() -> Result<Vec<RoomInfo>> {
    with_db_lock!({
        // 执行 SQLite 查询
        store.get_all_rooms().await
    })
}
```

### **8.4 媒体文件缓存**

媒体文件（图片、视频、附件）下载后缓存至应用沙箱，使用内容哈希作为文件名避免重复下载：

```rust
// rust/sdk-wrapper/src/media.rs

pub async fn download_media(
    client: &Client,
    media_source: &MediaSource,
    cache_dir: &Path,
) -> Result<PathBuf> {
    // 使用 MXC URI 的哈希作为缓存键
    let cache_key = hash_media_source(media_source);
    let cache_path = cache_dir.join(&cache_key);
    
    // 命中缓存则直接返回
    if cache_path.exists() {
        return Ok(cache_path);
    }
    
    // 下载并写入缓存
    let content = client
        .media()
        .get_media_content(
            &MediaRequest { source: media_source.clone(), format: MediaFormat::File },
            true,
        )
        .await?;
    
    tokio::fs::write(&cache_path, &content).await?;
    Ok(cache_path)
}
```

---

## **第九章 通知系统集成**

### **9.1 通知架构**

Element X HarmonyOS 采用双通道通知策略：前台通知通过本地 `notificationManager` 直接推送，后台通知通过华为 Push Kit 实现进程唤醒。

```
前台通知（应用在前台/后台运行）:
  matrix-rust-sdk 推送规则匹配
      ↓
  Rust 侧触发 notification 事件
      ↓ ThreadSafeFunction
  ArkTS NotificationService
      ↓
  @ohos/notificationManager.publish()

后台通知（进程被系统回收）:
  Matrix 服务器 → 华为 Push Kit 服务器
      ↓ FCM-compatible push
  Push Kit 唤醒应用进程
      ↓ onReceiveMessage 回调
  解析 push payload → 本地通知展示
      ↓ 用户点击
  Deep Link 跳转到对应房间时间线
```

### **9.2 本地通知实现**

```typescript
// services/NotificationService.ets
import { notificationManager } from '@kit.NotificationKit';

export class NotificationService {
    private static notificationId = 1000;
    
    static async showMessageNotification(
        roomName: string,
        senderName: string,
        messagePreview: string,
        roomId: string,
    ): Promise<void> {
        const request: notificationManager.NotificationRequest = {
            id: NotificationService.notificationId++,
            content: {
                notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
                normal: {
                    title: roomName,
                    text: `${senderName}: ${messagePreview}`,
                }
            },
            // 点击通知跳转到对应房间
            wantAgent: await NotificationService.buildRoomWantAgent(roomId),
        };
        
        await notificationManager.publish(request);
    }
    
    private static async buildRoomWantAgent(roomId: string) {
        const { wantAgent } = await import('@kit.AbilityKit');
        return wantAgent.getWantAgent({
            wants: [{
                bundleName: 'im.element.x',
                abilityName: 'EntryAbility',
                parameters: { roomId },
            }],
            operationType: wantAgent.OperationType.START_ABILITY,
            requestCode: 0,
        });
    }
}
```

### **9.3 Push Kit 集成（P1）**

Push Kit 集成需要在华为开发者联盟注册应用并获取 `agconnect-services.json` 配置文件。API 22 Notification Kit 新增穿戴设备同步能力，Push Kit 推送的通知可自动同步至已配对的华为手表：

```typescript
// services/PushKitService.ets
import { pushService } from '@kit.PushKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class PushKitService {
    
    static async registerPushToken(): Promise<string> {
        const token = await pushService.getToken();
        hilog.info(0, 'PushKit', `Push token: ${token}`);
        // 将 token 上报至 Matrix 服务器的 Pusher 接口
        await MatrixPusherService.registerPusher(token);
        return token;
    }
    
    // 在 EntryAbility 的 onCreate 中调用
    static async onReceivePushMessage(
        remoteMessage: pushService.RemoteMessage
    ): Promise<void> {
        const data = remoteMessage.getData();
        const roomId = data['room_id'];
        const eventId = data['event_id'];
        
        if (roomId) {
            // 触发本地通知展示
            await NotificationService.showPushNotification(roomId, eventId);
        }
    }
}
```

Push Kit 与 Matrix Push Rules 的映射关系：Matrix 服务器通过 `/_matrix/push/v1/notify` 接口向华为 Push Kit 网关推送，payload 中携带 `room_id`、`event_id` 等最小必要信息（不含消息明文，保护 E2EE 隐私）。

---

## **第十章 性能优化指南**

### **10.1 性能目标基准**

| 指标                       | 目标值                 | 测量方法                    |
| :------------------------- | :--------------------- | :-------------------------- |
| 冷启动时间                 | ≤ 2000ms               | 进程创建到首帧渲染完成      |
| 房间列表滑动帧率           | ≥ 60fps（500 房间）    | DevEco Profiler Frame 面板  |
| 时间线首屏加载             | ≤ 800ms（5000 条消息） | Timeline 首条消息渲染完成   |
| 消息发送延迟（Local Echo） | ≤ 200ms                | 点击发送到气泡出现          |
| 峰值内存占用               | ≤ 300MB                | DevEco Profiler Memory 面板 |
| NAPI 单次调用开销          | ≤ 5ms                  | 不含业务逻辑的纯桥接耗时    |

### **10.2 启动性能优化**

冷启动路径上的关键优化点：

**延迟初始化 tokio 运行时**：tokio 运行时的初始化（约 50\~100ms）放在 `EntryAbility.onCreate()` 的异步任务中执行，不阻塞首帧渲染。

**分阶段加载**：首屏仅加载最近 20 个房间的摘要数据，历史房间在用户滚动时按需加载。

```typescript
// entryability/EntryAbility.ets
export default class EntryAbility extends UIAbility {
    async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
        // 异步初始化，不阻塞 UI
        napiInitRuntime().then(() => {
            // 运行时就绪后开始同步
            RoomListService.startSync();
        });
    }
    
    onWindowStageCreate(windowStage: window.WindowStage) {
        // 立即加载 UI，不等待 Rust 初始化完成
        windowStage.loadContent('pages/SplashPage');
    }
}
```

### **10.3 列表渲染优化**

`LazyForEach` 配合以下策略达到 60fps 滑动目标：

- **`cachedCount` 调优**：设置为 5，在视口外预渲染 5 个条目，消除快速滑动时的白屏闪烁，同时不过度消耗内存。
- **`@Reusable` 组件池**：`RoomListItem` 和 `MessageBubble` 均标注 `@Reusable`，ArkUI 框架自动维护组件对象池，避免频繁创建/销毁。
- **图片异步解码**：头像和媒体缩略图使用 `Image` 组件的异步加载模式，解码在非主线程完成。
- **key 稳定性**：`LazyForEach` 的 key 函数必须返回稳定的 `roomId` 或 `eventId`，禁止使用 index 作为 key，否则会导致全量重渲染。

### **10.4 内存管理**

**时间线分页窗口**：时间线内存中最多保留 500 条消息条目，超出时自动从内存中移除最旧的条目（但保留在 SQLite 中），用户上滑时触发分页重新加载。

**媒体缓存 LRU 淘汰**：媒体文件缓存总大小上限 200MB，超出时按 LRU 策略淘汰最久未访问的文件。

**Rust 侧内存监控**：在 Debug 构建中启用 `jemalloc` 统计，通过 NAPI 导出内存快照接口供 DevEco Profiler 集成：

```rust
#[napi]
#[cfg(debug_assertions)]
pub fn get_rust_memory_stats() -> String {
    // 返回 jemalloc 统计 JSON
    serde_json::to_string(&MemoryStats::current()).unwrap_or_default()
}
```

### **10.5 NAPI 调用频率控制**

频繁的 NAPI 调用会产生不可忽视的跨语言边界开销，以下场景需要特别注意：

- **批量更新合并**：`ThreadSafeFunction` 推送时间线更新时，将 100ms 内的多次 diff 合并为一次回调，减少 ArkTS 侧的状态更新频次。
- **事件过滤下沉**：将不影响 UI 的内部事件（如密钥交换、已读回执确认）过滤在 Rust 层，不推送到 ArkTS。
- **避免轮询**：禁止在 ArkTS 层使用 `setInterval` 轮询 Rust 侧状态，所有状态变更必须通过事件推送模式驱动。

---

## **第十一章 调试与测试**

### **11.1 HybridStack 混合调用栈调试**

API 22 新增的 HybridStack 特性支持在 DevEco Studio 调试器中同时展示 Rust 与 ArkTS 的完整调用栈，这是定位跨语言崩溃的核心工具。

启用 HybridStack 需在 `module.json5` 中声明：

```json
{
  "module": {
    "debuggingMode": "hybridStack"
  }
}
```

启用后，当 Rust 层发生 panic 或 ArkTS 层触发异常时，调试器将展示完整的跨语言调用链，格式如下：

```
ArkTS Frame: TimelinePage.handleSendMessage (TimelinePage.ets:87)
ArkTS Frame: MessageComposer.onClick (MessageComposer.ets:43)
--- NAPI Boundary ---
Rust Frame: napi_send_message (napi-bridge/src/send.rs:34)
Rust Frame: sdk_wrapper::send::send_text_message (sdk-wrapper/src/send.rs:67)
Rust Frame: matrix_sdk::room::Room::send (matrix-sdk/src/room/mod.rs:412)
```

### **11.2 日志规范**

项目统一使用鸿蒙 `hilog` 进行日志输出，Rust 侧通过 `hilog` crate 集成：

```rust
// Cargo.toml
[dependencies]
hilog = "0.1"  # 鸿蒙 hilog Rust 绑定

// 使用示例
use hilog::{hilog_info, hilog_error};

pub async fn login_with_password(...) -> Result<()> {
    hilog_info!(0x0001, "Auth", "Starting password login for user: {}", username);
    match client.matrix_auth().login_username(username, password).await {
        Ok(_) => { hilog_info!(0x0001, "Auth", "Login successful"); Ok(()) }
        Err(e) => { hilog_error!(0x0001, "Auth", "Login failed: {}", e); Err(e.into()) }
    }
}
```

日志 Domain 分配规范：

| Domain   | 模块        |
| :------- | :---------- |
| `0x0001` | 认证模块    |
| `0x0002` | 房间列表    |
| `0x0003` | 时间线      |
| `0x0004` | 加密模块    |
| `0x0005` | NAPI 桥接层 |
| `0x0006` | 存储模块    |
| `0x0007` | 通知模块    |

### **11.3 测试策略**

#### **Rust 单元测试**

`sdk-wrapper` 层的业务逻辑使用标准 `#[tokio::test]` 进行异步单元测试，matrix-rust-sdk 提供 `MockServer` 用于模拟 Matrix 服务器响应：

```rust
#[cfg(test)]
mod tests {
    use matrix_sdk_test::async_test;
    use wiremock::MockServer;
    
    #[async_test]
    async fn test_login_success() {
        let mock_server = MockServer::start().await;
        // 注册 mock 响应...
        let result = login_with_password(
            &mock_server.uri(), "user", "pass"
        ).await;
        assert!(result.is_ok());
    }
}
```

#### **ArkTS 单元测试**

使用 DevEco Studio 内置的 `@ohos/hypium` 框架测试 ArkTS 服务层逻辑：

```typescript
// test/services/AuthService.test.ets
import { describe, it, expect } from '@ohos/hypium';

export default function authServiceTest() {
    describe('AuthService', () => {
        it('should_parse_login_result_correctly', 0, () => {
            const json = '{"userId":"@user:matrix.org","accessToken":"token123"}';
            const result = parseLoginResult(json);
            expect(result.userId).assertEqual('@user:matrix.org');
        });
    });
}
```

#### **E2E 集成测试**

P1 阶段搭建本地 Conduit 服务器作为测试环境，执行完整的登录 → 创建房间 → 发送消息 → E2EE 验证的端到端流程测试。

---

## **附录 A：NAPI 导出函数速查表**

| 函数名                   | 参数                             | 返回值                       | 所属模块  |
| :----------------------- | :------------------------------- | :--------------------------- | :-------- |
| `napiInitRuntime`        | 无                               | `Promise<void>`              | runtime   |
| `napiLoginPassword`      | `homeserver, username, password` | `Promise<string>` (JSON)     | auth      |
| `napiStartOAuthLogin`    | 无                               | `Promise<string>` (授权 URL) | oauth     |
| `napiCompleteOAuthLogin` | `callbackUrl`                    | `Promise<void>`              | oauth     |
| `napiLogout`             | 无                               | `Promise<void>`              | auth      |
| `napiSubscribeRoomList`  | `callback: Function`             | `void`                       | room_list |
| `napiLoadTimeline`       | `roomId, callback: Function`     | `Promise<void>`              | timeline  |
| `napiPaginateBackwards`  | `roomId`                         | `Promise<boolean>`           | timeline  |
| `napiDownloadMedia` | `roomId, eventId, mxcUri` | `Promise<string>` (本地路径) | media |
| `napiGetEncryptionState` | `roomId` | `Promise<string>` (JSON) | crypto |
| `napiStartSasVerification` | `userId, deviceId` | `Promise<string>` (JSON) | verification |
| `napiConfirmSas` | `verificationId` | `Promise<void>` | verification |
| `napiCancelVerification` | `verificationId` | `Promise<void>` | verification |
| `napiGetBackupState` | 无 | `Promise<string>` (JSON) | backup |
| `napiRecoverWithKey` | `recoveryKey` | `Promise<void>` | backup |
| `napiGetRustMemoryStats` | 无 | `string` (JSON, Debug 构建) | debug |

---

## **附录 B：错误码对照表**

所有从 Rust 层抛出的错误均携带结构化错误码，ArkTS 层通过 `error.message` 解析 JSON 获取 `code` 字段进行分支处理，禁止直接匹配 `error.message` 字符串（Rust 错误描述文本可能随 SDK 版本变化）。

| 错误码 | 枚举值                 | 触发场景                         | ArkTS 处理建议                               |
| :----- | :--------------------- | :------------------------------- | :------------------------------------------- |
| `1001` | `NetworkError`         | 网络不可达 / 连接超时            | 展示"网络异常，请检查连接"提示，提供重试按钮 |
| `1002` | `ServerError`          | 服务器返回 5xx                   | 展示"服务器异常"提示，记录 hilog             |
| `2001` | `AuthenticationFailed` | 用户名或密码错误                 | 展示"用户名或密码错误"，清空密码输入框       |
| `2002` | `SessionExpired`       | Access Token 失效                | 清除本地 Session，跳转登录页                 |
| `2003` | `UserDeactivated`      | 账号已被停用                     | 展示停用提示，禁止重试                       |
| `3001` | `RoomNotFound`         | 房间 ID 不存在                   | 从列表移除该房间条目                         |
| `3002` | `RoomNotJoined`        | 未加入目标房间                   | 展示"无权访问此房间"                         |
| `4001` | `DecryptionFailed`     | Megolm 会话密钥缺失              | 展示"无法解密，等待密钥同步"，触发密钥请求   |
| `4002` | `VerificationFailed`   | SAS 表情符号不匹配               | 展示验证失败提示，建议重新发起验证           |
| `4003` | `BackupRestoreFailed`  | 密钥备份恢复失败                 | 提示检查安全密钥是否正确                     |
| `5001` | `StorageError`         | SQLite 读写失败                  | 记录 hilog error，展示通用错误提示           |
| `5002` | `StorageLockTimeout`   | SQLite 锁等待超时（Issue #5160） | 自动重试一次，仍失败则上报                   |
| `6001` | `MediaDownloadFailed`  | 媒体文件下载失败                 | 展示重试按钮，不影响其他消息渲染             |
| `6002` | `MediaTooLarge`        | 上传文件超过服务器限制           | 展示"文件大小超出限制（上限 XMB）"           |
| `9999` | `UnknownError`         | 未分类错误                       | 记录完整 hilog，展示通用错误提示             |

ArkTS 侧统一错误处理示例：

```typescript
// utils/ErrorHandler.ets
export interface BridgeError {
    code: number;
    message: string;
}

export function parseBridgeError(error: Error): BridgeError {
    try {
        return JSON.parse(error.message) as BridgeError;
    } catch {
        return { code: 9999, message: error.message };
    }
}

export async function withErrorHandling<T>(
    operation: () => Promise<T>,
    onError?: (error: BridgeError) => void,
): Promise<T | null> {
    try {
        return await operation();
    } catch (e) {
        const bridgeError = parseBridgeError(e as Error);
        
        // Session 过期全局处理
        if (bridgeError.code === 2002) {
            await AuthService.clearSession();
            AppRouter.navigateToLogin();
            return null;
        }
        
        onError?.(bridgeError);
        hilog.error(0x0000, 'ErrorHandler',
            `Bridge error []: `, bridgeError.code, bridgeError.message);
        return null;
    }
}
```

---

## **附录 C：Boilerplate 代码生成**

本附录提供各核心模块的最小可运行 Boilerplate，可直接作为新模块开发的起始模板。

### **C.1 新增 NAPI 导出函数模板**

每新增一个 NAPI 函数，需同时在以下三处添加代码：

**Step 1：Rust 侧 NAPI 导出（`rust/napi-bridge/src/`）**

```rust
// rust/napi-bridge/src/your_module.rs
use napi_derive::napi;
use crate::runtime::get_runtime;
use crate::sdk_wrapper::your_wrapper::your_business_logic;

/// 同步返回 Promise 的标准异步 NAPI 函数模板
#[napi]
pub async fn napi_your_function(
    param_one: String,
    param_two: i64,
) -> napi::Result<String> {  // 统一返回 JSON string
    get_runtime()
        .spawn(async move {
            your_business_logic(&param_one, param_two)
                .await
                .map(|result| serde_json::to_string(&result)
                    .map_err(|e| napi::Error::from_reason(e.to_string())))
                .map_err(|e| napi::Error::from_reason(
                    serde_json::to_string(&BridgeError::from(e))
                        .unwrap_or_default()
                ))?
        })
        .await
        .map_err(|e| napi::Error::from_reason(e.to_string()))?
}

/// 持续推送事件流的 ThreadSafeFunction 模板
#[napi]
pub fn napi_subscribe_your_stream(
    callback: napi::JsFunction,
) -> napi::Result<()> {
    let tsfn: ThreadsafeFunction<String> = callback
        .create_threadsafe_function(0, |ctx: ThreadSafeCallContext<String>| {
            Ok(vec![ctx.env.create_string(&ctx.value)?])
        })?;

    get_runtime().spawn(async move {
        let mut stream = your_event_stream().await;
        while let Some(event) = stream.next().await {
            let json = serde_json::to_string(&event).unwrap_or_default();
            tsfn.call(Ok(json), ThreadsafeFunctionCallMode::NonBlocking);
        }
    });
    Ok(())
}
```

**Step 2：在模块入口注册（`rust/napi-bridge/src/lib.rs`）**

```rust
// rust/napi-bridge/src/lib.rs
mod runtime;
mod error;
mod auth;
mod room_list;
mod timeline;
mod your_module;  // 新增此行

// ohos-rs 会自动扫描所有 #[napi] 标注的函数并生成 .d.ts 类型声明
```

**Step 3：ArkTS 侧调用封装（`entry/src/main/ets/services/`）**

```typescript
// entry/src/main/ets/services/YourService.ets
import { napiYourFunction, napiSubscribeYourStream } from 'libentry.so';
import { parseBridgeError, withErrorHandling } from '../utils/ErrorHandler';

export interface YourResult {
    fieldOne: string;
    fieldTwo: number;
}

export class YourService {
    
    /// 单次调用模板
    static async doSomething(
        paramOne: string,
        paramTwo: number,
    ): Promise<YourResult | null> {
        return withErrorHandling(async () => {
            const json = await napiYourFunction(paramOne, paramTwo);
            return JSON.parse(json) as YourResult;
        }, (error) => {
            // 模块特定错误处理
            if (error.code === 3001) {
                // 处理特定错误码
            }
        });
    }
    
    /// 事件订阅模板
    static subscribeToStream(
        onUpdate: (data: YourResult) => void,
        onError?: (error: Error) => void,
    ): void {
        napiSubscribeYourStream((err: Error | null, json: string) => {
            if (err) {
                onError?.(err);
                return;
            }
            try {
                onUpdate(JSON.parse(json) as YourResult);
            } catch (e) {
                onError?.(e as Error);
            }
        });
    }
}
```

### **C.2 新增 ArkUI 页面模板**

```typescript
// entry/src/main/ets/pages/YourPage.ets
import { YourService, YourResult } from '../services/YourService';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Entry
@Component
struct YourPage {
    // 路由参数接收
    @State roomId: string = '';
    
    // 页面状态
    @State isLoading: boolean = true;
    @State hasError: boolean = false;
    @State data: YourResult | null = null;
    
    // 路由栈（由父级 Navigation 注入）
    @Consume('navPathStack') navPathStack: NavPathStack;
    
    aboutToAppear(): void {
        this.loadData();
    }
    
    aboutToDisappear(): void {
        // 清理订阅、取消异步任务
    }
    
    private async loadData(): Promise<void> {
        this.isLoading = true;
        this.hasError = false;
        
        const result = await YourService.doSomething(this.roomId, 0);
        
        if (result) {
            this.data = result;
        } else {
            this.hasError = true;
        }
        this.isLoading = false;
    }
    
    build() {
        NavDestination() {
            if (this.isLoading) {
                LoadingProgress().width(48).height(48)
            } else if (this.hasError) {
                Column() {
                    Text('加载失败').fontSize(16).opacity(0.6)
                    Button('重试').onClick(() => this.loadData())
                        .margin({ top: 12 })
                }
            } else {
                // 正常内容渲染
                Column() {
                    Text(this.data?.fieldOne ?? '')
                }
            }
        }
        .title('页面标题')
        .onBackPressed(() => {
            this.navPathStack.pop();
            return true;
        })
    }
}
```

### **C.3 新增 @Reusable 列表组件模板**

```typescript
// entry/src/main/ets/components/YourListItem.ets

@Reusable
@Component
struct YourListItem {
    @State item: YourDataModel = {} as YourDataModel;
    onTap?: (item: YourDataModel) => void;
    
    /// @Reusable 组件复用时必须实现此方法重置状态
    aboutToReuse(params: Record<string, ESObject>): void {
        this.item = params['item'] as YourDataModel;
    }
    
    build() {
        Row() {
            // 组件内容
            Text(this.item.title).fontSize(16)
        }
        .height(56)
        .width('100%')
        .padding({ left: 16, right: 16 })
        .onClick(() => this.onTap?.(this.item))
    }
}

/// 配套的 IDataSource 实现模板
class YourDataSource implements IDataSource {
    private items: YourDataModel[] = [];
    private listeners: DataChangeListener[] = [];
    
    totalCount(): number { return this.items.length; }
    getData(index: number): YourDataModel { return this.items[index]; }
    
    registerDataChangeListener(listener: DataChangeListener): void {
        this.listeners.push(listener);
    }
    unregisterDataChangeListener(listener: DataChangeListener): void {
        this.listeners = this.listeners.filter(l => l !== listener);
    }
    
    private notifyDataAdd(index: number): void {
        this.listeners.forEach(l => l.onDataAdd(index));
    }
    private notifyDataDelete(index: number): void {
        this.listeners.forEach(l => l.onDataDelete(index));
    }
    private notifyDataChange(index: number): void {
        this.listeners.forEach(l => l.onDataChange(index));
    }
    
    /// 应用增量 diff 更新，避免全量重渲染
    applyDiffs(diffs: DataDiff[]): void {
        for (const diff of diffs) {
            switch (diff.type) {
                case 'Insert':
                    this.items.splice(diff.index, 0, diff.item);
                    this.notifyDataAdd(diff.index);
                    break;
                case 'Remove':
                    this.items.splice(diff.index, 1);
                    this.notifyDataDelete(diff.index);
                    break;
                case 'Update':
                    this.items[diff.index] = diff.item;
                    this.notifyDataChange(diff.index);
                    break;
            }
        }
    }
}
```

### **C.4 sdk-wrapper 业务逻辑模板**

```rust
// rust/sdk-wrapper/src/your_wrapper.rs
use matrix_sdk::Client;
use serde::{Deserialize, Serialize};
use crate::error::BridgeError;

/// 返回给 ArkTS 的数据结构，必须实现 Serialize
#[derive(Debug, Serialize, Deserialize)]
pub struct YourResult {
    pub field_one: String,
    pub field_two: i64,
}

/// 业务逻辑函数，所有 matrix-sdk 调用在此层发生
/// 不得在此层调用任何 NAPI 相关 API
pub async fn your_business_logic(
    param_one: &str,
    param_two: i64,
) -> Result<YourResult, BridgeError> {
    // 获取全局 Client 单例
    let client = crate::CLIENT
        .get()
        .ok_or(BridgeError::new(2002, "Client not initialized"))?;
    
    // 执行 matrix-sdk 操作
    // let result = client.some_operation().await
    //     .map_err(BridgeError::from)?;
    
    Ok(YourResult {
        field_one: param_one.to_string(),
        field_two: param_two,
    })
}
```

---

至此，**Element X HarmonyOS 技术文档 v1.0.0** 全部内容已输出完毕。完整文档结构如下：

- 第一章 项目概述
- 第二章 系统架构
- 第三章 核心依赖与工具链
- 第四章 NAPI 桥接层设计
- 第五章 matrix-rust-sdk 集成
- 第六章 ArkUI 层实现规范
- 第七章 端到端加密实现
- 第八章 数据持久化与安全存储
- 第九章 通知系统集成
- 第十章 性能优化指南
- 第十一章 调试与测试
- 附录 A NAPI 导出函数速查表
- 附录 B 错误码对照表
- 附录 C Boilerplate 代码生成

如需导出为 Markdown 文件或对某个章节做进一步细化，告诉我即可。