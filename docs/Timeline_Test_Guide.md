# Timeline 功能测试指南

## 测试环境

- 设备: 192.168.1.4 (已连接)
- 应用: org.matrix.chen (已安装)
- HAP: entry-default-signed.hap

## 测试流程

### Phase 0: 登录测试
1. 启动应用 → 显示登录页面
2. 输入 Homeserver URL (例如: https://matrix.org)
3. 输入用户名密码
4. 点击登录 → 进入房间列表

**预期日志:**
```
AuthService: Login successful
SyncService: Sync started
RoomListService: Room list subscribed
```

### Phase 1: 房间列表测试
1. 查看房间列表是否加载
2. 检查未读消息角标
3. 检查加密图标 (🔒)
4. 点击房间进入

**预期日志:**
```
RoomListService: Rooms count: X
RoomListItem: Click room XXX
```

### Phase 2: Timeline 消息测试

#### 2.1 消息加载
1. 进入房间 → 消息列表加载
2. 检查消息显示 (发送者、内容、时间)

**预期日志:**
```
TimelineService: Timeline initialized for room: XXX
TimelineService: Sending initial timeline: X items
RoomPage: UI state updated: isLoading=0, messages=X
```

#### 2.2 分页加载
1. 滚动到顶部
2. 触发加载更多
3. 检查历史消息加载

**预期日志:**
```
RoomPage: Loading more messages for room: XXX
TimelineService: Paginated backwards, more=true/false
```

#### 2.3 发送消息 (Local Echo)
1. 输入消息内容
2. 点击发送按钮
3. 观察:
   - 消息立即显示 (Local Echo)
   - 发送状态: ⏳ → ✓
   - 如果失败: ✗ + 红色背景

**预期日志:**
```
RoomPage: Message sent: XXX
TimelineService: Text message sent
Timeline update: append/insert
```

#### 2.4 已读回执
1. 查看他人消息
2. 自动发送已读回执

**预期日志:**
```
ReadReceiptTracker: markVisible eventId=XXX
TimelineService: Read receipt sent for event: XXX
```

## 日志监控命令

```bash
# 监控所有 Timeline 相关日志
hdc shell hilog -T RoomPage,TimelineService,AuthService,RoomListService -x

# 只看 Timeline 日志
hdc shell hilog -T TimelineService -x

# 实时过滤错误
hdc shell hilog -T RoomPage,TimelineService | grep -i error
```

## 验证检查点

| 功能 | 验证方式 | 日志关键字 |
|------|----------|------------|
| 登录 | 进入房间列表 | Login successful |
| 房间列表 | 显示房间卡片 | Rooms count |
| Timeline初始化 | 消息加载 | Timeline initialized |
| 分页 | 滚动到顶部加载 | Paginated backwards |
| 发送消息 | 状态图标变化 | Message sent |
| 已读回执 | 滚动时自动发送 | Read receipt sent |
| 加密状态 | 🔒图标 | is_encrypted |

## 常见问题排查

### 消息不显示
- 检查 Timeline 初始化日志
- 检查 messages count 是否 > 0
- 确认 hasMessages 状态

### 分页不工作
- 检查 hasMoreMessages 状态
- 确认 onReachEdge 触发
- 查看 paginate_backwards 返回值

### 发送失败
- 检查网络连接
- 查看 EventSendState 日志
- 检查 E2EE 加密状态

## 性能指标验证

| 指标 | 目标 | 测试方法 |
|------|------|----------|
| 冷启动 | ≤ 2000ms | hilog 时间戳计算 |
| Timeline加载 | ≤ 800ms | 初始化到 isLoading=false |
| 发送延迟 | ≤ 200ms | 点击到 Local Echo 显示 |
| 滚动帧率 | ≥ 60fps | DevEco Studio 性能分析 |