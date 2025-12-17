const fs = require('fs');
const path = require('path');

// Load the WASM module
const wasmPath = path.join(__dirname, 'bigint-karatsuba.wasm');
const wasmBuffer = fs.readFileSync(wasmPath);

async function test() {
    const wasmModule = await WebAssembly.instantiate(wasmBuffer);
    const { memory, bigint_from_u32, bigint_len, bigint_get_limb, bigint_add, bigint_mul_simple, reset_heap } = wasmModule.instance.exports;
    
    console.log('Testing basic bigint operations:\n');
    
    // Test 1: Create bigint from u32
    reset_heap();
    const ptr1 = bigint_from_u32(123);
    console.log(`Created bigint from 123, ptr=${ptr1}, len=${bigint_len(ptr1)}, limb[0]=${bigint_get_limb(ptr1, 0)}`);
    
    const ptr2 = bigint_from_u32(456);
    console.log(`Created bigint from 456, ptr=${ptr2}, len=${bigint_len(ptr2)}, limb[0]=${bigint_get_limb(ptr2, 0)}`);
    
    // Test 2: Addition
    const ptr_sum = bigint_add(ptr1, ptr2);
    console.log(`\nAddition: 123 + 456 = ${bigint_get_limb(ptr_sum, 0)} (expected 579)`);
    
    // Test 3: Simple multiplication
    reset_heap();
    const ptr_a = bigint_from_u32(123);
    const ptr_b = bigint_from_u32(456);
    const ptr_prod = bigint_mul_simple(ptr_a, ptr_b);
    
    const len_prod = bigint_len(ptr_prod);
    console.log(`\nMultiplication: 123 × 456`);
    console.log(`Result length: ${len_prod} limbs`);
    
    let result = 0n;
    for (let i = 0; i < len_prod; i++) {
        const limb = bigint_get_limb(ptr_prod, i);
        result = result | (BigInt(limb >>> 0) << (BigInt(i) * 32n));
    }
    console.log(`Result: ${result} (expected 56088)`);
    
    // Test 4: Larger numbers
    reset_heap();
    const val1 = 0xFFFFFFFF; // Max u32
    const val2 = 2;
    const ptr_large1 = bigint_from_u32(val1);
    const ptr_large2 = bigint_from_u32(val2);
    const ptr_large_prod = bigint_mul_simple(ptr_large1, ptr_large2);
    
    const len_large = bigint_len(ptr_large_prod);
    console.log(`\nLarge multiplication: ${val1} × ${val2}`);
    console.log(`Result length: ${len_large} limbs`);
    
    let large_result = 0n;
    for (let i = 0; i < len_large; i++) {
        const limb = bigint_get_limb(ptr_large_prod, i);
        console.log(`  limb[${i}] = ${limb}`);
        large_result = large_result | (BigInt(limb >>> 0) << (BigInt(i) * 32n));
    }
    console.log(`Result: ${large_result} (expected ${BigInt(val1) * BigInt(val2)})`);
}

test().catch(console.error);
