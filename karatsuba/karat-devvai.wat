(func $karatsuba (param $num1 i32) (param $num2 i32) (result i32)
    (if (i32.or
            (i32.lt_s (get_local $num1) (i32.const 10))
            (i32.lt_s (get_local $num2) (i32.const 10))
        (then
            (return
                (i32.mul (get_local $num1) (get_local $num2))
            )
        )
    )
    (local $m i32)
    (local $m2 i32)
    (local $high1 i32)
    (local $low1 i32)
    (local $high2 i32)
    (local $low2 i32)
    (local $z0 i32)
    (local $z1 i32)
    (local $z2 i32)
    
    ;; Calculate the size of the numbers
    (set_local $m (call $size_base10 (get_local $num1)))
    (set_local $m2 (i32.shr_u (get_local $m) (i32.const 1)))
    
    ;; Split the digit sequences in the middle
    (set_local $high1 (call $split_at (get_local $num1) (get_local $m2)))
    (set_local $low1 (i32.sub (get_local $num1) (get_local $high1)))
    (set_local $high2 (call $split_at (get_local $num2) (get_local $m2)))
    (set_local $low2 (i32.sub (get_local $num2) (get_local $high2)))
    
    ;; Recursive calls
    (set_local $z0 (call $karatsuba (get_local $low1) (get_local $low2)))
    (set_local $z1 (call $karatsuba (i32.add (get_local $low1) (get_local $high1)) (i32.add (get_local $low2) (get_local $high2))))
    (set_local $z2 (call $karatsuba (get_local $high1) (get_local $high2)))
    
    ;; Combine the results
    (return
        (i32.add
            (i32.add
                (i32.mul (get_local $z2) (i32.const (10 ** (get_local $m2 * 2))))
                (i32.mul (i32.sub (i32.sub (get_local $z1) (get_local $z2)) (get_local $z0)) (i32.const (10 ** get_local $m2)))
            )
            (get_local $z0)
        )
    )
)
