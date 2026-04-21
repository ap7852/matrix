/**
 * Account 服务 - 用户账户管理
 */

import { getBridge } from './MatrixBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0007;
const TAG = 'AccountService';

export interface UserProfile {
  userId: string;
  displayName?: string;
  avatarUrl?: string;
}

export interface DeviceInfo {
  deviceId: string;
  displayName?: string;
  lastSeenTs?: string;
  lastSeenIp?: string;
  isOwn: boolean;
}

export class AccountService {
  /**
   * 获取当前用户资料
   */
  static async getProfile(): Promise<UserProfile> {
    hilog.info(DOMAIN, TAG, 'getProfile called');
    try {
      const bridge = getBridge();
      const jsonStr: string = await bridge.napiGetProfile() as string;
      const profile: UserProfile = JSON.parse(jsonStr) as UserProfile;
      hilog.info(DOMAIN, TAG, 'Profile: userId=%{public}s, displayName=%{public}s', profile.userId, profile.displayName ?? 'null');
      return profile;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Get profile failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 设置显示名称
   */
  static async setDisplayName(name: string): Promise<void> {
    hilog.info(DOMAIN, TAG, 'setDisplayName called: %{public}s', name);
    try {
      const bridge = getBridge();
      await bridge.napiSetDisplayName(name);
      hilog.info(DOMAIN, TAG, 'Display name set successfully');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Set display name failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 设置头像 URL (需要先上传头像获取 mxc:// URL)
   */
  static async setAvatarUrl(url: string): Promise<void> {
    hilog.info(DOMAIN, TAG, 'setAvatarUrl called: %{public}s', url);
    try {
      const bridge = getBridge();
      await bridge.napiSetAvatarUrl(url);
      hilog.info(DOMAIN, TAG, 'Avatar URL set successfully');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Set avatar URL failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 获取设备列表
   */
  static async getDevices(): Promise<DeviceInfo[]> {
    hilog.info(DOMAIN, TAG, 'getDevices called');
    try {
      const bridge = getBridge();
      const jsonStr: string = await bridge.napiGetDevices() as string;
      const devices: DeviceInfo[] = JSON.parse(jsonStr) as DeviceInfo[];
      hilog.info(DOMAIN, TAG, 'Found %{public}d devices', devices.length);
      return devices;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Get devices failed: %{public}s', error.message);
      throw error;
    }
  }

  /**
   * 删除设备
   */
  static async deleteDevice(deviceId: string): Promise<void> {
    hilog.info(DOMAIN, TAG, 'deleteDevice called: %{public}s', deviceId);
    try {
      const bridge = getBridge();
      await bridge.napiDeleteDevice(deviceId);
      hilog.info(DOMAIN, TAG, 'Device deleted successfully');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Delete device failed: %{public}s', error.message);
      throw error;
    }
  }
}