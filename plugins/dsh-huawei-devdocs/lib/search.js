// search.js — 官方目录索引上的中文/英文混合检索（纯函数，可单测）。

/** 分词：拉丁词 + CJK 单字 + CJK 相邻二元组。 */
export function tokenize(text) {
  const lower = String(text ?? "").toLowerCase();
  const tokens = new Set();
  const latin = lower.match(/[a-z0-9][a-z0-9._-]*/g) || [];
  for (const word of latin) tokens.add(word);
  const runs = lower.match(/[\u4e00-\u9fff]+/g) || [];
  for (const run of runs) {
    for (const char of run) tokens.add(char);
    for (let i = 0; i < run.length - 1; i++) tokens.add(run.slice(i, i + 2));
  }
  return [...tokens];
}

/** 从条目文本中匹配查询 token，返回命中数。 */
export function countMatches(haystack, tokens) {
  const lower = String(haystack ?? "").toLowerCase();
  let hits = 0;
  for (const token of tokens) {
    if (lower.includes(token)) hits += 1;
  }
  return hits;
}

const WEIGHTS = {
  title: 4,
  path: 3,
  slug: 2,
  url: 1,
};

/**
 * 在官方目录条目上检索。
 * 强 token（拉丁词 + CJK 二元组）需满足比例门槛才入选，避免单字噪声。
 * 返回 [{ title, path, catalog, catalogLabel, url, score, matches }]（按分数降序）。
 */
export function searchEntries(entries, query, { limit = 20, minCoverage = 0.6 } = {}) {
  const q = String(query ?? "").trim();
  if (!q) return [];
  const tokens = tokenize(q);
  const strong = tokens.filter((t) => /[a-z0-9]/.test(t) || t.length > 1);
  const weak = tokens.filter((t) => !strong.includes(t));
  const required = strong.length ? strong : weak;

  const scored = [];
  for (const entry of entries || []) {
    const title = String(entry.title ?? "");
    const path = String(entry.path ?? title);
    const slug = String(entry.slug ?? "");
    const url = String(entry.url ?? "");
    const titleHits = countMatches(title, tokens);
    const pathHits = countMatches(path, tokens);
    const slugHits = countMatches(slug, tokens);
    const urlHits = countMatches(url, tokens);
    const totalHits = titleHits + pathHits + slugHits + urlHits;
    if (totalHits === 0) continue;
    // 覆盖率门槛：所有 token 里至少 minCoverage 比例命中过（title/path/slug/url 之一）。
    const covered = new Set();
    for (const t of tokens) {
      if (title.toLowerCase().includes(t) || path.toLowerCase().includes(t) ||
          slug.toLowerCase().includes(t) || url.toLowerCase().includes(t)) covered.add(t);
    }
    if (covered.size / Math.max(1, required.length) < minCoverage) continue;
    const score =
      titleHits * WEIGHTS.title +
      (pathHits - titleHits) * WEIGHTS.path +
      slugHits * WEIGHTS.slug +
      urlHits * WEIGHTS.url;
    scored.push({
      title,
      path,
      slug,
      catalog: entry.catalog,
      catalogLabel: entry.catalogLabel ?? entry.catalog,
      url,
      score,
      matches: [...covered].length,
    });
  }
  scored.sort((a, b) => b.score - a.score || a.title.length - b.title.length);
  return scored.slice(0, Math.max(1, Math.min(50, Number(limit) || 20)));
}

/** 目录概览：取分类树顶层章节（path 无祖先的节点按字母序）。 */
export function topSections(entries, { limit = 40 } = {}) {
  const roots = [];
  const seen = new Set();
  for (const entry of entries || []) {
    const first = String(entry.path ?? entry.title ?? "").split(" / ")[0];
    if (!first || seen.has(first)) continue;
    seen.add(first);
    roots.push({ name: first, count: 0 });
  }
  for (const entry of entries || []) {
    const first = String(entry.path ?? entry.title ?? "").split(" / ")[0];
    const root = roots.find((r) => r.name === first);
    if (root) root.count += 1;
  }
  roots.sort((a, b) => a.name.localeCompare(b.name, "zh-CN"));
  return roots.slice(0, Math.max(1, Math.min(200, Number(limit) || 40)));
}
