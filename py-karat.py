def karatsuba(num1, num2):
    if num1 < 2**64 or num2 < 2**64:
        return num1 * num2
    m = max(len(str(num1)), len(str(num2)))
    m2 = m // 2 
    high1, low1 = divmod(num1, 10**m2)
    high2, low2 = divmod(num2, 10**m2)
    z0 = karatsuba(low1, low2)
    z1 = karatsuba(low1 + high1, low2 + high2)
    z2 = karatsuba(high1, high2)
    return (z2 * 10**(2 * m2)) + ((z1 - z2 - z0) * 10**m2) + z0

def example_karatsuba_00():
    num1 = 0
    num2 = 0
    result = karatsuba(num1, num2)
    print(f"The product of {num1} and {num2} is {result}")

def example_karatsuba_01():
    num1 = 1
    num2 = 0
    result = karatsuba(num1, num2)
    print(f"The product of {num1} and {num2} is {result}")

def example_karatsuba_11():
    num1 = 1
    num2 = 1
    result = karatsuba(num1, num2)
    print(f"The product of {num1} and {num2} is {result}")

(example_karatsuba_01(),example_karatsuba_00(),example_karatsuba_11(),)

import time
a = b =  1e50
n = 10

def time_mult_karat(n):
    start = time.time()
    zs = [karatsuba(a,b) for _ in range(n)]
    end = time.time()
    print(f"Karat:\t time taken for {n} multiplications: {end - start} seconds")
    return zs

def time_mult_normal(n):
    start = time.time()
    zs = [a*b for i in range(n)]
    end = time.time()
    print(f"Normal:\t time taken for {n} multiplications: {end - start} seconds")
    return zs

x,y,=time_mult_karat(n),time_mult_normal(n)
assert x == y

# Threshold := 10
# Karat:   time taken for 1000 multiplications: 0.0031778812408447266 seconds
# Normal:  time taken for 1000 multiplications: 4.100799560546875e-05 seconds

# Threshold := 2**64
# Karat:   time taken for 1000 multiplications: 0.0031778812408447266 seconds
# Normal:  time taken for 1000 multiplications: 4.100799560546875e-05 seconds
# CONCLUSION! EVEN for the max recursive limit set by python, normal multiplication is still way faster!