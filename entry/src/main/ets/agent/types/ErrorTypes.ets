/**
 * 错误处理相关类型定义
 */

/**
 * 执行阶段枚举
 */
export enum ExecutionPhase {
  /** 初始化 */
  Init = 'init',
  /** 截图 */
  Screenshot = 'screenshot',
  /** 分析 */
  Analysis = 'analysis',
  /** 执行动作 */
  Action = 'action',
  /** 验证 */
  Verification = 'verification'
}

/**
 * Agent 错误代码枚举
 */
export enum AgentErrorCode {
  /** 意图解析失败 */
  INTENT_PARSE_FAILED = 'INTENT_PARSE_FAILED',
  /** 计划生成失败 */
  PLAN_GENERATION_FAILED = 'PLAN_GENERATION_FAILED',
  /** 截图失败 */
  SCREENSHOT_FAILED = 'SCREENSHOT_FAILED',
  /** 屏幕分析失败 */
  SCREEN_ANALYSIS_FAILED = 'SCREEN_ANALYSIS_FAILED',
  /** 动作解析失败 */
  ACTION_PARSE_FAILED = 'ACTION_PARSE_FAILED',
  /** 动作执行失败 */
  ACTION_EXECUTION_FAILED = 'ACTION_EXECUTION_FAILED',
  /** 动作超时 */
  ACTION_TIMEOUT = 'ACTION_TIMEOUT',
  /** 验证失败 */
  VERIFICATION_FAILED = 'VERIFICATION_FAILED',
  /** 检测到弹窗 */
  POPUP_DETECTED = 'POPUP_DETECTED',
  /** 应用无响应 */
  APP_NOT_RESPONDING = 'APP_NOT_RESPONDING',
  /** 超过最大重试次数 */
  MAX_RETRIES_EXCEEDED = 'MAX_RETRIES_EXCEEDED',
  /** 超过最大步骤数 */
  MAX_STEPS_EXCEEDED = 'MAX_STEPS_EXCEEDED',
  /** 用户取消 */
  USER_CANCELLED = 'USER_CANCELLED'
}

/**
 * 可恢复的错误代码列表
 */
const RECOVERABLE_CODES: AgentErrorCode[] = [
  AgentErrorCode.SCREENSHOT_FAILED,
  AgentErrorCode.ACTION_TIMEOUT,
  AgentErrorCode.POPUP_DETECTED,
  AgentErrorCode.APP_NOT_RESPONDING
];

/**
 * Agent 错误类
 * 继承自 Error，添加错误代码、阶段和可恢复性属性
 */
export class AgentError extends Error {
  /** 错误代码 */
  code: AgentErrorCode;
  /** 发生错误的执行阶段 */
  phase: ExecutionPhase;
  /** 是否可恢复 */
  recoverable: boolean;

  constructor(message: string, code: AgentErrorCode, phase: ExecutionPhase) {
    super(message);
    this.name = 'AgentError';
    this.code = code;
    this.phase = phase;
    this.recoverable = this.isRecoverable(code);
  }

  /**
   * 判断错误是否可恢复
   * @param code 错误代码
   * @returns 是否可恢复
   */
  private isRecoverable(code: AgentErrorCode): boolean {
    return RECOVERABLE_CODES.includes(code);
  }
}
