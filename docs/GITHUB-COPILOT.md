# GitHub Copilot 接入策略（鸿蒙 ProMax）

本仓库把 GitHub Copilot 作为 dsh 的纯 JS 模型提供方接入，默认用于
`harmony-chat-promax`。不依赖 VS Code、不加载原生模块、不把 OAuth token 写进仓库。

## 架构

```text
HarmonyOS dsh
└── dsh-copilot（plugins/dsh-copilot）
    ├── provider: copilot
    │   ├── gpt-5.4-nano  → POST /responses
    │   ├── gpt-4.1       → POST /chat/completions
    │   └── gpt-4o        → POST /chat/completions
    ├── copilot_ask       单轮问答
    └── copilot_status    账号 / 套餐 / 模型目录
            │
            └── 读取 ~/.local/share/copilot-hm/auth.json
```

插件通过 `@deepseek-ai/dsh-llm-pi-ai` 的 `PiAiAdapter` 注册 provider，因此模型选择器、
工具调用、流式输出都走 dsh 原生的 LLM 通路。HTTP 请求只使用 Node 内置 `fetch`。

## 认证

优先复用 `copilot-hm` 的设备码 OAuth 凭据：

```sh
copilot-hm login
copilot-hm status
```

凭据文件默认是 `/storage/Users/currentUser/.local/share/copilot-hm/auth.json`。也可用
`COPILOT_GITHUB_TOKEN` 覆盖，但必须是带 Copilot Requests 权限的细粒度 PAT；旧式
`ghp_` classic PAT 不支持推理接口。

## 模型策略

| 模型 | 协议 | 上下文 | 输出上限 | 用途 |
| --- | --- | ---: | ---: | --- |
| `gpt-5.4-nano` | Responses | 400k | 128k | ProMax 默认，长上下文、工具调用、日常交付 |
| `gpt-4.1` | Chat Completions | 128k | 16k | 兼容性回退、保守工具调用 |
| `gpt-4o` | Chat Completions | 128k | 4k | 短任务、低成本 |

目录里能看到的高级模型（如 `gpt-5.6-luna`、`gpt-6-luna`、`kimi-k3`）在当前账号套餐下
会返回 HTTP 400 `model_not_supported`。插件只暴露真实对话验证通过的三款，避免模型选择器
混入不可用条目。

## 鸿蒙挂载

`harmony.patch.yml` 做两件事：

```yaml
- id: agent-default-model
  name: '@deepseek-ai/dsh-agent-default-model'
  config:
    provider: copilot
    model: gpt-5.4-nano
- insert:
    - id: copilot
      name: dsh-copilot
```

dsh 的 `agentDefaultModel` 是**进程级单例**，不能按 preset 保存不同默认值。因此这里把
全局默认设为 Copilot GPT-5.4 nano。鸿蒙客户端默认选中 `harmony-chat-promax`，其新会话
会直接命中该路由；Web 端需手动选择 ProMax（它在 `agentPresets/list` 里不是服务端默认
preset），但模型层默认仍对进程内的新会话生效。ProMax 的 persona 另外写明 `gpt-4.1` /
`gpt-4o` 的回退策略。模型胶囊仍可手动切模型。

## 安装与更新

```sh
cd /storage/Users/currentUser/dsh-harmonyos-pc
node scripts/dsh-hm-update.mjs update
```

更新器会把 `plugins/dsh-copilot` 同步到 web profile 的 `plugins-src`，建立
`node_modules/dsh-copilot` 软链，然后重启 dsh。`harmony.patch.yml` 由 `dsh-web.sh`
自动作为 `--patch` 叠加。

## 验证

```sh
cd /storage/Users/currentUser/dsh-harmonyos-pc/plugins/dsh-copilot
node --test tests/*.test.mjs
cd /storage/Users/currentUser/dsh-harmonyos-pc
grep '\[copilot\]' /storage/Users/currentUser/dsh-web.log | tail -5
curl -s http://127.0.0.1:3080/ -o /dev/null -w '%{http_code}\n'
```

预期：单元测试全过；启动日志包含 `registered 2 tools` 与 `provider "copilot" -> llm adapter`；
`session/modelCatalog` 的 `routableProviders` 包含 `copilot`；健康检查返回 `303`。

## 已知限制

- dsh 默认模型不能按 preset 分区，只有进程级单例。
- Copilot 套餐会变化；模型目录里的 `enabled` 不等于当前套餐可调用。
- 插件只负责推理接入，不提供 VS Code 式行内补全。
- token 只存在本机凭据文件或进程环境变量，仓库与日志都不写入完整凭据。
