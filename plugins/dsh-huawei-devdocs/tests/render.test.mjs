// 渲染回归：dsh-tools 0.1.2-rc.1 调用 output.render 的约定是 render(exec.arguments, value)
// （入参在前、结果在后）。渲染函数必须取第二个参数 value，否则会把入参对象当结果渲染，
// 表现为 [huawei_devdocs_search] 失败: 未知错误 / huawei_devdocs_status 返回 {}。
import { test } from "node:test";
import assert from "node:assert/strict";
import { renderSearch, renderGet, renderCatalog, renderStatus } from "../lib/index.js";
import { SEARCHED_MARKER } from "../lib/enforce.js";

function textOf(blocks) {
  return blocks.map((b) => b.text ?? "").join("\n");
}

test("render 按 (args, value) 约定取第二个参数作为结果", () => {
  const search = textOf(renderSearch({ query: "TextPicker" }, { ok: true, query: "TextPicker", count: 2, results: [], error: "" }));
  assert.ok(search.includes(SEARCHED_MARKER), "search 结果应以成功标记开头，而非渲染入参");
  assert.ok(!search.includes("未知错误"));

  const status = textOf(renderStatus({}, { ok: true, apiBase: "https://x", catalogs: [] }));
  assert.ok(status.includes('"ok": true'), "status 应渲染结果对象而非空入参 {}");

  const failed = textOf(renderSearch({ query: "x" }, { ok: false, error: "连接超时" }));
  assert.ok(failed.includes("失败: 连接超时"), "真实错误应透出 error 字段");

  const get = textOf(renderGet({ url: "u" }, { ok: true, title: "ArkUI 简介", content: "正文", url: "u", totalChars: 2 }));
  assert.ok(get.includes("ArkUI 简介"));

  const catalog = textOf(renderCatalog({ catalog: "harmonyos-guides" }, { ok: true, label: "开发指南", total: 1, sections: [] }));
  assert.ok(catalog.includes("开发指南"));
});
