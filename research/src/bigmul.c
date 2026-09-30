// bigmul.c — balanced n×n big-integer multiplication kernels for WebAssembly.
//
// Numbers are little-endian arrays of 32-bit limbs in linear memory. All kernels
// write into caller-provided buffers; nothing allocates on the hot path.
//
//   mul_school   O(n^2) schoolbook, row-wise (baseline)
//   mul_comba    O(n^2) column-wise with split lo/hi accumulators (no carry chain)
//   mul_kara     O(n^1.585) subtractive Karatsuba over a scratch buffer
//   mul_fft      O(n log n) complex f64 FFT, SIMD (split re/im arrays)
//   mul_auto     picks one of the above by size
//
// Build: see ../build.sh

#include <stdint.h>
#include <wasm_simd128.h>

typedef uint32_t u32;
typedef uint64_t u64;
typedef int64_t i64;

#define EXPORT(name) __attribute__((export_name(#name)))

// ---------------------------------------------------------------------------
// Memory: a bump allocator the JS harness uses once to lay out its buffers.

extern unsigned char __heap_base;
static uintptr_t hp;

EXPORT(heap_reset) void heap_reset(void) {
  hp = ((uintptr_t)&__heap_base + 63) & ~(uintptr_t)63;
}

EXPORT(alloc) void *alloc(u32 bytes) {
  if (!hp) heap_reset();
  uintptr_t p = hp;
  hp = (hp + bytes + 63) & ~(uintptr_t)63;
  uintptr_t have = __builtin_wasm_memory_size(0) * 65536u;
  if (hp > have) {
    if (__builtin_wasm_memory_grow(0, (hp - have + 65535) / 65536) < 0) return 0;
  }
  return (void *)p;
}

// ---------------------------------------------------------------------------
// Limb-vector helpers.

static u32 add_n(u32 *r, const u32 *a, const u32 *b, int n) {
  u64 c = 0;
  for (int i = 0; i < n; i++) { c += (u64)a[i] + b[i]; r[i] = (u32)c; c >>= 32; }
  return (u32)c;
}

static u32 sub_n(u32 *r, const u32 *a, const u32 *b, int n) {
  u64 br = 0;
  for (int i = 0; i < n; i++) { u64 t = (u64)a[i] - b[i] - br; r[i] = (u32)t; br = (t >> 32) & 1; }
  return (u32)br;
}

// r[0..n) += c, returns carry out
static u32 inc_n(u32 *r, int n, u32 c) {
  for (int i = 0; c && i < n; i++) { u64 t = (u64)r[i] + c; r[i] = (u32)t; c = (u32)(t >> 32); }
  return c;
}

static u32 dec_n(u32 *r, int n, u32 br) {
  for (int i = 0; br && i < n; i++) { u32 x = r[i]; r[i] = x - br; br = x < br; }
  return br;
}

// r = |x - y| where x has k limbs and y has h <= k limbs. Returns 1 if x < y.
static int absdiff(u32 *r, const u32 *x, int k, const u32 *y, int h) {
  int xbig = 1;
  int i = k - 1;
  for (; i >= h; i--) if (x[i]) goto have;  // x has nonzero limbs above y's top
  for (i = h - 1; i >= 0; i--) {
    if (x[i] != y[i]) { xbig = x[i] > y[i]; goto have; }
  }
have:
  if (xbig) {
    u32 br = sub_n(r, x, y, h);
    for (i = h; i < k; i++) r[i] = x[i];
    dec_n(r + h, k - h, br);
    return 0;
  }
  // y > x implies x's limbs above h are all zero
  sub_n(r, y, x, h);
  for (i = h; i < k; i++) r[i] = 0;
  return 1;
}

// ---------------------------------------------------------------------------
// Schoolbook, row-wise: r[0..2n) = a[0..n) * b[0..n)

EXPORT(mul_school) void mul_school(u32 *restrict r, const u32 *restrict a, const u32 *restrict b, int n) {
  u64 c = 0;
  u32 a0 = a[0];
  for (int j = 0; j < n; j++) { u64 t = (u64)a0 * b[j] + c; r[j] = (u32)t; c = t >> 32; }
  r[n] = (u32)c;
  for (int i = 1; i < n; i++) {
    u32 ai = a[i];
    u32 *ri = r + i;
    c = 0;
    for (int j = 0; j < n; j++) { u64 t = (u64)ai * b[j] + ri[j] + c; ri[j] = (u32)t; c = t >> 32; }
    ri[n] = (u32)c;
  }
}

// Schoolbook, column-wise (Comba). Each 64-bit product is split into its low
// and high 32-bit halves, which are summed in separate 64-bit accumulators, so
// the inner loop has no carry dependency and vectorises (i64x2.extmul).
EXPORT(mul_comba) void mul_comba(u32 *restrict r, const u32 *restrict a, const u32 *restrict b, int n) {
  u64 carry = 0;
  for (int k = 0; k < 2 * n - 1; k++) {
    int i0 = k < n ? 0 : k - n + 1;
    int i1 = k < n ? k : n - 1;
    u64 lo = 0, hi = 0;
    for (int i = i0; i <= i1; i++) {
      u64 p = (u64)a[i] * b[k - i];
      lo += (u32)p;
      hi += p >> 32;
    }
    lo += carry & 0xffffffffu;
    r[k] = (u32)lo;
    carry = hi + (carry >> 32) + (lo >> 32);
  }
  r[2 * n - 1] = (u32)carry;
}

// SIMD Comba: b is first reversed into brev so each column is a contiguous dot
// product a[i0..i1] · brev[..]. 4 products per two i64x2.extmul instructions.
static void mul_comba_simd_rev(u32 *restrict r, const u32 *restrict a, const u32 *restrict brev, int n) {
  // brev[t] = b[n-1-t];  b[k-i] = brev[n-1-k+i]
  const v128_t mask = wasm_i64x2_splat(0xffffffff);
  u64 carry = 0;
  for (int k = 0; k < 2 * n - 1; k++) {
    int i0 = k < n ? 0 : k - n + 1;
    int i1 = k < n ? k : n - 1;
    const u32 *pa = a + i0;
    const u32 *pb = brev + (n - 1 - k + i0);
    int len = i1 - i0 + 1;
    v128_t vlo = wasm_i64x2_const(0, 0), vhi = wasm_i64x2_const(0, 0);
    int i = 0;
    for (; i + 4 <= len; i += 4) {
      v128_t x = wasm_v128_load(pa + i), y = wasm_v128_load(pb + i);
      v128_t p0 = wasm_u64x2_extmul_low_u32x4(x, y);
      v128_t p1 = wasm_u64x2_extmul_high_u32x4(x, y);
      vlo = wasm_i64x2_add(vlo, wasm_i64x2_add(wasm_v128_and(p0, mask), wasm_v128_and(p1, mask)));
      vhi = wasm_i64x2_add(vhi, wasm_i64x2_add(wasm_u64x2_shr(p0, 32), wasm_u64x2_shr(p1, 32)));
    }
    u64 lo = wasm_i64x2_extract_lane(vlo, 0) + wasm_i64x2_extract_lane(vlo, 1);
    u64 hi = wasm_i64x2_extract_lane(vhi, 0) + wasm_i64x2_extract_lane(vhi, 1);
    for (; i < len; i++) { u64 p = (u64)pa[i] * pb[i]; lo += (u32)p; hi += p >> 32; }
    lo += carry & 0xffffffffu;
    r[k] = (u32)lo;
    carry = hi + (carry >> 32) + (lo >> 32);
  }
  r[2 * n - 1] = (u32)carry;
}

static u32 revbuf[1 << 17];
EXPORT(mul_comba_simd) void mul_comba_simd(u32 *restrict r, const u32 *restrict a, const u32 *restrict b, int n) {
  // n <= 2^17
  for (int t = 0; t < n; t++) revbuf[t] = b[n - 1 - t];
  mul_comba_simd_rev(r, a, revbuf, n);
}

// ---------------------------------------------------------------------------
// Karatsuba (subtractive variant: no carries out of the half-sums).
//   a = a0 + a1·B^k, b = b0 + b1·B^k, k = ceil(n/2), h = n - k
//   a0b1 + a1b0 = a0b0 + a1b1 - (a0 - a1)(b0 - b1)
// Scratch t needs ~4n + O(log n) limbs.

static int kara_thresh = 96;
static int kara_base = 1;  // 0 = row schoolbook, 1 = SIMD comba
EXPORT(set_kara) void set_kara(int thresh, int base) { kara_thresh = thresh; kara_base = base; }

static void base_mul(u32 *r, const u32 *a, const u32 *b, int n) {
  if (kara_base) mul_comba_simd(r, a, b, n); else mul_school(r, a, b, n);
}

static void kara(u32 *r, const u32 *a, const u32 *b, int n, u32 *t) {
  if (n < kara_thresh) { base_mul(r, a, b, n); return; }
  int k = (n + 1) >> 1, h = n - k;
  int sa = absdiff(t, a, k, a + k, h);        // |a0 - a1|
  int sb = absdiff(t + k, b, k, b + k, h);    // |b0 - b1|
  u32 *d = t + 2 * k, *rest = t + 4 * k;
  kara(d, t, t + k, k, rest);                  // d = |a0-a1|·|b0-b1|
  kara(r, a, b, k, rest);                      // z0 -> r[0, 2k)
  kara(r + 2 * k, a + k, b + k, h, rest);      // z2 -> r[2k, 2n)
  // w = z0 + z2 -+ d   (2k+1 limbs, lives in rest)
  u32 *w = rest;
  u32 c = add_n(w, r, r + 2 * k, 2 * h);
  for (int i = 2 * h; i < 2 * k; i++) w[i] = r[i];
  c = inc_n(w + 2 * h, 2 * k - 2 * h, c);
  if (sa == sb) c -= sub_n(w, w, d, 2 * k);    // (a0-a1)(b0-b1) >= 0
  else          c += add_n(w, w, d, 2 * k);
  w[2 * k] = c;
  // r[k ..) += w
  int wl = 2 * k + 1, room = 2 * n - k;
  if (wl > room) wl = room;                    // top limb of w is 0 when it would not fit
  u32 cc = add_n(r + k, r + k, w, wl);
  inc_n(r + k + wl, room - wl, cc);
}

EXPORT(mul_kara) void mul_kara(u32 *r, const u32 *a, const u32 *b, int n, u32 *scratch) {
  kara(r, a, b, n, scratch);
}

// ---------------------------------------------------------------------------
// FFT multiplication in double precision.
//
// Each operand is cut into `bits`-bit coefficients. The two coefficient vectors
// are packed as one complex signal z = a + i·b and transformed once; the
// spectrum of the product follows from Z_k and conj(Z_{-k}):
//     A_k·B_k = (Z_k^2 - conj(Z_{-k})^2) / 4i
// One forward and one inverse complex FFT of size N >= len(a)+len(b) coefficients.
//
// Forward: iterative radix-2 DIT, input written in bit-reversed order.
// Inverse: radix-2 DIF with conjugate twiddles, output read in bit-reversed order.
// Data are split arrays (re[], im[]) so f64x2 processes two butterflies at once.
// Twiddles: per-stage contiguous table tw[s + j] = exp(-i·pi·j/s), 0 <= j < s.

static double *twr, *twi, *fre, *fim;
static double *tsr, *tsi;  // W^-k = exp(+2*pi*i*k/N) stored at bit-reversed position rev_{N/2}(k)
static int plan_n = 0;

// sin/cos(pi*x) for x in [0, 1/4]: Taylor series, error < 1e-17.
static void sincospi_small(double x, double *s, double *c) {
  const double PI = 3.14159265358979323846;
  double t = PI * x, t2 = t * t;
  double sn = 0, cs = 0, term;
  // sin
  term = t; sn = t;
  for (int k = 1; k < 12; k++) { term *= -t2 / ((2 * k) * (2 * k + 1)); sn += term; }
  term = 1; cs = 1;
  for (int k = 1; k < 12; k++) { term *= -t2 / ((2 * k - 1) * (2 * k)); cs += term; }
  *s = sn; *c = cs;
}

// sin/cos(pi*j/m), m a power of two, 0 <= j < m; octant reduction on exact integers
static void sincospi_frac(u32 j, u32 m, double *s, double *c) {
  if (m < 4) { if (j == 0) { *s = 0; *c = 1; } else { *s = 1; *c = 0; } return; }  // 0 or pi/2
  u32 q = m / 4;                                       // j = q  <=>  angle pi/4
  double ss, cc;
  if (j <= q)          { sincospi_small((double)j / m, s, c); }
  else if (j <= 2 * q) { sincospi_small((double)(2 * q - j) / m, &ss, &cc); *s = cc; *c = ss; }
  else                 { sincospi_frac(m - j, m, &ss, &cc); *s = ss; *c = -cc; }
}

EXPORT(fft_plan) int fft_plan(int n) {
  if (n <= plan_n) return plan_n;
  twr = alloc(n * 8); twi = alloc(n * 8);
  fre = alloc(n * 8); fim = alloc(n * 8);
  tsr = alloc(n * 4); tsi = alloc(n * 4);
  if (!tsi) return 0;
  plan_n = n;
  // twiddles for the largest stage, then subsampled for smaller ones
  int half = n / 2;
  for (int j = 0; j < half; j++) {
    double s, c;
    sincospi_frac(j, half, &s, &c);  // angle pi*j/half
    twr[half + j] = c; twi[half + j] = -s;
  }
  for (int s = half / 2; s >= 1; s >>= 1) {
    int step = half / s;
    for (int j = 0; j < s; j++) { twr[s + j] = twr[half + j * step]; twi[s + j] = twi[half + j * step]; }
  }
  // rev_H(p) for a smaller H' is rev_{H'}(p)·(H/H'), so this table serves every N <= n
  int lgh = __builtin_ctz(half);
  for (int p = 0; p < half; p++) {
    u32 k = lgh ? __builtin_bitreverse32(p) >> (32 - lgh) : 0;
    tsr[p] = twr[half + k]; tsi[p] = -twi[half + k];
  }
  return n;
}

// One radix-2 stage of half-size s over a block of 2s points starting at x.
// Forward DIF: (u, v) -> (u + v, (u - v)·w).  Inverse DIT: (u, v) -> (u ± v·conj(w)).
static void dif_stage(double *re, double *im, int n, int s) {
  const double *wr = twr + s, *wi = twi + s;
  if (s == 1) {
    for (int b = 0; b < n; b += 2) {
      double ur = re[b], ui = im[b], vr = re[b + 1], vi = im[b + 1];
      re[b] = ur + vr; im[b] = ui + vi; re[b + 1] = ur - vr; im[b + 1] = ui - vi;
    }
    return;
  }
  for (int b = 0; b < n; b += 2 * s) {
    double *xr = re + b, *xi = im + b, *yr = re + b + s, *yi = im + b + s;
    for (int j = 0; j < s; j += 2) {
      v128_t ar = wasm_v128_load(xr + j), ai = wasm_v128_load(xi + j);
      v128_t br = wasm_v128_load(yr + j), bi = wasm_v128_load(yi + j);
      v128_t cr = wasm_v128_load(wr + j), ci = wasm_v128_load(wi + j);
      v128_t dr = wasm_f64x2_sub(ar, br), di = wasm_f64x2_sub(ai, bi);
      wasm_v128_store(xr + j, wasm_f64x2_add(ar, br)); wasm_v128_store(xi + j, wasm_f64x2_add(ai, bi));
      wasm_v128_store(yr + j, wasm_f64x2_sub(wasm_f64x2_mul(dr, cr), wasm_f64x2_mul(di, ci)));
      wasm_v128_store(yi + j, wasm_f64x2_add(wasm_f64x2_mul(dr, ci), wasm_f64x2_mul(di, cr)));
    }
  }
}

static void dit_stage(double *re, double *im, int n, int s) {
  const double *wr = twr + s, *wi = twi + s;
  if (s == 1) {
    for (int b = 0; b < n; b += 2) {
      double ur = re[b], ui = im[b], vr = re[b + 1], vi = im[b + 1];
      re[b] = ur + vr; im[b] = ui + vi; re[b + 1] = ur - vr; im[b + 1] = ui - vi;
    }
    return;
  }
  for (int b = 0; b < n; b += 2 * s) {
    double *xr = re + b, *xi = im + b, *yr = re + b + s, *yi = im + b + s;
    for (int j = 0; j < s; j += 2) {
      v128_t ar = wasm_v128_load(xr + j), ai = wasm_v128_load(xi + j);
      v128_t br = wasm_v128_load(yr + j), bi = wasm_v128_load(yi + j);
      v128_t cr = wasm_v128_load(wr + j), ci = wasm_v128_load(wi + j);
      // v = b·conj(c)
      v128_t vr = wasm_f64x2_add(wasm_f64x2_mul(br, cr), wasm_f64x2_mul(bi, ci));
      v128_t vi = wasm_f64x2_sub(wasm_f64x2_mul(bi, cr), wasm_f64x2_mul(br, ci));
      wasm_v128_store(xr + j, wasm_f64x2_add(ar, vr)); wasm_v128_store(xi + j, wasm_f64x2_add(ai, vi));
      wasm_v128_store(yr + j, wasm_f64x2_sub(ar, vr)); wasm_v128_store(yi + j, wasm_f64x2_sub(ai, vi));
    }
  }
}

// Radix-4 passes: the stages of half-size 2q and q fused, so each pass reads and
// writes the data once instead of twice.
#define LD(p) wasm_v128_load(p)
#define ST(p, v) wasm_v128_store(p, v)
#define ADD wasm_f64x2_add
#define SUB wasm_f64x2_sub
#define MUL wasm_f64x2_mul
// (xr + i xi)·(cr + i ci)
#define CMUL(or, oi, xr, xi, cr, ci) do { v128_t _r = SUB(MUL(xr, cr), MUL(xi, ci)); \
  oi = ADD(MUL(xr, ci), MUL(xi, cr)); or = _r; } while (0)
// (xr + i xi)·conj(cr + i ci)
#define CMULC(or, oi, xr, xi, cr, ci) do { v128_t _r = ADD(MUL(xr, cr), MUL(xi, ci)); \
  oi = SUB(MUL(xi, cr), MUL(xr, ci)); or = _r; } while (0)

static void dif4_pass(double *re, double *im, int n, int q) {  // q >= 2
  const double *w1r = twr + 2 * q, *w1i = twi + 2 * q;
  for (int b = 0; b < n; b += 4 * q) {
    double *r0 = re + b, *i0 = im + b;
    for (int j = 0; j < q; j += 2) {
      v128_t x0r = LD(r0 + j), x0i = LD(i0 + j), x1r = LD(r0 + j + q), x1i = LD(i0 + j + q);
      v128_t x2r = LD(r0 + j + 2 * q), x2i = LD(i0 + j + 2 * q), x3r = LD(r0 + j + 3 * q), x3i = LD(i0 + j + 3 * q);
      // w1(j + q) = -i·w1(j), w2(j) = w1(j)^2: one twiddle load instead of three
      v128_t ar = LD(w1r + j), ai = LD(w1i + j), br = ai, bi = wasm_f64x2_neg(ar);
      v128_t cr = SUB(MUL(ar, ar), MUL(ai, ai)), ci = MUL(ADD(ai, ai), ar);
      v128_t a0r = ADD(x0r, x2r), a0i = ADD(x0i, x2i), a1r = ADD(x1r, x3r), a1i = ADD(x1i, x3i);
      v128_t a2r, a2i, a3r, a3i;
      CMUL(a2r, a2i, SUB(x0r, x2r), SUB(x0i, x2i), ar, ai);
      CMUL(a3r, a3i, SUB(x1r, x3r), SUB(x1i, x3i), br, bi);
      v128_t y1r, y1i, y3r, y3i;
      CMUL(y1r, y1i, SUB(a0r, a1r), SUB(a0i, a1i), cr, ci);
      CMUL(y3r, y3i, SUB(a2r, a3r), SUB(a2i, a3i), cr, ci);
      ST(r0 + j, ADD(a0r, a1r)); ST(i0 + j, ADD(a0i, a1i));
      ST(r0 + j + q, y1r); ST(i0 + j + q, y1i);
      ST(r0 + j + 2 * q, ADD(a2r, a3r)); ST(i0 + j + 2 * q, ADD(a2i, a3i));
      ST(r0 + j + 3 * q, y3r); ST(i0 + j + 3 * q, y3i);
    }
  }
}

static void dit4_pass(double *re, double *im, int n, int q) {  // q >= 2
  const double *w1r = twr + 2 * q, *w1i = twi + 2 * q;
  for (int b = 0; b < n; b += 4 * q) {
    double *r0 = re + b, *i0 = im + b;
    for (int j = 0; j < q; j += 2) {
      v128_t x0r = LD(r0 + j), x0i = LD(i0 + j), x1r = LD(r0 + j + q), x1i = LD(i0 + j + q);
      v128_t x2r = LD(r0 + j + 2 * q), x2i = LD(i0 + j + 2 * q), x3r = LD(r0 + j + 3 * q), x3i = LD(i0 + j + 3 * q);
      // w1(j + q) = -i·w1(j), w2(j) = w1(j)^2: one twiddle load instead of three
      v128_t ar = LD(w1r + j), ai = LD(w1i + j), br = ai, bi = wasm_f64x2_neg(ar);
      v128_t cr = SUB(MUL(ar, ar), MUL(ai, ai)), ci = MUL(ADD(ai, ai), ar);
      v128_t v1r, v1i, v3r, v3i;
      CMULC(v1r, v1i, x1r, x1i, cr, ci);
      CMULC(v3r, v3i, x3r, x3i, cr, ci);
      v128_t a0r = ADD(x0r, v1r), a0i = ADD(x0i, v1i), a1r = SUB(x0r, v1r), a1i = SUB(x0i, v1i);
      v128_t a2r = ADD(x2r, v3r), a2i = ADD(x2i, v3i), a3r = SUB(x2r, v3r), a3i = SUB(x2i, v3i);
      v128_t u2r, u2i, u3r, u3i;
      CMULC(u2r, u2i, a2r, a2i, ar, ai);
      CMULC(u3r, u3i, a3r, a3i, br, bi);
      ST(r0 + j, ADD(a0r, u2r)); ST(i0 + j, ADD(a0i, u2i));
      ST(r0 + j + 2 * q, SUB(a0r, u2r)); ST(i0 + j + 2 * q, SUB(a0i, u2i));
      ST(r0 + j + q, ADD(a1r, u3r)); ST(i0 + j + q, ADD(a1i, u3i));
      ST(r0 + j + 3 * q, SUB(a1r, u3r)); ST(i0 + j + 3 * q, SUB(a1i, u3i));
    }
  }
}

// In-cache transform: radix-4 passes while >= 2 stages with q >= 2 remain, radix-2 for the rest.
static void dif_block(double *re, double *im, int n) {
  int s = n / 2;
  for (; s >= 4; s >>= 2) dif4_pass(re, im, n, s / 2);
  for (; s >= 1; s >>= 1) dif_stage(re, im, n, s);
}
static void dit_block(double *re, double *im, int n) {
  int s = 1;
  // mirror of dif_block: radix-2 for the low stages dif_block left, then radix-4
  int lg = __builtin_ctz(n), r2 = 0;
  for (int t = n / 2; t >= 4; t >>= 2) r2 += 2;
  r2 = lg - r2;  // stages done by radix-2 in dif_block
  for (int k = 0; k < r2; k++, s <<= 1) dit_stage(re, im, n, s);
  for (; s < n; s <<= 2) dit4_pass(re, im, n, s);
}

// Depth-first recursion: once a sub-transform fits in L1 (FFT_BLOCK points of
// re+im = 64 KiB) all its remaining stages run while it stays cache-resident.
// Above that, each level is one radix-4 pass followed by four quarter-size transforms.
#define FFT_BLOCK 4096
static void fft_dif(double *re, double *im, int n) {  // natural in, bit-reversed out
  if (n <= FFT_BLOCK) { dif_block(re, im, n); return; }
  dif4_pass(re, im, n, n / 4);
  for (int k = 0; k < 4; k++) fft_dif(re + k * (n / 4), im + k * (n / 4), n / 4);
}
static void fft_dit_inv(double *re, double *im, int n) {  // bit-reversed in, natural out
  if (n <= FFT_BLOCK) { dit_block(re, im, n); return; }
  for (int k = 0; k < 4; k++) fft_dit_inv(re + k * (n / 4), im + k * (n / 4), n / 4);
  dit4_pass(re, im, n, n / 4);
}

static int fft_bits_override = 0, fft_budget = 56, fft_balanced = 1, fft_check = 1;
EXPORT(set_fft) void set_fft(int bits, int budget, int balanced, int check) {
  fft_bits_override = bits; fft_budget = budget; fft_balanced = balanced; fft_check = check;
}

static int fft_size(int nlimbs, int bits) {
  int coefs = (nlimbs * 32 + bits - 1) / bits;
  int N = 1;
  while (N < 2 * coefs + 2) N <<= 1;
  return N;
}

// Largest coefficient size with 2*bits + log2(N) <= budget.
static int bits_for_budget(int nlimbs, int budget) {
  for (int bits = 20; bits >= 6; bits--)
    if (2 * bits + __builtin_ctz(fft_size(nlimbs, bits)) <= budget) return bits;
  return 6;
}
static int choose_bits(int nlimbs) {
  return fft_bits_override ? fft_bits_override : bits_for_budget(nlimbs, fft_budget);
}
static double max_err;
static int last_bits, retries;
EXPORT(fft_max_err) double fft_max_err(void) { return max_err; }
EXPORT(fft_last_bits) int fft_last_bits(void) { return last_bits; }
EXPORT(fft_retries) int fft_retries(void) { return retries; }

// Write a's `bits`-bit coefficients into dst[]. Balanced
// digits lie in [-2^(bits-1), 2^(bits-1)): 4x smaller products, random signs.
static void load_coefs(double *dst, const u32 *a, int n, int bits, int N) {
  u32 mask = (1u << bits) - 1, half = 1u << (bits - 1);
  u64 buf = 0; int have = 0, i = 0, j = 0; u32 c = 0;
  int coefs = (n * 32 + bits - 1) / bits;
  for (; j < coefs; j++) {
    if (have < bits) { if (i < n) buf |= (u64)a[i++] << have; have += 32; }
    u32 d = (u32)(buf & mask) + c;
    buf >>= bits; have -= bits;
    if (fft_balanced && d >= half) { dst[j] = (double)((i64)d - ((i64)1 << bits)); c = 1; }
    else { dst[j] = (double)d; c = 0; }
  }
  dst[j++] = (double)c;
  for (; j < N; j++) dst[j] = 0.0;
}

// O(n) residues used to verify each FFT product (mod 2^32-1 and mod 2^31-1).
#define M32 0xffffffffull
#define P31 0x7fffffffull
static u64 fold32(u64 t) { t = (t & M32) + (t >> 32); t = (t & M32) + (t >> 32); return t == M32 ? 0 : t; }
static u64 fold31(u64 t) { t = (t & P31) + (t >> 31); t = (t & P31) + (t >> 31); return t >= P31 ? t - P31 : t; }
// Both residues in one pass with independent iterations (vectorisable):
//   a mod 2^32-1 = sum a_i;   a mod 2^31-1 = sum a_i·2^(i mod 31)   since 2^32 = 2 (mod 2^31-1)
static void residues(const u32 *a, int n, u64 *r32, u64 *r31) {
  u64 s32 = 0, s31 = 0;
  int i = 0;
  for (; i + 31 <= n; i += 31) {           // n < 2^32 limbs: no u64 overflow
    for (int k = 0; k < 31; k++) {
      u64 t = (u64)a[i + k] << k;          // < 2^62
      s32 += a[i + k];
      s31 += (t & P31) + (t >> 31);        // < 2^32 per term
    }
  }
  for (int k = 0; i < n; i++, k++) { u64 t = (u64)a[i] << k; s32 += a[i]; s31 += (t & P31) + (t >> 31); }
  *r32 = fold32(s32); *r31 = fold31(s31);
}


// Pointwise in bit-reversed order: P_k = (Z_k^2 - conj(Z_{-k})^2) / 4i.
// Frequency -k sits at position 3·2^m - 1 - p for p in [2^m, 2^(m+1)); 0 and 1 self-pair.
static void fft_pointwise(double *re, double *im, int N) {
  for (int p = 0; p < 2; p++) {
    double zr = re[p], zi = im[p];
    re[p] = zr * zi; im[p] = 0;  // (Z^2 - conj(Z)^2)/4i = Re·Im for a self-paired bin
  }
  for (int m = 2; m < N; m <<= 1) {
    for (int p = m, q = 2 * m - 1; p < q; p++, q--) {
      double zr = re[p], zi = im[p], yr = re[q], yi = -im[q];   // y = conj(Z_{-k})
      double pr = (zr * zr - zi * zi) - (yr * yr - yi * yi);
      double pi = 2 * (zr * zi - yr * yi);
      re[p] = pi * 0.25; im[p] = -pr * 0.25;                 // divide by 4i
      re[q] = pi * 0.25; im[q] = pr * 0.25;                  // partner: -pr, same pi
    }
  }
}

// Scale by 1/N, round, propagate signed carries into 2n limbs. Returns max rounding error.
// Real-output inverse at half size. The product spectrum C (length N, bit-reversed)
// is Hermitian, so c = IDFT_N(C) is real and z_j = c_2j + i·c_2j+1 has the length-H
// spectrum (H = N/2)
//     Z'_k = (C_k + conj(C_{H-k})) + i·W^-k·(C_k - conj(C_{H-k})),   IDFT_H(Z') = N·z.
// In bit-reversed order C_k (k < H) sits at 2p where p = rev_H(k), C_{H-k} at 2·partner(p)
// (C_H at 1). Writes go to block [2^m, 2^(m+1)), reads come from the next block up, so
// an ascending sweep can work in place.
static void fft_fold_half(double *re, double *im, int N) {
  int H = N / 2;
  for (int p = 0; p < H; p++) {
    int q;
    if (p < 2) q = p ? 2 : 1;
    else { int m = 31 - __builtin_clz(p); q = 2 * (3 * (1 << m) - 1 - p); }
    double xr = re[2 * p], xi = im[2 * p], yr = re[q], yi = -im[q];   // X = C_k, Y = conj(C_{H-k})
    double sr = xr + yr, si = xi + yi, dr = xr - yr, di = xi - yi;
    double wr = tsr[p], wi = tsi[p];
    double tr = dr * wr - di * wi, ti = dr * wi + di * wr;             // W^-k·(X - Y)
    re[p] = sr - ti; im[p] = si + tr;                                  // (X + Y) + i·t
  }
}

// Scale by 1/N, round, propagate signed carries into 2n limbs; coefficient 2j is in
// re[j], 2j+1 in im[j]. Returns the largest rounding error.
static double fft_extract(u32 *r, double *re, double *im, int n, int bits, int N) {
  int coefs = 2 * ((n * 32 + bits - 1) / bits) + 1;
  if (coefs > N) coefs = N;
  int half = (coefs + 1) / 2;
  // pass 1 (SIMD): round, track the largest distance to the nearest integer
  v128_t vs = wasm_f64x2_splat(1.0 / N), verr = wasm_f64x2_splat(0);
  int j = 0;
  for (; j + 2 <= half; j += 2) {
    v128_t x = MUL(LD(re + j), vs), rx = wasm_f64x2_nearest(x);
    v128_t y = MUL(LD(im + j), vs), ry = wasm_f64x2_nearest(y);
    verr = wasm_f64x2_pmax(verr, wasm_f64x2_pmax(wasm_f64x2_abs(SUB(x, rx)), wasm_f64x2_abs(SUB(y, ry))));
    ST(re + j, rx); ST(im + j, ry);
  }
  double err = wasm_f64x2_extract_lane(verr, 0);
  if (wasm_f64x2_extract_lane(verr, 1) > err) err = wasm_f64x2_extract_lane(verr, 1);
  for (; j < half; j++) {
    double x = re[j] / N, rx = __builtin_nearbyint(x), y = im[j] / N, ry = __builtin_nearbyint(y);
    double e = __builtin_fabs(x - rx), f = __builtin_fabs(y - ry);
    if (e > err) err = e;
    if (f > err) err = f;
    re[j] = rx; im[j] = ry;
  }
  // pass 2: signed carry propagation and bit packing
  i64 carry = 0; u64 buf = 0; int have = 0, o = 0, total = 2 * n;
  u64 mask = (1u << bits) - 1;
  for (int t = 0; t < coefs && o < total; t++) {
    carry += (i64)((t & 1) ? im[t >> 1] : re[t >> 1]);
    buf |= ((u64)carry & mask) << have; have += bits; carry >>= bits;
    if (have >= 32) { r[o++] = (u32)buf; buf >>= 32; have -= 32; }
  }
  while (o < total) {
    buf |= ((u64)carry & M32) << have; carry >>= 32;
    r[o++] = (u32)buf; buf >>= 32;
  }
  return err;
}

static double fft_attempt(u32 *r, const u32 *a, const u32 *b, int n, int bits) {
  int N = fft_size(n, bits);
  if (!fft_plan(N)) return 1e9;
  load_coefs(fre, a, n, bits, N);
  load_coefs(fim, b, n, bits, N);
  fft_dif(fre, fim, N);
  fft_pointwise(fre, fim, N);
  fft_fold_half(fre, fim, N);
  fft_dit_inv(fre, fim, N / 2);
  return fft_extract(r, fre, fim, n, bits, N);
}

// Returns the coefficient size used (0 on failure).
EXPORT(mul_fft) int mul_fft(u32 *r, const u32 *a, const u32 *b, int n) {
  retries = 0;
  for (int bits = choose_bits(n); bits >= 6; retries++) {
    double err = fft_attempt(r, a, b, n, bits);
    max_err = err;
    last_bits = bits;
    if (!fft_check) return bits;
    if (err < 0.375) {
      u64 a32, a31, b32, b31, r32, r31;
      residues(a, n, &a32, &a31); residues(b, n, &b32, &b31); residues(r, 2 * n, &r32, &r31);
      if (fold32(a32 * b32) == r32 && fold31(a31 * b31) == r31) return bits;
    }
    bits--;  // an input coherent for one digit size is not coherent for the next
  }
  return 0;
}

// ---------------------------------------------------------------------------
static int auto_fft = 216;
EXPORT(set_auto) void set_auto(int fft_from) { auto_fft = fft_from; }

EXPORT(mul_auto) void mul_auto(u32 *r, const u32 *a, const u32 *b, int n, u32 *scratch) {
  if (n >= auto_fft && mul_fft(r, a, b, n)) return;
  kara(r, a, b, n, scratch);
}

// Profiling hooks: run one pipeline stage in isolation on the planned buffers.
volatile u64 prof_sink;
EXPORT(prof_stage) void prof_stage(int stage, int N, u32 *r, const u32 *a, int n, int bits) {
  fft_plan(N);
  switch (stage) {
    case 0: load_coefs(fre, a, n, bits, N); break;
    case 1: fft_dif(fre, fim, N); break;
    case 2: fft_dit_inv(fre, fim, N / 2); break;
    case 3: { u64 x, y; residues(a, n, &x, &y); prof_sink = x + y; } break;
    case 4: fft_pointwise(fre, fim, N); break;
    case 5: prof_sink = (u64)fft_extract(r, fre, fim, n, bits, N); break;
    case 6: fft_fold_half(fre, fim, N); break;
  }
}

// ---------------------------------------------------------------------------
// BigInt <-> limbs via hex text (BigInt.prototype.toString(16) / BigInt('0x…') are
// linear-time in V8; the text crosses the boundary with TextEncoder.encodeInto).

static inline u32 hexval(u32 c) { return (c & 0xf) + 9 * (c >> 6); }  // '0'-'9', 'a'-'f', 'A'-'F'

EXPORT(hex_to_limbs) int hex_to_limbs(u32 *dst, const unsigned char *hex, int len) {
  int n = 0, e = len;
  for (; e >= 8; e -= 8) {
    const unsigned char *p = hex + e - 8;
    u32 v = 0;
    for (int k = 0; k < 8; k++) v = (v << 4) | hexval(p[k]);
    dst[n++] = v;
  }
  if (e > 0) { u32 v = 0; for (int k = 0; k < e; k++) v = (v << 4) | hexval(hex[k]); dst[n++] = v; }
  return n;
}

// Writes the most-significant-first hex of src[0..n) without leading zeros; returns its length.
EXPORT(limbs_to_hex) int limbs_to_hex(unsigned char *dst, const u32 *src, int n) {
  while (n > 1 && !src[n - 1]) n--;
  static const char digits[] = "0123456789abcdef";
  int o = 0, lead = 1;
  for (int i = n - 1; i >= 0; i--) {
    u32 v = src[i];
    for (int s = 28; s >= 0; s -= 4) {
      u32 d = (v >> s) & 0xf;
      if (lead && d == 0 && !(i == 0 && s == 0)) continue;
      lead = 0;
      dst[o++] = digits[d];
    }
  }
  return o;
}
