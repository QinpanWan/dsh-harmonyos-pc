import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  COPILOT_MODELS,
  DEFAULT_MODEL,
  apiForModel,
  identityHeaders,
  messageText,
  responsesRequest,
  responseText,
  resolveBaseURL,
  resolveToken
} from "../lib/copilot.js";

test("默认模型是 gpt-5.4-nano", () => {
  assert.equal(DEFAULT_MODEL, "gpt-5.4-nano");
});

test("模型按各自协议分流", () => {
  assert.equal(apiForModel("gpt-5.4-nano"), "openai-responses");
  assert.equal(apiForModel("gpt-4.1"), "openai-completions");
  assert.equal(apiForModel("gpt-4o"), "openai-completions");
  assert.deepEqual(COPILOT_MODELS.map((model) => model.id), ["gpt-5.4-nano", "gpt-4.1", "gpt-4o"]);
});

test("Copilot 身份头包含 CLI 集成标识", () => {
  const headers = identityHeaders();
  assert.equal(headers["Copilot-Integration-Id"], "copilot-developer-cli");
  assert.equal(headers["Editor-Version"], "vscode/1.107.0");
  assert.equal(headers["x-initiator"], "user");
});

test("支持字符串与分片数组消息", () => {
  assert.equal(messageText({ content: "hello" }), "hello");
  assert.equal(messageText({ content: [{ text: "he" }, "llo"] }), "hello");
  assert.equal(messageText({ content: null }), "");
});

test("Responses 请求把 system 转成 instructions", () => {
  assert.deepEqual(responsesRequest([
    { role: "system", content: "be brief" },
    { role: "user", content: "hello" }
  ]), {
    instructions: "be brief",
    input: [{ role: "user", content: "hello" }]
  });
});

test("Responses 输出支持 output_text 与 output 数组", () => {
  assert.equal(responseText({ output_text: "hello" }), "hello");
  assert.equal(responseText({ output: [{ content: [{ type: "output_text", text: "he" }, { type: "text", text: "llo" }] }] }), "hello");
});

test("COPILOT_BASE_URL 可覆盖凭据里的地址", () => {
  const previous = process.env.COPILOT_BASE_URL;
  process.env.COPILOT_BASE_URL = "https://example.test/";
  try {
    assert.equal(resolveBaseURL(), "https://example.test");
  } finally {
    if (previous === void 0) delete process.env.COPILOT_BASE_URL;
    else process.env.COPILOT_BASE_URL = previous;
  }
});

test("显式环境变量优先于凭据文件", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dsh-copilot-"));
  const authFile = path.join(dir, "auth.json");
  fs.writeFileSync(authFile, JSON.stringify({ token: "file-token" }));
  const previousAuth = process.env.COPILOT_AUTH_FILE;
  const previousToken = process.env.COPILOT_GITHUB_TOKEN;
  const previousGhToken = process.env.GH_TOKEN;
  const previousGithubToken = process.env.GITHUB_TOKEN;
  process.env.COPILOT_AUTH_FILE = authFile;
  process.env.COPILOT_GITHUB_TOKEN = "env-token";
  process.env.GH_TOKEN = "generic-gh-token";
  process.env.GITHUB_TOKEN = "generic-token";
  try {
    assert.equal(resolveToken(), "env-token");
    delete process.env.COPILOT_GITHUB_TOKEN;
    assert.equal(resolveToken(), "file-token");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
    if (previousAuth === void 0) delete process.env.COPILOT_AUTH_FILE;
    else process.env.COPILOT_AUTH_FILE = previousAuth;
    if (previousToken === void 0) delete process.env.COPILOT_GITHUB_TOKEN;
    else process.env.COPILOT_GITHUB_TOKEN = previousToken;
    if (previousGhToken === void 0) delete process.env.GH_TOKEN;
    else process.env.GH_TOKEN = previousGhToken;
    if (previousGithubToken === void 0) delete process.env.GITHUB_TOKEN;
    else process.env.GITHUB_TOKEN = previousGithubToken;
  }
});
