/**
 * 启动页
 * 负责 HDC 初始化和密钥创建
 */
import { common } from '@kit.AbilityKit';
import { HdcClient, HdcErrorCode } from 'hdclib';
import { APP_CONFIG } from '../models';

@Entry
@Component
struct SplashPage {
  @State logoScale: number = 0.8;
  @State logoOpacity: number = 0;
  @State statusText: string = '';
  private uiContext: UIContext | undefined;
  private context: common.UIAbilityContext | undefined;
  private minDisplayTime: number = APP_CONFIG.ui.splashDuration;
  private startTime: number = 0;

  aboutToAppear(): void {
    this.startTime = Date.now();

    // 延迟初始化 HDC，确保 NAPI 模块加载完成
    setTimeout(() => {
      this.initHdc();
    }, 100);
  }

  onPageShow(): void {
    // 获取 UIContext 用于动画和路由
    this.uiContext = this.getUIContext();
    this.context = this.uiContext?.getHostContext() as common.UIAbilityContext;

    // 启动动画
    this.uiContext?.animateTo({
      duration: 400,
      curve: Curve.EaseOut
    }, () => {
      this.logoScale = 1;
      this.logoOpacity = 1;
    });
  }

  /**
   * 初始化 HDC 客户端
   */
  private async initHdc(): Promise<void> {
    this.statusText = '正在初始化...';

    try {
      const sandboxPath = this.context?.filesDir ?? '';
      const resourceManager = this.context?.resourceManager;
      console.info(`SplashPage: initHdc sandboxPath=${sandboxPath}`);

      if (!resourceManager) {
        throw new Error('resourceManager is undefined');
      }

      const result = await HdcClient.initWithPresetKeys(resourceManager, sandboxPath, 3);
      console.info(`SplashPage: HdcClient.initWithPresetKeys result=${result}`);

      if (result === HdcErrorCode.SUCCESS || result === 0) {
        AppStorage.setOrCreate('hdcInitialized', true);
        HdcClient.setHostname('Next AI Agent');
        console.info(`SplashPage: HDC version=${HdcClient.version()}`);
        this.statusText = '初始化完成';
      } else {
        AppStorage.setOrCreate('hdcInitialized', false);
        AppStorage.setOrCreate('hdcInitError', `初始化失败: ${result}`);
        this.statusText = '初始化失败';
      }
    } catch (error) {
      AppStorage.setOrCreate('hdcInitialized', false);
      AppStorage.setOrCreate('hdcInitError', `初始化异常: ${error}`);
      this.statusText = '初始化异常';
    }

    this.navigateToIndex();
  }

  /**
   * 跳转到主页，确保最少显示时间
   */
  private navigateToIndex(): void {
    const elapsed = Date.now() - this.startTime;
    const remaining = Math.max(0, this.minDisplayTime - elapsed);

    setTimeout(() => {
      this.uiContext?.getRouter().replaceUrl({ url: 'pages/Index' }).catch((err: Error) => {
        console.error(`SplashPage: navigateToIndex error: ${err.message}`);
      });
    }, remaining);
  }

  build() {
    Column() {
      Image($r('app.media.foreground'))
        .width(120)
        .height(120)
        .borderRadius(28)
        .scale({ x: this.logoScale, y: this.logoScale })
        .opacity(this.logoOpacity)
        .shadow({
          radius: 24,
          color: 'rgba(52, 120, 246, 0.2)',
          offsetY: 8
        })

      Text('Next AI Agent')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1F2937')
        .margin({ top: 24 })
        .opacity(this.logoOpacity)

      if (this.statusText) {
        Text(this.statusText)
          .fontSize(12)
          .fontColor('#9CA3AF')
          .margin({ top: 12 })
          .opacity(this.logoOpacity)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .justifyContent(FlexAlign.Center)
  }
}
