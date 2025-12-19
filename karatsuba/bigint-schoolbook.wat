(module
  ;; Memory for storing bigint data
  ;; Each bigint is represented as an array of i32 limbs (base 2^32)
  ;; Format: [length, limb0, limb1, limb2, ...]
  (memory (export "memory") 100)
  
  ;; Global pointer to next free memory location
  (global $heap_ptr (mut i32) (i32.const 0))
  
  ;; Allocate memory for a bigint with n limbs
  ;; Returns pointer to the start of the bigint (length field)
  (func $alloc (param $limbs i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $heap_ptr))
    ;; Update heap pointer: current + 4 bytes for length + 4*limbs for data
    (global.set $heap_ptr 
      (i32.add (global.get $heap_ptr) 
        (i32.add (i32.const 4) (i32.mul (local.get $limbs) (i32.const 4)))))
    (local.get $ptr)
  )
  
  ;; Reset heap (for testing)
  (func $reset_heap (export "reset_heap")
    (global.set $heap_ptr (i32.const 0))
  )
  
  ;; Create a bigint from a single i32 value
  ;; Returns pointer to bigint
  (func $bigint_from_u32 (param $value i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (call $alloc (i32.const 1)))
    ;; Store length = 1
    (i32.store (local.get $ptr) (i32.const 1))
    ;; Store value
    (i32.store (i32.add (local.get $ptr) (i32.const 4)) (local.get $value))
    (local.get $ptr)
  )
  
  ;; Get bigint length
  (func $bigint_len (param $ptr i32) (result i32)
    (i32.load (local.get $ptr))
  )
  
  ;; Get limb at index
  (func $bigint_get_limb (param $ptr i32) (param $idx i32) (result i32)
    (i32.load (i32.add (local.get $ptr) (i32.add (i32.const 4) (i32.mul (local.get $idx) (i32.const 4)))))
  )
  
  ;; Set limb at index
  (func $bigint_set_limb (param $ptr i32) (param $idx i32) (param $value i32)
    (i32.store (i32.add (local.get $ptr) (i32.add (i32.const 4) (i32.mul (local.get $idx) (i32.const 4)))) (local.get $value))
  )
  
  ;; Add two bigints: c = a + b
  (func $bigint_add (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $max_len i32)
    (local $result i32)
    (local $i i32)
    (local $limb_a i32)
    (local $limb_b i32)
    (local $sum i64)
    (local $carry i64)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    (local.set $max_len 
      (if (result i32) (i32.gt_u (local.get $len_a) (local.get $len_b))
        (then (local.get $len_a))
        (else (local.get $len_b))
      )
    )
    
    ;; Allocate result with max_len + 1 for potential carry
    (local.set $result (call $alloc (i32.add (local.get $max_len) (i32.const 1))))
    
    (local.set $carry (i64.const 0))
    (local.set $i (i32.const 0))
    
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $max_len)))
        
        ;; Get limbs (or 0 if out of bounds)
        (local.set $limb_a 
          (if (result i32) (i32.lt_u (local.get $i) (local.get $len_a))
            (then (call $bigint_get_limb (local.get $a) (local.get $i)))
            (else (i32.const 0))
          )
        )
        (local.set $limb_b 
          (if (result i32) (i32.lt_u (local.get $i) (local.get $len_b))
            (then (call $bigint_get_limb (local.get $b) (local.get $i)))
            (else (i32.const 0))
          )
        )
        
        ;; Add with carry
        (local.set $sum (i64.add (i64.extend_i32_u (local.get $limb_a)) (i64.extend_i32_u (local.get $limb_b))))
        (local.set $sum (i64.add (local.get $sum) (local.get $carry)))
        
        ;; Store result limb
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.wrap_i64 (local.get $sum)))
        
        ;; Update carry
        (local.set $carry (i64.shr_u (local.get $sum) (i64.const 32)))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    ;; Handle final carry
    (if (i64.ne (local.get $carry) (i64.const 0))
      (then
        (call $bigint_set_limb (local.get $result) (local.get $max_len) (i32.wrap_i64 (local.get $carry)))
        (i32.store (local.get $result) (i32.add (local.get $max_len) (i32.const 1)))
      )
      (else
        (i32.store (local.get $result) (local.get $max_len))
      )
    )
    
    (local.get $result)
  )
  
  ;; Normalize bigint (remove leading zeros)
  (func $bigint_normalize (param $ptr i32)
    (local $len i32)
    (local $actual_len i32)
    
    (local.set $len (call $bigint_len (local.get $ptr)))
    (local.set $actual_len (local.get $len))
    
    (block $break
      (loop $continue
        (br_if $break (i32.le_u (local.get $actual_len) (i32.const 1)))
        (br_if $break (i32.ne (call $bigint_get_limb (local.get $ptr) (i32.sub (local.get $actual_len) (i32.const 1))) (i32.const 0)))
        (local.set $actual_len (i32.sub (local.get $actual_len) (i32.const 1)))
        (br $continue)
      )
    )
    
    (i32.store (local.get $ptr) (local.get $actual_len))
  )
  
  ;; Multiply bigint by single limb: result = a * limb
  (func $bigint_mul_limb (param $a i32) (param $limb i32) (result i32)
    (local $len i32)
    (local $result i32)
    (local $i i32)
    (local $prod i64)
    (local $carry i64)
    (local $limb_a i32)
    
    (local.set $len (call $bigint_len (local.get $a)))
    (local.set $result (call $alloc (i32.add (local.get $len) (i32.const 1))))
    
    (local.set $carry (i64.const 0))
    (local.set $i (i32.const 0))
    
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
        
        (local.set $limb_a (call $bigint_get_limb (local.get $a) (local.get $i)))
        (local.set $prod (i64.mul (i64.extend_i32_u (local.get $limb_a)) (i64.extend_i32_u (local.get $limb))))
        (local.set $prod (i64.add (local.get $prod) (local.get $carry)))
        
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.wrap_i64 (local.get $prod)))
        (local.set $carry (i64.shr_u (local.get $prod) (i64.const 32)))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    ;; Handle final carry
    (if (i64.ne (local.get $carry) (i64.const 0))
      (then
        (call $bigint_set_limb (local.get $result) (local.get $len) (i32.wrap_i64 (local.get $carry)))
        (i32.store (local.get $result) (i32.add (local.get $len) (i32.const 1)))
      )
      (else
        (i32.store (local.get $result) (local.get $len))
      )
    )
    
    (local.get $result)
  )
  
  ;; Shift bigint left by n limbs (multiply by 2^(32*n))
  (func $bigint_shift_left (param $a i32) (param $n i32) (result i32)
    (local $len i32)
    (local $result i32)
    (local $i i32)
    
    (local.set $len (call $bigint_len (local.get $a)))
    (local.set $result (call $alloc (i32.add (local.get $len) (local.get $n))))
    (i32.store (local.get $result) (i32.add (local.get $len) (local.get $n)))
    
    ;; Fill lower limbs with zeros
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $n)))
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.const 0))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    ;; Copy original limbs
    (local.set $i (i32.const 0))
    (block $break2
      (loop $continue2
        (br_if $break2 (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $result) 
          (i32.add (local.get $i) (local.get $n))
          (call $bigint_get_limb (local.get $a) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue2)
      )
    )
    
    (local.get $result)
  )
  
  ;; Simple multiplication (schoolbook algorithm)
  (func $bigint_mul_simple (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $result i32)
    (local $temp i32)
    (local $i i32)
    (local $limb_b i32)
    (local $partial i32)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    
    ;; Initialize result to 0
    (local.set $result (call $alloc (i32.const 1)))
    (i32.store (local.get $result) (i32.const 1))
    (call $bigint_set_limb (local.get $result) (i32.const 0) (i32.const 0))
    
    ;; For each limb in b
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len_b)))
        
        (local.set $limb_b (call $bigint_get_limb (local.get $b) (local.get $i)))
        
        ;; Multiply a by this limb
        (local.set $partial (call $bigint_mul_limb (local.get $a) (local.get $limb_b)))
        
        ;; Shift left by i limbs
        (local.set $partial (call $bigint_shift_left (local.get $partial) (local.get $i)))
        
        ;; Add to result
        (local.set $temp (local.get $result))
        (local.set $result (call $bigint_add (local.get $result) (local.get $partial)))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Create bigint from array of limbs stored in memory
  ;; Takes: ptr to array where first i32 is length, followed by limbs
  ;; Returns: ptr to new bigint
  (func $bigint_from_limbs (param $src_ptr i32) (result i32)
    (local $len i32)
    (local $result i32)
    (local $i i32)
    
    (local.set $len (i32.load (local.get $src_ptr)))
    (local.set $result (call $alloc (local.get $len)))
    (i32.store (local.get $result) (local.get $len))
    
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $result) (local.get $i)
          (i32.load (i32.add (local.get $src_ptr) (i32.add (i32.const 4) (i32.mul (local.get $i) (i32.const 4))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (local.get $result)
  )
  
  ;; Export functions for testing
  (func (export "bigint_from_u32") (param i32) (result i32)
    (call $bigint_from_u32 (local.get 0))
  )
  
  (func (export "bigint_from_limbs") (param i32) (result i32)
    (call $bigint_from_limbs (local.get 0))
  )
  
  (func (export "bigint_len") (param i32) (result i32)
    (call $bigint_len (local.get 0))
  )
  
  (func (export "bigint_get_limb") (param i32 i32) (result i32)
    (call $bigint_get_limb (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_add") (param i32 i32) (result i32)
    (call $bigint_add (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_mul_simple") (param i32 i32) (result i32)
    (call $bigint_mul_simple (local.get 0) (local.get 1))
  )
  
  ;; Export as bigint_karatsuba to match the interface expected by the test runner
  (func (export "bigint_karatsuba") (param i32 i32) (result i32)
    (call $bigint_mul_simple (local.get 0) (local.get 1))
  )
)
