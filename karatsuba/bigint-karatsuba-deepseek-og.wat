(module
  ;; Memory layout:
  ;; - Heap starts at 0
  ;; - Each bigint: [length (i32), limb0 (i32), limb1 (i32), ...]
  ;; - Workspace for Karatsuba: separate area for temporary calculations
  (memory (export "memory") 200)
  
  ;; Global pointers
  (global $heap_ptr (mut i32) (i32.const 0))
  (global $karatsuba_threshold (mut i32) (i32.const 32))  ;; Optimized threshold
  
  ;; Allocate memory for a bigint with n limbs
  (func $alloc (param $limbs i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $heap_ptr))
    (global.set $heap_ptr 
      (i32.add (global.get $heap_ptr) 
        (i32.add (i32.const 4) (i32.mul (local.get $limbs) (i32.const 4)))))
    (local.get $ptr)
  )
  
  ;; Allocate workspace for Karatsuba (reused across recursive calls)
  (global $karatsuba_workspace_ptr (mut i32) (i32.const 0))
  (global $karatsuba_workspace_size (mut i32) (i32.const 0))
  
  ;; Initialize Karatsuba workspace
  (func $init_karatsuba_workspace (param $size i32)
    ;; Allocate 4 * size limbs: enough for z0, z1, z2, and temporary buffers
    (global.set $karatsuba_workspace_size 
      (i32.mul (local.get $size) (i32.const 4)))
    (global.set $karatsuba_workspace_ptr (global.get $heap_ptr))
    (global.set $heap_ptr 
      (i32.add (global.get $heap_ptr) 
        (i32.mul (global.get $karatsuba_workspace_size) (i32.const 4))))
  )
  
  ;; Get pointer to workspace area for temporary bigint
  (func $workspace_alloc (param $index i32) (param $size i32) (result i32)
    (local $ptr i32)
    (local.set $ptr 
      (i32.add (global.get $karatsuba_workspace_ptr)
        (i32.mul (local.get $index) (i32.const 4))))
    (i32.store (local.get $ptr) (local.get $size))
    (local.get $ptr)
  )
  
  ;; Reset heap (for testing)
  (func $reset_heap (export "reset_heap")
    (global.set $heap_ptr (i32.const 0))
    (global.set $karatsuba_workspace_ptr (i32.const 0))
    (global.set $karatsuba_workspace_size (i32.const 0))
  )
  
  ;; Set Karatsuba threshold
  (func $set_karatsuba_threshold (export "set_karatsuba_threshold") (param $threshold i32)
    (global.set $karatsuba_threshold (local.get $threshold))
  )
  
  ;; Create a bigint from a single i32 value
  (func $bigint_from_u32 (param $value i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (call $alloc (i32.const 1)))
    (i32.store (local.get $ptr) (i32.const 1))
    (i32.store (i32.add (local.get $ptr) (i32.const 4)) (local.get $value))
    (local.get $ptr)
  )
  
  ;; Get bigint length
  (func $bigint_len (param $ptr i32) (result i32)
    (i32.load (local.get $ptr))
  )
  
  ;; Get limb at index
  (func $bigint_get_limb (param $ptr i32) (param $idx i32) (result i32)
    (i32.load (i32.add (local.get $ptr) (i32.add (i32.const 4) 
      (i32.mul (local.get $idx) (i32.const 4)))))
  )
  
  ;; Set limb at index
  (func $bigint_set_limb (param $ptr i32) (param $idx i32) (param $value i32)
    (i32.store (i32.add (local.get $ptr) (i32.add (i32.const 4) 
      (i32.mul (local.get $idx) (i32.const 4)))) (local.get $value))
  )
  
  ;; Copy bigint (creates new allocation)
  (func $bigint_copy (param $src i32) (result i32)
    (local $len i32)
    (local $dst i32)
    (local $i i32)
    
    (local.set $len (call $bigint_len (local.get $src)))
    (local.set $dst (call $alloc (local.get $len)))
    (i32.store (local.get $dst) (local.get $len))
    
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $dst) (local.get $i)
          (call $bigint_get_limb (local.get $src) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    (local.get $dst)
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
        (br_if $break (i32.ne 
          (call $bigint_get_limb (local.get $ptr) 
            (i32.sub (local.get $actual_len) (i32.const 1))) 
          (i32.const 0)))
        (local.set $actual_len (i32.sub (local.get $actual_len) (i32.const 1)))
        (br $continue)
      )
    )
    
    ;; Special case: if all zeros, keep a single zero
    (if (i32.eq (local.get $actual_len) (i32.const 0))
      (then
        (i32.store (local.get $ptr) (i32.const 1))
        (call $bigint_set_limb (local.get $ptr) (i32.const 0) (i32.const 0))
      )
      (else
        (i32.store (local.get $ptr) (local.get $actual_len))
      )
    )
  )
  
  ;; Compare two bigints: returns -1 if a < b, 0 if a == b, 1 if a > b
  (func $bigint_cmp (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $i i32)
    (local $limb_a i32)
    (local $limb_b i32)
    
    (call $bigint_normalize (local.get $a))
    (call $bigint_normalize (local.get $b))
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    
    ;; Compare lengths first
    (if (i32.lt_u (local.get $len_a) (local.get $len_b))
      (then (return (i32.const -1)))
    )
    (if (i32.gt_u (local.get $len_a) (local.get $len_b))
      (then (return (i32.const 1)))
    )
    
    ;; Same length, compare limbs from most significant
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
  
  ;; Add two bigints: c = a + b (optimized version)
  (func $bigint_add (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $max_len i32)
    (local $result i32)
    (local $i i32)
    (local $carry i32)
    (local $sum i64)
    (local $limb_a i32)
    (local $limb_b i32)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    
    ;; Get maximum length
    (local.set $max_len
      (if (result i32) (i32.gt_u (local.get $len_a) (local.get $len_b))
        (then (local.get $len_a))
        (else (local.get $len_b))
      )
    )
    
    ;; Allocate result with space for carry
    (local.set $result (call $alloc (i32.add (local.get $max_len) (i32.const 1))))
    
    (local.set $carry (i32.const 0))
    (local.set $i (i32.const 0))
    
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $max_len)))
        
        ;; Get limbs with bounds checking
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
        
        ;; 64-bit addition for carry handling
        (local.set $sum (i64.add 
          (i64.extend_i32_u (local.get $limb_a))
          (i64.extend_i32_u (local.get $limb_b))))
        (local.set $sum (i64.add (local.get $sum) 
          (i64.extend_i32_u (local.get $carry))))
        
        (call $bigint_set_limb (local.get $result) (local.get $i)
          (i32.wrap_i64 (local.get $sum)))
        
        (local.set $carry (i32.wrap_i64 (i64.shr_u (local.get $sum) (i64.const 32))))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    ;; Handle final carry
    (if (i32.ne (local.get $carry) (i32.const 0))
      (then
        (call $bigint_set_limb (local.get $result) (local.get $max_len) (local.get $carry))
        (i32.store (local.get $result) (i32.add (local.get $max_len) (i32.const 1)))
      )
      (else
        (i32.store (local.get $result) (local.get $max_len))
      )
    )
    
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Subtract two bigints: c = a - b (assumes a >= b)
  (func $bigint_sub (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $result i32)
    (local $i i32)
    (local $borrow i32)
    (local $diff i64)
    (local $limb_a i32)
    (local $limb_b i32)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    
    ;; Allocate result
    (local.set $result (call $alloc (local.get $len_a)))
    
    (local.set $borrow (i32.const 0))
    (local.set $i (i32.const 0))
    
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len_a)))
        
        (local.set $limb_a (call $bigint_get_limb (local.get $a) (local.get $i)))
        (local.set $limb_b 
          (if (result i32) (i32.lt_u (local.get $i) (local.get $len_b))
            (then (call $bigint_get_limb (local.get $b) (local.get $i)))
            (else (i32.const 0))
          )
        )
        
        ;; 64-bit subtraction with borrow
        (local.set $diff (i64.sub 
          (i64.extend_i32_u (local.get $limb_a))
          (i64.extend_i32_u (local.get $limb_b))))
        (local.set $diff (i64.sub (local.get $diff)
          (i64.extend_i32_u (local.get $borrow))))
        
        ;; Handle negative result
        (if (i64.lt_s (local.get $diff) (i64.const 0))
          (then
            (local.set $diff (i64.add (local.get $diff) (i64.const 0x100000000)))
            (local.set $borrow (i32.const 1))
          )
          (else
            (local.set $borrow (i32.const 0))
          )
        )
        
        (call $bigint_set_limb (local.get $result) (local.get $i)
          (i32.wrap_i64 (local.get $diff)))
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (i32.store (local.get $result) (local.get $len_a))
    (call $bigint_normalize (local.get $result))
    
    (local.get $result)
  )
  
  ;; Optimized schoolbook multiplication for base case
  (func $bigint_mul_schoolbook (param $a i32) (param $b i32) (result i32)
    (local $len_a i32)
    (local $len_b i32)
    (local $result_len i32)
    (local $result i32)
    (local $i i32)
    (local $j i32)
    (local $carry i64)
    (local $limb_a i32)
    (local $limb_b i32)
    (local $prod i64)
    (local $sum i64)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    (local.set $result_len (i32.add (local.get $len_a) (local.get $len_b)))
    
    ;; Allocate and initialize result to 0
    (local.set $result (call $alloc (local.get $result_len)))
    (i32.store (local.get $result) (local.get $result_len))
    
    ;; Initialize all limbs to 0
    (local.set $i (i32.const 0))
    (block $init_loop
      (loop $init_continue
        (br_if $init_loop (i32.ge_u (local.get $i) (local.get $result_len)))
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.const 0))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $init_continue)
      )
    )
    
    ;; Schoolbook multiplication
    (local.set $i (i32.const 0))
    (block $outer_break
      (loop $outer_continue
        (br_if $outer_break (i32.ge_u (local.get $i) (local.get $len_a)))
        
        (local.set $carry (i64.const 0))
        (local.set $limb_a (call $bigint_get_limb (local.get $a) (local.get $i)))
        
        (local.set $j (i32.const 0))
        (block $inner_break
          (loop $inner_continue
            (br_if $inner_break (i32.ge_u (local.get $j) (local.get $len_b)))
            
            (local.set $limb_b (call $bigint_get_limb (local.get $b) (local.get $j)))
            
            ;; Multiply and accumulate
            (local.set $prod (i64.mul 
              (i64.extend_i32_u (local.get $limb_a))
              (i64.extend_i32_u (local.get $limb_b))))
            
            (local.set $sum (i64.add 
              (i64.extend_i32_u 
                (call $bigint_get_limb (local.get $result) 
                  (i32.add (local.get $i) (local.get $j))))
              (local.get $prod)))
            (local.set $sum (i64.add (local.get $sum) (local.get $carry)))
            
            ;; Store result
            (call $bigint_set_limb (local.get $result) 
              (i32.add (local.get $i) (local.get $j))
              (i32.wrap_i64 (local.get $sum)))
            
            ;; Update carry
            (local.set $carry (i64.shr_u (local.get $sum) (i64.const 32)))
            
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner_continue)
          )
        )
        
        ;; Store remaining carry
        (if (i64.ne (local.get $carry) (i64.const 0))
          (then
            (call $bigint_set_limb (local.get $result)
              (i32.add (local.get $i) (local.get $len_b))
              (i32.wrap_i64 (local.get $carry)))
          )
        )
        
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $outer_continue)
      )
    )
    
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Get slice of bigint from start to start+len (exclusive)
  ;; Uses workspace to avoid allocation
  (func $bigint_slice (param $src i32) (param $start i32) (param $len i32) (param $workspace_idx i32) (result i32)
    (local $src_len i32)
    (local $result i32)
    (local $i i32)
    (local $actual_len i32)
    
    (local.set $src_len (call $bigint_len (local.get $src)))
    
    ;; Ensure we don't go beyond source length
    (if (i32.gt_u (i32.add (local.get $start) (local.get $len)) (local.get $src_len))
      (then
        (local.set $len (i32.sub (local.get $src_len) (local.get $start)))
      )
    )
    
    (local.set $result (call $workspace_alloc (local.get $workspace_idx) (local.get $len)))
    
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $result) (local.get $i)
          (call $bigint_get_limb (local.get $src)
            (i32.add (local.get $start) (local.get $i))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (call $bigint_normalize (local.get $result))
    (local.get $result)
  )
  
  ;; Main Karatsuba multiplication
  (func $bigint_karatsuba_impl (param $x i32) (param $y i32) (param $workspace_offset i32) (result i32)
    (local $len_x i32)
    (local $len_y i32)
    (local $max_len i32)
    (local $half i32)
    (local $x0 i32)
    (local $x1 i32)
    (local $y0 i32)
    (local $y1 i32)
    (local $z0 i32)
    (local $z1 i32)
    (local $z2 i32)
    (local $result i32)
    (local $temp1 i32)
    (local $temp2 i32)
    (local $sum_x i32)
    (local $sum_y i32)
    
    (local.set $len_x (call $bigint_len (local.get $x)))
    (local.set $len_y (call $bigint_len (local.get $y)))
    
    ;; Base case: use schoolbook for small numbers
    (if (i32.or 
          (i32.lt_u (local.get $len_x) (global.get $karatsuba_threshold))
          (i32.lt_u (local.get $len_y) (global.get $karatsuba_threshold)))
      (then
        (return (call $bigint_mul_schoolbook (local.get $x) (local.get $y)))
      )
    )
    
    ;; Ensure len_x >= len_y for balanced split
    (if (i32.lt_u (local.get $len_x) (local.get $len_y))
      (then
        ;; Swap x and y
        (local.set $temp1 (local.get $x))
        (local.set $x (local.get $y))
        (local.set $y (local.get $temp1))
        (local.set $temp1 (local.get $len_x))
        (local.set $len_x (local.get $len_y))
        (local.set $len_y (local.get $temp1))
      )
    )
    
    ;; Calculate split point (half of max_len, rounded up)
    (local.set $max_len (local.get $len_x))
    (local.set $half (i32.shr_u (local.get $max_len) (i32.const 1)))
    
    ;; Ensure half is at least 1 and not larger than len_y
    (if (i32.eq (local.get $half) (i32.const 0))
      (then (local.set $half (i32.const 1)))
    )
    
    ;; Split x into x0 (low) and x1 (high)
    (local.set $x0 (call $bigint_slice (local.get $x) (i32.const 0) (local.get $half) 
      (i32.add (local.get $workspace_offset) (i32.const 0))))
    (local.set $x1 (call $bigint_slice (local.get $x) (local.get $half) 
      (i32.sub (local.get $len_x) (local.get $half))
      (i32.add (local.get $workspace_offset) (i32.const 1))))
    
    ;; Split y into y0 (low) and y1 (high)
    (local.set $y0 (call $bigint_slice (local.get $y) (i32.const 0) 
      (if (result i32) (i32.lt_u (local.get $half) (local.get $len_y))
        (then (local.get $half))
        (else (local.get $len_y))
      )
      (i32.add (local.get $workspace_offset) (i32.const 2))))
    
    (local.set $y1 (call $bigint_slice (local.get $y) 
      (if (result i32) (i32.lt_u (local.get $half) (local.get $len_y))
        (then (local.get $half))
        (else (local.get $len_y))
      )
      (i32.sub (local.get $len_y) 
        (if (result i32) (i32.lt_u (local.get $half) (local.get $len_y))
          (then (local.get $half))
          (else (local.get $len_y))
        ))
      (i32.add (local.get $workspace_offset) (i32.const 3))))
    
    ;; Recursive multiplications
    (local.set $z0 (call $bigint_karatsuba_impl (local.get $x0) (local.get $y0)
      (i32.add (local.get $workspace_offset) (i32.const 4))))
    
    (local.set $z2 (call $bigint_karatsuba_impl (local.get $x1) (local.get $y1)
      (i32.add (local.get $workspace_offset) (i32.const 8))))
    
    ;; Compute (x0 + x1) and (y0 + y1)
    (local.set $sum_x (call $bigint_add (local.get $x0) (local.get $x1)))
    (local.set $sum_y (call $bigint_add (local.get $y0) (local.get $y1)))
    
    ;; Allocate temp space for sums (reuse workspace)
    (local.set $temp1 (call $workspace_alloc 
      (i32.add (local.get $workspace_offset) (i32.const 12))
      (call $bigint_len (local.get $sum_x))))
    (call $bigint_copy_to_workspace (local.get $sum_x) (local.get $temp1))
    
    (local.set $temp2 (call $workspace_alloc 
      (i32.add (local.get $workspace_offset) (i32.const 13))
      (call $bigint_len (local.get $sum_y))))
    (call $bigint_copy_to_workspace (local.get $sum_y) (local.get $temp2))
    
    (local.set $z1 (call $bigint_karatsuba_impl (local.get $temp1) (local.get $temp2)
      (i32.add (local.get $workspace_offset) (i32.const 14))))
    
    ;; z1 = z1 - z2 - z0
    (local.set $z1 (call $bigint_sub (local.get $z1) (local.get $z2)))
    (local.set $z1 (call $bigint_sub (local.get $z1) (local.get $z0)))
    
    ;; Combine results: result = z2 * B^(2*half) + z1 * B^half + z0
    (local.set $result (call $bigint_shift_and_add 
      (local.get $z2) (local.get $z1) (local.get $z0) (local.get $half)))
    
    (local.get $result)
  )
  
  ;; Helper: copy bigint to workspace
  (func $bigint_copy_to_workspace (param $src i32) (param $dst i32)
    (local $len i32)
    (local $i i32)
    
    (local.set $len (call $bigint_len (local.get $src)))
    (i32.store (local.get $dst) (local.get $len))
    
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $dst) (local.get $i)
          (call $bigint_get_limb (local.get $src) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
  )
  
  ;; Helper: shift and add z2, z1, z0
  (func $bigint_shift_and_add (param $z2 i32) (param $z1 i32) (param $z0 i32) (param $half i32) (result i32)
    (local $result i32)
    (local $temp i32)
    
    ;; Shift z2 by 2*half limbs
    (local.set $result (call $bigint_shift_left_limbs (local.get $z2) 
      (i32.mul (local.get $half) (i32.const 2))))
    
    ;; Shift z1 by half limbs and add
    (local.set $temp (call $bigint_shift_left_limbs (local.get $z1) (local.get $half)))
    (local.set $result (call $bigint_add (local.get $result) (local.get $temp)))
    
    ;; Add z0
    (local.set $result (call $bigint_add (local.get $result) (local.get $z0)))
    
    (local.get $result)
  )
  
  ;; Shift bigint left by n limbs
  (func $bigint_shift_left_limbs (param $a i32) (param $n i32) (result i32)
    (local $len i32)
    (local $result i32)
    (local $i i32)
    
    ;; Handle zero shift
    (if (i32.eq (local.get $n) (i32.const 0))
      (then
        (return (call $bigint_copy (local.get $a)))
      )
    )
    
    (local.set $len (call $bigint_len (local.get $a)))
    (local.set $result (call $alloc (i32.add (local.get $len) (local.get $n))))
    
    ;; Fill first n limbs with zeros
    (local.set $i (i32.const 0))
    (block $zero_loop
      (loop $zero_continue
        (br_if $zero_loop (i32.ge_u (local.get $i) (local.get $n)))
        (call $bigint_set_limb (local.get $result) (local.get $i) (i32.const 0))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $zero_continue)
      )
    )
    
    ;; Copy original limbs
    (local.set $i (i32.const 0))
    (block $copy_loop
      (loop $copy_continue
        (br_if $copy_loop (i32.ge_u (local.get $i) (local.get $len)))
        (call $bigint_set_limb (local.get $result) 
          (i32.add (local.get $i) (local.get $n))
          (call $bigint_get_limb (local.get $a) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $copy_continue)
      )
    )
    
    (i32.store (local.get $result) (i32.add (local.get $len) (local.get $n)))
    (call $bigint_normalize (local.get $result))
    
    (local.get $result)
  )
  
  ;; Public Karatsuba multiplication (wrapper)
  (func $bigint_karatsuba (param $x i32) (param $y i32) (result i32)
    (local $max_len i32)
    (local $result i32)
    
    ;; Normalize inputs
    (call $bigint_normalize (local.get $x))
    (call $bigint_normalize (local.get $y))
    
    ;; Initialize workspace if needed
    (local.set $max_len
      (if (result i32) (i32.gt_u (call $bigint_len (local.get $x)) (call $bigint_len (local.get $y)))
        (then (call $bigint_len (local.get $x)))
        (else (call $bigint_len (local.get $y)))
      )
    )
    
    ;; Estimate workspace size: 4 * max_len for recursive depth
    (call $init_karatsuba_workspace 
      (i32.mul (local.get $max_len) (i32.const 4)))
    
    ;; Call implementation
    (local.set $result (call $bigint_karatsuba_impl 
      (local.get $x) (local.get $y) (i32.const 0)))
    
    (local.get $result)
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
          (i32.load (i32.add (local.get $src_ptr) 
            (i32.add (i32.const 4) (i32.mul (local.get $i) (i32.const 4))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    
    (call $bigint_normalize (local.get $result))
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
  
  (func (export "bigint_sub") (param i32 i32) (result i32)
    (call $bigint_sub (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_cmp") (param i32 i32) (result i32)
    (call $bigint_cmp (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_mul_schoolbook") (param i32 i32) (result i32)
    (call $bigint_mul_schoolbook (local.get 0) (local.get 1))
  )
  
  (func (export "bigint_karatsuba") (param i32 i32) (result i32)
    (call $bigint_karatsuba (local.get $0) (local.get $1))
  )
  
  (func (export "reset_heap")
    (call $reset_heap)
  )
  
  (func (export "set_karatsuba_threshold") (param i32)
    (call $set_karatsuba_threshold (local.get 0))
  )
)