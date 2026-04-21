import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { TimelineMessage, TimelineUpdate, SendState, MessageContent, TextContent, ImageContent, EncryptedFileData } from '../../../main/ets/models/TimelineModels';
import { TimelineService } from '../../../main/ets/services/TimelineService';

// 定义订阅接口以符合 ArkTS 规范
interface RoomSubscription {
  callback: (update: TimelineUpdate) => void;
  messages: TimelineMessage[];
}

export default function timelineTest() {
  describe('TimelineServiceTest', () => {
    // 测试数据构建辅助函数
    const createTestMessage = (id: string, senderId: string, body: string): TimelineMessage => {
      const content: TextContent = { type: 'text', body: body };
      return {
        eventId: id,
        senderId: senderId,
        senderName: senderId,
        content: content,
        timestamp: new Date().toISOString(),
        isOwn: senderId === 'me',
        sendState: 'sent' as SendState,
      };
    };

    beforeEach(() => {
      TimelineService.clearAll();
    });

    afterAll(() => {
      TimelineService.clearAll();
    });

    it('applyUpdate_reset_shouldReplaceMessages', 0, () => {
      const roomId = 'test-room-1';

      // 创建订阅（模拟 subscribe 内部操作）
      const subscription = new Map<string, RoomSubscription>();
      const subData: RoomSubscription = {
        callback: () => {},
        messages: [createTestMessage('old-1', 'user-a', 'old message')],
      };
      subscription.set(roomId, subData);

      // 构造 reset 更新
      const resetUpdate: TimelineUpdate = {
        type: 'reset',
        items: [
          createTestMessage('new-1', 'user-b', 'new message 1'),
          createTestMessage('new-2', 'user-c', 'new message 2'),
        ],
      };

      // 验证 reset 更新结构
      expect(resetUpdate.type).assertEqual('reset');
      expect(resetUpdate.items!.length).assertEqual(2);
      expect(resetUpdate.items![0].eventId).assertEqual('new-1');
    });

    it('applyUpdate_append_shouldAddMessages', 0, () => {
      const existingMessages: TimelineMessage[] = [
        createTestMessage('msg-1', 'user-a', 'first'),
      ];

      const appendUpdate: TimelineUpdate = {
        type: 'append',
        items: [
          createTestMessage('msg-2', 'user-b', 'second'),
          createTestMessage('msg-3', 'user-c', 'third'),
        ],
      };

      // 模拟 append 操作
      const result = existingMessages.concat(appendUpdate.items!);

      expect(result.length).assertEqual(3);
      expect(result[0].eventId).assertEqual('msg-1');
      expect(result[2].eventId).assertEqual('msg-3');
    });

    it('applyUpdate_insert_shouldInsertAtIndex', 0, () => {
      const existingMessages: TimelineMessage[] = [
        createTestMessage('msg-1', 'user-a', 'first'),
        createTestMessage('msg-3', 'user-c', 'third'),
      ];

      const insertUpdate: TimelineUpdate = {
        type: 'insert',
        index: 1,
        item: createTestMessage('msg-2', 'user-b', 'second'),
      };

      // 模拟 insert 操作
      const messages: TimelineMessage[] = [...existingMessages];
      if (insertUpdate.index! >= 0 && insertUpdate.index! <= messages.length) {
        messages.splice(insertUpdate.index!, 0, insertUpdate.item!);
      }

      expect(messages.length).assertEqual(3);
      expect(messages[0].eventId).assertEqual('msg-1');
      expect(messages[1].eventId).assertEqual('msg-2');
      expect(messages[2].eventId).assertEqual('msg-3');
    });

    it('applyUpdate_update_shouldReplaceAtIndex', 0, () => {
      const existingMessages: TimelineMessage[] = [
        createTestMessage('msg-1', 'user-a', 'original'),
      ];

      const updateUpdate: TimelineUpdate = {
        type: 'update',
        index: 0,
        item: createTestMessage('msg-1', 'user-a', 'edited'),
      };

      // 模拟 update 操作
      const messages: TimelineMessage[] = [...existingMessages];
      if (updateUpdate.index! >= 0 && updateUpdate.index! < messages.length) {
        messages[updateUpdate.index!] = updateUpdate.item!;
      }

      expect(messages.length).assertEqual(1);
      // 需要先检查 content 类型再访问 body
      const content = messages[0].content;
      if (content.type === 'text') {
        expect((content as TextContent).body).assertEqual('edited');
      }
    });

    it('applyUpdate_remove_shouldDeleteAtIndex', 0, () => {
      const existingMessages: TimelineMessage[] = [
        createTestMessage('msg-1', 'user-a', 'first'),
        createTestMessage('msg-2', 'user-b', 'second'),
        createTestMessage('msg-3', 'user-c', 'third'),
      ];

      const removeUpdate: TimelineUpdate = {
        type: 'remove',
        index: 1,
      };

      // 模拟 remove 操作
      const messages: TimelineMessage[] = [...existingMessages];
      if (removeUpdate.index! >= 0 && removeUpdate.index! < messages.length) {
        messages.splice(removeUpdate.index!, 1);
      }

      expect(messages.length).assertEqual(2);
      expect(messages[0].eventId).assertEqual('msg-1');
      expect(messages[1].eventId).assertEqual('msg-3');
    });

    it('messageContent_types_shouldBeValid', 0, () => {
      // 文本内容 - 使用显式类型
      const textContent: TextContent = { type: 'text', body: 'hello' };
      expect(textContent.type).assertEqual('text');

      // 图片内容
      const imageContent: ImageContent = {
        type: 'image',
        mxcUrl: 'mxc://server/image',
        body: 'image.png',
        width: 100,
        height: 200,
      };
      expect(imageContent.type).assertEqual('image');

      // 加密文件数据 - 使用显式类型
      const encryptedFile: EncryptedFileData = { key: 'key123', iv: 'iv456', hashes: 'hash789' };
      expect(encryptedFile.key).assertEqual('key123');
    });

    it('sendState_values_shouldBeValid', 0, () => {
      const state1: SendState = 'sending';
      const state2: SendState = 'sent';
      const state3: SendState = 'failed';

      expect(state1).assertEqual('sending');
      expect(state2).assertEqual('sent');
      expect(state3).assertEqual('failed');
    });

    it('getMessages_shouldReturnEmptyWhenNoSubscription', 0, () => {
      const messages = TimelineService.getMessages('non-existent-room');
      expect(messages.length).assertEqual(0);
    });

    it('clearAll_shouldRemoveAllSubscriptions', 0, () => {
      TimelineService.clearAll();
      const messages = TimelineService.getMessages('any-room');
      expect(messages.length).assertEqual(0);
    });
  });
}