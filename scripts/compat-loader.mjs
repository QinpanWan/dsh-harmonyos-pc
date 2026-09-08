// ESM loader for node v22 (HarmonyOS) that polyfills node-24-only builtin
// named exports missing on this runtime, so dsh can boot.
//
// Strategy: a `resolve` hook rewrites top-level imports of `node:zlib` /
// `node:module` (from userland modules) into a distinct `?compat` URL. The
// matching `load` hook serves a wrapper module that re-exports the REAL builtin
// (`export * from 'node:zlib'`, whose parent is a `node:` URL so it is NOT
// rewritten -> genuine builtin) plus the extra named exports. This avoids the
// self-referential-wrapper problem that breaks `export *` re-exports.
//
// zstd decompression (node-24 API missing on v22) is backed by the pure-JS
// `fzstd` package so dsh can read the existing .jsonl.zstd sessions it creates.
'use strict';

const COMPAT_NAMES = new Set(['node:zlib', 'node:module']);
const DSH_ROOT = 'file:///storage/Users/currentUser/dsh-test/';

export function resolve(specifier, context, nextResolve) {
  const parent = context.parentURL || '';
  // fs-ext is a native addon (no HarmonyOS build; flock is only used for a
  // cross-process lease that a single-process deployment never contends on).
  if (specifier === 'fs-ext') return { url: DSH_ROOT + 'fs-ext?compat', shortCircuit: true };
  if (COMPAT_NAMES.has(specifier) && !parent.startsWith('node:')) {
    return { url: `${specifier}?compat`, shortCircuit: true };
  }
  return nextResolve(specifier, context);
}

// zstd decode is backed by pure-JS fzstd so dsh can read existing .jsonl.zstd
// sessions (encoded by native zstd, which the WASM codec cannot decode).
// zstd ENCODE is backed by the WASM zstd-codec, which also makes new-session
// writes work on this v22 build (no native zstd). dsh wraps the one-shot API
// through `promisify`, so the functions MUST be callback-style `(input, opts, cb)`.
// The sync decoder and the private-stream probe route to the same fzstd decode.
const ZLIB_SOURCE = `
import { createRequire } from 'node:module';
import { Transform } from 'node:stream';
import * as _zlib from 'node:zlib';
const _require = createRequire('${DSH_ROOT}');
const _fzstd = _require('fzstd');

export * from 'node:zlib';
export default _zlib;

function _decode(input) {
  const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input;
  return Buffer.from(_fzstd.decompress(buf));
}

let _codecPromise = null;
function _codec() {
  if (!_codecPromise) {
    _codecPromise = new Promise((resolve) => {
      try {
        const Z = _require('zstd-codec').ZstdCodec;
        Z.run((z) => resolve(new z.Simple()), () => resolve(null));
      } catch (e) { resolve(null); }
    });
  }
  return _codecPromise;
}

export function zstdDecompress(input, options, callback) {
  if (typeof options === 'function') { callback = options; options = undefined; }
  let out;
  try { out = _decode(input); }
  catch (e) {
    if (callback) { process.nextTick(() => callback(e)); return; }
    return Promise.reject(e);
  }
  if (callback) { process.nextTick(() => callback(null, out)); return; }
  return Promise.resolve(out);
}

export function zstdDecompressSync(input) {
  return _decode(input);
}

export async function zstdCompress(input, options, callback) {
  if (typeof options === 'function') { callback = options; options = undefined; }
  const cb = callback;
  if (input == null) {
    const err = Object.assign(new TypeError('The "input" argument must be of type string or an instance of Buffer, TypedArray, DataView, or ArrayBuffer. Received ' + typeof input), { code: 'ERR_INVALID_ARG_TYPE' });
    if (cb) { process.nextTick(() => cb(err)); return undefined; }
    throw err;
  }
  try {
    const simple = await _codec();
    if (!simple) throw Object.assign(new Error('zstd: zstdCompress unavailable'), { code: 'ERR_ZSTD_NOT_SUPPORTED' });
    const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input;
    const out = Buffer.from(simple.compress(new Uint8Array(buf), 3));
    if (cb) process.nextTick(() => cb(null, out));
    return out;
  } catch (e) {
    if (cb) { process.nextTick(() => cb(e)); return undefined; }
    throw e;
  }
}

// dsh probes the returned object for a Node-private stream shape; make the
// probe reject so it falls back to the sync one-shot decoder (zstdDecompressSync
// above) instead of expecting a native zstd stream handle this build lacks.
export function createZstdDecompress() {
  return { _handle: null, _writeState: new Uint32Array(0), close() {} };
}

// v0/v1 → v2 session migration pipes event rows through a real Zstd stream
// (createZstdCompress). Node >=22.18 has a native one; v22.7 does not, so buffer
// the whole input and emit a single WASM-encoded frame at flush. The reader's
// frame scanner decodes each frame independently, so one big frame is fine.
export function createZstdCompress() {
  const chunks = [];
  return new Transform({
    transform(chunk, _encoding, callback) {
      chunks.push(Buffer.from(chunk));
      callback();
    },
    flush(callback) {
      const input = chunks.length === 1 ? chunks[0] : Buffer.concat(chunks);
      chunks.length = 0;
      _codec().then((simple) => {
        if (!simple) return callback(Object.assign(new Error('zstd: createZstdCompress unavailable'), { code: 'ERR_ZSTD_NOT_SUPPORTED' }));
        try {
          // HarmonyOS patch: WASM zstd 对单帧 >4~8MB 的输入直接 OOM；0.1.3-alpha.2
          // 历史会话(v0→v2)迁移发布会把整段日志一次性压缩，大会话(20MB+)必然 abort。
          // 改为按 2MB 分帧压缩后拼接，读取端按帧独立解码，输出语义与单帧等价。
          const FRAME_CHUNK = 2 * 1024 * 1024;
          const frames = [];
          for (let offset = 0; offset < input.length; offset += FRAME_CHUNK) {
            const piece = input.subarray(offset, Math.min(offset + FRAME_CHUNK, input.length));
            frames.push(Buffer.from(simple.compress(new Uint8Array(piece), 3)));
          }
          callback(null, Buffer.concat(frames));
        } catch (error) { callback(error); }
      }, (error) => callback(error));
    }
  });
}

`;

const MODULE_SOURCE = `
export * from 'node:module';
export function stripTypeScriptTypes(source) { return { source }; }
`;

const FS_EXT_SOURCE = `
// HarmonyOS patch: fs-ext is a native addon without a HarmonyOS build; flock is
// used only for the cross-process session lease, which a single-process
// deployment never contends on, so report immediate success.
export function flock(_fd, _flags, callback) {
  if (typeof callback === 'function') { process.nextTick(() => callback(null)); return undefined; }
  return Promise.resolve();
}
export function lockf() { return undefined; }
export function unlock() { return undefined; }
`;

export function load(url, context, nextLoad) {
  if (url === DSH_ROOT + 'fs-ext?compat') {
    return { format: 'module', source: FS_EXT_SOURCE, shortCircuit: true };
  }
  if (url === 'node:zlib?compat') {
    return { format: 'module', source: ZLIB_SOURCE, shortCircuit: true };
  }
  if (url === 'node:module?compat') {
    return { format: 'module', source: MODULE_SOURCE, shortCircuit: true };
  }
  return nextLoad(url, context);
}
