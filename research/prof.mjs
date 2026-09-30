import { load, makeRng, randLimbs } from './harness.mjs';
const { x, u32 } = await load();
const rng = makeRng(1);
for (const n of (process.argv[2]||"4096,65536,1048576").split(",").map(Number)) {
  const A = x.alloc(n * 4), B = x.alloc(n * 4), R = x.alloc(n * 8);
  let m = u32(); m.set(randLimbs(n, rng), A >> 2); m.set(randLimbs(n, rng), B >> 2);
  x.set_fft(0, 56, 1, 1); x.mul_fft(R, A, B, n); const bits = x.fft_last_bits();
  const coefs = Math.ceil(n * 32 / bits); let N = 1; while (N < 2 * coefs + 2) N *= 2;
  const T = f => { f(); let best = 1e9; for (let t = 0; t < 7; t++) { const s = performance.now(); for (let k = 0; k < 200; k++) f(); best = Math.min(best, (performance.now() - s) / 200); } return best; };
  const r = { full: T(() => x.mul_fft(R, A, B, n)), load: 2 * T(() => x.prof_stage(0, N, R, A, n, bits)),
    fwd: T(() => x.prof_stage(1, N, R, A, n, bits)), pointwise: T(() => x.prof_stage(4, N, R, A, n, bits)),
    inv: T(() => x.prof_stage(2, N, R, A, n, bits)), extract: T(() => x.prof_stage(5, N, R, A, n, bits)),
    residues: 4 * T(() => x.prof_stage(3, N, R, A, n, bits)) };
  console.log(`n=${n} bits=${bits} N=2^${Math.log2(N)} ` + Object.entries(r).map(([k, v]) => `${k}=${v.toFixed(3)}`).join(' '));
}
