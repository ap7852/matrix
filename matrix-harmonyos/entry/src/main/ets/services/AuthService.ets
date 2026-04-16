/**
 * 认证服务 - NAPI 调用封装
 */

import { getBridge } from './MatrixBridge';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SessionData } from '../models/AuthModels';
import { common } from '@kit.AbilityKit';

export { SessionData } from '../models/AuthModels';

const DOMAIN = 0x0001;
const TAG = 'AuthService';

export class AuthService {
  private static session: SessionData | null = null;
  private static dataDir: string = '';

  /**
   * 初始化数据目录
   */
  static init(context: common.UIAbilityContext): void {
    AuthService.dataDir = context.filesDir;
    hilog.info(DOMAIN, TAG, 'Data directory: %{public}s', AuthService.dataDir);
  }

  /**
   * 密码登录
   */
  static async loginWithPassword(
    homeserver: string,
    username: string,
    password: string
  ): Promise<SessionData | null> {
    try {
      if (!AuthService.dataDir) {
        throw new Error('AuthService not initialized, call init() first');
      }
      const bridge = getBridge();
      const json: string = await bridge.napiLoginPassword(homeserver, username, password, AuthService.dataDir);
      const session: SessionData = JSON.parse(json) as SessionData;
      AuthService.session = session;
      hilog.info(DOMAIN, TAG, 'Login successful: %{public}s', session.userId);
      return session;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Login failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * 检查是否有会话
   */
  static hasSession(): boolean {
    const bridge = getBridge();
    return bridge.napiHasSession();
  }

  /**
   * 恢复会话
   */
  static async restoreSession(): Promise<SessionData | null> {
    try {
      if (!AuthService.dataDir) {
        throw new Error('AuthService not initialized');
      }
      const bridge = getBridge();
      const json: string = await bridge.napiRestoreSession(AuthService.dataDir);
      const session: SessionData = JSON.parse(json) as SessionData;
      AuthService.session = session;
      return session;
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Restore session failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * 登出
   */
  static async logout(): Promise<void> {
    try {
      if (!AuthService.dataDir) {
        throw new Error('AuthService not initialized');
      }
      const bridge = getBridge();
      await bridge.napiLogout(AuthService.dataDir);
      AuthService.session = null;
      hilog.info(DOMAIN, TAG, 'Logout successful');
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, 'Logout failed: %{public}s', error.message);
    }
  }

  /**
   * 获取当前会话
   */
  static getSession(): SessionData | null {
    return AuthService.session;
  }
}