/**
 * 房间页面 - Timeline 消息列表
 */

import { TimelineService } from '../services/TimelineService';
import { MediaService } from '../services/MediaService';
import { AvatarService } from '../services/AvatarService';
import { RoomService } from '../services/RoomService';
import { TimelineMessage, MessageContent, SendState, ImageContent, ReplyPreview } from '../models/TimelineModels';
import { ImageMessage } from '../components/timeline/ImageMessage';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pasteboard } from '@kit.BasicServicesKit';

const DOMAIN = 0x0003;
const TAG = 'RoomPage';

// 导航参数类型
interface RoomNavParam {
  roomId: string;
  roomName: string;
  avatarUrl?: string;
}

// NavDestination 页面不需要 @Entry 装饰器
@Component
export struct RoomPage {
  // 参数通过 prop 传入，不从 navPathStack 获取
  roomId: string = '';  // 非 @State，由父组件传入
  roomName: string = '';  // 非 @State，由父组件传入
  avatarUrl: string = '';  // 非 @State，由父组件传入
  @State displayRoomName: string = '';  // 用于显示的房间名
  @State roomAvatarBase64: string = '';  // 房间头像 Base64
  @State isLoading: boolean = true;
  @State inputText: string = '';
  @State isSending: boolean = false;
  @State messages: TimelineMessage[] = []; // @State 数组，UI 会自动刷新
  @State hasMessages: boolean = false; // 用于强制触发 UI 刷新
  @State isLoadingMore: boolean = false; // 加载历史消息状态
  @State hasMoreMessages: boolean = true; // 是否还有更多历史消息
  @State isPickingImage: boolean = false; // 选择图片状态
  @State selectedMessage: TimelineMessage | null = null; // 长按选中的消息
  @State showContextMenu: boolean = false; // 显示上下文菜单
  @State replyTarget: TimelineMessage | null = null; // 回复目标消息
  @State editTarget: TimelineMessage | null = null; // 编辑目标消息
  @State userAvatarCache: Map<string, string> = new Map(); // 用户头像缓存
  @State isSearching: boolean = false; // 搜索模式
  @State searchText: string = ''; // 搜索文本
  @State searchResults: TimelineMessage[] = []; // 搜索结果

  @Consume('navPathStack') navPathStack: NavPathStack;

  private readTracker: ReadReceiptTracker = new ReadReceiptTracker();

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'RoomPage aboutToAppear for room: %{public}s, name: %{public}s', this.roomId, this.roomName);

    // 先使用传入的名称作为临时显示
    this.displayRoomName = this.roomName || this.roomId;

    // 异步初始化 Timeline
    this.initTimeline();

    // 加载头像
    this.loadRoomAvatar();

    // 异步获取实时房间名称
    this.loadRoomDetails();
  }

  private async loadRoomDetails(): Promise<void> {
    try {
      const details = await RoomService.getDetails(this.roomId);
      // 更新为实时房间名称
      this.displayRoomName = details.name;
      hilog.info(DOMAIN, TAG, 'Room name updated from details: %{public}s', details.name);
    } catch (err) {
      const error = err as Error;
      hilog.warn(DOMAIN, TAG, 'Load room details failed: %{public}s', error.message);
    }
  }

  private async loadRoomAvatar(): Promise<void> {
    if (this.avatarUrl && this.avatarUrl.startsWith('mxc://')) {
      try {
        this.roomAvatarBase64 = await AvatarService.getAvatar(this.avatarUrl);
        hilog.info(DOMAIN, TAG, 'Room avatar loaded');
      } catch (err) {
        const error = err as Error;
        hilog.warn(DOMAIN, TAG, 'Room avatar load failed: %{public}s', error.message);
      }
    }
  }

  /**
   * 加载用户头像
   */
  private async loadUserAvatar(senderId: string, avatarUrl: string): Promise<void> {
    if (this.userAvatarCache.has(senderId)) {
      return; // 已缓存
    }

    try {
      const base64 = await AvatarService.getAvatar(avatarUrl);
      this.userAvatarCache.set(senderId, base64);
      hilog.debug(DOMAIN, TAG, 'User avatar loaded for: %{public}s', senderId);
    } catch (err) {
      const error = err as Error;
      hilog.warn(DOMAIN, TAG, 'User avatar load failed: %{public}s', error.message);
    }
  }

  private async initTimeline(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Initializing timeline for room: %{public}s', this.roomId);

    // 初始化 Timeline
    await TimelineService.init(this.roomId);
    hilog.info(DOMAIN, TAG, 'Timeline initialized');

    // 订阅 Timeline 更新
    TimelineService.subscribe(this.roomId, (update) => {
      const newMessages = TimelineService.getMessages(this.roomId);
      hilog.info(DOMAIN, TAG, 'Timeline update: %{public}s, total messages: %{public}d', update.type, newMessages.length);
      if (newMessages.length > 0) {
        hilog.info(DOMAIN, TAG, 'First message: sender=%{public}s, content=%{public}s', newMessages[0].senderId, newMessages[0].content.type);
      }
      // 直接赋值新的数组，触发 UI 刷新
      this.messages = [...newMessages]; // 使用展开运算符确保新数组
      this.isLoading = false;
      this.hasMessages = this.messages.length > 0;
      hilog.info(DOMAIN, TAG, 'UI state updated: isLoading=%{public}d, messages=%{public}d', this.isLoading, this.messages.length);
    });
  }

  aboutToDisappear(): void {
    TimelineService.unsubscribe(this.roomId);
    hilog.info(DOMAIN, TAG, 'RoomPage disappearing for room: %{public}s', this.roomId);
  }

  /**
   * 获取消息文本内容
   */
  private getMessageText(message: TimelineMessage): string {
    if (message.content.type === 'text') {
      return message.content.body;
    } else if (message.content.type === 'image') {
      return `[图片] ${message.content.body}`;
    } else {
      return '';
    }
  }

  /**
   * 执行搜索
   */
  private performSearch(query: string): void {
    if (query.trim().length === 0) {
      this.searchResults = [];
      return;
    }

    const lowerQuery = query.toLowerCase();
    this.searchResults = this.messages.filter(msg => {
      if (msg.content.type === 'text' && msg.content.body) {
        return msg.content.body.toLowerCase().includes(lowerQuery);
      }
      return false;
    });
    hilog.info(DOMAIN, TAG, 'Search found %{public}d results', this.searchResults.length);
  }

  /**
   * 发送消息
   */
  async sendMessage(): Promise<void> {
    if (!this.inputText.trim() || this.isSending) {
      return;
    }

    const text = this.inputText.trim();
    this.inputText = '';
    this.isSending = true;

    try {
      // 处理回复
      if (this.replyTarget && this.replyTarget.eventId) {
        await TimelineService.replyToMessage(this.roomId, this.replyTarget.eventId, text);
        this.replyTarget = null;
        hilog.info(DOMAIN, TAG, 'Reply sent: %{public}s', text);
      }
      // 处理编辑
      else if (this.editTarget && this.editTarget.eventId) {
        await TimelineService.editMessage(this.roomId, this.editTarget.eventId, text);
        this.editTarget = null;
        hilog.info(DOMAIN, TAG, 'Edit sent: %{public}s', text);
      }
      // 正常发送
      else {
        await TimelineService.sendText(this.roomId, text);
        hilog.info(DOMAIN, TAG, 'Message sent: %{public}s', text);
      }
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Send message failed: %{public}s', error.message);
    }

    this.isSending = false;
  }

  /**
   * 加载历史消息
   */
  async loadMoreMessages(): Promise<void> {
    if (this.isLoadingMore || !this.hasMoreMessages) {
      return;
    }

    this.isLoadingMore = true;
    hilog.info(DOMAIN, TAG, 'Loading more messages for room: %{public}s', this.roomId);

    try {
      const hasMore = await TimelineService.paginateBackwards(this.roomId);
      this.hasMoreMessages = hasMore;
      hilog.info(DOMAIN, TAG, 'Pagination result: hasMore=%{public}s', hasMore.toString());
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Load more messages failed: %{public}s', error.message);
    }

    this.isLoadingMore = false;
  }

  /**
   * 选择图片并发送
   */
  async pickAndSendImage(): Promise<void> {
    if (this.isPickingImage) {
      return;
    }

    this.isPickingImage = true;
    hilog.info(DOMAIN, TAG, 'Picking image for room: %{public}s', this.roomId);

    try {
      // 使用 PhotoAccessHelper 选择图片
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });

      if (result.photoUris.length === 0) {
        hilog.info(DOMAIN, TAG, 'No image selected');
        this.isPickingImage = false;
        return;
      }

      const imageUri = result.photoUris[0];
      hilog.info(DOMAIN, TAG, 'Image selected: %{public}s', imageUri);

      // 打开文件并读取内容
      const file = fileIo.openSync(imageUri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      const fileSize = stat.size;
      hilog.info(DOMAIN, TAG, 'Image file size: %{public}d bytes', fileSize);

      // 读取文件内容到 ArrayBuffer
      const buffer = new ArrayBuffer(fileSize);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file.fd);

      // 转换为 Base64
      const base64Data = await this.arrayBufferToBase64(buffer);
      hilog.info(DOMAIN, TAG, 'Image converted to Base64, length: %{public}d', base64Data.length);

      // 发送图片
      const filename = `image_${Date.now()}.jpg`;
      const mimetype = 'image/jpeg';
      await MediaService.sendImage(this.roomId, filename, mimetype, base64Data);

      hilog.info(DOMAIN, TAG, 'Image sent successfully');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Pick/send image failed: %{public}s', error.message);
    }

    this.isPickingImage = false;
  }

  /**
   * ArrayBuffer 转 Base64
   */
  async arrayBufferToBase64(buffer: ArrayBuffer): Promise<string> {
    const bytes = new Uint8Array(buffer);
    // 使用 util.Base64Helper 编码 (异步)
    const base64Helper = new util.Base64Helper();
    const encodedBytes = await base64Helper.encode(bytes);
    // 转换 Uint8Array 结果为 string
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(encodedBytes);
  }

  /**
   * 回复引用预览
   */
  @Builder
  replyPreviewBuilder(reply: ReplyPreview, isOwn: boolean) {
    Row() {
      // 引用线
      Column()
        .width(2)
        .height(40)
        .backgroundColor(isOwn ? '#FFFFFF' : '#2196F3')
        .margin({ right: 8 })

      Column() {
        Text(reply.senderName || reply.senderId)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(isOwn ? '#FFFFFF' : '#2196F3')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(reply.contentBody)
          .fontSize(12)
          .opacity(0.7)
          .fontColor(isOwn ? '#FFFFFF' : '#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ bottom: 8 })
  }

  /**
   * 渲染消息内容
   */
  @Builder
  messageContentBuilder(message: TimelineMessage) {
    if (message.content.type === 'text') {
      Text(message.content.body ?? '')
        .fontSize(14)
        .fontColor(message.isOwn ? '#FFFFFF' : '#333333')
    } else if (message.content.type === 'image') {
      // 使用 ImageMessage 组件显示图片
      ImageMessage({ content: message.content })
    } else if (message.content.type === 'video') {
      // 视频消息 - 显示占位符
      Column() {
        Text('🎬')
          .fontSize(32)
        Text(message.content.body ?? '视频')
          .fontSize(12)
          .opacity(0.6)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width(200)
      .height(150)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#E8E8E8')
      .borderRadius(8)
    } else if (message.content.type === 'file') {
      // 文件消息 - 显示下载按钮
      Column() {
        Text('📎')
          .fontSize(24)
        Text(message.content.filename ?? message.content.body ?? '文件')
          .fontSize(12)
          .opacity(0.6)
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (message.content.size) {
          Text(this.formatFileSize(message.content.size))
            .fontSize(10)
            .opacity(0.4)
        }
      }
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#E8E8E8')
      .borderRadius(8)
      .padding(12)
    } else if (message.content.type === 'audio') {
      // 音频消息 - 显示播放占位符
      Row() {
        Text('🎵')
          .fontSize(24)
        Column() {
          Text(message.content.body ?? '音频')
            .fontSize(12)
            .opacity(0.6)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (message.content.duration) {
            Text(this.formatDuration(message.content.duration))
              .fontSize(10)
              .opacity(0.4)
          }
        }
        .margin({ left: 8 })
        .alignItems(HorizontalAlign.Start)
      }
      .justifyContent(FlexAlign.Start)
      .backgroundColor('#E8E8E8')
      .borderRadius(8)
      .padding(12)
    } else if (message.content.type === 'unableToDecrypt') {
      // 解密失败 - 显示详细提示和操作按钮
      Column() {
        Row() {
          Text('🔒')
            .fontSize(20)
          Text('无法解密此消息')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FF5252')
            .margin({ left: 8 })
        }
        Text(message.content.reason || '发送者的设备尚未验证，或密钥尚未同步')
          .fontSize(12)
          .opacity(0.7)
          .fontColor('#FF5252')
          .margin({ top: 4 })
        Button('请求重发密钥')
          .fontSize(12)
          .height(28)
          .backgroundColor('#FF5252')
          .fontColor('#FFFFFF')
          .margin({ top: 8 })
          .onClick(() => {
            hilog.info(DOMAIN, TAG, 'Request key resend for: %{public}s', message.eventId ?? '');
            // TODO: 实现密钥重发请求
          })
      }
      .width(200)
      .padding(12)
      .backgroundColor('#FFEBEE')
      .borderRadius(8)
      .alignItems(HorizontalAlign.Start)
    } else if (message.content.type === 'redacted') {
      Text('[消息已删除]')
        .fontSize(14)
        .fontColor('#999999')
    } else {
      Text('[不支持的消息类型]')
        .fontSize(14)
        .fontColor('#999999')
    }
  }

  /**
   * 格式化文件大小
   */
  private formatFileSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    } else if (bytes < 1024 * 1024) {
      return `${Math.round(bytes / 1024)} KB`;
    } else if (bytes < 1024 * 1024 * 1024) {
      return `${Math.round(bytes / (1024 * 1024))} MB`;
    } else {
      return `${Math.round(bytes / (1024 * 1024 * 1024))} GB`;
    }
  }

  /**
   * 格式化时长
   */
  private formatDuration(ms: number): string {
    const seconds = Math.round(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  /**
   * 发送状态图标 - 更醒目的设计
   */
  @Builder
  sendStateIcon(state: SendState) {
    if (state === 'sending') {
      Row() {
        LoadingProgress()
          .width(12)
          .height(12)
          .color('#FFFFFF')
      }
      .width(16)
      .height(16)
      .margin({ left: 4 })
    } else if (state === 'sent') {
      Text('✓')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ left: 4 })
    } else if (state === 'failed') {
      Text('!')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF5252')
        .margin({ left: 4 })
    }
  }

  /**
   * 用户头像
   */
  @Builder
  userAvatar(message: TimelineMessage) {
    if (message.senderAvatarUrl && message.senderAvatarUrl.startsWith('mxc://') && this.userAvatarCache.has(message.senderId)) {
      // 远程头像 - 已缓存
      Image('data:image/jpeg;base64,' + this.userAvatarCache.get(message.senderId))
        .width(32)
        .height(32)
        .borderRadius(16)
        .objectFit(ImageFit.Cover)
    } else {
      // 占位符
      this.avatarPlaceholder(message)
    }
  }

  /**
   * 头像占位符 - 显示首字母
   */
  @Builder
  avatarPlaceholder(message: TimelineMessage) {
    Text((message.senderName || message.senderId).charAt(0).toUpperCase())
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .width(32)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(16)
      .backgroundColor('#E0E0E0')
      .fontColor('#666666')
  }

  /**
   * 消息上下文菜单
   */
  @Builder
  messageContextMenu(message: TimelineMessage) {
    Menu() {
      // 复制文本
      if (message.content.type === 'text') {
        MenuItem() {
          Text('复制')
            .fontSize(14)
        }
        .onClick(() => {
          // 复制文本到剪贴板
          if (message.content.type === 'text') {
            const text = message.content.body;
            const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
            const systemPasteboard = pasteboard.getSystemPasteboard();
            systemPasteboard.setData(pasteboardData);
            hilog.info(DOMAIN, TAG, 'Copied text: %{public}s', text);
          }
          this.selectedMessage = null;
        })
      }

      // 回复
      MenuItem() {
        Text('回复')
          .fontSize(14)
      }
      .onClick(() => {
        this.replyTarget = message;
        this.editTarget = null; // 清除编辑状态
        // 如果是文本消息，预填充内容（可选）
        if (message.content.type === 'text') {
          // 不预填充，保持空输入
        }
        hilog.info(DOMAIN, TAG, 'Reply to: %{public}s', message.eventId ?? '');
        this.selectedMessage = null;
      })

      // 自己的消息才有编辑和删除
      if (message.isOwn) {
        MenuItem() {
          Text('编辑')
            .fontSize(14)
        }
        .onClick(() => {
          this.editTarget = message;
          this.replyTarget = null; // 清除回复状态
          // 预填充原文本
          const text = this.getMessageText(message);
          if (text) {
            this.inputText = text;
          }
          hilog.info(DOMAIN, TAG, 'Edit message: %{public}s', message.eventId ?? '');
          this.selectedMessage = null;
        })

        MenuItem() {
          Text('删除')
            .fontSize(14)
            .fontColor('#FF5252')
        }
        .onClick(async () => {
          if (message.eventId) {
            try {
              await TimelineService.redactMessage(this.roomId, message.eventId);
              hilog.info(DOMAIN, TAG, 'Message deleted: %{public}s', message.eventId);
            } catch (err) {
              const error = err as Error;
              hilog.error(DOMAIN, TAG, 'Delete failed: %{public}s', error.message);
            }
          }
          this.selectedMessage = null;
        })
      }

      // 反应表情 - 每个表情单独点击
      MenuItem() {
        Text('👍')
          .fontSize(16)
      }
      .onClick(async () => {
        if (message.eventId) {
          try {
            await TimelineService.toggleReaction(this.roomId, message.eventId, '👍');
            hilog.info(DOMAIN, TAG, 'Reaction 👍 toggled');
          } catch (err) {
            const error = err as Error;
            hilog.error(DOMAIN, TAG, 'Reaction failed: %{public}s', error.message);
          }
        }
        this.selectedMessage = null;
      })

      MenuItem() {
        Text('❤️')
          .fontSize(16)
      }
      .onClick(async () => {
        if (message.eventId) {
          try {
            await TimelineService.toggleReaction(this.roomId, message.eventId, '❤️');
            hilog.info(DOMAIN, TAG, 'Reaction ❤️ toggled');
          } catch (err) {
            const error = err as Error;
            hilog.error(DOMAIN, TAG, 'Reaction failed: %{public}s', error.message);
          }
        }
        this.selectedMessage = null;
      })

      MenuItem() {
        Text('😄')
          .fontSize(16)
      }
      .onClick(async () => {
        if (message.eventId) {
          try {
            await TimelineService.toggleReaction(this.roomId, message.eventId, '😄');
            hilog.info(DOMAIN, TAG, 'Reaction 😄 toggled');
          } catch (err) {
            const error = err as Error;
            hilog.error(DOMAIN, TAG, 'Reaction failed: %{public}s', error.message);
          }
        }
        this.selectedMessage = null;
      })
    }
  }

  build() {
    Column() {
      // 顶部 Header
      Row() {
        Button({ type: ButtonType.Circle }) {
          Text('<')
            .fontSize(20)
            .fontColor('#333333')
        }
        .width(36)
        .height(36)
        .backgroundColor('#F5F5F5')
        .onClick(() => {
          this.navPathStack.pop();
        })

        // 房间头像
        if (this.roomAvatarBase64) {
          Image(`data:image/jpeg;base64,${this.roomAvatarBase64}`)
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .margin({ left: 12 })
        } else {
          Text(this.displayRoomName.charAt(0).toUpperCase())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .borderRadius(18)
            .backgroundColor('#E0E0E0')
            .fontColor('#666666')
            .margin({ left: 12 })
        }

        Text(this.displayRoomName)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 成员按钮
        Button({ type: ButtonType.Circle }) {
          Text('👥')
            .fontSize(16)
        }
        .width(36)
        .height(36)
        .backgroundColor('#F5F5F5')
        .margin({ right: 8 })
        .onClick(() => {
          const navParam: RoomNavParam = { roomId: this.roomId, roomName: '' };
          this.navPathStack.pushPath({ name: 'RoomMembersPage', param: navParam });
        })

        // 搜索按钮
        Button({ type: ButtonType.Circle }) {
          Text('🔍')
            .fontSize(16)
        }
        .width(36)
        .height(36)
        .backgroundColor(this.isSearching ? '#E3F2FD' : '#F5F5F5')
        .onClick(() => {
          this.isSearching = !this.isSearching;
          if (!this.isSearching) {
            this.searchText = '';
            this.searchResults = [];
          }
        })

        // 测试按钮 - 手动触发分页（醒目设计）
        Button('⚡加载更多')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .height(36)
          .backgroundColor(this.hasMoreMessages ? '#2196F3' : '#E0E0E0')
          .fontColor(this.hasMoreMessages ? '#FFFFFF' : '#999999')
          .borderRadius(8)
          .enabled(!this.isLoadingMore && this.hasMoreMessages)
          .onClick(() => {
            hilog.info(DOMAIN, TAG, 'User clicked load more button');
            this.loadMoreMessages();
          })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })
      .backgroundColor('#FFFFFF')

      // 搜索栏
      if (this.isSearching) {
        Row() {
          TextInput({ placeholder: '搜索消息...', text: this.searchText })
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#F5F5F5')
            .borderRadius(20)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.searchText = value;
              this.performSearch(value);
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#F5F5F5')
      }

      // 消息列表 - 使用 ForEach 配合 @State 数组
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('加载中...')
            .fontSize(14)
            .fontColor('#666666')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.hasMessages) {
        Column() {
          Text('暂无消息')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          // 搜索模式下显示搜索结果
          if (this.isSearching && this.searchText.trim().length > 0) {
            if (this.searchResults.length === 0) {
              ListItem() {
                Column() {
                  Text('未找到匹配消息')
                    .fontSize(14)
                    .fontColor('#999999')
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 20, bottom: 20 })
              }
            } else {
              ForEach(this.searchResults, (message: TimelineMessage, index: number) => {
                ListItem() {
                  Row() {
                    if (message.isOwn) {
                      Column() {
                        this.messageContentBuilder(message)
                        Text(message.timestamp)
                          .fontSize(10)
                          .fontColor('#CCCCCC')
                          .margin({ top: 4 })
                      }
                      .backgroundColor('#2196F3')
                      .borderRadius(12)
                      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                      .alignItems(HorizontalAlign.End)
                    } else {
                      Column() {
                        Text(message.senderName || message.senderId)
                          .fontSize(12)
                          .fontColor('#666666')
                          .margin({ bottom: 4 })
                        this.messageContentBuilder(message)
                        Text(message.timestamp)
                          .fontSize(10)
                          .fontColor('#999999')
                          .margin({ top: 4 })
                      }
                      .backgroundColor('#F5F5F5')
                      .borderRadius(12)
                      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                      .alignItems(HorizontalAlign.Start)
                    }
                  }
                  .width('100%')
                  .justifyContent(message.isOwn ? FlexAlign.End : FlexAlign.Start)
                  .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                }
              }, (message: TimelineMessage, index: number) => message.eventId ?? `search-${index}`)
            }
          } else {
            // 正常消息列表
            // 加载更多指示器 - 在顶部显示
            if (this.isLoadingMore) {
              ListItem() {
                Row() {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                  Text('加载更多...')
                    .fontSize(14)
                    .opacity(0.6)
                    .margin({ left: 8 })
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 8, bottom: 8 })
              }
            }

            // 历史消息加载提示
            if (this.hasMoreMessages && !this.isLoadingMore) {
              ListItem() {
                Text('↑ 向上滚动加载历史消息')
                  .fontSize(12)
                  .opacity(0.5)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 4, bottom: 4 })
              }
            }

            ForEach(this.messages, (message: TimelineMessage, index: number) => {
            ListItem() {
              Row() {
                if (message.isOwn) {
                  // 自己的消息 - 右侧
                  Column() {
                    // 回复引用预览
                    if (message.inReplyTo) {
                      this.replyPreviewBuilder(message.inReplyTo, true)
                    }
                    this.messageContentBuilder(message)
                    Row() {
                      Text(message.timestamp)
                        .fontSize(10)
                        .fontColor('#CCCCCC')
                      // 发送状态图标
                      this.sendStateIcon(message.sendState)
                    }
                    .margin({ top: 4 })
                  }
                  .backgroundColor(message.sendState === 'failed' ? '#FFEBEE' : '#2196F3')
                  .borderRadius(12)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .alignItems(HorizontalAlign.End)
                  .opacity(message.sendState === 'sending' ? 0.7 : 1)
                } else {
                  // 他人的消息 - 左侧，带头像
                  this.userAvatar(message)
                  Column() {
                    Text(message.senderName || message.senderId)
                      .fontSize(12)
                      .fontColor('#666666')
                      .margin({ bottom: 4 })
                    // 回复引用预览
                    if (message.inReplyTo) {
                      this.replyPreviewBuilder(message.inReplyTo, false)
                    }
                    this.messageContentBuilder(message)
                    Text(message.timestamp)
                      .fontSize(10)
                      .fontColor('#999999')
                      .margin({ top: 4 })
                  }
                  .backgroundColor('#F5F5F5')
                  .borderRadius(12)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: 8 })
                }
              }
              .width('100%')
              .justifyContent(message.isOwn ? FlexAlign.End : FlexAlign.Start)
              .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            }
            .gesture(
              LongPressGesture({ repeat: false })
                .onAction(() => {
                  this.selectedMessage = message;
                  hilog.info(DOMAIN, TAG, 'Long press on message: %{public}s', message.eventId ?? '');
                })
            )
            .bindContextMenu(this.selectedMessage?.eventId === message.eventId, this.messageContextMenu(message))
            .onAppear(() => {
              // 仅对他人消息发送已读回执
              if (!message.isOwn && message.eventId) {
                this.readTracker.markVisible(this.roomId, message.eventId);
                this.readTracker.flush(this.roomId);
              }
              // 加载用户头像
              if (!message.isOwn && message.senderAvatarUrl && !this.userAvatarCache.has(message.senderId)) {
                this.loadUserAvatar(message.senderId, message.senderAvatarUrl);
              }
            })
          }, (message: TimelineMessage, index: number) => message.eventId ?? `msg-${index}`)
          } // end of normal message list else block
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
        .edgeEffect(EdgeEffect.Spring)
      }

      // 底部 MessageComposer - 输入框和发送按钮
      Column() {
        // 回复/编辑指示器
        if (this.replyTarget) {
          Row() {
            Text('回复:')
              .fontSize(12)
              .fontColor('#666666')
            Text(this.getMessageText(this.replyTarget))
              .fontSize(12)
              .fontColor('#2196F3')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 4 })
            Button('✕')
              .fontSize(12)
              .width(24)
              .height(24)
              .backgroundColor('#E0E0E0')
              .onClick(() => {
                this.replyTarget = null;
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor('#F0F0F0')
        }

        if (this.editTarget) {
          Row() {
            Text('编辑:')
              .fontSize(12)
              .fontColor('#666666')
            Text(this.getMessageText(this.editTarget))
              .fontSize(12)
              .fontColor('#2196F3')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .margin({ left: 4 })
            Button('✕')
              .fontSize(12)
              .width(24)
              .height(24)
              .backgroundColor('#E0E0E0')
              .onClick(() => {
                this.editTarget = null;
                this.inputText = '';
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor('#F0F0F0')
        }

        Row() {
          // 图片选择按钮
          Button({ type: ButtonType.Circle }) {
            if (this.isPickingImage) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color('#2196F3')
            } else {
              Text('📷')
                .fontSize(18)
            }
          }
          .width(40)
          .height(40)
          .backgroundColor('#F5F5F5')
          .margin({ right: 4 })
          .enabled(!this.isPickingImage)
          .onClick(() => {
            this.pickAndSendImage();
          })

          TextInput({ placeholder: '输入消息...', text: this.inputText })
            .layoutWeight(1)
            .height(40)
            .backgroundColor('#F5F5F5')
            .borderRadius(20)
            .padding({ left: 16, right: 16 })
            .onChange((value: string) => {
              this.inputText = value;
            })
            .enabled(!this.isSending)

          Button({ type: ButtonType.Circle }) {
            if (this.isSending) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color('#FFFFFF')
            } else {
              Text('>')
                .fontSize(18)
                .fontColor('#FFFFFF')
            }
          }
          .width(40)
          .height(40)
          .backgroundColor(this.inputText.trim().length > 0 ? '#2196F3' : '#CCCCCC')
          .margin({ left: 8 })
          .enabled(this.inputText.trim().length > 0 && !this.isSending)
          .onClick(() => {
            this.sendMessage();
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FFFFFF')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}

// 已读回执追踪器
class ReadReceiptTracker {
  private pendingEventId: string | null = null;
  private lastSentEventId: string | null = null;

  markVisible(roomId: string, eventId: string | undefined): void {
    if (!eventId) return;
    this.pendingEventId = eventId;
  }

  flush(roomId: string): void {
    if (this.pendingEventId && this.pendingEventId !== this.lastSentEventId) {
      TimelineService.sendReadReceipt(roomId, this.pendingEventId);
      this.lastSentEventId = this.pendingEventId;
      this.pendingEventId = null;
    }
  }
}