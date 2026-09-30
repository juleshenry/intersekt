# Beating V8 BigInt multiplication from WebAssembly

A WASM multiplier (`src/bigmul.c` → `bigmul.wasm`) that beats V8's native `BigInt`
multiply for every tested operand size from 16 kbit (512 limbs) to 33.5 Mbit (1M limbs):
1.2–4.5× kernel time, up to 2.9× including BigInt ↔ WASM conversion
(Node 26.5 / V8 14.6, Apple M1 Pro).

| Kernel | Algorithm | Notes |
| --- | --- | --- |
| `mul_kara` | Subtractive Karatsuba, O(n^1.585) | in-place, SIMD Comba base case below 96 limbs |
| `mul_fft` | Complex f64 FFT, O(n log n) | balanced digits, radix-4 SIMD, half-size real inverse, residue-checked with retry |
| `mul_auto` | Karatsuba < 216 limbs ≤ FFT | what you would call |

## Reproduce

```sh
./build.sh                 # needs a clang with the wasm32 target (CC=... to override)
node verify.mjs            # 1,336 exact comparisons against V8, up to 1M limbs
node bench.mjs 3 20 v8,kara,fft,auto 2   # kernel timing sweep (OUT=file.json to save)
node e2e.mjs               # BigInt in / BigInt out, including conversion
node bench_old.mjs 14      # the repo's previous kernels, same harness
node old_check.mjs         # shows the previous karatsuba.wasm returning wrong products
node errsweep.mjs          # FFT rounding error vs digit size, balanced vs unsigned
node adversary.mjs 56      # worst-case inputs for balanced digits (verify + retry)
node prof.mjs 4096,1048576 # per-stage FFT profile
```

Results from the paper's runs are in `results/`.

## Previous kernel bug

`../karatsuba/karatsuba.wat` builds `x_low + x_high` in an (m+1)-limb block but copies
only m limbs; a carry then adds stale heap contents. It passes on fresh memory (how the
old tests ran) and fails for most random operands above 32 limbs. `oldfix/` has the
one-line fix used for the timing comparison.
