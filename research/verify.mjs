// Exactness: every kernel vs V8 BigInt, random + adversarial (all-ones) operands.
import { load, makeRng, randLimbs, limbsToBigInt } from './harness.mjs';

const { x, u32 } = await load();
const MAXN = 1 << 20;
const A = x.alloc(MAXN * 4), B = x.alloc(MAXN * 4), R = x.alloc(MAXN * 8), S = x.alloc(MAXN * 32 + 4096);
const rng = makeRng(7);

const kernels = {
  school: (n) => x.mul_school(R, A, B, n),
  comba: (n) => x.mul_comba(R, A, B, n),
  comba_simd: (n) => x.mul_comba_simd(R, A, B, n),
  kara: (n) => x.mul_kara(R, A, B, n, S),
  fft: (n) => { if (!x.mul_fft(R, A, B, n)) throw new Error('fft refused'); },
  auto: (n) => x.mul_auto(R, A, B, n, S),
};

const sizes = [];
for (let n = 1; n <= 80; n++) sizes.push(n);
for (let p = 7; p <= 16; p++) sizes.push(2 ** p - 1, 2 ** p, 2 ** p + 1, Math.round(2 ** p * 1.37));
sizes.push(1 << 18, 777777, 1 << 20);
let fails = 0, checks = 0, worstErr = 0;
for (const n of sizes) {
  for (const kind of ['rand', 'ones']) {
    const a = kind === 'ones' ? new Uint32Array(n).fill(0xffffffff) : randLimbs(n, rng);
    const b = kind === 'ones' ? new Uint32Array(n).fill(0xffffffff) : randLimbs(n, rng);
    const want = limbsToBigInt(a) * limbsToBigInt(b);
    for (const [name, f] of Object.entries(kernels)) {
      if (n > 4096 && (name === 'school' || name === 'comba' || name === 'comba_simd')) continue;
      if (n < 2 && name === 'kara') continue;
      if (n > 1 << 17 && name !== 'fft') continue;
      let m = u32(); m.set(a, A >> 2); m.set(b, B >> 2); m.fill(0xdeadbeef, R >> 2, (R >> 2) + 2 * n);
      f(n);
      m = u32();
      const got = limbsToBigInt(m.subarray(R >> 2, (R >> 2) + 2 * n));
      checks++;
      if (name === "fft") { const e = x.fft_max_err(); worstErr = Math.max(worstErr, e); if (e > 0.05) console.log(`  err n=${n} ${kind} ${e.toFixed(4)}`); }
      if (got !== want) { fails++; if (fails < 10) console.log(`FAIL ${name} n=${n} ${kind}`); }
    }
  }
}
console.log(`${checks} checks, ${fails} failures, worst FFT rounding error ${worstErr.toExponential(3)}`);
process.exit(fails ? 1 : 0);
