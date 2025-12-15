# Testing the Karatsuba WASM Implementation

## Quick Start

### 1. Command Line Testing (Node.js)

The simplest way to verify the implementation:

```bash
cd karatsuba
node test-node.js
```

Expected output:
```
=== Karatsuba Algorithm Test Suite ===

1. Correctness Tests:

✓ Zero multiplication: 0 × 0 = 0
✓ Multiplication by zero: 1 × 0 = 0
✓ One times one: 1 × 1 = 1
✓ Single digit multiplication: 5 × 7 = 35
...
Results: 10 passed, 0 failed

2. Performance Tests:
...
```

### 2. Browser Testing

#### Option A: Using Python HTTP Server

```bash
cd karatsuba
python3 -m http.server 8000
```

Then open in browser: `http://localhost:8000/test-karatsuba.html`

#### Option B: Using Node HTTP Server

```bash
cd karatsuba
npx http-server -p 8000
```

Then open in browser: `http://localhost:8000/test-karatsuba.html`

#### Option C: Direct File Access

Some browsers allow opening HTML files directly:
1. Navigate to the `karatsuba` directory
2. Open `test-karatsuba.html` in your browser
3. Click "Run Correctness Tests", "Run Performance Tests", etc.

### 3. Comparing with Original Test

The original comparison tool has been updated:

```bash
cd new
python3 -m http.server 8001
```

Open `http://localhost:8001/compare-updated.html`

## Test Features

### test-karatsuba.html

Comprehensive browser-based testing with three sections:

1. **Correctness Tests**
   - Validates results against expected values
   - Tests edge cases (0, 1, small, large numbers)
   - Visual pass/fail indicators

2. **Performance Comparison**
   - Tests across 5 size categories
   - 10,000 iterations per category
   - Highlights fastest method

3. **Detailed Analysis**
   - 100,000 iterations per specific test case
   - Shows speedup/slowdown factors
   - Educational insights

### test-node.js

Command-line testing for CI/CD integration:
- Automated correctness validation
- Performance benchmarking
- No browser required

## Expected Results

### Correctness
✅ All tests should pass with 100% accuracy

### Performance
For i32 integers, expect this ranking (fastest to slowest):
1. 🥇 JavaScript native multiplication
2. 🥈 WASM i32.mul instruction
3. 🥉 Karatsuba algorithm

**This is expected!** The recursive Karatsuba algorithm has overhead that only pays off with very large numbers (1000+ digits), which exceed i32 capacity.

## Troubleshooting

### CORS Errors in Browser

If you see CORS errors when loading WASM files:
- Don't open HTML files directly with `file://` protocol
- Use a local HTTP server (see options above)

### Module Not Found in Node.js

If Node.js can't find the WASM file:
- Ensure you're running from the `karatsuba` directory
- Check that `karatsuba.wasm` exists
- Recompile if needed: `wat2wasm karatsuba.wat -o karatsuba.wasm`

### Different Performance Results

Performance can vary based on:
- CPU architecture and speed
- JavaScript engine (V8, SpiderMonkey, JavaScriptCore)
- Browser vs Node.js runtime
- System load and background processes

This is normal! The relative ranking should remain consistent.

## Integration Testing

To integrate these tests into a CI/CD pipeline:

```bash
# Install dependencies
npm install -g http-server
sudo apt-get install wabt

# Run command-line tests
cd karatsuba
node test-node.js

# Exit with error if tests fail
if [ $? -ne 0 ]; then
    echo "Karatsuba tests failed"
    exit 1
fi
```

## Manual Verification Examples

You can test individual calculations:

### Using Node.js REPL

```javascript
const fs = require('fs');
const wasmBuffer = fs.readFileSync('./karatsuba/karatsuba.wasm');

WebAssembly.instantiate(wasmBuffer).then(wasmModule => {
    const { mult, karat } = wasmModule.instance.exports;
    
    console.log('12345 × 67890 =', karat(12345, 67890));  // 838102050
    console.log('9999 × 9999 =', karat(9999, 9999));      // 99980001
});
```

### Using Browser Console

```javascript
fetch('./karatsuba.wasm')
    .then(response => response.arrayBuffer())
    .then(bytes => WebAssembly.instantiate(bytes))
    .then(result => {
        const { mult, karat } = result.instance.exports;
        console.log('12345 × 67890 =', karat(12345, 67890));
    });
```

## Performance Profiling

For detailed performance analysis:

### Browser DevTools

1. Open test-karatsuba.html
2. Open DevTools (F12)
3. Go to Performance tab
4. Start recording
5. Click "Run Performance Tests"
6. Stop recording
7. Analyze the flame graph to see where time is spent

### Node.js Profiling

```bash
node --prof test-node.js
node --prof-process isolate-*.log > profile.txt
```

This generates a detailed profile showing function call times.

## What to Look For

### Success Indicators
✅ All correctness tests pass
✅ No WASM loading errors
✅ Performance tests complete without errors
✅ Karatsuba produces identical results to native multiplication

### Performance Insights
📊 Karatsuba is slower for small i32 integers (expected)
📊 Native methods benefit from hardware optimization
📊 Recursive overhead is measurable and significant

### Educational Outcomes
🎓 Understand asymptotic vs constant-factor complexity
🎓 See WASM recursive algorithms in action
🎓 Learn when to use (and not use) advanced algorithms

## Next Steps

After testing:
1. Review IMPLEMENTATION.md for detailed findings
2. Experiment with different number sizes
3. Consider implementing BigInt version for larger numbers
4. Explore other multiplication algorithms (Toom-Cook, FFT)
