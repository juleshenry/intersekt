(module
  ;; Helper function to calculate power of 10
  (func $power_of_10 (param $exp i32) (result i32)
    (local $result i32)
    (local $i i32)
    (local.set $result (i32.const 1))
    (local.set $i (i32.const 0))
    (block $break
      (loop $continue
        (br_if $break (i32.ge_u (local.get $i) (local.get $exp)))
        (local.set $result (i32.mul (local.get $result) (i32.const 10)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $continue)
      )
    )
    (local.get $result)
  )

  ;; Helper function to count digits (base 10 size)
  (func $count_digits (param $num i32) (result i32)
    (local $count i32)
    (local $n i32)
    (local.set $n (local.get $num))
    (local.set $count (i32.const 0))
    
    ;; Handle zero case
    (if (i32.eqz (local.get $n))
      (then
        (return (i32.const 1))
      )
    )
    
    (block $break
      (loop $continue
        (br_if $break (i32.eqz (local.get $n)))
        (local.set $count (i32.add (local.get $count) (i32.const 1)))
        (local.set $n (i32.div_u (local.get $n) (i32.const 10)))
        (br $continue)
      )
    )
    (local.get $count)
  )

  ;; Helper function to get maximum of two numbers
  (func $max (param $a i32) (param $b i32) (result i32)
    (if (result i32) (i32.gt_u (local.get $a) (local.get $b))
      (then (local.get $a))
      (else (local.get $b))
    )
  )

  ;; Karatsuba multiplication algorithm
  (func $karatsuba (param $x i32) (param $y i32) (result i32)
    (local $m i32)
    (local $m2 i32)
    (local $high1 i32)
    (local $low1 i32)
    (local $high2 i32)
    (local $low2 i32)
    (local $z0 i32)
    (local $z1 i32)
    (local $z2 i32)
    (local $power i32)
    (local $power2 i32)
    (local $sum1 i32)
    (local $sum2 i32)

    ;; Base case: if either number is less than 10, use simple multiplication
    (if (i32.or 
          (i32.lt_u (local.get $x) (i32.const 10))
          (i32.lt_u (local.get $y) (i32.const 10)))
      (then
        (return (i32.mul (local.get $x) (local.get $y)))
      )
    )

    ;; Calculate the number of digits and split point
    (local.set $m (call $max 
      (call $count_digits (local.get $x))
      (call $count_digits (local.get $y))
    ))
    (local.set $m2 (i32.shr_u (local.get $m) (i32.const 1)))  ;; m2 = m / 2
    
    ;; Calculate power of 10 for splitting: 10^m2
    (local.set $power (call $power_of_10 (local.get $m2)))
    
    ;; Split x into high and low parts
    (local.set $high1 (i32.div_u (local.get $x) (local.get $power)))
    (local.set $low1 (i32.rem_u (local.get $x) (local.get $power)))
    
    ;; Split y into high and low parts
    (local.set $high2 (i32.div_u (local.get $y) (local.get $power)))
    (local.set $low2 (i32.rem_u (local.get $y) (local.get $power)))

    ;; Three recursive calls
    (local.set $z0 (call $karatsuba (local.get $low1) (local.get $low2)))
    (local.set $z2 (call $karatsuba (local.get $high1) (local.get $high2)))
    
    ;; Calculate (low1 + high1) * (low2 + high2)
    (local.set $sum1 (i32.add (local.get $low1) (local.get $high1)))
    (local.set $sum2 (i32.add (local.get $low2) (local.get $high2)))
    (local.set $z1 (call $karatsuba (local.get $sum1) (local.get $sum2)))
    
    ;; Calculate z1 - z2 - z0
    (local.set $z1 (i32.sub (local.get $z1) (local.get $z2)))
    (local.set $z1 (i32.sub (local.get $z1) (local.get $z0)))
    
    ;; Calculate power for final combination: 10^(2*m2)
    (local.set $power2 (call $power_of_10 (i32.mul (local.get $m2) (i32.const 2))))
    
    ;; Combine results: z2 * 10^(2*m2) + z1 * 10^m2 + z0
    (return
      (i32.add
        (i32.add
          (i32.mul (local.get $z2) (local.get $power2))
          (i32.mul (local.get $z1) (local.get $power))
        )
        (local.get $z0)
      )
    )
  )

  ;; Regular multiplication for comparison
  (func (export "mult") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.mul
  )

  ;; Export the Karatsuba function
  (func (export "karat") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    call $karatsuba
  )
)
