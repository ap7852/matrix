import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { RoomSummary, RoomListDiff, RoomListUpdate, RoomMember } from '../../../main/ets/models/RoomModels';

export default function roomTest() {
  describe('RoomModelsTest', () => {
    // 测试数据构建辅助函数 - 返回显式类型
    const createTestRoom = (id: string, name: string, unread: number): RoomSummary => {
      const room: RoomSummary = {
        roomId: id,
        name: name,
        unreadCount: unread,
        isEncrypted: true,
      };
      return room;
    };

    const createTestMember = (userId: string, displayName: string): RoomMember => {
      const member: RoomMember = {
        userId: userId,
        displayName: displayName,
        membership: 'join',
        isOwn: userId === '@me:server',
      };
      return member;
    };

    it('roomSummary_shouldHaveRequiredFields', 0, () => {
      const room: RoomSummary = createTestRoom('!room1:server', 'Test Room', 5);

      expect(room.roomId).assertEqual('!room1:server');
      expect(room.name).assertEqual('Test Room');
      expect(room.unreadCount).assertEqual(5);
      expect(room.isEncrypted).assertEqual(true);
    });

    it('roomSummary_shouldHaveOptionalFields', 0, () => {
      const room: RoomSummary = {
        roomId: '!room2:server',
        name: 'DM Room',
        avatarUrl: 'mxc://server/avatar',
        lastMessage: 'Hello',
        timestamp: '2024-01-01T00:00:00Z',
        unreadCount: 0,
        isEncrypted: true,
      };

      expect(room.avatarUrl!).assertEqual('mxc://server/avatar');
      expect(room.lastMessage!).assertEqual('Hello');
      expect(room.timestamp!).assertEqual('2024-01-01T00:00:00Z');
    });

    it('roomListDiff_reset_shouldContainItems', 0, () => {
      const items: RoomSummary[] = [
        createTestRoom('!room1:server', 'Room 1', 0),
        createTestRoom('!room2:server', 'Room 2', 3),
      ];
      const diff: RoomListDiff = {
        type: 'reset',
        items: items,
      };

      expect(diff.type).assertEqual('reset');
      expect(diff.items!.length).assertEqual(2);
      expect(diff.items![0].roomId).assertEqual('!room1:server');
    });

    it('roomListDiff_insert_shouldContainIndexAndItem', 0, () => {
      const diff: RoomListDiff = {
        type: 'insert',
        index: 2,
        item: createTestRoom('!new:server', 'New Room', 1),
      };

      expect(diff.type).assertEqual('insert');
      expect(diff.index!).assertEqual(2);
      expect(diff.item!.roomId).assertEqual('!new:server');
    });

    it('roomListDiff_update_shouldReplaceAtIndex', 0, () => {
      const diff: RoomListDiff = {
        type: 'update',
        index: 0,
        item: createTestRoom('!room1:server', 'Updated Name', 5),
      };

      expect(diff.type).assertEqual('update');
      expect(diff.item!.name).assertEqual('Updated Name');
    });

    it('roomListDiff_remove_shouldHaveIndex', 0, () => {
      const diff: RoomListDiff = {
        type: 'remove',
        index: 3,
      };

      expect(diff.type).assertEqual('remove');
      expect(diff.index!).assertEqual(3);
    });

    it('roomListDiff_append_shouldAddToEnd', 0, () => {
      const items: RoomSummary[] = [createTestRoom('!new:server', 'New Room', 0)];
      const diff: RoomListDiff = {
        type: 'append',
        items: items,
      };

      expect(diff.type).assertEqual('append');
      expect(diff.items!.length).assertEqual(1);
    });

    it('roomListUpdate_shouldContainDiffs', 0, () => {
      const diffs: RoomListDiff[] = [
        { type: 'reset', items: [createTestRoom('!room1:server', 'Room 1', 0)] },
        { type: 'append', items: [createTestRoom('!room2:server', 'Room 2', 0)] },
      ];
      const update: RoomListUpdate = {
        diffs: diffs,
      };

      expect(update.diffs.length).assertEqual(2);
      expect(update.diffs[0].type).assertEqual('reset');
      expect(update.diffs[1].type).assertEqual('append');
    });

    it('roomMember_shouldHaveRequiredFields', 0, () => {
      const member: RoomMember = createTestMember('@user:server', 'User Name');

      expect(member.userId).assertEqual('@user:server');
      expect(member.displayName!).assertEqual('User Name');
      expect(member.membership).assertEqual('join');
      expect(member.isOwn).assertEqual(false);
    });

    it('roomMember_ownUser_shouldHaveIsOwnTrue', 0, () => {
      const member: RoomMember = createTestMember('@me:server', 'Me');

      expect(member.isOwn).assertEqual(true);
    });

    it('roomMember_withAvatar_shouldHaveOptionalFields', 0, () => {
      const member: RoomMember = {
        userId: '@user:server',
        displayName: 'User',
        avatarUrl: 'mxc://server/avatar',
        membership: 'join',
        isOwn: false,
      };

      expect(member.avatarUrl!).assertEqual('mxc://server/avatar');
    });

    it('roomMember_membershipValues_shouldBeValid', 0, () => {
      const memberships: string[] = ['join', 'invite', 'leave', 'ban'];

      for (const membership of memberships) {
        const member: RoomMember = {
          userId: '@user:server',
          membership: membership,
          isOwn: false,
        };
        expect(member.membership).assertEqual(membership);
      }
    });
  });
}