import { test } from "node:test";
import assert from "node:assert/strict";
import { tokenize, searchEntries, topSections } from "../lib/search.js";
import { htmlToText, parseDocRef } from "../lib/huawei-api.js";

const SAMPLE = [
  { title: "TextPicker 文本选择器", slug: "ts-basic-components-textpicker", path: "基础组件 / TextPicker 文本选择器", catalog: "harmonyos-guides", catalogLabel: "开发指南", url: "https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ts-basic-components-textpicker" },
  { title: "应用权限申请指导", slug: "app-permission-request-guide", path: "安全 / 应用权限申请指导", catalog: "harmonyos-guides", catalogLabel: "开发指南", url: "https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/app-permission-request-guide" },
  { title: "@ohos.app.ability.UIAbility", slug: "js-apis-app-ability-uiAbility", path: "API参考 / Ability / UIAbility", catalog: "harmonyos-references", catalogLabel: "API参考", url: "https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-app-ability-uiAbility" },
  { title: "状态管理 V1：@State", slug: "arkts-state-management", path: "ArkUI / 状态管理 / @State", catalog: "harmonyos-guides", catalogLabel: "开发指南", url: "https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state-management" },
];

test("分词：中英混合", () => {
  const tokens = tokenize("TextPicker 文本选择器");
  assert.ok(tokens.includes("textpicker"));
  assert.ok(tokens.includes("文本"));
  assert.ok(tokens.includes("选择"));
});

test("英文关键词命中标题", () => {
  const hits = searchEntries(SAMPLE, "TextPicker", { limit: 5 });
  assert.equal(hits.length >= 1, true);
  assert.equal(hits[0].slug, "ts-basic-components-textpicker");
});

test("中文关键词按相关度排序", () => {
  const hits = searchEntries(SAMPLE, "文本选择器", { limit: 5 });
  assert.ok(hits.length >= 1);
  assert.equal(hits[0].title.includes("TextPicker"), true);
});

test("权限类查询能覆盖到 API 参考", () => {
  const hits = searchEntries(SAMPLE, "权限", { limit: 5 });
  assert.ok(hits.some((h) => h.title.includes("权限")));
});

test("topSections 聚合顶层章节", () => {
  const sections = topSections(SAMPLE);
  assert.ok(sections.some((s) => s.name.includes("基础组件")));
  assert.ok(sections.some((s) => s.name.includes("安全")));
});

test("官方 HTML 转文本保留标题与代码块", () => {
  const html = `<html><body><h1>ArkUI 简介</h1><p>方舟UI框架为应用提供UI能力。</p><pre>Column(){ Text("hi") }</pre><ul><li>组件</li><li>布局</li></ul></body></html>`;
  const text = htmlToText(html);
  assert.match(text, /ArkUI 简介/);
  assert.match(text, /Column\(\)/);
  assert.match(text, /组件/);
});

test("官方 URL 解析", () => {
  const ref = parseDocRef("https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkui-overview");
  assert.deepEqual(ref, { catalog: "harmonyos-guides", slug: "arkui-overview" });
  const bare = parseDocRef("harmonyos-references/js-apis-ohos-ability");
  assert.deepEqual(bare, { catalog: "harmonyos-references", slug: "js-apis-ohos-ability" });
  assert.equal(parseDocRef("https://example.com/other"), null);
});
