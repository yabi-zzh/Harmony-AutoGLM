/**
 * 设备服务
 * 封装设备控制功能，使用 UITest TCP 协议实现
 * 提供截图、点击、滑动、返回、Home 等设备控制功能
 */

import { HdcClient } from 'hdclib';
import {
  Action,
  ActionType,
  DoubleTapAction,
  DragAction,
  DrawAction,
  LaunchAction,
  LongPressAction,
  PinchInAction,
  PinchOutAction,
  SwipeAction,
  TapAction,
  TypeAction,
  WaitAction
} from '../types/ActionTypes';
import { ConnectionState, DisplayRotationResult, UITestClient } from './UITestClient';
import { common } from '@kit.AbilityKit';

/**
 * 截图结果
 */
export interface ScreenshotResult {
  success: boolean;
  base64Data?: string;
  width?: number;
  height?: number;
  error?: string;
}

/**
 * 执行结果
 */
export interface ExecuteResult {
  success: boolean;
  message?: string;
  error?: string;
}

/**
 * 屏幕尺寸
 */
export interface ScreenSize {
  width: number;
  height: number;
}

/**
 * 应用信息
 */
export interface AppInfo {
  bundleName: string;
  label: string;
}

/**
 * 应用匹配结果
 */
interface AppMatchResult {
  found: boolean;
  bundleName?: string;
  abilityName?: string;
}

/**
 * 命令启动结果
 */
interface LaunchCommandResult {
  success: boolean;
  output?: string;
}

/**
 * 设备服务类
 */
export class DeviceService {
  private static instance: DeviceService | null = null;
  private screenWidth: number = 1080;
  private screenHeight: number = 2340;
  private connId?: string;
  private uitestClient?: UITestClient;
  private installedApps: AppInfo[] = [];
  private currentRotation: number = 0;  // 当前屏幕旋转方向: 0=竖屏, 1=横屏左, 2=竖屏倒置, 3=横屏右

  // 固定截图路径（不再使用时间戳，下次截图自动覆盖）
  private readonly SCREENSHOT_PATH = '/data/local/tmp/agent_screenshot.jpeg';

  private constructor() {}

  /**
   * 获取单例实例
   */
  static getInstance(): DeviceService {
    if (!DeviceService.instance) {
      DeviceService.instance = new DeviceService();
    }
    return DeviceService.instance;
  }

  /**
   * 设置连接 ID
   */
  setConnId(connId?: string): void {
    this.connId = connId;
  }

  /**
   * 初始化 UITest TCP 客户端
   */
  async initUITestClient(context?: common.Context): Promise<boolean> {
    // 如果已经有连接的客户端，检查是否需要重新连接
    if (this.uitestClient) {
      // 检查 connId 是否改变（连接了不同的设备）
      const currentConnId = this.connId || '';
      const clientConnId = this.uitestClient.getConnId();
      
      // 如果 connId 相同且已连接，直接返回
      if (currentConnId === clientConnId && this.uitestClient.getState() === ConnectionState.Connected) {
        return true;
      }
      
      // connId 改变或连接状态异常，需要重新连接
      await this.closeUITestClient();
    }
    
    this.uitestClient = new UITestClient(this.connId, context);
    const connected = await this.uitestClient.connect();
    if (connected) {
      // 获取屏幕尺寸
      await this.fetchScreenSize();
    }
    return connected;
  }

  /**
   * 获取屏幕尺寸（优先 TCP，失败回退 HDC）
   */
  private async fetchScreenSize(): Promise<void> {
    // 方式1: 使用 UITest TCP 协议
    if (this.uitestClient) {
      try {
        const sizeResult = await this.uitestClient.getDisplaySize();
        if (sizeResult.success && sizeResult.width && sizeResult.height) {
          this.screenWidth = sizeResult.width;
          this.screenHeight = sizeResult.height;
          console.info(`DeviceService: Screen ${this.screenWidth}x${this.screenHeight}`);
          return;
        }
      } catch (error) {
        // TCP 获取失败，尝试 HDC
      }
    }

    // 方式2: 回退到 HDC 命令
    try {
      const result = HdcClient.shell("hidumper -s RenderService -a 'screen' | grep 'activeMode:'", this.connId);
      if (result.success) {
        // 解析格式: activeMode: 1260x2720, refreshRate=60
        const match = result.output.match(/activeMode:\s*(\d+)x(\d+)/);
        if (match) {
          this.screenWidth = parseInt(match[1]);
          this.screenHeight = parseInt(match[2]);
          console.info(`DeviceService: Screen ${this.screenWidth}x${this.screenHeight} (HDC)`);
          return;
        }
      }
    } catch (error) {
      // HDC 获取失败
    }

    console.warn(`DeviceService: Using default screen size ${this.screenWidth}x${this.screenHeight}`);
  }

  /**
   * 关闭 UITest TCP 客户端
   */
  async closeUITestClient(): Promise<void> {
    if (this.uitestClient) {
      await this.uitestClient.disconnect();
      this.uitestClient = undefined;
    }
  }

  /**
   * 设置屏幕尺寸
   */
  setScreenSize(width: number, height: number): void {
    this.screenWidth = width;
    this.screenHeight = height;
  }

  /**
   * 获取屏幕尺寸
   */
  async getScreenSize(): Promise<ScreenSize> {
    if (this.uitestClient) {
      const result = await this.uitestClient.getDisplaySize();
      if (result.success && result.width && result.height) {
        this.screenWidth = result.width;
        this.screenHeight = result.height;
      }
    }
    return { width: this.screenWidth, height: this.screenHeight };
  }

  /**
   * 获取屏幕旋转方向
   * @returns rotation: 0=竖屏, 1=横屏左, 2=竖屏倒置, 3=横屏右
   */
  async getDisplayRotation(): Promise<DisplayRotationResult> {
    if (this.uitestClient) {
      const result = await this.uitestClient.getDisplayRotation();
      if (result.success && result.rotation !== undefined) {
        this.currentRotation = result.rotation;
        console.info(`DeviceService: Display rotation = ${this.currentRotation}`);
      }
      return result;
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 获取当前屏幕旋转方向（缓存值）
   */
  getCurrentRotation(): number {
    return this.currentRotation;
  }

  /**
   * 截取屏幕（优化版：使用 -w -h 参数缩小图片 + 固定文件名）
   * 截图前会先获取屏幕旋转方向，根据旋转方向调整宽高
   */
  async takeScreenshot(): Promise<ScreenshotResult> {
    try {
      // 先获取屏幕旋转方向
      await this.getDisplayRotation();
      
      // 根据旋转方向决定截图的宽高
      // rotation 0/2 为竖屏，1/3 为横屏
      const isLandscape = this.currentRotation === 1 || this.currentRotation === 3;
      
      // 计算缩放后的尺寸（原始尺寸的一半）
      let targetWidth: number;
      let targetHeight: number;
      
      if (isLandscape) {
        // 横屏时交换宽高
        targetWidth = Math.round(this.screenHeight / 2);
        targetHeight = Math.round(this.screenWidth / 2);
        console.info(`DeviceService: Landscape mode, screenshot size ${targetWidth}x${targetHeight}`);
      } else {
        // 竖屏正常
        targetWidth = Math.round(this.screenWidth / 2);
        targetHeight = Math.round(this.screenHeight / 2);
      }

      // 截图并指定分辨率
      const captureResult = HdcClient.shell(
        `snapshot_display -f ${this.SCREENSHOT_PATH} -w ${targetWidth} -h ${targetHeight}`,
        this.connId
      );
      if (!captureResult.success) {
        return {
          success: false,
          error: `截图失败: ${captureResult.errorMessage}`
        };
      }

      // 读取截图文件并转为 base64
      const base64Result = HdcClient.shell(`base64 ${this.SCREENSHOT_PATH}`, this.connId);
      if (!base64Result.success) {
        return {
          success: false,
          error: '读取截图失败'
        };
      }

      // 处理 base64 数据
      const base64Data = base64Result.output.replace(/[\r\n\s]/g, '');

      return {
        success: true,
        base64Data: base64Data,
        width: targetWidth,
        height: targetHeight
      };
    } catch (error) {
      return {
        success: false,
        error: `截图异常: ${error}`
      };
    }
  }

  /**
   * 带重试的截图
   */
  async takeScreenshotWithRetry(maxRetries: number = 3): Promise<ScreenshotResult> {
    for (let i = 0; i < maxRetries; i++) {
      const result = await this.takeScreenshot();
      if (result.success) return result;

      console.warn(`DeviceService: Screenshot failed, retry ${i + 1}/${maxRetries}`);
      await new Promise<void>(resolve => setTimeout(resolve, 200));
    }
    return { success: false, error: '截图重试失败' };
  }

  /**
   * 获取页面布局结构
   * @returns 布局 JSON 字符串，失败返回 undefined
   */
  async getPageLayout(): Promise<string | undefined> {
    if (!this.uitestClient) {
      return undefined;
    }
    
    try {
      const result = await this.uitestClient.captureLayout();
      if (result.success && result.layout) {
        return JSON.stringify(result.layout, null, 2);
      }
    } catch (error) {
      console.warn(`DeviceService: Get layout failed: ${error}`);
    }
    return undefined;
  }

  /**
   * 获取当前应用
   */
  async getCurrentApp(): Promise<string> {
    try {
      // 使用 hidumper 获取前台应用信息
      const result = HdcClient.shell('hidumper -s AbilityManagerService -a "-a"', this.connId);
      if (result.success) {
        // 解析 bundle name
        const match = result.output.match(/bundle name\s*\[\s*(\S+)\s*\]/i);
        if (match) {
          return match[1];
        }
        // 备用匹配
        const altMatch = result.output.match(/bundleName\s*[:=]\s*(\S+)/i);
        if (altMatch) {
          return altMatch[1];
        }
      }
      return 'unknown';
    } catch (error) {
      return 'unknown';
    }
  }

  /**
   * 执行动作
   */
  async executeAction(action: Action): Promise<ExecuteResult> {
    console.info(`DeviceService: Execute action - ${action.type}`);
    try {
      switch (action.type) {
        case ActionType.Tap:
          return await this.executeTap(action as TapAction);

        case ActionType.Swipe:
          return await this.executeSwipe(action as SwipeAction);

        case ActionType.Type:
        case ActionType.TypeName:
          return this.executeType(action as TypeAction);

        case ActionType.Launch:
          return await this.executeLaunchWithFallback(action as LaunchAction);

        case ActionType.Back:
          return this.executeBack();

        case ActionType.Home:
          return this.executeHome();

        case ActionType.LongPress:
          return await this.executeLongPress(action as LongPressAction);

        case ActionType.DoubleTap:
          return await this.executeDoubleTap(action as DoubleTapAction);

        case ActionType.Wait:
          return this.executeWait(action as WaitAction);

        case ActionType.Drag:
          return await this.executeDrag(action as DragAction);

        case ActionType.Draw:
          return await this.executeDraw(action as DrawAction);

        case ActionType.PinchIn:
          return await this.executePinchIn(action as PinchInAction);

        case ActionType.PinchOut:
          return await this.executePinchOut(action as PinchOutAction);

        case ActionType.Finish:
          return { success: true, message: '任务完成' };

        default:
          return { success: false, error: `不支持的动作类型: ${action.type}` };
      }
    } catch (error) {
      return { success: false, error: `执行动作异常: ${error}` };
    }
  }

  /**
   * 坐标转换
   * autoglm-phone 模型返回 0-1000 的相对坐标，需要转换为实际屏幕像素坐标
   * 根据屏幕旋转方向调整坐标计算
   */
  private convertCoordinates(element: [number, number]): number[] {
    const relX = element[0];
    const relY = element[1];
    
    // 根据旋转方向调整坐标
    // rotation: 0=竖屏, 1=横屏左, 2=竖屏倒置, 3=横屏右
    let x: number;
    let y: number;
    
    switch (this.currentRotation) {
      case 1:
        // 横屏左（逆时针90度）：交换宽高，x/y 需要转换
        x = Math.round(relX / 1000 * this.screenHeight);
        y = Math.round(relY / 1000 * this.screenWidth);
        break;
      case 2:
        // 竖屏倒置（180度）：坐标反转
        x = Math.round((1000 - relX) / 1000 * this.screenWidth);
        y = Math.round((1000 - relY) / 1000 * this.screenHeight);
        break;
      case 3:
        // 横屏右（顺时针90度）：交换宽高，x/y 需要转换
        x = Math.round(relX / 1000 * this.screenHeight);
        y = Math.round(relY / 1000 * this.screenWidth);
        break;
      default:
        // 竖屏正常（0度）
        x = Math.round(relX / 1000 * this.screenWidth);
        y = Math.round(relY / 1000 * this.screenHeight);
        break;
    }
    
    return [x, y];
  }

  /**
   * 执行点击
   */
  private async executeTap(action: TapAction): Promise<ExecuteResult> {
    const coords = this.convertCoordinates(action.element);
    const x = coords[0];
    const y = coords[1];
    console.info(`DeviceService: Tap (${x}, ${y})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.tap(x, y);
      if (result.success) {
        return { success: true, message: `点击 (${x}, ${y})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行滑动
   */
  private async executeSwipe(action: SwipeAction): Promise<ExecuteResult> {
    const startCoords = this.convertCoordinates(action.start);
    const endCoords = this.convertCoordinates(action.end);
    const startX = startCoords[0];
    const startY = startCoords[1];
    const endX = endCoords[0];
    const endY = endCoords[1];
    console.info(`DeviceService: Swipe (${startX},${startY}) -> (${endX},${endY})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.swipe(startX, startY, endX, endY, 200);
      if (result.success) {
        return { success: true, message: `滑动 (${startX},${startY}) -> (${endX},${endY})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行输入
   */
  private async executeType(action: TypeAction): Promise<ExecuteResult> {
    console.info(`DeviceService: Type "${action.text}"`);
    if (this.uitestClient) {
      const result = await this.uitestClient.inputText(action.text);
      if (result.success) {
        return { success: true, message: `输入: ${action.text}` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行启动应用
   * 策略：
   * 1. 精确匹配已安装应用列表，找到则用 aa start 命令启动
   * 2. 验证启动结果是否真的成功
   * 3. 如果找不到或启动失败，返回特殊结果让调用方执行桌面滑动查找
   */
  private executeLaunch(action: LaunchAction): ExecuteResult {
    console.info(`DeviceService: Launch app "${action.app}"`);
    
    // 步骤1：精确匹配应用名，获取 bundleName
    const matchResult = this.exactMatchApp(action.app);
    
    if (!matchResult.found) {
      console.warn(`DeviceService: App "${action.app}" not found in installed apps, need desktop search`);
      const notFoundResult: ExecuteResult = { 
        success: false, 
        error: `APP_NOT_FOUND:${action.app}`,
        message: `应用"${action.app}"在已安装列表中未找到，需要在桌面滑动查找`
      };
      return notFoundResult;
    }
    
    const bundleName = matchResult.bundleName!;
    const abilityName = matchResult.abilityName;
    console.info(`DeviceService: Matched app "${action.app}" -> ${bundleName}, ability=${abilityName || 'unknown'}`);
    
    // 步骤2：使用 aa start 命令启动应用
    const launchResult = this.launchByCommand(bundleName, abilityName);
    
    if (launchResult.success) {
      console.info(`DeviceService: App "${bundleName}" launched successfully`);
      const successResult: ExecuteResult = { success: true, message: `启动应用成功: ${action.app}` };
      return successResult;
    }
    
    // 步骤3：命令启动失败，返回需要桌面查找
    console.warn(`DeviceService: Command launch failed for "${bundleName}", need desktop search`);
    const failedResult: ExecuteResult = { 
      success: false, 
      error: `LAUNCH_FAILED:${action.app}`,
      message: `应用"${action.app}"命令启动失败，需要在桌面滑动查找`
    };
    return failedResult;
  }

  /**
   * 精确匹配应用名（完全匹配，不做模糊匹配）
   */
  private exactMatchApp(appNameOrBundle: string): AppMatchResult {
    // 如果是 bundleName 格式（包含点号且无中文），直接验证是否存在
    if (appNameOrBundle.includes('.') && !/[\u4e00-\u9fa5]/.test(appNameOrBundle)) {
      const exists = this.installedApps.some(app => app.bundleName === appNameOrBundle);
      if (exists) {
        const abilityName = this.getAbilityName(appNameOrBundle);
        const result: AppMatchResult = { found: true, bundleName: appNameOrBundle, abilityName: abilityName || undefined };
        return result;
      }
      // bundleName 格式但不在列表中，仍尝试获取 abilityName（可能是系统应用）
      const abilityName = this.getAbilityName(appNameOrBundle);
      if (abilityName) {
        const result: AppMatchResult = { found: true, bundleName: appNameOrBundle, abilityName };
        return result;
      }
      const notFound: AppMatchResult = { found: false };
      return notFound;
    }
    
    // 确保已安装应用列表不为空
    if (this.installedApps.length === 0) {
      this.installedApps = this.getInstalledApps();
    }
    
    // 精确匹配应用名（label）
    for (const app of this.installedApps) {
      if (app.label === appNameOrBundle) {
        console.info(`DeviceService: Exact match found "${appNameOrBundle}" -> ${app.bundleName}`);
        const abilityName = this.getAbilityName(app.bundleName);
        const result: AppMatchResult = { found: true, bundleName: app.bundleName, abilityName: abilityName || undefined };
        return result;
      }
    }
    
    const notFound: AppMatchResult = { found: false };
    return notFound;
  }

  /**
   * 使用 aa start 命令启动应用，并验证结果
   */
  private launchByCommand(bundleName: string, abilityName?: string): LaunchCommandResult {
    // 如果有 abilityName，直接使用
    if (abilityName) {
      const result = HdcClient.shell(`aa start -a ${abilityName} -b ${bundleName}`, this.connId);
      if (result.success && result.output.includes('successfully')) {
        const success: LaunchCommandResult = { success: true, output: result.output };
        return success;
      }
    }
    
    // 尝试查询 mainAbility
    const queriedAbility = this.getAbilityName(bundleName);
    if (queriedAbility) {
      const result = HdcClient.shell(`aa start -a ${queriedAbility} -b ${bundleName}`, this.connId);
      if (result.success && result.output.includes('successfully')) {
        const success: LaunchCommandResult = { success: true, output: result.output };
        return success;
      }
    }
    
    // 尝试常见的 abilityName
    const commonAbilities = ['MainAbility', 'EntryAbility'];
    for (const ability of commonAbilities) {
      const result = HdcClient.shell(`aa start -a ${ability} -b ${bundleName}`, this.connId);
      if (result.success && result.output.includes('successfully')) {
        const success: LaunchCommandResult = { success: true, output: result.output };
        return success;
      }
    }
    
    const failed: LaunchCommandResult = { success: false };
    return failed;
  }

  /**
   * 启动应用（带桌面滑动查找降级方案）
   */
  private async executeLaunchWithFallback(action: LaunchAction): Promise<ExecuteResult> {
    // 先尝试命令启动
    const launchResult = this.executeLaunch(action);
    
    // 如果成功，直接返回
    if (launchResult.success) {
      return launchResult;
    }
    
    // 检查是否需要桌面查找（错误信息以 APP_NOT_FOUND 或 LAUNCH_FAILED 开头）
    const needDesktopSearch = launchResult.error?.startsWith('APP_NOT_FOUND:') || 
                              launchResult.error?.startsWith('LAUNCH_FAILED:');
    
    if (!needDesktopSearch) {
      return launchResult;
    }
    
    console.info(`DeviceService: Starting desktop search for "${action.app}"`);
    
    // 执行桌面滑动查找
    const searchResult = await this.searchAppOnDesktop(action.app);
    return searchResult;
  }

  /**
   * 在桌面滑动查找应用
   * 策略：回到桌面，让 AI 模型在后续步骤中识别并点击应用
   * 如果需要滑动，AI 会自己决定
   */
  private async searchAppOnDesktop(appName: string): Promise<ExecuteResult> {
    if (!this.uitestClient) {
      const noClientResult: ExecuteResult = { success: false, error: 'UITest 客户端未初始化，无法执行桌面查找' };
      return noClientResult;
    }

    // 回到桌面
    console.info('DeviceService: Going to home screen for app search');
    const homeResult = await this.uitestClient.pressHome();
    if (!homeResult.success) {
      const homeFailedResult: ExecuteResult = { success: false, error: '回到桌面失败' };
      return homeFailedResult;
    }
    await this.delay(500);

    // 返回特殊状态，告诉调用方已回到桌面
    // 后续由 AI 模型通过截图识别应用图标并点击
    const successResult: ExecuteResult = { 
      success: true, 
      message: `应用"${appName}"未在安装列表中找到，已回到桌面，请在桌面上查找并点击该应用图标` 
    };
    return successResult;
  }

  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * 设置已安装应用列表（供外部调用）
   */
  setInstalledApps(apps: AppInfo[]): void {
    this.installedApps = apps;
    console.info(`DeviceService: Set ${apps.length} installed apps`);
  }

  /**
   * 获取应用的 AbilityName（使用 bm dump 查询 mainAbility）
   */
  private getAbilityName(bundleName: string): string | null {
    try {
      // 使用 bm dump 命令查询应用的 mainAbility
      const result = HdcClient.shell(`bm dump -n ${bundleName} | grep "mainAbility"`, this.connId);
      if (result.success && result.output) {
        // 解析格式: "mainAbility": "EntryAbility",
        const match = result.output.match(/"mainAbility":\s*"([^"]+)"/);
        if (match && match[1]) {
          const abilityName = match[1];
          console.info(`DeviceService: Found abilityName=${abilityName} for ${bundleName}`);
          return abilityName;
        }
      }
    } catch (error) {
      console.error(`DeviceService: getAbilityName error: ${error}`);
    }
    return null;
  }

  /**
   * 获取设备上已安装的应用列表
   */
  getInstalledApps(): AppInfo[] {
    const apps: AppInfo[] = [];
    try {
      const result = HdcClient.shell('bm dump -a -l', this.connId);
      if (result.success && result.output) {
        const jsonStart = result.output.indexOf('[');
        const jsonEnd = result.output.lastIndexOf(']') + 1;
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          const jsonStr = result.output.substring(jsonStart, jsonEnd);
          const parsed = JSON.parse(jsonStr) as AppInfo[];
          for (const app of parsed) {
            apps.push(app);
          }
        }
      }
    } catch (error) {
      console.error(`DeviceService: getInstalledApps error: ${error}`);
    }
    return apps;
  }

  /**
   * 执行返回
   */
  private async executeBack(): Promise<ExecuteResult> {
    console.info('DeviceService: Press Back');
    if (this.uitestClient) {
      const result = await this.uitestClient.pressBack();
      if (result.success) {
        return { success: true, message: '返回' };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行回到桌面
   */
  private async executeHome(): Promise<ExecuteResult> {
    console.info('DeviceService: Press Home');
    if (this.uitestClient) {
      const result = await this.uitestClient.pressHome();
      if (result.success) {
        return { success: true, message: '回到桌面' };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行长按
   */
  private async executeLongPress(action: LongPressAction): Promise<ExecuteResult> {
    const coords = this.convertCoordinates(action.element);
    const x = coords[0];
    const y = coords[1];
    console.info(`DeviceService: LongPress (${x}, ${y})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.longPress(x, y);
      if (result.success) {
        return { success: true, message: `长按 (${x}, ${y})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行双击
   */
  private async executeDoubleTap(action: DoubleTapAction): Promise<ExecuteResult> {
    const coords = this.convertCoordinates(action.element);
    const x = coords[0];
    const y = coords[1];
    console.info(`DeviceService: DoubleTap (${x}, ${y})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.doubleTap(x, y);
      if (result.success) {
        return { success: true, message: `双击 (${x}, ${y})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行等待
   */
  private async executeWait(action: WaitAction): Promise<ExecuteResult> {
    const duration = action.duration * 1000;
    await new Promise<void>(resolve => setTimeout(resolve, duration));
    return { success: true, message: `等待 ${action.duration} 秒` };
  }

  /**
   * 执行拖拽
   */
  private async executeDrag(action: DragAction): Promise<ExecuteResult> {
    const startCoords = this.convertCoordinates(action.start);
    const endCoords = this.convertCoordinates(action.end);
    const startX = startCoords[0];
    const startY = startCoords[1];
    const endX = endCoords[0];
    const endY = endCoords[1];
    console.info(`DeviceService: Drag (${startX},${startY}) -> (${endX},${endY})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.drag(startX, startY, endX, endY);
      if (result.success) {
        return { success: true, message: `拖拽 (${startX},${startY}) -> (${endX},${endY})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行绘制路径
   */
  private async executeDraw(action: DrawAction): Promise<ExecuteResult> {
    if (!action.path || action.path.length < 2) {
      return { success: false, error: '绘制路径至少需要2个点' };
    }

    // 转换所有坐标点
    const convertedPath: [number, number][] = action.path.map(point => {
      const coords = this.convertCoordinates(point);
      return [coords[0], coords[1]];
    });

    console.info(`DeviceService: Draw path with ${convertedPath.length} points`);

    if (this.uitestClient) {
      const result = await this.uitestClient.draw(convertedPath);
      if (result.success) {
        return { success: true, message: `绘制路径 (${convertedPath.length} 个点)` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行捏合缩小
   */
  private async executePinchIn(action: PinchInAction): Promise<ExecuteResult> {
    const centerCoords = this.convertCoordinates(action.center);
    const centerX = centerCoords[0];
    const centerY = centerCoords[1];
    const distance = Math.min(this.screenWidth, this.screenHeight) / 4;
    console.info(`DeviceService: PinchIn at (${centerX},${centerY})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.pinchIn(centerX, centerY, distance);
      if (result.success) {
        return { success: true, message: `捏合缩小 (${centerX},${centerY})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }

  /**
   * 执行捏合放大
   */
  private async executePinchOut(action: PinchOutAction): Promise<ExecuteResult> {
    const centerCoords = this.convertCoordinates(action.center);
    const centerX = centerCoords[0];
    const centerY = centerCoords[1];
    const distance = Math.min(this.screenWidth, this.screenHeight) / 4;
    console.info(`DeviceService: PinchOut at (${centerX},${centerY})`);

    if (this.uitestClient) {
      const result = await this.uitestClient.pinchOut(centerX, centerY, distance);
      if (result.success) {
        return { success: true, message: `捏合放大 (${centerX},${centerY})` };
      }
      return { success: false, error: result.error };
    }
    return { success: false, error: 'UITest 客户端未初始化' };
  }
}
