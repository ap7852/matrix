/**
 * 房间列表数据源 - 用于 LazyForEach
 */

import { RoomSummary } from './RoomModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'RoomDataSource';

export class RoomDataSource implements IDataSource {
  private rooms: RoomSummary[] = [];
  private listeners: DataChangeListener[] = [];

  /**
   * 更新房间列表
   */
  updateRooms(rooms: RoomSummary[]): void {
    this.rooms = rooms;
    this.notifyAllListeners();
  }

  /**
   * 通知所有监听器数据已更新
   */
  private notifyAllListeners(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  /**
   * 获取数据总数
   */
  totalCount(): number {
    return this.rooms.length;
  }

  /**
   * 获取指定索引的数据
   */
  getData(index: number): RoomSummary {
    if (index < 0 || index >= this.rooms.length) {
      hilog.error(DOMAIN, TAG, 'Invalid index: %{public}d', index);
      return this.rooms[0] ?? { roomId: '', name: '', unreadCount: 0, isEncrypted: false };
    }
    return this.rooms[index];
  }

  /**
   * 注册数据变化监听器
   */
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  /**
   * 注销数据变化监听器
   */
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }
}