import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * 后台任务管理器
 * 用于管理应用的长时任务，保持应用在后台持续运行
 */
export class BackgroundTaskManager {
  private static instance: BackgroundTaskManager;
  private context: Context | null = null;
  private isRunning: boolean = false;

  private constructor() {}

  public static getInstance(): BackgroundTaskManager {
    if (!BackgroundTaskManager.instance) {
      BackgroundTaskManager.instance = new BackgroundTaskManager();
    }
    return BackgroundTaskManager.instance;
  }

  /**
   * 初始化上下文
   * @param context 应用上下文
   */
  public init(context: Context): void {
    this.context = context;
  }

  /**
   * 启动后台长时任务
   * @returns Promise<boolean> 是否启动成功
   */
  public async startBackgroundTask(): Promise<boolean> {
    if (this.isRunning) {
      console.info('[BackgroundTaskManager] 后台任务已在运行中');
      return true;
    }

    if (!this.context) {
      console.error('[BackgroundTaskManager] 上下文未初始化');
      return false;
    }

    try {
      // 创建 WantAgent 用于点击通知时返回应用
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: 'io.github.yabizzh.autoglm',
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };

      const agent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);

      // 启动长时任务
      await backgroundTaskManager.startBackgroundRunning(
        this.context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      );

      this.isRunning = true;
      console.info('[BackgroundTaskManager] 后台任务启动成功');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[BackgroundTaskManager] 启动后台任务失败: ${err.code}, ${err.message}`);
      return false;
    }
  }

  /**
   * 停止后台长时任务
   * @returns Promise<boolean> 是否停止成功
   */
  public async stopBackgroundTask(): Promise<boolean> {
    if (!this.isRunning) {
      console.info('[BackgroundTaskManager] 后台任务未在运行');
      return true;
    }

    if (!this.context) {
      console.error('[BackgroundTaskManager] 上下文未初始化');
      return false;
    }

    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      this.isRunning = false;
      console.info('[BackgroundTaskManager] 后台任务已停止');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      console.error(`[BackgroundTaskManager] 停止后台任务失败: ${err.code}, ${err.message}`);
      return false;
    }
  }

  /**
   * 检查后台任务是否正在运行
   */
  public isBackgroundRunning(): boolean {
    return this.isRunning;
  }
}

export default BackgroundTaskManager.getInstance();
