/**
 * Room 服务 - 房间成员等功能
 */

import { getBridge } from './MatrixBridge';
import { RoomMember, RoomDetails } from '../models/RoomModels';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0003;
const TAG = 'RoomService';

export class RoomService {
  /**
   * 获取房间详情（包括实时名称）
   */
  static async getDetails(roomId: string): Promise<RoomDetails> {
    hilog.info(DOMAIN, TAG, 'getDetails called for room: %{public}s', roomId);
    try {
      const bridge = getBridge();
      const jsonStr: string = await bridge.napiGetRoomDetails(roomId) as string;
      hilog.debug(DOMAIN, TAG, 'Room details JSON: %{public}s', jsonStr);
      const details: RoomDetails = JSON.parse(jsonStr) as RoomDetails;
      hilog.info(DOMAIN, TAG, 'Room details: name=%{public}s, isDirect=%{public}s', details.name, details.isDirect.toString());
      return details;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Get details failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 获取房间成员列表
   */
  static async getMembers(roomId: string): Promise<RoomMember[]> {
    hilog.info(DOMAIN, TAG, 'getMembers called for room: %{public}s', roomId);
    try {
      const bridge = getBridge();
      hilog.info(DOMAIN, TAG, 'Calling napiGetRoomMembers...');
      // NAPI 返回单个 JSON 字符串
      const jsonStr: string = await bridge.napiGetRoomMembers(roomId) as string;
      hilog.info(DOMAIN, TAG, 'NAPI returned JSON string length: %{public}d', jsonStr.length);
      hilog.debug(DOMAIN, TAG, 'NAPI returned JSON: %{public}s', jsonStr.substring(0, 200));
      const members: RoomMember[] = JSON.parse(jsonStr) as RoomMember[];
      hilog.info(DOMAIN, TAG, 'Parsed %{public}d members', members.length);
      return members;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Get members failed: %{public}s', error.message);
      hilog.error(DOMAIN, TAG, 'Error stack: %{public}s', error.stack ?? 'no stack');
      throw error;
    }
  }
}