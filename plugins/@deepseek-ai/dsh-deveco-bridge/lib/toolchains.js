// Toolchain profiles for the DevEco toolchains installed on this machine.
//
// Two mutually-exclusive toolchains (see ~/MEMORY.md 2026-09-16):
//   api23 → ~/deveco/deveco_tools       hvigor 6.23.15 + HarmonyOS 6.1.0(23) SDK
//           only accepts the legacy package format  "x.y.z(N)"   e.g. "6.1.0(23)"
//   api26 → ~/deveco/suite/tools-api26  hvigor 6.26.4  + HarmonyOS 26.0.0  SDK
//           only accepts the bare format             "x.y.z"     e.g. "26.0.0"
// A project whose compileSdkVersion/targetSdkVersion is "26.0.0" can only be built by
// the API 26 toolchain (writing "26.0.0(26)" into it makes hvigor 6.26.4 fail with
// 00303313, and writing "26.0.0" makes hvigor 6.23.15 fail with 00306042), so the
// plugin auto-detects the requirement from build-profile.json5 and picks accordingly.
import { existsSync } from "node:fs";
import { copyFile, readFile, rm, writeFile } from "node:fs/promises";
import { resolve as resolvePath } from "node:path";

const HOME = process.env.HOME ?? "";

const PRESETS = {
  api23: {
    id: "api23",
    apiVersion: 23,
    label: "HarmonyOS 6.1.0(23)",
    root: `${HOME}/deveco/deveco_tools`,
    nodeHome: `${HOME}/deveco/deveco_tools/node`,
    versionFormat: "msf"
  },
  api26: {
    id: "api26",
    apiVersion: 26,
    label: "HarmonyOS 26.0.0 (API 26)",
    root: `${HOME}/deveco/suite/tools-api26`,
    // the API 26 command-line package ships no node for aarch64; the HNP node from
    // deveco_tools (system-signed, allowed to exec) is reused, as ~/bin/deveco-api26.sh does.
    nodeHome: `${HOME}/deveco/deveco_tools/node`,
    versionFormat: "bare"
  }
};

export const TOOLCHAIN_IDS = ["api23", "api26"];

/** Default toolchain when nothing is detected: honour DEVECO_TOOLCHAIN, else api23. */
export const DEFAULT_TOOLCHAIN_ID =
  process.env.DEVECO_TOOLCHAIN === "api26" ? "api26" : "api23";

/** Resolve a toolchain profile to concrete paths (env-overridable, per-toolchain first). */
export function resolveToolchain(id = DEFAULT_TOOLCHAIN_ID) {
  const key = PRESETS[id] ? id : DEFAULT_TOOLCHAIN_ID;
  const preset = PRESETS[key];
  const upper = key.toUpperCase();
  const root = process.env[`DEVECO_${upper}_ROOT`] ?? preset.root;
  const nodeHome =
    process.env[`DEVECO_${upper}_NODE_HOME`] ?? process.env.DEVECO_NODE_HOME ?? preset.nodeHome;
  const sdkHome =
    process.env[`DEVECO_${upper}_SDK_HOME`] ?? process.env.DEVECO_SDK_HOME ?? `${root}/sdk`;
  const hvigorHome =
    process.env[`DEVECO_${upper}_HVIGOR_HOME`] ?? process.env.DEVECO_HVIGOR_HOME ?? `${root}/hvigor`;
  return {
    id: key,
    apiVersion: preset.apiVersion,
    label: preset.label,
    versionFormat: preset.versionFormat,
    root,
    nodeHome,
    sdkHome,
    hvigorHome,
    nodeBin: `${nodeHome}/bin/node`,
    hvigorJs: `${hvigorHome}/bin/hvigorw.js`,
    ohpmBin: process.env.DEVECO_OHPM_BIN ?? `${root}/ohpm/bin/ohpm`,
    versionFile: `${root}/version.txt`,
    // hdc is a device tool: independent of the SDK level, keep the known-good one.
    hdcBin:
      process.env.DEVECO_HDC_BIN ??
      `${HOME}/deveco/deveco_tools/sdk/default/openharmony/toolchains/hdc`,
    pythonBin: process.env.DEVECO_PYTHON_BIN ?? "python3"
  };
}

/** Environment for spawning a toolchain binary (NODE_HOME / DEVECO_SDK_HOME / PATH ...). */
export function buildEnv(toolchain = resolveToolchain()) {
  const env = { ...process.env };
  env.NODE_HOME = toolchain.nodeHome;
  env.DEVECO_SDK_HOME = toolchain.sdkHome;
  env.HVIGOR_USER_HOME = env.HVIGOR_USER_HOME || `${HOME}/.hvigor`;
  env.PATH = `${toolchain.nodeHome}/bin:${toolchain.root}/bin:${env.PATH || ""}`;
  if (toolchain.id === "api26") {
    env.OHPM_HOME = env.OHPM_HOME || `${toolchain.root}/ohpm`;
    // node 22 needs this to require the newer ESM deps of the ohpm 26 / hvigor 6.26 runtime.
    env.NODE_OPTIONS = `${env.NODE_OPTIONS ?? ""} --experimental-require-module`.trim();
  }
  return env;
}

/** Is this toolchain actually installed (node + hvigor + sdk present)? */
export function isToolchainAvailable(toolchain) {
  return (
    existsSync(toolchain.nodeBin) &&
    existsSync(toolchain.hvigorJs) &&
    existsSync(toolchain.sdkHome)
  );
}

/** Parse the `apiVersion : NN` / `hvigor : x.y.z` lines of a toolchain version.txt. */
export function parseToolchainVersion(text) {
  const api = /^apiVersion\s*:\s*(\d+)/m.exec(text);
  const hvigor = /^hvigor\s*:\s*(\S+)/m.exec(text);
  const sdk = /^HarmonyOS SDK\s*:\s*(.+)$/m.exec(text);
  return {
    apiVersion: api ? Number(api[1]) : null,
    hvigorVersion: hvigor ? hvigor[1] : null,
    sdk: sdk ? sdk[1].trim() : null
  };
}

/** Probe every known toolchain: existence, version file, declared API level. */
export async function listToolchains() {
  const out = [];
  for (const id of TOOLCHAIN_IDS) {
    const tc = resolveToolchain(id);
    const text = await readFile(tc.versionFile, "utf8").catch(() => null);
    const meta = text ? parseToolchainVersion(text) : {};
    out.push({ ...tc, available: isToolchainAvailable(tc), installed: text != null, ...meta });
  }
  return out;
}

/**
 * Parse a SDK version string in either accepted format.
 *   "26.0.0"     → bare, API 26 (HarmonyOS >= 26 scheme, major == API level)
 *   "6.1.0(23)"  → legacy MSF, API 23
 *   "26.0.0(26)" → Studio format: hvigor 6.26.4 rejects it (00303313), needs normalizing
 */
export function parseSdkVersion(value) {
  const raw = String(value ?? "").trim();
  if (raw === "") return { raw, apiVersion: null, format: "empty" };
  const msf = /^(\d+)\.\d+\.\d+\((\d+)\)$/.exec(raw);
  if (msf) {
    return { raw, apiVersion: Number(msf[2]), format: Number(msf[2]) >= 26 ? "msf-api26" : "msf" };
  }
  const bare = /^(\d+)\.(\d+)\.(\d+)$/.exec(raw);
  if (bare) {
    const major = Number(bare[1]);
    return {
      raw,
      apiVersion: major >= 26 ? major : null,
      // a bare "6.1.0" is invalid for hvigor 6.23.15 (00306042) and not an API 26 marker
      format: major >= 26 ? "bare" : "bare-legacy"
    };
  }
  return { raw, apiVersion: null, format: "unknown" };
}

/** Read a project's declared SDK levels from build-profile.json5 (products[]). */
export async function detectProjectApi(project) {
  const path = resolvePath(project, "build-profile.json5");
  const text = await readFile(path, "utf8").catch(() => null);
  if (text == null) {
    return { found: false, path, versions: [], apiVersion: null, format: null, needsApi26: false };
  }
  const versions = [];
  const re = /"(compileSdkVersion|targetSdkVersion|compatibleSdkVersion)"\s*:\s*"([^"]*)"/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    versions.push({ field: m[1], value: m[2], ...parseSdkVersion(m[2]) });
  }
  const sdkFields = versions.filter(
    (v) => v.field === "compileSdkVersion" || v.field === "targetSdkVersion"
  );
  const highest = sdkFields.reduce(
    (acc, v) => (v.apiVersion != null && (acc == null || v.apiVersion > acc.apiVersion) ? v : acc),
    null
  );
  const apiVersion = highest?.apiVersion ?? null;
  const needsApi26 = sdkFields.some((v) => (v.apiVersion ?? 0) >= 26);
  return {
    found: true,
    path,
    versions,
    apiVersion,
    format: highest?.format ?? null,
    raw: highest?.raw ?? null,
    compileSdkVersion: sdkFields.find((v) => v.field === "compileSdkVersion")?.raw ?? null,
    targetSdkVersion: sdkFields.find((v) => v.field === "targetSdkVersion")?.raw ?? null,
    // "26.0.0(26)" is Studio's spelling: valid for the IDE, rejected by hvigor 6.26.4
    needsNormalize: sdkFields.some((v) => v.format === "msf-api26"),
    needsApi26
  };
}

/**
 * Pick the toolchain for a project. `requested` is "auto" | "23" | "26" | "api23" | "api26".
 * Returns { toolchain, detection, reason } and never throws.
 */
export async function selectToolchain(project, requested = "auto") {
  const detection = project ? await detectProjectApi(project) : null;
  let id;
  let reason;
  if (requested && requested !== "auto") {
    const wanted = String(requested).replace(/^api/i, "");
    id = wanted === "26" ? "api26" : "api23";
    reason = `调用方显式指定 API ${wanted}`;
  } else if (detection?.needsApi26) {
    id = "api26";
    reason = `工程 build-profile.json5 声明 ${detection.raw ?? "API 26"}（compile/targetSdkVersion ≥ 26）`;
  } else if (detection?.found && detection.apiVersion != null) {
    id = "api23";
    reason = `工程声明 API ${detection.apiVersion}（< 26）`;
  } else if (detection?.found) {
    id = DEFAULT_TOOLCHAIN_ID;
    reason = `工程 SDK 版本写法无法解析（compile=${detection.compileSdkVersion} target=${detection.targetSdkVersion}），回退默认工具链`;
  } else {
    id = DEFAULT_TOOLCHAIN_ID;
    reason = project ? "工程没有 build-profile.json5，使用默认工具链" : "未提供工程路径，使用默认工具链";
  }
  const toolchain = resolveToolchain(id);
  if (!isToolchainAvailable(toolchain)) {
    const fallback = TOOLCHAIN_IDS.map(resolveToolchain).find(isToolchainAvailable);
    return {
      toolchain: fallback ?? toolchain,
      requested: id,
      fallbackFrom: fallback && fallback.id !== toolchain.id ? toolchain.id : null,
      detection,
      reason: `${reason}；但 ${toolchain.id} 工具链未安装（${toolchain.root}）`,
      missing: !fallback
    };
  }
  return { toolchain, requested: id, fallbackFrom: null, detection, reason, missing: false };
}

const API26_VERSION = "26.0.0";

/**
 * Rewrite a project to the API 26 spelling hvigor 6.26.4 accepts (`"26.0.0"`, no parens)
 * and point local.properties at the API 26 sdk/node. Mirrors ~/bin/api26-project.sh,
 * including the `.bak-api26` backup (which is the pre-API26 = API23 config).
 */
export async function normalizeProjectToApi26(project, { clean = false } = {}) {
  const bp = resolvePath(project, "build-profile.json5");
  const lp = resolvePath(project, "local.properties");
  const original = await readFile(bp, "utf8").catch(() => null);
  if (original == null) throw new Error(`build-profile.json5 not found in ${project}`);

  const notes = [];
  const bpBackup = `${bp}.bak-api26`;
  if (!existsSync(bpBackup)) {
    await copyFile(bp, bpBackup);
    notes.push(`备份 ${bpBackup}`);
  }

  const lpOriginal = await readFile(lp, "utf8").catch(() => null);
  const lpBackup = `${lp}.bak-api26`;
  // only keep a backup when this local.properties predates our own rewrite, otherwise
  // restoring would write the API 26 paths back in.
  if (lpOriginal != null && !existsSync(lpBackup) && !lpOriginal.includes("tools-api26")) {
    await copyFile(lp, lpBackup);
    notes.push(`备份 ${lpBackup}`);
  }

  let next = original
    .replace(/"compileSdkVersion"\s*:\s*"[^"]*",?[ \t]*\n?[ \t]*/g, "")
    .replace(/"targetSdkVersion"\s*:\s*"[^"]*"/g, `"targetSdkVersion": "${API26_VERSION}"`);
  if (!next.includes('"targetSdkVersion"')) {
    throw new Error("build-profile.json5 里没有 targetSdkVersion，无法自动切换到 API 26");
  }
  next = next.replace(
    `"targetSdkVersion": "${API26_VERSION}"`,
    `"compileSdkVersion": "${API26_VERSION}",\n        "targetSdkVersion": "${API26_VERSION}"`
  );

  const changed = next !== original;
  if (changed) await writeFile(bp, next, "utf8");

  const sdkHome = resolveToolchain("api26").sdkHome;
  const nodeHome = resolveToolchain("api26").nodeHome;
  const lpWanted = `sdk.dir=${sdkHome}\nnodejs.dir=${nodeHome}\n`;
  const lpChanged = lpOriginal !== lpWanted;
  if (lpChanged) await writeFile(lp, lpWanted, "utf8");

  if (clean) {
    for (const dir of [".hvigor", "build", "entry/build"]) {
      await rm(resolvePath(project, dir), { recursive: true, force: true }).catch(() => {});
    }
  }
  return {
    ok: true,
    changed,
    localPropertiesChanged: lpChanged,
    backups: notes,
    version: API26_VERSION
  };
}

/** Restore a project switched by normalizeProjectToApi26(): back to the API23 config. */
export async function restoreProjectToApi23(project, { clean = true } = {}) {
  const bp = resolvePath(project, "build-profile.json5");
  const lp = resolvePath(project, "local.properties");
  const notes = [];
  const bpBackup = `${bp}.bak-api26`;
  const lpBackup = `${lp}.bak-api26`;
  if (existsSync(bpBackup)) {
    await copyFile(bpBackup, bp);
    notes.push(`还原 ${bp}`);
  }
  if (existsSync(lpBackup)) {
    await copyFile(lpBackup, lp);
    notes.push(`还原 ${lp}`);
  } else if (existsSync(lp)) {
    await rm(lp, { force: true });
    notes.push(`删除生成的 ${lp}`);
  }
  if (clean) {
    for (const dir of [".hvigor", "build", "entry/build"]) {
      await rm(resolvePath(project, dir), { recursive: true, force: true }).catch(() => {});
    }
  }
  if (notes.length === 0) notes.push("没有找到 .bak-api26 备份，工程未被本工具切换过");
  return { ok: true, notes };
}

/** Read the first module / target / device type of a project (build defaults). */
export async function detectBuildDefaults(project) {
  const bp = await readFile(resolvePath(project, "build-profile.json5"), "utf8").catch(() => "");
  const module = /"modules"\s*:\s*\[[\s\S]*?"name"\s*:\s*"([^"]+)"/.exec(bp)?.[1] ?? "entry";
  const target =
    /"targets"\s*:\s*\[[\s\S]*?"name"\s*:\s*"([^"]+)"/.exec(bp)?.[1] ?? "default";
  const product = /"products"\s*:\s*\[[\s\S]*?"name"\s*:\s*"([^"]+)"/.exec(bp)?.[1] ?? "default";
  const mod = await readFile(
    resolvePath(project, module, "src", "main", "module.json5"),
    "utf8"
  ).catch(() => "");
  const deviceTypes = [...mod.matchAll(/"deviceTypes"\s*:\s*\[([^\]]*)\]/g)]
    .flatMap((m) => m[1].split(",").map((s) => s.trim().replace(/["']/g, "")).filter(Boolean));
  // hvigor's requiredDeviceType picks the device profile to build for; the value verified
  // on this 2in1 PC is "2in1" even when the module lists phone/tablet only, so that is the
  // default and callers override it per project via the deviceType parameter.
  return { module, target, product, deviceTypes, deviceType: "2in1" };
}
