// CJS twin of compat-loader.mjs for node v22 (HarmonyOS) worker_threads paths
// (worker.cjs requires node:zlib directly, which loader hooks cannot rewrite).
// Mutates the real node:zlib exports object (writable, verified) with the
// node-24 zstd API surface dsh 0.1.3-alpha.2 expects, backed by pure-JS fzstd
// (decode) and the WASM zstd-codec (encode).
'use strict';
const zlib = require('node:zlib');
const { createRequire } = require('node:module');
const { Transform } = require('node:stream');
const req = createRequire(__filename);
const fzstd = req('fzstd');
const ZstdCodec = req('zstd-codec').ZstdCodec;

let codecPromise = null;
function codec() {
  if (!codecPromise) {
    codecPromise = new Promise((resolve) => {
      try {
        ZstdCodec.run((z) => resolve(new z.Simple()), () => resolve(null));
      } catch (error) { resolve(null); }
    });
  }
  return codecPromise;
}
function decode(input) {
  const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input;
  return Buffer.from(fzstd.decompress(buf));
}

function zstdDecompressSync(input) { return decode(input); }

function zstdDecompress(input, options, callback) {
  if (typeof options === 'function') { callback = options; options = undefined; }
  let out;
  try { out = decode(input); }
  catch (error) {
    if (callback) { process.nextTick(() => callback(error)); return; }
    return Promise.reject(error);
  }
  if (callback) { process.nextTick(() => callback(null, out)); return; }
  return Promise.resolve(out);
}

async function zstdCompress(input, options, callback) {
  if (typeof options === 'function') { callback = options; options = undefined; }
  const cb = callback;
  if (input == null) {
    const error = Object.assign(new TypeError('The "input" argument must be of type string or an instance of Buffer, TypedArray, DataView, or ArrayBuffer. Received ' + typeof input), { code: 'ERR_INVALID_ARG_TYPE' });
    if (cb) { process.nextTick(() => cb(error)); return undefined; }
    throw error;
  }
  try {
    const simple = await codec();
    if (!simple) throw Object.assign(new Error('zstd: zstdCompress unavailable'), { code: 'ERR_ZSTD_NOT_SUPPORTED' });
    const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input;
    const out = Buffer.from(simple.compress(new Uint8Array(buf), 3));
    if (cb) process.nextTick(() => cb(null, out));
    return out;
  } catch (error) {
    if (cb) { process.nextTick(() => cb(error)); return undefined; }
    throw error;
  }
}

// Same strategy as the ESM loader: make the private-stream probe reject so the
// code falls back to the sync one-shot decoder this build can actually provide.
function createZstdDecompress() {
  return { _handle: null, _writeState: new Uint32Array(0), close() {} };
}

// Buffer the piped rows and emit one WASM-encoded zstd frame at flush; the
// reader scans/decompresses frames independently.
function createZstdCompress() {
  const chunks = [];
  return new Transform({
    transform(chunk, _encoding, callback) {
      chunks.push(Buffer.from(chunk));
      callback();
    },
    flush(callback) {
      const input = chunks.length === 1 ? chunks[0] : Buffer.concat(chunks);
      chunks.length = 0;
      codec().then((simple) => {
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

if (typeof zlib.zstdDecompressSync !== 'function') zlib.zstdDecompressSync = zstdDecompressSync;
if (typeof zlib.zstdDecompress !== 'function') zlib.zstdDecompress = zstdDecompress;
if (typeof zlib.zstdCompress !== 'function') zlib.zstdCompress = zstdCompress;
if (typeof zlib.createZstdDecompress !== 'function') zlib.createZstdDecompress = createZstdDecompress;
if (typeof zlib.createZstdCompress !== 'function') zlib.createZstdCompress = createZstdCompress;

module.exports = zlib;
