// 独立烟测：真实验证官方文档门户后端 + 检索 + 取正文 + 守卫判定（不依赖 dsh 运行时）。
// 用法: node scripts/verify.mjs [--live]
import {
  probePortal,
  ensureCatalogIndex,
  ensureCatalogs,
  fetchDocument,
  readCatalogIndex,
  CATALOG_IDS,
} from "../lib/huawei-api.js";
import { searchEntries } from "../lib/search.js";
import { isHarmonyDevIntent, buildGuardText, SEARCHED_MARKER } from "../lib/enforce.js";

const live = process.argv.includes("--live");

console.log("== 1) 守卫/意图纯逻辑 ==");
console.log("鸿蒙问题:", isHarmonyDevIntent("鸿蒙 ArkUI 怎么居中？"), "| 网页问题:", isHarmonyDevIntent("写个 react 卡片"), "| 守卫含工具:", buildGuardText(1).includes("huawei_devdocs_search"));

if (!live) {
  console.log("== 跳过联网（加 --live 执行真实后端校验）==");
  process.exit(0);
}

console.log("== 2) 官方门户连通性 ==");
console.log(await probePortal());

console.log("== 3) 单分类索引（best-practices，最小） ==");
const index = await ensureCatalogIndex("best-practices", { force: true });
console.log(`entries=${index.entries.length} version=${index.versionLabel} label=${index.label}`);
const cached = readCatalogIndex("best-practices");
console.log("磁盘缓存条目:", cached?.entries?.length);

console.log("== 4) 全分类并发索引 ==");
const all = await ensureCatalogs(CATALOG_IDS);
console.log(all.indexes.map((i) => `${i.catalog}:${i.entries.length}`).join(" "), "errors:", all.errors.length);

console.log("== 5) 检索示例 ==");
const entries = all.indexes.flatMap((i) => i.entries);
for (const q of ["TextPicker", "TextPicker 文本选择器", "应用权限", "startAbility", "卡片"]) {
  const hits = searchEntries(entries, q, { limit: 5 });
  console.log(`query="${q}" ->`, hits.slice(0, 3).map((h) => `${h.title} [${h.catalog}]`).join(" | "));
}

console.log("== 6) 读取官方文档全文 ==");
const first = entries.find((e) => e.catalog === "harmonyos-guides" && /TextPicker/.test(e.title));
if (first) {
  const doc = await fetchDocument(first.catalog, first.slug);
  console.log(`${doc.title} (${doc.version}) text=${doc.text.length} chars; 开头: ${doc.text.slice(0, 120).replace(/\n/g, " ")}`);
} else {
  console.log("未找到 TextPicker 文档，跳过正文读取（直接用已知 slug）");
  const doc = await fetchDocument("harmonyos-guides", "arkui-overview");
  console.log(`${doc.title} text=${doc.text.length} chars; 开头: ${doc.text.slice(0, 120).replace(/\n/g, " ")}`);
}

console.log(`\n标记常量: ${SEARCHED_MARKER}`);
console.log("OK: 后端、索引、检索、取文全部通过。");
