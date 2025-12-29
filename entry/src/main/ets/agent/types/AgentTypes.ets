/**
 * Agent 相关类型定义
 * 
 * 注意：TaskStatus 已迁移到 models/Constants.ets
 * 本文件保留 Agent 专用的类型定义
 */

import { Action } from './ActionTypes';

// 重新导出 models 中的 TaskStatus 以保持向后兼容
export { TaskStatus } from '../../models';

/**
 * Agent 配置
 */
export interface AgentConfig {
  /** 最大步骤数，默认 100 */
  maxSteps?: number;
  /** 自定义系统提示词（保留用于扩展） */
  systemPrompt?: string;
}

/**
 * Agent 配置默认值
 */
export const DEFAULT_AGENT_CONFIG: AgentConfig = {
  maxSteps: 100
};

/**
 * 任务执行信息
 */
export interface TaskInfo {
  /** 任务状态 */
  status: string;
  /** 当前步骤数 */
  stepCount: number;
  /** 最大步骤数 */
  maxSteps: number;
  /** 当前动作 */
  currentAction?: Action;
  /** 当前思考 */
  currentThinking?: string;
  /** 结果消息 */
  message?: string;
}
