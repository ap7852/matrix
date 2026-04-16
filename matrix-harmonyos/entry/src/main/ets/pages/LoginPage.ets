/**
 * 登录页面
 */

import { AuthService } from '../services/AuthService';
import { SessionData } from '../services/AuthService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'LoginPage';

@Entry
@Component
export struct LoginPage {
  @State homeserver: string = 'matrix.org';
  @State username: string = '';
  @State password: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  @Consume('navPathStack') navPathStack: NavPathStack;
  @Consume('isAuthenticated') isAuthenticated: boolean;

  private async handleLogin(): Promise<void> {
    if (this.isLoading) return;
    if (!this.username || !this.password) {
      this.errorMessage = '请输入用户名和密码';
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    const session = await AuthService.loginWithPassword(
      this.homeserver,
      this.username,
      this.password
    );

    this.isLoading = false;

    if (session) {
      hilog.info(DOMAIN, TAG, 'Login successful: %{public}s', session.userId);
      this.isAuthenticated = true;
    } else {
      this.errorMessage = '登录失败，请检查用户名和密码';
    }
  }

  build() {
    Column() {
      Text('Element X')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 32 })

      TextInput({ placeholder: '服务器地址 (如 matrix.org)', text: this.homeserver })
        .onChange((value: string) => this.homeserver = value)
        .width('80%')
        .margin({ bottom: 16 })

      TextInput({ placeholder: '用户名 (@user:server.com)', text: this.username })
        .onChange((value: string) => this.username = value)
        .width('80%')
        .margin({ bottom: 16 })

      TextInput({ placeholder: '密码', text: this.password })
        .type(InputType.Password)
        .onChange((value: string) => this.password = value)
        .width('80%')
        .margin({ bottom: 24 })

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor('#FF5252')
          .margin({ bottom: 16 })
      }

      Button(this.isLoading ? '登录中...' : '登录')
        .width('80%')
        .enabled(!this.isLoading && this.username.length > 0 && this.password.length > 0)
        .onClick(() => this.handleLogin())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding(20)
  }
}