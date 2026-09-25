# 上游桌面端源码快照（只读参考）

本目录是 **DeepSeek Harness 官方桌面端（Electron 壳）** 的源码快照，仅作离线查阅与「逐行对照移植」用途，
运行时**不参与**鸿蒙客户端构建（`client/` 才是可编译产物）。

## 出处

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/deepseek-ai/deepseek-harness |
| 分支 | `master`（注意：**不是 `main`**，raw 取文件用错分支会 404） |
| 提交 | `477b4f420553e8a52c2fbccc464d7561b239c443`（2026-09-24，Merge PR #5180 from rel/dsh-0.1.7-rc.2） |
| 应用版本 | `@deepseek-ai/dsh-desktop@0.1.7-rc.2` |
| 抓取时间 | 2026-09-25（Asia/Shanghai） |
| 抓取方式 | `curl -sSL -o dsh-master.tar.gz https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/refs/heads/master`（32,385,353 B）后解出 `apps/` |
| 许可证 | MIT，Copyright (c) 2026 DeepSeek（见 `LICENSE`，第三方声明见 `THIRD_PARTY_NOTICES.md`） |

## 目录内容

- `apps/desktop/` —— Electron 桌面壳本体（441 文件，6.0 MB）：主进程 `src/main.ts`、预加载脚本 `src/preload-*.ts`、
  自绘窗口 UI `src/client/`、安装器脚本 `installer/`、打包与发布 `scripts/`、快照用期望值 `tests/expected/`。
- `apps/desktop-host/` —— Desktop 私有 Host（143 KB）：`src/index.ts` 生命周期协议、`office.ts` 文档引擎、
  `quit-inspection.ts` 退出前任务巡检、`update-tasks.ts` 更新前任务停止。
- 未包含 `packages/`、`apps/web`、`apps/cli`：本快照只服务于「桌面壳层」的移植对照；Web 客户端与 dsh 内核走 npm 安装。

## 与鸿蒙移植的关系

上游壳层能力到鸿蒙的映射见 `../docs/HARMONY-DESKTOP-PORT.md`，上游架构剖析见 `../docs/DESKTOP-SHELL-UPSTREAM.md`。
关键差别一句话：上游用 Electron 进程承载「窗口 + 菜单 + 更新器 + 打包 Web 页面」，
鸿蒙侧换成 **ArkTS/ArkUI 原生 Ability 承载同一套壳层语义**，dsh 内核仍走本机服务（3080/19387）。

## 刷新快照

```sh
cd ~/dsh-desktop-src && \
curl -sSL -o dsh-master.tar.gz https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/refs/heads/master && \
tar xzf dsh-master.tar.gz && \
rm -rf ~/dsh-harmonyos-pc/desktop-upstream/apps && \
cp -r deepseek-harness-master/apps/desktop deepseek-harness-master/apps/desktop-host ~/dsh-harmonyos-pc/desktop-upstream/apps/
```

> 刷新后请同步更新本文件的「提交 / 版本 / 抓取时间」三行，并在仓库 README 更新记录里补一条。
