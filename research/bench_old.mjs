// The repository's previous kernels (karatsuba.wasm / schoolbook.wasm) timed the same way:
// operands already in linear memory, heap reset per multiply; conversion excluded.
import { readFileSync } from 'node:fs';
import { makeRng, randLimbs, limbsToBigInt } from './harness.mjs';
const rng = makeRng(12345);
const mods = {};
for (const name of ['karatsuba', 'schoolbook']) {
  const { instance } = await WebAssembly.instantiate(readFileSync(new URL(name === 'karatsuba' ? './oldfix/karatsuba_fixed.wasm' : `../karatsuba/${name}.wasm`, import.meta.url)));
  const x = instance.exports;
  const pages = x.memory.buffer.byteLength / 65536;
  if (pages < 8192) x.memory.grow(8192 - pages);  // 512 MiB; inputs live at 400 MiB
  mods[name] = x;
}
function time(op, minMs) {
  let reps = 1, t;
  for (;;) { const s = performance.now(); for (let i = 0; i < reps; i++) op(i); t = performance.now() - s; if (t >= minMs) break; reps *= 2; }
  return t / reps;
}
const median = v => [...v].sort((a, b) => a - b)[v.length >> 1];
const maxPow = +(process.argv[2] ?? 14);
console.log('limbs32\told_kara_us\told_school_us\texact');
for (let p = 3; p <= maxPow; p++) {
  const n = 2 ** p, row = [n];
  let exact = true;
  for (const [name, x] of Object.entries(mods)) {
    if (name === 'schoolbook' && n > 4096) { row.push('-'); continue; }
    const base = 400 << 20, m = new Uint32Array(x.memory.buffer);
    const ptrs = [];
    for (let i = 0; i < 8; i++) {                       // 4 A's and 4 B's, [len, limbs...]
      const l = randLimbs(n, rng), at = base + i * (n + 1) * 4;
      m[at >> 2] = n; m.set(l, (at >> 2) + 1); ptrs.push({ at, v: limbsToBigInt(l) });
    }
    const f = name === 'karatsuba' ? x.bigint_karatsuba : x.bigint_karatsuba;
    x.reset_heap();
    const rp = f(ptrs[0].at, ptrs[4].at), len = new Uint32Array(x.memory.buffer)[rp >> 2];
    const got = limbsToBigInt(new Uint32Array(x.memory.buffer).subarray((rp >> 2) + 1, (rp >> 2) + 1 + len));
    exact &&= got === ptrs[0].v * ptrs[4].v;
    const ts = [];
    for (let t = 0; t < 5; t++) ts.push(time(i => { x.reset_heap(); f(ptrs[i & 3].at, ptrs[4 + ((i >> 2) & 3)].at); }, 60) * 1000);
    row.push(median(ts).toPrecision(4));
  }
  row.push(exact ? 'yes' : 'NO');
  console.log(row.join('\t'));
}
