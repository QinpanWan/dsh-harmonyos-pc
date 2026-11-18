import { defineTool } from "@deepseek-ai/dsh-tools";
import { createProvider } from "@earendil-works/pi-ai";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";
import { PiAiAdapter } from "@deepseek-ai/dsh-llm-pi-ai";
import {
  COPILOT_MODELS,
  DEFAULT_MODEL,
  DEFAULT_TIMEOUT_MS,
  authFilePath,
  chat,
  errorText,
  fetchModels,
  identityHeaders,
  resolveAccount,
  resolveBaseURL,
  resolveToken
} from "./copilot.js";

const name = "copilot";
const inject = ["tools", "llm"];
const PROVIDER_ID = "copilot";
const PROVIDER_DISPLAY = "GitHub Copilot";
const NO_COST = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 };

const resultSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean", required: true },
    action: { type: "string", required: true },
    text: { type: "string" },
    model: { type: "string" },
    account: { type: "string" },
    plan: { type: "string" },
    baseUrl: { type: "string" },
    credential: { type: "string" },
    finishReason: { type: "string" },
    usage: { type: "json" },
    models: { type: "array", items: { type: "json" } },
    error: { type: "string" }
  }
};

function renderResult(_args, value) {
  const lines = [`${value.ok ? "OK" : "FAIL"} · ${value.action}`];
  if (value.account) lines.push(`account: ${value.account}${value.plan ? ` (${value.plan})` : ""}`);
  if (value.model) lines.push(`model: ${value.model}`);
  if (value.baseUrl) lines.push(`api: ${value.baseUrl}`);
  if (value.credential) lines.push(`credential: ${value.credential}`);
  if (value.finishReason) lines.push(`finish: ${value.finishReason}`);
  if (value.text) lines.push("", value.text);
  if (value.models?.length) {
    lines.push("", `模型 (${value.models.length})：`);
    for (const model of value.models) {
      const state = model.state ? ` [${model.state}]` : "";
      const note = model.verified ? " ✅实测可用" : "";
      lines.push(`- ${model.id || model}${model.name && model.name !== model.id ? ` · ${model.name}` : ""}${state}${note}`);
    }
  }
  if (value.usage) lines.push("", `usage: ${JSON.stringify(value.usage)}`);
  if (value.error) lines.push("", `错误：${value.error}`);
  return [{ type: "text", text: lines.join("\n") }];
}

function present(title, rawInput) {
  return (args) => ({
    card: "generic",
    title,
    kind: "write",
    ...(rawInput && args[rawInput] !== void 0 ? { rawInput: args[rawInput] } : {})
  });
}

async function run(action, fn) {
  try {
    return { ok: true, action, ...(await fn()) };
  } catch (error) {
    return { ok: false, action, error: errorText(error) };
  }
}

function buildPiAdapter() {
  const baseURL = resolveBaseURL();
  const headers = identityHeaders();
  const models = COPILOT_MODELS.map((model) => ({
    id: model.id,
    name: model.name,
    api: model.api,
    provider: PROVIDER_ID,
    baseUrl: baseURL,
    input: model.input,
    cost: NO_COST,
    contextWindow: model.contextWindow,
    maxTokens: model.maxTokens,
    reasoning: model.reasoning
  }));

  const piProvider = createProvider({
    id: PROVIDER_ID,
    name: PROVIDER_DISPLAY,
    baseUrl: baseURL,
    headers,
    auth: {
      apiKey: {
        name: PROVIDER_DISPLAY,
        resolve: ({ credential }) => Promise.resolve({
          auth: credential?.key === void 0 ? {} : { apiKey: credential.key },
          source: PROVIDER_DISPLAY
        })
      }
    },
    models,
    api: {
      "openai-completions": openAICompletionsApi(),
      "openai-responses": openAIResponsesApi()
    }
  });

  const profile = {
    provider: PROVIDER_ID,
    displayName: PROVIDER_DISPLAY,
    baseURL,
    headers,
    streamIdleTimeoutMs: 300_000,
    maxRequestImageBytes: 20 * 1024 * 1024,
    requestImagePixelBudget: 2048 * 2048,
    requestImageMaxBytes: 1024 * 1024,
    retryPolicy: void 0,
    configuredMaxTokens: new Map(),
    modelErrors: new Map(),
    catalogError: void 0,
    reasoning: void 0,
    piProvider
  };

  return new PiAiAdapter({
    profiles: () => new Map([[PROVIDER_ID, profile]]),
    resolveApiKey: async () => resolveToken(),
    auth: {}
  });
}

function registerProviderAdapter(ctx) {
  if (ctx.llm == null || typeof ctx.llm.registerAdapter !== "function") return "no llm service";
  if (ctx.llm.listProviders().some((provider) => provider.id === PROVIDER_ID)) {
    return "provider 已注册，跳过";
  }
  ctx.llm.registerAdapter([PROVIDER_ID], buildPiAdapter());
  return "adapter 已注册";
}

function apply(ctx, config = {}) {
  const timeoutMs = Number(config.timeoutMs ?? process.env.COPILOT_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);

  ctx.tools.register(defineTool({
    name: "copilot_ask",
    description:
      "调用 GitHub Copilot 进行一次单轮问答。默认使用 gpt-5.4-nano；"
      + "适合让 Copilot 做代码解释、方案对比或第二意见。需要多轮/工具调用时，"
      + "可直接在模型选择器里选择 GitHub Copilot。",
    parameters: {
      prompt: {
        type: "string",
        required: true,
        description: "要问 Copilot 的完整问题或指令。"
      },
      system: {
        type: "string",
        description: "可选系统提示词。"
      },
      model: {
        type: "string",
        description: `Copilot 模型 id，默认 ${DEFAULT_MODEL}；可选 ${COPILOT_MODELS.map((model) => model.id).join("、")}。`
      },
      maxTokens: {
        type: "integer",
        description: "最大输出 token，默认不限制，由 Copilot 决定。"
      },
      temperature: {
        type: "number",
        description: "采样温度，0~2。"
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => true,
    timeoutMs,
    presentCall: present("问 GitHub Copilot", "prompt"),
    async execute(args, exec) {
      const token = resolveToken();
      if (!token) {
        return { ok: false, action: "ask", error: "未登录：请先运行 copilot-hm login" };
      }
      const messages = [];
      if (args.system) messages.push({ role: "system", content: args.system });
      messages.push({ role: "user", content: args.prompt });
      return run("ask", async () => {
        const data = await chat({
          token,
          model: args.model || DEFAULT_MODEL,
          messages,
          maxTokens: args.maxTokens,
          temperature: args.temperature,
          signal: exec.signal,
          timeoutMs
        });
        return {
          text: data.text,
          model: data.model,
          finishReason: data.finishReason,
          usage: data.usage
        };
      });
    }
  }));

  ctx.tools.register(defineTool({
    name: "copilot_status",
    description:
      "查询 GitHub Copilot 登录状态、套餐和模型目录。默认附带模型列表；"
      + "插件暴露的模型均经过真实对话验证，其它目录模型可能返回 model_not_supported。",
    parameters: {
      includeModels: {
        type: "boolean",
        description: "是否查询模型目录，默认 true。"
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => true,
    timeoutMs,
    presentCall: present("查询 GitHub Copilot 状态"),
    async execute(args, exec) {
      return run("status", async () => {
        const token = resolveToken();
        if (!token) throw new Error("未登录：请先运行 copilot-hm login");
        const account = await resolveAccount(token, { signal: exec.signal, timeoutMs });
        const models = args.includeModels === false
          ? []
          : (await fetchModels(token, { signal: exec.signal, timeoutMs }))
            .filter((model) => model?.capabilities?.type !== "embedding")
            .map((model) => ({
              id: model.id,
              name: model.name,
              state: model.policy?.state || "",
              verified: COPILOT_MODELS.some((entry) => entry.id === model.id)
            }));
        return {
          account: account.login,
          plan: account.plan,
          baseUrl: account.baseUrl,
          credential: authFilePath(),
          models
        };
      });
    }
  }));

  console.error(`[copilot] registered 2 tools (${resolveBaseURL()}, default ${DEFAULT_MODEL}, models ${COPILOT_MODELS.map((model) => model.id).join(",")})`);

  try {
    const message = registerProviderAdapter(ctx);
    console.error(`[copilot] provider "${PROVIDER_ID}" -> llm adapter: ${message}`);
  } catch (error) {
    console.error(`[copilot] provider "${PROVIDER_ID}" -> llm adapter 注册失败: ${String(error?.message ?? error)}`);
  }
}

export { apply, buildPiAdapter, inject, name };
