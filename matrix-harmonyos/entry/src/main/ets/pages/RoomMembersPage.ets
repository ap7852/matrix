/**
 * 房间成员页面
 */

import { RoomService } from '../services/RoomService';
import { AvatarService } from '../services/AvatarService';
import { RoomMember } from '../models/RoomModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0003;
const TAG = 'RoomMembersPage';

@Component
export struct RoomMembersPage {
  roomId: string = '';
  @State members: RoomMember[] = [];
  @State isLoading: boolean = true;
  @State avatarCache: Map<string, string> = new Map();

  @Consume('navPathStack') navPathStack: NavPathStack;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Loading members for room: %{public}s', this.roomId);
    this.loadMembers();
  }

  private async loadMembers(): Promise<void> {
    try {
      this.members = await RoomService.getMembers(this.roomId);
      this.isLoading = false;
      // 加载头像
      for (const member of this.members) {
        if (member.avatarUrl && !this.avatarCache.has(member.userId)) {
          try {
            const base64 = await AvatarService.getAvatar(member.avatarUrl);
            this.avatarCache.set(member.userId, base64);
          } catch (err) {
            hilog.warn(DOMAIN, TAG, 'Avatar load failed for %{public}s', member.userId);
          }
        }
      }
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Load members failed: %{public}s', error.message);
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // Header
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

        Text('房间成员')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .padding({ left: 12, right: 16 })
      .backgroundColor('#FFFFFF')

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
      } else {
        List() {
          ForEach(this.members, (member: RoomMember) => {
            ListItem() {
              Row() {
                // Avatar
                if (this.avatarCache.has(member.userId)) {
                  Image(`data:image/jpeg;base64,${this.avatarCache.get(member.userId)}`)
                    .width(40)
                    .height(40)
                    .borderRadius(20)
                    .objectFit(ImageFit.Cover)
                } else {
                  Text((member.displayName ?? member.userId).charAt(0).toUpperCase())
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .width(40)
                    .height(40)
                    .textAlign(TextAlign.Center)
                    .borderRadius(20)
                    .backgroundColor('#E0E0E0')
                    .fontColor('#666666')
                }

                Column() {
                  Text(member.displayName ?? member.userId)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(member.userId)
                    .fontSize(12)
                    .opacity(0.5)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .margin({ left: 12 })
                .alignItems(HorizontalAlign.Start)

                if (member.isOwn) {
                  Text('你')
                    .fontSize(12)
                    .fontColor('#2196F3')
                    .backgroundColor('#E3F2FD')
                    .borderRadius(4)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                }
              }
              .width('100%')
              .height(60)
              .padding({ left: 16, right: 16 })
            }
          }, (member: RoomMember) => member.userId)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FFFFFF')
      }

      // Footer - member count
      Row() {
        Text(`${this.members.length} 位成员`)
          .fontSize(14)
          .opacity(0.6)
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#F5F5F5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}