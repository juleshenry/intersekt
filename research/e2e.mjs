// End-to-end: BigInt in, BigInt out. Drop-in `mul(a, b)` vs V8 `a * b`, including conversion.
import { load, makeRng, randLimbs, limbsToBigInt } from './harness.mjs';
const { x } = await load();
const MAXN = 1 << 20;
const A = x.alloc(MAXN * 4), B = x.alloc(MAXN * 4), R = x.alloc(MAXN * 8), S = x.alloc(MAXN * 32 + 65536), HEX = x.alloc(MAXN * 16);
x.set_kara(96, 1); x.set_auto(+(process.env.AUTO_FFT ?? 384));
const enc = new TextEncoder(), dec = new TextDecoder();
function toWasm(v, ptr) {
  const h = v.toString(16);
  enc.encodeInto(h, new Uint8Array(x.memory.buffer, HEX, h.length));
  return x.hex_to_limbs(ptr, HEX, h.length);
}
function fromWasm(ptr, n) {
  const len = x.limbs_to_hex(HEX, ptr, n);
  return BigInt('0x' + dec.decode(new Uint8Array(x.memory.buffer, HEX, len)));
}
export function mul(a, b) {
  const na = toWasm(a, A), nb = toWasm(b, B);
  const n = Math.max(na, nb);
  const m = new Uint32Array(x.memory.buffer);
  m.fill(0, (A >> 2) + na, (A >> 2) + n); m.fill(0, (B >> 2) + nb, (B >> 2) + n);  // balance lengths
  x.mul_auto(R, A, B, n, S);
  return fromWasm(R, 2 * n);
}
function time(op, minMs) {
  let reps = 1, t;
  for (;;) { const s = performance.now(); for (let i = 0; i < reps; i++) op(i); t = performance.now() - s; if (t >= minMs) break; reps *= 2; }
  return t / reps;
}
const median = v => [...v].sort((a, b) => a - b)[v.length >> 1];
globalThis.sink = [];
const rng = makeRng(3);
console.log('limbs32\tv8_us\tconv_in_us\tkernel_us\tconv_out_us\te2e_us\te2e_speedup');
for (let p = 6; p <= 20; p++) {
  const n = 2 ** p;
  const as = [], bs = [];
  for (let i = 0; i < 4; i++) { as.push(limbsToBigInt(randLimbs(n, rng))); bs.push(limbsToBigInt(randLimbs(n, rng))); }
  for (let i = 0; i < 4; i++) if (mul(as[i], bs[i]) !== as[i] * bs[i]) throw new Error('mismatch n=' + n);
  const minMs = n > 1 << 16 ? 300 : 60, T = { v8: [], cin: [], ker: [], cout: [], e2e: [] };
  toWasm(as[0], A); toWasm(bs[0], B);
  for (let t = 0; t < 5; t++) {
    T.v8.push(time(i => { sink[i & 7] = as[i & 3] * bs[(i >> 2) & 3]; }, minMs));
    T.cin.push(time(i => { toWasm(as[i & 3], A); toWasm(bs[(i >> 2) & 3], B); }, minMs));
    T.ker.push(time(i => x.mul_auto(R, A, B, n, S), minMs));
    T.cout.push(time(i => { sink[i & 7] = fromWasm(R, 2 * n); }, minMs));
    T.e2e.push(time(i => { sink[i & 7] = mul(as[i & 3], bs[(i >> 2) & 3]); }, minMs));
  }
  const r = Object.fromEntries(Object.entries(T).map(([k, v]) => [k, median(v) * 1000]));
  console.log([n, r.v8, r.cin, r.ker, r.cout, r.e2e].map(v => typeof v === 'number' && v % 1 ? v.toPrecision(4) : v).join('\t') + '\t' + (r.v8 / r.e2e).toFixed(2));
}
