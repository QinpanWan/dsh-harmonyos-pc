// enforce.js — 鸿蒙开发意图检测 + 「强制先检索华为开发者文档」守卫文案（纯函数，可单测）。

/** 检索完成标记：huawei_devdocs_search 的结果文本首行固定包含，供守卫识别「本问题已检索过」。 */
export const SEARCHED_MARKER = "HUAWEI_DEVDOCS_SEARCHED";

/** 强信号：命中任意一条即判定为鸿蒙开发意图。 */
const STRONG_PATTERNS = [
  /鸿蒙/,
  /\bharmonyos\b/i,
  /\bohos\b/i,          // @ohos.* 导入、ohos 工程
  /\barkts\b/i,
  /\barkui\b/i,
  /\bhvigorw?\b/i,
  /\bohpm\b/i,
  /\bhdc\b/i,
  /\bdeveco\b/i,
  /元服务/,
  /@kit\.[A-Za-z]/,
  /\.ets\b/,
  /module\.json5|oh-package\.json5|build-profile\.json5|app\.json5/,
];

/** 弱信号：命中 >=2 条才判定（避免对通用话题误报）。 */
const WEAK_PATTERNS = [
  /\bability\b/i,
  /\bhap\b|\bhar\b|\bhsp\b/i,
  /stage\s*模型/i,
  /端侧/,
  /服务卡片|原子化服务|卡片服务/,
  /上架|应用市场/,
  /\b@ohos\./,
];

function countMatches(patterns, text) {
  let hits = 0;
  for (const pattern of patterns) {
    if (pattern.test(text)) hits += 1;
  }
  return hits;
}

/** 判定一段文本是否属于鸿蒙/HarmonyOS 开发。 */
export function isHarmonyDevIntent(text) {
  const content = String(text ?? "");
  if (!content.trim()) return false;
  if (countMatches(STRONG_PATTERNS, content) >= 1) return true;
  return countMatches(WEAK_PATTERNS, content) >= 2;
}

/** 提取消息列表的可见文本（递归覆盖 text 块/嵌套 content/纯字符串）。 */
export function textOfMessages(messages) {
  const parts = [];
  for (const message of Array.isArray(messages) ? messages : []) {
    const content = message?.content;
    if (typeof content === "string") {
      parts.push(content);
      continue;
    }
    if (!Array.isArray(content)) continue;
    const push = (block) => {
      if (!block) return;
      if (typeof block === "string") parts.push(block);
      else if (typeof block?.text === "string") parts.push(block.text);
      else if (typeof block?.content === "string") parts.push(block.content);
      else if (Array.isArray(block?.content)) block.content.forEach(push);
    };
    content.forEach(push);
  }
  return parts.join("\n");
}

/** 消息列表是否包含检索完成标记。 */
export function hasSearchedMarker(messages) {
  return textOfMessages(messages).includes(SEARCHED_MARKER);
}

/** 找到最后一个 user 角色的消息索引；guard 消息（plugin source）不算用户新问题。 */
export function lastUserIndex(messages) {
  const list = Array.isArray(messages) ? messages : [];
  for (let i = list.length - 1; i >= 0; i--) {
    const message = list[i];
    if (message?.role !== "user") continue;
    const source = message?.source ?? message?.pluginSource;
    if (source?.kind === "plugin") continue; // 插件注入的守卫不是新问题
    return i;
  }
  return -1;
}

/** 单个预置轮次的状态机：决定本轮是否注入守卫。 */
export function decideInjection({ harmony, searched, injections, maxInjections = 2 }) {
  if (!harmony || searched) return { inject: false, reason: searched ? "已检索" : "非鸿蒙" };
  if (injections >= maxInjections) {
    return { inject: false, reason: "已达本轮上限", exhausted: true };
  }
  return { inject: true, reason: "鸿蒙开发问题且尚未检索官方文档" };
}

/** 守卫文案（attempt=1..n，语气递增）。 */
export function buildGuardText(attempt = 1) {
  const base =
    "【强制规则 · 华为开发者文档检索】当前是 HarmonyOS/鸿蒙 开发问题。本机约定：涉及鸿蒙 " +
    "API、ArkTS/ArkUI 代码、工程配置（module.json5 / hvigor / ohpm）、版本与权限细节时，必须先调用 " +
    "`huawei_devdocs_search` 检索华为开发者官方文档（覆盖 开发指南 / API参考 / 版本说明 / 最佳实践 / FAQ），" +
    "再用 `huawei_devdocs_get` 读取命中页面原文，最后基于检索结果作答；禁止仅凭记忆输出可能过期的 API 细节。";
  if (attempt <= 1) {
    return `${base}\n请现在先执行 \`huawei_devdocs_search\`，不要跳过检索直接作答。`;
  }
  return (
    `${base}\n（第 ${attempt} 次提醒）你仍未执行 \`huawei_devdocs_search\`。` +
    "该检索是本环境的强制前置步骤。若工具异常，请先调用 `huawei_devdocs_status` 诊断并如实说明原因，" +
    "不要直接输出未经检索的鸿蒙 API 细节。"
  );
}
