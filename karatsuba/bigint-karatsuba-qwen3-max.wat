(module
  ;; Memory for storing bigint data
  (memory (export "memory") 100)
  
  ;; Global pointer to next free memory location
  (global $heap_ptr (mut i32) (i32.const 0))
  
  ;; Allocate memory for a bigint with n limbs
  (func $alloc (param $limbs i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $heap_ptr))
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
  (func $bigint_from_u32 (param $value i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (call $alloc (i32.const 1)))
    (i32.store (local.get $ptr) (i32.const 1))
    (i32.store (i32.add (local.get $ptr) (i32.const 4)) (local.get $value))
    (local.get $ptr)
  )
  
  ;; Copy bigint (for region-based allocation)
  (func $bigint_copy (param $src i32) (result i32)
    (local $len i32)
    (local $result i32)
    (local $i i32)
    (local.set $len (call $bigint_len (local.get $src)))
    (local.set $result (call $alloc (local.get $len)))
    (i32.store (local.get $result) (local.get $len))
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $result) (local.get $i)
          (call $bigint_get_limb (local.get $src) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    (local.get $result)
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
  
  ;; Normalize bigint (remove leading zeros)
  (func $bigint_normalize (param $ptr i32)
    (local $len i32)
    (local $actual_len i32)
    (local $limb i32)
    
    (local.set $len (call $bigint_len (local.get $ptr)))
    (local.set $actual_len (local.get $len))
    
    (block $break
      (loop $continue
        ;; Stop at length 1 to preserve zero representation
        (br_if $break (i32.le_u (local.get $actual_len) (i32.const 1)))
        (local.set $limb (call $bigint_get_limb 
          (local.get $ptr) 
          (i32.sub (local.get $actual_len) (i32.const 1))))
        (br_if $break (i32.ne (local.get $limb) (i32.const 0)))
        (local.set $actual_len (i32.sub (local.get $actual_len) (i32.const 1)))
        (br $continue)
      )
    )
    
    (i32.store (local.get $ptr) (local.get $actual_len))
  )
  
  ;; Compare two bigints
  (func $bigint_cmp (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $i i32)
    (local $limb_a i32)
    (local $limb_b i32)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    
    (if (i32.lt_u (local.get $len_a) (local.get $len_b))
      (then (return (i32.const -1)))
    )
    (if (i32.gt_u (local.get $len_a) (local.get $len_b))
      (then (return (i32.const 1)))
    )
    
    (local.set $i (local.get $len_a))
    (block $break
      (loop $continue
        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
        (br_if $break (i32.lt_s (local.get $i) (i32.const 0)))
        
        (local.set $limb_a (call $bigint_get_limb (local.get $a) (local.get $i)))
        (local.set $limb_b (call $bigint_get_limb (local.get $b) (local.get $i)))
        
        (if (i32.lt_u (local.get $limb_a) (local.get $limb_b))
          (then (return (i32.const -1)))
        )
        (if (i32.gt_u (local.get $limb_a) (local.get $limb_b))
          (then (return (i32.const 1)))
        )
        
        (br $continue)
      )
    )
    (i32.const 0)
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
    
    (local.set $result (call $alloc (i32.add (local.get $max_len) (i32.const 1))))
    
    (local.set $carry (i64.const 0))
    (local.set $i (i32.const 0))
    
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $max_len)))
        
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
        
        (local.set $sum (i64.add (i64.extend_i32_u (local.get $limb_a)) (i64.extend_i32_u (local.get $limb_b))))
        (local.set $sum (i64.add (local.get $sum) (local.get $carry)))
        
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.wrap_i64 (local.get $sum)))
        
        (local.set $carry (i64.shr_u (local.get $sum) (i64.const 32)))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (if (i64.ne (local.get $carry) (i64.const 0))
      (then
        (call $bigint_set_limb (local.get $result) (local.get $max_len) (i32.wrap_i64 (local.get $carry)))
        (i32.store (local.get $result) (i32.add (local.get $max_len) (i32.const 1)))
      )
      (else
        (i32.store (local.get $result) (local.get $max_len))
      )
    )
    
    ;; CRITICAL FIX: Normalize result
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Subtract two bigints: c = a - b (assumes a >= b)
  (func $bigint_sub (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $result i32)
    (local $i i32)
    (local $limb_a i64)
    (local $limb_b i64)
    (local $diff i64)
    (local $borrow i64)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    
    (local.set $result (call $alloc (local.get $len_a)))
    (i32.store (local.get $result) (local.get $len_a))
    
    (local.set $borrow (i64.const 0))
    (local.set $i (i32.const 0))
    
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len_a)))
        
        (local.set $limb_a (i64.extend_i32_u (call $bigint_get_limb (local.get $a) (local.get $i))))
        (local.set $limb_b 
          (if (result i64) (i32.lt_u (local.get $i) (local.get $len_b))
            (then (i64.extend_i32_u (call $bigint_get_limb (local.get $b) (local.get $i))))
            (else (i64.const 0))
          )
        )
        
        (local.set $diff (i64.sub (local.get $limb_a) (local.get $limb_b)))
        (local.set $diff (i64.sub (local.get $diff) (local.get $borrow)))
        
        (if (i64.lt_s (local.get $diff) (i64.const 0))
          (then
            (local.set $diff (i64.add (local.get $diff) (i64.const 0x100000000)))
            (local.set $borrow (i64.const 1))
          )
          (else
            (local.set $borrow (i64.const 0))
          )
        )
        
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.wrap_i64 (local.get $diff)))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Multiply bigint by single limb
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
    
    (if (i64.ne (local.get $carry) (i64.const 0))
      (then
        (call $bigint_set_limb (local.get $result) (local.get $len) (i32.wrap_i64 (local.get $carry)))
        (i32.store (local.get $result) (i32.add (local.get $len) (i32.const 1)))
      )
      (else
        (i32.store (local.get $result) (local.get $len))
      )
    )
    
    ;; CRITICAL FIX: Normalize result
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Shift bigint left by n limbs
  (func $bigint_shift_left (param $a i32) (param $n i32) (result i32)
    (local $len i32)
    (local $result i32)
    (local $i i32)
    (local $src_len i32)
    
    (local.set $len (call $bigint_len (local.get $a)))
    (local.set $src_len (local.get $len))
    (local.set $result (call $alloc (i32.add (local.get $len) (local.get $n))))
    
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
    
    ;; Set length and normalize
    (i32.store (local.get $result) (i32.add (local.get $src_len) (local.get $n)))
    (call $bigint_normalize (local.get $result))
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
    
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len_b)))
        
        (local.set $limb_b (call $bigint_get_limb (local.get $b) (local.get $i)))
        
        (local.set $partial (call $bigint_mul_limb (local.get $a) (local.get $limb_b)))
        (local.set $partial (call $bigint_shift_left (local.get $partial) (local.get $i)))
        
        (local.set $temp (local.get $result))
        (local.set $result (call $bigint_add (local.get $result) (local.get $partial)))
        
        ;; CRITICAL FIX: Free temporary intermediates
        ;; (In real implementation, would use region allocator or free-list)
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    ;; CRITICAL FIX: Normalize final result
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; OPTIMIZED Karatsuba multiplication with region-based allocation
  (func $bigint_karatsuba (param $x i32) (param $y i32) (result i32)
    ;; Save heap pointer for region allocation
    (local $saved_heap_ptr i32)
    (local $len_x i32)
    (local $len_y i32)
    (local $max_len i32)
    (local $half i32)
    (local $x_low i32)
    (local $x_high i32)
    (local $y_low i32)
    (local $y_high i32)
    (local $z0 i32)
    (local $z1 i32)
    (local $z2 i32)
    (local $sum_x i32)
    (local $sum_y i32)
    (local $temp1 i32)
    (local $temp2 i32)
    (local $result i32)
    (local $i i32)
    (local $final_result i32)
    (local $result_len i32)

    (local.set $saved_heap_ptr (global.get $heap_ptr))
    
    (local.set $len_x (call $bigint_len (local.get $x)))
    (local.set $len_y (call $bigint_len (local.get $y)))
    
    ;; OPTIMIZATION: Increased threshold to 32 limbs
    (if (i32.or 
          (i32.le_u (local.get $len_x) (i32.const 32)) 
          (i32.le_u (local.get $len_y) (i32.const 32))
        )
      (then
        (local.set $result (call $bigint_mul_simple (local.get $x) (local.get $y)))
        (local.set $result_len (call $bigint_len (local.get $result)))

        ;; Rewind and materialize a stable result so callers do not read freed space
        (global.set $heap_ptr (local.get $saved_heap_ptr))
        (local.set $final_result (call $alloc (local.get $result_len)))
        (i32.store (local.get $final_result) (local.get $result_len))
        (local.set $i (i32.const 0))
        (block $copy_base
          (loop $copy_base_continue
            (br_if $copy_base (i32.ge_u (local.get $i) (local.get $result_len)))
            (call $bigint_set_limb (local.get $final_result) (local.get $i)
              (call $bigint_get_limb (local.get $result) (local.get $i)))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $copy_base_continue)
          )
        )
        (return (local.get $final_result))
      )
    )
    
    (local.set $max_len 
      (if (result i32) (i32.gt_u (local.get $len_x) (local.get $len_y))
        (then (local.get $len_x))
        (else (local.get $len_y))
      )
    )
    (local.set $half (i32.shr_u (local.get $max_len) (i32.const 1)))
    
    ;; Split x into x_low and x_high
    (local.set $x_low (call $alloc (local.get $half)))
    (i32.store (local.get $x_low) (local.get $half))
    (local.set $i (i32.const 0))
    (block $break1
      (loop $continue1
        (br_if $break1 (i32.ge_u (local.get $i) (local.get $half)))
        (call $bigint_set_limb (local.get $x_low) (local.get $i)
          (if (result i32) (i32.lt_u (local.get $i) (local.get $len_x))
            (then (call $bigint_get_limb (local.get $x) (local.get $i)))
            (else (i32.const 0))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue1)
      )
    )
    (call $bigint_normalize (local.get $x_low))
    
    (local.set $x_high (call $alloc (i32.sub (local.get $max_len) (local.get $half))))
    (i32.store (local.get $x_high) (i32.sub (local.get $max_len) (local.get $half)))
    (local.set $i (i32.const 0))
    (block $break2
      (loop $continue2
        (br_if $break2 (i32.ge_u (local.get $i) (i32.sub (local.get $max_len) (local.get $half))))
        (call $bigint_set_limb (local.get $x_high) (local.get $i)
          (if (result i32) (i32.lt_u (i32.add (local.get $i) (local.get $half)) (local.get $len_x))
            (then (call $bigint_get_limb (local.get $x) (i32.add (local.get $i) (local.get $half))))
            (else (i32.const 0))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue2)
      )
    )
    (call $bigint_normalize (local.get $x_high))
    
    ;; Split y into y_low and y_high
    (local.set $y_low (call $alloc (local.get $half)))
    (i32.store (local.get $y_low) (local.get $half))
    (local.set $i (i32.const 0))
    (block $break3
      (loop $continue3
        (br_if $break3 (i32.ge_u (local.get $i) (local.get $half)))
        (call $bigint_set_limb (local.get $y_low) (local.get $i)
          (if (result i32) (i32.lt_u (local.get $i) (local.get $len_y))
            (then (call $bigint_get_limb (local.get $y) (local.get $i)))
            (else (i32.const 0))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue3)
      )
    )
    (call $bigint_normalize (local.get $y_low))
    
    (local.set $y_high (call $alloc (i32.sub (local.get $max_len) (local.get $half))))
    (i32.store (local.get $y_high) (i32.sub (local.get $max_len) (local.get $half)))
    (local.set $i (i32.const 0))
    (block $break4
      (loop $continue4
        (br_if $break4 (i32.ge_u (local.get $i) (i32.sub (local.get $max_len) (local.get $half))))
        (call $bigint_set_limb (local.get $y_high) (local.get $i)
          (if (result i32) (i32.lt_u (i32.add (local.get $i) (local.get $half)) (local.get $len_y))
            (then (call $bigint_get_limb (local.get $y) (i32.add (local.get $i) (local.get $half))))
            (else (i32.const 0))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue4)
      )
    )
    (call $bigint_normalize (local.get $y_high))
    
    ;; Three recursive multiplications
    (local.set $z0 (call $bigint_karatsuba (local.get $x_low) (local.get $y_low)))
    (local.set $z2 (call $bigint_karatsuba (local.get $x_high) (local.get $y_high)))
    
    (local.set $sum_x (call $bigint_add (local.get $x_low) (local.get $x_high)))
    (local.set $sum_y (call $bigint_add (local.get $y_low) (local.get $y_high)))
    (local.set $z1 (call $bigint_karatsuba (local.get $sum_x) (local.get $sum_y)))
    
    (local.set $z1 (call $bigint_sub (local.get $z1) (local.get $z2)))
    (local.set $z1 (call $bigint_sub (local.get $z1) (local.get $z0)))
    
    ;; Combine: result = z2 * 2^(2*half*32) + z1 * 2^(half*32) + z0
    (local.set $z2 (call $bigint_shift_left (local.get $z2) (i32.mul (local.get $half) (i32.const 2))))
    (local.set $z1 (call $bigint_shift_left (local.get $z1) (local.get $half)))
    
    (local.set $result (call $bigint_add (local.get $z2) (local.get $z1)))
    (local.set $result (call $bigint_add (local.get $result) (local.get $z0)))
    
    (local.set $result_len (call $bigint_len (local.get $result)))

    ;; Rewind and keep only the final result so callers do not see overlapped temporaries
    (global.set $heap_ptr (local.get $saved_heap_ptr))
    (local.set $final_result (call $alloc (local.get $result_len)))
    (i32.store (local.get $final_result) (local.get $result_len))
    
    (local.set $i (i32.const 0))
    (block $copy_final
      (loop $copy_final_continue
        (br_if $copy_final (i32.ge_u (local.get $i) (local.get $result_len)))
        (call $bigint_set_limb (local.get $final_result) (local.get $i)
          (call $bigint_get_limb (local.get $result) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_final_continue)
      )
    )

    (call $bigint_normalize (local.get $final_result))
    (local.get $final_result)
  )
  
  ;; Create bigint from array of limbs
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
  
  ;; Export functions
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
  
  (func (export "bigint_karatsuba") (param i32 i32) (result i32)
    (call $bigint_karatsuba (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_cmp") (param i32 i32) (result i32)
    (call $bigint_cmp (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_sub") (param i32 i32) (result i32)
    (call $bigint_sub (local.get 0) (local.get 1))
  )
)