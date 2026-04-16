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
  type: 'Insert' | 'Update' | 'Remove' | 'Clear';
  index?: number;
  item?: RoomSummary;
}

export interface RoomListUpdate {
  diffs: RoomListDiff[];
}