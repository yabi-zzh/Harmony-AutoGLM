/**
 * AI Agent 动作类型定义
 */

/**
 * 动作类型枚举
 */
export enum ActionType {
  Tap = "Tap",
  Click = "Click",  // AutoGLM-Phone 使用 Click
  Swipe = "Swipe",
  Type = "Type",
  TypeName = "Type_Name",
  Launch = "Launch",
  Back = "Back",
  Home = "Home",
  LongPress = "Long Press",
  DoubleTap = "Double Tap",
  Wait = "Wait",
  TakeOver = "Take_over",
  Note = "Note",
  CallAPI = "Call_API",
  Interact = "Interact",
  Finish = "Finish",
  // 新增手势类型
  Drag = "Drag",
  PinchIn = "Pinch In",
  PinchOut = "Pinch Out",
  Draw = "Draw"
}

/**
 * 基础动作接口
 */
export interface BaseAction {
  type: ActionType;
  message?: string;
}

/**
 * 点击动作
 */
export interface TapAction extends BaseAction {
  type: ActionType.Tap | ActionType.Click;
  element: [number, number]; // 相对坐标 [0-1000, 0-1000]
}

/**
 * 滑动动作
 */
export interface SwipeAction extends BaseAction {
  type: ActionType.Swipe;
  start: [number, number];
  end: [number, number];
}

/**
 * 输入动作
 */
export interface TypeAction extends BaseAction {
  type: ActionType.Type | ActionType.TypeName;
  text: string;
}

/**
 * 启动应用动作
 */
export interface LaunchAction extends BaseAction {
  type: ActionType.Launch;
  app: string;
}

/**
 * 等待动作
 */
export interface WaitAction extends BaseAction {
  type: ActionType.Wait;
  duration: number; // 秒
}

/**
 * 结束动作
 */
export interface FinishAction extends BaseAction {
  type: ActionType.Finish;
  message: string;
}

/**
 * 长按动作
 */
export interface LongPressAction extends BaseAction {
  type: ActionType.LongPress;
  element: [number, number];
}

/**
 * 双击动作
 */
export interface DoubleTapAction extends BaseAction {
  type: ActionType.DoubleTap;
  element: [number, number];
}

/**
 * 接管动作
 */
export interface TakeOverAction extends BaseAction {
  type: ActionType.TakeOver;
  message: string;
}

/**
 * 简单动作（Back、Home 等无参数动作）
 */
export interface SimpleAction extends BaseAction {
  type: ActionType.Back | ActionType.Home | ActionType.Note | ActionType.Interact;
}

/**
 * API 调用动作
 */
export interface CallAPIAction extends BaseAction {
  type: ActionType.CallAPI;
  instruction: string;
}

/**
 * 拖拽动作（长按后移动）
 */
export interface DragAction extends BaseAction {
  type: ActionType.Drag;
  start: [number, number];
  end: [number, number];
}

/**
 * 捏合缩小动作（双指向内）
 */
export interface PinchInAction extends BaseAction {
  type: ActionType.PinchIn;
  center: [number, number];
  scale?: number; // 缩放比例，默认 0.5
}

/**
 * 捏合放大动作（双指向外）
 */
export interface PinchOutAction extends BaseAction {
  type: ActionType.PinchOut;
  center: [number, number];
  scale?: number; // 缩放比例，默认 2.0
}

/**
 * 绘制路径动作（写字、画图等）
 */
export interface DrawAction extends BaseAction {
  type: ActionType.Draw;
  path: [number, number][]; // 路径点序列
}

/**
 * 动作联合类型
 */
export type Action =
  | TapAction
  | SwipeAction
  | TypeAction
  | LaunchAction
  | WaitAction
  | FinishAction
  | LongPressAction
  | DoubleTapAction
  | TakeOverAction
  | SimpleAction
  | CallAPIAction
  | DragAction
  | PinchInAction
  | PinchOutAction
  | DrawAction;
