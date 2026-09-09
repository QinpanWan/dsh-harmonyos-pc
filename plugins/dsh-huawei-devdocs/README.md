# dsh-huawei-devdocs

华为开发者文档（HarmonyOS/鸿蒙）检索插件：为 dsh 提供「检索华为开发者官方文档」的工具，
并在检测到鸿蒙应用开发意图时**强制先检索官方文档再作答**，防止模型凭记忆输出过期/错误的 API 细节。

- 数据源：`developer.huawei.com` 官方文档门户后端（`documentPortal` REST，站点 SPA 同源接口）
- 检索覆盖：**开发指南 / API参考 / 版本说明 / 最佳实践 / FAQ**（约 1.6 万篇，与官网准实时同步）
- 实现：纯 JS + 全局 `fetch`，无任何原生/第三方依赖；索引落盘缓存到 `~/.dsh/cache/huawei-devdocs/`
- 语义对齐：与华为官方「鸿蒙开发者知识 MCP 服务」的 `searchDocuments` 同源（官方文档内容实时检索 + 全文获取）

## 工具

| 工具 | 说明 |
| --- | --- |
| `huawei_devdocs_search` | 关键词检索官方文档目录（中文/英文均可），返回标题、章节路径、分类与官方 URL。结果首行含 `HUAWEI_DEVDOCS_SEARCHED` 标记，供强制守卫识别「本问题已检索」。 |
| `huawei_devdocs_get` | 按官方 URL 读取单篇文档全文（正文纯文本，默认前 15000 字符；长文档用 `start` 翻页，`maxChars` 调页长）。 |
| `huawei_devdocs_catalog` | 浏览某分类顶层章节（含每章文档数），适合定位不熟悉的关键词。 |
| `huawei_devdocs_status` | 诊断：官方门户连通性、各分类索引缓存、强制规则开关与当前配置。 |

## 强制机制（核心）

在 `agent/pre-step`（进入模型前）挂守卫，参照 `dsh-prompt-antivirus` 的注入模式：

1. 取当前**用户提问**文本，检测鸿蒙开发意图：
   - 强信号（命中任一即触发）：`鸿蒙`、`harmonyos`、`ohos`、`arkts`、`arkui`、`hvigor(w)`、`ohpm`、
     `hdc`、`deveco`、`元服务`、`@kit.*`、`.ets`、`module.json5 / oh-package.json5 / build-profile.json5` 等
   - 弱信号（命中 ≥2 才触发，避免误报）：`ability`、`hap/har/hsp`、`stage 模型`、`端侧`、`卡片/服务卡片`、`上架/应用市场` 等
2. 若触发且自该提问以来**没有** `huawei_devdocs_search` 的成功结果（结果文本含 `HUAWEI_DEVDOCS_SEARCHED` 标记），
   向模型注入 user 角色守卫消息：必须先用 `huawei_devdocs_search` 检索、再用 `huawei_devdocs_get` 读原文，禁止直接凭记忆输出 API 细节。
3. 每轮用户提问最多注入 `maxInjections`（默认 2）次；仍未检索则注入最终提示（要求先 `huawei_devdocs_status` 诊断工具异常）。

只要模型先执行了检索，检索结果文本的标记即被识别，后续步骤不再重复注入。切到下一个新问题（指纹变化）时重新武装。

关闭/调整：

```sh
HUAWEI_DEVDOCS_ENFORCE=off        # 关闭强制（仅保留工具）
HUAWEI_DEVDOCS_MAX_INJECTIONS=1   # 每问最多注入 1 次
```

## 安装 / 注册

插件目录：`~/.dsh/profiles/web/plugins-src/dsh-huawei-devdocs/`

```sh
PLUGIN="$HOME/.dsh/profiles/web/plugins-src/dsh-huawei-devdocs"
# 1) 共享 node_modules 软链（web 与 headless 均解析自 profiles/node_modules）
ln -sfn "$PLUGIN" "$HOME/.dsh/profiles/node_modules/dsh-huawei-devdocs"
# 2) web profile package.json dependencies 增加：
#    "dsh-huawei-devdocs": "link:$PLUGIN"
# 3) web profile cordis.patch.yml 追加：
#    - insert:
#        - id: huawei-devdocs
#          name: 'dsh-huawei-devdocs'
# 4) headless profile cordis.patch.yml（AgentHub/@dsh 子代理）追加同样的 insert
# 5) 重启 dsh web
sh ~/bin/dsh-daemon-runner.py
```

本机已按上述步骤注册完成。启动日志应出现：

```
[huawei-devdocs] 已加载: enforce=strict, maxInjections=2, catalogs=5 (harmonyos-guides,harmonyos-references,...)
```

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `HUAWEI_DEVDOCS_ENFORCE` | `strict` | `strict`=强制检索；`off`=仅工具不注入守卫 |
| `HUAWEI_DEVDOCS_MAX_INJECTIONS` | `2` | 每个用户提问最多注入守卫次数 |
| `HUAWEI_DEVDOCS_MAX_RESULTS` | `20` | 检索默认返回条数 |
| `HUAWEI_DEVDOCS_API_BASE` | `https://svc-drcn.developer.huawei.com/.../documentPortal` | 官方门户 API 地址（一般无需改） |
| `HUAWEI_DEVDOCS_TIMEOUT_MS` | `20000` | 单次 HTTP 超时 |
| `HUAWEI_DEVDOCS_INDEX_TTL_MS` | `12h` | 目录索引缓存有效期 |
| `HUAWEI_DEVDOCS_OFFLINE` | `0` | `1`=仅用本地缓存索引，不联网 |
| `HUAWEI_DEVDOCS_CACHE_DIR` | `~/.dsh/cache/huawei-devdocs` | 索引缓存目录 |

## 验证

```sh
cd ~/.dsh/profiles/web/plugins-src/dsh-huawei-devdocs
npm test                        # 纯逻辑单测（意图检测/分词/HTML 转文本/URL 解析）
node scripts/verify.mjs --live  # 真实后端：连通性 + 全分类索引 + 检索 + 读全文
```

在 dsh 会话中让模型执行 `huawei_devdocs_status` 可查看运行态诊断；对鸿蒙问题先不要检索、直接作答，
观察是否被注入「强制规则」守卫（模型会被告知必须先检索）。

## 故障排查

- 搜索报错/超时：先跑 `huawei_devdocs_status` 看 `probe`；确认网络可访问 `svc-drcn.developer.huawei.com`
  （个别网络需放行该域或关代理拦截）。有旧缓存时搜索会自动降级为缓存结果并在 note 中标注「缓存降级」。
- 强制守卫误报/漏报：检测词表在 `lib/enforce.js`（`STRONG_PATTERNS` / `WEAK_PATTERNS`），可自行增删。
- 想彻底关掉强制：设 `HUAWEI_DEVDOCS_ENFORCE=off` 后重启。
- 缓存损坏/过期：删 `~/.dsh/cache/huawei-devdocs/*.json` 后重新搜索即重建。
- 该插件依赖的官方 REST 接口即官网页面本身使用的接口；若华为调整接口，工具会报错并可据
  `lib/huawei-api.js` 中 `postPortal` 的三处服务名快速适配。

## 数据来源与合规

文档标题/正文/版本号均实时取自华为开发者官网官方后端（与官网页面同源），索引仅缓存文档
**标题/路径/URL**，正文按需拉取，不做全文镜像。本插件为开发辅助，请以华为开发者官网内容为准。
