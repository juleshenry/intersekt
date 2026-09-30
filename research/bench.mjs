// Kernel timing: V8 BigInt a*b vs WASM kernels on identical operands.
// Usage: node bench.mjs [minPow] [maxPow] [methods,comma,separated] [steps-per-octave]
import { load, makeRng, randLimbs, limbsToBigInt } from './harness.mjs';

const [minPow = 3, maxPow = 20, methodArg = 'v8,school,comba_simd,kara,fft,auto', spo = 1] = process.argv.slice(2);
const methods = methodArg.split(',');
const { x, u32 } = await load();
const MAXN = Math.ceil(2 ** +maxPow);
const P = 4;  // operand pairs rotated per repetition (defeats hoisting / CSE)
const As = [], Bs = [];
for (let i = 0; i < P; i++) { As.push(x.alloc(MAXN * 4)); Bs.push(x.alloc(MAXN * 4)); }
const R = x.alloc(MAXN * 8), S = x.alloc(MAXN * 32 + 65536);
if (process.env.KT) x.set_kara(+process.env.KT, +(process.env.KB ?? 1));
if (process.env.AUTO_FFT) x.set_auto(+process.env.AUTO_FFT);
if (process.env.BUDGET) x.set_fft(0, +process.env.BUDGET, 1, 1);
globalThis.sink = [];

function time(op, minMs) {
  let reps = 1, t;
  for (;;) {
    const s = performance.now();
    for (let i = 0; i < reps; i++) op(i);
    t = performance.now() - s;
    if (t >= minMs) break;
    reps *= t < minMs / 8 ? 4 : 2;
  }
  return t / reps;
}
function median(v) { v = [...v].sort((a, b) => a - b); return v[v.length >> 1]; }

const limits = { school: 1 << 14, comba: 1 << 14, comba_simd: 1 << 14, kara: 1 << 20 };
const rng = makeRng(12345);
const rows = [];
console.log(['limbs32', ...methods.map(m => m + '_us')].join('\t'));
for (let e = +minPow * spo; e <= +maxPow * spo; e++) {
  const n = Math.round(2 ** (e / spo));
  const al = [], bl = [], ab = [], bb = [];
  for (let i = 0; i < P; i++) {
    al.push(randLimbs(n, rng)); bl.push(randLimbs(n, rng));
    ab.push(limbsToBigInt(al[i])); bb.push(limbsToBigInt(bl[i]));
    const m = u32(); m.set(al[i], As[i] >> 2); m.set(bl[i], Bs[i] >> 2);
  }
  const ops = {
    v8: i => { sink[i & 7] = ab[i & 3] * bb[(i >> 2) & 3]; },
    school: i => x.mul_school(R, As[i & 3], Bs[(i >> 2) & 3], n),
    comba: i => x.mul_comba(R, As[i & 3], Bs[(i >> 2) & 3], n),
    comba_simd: i => x.mul_comba_simd(R, As[i & 3], Bs[(i >> 2) & 3], n),
    kara: i => x.mul_kara(R, As[i & 3], Bs[(i >> 2) & 3], n, S),
    fft: i => x.mul_fft(R, As[i & 3], Bs[(i >> 2) & 3], n),
    auto: i => x.mul_auto(R, As[i & 3], Bs[(i >> 2) & 3], n, S),
  };
  const row = { n };
  const minMs = n > 1 << 16 ? 400 : 60;
  for (let trial = 0; trial < 5; trial++) {
    for (const m of methods) {          // interleave methods within each trial
      if (n > (limits[m] ?? Infinity)) continue;
      (row[m] ??= []).push(time(ops[m], minMs) * 1000);
    }
  }
  for (const m of methods) if (row[m]) { row[m + '_lo'] = Math.min(...row[m]); row[m + '_hi'] = Math.max(...row[m]); row[m] = median(row[m]); }
  rows.push(row);
  console.log([n, ...methods.map(m => row[m] === undefined ? '-' : row[m].toPrecision(4))].join('\t'));
}
if (process.env.OUT) (await import('node:fs')).writeFileSync(process.env.OUT, JSON.stringify(rows, null, 1));
