/**
 * ViewModel 模块导出
 * 
 * 本模块包含 MVVM 架构中的 ViewModel 层，负责管理 UI 状态和业务逻辑。
 * 每个 ViewModel 对应一个页面，使用 @Observed 装饰器实现响应式绑定。
 */

// ViewModel 导出
export { IndexViewModel } from './IndexViewModel';
export { TaskViewModel } from './TaskViewModel';
export { SettingsViewModel } from './SettingsViewModel';

// 重新导出 models 中的类型以保持向后兼容
export { ChatMessage, MessageType } from '../models';
