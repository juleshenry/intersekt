import { readFileSync } from 'node:fs';
import { makeRng, randLimbs, limbsToBigInt } from './harness.mjs';
const rng = makeRng(5);
for (const name of ['karatsuba', 'schoolbook']) {
  const { instance } = await WebAssembly.instantiate(readFileSync(new URL(`../karatsuba/${name}.wasm`, import.meta.url)));
  const x = instance.exports; x.memory.grow(8192 - x.memory.buffer.byteLength / 65536);
  const bad = [];
  for (const n of [8, 16, 31, 32, 33, 48, 64, 65, 96, 100, 127, 128, 200, 256, 1000, 1024]) {
    let fails = 0;
    for (let t = 0; t < 20; t++) {
      const a = randLimbs(n, rng), b = randLimbs(n, rng), base = 400 << 20;
      let m = new Uint32Array(x.memory.buffer);
      m[base >> 2] = n; m.set(a, (base >> 2) + 1); const bb = base + (n + 1) * 4; m[bb >> 2] = n; m.set(b, (bb >> 2) + 1);
      x.reset_heap(); const rp = x.bigint_karatsuba(base, bb);
      m = new Uint32Array(x.memory.buffer); const len = m[rp >> 2];
      if (limbsToBigInt(m.subarray((rp >> 2) + 1, (rp >> 2) + 1 + len)) !== limbsToBigInt(a) * limbsToBigInt(b)) fails++;
    }
    if (fails) bad.push(`${n}:${fails}/20`);
  }
  console.log(name, 'failures:', bad.join(' ') || 'none');
}
