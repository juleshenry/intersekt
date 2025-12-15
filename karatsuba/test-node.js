const fs = require('fs');
const path = require('path');

// Load the WASM module
const wasmPath = path.join(__dirname, 'karatsuba.wasm');
const wasmBuffer = fs.readFileSync(wasmPath);

async function testKaratsuba() {
    const wasmModule = await WebAssembly.instantiate(wasmBuffer);
    const { mult, karat } = wasmModule.instance.exports;

    console.log('=== Karatsuba Algorithm Test Suite ===\n');

    // Test cases: [a, b, expected, description]
    // Note: i32 max is 2,147,483,647. Test cases must not overflow.
    const testCases = [
        [0, 0, 0, 'Zero multiplication'],
        [1, 0, 0, 'Multiplication by zero'],
        [1, 1, 1, 'One times one'],
        [5, 7, 35, 'Single digit multiplication'],
        [12, 34, 408, 'Two digit multiplication'],
        [123, 456, 56088, 'Three digit multiplication'],
        [1234, 5678, 7006652, 'Four digit multiplication'],
        [9999, 9999, 99980001, 'Four digit max'],
        [12345, 67890, 838102050, 'Five digit multiplication'],
        [46340, 46340, 2147395600, 'Near i32 max without overflow'],
    ];

    console.log('1. Correctness Tests:\n');
    let passed = 0;
    let failed = 0;

    testCases.forEach(([a, b, expected, description]) => {
        const jsResult = a * b;
        const wasmResult = mult(a, b);
        const karatResult = karat(a, b);

        const jsMatch = jsResult === expected;
        const wasmMatch = wasmResult === expected;
        const karatMatch = karatResult === expected;
        const allMatch = jsMatch && wasmMatch && karatMatch;

        if (allMatch) {
            console.log(`✓ ${description}: ${a} × ${b} = ${karatResult}`);
            passed++;
        } else {
            console.log(`✗ ${description}: ${a} × ${b}`);
            console.log(`  Expected: ${expected}`);
            console.log(`  JS: ${jsResult}, WASM: ${wasmResult}, Karatsuba: ${karatResult}`);
            failed++;
        }
    });

    console.log(`\nResults: ${passed} passed, ${failed} failed\n`);

    // Performance tests
    console.log('2. Performance Tests:\n');

    const iterations = 100000;
    const perfTests = [
        { a: 5, b: 7, name: 'Small numbers (< 10)' },
        { a: 12, b: 34, name: 'Medium numbers (10-99)' },
        { a: 123, b: 456, name: 'Large numbers (100-999)' },
        { a: 1234, b: 5678, name: 'Very large (1000-9999)' },
    ];

    perfTests.forEach(({ a, b, name }) => {
        // JavaScript
        let start = process.hrtime.bigint();
        for (let i = 0; i < iterations; i++) {
            const result = a * b;
        }
        let jsTime = Number(process.hrtime.bigint() - start) / 1e6;

        // WASM standard mult
        start = process.hrtime.bigint();
        for (let i = 0; i < iterations; i++) {
            const result = mult(a, b);
        }
        let wasmTime = Number(process.hrtime.bigint() - start) / 1e6;

        // Karatsuba
        start = process.hrtime.bigint();
        for (let i = 0; i < iterations; i++) {
            const result = karat(a, b);
        }
        let karatTime = Number(process.hrtime.bigint() - start) / 1e6;

        console.log(`${name} (${a} × ${b}):`);
        console.log(`  JS:        ${jsTime.toFixed(3)} ms`);
        console.log(`  WASM Mult: ${wasmTime.toFixed(3)} ms`);
        console.log(`  Karatsuba: ${karatTime.toFixed(3)} ms`);
        
        const fastest = Math.min(jsTime, wasmTime, karatTime);
        let winner = 'JS';
        if (fastest === wasmTime) winner = 'WASM Mult';
        if (fastest === karatTime) winner = 'Karatsuba';
        console.log(`  Winner:    ${winner}\n`);
    });

    console.log('3. Analysis:\n');
    console.log('The Karatsuba algorithm is designed for very large numbers (typically 1000+ digits).');
    console.log('For small integers that fit in i32 (up to ~2 billion), the recursive overhead');
    console.log('of Karatsuba typically makes it slower than native multiplication.');
    console.log('');
    console.log('To see Karatsuba benefits, you would need:');
    console.log('- BigInt support in WASM');
    console.log('- Numbers with hundreds or thousands of digits');
    console.log('- Implementation that avoids the constant factor overhead');
}

testKaratsuba().catch(console.error);
