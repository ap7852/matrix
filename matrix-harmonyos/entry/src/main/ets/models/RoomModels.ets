/**
 * 房间数据模型
 */

export interface RoomSummary {
  roomId: string;
  name: string;
  avatarUrl?: string;
  lastMessage?: string;
  timestamp?: string;
  unreadCount: number;
  isEncrypted: boolean;
}

export interface RoomListDiff {
  type: 'reset' | 'insert' | 'update' | 'remove' | 'append';
  index?: number;
  items?: RoomSummary[];  // 用于 reset 和 append
  item?: RoomSummary;     // 用于 insert 和 update
}

export interface RoomListUpdate {
  diffs: RoomListDiff[];
}