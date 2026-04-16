/**
 * 房间列表页面
 */

import { AuthService } from '../services/AuthService';
import { RoomListService } from '../services/RoomListService';
import { RoomSummary } from '../models/RoomModels';
import { RoomListItem } from '../components/room/RoomListItem';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'RoomListPage';

@Entry
@Component
export struct RoomListPage {
  @State sessionInfo: string = '';
  @State rooms: RoomSummary[] = [];
  @State isLoading: boolean = true;

  @Consume('navPathStack') navPathStack: NavPathStack;
  @Consume('isAuthenticated') isAuthenticated: boolean;

  async aboutToAppear(): Promise<void> {
    const session = AuthService.getSession();
    if (session) {
      this.sessionInfo = `已登录: ${session.userId}`;
    }

    await RoomListService.startSync();
    this.rooms = RoomListService.getRooms();
    this.isLoading = false;
  }

  build() {
    Column() {
      Row() {
        Text(this.sessionInfo)
          .fontSize(14)
          .opacity(0.6)
          .layoutWeight(1)

        Button('退出')
          .fontSize(14)
          .onClick(async () => {
            await AuthService.logout();
            this.isAuthenticated = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
          Text('加载中...')
            .fontSize(14)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.rooms.length === 0) {
        Column() {
          Text('暂无房间')
            .fontSize(16)
            .opacity(0.6)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.rooms, (room: RoomSummary) => {
            ListItem() {
              RoomListItem({ room: room })
            }
          }, (room: RoomSummary) => room.roomId)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}