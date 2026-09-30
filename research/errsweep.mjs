// Max FFT rounding error vs coefficient size, balanced vs unsigned digits (checks disabled).
import { load, makeRng, randLimbs, limbsToBigInt } from './harness.mjs';
const { x, u32 } = await load();
const MAXN = 1 << 20;
const A = x.alloc(MAXN * 4), B = x.alloc(MAXN * 4), R = x.alloc(MAXN * 8);
const rng = makeRng(99);
const out = [];
console.log('limbs\tbits\tlog2N\tbudget\tbalanced\tkind\tmaxErr\texact');
for (const n of [1 << 10, 1 << 14, 1 << 18, 1 << 20]) {
  for (const kind of ['rand', 'ones']) {
    const a = kind === 'ones' ? new Uint32Array(n).fill(0xffffffff) : randLimbs(n, rng);
    const b = kind === 'ones' ? new Uint32Array(n).fill(0xffffffff) : randLimbs(n, rng);
    const want = n <= 1 << 18 ? limbsToBigInt(a) * limbsToBigInt(b) : null;
    let m = u32(); m.set(a, A >> 2); m.set(b, B >> 2);
    for (const bal of [1, 0]) for (let bits = 12; bits <= 22; bits++) {
      x.set_fft(bits, 0, bal, 0);
      x.mul_fft(R, A, B, n);
      const err = x.fft_max_err();
      const coefs = Math.ceil(n * 32 / bits); let N = 1; while (N < 2 * coefs + 2) N *= 2;
      let exact = '';
      if (want !== null && err < 0.5) { m = u32(); exact = limbsToBigInt(m.subarray(R >> 2, (R >> 2) + 2 * n)) === want ? 'yes' : 'NO'; }
      const row = { n, bits, lgN: Math.log2(N), budget: 2 * bits + Math.log2(N), bal, kind, err, exact };
      out.push(row);
      console.log(Object.values(row).join('\t'));
      if (err >= 0.5) break;
    }
  }
}
(await import('node:fs')).writeFileSync('results/errsweep.json', JSON.stringify(out));
