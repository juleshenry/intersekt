# Karatsuba Algorithm Implementation in WebAssembly

## Overview

This directory contains a complete implementation of the Karatsuba multiplication algorithm in WebAssembly (WASM), along with comprehensive test harnesses to evaluate its performance characteristics.

## Files

- **karatsuba.wat** - WebAssembly Text format implementation of the Karatsuba algorithm
- **karatsuba.wasm** - Compiled WebAssembly binary (generated from karatsuba.wat)
- **test-karatsuba.html** - Comprehensive browser-based test suite with correctness and performance tests
- **test-node.js** - Node.js test script for command-line testing
- **IMPLEMENTATION.md** - This documentation file

## Algorithm Description

The Karatsuba algorithm is a divide-and-conquer algorithm for multiplication that reduces the number of single-digit multiplications required. For two n-digit numbers:

- **Standard multiplication**: O(n²) complexity
- **Karatsuba algorithm**: O(n^1.585) complexity

### How It Works

For two numbers x and y with m digits:

1. Split each number into high and low parts at m/2:
   - x = x₁ × 10^(m/2) + x₀
   - y = y₁ × 10^(m/2) + y₀

2. Compute three recursive multiplications:
   - z₂ = x₁ × y₁
   - z₀ = x₀ × y₀
   - z₁ = (x₁ + x₀) × (y₁ + y₀) - z₂ - z₀

3. Combine results:
   - result = z₂ × 10^m + z₁ × 10^(m/2) + z₀

### Implementation Details

The WASM implementation includes:

1. **Helper Functions**:
   - `power_of_10`: Calculates 10^n for splitting and recombining
   - `count_digits`: Counts the number of digits in base 10
   - `max`: Returns the maximum of two numbers

2. **Main Functions**:
   - `karatsuba` (internal): Recursive implementation of the algorithm
   - `karat` (exported): Public API for Karatsuba multiplication
   - `mult` (exported): Standard WASM multiplication for comparison

3. **Base Case**: Numbers < 10 use standard multiplication to avoid excessive recursion

## Building

To compile the WAT file to WASM:

```bash
wat2wasm karatsuba.wat -o karatsuba.wasm
```

Requirements: Install `wabt` (WebAssembly Binary Toolkit)
```bash
sudo apt-get install wabt
```

## Testing

### Node.js Testing

Run the automated test suite:

```bash
node test-node.js
```

This will:
- Verify correctness with 9 test cases
- Compare performance between JavaScript, WASM, and Karatsuba
- Display detailed timing analysis

### Browser Testing

Open `test-karatsuba.html` in a web browser to:
- Run correctness tests with visual feedback
- Compare performance across different number sizes
- View detailed analysis and findings

### Existing Compare Tool

The `../new/compare-updated.html` file demonstrates the original comparison pattern with the updated Karatsuba implementation.

## Test Results

### Correctness

✅ All test cases pass:
- Zero handling (0 × 0, 1 × 0)
- Small numbers (1 × 1, 5 × 7)
- Medium numbers (12 × 34, 123 × 456)
- Large numbers (1234 × 5678, 9999 × 9999)
- Very large numbers (12345 × 67890)

### Performance Findings

**Key Discovery**: For i32 integers (WASM's native 32-bit integers), the Karatsuba algorithm is **slower** than both standard JavaScript multiplication and native WASM multiplication across all tested size ranges.

#### Performance by Number Size

| Number Size | JavaScript | WASM Mult | Karatsuba | Winner |
|-------------|-----------|-----------|-----------|--------|
| < 10        | 1.7 ms    | 2.2 ms    | 2.3 ms    | JavaScript |
| 10-99       | 0.1 ms    | 0.4 ms    | 3.2 ms    | JavaScript |
| 100-999     | 0.1 ms    | 0.4 ms    | 7.6 ms    | JavaScript |
| 1000-9999   | 0.1 ms    | 0.4 ms    | 12.2 ms   | JavaScript |

*(100,000 iterations per test)*

## Analysis and Conclusions

### Why Karatsuba is Slower Here

1. **Hardware Optimization**: Modern CPUs have highly optimized multiplication circuits that can multiply 32-bit integers in a single cycle. This makes native multiplication extremely fast.

2. **Recursive Overhead**: The Karatsuba algorithm requires:
   - Multiple function calls (recursion overhead)
   - Additional arithmetic operations for splitting and recombining
   - Multiple intermediate value storage

3. **Small Number Domain**: For numbers that fit in i32 (~2 billion), there simply aren't enough digits for the algorithmic complexity advantage to overcome the constant-factor overhead.

4. **Crossover Point**: The Karatsuba algorithm typically becomes beneficial when numbers have **hundreds or thousands of digits**, far exceeding what i32 can represent.

### When Karatsuba Shines

The Karatsuba algorithm would show performance benefits when:

1. **Very Large Numbers**: Numbers with 100+ digits (requires BigInt support)
2. **Software Multiplication**: When hardware multiplication is unavailable or limited
3. **Theoretical Importance**: Demonstrates divide-and-conquer principles and asymptotic complexity
4. **Academic Interest**: Foundation for more advanced algorithms (Toom-Cook, FFT-based multiplication)

### Practical Applications

For production use with i32 integers:
- ✅ Use native JavaScript `*` operator
- ✅ Use WASM `i32.mul` instruction
- ❌ Avoid Karatsuba for small integers

For BigInt arithmetic:
- ✅ Consider Karatsuba for 1000+ digit numbers
- ✅ Use optimized libraries (GMP, BigInt.js)
- ✅ Profile to find the actual crossover point

## Educational Value

This implementation serves as:

1. **Algorithm Demonstration**: Shows how Karatsuba works in a low-level language
2. **Performance Study**: Illustrates why asymptotic complexity doesn't always predict real-world performance
3. **WASM Learning**: Demonstrates recursive algorithms and helper functions in WebAssembly
4. **Benchmarking Practice**: Shows how to properly measure and compare algorithm performance

## Future Enhancements

To make Karatsuba practical in WASM:

1. Implement BigInt support using memory arrays
2. Add different base representations (base 2^16 instead of base 10)
3. Implement hybrid approach (switch to native mult for small numbers)
4. Add Toom-Cook-3 or higher-order algorithms
5. Optimize splitting/recombining operations
6. Add proper overflow handling

## References

- [Karatsuba Algorithm - Wikipedia](https://en.wikipedia.org/wiki/Karatsuba_algorithm)
- [WebAssembly Specification](https://webassembly.github.io/spec/)
- Original paper: Karatsuba, A., & Ofman, Y. (1962). "Multiplication of Multidigit Numbers on Automata"

## License

Part of the intersekt project. See main repository for license information.
