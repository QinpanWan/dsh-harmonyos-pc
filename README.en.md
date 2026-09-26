[简体中文](README.md) | **English**

# dsh-harmonyos-pc

<p align="center"><img src="repo-cover-teal.png" alt="dsh-harmonyos-pc cover" width="100%"></p>

<p align="center">
  <img alt="HarmonyOS" src="https://img.shields.io/badge/HarmonyOS-Adapt-blue">
  <img alt="DeepSeek Harness" src="https://img.shields.io/badge/DeepSeek_Harness-dsh-41b0ff">
  <img alt="Cache Hit" src="https://img.shields.io/badge/Cache_Hit-98%25-orange">
  <img alt="Node.js 22 / 24 / 26 (not pinned)" src="https://img.shields.io/badge/Node.js-22%E2%80%9326-black">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
</p>

A complete adaptation suite to get [DeepSeek Harness](https://github.com/deepseek-ai/dsh) (dsh) fully running on **HarmonyOS** devices.

<p align="center">
  <img src="repo-cover-aurora.png" alt="dsh-harmonyos-pc features: cache hit 93.8%~98%, 30x lower conversation cost, pure-JS zero-dependency, MIT" width="85%">
</p>

<p align="center">
  <a href="repo-cover.png"><img src="repo-cover.png" alt="dsh-harmonyos-pc cover (navy)" width="85%"></a>
</p>

> Almost nobody has done this on HarmonyOS—native ELF/.node modules, node-pty, and Koffi simply cannot load on such devices. This repository distills the whole engineering effort—installation, patching, cache optimization, plugin installation, and self-update—into a reproducible open-source solution.

> **QQ group for project discussion: 930088487** — HarmonyOS dsh adaptation, cache optimization, and plugin development. You're welcome to join.
>
> **Beginner tutorial** (online): [Open the dsh-harmonyos-pc beginner installation tutorial](https://docs.google.com/document/d/1f3l-Q2Di6DmPy4xydYr4lUYIxmoOA014D63XNBTPSys/edit)

> **About this project**: A complete adaptation suite to get DeepSeek Harness (dsh) fully running on HarmonyOS devices. Almost nobody has done this on HarmonyOS—native ELF/.node modules, node-pty, and Koffi cannot load on such devices. This repository distills the whole engineering effort—installation, patching, cache optimization, plugin installation, and self-update—into a reproducible open-source solution:
>
> - **Eight HarmonyOS "conversation mode" Agent presets**: push DeepSeek's prefix cache hit rate to the maximum while retaining task delivery capability—`harmony-chat` (minimal) / `harmony-chat-pro` (cache-optimized) / `harmony-chat-promax` (strongest Hexagon delivery) / `harmony-chat-ops` (resident background task steward) / `harmony-chat-rampagemax` (Rampage Max quality) / `harmony-kb` (knowledge-base expert) / `harmony-deveco` (DevEco full-stack development master) / `harmony-chat-monash` (Monash student edition)
> - **Hexagon ProMax** (upgraded 2026-08-18): six hard rules in one place—cache hit, token savings, delivery capability, test verification, integration loop, coexistence defense—turning the gap between "code written" and "system running" into a mechanical checklist, with delivery discipline benchmarked against and exceeding mainstream general-purpose Agents
> - **Rampage Max** (added 2026-08-18): an extreme mode that spends token without restraint, prioritizing quality and delivery—runtime context and web fetching fully enabled, exhaustive pre-check scanning, integration loop and double verification written as iron rules. Use with caution: high token consumption, may drain your account quota
> - **Launch patches** `harmony.patch.yml` (web) + `harmony-headless.patch.yml` (headless): disable plugin lines that depend on native binaries, so dsh no longer crashes on startup
> - **node_modules patch scripts**: work around the HarmonyOS filesystem restrictions (`chmod 600` rejected, no hard-link support) + restore the dialog permission presets (`dsh-permission-presets` reads `sandboxMode` from the fs sandbox; the read-only/workspace-write/danger-full-access dropdown is back)
> - **Measured token savings**: an A/B benchmark over 11 tasks verifies `reasoningEffort: high` as Pareto-optimal (all correct + fewest steps + nearly unchanged cost), with the promax delegation group routing complex subtasks to a Pro model as fallback
> - **Five-preset benchmark (2026-08-18)**: after static persona padding (prefix crosses the 128-token chunk boundary), the static-prefix presets' cache hit rate rose from 52.9%–89.9% to **93.8%–98.0%** (promax 96.7%, ops 97.9%, rampagemax 98.0%), and even harmony-chat with runtime context enabled was pulled up to 93.8%—data confirming that "to preserve the cache, keep the prefix stable first" (see "Performance Benchmarks" below)
> - **Toolchain**: one-click GitHub plugin installer, dsh self-updater + settings page
> - **Global prompt-antivirus `dsh-prompt-antivirus`** (added 2026-08-31): scans tool arguments / tool results / messages before they enter the model, quarantining or blocking prompt injection and "context-virus" payloads; injects a per-session canary guard and routes high-risk dangerous tools through human approval—mounted at the profile layer, active globally across all presets and subagents

- **Eight HarmonyOS "conversation mode" Agent presets**: push DeepSeek's prefix cache hit rate to the maximum while retaining task delivery capability—`harmony-chat` (minimal) / `harmony-chat-pro` (cache-optimized) / `harmony-chat-promax` (strongest Hexagon delivery) / `harmony-chat-ops` (resident background task steward) / `harmony-chat-rampagemax` (Rampage Max quality) / `harmony-kb` (knowledge-base expert) / `harmony-deveco` (DevEco full-stack development master) / `harmony-chat-monash` (Monash student edition)
- **Hexagon ProMax** (upgraded 2026-08-18): six hard rules in one place—cache hit, token savings, delivery capability, test verification, integration loop, coexistence defense—turning the gap between "code written" and "system running" into a mechanical checklist, with delivery discipline benchmarked against and exceeding mainstream general-purpose Agents
- **Rampage Max** (added 2026-08-18): an extreme mode that spends token without restraint, prioritizing quality and delivery—runtime context and web fetching fully enabled, exhaustive pre-check scanning, integration loop and double verification written as iron rules. Use with caution: high token consumption, may drain your account quota
- **HarmonyOS Dev Master `harmony-deveco`** (added 2026-08-20): a DevEco full-stack development agent—drives hvigor/ohpm/hdc through the dev_* tools to close the "write ArkTS → build → deploy to device → launch" loop (including signing/packaging guidance); `dev_code` delegates deep sub-tasks to the local DevEco Code agent (OpenCode web, 127.0.0.1:4096). Kirin X90 software-hardware-coordinated power discipline: serialized delegation, never saturating the 4 cores
- **Launch patches** `harmony.patch.yml` (web) + `harmony-headless.patch.yml` (headless): disable plugin lines that depend on native binaries, so dsh no longer crashes on startup
- **node_modules patch scripts**: work around the HarmonyOS filesystem restrictions (`chmod 600` rejected, no hard-link support) + restore the dialog permission presets (`dsh-permission-presets` reads `sandboxMode` from the fs sandbox; the read-only/workspace-write/danger-full-access dropdown is back)
- **Measured token savings**: an A/B benchmark over 11 tasks verifies `reasoningEffort: high` as Pareto-optimal (all correct + fewest steps + nearly unchanged cost), with the promax delegation group routing complex subtasks to a Pro model as fallback
- **Five-preset benchmark (2026-08-18)**: after static persona padding (prefix crosses the 128-token chunk boundary), the static-prefix presets' cache hit rate rose from 52.9%–89.9% to **93.8%–98.0%** (promax 96.7%, ops 97.9%, rampagemax 98.0%), and even harmony-chat with runtime context enabled was pulled up to 93.8%—data confirming that "to preserve the cache, keep the prefix stable first" (see "Performance Benchmarks" below)
- **Toolchain**: one-click GitHub plugin installer, dsh self-updater + settings page
- **Global prompt-antivirus `dsh-prompt-antivirus`** (added 2026-08-31): scans tool arguments / tool results / messages before they enter the model, quarantining or blocking prompt injection and "context-virus" payloads smuggled inside `[CRON TASK]` / `[SCHEDULE REMINDER]` / web-search results / file contents; injects a per-session canary guard and routes high-risk dangerous tools through human approval; `block` / `quarantine` / `monitor` modes plus local audit logging—mounted at the profile layer, active globally across all presets and subagents, pure JS with zero dependencies

---

## Why This Suite Is Needed

| HarmonyOS device limitation | Consequence | Solution in this repo |
|---|---|---|
| Cannot load native ELF / `.node` modules | `node-pty` (subprocess), `Koffi` (sandbox/fs-local) crash on startup | `harmony.patch.yml` disables these plugin lines |
| Filesystem enforces group permission bits, `chmod 600` is rejected | Credential file permission check always fails; cannot configure an API key | Patch `dsh-credentials-local`: `assertOwnerOnly` returns immediately |
| Filesystem does not support hard links | Session persistence `link()` emits `EPERM` in release logs | Patch `dsh-session-persistence-jsonl`: `link` changed to `rename` |
| No bash shell on HarmonyOS (native sandbox deps disabled) | No permission-preset dropdown in the dialog (read-only/workspace-write/danger-full-access) | Patch `dsh-permission-presets`: read `sandboxMode` from the fs sandbox (pure JS, always running) |
| HarmonyOS storage rejects hard links / some mount points refuse read-only handles | Image reading (read_image / attachment) `link()` emits `EPERM`, directory `fsync` errors; images cannot persist → the model never sees them | Patch `dsh-attachment-local`: on `link` failure publish via `copy` (EEXIST race goes through sha256 integrity check); `syncDirectory` skips fsync on EPERM/EACCES/ENOTSUP mount points |
| HarmonyOS storage rejects hard links | New-file writes in the workspace (`createIfAbsent`) `link()` emits `EPERM`, so new files cannot be created | Patch `dsh-fs-local`: verify the target is absent, then publish via `rename`, preserving create-if-absent semantics |
| `dsh-visual-plugin` (third-party) panel defaults to an unconfigured vision endpoint | `vision model is not configured`, or a custom prompt returns empty text and gets hard-thrown | Patch `dsh-visual-plugin`: when the endpoint is empty, fall back to the main DeepSeek vision model (`llm-deepseek` + `DEEPSEEK_API_KEY`); retry once on empty content and degrade to a clear message |
| `git ls-remote` is intercepted by the isogit shim | GitHub-source plugins cannot be installed | `scripts/dsh-hm-install.mjs` installer (fetch source → build → symlink) |

---

## Security Statement

Everything in this repository is plain-text / pure-JS configuration and scripts. It does **not delete, encrypt, or transmit your data, does not register system services, and does not require root**. Safe to use:

- **Pure JS / plain text**: presets are YAML config files, patches are YAML overlay layers, plugins are zero-dependency pure JS (only `node:fs/promises`), scripts are Node/Shell text. No executable binaries, native `.node`/ELF modules, kernel modifications, or drivers.
- **No system-level changes**: does not register `systemd` / autostart / system scheduled tasks, does not modify system paths, does not require root. All writes occur within the dsh installation directory and the `~/.dsh` user config directory.
- **Your data is untouched**: presets only modify dsh's "conversation mode" config; plugins only enumerate directories and read files; patches only enable/disable dsh's own plugin lines. Your files are never deleted, overwritten, encrypted, or transmitted.
- **Minimal network behavior**: only loads config when dsh starts and only accesses the official DeepSeek and GitHub APIs when you actively start a conversation or check for updates. No telemetry, no tracking, no data reporting.
- **Fully auditable**: the entire repository contains just over 20 text files; every single line can be opened and inspected.
- **Reversible uninstall**: delete `~/.dsh/.agent-presets/harmony-chat-ops/`, `~/dsh-test/node_modules/@deepseek-ai/dsh-tool-list/` and `@deepseek-ai/dsh-deveco-bridge/`, and the corresponding profile-layer symlinks, then restart dsh to fully restore.

---

## Quick Start

### 1. Install dsh

```bash
cd ~/dsh-test && npm install @deepseek-ai/dsh
```

> The install location can be overridden with the `DSH_DIR` environment variable; the default `~/dsh-test` is used below.

### 2. Deploy the presets (conversation modes)

Copy the preset directories into dsh's user preset directory:

```bash
mkdir -p ~/.dsh/.agent-presets
cp -r presets/* ~/.dsh/.agent-presets/
```

Then set the default conversation mode to one of them in `~/.dsh/settings.yaml`:

```yaml
agent-presets:
  default: harmony-chat-promax
```

All eight modes can be freely switched at any time in the "conversation mode" dropdown of dsh's settings panel (switching only affects new sessions). See [docs/CACHE-OPTIMIZATION.en.md](docs/CACHE-OPTIMIZATION.en.md) for why they are fast.

| Mode | persona | Cache strategy | Tool set |
|---|---|---|---|
| `harmony-chat` (base) | Normal | Runtime context enabled (prefix varies) | Single Agent |
| `harmony-chat-pro` (cache-optimized) | `complete:true` unique prompt section | Zero prefix change, maximum hit rate | Single Agent, planning discipline built in |
| `harmony-chat-promax` (strongest Hexagon delivery) | `complete:false` | Runtime context disabled, long stable prefix | + Subagents / workflows / Ralph delegation group + six hard delivery rules |
| `harmony-chat-ops` (task steward) | Resident background task steward | Runtime context disabled, stable prefix | + Scheduled tasks (cron_create/list/set_enabled/delete + schedule_create/list/delete) + directory enumeration (list_dir) |
| `harmony-chat-rampagemax` (Rampage Max) | No token savings, quality and delivery first | Runtime context enabled (prefix varies) + web fetching fully enabled | + Delegation group (all Pro) + exhaustive pre-check / double verification / retrospective iron rules |
| `harmony-chat-rampagemax` (Rampage Max, use with caution) | No token savings, quality and delivery first | **Runtime context enabled**, dynamic prefix, low hit rate | All promax capabilities + web fetch fully enabled + double verification/cross-checking + full-Pro delegation + exhaustive pre-check scan |
| `harmony-kb` (knowledge-base expert) | Workspace-as-knowledge-base: layered retrieval / deep research / doc organization / mind maps / notes | Runtime context disabled, stable prefix | + directory enumeration (list_dir) + Obsidian wikilink note push |
| `harmony-deveco` (Dev Master) | HarmonyOS DevEco full-stack development (write ArkTS → build → deploy → launch) | Runtime context disabled, stable prefix | + dev_environment/build/install_deps/list_devices/deploy + dev_code (delegate to local DevEco Code agent) + Kirin X90 power discipline |
| `harmony-chat-monash` (Monash student edition) | Monash all-campus study assistant: literature interpretation / plagiarism check / assignment help + student services & Melbourne transport KB | Runtime context disabled, long stable prefix (same as ProMax) | Same full tool set as promax (fs / web search / delegation / workflows) |

### 2.4 Hexagon ProMax: the ceiling of delivery capability on HarmonyOS

`harmony-chat-promax` does not trade off between "cache hit" and "delivery capability"; instead it applies six hard rules in one place—each one distilled from a real pitfall encountered in practice:

| # | Dimension | Rule | Failure mode it guards against |
|---|---|---|---|
| 1 | **Cache hit** | `includeRuntimeContext:false`; system prompt fully static, zero prefix change | Prefix varies dynamically with the session, DeepSeek's cache hit rate bottoms out (uncached input is roughly **30×** more expensive) |
| 2 | **Token savings** | Static prefix + task tiering: light tasks completed directly without a plan; only heavy tasks run the full loop | Turning even simple Q&A into plans/multiple round trips, wasting output |
| 3 | **Delivery capability** | Keep all prompt sections (planning strategy / tool guidance / delegation group), only disable runtime context | Trimming into a thin shell to preserve the cache, heavy tasks cannot be delivered |
| 4 | **Test verification** | "Before claiming done, you must run verification commands and obtain real output; no evidence equals not done" | Claiming done right after writing code, with syntax/regression fully unguarded |
| 5 | **Integration loop** | Delivery = files written + dependencies in place (node_modules symlinks) + service restarted + boot loading verified + functionality actually tested | "File correct" ≠ "system runs"; the missing steps are left undone |
| 6 | **Coexistence defense** | Scan for conflicts before starting (namespace / wiring.id / system-prompt slots / settings-page order / tool names), reuse an isomorphic already-shipped reference as a template | New plugins step on each other; shared-resource changes don't list the impact scope |

All six rules live in the static persona text of `agent.cordis.yml`, injecting no dynamic content—**the rules themselves do not break rule #1's cache hit**.

#### Comparison with other Agents

| Capability | Hexagon ProMax | Mainstream general-purpose Agent (Claude Code / Codex CLI / Cursor, etc.) |
|---|---|---|
| Cache hit rate | Static prefix preserves the cache, maximum hit rate | Runtime context varies with the session, fragile prefix, high uncached cost |
| Token cost | Cached input ≈ 1/30 the price; zero waste on light tasks | Dynamic injection per request, cache benefit greatly diminished |
| Platform awareness | Knows the HarmonyOS/dsh-specific constraints: no native ELF, `chmod 600` rejected, no hard-link support, isogit shim, native plugins crash on startup | Modeled on Linux/server assumptions; crashes or is restricted from the first step on HarmonyOS |
| Integration loop | **symlink → restart → boot verification → live test** hard-coded as a mechanical checklist | Stops at code written + tests passed; doesn't know the dsh-specific steps |
| Verification discipline | "Evidence after a change" written into the persona; verification commands and output recorded | Relies on model discretion, not enforced; prone to "should be fine" empty assertions |

**Why it crushes general-purpose Agents:** A general-purpose Agent's "done" standard is "code written + tests passed", but the "done" standard for dsh plugin delivery is "the system actually runs". The difference is exactly that whole stretch of **platform-specific finishing steps**—node_modules symlinks must be created inside the `~/.dsh` tree, restarts must use `--patch harmony.patch.yml`, boot entries must be verified as loaded, and functionality must be tested live. General-purpose Agents don't know these steps; they treat "written" as the finish line. ProMax writes this mechanical checklist into the persona, making the "finishing" an unskippable part of delivery.

**Where these rules came from:** They were not designed; they grew out of real plugin-development testing. Problems exposed while using ProMax to write the Arknights operator character plugin (dsh-arknights-persona)—zero syntax errors, all APIs correct (9/10), but the node_modules symlink wasn't created, no restart, no boot verification, no live test (integration loop only 6/10)—each became a rule in the table above. That's exactly what "strongest delivery" means: **code delivery 9/10, system running 6/10—the gap is in finishing discipline, not intelligence.**

### 2.5 Install the ops-mode dependency (only required by `harmony-chat-ops`)

The ops preset references a **custom plugin** outside dsh, `@deepseek-ai/dsh-tool-list` (directory enumeration; the dsh fs service has no readdir). It is not part of dsh's base installation and must be placed in two locations manually (source + profile-layer symlink, both required):

```bash
# ① Put the source into dsh's base node_modules (presets resolve by bare package name to this layer)
cp -r plugins/@deepseek-ai/dsh-tool-list ~/dsh-test/node_modules/@deepseek-ai/
# ② Symlink into the profile-layer dependency tree (web profile's node_modules resolves up to profiles/node_modules)
ln -s ~/dsh-test/node_modules/@deepseek-ai/dsh-tool-list ~/.dsh/profiles/node_modules/@deepseek-ai/
```

> The scheduled-task tools `schedule_create/list/delete` ship with dsh's base installation (`@deepseek-ai/dsh-schedule` is a direct dsh dependency), and `harmony.patch.yml` already mounts them via `insert`; no additional installation needed.

### 2.6 Install the harmony-deveco dependency (`dsh-deveco-bridge`)

The `harmony-deveco` dev_* tools are provided by another **custom plugin** outside dsh, `@deepseek-ai/dsh-deveco-bridge` (drives hvigor/ohpm/hdc + `dev_code` delegation; pure JS via node:child_process, no native deps). It is not part of dsh's base installation and must be placed in two locations manually (source + profile-layer symlink, both required — same as `dsh-tool-list` in 2.5):

```bash
# ① Put the source into dsh's base node_modules (presets resolve by bare package name to this layer)
cp -r plugins/@deepseek-ai/dsh-deveco-bridge ~/dsh-test/node_modules/@deepseek-ai/
# ② Symlink into the profile-layer dependency tree
ln -s ~/dsh-test/node_modules/@deepseek-ai/dsh-deveco-bridge ~/.dsh/profiles/node_modules/@deepseek-ai/
```

The preset ships with the `- id: deveco-bridge` mount row, so dev_* tools are available automatically in the `harmony-deveco` preset. To expose dev_* in other presets too, add an `insert` block to your profile patch `cordis.patch.yml`:

```yaml
- insert:
    - id: deveco-bridge
      name: '@deepseek-ai/dsh-deveco-bridge'
```

> **Tool paths**: the plugin looks in `$HOME/deveco/deveco_tools/` for node/hvigor/sdk/ohpm (DevEco Studio's default install location); point `DEVECO_TOOLS_HOME` at a custom root, or override individually with `DEVECO_NODE_HOME` / `DEVECO_HVIGOR_HOME` / `DEVECO_SDK_HOME` / `DEVECO_OHPM_BIN` / `DEVECO_HDC_BIN`.
>
> **`dev_code` delegation**: hands a self-contained deep sub-task to the local DevEco Code agent (OpenCode web, 127.0.0.1:4096) which runs its own agent loop. Start DevEco Code and configure DeepSeek first (`~/.deveco/deveco.jsonc`); override the address with `DEVECO_WEB_BASE`. Each delegation costs ~13K input tokens and runs serially — reserve it for deep sub-tasks (power discipline is baked into the preset persona).

### 3. Start dsh (with the HarmonyOS patches)

```bash
sh scripts/dsh-web.sh
# Equivalent manual startup:
# cd ~/dsh-test && node --expose-internals node_modules/@deepseek-ai/dsh/lib/bin.js \
#   --profile web --patch <this repo>/harmony.patch.yml
```

After startup, open `http://127.0.0.1:3080` in a browser.

> **`--expose-internals` is required**, otherwise `cordis-plugin-hmr` errors out; `--patch harmony.patch.yml` is required, otherwise native plugins crash. `dsh-web.sh` automatically locates the patch file in the repository by default, or it can be overridden with `PATCH_YML`.

### 3.5 Headless mode (unattended / benchmarking)

The headless tree has more native-dependency plugin lines than web (bash/pwsh/fs-search, etc.), so a second patch is needed:

```bash
cd ~/dsh-test && node --expose-internals node_modules/@deepseek-ai/dsh/lib/bin.js \
  --profile headless --patch <this repo>/harmony-headless.patch.yml "task description"
```

> ⚠ `fs-sandbox` is the pure-JS provider of the fs service and **must not be disabled** (`tool-fs` depends on it). The headless patch only disables native-dependency plugin lines.

### 3.6 Startup after reboot

HarmonyOS has no `systemd` / `cron` / `XDG autostart`. After a shutdown-then-power-on, bring dsh back up with any of the following:

**① Repository script (recommended; idempotent probe on 3080)**

```bash
sh scripts/dsh-web.sh        # skips if already running; otherwise starts and waits for the health check
```

Equivalent manual startup (no script):

```bash
cd ~/dsh-test && node --expose-internals node_modules/@deepseek-ai/dsh/lib/bin.js \
  --profile web --patch <this repo>/harmony.patch.yml
```

Then open `http://127.0.0.1:3080` in a browser.

**② Headless (unattended / benchmarking)**

```bash
cd ~/dsh-test && node --expose-internals node_modules/@deepseek-ai/dsh/lib/bin.js \
  --profile headless --patch <this repo>/harmony-headless.patch.yml "task description"
```

**③ Boot auto-restore (optional)**: enable the "Terminal" app to auto-start at boot in HarmonyOS Settings, then add a probe hook to your shell config (e.g. `~/.zshrc`) that pulls services up every time a terminal opens:

```bash
for _svc in dsh-web; do sh "$HOME/bin/$_svc.sh" >/dev/null 2>&1 & done
```

`dsh-web.sh` is idempotent: it skips if already running and starts only when down, so no manual intervention is needed after a reboot. See the "Limitations" section below for the rationale.

### 4. Apply the node_modules patches (re-apply after upgrade/reinstall)

```bash
node scripts/dsh-update.mjs patch
```

Re-applies the nine patches idempotently using content anchors (recognizes code changes in new versions). Without these nine patches:
- Can't configure a model API key (credential 660 permission check)
- Sending messages errors with `EPERM link` (session persistence)
- No permission-preset dropdown in the dialog (`dsh-permission-presets` must read `sandboxMode` from the fs sandbox)
- Image reading can't persist (attachment-local: `link`→`copy` publish + mount-point fsync tolerance)
- New-file workspace writes fail with `EPERM link` (dsh-fs-local: on `createIfAbsent`, `link` failure falls back to `rename`)
- Vision reports "model not configured" / custom prompt returns empty text (dsh-visual-plugin falls back to the main vision model + empty-content retry/degrade)
- Bare plugin names resolve from `dsh-test` and fail (`cordis-plugin-loader` needs a `v0` legacy internal-loader shape for HarmonyOS node v22.7.0, which lacks `getOrCreateModuleJob`/`getModuleJobForImport`)
- `dsh-settings` lacks the old `installSettingsSection`/`settingsNamespace` exports (restore them and delegate to `SettingsProvider.installSection` for community plugins on the old API)
- The bare address `127.0.0.1:3080` in a browser/favorite always shows 401 "authentication required" (dsh-client-connection loopback is exempt from the token and auto-mints a 30-day cookie; stale token URLs are also re-minted)

---

## Performance Benchmarks: "Hexagon" scores of the five presets (2026-08-18)

Benchmark engine = **Hexagon capability radar** (6 axes × 2 questions each = 12 auto-graded questions across math/code/logic/facts/planning/self-correction, via the opencode-go API with free cost:0) + **performance table** (DeepSeek direct API, same prefix sent 4 times in a row, measuring the 4th send's steady-state cache hit rate; prefix cache billed in 128-token chunks) + **delivery quality table** (3 process questions scored by marking hits against delivery steps, measuring how thoroughly the persona's delivery discipline is followed).

### Hexagon capability radar

| Preset | Math | Code | Logic | Facts | Planning | Self-correction | Overall |
|---|---|---|---|---|---|---|---|
| `harmony-chat` | 100 | 100 | 100 | 100 | 100 | 100 | **100** |
| `harmony-chat-pro` | 100 | 100 | 100 | 100 | 100 | 100 | **100** |
| `harmony-chat-promax` | 100 | 100 | 100 | 100 | 100 | 100 | **100** |
| `harmony-chat-ops` | 100 | 100 | 100 | 100 | 100 | 100 | **100** |
| `harmony-chat-rampagemax` | 100 | 100 | 100 | 100 | 100 | 100 | **100** |

The capability floor is identical and perfect—all five presets share the same model, so the benchmark is really comparing **performance and delivery discipline**, not capability.

### Performance table (before → after: after padding the persona with static instructions to cross the 128-token chunk boundary)

| Preset | Prefix tokens | Cache hit rate | Output efficiency (median tok/correct question) | Avg. time |
|---|---|---|---|---|
| `harmony-chat` | 273 | 52.9% → **93.8%** | 70 | 130s |
| `harmony-chat-pro` | 406 | 71.3% → **94.6%** | 73 | 98s |
| `harmony-chat-promax` | 794 | 87.2% → **96.7%** | 104 | **71s** |
| `harmony-chat-ops` | 523 | 97.9% → 97.9% | 155 | 99s |
| `harmony-chat-rampagemax` | 914 | 89.9% → **98.0%** | 125 | 142s |

### Delivery quality (delivery-spec adherence)

| Preset | Integration loop W1 | Verify before claiming done W2 | Retrospective & wrap-up W3 | Overall |
|---|---|---|---|---|
| `harmony-chat` | 75 | 75 | 67 | **72** |
| `harmony-chat-pro` | 25 | 50 | 67 | **47** |
| `harmony-chat-promax` | **100** | **100** | 67 | **89** |
| `harmony-chat-ops` | 25 | 50 | 33 | **36** |
| `harmony-chat-rampagemax` | **100** | 75 | **100** | **92** |

**Conclusions**

- **ProMax = the Hexagon all-rounder**: full marks across all six capability axes, performance maxed out—cache 96.7% in the top tier, output efficiency 104 tok (most economical among fully-featured presets), average time 71s the fastest of all, delivery-spec score 89 second only to Rampage Max. **Performance and delivery discipline in one.**
- **Rampage Max = the ceiling of delivery quality**: delivery-spec score **92, the highest of all**, integration loop 100 + retrospective & wrap-up 100 (the only full marks)—verification/retrospective/loop carried through most thoroughly; cache 98.0% also the highest, but efficiency 125 tok and time 142s the longest, as intended by the "no token savings, quality first" design.
- **Minimal harmony-chat is the most output-frugal**: efficiency 70 tok the lowest of all, but no delivery-discipline clauses, delivery 72; pro is the next most frugal at 73 tok, but delivery discipline is weak (47).
- **Cache optimization is immediately effective**: padding static persona instructions pushes the prefix across the 128-token chunk boundary (remainder ≤15), raising the hit rate from 52.9-89.9% to 93.8-98.0%—cached input is roughly **30×** cheaper than uncached, so prefix stability is the biggest lever.
- For runtime-context presets (harmony-chat / rampagemax), real-session prefixes vary with snapshots; this is the ideal static baseline, so actual hit rates are slightly lower.

Raw data `bench/result.json`, report `bench/result.md`; the benchmark script `bench/bench.mjs` is reproducible.

---

## Toolchain

| Script | Purpose |
|---|---|
| `scripts/dsh-web.sh` | Start/restart the dsh Web service (3080, idempotent liveness probe) |
| `scripts/dsh-update.mjs` | dsh update checks: `check` / `patch` / `install` / `rollback`; re-applies patches automatically after an upgrade |
| `scripts/dsh-manual-install.mjs` | Manual installer: recursively resolves the full dependency graph from registry metadata and installs tarballs directly (bypasses npm arborist resolution hang); `install()`/`rollback()` call it automatically, npm as fallback |
| `scripts/dsh-update-web.sh` | Settings and update page (3098, embedded HTML) |
| `scripts/dsh-hm-install.mjs` | One-click install of GitHub-source plugins (bypasses isogit interception) |
| `scripts/node-runtime.sh` | Shared runtime resolver (sourced by every launcher): probes all local node builds and picks the highest one that actually boots |
| `scripts/dsh-runtime-check.mjs` | Runtime-selection regression (24 checks, every branch exercised with fake node binaries) |

**Node version: not pinned — use the newest one that runs (latest line = Node 26.10.0, active LTS = 24.21.0).** Upstream dsh targets node ≥ 22.18 (this repo's `compat-loader`
drops that floor to the v22.7 that ships with HarmonyOS tooling), while the HarmonyOS-bundled hnp node is **v24.13**. But on some HarmonyOS devices/channels that very v24 build dies natively during V8 init
(code-range reservation `mmap` fails → `Fatal error in , line 0` / `Check failed: 12 == (*__errno_location())`,
with no upstream switch to disable it), whereas deveco's v22.7 is stable. So no script hardcodes a path any more:

1. enumerate every node it can find (`/data/service/hnp/node.org/node_*/bin/node`, `~/deveco/deveco_tools/node/bin/node`, whatever is on `PATH`, common install dirs) —
   the hnp entries are matched by `node_*` directory, so **an hnp upgrade to Node 26 is picked up with no script change**;
2. smoke-test each one **highest version first** with `-e 'process.exit(0)'` (the crash is flaky, so it gets 3 tries);
3. take the first that really boots — **26 if the machine has it, then 24, then 22**; neither machine has to change a command;
4. derive flags (`--expose-internals` / `--experimental-sqlite` / `compat-loader`) from **runtime capability probing**, never passing a flag the runtime would reject (v24 has native `node:sqlite` and native zstd, so no shim flags).

- Just see which one wins and with which flags: `sh scripts/dsh-web.sh --print-node` (also supported by `dsh-update.sh` / `dsh-hm-update.sh` / `dsh-update-web.sh`; probe only, starts nothing, touches no running service)
- Pin explicitly: `NODE_BIN=/path/to/node` (or `DSH_NODE_BIN`; tried first, still falls back if it cannot boot) or `DSH_NODE_CANDIDATES=a:b` (only those)
- Regression: `node scripts/dsh-runtime-check.mjs`

---

## HarmonyOS adaptation details

### What the installer does (`dsh-hm-install.mjs`)

When you click a GitHub-source plugin in the market (intercepted via the `process.platform === 'openharmony'` branch):
1. `fetch` the source `tar.gz` and recursively scan for plugin directories carrying a dsh manifest
2. Install directly if precompiled artifacts exist; otherwise **attempt an in-place build** (`--ignore-scripts` as a fallback for native postinstall)
3. Strip the missing `dsh.client` frontend artifacts (prevents `MissingClientBundleError` from crashing startup), installing server-only
4. Symlink into the `~/.dsh/profiles/web` dependency tree, write the manifest, and take effect after a restart

> ⚠ **link plugins must live inside the `~/.dsh` tree**: put the source in `plugins-src/<name>` and write `link:/storage/Users/currentUser/.dsh/profiles/web/plugins-src/<name>` in `package.json`; otherwise the `@deepseek-ai/*` symlinks won't resolve.

### Which plugins can be installed

Only plugins depending on **pure JS / `node:sqlite`** are selected. Native dependencies (koffi/pty/esbuild/WASM runtimes) cannot run on HarmonyOS.

---

## Limitations

- No `systemd` / `cron` / `XDG autostart`; HarmonyOS has no autostart system service. For autostart, set the "Terminal" App to launch on boot in HarmonyOS settings plus a shell liveness hook to pull the service up
- `bash`/terminal execution and the sandbox are disabled; the Agent cannot actually run shell commands, and can only work through file editing / web search / Skills / planning / delegation
- Cannot switch back to the official `standard` / `code` / `minimal` presets (they depend on disabled native capabilities and will report `agent-preset-invalid`)
- Pure-UI client plugins become empty shells; WASM-runtime dependencies only crash when invoked
- Sidebar terminal **awaits upstream support**: the 0.1.6 host `dsh-api-terminal-controller` and client `ui-sidebar-terminal` both depend on the `subprocess` service (`@deepseek-ai/dsh-subprocess-local`), which statically imports `node-pty` (pty allocation) and `koffi` (FFI execve) at the top level — HarmonyOS blocks dlopen of untrusted ELF and ships no openharmony-arm64 prebuild, so loading fails with `Cannot find the native Koffi module`; `harmony.patch.yml` disables those rows explicitly (host and client together). Re-enable once upstream offers a pure-JS/standalone pty or HarmonyOS permits native modules
- The HarmonyOS desktop shell **does not install updates in-app**: official desktop updates are Electron artifacts (win-x64/mac-arm64) that HarmonyOS cannot install; the update check in `client/` only reports "upstream published a new version" and points to the download page
- The HarmonyOS desktop shell **cannot inject editor keys**: upstream Windows dispatches `Ctrl+Z/Ctrl+C…` as physical keys via `sendEditingKey()`; ArkTS text components own their edit history and expose no handle, so the Edit menu keeps its entries and tells you to use the system shortcut
- The HarmonyOS desktop shell **has no tray**: upstream "close = go to tray, click tray to return" maps to "confirm before close + minimize", so Hide / Hide Others / Show All all minimize the window
- **Prebuilt HAP**: the unsigned release HAP built from this source tree is attached to GitHub Releases ([`v1.0.0-pc`](https://github.com/QinpanWan/dsh-harmonyos-pc/releases/tag/v1.0.0-pc), asset `dsh-pc-1.0.0-unsigned.hap`) — grab it there and **sign it yourself before sideloading** (`client/build-profile.json5` has an empty `signingConfigs`, so the package carries no `META-INF/` and will not install unsigned)

### Installing locally: unsigned HAP → real device

An unsigned HAP (no `META-INF/` inside) fails `hdc install` with **`error: no signature file`**, so it must be signed first:

- **With DevEco Studio and a signed-in Huawei account**: open `client/` → `File > Project Structure > Signing Configs` → tick automatic signing → `Run` (or `Build > Build Hap(s)`), then `hdc install <signed.hap>`. Easiest, recommended.
- **Signing from the CLI (the path exercised on this machine)**: the SDK ships `hap-sign-tool.jar` (`$DEVECO_SDK_HOME/default/openharmony/toolchains/lib/hap-sign-tool.jar`); pair it with a **debug certificate** (a `.p12` keystore, a `.cer` certificate and a `.p7b` profile whose `debug-info.device-ids` lists the target UDID, see `hdc shell bm get --udid`):

  ```bash
  java -jar "$SDK/default/openharmony/toolchains/lib/hap-sign-tool.jar" sign-app \
    -mode localSign -keyAlias <alias> -signAlg SHA256withECDSA \
    -appCertFile <cert.cer> -profileFile <profile.p7b> -keystoreFile <key.p12> \
    -keyPwd <pass> -keystorePwd <pass> \
    -inFile entry-default-unsigned.hap -outFile entry-default-signed.hap
  hdc install -r entry-default-signed.hap
  ```

  Where to get them: DevEco's automatic signing drops them into `~/.ohos/config/` (`*.p12` + `*.p7b`). **Somebody else's certificate will not install on your device** (UDID allow-list plus the certificate chain) — use your own.

> **When the device *is* this machine**: `hdc list targets` simply lists `127.0.0.1:32905`, so `hdc shell "aa start -b com.dsh.harmonyos.client -a EntryAbility"` raises the window and `hdc shell "snapshot_display -f /data/local/tmp/s.jpeg"` + `hdc file recv` captures it — no second machine needed.

---

## License and acknowledgments

MIT License, see [LICENSE](LICENSE).

This project does not include dsh source code; it only contains independently written configuration, patch scripts, and documentation. dsh itself is released by [DeepSeek](https://github.com/deepseek-ai/dsh) under the MIT license; this repository's references to it and its patches follow the MIT terms, and we hereby acknowledge it.

One exception: `desktop-upstream/` is a **source snapshot** of the official desktop app (`apps/desktop` + `apps/desktop-host`), also MIT (Copyright (c) 2026 DeepSeek), kept for offline reading and porting reference only; it does not take part in any build. Provenance and refresh steps are in `desktop-upstream/README.md`.

---

## Changelog

### 2026-09-26 (follow-up) — node support statement aligned with the latest line: Node 26.10.0 / LTS 24.21.0, still not pinned

- **Why another pass**: the previous round made the runtime adaptive (highest bootable wins), but the public statement still only reached 24
  (badge `Node.js 22–24`, docs "latest line v24"). Per node's official dist index, the **latest line is Node 26.10.0** (released 2026-09-21, Current)
  and the **active LTS is 24.21.0** (Krypton, 2026-09-07). The repo now says: **not pinned — ≥22.18 is upstream's floor, and the ceiling follows the
  highest build that actually boots on the machine (26 → 24 → 22)**.
- **Changes**: badges `Node.js 22–24` → `22–26` in both READMEs; the "toolchain" section (both READMEs) and the beginner tutorial prerequisites now carry
  the concrete latest/LTS numbers and the 26-first fallback order; `scripts/node-runtime.sh` header comment updated (no more "currently Node 24").
- **Last hardcoded version removed**: `scripts/dsh-hm-install.mjs` still pinned hnp `node_v24.13.0` in its npm/hdc fallback list; it now globs
  `/data/service/hnp/node.org/node_*/bin/` and takes the **highest version**, so an hnp upgrade to 26 needs no code change.
- **Regression**: `node scripts/dsh-runtime-check.mjs` **22 → 24 checks** (adds "no script hardcodes an hnp version `node_v<digits>`" and "hm-install globs hnp versions");
  `desktop-shell-check.mjs` 33/33, `direct-mode-check.mjs` 47/47, `session-live-check.mjs` 58/58, `gen-harmony-ui-assets.mjs --check` 5/5 unchanged.
- **Honest scope**: this machine only has hnp v24.13 (dies in V8 init) and deveco v22.7 (stable), and the official `nodejs.org` `linux-arm64` binaries cannot even
  execute on HarmonyOS (`permission denied` — different ABI/loader). So "26 works" is derived from the script's behaviour (descending version order, boot smoke
  test, capability-probed flags; `--experimental-loader` is still in the Node 26 man page), not measured here. Once a HarmonyOS build of Node 26 exists
  (hnp or DevEco), that becomes the real test.

### 2026-09-26 — Node version no longer pinned to 22: use 24 when it boots, fall back to 22 when it does not (all four launchers)

- **Problem**: the scheme hardcoded node paths (`dsh-update.sh` / `dsh-hm-update.sh` / `dsh-update-web.sh` / `dsh-hm-update.mjs` pinned hnp `node_v24.13.0`,
  `dsh-web.sh` pinned deveco v22.7), so whichever build happened to be broken on that machine became the ceiling — and the badge still claimed `Node.js 22+`.
- **Fix**: new shared `scripts/node-runtime.sh` (the probing logic lifted out of `dsh-web.sh`): enumerate candidates → smoke-test them highest-version-first with
  `-e 'process.exit(0)'` (the crash is flaky, so 3 tries) → take the first that really boots; flags (`--expose-internals` / `--experimental-sqlite` / `compat-loader`)
  come from runtime capability probing, never passing a flag the runtime would reject. All four launchers now use it, and every one supports `--print-node`
  (probe only — starts nothing, touches no running service).
- **Also**: `dsh-hm-update.mjs` now spawns `process.execPath` (follows the node you are already running) and `dsh-hm-install.mjs` looks for npm/`hdc` in the current node's `bin/` first.
- **Regression**: `node scripts/dsh-runtime-check.mjs` **12 → 22 checks** (adds "no launcher hardcodes a path", "the three update scripts also pick the highest bootable version via `--print-node`", "the .mjs files follow `process.execPath`");
  `desktop-shell-check.mjs` 33/33, `direct-mode-check.mjs` 47/47, `session-live-check.mjs` 58/58, `gen-harmony-ui-assets.mjs --check` 5/5.
- **On this machine**: the HarmonyOS-bundled hnp `node_v24.13.0` dies natively during V8 init (`Check failed: 12 == (*__errno_location())`; `--jitless` runs but means no JIT and no WASM),
  so probing settles on deveco v22.7 + `--experimental-sqlite` + compat-loader — i.e. on the "use 24 when it works" path this box is simply the case where 24 does not, with no command changes.

### 2026-09-26 — HarmonyOS desktop HAP published to Releases: grab `v1.0.0-pc` and sideload it yourself

The desktop no longer lives only in a local `client/dist/`. This change lands the whole "take the official Electron shell apart → rewrite the shell natively in ArkTS" round on `main` (`client/` shell and UI rewrites, `docs/DESKTOP-SHELL-UPSTREAM.md`, `docs/HARMONY-DESKTOP-PORT.md`, the `scripts/gen-harmony-ui-assets.mjs` / `gen-client-presets.mjs` / `desktop-shell-check.mjs` / `svg-preview.py` toolchain, and the `desktop-upstream/` source snapshot) and publishes the unsigned HAP built from that exact source on **GitHub Releases**:

- **Download**: [Releases › `v1.0.0-pc`](https://github.com/QinpanWan/dsh-harmonyos-pc/releases/tag/v1.0.0-pc) → asset **`dsh-pc-1.0.0-unsigned.hap`** (tag naming follows the tablet releases `v1.0.0-pad` / `v2.0.0-pad`)
- **Size / checksum**: **742,569 B** (`ets/modules.abc` **687,544 B**), sha256 `4a982689f659f8c907e4cb7fc81b455d39d649f7e3a44b3408d9566e4f5605e3` — byte-identical to the local copies in `client/dist/` and `~/Download/`
- **Unsigned — you sign it before installing**: `client/build-profile.json5` has an empty `signingConfigs`, and the package contains no `META-INF/` (no certificate, no profile). Two ways to sideload:
  - Open `client/` in DevEco Studio → sign in with a Huawei account → `File > Project Structure > Signing Configs` → tick automatic signing → `Run` (or `Build > Build Hap(s)` and then `hdc install <hap>`)
  - Or sign with your own debug certificate via `hapsigntool`, then `hdc install <hap>`
- **Turnkey**: the client defaults to **standalone mode** — the 8 conversation modes and their system prompts ship inside the package (`resources/rawfile/presets.json`), so a DeepSeek API key is all you need and **no local dsh service is required**; switch to "dsh service mode" in Settings to talk to a local/LAN instance
- **Still unverified on a real device**: `hdc list targets` was empty at packaging time, so the UI/interaction has not been exercised on hardware; the four known limitations (update check finds but never installs, Edit menu does not inject keys, no tray, `restartAppHost` asks you to restart from a terminal) are listed under Limitations above

### 2026-09-26 (seventh round) — standalone mode never minted a sidebar row: the session id carried over from dsh service mode

The owner reported "after sending a message no new session appears on the left — this one is in standalone mode". Reproduced on the device (this machine *is* the HarmonyOS PC): **click "new session" (or select an empty session) in dsh service mode first, then switch back to standalone mode and send** — transcript, reasoning and the reply all stream in fine, but the sidebar keeps saying "no sessions yet".

- **Root cause**: `Index.sendDirect()` decided whether to mint a local conversation with `currentSessionId.length === 0`. Coming back from dsh service mode, `currentSessionId` still holds the *server* session id — non-empty, yet absent from `directConversations` — so `beginDirectConversation()` was skipped and the sidebar projection (`publishDirectSessions()`) stayed empty. The test has to be "is this id in the local conversation list": `if (this.findDirectConversation(this.currentSessionId) === null) { this.beginDirectConversation(text); }`.
- **Same family, second spot**: `adoptDirectConversation()` returned early when `messages.length === 0`, leaving that dangling server id in place — same missed row. It now drops an id that is not a local conversation (and resets the title to "new session" when the transcript is empty too).
- **Third spot — mode isolation**: streams opened in the other mode stay alive across a switch. A late `session/list` response replaced the sidebar projection with the server's few hundred sessions, a `follow` snapshot overwrote the standalone transcript, and `$events`' `api-session/added` inserted server rows. Each of `refreshSessions()`'s then-callback, `onFollowValue()` and `onHostEvent()` now starts with `if (this.mode !== 'dsh')` (dsh service mode behaviour unchanged).

**Verified on the device (18:12–18:18, `uitest dumpLayout`)**:

- **Repro (pre-fix)**: in dsh service mode select an empty session (non-empty `currentSessionId`, empty transcript) → switch back to standalone → send "测试乙" → reply arrives, sidebar still "no sessions yet".
- **Same path after the fix**: the title bar resets to "new session" on switching back; sending "回归乙" puts "回归乙 18:16" on top of the sidebar instantly, with the previous "回归甲 18:15" still below.
- **Regression**: a cold start in standalone mode plus "回归甲" still produces its row.
- **Isolation**: creating dsh activity from the command line while the app sat in standalone mode (a parallel `$events` probe received the `api-session/added` frame) left the app sidebar untouched; repeating it after switching back to dsh service mode still made both "new session 18:17" rows appear live.
- **Regression guard**: `direct-mode-check.mjs` **41 → 47 checks**; `session-live-check.mjs` 58/58, `desktop-shell-check.mjs` 33/33, `gen-harmony-ui-assets.mjs --check` 5/5 (181 tokens · 94 glyphs).
- **Artifact**: release unsigned HAP **769,014 B** (`ets/modules.abc` **713,988 B**), sha256 `af4a1f45b6c8f4bd35e39fbc9dad59bcfabb2d4fc511ca46c9610caef8fba3bd`, refreshed into `client/dist/` and `~/Download/`.

### 2026-09-26 (sixth round) — the live sidebar actually working on hardware: the `$events` handshake was missing `supportOriginPort` (403), and sidebar rows never repainted

The "new sessions show up in the sidebar live" work from the fourth round had **never once taken effect on real hardware**. Since the fifth round established that **this machine *is* the HarmonyOS PC** (`hdc list targets` = `127.0.0.1:32905`), this round debugged it on the device against the local dsh service (`127.0.0.1:3080`) and found two device-only bugs:

- **① The WebSocket handshake's `Origin` was missing its port, so dsh's Host/Origin fence answered 403 and `$events` never connected.** ArkTS `@ohos.web.webSocket` derives `Origin` from `address` by default — host only, no port — while the dsh gateway requires the Origin authority to match the Host exactly, port included: `Origin: http://127.0.0.1` vs `Host: 127.0.0.1:3080` fails the comparison, so the event stream died at the door. Every `api-session/added` / `removed` / `status` / `activity` branch added in the fourth round was therefore **never fed a single event**, leaving the sidebar with nothing but "wait for the next full `session/list`" — exactly the reported "the sidebar does not refresh with the newest session". Fix in `openHostEvents()` (`service/DshApiClient.ets`): `const options: webSocket.WebSocketRequestOptions = { header: header, supportOriginPort: true }` (the switch available since API 26; with it the `Origin` carries `host:port`). It was pinned down with three throwaway probes — `mux-events-probe.mjs` / `mux-origin-probe.mjs` / `ws-probe-server.mjs`: first a local fake gateway echoed the handshake headers to expose the portless `Origin`, then the real dsh reproduced the 403.
- **② Sidebar rows changed content while their key stayed the same, so ArkUI reused the old row.** The `ForEach` key in `view/Sidebar.ets` was just `sessionId`. The fifth round had already hit this exact trap on message bubbles (`ForEach` compares keys only), and the sidebar is the second case of the same disease: a new session **does** get inserted (the array changed, so the key is new), but when the title arrives from `session/title`, when the running dot lights up, when the timestamp moves forward or when the selection changes, **the key does not change** — ArkUI reuses the row as-is. The symptom is "the row is there, but its title/time/dot never follow". Fix: fold `sessionId | title | updatedAt | running | is-currently-selected` into the row key (one event rebuilds one row, which is cheap).

**Verified on the device (17:49–17:52, screenshots and `uitest dumpLayout`)**:

- **A session created elsewhere appears instantly**: `POST /api/session/create` from the command line (cwd = `BrewDiary-New`) → the row showed up at the top of the sidebar within ~2 seconds, without touching the app.
- **Title and time refresh live**: `POST /api/session/prompt` against that fresh session → the row's title became "从1数到3", its time became 17:50, it moved to the top, and the tab label followed.
- **Reasoning scrolls live and the view follows to the bottom**: while that turn was running, the "think" disclosure row grew as the stream arrived and the transcript auto-followed.
- **"Back to bottom" button**: `uitest uiInput fling` to scroll the transcript up → the 34 vp circle appeared at the bottom right (px `[2451,1575][2516,1640]`); clicking it returned to the bottom and the button disappeared.
- **The app's own send path**: typing into the composer with `uitest uiInput inputText` and clicking send produced the user bubble, the thinking row and the reply (17:52, "收到，主人～有事随时吩咐，我在。"), with the sidebar timestamp following to 17:52.

- **Regression guard**: `session-live-check.mjs` grew from **50 to 58 checks** (the handshake must carry `supportOriginPort`; standalone mode's local session list; sending a first message creates the session in place; "new session" files the current turn away before opening an empty one; the row key must include title / time / running bit / selection). Others: `desktop-shell-check.mjs` **33/33**, `direct-mode-check.mjs` **41 checks** (up from 32), `gen-harmony-ui-assets.mjs --check` 5/5 (181 tokens · 94 glyphs).
- **Artifact**: release unsigned HAP **768,766 B** (`ets/modules.abc` **713,740 B**; `supportOriginPort` / `$events` / `api-session/added` / `blocksToReasoning` / "back to bottom" all findable inside), sha256 `dca83051433c63319f12ac783988bfc872affae6368cd2366849f3f0f57db9fd`, refreshed in `client/dist/` and `~/Download/` (byte-identical to `entry/build/.../entry-default-unsigned.hap`).
- **How to install (the device is this machine)**: `sh ~/bin/hm-sign-install.sh <unsigned.hap>` (signs locally with `xiaobai.p12` + `xiaobai-debug.cer` + `com_dsh_harmonyos_client.p7b` from `~/Download/com.xiaobai.hap_installer/hap_installer/store/`) → `hdc install -r` → `hdc shell "aa start -b com.dsh.harmonyos.client -a EntryAbility"` → `hdc shell snapshot_display -f …` to grab screenshots directly.
- **Still unverified**: this live pipeline in **standalone mode** (direct to `api.deepseek.com`) — what was exercised this round is **dsh service mode**.

### 2026-09-26 (fifth round) — first run on a real device (this machine *is* the HarmonyOS PC): streaming text never repainted, and standalone-mode reasoning was dropped entirely

The report was "still nothing happens, the reasoning chain does not scroll", with the hint that **this is installed on this very machine** (`hdc list targets` returns `127.0.0.1:32905`, i.e. the HarmonyOS PC is the host itself, so `aa start` raises the client and `snapshot_display` captures it directly). This round finally installed the previous round's work onto the device — and two device-only bugs surfaced:

- **① Not a single streamed delta repainted (the real body of "I sent it and nothing happened")**: the `ForEach` key over the message body in `view/MessageItem.ets` used to be just `message id - index`. **ArkUI's `ForEach` compares keys only** — an unchanged key means "same item", so nothing is redrawn. An assistant bubble is created empty and then appended to delta by delta, so with a static key the bubble stayed **empty forever** (with `reasoning` non-empty the words "thinking" above it at least proved it was alive, which is why it read as "stuck" rather than "dead"). Fix: fold the content into the key — `blockKey()` = `message id - index - t|c - text length` (`isCode` and the text length both participate), so every delta produces a new key and the body repaints.
- **② Standalone mode (built-in direct connection) dropped the whole chain of thought**: standalone mode talks to the official `/chat/completions` **streaming SSE**, and reasoning models (`deepseek-v4-flash` / `*-reasoner`) put the chain of thought in `choices[0].delta.reasoning_content`, while the standalone parser only understood `delta.content`. The UI therefore showed a single "thinking" line for the entire reasoning phase and never grew a character — precisely "the reasoning chain does not scroll". Fix (`service/DshApiClient.ets`): field extraction became `frameField(frame, field)`, on top of which `frameText` / `frameReasoning` (= `delta.content` / `delta.reasoning_content`), `streamText` / `streamReasoning` and `completionText` / `completionReasoning` are derived; `Index.ets` writes reasoning deltas into the assistant message's `reasoning`, so the reasoning disclosure row added last round now has live content in standalone mode too.
- **③ App logs moved to the public domain so they are visible on the device**: `DOMAIN` in `EntryAbility.ets` went from `0x0000` to **`0xD0042`** — `0x00000–0x0FFFF` is the system-private range, which a plain `hdc shell hilog` cannot read. The first half of this round was wasted on that trap (12,743 lines of hilog captured, not one app line in it); now `hdc shell hilog -T DshDirect` shows the direct-mode first-chunk / completion-size / timing / failure reason.
- **Verified on the device (02:43, screenshots)**: with a diagnostic probe build the standalone mode auto-sent "say hello"; the screen showed ① the user bubble, ② the **reasoning row** (icon + "think" + a one-line summary trailing the model's reasoning) and ③ the answer "你好！有什么需要帮忙的？" — both bugs gone at once. The probe was then removed, the package rebuilt clean, re-signed and reinstalled (02:44); the app starts normally from it (process and window alive).
- **Regression guard**: `direct-mode-check.mjs` grew from 32 to **41 checks** — it now lifts `frameField / frameReasoning / streamReasoning / completionField / completionReasoning` out of the `.ets` alongside the rest, plus six reasoning cases (per-frame CoT, CoT frames not polluting the body, a whole stream with a trailing partial frame, empty CoT for non-reasoning models, keep-alive frames, plain-JSON CoT fallback). The others: `desktop-shell-check.mjs` **33/33**, `session-live-check.mjs` **50/50**, `gen-harmony-ui-assets.mjs --check` 5/5 (181 tokens · 94 glyphs).
- **Artifact**: release unsigned HAP **763,994 B** (`ets/modules.abc` **708,968 B**; `reasoning_content` / `frameReasoning` / `blocksToReasoning` / "thinking" / "back to bottom" / `api-session/added` all findable inside), sha256 `a3369d3371673b769b19cf4e94d4a55cb6272f4500983f2a855a6134b8a00908`, refreshed in `client/dist/` and `~/Download/`. The build installed on the device is exactly this one (signed with `hap-sign-tool` and a local debug certificate, then `hdc install` — see the Chinese README's "local install" section).
- **Not yet verified on a device**: only standalone mode was exercised (with screenshots). The `dsh` service-mode sidebar/reasoning path shares the same code but has not had a "does a session created elsewhere appear instantly" A/B check yet.

### 2026-09-26 (fourth round) — the sidebar now shows new sessions live, and the reasoning chain is rendered and followed

The report was "the desktop still has problems: no live display and no scrolling reasoning chain, and the left sidebar does not refresh in the latest sessions in real time". Both parts were real bugs, one root cause each.

- **Sidebar: subscribe to the host's live event stream `$events`** (the authoritative source for the session list). The host's `dsh-api-session-controller` maps `session/created|session/disposed|agent/status|session/event` onto `ctx.emit('api-session/added'|'removed'|'status'|'activity')`, and `API_REMOTE_FORWARDED_EVENTS` in `dsh-api-remotes` whitelists those onto the gateway's built-in logical stream — the very same route the official web client uses through `ctx.remote.$on`. Downstream frames look like `{"type":"item","streamId":…,"value":{"type":"ready",…}}` (source ready) and `{"type":"emit","event":"api-session/added","args":[summary]}` (payload). The new `DshApiClient.openHostEvents()` opens one `$events` stream (the payload must carry an **empty** `args: {}`, the gateway validates it), and `Index.onHostEvent()` patches the list in place: `added` → `upsertSession()` (a new session — even one created elsewhere — lands at the top **immediately**), `removed` → `removeSession()`, `status` → `markSessionRunning()` (the little running dot on the row), `activity` → `touchSession()` (bumps the row by `updatedAt`). The old code only refreshed on `turn/end` / `session/title`, so **a session created elsewhere had to wait for the next full reload to appear** — exactly the reported symptom.
- **Never refetch the whole table per event**: `session/list` measures 286 rows / ~188KB / ~1s. The event payload is the same shape as a `session/list` row, so the client reuses one `parseSessionSummary()` and patches the local list; only when the row is **not found locally** does it fall back to a debounced full reload (200/800 ms), behind a `sessionRefreshInFlight` concurrency gate (one in flight at a time; anything arriving mid-flight is parked and redeemed 200 ms after it lands).
- **Both sources of the reasoning chain (CoT) are understood**: ① the live `assistant-stream` frames (`block-start{blockType:'reasoning'|'text'}`, `reasoning-delta{index,text}`, `text-delta`, `block-end`, `usage`, `finish` → `end{outcome.kind:'committed'}`; a real answer measured ~200 frames), and ② the persisted `assistant/message` → `data.message.content[]` entries of the form `{"type":"reasoning","text":…}` — the only copy available in a snapshot when you switch sessions or reconnect. The old `blocksToText()` recognised **only** `text` blocks, so the reasoning chain was dropped the moment you switched sessions, and `MessageItem` merely printed the words "thinking" when there was reasoning and no text — it never rendered the reasoning itself. There is now a `blocksToReasoning()`, the `assistant/message` branch fills `msg.reasoning` (and takes over the streaming bubble), and `applyAssistantFrame` handles multiple `block-start` segments (from the second one on it joins with `\n\n`, and **a lone `block-start` no longer creates an empty bubble**).
- **Reasoning disclosure row** (`reasoningRow()` in `view/MessageItem.ets`, matching the upstream `ReasoningRow` in `ui-chat`): `IconThinkOutline` + a title ("thinking" while streaming / "think" once finished) + **a one-line live summary** + an expand/collapse chevron, with a click on the title revealing the full chain of thought. The summary follows the same trade-off as upstream: while streaming it shows the **last** line (it trails the model's reasoning, which is what makes it feel live), and once finished the **first** line; `**` markers are stripped and the line is capped at 160 characters. Upstream's folding and hover-pinning were deliberately **not** ported this round (the simplification is documented in a code comment).
- **Follow-along scrolling plus a "back to bottom" button**: `scrollToBottom(force)` gained a `followBottom` gate, so once the reader scrolls up they are no longer yanked back down; sending a message or switching sessions re-arms it with `force = true`. `ChatView` reports whether the list is at the bottom from `onDidScroll` via **`Scroller.isAtEnd()`** (comparing indices misreads the growing streaming content as "the reader scrolled up"), and a 34 vp circular "back to bottom" button appears once you are not at the bottom (upstream's `.toBottom` slot, `aria-label` included as `accessibilityText`).
- **Regression guard**: new `scripts/session-live-check.mjs` (**50 checks**) = static contract plus the *real* functions lifted out of the `.ets` files and run under `node --experimental-strip-types` against **fixtures captured from the live dsh service** (reasoning-delta / block-start frame sequences, the reasoning blocks of an `assistant/message`, `session/list` summary rows, activity / status events). `desktop-shell-check.mjs` **33/33**, `direct-mode-check.mjs` **32/32**, `gen-harmony-ui-assets.mjs --check` clean (181 tokens · 94 glyphs).
- **Artifact**: release unsigned HAP **761,969 B** (`ets/modules.abc` **706,944 B**; `$events` / `api-session/added` / `blocksToReasoning` are all findable inside the package), sha256 `4d8c1f41796269eaeee58bacea6c8cb3dd008c946d2cc1f7c9433e6f80de34d7`, refreshed in `client/dist/` and `~/Download/`.
- **Still unverified on a real device at the time of that round**: `hdc list targets` was empty then, so this round rests on upstream source cross-reading plus a real-service fixture suite rather than a device screenshot. Once installed, check three things: does a session created elsewhere appear in the sidebar within a second, does the thinking row scroll live, and does the "back to bottom" button show up after you scroll up.

### 2026-09-26 (third round) — standalone mode never replies: `@ohos.net.http` only emits `dataReceive`/`dataEnd` for *streaming* requests

The report was "the desktop's turnkey (standalone) mode sends a message and nothing comes back — I see no reaction from the agent at all, and it is the same after I configured the key". It is **not the key, not the model name, not the network** (verified live against the official API with the local real key: `/v1/models` → 200, and `deepseek-v4-flash` / `deepseek-flash` / `deepseek-v4-pro` / `deepseek-chat` / `deepseek-reasoner` all → 200). It is the **wrong HTTP API**:

- **Root cause (read straight out of the netstack source)**: ArkTS `@ohos.net.http` only dispatches `dataReceive` / `dataEnd` for streaming requests. In `communication_netstack`, both `HttpExec::OnWritingMemoryBody` and `ProcessResponseBodyAndEmitEvents` gate the `SetTempData` + `OnDataReceive` delivery on `context->IsRequestInStream()`, and `ON_DATA_END` is emitted *only* from `AsyncWorkRequestInStreamCallback` (`http_exec.cpp`); `EnableRequestInStream()` is called by exactly one place — `requestInStream` in `http_module.cpp`. So the old code posting SSE with `req.request(...)` got **HTTP 200 with the whole answer sitting in `resp.result` while not a single byte ever reached the callbacks** — and since only non-200 responses were treated as errors, the UI showed neither text nor an error: exactly the "sent it, no reaction" report.
- **Fix**: `DeepSeekClient.chat()` in `service/DshApiClient.ets` now uses `requestInStream` (the promise resolves with the response code; the body arrives only through events). Teardown is a single `settle(err, flush)` guarded by a `finished` latch; **non-2xx errors are reported with the raw text we accumulate ourselves** (streaming mode has no `resp.result`); **HTTP 200 with zero data chunks now reports "the server returned no content"** (turning the silent fake-success into a visible failure); pressing **Stop** / starting a new turn goes through `cancelHook` and finishes as a *normal* completion (no more "request failed" on a deliberate abort); endpoints that ignore `stream:true` and return one whole JSON body fall back to `completionText`; the read timeout goes 300s → **600s** (netstack maps it to curl's `CURLOPT_TIMEOUT_MS`, i.e. the total budget for the whole response); and `DshDirect` hilog lines (first chunk / completion size and duration / failure reason) make the next on-device report diagnosable instead of guesswork.
- **Also**: the SSE parsing is now static (`frameBoundary` / `frameText` / `streamText` / `completionText`) so teardown can reuse it and scripts can feed it real fixtures; `data:` without a space is accepted, and multiple `data:` lines in one frame are concatenated per the SSE spec.
- **Regression guard**: new `scripts/direct-mode-check.mjs` (**32 checks**: static contract + the *real* parser functions lifted out of the `.ets` and run under `node --experimental-strip-types`, fed a **real SSE fixture captured from the official API** and re-chunked at 1/2/3/4/5/7/13/64/999-byte boundaries — including multi-byte Chinese characters split in half — plus keep-alive heartbeat frames, `[DONE]`, a truncated tail frame and the non-SSE whole-JSON fallback). The script immediately caught a boundary bug I had just introduced myself (`lastIndexOf('\n\n')` returns -1, and `-1 + 2 = 1 > 0` sliced the first character off as a frame, wrecking the whole stream). `scripts/desktop-shell-check.mjs` gains one gatekeeper check → **33/33**.
- **Artifact**: release unsigned HAP **744,701 B** (`ets/modules.abc` **689,676 B**; `requestInStream` / `frameBoundary` / `DshDirect` are all findable inside the package), sha256 `03e5a3622b013d810870ab79012cc69c07033a52ca920a24e4aa6ee7c8528456`, copied to `client/dist/` and `~/Download/dsh-harmonyos-client-1.0.0-release-unsigned.hap`.
- **Still unverified on a real device**: `hdc list targets` is still empty (no device attached), so the fix rests on netstack source plus the real-stream regression suite rather than a device screenshot. If it still stalls after installing, please paste `hdc shell hilog -T DshDirect` — those logs state first-chunk/completion/failure directly.

### 2026-09-26 (second round) — the real cause of the "ghosted" top-left logo: ArkUI strokes **every** `Path` a second time (default `strokeWidth` = 1vp black)

The owner reported the top-left deepseekharness logo was **still** ghosted and fuzzy. The previous round fixed "the same whale drawn twice"; this one is a different, lower-level cause. The brand geometry was already byte-for-byte upstream's `BrandWordmark.tsx` — the problem is how ArkUI draws it: `DrawingPainter::DrawPath` (`arkui_ace_engine`) always draws a `Path` twice (brush fill, then a pen stroke) and `SetPen()` only returns false — skipping the second pass — when `strokeWidth` is explicitly zero. Omitted, the pen falls back to `STROKE_WIDTH_DEFAULT = 1.0_vp` and `GetStrokeValue(Color::BLACK)`, so every filled glyph gets a black outline traced around it. The smaller the artwork the worse: the wordmark is only 30vp tall and "deepseek" stems are about 2 viewBox units wide, so a 1vp black stroke eats nearly half the stem width — that is the ghosting.

- **Fix (not "thinner stroke" — skip the second draw)**: `scripts/gen-harmony-ui-assets.mjs` now appends `.strokeWidth(0)` to every filled glyph (`emitIcons`' fill branch plus every `Path` in `emitBrand`/`emitBrandFull`), and the hand-written `common/Brand.ets` (`FishMark`) and `view/InputBar.ets` (send arrow) were updated the same way. Outline icons already set an explicit `strokeWidth`, which is exactly why only filled artwork was damaged: the wordmark, the letters inside the inverted HARNESS badge, the send arrow and a few solid glyphs.
- **Regression guard**: `scripts/desktop-shell-check.mjs` gained 3 checks (the number of `.commands(` equals the number of `.strokeWidth(` in `Icons.ets`; every `.fill(` chain in `Brand.ets`/`InputBar.ets` must contain `.strokeWidth`) — now **32/32** green.
- **Self-check images**: `scripts/svg-preview.py` gained `--scale` (zoom in) and `--pen` (reproduce ArkUI's default black pen second pass). Same official geometry, two renders: `docs/assets/brand-strokeWidth0.png` (now — clean) vs `docs/assets/brand-arkui-default-pen.png` (before — a black ring around every stem = the ghost).
- **Packaging**: unsigned release HAP **742,569 B** (`ets/modules.abc` **687,544 B**), sha256 `4a982689f659f8c907e4cb7fc81b455d39d649f7e3a44b3408d9566e4f5605e3`, identical in `client/dist/` and `~/Download/dsh-harmonyos-client-1.0.0-release-unsigned.hap`; disassembling with `ark_disasm` confirms **87** call sites of `strokeWidth(0)` (85 filled glyphs + `FishMark` + the send arrow). Still unverified on a real device (`hdc list targets` is empty).

### 2026-09-26 — HarmonyOS desktop: standalone mode is turnkey (bundled conversation modes) + four chips in the composer row + a real model menu + brand double-draw fix

The owner reported four things: (1) "the desktop still wants a local service, and it cannot connect"; (2) "the workspace picker and conversation-mode picker can move next to the workspace permission"; (3) "the conversation-mode button left of Send has a bug — clicking it opens Settings"; (4) "the deepseekharness logo in the top-left is ghosted/doubled". All four addressed:

- **The real reason it could not connect = wrong way of getting the login cookie from the 303** (the service was fine). dsh's `GET /` answers **303 See Other** + `set-cookie: dsh-auth-*` when no cookie is present, and only returns 200 once you send that cookie; `@ohos.net.http` follows redirects by default, which drops that `set-cookie`, so every subsequent RPC returned 401 — which the client showed as "cannot connect". Fix: `service/DshApiClient.ets` `login()` now passes `maxRedirects: 0` (API 23+; this SDK has **no** `followRedirects`, which fails to compile), plus a case-insensitive `headerValue()` and a `resp.cookies` fallback. Verified with curl: `GET /` 303+cookie → `POST /api/session/list` with the cookie 200 → `ws://…/api/remote.mux` handshake **101**.
- **Standalone mode (`direct`) is genuinely turnkey**: new `scripts/gen-client-presets.mjs` (zero-dependency, with `--check`) generates `rawfile/presets.json` (8 modes: id / Chinese product name / description / persona system prompt) from the repo's `presets/*/{preset.yml,agent.cordis.yml}`, shipped inside the HAP; new `common/PresetCatalog.ets` reads it (falls back to `Constants.BUILTIN_PRESETS` and never blocks startup). In standalone mode the conversation-mode chip lists exactly these 8 bundled modes, and the chosen one becomes the `system` prompt of every request (`{{model}}`/`{{cwd}}` placeholders substituted) — **no dsh service and no server-side `agentPresets/list` needed**. Settings gains an endpoint field for standalone mode (default `https://api.deepseek.com/v1`, OpenAI-compatible); API key + model + endpoint are stored locally only. Copy now reads "独立模式（内置，开箱即用）" / "dsh 服务模式".
- **All four selectors in one row** (as requested): `view/InputBar.ets`'s tool row is now a wrapping Flex — `+` circle → **workspace permission** → **workspace** → **conversation mode**; the old `heroWorkspaceRow()` above the hero card (workspace + conversation mode chips) is deleted, and `view/ChatView.ets` trimmed accordingly. The three chips keep the existing rule: when unavailable they are greyed out with a stated reason and a "切换到 dsh 服务模式…" action in the menu, never hidden.
- **Fixed "the conversation-mode button opens Settings"**: that was the model chip (`conversation.input.model` seat) miswired to `onOpenModelSettings`. It is now a real `bindMenu(modelMenu())`: candidates list with a ✓ on the current one, selecting switches immediately (standalone mode updates and persists locally; dsh service mode calls `session/selectModel` and refreshes the session list); the settings entry is demoted to the last menu line ("模型与 API Key…" / "模型与连接设置…"). Candidates: standalone = built-in model ids, dsh service = `session/modelCatalog`'s `provider/model` (new `DshApiClient.modelCatalog()` / `selectModel()`, and `session/list`'s `modelSelection` projection now fills in the current model; `modelLabel()` no longer passes a preset off as a model).
- **Top-left logo ghosting = the same whale drawn twice**: the generator took the `includeMark=true` 182-wide wordmark (which already contains the whale) while `view/Sidebar.ets` also drew a separate `FishMark`. Fix: `scripts/gen-harmony-ui-assets.mjs` now emits two builders via `parseBrandParts()` — `IconBrandWordmark` (viewBox `26 0 156 24`, just "DeepSeek HARNESS" + inverted badge) and **`IconBrandFull`** (viewBox `0 0 182 24`, whale and wordmark in one). The sidebar brand row uses the single `IconBrandFull`; the collapsed rail still uses only `FishMark` (a whale alone there was never a double-draw). When system window decorations are hidden the brand row is not rendered at all (`hideBrand`) so it cannot fight the self-drawn menu bar. **⚠️ This only covered the duplicated whale; the owner still saw "ghosting, not sharp" after installing, and the real cause was ArkUI's extra default black stroke on every `Path` — see the second round entry above.**
- **Packaging**: unsigned release HAP **739,841 B** (`ets/modules.abc` **684,816 B**), sha256 `2aa4ddc73d58dd12b8f9ba7c2ab678931af0a4910b9f135eafb274f1b6159774`, identical in `client/dist/` and `~/Download/dsh-harmonyos-client-1.0.0-release-unsigned.hap`. Checks: `desktop-shell-check.mjs` 29/29, `gen-harmony-ui-assets.mjs --check` 5/5 (181 tokens · 94 glyphs), `gen-client-presets.mjs --check` pass, zero ArkTS errors (one known harmless WARN left), and the package was inspected to contain `rawfile/presets.json` plus the new copy. **Still unverified on a real device** (`hdc list targets` is empty).

### 2026-09-26 — Home-screen conversation entries: workspace picker / workspace permission / conversation mode, and one composer only

The owner reported: "the desktop home screen shows two chat inputs, there is no workspace-picker button, no workspace-permission choice, and the conversation mode cannot be chosen either." All four share one root cause: upstream hangs the three session entries (workspace chip, permission chip, agent-preset chip) off the **hero (blank-session) phase**, while the HarmonyOS port only copied the hero headline, dropped the three selectors, and additionally kept a second composer docked at the bottom of the column.

- **Root causes**: (1) `view/ChatView.ets` rendered one `InputBar` in the hero phase *and* kept another docked at the column foot, so a blank session showed both at once; (2) the old "workspace row" was a single dead button calling `pickWorkspaceDirectory()`, with nothing to choose from; (3) permission and conversation mode were passive text — `agentPresets/list` and `permissionPresets/catalog` were never wired up at all.
- **Aligned with upstream** (sources: `ui-conversation/src/client/skeleton/{ConversationContent,InputBar,EmptyHero}.tsx` and `ConversationRoot.module.css`): exactly **one** composer per column (`composer(true|false)`; hero phase = hero chrome + workspace row + card, with messages = transcript + the same card; the whole client now has a single `TextArea`); `heroWorkspaceRow` = workspace chip (`bindMenu` listing session `cwd`s plus "Choose folder…" → `DocumentViewPicker`, label from the directory's last segment) + agent-preset chip (menu listing `agentPresets/list` minus `broken` presets, locked after the first turn).
- **Workspace-permission chip** (upstream `conversation.input.permission` / `ui-permission-presets`' `PermissionSelect`): in the composer tool row, with its permission glyph + display name + chevron; the menu comes from `permissionPresets/catalog` and writes go through `commands/execute`'s `/permission <preset>` (the same path the web client uses). `danger-full-access` and `auto` first raise a **risk confirmation** (self-drawn `DesktopPermissionRiskPanel`, copy taken from upstream's `RiskConfirmation`; the enable button stays disabled until "I understand the risks" is checked).
- **Display-name rules** (`Constants.permissionLabel()`, matching upstream `displayPermissionPreset`): `read-only`→仅可查看, `workspace-write`→工作区内修改, `danger-full-access`→完全权限, `auto`→`Auto review` (with an `EXP` superscript); any other deployment name goes through upstream's `displayPresetName` title-casing. **Machine values are only used for menu comparison and protocol writes** — a display name is never written back.
- **Protocol updates** (0.1.6 typert gateway, measured locally): `/api/events.mux` (SSE) and `agentPreset.list`/`host.describe` are gone → cookie login (`GET /` on loopback returns `dsh-auth-*`; persisted and reused, with one automatic re-login on 401) plus the WebSocket `/api/remote.mux` (`session/follow`, whose downstream frames are `snapshot` / `event` / `assistant-stream`; exponential-backoff reconnect re-subscribes live streams) plus `agentPresets/list`, `permissionPresets/catalog` and `commands/execute`.
- **Direct mode**: the built-in DeepSeek API has no workspace/permission concept — the permission chip is greyed out with its reason spelled out, and the workspace / conversation-mode menus open with a disabled explainer line. All three menus also carry a clickable "切换到 dsh 服务模式…" action (the same switch as the Settings connection mode), so the entries are neither hidden nor dead ends.
- **Packaging**: unsigned release HAP **660,589 B** (`ets/modules.abc` **638,368 B**), copies in `client/dist/` and `~/Download/dsh-harmonyos-client-1.0.0-release-unsigned.hap`. Checks: `gen-harmony-ui-assets.mjs --check` 5/5 (181 tokens · 94 glyphs), `desktop-shell-check.mjs` 29/29, zero ArkTS errors (one known harmless WARN left), and the packaged `ets/modules.abc` was inspected for the new copy. **Still unverified on a real device** (`hdc list targets` is empty).

### 2026-09-25 — HarmonyOS desktop adaptation: upstream Electron shell source + a native ArkTS desktop shell

The official desktop app (`apps/desktop` in `deepseek-ai/deepseek-harness`) is a thin Electron shell that cannot run on HarmonyOS (its release targets are mac/win only, and Electron/`koffi`/`node-pty` all fail to load on HarmonyOS). This change takes it apart and rewrites the shell layer in ArkTS:

- **Source archive**: new `desktop-upstream/` (`apps/desktop` + `apps/desktop-host`, 456 files / 6.2 MB, MIT) recording the repository, branch (`master`, not `main`), commit `477b4f42`, version `0.1.7-rc.2`, fetch date, a one-line refresh command, and the upstream `LICENSE` / `THIRD_PARTY_NOTICES.md`.
- **Architecture analysis**: new `docs/DESKTOP-SHELL-UPSTREAM.md` covering the process model (shell / renderer / RunAsNode Host / embedded browser view), the `dsh-app://app/` scheme with cookie-forwarded authentication, port 19387 and exclusive `$DSH_HOME/profiles/desktop`, the 25-channel IPC surface, menus and context menus, the device-level `keybindings.json`, the auto-update state machine with its 10 min / 1 h / ±20% schedule, and the crash/recovery surface — plus a per-capability portability verdict.
- **Implementation** (`client/`, all new files; the existing chat path is untouched):
  - `desktop/DesktopShellContract.ets` + `resources/rawfile/desktop-shell.json`: turns upstream's hard-coded constants (window 1280x820 / min 520x600, update 600000 ms / 3600000 ms / 0.2, ports, protocol version, menu tree, shortcut table) into a **single source of truth** read at runtime, with a built-in fallback that explains itself when loading fails.
  - `desktop/WindowGeometry.ets` + `entryability/EntryAbility.ets`: window geometry restore (clamped back on screen), `setWindowLimits` minimum size, 400 ms coalesced persistence; `windowStage.on('windowStageClose')` intercepts close → in-page confirmation → `terminateSelf()`, and never intercepts before the page is ready (no stuck window).
  - `view/DesktopMenuBar.ets`: self-drawn application menu bar plus dropdown (structure from the contract; shortcut hints generated by `ShortcutRegistry`, so the menu can never claim a binding that is not registered). `Ctrl+W` close-confirm, `Ctrl+R` reconnect, `F11` full screen via `keyboardShortcut()`.
  - `view/DesktopDialogs.ets`: About panel (client version / adaptation baseline / upstream commit / host protocol version / contract source), quit confirmation (reusing upstream's "tasks will be interrupted" vs "scheduled tasks will not run" copy), update panel (same state-machine copy plus technical details).
  - `service/DesktopUpdateService.ets` + `desktop/UpdateFeed.ets` + `desktop/UpdateSchedule.ets`: reads the **same** official feed (`dsh-desk/feeds/<target>/nightly.yml`), implements semver comparison including `-rc.N` prerelease rules, and mirrors upstream scheduling semantics line by line (completion-based deadline, manual checks joined to the in-flight automatic one, exponential backoff with jitter, no re-arming after `dispose`). Discovery only — installation is handed to the download page.
  - `desktop/DesktopDirectoryPicker.ets`: `DocumentViewPicker` folder selection with concurrent requests coalesced into one (upstream's `WeakMap` dedupe).
  - `desktop/ShortcutRegistry.ets` + `desktop/DesktopPrefs.ets`: device-level shortcut preferences (defaults + overrides + revisioned single-writer snapshot) and one shared preference store.
- **Drift guard**: new `scripts/desktop-shell-check.mjs` (zero dependencies, `node scripts/desktop-shell-check.mjs`) reconciles contract ↔ upstream source snapshot ↔ ArkTS implementation (copy fields, label resolver, menu dispatch, contract reads): currently **24/24 green**, and a negative test (deliberately breaking `defaultWidth`) is pinpointed with exit 1.
- **Build**: `sh ~/bin/deveco-api26.sh ~/dsh-harmonyos-pc/client assembleHap` — **compiles clean** (zero ArkTS errors), producing an unsigned HAP (a device install needs DevEco signing).
- **Unsigned HAP packaging**: `client/build-profile.json5` has an empty `signingConfigs` array, so hvigor only prints `WARN: No signingConfig found for product default` at the `SignHap` step and skips it — the artifact is **unsigned by construction** (no `META-INF/`, no certificate or profile inside). A clean full **release** build (34 tasks / 15 s) yields `entry-default-unsigned.hap` at **284,192 B** (`ets/modules.abc` 271,972 B, plus the `resources/rawfile/desktop-shell.json` contract and `pack.info`), with copies at `client/dist/dsh-harmonyos-client-1.0.0-release-unsigned.hap` and in `~/Download/`, sha256 `0ba5bbe388a76d3b09fd5f56e03bf3d1c10e1ff00b183b6e5bdf854c72f0b77e`; the debug variant (unobfuscated, with sourcemaps) is 660,742 B when `-p buildMode=release` is dropped.
- **UI replication (everything read off the upstream open-source client, nothing hand-drawn)**: a new `scripts/gen-harmony-ui-assets.mjs` acts as the **single generator** (`node scripts/gen-harmony-ui-assets.mjs` to emit, `--check` to assert the emitted files match the disk, `--upstream`/`DSH_UPSTREAM` to point at another checkout) and compiles upstream's design sources straight into ArkTS:
  - `common/Tokens.ets` — the **181 `--dsw-*` tokens** from `packages/client/ui-theme/src/styles/design-platform.css` (light `body` and dark `body[data-ds-dark-theme]` tables, with `var()` chains and `color-mix(in srgb)` resolved at generation time);
  - `common/Icons.ets` — the **94 glyphs** from `ui-primitives/src/icons/{index,shared-artwork,PermissionIcon}.tsx` (including the three `PermissionIcon*` permission artworks), each turned into `Shape` + `Path.commands` (viewPort-scaled, so they take a runtime colour and follow the dark/light switch instead of going through statically tinted `Image($r('app.media.*'))` assets), plus the official whale `FISH_LOGO_PATH` and the `BrandWordmark` wordmark with its inverted HARNESS badge;
  - `common/Theme.ets` — sizing and rhythm constants matched line by line against `ui-theme/base.css`, `apps/desktop/src/windows-layout.ts` and the per-component `*.module.css` files (titlebar 40, caption menu 28/padding 10/radius 6/start x 48 (84 when collapsed), sidebar 280↔56, conversation header 76, composer radius 28 capped at "column + 32", bubble radius 20 with 10/16 padding, session row 32 / project row 34, 800×800 settings panel with a 188 nav…). No visual value is invented here;
  - views rewritten on top of those tokens: a self-drawn Windows titlebar (28×28 toggle at x=12, plus a new-session control at x=48 when collapsed — the same geometry as the inline CSS in upstream `preload-menu.ts`), the three-column frame (16px rounded top-left on the conversation column), the sidebar (40px brand row / 38px new session / 32px session rows / 42px settings trigger), the empty-session HeroShell (34px whale + 26/32 headline + preview badge), the composer and message bubbles, and the settings panel with its appearance cubes and font-size stepper. The app icon, ability icon and start-window icon all now come from upstream `apps/desktop/resources/icon-windows.svg` (generated by stripping `filter`, folding `linearGradient` into solid paint and baking `transform` into the coordinates, because ArkUI's SVG parser guarantees none of the three); the old hand-drawn placeholder icons are gone.
  - Two real defects found and fixed on the way: (1) the dark/light and font-size preferences were written to AppStorage but **nobody subscribed** (`Theme.palette()` reading AppStorage directly creates no dependency), so every component now passes its `@StorageProp` through `Theme.palette(this.dark)`, the page keeps an `@State dark`, and `EntryAbility.onConfigurationUpdate` → eventHub makes "follow the system" apply immediately; (2) the sidebar brand row's collapse toggle was a **permanently lit** hover-coloured square — now transparent until hovered, with upstream's hover feedback added back to the sidebar rows and the caption menus.
  - Repackaged: the unsigned release HAP is now **595,373 B**, sha256 `a83adf27c72ecec1e96d0221ee857694847da134035c4bdad7d64a6dbe9f963e` (copies in `client/dist/` and `~/Download/`). The size increase comes from the 181 tokens, 94 glyphs and the official 1024px icon geometry.
- **Pre-existing build blocker fixed along the way**: `module.json5` now declares `ohos.permission.USE_AI` under `definePermissions` (`system_grant`/`system_basic`). The HarmonyOS 26 (API 26) SDK ships no `USE_AI` in its predefined permission table, so `PreBuild` failed with `00303221`; the explicit declaration builds cleanly with identical permission semantics (still needs a `system_basic` APL signing template to actually be granted).
- **Limitations**: on HarmonyOS the update check **discovers but never installs**, the Edit menu **does not inject keys**, there is **no tray** (close → confirm + minimize), and `restartAppHost` tells you to restart dsh from the terminal — all four are recorded in the Limitations section above.

- **Two small defects reported by the owner (fixed 2026-09-26)**:
  - **"The window cannot be made smaller" = mixed window-geometry units.** The official docs (`arkts-apis-window-Window.md` / `arkts-apis-window-i.md`) are explicit: the arguments of `resize()`/`resizeAsync()`/`moveWindowTo()`, `getWindowProperties().windowRect`, the `Size` handed to `windowSizeChange`, and `WindowLimits` min/maxWidth/Height are **all px** (only the API 22/23 `SizeInVP`/`RectInVP`/`getWindowLimitsVP` family is vp). The old code treated px-typed geometry as vp and then passed it back into px APIs, so every restart halved the window via `density`, and the minimum-size clamp left it stuck at 520x600 (from the owner's seat: "I can't shrink it", plus a slow drift towards the top-left corner). Fix: keep everything (in-memory fields, persisted JSON, clamping, display comparisons) in vp, funnel every window API call through `WindowGeometry.pxFromVp(vp, density)`, and convert back with `fromPixelRect()` in `persistGeometry()`; the persisted format gained a `v:2` version tag that discards mixed-unit dirty data wholesale instead of guessing. `setWindowLimits` now takes min = min(contract minimum, display work area) and max = display, so the window always stays on screen and draggable.
  - **The top-left logo was too small, and one whale was drawn twice.** Upstream `SidebarRoot` renders `sidebar.brand.mark` at size 24 and the official `ui-brand-official` plugin uses `BrandWordmark includeMark={false}` (viewBox `26 0 156 24`, the "DeepSeek HARNESS" wordmark only), while the generator had taken the 182-wide `includeMark=true` variant — so `FishMark` and the whale embedded in the wordmark appeared side by side. Fix: the generator now strips `<defs>` first, then the wordmark's `dsh-wordmark-whale-clip` whale group, emitting `viewPort {26,0,156,24}` at width `size*156/24`; `Theme.BRAND_MARK_SIZE` / `BRAND_NAME_HEIGHT` were enlarged from upstream's 24 to **30** on the owner's request (40px brand row leaves a 10px margin; locked column width 30+8+195+4=237 fits the sidebar's 252 available, and 32 would sit flush against the edge).
  - Repackaged: the unsigned release HAP is **598,357 B** (`ets/modules.abc` 576,136 B), sha256 `d1cef772a8bd9e9b15fdb357edb57164fbd06365663cce359b0fc5361556d3d6` (a HAP is a zip with mtimes inside, so two builds of identical source never share a sha — compare sizes instead), with copies in `client/dist/` and `~/Download/`. Checks: `gen-harmony-ui-assets.mjs --check` 5/5, `desktop-shell-check.mjs` 29/29, one known harmless ArkTS WARN left. **Still unverified on a real device** (`hdc list targets` is empty).

### 2026-09-16 — Fix "history with reasoning blocks breaks every turn" under the Messages protocol

- **Symptom**: after upgrading to 0.1.6-alpha.1 some sessions failed on every turn with the UI notice "本轮运行失败" and the error text `DeepSeek Messages cannot represent user/tool-result content reasoning` (`UNSUPPORTED_CONTENT`).
- **Root cause**: 0.1.6 gave `dsh-llm-deepseek` a `protocol: chat-completions | messages` switch and made **`messages` the default** (Anthropic-style, strictly validated); its serializer only accepts `text`/`image` and throws on any other block type. This device's history contains user messages with embedded `reasoning` blocks, written by **`dsh-subagent` 0.1.3-alpha.2**: back then `createSettlementMessage` copied a subagent's entire terminal output — thinking blocks included — into the "Background subagent … finished" settlement notice. 0.1.6 keeps only `text` when writing those, but the existing history still carries them. Before the upgrade everything went through chat-completions (`flattenText` keeps text and silently drops the rest), so it never failed.
- **Fix** (`patchMessagesSkipNonText()`, idempotently re-applied by `patchAll()`): the Messages serializer's `if (block.type !== "image") return unsupported(...)` became `return []`, i.e. **non-text/image blocks are skipped silently**, matching chat-completions semantics. Only user/`tool-result` content is affected; the assistant branch and the system-message validation are untouched.
- **Verification**: A/B on the same history containing `reasoning` blocks — before the patch it threw `UNSUPPORTED_CONTENT`, after it produced the request body with the original text preserved; dsh web was then restarted and the session resumed normally.

### 2026-09-15 — Follow upstream 0.1.6-alpha.1 (usability fixes; sidebar terminal unavailable for now)

Upstream `0.1.6-alpha.1` is installed on this device (`~/dsh-test`, re-applying all 13 patches through `~/bin/dsh-update.mjs`). The web app would not boot and model calls returned 404 on upgrade day; fixes, root cause first:

- **Inlined flock shim (compat-loader)**: 0.1.6 moved the session write lease from `fs-ext` to `@deepseek-ai/node-addon-system/flock`, which ships no openharmony-arm64 prebuild (its `loadBinding` resolves the platform package first and fails). The loader now resolves that specifier to a no-op shim — upstream documents that a single-process deployment may treat flock as immediately successful (the browser worker does exactly that), and this device runs one process.
- **`node:util` compat layer**: 0.1.6's `dsh-subprocess-local` runner calls `util.getSystemErrorMessage`, added in node >=23.6 (this runtime is v22.7). The loader serves a `node:util?compat` wrapper (`export * from 'node:util'` plus an errno-to-libuv-message table with a name fallback).
- **Config regression: `llm-deepseek.baseURL`**: as of 0.1.6 an explicit `baseURL` is used verbatim (0.1.3 appended `/anthropic` by protocol); the Messages protocol root is `https://api.deepseek.com/anthropic`. The device pinned `https://api.deepseek.com`, so every request 404'd (`DeepSeek Messages request failed (404)`). It is now left unset so the protocol default applies.
- **Plugin regression: `dsh-huawei-local-llm`**: 0.1.6's `PiAiAdapter` reads `profile.modelErrors`, and the hand-built profile lacked it, so the `session/modelCatalog` probe threw `Cannot read properties of undefined (reading 'get')` and the provider fell into `failures`; `modelErrors`/`catalogError`/`reasoning` are now supplied.
- **`dsh-subagent` legacy descriptor v2 identity projection** (`patchLegacySubagentIdentity()`): identity projection has accepted only descriptor version 3 since 0.1.3, while sessions written by this device's 2026-08 development builds carry version 2, so opening such a subagent address from the web UI reported a corrupt descriptor; the patch tolerates v2 for identity (mode/label) only, leaving continuation/recovery semantics untouched.
- **Sidebar terminal unavailable (new upstream feature)**: 0.1.6 adds the host `dsh-api-terminal-controller`, the client `ui-sidebar-terminal`, and `ptc-runtime`, all of which depend on the `subprocess` service = `@deepseek-ai/dsh-subprocess-local`; that package statically imports `node-pty` (pty allocation) and `koffi` (FFI execve) at the top level, and HarmonyOS blocks dlopen of untrusted ELF plus ships no openharmony-arm64 prebuild, so the module fails with `Cannot find the native Koffi module`. `harmony.patch.yml` disables all three rows (host and client together), which also removes the leftover "did not activate" startup warning. Re-enable once upstream offers a pure-JS/standalone pty or HarmonyOS permits native modules.

**Verified after upgrade**: clean boot (only the known `@napi-rs/canvas` and UV notices); `settings/describe` reports 19 namespaces including `llm-pi-ai`; `session/modelCatalog` lists 7 routable providers with `failures: []`; `session/list` returns 280 sessions; a deep legacy session (turn 285) pages correctly; a new session's `session/prompt` produced a model reply and `turn/end reason=completed`.

### 2026-09-09 — Fix "web UI cannot message sessions" after 0.1.3-alpha.2 (4 resume-chain regressions)

Resuming any pre-upgrade session failed mid-resume, so sending from the web UI appeared broken. Root causes, each fixed:

- **`patchSessionVerify()` scope bug (fatal)**: the inserted `verifyCurrentFile` callback referenced an out-of-scope `internals`, so every v0 resume threw `ReferenceError: internals is not defined`; it now delegates to the module-level `defaultGenerationRuntime.verify`.
- **Migration publish hard-link EPERM (fatal)**: v0→v2 on-demand publication used `fs.link()`, which HarmonyOS `/storage` rejects with EPERM even for absent targets; new idempotent `patchMigrationPublish()` falls back to `rename` after confirming the target is absent (same pattern as the existing `dsh-fs-local` workaround).
- **`dsh-pet` 0.2.6 cold-boot crash**: host entry imports `@electron/get`/`@electron-internal/extract-zip` native bindings at top level (dlopen fails on HarmonyOS, no musl prebuild), crashing plugin-tree load into a watchdog restart loop; `harmony.patch.yml` now disables the `pet` row (0.2.0 loaded fine; re-enable once upstream is pure JS).
- **agent-presets persona key migration**: `dsh-persona` in 0.1.3-alpha.2 requires `prefix` instead of the old `text` key; all presets (harmony-chat/deveco/liangshen etc.) were migrated to `prefix`.


### 2026-09-09 — Client glass theme / on-device local AI + Huawei plugins shipped in-repo

- **`plugins/dsh-huawei-devdocs` and `plugins/dsh-huawei-local-llm` are now shipped in-repo**, byte-identical to the running `plugins-src` copies (incl. the `(_args, value)` render-signature fix, guard messages without `form:"guard"`, MIT LICENSE and test fixtures). `dsh-hm-update.mjs` auto-deploys every profile-level plugin under `plugins/`, so no separate install step is needed.
- **The HarmonyOS client now declares `ohos.permission.USE_AI`** (system_basic) with a permission-reason string; the signing / whitelist paths are documented in `docs/LOCAL-AI-USE_AI.md`.
- **Client UI "immersive glass" pass**: glass layers, light borders and a brand gradient were added to the theme tokens; the settings panel moved to a `bindSheet` half-modal (MEDIUM/LARGE detents + blur + drag bar), and the sidebar / chat / input / message views were glassified.

### 2026-09-09 — Follow official 0.1.3-alpha.2 (legacy-session migration compat + loader frame-split compression)

dsh upgraded to official `0.1.3-alpha.2` (released 2026-09-08; local dsh-test upgraded). The official release freezes released-v0 sessions to read-only validation and adds v0→v2 generation migration; the frozen checks are too strict for dev-era logs, so every session history failed to load after the upgrade ("model cannot load"):

- **worker.cjs migration verification moved back to the main thread (`patchSessionVerify()`) + CJS zstd twin `compat-loader-cjs.cjs`**: the official migration verifier defaults to worker_threads; the worker pulls ESM packages via CJS `require`, which node v22.7.0 cannot do. It now verifies on the main thread (`verifyCurrentGeneration`, same module, fzstd sync decode available) at the cost of losing thread isolation.
- **v0→v1 frozen-validation compat patch (new idempotent `patchSessionFormat()` in `patchAll`)**: only two legacy data shapes are admitted — plugin `source.form:"guard"` (guard messages from prompt-antivirus / huawei-devdocs; not a released-v0 form) and `subagent/descriptor` version 2 (deepseek-harness dev-era sessions). Everything else keeps the upstream closed whitelist. Full probe over all 251 v0 sessions through the official format catalog: 107 refused before → 0 failures after.
- **compat-loader frame-split compression**: the WASM zstd codec OOMs on single frames over ~4-8MB; migration publishing compresses an entire log at once, so 20MB+ sessions always aborted. `createZstdCompress` now compresses in 2MB frames and concatenates them; readers decode frames independently, so output semantics equal a single frame.
- **`harmony.patch.yml` disables `open-in-app` + `ui-open-in-app`**: the web-app bundle gained an open-in-app (host) plugin depending on native spawn (`dsh-subprocess`/`dsh-native-command`, unavailable on HarmonyOS) → the host stayed pending → the whole plugin tree failed to load.
- **Plugins stop writing non-standard `source.form`**: prompt-antivirus / huawei-devdocs guard messages drop `form:"guard"` (source keeps only `kind` + `plugin`) so new sessions no longer persist custom forms the released validator rejects.

Verified: after restart, 3080 is healthy with no OOM; all 251 sessions migrate to v2 through the official chain.

### 2026-09-03 — Follow official 0.1.2-rc.1 (all 9 patch anchors hit + 2 self-updater compat fixes)

dsh upgraded to official `0.1.2-rc.1` (released 2026-09-03); the local dsh-test is synced and the web UI verified to start. All nine node_modules patch anchors matched rc.1, and after re-applying, 3080 behaves normally:

- **`ensureCompatDeps()` drops npm for direct tarball install**: the rc.1 closure no longer contains `fzstd`/`zstd-codec` (compat-loader deps). The old `npm install` path made npm's arborist re-resolve the whole tree against the stale `^0.1.1-rc.2` range in `~/dsh-test/package.json`, **downgrading freshly-installed `0.1.2-rc.1` back to `0.1.1-rc.2`** and wiping every patch (reproduced this run). It now installs those two packages directly from the registry (manifest + tarball + tar), with zero side effects; new `syncPackageJson()` pins the installed dsh version into `~/dsh-test/package.json` after upgrade/rollback so no later `npm` run can downgrade again.
- **`dsh-web.sh` upgraded to a working HarmonyOS version + orphan-lock cleanup**: the in-repo `scripts/dsh-web.sh` was still the v24-node draft (crashes `ENOMEM` in the V8 code-range on HarmonyOS) and lacked compat-loader / the local market mirror / correct patch resolution. It now mirrors the machine-proven logic: default deveco node v22 + `--experimental-loader compat-loader.mjs` + `--patch harmony.patch.yml` + market mirror on 3988, with `NODE_BIN/DSH_DIR/PATCH_YML/PORT/LOG` env overrides. New `clear_stale_locks()` handles dsh's atomic-write orphan locks (SIGKILL/crash leaves `~/.dsh/profiles/node_modules.lock`, so the next boot dies with "timed out waiting for the writer lock" — reproduced this run); it clears them once before starting.
- Validation: `@deepseek-ai/dsh` 0.1.2-rc.1 (549-package closure); `node scripts/dsh-update.mjs patch` all-green (credential/session/permission/attachment/cordisLoader/settingsCompat/loopbackAuth/fsLocal re-applied, vision idempotent); 3080 returns 303 with a token; codex-bridge / deveco-bridge / cron / peak-valley / evoresearch / cost-meter all load. `bridge-browser` stays disabled (rc.1 `dsh-api-remotes` still doesn't restore `ApiRemoteSessionNotFound`).

### 2026-09-01 — Follow official 0.1.2-alpha.3 (fs-local patch + self-updater fix)

dsh upgraded to official `0.1.2-alpha.3` (released 2026-08-31); the local dsh-test is synced and the web UI verified to start:

- **`dsh-fs-local` patch folded into `patchAll` (new `patchFsLocal()`)** — new-file workspace writes (`createIfAbsent`) hit `EPERM` from `link()` on HarmonyOS `/storage`, even when the target is absent. This patch was previously missing from the self-updater, so every upgrade/reinstall wiped it and required a manual re-apply. It now follows the same "content-anchor + idempotency marker" pattern as the other patches and is re-applied automatically. Neither official `dsh-fs-local@0.1.2-alpha.3` nor alpha.2 (byte-identical) ships this fallback — confirmed by diffing the published tarballs.
- **Fixed the false-negative in `dsh-update.mjs` `isUp()`** — under token auth the bare `/` returns a 303 redirect when no cookie is present; `fetch()` follows redirects but does not carry the cookie across hops, so it lands on a 3xx again and was misread as "not up", making `install` fail even though the upgrade succeeded and the server was serving. Switched to `redirect:'manual'` and treat 2xx–3xx as up; `dsh-web.sh`'s `is_up` (curl waits on any response) remains the backstop.
- Validation: after `install`, `@deepseek-ai/dsh` reports `0.1.2-alpha.3` with `fsLocal=重打` and the other patches idempotent; `node scripts/dsh-update.mjs patch` is all-green; `/` on 3080 reaches 200 with a cookie, and `codex-bridge` / `deveco-bridge` / `cron` / `peak-valley` / `cost-meter` / `evoresearch` all load.

### 2026-08-31 — New preset harmony-chat-monash (Monash student edition)

Eighth "HarmonyOS conversation mode" preset (order 8), built on the `harmony-chat-promax` skeleton (`includeRuntimeContext: false` — fully static system prompt, high DeepSeek prefix-cache hit rate; identical tool set to ProMax: fs / web search / delegation / planning / workflows, pure JS with no native dependencies), with the persona specialized for Monash University students:

- **Literature interpretation**: one-sentence summary + research question → background → methods → results → discussion → limitations → relevance to the assignment; explains key terms and statistical methods (t-tests, regression, effect sizes) and provides ready-to-use citations (APA 7th by default, AGLC4 for legal sources)
- **Plagiarism check & academic integrity**: does not replace Turnitin — guides uploading drafts to Moodle for the Similarity Report, distinguishes legitimate citations from text needing rewriting with concrete rewriting strategies; red lines: contract cheating, buying essays, undeclared AI use, and self-plagiarism all violate the Student Academic Integrity Procedure
- **Assignment help**: breaks down task verbs + rubric → argument structure → key points → section-by-section draft review; never writes whole essays or fabricates references
- **Built-in knowledge base**: student services & libraries across Clayton / Caulfield / Docklands (Monash College), university-wide services (Student Academic Success / English Connect / counselling 03 9905 3020 / Safer Community / eSolutions / Career Connect; moodle.monash.edu · my.monash.edu · WES); Melbourne transport (free Intercampus Shuttle, Huntingdale / Caulfield / Southern Cross travel guides, myki concession / ISTP / Monash Commuter Club discounts; timetables per PTV Journey Planner)

### 2026-08-31 — Global prompt-antivirus dsh-prompt-antivirus (context-virus defense)

Ported the principle of `openclaw-prompt-antivirus` (runtime defense against prompt injection / mind-virus attacks) onto dsh as a profile-layer global plugin:

- **Four hook layers**: `tools/pre-execute` scans tool arguments (deny on high risk, human approval for dangerous tools), `tools/post-execute` scans tool results (where indirect injection hides; block/quarantine), `agent/pre-step` scans messages before they enter the model (`[CRON TASK]` / `[SCHEDULE REMINDER]` / web-search / file-content payloads are quarantined before reaching the model) plus a one-time per-session canary guard, and `llm/stream` sanitizes outbound text and detects canary hits (interrupts output in block mode).
- **Three modes**: `quarantine` (default; rewrites matched spans where in-place replacement is possible) / `block` (stricter + canary interrupt) / `monitor` (audit-only).
- **Tools & audit**: `_antivirus_scan` / `_antivirus_status` available per session; audit written to `~/.dsh/task-board/prompt-antivirus-audit.jsonl` (500-entry ring + 2 MB file cap, fail-silent).
- **Install**: shipped as `plugins/dsh-prompt-antivirus/`; `scripts/dsh-prompt-antivirus-install.mjs` installs it into the web + headless profiles idempotently (source → plugins-src + symlinks + manifest registration); `dsh-hm-update.mjs` auto-deploys all profile-level plugins under `plugins/`.
- **Validation**: 32 unit + harness tests green (signature coverage/severity, no false positives on benign Chinese text, three-mode decisions, one-time canary injection per session, canary interrupt/removal in the stream).

### 2026-08-30 — Built-in cron scheduled tasks for harmony-chat-ops

**The `harmony-chat-ops` resident background task steward gains full cron scheduling**:

- **Standard cron syntax**: new `cron_create` (standard 5-field cron "min hour day month weekday", with `@daily/@weekly/@monthly/@hourly` shortcuts and `JAN..DEC`/`SUN..SAT` names; when both day and weekday are restricted, either match triggers) + `cron_next` (validate the expression against the user's intent before creating) + management tools `cron_list` / `cron_set_enabled` / `cron_delete`; timezone defaults to `Asia/Shanghai`, overridable via `time_zone`.
- **`[CRON TASK]` framing semantics**: due tasks are delivered as untrusted task text (not new instructions); the agent executes and archives to `~/dsh-kb/` when idle. Tasks bind to the creating session—triggered on time while online, marked `overdue` offline, and only the latest missed run is backfilled on resume (no replay of backlog).
- **Backward compatible**: the old `schedule_create / schedule_list / schedule_delete` (after/at/every) remain available.

### 2026-08-22 — Fixed image reading and vision recognition (attachment-local + dsh-visual-plugin patches)

On this device, dragging an image into DeepSeek Harness then having the model see and describe it used to break at two levels: the image couldn't persist, and the vision endpoint wasn't configured.

- **`[Patch] dsh-attachment-local`**: HarmonyOS storage rejects `link()` with `EPERM` (Android/HarmonyOS don't support hard links), so publishing an image attachment into the same directory failed → read_image logged `Unable to persist image attachment`. The patch publishes via `copyFile(..., COPYFILE_EXCL)` when `link` fails (the `EEXIST` race still goes through the sha256 integrity check); `syncDirectory` skips that fsync on mount points that refuse a read-only handle (EPERM/EACCES/ENOTSUP). Fixes "read_image can read and persist".
- **`[Patch] dsh-visual-plugin`**: (1) When the vision panel is unconfigured, `resolvedFacts()` falls back to the main DeepSeek vision model — reusing the `llm-deepseek` (provider) section's `baseURL` + `DEEPSEEK_API_KEY` with `deepseek-v4-flash-vision-exp`, eliminating "`vision model is not configured`"; (2) `describeImage` retries once when the model returns empty `content` (PROTOCOL) for a custom prompt, and if still empty degrades to a clear "model returned no content" message instead of hard-throwing. Fixes "a targeted prompt also returns a stable vision description".
- **Companion**: `settings.yaml` adds a `vision-bridge` section after `llm-deepseek` (url=DeepSeek, model=deepseek-v4-flash-vision-exp, apiKeyEnv=DEEPSEEK_API_KEY) — double insurance with the code fallback and hot-reloadable.
- **`scripts/dsh-update.mjs`**: adds `patchAttachment()` / `patchVision()` (idempotent, content-anchored, marked `HarmonyOS patch`), merged into `patchAll()`'s five-way verification — re-applied automatically after upgrade/reinstall, so image reading no longer fails and vision no longer reports unconfigured.

### 2026-08-20 — Added the HarmonyOS Dev Master preset (harmony-deveco) + dev_code delegation to DevEco Code

**The 7th conversation mode `harmony-deveco`** (order 7, preset count six→seven), turning dsh into a HarmonyOS DevEco full-stack development agent:

- **dev_* toolchain**: drives hvigor/ohpm/hdc directly through dsh-deveco-bridge (pure JS via node:child_process, no native deps), closing the "write ArkTS → build → deploy to device → launch" loop, including release signing/packaging guidance
- **`dev_code` delegation to the local DevEco Code agent**: deveco-bridge gained a 6th tool `dev_code` — hands a self-contained deep sub-task over HTTP to the local DevEco Code (OpenCode web, 127.0.0.1:4096), which runs its own agent loop; one at a time (`isConcurrencySafe:false`), model defaults to `deepseek-v4-pro`; `task` must be self-contained (the sub-agent has no memory of this session); returns cost/tokens metadata for post-mortems
- **Kirin X90 software-hardware-coordinated power discipline**: this device is 4-core AArch64 + 32GB; parallel multi-agent is the most power-hungry behavior — at most one delegating agent (subagent / dev_code) running at any time, tools step forward serially on their dependencies, concentrating "depth" on the few steps that truly need it (dev_code / pro sub-agents) — fast without burning the cores
- **Verified loop**: after restarting dsh, `deveco-bridge` registers 6 tools (including dev_code); end-to-end dev_code delegation measured 4.2s / 13,528 tokens / ¥0.0002 returning a correct answer; repo preset matches `~/.dsh/.agent-presets/harmony-deveco/`

### 2026-08-20 — Follow official 0.1.0-rc.8

dsh was officially updated to `0.1.0-rc.8` (released 2026-08-19); this repository's ported version is synced. Upgrade highlights:

- **`dsh-update.mjs getLatest()` dist-tags fix**: the official `dist-tags.latest` stayed at rc.7 after rc.8 shipped, so `npm view version` reported "already latest". It now scans the full `versions` list and picks the numerically highest (rc.N and stable compared by number); `check` verified `installed = latest = 0.1.0-rc.8`.
- **New `scripts/dsh-manual-install.mjs`**: npm's arborist silently hangs during dependency resolution on HarmonyOS (no output, low CPU, times out — reproduced 3×). The manual installer recursively resolves the full dependency graph from registry metadata and installs tarballs directly, keeping baseline packages that already satisfy their spec and gating optional dependencies by `os`/`cpu`. Verified a 470-package closure with zero gaps. Wired into `dsh-update.mjs` `install()`/`rollback()` with npm as fallback.
- **rc.8 dependency tree**: 54 `@deepseek-ai/dsh-*` packages bumped `^0.1.0-rc.7` → `^0.1.0-rc.8` (including official changes: pass reasoning_content back on every reasoned turn, SQLite persistence layout optimization, Agent Teams directory renames, build artifact slot binding, pwsh persistent pty) plus new `@deepseek-ai/dsh-tool-pwsh-persistent`.
- **All three HarmonyOS patches anchored cleanly on rc.8**: credentials (skip chmod-600 owner check), session (link→rename + `rename` import; the SQLite change did not touch the JSONL persistence file), permission (`ctx.shell.sandboxMode` → `ctx.fs.sandboxMode`).
- **Verified loop**: manual install of rc.8 → re-apply patches → restart dsh → 3080 HTTP 200 → plugins load (deveco-bridge 5 tools / evoresearch / dsh-cost-meter) → all seven HarmonyOS presets report `broken: none` in `agentPreset.list`.

### 2026-08-18 — Follow official 0.1.0-rc.7

dsh was officially updated to `0.1.0-rc.7` (released in the DeepSeek group chat); this repository's ported version is synced. Upgrade highlights:

- **`--ignore-scripts` bypasses the koffi native build**: the rc.7 dependency tree bumps koffi to 3.1.5, whose install script needs CMake to compile native binaries—HarmonyOS has no compiler, so it fails outright. Testing confirms koffi's native part is only lazy-loaded via dsh-fs-local on the win32 path (never triggered on HarmonyOS), node-pty is unavailable on this machine anyway, sharp ships precompiled, and all `@deepseek-ai` packages are pure JS with no install scripts—so skipping scripts entirely during install is safe. This is now baked into `scripts/dsh-update.mjs`, so future upgrades won't hit this pitfall again.
- **DeepSeek adds a `low` reasoning tier**: the official adapter now supports `off/low/high/max` (default remains `high`); `medium` is invalid. The measured note in `docs/CACHE-OPTIMIZATION.md` has been synced.
- **Upgrade loop**: npm install → re-apply the HarmonyOS patches (credentials/session) → restart dsh → 3080 works → all five presets' `agent.cordis.yml` pass the rc.7 `entryListSchema` validation and load successfully.

### 2026-08-18 — Benchmark rewritten as "Hexagon radar + performance table + delivery quality table"

The benchmark expanded from 6 questions to 6 axes × 2 questions = 12 auto-graded questions, and a delivery quality table was added (3 process questions scored by marking hits against delivery steps). Key numbers: all five presets get full marks across the six capability axes (same-model capability floor); cache hit rate after static persona padding goes from 52.9-89.9% to 93.8-98.0%; delivery-spec scores—promax 89 (performance and discipline in one), rampagemax 92 the highest of all (only full marks in retrospective & wrap-up, but most expensive in efficiency/time). The script `bench/bench.mjs` is reproducible, with raw data `result.json` and report `result.md`. README summary synced: preset count four→five (added the `harmony-chat-rampagemax` row to the mode table), and the summary benchmark figures updated to the post-padding 93.8-98.0%.

### 2026-08-18 — Added the Rampage Max preset (no token savings, quality first)

**The fifth conversation mode `harmony-chat-rampagemax`**, the opposite of promax—trades cache for quality; use with caution (high token consumption):

- **Runtime context enabled** (`includeRuntimeContext:true`), prefix varies dynamically with the session, low cache hit rate
- **Web fetch fully enabled** (`fetch:true`, search timeout relaxed to 30s), can fetch full page text for verification
- **Double verification + cross-checking on critical paths**; light tasks get no shortcuts, everything runs the full loop
- **Exhaustive pre-check scan**: namespace / wiring.id / system-prompt slots / settings-page order / tool names checked one by one
- **Full-Pro delegation**: subagents are always routed to deepseek-v4-pro, getting it right the first time
- **Built-in caution warning in the persona**: "May drain the entire account quota in one go; use only for hard debugging, cross-file refactoring, or the final check before delivery"

**Measured loop**: YAML parsing passes → synced the running copy → dsh restarted → `agentPreset.list` shows "HarmonyOS Rampage Max loaded, broken: none" → `agentPreset.read` returns the full 7409-character text including the caution warning / quality-first / double / exhaustive / delegation.

### 2026-08-18 — Hexagon ProMax: delivery discipline upgrade

**promax's persona block was rewritten into six hard rules** (task tiering / pre-check / implementation / integration loop / verify before claiming done / delegation), all static text, no dynamic content injected, cache hit rate unaffected. The core is writing "integration loop" and "verify before claiming done" as an unskippable mechanical checklist: delivery = files written + node_modules symlinks + restart + boot verification + live test.

**Trigger**: the measured test of using promax to write the Arknights operator character plugin (dsh-arknights-persona). Result—code delivery 9/10 (zero syntax errors, all APIs correct, idiomatic framework), but the integration loop was only 6/10 (symlink not created, no restart, no boot verification, no live test). Conclusion: **the gap is in finishing discipline, not intelligence**, so each shortfall became a rule in the persona. See "2.4 Hexagon ProMax" above.

### 2026-08-17 — Added the ops resident task steward mode + scheduled tasks

**New features**

- **The `harmony-chat-ops` resident background task steward preset**: an unattended task mode for HarmonyOS devices, pure JS with zero native dependencies. Three categories of duties—knowledge organization (read directory → extract → deduplicate → archive to `~/dsh-kb/`), batch file processing (rename/archive/deduplicate → manifest to `~/dsh-kb/logs/`), and scheduled tasks (standard cron expressions via `cron_create` + `schedule_create` every/at, executed and archived when idle). Things outside these three categories are first confirmed with the user.
- **`@deepseek-ai/dsh-tool-list` directory enumeration plugin**: dsh's fs service has no readdir, so the ops mode cannot discover directory contents. This adds a zero-dependency `list_dir` tool (`node:fs/promises`) supporting relative paths, file sizes, and a 200-entry limit.
- **`harmony.patch.yml` mounts dsh-schedule for scheduled tasks**: registers `schedule_create / schedule_list / schedule_delete` for the web session's root agent (the package ships with dsh's base installation); one-shot/periodic reminders auto-trigger when due, and the agent executes and archives them when idle.
- **Delegated subagents route to Pro**: overrides `tool-subagent`'s `agentOptions` entirely by id to `deepseek-v4-pro` (measured: agentOptions inside presets don't take effect; the profile-layer override is required). The flash main loop saves cost; complex subtasks go to Pro to be done right the first time, avoiding repeated trial-and-error round trips.

**Measured loop (verified on this machine)**

- Manual batch: an ops session enumerated 3 meeting notes in `~/dsh-kb-test/notes/` → read → deduplicated "budget ok" → archived to `~/dsh-kb/会议纪要/*.md` (with a source table).
- Scheduled: `schedule_create after_seconds: 60` auto-triggers when due, and the agent independently produces `~/dsh-kb/reports/notes-summary-*.md`; after a one-shot reminder executes, it no longer appears in `schedule_list`.
- Regression: the existing harmony-chat / pro / promax presets all load without errors and web stays UP; test data has been cleaned up.

**Fixes**

- Fixed the bug where creating new sessions failed: custom plugin package names referenced by presets must exist in both dsh's base `node_modules` and the profile-layer `node_modules` symlink layer (the host composition base resolves upward to `profiles/node_modules`); a missing symlink causes preset mount failure → `SessionCreateError`. Install steps are in "2.5" above. `dsh-tool-list` has been put in place on this dual path.

---

## Contributing

Co-creation welcome! Dev-group members can apply to become collaborators; anyone can contribute via Fork + PR.

- Guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- `main` is protected - PRs require review before merge.
