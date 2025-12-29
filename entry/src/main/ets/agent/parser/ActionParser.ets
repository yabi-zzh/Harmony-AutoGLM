/**
 * AI Agent 动作解析器
 * 负责解析模型输出字符串为 Action 对象，以及将 Action 对象格式化为字符串
 */

import {
  Action,
  ActionType,
  CallAPIAction,
  DoubleTapAction,
  DragAction,
  DrawAction,
  FinishAction,
  LaunchAction,
  LongPressAction,
  PinchInAction,
  PinchOutAction,
  SimpleAction,
  SwipeAction,
  TakeOverAction,
  TapAction,
  TypeAction,
  WaitAction
} from '../types/ActionTypes';

/**
 * 解析响应结果
 */
export interface ParsedResponse {
  thinking: string;
  actionRaw: string;
}

/**
 * 解析错误
 */
export class ActionParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ActionParseError';
  }
}

/**
 * 动作解析器类
 */
export class ActionParser {
  /**
   * 解析模型输出字符串为 Action 对象
   * @param response 模型输出的动作字符串，如 do(action="Tap", element=[500,300])
   * @returns 解析后的 Action 对象
   * @throws ActionParseError 解析失败时抛出
   */
  static parse(response: string): Action {
    const trimmed = response.trim();

    // 先尝试从响应中提取动作（支持动作在中间或末尾的情况）
    const extracted = ActionParser.extractAction(trimmed);
    if (extracted) {
      // 处理 Type 动作的特殊情况（文本可能包含特殊字符）
      if (extracted.startsWith('do(action="Type"') || extracted.startsWith('do(action="Type_Name"')) {
        return ActionParser.parseTypeAction(extracted);
      }

      // 处理 finish 动作
      if (extracted.startsWith('finish(')) {
        return ActionParser.parseFinishAction(extracted);
      }

      // 处理 do 动作
      if (extracted.startsWith('do(')) {
        return ActionParser.parseDoAction(extracted);
      }
    }

    // 回退：直接检查原始响应
    if (trimmed.startsWith('do(action="Type"') || trimmed.startsWith('do(action="Type_Name"')) {
      return ActionParser.parseTypeAction(trimmed);
    }

    if (trimmed.startsWith('finish(')) {
      return ActionParser.parseFinishAction(trimmed);
    }

    if (trimmed.startsWith('do(')) {
      return ActionParser.parseDoAction(trimmed);
    }

    throw new ActionParseError(`无法解析动作: ${response.substring(0, 200)}`);
  }

  /**
   * 从响应中提取动作字符串
   * 支持动作在响应中间或末尾的情况
   */
  private static extractAction(response: string): string | null {
    // 优先查找最后一个 do( 或 finish(，因为模型可能在思考过程中提到动作格式
    const lastDoIndex = response.lastIndexOf('do(action=');
    const lastFinishIndex = response.lastIndexOf('finish(message=');

    // 选择最后出现的动作
    const actionIndex = Math.max(lastDoIndex, lastFinishIndex);
    if (actionIndex === -1) {
      return null;
    }

    // 从动作开始位置提取
    let actionStr = response.substring(actionIndex);

    // 尝试找到动作的结束位置（匹配括号）
    let depth = 0;
    let endIndex = -1;
    for (let i = 0; i < actionStr.length; i++) {
      const char = actionStr[i];
      if (char === '(') {
        depth++;
      } else if (char === ')') {
        depth--;
        if (depth === 0) {
          endIndex = i + 1;
          break;
        }
      }
    }

    if (endIndex > 0) {
      return actionStr.substring(0, endIndex);
    }

    // 如果括号不匹配，返回到行尾或字符串结尾
    const lineEnd = actionStr.indexOf('\n');
    if (lineEnd > 0) {
      return actionStr.substring(0, lineEnd).trim();
    }

    return actionStr.trim();
  }

  /**
   * 将 Action 对象格式化为字符串
   * @param action Action 对象
   * @returns 格式化后的字符串
   */
  static format(action: Action): string {
    if (action.type === ActionType.Finish) {
      const finishAction = action as FinishAction;
      return `finish(message="${ActionParser.escapeString(finishAction.message)}")`;
    }

    let params: string[] = [`action="${action.type}"`];

    switch (action.type) {
      case ActionType.Tap:
      case ActionType.Click:
        const tapAction = action as TapAction;
        params.push(`element=[${tapAction.element[0]},${tapAction.element[1]}]`);
        if (tapAction.message) {
          params.push(`message="${ActionParser.escapeString(tapAction.message)}"`);
        }
        break;

      case ActionType.Swipe:
        const swipeAction = action as SwipeAction;
        params.push(`start=[${swipeAction.start[0]},${swipeAction.start[1]}]`);
        params.push(`end=[${swipeAction.end[0]},${swipeAction.end[1]}]`);
        break;

      case ActionType.Type:
      case ActionType.TypeName:
        const typeAction = action as TypeAction;
        params.push(`text="${ActionParser.escapeString(typeAction.text)}"`);
        break;

      case ActionType.Launch:
        const launchAction = action as LaunchAction;
        params.push(`app="${ActionParser.escapeString(launchAction.app)}"`);
        break;

      case ActionType.Wait:
        const waitAction = action as WaitAction;
        params.push(`duration="${waitAction.duration} seconds"`);
        break;

      case ActionType.LongPress:
        const longPressAction = action as LongPressAction;
        params.push(`element=[${longPressAction.element[0]},${longPressAction.element[1]}]`);
        break;

      case ActionType.DoubleTap:
        const doubleTapAction = action as DoubleTapAction;
        params.push(`element=[${doubleTapAction.element[0]},${doubleTapAction.element[1]}]`);
        break;

      case ActionType.TakeOver:
        const takeOverAction = action as TakeOverAction;
        params.push(`message="${ActionParser.escapeString(takeOverAction.message)}"`);
        break;

      case ActionType.CallAPI:
        const callAPIAction = action as CallAPIAction;
        params.push(`instruction="${ActionParser.escapeString(callAPIAction.instruction)}"`);
        break;

      case ActionType.Back:
      case ActionType.Home:
      case ActionType.Note:
      case ActionType.Interact:
        // 简单动作无额外参数
        break;
    }

    return `do(${params.join(', ')})`;
  }

  /**
   * 解析完整响应为 thinking 和 action 两部分
   * @param content 完整的模型响应内容
   * @returns 解析后的 thinking 和 actionRaw
   */
  static parseResponse(content: string): ParsedResponse {
    // 规则 1: 优先检查 XML 格式 <think>...</think><answer>...</answer>
    if (content.includes('<answer>')) {
      const answerMatch = content.match(/<answer>([\s\S]*?)<\/answer>/);
      if (answerMatch) {
        const thinkMatch = content.match(/<think>([\s\S]*?)<\/think>/);
        const thinking = thinkMatch ? thinkMatch[1].trim() : '';
        const actionRaw = answerMatch[1].trim();
        return { thinking, actionRaw };
      }
      // 如果没有闭合标签，尝试提取 <answer> 后的内容
      const parts = content.split('<answer>');
      const thinking = parts[0].replace(/<\/?think>/g, '').trim();
      const actionRaw = parts[1] ? parts[1].replace('</answer>', '').trim() : '';
      return { thinking, actionRaw };
    }

    // 规则 2: 使用 extractAction 提取最后一个有效动作
    const extractedAction = ActionParser.extractAction(content);
    
    if (extractedAction) {
      // 找到动作在原文中的位置，之前的内容作为 thinking
      const actionIndex = content.lastIndexOf(extractedAction.substring(0, 20)); // 用前20字符定位
      const thinking = actionIndex > 0 ? content.substring(0, actionIndex).trim() : '';
      return { thinking, actionRaw: extractedAction };
    }

    // 回退：规则 3 - 检查 finish(message=（使用最后一个出现的位置）
    const lastFinishIndex = content.lastIndexOf('finish(message=');
    if (lastFinishIndex !== -1) {
      const thinking = content.substring(0, lastFinishIndex).trim();
      const actionRaw = content.substring(lastFinishIndex);
      return { thinking, actionRaw };
    }

    // 回退：规则 4 - 检查 do(action=（使用最后一个出现的位置）
    const lastDoIndex = content.lastIndexOf('do(action=');
    if (lastDoIndex !== -1) {
      const thinking = content.substring(0, lastDoIndex).trim();
      const actionRaw = content.substring(lastDoIndex);
      return { thinking, actionRaw };
    }

    // 规则 5: 无标记，返回整个内容作为 action
    return { thinking: '', actionRaw: content };
  }

  /**
   * 解析 Type 动作
   */
  private static parseTypeAction(response: string): TypeAction {
    const isTypeName = response.includes('action="Type_Name"');
    const textMatch = response.match(/text="([^"]*)"/);

    if (!textMatch) {
      // 尝试提取 text= 后面的内容直到结尾
      const textStart = response.indexOf('text=');
      if (textStart !== -1) {
        let text = response.substring(textStart + 6); // 跳过 'text="'
        // 移除结尾的 ")
        if (text.endsWith('")')) {
          text = text.slice(0, -2);
        }
        return {
          type: isTypeName ? ActionType.TypeName : ActionType.Type,
          text: ActionParser.unescapeString(text)
        };
      }
      throw new ActionParseError('Type 动作缺少 text 参数');
    }

    return {
      type: isTypeName ? ActionType.TypeName : ActionType.Type,
      text: ActionParser.unescapeString(textMatch[1])
    };
  }

  /**
   * 解析 finish 动作
   */
  private static parseFinishAction(response: string): FinishAction {
    // 查找 message=" 的位置，然后找到最后一个 ") 作为结束
    const msgStart = response.indexOf('message="');
    if (msgStart !== -1) {
      let message = response.substring(msgStart + 9); // 跳过 'message="'
      // 找到最后一个 ") 作为结束（处理消息中包含引号的情况）
      const endIndex = message.lastIndexOf('")');
      if (endIndex !== -1) {
        message = message.substring(0, endIndex);
      } else if (message.endsWith('"')) {
        message = message.slice(0, -1);
      }
      return {
        type: ActionType.Finish,
        message: ActionParser.unescapeString(message)
      };
    }
    
    // 回退到正则匹配（简单情况）
    const messageMatch = response.match(/message="([^"]*)"/);
    if (messageMatch) {
      return {
        type: ActionType.Finish,
        message: ActionParser.unescapeString(messageMatch[1])
      };
    }
    
    throw new ActionParseError('finish 动作缺少 message 参数');
  }

  /**
   * 解析 do 动作
   */
  private static parseDoAction(response: string): Action {
    // 提取 action 类型
    const actionMatch = response.match(/action="([^"]+)"/);
    if (!actionMatch) {
      throw new ActionParseError('do 动作缺少 action 参数');
    }

    const actionType = actionMatch[1];

    switch (actionType) {
      case 'Click':  // AutoGLM-Phone 格式
      case 'Tap':
        return ActionParser.parseTapAction(response);
      case 'Swipe':
        return ActionParser.parseSwipeAction(response);
      case 'Type':
        return ActionParser.parseTypeAction(response);
      case 'Type_Name':
        return ActionParser.parseTypeAction(response);
      case 'Launch':
        return ActionParser.parseLaunchAction(response);
      case 'Back':
        return { type: ActionType.Back } as SimpleAction;
      case 'Home':
        return { type: ActionType.Home } as SimpleAction;
      case 'Long Press':
      case 'LongPress':
        return ActionParser.parseLongPressAction(response);
      case 'Double Tap':
      case 'DoubleTap':
        return ActionParser.parseDoubleTapAction(response);
      case 'Wait':
        return ActionParser.parseWaitAction(response);
      case 'Take_over':
        return ActionParser.parseTakeOverAction(response);
      case 'Note':
        return { type: ActionType.Note } as SimpleAction;
      case 'Call_API':
        return ActionParser.parseCallAPIAction(response);
      case 'Interact':
        return { type: ActionType.Interact } as SimpleAction;
      case 'Drag':
        return ActionParser.parseDragAction(response);
      case 'Draw':
        return ActionParser.parseDrawAction(response);
      case 'Pinch In':
      case 'PinchIn':
        return ActionParser.parsePinchInAction(response);
      case 'Pinch Out':
      case 'PinchOut':
        return ActionParser.parsePinchOutAction(response);
      default:
        throw new ActionParseError(`未知的动作类型: ${actionType}`);
    }
  }

  /**
   * 解析 Tap 动作
   * 支持多种格式：
   * 1. element_coordinates=[x,y] - AutoGLM-Phone 格式
   * 2. element=[x,y] - 直接坐标（旧格式）
   * 3. element=[[x1,y1,x2,y2]] - bbox格式，取中心点
   * 4. element=[x1,y1,x2,y2] - bbox格式（无嵌套），取中心点
   */
  private static parseTapAction(response: string): TapAction {
    // 先尝试匹配 AutoGLM-Phone 格式 element_coordinates=[x,y]
    const coordMatch = response.match(/element_coordinates=\[(\d+),\s*(\d+)\]/);
    if (coordMatch) {
      const messageMatch = response.match(/message="([^"]*)"/);
      return {
        type: ActionType.Tap,
        element: [parseInt(coordMatch[1]), parseInt(coordMatch[2])],
        message: messageMatch ? ActionParser.unescapeString(messageMatch[1]) : undefined
      };
    }

    // 尝试匹配 bbox 格式 [[x1,y1,x2,y2]]
    const bboxMatch = response.match(/element=\[\[(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\]\]/);
    if (bboxMatch) {
      const x1 = parseInt(bboxMatch[1]);
      const y1 = parseInt(bboxMatch[2]);
      const x2 = parseInt(bboxMatch[3]);
      const y2 = parseInt(bboxMatch[4]);
      const centerX = Math.round((x1 + x2) / 2);
      const centerY = Math.round((y1 + y2) / 2);
      console.info(`ActionParser: Tap bbox [[${x1},${y1},${x2},${y2}]] -> center [${centerX},${centerY}]`);
      
      const messageMatch = response.match(/message="([^"]*)"/);
      return {
        type: ActionType.Tap,
        element: [centerX, centerY],
        message: messageMatch ? ActionParser.unescapeString(messageMatch[1]) : undefined
      };
    }

    // 尝试匹配 bbox 格式 [x1,y1,x2,y2]（4个数字）
    const bbox4Match = response.match(/element=\[(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\]/);
    if (bbox4Match) {
      const x1 = parseInt(bbox4Match[1]);
      const y1 = parseInt(bbox4Match[2]);
      const x2 = parseInt(bbox4Match[3]);
      const y2 = parseInt(bbox4Match[4]);
      const centerX = Math.round((x1 + x2) / 2);
      const centerY = Math.round((y1 + y2) / 2);
      console.info(`ActionParser: Tap bbox [${x1},${y1},${x2},${y2}] -> center [${centerX},${centerY}]`);
      
      const messageMatch = response.match(/message="([^"]*)"/);
      return {
        type: ActionType.Tap,
        element: [centerX, centerY],
        message: messageMatch ? ActionParser.unescapeString(messageMatch[1]) : undefined
      };
    }

    // 匹配简单坐标格式 element=[x,y]（旧格式）
    const elementMatch = response.match(/element=\[(\d+),\s*(\d+)\]/);
    if (!elementMatch) {
      throw new ActionParseError('Tap 动作缺少 element 或 element_coordinates 参数');
    }

    const messageMatch = response.match(/message="([^"]*)"/);

    return {
      type: ActionType.Tap,
      element: [parseInt(elementMatch[1]), parseInt(elementMatch[2])],
      message: messageMatch ? ActionParser.unescapeString(messageMatch[1]) : undefined
    };
  }

  /**
   * 解析 Swipe 动作
   * 支持两种格式：
   * 1. start_coordinates=[x1,y1], end_coordinates=[x2,y2] - AutoGLM-Phone 格式
   * 2. start=[x1,y1], end=[x2,y2] - 旧格式
   */
  private static parseSwipeAction(response: string): SwipeAction {
    // 先尝试匹配 AutoGLM-Phone 格式 start_coordinates/end_coordinates
    const startCoordMatch = response.match(/start_coordinates=\[(\d+),\s*(\d+)\]/);
    const endCoordMatch = response.match(/end_coordinates=\[(\d+),\s*(\d+)\]/);

    if (startCoordMatch && endCoordMatch) {
      return {
        type: ActionType.Swipe,
        start: [parseInt(startCoordMatch[1]), parseInt(startCoordMatch[2])],
        end: [parseInt(endCoordMatch[1]), parseInt(endCoordMatch[2])]
      };
    }

    // 回退到旧格式 start/end
    const startMatch = response.match(/start=\[(\d+),\s*(\d+)\]/);
    const endMatch = response.match(/end=\[(\d+),\s*(\d+)\]/);

    if (!startMatch || !endMatch) {
      throw new ActionParseError('Swipe 动作缺少 start/end 或 start_coordinates/end_coordinates 参数');
    }

    return {
      type: ActionType.Swipe,
      start: [parseInt(startMatch[1]), parseInt(startMatch[2])],
      end: [parseInt(endMatch[1]), parseInt(endMatch[2])]
    };
  }

  /**
   * 解析 Launch 动作
   */
  private static parseLaunchAction(response: string): LaunchAction {
    const appMatch = response.match(/app="([^"]*)"/);
    if (!appMatch) {
      throw new ActionParseError('Launch 动作缺少 app 参数');
    }

    return {
      type: ActionType.Launch,
      app: ActionParser.unescapeString(appMatch[1])
    };
  }

  /**
   * 解析 Wait 动作
   */
  private static parseWaitAction(response: string): WaitAction {
    const durationMatch = response.match(/duration="(\d+)\s*seconds?"/);
    let duration = 1; // 默认 1 秒
    
    if (durationMatch) {
      duration = parseInt(durationMatch[1]);
    } else {
      // 尝试直接匹配数字
      const numMatch = response.match(/duration="?(\d+)"?/);
      if (numMatch) {
        duration = parseInt(numMatch[1]);
      }
    }
    
    // 限制最大等待时间为 1 秒，避免等待过长
    if (duration > 1) {
      console.warn(`ActionParser: Wait duration ${duration}s too long, capped to 1s`);
      duration = 1;
    }

    return {
      type: ActionType.Wait,
      duration: duration
    };
  }

  /**
   * 解析 Long Press 动作
   */
  private static parseLongPressAction(response: string): LongPressAction {
    const elementMatch = response.match(/element=\[(\d+),\s*(\d+)\]/);
    if (!elementMatch) {
      throw new ActionParseError('Long Press 动作缺少 element 参数');
    }

    return {
      type: ActionType.LongPress,
      element: [parseInt(elementMatch[1]), parseInt(elementMatch[2])]
    };
  }

  /**
   * 解析 Double Tap 动作
   */
  private static parseDoubleTapAction(response: string): DoubleTapAction {
    const elementMatch = response.match(/element=\[(\d+),\s*(\d+)\]/);
    if (!elementMatch) {
      throw new ActionParseError('Double Tap 动作缺少 element 参数');
    }

    return {
      type: ActionType.DoubleTap,
      element: [parseInt(elementMatch[1]), parseInt(elementMatch[2])]
    };
  }

  /**
   * 解析 Take_over 动作
   */
  private static parseTakeOverAction(response: string): TakeOverAction {
    const messageMatch = response.match(/message="([^"]*)"/);
    if (!messageMatch) {
      return {
        type: ActionType.TakeOver,
        message: '需要用户协助'
      };
    }

    return {
      type: ActionType.TakeOver,
      message: ActionParser.unescapeString(messageMatch[1])
    };
  }

  /**
   * 解析 Call_API 动作
   */
  private static parseCallAPIAction(response: string): CallAPIAction {
    const instructionMatch = response.match(/instruction="([^"]*)"/);
    if (!instructionMatch) {
      return {
        type: ActionType.CallAPI,
        instruction: ''
      };
    }

    return {
      type: ActionType.CallAPI,
      instruction: ActionParser.unescapeString(instructionMatch[1])
    };
  }

  /**
   * 解析 Drag 动作
   */
  private static parseDragAction(response: string): DragAction {
    const startMatch = response.match(/start=\[(\d+),\s*(\d+)\]/);
    const endMatch = response.match(/end=\[(\d+),\s*(\d+)\]/);

    if (!startMatch || !endMatch) {
      throw new ActionParseError('Drag 动作缺少 start 或 end 参数');
    }

    return {
      type: ActionType.Drag,
      start: [parseInt(startMatch[1]), parseInt(startMatch[2])],
      end: [parseInt(endMatch[1]), parseInt(endMatch[2])]
    };
  }

  /**
   * 解析 Draw 动作
   */
  private static parseDrawAction(response: string): DrawAction {
    // 匹配 path=[[x1,y1],[x2,y2],...] 格式
    const pathMatch = response.match(/path=\[((?:\[\d+,\s*\d+\],?\s*)+)\]/);
    if (!pathMatch) {
      throw new ActionParseError('Draw 动作缺少 path 参数');
    }

    const pointMatches = pathMatch[1].matchAll(/\[(\d+),\s*(\d+)\]/g);
    const path: [number, number][] = [];
    for (const match of pointMatches) {
      path.push([parseInt(match[1]), parseInt(match[2])]);
    }

    if (path.length < 2) {
      throw new ActionParseError('Draw 动作的 path 至少需要2个点');
    }

    return {
      type: ActionType.Draw,
      path: path
    };
  }

  /**
   * 解析 Pinch In 动作
   */
  private static parsePinchInAction(response: string): PinchInAction {
    const centerMatch = response.match(/center=\[(\d+),\s*(\d+)\]/);
    if (!centerMatch) {
      throw new ActionParseError('Pinch In 动作缺少 center 参数');
    }

    const scaleMatch = response.match(/scale=([\d.]+)/);

    return {
      type: ActionType.PinchIn,
      center: [parseInt(centerMatch[1]), parseInt(centerMatch[2])],
      scale: scaleMatch ? parseFloat(scaleMatch[1]) : 0.5
    };
  }

  /**
   * 解析 Pinch Out 动作
   */
  private static parsePinchOutAction(response: string): PinchOutAction {
    const centerMatch = response.match(/center=\[(\d+),\s*(\d+)\]/);
    if (!centerMatch) {
      throw new ActionParseError('Pinch Out 动作缺少 center 参数');
    }

    const scaleMatch = response.match(/scale=([\d.]+)/);

    return {
      type: ActionType.PinchOut,
      center: [parseInt(centerMatch[1]), parseInt(centerMatch[2])],
      scale: scaleMatch ? parseFloat(scaleMatch[1]) : 2.0
    };
  }

  /**
   * 转义字符串中的特殊字符
   */
  private static escapeString(str: string): string {
    return str
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"')
      .replace(/\n/g, '\\n')
      .replace(/\r/g, '\\r')
      .replace(/\t/g, '\\t');
  }

  /**
   * 反转义字符串
   */
  private static unescapeString(str: string): string {
    return str
      .replace(/\\n/g, '\n')
      .replace(/\\r/g, '\r')
      .replace(/\\t/g, '\t')
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\');
  }
}
