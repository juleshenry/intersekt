// Worst case for balanced digits: every `bits`-bit chunk = 2^(bits-1)+1, so each balanced
// digit is -(2^(bits-1)-1) (all same sign): convolution sums add coherently.
import { load, limbsToBigInt } from './harness.mjs';
const { x, u32 } = await load();
const MAXN = 1 << 20;
const A = x.alloc(MAXN * 4), B = x.alloc(MAXN * 4), R = x.alloc(MAXN * 8);
function adversary(n, bits) {
  let v = 0n; const chunk = (1n << BigInt(bits - 1)) + 1n, total = n * 32;
  // build by repeated doubling of the chunk pattern
  let pat = chunk, len = bits;
  while (len < total) { pat = pat | (pat << BigInt(len)); len *= 2; }
  v = pat & ((1n << BigInt(total)) - 1n);
  const h = v.toString(16).padStart(total / 4, '0'), l = new Uint32Array(n);
  for (let i = 0; i < n; i++) l[i] = parseInt(h.slice(h.length - 8 * (i + 1), h.length - 8 * i), 16);
  return l;
}
const budget = +(process.argv[2] ?? 56);
console.log('limbs\tbits\tfirstErr\tretries\tbitsUsed\texact\tms');
for (const n of [1 << 10, 1 << 12, 1 << 14, 1 << 16, 1 << 18, 1 << 20]) {
  x.set_fft(0, budget, 1, 0); x.mul_fft(R, A, B, 8);  // probe bits for n
  x.set_fft(0, budget, 1, 1);
  // discover the bits the policy picks for n
  const a0 = new Uint32Array(n).fill(1); let m = u32(); m.set(a0, A >> 2); m.set(a0, B >> 2);
  x.mul_fft(R, A, B, n); const bits = x.fft_last_bits();
  const a = adversary(n, bits);
  m = u32(); m.set(a, A >> 2); m.set(a, B >> 2);
  x.set_fft(0, budget, 1, 0); x.mul_fft(R, A, B, n); const firstErr = x.fft_max_err();
  x.set_fft(0, budget, 1, 1);
  const t = performance.now(); const used = x.mul_fft(R, A, B, n); const ms = performance.now() - t;
  let exact = '';
  if (true) { const w = limbsToBigInt(a); m = u32(); exact = limbsToBigInt(m.subarray(R >> 2, (R >> 2) + 2 * n)) === w * w ? 'yes' : 'NO'; }
  console.log([n, bits, firstErr.toFixed(4), x.fft_retries(), used, exact, ms.toFixed(1)].join('\t'));
}
