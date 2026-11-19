/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _MATH_H_
#define _MATH_H_
#include <_ferry.h>
__FERRY_BEGIN
#define M_PI 3.14159265358979323846
#define M_E 2.7182818284590452354
#define HUGE_VAL __builtin_huge_val()
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#define isfinite(x) __builtin_isfinite(x)
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
__FERRY_END
#endif
