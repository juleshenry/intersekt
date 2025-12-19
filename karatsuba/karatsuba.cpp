#include <iostream>
#include <vector>
#include <string>
#include <algorithm>
#include <iomanip>
#include <math.h>

using namespace std;

// Using Base 10^9 allows us to fit the product of two digits into a 64-bit long long
// 10^9 * 10^9 = 10^18 < 2^63-1
const long long BASE = 1000000000;

struct BigInt {
    vector<long long> digits;

    BigInt() {}
    
    BigInt(long long v) {
        if (v == 0) digits.push_back(0);
        while (v > 0) {
            digits.push_back(v % BASE);
            v /= BASE;
        }
    }

    BigInt(string s) {
        if (s.empty()) { digits.push_back(0); return; }
        for (int i = (int)s.length(); i > 0; i -= 9) {
            if (i < 9)
                digits.push_back(stoll(s.substr(0, i)));
            else
                digits.push_back(stoll(s.substr(i - 9, 9)));
        }
        removeLeadingZeros();
    }

    void removeLeadingZeros() {
        while (digits.size() > 1 && digits.back() == 0) {
            digits.pop_back();
        }
    }

    void print() const {
        if (digits.empty()) { cout << 0 << endl; return; }
        cout << digits.back();
        for (int i = (int)digits.size() - 2; i >= 0; i--) {
            cout << setfill('0') << setw(9) << digits[i];
        }
        cout << endl;
    }
};

// Helper: Add two BigInts
BigInt add(const BigInt& a, const BigInt& b) {
    BigInt c;
    long long carry = 0;
    size_t n = max(a.digits.size(), b.digits.size());
    for (size_t i = 0; i < n || carry; ++i) {
        long long sum = carry + (i < a.digits.size() ? a.digits[i] : 0) + (i < b.digits.size() ? b.digits[i] : 0);
        c.digits.push_back(sum % BASE);
        carry = sum / BASE;
    }
    return c;
}

// Helper: Subtract two BigInts (assumes a >= b)
BigInt subtract(const BigInt& a, const BigInt& b) {
    BigInt c;
    long long borrow = 0;
    for (size_t i = 0; i < a.digits.size(); ++i) {
        long long sub = a.digits[i] - borrow - (i < b.digits.size() ? b.digits[i] : 0);
        if (sub < 0) {
            sub += BASE;
            borrow = 1;
        } else {
            borrow = 0;
        }
        c.digits.push_back(sub);
    }
    c.removeLeadingZeros();
    return c;
}

// Helper: Shift BigInt by n positions (multiply by BASE^n)
BigInt shift(const BigInt& a, int n) {
    if (a.digits.size() == 1 && a.digits[0] == 0) return a;
    BigInt c;
    c.digits.insert(c.digits.begin(), n, 0);
    c.digits.insert(c.digits.end(), a.digits.begin(), a.digits.end());
    return c;
}

// Karatsuba Multiplication
BigInt multiply(const BigInt& x, const BigInt& y) {
    int n = max(x.digits.size(), y.digits.size());
    
    // Base case: if small enough, use simple multiplication
    if (n <= 1) {
        long long valX = x.digits.empty() ? 0 : x.digits[0];
        long long valY = y.digits.empty() ? 0 : y.digits[0];
        // valX and valY are < BASE (10^9), so product < 10^18, fits in long long
        long long prod = valX * valY;
        return BigInt(prod);
    }

    int k = (n + 1) / 2;

    BigInt xl, xr, yl, yr;
    
    // Split x
    for (size_t i = 0; i < x.digits.size(); ++i) {
        if (i < k) xr.digits.push_back(x.digits[i]);
        else xl.digits.push_back(x.digits[i]);
    }
    if (xr.digits.empty()) xr.digits.push_back(0);
    if (xl.digits.empty()) xl.digits.push_back(0);

    // Split y
    for (size_t i = 0; i < y.digits.size(); ++i) {
        if (i < k) yr.digits.push_back(y.digits[i]);
        else yl.digits.push_back(y.digits[i]);
    }
    if (yr.digits.empty()) yr.digits.push_back(0);
    if (yl.digits.empty()) yl.digits.push_back(0);

    BigInt p1 = multiply(xl, yl);
    BigInt p2 = multiply(xr, yr);
    BigInt p3 = multiply(add(xl, xr), add(yl, yr));

    // Result = p1 * BASE^(2k) + (p3 - p1 - p2) * BASE^k + p2
    BigInt term1 = shift(p1, 2 * k);
    BigInt term2 = shift(subtract(subtract(p3, p1), p2), k);
    
    return add(add(term1, term2), p2);
}

int main() 
{
    // Example: 10^96 requires multiple longs
    cout << "Multiplying large numbers using Karatsuba..." << endl;

    // Test with 10^48 * 10^48 approx 10^96
    cout << "\nTesting 10^96 scale:" << endl;
    string big1(48, '9'); // 48 nines
    string big2(48, '9'); // 48 nines
    
    BigInt ba(big1), bb(big2);
    
    cout << "Number 1 (48 digits): "; ba.print();
    cout << "Number 2 (48 digits): "; bb.print();
    
    BigInt bres = multiply(ba, bb);
    cout << "Result (approx 96 digits): ";
    bres.print();

    return 0;
}
