/**
 * Timeline 数据源 - 用于 LazyForEach
 *
 * 实现 IDataSource 接口，配合 List 组件使用
 */

import { TimelineMessage } from './TimelineModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0003;
const TAG = 'TimelineDataSource';

export class TimelineDataSource implements IDataSource {
  private messages: TimelineMessage[] = [];
  private listeners: DataChangeListener[] = [];

  /**
   * 更新消息列表
   * 用于完整替换消息列表（如 Reset 更新）
   */
  updateMessages(messages: TimelineMessage[]): void {
    this.messages = messages;
    this.notifyAllListeners();
  }

  /**
   * 追加消息
   * 用于新消息到达
   */
  appendMessages(messages: TimelineMessage[]): void {
    this.messages = this.messages.concat(messages);
    this.notifyDataAdded(this.messages.length - messages.length);
  }

  /**
   * 插入消息
   * 用于指定位置插入（如本地 echo）
   */
  insertMessage(index: number, message: TimelineMessage): void {
    if (index >= 0 && index <= this.messages.length) {
      this.messages.splice(index, 0, message);
      this.notifyDataAdded(index);
    }
  }

  /**
   * 更新单条消息
   * 用于消息发送状态变化或内容更新
   */
  updateMessage(index: number, message: TimelineMessage): void {
    if (index >= 0 && index < this.messages.length) {
      this.messages[index] = message;
      this.notifyDataChanged(index);
    }
  }

  /**
   * 移除消息
   */
  removeMessage(index: number): void {
    if (index >= 0 && index < this.messages.length) {
      this.messages.splice(index, 1);
      this.notifyDataDeleted(index);
    }
  }

  /**
   * 清空消息
   */
  clear(): void {
    this.messages = [];
    this.notifyAllListeners();
  }

  /**
   * 通知所有监听器数据已重载
   */
  private notifyAllListeners(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }

  /**
   * 通知监听器新增数据
   */
  private notifyDataAdded(index: number): void {
    for (const listener of this.listeners) {
      listener.onDataAdd(index);
    }
  }

  /**
   * 通知监听器数据变化
   */
  private notifyDataChanged(index: number): void {
    for (const listener of this.listeners) {
      listener.onDataChange(index);
    }
  }

  /**
   * 通知监听器数据删除
   */
  private notifyDataDeleted(index: number): void {
    for (const listener of this.listeners) {
      listener.onDataDelete(index);
    }
  }

  /**
   * 获取数据总数
   */
  totalCount(): number {
    return this.messages.length;
  }

  /**
   * 获取指定索引的数据
   */
  getData(index: number): TimelineMessage {
    if (index < 0 || index >= this.messages.length) {
      hilog.error(DOMAIN, TAG, 'Invalid index: %{public}d', index);
      // 返回一个空消息占位符
      return {
        eventId: undefined,
        senderId: '',
        senderName: '',
        content: { type: 'unsupported' },
        timestamp: '',
        isOwn: false,
        sendState: 'sent',
      };
    }
    return this.messages[index];
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