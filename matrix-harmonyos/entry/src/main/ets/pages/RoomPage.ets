/**
 * 房间页面 - Timeline 消息列表
 */

import { TimelineService } from '../services/TimelineService';
import { MediaService } from '../services/MediaService';
import { TimelineMessage, MessageContent, SendState, ImageContent } from '../models/TimelineModels';
import { ImageMessage } from '../components/timeline/ImageMessage';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0003;
const TAG = 'RoomPage';

// 导航参数类型
interface RoomNavParam {
  roomId: string;
  roomName: string;
}

// NavDestination 页面不需要 @Entry 装饰器
@Component
export struct RoomPage {
  // 参数通过 prop 传入，不从 navPathStack 获取
  roomId: string = '';  // 非 @State，由父组件传入
  roomName: string = '';  // 非 @State，由父组件传入
  @State displayRoomName: string = '';  // 用于显示的房间名
  @State isLoading: boolean = true;
  @State inputText: string = '';
  @State isSending: boolean = false;
  @State messages: TimelineMessage[] = []; // @State 数组，UI 会自动刷新
  @State hasMessages: boolean = false; // 用于强制触发 UI 刷新
  @State isLoadingMore: boolean = false; // 加载历史消息状态
  @State hasMoreMessages: boolean = true; // 是否还有更多历史消息
  @State isPickingImage: boolean = false; // 选择图片状态

  @Consume('navPathStack') navPathStack: NavPathStack;

  private readTracker: ReadReceiptTracker = new ReadReceiptTracker();

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'RoomPage aboutToAppear for room: %{public}s, name: %{public}s', this.roomId, this.roomName);

    // 设置显示的房间名
    this.displayRoomName = this.roomName || this.roomId;

    // 异步初始化 Timeline
    this.initTimeline();
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
      await TimelineService.sendText(this.roomId, text);
      hilog.info(DOMAIN, TAG, 'Message sent: %{public}s', text);
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
    } else if (message.content.type === 'unableToDecrypt') {
      Text('[无法解密]')
        .fontSize(14)
        .fontColor('#FF5252')
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
   * 发送状态图标 - 更醒目的设计
   */
  @Builder
  sendStateIcon(state: SendState) {
    if (state === 'sending') {
      // 发送中 - 明显的时钟图标 + 灰色
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
      // 已发送 - 明显的单勾 + 白色
      Text('✓')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .margin({ left: 4 })
    } else if (state === 'failed') {
      // 发送失败 - 明显的红色感叹号
      Text('!')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF5252')
        .margin({ left: 4 })
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

        Text(this.displayRoomName)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

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
                  // 他人的消息 - 左侧
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
            .onAppear(() => {
              // 仅对他人消息发送已读回执
              if (!message.isOwn && message.eventId) {
                this.readTracker.markVisible(this.roomId, message.eventId);
                this.readTracker.flush(this.roomId);
              }
            })
          }, (message: TimelineMessage, index: number) => message.eventId ?? `msg-${index}`)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
        .edgeEffect(EdgeEffect.Spring)
      }

      // 底部 MessageComposer - 输入框和发送按钮
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