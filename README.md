# WASM Karatsuba vs BigInt

![Benchmark Results](final-benchmark.jpg)

This repo is a focused experiment to compare Karatsuba multiplication in WebAssembly against JavaScript BigInt, mathematically demonstrating the $O(N^{1.58})$ asymptotic threshold where Karatsuba breaks away from an $O(N^2)$ Schoolbook implementation.

## Repo Layout

- `karatsuba/` - All WASM sources, binaries, and test harnesses.
- `karatsuba/test-bigint.js` - Node benchmark: JS BigInt vs WASM.
- `karatsuba/test-bigint.html` - Browser benchmark with parameter controls.
- `karatsuba/graph.html` + `karatsuba/graph.js` - Power-of-two size sweep and graph output (up to 1024 limbs).
- `karatsuba/karatsuba.wat` - The final consolidated Karatsuba implementation (WAT).
- `karatsuba/schoolbook.wat` - Baseline O(n^2) schoolbook implementation (WAT).

## Step-by-Step: Run the Experiment

### 1) Node benchmark (fast sanity check)

```bash
cd karatsuba
node test-bigint.js
```

What you get:
- JS BigInt baseline time
- Correctness checks up to 10,000 digits
- Average execution time across JS, Schoolbook, and Karatsuba

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

This runs a log-log sweep from 2^1 to 2^10 limbs and dynamically renders the benchmark graph above.

## WASM Karatsuba Design Choices (BigInt)

### 1) Representation
- Base: 2^32 limbs (i32 words), little-endian.
- Layout in linear memory:
  - `[len: i32, limb0: i32, limb1: i32, ...]`

Why: 2^32 matches native i32 ops and minimizes limb count vs base-10 splits.

### 2) Memory Management
- Simple bump allocator with an exported global `heap_ptr` to avoid GC and permit precise zero-overhead loop re-execution.
- Exported memory boundary set to 2,000 pages (~128MB) to handle recursive depth without OOMing.

### 3) Core Ops
- `bigint_add` / `bigint_sub`: carry/borrow handled with i64 intermediates.
- `bigint_mul_simple`: schoolbook base case.
- `bigint_karatsuba`: recursive split with three multiplications.

### 4) Threshold
- Base case threshold = 8 limbs (256 bits).
- Why: balances recursion overhead and algorithmic savings.

### 5) Notes on Results
- The mathematical divergence between $O(N^2)$ and $O(N^{1.58})$ is successfully proven locally in the WASM sandbox.
- Native JavaScript BigInt leverages compiled C++ bindings, hardware carry flags, and dynamic FFT-based algorithms ($O(N \log N)$), ensuring it evaluates substantially faster than the sandboxed WASM implementations.

## Algorithms & Memory Architecture

Both algorithms rely on WebAssembly's linear memory. To prevent `Out of Memory` (OOM) errors during heavy recursive iterations, the benchmark suite leverages a **Bump Allocator** design. Memory is allocated forward during operations, and the `heap_ptr` is dynamically exported and reset between benchmark iterations.

### Schoolbook ($O(N^2)$) - Memory Allocation

The Schoolbook algorithm allocates aggressively across its iterations. For a $1024$-limb BigInt, a single multiplication issues over 3000 bump allocations, inflating the heap pointer by roughly ~16.7MB per multiplication.

```mermaid
sequenceDiagram
participant Mem as Linear Memory (bump alloc)
participant Main as bigint_mul_simple
participant MulL as bigint_mul_limb
participant Shl as bigint_shift_left
participant Add as bigint_add

Main->>Mem: alloc result (1 limb = 0)

loop for each limb b[i]
Main->>MulL: mul_limb(a, b[i])
MulL->>Mem: alloc partial product
Mem-->>MulL: ptr
MulL-->>Main: partial

Main->>Shl: shift_left(partial, i)
Shl->>Mem: alloc shifted copy
Mem-->>Shl: ptr
Shl-->>Main: shifted

Main->>Add: add(result, shifted)
Add->>Mem: alloc new result
Mem-->>Add: ptr
Add-->>Main: result = new sum
end

Note over Mem: heap_ptr reset between benchmark runs
```

### Karatsuba ($O(N^{1.58})$) - Limb Split Logic

The Karatsuba approach trades raw arithmetic for recursive complexity. It splits the BigInt representations (stored as an array of 32-bit limbs) exactly in half, repeatedly chunking them until hitting a small base case (where it defaults back to schoolbook).

```mermaid
flowchart TD
    A["BigInt A (N limbs)"] --> |"m = N/2"| A_high["A_high<br>(N-m limbs)"]
    A --> A_low["A_low<br>(m limbs)"]
    
    B["BigInt B (M limbs)"] --> |"m = max(N,M)/2"| B_high["B_high<br>(M-m limbs)"]
    B --> B_low["B_low<br>(m limbs)"]

    A_low --> |"Recursive Karatsuba"| Z0["Z0 = A_low x B_low"]
    B_low --> Z0
    
    A_high --> |"Recursive Karatsuba"| Z2["Z2 = A_high x B_high"]
    B_high --> Z2
    
    A_low --> SumA["Sum_A = A_low + A_high"]
    A_high --> SumA
    B_low --> SumB["Sum_B = B_low + B_high"]
    B_high --> SumB
    
    SumA --> |"Recursive Karatsuba"| Z1_mid["Z1_mid = Sum_A x Sum_B"]
    SumB --> Z1_mid
    
    Z1_mid --> Z1["Z1 = Z1_mid - Z0 - Z2"]
    Z0 --> Z1
    Z2 --> Z1
    
    Z2 --> |"Shift Left 2m"| Z2_shifted["Z2 << 2m limbs"]
    Z1 --> |"Shift Left m"| Z1_shifted["Z1 << m limbs"]
    
    Z2_shifted --> Result["Result = Z2_shifted + Z1_shifted + Z0"]
    Z1_shifted --> Result
    Z0 --> Result
```
