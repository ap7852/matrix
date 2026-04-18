/**
 * 房间列表服务
 */

import { getBridge } from './MatrixBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RoomSummary, RoomListUpdate, RoomListDiff } from '../models/RoomModels';

const DOMAIN = 0x0002;
const TAG = 'RoomListService';

export class RoomListService {
  private static rooms: RoomSummary[] = [];
  private static initialized = false;
  private static subscribed = false;

  /**
   * 重置状态（用于 logout 后重新登录）
   */
  static reset(): void {
    RoomListService.rooms = [];
    RoomListService.initialized = false;
    RoomListService.subscribed = false;
    hilog.info(DOMAIN, TAG, 'RoomListService reset');
  }

  /**
   * 初始化房间列表和加密同步
   * 使用 SyncService 统一管理（包含 EncryptionSyncService）
   */
  static async init(): Promise<void> {
    if (RoomListService.initialized) return;

    try {
      const bridge = getBridge();

      // 初始化 SyncService（同时包含 EncryptionSyncService 和 RoomListService）
      try {
        await bridge.napiInitSyncService();
        hilog.info(DOMAIN, TAG, 'SyncService initialized (includes encryption)');

        // 启动同步
        await bridge.napiStartSync();
        hilog.info(DOMAIN, TAG, 'Sync started');
      } catch (syncErr) {
        const error = syncErr as Error;
        hilog.warn(DOMAIN, TAG, 'SyncService init failed: %{public}s', error.message);
      }

      // 再初始化 RoomListService（用于获取房间列表流）
      await bridge.napiInitRoomListService();
      RoomListService.initialized = true;
      hilog.info(DOMAIN, TAG, 'RoomListService initialized');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Init failed: %{public}s', error.message);
    }
  }

  /**
   * 订阅房间列表更新
   * 使用 ThreadSafeFunction 实现实时推送
   */
  static subscribe(callback: (update: RoomListUpdate) => void): void {
    if (RoomListService.subscribed) return;

    try {
      const bridge = getBridge();
      bridge.napiSubscribeRoomList((json: string) => {
        const update = JSON.parse(json) as RoomListUpdate;
        RoomListService.applyUpdate(update);
        callback(update);
      });
      RoomListService.subscribed = true;
      hilog.info(DOMAIN, TAG, 'Room list subscribed');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Subscribe failed: %{public}s', error.message);
    }
  }

  /**
   * 停止同步
   */
  static async stopSync(): Promise<void> {
    try {
      const bridge = getBridge();
      await bridge.napiStopRoomListSync();
      await bridge.napiStopSync();
      hilog.info(DOMAIN, TAG, 'Sync stopped');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Stop sync failed: %{public}s', error.message);
    }
    RoomListService.subscribed = false;
    RoomListService.initialized = false;
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
      RoomListService.applyDiff(diff);
    }
  }

  /**
   * 应用单个差异
   */
  private static applyDiff(diff: RoomListDiff): void {
    switch (diff.type) {
      case 'reset':
        if (diff.items) {
          RoomListService.rooms = diff.items;
        } else {
          RoomListService.rooms = [];
        }
        break;
      case 'append':
        if (diff.items) {
          RoomListService.rooms = RoomListService.rooms.concat(diff.items);
        }
        break;
      case 'insert':
        if (diff.index !== undefined && diff.item) {
          RoomListService.rooms.splice(diff.index, 0, diff.item);
        }
        break;
      case 'update':
        if (diff.index !== undefined && diff.item) {
          RoomListService.rooms[diff.index] = diff.item;
        }
        break;
      case 'remove':
        if (diff.index !== undefined) {
          RoomListService.rooms.splice(diff.index, 1);
        }
        break;
    }
  }
}