/**
 * Constants - 全局常量定义
 *
 * 定义应用中使用的全局常量，包括任务状态枚举及其对应的颜色和文本映射。
 * 从 agent/types/AgentTypes.ets 迁移 TaskStatus 枚举。
 */

/**
 * 任务状态枚举
 */
export enum TaskStatus {
  /** 空闲 */
  Idle = 'idle',
  /** 运行中 */
  Running = 'running',
  /** 已完成 */
  Completed = 'completed',
  /** 出错 */
  Error = 'error',
  /** 已停止 */
  Stopped = 'stopped'
}

/**
 * 状态颜色映射
 */
export const STATUS_COLORS: Record<string, string> = {
  [TaskStatus.Idle]: '#999999',
  [TaskStatus.Running]: '#007DFF',
  [TaskStatus.Completed]: '#00AA44',
  [TaskStatus.Error]: '#FA2A2D',
  [TaskStatus.Stopped]: '#FF9800'
};

/**
 * 状态文本映射
 */
export const STATUS_TEXTS: Record<string, string> = {
  [TaskStatus.Idle]: '空闲',
  [TaskStatus.Running]: '执行中',
  [TaskStatus.Completed]: '已完成',
  [TaskStatus.Error]: '出错',
  [TaskStatus.Stopped]: '已停止'
};
