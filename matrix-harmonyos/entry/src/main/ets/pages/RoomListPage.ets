/**
 * 房间列表页面
 */

import { AuthService } from '../services/AuthService';
import { RoomListService } from '../services/RoomListService';
import { RoomSummary } from '../models/RoomModels';
import { RoomDataSource } from '../models/RoomDataSource';
import { RoomListItem } from '../components/room/RoomListItem';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'RoomListPage';

@Entry
@Component
export struct RoomListPage {
  @State sessionInfo: string = '';
  @State isLoading: boolean = true;
  @State isEmpty: boolean = false;
  @State @Watch('onRoomsChanged') rooms: RoomSummary[] = [];  // 添加 @State 和 @Watch 触发 UI 刷新

  @Consume('navPathStack') navPathStack: NavPathStack;
  @Consume('isAuthenticated') isAuthenticated: boolean;

  private dataSource: RoomDataSource = new RoomDataSource();

  onRoomsChanged(): void {
    this.dataSource.updateRooms(this.rooms);
    this.isLoading = false;
    this.isEmpty = this.rooms.length === 0;
  }

  async aboutToAppear(): Promise<void> {
    const session = AuthService.getSession();
    if (session) {
      this.sessionInfo = `已登录: ${session.userId}`;
    }

    // 初始化 RoomListService
    await RoomListService.init();

    // 订阅房间列表更新
    RoomListService.subscribe(() => {
      this.rooms = RoomListService.getRooms();
    });
  }

  aboutToDisappear(): void {
    RoomListService.stopSync();
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
            RoomListService.reset();  // 重置状态以便下次登录
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
      } else if (this.isEmpty) {
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
          LazyForEach(this.dataSource, (room: RoomSummary) => {
            ListItem() {
              RoomListItem({ room: room })
            }
          }, (room: RoomSummary) => `${room.roomId}_${room.name}`)  // key包含name，name变化时重新渲染
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(5)  // 预渲染 5 个条目提升滚动性能
      }
    }
    .width('100%')
    .height('100%')
  }
}