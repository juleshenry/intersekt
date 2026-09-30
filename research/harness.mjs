// Shared harness: load the module, move numbers between BigInt and WASM memory.
import { readFileSync } from 'node:fs';

export async function load() {
  const bytes = readFileSync(new URL('./bigmul.wasm', import.meta.url));
  const { instance } = await WebAssembly.instantiate(bytes);
  const x = instance.exports;
  const u32 = () => new Uint32Array(x.memory.buffer);  // re-view after any growth
  return { x, u32 };
}

// Deterministic xorshift128+ limbs; top limb forced full-size
export function makeRng(seed) {
  let s0 = BigInt.asUintN(64, BigInt(seed) * 0x9E3779B97F4A7C15n + 1n), s1 = 0x5851F42D4C957F2Dn ^ s0;
  return () => {
    let a = s0, b = s1; s0 = b; a ^= BigInt.asUintN(64, a << 23n); a ^= a >> 17n; a ^= b ^ (b >> 26n); s1 = a;
    return Number(BigInt.asUintN(32, (s0 + s1) >> 11n));
  };
}
export function randLimbs(n, rng) {
  const l = new Uint32Array(n);
  for (let i = 0; i < n; i++) l[i] = rng();
  l[n - 1] |= 0x80000000;
  return l;
}

export function limbsToBigInt(l) {
  let h = '';
  for (let i = l.length - 1; i >= 0; i--) h += l[i].toString(16).padStart(8, '0');
  return BigInt('0x' + h);
}
export function bigIntToLimbs(v, n) {
  const h = v.toString(16), l = new Uint32Array(n);
  for (let i = 0, e = h.length; e > 0; i++, e -= 8) l[i] = parseInt(h.slice(Math.max(0, e - 8), e), 16);
  return l;
}
