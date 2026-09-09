// dsh-huawei-devdocs — 华为开发者文档（HarmonyOS/鸿蒙）检索 + 强制检索守卫。
//
// 数据源为华为官方「文档门户」后端（developer.huawei.com 的 SPA 同源 REST，
// getCatalogTree / getDocumentById / getNavigationAddress），与官方「鸿蒙开发者知识
// MCP 服务」searchDocuments 同源语义：实时同步 开发指南/API参考/版本说明/最佳实践/FAQ。
//
// 工具（随 agent 创建注册，web 与 headless profile 均可用）：
//   huawei_devdocs_search  关键词检索官方目录（标题/章节路径），返回官方 URL
//   huawei_devdocs_get     按官方 URL 读取单篇文档全文（可分页）
//   huawei_devdocs_catalog 浏览某分类顶层章节
//   huawei_devdocs_status  后端连通性 / 索引缓存 / 强制规则状态诊断
//
// 强制机制（agent/pre-step，参照 dsh-prompt-antivirus 的守卫注入模式）：
//   检测到鸿蒙开发意图（用户消息含 鸿蒙/harmonyos/arkts/arkui/hvigor/ohpm/.ets/
//   module.json5/@kit.* 等）且当前用户提问尚未出现 huawei_devdocs_search 的成功结果
//   （结果首行含 HUAWEI_DEVDOCS_SEARCHED 标记）时，向模型注入 user 角色守卫，
//   要求先检索官方文档再作答；每轮最多注入 maxInjections 次。
// 纯 JS + 全局 fetch，无原生依赖；目录索引落盘缓存 ~/.dsh/cache/huawei-devdocs/。

import { defineTool } from "@deepseek-ai/dsh-tools";
import { createUserMessage } from "@deepseek-ai/dsh-llm";
import {
  CATALOGS,
  CATALOG_BY_ID,
  SITE_BASE,
  apiBase,
  cacheDir,
  offlineMode,
  indexTtlMs,
  ensureCatalogIndex,
  ensureCatalogs,
  fetchDocument,
  parseDocRef,
  probePortal,
  readCatalogIndex,
} from "./huawei-api.js";
import { searchEntries, topSections } from "./search.js";
import {
  SEARCHED_MARKER,
  isHarmonyDevIntent,
  textOfMessages,
  hasSearchedMarker,
  lastUserIndex,
  decideInjection,
  buildGuardText,
} from "./enforce.js";

export const name = "huawei-devdocs";
export const inject = ["agents", "tools"];

const DEFAULT_CONFIG = {
  enforce: "strict", // "strict" | "off"
  maxInjections: 2,
  maxResults: 20,
  toolTimeoutMs: 120_000,
};

function configValue(envName, configValue, fallback) {
  const raw = process.env[envName];
  if (raw !== undefined && raw !== "") return raw;
  return configValue ?? fallback;
}

/** 每 agent 会话的守卫状态（用对象做 key，与 prompt-antivirus 金丝雀同法）。 */
const states = new Map();

function stateFor(agent) {
  let state = states.get(agent);
  if (!state) {
    state = { fingerprint: "", injections: 0, exhaustedNoted: false };
    states.set(agent, state);
  }
  return state;
}

function renderValue(value) {
  return [{ type: "text", text: JSON.stringify(value, null, 2) }];
}

export function renderSearch(_args, value) {
  const lines = [];
  if (value?.ok) {
    lines.push(`[${SEARCHED_MARKER}] 华为开发者官方文档检索完成`);
    lines.push(`关键词: ${value.query} · 分类: ${value.catalog} · 命中 ${value.count} 篇`);
    if (value.note) lines.push(value.note);
    lines.push("");
    for (const item of value.results || []) {
      lines.push(`- ${item.title} [${item.catalogLabel ?? item.catalog}]`);
      if (item.path && item.path !== item.title) lines.push(`  章节: ${item.path}`);
      lines.push(`  URL: ${item.url}`);
    }
    if ((value.results || []).length === 0) {
      lines.push("未命中，可换关键词，或用 huawei_devdocs_catalog 浏览分类章节。");
    }
    lines.push("");
    lines.push("下一步：用 huawei_devdocs_get 传入上述 URL 读取文档全文，再基于官方内容作答。");
  } else {
    lines.push(`[huawei_devdocs_search] 失败: ${value?.error ?? "未知错误"}`);
    lines.push("请用 huawei_devdocs_status 诊断网络与缓存；也可检查代理是否放行 svc-drcn.developer.huawei.com。");
  }
  return [{ type: "text", text: lines.join("\n") }];
}

export function renderGet(_args, value) {
  const lines = [];
  if (value?.ok) {
    lines.push(`# ${value.title}`);
    lines.push(`来源: ${value.url}`);
    lines.push(`分类: ${value.catalogLabel ?? value.catalog} · 版本: ${value.version || "最新"} · 正文 ${value.totalChars} 字符`);
    lines.push("");
    lines.push(value.content || "(空正文)");
    if (value.truncated) {
      lines.push("");
      lines.push(`…（内容截断，继续阅读请再次调用 huawei_devdocs_get，传 start=${value.start + (value.maxChars || value.content?.length || 0)}）`);
    }
  } else {
    lines.push(`[huawei_devdocs_get] 失败: ${value?.error ?? "未知错误"}`);
  }
  return [{ type: "text", text: lines.join("\n") }];
}

export function renderCatalog(_args, value) {
  const lines = [];
  if (value?.ok) {
    lines.push(`# ${value.label ?? value.catalog}（共 ${value.total} 篇文档）`);
    lines.push(`版本: ${value.version || "最新"}`);
    lines.push("");
    for (const section of value.sections || []) {
      lines.push(`- ${section.name}（${section.count} 篇）`);
    }
    lines.push("");
    lines.push("提示：可用 huawei_devdocs_search 检索具体关键词。");
  } else {
    lines.push(`[huawei_devdocs_catalog] 失败: ${value?.error ?? "未知错误"}`);
  }
  return [{ type: "text", text: lines.join("\n") }];
}

export function renderStatus(_args, value) {
  return [{ type: "text", text: JSON.stringify(value, null, 2) }];
}

const SEARCH_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean" },
    marker: { type: "string" },
    query: { type: "string" },
    catalog: { type: "string" },
    count: { type: "integer" },
    stale: { type: "boolean" },
    note: { type: "string" },
    error: { type: "string" },
    results: { type: "array" },
  },
};

const GET_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean" },
    title: { type: "string" },
    url: { type: "string" },
    catalog: { type: "string" },
    catalogLabel: { type: "string" },
    version: { type: "string" },
    totalChars: { type: "integer" },
    start: { type: "integer" },
    maxChars: { type: "integer" },
    content: { type: "string" },
    truncated: { type: "boolean" },
    error: { type: "string" },
  },
};

const CATALOG_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean" },
    catalog: { type: "string" },
    label: { type: "string" },
    version: { type: "string" },
    total: { type: "integer" },
    sections: { type: "array" },
    error: { type: "string" },
  },
};

const STATUS_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean" },
    enforce: { type: "string" },
    maxInjections: { type: "integer" },
    offline: { type: "boolean" },
    apiBase: { type: "string" },
    cacheDir: { type: "string" },
    indexTtlMs: { type: "integer" },
    probe: { type: "object", additionalProperties: true },
    catalogs: { type: "array" },
    lastError: { type: "string" },
  },
};

function intOr(raw, fallback, min, max) {
  const value = Number(raw);
  if (!Number.isFinite(value)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(value)));
}

function resolveCatalog(input) {
  const raw = String(input ?? "").trim();
  if (!raw || raw === "all") return null;
  const exact = CATALOG_BY_ID.get(raw);
  if (exact) return exact;
  const byLabel = CATALOGS.find((c) => raw.includes(c.label) || c.label.includes(raw));
  if (byLabel) return byLabel;
  return undefined; // 无效分类
}

function buildSearchHandler(cfg) {
  return async function searchHandler(args, exec) {
    const query = String(args?.query ?? "").trim();
    if (!query) return { ok: false, marker: "", query: "", catalog: "", count: 0, note: "", error: "缺少 query（要检索的关键词）。", results: [] };
    const limit = intOr(args?.limit, cfg.maxResults, 1, 50);
    const catalogMeta = resolveCatalog(args?.catalog);
    if (catalogMeta === undefined) {
      const available = CATALOGS.map((c) => `${c.id}(${c.label})`).join(", ");
      return { ok: false, marker: "", query, catalog: String(args?.catalog), count: 0, note: "", error: `未知分类，可用: ${available}`, results: [] };
    }
    const requested = catalogMeta ? [catalogMeta.id] : CATALOGS.map((c) => c.id);
    try {
      const { indexes, errors } = await ensureCatalogs(requested, { signal: exec?.signal });
      if (!indexes.length) {
        const detail = errors.map((e) => `${e.catalog}: ${e.error}`).join("; ");
        return { ok: false, marker: "", query, catalog: catalogMeta?.id ?? "all", count: 0, note: "", error: `无法获取文档索引: ${detail}`, results: [] };
      }
      const entries = indexes.flatMap((index) => index.entries);
      const results = searchEntries(entries, query, { limit });
      const indexNote = indexes
        .map((i) => `${i.label}: ${i.entries.length} 篇${i.stale ? "（缓存降级）" : ""}${i.offline ? "（离线）" : ""}`)
        .join(" · ");
      const note = `索引: ${indexNote}` + (errors.length ? `；部分分类失败: ${errors.map((e) => e.error).join("; ")}` : "");
      return {
        ok: true,
        marker: SEARCHED_MARKER,
        query,
        catalog: catalogMeta?.id ?? "all",
        count: results.length,
        stale: indexes.some((i) => i.stale),
        note,
        error: "",
        results: results.map((r) => ({ title: r.title, path: r.path, catalog: r.catalog, catalogLabel: r.catalogLabel, url: r.url })),
      };
    } catch (error) {
      return { ok: false, marker: "", query, catalog: catalogMeta?.id ?? "all", count: 0, note: "", error: String(error?.message ?? error), results: [] };
    }
  };
}

function buildGetHandler(_cfg) {
  return async function getHandler(args, exec) {
    const ref = parseDocRef(args?.url ?? args?.docPath);
    if (!ref) {
      return {
        ok: false, title: "", url: String(args?.url ?? ""), catalog: "", catalogLabel: "", version: "",
        totalChars: 0, start: 0, maxChars: 0, content: "",
        truncated: false,
        error: "无法解析文档 URL。请传入形如 https://developer.huawei.com/consumer/cn/doc/<分类>/<slug> 的官方地址（来自 huawei_devdocs_search 结果）。",
      };
    }
    const start = Math.max(0, intOr(args?.start, 0, 0, 1_000_000));
    const maxChars = Math.min(60000, Math.max(1000, intOr(args?.maxChars, 15000, 1000, 60000)));
    try {
      const doc = await fetchDocument(ref.catalog, ref.slug, { signal: exec?.signal });
      const text = doc.text ?? "";
      const totalChars = text.length;
      if (start > 0 && start >= totalChars) {
        return {
          ok: false, title: doc.title, url: `${SITE_BASE}/${ref.catalog}/${ref.slug}`, catalog: ref.catalog,
          catalogLabel: doc.catalogLabel, version: doc.version, totalChars, start, maxChars,
          content: "", truncated: false,
          error: `start(${start}) 超过正文长度 ${totalChars}。`,
        };
      }
      const content = text.slice(start, start + maxChars);
      return {
        ok: true, title: doc.title, url: `${SITE_BASE}/${ref.catalog}/${ref.slug}`, catalog: ref.catalog,
        catalogLabel: doc.catalogLabel, version: doc.version, totalChars, start, maxChars,
        content, truncated: start + maxChars < totalChars, error: "",
      };
    } catch (error) {
      return {
        ok: false, title: "", url: `${SITE_BASE}/${ref.catalog}/${ref.slug}`, catalog: ref.catalog,
        catalogLabel: CATALOG_BY_ID.get(ref.catalog)?.label ?? ref.catalog, version: "",
        totalChars: 0, start, maxChars, content: "", truncated: false,
        error: String(error?.message ?? error),
      };
    }
  };
}

function buildCatalogHandler(_cfg) {
  return async function catalogHandler(args, exec) {
    const catalogMeta = resolveCatalog(args?.catalog);
    if (catalogMeta === undefined) {
      const available = CATALOGS.map((c) => `${c.id}(${c.label})`).join(", ");
      return { ok: false, catalog: String(args?.catalog ?? ""), label: "", version: "", total: 0, sections: [], error: `未知分类，可用: ${available}` };
    }
    const limit = intOr(args?.limit, 60, 1, 200);
    try {
      const index = await ensureCatalogIndex(catalogMeta.id, { signal: exec?.signal });
      return {
        ok: true, catalog: catalogMeta.id, label: index.label, version: index.versionLabel ?? "",
        total: index.entries.length, sections: topSections(index.entries, { limit }), error: "",
      };
    } catch (error) {
      return { ok: false, catalog: catalogMeta.id, label: catalogMeta.label, version: "", total: 0, sections: [], error: String(error?.message ?? error) };
    }
  };
}

function buildStatusHandler(cfg) {
  return async function statusHandler(_args, exec) {
    const probe = await probePortal({ signal: exec?.signal, ms: 8000 });
    const catalogStates = [];
    for (const catalog of CATALOGS) {
      const index = readCatalogIndex(catalog.id);
      const state = { id: catalog.id, label: catalog.label, cached: !!index, entries: index?.entries?.length ?? 0, ageSeconds: null, version: index?.versionLabel ?? "" };
      if (index) state.ageSeconds = Math.round((Date.now() - index.fetchedAt) / 1000);
      catalogStates.push(state);
    }
    return {
      ok: probe.ok,
      enforce: cfg.enforce,
      maxInjections: cfg.maxInjections,
      offline: offlineMode(),
      apiBase: apiBase(),
      cacheDir: cacheDir(),
      indexTtlMs: indexTtlMs(),
      probe,
      catalogs: catalogStates,
      lastError: probe.ok ? "" : probe.error ?? "",
    };
  };
}

export function apply(ctx, config = {}) {
  const cfg = {
    ...DEFAULT_CONFIG,
    ...config,
    enforce: String(configValue("HUAWEI_DEVDOCS_ENFORCE", config.enforce, DEFAULT_CONFIG.enforce)),
    maxInjections: intOr(process.env.HUAWEI_DEVDOCS_MAX_INJECTIONS ?? config.maxInjections, DEFAULT_CONFIG.maxInjections, 1, 5),
    maxResults: intOr(process.env.HUAWEI_DEVDOCS_MAX_RESULTS ?? config.maxResults, DEFAULT_CONFIG.maxResults, 1, 50),
    toolTimeoutMs: intOr(process.env.HUAWEI_DEVDOCS_TOOL_TIMEOUT_MS ?? config.toolTimeoutMs, DEFAULT_CONFIG.toolTimeoutMs, 5000, 600000),
  };
  if (cfg.enforce !== "strict" && cfg.enforce !== "off") cfg.enforce = DEFAULT_CONFIG.enforce;

  const createGuardMessage = (text) =>
    createUserMessage({
      content: [{ type: "text", text }],
      source: { kind: "plugin", plugin: "huawei-devdocs" }, // 无 form：released v0 插件表单封闭，"guard" 自定义表单会被官方 v0→v1 冻结校验拒绝
    });

  // 全局拦截点：agent/pre-step → 检测鸿蒙开发意图 + 检索缺失 → 注入强制守卫。
  ctx.effect(() => {
    const disposer = ctx.on("agent/pre-step", async (payload, next) => {
      const decision = await next(payload);
      if (!payload || !Array.isArray(payload.messages)) return decision;
      if (!decision || decision.kind !== "enter") return decision;
      const messages = Array.isArray(decision.messages) ? decision.messages : payload.messages;
      if (cfg.enforce === "off") return decision;
      const userIndex = lastUserIndex(messages);
      if (userIndex === -1) return decision;
      const userMessage = messages[userIndex];
      const userText = textOfMessages([userMessage]).trim();
      if (!userText) return decision;
      const state = stateFor(payload.agent);
      const fingerprint = userText.slice(0, 400);
      if (fingerprint !== state.fingerprint) {
        state.fingerprint = fingerprint;
        state.injections = 0;
        state.exhaustedNoted = false;
      }
      const harmony = isHarmonyDevIntent(userText);
      const searched = hasSearchedMarker(messages.slice(userIndex));
      if (!harmony || searched) return decision;
      const verdict = decideInjection({ harmony, searched, injections: state.injections, maxInjections: cfg.maxInjections });
      if (!verdict.inject) {
        if (verdict.exhausted && !state.exhaustedNoted) {
          state.exhaustedNoted = true;
          const notice = createGuardMessage(buildGuardText(state.injections + 1));
          return { kind: "enter", messages: [...messages, notice] };
        }
        return decision;
      }
      state.injections += 1;
      const guard = createGuardMessage(buildGuardText(state.injections));
      return { kind: "enter", messages: [...messages, guard] };
    });
    return () => disposer();
  }, "huawei-devdocs: hooks");

  // 每 agent 注册检索工具（web 与 headless 的 agent 均覆盖）。
  ctx.effect(() => {
    const stopCreated = ctx.on("agent/created", ({ agent }) => {
      if (!agent?.ctx) return;
      return agent.ctx.effect(() => {
        const tools = agent.ctx.get("tools");
        if (!tools) return;
        const disposers = [
          tools.register(
            defineTool({
              name: "huawei_devdocs_search",
              description:
                "检索华为开发者官方文档（HarmonyOS/鸿蒙）：覆盖 开发指南、API参考、版本说明、最佳实践、FAQ，"
                + "索引实时同步自官方文档门户。关键词支持中文与英文（如 ArkUI、TextPicker、@kit.AbilityKit、module.json5 配置）。"
                + "鸿蒙开发问题的强制前置步骤：先调用本工具检索，再用 huawei_devdocs_get 读取命中页面后作答。",
              parameters: {
                query: { type: "string", required: true, description: "检索关键词，例如 ArkUI 布局 / TextPicker / 应用权限申请。" },
                catalog: { type: "string", description: "限定分类: harmonyos-guides(开发指南) | harmonyos-references(API参考) | harmonyos-releases(版本说明) | best-practices(最佳实践) | harmonyos-faqs(FAQ)；省略则全部分类。" },
                limit: { type: "integer", description: "返回条数 1~50，默认 20。" },
              },
              output: { schema: SEARCH_OUTPUT_SCHEMA, render: renderSearch },
              isConcurrencySafe: () => true,
              timeoutMs: cfg.toolTimeoutMs,
              async execute(args, exec) {
                return buildSearchHandler(cfg)(args, exec);
              },
            }),
          ),
          tools.register(
            defineTool({
              name: "huawei_devdocs_get",
              description:
                "读取华为开发者官方文档单篇全文（按 huawei_devdocs_search 返回的 URL）。"
                + "返回正文纯文本（默认前 15000 字符，长文档用 start 参数翻页）。",
              parameters: {
                url: { type: "string", required: true, description: "官方文档 URL，形如 https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/<slug>。" },
                start: { type: "integer", description: "正文起始偏移（字符数），用于读取被截断的后续内容，默认 0。" },
                maxChars: { type: "integer", description: "本次最多返回字符数，默认 15000，上限 60000。" },
              },
              output: { schema: GET_OUTPUT_SCHEMA, render: renderGet },
              isConcurrencySafe: () => true,
              timeoutMs: cfg.toolTimeoutMs,
              async execute(args, exec) {
                return buildGetHandler(cfg)(args, exec);
              },
            }),
          ),
          tools.register(
            defineTool({
              name: "huawei_devdocs_catalog",
              description: "浏览华为开发者官方文档某分类的顶层章节（含每章文档数），便于不熟悉关键词时定位文档。",
              parameters: {
                catalog: { type: "string", required: true, description: "分类 id: harmonyos-guides / harmonyos-references / harmonyos-releases / best-practices / harmonyos-faqs。" },
                limit: { type: "integer", description: "最多返回章节数，默认 60。" },
              },
              output: { schema: CATALOG_OUTPUT_SCHEMA, render: renderCatalog },
              isConcurrencySafe: () => true,
              timeoutMs: cfg.toolTimeoutMs,
              async execute(args, exec) {
                return buildCatalogHandler(cfg)(args, exec);
              },
            }),
          ),
          tools.register(
            defineTool({
              name: "huawei_devdocs_status",
              description: "诊断华为开发者文档插件：官方门户连通性、各分类索引缓存状态、强制规则开关与注入次数。工具异常时先调用它。",
              parameters: {},
              output: { schema: STATUS_OUTPUT_SCHEMA, render: renderStatus },
              isConcurrencySafe: () => true,
              timeoutMs: cfg.toolTimeoutMs,
              async execute(args, exec) {
                return buildStatusHandler(cfg)(args, exec);
              },
            }),
          ),
        ];
        return () => {
          for (const dispose of disposers) dispose();
        };
      }, "huawei-devdocs: tools");
    });
    return () => stopCreated();
  }, "huawei-devdocs: agents");

  console.error(
    `[huawei-devdocs] 已加载: enforce=${cfg.enforce}, maxInjections=${cfg.maxInjections}, ` +
    `catalogs=${CATALOGS.length} (${CATALOGS.map((c) => c.id).join(",")}), api=${apiBase()}, offline=${offlineMode()}, cacheDir=${cacheDir()}`
  );
}
