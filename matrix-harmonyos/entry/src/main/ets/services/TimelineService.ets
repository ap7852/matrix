/**
 * Timeline 服务层
 *
 * 封装 Rust NAPI 调用，管理消息时间线
 */

import { getBridge } from './MatrixBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TimelineMessage, TimelineUpdate } from '../models/TimelineModels';

const DOMAIN = 0x0003;
const TAG = 'TimelineService';

// 房间订阅回调类型
type TimelineCallback = (update: TimelineUpdate) => void;

// 房间订阅状态
interface RoomSubscription {
  callback: TimelineCallback;
  messages: TimelineMessage[];
}

export class TimelineService {
  // 每个房间独立的订阅
  private static subscriptions: Map<string, RoomSubscription> = new Map();

  /**
   * 初始化房间 Timeline
   * 进入房间时调用
   */
  static async init(roomId: string): Promise<void> {
    try {
      const bridge = getBridge();
      await bridge.napiInitTimeline(roomId);
      hilog.info(DOMAIN, TAG, 'Timeline initialized for room: %{public}s', roomId);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Init timeline failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 订阅 Timeline 更新
   * 使用 ThreadSafeFunction 实现实时推送
   */
  static subscribe(roomId: string, callback: TimelineCallback): void {
    // 如果已有订阅，先移除
    if (TimelineService.subscriptions.has(roomId)) {
      hilog.warn(DOMAIN, TAG, 'Replacing existing subscription for room: %{public}s', roomId);
      TimelineService.subscriptions.delete(roomId);
    }

    // 创建订阅记录
    TimelineService.subscriptions.set(roomId, {
      callback,
      messages: [],
    });

    try {
      const bridge = getBridge();
      bridge.napiSubscribeTimeline(roomId, (json: string) => {
        const update = JSON.parse(json) as TimelineUpdate;
        const subscription = TimelineService.subscriptions.get(roomId);
        if (subscription) {
          TimelineService.applyUpdate(roomId, update);
          subscription.callback(update);
        }
      });
      hilog.info(DOMAIN, TAG, 'Timeline subscribed for room: %{public}s', roomId);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Subscribe timeline failed: %{public}s', error.message);
      TimelineService.subscriptions.delete(roomId);
      throw error;
    }
  }

  /**
   * 取消订阅
   * 离开房间时调用
   */
  static unsubscribe(roomId: string): void {
    if (TimelineService.subscriptions.has(roomId)) {
      TimelineService.subscriptions.delete(roomId);
      hilog.info(DOMAIN, TAG, 'Timeline unsubscribed for room: %{public}s', roomId);
    }
  }

  /**
   * 发送文本消息
   */
  static async sendText(roomId: string, text: string, replyTo?: string): Promise<void> {
    try {
      const bridge = getBridge();
      await bridge.napiSendText(roomId, text, replyTo ?? null);
      hilog.info(DOMAIN, TAG, 'Text message sent to room: %{public}s', roomId);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Send text failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 分页加载历史消息
   * @returns 是否还有更多消息
   */
  static async paginateBackwards(roomId: string): Promise<boolean> {
    try {
      const bridge = getBridge();
      const result: boolean = await bridge.napiPaginateBackwards(roomId) as boolean;
      hilog.info(DOMAIN, TAG, 'Paginated backwards for room: %{public}s, more: %{public}s', roomId, result.toString());
      return result;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Paginate backwards failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 发送已读回执
   */
  static async sendReadReceipt(roomId: string, eventId: string): Promise<void> {
    try {
      const bridge = getBridge();
      await bridge.napiSendReadReceipt(roomId, eventId);
      hilog.debug(DOMAIN, TAG, 'Read receipt sent for event: %{public}s', eventId);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Send read receipt failed: %{public}s', error.message);
      // 不抛出异常，已读回执失败不影响用户体验
    }
  }

  /**
   * 获取房间的消息列表
   */
  static getMessages(roomId: string): TimelineMessage[] {
    const subscription = TimelineService.subscriptions.get(roomId);
    return subscription ? subscription.messages : [];
  }

  /**
   * 应用更新到本地消息列表
   */
  static applyUpdate(roomId: string, update: TimelineUpdate): void {
    const subscription = TimelineService.subscriptions.get(roomId);
    if (!subscription) {
      hilog.warn(DOMAIN, TAG, 'No subscription for room: %{public}s', roomId);
      return;
    }

    switch (update.type) {
      case 'reset':
        subscription.messages = [...update.items];
        break;

      case 'append':
        subscription.messages = subscription.messages.concat(update.items);
        break;

      case 'insert':
        if (update.index >= 0 && update.index <= subscription.messages.length) {
          subscription.messages.splice(update.index, 0, update.item);
        }
        break;

      case 'update':
        if (update.index >= 0 && update.index < subscription.messages.length) {
          subscription.messages[update.index] = update.item;
        }
        break;

      case 'remove':
        if (update.index >= 0 && update.index < subscription.messages.length) {
          subscription.messages.splice(update.index, 1);
        }
        break;
    }

    hilog.debug(DOMAIN, TAG, 'Applied %{public}s update, messages count: %{public}d', update.type, subscription.messages.length);
  }

  /**
   * 清理所有订阅
   * 退出登录时调用
   */
  static clearAll(): void {
    TimelineService.subscriptions.clear();
    hilog.info(DOMAIN, TAG, 'All subscriptions cleared');
  }
}