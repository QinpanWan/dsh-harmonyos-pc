// dsh-huawei-local-llm: 接入华为 / 鸿蒙 PC 官方本地大模型。
// 服务端运行在 127.0.0.1:11434（华为「本地 AI 模型管理」内置，Ollama/OpenAI 兼容）。
// 提供的工具:
//   - huawei_local_llm     : 直连本地模型对话 (OpenAI 兼容 /v1/chat/completions 或 原生 /api/chat)
//   - huawei_local_models  : 列出本地可用模型 + 连通性/白名单诊断
// 同时把 provider 'huawei-local' 写入 dsh 的 llm-pi-ai.providers，并直接向 ctx.llm 注册一个
// 自包含的 OpenAI 兼容适配器（本机 llm-pi-ai 命名空间未挂载，仅写 settings.yaml 模型选择器读不到）。
import { defineTool } from "@deepseek-ai/dsh-tools";
import { homedir } from "node:os";
import { join } from "node:path";
import { readFileSync, copyFileSync } from "node:fs";
import yaml from "js-yaml";
import { writeFileAtomic, withFileLock } from "@deepseek-ai/dsh-atomic-write";
import { createProvider } from "@earendil-works/pi-ai";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import { PiAiAdapter, Config } from "@deepseek-ai/dsh-llm-pi-ai";

const name = "huawei-local-llm";
const inject = ["tools", "settings", "llm"];

const DEFAULT_BASE = "http://127.0.0.1:11434";
const DEFAULT_MODEL = "qwen3:8b";
const DEFAULT_TIMEOUT_MS = 120_000;
const PROVIDER_ID = "huawei-local";
const PROVIDER_DISPLAY = "华为官方本地大模型 (127.0.0.1:11434)";
const NO_COST = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };
const WHITELIST_RE = /not in the whitelist|白名单|whitelist/i;

/** 归一化来源地址：去掉末尾斜杠与 /v1，避免拼接重复。 */
function origin(base) {
  return String(base ?? DEFAULT_BASE).replace(/\/+$/, "").replace(/\/v1$/, "");
}

/** 当前来源地址（环境变量可覆盖）。 */
function currentOrigin() {
  return origin(process.env.HUAWEI_LLM_BASE_URL ?? DEFAULT_BASE);
}

/** 当前默认模型。 */
function currentModel() {
  return process.env.HUAWEI_LLM_MODEL ?? DEFAULT_MODEL;
}

/** 工具调用 / 请求头：允许通过环境变量注入 API Key 与任意附加头。 */
function requestHeaders(extra = {}) {
  const headers = { "Content-Type": "application/json", ...extra };
  if (process.env.HUAWEI_LLM_API_KEY) {
    headers.Authorization = `Bearer ${process.env.HUAWEI_LLM_API_KEY}`;
  }
  if (process.env.HUAWEI_LLM_HEADERS) {
    try {
      const parsed = JSON.parse(process.env.HUAWEI_LLM_HEADERS);
      if (parsed && typeof parsed === "object") Object.assign(headers, parsed);
    } catch {
      /* 忽略无效应答，静默降级 */
    }
  }
  return headers;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** 把 AbortSignal 与超时合并成一个信号控制器。 */
function withTimeout(signal, timeoutMs) {
  const controller = new AbortController();
  const effectiveMs = Number.isFinite(Number(timeoutMs)) && Number(timeoutMs) > 0 ? Number(timeoutMs) : DEFAULT_TIMEOUT_MS;
  const timer = setTimeout(() => controller.abort(new Error("timeout")), effectiveMs);
  const onAbort = () => controller.abort(signal?.reason);
  if (signal?.aborted) onAbort();
  else signal?.addEventListener?.("abort", onAbort, { once: true });
  return {
    signal: controller.signal,
    done: () => { clearTimeout(timer); signal?.removeEventListener?.("abort", onAbort); }
  };
}

/** 读取 HTTP 错误的 JSON（错误串用白名单/连接失败信息统一归类）。 */
async function errorMessage(resp) {
  let text = "";
  try { text = await resp.text(); } catch { /* ignore */ }
  let detail = text;
  try {
    const body = JSON.parse(text);
    detail = body?.error?.message ?? body?.error ?? detail;
  } catch { /* not JSON */ }
  const normalized = String(detail ?? text);
  return {
    text: normalized,
    whitelist: WHITELIST_RE.test(normalized)
  };
}

/** OpenAI 兼容 chat/completions 调用。 */
async function openaiChat({ model, messages, temperature, maxTokens, signal, timeoutMs }) {
  const url = `${currentOrigin()}/v1/chat/completions`;
  const guarded = withTimeout(signal, timeoutMs);
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: requestHeaders(),
      body: JSON.stringify({
        model,
        messages,
        ...(temperature === void 0 ? {} : { temperature }),
        ...(maxTokens === void 0 ? {} : { max_tokens: maxTokens }),
        stream: false
      }),
      signal: guarded.signal
    });
    if (!resp.ok) {
      const err = await errorMessage(resp);
      return { ok: false, error: err.text, whitelist: err.whitelist, from: "openai", model };
    }
    const data = await resp.json().catch(() => null);
    const choice = data?.choices?.[0];
    const content = choice?.message?.content ?? "";
    return {
      ok: true,
      from: "openai",
      model: data?.model ?? model,
      content,
      usage: data?.usage ?? void 0
    };
  } catch (error) {
    return { ok: false, error: String(error?.message ?? error), from: "openai", model };
  } finally {
    guarded.done();
  }
}

/** Ollama 原生 /api/chat 调用。 */
async function nativeChat({ model, messages, temperature, maxTokens, signal, timeoutMs }) {
  const url = `${currentOrigin()}/api/chat`;
  const guarded = withTimeout(signal, timeoutMs);
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: requestHeaders(),
      body: JSON.stringify({
        model,
        messages,
        ...(temperature === void 0 ? {} : { temperature }),
        ...(maxTokens === void 0 ? {} : { num_predict: maxTokens }),
        stream: false
      }),
      signal: guarded.signal
    });
    if (!resp.ok) {
      const err = await errorMessage(resp);
      return { ok: false, error: err.text, whitelist: err.whitelist, from: "native", model };
    }
    const data = await resp.json().catch(() => null);
    return {
      ok: true,
      from: "native",
      model: data?.model ?? model,
      content: data?.message?.content ?? "",
      usage: data?.prompt_eval_count !== void 0
        ? { prompt_tokens: data.prompt_eval_count, completion_tokens: data.eval_count }
        : void 0
    };
  } catch (error) {
    return { ok: false, error: String(error?.message ?? error), from: "native", model };
  } finally {
    guarded.done();
  }
}

/** 供工具使用：先用 OpenAI 兼容接口，失败再回退原生 Ollama 接口。 */
async function chat(args, signal) {
  const messages = [];
  if (args.system) messages.push({ role: "system", content: args.system });
  messages.push({ role: "user", content: args.prompt });
  const opts = {
    messages,
    temperature: args.temperature,
    maxTokens: args.maxTokens,
    signal,
    timeoutMs: args.timeoutMs
  };
  let result = await openaiChat({ ...opts, model: args.model ?? currentModel() });
  if (!result.ok) result = await nativeChat({ ...opts, model: args.model ?? currentModel() });
  return result;
}

/** 列出模型：同时探测 /v1/models 与 /api/tags，优先合并去重。 */
async function listModels(signal, timeoutMs) {
  const probes = [
    { url: `${currentOrigin()}/v1/models`, kind: "openai", pick: (d) => (d?.data ?? []).map((m) => m.id ?? m.name) },
    { url: `${currentOrigin()}/api/tags`, kind: "native", pick: (d) => (d?.models ?? []).map((m) => m.name ?? m.model) }
  ];
  const seen = new Set();
  const models = [];
  const notes = [];
  let whitelist = false;
  for (const probe of probes) {
    const guarded = withTimeout(signal, timeoutMs);
    try {
      const resp = await fetch(probe.url, { headers: requestHeaders(), signal: guarded.signal });
      if (!resp.ok) {
        const err = await errorMessage(resp);
        whitelist = whitelist || err.whitelist;
        notes.push(`${probe.kind}: ${err.text}`);
        continue;
      }
      const data = await resp.json().catch(() => null);
      const picked = data ? probe.pick(data) : [];
      for (const id of picked) {
        if (!seen.has(id)) { seen.add(id); models.push(id); }
      }
    } catch (error) {
      notes.push(`${probe.kind}: ${String(error?.message ?? error)}`);
    } finally {
      guarded.done();
    }
  }
  return { models, notes, whitelist };
}

/** 通用工具结果的数据结构与渲染。 */
const resultSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean", required: true },
    from: { type: "string" },
    model: { type: "string", required: true },
    content: { type: "string" },
    usage: { type: "object", additionalProperties: true },
    whitelist: { type: "boolean" },
    models: { type: "array", items: { type: "string" } },
    notes: { type: "array", items: { type: "string" } },
    error: { type: "string" }
  }
};

function whitelistHint() {
  return [
    "",
    "[白名单提示] 本地模型服务拒绝非白名单调用方（app is not in the whitelist）。",
    "作为鸿蒙普通进程，dsh 直接访问 127.0.0.1:11434 会被系统拦截。",
    "解法：① 在 dsh 所在应用的 module.json5 声明 ohos.permission.USE_AI 并加入本地AI白名单；"
      + "② 或经鸿蒙官方本地AI SDK/桥接转发；③ 或改用模型管理器的已授权入口/带上其签发的 app token（可用环境变量 HUAWEI_LLM_HEADERS 注入任意头）。"
  ].join("\n");
}

function renderResult(_args, value) {
  const lines = [];
  lines.push(`· ${value.ok ? "OK" : "FAIL"} · ${value.from ?? ""} · ${value.model}`);
  if (value.content) lines.push("", value.content);
  if (value.models?.length) {
    lines.push("", `本地模型 (${value.models.length})：`, ...value.models.map((id) => `- ${id}`));
  }
  if (value.notes?.length) lines.push("", `探测记录：`, ...value.notes.map((n) => `- ${n}`));
  if (value.error) lines.push("", `错误：${value.error}`);
  if (value.whitelist) lines.push(whitelistHint());
  return [{ type: "text", text: lines.join("\n") }];
}

function present(card, title, kind, rawInput) {
  return (args) => ({
    card,
    title,
    kind,
    ...(rawInput && args[rawInput] !== void 0 ? { rawInput: args[rawInput] } : {})
  });
}

/** dsh 设置文件路径（与 dsh 服务一致，位于 $DSH_HOME/settings.yaml）。 */
function settingsPath() {
  return join(homedir(), ".dsh", "settings.yaml");
}

/** 把 huawei-local 生成成 4 空格缩进的 YAML 块（供 providers 下方插入）。 */
function providerYamlBlock(models) {
  const modelLines = (models ?? []).map((m) =>
    `        - id: ${String(m.id).replace(/:/g, "\u003a")}\n          name: ${m.name}\n          contextWindow: ${m.contextWindow}\n          maxTokens: ${m.maxTokens}`
  ).join("\n");
  // 请求头里 Content-Type 是协议标记，不写入 provider 静态头；仅保留鉴权/自定义头。
  const headers = requestHeaders();
  const extra = Object.entries(headers).filter(([k]) => k.toLowerCase() !== "content-type");
  const headerLines = extra.map(([k, v]) => `        ${k}: ${JSON.stringify(String(v))}`).join("\n");
  return [
    `    ${PROVIDER_ID}:`,
    `      displayName: 华为官方本地大模型 (127.0.0.1:11434)`,
    `      api: openai-completions`,
    `      baseURL: ${currentOrigin()}/v1`,
    ...(extra.length ? [`      headers:`, headerLines] : []),
    `      models:`,
    modelLines
  ].join("\n");
}

/** 在 llm-pi-ai.providers 下、保留注释地插入 provider 块；已存在则返回原文。 */
function insertProviderIntoText(text, block) {
  const lines = text.split("\n");
  const li = lines.findIndex((l) => /^llm-pi-ai:\s*$/.test(l));
  if (li === -1) return text;
  let pi = -1;
  for (let i = li + 1; i < lines.length; i++) {
    const line = lines[i];
    if (line === "" || /^[ \t]*$/.test(line)) continue;
    if (/^[^ \t]/.test(line)) break;
    if (/^  providers:\s*$/.test(line)) { pi = i; break; }
  }
  if (pi === -1) return text;
  if (lines.some((l) => /^\s{4}huawei-local:/.test(l))) return text;
  lines.splice(pi + 1, 0, ...block.split("\n"));
  return lines.join("\n");
}

/** 幂等写入 provider 到 settings.yaml：先备份，插入后校验 YAML，再原子写回。 */
async function ensureProviderRegistered(models) {
  const path = settingsPath();
  const block = providerYamlBlock(models);
  let original;
  try { original = readFileSync(path, "utf8"); } catch { return "settings.yaml 不存在，跳过"; }
  const next = insertProviderIntoText(original, block);
  if (next === original) return "provider 已存在，跳过";
  let parsed;
  try { parsed = yaml.load(next); } catch (error) { return `写前校验失败(${String(error?.message ?? error)})`; }
  if (parsed?.["llm-pi-ai"]?.providers?.[PROVIDER_ID] === void 0) return "插入后未找到 huawei-local，跳过";
  // 写后回读校验；锁被占用时退化无锁原子写，仍失败则重试。
  for (let attempt = 0; attempt < 5; attempt++) {
    const wrote = await withFileLock(path, async () => {
      try { copyFileSync(path, `${path}.bak-huawei`); } catch { /* optional */ }
      await writeFileAtomic(path, next, {});
      return true;
    }, { waitMs: 1200 }).catch(() => {
      return writeFileAtomic(path, next, {}).then(() => true).catch(() => false);
    });
    if (wrote) {
      try {
        const now = yaml.load(readFileSync(path, "utf8"));
        if (now?.["llm-pi-ai"]?.providers?.[PROVIDER_ID] !== void 0) return "已写入";
      } catch { /* read-back failed; retry */ }
    }
    await sleep(400);
  }
  return "写入失败（多次重试后仍校验不到 provider）";
}


/** 默认 provider 模型列表（与 settings.yaml 默认一致）。 */
function defaultProviderModels() {
  return [
    { id: "qwen3:8b", name: "Qwen3 8B（华为本地）", contextWindow: 32768, maxTokens: 8192 },
    { id: "qwen3:14b", name: "Qwen3 14B（华为本地）", contextWindow: 32768, maxTokens: 8192 }
  ];
}

/**
 * 构建可直接注册进 ctx.llm 的 huawei-local 适配器。
 *
 * 不依赖 llm-pi-ai 命名空间的 settings 注册（本机该命名空间未挂载，
 * 仅往 settings.yaml 写 provider 模型选择器读不到），因此在这里自包含地
 * 用 pi-ai 的 createProvider + PiAiAdapter 造一个 OpenAI 兼容适配器。
 */
function buildPiAdapter(config) {
  const baseURL = `${currentOrigin()}/v1`;
  const source = Config({ providers: { [PROVIDER_ID]: {
    displayName: PROVIDER_DISPLAY,
    api: "openai-completions",
    baseURL,
    models: config.models ?? defaultProviderModels()
  } } }).providers[PROVIDER_ID];
  const models = source.models.map((m) => ({
    id: m.id,
    name: m.name ?? m.id,
    api: source.api,
    provider: PROVIDER_ID,
    baseUrl: source.baseURL,
    input: m.input && m.input.length > 0 ? [...m.input] : [...(source.defaultInput ?? ["text"])],
    cost: NO_COST,
    contextWindow: m.contextWindow,
    maxTokens: m.maxTokens,
    reasoning: false
  }));
  const piProvider = createProvider({
    id: PROVIDER_ID,
    name: source.displayName,
    baseUrl: source.baseURL,
    auth: {
      apiKey: {
        name: source.displayName,
        resolve: ({ credential }) => Promise.resolve({
          auth: credential?.key === void 0 ? {} : { apiKey: credential.key },
          source: source.displayName
        })
      }
    },
    models,
    api: openAICompletionsApi()
  });
  const profile = {
    ...source,
    provider: PROVIDER_ID,
    displayName: source.displayName,
    streamIdleTimeoutMs: 300_000,
    maxRequestImageBytes: 20 * 1024 * 1024,
    requestImagePixelBudget: 2048 * 2048,
    requestImageMaxBytes: 1024 * 1024,
    retryPolicy: void 0,
    configuredMaxTokens: new Map(),
    piProvider
  };
  return new PiAiAdapter({
    profiles: () => new Map([[PROVIDER_ID, profile]]),
    resolveApiKey: async () => void 0,
    auth: {}
  });
}

/** 把 huawei-local 直接注册为 llm 适配器（已在时跳过），使模型选择器可见。 */
function registerProviderAdapter(ctx, config) {
  if (ctx.llm == null || typeof ctx.llm.registerAdapter !== "function") return "no llm service";
  if (ctx.llm.listProviders().some((p) => p.id === PROVIDER_ID)) return "provider 已注册，跳过";
  ctx.llm.registerAdapter([PROVIDER_ID], buildPiAdapter(config));
  return "adapter 已注册";
}

function apply(ctx, config = {}) {
  const defaultTimeoutMs = Number(config.timeoutMs ?? process.env.HUAWEI_LLM_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);

  ctx.tools.register(defineTool({
    name: "huawei_local_llm",
    description:
      "调用华为官方本地大模型（HarmonyOS PC 本地 AI，127.0.0.1:11434）。"
      + "先走 OpenAI 兼容 /v1/chat/completions，失败自动回退 Ollama 原生 /api/chat。"
      + "适合需要本地/离线、隐私优先或断网时仍可用的文本生成。"
      + "默认模型 qwen3:8b（可用 HUAWEI_LLM_MODEL 覆盖，或查 huawei_local_models 获取真实模型 id）。",
    parameters: {
      prompt: {
        type: "string",
        description: "用户问题/指令，完整放进一次调用。"
      },
      system: {
        type: "string",
        description: "可选的系统提示词。"
      },
      model: {
        type: "string",
        description: "本地模型 id，默认 qwen3:8b。"
      },
      temperature: {
        type: "number",
        description: "采样温度，0~2，默认由服务端决定。"
      },
      maxTokens: {
        type: "integer",
        description: "最大生成长度。"
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => true,
    timeoutMs: defaultTimeoutMs,
    presentCall: present("generic", "调用华为本地大模型", "write", "prompt"),
    async execute(args, exec) {
      return chat({ ...args, timeoutMs: args.timeoutMs ?? defaultTimeoutMs }, exec.signal);
    }
  }));

  ctx.tools.register(defineTool({
    name: "huawei_local_models",
    description:
      "列出华为官方本地大模型（127.0.0.1:11434）当前可用的模型，并做连通性/白名单诊断。"
      + "调用前建议先跑一次，确认本地服务可用、模型 id 正确。",
    parameters: {},
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => true,
    timeoutMs: defaultTimeoutMs,
    presentCall: () => ({ card: "generic", title: "列出华为本地模型", kind: "write" }),
    async execute(_args, exec) {
      const r = await listModels(exec.signal, defaultTimeoutMs);
      return {
        ok: r.models.length > 0 || !r.whitelist,
        from: "discovery",
        model: "discovery",
        models: r.models,
        notes: r.notes,
        whitelist: r.whitelist,
        ...(r.models.length === 0 ? { error: r.notes[0] ?? "未发现模型" } : {})
      };
    }
  }));

  console.error(`[huawei-local-llm] registered 2 tools (${currentOrigin()}, model ${currentModel()})`);

  // 把 provider 配置写入 dsh 的 settings.yaml（保留注释、幂等、原子+锁），
  // 让模型选择器能选中本地模型。此写发生在启动期，失败只告警不影响 dsh。
  void (async () => {
    try {
      const msg = await ensureProviderRegistered(config.models ?? [
        { id: "qwen3:8b", name: "Qwen3 8B（华为本地）", contextWindow: 32768, maxTokens: 8192 },
        { id: "qwen3:14b", name: "Qwen3 14B（华为本地）", contextWindow: 32768, maxTokens: 8192 }
      ]);
      console.error(`[huawei-local-llm] provider "${PROVIDER_ID}" -> settings.yaml: ${msg}`);
    } catch (error) {
      console.error(`[huawei-local-llm] provider auto-register skipped: ${String(error?.message ?? error)}`);
    }
  })();

  // 直接把 huawei-local 注册成 llm 适配器，使模型选择器（session.modelCatalog）能列出本地模型。
  // 兼容 llm-pi-ai 命名空间未挂载的本机构建；已在时跳过、失败只告警不影响 dsh。
  try {
    const msg = registerProviderAdapter(ctx, config);
    console.error(`[huawei-local-llm] provider "${PROVIDER_ID}" -> llm adapter: ${msg}`);
  } catch (error) {
    console.error(`[huawei-local-llm] provider "${PROVIDER_ID}" -> llm adapter 注册失败: ${String(error?.message ?? error)}`);
  }
}

export { apply, inject, name };
