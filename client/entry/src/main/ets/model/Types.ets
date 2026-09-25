/**
 * 数据模型：与 dsh HTTP API（@deepseek-ai/dsh-host-apiproxy 契约）对应的客户端类型。
 * 参照华为开发者文档《状态管理（V1）》：@Observed 用于观察 class 属性变化，
 * 与子组件中的 @ObjectLink 配合实现消息流式增量刷新。
 */

/**
 * 单条聊天消息（UI 投影）。
 * - role: user | assistant | tool
 * - status: streaming（流式生成中）| done | running（工具执行中）| error
 */
@Observed
export class ChatMessage {
  id: string = '';
  role: string = 'assistant';
  text: string = '';
  reasoning: string = '';
  toolName: string = '';
  toolArgs: string = '';
  status: string = 'done';
  time: number = 0;

  constructor(id: string, role: string, time: number) {
    this.id = id;
    this.role = role;
    this.time = time;
  }
}

/**
 * 会话摘要（session.list 返回项的 UI 投影）
 * 除标题外还携带「工作区（cwd）/ 工作区权限（permissions 投影）/ 对话模式（agentPreset 投影）」，
 * 首页的三个选择器都读这三个字段（对应上游 sidebar 的 cwd 与 Session 投影）。
 */
@Observed
export class DshSession {
  sessionId: string = '';
  title: string = '';
  updatedAt: number = 0;
  running: boolean = false;
  blank: boolean = true;
  /** 会话工作目录（工作区）；空串表示服务端默认目录 */
  cwd: string = '';
  /** 当前工作区权限预设（permissions 投影 currentValue） */
  permission: string = '';
  /** 该会话创建时绑定的对话模式（agentPreset 投影） */
  agentPreset: string = '';
  /** 该会话当前使用的模型（modelSelection 投影 lastUsed / next）；空串表示未知 */
  model: string = '';
  /** 该会话模型所属 provider（与 model 成对，session/selectModel 需要） */
  modelProvider: string = '';

  constructor(id: string) {
    this.sessionId = id;
    this.updatedAt = Date.now();
  }
}

/**
 * 富文本渲染块：用于消息文本中代码块与普通文本的区分
 */
export class TextBlock {
  text: string = '';
  isCode: boolean = false;

  constructor(text: string, isCode: boolean) {
    this.text = text;
    this.isCode = isCode;
  }
}
