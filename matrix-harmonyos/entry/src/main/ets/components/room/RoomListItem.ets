/**
 * 房间列表项组件
 */

import { RoomSummary } from '../../models/RoomModels';

@Component
export struct RoomListItem {
  @Prop room: RoomSummary = {} as RoomSummary;

  build() {
    Row() {
      Text(this.room.name.charAt(0).toUpperCase())
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .borderRadius(24)
        .backgroundColor('#E0E0E0')
        .fontColor('#666666')

      Column() {
        Text(this.room.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.room.lastMessage ?? '')
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
  }
}