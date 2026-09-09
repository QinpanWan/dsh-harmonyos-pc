import { test } from "node:test";
import assert from "node:assert/strict";
import {
  SEARCHED_MARKER,
  isHarmonyDevIntent,
  textOfMessages,
  hasSearchedMarker,
  lastUserIndex,
  decideInjection,
  buildGuardText,
} from "../lib/enforce.js";

test("鸿蒙开发意图检测：强信号命中", () => {
  assert.equal(isHarmonyDevIntent("帮我写一个 HarmonyOS 应用的 ArkTS 页面"), true);
  assert.equal(isHarmonyDevIntent("module.json5 里怎么声明权限？"), true);
  assert.equal(isHarmonyDevIntent("@kit.AbilityKit 的 startAbility 用法"), true);
  assert.equal(isHarmonyDevIntent("ohpm install @ohos/hypium 报错"), true);
  assert.equal(isHarmonyDevIntent("这个 .ets 文件编译不过"), true);
  assert.equal(isHarmonyDevIntent("鸿蒙应用如何上架应用市场"), true);
});

test("鸿蒙开发意图检测：弱信号需 >=2", () => {
  assert.equal(isHarmonyDevIntent("写一个卡片式 UI 的网页"), false);
  assert.equal(isHarmonyDevIntent("端侧模型能力与上架审核有关吗"), true); // 端侧 + 上架
  assert.equal(isHarmonyDevIntent("Ability 和 Stage 模型有什么区别"), true); // ability + stage模型
});

test("非鸿蒙话题不误报", () => {
  assert.equal(isHarmonyDevIntent("帮我写个 python 爬虫"), false);
  assert.equal(isHarmonyDevIntent("React 的 useState 怎么用"), false);
  assert.equal(isHarmonyDevIntent(""), false);
});

test("检索标记检测", () => {
  const searched = [{ role: "tool", content: [{ type: "text", text: `[${SEARCHED_MARKER}] 检索完成` }] }];
  assert.equal(hasSearchedMarker(searched), true);
  assert.equal(hasSearchedMarker([{ role: "assistant", content: "没检索" }]), false);
});

test("消息文本提取与最后用户消息", () => {
  const messages = [
    { role: "user", content: "第一个问题" },
    { role: "assistant", content: [{ type: "text", text: "回答" }] },
    { role: "user", content: "鸿蒙 ArkUI 布局怎么居中？" },
  ];
  assert.equal(lastUserIndex(messages), 2);
  assert.match(textOfMessages(messages), /ArkUI/);
});

test("插件守卫消息不算新用户问题", () => {
  const messages = [
    { role: "user", content: "问题" },
    { role: "user", content: "守卫", source: { kind: "plugin", plugin: "huawei-devdocs" } },
  ];
  assert.equal(lastUserIndex(messages), 0);
});

test("注入决策：未检索注入 / 已检索不注入 / 达上限停", () => {
  assert.equal(decideInjection({ harmony: true, searched: false, injections: 0 }).inject, true);
  assert.equal(decideInjection({ harmony: true, searched: true, injections: 0 }).inject, false);
  assert.equal(decideInjection({ harmony: false, searched: false, injections: 0 }).inject, false);
  const exhausted = decideInjection({ harmony: true, searched: false, injections: 2, maxInjections: 2 });
  assert.equal(exhausted.inject, false);
  assert.equal(exhausted.exhausted, true);
});

test("守卫文案包含强制指令与工具名", () => {
  const text = buildGuardText(1);
  assert.match(text, /huawei_devdocs_search/);
  assert.match(text, /强制规则/);
  const retry = buildGuardText(2);
  assert.match(retry, /第 2 次提醒/);
  assert.match(retry, /huawei_devdocs_status/);
});
