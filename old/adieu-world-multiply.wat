(function() {
  "use strict";
  
  function karatsuba(a, b) {
    if (a < 10 && b < 10) {
      return a * b; // fall back to traditional multiplication
    }
    
    const m = max(size_base10(a), size_base10(b));
    const m2 = floor(m / 2);
    
    const high1 = split_at(a, m2)[0];
    const low1 = split_at(a, m2)[1];
    const high2 = split_at(b, m2)[0];
    const low2 = split_at(b, m2)[1];
    
    return (karatsuba(low1, low2) + karatsuba(high1, high2)) * 10 ^ m2;
  }
  
  function size_base10(n) {
    return n.toString().length;
  }
  
  function split_at(n, size) {
    const high = n.substring(0, size);
    const low = n.substring(size);
    return [high, low];
  }
})();
