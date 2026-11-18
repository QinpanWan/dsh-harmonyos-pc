# dsh-copilot

把 GitHub Copilot 接进 dsh。插件只使用 Node 内置 `fetch`，不依赖原生模块，可在鸿蒙设备上运行。

## 能力

- **模型提供方**：在 dsh 模型选择器里注册 `GitHub Copilot`，提供 `GPT-5.4 nano`（默认）、`GPT-4.1`、`GPT-4o`；统一走 pi-ai 适配器，支持 dsh 的工具调用。
- **`copilot_ask` 工具**：单轮调用 Copilot，适合让 Copilot 做第二意见、代码解释或方案对比。
- **`copilot_status` 工具**：查询账号、套餐、API 地址和模型目录。

当前账号（`free_educational_quota`）里多数高级模型仍返回
`The requested model is not supported`。插件只暴露真实对话验证通过的三款：`gpt-5.4-nano`
走 `/responses`，`gpt-4.1` / `gpt-4o` 走 `/chat/completions`。其余目录条目可能只是
账号可见，不代表此套餐可用。

## 登录

复用 `copilot-hm` 的凭据：

```sh
copilot-hm login
copilot-hm status
```

也可以用环境变量 `COPILOT_GITHUB_TOKEN`（细粒度 PAT，需要 Copilot Requests 权限）
覆盖凭据文件。`GITHUB_TOKEN` 若是旧式 `ghp_` PAT 不可用。

## 配置

| 环境变量 | 默认值 | 说明 |
|---|---|---|
| `COPILOT_AUTH_FILE` | `~/.local/share/copilot-hm/auth.json` | 凭据文件 |
| `COPILOT_GITHUB_TOKEN` | — | 显式 token，优先于凭据文件 |
| `COPILOT_BASE_URL` | 凭据里的 `baseUrl` | Copilot API 根地址，默认 `https://api.individual.githubcopilot.com` |
| `COPILOT_TIMEOUT_MS` | `180000` | 单次工具/请求超时 |

## 鸿蒙 ProMax 接入策略

仓库根目录的 `harmony.patch.yml` 负责两件事：

1. `insert` 插件行 `id: copilot / name: dsh-copilot`，让 provider 与两个工具随 dsh 启动加载；
2. 把 `agent-default-model` 固定为 `provider: copilot / model: gpt-5.4-nano`。

鸿蒙客户端默认选中 `harmony-chat-promax`，其新会话直接使用 Copilot GPT-5.4 nano；
Web 端需手动选择 ProMax（它不是服务端默认 preset），但模型层默认仍对进程内新会话生效。
dsh 的默认模型是进程级单例，不能按 preset 分别保存；ProMax 的 persona 写明 Copilot
路由与回退策略，模型胶囊里仍可切到 `gpt-4.1` / `gpt-4o`。

`scripts/dsh-hm-update.mjs` 会把本目录部署到 `~/.dsh/profiles/web/plugins-src/dsh-copilot`
并建立 `node_modules` 软链，无需手工复制。

## 安装

从仓库部署时执行：

```sh
cd /storage/Users/currentUser/dsh-harmonyos-pc
node scripts/dsh-hm-update.mjs update
```

`update` 会同步插件、应用 `harmony.patch.yml` 并重启 dsh web。若从零手工安装：

```sh
PLUGIN="/storage/Users/currentUser/.dsh/profiles/web/plugins-src/dsh-copilot"
ln -sfn "$PLUGIN" "$HOME/.dsh/profiles/web/node_modules/dsh-copilot"
# ~/.dsh/profiles/web/cordis.patch.yml 末尾追加：
# - insert:
#     - id: copilot
#       name: 'dsh-copilot'
```

安装后重启 dsh web，模型选择器应出现 `GitHub Copilot` 下的 `GPT-5.4 nano`、`GPT-4.1`、`GPT-4o`。

## 验证

```sh
cd /storage/Users/currentUser/dsh-harmonyos-pc/plugins/dsh-copilot
node --test tests/*.test.mjs
grep '\[copilot\]' "$HOME/dsh-web.log"
```
