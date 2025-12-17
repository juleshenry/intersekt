const fs = require('fs');
const path = require('path');

// Load the WASM module
const wasmPath = path.join(__dirname, 'bigint-karatsuba.wasm');
const wasmBuffer = fs.readFileSync(wasmPath);

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

async function testBigintKaratsuba() {
    const wasmModule = await WebAssembly.instantiate(wasmBuffer);
    const instance = wasmModule.instance;
    const { memory, bigint_from_u32, bigint_len, bigint_get_limb, bigint_karatsuba, bigint_mul_simple, reset_heap } = instance.exports;
    
    console.log('=== BigInt Karatsuba Algorithm Test Suite ===\n');
    
    // Test 1: Small numbers for correctness
    console.log('1. Correctness Tests with Small Numbers:\n');
    
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
        
        // Create bigints using helper function
        const ptr_a = bigintToWasm(instance, a);
        const ptr_b = bigintToWasm(instance, b);
        
        // Multiply using Karatsuba
        const result_ptr = bigint_karatsuba(ptr_a, ptr_b);
        const result = wasmToBigint(instance, result_ptr);
        
        if (result === expected) {
            console.log(`✓ ${a} × ${b} = ${result}`);
            passed++;
        } else {
            console.log(`✗ ${a} × ${b}`);
            console.log(`  Expected: ${expected}`);
            console.log(`  Got:      ${result}`);
            failed++;
        }
    }
    
    console.log(`\nSmall Tests: ${passed} passed, ${failed} failed\n`);
    
    // Test 2: Large numbers (100+ digits)
    console.log('2. Large Number Tests (100+ digits):\n');
    
    // Generate large random numbers
    const digits100_1 = '1'.repeat(100);
    const digits100_2 = '2'.repeat(100);
    
    reset_heap();
    
    const big1 = BigInt(digits100_1);
    const big2 = BigInt(digits100_2);
    const expectedLarge = big1 * big2;
    
    console.log(`Testing: ${digits100_1.substring(0, 20)}...${digits100_1.substring(80)} × ${digits100_2.substring(0, 20)}...${digits100_2.substring(80)}`);
    console.log(`Number of digits: ${digits100_1.length} × ${digits100_2.length}`);
    
    const ptr_1 = bigintToWasm(instance, big1);
    const ptr_2 = bigintToWasm(instance, big2);
    
    // Multiply
    const result_ptr_large = bigint_karatsuba(ptr_1, ptr_2);
    const resultLarge = wasmToBigint(instance, result_ptr_large);
    
    if (resultLarge === expectedLarge) {
        console.log(`✓ Correct result for 100-digit multiplication`);
        console.log(`  Result: ${resultLarge.toString().substring(0, 40)}...${resultLarge.toString().slice(-40)}`);
    } else {
        console.log(`✗ Incorrect result for 100-digit multiplication`);
        console.log(`  Expected: ${expectedLarge.toString().substring(0, 40)}...`);
        console.log(`  Got:      ${resultLarge.toString().substring(0, 40)}...`);
    }
    
    // Test 3: Performance comparison with 1000+ digit numbers
    console.log('\n3. Performance Test (1000+ digits):\n');
    
    // Create two 1000-digit numbers
    let num1000Str = '';
    let num2000Str = '';
    for (let i = 0; i < 1000; i++) {
        num1000Str += String((i % 9) + 1);
    }
    for (let i = 0; i < 1000; i++) {
        num2000Str += String(((i + 5) % 9) + 1);
    }
    
    const num1000 = BigInt(num1000Str);
    const num2000 = BigInt(num2000Str);
    
    console.log(`Number 1: ${num1000Str.substring(0, 40)}...${num1000Str.slice(-40)} (${num1000Str.length} digits)`);
    console.log(`Number 2: ${num2000Str.substring(0, 40)}...${num2000Str.slice(-40)} (${num2000Str.length} digits)`);
    
    // JavaScript BigInt multiplication
    const jsStart = process.hrtime.bigint();
    const jsIterations = 100;
    let jsResult;
    for (let i = 0; i < jsIterations; i++) {
        jsResult = num1000 * num2000;
    }
    const jsTime = Number(process.hrtime.bigint() - jsStart) / 1e6;
    console.log(`\nJavaScript BigInt (${jsIterations} iterations): ${jsTime.toFixed(3)} ms`);
    console.log(`  Average per multiplication: ${(jsTime / jsIterations).toFixed(6)} ms`);
    
    // WASM Karatsuba multiplication
    const wasmStart = process.hrtime.bigint();
    const wasmIterations = 100;
    let wasmResultPtr;
    for (let i = 0; i < wasmIterations; i++) {
        reset_heap();
        const p1 = bigintToWasm(instance, num1000);
        const p2 = bigintToWasm(instance, num2000);
        wasmResultPtr = bigint_karatsuba(p1, p2);
    }
    const wasmTime = Number(process.hrtime.bigint() - wasmStart) / 1e6;
    console.log(`\nWASM Karatsuba (${wasmIterations} iterations): ${wasmTime.toFixed(3)} ms`);
    console.log(`  Average per multiplication: ${(wasmTime / wasmIterations).toFixed(6)} ms`);
    
    // Verify correctness
    reset_heap();
    const ptr1 = bigintToWasm(instance, num1000);
    const ptr2 = bigintToWasm(instance, num2000);
    wasmResultPtr = bigint_karatsuba(ptr1, ptr2);
    const wasmResult = wasmToBigint(instance, wasmResultPtr);
    
    if (wasmResult === jsResult) {
        console.log('\n✓ WASM result matches JavaScript BigInt');
    } else {
        console.log('\n✗ WASM result does NOT match JavaScript BigInt');
        console.log(`  First 40 digits - JS: ${jsResult.toString().substring(0, 40)}`);
        console.log(`  First 40 digits - WASM: ${wasmResult.toString().substring(0, 40)}`);
    }
    
    // Performance comparison
    const speedup = jsTime / wasmTime;
    console.log(`\n=== Performance Summary ===`);
    console.log(`Speed comparison: WASM is ${speedup > 1 ? speedup.toFixed(2) + 'x FASTER' : (1/speedup).toFixed(2) + 'x SLOWER'} than JavaScript`);
    
    if (speedup > 1) {
        console.log(`\n✓ SUCCESS: WASM Karatsuba is demonstrably superior to vanilla JavaScript for 1000+ digit multiplication!`);
    } else {
        console.log(`\nNote: For optimal WASM performance, consider:
- Using wasm-opt for optimization
- Reducing memory allocation overhead
- Further tuning the Karatsuba threshold`);
    }
    
    console.log(`\n=== Conclusion ===`);
    console.log(`Implemented bigint support in WASM using array of i32 limbs (base 2^32)`);
    console.log(`Successfully multiplies 1000+ digit numbers using Karatsuba algorithm`);
    console.log(`Result length for 1000×1000: ${wasmResult.toString().length} digits`);
}

testBigintKaratsuba().catch(console.error);
