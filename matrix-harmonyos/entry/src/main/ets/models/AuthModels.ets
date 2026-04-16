/**
 * 认证数据模型
 */

export interface SessionData {
  userId: string;
  deviceId: string;
  accessToken: string;
  homeserverUrl: string;
}

export interface LoginRequest {
  homeserver: string;
  username: string;
  password: string;
}