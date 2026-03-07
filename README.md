# WASM Karatsuba vs BigInt

This repo is a focused experiment to compare Karatsuba multiplication in WebAssembly against JavaScript BigInt, including multiple AI-generated WASM variants.

## Repo Layout (What Matters)

- `karatsuba/` - All WASM sources, binaries, and test harnesses.
- `karatsuba/test-bigint.js` - Node benchmark: JS BigInt vs multiple WASM variants.
- `karatsuba/test-bigint.html` - Browser benchmark with parameter controls.
- `karatsuba/graph.html` + `karatsuba/graph.js` - Power-of-two size sweep and graph output.
- `karatsuba/bigint-karatsuba.wat` - Baseline bigint Karatsuba implementation (WAT).
- `karatsuba/bigint-schoolbook.wat` - Baseline O(n^2) schoolbook implementation (WAT).

All legacy completion reports and scratch artifacts were removed to keep only the current experiment.

## Experiment Modules (AI + Baselines)

All comparison binaries live in `karatsuba/`:

- `bigint-karatsuba.wasm` - Baseline bigint Karatsuba.
- `bigint-schoolbook.wasm` - Baseline schoolbook.
- `bigint-karatsuba-deepseek.wasm` - AI (DeepSeek) variant.
- `bigint-karatsuba-gemini3.wasm` - AI (Gemini 3) variant.
- `bigint-karatsuba-qwen3-max.wasm` - AI (Qwen3 Max) variant.

If you add a new AI implementation, drop the `.wasm` into `karatsuba/` and add it to:
- `karatsuba/test-bigint.js`
- `karatsuba/test-bigint.html`
- `karatsuba/graph.js`

## Step-by-Step: Run the Experiment

### 1) Node benchmark (fast sanity check)

```bash
cd karatsuba
node test-bigint.js
```

What you get:
- JS BigInt baseline time
- Per-module correctness checks
- Per-module average time and speedup vs JS

### 2) Browser benchmark (interactive)

```bash
cd karatsuba
python3 -m http.server 8000
```

Open:
- `http://localhost:8000/test-bigint.html`

Adjust:
- `num_digits` (default 1000)
- `iterations` (default 100)

### 3) Graph sweep (power-of-two sizes)

With the same server running, open:
- `http://localhost:8000/graph.html`

This runs a log-log sweep from 2^5 to 2^17 limbs and renders a downloadable JPG.

## WASM Karatsuba Design Choices (BigInt)

### 1) Representation

- Base: 2^32 limbs (i32 words), little-endian.
- Layout in linear memory:
  - `[len: i32, limb0: i32, limb1: i32, ...]`

Why: 2^32 matches native i32 ops and minimizes limb count vs base-10 splits.

### 2) Memory Management

- Simple bump allocator with a global heap pointer.
- `reset_heap()` exported for clean test runs.

Why: predictable, simple, and avoids GC inside WASM.

### 3) Core Ops

- `bigint_add` / `bigint_sub`: carry/borrow handled with i64 intermediates.
- `bigint_mul_simple`: schoolbook base case.
- `bigint_karatsuba`: recursive split with three multiplications.

Why: Karatsuba only helps for sufficiently large operand sizes; small sizes use the simpler path.

### 4) Threshold

- Base case threshold = 8 limbs (256 bits).

Why: balances recursion overhead and algorithmic savings; easy to retune later.

### 5) Data Movement Policy

- Benchmarks copy input limbs into WASM each iteration.
- `reset_heap()` used to prevent heap growth issues.

Why: repeatable results and avoids corrupting long-running benchmarks.

## Notes on Results

- JS BigInt is typically faster than WASM due to V8 optimizations and native code.
- WASM Karatsuba becomes interesting only at very large sizes, but JS still wins in practice here.

## Add a New AI Variant

1. Place the `.wasm` file in `karatsuba/`.
2. Update module lists in:
   - `karatsuba/test-bigint.js`
   - `karatsuba/test-bigint.html`
   - `karatsuba/graph.js`
3. Re-run the benchmarks.
