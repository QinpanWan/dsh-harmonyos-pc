import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const DEFAULT_BASE_URL = "https://api.individual.githubcopilot.com";
const DEFAULT_MODEL = "gpt-5.4-nano";
const DEFAULT_TIMEOUT_MS = 180_000;
const ACCOUNT_URL = "https://api.github.com/copilot_internal/user";
const DEFAULT_AUTH_FILE = path.join(os.homedir(), ".local", "share", "copilot-hm", "auth.json");

const COPILOT_MODELS = [
  {
    id: "gpt-5.4-nano",
    name: "GPT-5.4 nano",
    api: "openai-responses",
    contextWindow: 400_000,
    maxTokens: 128_000,
    input: ["text", "image"],
    reasoning: true
  },
  {
    id: "gpt-4.1",
    name: "GPT-4.1",
    api: "openai-completions",
    contextWindow: 128_000,
    maxTokens: 16_384,
    input: ["text", "image"],
    reasoning: false
  },
  {
    id: "gpt-4o",
    name: "GPT-4o",
    api: "openai-completions",
    contextWindow: 128_000,
    maxTokens: 4_096,
    input: ["text", "image"],
    reasoning: false
  }
];

function authFilePath() {
  return process.env.COPILOT_AUTH_FILE || DEFAULT_AUTH_FILE;
}

function readAuthFile() {
  try {
    const raw = JSON.parse(fs.readFileSync(authFilePath(), "utf8"));
    return typeof raw?.token === "string" && raw.token.trim() ? raw : null;
  } catch {
    return null;
  }
}

function resolveToken() {
  const explicit = process.env.COPILOT_GITHUB_TOKEN;
  if (explicit) return explicit;
  const saved = readAuthFile();
  if (saved?.token) return saved.token;
  return process.env.GH_TOKEN || process.env.GITHUB_TOKEN || "";
}

function resolveBaseURL() {
  const explicit = String(process.env.COPILOT_BASE_URL || "").trim();
  if (explicit) return explicit.replace(/\/+$/, "");
  const saved = readAuthFile();
  return String(saved?.baseUrl || DEFAULT_BASE_URL).replace(/\/+$/, "");
}

function identityHeaders() {
  return {
    "Accept-Encoding": "identity",
    "Editor-Version": "vscode/1.107.0",
    "Editor-Plugin-Version": "copilot-chat/0.35.0",
    "User-Agent": "GitHubCopilotChat/0.35.0",
    "Copilot-Integration-Id": "copilot-developer-cli",
    "Openai-Organization": "github-copilot",
    "x-initiator": "user"
  };
}

function withTimeout(signal, timeoutMs) {
  const controller = new AbortController();
  const ms = Number.isFinite(Number(timeoutMs)) && Number(timeoutMs) > 0
    ? Number(timeoutMs)
    : DEFAULT_TIMEOUT_MS;
  const timer = setTimeout(() => controller.abort(new Error("timeout")), ms);
  const onAbort = () => controller.abort(signal?.reason);
  if (signal?.aborted) onAbort();
  else signal?.addEventListener?.("abort", onAbort, { once: true });
  return {
    signal: controller.signal,
    done() {
      clearTimeout(timer);
      signal?.removeEventListener?.("abort", onAbort);
    }
  };
}

function errorText(error) {
  if (error?.status) return `HTTP ${error.status}: ${error.message}`;
  return String(error?.message || error);
}

async function readJson(response, label) {
  const text = await response.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${label}返回了非 JSON 响应：${text.slice(0, 300)}`);
  }
  if (!response.ok) {
    const detail = data?.error?.message || data?.message || data?.error || text.slice(0, 300);
    const error = new Error(`${label}失败：${detail}`);
    error.status = response.status;
    throw error;
  }
  if (data?.error) {
    const detail = data.error?.message || data.error;
    const error = new Error(`${label}失败：${detail}`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function resolveAccount(token, { signal, timeoutMs } = {}) {
  if (!token) throw new Error("未登录 GitHub Copilot：请先运行 copilot-hm login");
  const guarded = withTimeout(signal, timeoutMs);
  try {
    const response = await fetch(ACCOUNT_URL, {
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
        "User-Agent": "copilot-hm/1.0"
      },
      signal: guarded.signal
    });
    const data = await readJson(response, "GitHub Copilot 账号校验");
    return {
      login: data.login || "unknown",
      plan: data.copilot_plan || data.access_type_sku || "unknown",
      cliEnabled: data.cli_enabled !== false,
      baseUrl: String(data?.endpoints?.api || resolveBaseURL()).replace(/\/+$/, "")
    };
  } finally {
    guarded.done();
  }
}

async function fetchModels(token, { signal, timeoutMs } = {}) {
  if (!token) throw new Error("未登录 GitHub Copilot：请先运行 copilot-hm login");
  const guarded = withTimeout(signal, timeoutMs);
  try {
    const response = await fetch(`${resolveBaseURL()}/models`, {
      headers: {
        ...identityHeaders(),
        Authorization: `Bearer ${token}`
      },
      signal: guarded.signal
    });
    const data = await readJson(response, "读取 Copilot 模型列表");
    return Array.isArray(data?.data) ? data.data : Array.isArray(data) ? data : [];
  } finally {
    guarded.done();
  }
}

function messageText(message) {
  const content = message?.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content.map((part) => (typeof part === "string" ? part : part?.text || "")).join("");
  }
  return "";
}

function modelProfile(model) {
  return COPILOT_MODELS.find((entry) => entry.id === model);
}

function apiForModel(model) {
  return modelProfile(model)?.api || "openai-completions";
}

function responseText(data) {
  if (typeof data?.output_text === "string") return data.output_text;
  if (!Array.isArray(data?.output)) return "";
  return data.output
    .flatMap((item) => Array.isArray(item?.content) ? item.content : [])
    .map((part) => part?.text || "")
    .join("");
}

function responsesRequest(messages) {
  const instructions = [];
  const input = [];
  for (const message of messages) {
    const text = messageText(message);
    if (!text) continue;
    if (message.role === "system" || message.role === "developer") {
      instructions.push(text);
      continue;
    }
    input.push({ role: message.role === "assistant" ? "assistant" : "user", content: text });
  }
  return {
    input,
    ...(instructions.length > 0 ? { instructions: instructions.join("\n\n") } : {})
  };
}

async function chatCompletions({ token, model, messages, maxTokens, temperature, signal, timeoutMs }) {
  const guarded = withTimeout(signal, timeoutMs);
  try {
    const response = await fetch(`${resolveBaseURL()}/chat/completions`, {
      method: "POST",
      headers: {
        ...identityHeaders(),
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify({
        model,
        messages,
        stream: false,
        ...(maxTokens === void 0 ? {} : { max_tokens: maxTokens }),
        ...(temperature === void 0 ? {} : { temperature })
      }),
      signal: guarded.signal
    });
    const data = await readJson(response, "Copilot 对话");
    const text = messageText(data?.choices?.[0]?.message);
    if (!text) throw new Error(`Copilot 没有返回文本：${JSON.stringify(data).slice(0, 300)}`);
    return {
      text,
      model: data?.model || model,
      finishReason: data?.choices?.[0]?.finish_reason,
      usage: data?.usage
    };
  } finally {
    guarded.done();
  }
}

async function responses({ token, model, messages, maxTokens, temperature, signal, timeoutMs }) {
  const guarded = withTimeout(signal, timeoutMs);
  try {
    const response = await fetch(`${resolveBaseURL()}/responses`, {
      method: "POST",
      headers: {
        ...identityHeaders(),
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify({
        model,
        ...responsesRequest(messages),
        stream: false,
        ...(maxTokens === void 0 ? {} : { max_output_tokens: maxTokens }),
        ...(temperature === void 0 ? {} : { temperature })
      }),
      signal: guarded.signal
    });
    const data = await readJson(response, "Copilot 对话");
    const text = responseText(data);
    if (!text) throw new Error(`Copilot 没有返回文本：${JSON.stringify(data).slice(0, 300)}`);
    return {
      text,
      model: data?.model || model,
      finishReason: data?.status,
      usage: data?.usage
    };
  } finally {
    guarded.done();
  }
}

async function chat({
  token,
  model = DEFAULT_MODEL,
  messages,
  maxTokens,
  temperature,
  signal,
  timeoutMs
}) {
  if (!token) throw new Error("未登录 GitHub Copilot：请先运行 copilot-hm login");
  if (!Array.isArray(messages) || messages.length === 0) throw new Error("messages 不能为空");
  const request = { token, model, messages, maxTokens, temperature, signal, timeoutMs };
  return apiForModel(model) === "openai-responses" ? responses(request) : chatCompletions(request);
}

export {
  COPILOT_MODELS,
  DEFAULT_BASE_URL,
  DEFAULT_MODEL,
  DEFAULT_TIMEOUT_MS,
  apiForModel,
  authFilePath,
  chat,
  errorText,
  fetchModels,
  identityHeaders,
  messageText,
  modelProfile,
  readAuthFile,
  responsesRequest,
  responseText,
  resolveAccount,
  resolveBaseURL,
  resolveToken
};
