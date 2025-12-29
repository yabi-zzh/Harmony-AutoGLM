/**
 * SimpleAgent - 极简 AI Agent
 *
 * 设计原则：
 * 1. 简单任务直接执行，不调用AI决策
 * 2. 每步执行后检查屏幕，处理弹窗
 * 3. 复杂任务一次AI调用输出下一步动作
 * 4. 维护对话上下文，让模型知道历史操作
 */

import { ModelClient } from '../client/ModelClient';
import { Message, ModelConfig } from '../types/ModelTypes';
import {
  Action,
  ActionType,
  FinishAction,
  LaunchAction,
  SimpleAction,
  SwipeAction,
  TapAction,
  TypeAction,
  WaitAction
} from '../types/ActionTypes';
import { ActionParser } from '../parser/ActionParser';
import { APP_CONFIG } from '../../models';

/** 应用信息 */
interface AppInfo {
  bundleName: string;
  label: string;
}

/** 任务结果 */
export interface SimpleTaskResult {
  success: boolean;
  message: string;
  steps: number;
  totalTime: number;
}

/** 预处理结果 */
interface PreprocessResult {
  prefixActions: Action[];
  remainingTask: string | null;
}

/** 屏幕信息 */
interface ScreenInfo {
  screenshot: string | undefined;
  layout: string | undefined;
}

/** 应用匹配候选 */
interface AppCandidate {
  app: AppInfo;
  score: number;
}

/** AI 决策结果 */
interface DecisionResult {
  action: Action;
  thinking: string;
}

/** 进度回调 - 包含步骤、思考内容和动作描述 */
type ProgressCallback = (step: number, thinking: string, actionDesc: string) => void;

/** 流式思考回调 - 实时显示模型思考过程 */
type ThinkingCallback = (content: string) => void;

/**
 * 极简 Agent
 */
export class SimpleAgent {
  private modelClient: ModelClient;
  private installedApps: AppInfo[] = [];
  private isStopped: boolean = false;
  private maxSteps: number = APP_CONFIG.agent.maxSteps;
  
  // 对话上下文 - 维护历史消息
  private context: Message[] = [];
  // 最近动作历史 - 用于检测重复
  private recentActions: string[] = [];
  // 流式思考回调
  private onThinking?: ThinkingCallback;

  constructor(modelConfig: ModelConfig) {
    this.modelClient = new ModelClient(modelConfig);
  }

  setScreenSize(width: number, height: number): void {
    // 屏幕尺寸信息（目前未使用，但保留接口以便将来扩展）
    console.info(`SimpleAgent: setScreenSize ${width}x${height}`);
  }

  setInstalledApps(apps: AppInfo[]): void {
    this.installedApps = apps;
  }

  getInstalledApps(): AppInfo[] {
    return this.installedApps;
  }

  stop(): void {
    this.isStopped = true;
  }

  reset(): void {
    this.isStopped = false;
    this.context = [];
    this.recentActions = [];
  }

  /**
   * 执行任务
   */
  async execute(
    task: string,
    getScreenshot: () => Promise<string>,
    executeAction: (action: Action) => Promise<boolean>,
    onProgress?: ProgressCallback,
    getPageLayout?: () => Promise<string | undefined>,
    onThinking?: ThinkingCallback
  ): Promise<SimpleTaskResult> {
    this.isStopped = false;
    this.context = [];
    this.recentActions = [];
    this.onThinking = onThinking;
    const startTime = Date.now();
    let stepCount = 0;

    try {
      // 预处理任务，提取可直接执行的前置动作
      const preprocessResult: PreprocessResult = this.preprocessTask(task);
      const prefixActions: Action[] = preprocessResult.prefixActions;
      const remainingTask: string | null = preprocessResult.remainingTask;

      // 执行前置动作（不需要AI决策）
      for (const action of prefixActions) {
        if (this.isStopped) break;
        stepCount++;
        const actionDesc = this.describeAction(action);
        onProgress?.(stepCount, '直接执行预处理动作', actionDesc);
        await executeAction(action);
      }

      // 如果没有剩余任务，直接返回
      if (!remainingTask) {
        return {
          success: true,
          message: '任务完成',
          steps: stepCount,
          totalTime: Date.now() - startTime
        };
      }

      // 复杂任务 - 循环执行（AI 会同时处理弹窗和任务）
      while (stepCount < this.maxSteps && !this.isStopped) {
        stepCount++;

        // 获取屏幕信息
        const screenInfo = await this.getScreenInfo(getScreenshot, getPageLayout);

        // AI决定下一步（prompt 中包含弹窗处理指令）
        const decision = await this.decideNextAction(remainingTask, screenInfo, stepCount);
        const action = decision.action;
        const thinking = decision.thinking;

        // 检查是否完成
        if (action.type === ActionType.Finish) {
          const finishAction = action as FinishAction;
          return {
            success: true,
            message: finishAction.message || '任务完成',
            steps: stepCount,
            totalTime: Date.now() - startTime
          };
        }

        // 执行动作 - 传递思考内容和动作描述
        const actionDesc = this.describeAction(action);
        onProgress?.(stepCount, thinking, actionDesc);
        await executeAction(action);
        
        // Wait 动作本身已包含等待，不需要额外等待
        if (action.type !== ActionType.Wait) {
          await this.wait(APP_CONFIG.agent.actionDelay);
        }
      }

      return {
        success: false,
        message: this.isStopped ? '任务已停止' : '超过最大步骤数',
        steps: stepCount,
        totalTime: Date.now() - startTime
      };

    } catch (error) {
      return {
        success: false,
        message: error instanceof Error ? error.message : String(error),
        steps: stepCount,
        totalTime: Date.now() - startTime
      };
    }
  }

  /**
   * 预处理任务，提取可直接执行的前置动作
   */
  private preprocessTask(task: string): PreprocessResult {
    const actions: Action[] = [];
    const separators = /[,，。.;；]|然后|接着|再|并/;
    const parts = task.split(separators).map(p => p.trim()).filter(p => p.length > 0);

    let processedCount = 0;
    for (const part of parts) {
      const action = this.tryParseSimpleAction(part);
      if (action) {
        actions.push(action);
        processedCount++;
      } else {
        break;
      }
    }

    if (processedCount === 0) {
      const result: PreprocessResult = { prefixActions: [], remainingTask: task };
      return result;
    } else if (processedCount === parts.length) {
      const result: PreprocessResult = { prefixActions: actions, remainingTask: null };
      return result;
    } else {
      const remainingParts = parts.slice(processedCount);
      const result: PreprocessResult = { prefixActions: actions, remainingTask: remainingParts.join('，') };
      return result;
    }
  }

  /**
   * 尝试将单个指令解析为动作
   */
  private tryParseSimpleAction(instruction: string): Action | null {
    const t = instruction.trim().toLowerCase();

    // Home
    if (t.includes('回到桌面') || t.includes('返回桌面') || t.includes('回桌面') || t === '桌面') {
      return { type: ActionType.Home } as SimpleAction;
    }

    // Back
    if (t === '返回' || t === '后退' || t === '回退') {
      return { type: ActionType.Back } as SimpleAction;
    }

    // Launch - 从本地应用列表查找，不依赖 AI
    const launchPatterns = [
      /^(打开|启动|进入|开启|拉起)\s*(.+)$/,
      /^(.+)\s*(打开|启动)$/
    ];

    for (const pattern of launchPatterns) {
      const match = instruction.match(pattern);
      if (match) {
        const appName = (match[2] || match[1]).trim();
        console.info(`SimpleAgent: 尝试匹配应用 "${appName}"，已安装应用数: ${this.installedApps.length}`);
        if (this.isLikelyAppName(appName)) {
          const app = this.findApp(appName);
          if (app) {
            console.info(`SimpleAgent: 找到应用 "${appName}" -> ${app.bundleName}`);
            return { type: ActionType.Launch, app: app.bundleName } as LaunchAction;
          } else {
            // 找不到应用，记录日志，但仍返回 null 让后续流程处理
            console.warn(`SimpleAgent: 未找到应用 "${appName}"`);
          }
        }
      }
    }

    return null;
  }

  /**
   * 判断是否像应用名
   */
  private isLikelyAppName(name: string): boolean {
    const actionWords = ['搜索', '点击', '输入', '滑动', '查找', '查看', '播放', '下载', '分享', '点赞', '评论', '收藏'];
    for (const word of actionWords) {
      if (name.includes(word)) return false;
    }
    return name.length > 0 && name.length <= 10;
  }


  /**
   * 智能查找应用
   */
  private findApp(name: string): AppInfo | undefined {
    const input = name.trim().toLowerCase();
    const candidates: AppCandidate[] = [];

    // 如果列表为空，直接返回
    if (this.installedApps.length === 0) {
      return undefined;
    }

    // 先尝试精确匹配
    for (const app of this.installedApps) {
      if (app.label === name.trim() || app.label.toLowerCase() === input) {
        return app;
      }
    }

    const aliases: Record<string, string[]> = {
      '浏览器': ['浏览器'],
      '相机': ['相机', 'camera'],
      '相册': ['相册', '图库', '照片'],
      '设置': ['设置', 'settings'],
      '电话': ['电话', '拨号', 'phone'],
      '短信': ['短信', '信息', '消息', 'message'],
      '日历': ['日历', 'calendar'],
      '时钟': ['时钟', '闹钟', 'clock'],
      '计算器': ['计算器', 'calculator'],
      '备忘录': ['备忘录', '笔记', 'note', 'memo'],
      '文件': ['文件', '文件管理', 'file'],
      '音乐': ['音乐', 'music'],
      '视频': ['视频', 'video'],
      '地图': ['地图', 'map'],
      '天气': ['天气', 'weather'],
      '邮件': ['邮件', '邮箱', 'mail', 'email'],
    };

    for (const app of this.installedApps) {
      const label = app.label.toLowerCase();
      let score = 0;

      if (label === input) {
        score = 100;
      } else if (input.includes(label)) {
        score = 80;
      } else if (label.includes(input)) {
        score = 70;
      } else {
        for (const key of Object.keys(aliases)) {
          const values = aliases[key];
          if (input.includes(key) || values.some(v => input.includes(v))) {
            if (values.some(v => label.includes(v)) || label.includes(key)) {
              const isSystem = app.bundleName.startsWith('com.huawei') || app.bundleName.startsWith('com.ohos');
              score = isSystem ? 65 : 60;
              break;
            }
          }
        }
      }

      if (score > 0) {
        const candidate: AppCandidate = { app: app, score: score };
        candidates.push(candidate);
      }
    }

    if (candidates.length === 0) {
      console.warn(`SimpleAgent.findApp: 未找到匹配 "${name}"`);
      return undefined;
    }

    candidates.sort((a, b) => b.score - a.score);

    if (candidates.length === 1 || candidates[0].score > candidates[1].score + 10) {
      return candidates[0].app;
    }

    return undefined;
  }

  /**
   * 获取屏幕信息
   */
  private async getScreenInfo(
    getScreenshot: () => Promise<string>,
    _getPageLayout?: () => Promise<string | undefined>
  ): Promise<ScreenInfo> {
    const result: ScreenInfo = {
      screenshot: undefined,
      layout: undefined
    };

    // 始终获取截图（AI 需要图片来理解屏幕）
    result.screenshot = await getScreenshot();

    // 可选：获取页面布局（暂时禁用，因为布局数据太大会影响性能）
    // if (getPageLayout) {
    //   try {
    //     result.layout = await getPageLayout();
    //   } catch (e) {
    //     console.warn('获取页面布局失败');
    //   }
    // }

    return result;
  }

  /**
   * AI决定下一步动作
   * 使用官方 AutoGLM 格式：system message + 对话上下文
   * 返回动作和思考内容
   */
  private async decideNextAction(
    task: string,
    screenInfo: ScreenInfo,
    step: number
  ): Promise<DecisionResult> {
    const isFirstStep = this.context.length === 0;
    
    // 第一步：添加 system message
    if (isFirstStep) {
      const systemPrompt = this.buildSystemPrompt();
      this.context.push(ModelClient.createSystemMessage(systemPrompt));
    }
    
    // 构建用户消息
    const userContent = this.buildUserContent(task, step, isFirstStep);
    const userMessage = screenInfo.screenshot 
      ? ModelClient.createUserMessage(userContent, screenInfo.screenshot)
      : ModelClient.createUserMessage(userContent);
    this.context.push(userMessage);

    // 调用模型 - 传递流式回调
    const result = await this.modelClient.requestStream(this.context, this.onThinking);
    const response = result.actionRaw;

    // 移除用户消息中的图片以节省上下文空间（保留文本）
    this.removeImageFromLastMessage();

    try {
      const action = ActionParser.parse(response);
      const actionStr = this.describeAction(action);
      console.info(`SimpleAgent: 解析动作成功 - ${action.type}`);
      
      // 获取思考内容
      const thinking = result.thinking || '分析屏幕并决定下一步';
      
      // 检测重复动作
      if (this.isRepeatedAction(actionStr)) {
        console.warn(`SimpleAgent: 检测到重复动作 "${actionStr}"，尝试打破循环`);
        // 添加提示到上下文，告诉模型动作重复了
        const assistantMsg = ModelClient.createAssistantMessage(
          `<think>执行了 ${actionStr}，但似乎没有效果</think><answer>${response}</answer>`
        );
        this.context.push(assistantMsg);
        
        // 如果连续重复超过3次，返回 Back 动作尝试打破循环
        const repeatCount = this.countRecentRepeats(actionStr);
        if (repeatCount >= 3) {
          console.warn(`SimpleAgent: 动作重复 ${repeatCount} 次，执行 Back 打破循环`);
          this.recentActions = []; // 清空历史
          const backResult: DecisionResult = { 
            action: { type: ActionType.Back } as SimpleAction, 
            thinking: '动作重复多次，尝试返回上一页' 
          };
          return backResult;
        }
        
        // 记录动作
        this.recentActions.push(actionStr);
        if (this.recentActions.length > 5) {
          this.recentActions.shift();
        }
        const repeatResult: DecisionResult = { action, thinking: `${thinking}（重复动作）` };
        return repeatResult;
      }
      
      // 添加助手响应到上下文（官方格式）
      const assistantMsg = ModelClient.createAssistantMessage(
        `<think>${thinking}</think><answer>${response}</answer>`
      );
      this.context.push(assistantMsg);
      
      // 记录动作
      this.recentActions.push(actionStr);
      if (this.recentActions.length > 5) {
        this.recentActions.shift();
      }
      
      const successResult: DecisionResult = { action, thinking };
      return successResult;
    } catch (error) {
      const preview = response.length > 200 ? response.substring(0, 200) + '...' : response;
      console.warn(`SimpleAgent: 解析动作失败，返回 Wait。响应: ${preview}`);
      
      // 检查是否包含登录/验证码等关键词，如果是则直接 finish
      const lowerResponse = response.toLowerCase();
      if (lowerResponse.includes('登录') || lowerResponse.includes('login') ||
          lowerResponse.includes('验证码') || lowerResponse.includes('支付') ||
          lowerResponse.includes('未登录') || lowerResponse.includes('需要登录')) {
        console.info(`SimpleAgent: 检测到登录/验证相关内容，返回 Finish`);
        const finishResult: DecisionResult = {
          action: { type: ActionType.Finish, message: '需要登录才能继续操作' } as FinishAction,
          thinking: '检测到需要登录，无法继续'
        };
        return finishResult;
      }
      
      const waitResult: DecisionResult = { 
        action: { type: ActionType.Wait, duration: 1 } as WaitAction, 
        thinking: '解析响应失败，等待重试' 
      };
      return waitResult;
    }
  }

  /**
   * 检测是否为重复动作
   */
  private isRepeatedAction(actionStr: string): boolean {
    if (this.recentActions.length === 0) return false;
    const lastAction = this.recentActions[this.recentActions.length - 1];
    return lastAction === actionStr;
  }

  /**
   * 统计最近重复次数
   */
  private countRecentRepeats(actionStr: string): number {
    let count = 0;
    for (let i = this.recentActions.length - 1; i >= 0; i--) {
      if (this.recentActions[i] === actionStr) {
        count++;
      } else {
        break;
      }
    }
    return count + 1; // 包括当前这次
  }

  /**
   * 移除最后一条消息中的图片（节省上下文空间）
   */
  private removeImageFromLastMessage(): void {
    if (this.context.length === 0) return;
    const lastMsg = this.context[this.context.length - 1];
    if (Array.isArray(lastMsg.content)) {
      // 过滤掉图片，只保留文本
      const textOnly = lastMsg.content.filter(item => item.type === 'text');
      if (textOnly.length > 0) {
        lastMsg.content = textOnly;
      }
    }
  }

  /**
   * 构建系统提示词 - 基于官方 AutoGLM prompt 优化
   */
  private buildSystemPrompt(): string {
    const today = new Date();
    const weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    const dateStr = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日 ${weekdays[today.getDay()]}`;

    return `今天的日期是: ${dateStr}
你是一个手机操作智能体，根据屏幕截图执行操作来完成用户任务。

操作指令：
- do(action="Launch", app="应用名") - 启动应用，比导航更快
- do(action="Tap", element=[x,y]) - 点击屏幕坐标
- do(action="Swipe", start=[x1,y1], end=[x2,y2]) - 滑动手势
- do(action="Type", text="内容") - 在当前输入框输入文本
- do(action="Long Press", element=[x,y]) - 长按
- do(action="Back") - 返回上一页
- do(action="Home") - 回到桌面
- do(action="Wait", duration="1") - 等待页面加载，通常1-2秒即可
- finish(message="结果") - 任务完成或无法继续

坐标系统：左上角(0,0)，右下角(999,999)

关键规则：
1. 执行操作前先确认当前是否在目标应用，不是则先 Launch
2. 进入无关页面时执行 Back 返回
3. 页面未加载完成时 Wait，最多等待3次
4. 找不到目标时 Swipe 滑动查找，向下滑动：start=[500,700] end=[500,300]
5. 滑动无效时尝试反方向，或调整起始位置
6. 执行下一步前检查上一步是否生效，未生效则调整位置重试
7. 有弹窗时优先关闭弹窗
8. 遇到需要登录、验证码、支付等敏感操作时，必须输出 finish(message="需要登录/验证码/支付，无法继续")
9. 如果同一操作尝试2次仍失败，finish 并说明原因
10. 任务完成后输出 finish，message 简洁说明结果
11. 当用户说"第N个"时，从屏幕顶部往下数，第1个是最上面的，第2个是紧接着的下一个

重要：每次响应只输出一条操作指令，必须使用上述格式，不要自创动作名称。`;
  }

  /**
   * 构建用户消息内容
   */
  private buildUserContent(task: string, step: number, isFirstStep: boolean): string {
    if (isFirstStep) {
      return `任务: ${task}

请分析屏幕并执行下一步操作。`;
    } else {
      // 简化后续步骤的提示，避免模型混乱
      return `请分析当前屏幕，继续执行任务。`;
    }
  }

  /**
   * 描述动作
   */
  private describeAction(action: Action): string {
    switch (action.type) {
      case ActionType.Tap:
        const tap = action as TapAction;
        return `点击 [${tap.element[0]}, ${tap.element[1]}]`;
      case ActionType.Swipe:
        const swipe = action as SwipeAction;
        return `滑动 [${swipe.start[0]},${swipe.start[1]}] → [${swipe.end[0]},${swipe.end[1]}]`;
      case ActionType.Type:
        const type = action as TypeAction;
        return `输入 "${type.text}"`;
      case ActionType.Launch:
        const launch = action as LaunchAction;
        return `启动 ${launch.app}`;
      case ActionType.Back:
        return '返回';
      case ActionType.Home:
        return '回到桌面';
      case ActionType.Wait:
        const wait = action as WaitAction;
        return `等待 ${wait.duration}秒`;
      case ActionType.Finish:
        return '完成';
      default:
        return action.type;
    }
  }

  /**
   * 等待
   */
  private wait(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
