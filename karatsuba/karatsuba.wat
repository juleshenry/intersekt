(module
  ;; 100 pages = 6.4MB. For 1000+ limbs, you might need more. For testing, did not reach max.
  (memory (export "memory") 2000)
  
  (global $heap_ptr (export "heap_ptr") (mut i32) (i32.const 0))

  ;; --- MEMORY MANAGEMENT ---
  
  (func $alloc (param $limbs i32) (result i32)
    (local $ptr i32)
    (local.set $ptr (global.get $heap_ptr))
    ;; Total size: 4 bytes (len) + (limbs * 4 bytes)
    (global.set $heap_ptr 
      (i32.add (local.get $ptr) 
        (i32.add (i32.const 4) (i32.shl (local.get $limbs) (i32.const 2)))))
    (local.get $ptr)
  )

  ;; --- UTILITIES ---

  (func $reset_heap (export "reset_heap")
    (global.set $heap_ptr (i32.const 0))
  )

  (func $bigint_from_limbs (export "bigint_from_limbs") (param $src i32) (result i32)
    (local $len i32)
    (local $dst i32)
    (local.set $len (i32.load (local.get $src)))
    (local.set $dst (call $alloc (local.get $len)))
    (i32.store (local.get $dst) (local.get $len))
    (memory.copy 
      (i32.add (local.get $dst) (i32.const 4)) 
      (i32.add (local.get $src) (i32.const 4)) 
      (i32.shl (local.get $len) (i32.const 2)))
    (local.get $dst)
  )

  (func $bigint_get_limb (export "bigint_get_limb") (param $ptr i32) (param $idx i32) (result i32)
    (i32.load (i32.add (i32.add (local.get $ptr) (i32.const 4)) (i32.shl (local.get $idx) (i32.const 2))))
  )

  (func $bigint_len (export "bigint_len") (param $ptr i32) (result i32) (i32.load (local.get $ptr)))

  (func $bigint_normalize (param $ptr i32)
    (local $len i32)
    (local.set $len (i32.load (local.get $ptr)))
    (loop $continue
      (if (i32.and 
            (i32.gt_u (local.get $len) (i32.const 1))
            (i32.eqz (i32.load (i32.add (local.get $ptr) (i32.shl (local.get $len) (i32.const 2))))))
        (then
          (local.set $len (i32.sub (local.get $len) (i32.const 1)))
          (br $continue)
        )
      )
    )
    (i32.store (local.get $ptr) (local.get $len))
  )

  ;; --- IN-PLACE ARITHMETIC ---

  ;; target += source << (offset * 32 bits)
  (func $add_at (param $target i32) (param $source i32) (param $offset i32)
    (local $i i32)
    (local $len_s i32)
    (local $carry i64)
    (local $sum i64)
    (local $target_limb_ptr i32)
    
    (local.set $len_s (call $bigint_len (local.get $source)))
    (local.set $carry (i64.const 0))
    
    (loop $loop
      (if (i32.or (i32.lt_u (local.get $i) (local.get $len_s)) (i64.gt_u (local.get $carry) (i64.const 0)))
        (then
          (local.set $target_limb_ptr (i32.add (local.get $target) (i32.shl (i32.add (local.get $i) (local.get $offset)) (i32.const 2))))
          (local.set $target_limb_ptr (i32.add (local.get $target_limb_ptr) (i32.const 4)))
          
          (local.set $sum (i64.add (local.get $carry) (i64.extend_i32_u (i32.load (local.get $target_limb_ptr)))))
          
          (if (i32.lt_u (local.get $i) (local.get $len_s))
            (then
              (local.set $sum (i64.add (local.get $sum) (i64.extend_i32_u (i32.load (i32.add (i32.add (local.get $source) (i32.const 4)) (i32.shl (local.get $i) (i32.const 2)))))))
            )
          )
          
          (i32.store (local.get $target_limb_ptr) (i32.wrap_i64 (local.get $sum)))
          (local.set $carry (i64.shr_u (local.get $sum) (i64.const 32)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $loop)
        )
      )
    )
    ;; Update target length if necessary
    (if (i32.gt_u (i32.add (local.get $i) (local.get $offset)) (call $bigint_len (local.get $target)))
      (then
        (i32.store (local.get $target) (i32.add (local.get $i) (local.get $offset)))
      )
    )
  )

  ;; target -= source (In-place, assumes target >= source)
  (func $sub_in_place (param $target i32) (param $source i32)
    (local $i i32)
    (local $len_t i32)
    (local $len_s i32)
    (local $borrow i64)
    (local $diff i64)
    (local $t_ptr i32)
    
    (local.set $len_t (call $bigint_len (local.get $target)))
    (local.set $len_s (call $bigint_len (local.get $source)))
    
    (loop $loop
      (if (i32.lt_u (local.get $i) (local.get $len_t))
        (then
          (local.set $t_ptr (i32.add (i32.add (local.get $target) (i32.const 4)) (i32.shl (local.get $i) (i32.const 2))))
          (local.set $diff (i64.sub (i64.extend_i32_u (i32.load (local.get $t_ptr))) (local.get $borrow)))
          
          (if (i32.lt_u (local.get $i) (local.get $len_s))
            (then
              (local.set $diff (i64.sub (local.get $diff) (i64.extend_i32_u (i32.load (i32.add (i32.add (local.get $source) (i32.const 4)) (i32.shl (local.get $i) (i32.const 2)))))))
            )
          )
          
          (if (i64.lt_s (local.get $diff) (i64.const 0))
            (then 
              (local.set $diff (i64.add (local.get $diff) (i64.const 0x100000000)))
              (local.set $borrow (i64.const 1))
            )
            (else (local.set $borrow (i64.const 0)))
          )
          
          (i32.store (local.get $t_ptr) (i32.wrap_i64 (local.get $diff)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $loop)
        )
      )
    )
    (call $bigint_normalize (local.get $target))
  )

  ;; --- SCHOOLBOOK MULTIPLICATION ---
  
  (func $bigint_mul_simple (param $a i32) (param $b i32) (result i32)
    (local $len_a i32) (local $len_b i32) (local $res i32)
    (local $i i32) (local $j i32)
    (local $carry i64) (local $prod i64)
    
    (local.set $len_a (call $bigint_len (local.get $a)))
    (local.set $len_b (call $bigint_len (local.get $b)))
    (local.set $res (call $alloc (i32.add (local.get $len_a) (local.get $len_b))))
    (i32.store (local.get $res) (i32.add (local.get $len_a) (local.get $len_b)))
    
    ;; Zero out the result memory
    (memory.fill 
      (i32.add (local.get $res) (i32.const 4)) 
      (i32.const 0) 
      (i32.shl (i32.add (local.get $len_a) (local.get $len_b)) (i32.const 2)))
    
    (loop $i_loop
      (if (i32.lt_u (local.get $i) (local.get $len_a))
        (then
          (local.set $carry (i64.const 0))
          (local.set $j (i32.const 0))
          (loop $j_loop
            (if (i32.lt_u (local.get $j) (local.get $len_b))
              (then
                (local.set $prod (i64.add 
                  (i64.mul (i64.extend_i32_u (i32.load (i32.add (i32.add (local.get $a) (i32.const 4)) (i32.shl (local.get $i) (i32.const 2)))))
                           (i64.extend_i32_u (i32.load (i32.add (i32.add (local.get $b) (i32.const 4)) (i32.shl (local.get $j) (i32.const 2))))))
                  (i64.extend_i32_u (i32.load (i32.add (i32.add (local.get $res) (i32.const 4)) (i32.shl (i32.add (local.get $i) (local.get $j)) (i32.const 2)))))))
                  (local.set $prod (i64.add (local.get $prod) (local.get $carry)))
                
                (i32.store (i32.add (i32.add (local.get $res) (i32.const 4)) (i32.shl (i32.add (local.get $i) (local.get $j)) (i32.const 2))) (i32.wrap_i64 (local.get $prod)))
                (local.set $carry (i64.shr_u (local.get $prod) (i64.const 32)))
                (local.set $j (i32.add (local.get $j) (i32.const 1)))
                (br $j_loop)
              )
            )
          )
          (i32.store (i32.add (i32.add (local.get $res) (i32.const 4)) (i32.shl (i32.add (local.get $i) (local.get $len_b)) (i32.const 2))) (i32.wrap_i64 (local.get $carry)))
          (local.set $i (i32.add (local.get $i) (i32.const 1)))
          (br $i_loop)
        )
      )
    )
    (call $bigint_normalize (local.get $res))
    (local.get $res)
  )

  ;; --- KARATSUBA ---

  (func $bigint_karatsuba (export "bigint_karatsuba") (param $x i32) (param $y i32) (result i32)
    (local $len_x i32) (local $len_y i32) (local $m i32)
    (local $x_low i32) (local $x_high i32) (local $y_low i32) (local $y_high i32)
    (local $z0 i32) (local $z1 i32) (local $z2 i32)
    (local $sx i32) (local $sy i32) (local $res i32)
    (local $stack_top i32)

    (local.set $len_x (call $bigint_len (local.get $x)))
    (local.set $len_y (call $bigint_len (local.get $y)))

    ;; Threshold: 32 limbs (approx 1024 bits)
    (if (i32.le_u (if (result i32) (i32.gt_u (local.get $len_x) (local.get $len_y)) (then (local.get $len_x)) (else (local.get $len_y))) (i32.const 32))
      (then (return (call $bigint_mul_simple (local.get $x) (local.get $y))))
    )

    ;; Save pointer for recursion cleanup
    (local.set $stack_top (global.get $heap_ptr))

    (local.set $m (i32.shr_u (i32.add (if (result i32) (i32.gt_u (local.get $len_x) (local.get $len_y)) (then (local.get $len_x)) (else (local.get $len_y))) (i32.const 1)) (i32.const 1)))

    ;; x_low = x[0..m], x_high = x[m..end]
    (local.set $x_low (call $alloc (local.get $m)))
    (i32.store (local.get $x_low) (local.get $m))
    (memory.copy 
        (i32.add (local.get $x_low) (i32.const 4)) 
        (i32.add (local.get $x) (i32.const 4)) 
        (i32.shl (if (result i32) (i32.lt_u (local.get $len_x) (local.get $m)) (then (local.get $len_x)) (else (local.get $m))) (i32.const 2)))
    (if (i32.lt_u (local.get $len_x) (local.get $m))
        (then
            (memory.fill 
                (i32.add (i32.add (local.get $x_low) (i32.const 4)) (i32.shl (local.get $len_x) (i32.const 2)))
                (i32.const 0)
                (i32.shl (i32.sub (local.get $m) (local.get $len_x)) (i32.const 2)))
        )
    )

    (local.set $x_high (call $alloc (if (result i32) (i32.gt_u (local.get $len_x) (local.get $m)) (then (i32.sub (local.get $len_x) (local.get $m))) (else (i32.const 1)))))
    (if (i32.gt_u (local.get $len_x) (local.get $m))
      (then 
        (i32.store (local.get $x_high) (i32.sub (local.get $len_x) (local.get $m)))
        (memory.copy (i32.add (local.get $x_high) (i32.const 4)) (i32.add (local.get $x) (i32.add (i32.const 4) (i32.shl (local.get $m) (i32.const 2)))) (i32.shl (i32.sub (local.get $len_x) (local.get $m)) (i32.const 2)))
      )
      (else (i32.store (local.get $x_high) (i32.const 1)) (i32.store (i32.add (local.get $x_high) (i32.const 4)) (i32.const 0)))
    )

    ;; ... repeat split for y ...
    (local.set $y_low (call $alloc (local.get $m)))
    (i32.store (local.get $y_low) (local.get $m))
    (memory.copy (i32.add (local.get $y_low) (i32.const 4)) (i32.add (local.get $y) (i32.const 4)) (i32.shl (if (result i32) (i32.lt_u (local.get $len_y) (local.get $m)) (then (local.get $len_y)) (else (local.get $m))) (i32.const 2)))
    (if (i32.lt_u (local.get $len_y) (local.get $m))
        (then
            (memory.fill 
                (i32.add (i32.add (local.get $y_low) (i32.const 4)) (i32.shl (local.get $len_y) (i32.const 2)))
                (i32.const 0)
                (i32.shl (i32.sub (local.get $m) (local.get $len_y)) (i32.const 2)))
        )
    )

    (local.set $y_high (call $alloc (if (result i32) (i32.gt_u (local.get $len_y) (local.get $m)) (then (i32.sub (local.get $len_y) (local.get $m))) (else (i32.const 1)))))
    (if (i32.gt_u (local.get $len_y) (local.get $m))
      (then 
        (i32.store (local.get $y_high) (i32.sub (local.get $len_y) (local.get $m)))
        (memory.copy (i32.add (local.get $y_high) (i32.const 4)) (i32.add (local.get $y) (i32.add (i32.const 4) (i32.shl (local.get $m) (i32.const 2)))) (i32.shl (i32.sub (local.get $len_y) (local.get $m)) (i32.const 2)))
      )
      (else (i32.store (local.get $y_high) (i32.const 1)) (i32.store (i32.add (local.get $y_high) (i32.const 4)) (i32.const 0)))
    )

    ;; Recursive calls
    (local.set $z0 (call $bigint_karatsuba (local.get $x_low) (local.get $y_low)))
    (local.set $z2 (call $bigint_karatsuba (local.get $x_high) (local.get $y_high)))
    
    ;; sx = x_low + x_high
    (local.set $sx (call $alloc (i32.add (local.get $m) (i32.const 1))))
    (i32.store (local.get $sx) (local.get $m))
    (memory.copy (i32.add (local.get $sx) (i32.const 4)) (i32.add (local.get $x_low) (i32.const 4)) (i32.shl (local.get $m) (i32.const 2)))
    (call $add_at (local.get $sx) (local.get $x_high) (i32.const 0))

    ;; sy = y_low + y_high
    (local.set $sy (call $alloc (i32.add (local.get $m) (i32.const 1))))
    (i32.store (local.get $sy) (local.get $m))
    (memory.copy (i32.add (local.get $sy) (i32.const 4)) (i32.add (local.get $y_low) (i32.const 4)) (i32.shl (local.get $m) (i32.const 2)))
    (call $add_at (local.get $sy) (local.get $y_high) (i32.const 0))

    ;; z1 = sx * sy
    (local.set $z1 (call $bigint_karatsuba (local.get $sx) (local.get $sy)))

    ;; z1 = z1 - z0 - z2
    (call $sub_in_place (local.get $z1) (local.get $z0))
    (call $sub_in_place (local.get $z1) (local.get $z2))

    ;; res = z0 + z1 << m + z2 << 2m
    (local.set $res (call $alloc (i32.add (local.get $len_x) (local.get $len_y))))
    (memory.fill 
      (i32.add (local.get $res) (i32.const 4)) 
      (i32.const 0) 
      (i32.shl (i32.add (local.get $len_x) (local.get $len_y)) (i32.const 2)))
    (i32.store (local.get $res) (i32.const 0))

    (call $add_at (local.get $res) (local.get $z0) (i32.const 0))
    (call $add_at (local.get $res) (local.get $z1) (local.get $m))
    (call $add_at (local.get $res) (local.get $z2) (i32.shl (local.get $m) (i32.const 1)))

    (call $bigint_normalize (local.get $res))
    
    ;; Copy result to stack_top to free intermediate memory
    (local.set $len_x (call $bigint_len (local.get $res)))
    (memory.copy 
        (i32.add (local.get $stack_top) (i32.const 4))
        (i32.add (local.get $res) (i32.const 4))
        (i32.shl (local.get $len_x) (i32.const 2)))
    (i32.store (local.get $stack_top) (local.get $len_x))
    (global.set $heap_ptr (i32.add (local.get $stack_top) (i32.add (i32.const 4) (i32.shl (local.get $len_x) (i32.const 2)))))
    
    (local.get $stack_top)
  )
)