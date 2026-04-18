/**
 * 房间列表项组件
 * 使用 @Reusable 实现组件复用，提升滚动性能
 */

import { RoomSummary } from '../../models/RoomModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'RoomListItem';

// 导航参数类型
interface NavParam {
  roomId: string;
  roomName: string;
}

@Reusable
@Component
export struct RoomListItem {
  @Prop room: RoomSummary = { roomId: '', name: '', unreadCount: 0, isEncrypted: false };
  @Consume('navPathStack') navPathStack: NavPathStack;

  /**
   * 组件复用时的初始化
   */
  aboutToReuse(params: ESObject): void {
    if (params.room) {
      this.room = params.room as RoomSummary;
    }
  }

  build() {
    // 日志输出房间信息，便于调试
    hilog.debug(DOMAIN, TAG, 'Room: %{public}s, encrypted=%{public}s', this.room.name, this.room.isEncrypted.toString());

    Row() {
      // Avatar 占位符 - 显示房间名首字母
      Text(this.room.name.charAt(0).toUpperCase())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .borderRadius(24)
        .backgroundColor(this.room.isEncrypted ? '#E3F2FD' : '#E0E0E0')  // 加密房间用淡蓝色背景
        .fontColor('#666666')

      Column() {
        Row() {
          Text(this.room.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 加密指示器 - 更醒目
          if (this.room.isEncrypted) {
            Text('🔒')
              .fontSize(16)
              .margin({ left: 6 })
          }
        }

        Text(this.room.lastMessage ?? '暂无消息')
          .fontSize(14)
          .opacity(0.6)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text(this.room.timestamp ?? '')
          .fontSize(12)
          .opacity(0.4)

        // 未读消息角标
        if (this.room.unreadCount > 0) {
          Text(this.room.unreadCount.toString())
            .fontSize(12)
            .fontColor('#FFFFFF')
            .backgroundColor('#2196F3')
            .borderRadius(10)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      const navParam: NavParam = { roomId: this.room.roomId, roomName: this.room.name };
      this.navPathStack.pushPath({ name: 'RoomPage', param: navParam });
    })
  }
}