# dsh-huawei-local-llm

接入华为 / 鸿蒙 PC「官方本地大模型」的 dsh 插件。

- 本地模型服务端口：`127.0.0.1:11434`（华为本地 AI 模型管理，`Ollama / OpenAI 兼容`）
- 默认模型：`qwen3:8b`（可用环境变量或参数覆盖）

## 功能

| 能力 | 说明 |
| --- | --- |
| `huawei_local_llm` 工具 | 直连本地模型对话。先走 OpenAI 兼容 `/v1/chat/completions`，失败自动回退 Ollama 原生 `/api/chat`。 |
| `huawei_local_models` 工具 | 枚举本地模型并做连通性/白名单诊断。 |
| provider 注册 | 启动时幂等写入 `llm-pi-ai.providers.huawei-local` 到 `~/.dsh/settings.yaml`，模型选择器可选中本地模型。 |

## 安装 / 注册

插件已安装在本机时，若从零接入：

```sh
PLUGIN="$HOME/.dsh/profiles/web/plugins-src/dsh-huawei-local-llm"
mkdir -p "$PLUGIN/lib"
# 拷贝本目录下的 lib/index.js、package.json、README.md 到此
ln -sfn "$PLUGIN" "$HOME/.dsh/profiles/node_modules/dsh-huawei-local-llm"
# 在 ~/.dsh/profiles/web/package.json 的 dependencies 加上:
#   "dsh-huawei-local-llm": "link:$PLUGIN"
# 在 ~/.dsh/profiles/web/cordis.patch.yml 追加:
#   - insert:
#       - id: huawei-local-llm
#         name: 'dsh-huawei-local-llm'
# 重启 dsh web
sh ~/bin/dsh-daemon-runner.py
```

## 配置

环境变量（工具运行时读取）：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `HUAWEI_LLM_BASE_URL` | `http://127.0.0.1:11434` | 本地模型服务地址（会自动拼 `/v1` 或 `/api`）。 |
| `HUAWEI_LLM_MODEL` | `qwen3:8b` | 默认模型 id。 |
| `HUAWEI_LLM_API_KEY` | — | 设置后作为 `Authorization: Bearer <key>`。 |
| `HUAWEI_LLM_HEADERS` | — | JSON 字符串，额外请求头（例如 `{"X-App-Id":"..."}`）。 |
| `HUAWEI_LLM_TIMEOUT_MS` | `120000` | 单次调用超时。 |

provider 的模型列表在 `~/.dsh/settings.yaml` 的
`llm-pi-ai.providers.huawei-local.models` 下，可自行增删。

## 白名单限制（重要）

实测当前设备对任意非白名单调用方返回：

```json
{"error": "Call is not allowed, app is not in the whitelist"}
```

这是鸿蒙本地 AI 引擎的应用级白名单校验，不是协议问题；仅凭请求头目前无法绕过。
解决方向（按官方要求）：

1. dsh 所属应用在 `module.json5` 声明 `ohos.permission.USE_AI`，并让应用签名/包名进入本地 AI 白名单；
2. 或改走鸿蒙官方本地 AI SDK / 桥接转发；
3. 或使用模型管理器的已授权入口，并注入其签发的 app token（用 `HUAWEI_LLM_HEADERS` 或 `HUAWEI_LLM_API_KEY`）。

在打通白名单前，工具仍会正确发起请求并给出清晰的错误与指引。

## 模型选择器可见性说明

本机 `dsh-llm-pi-ai` 命名空间未挂载（`settings.describe()` 不返回 `llm-pi-ai`），
若只把 provider 写入 `settings.yaml`，模型选择器读不到（`session.modelCatalog` 不包含
`huawei-local`）。因此插件现在**另走一条自包含路径**：

- 启动时用 `@earendil-works/pi-ai` 的 `createProvider` + `@deepseek-ai/dsh-llm-pi-ai` 的
  `PiAiAdapter` 构建一个 OpenAI 兼容适配器，并直接 `ctx.llm.registerAdapter(['huawei-local'], adapter)`；
- 已在 `listProviders()` 时跳过（避免与 `dsh-llm-pi-ai` 正常工作时重复注册）；
- 注册失败只告警，不影响 dsh 启动与工具加载。

这样 `huawei-local` 会出现在模型选择器与「模型」设置页的 provider 列表里。

## 手动添加 provider

若不依赖插件自动写入，可在 `~/.dsh/settings.yaml` 的 `llm-pi-ai.providers` 下加：

```yaml
llm-pi-ai:
  providers:
    huawei-local:
      displayName: 华为官方本地大模型 (127.0.0.1:11434)
      api: openai-completions
      baseURL: http://127.0.0.1:11434/v1
      models:
        - id: qwen3:8b
          name: Qwen3 8B（华为本地）
          contextWindow: 32768
          maxTokens: 8192
```

## 验证

```sh
# 工具直连（可看到白名单/模型列表）
cd "$HOME/.dsh/profiles/web/plugins-src/dsh-huawei-local-llm"
node --input-type=module -e "import('./lib/index.js').then(m=>console.log('ok',m.name))"

# 确认插件加载
grep huawei ~/dsh-web.log
```
