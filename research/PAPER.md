# Beating V8 BigInt Multiplication from WebAssembly

## Abstract

A WebAssembly multiplier now beats V8's native `BigInt` multiply at every operand size we tested from 16 kbit to 33.5 Mbit. It is 1.2× to 4.5× faster in kernel time, and up to 2.9× faster including conversion from and back to `BigInt`. The winning kernel is a SIMD double-precision FFT. It uses balanced digits, a half-size real-output inverse, and an O(n) residue check with automatic retry. All 1,336 test products matched V8 exactly, up to 1M limbs.

A rebuilt in-place Karatsuba scales with the textbook exponent (measured 1.60) but stays a constant 1.5× behind V8's own Karatsuba, because V8 multiplies 64-bit digits natively. No Karatsuba in WASM can overtake it; only a lower-exponent algorithm can. We also found that the repository's previous Karatsuba kernel returned wrong products for most random operands above 32 limbs.

## 1. Background

Intersekt asks whether hand-built WebAssembly (WASM) big-integer multiplication can beat the engine's own `BigInt` multiply. Earlier versions never did, at any size.

**The opponent is not naive.** We measured V8's `a*b` (Node 26.5, V8 14.6, Apple M1 Pro). Up to about 2,048 32-bit limbs its time grows with a local exponent of about 1.6 (Karatsuba). Beyond that the exponent is 1.05 to 1.2 (an FFT-class algorithm). V8 also uses 64-bit digits with native 64×64→128-bit multiplies. WASM has none: this V8 rejects the `wide-arithmetic` proposal's `i64.mul_wide_u`. A WASM kernel therefore does about 4× more digit products at every size.

**Why the previous attempts could not win:**

- *Algorithm ceiling.* O(n^1.585) Karatsuba can at best tie V8's Karatsuba, and it loses to V8's FFT above about 2K limbs.
- *Allocation on the hot path.* The old `karatsuba.wat` bump-allocated and copied every split, sum and partial product. The old schoolbook kernel allocated about 3,000 blocks (~16.7 MB) per 1,024-limb multiply.
- *Benchmark artefacts.* The old harness timed an O(n²) BigInt-to-limbs conversion as part of the WASM multiply. Its JS baseline also reused the same operands on every repetition. V8 hoists such loop-invariant `a*b` out of the loop, and it lowers `(a*b) & 1n` to a 64-bit multiply. Our first naive timings of V8 read 3 ns at every size, which is meaningless.

The way forward is a different algorithm class, not a better-tuned Karatsuba. A double-precision FFT multiply does its heavy work in WASM's SIMD `f64x2` arithmetic, where WASM is not at a disadvantage.

## 2. Methods

All kernels live in `research/src/bigmul.c`: 654 lines of C compiled to a 21 KB WASM module with SIMD128. Numbers are little-endian 32-bit limbs in linear memory. Every kernel writes into caller-provided buffers, so nothing is allocated during a multiply.

**Karatsuba, rebuilt.** Subtractive form: a0b1 + a1b0 = a0b0 + a1b1 − (a0 − a1)(b0 − b1), so half-sums never grow a carry limb (the old kernel's bug class). Recursion runs over one scratch buffer of about 4n limbs. Below 96 limbs it switches to a SIMD Comba base case: each column is a contiguous dot product, `i64x2.extmul` forms two 32×32-bit products per instruction, and low/high halves go into separate 64-bit accumulators, so there is no carry chain. Cutoff tuned over 16–256 limbs.

**FFT multiply.** Five steps, all SIMD `f64x2` on split real/imaginary arrays:

1. **Balanced digits.** Cut each operand into b-bit digits in [−2^(b−1), 2^(b−1)). b is the largest value with 2b + log2 N ≤ 56 (15–20 bits).
2. **One forward transform for both operands.** Pack z = a + i·b; radix-4 DIF FFT of size N, depth-first until a sub-transform fits in L1 (4,096 points). Each radix-4 group loads one twiddle and derives the rest: w(j+q) = −i·w(j), w2 = w1².
3. **Pointwise product in scrambled order.** A_k·B_k = (Z_k² − conj(Z_−k)²) / 4i. In bit-reversed order the mirror of position p in block [2^m, 2^(m+1)) is 3·2^m − 1 − p, so no permutation pass is needed.
4. **Half-size inverse.** The product spectrum is Hermitian; fold it in place into a size-N/2 complex spectrum Z'_k = (C_k + conj(C_{H−k})) + i·W^−k·(C_k − conj(C_{H−k})) and invert, giving z_j = c_2j + i·c_2j+1. Transform work drops from 2N to 1.5N.
5. **Round, carry, verify.** Accept only if max rounding error < 0.375 and residues mod 2^32−1 and 2^31−1 match; otherwise retry with b − 1. A single wrong coefficient changes the result by ±2^(bk), never 0 mod 2^32−1, so it is always caught.

**Selection.** `mul_auto`: Karatsuba below 216 limbs, FFT from 216 limbs up.

**Optimisation ladder at 1M limbs (33.5 Mbit), V8 = 304 ms:**

| Step | FFT time (ms) | vs V8 |
| --- | --- | --- |
| Radix-2, bit-reversal-free, depth-first; budget 50 | 206 | 1.5× |
| Budget 56 with balanced digits | 114 | 2.7× |
| Radix-4 passes | 122 | 2.5× |
| Vectorised rounding and residues | 99 | 3.1× |
| Derived twiddles (1 load instead of 3) | 81 | 3.7× |
| Half-size real-output inverse | 73 | 4.2× |

## 3. Experimental setup

| Item | Value |
| --- | --- |
| Hardware | Apple M1 Pro, arm64, macOS 26 (Darwin 25.6) |
| Engine | Node 26.5.0, V8 14.6.202.34 |
| Compiler | clang 24.0.0git (Emscripten 6.0.5 LLVM), `--target=wasm32 -O3 -msimd128 -nostdlib` |
| Sizes | 8 to 1,048,576 limbs (256 bit to 33.5 Mbit), half-octave steps, 35 sizes |
| Operands | Seeded xorshift128+ limbs, top bit set |

**Timing** (`bench.mjs`): four distinct operand pairs rotated through 16 combinations; every V8 product stored to a global array; repetitions double until ≥ 60 ms (400 ms above 64K limbs); five interleaved trials, median reported; min–max spread < 2% above 8 limbs. Kernel time assumes operands are in WASM memory; `e2e.mjs` adds BigInt → hex → limbs and back. Previous kernels timed in the same harness (`bench_old.mjs`).

**Correctness** (`verify.mjs`, 1,336 exact comparisons with V8): every size 1–80 limbs; 2^p − 1, 2^p, 2^p + 1, 1.37·2^p for p = 7–16; 262,144, 777,777 and 1,048,576 limbs (FFT); random and all-ones operands; six kernels. `adversary.mjs` adds worst-case inputs for balanced digits.

## 4. Results

The WASM kernel beats V8 at every tested size from 16 kbit (512 limbs) up: 2.7–4.5× at power-of-two sizes from 64 kbit, 2.1–3.0× just above them (FFT padding). Below about 12 kbit V8 wins by 1.2–1.9×.

Speedup over V8 (V8 time ÷ WASM time), power-of-two sizes (full data in `results/final.json`, `e2e.tsv`, `old.tsv`):

| Size | Kernel | End-to-end | Previous WASM Karatsuba (fixed) |
| --- | --- | --- | --- |
| 2 kbit | 0.68× | 0.19× | 0.22× |
| 8 kbit | 0.84× | 0.38× | 0.19× |
| 16 kbit | 1.29× | 0.68× | 0.18× |
| 32 kbit | 1.85× | 1.00× | 0.17× |
| 64 kbit | 2.72× | 1.47× | 0.17× |
| 256 kbit | 2.81× | 1.64× | 0.087× |
| 1 Mbit | 3.39× | 2.01× | — |
| 8 Mbit | 4.49× | 2.89× | — |
| 32 Mbit | 4.16× | 2.93× | — |

### 4.1 Scaling

Fitted exponents (time ∝ size^k): 4–64 kbit V8 1.64, WASM Karatsuba 1.65; 128 kbit–33 Mbit V8 1.18, WASM Karatsuba 1.59, WASM FFT 1.08. Karatsuba runs parallel to V8; only the FFT bends below it. At 33.5 Mbit Karatsuba is 98× slower than the FFT.

### 4.2 Rounding error

Max rounding error at 1M limbs, random operands (`results/errsweep.tsv`):

| Bits/digit | Balanced | Unsigned |
| --- | --- | --- |
| 12 | 1.5e-5 | 0.020 |
| 14 | 2.4e-4 | 0.31 |
| 15 | 7.9e-4 | 0.5 (fail) |
| 17 (chosen) | 0.014 | — |
| 19 | 0.17 | — |
| 20 | 0.5 (fail) | — |

Unsigned digits average 2^(b−1), so products add coherently (error ∝ N); balanced digits average zero and add like a random walk. The gap grows with size: 53× at 1K limbs, ~160× at 16K, 1,280× at 1M.

**Adversarial inputs** (all balanced digits maximal, same sign) hit error 0.5 first time; the residue check caught every one and each product was exact after retry — one retry from 1K to 256K limbs, two at 1M (458 ms).

## 5. Discussion

**Why Karatsuba could never overtake.** From 128 to 2,048 limbs, WASM and V8 Karatsuba scale alike (1.65 vs 1.64); WASM stays a flat 1.47–1.52× behind, and a constant ratio between equal exponents never crosses. The ratio comes from digit width: one 64×64-bit product costs WASM four 32×32-bit products, and one extra Karatsuba level only recovers part of that. Above 2,048 limbs V8 switches to its FFT (1.18) and WASM Karatsuba falls 23× behind at 1M limbs. Overtaking needed a lower exponent with better constants than V8's FFT; the WASM FFT scales at 1.08.

**The previous kernel was wrong, not just slow.** `karatsuba.wat` stores x_low + x_high in an (m+1)-limb block but copies only m limbs; a carry adds whatever the heap held. It passes on zeroed memory (how the old tests ran). With a reused heap, random operands failed at 48 limbs 17/20 times and at every size ≥ 96 limbs 20/20; its own recursion reuses memory, so it fails even in one call at depth ≥ 2. One `i32.store` of zero fixes it (`oldfix/`). Fixed, it is 3.8× slower than the new Karatsuba and 10.6× slower than the FFT at 1,024 limbs.

**Limitations.**

- One machine and one engine; other engines/CPUs may differ.
- Balanced n×n products only.
- Power-of-two padding sawtooth: 2.1–3.0× instead of 2.7–4.5× just above powers of two.
- Exactness rests on verification, not proof; cancelling multi-coefficient errors are not ruled out (none observed).
- Adversarial inputs cost one retry (~2.2×), two at 1M limbs (1.5× slower than V8).
- End-to-end pays only from ~1,024 limbs; the hex round trip costs about half the multiply.
- FFT memory ≈ 5N doubles (~170 MB at 1M limbs); wasm32's 4 GB caps operands near 20M limbs.

**Future work.** `wide-arithmetic` (`i64.mul_wide_u`) for 64-bit digits; mixed-radix or truncated FFTs to remove the sawtooth; Toom-3 for 128–400 limbs; worker threads for large transforms; an NTT for proof-level exactness.
