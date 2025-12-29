/**
 * TaskViewModel - Task 页面的 ViewModel
 * 
 * 负责管理 Task 页面的 UI 状态和 AI 任务执行业务逻辑。
 * 使用 SimpleAgent 极简架构，最少AI调用。
 */

import { common } from '@kit.AbilityKit';
import { SimpleAgent } from '../agent/core/SimpleAgent';
import { Action } from '../agent/types/ActionTypes';
import { ConfigManager } from '../agent/storage/ConfigManager';
import { AppInfo, DeviceService, ScreenSize } from '../agent/device/DeviceService';
import {
  ChatMessage,
  DEFAULT_MODEL_CONFIG,
  MessageType,
  ModelConfig,
  STATUS_COLORS,
  STATUS_TEXTS,
  TaskStatus
} from '../models';

// 重新导出 ChatMessage 和 MessageType 以保持向后兼容
export { ChatMessage, MessageType } from '../models';

@Observed
export class TaskViewModel {
  // UI 状态属性
  messages: ChatMessage[] = [];
  inputText: string = '';
  taskStatus: TaskStatus = TaskStatus.Idle;
  stepCount: number = 0;
  maxSteps: number = 100;
  isRunning: boolean = false;
  deviceId: string = '';
  isConfigured: boolean = false;
  configError: string = '';
  isInitializing: boolean = true;
  initMessage: string = '正在初始化...';

  // 执行状态
  currentStep: number = 0;

  // 私有成员
  private agent: SimpleAgent | null = null;
  private deviceService: DeviceService = DeviceService.getInstance();
  private configManager: ConfigManager = ConfigManager.getInstance();
  private shouldStop: boolean = false;
  private messageId: number = 0;

  // 回调
  onScrollToBottom?: () => void;

  /**
   * 初始化 ViewModel（进入对话界面时调用）
   * 统一执行：UITest初始化 -> 获取屏幕尺寸 -> 获取应用列表 -> 初始化Agent
   * @param context UIAbilityContext
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.isInitializing = true;
    this.deviceId = AppStorage.get<string>('connectedDevice') || '';
    this.deviceService.setConnId(this.deviceId || undefined);

    try {
      // 1. 初始化 UITest 客户端
      this.initMessage = '正在连接 UITest...';
      const connected = await this.deviceService.initUITestClient(context);

      if (!connected) {
        this.initMessage = 'UITest 连接失败';
        this.isInitializing = false;
        this.configError = 'UITest 初始化失败，请检查设备连接';
        return;
      }

      // 2. 获取屏幕尺寸
      this.initMessage = '正在获取屏幕信息...';
      const screenSize = await this.deviceService.getScreenSize();

      // 3. 获取已安装应用列表
      this.initMessage = '正在获取应用列表...';
      const apps = this.deviceService.getInstalledApps();

      // 4. 初始化 Agent
      this.initMessage = '正在初始化 Agent...';
      await this.initializeAgent(context, screenSize, apps);

      this.isInitializing = false;
    } catch (error) {
      console.error(`TaskViewModel: Initialize error: ${error}`);
      this.isInitializing = false;
      this.configError = `初始化失败: ${error}`;
    }
  }

  /**
   * 初始化 Agent
   * @param context UIAbilityContext
   * @param screenSize 屏幕尺寸
   * @param apps 已安装应用列表
   */
  private async initializeAgent(
    context: common.UIAbilityContext,
    screenSize?: ScreenSize,
    apps?: AppInfo[]
  ): Promise<void> {
    const config = await this.loadConfig(context);

    // 检查 apiKey 是否为空
    if (!config.apiKey || config.apiKey.trim() === '') {
      this.configError = '请先配置 API 密钥';
      this.isConfigured = false;
      this.isInitializing = false;  // 确保退出初始化状态
      return;
    }

    try {
      this.agent = new SimpleAgent(config);
      this.isConfigured = true;
      this.configError = '';

      // 设置屏幕尺寸
      if (screenSize) {
        this.agent.setScreenSize(screenSize.width, screenSize.height);
      }

      // 设置已安装应用列表
      if (apps && apps.length > 0) {
        this.agent.setInstalledApps(apps);
        this.deviceService.setInstalledApps(apps);
      }
    } catch (error) {
      this.configError = `Agent 初始化失败: ${error}`;
      this.isConfigured = false;
    }
  }

  /**
   * 加载配置
   */
  private async loadConfig(context: common.UIAbilityContext): Promise<ModelConfig> {
    let config: ModelConfig = {
      baseUrl: DEFAULT_MODEL_CONFIG.baseUrl,
      apiKey: DEFAULT_MODEL_CONFIG.apiKey,
      modelName: DEFAULT_MODEL_CONFIG.modelName,
      maxTokens: DEFAULT_MODEL_CONFIG.maxTokens,
      temperature: DEFAULT_MODEL_CONFIG.temperature,
      topP: DEFAULT_MODEL_CONFIG.topP,
      frequencyPenalty: DEFAULT_MODEL_CONFIG.frequencyPenalty,
      timeout: DEFAULT_MODEL_CONFIG.timeout
    };

    try {
      await this.configManager.initialize(context);
      const savedConfig = await this.configManager.loadConfig();
      if (savedConfig) {
        config = savedConfig;
      }
    } catch (error) {
      console.error('加载配置失败，使用默认配置', error);
    }
    
    // 强制使用 60s 超时时间
    if (!config.timeout || config.timeout < 60000) {
      config.timeout = 60000;
    }
    
    return config;
  }

  /**
   * 重新加载配置（页面显示时调用，仅更新配置，不重新初始化）
   */
  async reloadConfig(context: common.UIAbilityContext): Promise<void> {
    // 检查设备连接状态
    const currentDevice = AppStorage.get<string>('connectedDevice') || '';
    if (currentDevice !== this.deviceId) {
      this.deviceId = currentDevice;
      this.deviceService.setConnId(this.deviceId || undefined);
    }

    // 仅重新加载配置，保留已有的屏幕尺寸和应用列表
    const config = await this.loadConfig(context);

    if (!config.apiKey || config.apiKey.trim() === '') {
      this.configError = '请先配置 API 密钥';
      this.isConfigured = false;
      return;
    }

    // 保留旧数据（如果有的话）
    const oldApps = this.agent?.getInstalledApps() ?? [];
    
    // 重新创建 Agent
    this.agent = new SimpleAgent(config);
    this.isConfigured = true;
    this.configError = '';

    // 恢复屏幕尺寸（从 DeviceService 获取）
    const screenSize = await this.deviceService.getScreenSize();
    this.agent.setScreenSize(screenSize.width, screenSize.height);

    // 恢复应用列表
    if (oldApps.length > 0) {
      this.agent.setInstalledApps(oldApps);
    }
  }

  /**
   * 发送任务
   */
  async sendTask(): Promise<void> {
    if (!this.inputText.trim() || !this.agent) {
      return;
    }

    const taskText = this.inputText.trim();
    this.inputText = '';
    this.addMessage(MessageType.User, taskText);

    this.isRunning = true;
    this.shouldStop = false;
    this.taskStatus = TaskStatus.Running;
    this.stepCount = 0;
    this.agent.reset();

    try {
      await this.delay(500);
      if (this.shouldStop) {
        return;
      }
      await this.runMultiStageTask(taskText);
    } catch (error) {
      this.addMessage(MessageType.Error, `执行失败: ${error}`);
      this.taskStatus = TaskStatus.Error;
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * 停止任务
   */
  stopTask(): void {
    this.shouldStop = true;
    this.isRunning = false;
    this.taskStatus = TaskStatus.Stopped;
    if (this.agent) {
      this.agent.stop();
    }
    this.addMessage(MessageType.Result, '任务已停止');
  }

  /**
   * 重置 Agent
   */
  resetAgent(): void {
    if (this.agent) {
      this.agent.reset();
    }
  }

  /**
   * 设置输入文本
   */
  setInputText(value: string): void {
    this.inputText = value;
  }

  /**
   * 获取状态颜色
   */
  getStatusColor(): string {
    return STATUS_COLORS[this.taskStatus] || '#999999';
  }

  /**
   * 获取状态文本
   */
  getStatusText(): string {
    return STATUS_TEXTS[this.taskStatus] || '空闲';
  }

  /**
   * 获取当前步骤信息
   */
  getCurrentStepInfo(): string {
    if (this.currentStep === 0) {
      return '';
    }
    return `步骤 ${this.currentStep}`;
  }

  /**
   * 获取消息标题
   */
  getMessageTitle(type: MessageType): string {
    switch (type) {
      case MessageType.Thinking: return '思考中';
      case MessageType.Action: return '执行动作';
      case MessageType.Result: return '任务结果';
      case MessageType.Error: return '错误提示';
      default: return '';
    }
  }

  /**
   * 格式化时间戳为 HH:mm:ss
   */
  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const seconds = date.getSeconds().toString().padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }

  /**
   * 格式化耗时为可读字符串
   */
  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) {
      return `${seconds} 秒`;
    }
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    if (minutes < 60) {
      return remainingSeconds > 0 ? `${minutes} 分 ${remainingSeconds} 秒` : `${minutes} 分钟`;
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return `${hours} 小时 ${remainingMinutes} 分钟`;
  }

  /**
   * 添加消息
   */
  addMessage(type: MessageType, content: string, actionType?: string): void {
    const newMessage = new ChatMessage(this.messageId++, type, content, Date.now(), actionType);
    this.messages.push(newMessage);

    // 触发滚动回调
    if (this.onScrollToBottom) {
      this.onScrollToBottom();
    }
  }

  /**
   * 更新最后一条指定类型的消息内容（用于流式输出）
   */
  updateLastMessage(type: MessageType, content: string): void {
    // 从后往前找到最后一条指定类型的消息
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].type === type) {
        this.messages[i].content = content;
        // 触发滚动回调
        if (this.onScrollToBottom) {
          this.onScrollToBottom();
        }
        return;
      }
    }
  }

  /**
   * 运行任务（使用 SimpleAgent）
   * @param taskText 用户任务文本
   */
  private async runMultiStageTask(taskText: string): Promise<void> {
    if (!this.agent) {
      this.addMessage(MessageType.Error, 'Agent 未初始化');
      this.taskStatus = TaskStatus.Error;
      return;
    }

    // 用于跟踪当前步骤的流式消息
    let currentStreamStep = 0;

    try {
      // 使用 SimpleAgent 执行任务
      const result = await this.agent.execute(
        taskText,
        // 获取截图回调
        async (): Promise<string> => {
          const screenshot = await this.deviceService.takeScreenshotWithRetry(3);
          if (!screenshot.success || !screenshot.base64Data) {
            throw new Error(`截图失败: ${screenshot.error}`);
          }
          return screenshot.base64Data;
        },
        // 执行动作回调 - 不再单独显示动作消息，因为思考中已包含
        async (action: Action): Promise<boolean> => {
          const execResult = await this.deviceService.executeAction(action);
          if (!execResult.success) {
            this.addMessage(MessageType.Error, `动作执行失败: ${execResult.error}`);
            return false;
          }
          return true;
        },
        // 进度回调 - 显示思考内容和动作
        (step: number, thinking: string, actionDesc: string): void => {
          this.stepCount = step;
          currentStreamStep = step;
          // 显示思考内容（如果有的话）
          if (thinking && thinking.length > 0) {
            // 更新流式消息为最终思考内容
            this.updateLastMessage(MessageType.Thinking, `[${step}] ${thinking}`);
          }
          // 显示要执行的动作
          this.addMessage(MessageType.Action, actionDesc);
        },
        // 获取页面布局回调
        async (): Promise<string | undefined> => {
          return await this.deviceService.getPageLayout();
        },
        // 流式思考回调 - 实时显示模型输出
        (content: string): void => {
          // 如果是新步骤，先添加一条新的思考消息
          if (currentStreamStep < this.stepCount + 1) {
            currentStreamStep = this.stepCount + 1;
            this.addMessage(MessageType.Thinking, `[${currentStreamStep}] 思考中...`);
          }
          // 实时更新思考内容（截取前300字符避免过长）
          const displayContent = content.length > 300 ? content.substring(0, 300) + '...' : content;
          this.updateLastMessage(MessageType.Thinking, `[${currentStreamStep}] ${displayContent}`);
        }
      );

      // 显示最终结果
      const totalTime = this.formatDuration(result.totalTime);
      if (result.success) {
        this.addMessage(MessageType.Result, `${result.message}\n\n共 ${result.steps} 步，耗时 ${totalTime}`);
        this.taskStatus = TaskStatus.Completed;
      } else {
        this.addMessage(MessageType.Result, `${result.message}\n\n共 ${result.steps} 步，耗时 ${totalTime}`);
        this.taskStatus = TaskStatus.Error;
      }

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addMessage(MessageType.Error, `任务执行失败: ${errorMsg}`);
      this.taskStatus = TaskStatus.Error;
    }
  }

  /**
   * 延迟函数
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
