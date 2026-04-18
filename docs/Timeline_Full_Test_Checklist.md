# Timeline 功能完整测试清单

## 待推送的提交 (4 commits)

| Commit | 功能 | 测试状态 |
|--------|------|----------|
| d2cf157 | Phase 1 Timeline + 登出清理 | ⏳ 待测试 |
| ac28858 | Timeline 分页 + 实例存储 | ⏳ 待测试 |
| d6094c9 | Local Echo UI + 加密指示器 | ⏳ 待测试 |
| b0bc690 | 分页触发 + 房间名称 fallback | ⏳ 待测试 |

---

## 测试流程

### Phase 0: 登录测试
- [ ] 启动应用
- [ ] 显示登录页面
- [ ] 输入 homeserver
- [ ] 输入用户名密码
- [ ] 点击登录 → 进入房间列表
- [ ] 日志: `Login successful`

### Phase 1: 房间列表测试
- [ ] 房间列表加载显示
- [ ] **房间名称显示正常**（不只是 room_id）
- [ ] 加密房间显示 🔒 图标
- [ ] 未读消息角标显示
- [ ] 点击房间进入
- [ ] 日志: `Rooms count: X`

### Phase 2: Timeline 消息测试

#### 2.1 消息加载
- [ ] 进入房间 → 消息列表加载
- [ ] 消息显示发送者、内容、时间
- [ ] 日志: `Timeline initialized`
- [ ] 日志: `messages count: X`

#### 2.2 分页加载 ⚠️ 重点测试
- [ ] 点击右上角 **"加载更多"** 按钮
- [ ] 观察日志: `Loading more messages`
- [ ] 观察日志: `Paginated backwards`
- [ ] 消息数量增加
- [ ] 或显示: `hasMore=false`

#### 2.3 发送消息 (Local Echo) ⚠️ 重点测试
- [ ] 输入消息内容
- [ ] 点击发送按钮
- [ ] **消息立即显示** (Local Echo)
- [ ] **发送状态图标**: ⏳ → ✓
- [ ] 日志: `Message sent`
- [ ] 日志: `Applied append update`

#### 2.4 已读回执
- [ ] 滚动查看他人消息
- [ ] 日志: `Read receipt sent`

### Phase 3: UI 状态测试
- [ ] 自己的消息右侧显示，蓝色背景
- [ ] 他人消息左侧显示，灰色背景 + 发送者名
- [ ] 发送中消息透明度 0.7
- [ ] 发送失败消息红色背景 + ✗

### Phase 4: 登出测试
- [ ] 点击退出按钮
- [ ] 返回登录页面
- [ ] 日志: `Timeline unsubscribed`
- [ ] 日志: `All subscriptions cleared`

---

## 测试命令

```bash
# 启动应用
hdc shell aa start -a EntryAbility -b org.matrix.chen

# 监控日志
hdc shell hilog -T RoomPage,TimelineService,RoomListService,AuthService -x

# 只看关键日志
hdc shell hilog -x | grep -E "Login|Timeline|pagination|Message sent|Read receipt"
```

---

## 测试通过标准

| 功能 | 通过条件 |
|------|----------|
| 登录 | 日志显示 `Login successful` |
| 房间名称 | 显示名称而非完整 room_id |
| 加密指示器 | 加密房间显示 🔒 |
| 消息加载 | `messages count: > 0` |
| 分页加载 | 日志显示 `Paginated backwards` |
| Local Echo | 发送后立即显示 + 状态图标变化 |
| 已读回执 | 日志显示 `Read receipt sent` |
| 登出清理 | 日志显示 `unsubscribed` |

---

## 失败处理

如果测试失败：
1. 记录失败原因和日志
2. 分析问题根因
3. 修复代码
4. 重新测试
5. **不推送直到测试通过**

---

## 最终确认

所有测试通过后：
1. 运行 `git log --oneline -4` 确认提交
2. 运行 `git push origin master`
3. 记录推送结果