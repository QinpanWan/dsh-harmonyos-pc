/**
 * DshApiClient：dsh 服务的 RPC 客户端（官方 0.1.6+「typert gateway」协议）。
 *
 * 与官方 Web 前端走**同一套物理协议**（@deepseek-ai/dsh-api-gateway + dsh-client-connection）：
 *
 * 1. 单次 RPC：`POST /api/<namespace>/<method>`
 *    body  = `{ type: 'client-request', rpcId, method, payload: { args: {...} } }`
 *    reply = `{ type: 'server-response', rpcId, result: { ok: true, value } | { ok: false, error } }`
 *    参数名**由描述符决定**（`_request` / `request` / 无参），不是统一信封。
 * 2. 会话事件流：WebSocket `/api/remote.mux`（旧版 SSE `/api/events.mux` 已下线）
 *    打开：`{ type: 'open', streamId, endpoint: 'session/follow', payload: { args: { request: {...} } } }`
 *    下行：`{ type: 'item'|'error'|'end', streamId, value | error }`
 *    帧：`snapshot`（历史 + 投影基线）/ `event`（durable 事件）/ `assistant-stream`（实时增量）
 * 3. 认证：`GET /`（本机回环）→ 303 + `set-cookie: dsh-auth-*`（30 天），
 *    之后所有 RPC 与 WebSocket 握手都要带 `Cookie` 头；401 时自动重新取一次。
 *
 * 参照华为开发者文档《HTTP 数据请求》《WebSocket 连接》：@ohos.net.http 负责单次 RPC 与
 * cookie 交换，@ohos.net.webSocket 负责事件流（旧版 SSE 长连接已不再需要）。
 */
import { http, webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 一条 Remote 流（session/follow）的下行接收口。
 * - onFrame：`item` 帧的 value（snapshot / event / assistant-stream）
 * - onEnd：`error` / `end` 帧或连接断开（reason 已本地化，可直接展示）
 */
export interface DshStreamSink {
  onFrame: (value: Record<string, Object>) => void;
  onEnd: (reason: string) => void;
}

/**
 * mux 事件流日志域。hilog 的**应用**域范围是 [0x0, 0xFFFF]（`hilog -h` 的 Domain description），
 * 超出范围的域会被静默丢弃（0xD0042 那种 5 位十六进制就属于这种，真机一条都抓不到）。
 * 真机排障：`hdc shell "hilog | grep DshMux"`（与 `DshDirect` 同域，靠 TAG 区分）。
 * 采样点都取「一次性的状态跃迁」（连上/断开/流错误），不做逐帧打印（一次回答约 200 帧）。
 */
const MUX_LOG_DOMAIN: number = 0xD004;

/** 一条已登记的流：端点 + 打开参数（重连后按原样重开）。 */
class DshStream {
  streamId: string = '';
  endpoint: string = '';
  args: Record<string, Object> = {};
  sink: DshStreamSink | null = null;

  constructor(streamId: string, endpoint: string, args: Record<string, Object>, sink: DshStreamSink) {
    this.streamId = streamId;
    this.endpoint = endpoint;
    this.args = args;
    this.sink = sink;
  }
}

export class DshApiClient {
  private baseUrl: string = '';
  private cookie: string = '';
  /** WebSocket mux（全局一条；每会话一条 follow 逻辑流复用同一条物理连接） */
  private socket: webSocket.WebSocket | null = null;
  private socketOpen: boolean = false;
  private streams: Map<string, DshStream> = new Map();
  private streamSeq: number = 0;
  private closed: boolean = true;
  private reconnectTimer: number = -1;
  private reconnectAttempt: number = 0;
  private onOpenCallback: (() => void) | null = null;
  private onErrorCallback: ((message: string) => void) | null = null;
  /** 401 只自动重取一次 cookie，避免死循环 */
  private authRetried: boolean = false;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url.replace(/\/+$/, '');
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  /** 复用的持久 cookie（由调用方落盘/注入；空串表示未登录） */
  setCookie(value: string): void {
    this.cookie = value;
  }

  getCookie(): string {
    return this.cookie;
  }

  private mintRpcId(): string {
    return 'rpc-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 0xffffff).toString(36);
  }

  /**
   * 换取登录 cookie（本机回环由 Host 直接签发 30 天会话）。
   *
   * ⚠️ 必须 `followRedirects: false`：dsh 的 `GET /` 在**没带 cookie** 时回
   * `303 See Other` + `location: /` + `set-cookie`，带上这枚 cookie 再请求同一路径才回 200。
   * 这是「靠 cookie 收敛的自重定向」：默认跟随重定向的客户端会在 303→303→… 里打转
   * （或在最后一跳丢掉 `set-cookie`），最终一枚 cookie 都拿不到 → 之后所有 RPC 401 →
   * 客户端表现就是「一直连不上本地服务」。这里关掉自动重定向，直接收第一跳的 `set-cookie`。
   *
   * @returns 新的 `Cookie` 头值；取不到时返回空串（调用方据此提示「服务端要 token」）
   */
  async login(): Promise<string> {
    const req: http.HttpRequest = http.createHttp();
    try {
      const resp: http.HttpResponse = await req.request(this.baseUrl + '/', {
        method: http.RequestMethod.GET,
        header: { 'Accept': 'text/html' },
        // maxRedirects: 0 = 不跟随重定向（API 23+）：303 的第一跳响应头里才有 set-cookie。
        // 老设备上这个字段会被忽略（仍跟随），所以下面还有 resp.cookies 兜底。
        maxRedirects: 0,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      let cookie: string = this.parseSetCookie(this.headerValue(resp, 'set-cookie'));
      if (cookie.length === 0) {
        // 兜底：网络库把重定向链上的 cookie 汇总在 resp.cookies（老设备不走 maxRedirects 时用）
        cookie = this.parseSetCookie(resp.cookies);
      }
      if (cookie.length > 0) {
        this.cookie = cookie;
      }
      return this.cookie;
    } catch (e) {
      return '';
    } finally {
      req.destroy();
    }
  }

  /** 取响应头（大小写不敏感：服务端/网络库对头名大小写不保证一致）。 */
  private headerValue(resp: http.HttpResponse, name: string): Object | undefined {
    const headers: Record<string, Object> = resp.header as Record<string, Object>;
    if (headers === undefined || headers === null) {
      return undefined;
    }
    const lower: string = name.toLowerCase();
    const keys: string[] = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === lower) {
        return headers[keys[i]];
      }
    }
    return undefined;
  }

  /** `set-cookie` 头 → `name=value`（多枚 cookie 时取第一枚；大小写不敏感） */
  private parseSetCookie(raw: Object | undefined): string {
    if (raw === undefined || raw === null) {
      return '';
    }
    let text: string = '';
    if (typeof raw === 'string') {
      text = raw;
    } else if (raw instanceof Array) {
      const list: Array<string> = raw as Array<string>;
      text = list.length > 0 ? list[0] : '';
    } else {
      text = String(raw);
    }
    const semi: number = text.indexOf(';');
    const first: string = semi === -1 ? text : text.substring(0, semi);
    return first.trim();
  }

  private authHeader(): Record<string, Object> {
    const header: Record<string, Object> = { 'Content-Type': 'application/json' };
    if (this.cookie.length > 0) {
      header['Cookie'] = this.cookie;
    }
    return header;
  }

  /**
   * 单次 RPC 调用：POST /api/<method>，成功返回 result.value，业务错误抛异常。
   * @param method - 形如 `session/list`、`permissionPresets/catalog`
   * @param args - 描述符声明的参数对象（键名必须与描述符一致，如 `_request` / `request`）
   */
  async call(method: string, args: Record<string, Object>): Promise<Record<string, Object>> {
    const payload: Record<string, Object> = { 'args': args };
    const reply: Record<string, Object> = await this.post(method, payload, true);
    const result: Record<string, Object> = reply['result'] as Record<string, Object>;
    if (result === undefined || result === null) {
      throw new Error('响应格式错误');
    }
    if (result['ok'] === true) {
      return result['value'] as Record<string, Object>;
    }
    const err: Record<string, Object> = result['error'] as Record<string, Object>;
    let code: string = 'unknown';
    let message: string = '未知错误';
    if (err !== undefined && err !== null) {
      code = String(err['code']);
      message = String(err['message']);
    }
    throw new Error(code + ': ' + message);
  }

  /** 原始 POST（含 401 自动重登录一次） */
  private async post(method: string, payload: Record<string, Object>, allowRetry: boolean): Promise<Record<string, Object>> {
    const envelope: Record<string, Object> = {
      'type': 'client-request',
      'rpcId': this.mintRpcId(),
      'method': method,
      'payload': payload
    };
    const req: http.HttpRequest = http.createHttp();
    let resp: http.HttpResponse;
    try {
      resp = await req.request(this.baseUrl + '/api/' + method, {
        method: http.RequestMethod.POST,
        header: this.authHeader(),
        extraData: JSON.stringify(envelope),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 60000
      });
    } catch (e) {
      req.destroy();
      throw new Error('无法连接 dsh 服务：' + String(e));
    }
    req.destroy();
    if (resp.responseCode === 401 && allowRetry && !this.authRetried) {
      this.authRetried = true;
      const cookie: string = await this.login();
      if (cookie.length > 0) {
        return await this.post(method, payload, false);
      }
    }
    if (resp.responseCode !== 200) {
      throw new Error('HTTP ' + resp.responseCode.toString());
    }
    const text: string = resp.result as string;
    let full: Record<string, Object>;
    try {
      full = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      throw new Error('响应不是合法 JSON');
    }
    return full;
  }

  // —— 会话域方法（与官方 Remote 端点一一对应） ——

  /** session/list：列出会话（updatedAt 降序，含 cwd 与投影：title / permissions / agentPreset） */
  async listSessions(): Promise<Array<Record<string, Object>>> {
    const filter: Record<string, Object> = {};
    const value: Record<string, Object> = await this.call('session/list', { '_request': filter });
    const items: Array<Record<string, Object>> = value['items'] as Array<Record<string, Object>>;
    return items === undefined || items === null ? [] : items;
  }

  /** session/create：创建会话（cwd 为空用 host 默认目录；agentPreset 为空用部署默认） */
  async createSession(cwd: string, agentPreset: string): Promise<string> {
    const request: Record<string, Object> = {};
    if (cwd.length > 0) {
      request['cwd'] = cwd;
    }
    if (agentPreset.length > 0) {
      request['agentPreset'] = agentPreset;
    }
    const value: Record<string, Object> = await this.call('session/create', { 'request': request });
    return String(value['sessionId']);
  }

  /** agentPresets/list：部署提供的对话模式（预设）列表 */
  async agentPresetList(): Promise<Array<Record<string, Object>>> {
    const value: Record<string, Object> = await this.call('agentPresets/list', {});
    const presets: Array<Record<string, Object>> = value['presets'] as Array<Record<string, Object>>;
    return presets === undefined || presets === null ? [] : presets;
  }

  /** permissionPresets/catalog：工作区权限（沙箱模式 + 审批策略）目录 */
  async permissionCatalog(): Promise<Array<Record<string, Object>>> {
    const value: Record<string, Object> = await this.call('permissionPresets/catalog', {});
    const options: Array<Record<string, Object>> = value['options'] as Array<Record<string, Object>>;
    return options === undefined || options === null ? [] : options;
  }

  /**
   * session/modelCatalog：本部署可路由的模型目录（`default` + `groups[].models[]`）。
   * 输入行右侧「模型」胶囊的数据源（上游 conversation.input.model 座位）。
   */
  async modelCatalog(): Promise<Record<string, Object>> {
    return await this.call('session/modelCatalog', {});
  }

  /**
   * session/selectModel：把当前会话的模型切到 provider/model（可选推理档位）。
   * 会话级 durable 投影，服务端会回推 modelSelection，UI 不必自己记。
   */
  async selectModel(sessionId: string, provider: string, model: string, reasoningEffort: string): Promise<void> {
    const request: Record<string, Object> = {
      'sessionId': sessionId,
      'provider': provider,
      'model': model
    };
    if (reasoningEffort.length > 0) {
      request['reasoningEffort'] = reasoningEffort;
    }
    await this.call('session/selectModel', { 'request': request });
  }

  /** session/prompt：发送消息（mode=queue 排队执行） */
  async prompt(sessionId: string, text: string): Promise<void> {
    const content: Array<Record<string, Object>> = [];
    content.push({ 'type': 'text', 'text': text });
    const request: Record<string, Object> = {
      'requestId': this.mintRpcId(),
      'sessionId': sessionId,
      'mode': 'queue',
      'content': content
    };
    await this.call('session/prompt', { 'request': request });
  }

  /** session/cancel：停止当前回合 */
  async cancel(sessionId: string): Promise<void> {
    const request: Record<string, Object> = { 'sessionId': sessionId };
    await this.call('session/cancel', { 'request': request });
  }

  /** session/rename：重命名会话 */
  async rename(sessionId: string, title: string): Promise<void> {
    const request: Record<string, Object> = { 'sessionId': sessionId, 'title': title };
    await this.call('session/rename', { 'request': request });
  }

  /** commands/execute：执行一条斜杠命令（权限切换走 `/permission <preset>`，与网页端同一写入路径） */
  async executeCommand(sessionId: string, line: string): Promise<string> {
    const args: Record<string, Object> = {
      'agentId': sessionId,
      'line': line,
      'submittedAttachments': []
    };
    const value: Record<string, Object> = await this.call('commands/execute', args);
    const result: Record<string, Object> = value['result'] as Record<string, Object>;
    if (result === undefined || result === null) {
      return '';
    }
    if (result['kind'] === 'error') {
      throw new Error(String(result['text']));
    }
    return String(result['text']);
  }

  /** settings/describe：探测服务连通性（旧版 host.describe 已不存在） */
  async describe(): Promise<Record<string, Object>> {
    return await this.call('settings/describe', {});
  }

  // —— 事件流（WebSocket mux） ——

  /**
   * 连接事件流。断开后指数退避自动重连（2s→…→30s），重连成功会把已登记的 follow 流原样重开。
   * @param onOpen - 每次握手成功（含重连）后回调
   * @param onError - 断开/握手失败（message 已本地化）
   */
  openMux(onOpen: () => void, onError: (message: string) => void): void {
    this.closeMux();
    this.onOpenCallback = onOpen;
    this.onErrorCallback = onError;
    this.closed = false;
    this.reconnectAttempt = 0;
    this.startSocket();
  }

  /** 关闭事件流（同时取消重连与全部逻辑流） */
  closeMux(): void {
    this.closed = true;
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    const socket = this.socket;
    this.socket = null;
    this.socketOpen = false;
    if (socket !== null) {
      try {
        socket.off('message');
        socket.off('close');
        socket.off('error');
        socket.close();
      } catch (e) {
        // 已关闭的 socket 再关一次会抛，忽略
      }
    }
  }

  private wsUrl(): string {
    const plain: string = this.baseUrl.indexOf('https://') === 0
      ? 'wss://' + this.baseUrl.substring(8)
      : (this.baseUrl.indexOf('http://') === 0 ? 'ws://' + this.baseUrl.substring(7) : this.baseUrl);
    return plain + '/api/remote.mux';
  }

  private startSocket(): void {
    const header: Record<string, Object> = {};
    if (this.cookie.length > 0) {
      header['Cookie'] = this.cookie;
    }
    // ⚠️ 必须带 `supportOriginPort: true`（API 26 起）：ArkTS 的 netstack 默认把握手
    // `Origin` 写成**不带端口**的 `ws://<host>`（源码：websocket_exec.cpp 的 ParseHost，
    // `origin = supportOriginPort ? host : address`）。dsh 的 Host/Origin fence
    // （dsh-client-connection 的 isTrustedApiRequest：`new URL(origin).host === host`）
    // 拿它跟带端口的 `Host`（127.0.0.1:3080）比 → 403，握手直接被拒 ⇒ 事件流永远连不上，
    // 侧栏实时刷新、思维链/正文流式全都收不到（真机实测：`UNEXPECTED 403`）。
    // 打开这一项后 Origin 变成 `ws://<host>:<port>`，与 Host 同端口，fence 放行。
    const options: webSocket.WebSocketRequestOptions = { header: header, supportOriginPort: true };
    const socket: webSocket.WebSocket = webSocket.createWebSocket();
    this.socket = socket;
    this.socketOpen = false;
    socket.on('open', (err: BusinessError, value: Object) => {
      this.socketOpen = true;
      this.reconnectAttempt = 0;
      hilog.info(MUX_LOG_DOMAIN, 'DshMux', '事件流已连接 %{public}s', this.wsUrl());
      this.reopenStreams();
      if (this.onOpenCallback !== null) {
        this.onOpenCallback();
      }
    });
    socket.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (typeof value === 'string') {
        this.dispatch(value);
      } else {
        try {
          const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
          this.dispatch(decoder.decodeToString(new Uint8Array(value as ArrayBuffer)));
        } catch (e) {
          // 非文本帧（理论上不存在）忽略
        }
      }
    });
    socket.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      this.socketOpen = false;
      hilog.warn(MUX_LOG_DOMAIN, 'DshMux', '事件流关闭 code=%{public}d reason=%{public}s',
        value === undefined || value === null ? 0 : value.code,
        value === undefined || value === null ? '' : String(value.reason));
      this.scheduleReconnect();
    });
    socket.on('error', (err: BusinessError) => {
      this.socketOpen = false;
      hilog.error(MUX_LOG_DOMAIN, 'DshMux', '事件流错误 %{public}s',
        err === undefined || err === null ? '' : String(err.message));
      this.scheduleReconnect();
    });
    try {
      socket.connect(this.wsUrl(), options, (err: BusinessError, ok: boolean) => {
        if (!ok && !this.closed) {
          hilog.error(MUX_LOG_DOMAIN, 'DshMux', '事件流握手失败 %{public}s',
            err === undefined || err === null ? '' : String(err.message));
          this.scheduleReconnect();
        }
      });
    } catch (e) {
      hilog.error(MUX_LOG_DOMAIN, 'DshMux', '事件流连接异常 %{public}s', String(e));
      this.scheduleReconnect();
    }
  }

  /** 重连后按原样重开所有逻辑流（streamId 保留，服务端按新连接重建） */
  private reopenStreams(): void {
    for (const stream of this.streams.values()) {
      this.sendOpen(stream);
    }
  }

  private sendOpen(stream: DshStream): void {
    const socket = this.socket;
    if (socket === null || !this.socketOpen) {
      return;
    }
    const payload: Record<string, Object> = { 'args': stream.args };
    const message: Record<string, Object> = {
      'type': 'open',
      'streamId': stream.streamId,
      'endpoint': stream.endpoint,
      'payload': payload
    };
    try {
      socket.send(JSON.stringify(message), (err: BusinessError, ok: boolean) => {
      });
    } catch (e) {
      // 发送失败由 close/error 事件统一走重连
    }
  }

  private scheduleReconnect(): void {
    if (this.closed) {
      return;
    }
    if (this.onErrorCallback !== null) {
      this.onErrorCallback('事件流断开，自动重连中…');
    }
    let delay: number = 2000 * Math.pow(2, this.reconnectAttempt);
    if (delay > 30000) {
      delay = 30000;
    }
    this.reconnectAttempt++;
    this.reconnectTimer = setTimeout(() => {
      if (this.closed) {
        return;
      }
      this.startSocket();
    }, delay);
  }

  /** 解析一条 mux 下行消息并投递给对应逻辑流 */
  private dispatch(text: string): void {
    let message: Record<string, Object>;
    try {
      message = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      return;
    }
    const streamId: string = String(message['streamId']);
    const stream: DshStream | undefined = this.streams.get(streamId);
    if (stream === undefined || stream.sink === null) {
      return;
    }
    const kind: string = String(message['type']);
    if (kind === 'item') {
      const value: Record<string, Object> = message['value'] as Record<string, Object>;
      if (value !== undefined && value !== null) {
        stream.sink.onFrame(value);
      }
      return;
    }
    if (kind === 'error') {
      const error: Record<string, Object> = message['error'] as Record<string, Object>;
      let reason: string = '事件流错误';
      if (error !== undefined && error !== null) {
        reason = String(error['message']);
      }
      hilog.warn(MUX_LOG_DOMAIN, 'DshMux', '流错误 %{public}s: %{public}s', streamId, reason);
      stream.sink.onEnd(reason);
      this.streams.delete(streamId);
      return;
    }
    if (kind === 'end') {
      stream.sink.onEnd('');
      this.streams.delete(streamId);
    }
  }

  /**
   * 订阅一个会话的事件流（历史快照 + 实时事件 + 实时增量）。
   * @param sessionId - 会话 id
   * @param sink - 接收口
   * @returns 逻辑流 id（可用于 closeStream）
   */
  followSession(sessionId: string, sink: DshStreamSink): string {
    this.streamSeq++;
    const streamId: string = 'follow-' + this.streamSeq.toString();
    const address: Record<string, Object> = { 'kind': 'session', 'sessionId': sessionId };
    const request: Record<string, Object> = {
      'address': address,
      'maxMessages': 200,
      'assistantStream': true
    };
    const args: Record<string, Object> = { 'request': request };
    const stream: DshStream = new DshStream(streamId, 'session/follow', args, sink);
    this.streams.set(streamId, stream);
    this.sendOpen(stream);
    return streamId;
  }

  /**
   * 订阅宿主全局事件流（`$events`）：宿主把 `api-session/added|removed|status|activity`
   * 等 Cordis 事件按原样转发给客户端（与官方 web 端 `ctx.remote.$on` 同一路）。
   * 侧栏会话列表的「实时出现 / 置顶 / 运行点」就靠这条流，不需要轮询 `session/list`。
   * @param sink - 接收口（value.type = `ready`（事件源就绪）或 `emit`（一条转发事件））
   * @returns 逻辑流 id（可用于 closeStream）
   */
  openHostEvents(sink: DshStreamSink): string {
    this.streamSeq++;
    const streamId: string = 'events-' + this.streamSeq.toString();
    // `$events` 只接受空 args：sendOpen 会把 stream.args 包成 `payload.args`，
    // 所以这里给的**就是** args 本体（真机实测：多包一层 `{args:{}}` 会被网关注回
    // `gateway/arguments-invalid: forwarded Remote event stream requires an empty args object`）。
    // ArkTS 不接受字面量空对象，所以先声明再传。
    const args: Record<string, Object> = {};
    const stream: DshStream = new DshStream(streamId, '$events', args, sink);
    this.streams.set(streamId, stream);
    this.sendOpen(stream);
    return streamId;
  }

  /** 关闭一条逻辑流 */
  closeStream(streamId: string): void {
    if (!this.streams.has(streamId)) {
      return;
    }
    this.streams.delete(streamId);
    const socket = this.socket;
    if (socket === null || !this.socketOpen) {
      return;
    }
    try {
      socket.send(JSON.stringify({ 'type': 'cancel', 'streamId': streamId }), (err: BusinessError, ok: boolean) => {
      });
    } catch (e) {
      // 忽略：连接已断时服务端流也随连接消失
    }
  }

  /** 当前事件流是否已连上 */
  isMuxOpen(): boolean {
    return this.socketOpen;
  }
}
/**
 * DeepSeekClient：内置直连模式（WorkBuddy 式「打开即用」）。
 * 不依赖 dsh 服务端，直接调用 DeepSeek 官方 API（OpenAI 兼容
 * /chat/completions，流式 SSE），与 dsh 模式共享同一套聊天 UI。
 *
 * ⚠️ 必须用 `requestInStream`（不是 `request`）：netstack 的 NAPI 层只在
 * 「流式请求」下才派发 `dataReceive` / `dataEnd`（实锤在 communication_netstack：
 * `http_exec.cpp` 的 `OnWritingMemoryBody` 与 `ProcessResponseBodyAndEmitEvents` 都以
 * `context->IsRequestInStream()` 为前提，`ON_DATA_END` 更是只在
 * `AsyncWorkRequestInStreamCallback` 里发出；`EnableRequestInStream()` 只由
 * `http_module.cpp` 的 `requestInStream` 调用）。用 `request()` 的话请求会**成功返回 200**
 * 但一个字节都不到回调 —— 界面表现就是「发出去没反应、也不报错」。
 *
 * 参照华为开发者文档《HTTP 数据请求》：`requestInStream` + on('dataReceive') 流式解析 SSE。
 */
export class DeepSeekClient {
  /** 官方默认端点（独立模式可在设置里改成任意 OpenAI 兼容端点，如本机 127.0.0.1:11434/v1）。 */
  static readonly API_URL: string = 'https://api.deepseek.com/v1';
  /**
   * 日志域（与 `DshMux` 同一个）。hilog 的应用域范围是 [0x0, 0xFFFF]，5 位十六进制的域会被
   * 静默丢弃 —— 原来写 0xD0042 时真机一条都抓不到，改成 0xD004 后 `hdc shell "hilog | grep DshDirect"` 才有效。
   */
  static readonly LOG_DOMAIN: number = 0xD004;
  /** 原文兜底（非 SSE 端点 / 错误详情）最多攒这么多字符，避免长回复白占内存。 */
  static readonly RAW_LIMIT: number = 8192;
  /** 读超时（毫秒）：netstack 把它映射成 curl 的 CURLOPT_TIMEOUT_MS = 整条响应的总时限。 */
  static readonly READ_TIMEOUT_MS: number = 600000;
  private endpoint: string = DeepSeekClient.API_URL;
  private request: http.HttpRequest | null = null;
  /** 当前这轮流式的取消钩子（用户点「停止」/ 开新回合时先撤掉上一轮）。 */
  private cancelHook: (() => void) | null = null;

  /** 设置接口地址（空串 / 只给主机时自动补 `/chat/completions`）。 */
  setEndpoint(baseUrl: string): void {
    this.endpoint = DeepSeekClient.chatUrl(baseUrl);
  }

  getEndpoint(): string {
    return this.endpoint;
  }

  /** 把用户填的「接口地址」归一化成一次性的 `/chat/completions` URL。 */
  static chatUrl(baseUrl: string): string {
    let url: string = baseUrl.trim();
    if (url.length === 0) {
      url = DeepSeekClient.API_URL;
    }
    if (url.endsWith('/chat/completions')) {
      return url;
    }
    url = url.replace(/\/+$/, '');
    // 官方端点填 `https://api.deepseek.com` 时补上版本段
    if (url === 'https://api.deepseek.com' || url === 'http://api.deepseek.com') {
      url += '/v1';
    }
    return url + '/chat/completions';
  }

  /** 停止当前生成（用户点「停止」）：按「正常结束」收尾，不把主动中止报成失败。 */
  stop(): void {
    const cancel: (() => void) | null = this.cancelHook;
    this.cancelHook = null;
    if (cancel !== null) {
      cancel();
    }
    if (this.request !== null) {
      this.request.destroy();
      this.request = null;
    }
  }

  /**
   * 流式对话。messages 形如 [{role: 'user'|'assistant', content: '…'}]，
   * systemPrompt 非空时作为首条 system 消息插入（独立模式的「对话模式」就落在这里）。
   * onDelta 逐块回调增量文本；onDone 正常结束；onError 失败。
   */
  chat(apiKey: string,
       model: string,
       messages: Array<Record<string, Object>>,
       onDelta: (text: string) => void,
       onDone: () => void,
       onError: (message: string) => void,
       systemPrompt: string = '',
       onReasoning: (text: string) => void = (text: string) => {}): void {
    this.stop();
    const req: http.HttpRequest = http.createHttp();
    this.request = req;
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    const started: number = Date.now();
    let buffer: string = '';
    let raw: string = '';
    let finished: boolean = false;
    let sawDelta: boolean = false;
    let sawReasoning: boolean = false;
    let chars: number = 0;
    let reasoningChars: number = 0;

    /**
     * 一条思维链增量。DeepSeek 的推理模型（deepseek-v4-flash 等）在 `delta.reasoning_content`
     * 里先吐完整段思考、再吐 `delta.content`；旧代码只认 content，所以思考期界面上
     * 一个字都没有（主人说的「思维链滚动不出来 / 没反应」）。
     */
    const emitReasoning = (text: string): void => {
      if (text.length === 0 || finished) {
        return;
      }
      if (!sawReasoning) {
        hilog.info(DeepSeekClient.LOG_DOMAIN, 'DshDirect', '思维链首块 %{public}dms（%{public}s）', Date.now() - started, model);
      }
      sawReasoning = true;
      reasoningChars += text.length;
      onReasoning(text);
    };

    /** 一条正文增量：过滤空块，记下「真的有内容」。 */
    const emit = (text: string): void => {
      if (text.length === 0 || finished) {
        return;
      }
      const first: boolean = !sawDelta;
      sawDelta = true;
      chars += text.length;
      if (first) {
        hilog.info(DeepSeekClient.LOG_DOMAIN, 'DshDirect', '正文首块 %{public}dms（%{public}s）', Date.now() - started, model);
      }
      onDelta(text);
    };

    /**
     * 收尾（只生效一次）。err 非空 = 失败；flush 为真时先吃下残帧并做非 SSE 兜底，
     * 真的一个字都没有才算「空回复」（HTTP 200 却没有任何数据块 = 最常见的静默假成功）。
     */
    const settle = (err: string, flush: boolean): void => {
      if (finished) {
        return;
      }
      let message: string = err;
      if (message.length === 0 && flush) {
        // 残帧里可能只剩半条思维链/正文，先吃掉再判空
        emitReasoning(DeepSeekClient.streamReasoning(buffer));
        emit(DeepSeekClient.streamText(buffer));
        if (!sawDelta) {
          const whole: string = DeepSeekClient.completionText(raw);
          if (whole.length > 0) {
            emit(whole);
          } else if (!sawReasoning) {
            const wholeReasoning: string = DeepSeekClient.completionReasoning(raw);
            if (wholeReasoning.length > 0) {
              emitReasoning(wholeReasoning);
            } else {
              message = '服务端没有返回任何内容（HTTP 200 但无数据块）';
            }
          }
        }
      }
      finished = true;
      this.cancelHook = null;
      if (message.length === 0) {
        hilog.info(DeepSeekClient.LOG_DOMAIN, 'DshDirect',
          '完成：正文 %{public}d 字 / 思维链 %{public}d 字 / %{public}dms',
          chars, reasoningChars, Date.now() - started);
        onDone();
      } else {
        hilog.error(DeepSeekClient.LOG_DOMAIN, 'DshDirect', '失败：%{public}s', message);
        onError(message);
      }
    };

    // 取消钩子：本轮流式被打断时按正常结束收尾（已到的文字留在气泡里）
    this.cancelHook = (): void => {
      settle('', false);
    };

    req.on('dataReceive', (data: ArrayBuffer) => {
      if (finished) {
        return;
      }
      const text: string = decoder.decodeToString(new Uint8Array(data), { stream: true });
      if (raw.length < DeepSeekClient.RAW_LIMIT) {
        raw += text;
      }
      buffer += text;
      // SSE 帧以空行分隔；分块边界可能落在半帧上，所以残帧留在 buffer 里等下一块
      const end: number = DeepSeekClient.frameBoundary(buffer);
      if (end > 0) {
        const frames: string[] = buffer.slice(0, end).split('\n\n');
        buffer = buffer.slice(end);
        for (let i = 0; i < frames.length; i++) {
          emitReasoning(DeepSeekClient.frameReasoning(frames[i]));
          emit(DeepSeekClient.frameText(frames[i]));
        }
      }
    });

    const withSystem: Array<Record<string, Object>> = [];
    if (systemPrompt.length > 0) {
      withSystem.push({ 'role': 'system', 'content': systemPrompt });
    }
    for (let i = 0; i < messages.length; i++) {
      withSystem.push(messages[i]);
    }
    const body: Record<string, Object> = {
      'model': model,
      'messages': withSystem,
      'stream': true
    };
    // 注意：流式模式下响应体不走 resp.result（netstack 不落盘），只按 dataReceive 事件下发；
    // 所以错误详情要靠上面的 raw 自己攒。
    req.requestInStream(this.endpoint, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + apiKey
      },
      extraData: JSON.stringify(body),
      connectTimeout: 10000,
      readTimeout: DeepSeekClient.READ_TIMEOUT_MS
    }).then((code: number) => {
      if (code >= 300) {
        settle('HTTP ' + code.toString() + (raw.length > 0 ? '：' + raw : ''), false);
      } else {
        settle('', true);
      }
    }).catch((e: BusinessError) => {
      settle('请求失败：' + String(e.message), false);
    });
  }

  /**
   * `buffer` 里最后一整帧的结束位置（没有完整帧时返回 0）。
   * 帧与帧之间用空行分隔；分块边界可能把一帧劈成两半，那半帧要留到下一块。
   */
  static frameBoundary(buffer: string): number {
    const at: number = buffer.lastIndexOf('\n\n');
    // 没有完整帧时 lastIndexOf 是 -1（注意 -1 + 2 = 1，不能直接加完再判 > 0，那会把首字符当帧切出去）
    return at === -1 ? 0 : at + 2;
  }

  /**
   * 把一段原文按 SSE 帧解析成增量文本（= `dataReceive` 里「切帧 + 解析」的纯逻辑版）。
   * 收尾时用来吃下没有以空行结尾的残帧；`scripts/direct-mode-check.mjs` 也拿它喂真流固件。
   */
  static streamText(raw: string): string {
    let text: string = '';
    const frames: string[] = raw.split('\n\n');
    for (let i = 0; i < frames.length; i++) {
      text += DeepSeekClient.frameText(frames[i]);
    }
    return text;
  }

  /**
   * 把一段原文里的思维链解析出来（收尾吃残帧用；与 `streamText` 同一套切帧规则）。
   */
  static streamReasoning(raw: string): string {
    let text: string = '';
    const frames: string[] = raw.split('\n\n');
    for (let i = 0; i < frames.length; i++) {
      text += DeepSeekClient.frameReasoning(frames[i]);
    }
    return text;
  }

  /**
   * 一帧 SSE 里 `delta.reasoning_content` 的增量（推理模型的思维链）。
   * 非推理模型不吐这个字段 → 返回空串，调用方原样忽略。
   */
  static frameReasoning(frame: string): string {
    return DeepSeekClient.frameField(frame, 'reasoning_content');
  }

  /**
   * 一帧 SSE（可能含多行 `data: {...}`）里的增量文本；坏帧/非 data 行一律跳过。
   * 抽成静态方法是为了让 `scripts/direct-mode-check.mjs` 能直接拿真流固件喂它。
   */
  static frameText(frame: string): string {
    return DeepSeekClient.frameField(frame, 'content');
  }

  /**
   * 一帧 SSE 里 `choices[0].delta.<field>` 的增量字符串。
   * 只认 `data:`（`data: {...}` / `data:{...}` 都收）；以 ':' 开头的 SSE 注释
   * （DeepSeek 长思考时的 keep-alive 心跳）与别的事件行在这里被跳过。
   */
  static frameField(frame: string, field: string): string {
    let text: string = '';
    const lines: string[] = frame.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (!line.startsWith('data:')) {
        continue;
      }
      const dataStr: string = line.slice(5).trim();
      if (dataStr === '[DONE]') {
        continue;
      }
      try {
        const json: Record<string, Object> = JSON.parse(dataStr) as Record<string, Object>;
        const choices: Array<Record<string, Object>> = json['choices'] as Array<Record<string, Object>>;
        if (choices === undefined || choices === null || choices.length === 0) {
          continue;
        }
        const delta: Record<string, Object> = choices[0]['delta'] as Record<string, Object>;
        if (delta === undefined || delta === null) {
          continue;
        }
        const value: Object = delta[field] as Object;
        if (value !== undefined && value !== null) {
          text += String(value);
        }
      } catch (e) {
        // 单行坏帧不影响整条流
      }
    }
    return text;
  }

  /** 非 SSE 兜底：整段原文其实是普通 `chat.completion` 时取它的思维链。 */
  static completionReasoning(raw: string): string {
    return DeepSeekClient.completionField(raw, 'reasoning_content');
  }

  /** 非 SSE 兜底：整段原文其实就是一条普通 `chat.completion`（端点忽略了 stream:true）。 */
  static completionText(raw: string): string {
    return DeepSeekClient.completionField(raw, 'content');
  }

  /** 非 SSE 兜底里 `choices[0].{message,delta}.<field>` 的整段文本。 */
  static completionField(raw: string, field: string): string {
    const start: number = raw.indexOf('{');
    if (start === -1) {
      return '';
    }
    try {
      const json: Record<string, Object> = JSON.parse(raw.slice(start)) as Record<string, Object>;
      const choices: Array<Record<string, Object>> = json['choices'] as Array<Record<string, Object>>;
      if (choices === undefined || choices === null || choices.length === 0) {
        return '';
      }
      const choice: Record<string, Object> = choices[0];
      const keys: string[] = ['message', 'delta'];
      for (let i = 0; i < keys.length; i++) {
        const block: Record<string, Object> = choice[keys[i]] as Record<string, Object>;
        if (block === undefined || block === null) {
          continue;
        }
        const value: Object = block[field] as Object;
        if (value !== undefined && value !== null) {
          return String(value);
        }
      }
    } catch (e) {
      // 不是 JSON（多半就是标准 SSE 文本），交给帧解析
    }
    return '';
  }
}
