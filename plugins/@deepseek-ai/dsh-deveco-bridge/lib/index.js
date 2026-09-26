// dsh-deveco-bridge: HarmonyOS DevEco toolchain tools for dsh presets.
// Pure JS; drives hvigor/ohpm/hdc through node:child_process (see runner.js).
import { stat, readdir } from "node:fs/promises";
import { isAbsolute, resolve as resolvePath } from "node:path";
import { defineTool } from "@deepseek-ai/dsh-tools";
import { runCommand, TOOLS } from "./runner.js";
import {
  detectBuildDefaults,
  detectProjectApi,
  listToolchains,
  normalizeProjectToApi26,
  resolveToolchain,
  restoreProjectToApi23,
  selectToolchain
} from "./toolchains.js";

/** Cordis plugin name used by loader diagnostics. */
const name = "deveco-bridge";
/** Services required by the tools. */
const inject = ["tools"];

const PYTHON_BIN = TOOLS.pythonBin ?? "python3";

function formatResult(value) {
  const head =
    `${value.ok ? "OK" : "FAIL"} · exit ${value.exitCode} · ${value.durationMs}ms` +
    `${value.timedOut ? " · TIMED OUT" : ""}` +
    `${value.truncated ? " · (tail " + 200 + " lines)" : ""}`;
  const lines = [head, `cmd: ${value.command}`];
  if (value.output) lines.push("", "```", value.output, "```");
  return lines.join("\n");
}

const resultSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    ok: { type: "boolean", required: true },
    command: { type: "string", required: true },
    exitCode: { type: "integer", required: true },
    durationMs: { type: "integer", required: true },
    timedOut: { type: "boolean", required: true },
    truncated: { type: "boolean", required: true },
    output: { type: "string", required: true }
  }
};

function renderResult(_args, value) {
  return [{ type: "text", text: formatResult(value) }];
}

async function ensureProjectDir(requested, cwd) {
  const target = isAbsolute(requested) ? requested : resolvePath(cwd, requested);
  const s = await stat(target).catch(() => null);
  if (!s?.isDirectory()) {
    throw new Error(`project directory not found: ${target}`);
  }
  return target;
}

/** Locate a project's ohosTest test module (default 'entry', then any module). */
async function findTestModule(project) {
  const candidates = ["entry"];
  try {
    for (const ent of await readdir(project, { withFileTypes: true })) {
      if (ent.isDirectory()) candidates.push(ent.name);
    }
  } catch { /* ignore unreadable project */ }
  for (const mod of candidates) {
    const ohosTest = resolvePath(project, mod, "src", "ohosTest");
    const s = await stat(ohosTest).catch(() => null);
    if (s?.isDirectory()) return ohosTest;
  }
  return null;
}

function present(card, title, kind, rawInput) {
  return (args) => ({
    card,
    title,
    kind,
    ...(rawInput && args[rawInput] !== void 0 ? { rawInput: args[rawInput] } : {})
  });
}

/** Assemble a tool result from one or more sequential command steps. */
function assemble(label, steps) {
  const last = steps[steps.length - 1];
  const ok = steps.every((s) => s.exitCode === 0);
  const command = steps.map((s) => s.command).join(" && ");
  const output = steps
    .map((s, i) => (steps.length > 1 ? `$ ${s.command}\n` : "") + s.output)
    .join("\n---\n")
    .trim();
  return {
    ok,
    command: `${label}: ${command}`,
    exitCode: ok ? 0 : last.exitCode,
    durationMs: steps.reduce((a, s) => a + s.durationMs, 0),
    timedOut: steps.some((s) => s.timedOut),
    truncated: steps.some((s) => s.truncated),
    output
  };
}

/** Human-readable report of every installed toolchain, plus this project's choice. */
async function describeToolchains(project) {
  const list = await listToolchains();
  const lines = ["工具链:"];
  for (const tc of list) {
    const ver = [
      tc.hvigorVersion && `hvigor ${tc.hvigorVersion}`,
      tc.apiVersion != null && `API ${tc.apiVersion}`,
      tc.sdk
    ].filter(Boolean).join(" · ");
    lines.push(
      `- ${tc.id} ${tc.available ? "OK" : "缺失(未安装)"}  ${tc.label}` +
        `\n    root=${tc.root}` +
        `\n    ${ver || "(没有 version.txt)"}` +
        `\n    接受写法=${tc.versionFormat === "bare" ? '"x.y.z" 裸写法（如 "26.0.0"）' : '"x.y.z(N)"（如 "6.1.0(23)"）'}`
    );
  }
  if (project) {
    const det = await detectProjectApi(project);
    if (!det.found) {
      lines.push(`工程探测: 找不到 ${det.path}`);
    } else {
      const picked = await selectToolchain(project, "auto");
      lines.push(
        `工程探测: compileSdkVersion=${det.compileSdkVersion ?? "(缺)"} targetSdkVersion=${det.targetSdkVersion ?? "(缺)"}` +
          ` → API ${det.apiVersion ?? "?"}` +
          `\n  选用工具链: ${picked.toolchain.id}（${picked.reason}）` +
          (det.needsNormalize
            ? `\n  注意: 版本号写成了 "${det.raw}"（Studio 写法），hvigor 6.26.4 只认裸写法 "26.0.0"，dev_build 会先自动改写并备份 .bak-api26`
            : "") +
          (det.format === "bare-legacy"
            ? `\n  注意: 裸写法 "${det.raw}" 只对 API >= 26 成立，老 hvigor 会报 00306042`
            : "")
      );
    }
  }
  return lines.join("\n");
}

function apply(ctx) {
  const tools = [];

  tools.push(defineTool({
    name: "dev_toolchain",
    description: "Inspect or switch a project's HarmonyOS toolchain. action=status (default) reports every installed toolchain (api23 / api26), the project's declared compileSdkVersion/targetSdkVersion and which toolchain dev_build would pick. action=use-api26 rewrites build-profile.json5 to the API 26 spelling hvigor 6.26.4 requires (bare \"26.0.0\") and points local.properties at the API 26 sdk/node, keeping a .bak-api26 backup (= the previous API 23 config). action=restore puts that backup back. This is a read-only status by default; the two switch actions write project files.",
    parameters: {
      project: {
        type: "string",
        description: "Path to the HarmonyOS project directory (containing build-profile.json5). Relative paths resolve against the session working directory."
      },
      action: {
        type: "string",
        description: "status | use-api26 | restore (default status)."
      },
      clean: {
        type: "boolean",
        description: "Also delete .hvigor/build caches when switching (recommended after a toolchain change; the switch actions default to true)."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => false,
    presentCall: present("generic", "Inspect/switch DevEco toolchain", "write", "project"),
    async execute(args, exec) {
      const cwd = exec.agent?.session.header.cwd ?? process.cwd();
      const action = args.action ?? "status";
      const started = Date.now();
      const project = args.project ? await ensureProjectDir(args.project, cwd) : null;
      if (action === "status") {
        const report = await describeToolchains(project);
        return {
          ok: true,
          command: `dev_toolchain status${project ? ` (${project})` : ""}`,
          exitCode: 0,
          durationMs: Date.now() - started,
          timedOut: false,
          truncated: false,
          output:
            `${report}\n\n` +
            "提示: DevEco Studio GUI 走的是它自己内置的 SDK/工具链，本机 Studio 6.1.5.408 只带 API 23，" +
            "所以 API 26 工程在 GUI 里同步/构建必然报 00303168 / 00306042 —— API 26 的编译能力只能走这里（dev_build）或 ~/bin/hm-build.sh。"
        };
      }
      if (!project) {
        throw new Error("use-api26 / restore 需要 project 参数");
      }
      if (action === "use-api26") {
        const r = await normalizeProjectToApi26(project, { clean: args.clean ?? true });
        return {
          ok: true,
          command: `dev_toolchain use-api26 (${project})`,
          exitCode: 0,
          durationMs: Date.now() - started,
          timedOut: false,
          truncated: false,
          output: [
            `已把 ${project} 切到 API 26 工具链配置`,
            `compileSdkVersion/targetSdkVersion → "${r.version}"${r.changed ? "" : "（本来就是这个写法）"}`,
            `local.properties → API26 sdk/node${r.localPropertiesChanged ? "" : "（本来就是）"}`,
            ...r.backups,
            "下一步: dev_build project=<工程> （会自动选 api26 工具链）"
          ].join("\n")
        };
      }
      if (action === "restore") {
        const r = await restoreProjectToApi23(project, { clean: args.clean ?? true });
        return {
          ok: true,
          command: `dev_toolchain restore (${project})`,
          exitCode: 0,
          durationMs: Date.now() - started,
          timedOut: false,
          truncated: false,
          output: [
            `已还原 ${project} 的切换前配置`,
            ...r.notes,
            "注意: 若工程代码本身用了 API 26 能力（如 @kit.ArkUI 的 uiMaterial/systemMaterial），还原后命令行构建会失败，需要重新 dev_toolchain action=use-api26。"
          ].join("\n")
        };
      }
      throw new Error(`未知 action: ${action}（可用: status | use-api26 | restore）`);
    }
  }));

  tools.push(defineTool({
    name: "dev_environment",
    description: "Probe the local DevEco toolchains: node / hvigor / ohpm / hdc versions and the installed SDKs. This machine has two mutually exclusive toolchains — api23 (~/deveco/deveco_tools, hvigor 6.23.15, HarmonyOS 6.1.0(23), accepts only 'x.y.z(N)') and api26 (~/deveco/suite/tools-api26, hvigor 6.26.4, HarmonyOS 26.0.0, accepts only bare 'x.y.z'); whatever a project declares in build-profile.json5 decides which one it must use. Run this first, and pass project to also see which toolchain that project resolves to.",
    parameters: {
      project: {
        type: "string",
        description: "Optional HarmonyOS project directory to inspect: reports its compileSdkVersion/targetSdkVersion and the toolchain dev_build would pick for it."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => true,
    presentCall: present("generic", "Probe DevEco environment", "read"),
    async execute(args, exec) {
      const cwd = exec.agent?.session.header.cwd ?? process.cwd();
      const project = args.project ? await ensureProjectDir(args.project, cwd) : null;
      const report = await describeToolchains(project);
      const chosen = project
        ? (await selectToolchain(project, "auto")).toolchain
        : resolveToolchain();
      const probes = [
        { file: chosen.nodeBin, args: ["--version"], cmd: `node --version (${chosen.id})` },
        { file: chosen.nodeBin, args: [chosen.hvigorJs, "--version"], cmd: `node hvigorw.js --version (${chosen.id})` },
        { file: chosen.ohpmBin, args: ["--version"], cmd: `ohpm --version (${chosen.id})` },
        { file: TOOLS.hdcBin, args: ["list", "targets"], cmd: "hdc list targets" }
      ];
      const steps = [];
      for (const p of probes) {
        const r = await runCommand(p.file, p.args, { cwd, toolchain: chosen });
        steps.push({ ...r, command: p.cmd });
      }
      const result = assemble("dev_environment", steps);
      return { ...result, output: `${report}\n\n${result.output}` };
    }
  }));

  tools.push(defineTool({
    name: "dev_install_deps",
    description: "Install a HarmonyOS project's dependencies by running `ohpm install` in the project directory. Run this when a build fails because oh-package dependencies are missing or outdated.",
    parameters: {
      project: {
        type: "string",
        description: "Path to the HarmonyOS project directory (containing oh-package.json5). Relative paths resolve against the session working directory."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => false,
    presentCall: present("generic", "Install ohpm dependencies", "write", "project"),
    async execute(args, exec) {
      const cwd = exec.agent?.session.header.cwd ?? process.cwd();
      const project = await ensureProjectDir(args.project, cwd);
      const tc = (await selectToolchain(project, "auto")).toolchain;
      const r = await runCommand(tc.ohpmBin, ["install"], { cwd: project, toolchain: tc });
      return { ...r, ok: r.exitCode === 0, command: `ohpm install (in ${project}, ${tc.id})` };
    }
  }));

  tools.push(defineTool({
    name: "dev_build",
    description: "Build a HarmonyOS project with hvigor. Defaults to assembling the HAP (assembleHap). The toolchain is auto-detected from build-profile.json5: a project with compileSdkVersion/targetSdkVersion API >= 26 is built with the API 26 toolchain (hvigor 6.26.4), anything else with the API 23 one — the two are mutually exclusive, so a mismatch fails with 00306042/00303313/00303168. API 26 projects additionally need the bare version spelling, so dev_build rewrites compile/targetSdkVersion to \"26.0.0\" first (backup: build-profile.json5.bak-api26; skip with keepConfig). Use clean to force a full rebuild, mode=release for a signed release package, and installDeps to run `ohpm install` first. Reports the last 200 lines of the build log.",
    parameters: {
      project: {
        type: "string",
        description: "Path to the HarmonyOS project directory (containing build-profile.json5). Relative paths resolve against the session working directory."
      },
      task: {
        type: "string",
        description: "hvigor task to run (default assembleHap)."
      },
      mode: {
        type: "string",
        description: "Build mode: debug or release (maps to -p buildMode). Omit for hvigor default."
      },
      apiVersion: {
        type: "string",
        description: "Toolchain to use: auto (default, from build-profile.json5), 23 / api23, or 26 / api26. Only override to force a specific toolchain."
      },
      keepConfig: {
        type: "boolean",
        description: "API 26 only: do not rewrite build-profile.json5 to the bare \"26.0.0\" spelling. Set this when the file is already hand-tuned; the build then fails if the spelling is the Studio one."
      },
      deviceType: {
        type: "string",
        description: "API 26 only: requiredDeviceType passed to hvigor (default: the project's preferred deviceTypes entry, else 2in1)."
      },
      module: {
        type: "string",
        description: "API 26 only: module@target to build (default: first module/target of build-profile.json5, e.g. entry@default)."
      },
      product: {
        type: "string",
        description: "API 26 only: -p product (default: first product of build-profile.json5, usually default)."
      },
      clean: {
        type: "boolean",
        description: "Run `hvigorw clean` before the build task."
      },
      installDeps: {
        type: "boolean",
        description: "Run `ohpm install` before building."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => false,
    presentCall: present("generic", "Build HarmonyOS project", "write", "project"),
    async execute(args, exec) {
      const cwd = exec.agent?.session.header.cwd ?? process.cwd();
      const project = await ensureProjectDir(args.project, cwd);
      const task = args.task ?? "assembleHap";
      const selected = await selectToolchain(project, args.apiVersion ?? "auto");
      const tc = selected.toolchain;
      const notes = [
        `工具链: ${tc.id} — ${selected.reason}`,
        ...(selected.fallbackFrom ? [`注意: 请求的 ${selected.fallbackFrom} 未安装，已回退到 ${tc.id}`] : []),
        ...(selected.detection?.needsNormalize && args.keepConfig
          ? [`注意: build-profile.json5 用的是 "${selected.detection.raw}"（Studio 写法），hvigor 6.26.4 只认 "26.0.0"；本次按 keepConfig 未改写`]
          : [])
      ];
      const steps = [];
      if (args.installDeps) {
        const inst = await runCommand(tc.ohpmBin, ["install"], { cwd: project, toolchain: tc });
        steps.push({ ...inst, command: `ohpm install (in ${project})` });
      }

      const hvigorArgs = [...(args.clean ? ["clean"] : []), task];
      if (tc.id === "api26") {
        const defaults = await detectBuildDefaults(project);
        if (selected.detection?.needsNormalize && !args.keepConfig) {
          const normalized = await normalizeProjectToApi26(project, { clean: Boolean(args.clean) });
          notes.push(
            `已把 build-profile.json5 切成 API 26 写法 "${normalized.version}"` +
              `${normalized.changed ? "" : "（本来就是这个写法）"}` +
              `${normalized.backups.length ? `；${normalized.backups.join("；")}` : ""}`
          );
        }
        hvigorArgs.push(
          "--mode", "module",
          "-p", `module=${args.module ?? `${defaults.module}@${defaults.target}`}`,
          "-p", `requiredDeviceType=${args.deviceType ?? defaults.deviceType}`,
          "-p", `product=${args.product ?? defaults.product}`
        );
      }
      if (args.mode) hvigorArgs.push("-p", `buildMode=${args.mode}`);

      const build = await runCommand(tc.nodeBin, [tc.hvigorJs, ...hvigorArgs], {
        cwd: project,
        toolchain: tc,
        timeoutMs: 1_200_000
      });
      steps.push({
        ...build,
        command: `node hvigorw.js ${hvigorArgs.join(" ")} (in ${project}, ${tc.id})`
      });
      const result = assemble("dev_build", steps);
      return { ...result, output: `${notes.join("\n")}\n\n${result.output}` };
    }
  }));

  tools.push(defineTool({
    name: "dev_list_devices",
    description: "List connected HarmonyOS devices/emulators by running `hdc list targets`. Each line is a serial usable as the device argument for dev_deploy.",
    parameters: {},
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => true,
    presentCall: present("generic", "List connected devices", "read"),
    async execute(_args, _exec) {
      const r = await runCommand(TOOLS.hdcBin, ["list", "targets"], {});
      return { ...r, ok: r.exitCode === 0, command: "hdc list targets" };
    }
  }));

  tools.push(defineTool({
    name: "dev_deploy",
    description: "Install a built HAP onto a connected device and optionally launch its main ability. First device is chosen automatically unless device is given. Pass bundleName (and abilityName, default EntryAbility) to launch after install.",
    parameters: {
      hapPath: {
        type: "string",
        description: "Path to the .hap file to install (absolute, or relative to the session working directory)."
      },
      device: {
        type: "string",
        description: "Target device serial from `hdc list targets`. Defaults to the first connected device."
      },
      bundleName: {
        type: "string",
        description: "Bundle name to launch after install (e.g. com.example.app). Omit to only install."
      },
      abilityName: {
        type: "string",
        description: "Ability to launch (default EntryAbility)."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => false,
    presentCall: present("generic", "Deploy HAP to device", "write", "hapPath"),
    async execute(args, exec) {
      const cwd = exec.agent?.session.header.cwd ?? process.cwd();
      const hap = isAbsolute(args.hapPath) ? args.hapPath : resolvePath(cwd, args.hapPath);
      const s = await stat(hap).catch(() => null);
      if (!s?.isFile()) throw new Error(`hap file not found: ${hap}`);

      const targets = await runCommand(TOOLS.hdcBin, ["list", "targets"], {});
      const lines = (targets.output ?? "")
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l.length > 0 && !l.startsWith("["));
      const device = args.device ?? lines[0];
      if (!device) {
        throw new Error("no connected device; run dev_list_devices or connect a device via hdc");
      }

      const steps = [{ ...targets, command: "hdc list targets" }];
      const inst = await runCommand(TOOLS.hdcBin, ["-t", device, "install", hap], {});
      steps.push({ ...inst, command: `hdc -t ${device} install ${hap}` });
      if (args.bundleName) {
        const ability = args.abilityName ?? "EntryAbility";
        const start = await runCommand(
          TOOLS.hdcBin,
          ["-t", device, "shell", "aa", "start", "-b", args.bundleName, "-a", ability],
          {}
        );
        steps.push({ ...start, command: `hdc -t ${device} shell aa start -b ${args.bundleName} -a ${ability}` });
      }
      return assemble("dev_deploy", steps);
    }
  }));

  tools.push(defineTool({
    name: "dev_test",
    description:
      "Run Hypium tests for a HarmonyOS project. Two modes: 'xdevice' drives the installed DevEco Testing Hypium (Python `python3 -m xdevice run`) against a connected device for UI/automation tests; 'hvigor' runs the project-local Hypium unit tests via `node hvigorw.js test` (the in-project @ohos/hypium module). 'auto' (default) uses xdevice when a testlist/testfile/testcase/run config is supplied, otherwise falls back to hvigor when an ohosTest test module exists. For xdevice pass device to pick a serial from dev_list_devices; reportPath is where the report is written (default <project>/test-reports).",
    parameters: {
      project: {
        type: "string",
        description: "Path to the HarmonyOS project directory (containing build-profile.json5). Relative paths resolve against the session working directory."
      },
      mode: {
        type: "string",
        description: "Test mode: auto (default), xdevice, or hvigor."
      },
      testlist: {
        type: "string",
        description: "xdevice test list file path (one test case per line), e.g. test/testlist.txt."
      },
      config: {
        type: "string",
        description: "xdevice config file path (device/user configuration XML), e.g. test/xdevice_config.xml."
      },
      testcase: {
        type: "string",
        description: "A single xdevice test case name (e.g. entry_test_Example). Mutually exclusive with testlist/testfile."
      },
      testfile: {
        type: "string",
        description: "xdevice test list file path (-tf), e.g. test/resource/xxx.txt."
      },
      device: {
        type: "string",
        description: "Target device serial from dev_list_devices. Defaults to the first connected device."
      },
      reportPath: {
        type: "string",
        description: "Directory for test reports. Defaults to <project>/test-reports."
      },
      resourcePath: {
        type: "string",
        description: "xdevice resource path (-respath) for resources the tests need."
      },
      testcasesPath: {
        type: "string",
        description: "xdevice test cases path (-tcpath), usually the built testcases directory."
      },
      task: {
        type: "string",
        description: "hvigor test task name. Default 'test' (runs the @ohos/hypium unit tests)."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => false,
    presentCall: present("generic", "Run Hypium tests", "write", "project"),
    async execute(args, exec) {
      const cwd = exec.agent?.session.header.cwd ?? process.cwd();
      const project = args.project ? await ensureProjectDir(args.project, cwd) : cwd;
      const mode = args.mode ?? "auto";
      const hasXdeviceSource = Boolean(args.testlist || args.testfile || args.testcase || args.config);

      const resolveWithin = (p) => {
        if (!p) return undefined;
        return isAbsolute(p) ? p : resolvePath(project, p);
      };

      // xdevice mode: the installed DevEco Testing Hypium (Python) drives a connected device.
      if (mode === "xdevice" || (mode === "auto" && hasXdeviceSource)) {
        if (!args.testlist && !args.testfile && !args.testcase) {
          return {
            ok: false,
            command: "dev_test(xdevice)",
            exitCode: 1,
            durationMs: 0,
            timedOut: false,
            truncated: false,
            output: "xdevice 模式需要指定 testlist / testfile / testcase 之一作为测试用例来源。"
          };
        }

        const targets = await runCommand(TOOLS.hdcBin, ["list", "targets"], {});
        const lines = (targets.output ?? "")
          .split("\n")
          .map((l) => l.trim())
          .filter((l) => l.length > 0 && !l.startsWith("["));
        const device = args.device ?? lines[0];
        if (!device) {
          return {
            ok: false,
            command: "dev_test(xdevice): hdc list targets",
            exitCode: 1,
            durationMs: 0,
            timedOut: false,
            truncated: false,
            output: "没有检测到已连接设备。先运行 dev_list_devices 查看，或通过 hdc 连接设备（USB / 无线调试）后再跑测试。"
          };
        }

        const report = resolveWithin(args.reportPath) ?? resolvePath(project, "test-reports");
        const xargs = ["-m", "xdevice", "run"];
        if (args.testlist) xargs.push("-l", resolveWithin(args.testlist));
        if (args.testfile) xargs.push("-tf", resolveWithin(args.testfile));
        if (args.testcase) xargs.push("-tc", args.testcase);
        if (args.config) xargs.push("-c", resolveWithin(args.config));
        if (args.resourcePath) xargs.push("-respath", resolveWithin(args.resourcePath));
        if (args.testcasesPath) xargs.push("-tcpath", resolveWithin(args.testcasesPath));
        xargs.push("-sn", device, "-rp", report);

        const r = await runCommand(PYTHON_BIN, xargs, { cwd: project, timeoutMs: 1_200_000 });
        const srcFlag = args.testlist ? `-l ${resolveWithin(args.testlist)}`
          : args.testfile ? `-tf ${resolveWithin(args.testfile)}`
          : `-tc ${args.testcase}`;
        const cfg = args.config ? ` -c ${resolveWithin(args.config)}` : "";
        return {
          ...r,
          ok: r.exitCode === 0,
          command: `python3 -m xdevice run ${srcFlag}${cfg} -sn ${device} -rp ${report}`
        };
      }

      // 'auto' without an xdevice source: only proceed if a project-local @ohos/hypium test module exists.
      if (mode === "auto" && !hasXdeviceSource) {
        const ohosTest = await findTestModule(project);
        if (!ohosTest) {
          return {
            ok: false,
            command: "dev_test(auto)",
            exitCode: 1,
            durationMs: 0,
            timedOut: false,
            truncated: false,
            output: "未找到测试来源。提供 testlist / testfile / testcase / config（xdevice UI 测试），或在工程里新增 src/ohosTest 模块（@ohos/hypium 单测）后再跑。"
          };
        }
      }

      // hvigor mode: project-local @ohos/hypium unit tests.
      const task = args.task ?? "test";
      const tc = (await selectToolchain(project, "auto")).toolchain;
      const build = await runCommand(tc.nodeBin, [tc.hvigorJs, task], {
        cwd: project,
        toolchain: tc,
        timeoutMs: 1_200_000
      });
      return {
        ...build,
        ok: build.exitCode === 0,
        command: `node hvigorw.js ${task} (in ${project}, ${tc.id})`
      };
    }
  }));

  tools.push(defineTool({
    name: "dev_code",
    description:
      "Delegate a self-contained sub-task to the locally running DevEco Code agent (OpenCode web server, default http://127.0.0.1:4096, override with DEVECO_WEB_BASE). DevEco Code runs its own agentic loop (tools + reasoning) on a separate model and returns a final text answer. Use it for a well-scoped sub-task you would otherwise hand to a sub-agent: it offloads the work and its context off this session. Delegations are serialized (one at a time). The sub-agent has no memory of this conversation, so put ALL needed context (file paths, constraints, expected output) into `task`. model selects what DevEco Code requests (default deepseek-v4-pro; deepseek-v4-flash-vision-exp is cheaper and faster for small tasks). The agent loop keeps the connection open until it fully finishes: simple tasks take seconds, but multi-step ones (network downloads, diagnostics) routinely take minutes. The wait is bounded by DEVECO_TIMEOUT_MS (default 900000 = 15 min); keep `task` focused to avoid long stalls.",
    parameters: {
      task: {
        type: "string",
        description: "Complete, self-contained sub-task for the DevEco Code agent. Include all context, file paths, constraints and the expected output format. The sub-agent has no access to this conversation."
      },
      model: {
        type: "string",
        description: "Model DevEco Code should request. Default deepseek-v4-pro. Use deepseek-v4-flash-vision-exp for cheap, small sub-tasks."
      }
    },
    output: {
      schema: resultSchema,
      render: renderResult
    },
    isConcurrencySafe: () => false,
    presentCall: present("generic", "Delegate to DevEco Code agent", "write", "task"),
    async execute(args, _exec) {
      const base = (process.env.DEVECO_WEB_BASE ?? "http://127.0.0.1:4096").replace(/\/+$/, "");
      const headers = { "content-type": "application/json" };
      const model = args.model ?? "deepseek-v4-pro";
      const timeoutMs = Number(process.env.DEVECO_TIMEOUT_MS ?? 900000);
      const t0 = Date.now();
      const probe = await fetch(`${base}/session`, {
        method: "POST", headers, body: "{}"
      }).catch(() => null);
      if (!probe?.ok) {
        return {
          ok: false, command: `POST ${base}/session`, exitCode: 1,
          durationMs: Date.now() - t0, timedOut: false, truncated: false,
          output: `DevEco Code web 服务不可访问(${base})。请先启动 DevEco Code(127.0.0.1:4096) 再试。`
        };
      }
      const { id } = await probe.json();
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      let res, text = "", body = null, aborted = false;
      try {
        res = await fetch(`${base}/session/${id}/message`, {
          method: "POST",
          headers,
          body: JSON.stringify({
            parts: [{ type: "text", text: args.task }],
            info: { providerID: "deepseek", model }
          }),
          signal: controller.signal
        });
        text = await res.text();
        try { body = JSON.parse(text); } catch { body = null; }
      } catch (e) {
        aborted = controller.signal.aborted;
        if (!aborted) throw e;
      } finally {
        clearTimeout(timer);
      }
      const ms = Date.now() - t0;
      if (aborted) {
        return { ok: false, command: `POST ${base}/session/${id}/message`, exitCode: 1, durationMs: ms, timedOut: true, truncated: false, output: `DevEco Code ${Math.round(timeoutMs / 60000)} 分钟内未返回(超时中止)。` };
      }
      if (!res?.ok || body == null) {
        return { ok: false, command: `POST ${base}/session/${id}/message`, exitCode: res?.status ?? 1, durationMs: ms, timedOut: false, truncated: false, output: `DevEco Code 调用失败(HTTP ${res?.status ?? "?"}): ${(text || "无响应").slice(0, 500)}` };
      }
      const texts = (body.parts ?? [])
        .filter((p) => p.type === "text")
        .map((p) => p.text ?? "")
        .join("\n")
        .trim();
      if (texts.length === 0) {
        return { ok: false, command: `POST ${base}/session/${id}/message`, exitCode: 1, durationMs: ms, timedOut: false, truncated: false, output: "DevEco Code 未返回文本结果(parts 中没有 text)。" };
      }
      const cost = body.info?.cost;
      const total = body.info?.tokens?.total;
      const meta = cost !== void 0 ? `\n\n[dev_code · ${model} · session ${id.slice(0, 8)} · ${ms}ms · cost ¥${Number(cost).toFixed(4)} · ${total ?? "?"} tok]` : "";
      return { ok: true, command: `dev_code → ${model} (session ${id.slice(0, 8)})`, exitCode: 0, durationMs: ms, timedOut: false, truncated: false, output: texts + meta };
    }
  }));

  for (const tool of tools) ctx.tools.register(tool);
  console.error(`[deveco-bridge] registered ${tools.length} tools: ${tools.map((t) => t.name).join(", ")}`);
}

export { apply, inject, name };
