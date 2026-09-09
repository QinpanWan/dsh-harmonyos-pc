// huawei-api.js — 华为开发者文档官方门户 REST 客户端 + 目录索引缓存 + HTML→文本。
//
// 数据源：developer.huawei.com「消费者文档门户」官方后端（documentPortal）：
//   POST .../documentPortal/getCatalogTree      → 完整目录树（nodeName 标题 + relateDocument slug）
//   POST .../documentPortal/getDocumentById     → 单篇文档正文（HTML）
//   POST .../documentPortal/getNavigationAddress→ 导航/健康探测
// 官方站点自身（SPA）即调用同一组接口；检索覆盖 开发指南/API参考/版本说明/最佳实践/FAQ，
// 与华为官方「鸿蒙开发者知识 MCP 服务」的 searchDocuments 语义同源（版本实时同步）。
// 纯 JS + 全局 fetch，无任何第三方/native 依赖。

import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { mkdirSync, readFileSync, writeFileSync, renameSync } from "node:fs";

export const DEFAULT_API_BASE =
  "https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal";
export const SITE_BASE = "https://developer.huawei.com/consumer/cn/doc";

export const CATALOGS = [
  { id: "harmonyos-guides", label: "开发指南" },
  { id: "harmonyos-references", label: "API参考" },
  { id: "harmonyos-releases", label: "版本说明" },
  { id: "best-practices", label: "最佳实践" },
  { id: "harmonyos-faqs", label: "FAQ" },
];

export const CATALOG_BY_ID = new Map(CATALOGS.map((c) => [c.id, c]));
export const CATALOG_IDS = CATALOGS.map((c) => c.id);

function env(name, fallback) {
  const value = process.env[name];
  return value === undefined || value === "" ? fallback : value;
}

export function apiBase() {
  return String(env("HUAWEI_DEVDOCS_API_BASE", DEFAULT_API_BASE)).replace(/\/+$/, "");
}

export function timeoutMs() {
  const value = Number(env("HUAWEI_DEVDOCS_TIMEOUT_MS", "20000"));
  return Number.isFinite(value) && value > 0 ? value : 20000;
}

export function offlineMode() {
  return env("HUAWEI_DEVDOCS_OFFLINE", "0") === "1";
}

export function indexTtlMs() {
  const value = Number(env("HUAWEI_DEVDOCS_INDEX_TTL_MS", String(12 * 60 * 60 * 1000)));
  return Number.isFinite(value) && value > 0 ? value : 12 * 60 * 60 * 1000;
}

export function cacheDir() {
  return env("HUAWEI_DEVDOCS_CACHE_DIR", join(homedir(), ".dsh", "cache", "huawei-devdocs"));
}

/** 组合外部 AbortSignal 与自身超时；返回 { signal, done }。 */
export function withTimeout(signal, ms) {
  const controller = new AbortController();
  const effective = Number.isFinite(Number(ms)) && Number(ms) > 0 ? Number(ms) : timeoutMs();
  const timer = setTimeout(() => controller.abort(new Error("timeout")), effective);
  const onAbort = () => controller.abort(signal?.reason ?? new Error("aborted"));
  if (signal?.aborted) onAbort();
  else signal?.addEventListener?.("abort", onAbort, { once: true });
  return {
    signal: controller.signal,
    done: () => {
      clearTimeout(timer);
      signal?.removeEventListener?.("abort", onAbort);
    },
  };
}

const BROWSER_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

/** 调用 documentPortal 的 JSON POST 服务。 */
export async function postPortal(service, payload, { signal, ms = timeoutMs() } = {}) {
  const guarded = withTimeout(signal, ms);
  try {
    const resp = await fetch(`${apiBase()}/${service}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Referer: "https://developer.huawei.com/",
        "User-Agent": BROWSER_UA,
      },
      body: JSON.stringify(payload ?? {}),
      signal: guarded.signal,
    });
    if (!resp.ok) {
      let text = "";
      try { text = (await resp.text()).slice(0, 300); } catch { /* ignore */ }
      throw new Error(`HTTP ${resp.status}: ${text}`);
    }
    const data = await resp.json();
    if (data?.code !== 0) {
      const message = String(data?.message ?? "unknown error").slice(0, 300);
      throw new Error(`API ${service} 失败 (${data?.code ?? "?"}): ${message}`);
    }
    return data;
  } catch (error) {
    const message = String(error?.message ?? error);
    if (/timeout|aborted/i.test(message)) throw new Error(`访问华为文档门户超时: ${message}`);
    throw error;
  } finally {
    guarded.done();
  }
}

/** 健康探测：拿导航地址（轻量请求）。 */
export async function probePortal({ signal, ms = 8000 } = {}) {
  const started = Date.now();
  try {
    const data = await postPortal(
      "getNavigationAddress",
      { catalogName: "harmonyos-guides", lang: "cn" },
      { signal, ms }
    );
    return {
      ok: true,
      ms: Date.now() - started,
      navigationAddress: data?.value?.navigationAddress ?? "",
      apiBase: apiBase(),
    };
  } catch (error) {
    return { ok: false, ms: Date.now() - started, error: String(error?.message ?? error), apiBase: apiBase() };
  }
}

/**
 * 拉取某分类的完整目录树并展平为条目。
 * 返回 { catalog, label, versionLabel, fetchedAt, entries }；
 * entries: [{ title, slug, path, url }]，path 为祖先节点标题链（/ 分隔）。
 */
export async function fetchCatalogTree(catalogId, { signal, ms } = {}) {
  const meta = CATALOG_BY_ID.get(catalogId);
  if (!meta) throw new Error(`未知分类 ${catalogId}，可用: ${CATALOG_IDS.join(", ")}`);
  const anchor = env("HUAWEI_DEVDOCS_TREE_ANCHOR", "arkui-overview");
  const data = await postPortal(
    "getCatalogTree",
    { language: "cn", catalogName: catalogId, objectId: anchor },
    { signal, ms }
  );
  const value = data?.value ?? {};
  const roots = Array.isArray(value.catalogTreeList) ? value.catalogTreeList : [];
  const entries = [];
  const walk = (node, ancestors) => {
    if (!node || typeof node !== "object") return;
    const title = String(node.nodeName ?? "").trim();
    const slug = String(node.relateDocument ?? "").trim();
    if (slug && title) {
      entries.push({
        title,
        slug,
        path: ancestors.length ? `${ancestors.join(" / ")} / ${title}` : title,
        catalog: catalogId,
        catalogLabel: meta.label,
        url: `${SITE_BASE}/${catalogId}/${slug}`,
      });
    }
    const children = Array.isArray(node.children) ? node.children : [];
    const nextAncestors = slug ? [...ancestors, title] : ancestors;
    for (const child of children) walk(child, nextAncestors);
  };
  for (const root of roots) walk(root, []);
  return {
    catalog: catalogId,
    label: meta.label,
    versionLabel: String(value.versionLabelList?.[0] ?? value.version ?? ""),
    fetchedAt: Date.now(),
    entries,
  };
}

function cacheFile(catalogId) {
  return join(cacheDir(), `index-${catalogId}.json`);
}

function readCache(catalogId) {
  try {
    const parsed = JSON.parse(readFileSync(cacheFile(catalogId), "utf8"));
    if (parsed?.catalog === catalogId && Array.isArray(parsed?.entries)) return parsed;
  } catch { /* 无缓存或损坏 */ }
  return null;
}

/** 只读：返回磁盘缓存中的分类索引（无缓存返回 null，不触网）。 */
export function readCatalogIndex(catalogId) {
  return readCache(catalogId);
}

function writeCache(data) {
  try {
    mkdirSync(dirname(cacheFile(data.catalog)), { recursive: true });
    const target = cacheFile(data.catalog);
    const temp = `${target}.tmp`;
    writeFileSync(temp, JSON.stringify(data));
    renameSync(temp, target);
  } catch { /* 缓存写失败不影响主流程 */ }
}

/**
 * 获取某分类索引：TTL 内命中磁盘缓存；过期/缺失才联网刷新。
 * 网络失败但有过期缓存时降级返回缓存并标记 stale。
 */
export async function ensureCatalogIndex(catalogId, { force = false, signal, ms } = {}) {
  const cached = readCache(catalogId);
  if (!force && cached && Date.now() - cached.fetchedAt < indexTtlMs()) {
    return { ...cached, fromCache: true, stale: false };
  }
  if (offlineMode()) {
    if (cached) return { ...cached, fromCache: true, stale: true, offline: true };
    throw new Error("HUAWEI_DEVDOCS_OFFLINE=1 且本分类无本地缓存，无法检索。请联网后重试或先关闭 offline。");
  }
  try {
    const fresh = await fetchCatalogTree(catalogId, { signal, ms });
    writeCache(fresh);
    return { ...fresh, fromCache: false, stale: false };
  } catch (error) {
    if (cached) return { ...cached, fromCache: true, stale: true, networkError: String(error?.message ?? error) };
    throw error;
  }
}

/** 并发获取多个分类索引（全部成功/单个失败均返回结果）。 */
export async function ensureCatalogs(catalogIds, opts = {}) {
  const requested = catalogIds && catalogIds.length ? catalogIds : CATALOG_IDS;
  const results = await Promise.allSettled(requested.map((id) => ensureCatalogIndex(id, opts)));
  const ok = [];
  const errors = [];
  for (let i = 0; i < results.length; i++) {
    const settled = results[i];
    if (settled.status === "fulfilled") ok.push(settled.value);
    else errors.push({ catalog: requested[i], error: String(settled.reason?.message ?? settled.reason) });
  }
  return { indexes: ok, errors };
}

/** 取单篇文档正文（getDocumentById）。返回 { title, catalog, version, html, text, anchors }。 */
export async function fetchDocument(catalogId, slug, { signal, ms } = {}) {
  const data = await postPortal(
    "getDocumentById",
    { objectId: slug, version: "", catalogName: catalogId, language: "cn" },
    { signal, ms }
  );
  const value = data?.value ?? {};
  const content = value?.content ?? {};
  const html = String(content.content ?? "");
  const anchors = Array.isArray(value.anchorList)
    ? value.anchorList.map((a) => ({
        id: String(a.anchorId ?? ""),
        title: String(a.title ?? ""),
        level: Number(a.level ?? 0),
      }))
    : [];
  return {
    title: String(value.title ?? slug),
    catalog: catalogId,
    catalogLabel: CATALOG_BY_ID.get(catalogId)?.label ?? catalogId,
    version: String(value.version ?? ""),
    status: String(value.status ?? ""),
    html,
    text: htmlToText(html),
    anchors,
  };
}

/** 从官方 URL / 形如 "catalog/slug" 的字符串解析出分类与 slug。 */
export function parseDocRef(input) {
  let url = String(input ?? "").trim();
  if (!url) return null;
  url = url.split("?")[0].split("#")[0].replace(/\/+$/, "");
  for (const catalog of CATALOG_IDS) {
    const marker = `/doc/${catalog}/`;
    if (url.includes(marker)) {
      const slug = url.slice(url.indexOf(marker) + marker.length);
      if (slug) return { catalog, slug };
    }
    const bare = new RegExp(`^${catalog}/([^/]+)$`);
    const match = url.match(bare);
    if (match) return { catalog, slug: match[1] };
  }
  return null;
}

const BLOCK_RE =
  /<(h[1-6]|p|div|section|article|li|ul|ol|tr|table|pre|br|blockquote|hr|dt|dd|title)(\s[^>]*)?>/gi;
const CLOSE_RE =
  /<\/(h[1-6]|p|div|section|article|li|ul|ol|tr|table|pre|blockquote|dt|dd|title)>/gi;
const SCRIPT_RE = /<(script|style|noscript)[\s\S]*?<\/\1>/gi;
const TAG_RE = /<[^>]+>/g;
const ENTITY_RE = /&(amp|lt|gt|quot|#39|nbsp|ensp|emsp);/g;

function decodeEntities(text) {
  return text
    .replace(ENTITY_RE, (_, name) => {
      const map = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", nbsp: " ", ensp: " ", emsp: " " };
      return map[name] ?? _;
    })
    .replace(/&#(\d+);/g, (_, code) => {
      const n = Number(code);
      return Number.isFinite(n) && n > 0 && n < 0x10ffff ? String.fromCodePoint(n) : "";
    });
}

/** 官方文档 HTML → 可读纯文本（保留标题/列表/代码块/表格结构）。 */
export function htmlToText(html) {
  if (!html) return "";
  let text = String(html);
  // 代码块/表格单元格先做占位保护，避免块标签替换破坏其内容。
  const preBlocks = [];
  text = text.replace(/<pre[\s\S]*?<\/pre>/gi, (match) => {
    preBlocks.push(decodeEntities(match.replace(/<[^>]+>/g, "")));
    return `\u0000PRE${preBlocks.length - 1}\u0000`;
  });
  text = text
    .replace(SCRIPT_RE, "")
    .replace(BLOCK_RE, "\n")
    .replace(CLOSE_RE, "\n")
    .replace(/<td[^>]*>/gi, " | ")
    .replace(/<th[^>]*>/gi, " | ")
    .replace(/<a[^>]*>|<\/a>/gi, "")
    .replace(/<[^>]+>/g, "");
  text = decodeEntities(text);
  text = text.replace(/\u0000PRE(\d+)\u0000/g, (_, i) => {
    const block = preBlocks[Number(i)];
    return block ? `\n\`\`\`\n${block.trim()}\n\`\`\`\n` : "";
  });
  text = text
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join("\n");
  return text.trim();
}
