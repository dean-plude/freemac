/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _MATH_H_
#define _MATH_H_
#include <_ferry.h>
__FERRY_BEGIN
#define M_PI 3.14159265358979323846
#define M_E 2.7182818284590452354
#define M_LOG2E 1.4426950408889634074
#define M_LOG10E 0.43429448190325182765
#define M_LN2 0.69314718055994530942
#define M_LN10 2.30258509299404568402
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_1_PI 0.31830988618379067154
#define M_2_PI 0.63661977236758134308
#define M_2_SQRTPI 1.12837916709551257390
#define M_SQRT2 1.41421356237309504880
#define M_SQRT1_2 0.70710678118654752440
#define HUGE_VAL __builtin_huge_val()
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#define isfinite(x) __builtin_isfinite(x)
/* fpclassify's answers, with the macOS numbers */
#define FP_NAN 1
#define FP_INFINITE 2
#define FP_ZERO 3
#define FP_NORMAL 4
#define FP_SUBNORMAL 5
#define FP_SUPERNORMAL 6
#define HUGE_VALF __builtin_huge_valf()
#define HUGE_VALL __builtin_huge_vall()
#define FP_ILOGB0 (-2147483647 - 1)
#define FP_ILOGBNAN (-2147483647 - 1)
#define MATH_ERRNO 1
#define MATH_ERREXCEPT 2
#define math_errhandling MATH_ERREXCEPT
typedef float float_t;
typedef double double_t;
#ifndef __cplusplus
#define fpclassify(x) __builtin_fpclassify(FP_NAN, FP_INFINITE, FP_NORMAL, FP_SUBNORMAL, FP_ZERO, x)
#define isnormal(x) __builtin_isnormal(x)
#define signbit(x) __builtin_signbit(x)
#define isgreater(x, y) __builtin_isgreater(x, y)
#define isgreaterequal(x, y) __builtin_isgreaterequal(x, y)
#define isless(x, y) __builtin_isless(x, y)
#define islessequal(x, y) __builtin_islessequal(x, y)
#define islessgreater(x, y) __builtin_islessgreater(x, y)
#define isunordered(x, y) __builtin_isunordered(x, y)
#endif
double sin(double); double cos(double); double tan(double);
double asin(double); double acos(double); double atan(double); double atan2(double, double);
double sinh(double); double cosh(double); double tanh(double);
double exp(double); double exp2(double); double log(double); double log2(double); double log10(double);
double pow(double, double); double sqrt(double); double cbrt(double); double hypot(double, double);
double floor(double); double ceil(double); double round(double); double trunc(double);
double fabs(double); double fmod(double, double); double fmin(double, double); double fmax(double, double);
double frexp(double, int *); double ldexp(double, int); double modf(double, double *);
long lround(double);
float sqrtf(float); float floorf(float); float ceilf(float); float roundf(float); float fabsf(float);
float sinf(float); float cosf(float); float powf(float, float);
double asinh(double); double acosh(double); double atanh(double); double expm1(double); double log1p(double);
double logb(double); int ilogb(double); double scalbn(double, int); double scalbln(double, long);
double rint(double); double nearbyint(double); long lrint(double); long long llrint(double); long long llround(double);
double remainder(double, double); double remquo(double, double, int *); double copysign(double, double);
double nan(const char *); double nextafter(double, double); double nexttoward(double, long double);
double fdim(double, double); double fma(double, double, double); double erf(double); double erfc(double);
double tgamma(double); double lgamma(double);
float acosf(float); float asinf(float); float atanf(float); float atan2f(float, float); float tanf(float);
float sinhf(float); float coshf(float); float tanhf(float); float asinhf(float); float acoshf(float);
float atanhf(float); float expf(float); float exp2f(float); float expm1f(float); float logf(float);
float log2f(float); float log10f(float); float log1pf(float); float logbf(float); int ilogbf(float);
float cbrtf(float); float hypotf(float, float); float truncf(float); float rintf(float); float nearbyintf(float);
long lroundf(float); long long llroundf(float); long lrintf(float); long long llrintf(float);
float fmodf(float, float); float remainderf(float, float); float remquof(float, float, int *);
float copysignf(float, float); float nanf(const char *); float nextafterf(float, float);
float nexttowardf(float, long double); float fdimf(float, float); float fmaxf(float, float);
float fminf(float, float); float fmaf(float, float, float); float erff(float); float erfcf(float);
float tgammaf(float); float lgammaf(float); float frexpf(float, int *); float ldexpf(float, int);
float modff(float, float *); float scalbnf(float, int); float scalblnf(float, long);
long double sqrtl(long double); long double fabsl(long double); long double floorl(long double);
long double ceill(long double); long double fmodl(long double, long double); long double powl(long double, long double);
long double expl(long double); long double logl(long double); long double sinl(long double);
long double cosl(long double); long double tanl(long double); long double atan2l(long double, long double);
long double frexpl(long double, int *); long double ldexpl(long double, int); long double modfl(long double, long double *);
long double copysignl(long double, long double); long double nanl(const char *);
long double roundl(long double); long double truncl(long double); long double fminl(long double, long double);
long double fmaxl(long double, long double); long double log10l(long double); long double log2l(long double);
long double exp2l(long double);
/* the rest of C99's float and long double maths (freemac 1.227, for Swift) */
long double acosl(long double);
long double asinl(long double);
long double atanl(long double);
long double acoshl(long double);
long double asinhl(long double);
long double atanhl(long double);
long double coshl(long double);
long double sinhl(long double);
long double tanhl(long double);
long double expm1l(long double);
int ilogbl(long double);
long double log1pl(long double);
long double logbl(long double);
long double scalbnl(long double, int);
long double scalblnl(long double, long);
long double cbrtl(long double);
long double hypotl(long double, long double);
long double erfl(long double);
long double erfcl(long double);
long double lgammal(long double);
long double tgammal(long double);
long double nearbyintl(long double);
long double rintl(long double);
long lrintl(long double);
long long llrintl(long double);
long lroundl(long double);
long long llroundl(long double);
long double remainderl(long double, long double);
long double remquol(long double, long double, int*);
long double nextafterl(long double, long double);
long double nexttowardl(long double, long double);
long double fdiml(long double, long double);
double lgamma_r(double, int *); float lgammaf_r(float, int *); long double lgammal_r(long double, int *);
/* the Bessel functions, which Swift's Darwin module wraps; only for Swift,
 * as their short names (yn...) are ones programs use for their own */
#ifdef __swift__
double j0(double); double j1(double); double jn(int, double); double y0(double); double y1(double); double yn(int, double);
#endif
long double fmal(long double, long double, long double);
__FERRY_END
#endif
