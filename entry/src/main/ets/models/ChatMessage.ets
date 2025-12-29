/**
 * ChatMessage - 聊天消息模型
 *
 * 定义聊天消息的类型枚举和消息类。
 * 从 viewmodels/TaskViewModel.ets 迁移而来，统一管理消息模型。
 */

/**
 * 消息类型枚举
 */
export enum MessageType {
  /** 用户消息 */
  User = 'user',
  /** AI 思考过程 */
  Thinking = 'thinking',
  /** 执行动作 */
  Action = 'action',
  /** 任务结果 */
  Result = 'result',
  /** 错误消息 */
  Error = 'error'
}

/**
 * 聊天消息类
 * 使用 @Observed 装饰器使属性变化可被观察
 */
@Observed
export class ChatMessage {
  /** 消息唯一标识 */
  id: number;
  /** 消息类型 */
  type: MessageType;
  /** 消息内容 */
  content: string;
  /** 时间戳 */
  timestamp: number;
  /** 动作类型（可选） */
  actionType?: string;

  constructor(
    id: number,
    type: MessageType,
    content: string,
    timestamp: number,
    actionType?: string
  ) {
    this.id = id;
    this.type = type;
    this.content = content;
    this.timestamp = timestamp;
    this.actionType = actionType;
  }
}
