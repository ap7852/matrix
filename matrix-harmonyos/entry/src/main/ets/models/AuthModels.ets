/**
 * 认证数据模型
 * 参考 Element X Android: 每个用户有独立的 sessionPath 和 cachePath
 */

export interface SessionData {
  userId: string;
  deviceId: string;
  accessToken: string;
  homeserverUrl: string;
  /** 会话数据目录路径（SQLite store） */
  sessionPath: string;
  /** 缓存目录路径 */
  cachePath: string;
}

export interface LoginRequest {
  homeserver: string;
  username: string;
  password: string;
}