const fs = require('fs');
const path = require('path');


const ITERATIONS = 100;
const NUM_DIGITS = 1000;
// Helper to create bigint from JavaScript BigInt using WASM functions
function bigintToWasm(wasmInstance, value) {
    const { memory, bigint_from_limbs } = wasmInstance.exports;
    const mem = new Uint32Array(memory.buffer);
    
    // Convert BigInt to array of 32-bit limbs
    const limbs = [];
    let temp = value;
    while (temp > 0n) {
        limbs.push(Number(temp & 0xFFFFFFFFn));
        temp = temp >> 32n;
    }
    
    if (limbs.length === 0) limbs.push(0);
    
    // Write limbs to a temporary location in memory (at high address to avoid conflicts)
    const tempPtr = 1000000; // Use a high address
    mem[tempPtr / 4] = limbs.length;
    for (let i = 0; i < limbs.length; i++) {
        mem[tempPtr / 4 + 1 + i] = limbs[i];
    }
    
    // Create bigint using WASM function
    return bigint_from_limbs(tempPtr);
}

// Helper to read bigint from WASM memory
function wasmToBigint(wasmInstance, ptr) {
    const { memory, bigint_len, bigint_get_limb } = wasmInstance.exports;
    
    const len = bigint_len(ptr);
    let result = 0n;
    
    for (let i = 0; i < len; i++) {
        const limb = bigint_get_limb(ptr, i);
        result = result | (BigInt(limb >>> 0) << (BigInt(i) * 32n));
    }
    
    return result;
}

async function testModule(name, filename, iterations) {
    console.log(`\n==================================================`);
    console.log(`Testing Module: ${name} (${filename})`);
    console.log(`==================================================`);

    const wasmPath = path.join(__dirname, filename);
    if (!fs.existsSync(wasmPath)) {
        console.log(`File not found: ${filename} - Skipping`);
        return null;
    }
    
    const wasmBuffer = fs.readFileSync(wasmPath);
    const wasmModule = await WebAssembly.instantiate(wasmBuffer);
    const instance = wasmModule.instance;
    const { memory, bigint_karatsuba, reset_heap } = instance.exports;
    
    // Test 1: Small numbers for correctness
    console.log('1. Correctness Tests with Small Numbers:');
    
    const smallTests = [
        [123n, 456n, '56088'],
        [1234n, 5678n, '7006652'],
        [12345n, 67890n, '838102050'],
    ];
    
    let passed = 0;
    let failed = 0;
    
    for (const [a, b, expectedStr] of smallTests) {
        reset_heap();
        const expected = BigInt(expectedStr);
        
        const ptr_a = bigintToWasm(instance, a);
        const ptr_b = bigintToWasm(instance, b);
        
        const result_ptr = bigint_karatsuba(ptr_a, ptr_b);
        const result = wasmToBigint(instance, result_ptr);
        
        if (result === expected) {
            passed++;
        } else {
            console.log(`  ✗ ${a} × ${b}`);
            console.log(`    Expected: ${expected}`);
            console.log(`    Got:      ${result}`);
            failed++;
        }
    }
    console.log(`  ${passed} passed, ${failed} failed`);
    
    // Test 2: Large numbers (100+ digits)
    console.log('2. Large Number Tests (100+ digits):');
    const digits100_1 = '1'.repeat(100);
    const digits100_2 = '2'.repeat(100);
    reset_heap();
    const big1 = BigInt(digits100_1);
    const big2 = BigInt(digits100_2);
    const expectedLarge = big1 * big2;
    
    const ptr_1 = bigintToWasm(instance, big1);
    const ptr_2 = bigintToWasm(instance, big2);
    const result_ptr_large = bigint_karatsuba(ptr_1, ptr_2);
    const resultLarge = wasmToBigint(instance, result_ptr_large);
    
    if (resultLarge === expectedLarge) {
        console.log(`  ✓ Correct result for 100-digit multiplication`);
    } else {
        console.log(`  ✗ Incorrect result for 100-digit multiplication`);
        failed++;
    }

    // Test 3: Performance comparison with 1000+ digit numbers
    console.log('3. Performance Test (1000+ digits):');
    
    let num1000Str = '';
    let num2000Str = '';
    for (let i = 0; i < NUM_DIGITS; i++) {
        num1000Str += String((i % 9) + 1);
    }
    for (let i = 0; i < NUM_DIGITS; i++) {
        num2000Str += String(((i + 5) % 9) + 1);
    }
    
    const num1000 = BigInt(num1000Str);
    const num2000 = BigInt(num2000Str);
    
    // WASM Karatsuba multiplication
    const wasmStart = process.hrtime.bigint();
    for (let i = 0; i < ITERATIONS; i++) {
        reset_heap();
        const p1 = bigintToWasm(instance, num1000);
        const p2 = bigintToWasm(instance, num2000);
        bigint_karatsuba(p1, p2);
    }
    const wasmTime = Number(process.hrtime.bigint() - wasmStart) / 1e6;
    const avgTime = wasmTime / ITERATIONS;
    console.log(`  Total time (${ITERATIONS} iterations): ${wasmTime.toFixed(3)} ms`);
    console.log(`  Average per multiplication: ${avgTime.toFixed(6)} ms`);

    return {
        name,
        filename,
        passed,
        failed,
        avgTime
    };
}

async function runAllTests() {
    const modules = [
        { name: 'Original', filename: 'bigint-karatsuba.wasm' },
        { name: 'Schoolbook', filename: 'bigint-schoolbook.wasm' },
        { name: 'Schoolbook Redux', filename: 'bigint-schoolbook-redux.wasm' },
        { name: 'DeepSeek', filename: 'bigint-karatsuba-deepseek.wasm' },
        { name: 'Gemini3', filename: 'bigint-karatsuba-gemini3.wasm' },
        { name: 'Qwen3 Max', filename: 'bigint-karatsuba-qwen3-max.wasm' }
    ];

    // Shuffle the modules array randomly
    for (let i = modules.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [modules[i], modules[j]] = [modules[j], modules[i]];
    }

    // Baseline JS Performance
    console.log(`\n==================================================`);
    console.log(`Baseline: JavaScript BigInt`);
    console.log(`==================================================`);
    
    let num1000Str = '';
    let num2000Str = '';
    for (let i = 0; i < NUM_DIGITS; i++) {
        num1000Str += String((i % 9) + 1);
    }
    for (let i = 0; i < NUM_DIGITS; i++) {
        num2000Str += String(((i + 5) % 9) + 1);
    }
    const num1000 = BigInt(num1000Str);
    const num2000 = BigInt(num2000Str);

    const jsStart = process.hrtime.bigint();
    const jsIterations = ITERATIONS;
    for (let i = 0; i < jsIterations; i++) {
        const _ = num1000 * num2000;
    }
    const jsTime = Number(process.hrtime.bigint() - jsStart) / 1e6;
    const jsAvgTime = jsTime / jsIterations;
    console.log(`  Average per multiplication: ${jsAvgTime.toFixed(6)} ms`);

    const results = [];
    for (const mod of modules) {
        try {
            const result = await testModule(mod.name, mod.filename, ITERATIONS);
            if (result) results.push(result);
        } catch (e) {
            console.error(`Error testing ${mod.name}:`, e.message);
        }
    }

    console.log(`\n==================================================`);
    console.log(`Final Comparison Summary`);
    console.log(`==================================================`);
    console.log(`Module          | Status | Avg Time (ms) | Speedup vs JS`);
    console.log(`----------------|--------|---------------|--------------`);
    
    console.log(`JavaScript      | OK     | ${jsAvgTime.toFixed(6).padEnd(13)} | 1.00x`);

    results.sort((a, b) => a.avgTime - b.avgTime);

    for (const res of results) {
        const status = res.failed === 0 ? 'OK' : `FAIL(${res.failed})`;
        const speedup = jsAvgTime / res.avgTime;
        console.log(`${res.name.padEnd(15)} | ${status.padEnd(6)} | ${res.avgTime.toFixed(6).padEnd(13)} | ${speedup.toFixed(2)}x`);
    }
}

runAllTests().catch(console.error);
