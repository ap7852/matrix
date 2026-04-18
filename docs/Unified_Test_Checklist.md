# Timeline 功能测试准备 (统一测试)

## 待推送提交 (6 commits)

```
dea321c feat: Add detailed NAPI logging for pagination and subscribe
25b14fe fix: Improve UI visibility for send state and encryption indicators
b0bc690 feat: Add pagination trigger and room name fallback
d6094c9 feat: Add Local Echo UI and encryption indicators
ac28858 feat: Implement Timeline pagination with persistent storage
d2cf157 feat: Implement Phase 1 Timeline and fix logout state reset
```

---

## 测试准备

### 步骤 1: 构建 HAP
在 DevEco Studio 中:
1. Build > Clean Project
2. Build > Make Hap(s)

### 步骤 2: 安装应用
```bash
hdc install -r matrix-harmonyos/entry/build/default/outputs/default/entry-default-signed.hap
```

### 步骤 3: 启动应用
```bash
hdc shell aa start -a EntryAbility -b org.matrix.chen
```

### 步骤 4: 开始监控日志
```bash
hdc shell hilog -T RoomPage,TimelineService,RoomListService,RoomListItem -x
```

---

## 测试清单

### Phase 1: 房间列表测试 ✅

| # | 测试项 | 操作 | 预期结果 | 日志关键字 |
|---|--------|------|----------|------------|
| 1 | 房间名称显示 | 查看房间列表 | 显示名称而非完整 room_id | `Room: XXX, encrypted=true/false` |
| 2 | 加密图标 | 查看加密房间 | 显示 🔒 图标 | `encrypted=true` |
| 3 | 未读角标 | 查看有未读的房间 | 显示蓝色数字 | - |
| 4 | 进入房间 | 点击房间 | 进入消息页面 | `RoomPage aboutToAppear` |

### Phase 2: Timeline 消息测试 ✅

| # | 测试项 | 操作 | 预期结果 | 日志关键字 |
|---|--------|------|----------|------------|
| 5 | 消息加载 | 进入房间 | 显示历史消息 | `messages count: X` |
| 6 | 消息样式 | 查看消息 | 自己蓝色右侧，他人灰色左侧 | - |
| 7 | 发送消息 | 输入并发送 | 立即显示 (Local Echo) | `Message sent`, `append update` |
| 8 | 发送状态 | 观察发送的消息 | 显示 ✓ 图标 (白色、加粗) | - |

### Phase 3: 分页加载测试 ⚠️ 重点

| # | 测试项 | 操作 | 预期结果 | 日志关键字 |
|---|--------|------|----------|------------|
| 9 | 加载更多按钮 | 查看右上角 | 显示蓝色 "⚡加载更多" 按钮 | - |
| 10 | 点击分页 | 点击按钮 | 加载历史消息 | `User clicked load more button` |
| 11 | 分页日志 | 查看日志 | 显示分页结果 | `NAPI: paginate_backwards called` |
| 12 | 消息增加 | 观察消息列表 | 消息数量增加 | `messages count: X+` |

### Phase 4: 已读回执测试 ✅

| # | 测试项 | 操作 | 预期结果 | 日志关键字 |
|---|--------|------|----------|------------|
| 13 | 自动发送 | 滚动查看他人消息 | 自动发送已读回执 | `Read receipt sent` |

### Phase 5: 登出测试 ✅

| # | 测试项 | 操作 | 预期结果 | 日志关键字 |
|---|--------|------|----------|------------|
| 14 | 登出清理 | 点击退出 | 返回登录页 | `Timeline unsubscribed` |

---

## UI 改进说明

### 发送状态图标
- **发送中**: LoadingProgress 动画 (白色圆形)
- **已发送**: ✓ 符号 (14px, 白色, 加粗)
- **发送失败**: ! 符号 (14px, 红色, 加粗)

### 加载更多按钮
- 蓝色背景 (#2196F3)
- 白色文字 "⚡加载更多"
- 36px 高度
- 禁用时灰色

### 加密图标
- 🔒 符号 (16px)
- 加密房间头像淡蓝色背景

---

## 测试通过标准

所有 14 个测试项预期结果与实际一致 → 测试通过

---

## 测试通过后推送

```bash
git push origin master
```

---

## 问题排查

### 如果看不到加载更多按钮:
- 检查是否有更多历史消息可加载
- 日志显示 `hasMore=false` 则按钮禁用

### 如果看不到加密图标:
- 检查日志 `encrypted=true/false`
- 可能房间未启用加密

### 如果分页不工作:
- 检查日志 `NAPI: paginate_backwards called`
- 检查日志 `Pagination result: more=true/false`
- 可能服务器无更多历史消息