/**
 * 房间列表服务
 */

import { getBridge } from './MatrixBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RoomSummary, RoomListUpdate } from '../models/RoomModels';

const DOMAIN = 0x0002;
const TAG = 'RoomListService';

export class RoomListService {
  private static rooms: RoomSummary[] = [];
  private static initialized = false;

  /**
   * 启动同步
   */
  static async startSync(): Promise<void> {
    if (RoomListService.initialized) return;

    try {
      const bridge = getBridge();
      const result: string = await bridge.napiStartRoomListSync();
      RoomListService.initialized = true;
      hilog.info(DOMAIN, TAG, 'Room list sync started: %{public}s', result);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Start sync failed: %{public}s', error.message);
    }
  }

  /**
   * 获取房间列表
   */
  static getRooms(): RoomSummary[] {
    return RoomListService.rooms;
  }

  /**
   * 应用更新
   */
  static applyUpdate(update: RoomListUpdate): void {
    for (const diff of update.diffs) {
      if (diff.type === 'Insert' && diff.index !== undefined && diff.item) {
        RoomListService.rooms.splice(diff.index, 0, diff.item);
      } else if (diff.type === 'Update' && diff.index !== undefined && diff.item) {
        RoomListService.rooms[diff.index] = diff.item;
      } else if (diff.type === 'Remove' && diff.index !== undefined) {
        RoomListService.rooms.splice(diff.index, 1);
      } else if (diff.type === 'Clear') {
        RoomListService.rooms = [];
      }
    }
  }
}