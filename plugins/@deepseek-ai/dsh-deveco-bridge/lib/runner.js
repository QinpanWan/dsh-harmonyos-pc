// Pure-JS subprocess runner for the DevEco toolchain. Uses node:child_process
// execFile so no native addon is ever loaded (HarmonyOS cannot run ELF/.node);
// injects the DevEco env (NODE_HOME / DEVECO_SDK_HOME / HVIGOR_USER_HOME).
import { execFile } from "node:child_process";
import { buildEnv as envForToolchain, resolveToolchain } from "./toolchains.js";

// Tool paths are env-configurable so the plugin is portable across machines:
// set DEVECO_TOOLS_HOME once to the dir that contains node/hvigor/sdk/ohpm, or
// override each bin individually. Defaults to $HOME/deveco/deveco_tools.
const home = process.env.HOME ?? "";
const toolsHome = process.env.DEVECO_TOOLS_HOME ?? `${home}/deveco/deveco_tools`;

// Legacy API 23 profile (kept as the default export for backwards compatibility).
// Toolchain-aware callers should resolve a toolchain via ./toolchains.js instead.
export const TOOLS = {
  nodeHome: process.env.DEVECO_NODE_HOME ?? `${toolsHome}/node`,
  hvigorHome: process.env.DEVECO_HVIGOR_HOME ?? `${toolsHome}/hvigor`,
  sdkHome: process.env.DEVECO_SDK_HOME ?? `${toolsHome}/sdk`,
  ohpmBin: process.env.DEVECO_OHPM_BIN ?? `${toolsHome}/ohpm/bin/ohpm`,
  hdcBin: process.env.DEVECO_HDC_BIN ?? `${toolsHome}/sdk/default/openharmony/toolchains/hdc`,
  pythonBin: process.env.DEVECO_PYTHON_BIN ?? `python3`,
};

const DEFAULT_TIMEOUT_MS = 600_000;
const TAIL_LINES = 200;
const MAX_BUFFER = 16 * 1024 * 1024;

/**
 * Env for a spawn. Pass `toolchain` (an id like "api26" or a resolved profile from
 * ./toolchains.js) to inject that toolchain's NODE_HOME / DEVECO_SDK_HOME / PATH;
 * defaults to the API 23 layout through the legacy TOOLS paths.
 */
function buildEnv(toolchain) {
  if (toolchain) {
    const resolved = typeof toolchain === "string" ? resolveToolchain(toolchain) : toolchain;
    return envForToolchain(resolved);
  }
  const env = { ...process.env };
  env.NODE_HOME = TOOLS.nodeHome;
  env.DEVECO_SDK_HOME = TOOLS.sdkHome;
  env.HVIGOR_USER_HOME = env.HVIGOR_USER_HOME || `${home}/.hvigor`;
  env.PATH = `${TOOLS.nodeHome}/bin:${env.PATH || ""}`;
  return env;
}

/**
 * Run a tool and resolve a normalized result object. Never rejects for a
 * non-zero exit or a timeout; only a catastrophic spawn failure throws.
 */
export function runCommand(file, args = [], { cwd, timeoutMs = DEFAULT_TIMEOUT_MS, toolchain } = {}) {
  return new Promise((resolve) => {
    const startedAt = Date.now();
    execFile(file, args, {
      cwd,
      env: buildEnv(toolchain),
      maxBuffer: MAX_BUFFER,
      timeout: timeoutMs,
    }, (error, stdout, stderr) => {
      const elapsedMs = Date.now() - startedAt;
      const output = `${stdout ?? ""}${stderr ?? ""}`;
      const lines = output.split("\n");
      const truncated = lines.length > TAIL_LINES;
      const body = truncated ? lines.slice(-TAIL_LINES).join("\n") : output;
      if (!error) {
        resolve({ exitCode: 0, timedOut: false, durationMs: elapsedMs, truncated, output: body });
        return;
      }
      const code = error.code;
      const timedOut = code === "ETIMEDOUT";
      if (code === "ENOENT") {
        resolve({ exitCode: 127, timedOut: false, durationMs: elapsedMs, truncated, output: `command not found: ${file}` });
        return;
      }
      resolve({ exitCode: timedOut ? 124 : (error.code ?? 1), timedOut, durationMs: elapsedMs, truncated, output: body });
    });
  });
}
