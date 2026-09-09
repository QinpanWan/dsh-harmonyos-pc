# 本地 AI 模型接入：USE_AI 权限与白名单

> 目标：让 dsh 鸿蒙客户端（Web 端 dsh 服务）调用设备「本地 AI 模型管理」（`127.0.0.1:11434`，OpenAI/Ollama 兼容）。

## 当前状态

- `client/entry/src/main/module.json5` 已声明 `ohos.permission.USE_AI`（`requestPermissions`），并新增 `use_ai_permission_reason` 字符串。
- 若不处理签名/白名单，直接请求 `127.0.0.1:11434` 仍返回：
  `{"error":"Call is not allowed, app is not in the whitelist"}`

## 权限与签名（必须先做）

`ohos.permission.USE_AI` 是 **system_basic** 级别权限，默认 DevEco 自动签名（normal APL）**不授予**该权限。要让它生效：

1. 使用能授予 `system_basic` APL 的签名模板（Profile）签名应用。DevEco 里把签名模板的 APL 调成 `system_basic`，再自动签名。
2. 需要 `.p7b`（Provision Profile）和 `.cer`（证书）。签名后应用的证书指纹即「签名」身份。
3. `build-profile.json5 > app.signingConfigs` 目前为空，需在 DevEco 完成签名后回填。

## 白名单（本地 AI 模型管理）

「本地 AI 白名单」由系统服务维护（`com.huawei.hmos.aidataservice`），普通应用**无法本地写入**。三条路径：

1. **华为在线提单申请（官方）**：在开发者联盟提交「Data Augmentation Kit / 端侧问答模型」接口调用申请，需要：
   - 应用名称：`DeepSeek Harness`
   - bundleName：`com.dsh.harmonyos.client`
   - AppID（来自 AGC 控制台）
   - 支持 PC/2in1：是
2. **官方 SDK/桥接**：改用 `@kit.DataAugmentationKit` 的 `localChatModel.init()/chat()`（ArkTS 在客户端调用），由系统代为鉴权，绕过裸 HTTP 白名单。适合后续把 dsh 本地模型调用挪到客户端桥接层。
3. **本地调试替代**：若仅需本地对话，可继续用云端 Provider（DeepSeek）或自建 Ollama，绕开本地 AI 白名单。

## 验证

- 权限声明：`module.json5` 的 `requestPermissions` 含 `ohos.permission.USE_AI`。
- 请求探活：`curl http://127.0.0.1:11434/v1/models` 仍会白名单拦截，除非白名单/桥接已就绪。
