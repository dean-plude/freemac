/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSDecimal and its functions, NSDecimalNumber and
 * NSDecimalNumberHandler, as Apple's class references and the "Number and
 * Value Programming Topics" describe them (freemac 1.211, Ferry 0.37.0).
 * Our own code; no Apple code was used.
 *
 * The arithmetic is done on decimal digits, exactly, and the result is
 * then fitted into an NSDecimal: trailing zeros are taken into the
 * exponent, and digits that don't fit in the 128-bit mantissa (38 or 39
 * of them) or below the exponent's least value (-128) are rounded away in
 * the rounding mode asked for, which is a loss of precision (or an
 * underflow, when nothing is left). A result above the exponent's greatest
 * value (127) is an overflow, and dividing by zero is an error of its own;
 * both give "not a number", and an underflow gives zero.
 *
 * NSRoundPlain rounds halves away from zero, NSRoundDown towards minus
 * infinity, NSRoundUp towards plus infinity, and NSRoundBankers rounds
 * halves to the even digit. */
#import "FInternal.h"

NSString *const NSDecimalNumberExactnessException = @"NSDecimalNumberExactnessException";
NSString *const NSDecimalNumberOverflowException = @"NSDecimalNumberOverflowException";
NSString *const NSDecimalNumberUnderflowException = @"NSDecimalNumberUnderflowException";
NSString *const NSDecimalNumberDivideByZeroException = @"NSDecimalNumberDivideByZeroException";

/* ---- numbers as decimal digits ---------------------------------------------------------- */

#define MAXD 440
typedef unsigned __int128 u128;

/* value = (-1)^neg x d[n-1]...d[1]d[0] x 10^exp, the lowest digit first. */
typedef struct {
    int nan, neg;
    int exp, n;
    unsigned char d[MAXD];
} Big;

static const char *const max_mantissa = "340282366920938463463374607431768211455";   /* 2^128 - 1 */

static void big_trim_top(Big *b)
{
    while (b->n && !b->d[b->n - 1])
        b->n--;
}

static void big_from_decimal(Big *b, const NSDecimal *d)
{
    memset(b, 0, offsetof(Big, d));
    if (NSDecimalIsNotANumber(d)) {
        b->nan = 1;
        return;
    }
    u128 m = 0;
    for (int i = (int)d->_length - 1; i >= 0; i--)
        m = (m << 16) | d->_mantissa[i];
    b->neg = d->_isNegative && m;
    b->exp = d->_exponent;
    while (m) {
        b->d[b->n++] = (unsigned char)(m % 10);
        m /= 10;
    }
}

/* Whether the digits fit in a 128-bit mantissa. */
static BOOL big_fits(const Big *b)
{
    if (b->n < 39)
        return YES;
    if (b->n > 39)
        return NO;
    for (int i = 0; i < 39; i++) {
        int digit = b->d[38 - i], limit = max_mantissa[i] - '0';
        if (digit != limit)
            return digit < limit;
    }
    return YES;
}

/* Puts digits that fit into dcm as they are (no rounding, no compacting). */
static void big_store(const Big *b, NSDecimal *dcm)
{
    memset(dcm, 0, sizeof *dcm);
    if (b->nan) {
        dcm->_isNegative = 1;
        return;
    }
    u128 m = 0;
    for (int i = b->n - 1; i >= 0; i--)
        m = m * 10 + b->d[i];
    int len = 0;
    for (int i = 0; i < NSDecimalMaxSize; i++) {
        dcm->_mantissa[i] = (unsigned short)(m & 0xffff);
        m >>= 16;
        if (dcm->_mantissa[i])
            len = i + 1;
    }
    dcm->_length = len;
    dcm->_isNegative = len && b->neg;
    dcm->_exponent = len ? b->exp : 0;
    dcm->_isCompact = !len || dcm->_mantissa[0] % 10 != 0 || b->exp == 127;
}

/* Adds one to the magnitude. */
static void big_increment(Big *b)
{
    for (int i = 0;; i++) {
        if (i == b->n) {
            b->d[b->n++] = 1;
            return;
        }
        if (++b->d[i] < 10)
            return;
        b->d[i] = 0;
    }
}

/* Drops the k lowest digits, rounding as mode says; answers whether a digit
 * that wasn't zero was dropped. */
static BOOL big_drop(Big *b, int k, NSRoundingMode mode)
{
    if (k <= 0)
        return NO;
    int half = k - 1 < b->n ? b->d[k - 1] : 0;
    BOOL sticky = NO;
    for (int i = 0; i < k - 1 && i < b->n; i++)
        sticky |= b->d[i] != 0;
    if (k >= b->n)
        b->n = 0;
    else {
        memmove(b->d, b->d + k, b->n - k);
        b->n -= k;
    }
    b->exp += k;
    BOOL up = NO;
    switch (mode) {
    case NSRoundPlain: up = half >= 5; break;
    case NSRoundDown: up = b->neg && (half || sticky); break;
    case NSRoundUp: up = !b->neg && (half || sticky); break;
    case NSRoundBankers: up = half > 5 || (half == 5 && (sticky || (b->n && (b->d[0] & 1)))); break;
    }
    if (up)
        big_increment(b);
    return half || sticky;
}

static void big_strip_low_zeros(Big *b)
{
    int z = 0;
    while (z < b->n && !b->d[z])
        z++;
    if (z && z < b->n) {
        memmove(b->d, b->d + z, b->n - z);
        b->n -= z;
        b->exp += z;
    }
}

/* Fits b into an NSDecimal, compacted, rounding as mode says. */
static NSCalculationError big_finish(Big *b, NSDecimal *out, NSRoundingMode mode)
{
    NSCalculationError err = NSCalculationNoError;
    if (b->nan) {
        big_store(b, out);
        return err;
    }
    big_trim_top(b);
    big_strip_low_zeros(b);
    for (;;) {
        if (!b->n)
            break;
        if (!big_fits(b)) {
            if (big_drop(b, b->n > 39 ? b->n - 39 : 1, mode))
                err = NSCalculationLossOfPrecision;
            big_trim_top(b);
            big_strip_low_zeros(b);
            continue;
        }
        if (b->exp < -128) {
            if (big_drop(b, -128 - b->exp, mode))
                err = NSCalculationLossOfPrecision;
            big_trim_top(b);
            big_strip_low_zeros(b);
            if (!b->n) {
                err = NSCalculationUnderflow;
                break;
            }
            continue;
        }
        break;
    }
    if (!b->n) {
        b->neg = 0;
        b->exp = 0;
    }
    while (b->n && b->exp > 127) {
        Big t = *b;
        memmove(t.d + 1, t.d, t.n);
        t.d[0] = 0;
        t.n++;
        t.exp--;
        if (!big_fits(&t)) {
            b->nan = 1;
            big_store(b, out);
            return NSCalculationOverflow;
        }
        *b = t;
    }
    big_store(b, out);
    out->_isCompact = 1;
    return err;
}

/* Magnitudes, with their exponents. */
static int big_compare_magnitude(const Big *a, const Big *b)
{
    if (!a->n || !b->n)
        return a->n ? 1 : b->n ? -1 : 0;
    int ta = a->n + a->exp, tb = b->n + b->exp;   /* the place of the leading digit */
    if (ta != tb)
        return ta > tb ? 1 : -1;
    for (int i = 0;; i++) {
        int ia = a->n - 1 - i, ib = b->n - 1 - i;
        if (ia < 0 && ib < 0)
            return 0;
        int da = ia >= 0 ? a->d[ia] : 0, db = ib >= 0 ? b->d[ib] : 0;
        if (da != db)
            return da > db ? 1 : -1;
    }
}

/* Brings b to the exponent e (at most its own), appending zeros. */
static void big_lower_exponent(Big *b, int e)
{
    int k = b->exp - e;
    if (k <= 0 || !b->n)
        return;
    memmove(b->d + k, b->d, b->n);
    memset(b->d, 0, k);
    b->n += k;
    b->exp = e;
}

static void big_add(Big *r, const Big *x, const Big *y)
{
    Big a = *x, b = *y;
    int e = a.exp < b.exp ? a.exp : b.exp;
    big_lower_exponent(&a, e);
    big_lower_exponent(&b, e);
    memset(r, 0, offsetof(Big, d));
    r->exp = e;
    if (!a.n)
        a.exp = e;
    if (!b.n)
        b.exp = e;
    if (a.neg == b.neg || !a.n || !b.n) {
        r->neg = a.n ? a.neg : b.neg;
        int n = a.n > b.n ? a.n : b.n, carry = 0;
        for (int i = 0; i < n; i++) {
            int s = (i < a.n ? a.d[i] : 0) + (i < b.n ? b.d[i] : 0) + carry;
            r->d[i] = s % 10;
            carry = s / 10;
        }
        r->n = n;
        if (carry)
            r->d[r->n++] = 1;
        return;
    }
    int c = big_compare_magnitude(&a, &b);
    const Big *big = c >= 0 ? &a : &b, *small = c >= 0 ? &b : &a;
    r->neg = c == 0 ? 0 : big->neg;
    int borrow = 0;
    for (int i = 0; i < big->n; i++) {
        int s = big->d[i] - (i < small->n ? small->d[i] : 0) - borrow;
        borrow = s < 0;
        r->d[i] = s + (borrow ? 10 : 0);
    }
    r->n = big->n;
    big_trim_top(r);
}

static void big_multiply(Big *r, const Big *a, const Big *b)
{
    memset(r, 0, offsetof(Big, d));
    r->neg = a->neg != b->neg;
    r->exp = a->exp + b->exp;
    if (!a->n || !b->n) {
        r->neg = 0;
        return;
    }
    int acc[MAXD] = {0};
    for (int i = 0; i < a->n; i++)
        for (int j = 0; j < b->n; j++)
            acc[i + j] += a->d[i] * b->d[j];
    int n = a->n + b->n, carry = 0;
    for (int i = 0; i < n; i++) {
        int s = acc[i] + carry;
        r->d[i] = s % 10;
        carry = s / 10;
    }
    r->n = n;
    big_trim_top(r);
}

/* Integer digits only: a >= b? (both without exponents) */
static int digits_compare(const unsigned char *a, int na, const unsigned char *b, int nb)
{
    while (na && !a[na - 1])
        na--;
    while (nb && !b[nb - 1])
        nb--;
    if (na != nb)
        return na > nb ? 1 : -1;
    for (int i = na - 1; i >= 0; i--)
        if (a[i] != b[i])
            return a[i] > b[i] ? 1 : -1;
    return 0;
}

/* q = a / b, with at least 41 digits, the last one marking a remainder. */
static void big_divide(Big *q, const Big *a, const Big *b)
{
    memset(q, 0, offsetof(Big, d));
    q->neg = a->neg != b->neg;
    if (!a->n) {
        q->neg = 0;
        return;
    }
    int k = 41 + b->n - a->n;
    if (k < 0)
        k = 0;
    /* the dividend's digits, highest first, with k zeros after them */
    int total = a->n + k;
    unsigned char rem[MAXD];
    int nrem = 0;
    unsigned char out[MAXD];
    int nout = 0;
    for (int i = 0; i < total; i++) {
        int digit = i < a->n ? a->d[a->n - 1 - i] : 0;
        /* rem = rem * 10 + digit */
        memmove(rem + 1, rem, nrem);
        rem[0] = (unsigned char)digit;
        nrem++;
        int count = 0;
        while (digits_compare(rem, nrem, b->d, b->n) >= 0) {
            int borrow = 0;
            for (int j = 0; j < nrem; j++) {
                int s = rem[j] - (j < b->n ? b->d[j] : 0) - borrow;
                borrow = s < 0;
                rem[j] = s + (borrow ? 10 : 0);
            }
            count++;
        }
        while (nrem && !rem[nrem - 1])
            nrem--;
        out[nout++] = (unsigned char)count;
    }
    /* out is highest first */
    BOOL remainder = nrem > 0;
    q->n = 0;
    if (remainder)
        q->d[q->n++] = 1;
    for (int i = nout - 1; i >= 0; i--)
        q->d[q->n++] = out[i];
    q->exp = a->exp - k - b->exp - (remainder ? 1 : 0);
    big_trim_top(q);
}

/* ---- the C functions -------------------------------------------------------------------- */

BOOL NSDecimalIsNotANumber(const NSDecimal *dcm) { return dcm->_length == 0 && dcm->_isNegative; }

void NSDecimalCopy(NSDecimal *destination, const NSDecimal *source) { *destination = *source; }

void NSDecimalCompact(NSDecimal *number)
{
    if (NSDecimalIsNotANumber(number))
        return;
    Big b;
    big_from_decimal(&b, number);
    big_finish(&b, number, NSRoundPlain);
}

NSComparisonResult NSDecimalCompare(const NSDecimal *leftOperand, const NSDecimal *rightOperand)
{
    Big a, b;
    big_from_decimal(&a, leftOperand);
    big_from_decimal(&b, rightOperand);
    if (a.nan || b.nan)
        return a.nan && b.nan ? NSOrderedSame : a.nan ? NSOrderedAscending : NSOrderedDescending;
    int sa = a.n ? (a.neg ? -1 : 1) : 0, sb = b.n ? (b.neg ? -1 : 1) : 0;
    if (sa != sb)
        return sa < sb ? NSOrderedAscending : NSOrderedDescending;
    int c = big_compare_magnitude(&a, &b) * (sa < 0 ? -1 : 1);
    return c < 0 ? NSOrderedAscending : c > 0 ? NSOrderedDescending : NSOrderedSame;
}

void NSDecimalRound(NSDecimal *result, const NSDecimal *number, NSInteger scale, NSRoundingMode roundingMode)
{
    Big b;
    big_from_decimal(&b, number);
    if (b.nan || scale == NSDecimalNoScale) {
        *result = *number;
        return;
    }
    if (b.exp < -scale)
        big_drop(&b, (int)(-scale - b.exp), roundingMode);
    big_finish(&b, result, roundingMode);
}

NSCalculationError NSDecimalNormalize(NSDecimal *number1, NSDecimal *number2, NSRoundingMode roundingMode)
{
    Big a, b;
    big_from_decimal(&a, number1);
    big_from_decimal(&b, number2);
    if (a.nan || b.nan || a.exp == b.exp)
        return NSCalculationNoError;
    Big *hi = a.exp > b.exp ? &a : &b, *lo = a.exp > b.exp ? &b : &a;
    /* first the larger exponent comes down, as far as the mantissa allows */
    while (hi->exp > lo->exp && hi->n) {
        Big t = *hi;
        big_lower_exponent(&t, t.exp - 1);
        if (!big_fits(&t))
            break;
        *hi = t;
    }
    if (!hi->n)
        hi->exp = lo->exp;
    NSCalculationError err = NSCalculationNoError;
    if (hi->exp > lo->exp && big_drop(lo, hi->exp - lo->exp, roundingMode))
        err = NSCalculationLossOfPrecision;
    if (!lo->n)
        lo->exp = hi->exp;
    big_store(&a, number1);
    big_store(&b, number2);
    number1->_exponent = a.exp;
    number2->_exponent = b.exp;
    return err;
}

NSCalculationError NSDecimalAdd(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                                NSRoundingMode roundingMode)
{
    Big a, b, r;
    big_from_decimal(&a, leftOperand);
    big_from_decimal(&b, rightOperand);
    if (a.nan || b.nan) {
        r.nan = 1;
        big_store(&r, result);
        return NSCalculationNoError;
    }
    big_add(&r, &a, &b);
    return big_finish(&r, result, roundingMode);
}

NSCalculationError NSDecimalSubtract(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                                     NSRoundingMode roundingMode)
{
    NSDecimal negated = *rightOperand;
    if (!NSDecimalIsNotANumber(&negated) && negated._length)
        negated._isNegative = !negated._isNegative;
    return NSDecimalAdd(result, leftOperand, &negated, roundingMode);
}

NSCalculationError NSDecimalMultiply(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                                     NSRoundingMode roundingMode)
{
    Big a, b, r;
    big_from_decimal(&a, leftOperand);
    big_from_decimal(&b, rightOperand);
    if (a.nan || b.nan) {
        r.nan = 1;
        big_store(&r, result);
        return NSCalculationNoError;
    }
    big_multiply(&r, &a, &b);
    return big_finish(&r, result, roundingMode);
}

NSCalculationError NSDecimalDivide(NSDecimal *result, const NSDecimal *leftOperand, const NSDecimal *rightOperand,
                                   NSRoundingMode roundingMode)
{
    Big a, b, r;
    big_from_decimal(&a, leftOperand);
    big_from_decimal(&b, rightOperand);
    if (a.nan || b.nan || !b.n) {
        memset(&r, 0, offsetof(Big, d));
        r.nan = 1;
        big_store(&r, result);
        return !a.nan && !b.nan ? NSCalculationDivideByZero : NSCalculationNoError;
    }
    big_divide(&r, &a, &b);
    return big_finish(&r, result, roundingMode);
}

NSCalculationError NSDecimalPower(NSDecimal *result, const NSDecimal *number, NSUInteger power,
                                  NSRoundingMode roundingMode)
{
    if (NSDecimalIsNotANumber(number)) {
        *result = *number;
        return NSCalculationNoError;
    }
    NSDecimal acc, base = *number;
    Big one = {0};
    one.n = 1;
    one.d[0] = 1;
    big_finish(&one, &acc, roundingMode);
    NSCalculationError worst = NSCalculationNoError;
    while (power) {
        NSCalculationError e;
        if (power & 1) {
            e = NSDecimalMultiply(&acc, &acc, &base, roundingMode);
            if (e > worst)
                worst = e;
        }
        power >>= 1;
        if (power) {
            e = NSDecimalMultiply(&base, &base, &base, roundingMode);
            if (e > worst)
                worst = e;
        }
        if (worst >= NSCalculationOverflow)
            break;
    }
    *result = acc;
    if (worst == NSCalculationOverflow)
        result->_length = 0, result->_isNegative = 1;
    return worst;
}

NSCalculationError NSDecimalMultiplyByPowerOf10(NSDecimal *result, const NSDecimal *number, short power,
                                                NSRoundingMode roundingMode)
{
    Big b;
    big_from_decimal(&b, number);
    if (b.nan) {
        *result = *number;
        return NSCalculationNoError;
    }
    b.exp += power;
    return big_finish(&b, result, roundingMode);
}

static NSString *decimal_separator(id locale)
{
    id sep = nil;
    if ([locale isKindOfClass:[NSDictionary class]])
        sep = [locale objectForKey:NSLocaleDecimalSeparator] ?: [locale objectForKey:@"NSDecimalSeparator"];
    else if ([locale respondsToSelector:@selector(objectForKey:)])
        sep = [locale objectForKey:NSLocaleDecimalSeparator];
    return [sep isKindOfClass:[NSString class]] && [sep length] ? sep : @".";
}

NSString *NSDecimalString(const NSDecimal *dcm, id locale)
{
    Big b;
    big_from_decimal(&b, dcm);
    if (b.nan)
        return @"NaN";
    if (!b.n)
        return @"0";
    NSString *sep = decimal_separator(locale);
    char digits[MAXD + 1];
    for (int i = 0; i < b.n; i++)
        digits[i] = (char)('0' + b.d[b.n - 1 - i]);
    digits[b.n] = 0;
    NSMutableString *s = [NSMutableString stringWithString:b.neg ? @"-" : @""];
    if (b.exp >= 0) {
        [s appendFormat:@"%s", digits];
        for (int i = 0; i < b.exp; i++)
            [s appendString:@"0"];
        return s;
    }
    int point = b.n + b.exp;
    if (point > 0) {
        [s appendString:[[NSString alloc] initWithBytes:digits length:point encoding:NSUTF8StringEncoding]];
        [s appendString:sep];
        [s appendFormat:@"%s", digits + point];
        return s;
    }
    [s appendString:@"0"];
    [s appendString:sep];
    for (int i = 0; i < -point; i++)
        [s appendString:@"0"];
    [s appendFormat:@"%s", digits];
    return s;
}

/* ---- reading numbers ------------------------------------------------------------------------- */

/* A number in s from *at: an optional sign, digits with one decimal separator,
 * and an optional exponent. Answers whether there were digits, with *at past them. */
static BOOL read_number(NSString *s, NSUInteger *at, NSString *sep, Big *b)
{
    NSUInteger i = *at, n = [s length], seplen = [sep length];
    memset(b, 0, offsetof(Big, d));
    while (i < n && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[s characterAtIndex:i]])
        i++;
    if (i < n && ([s characterAtIndex:i] == '-' || [s characterAtIndex:i] == '+')) {
        b->neg = [s characterAtIndex:i] == '-';
        i++;
    }
    unsigned char digits[MAXD];
    int nd = 0, shift = 0;
    BOOL any = NO, point = NO, sticky = NO;
    for (; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= '0' && c <= '9') {
            any = YES;
            if (!nd && c == '0') {   /* leading zeros */
                if (point)
                    shift--;
                continue;
            }
            if (nd < MAXD - 4) {
                digits[nd++] = (unsigned char)(c - '0');
                if (point)
                    shift--;
            } else {
                if (!point)
                    shift++;
                sticky |= c != '0';
            }
            continue;
        }
        if (!point && i + seplen <= n && [[s substringWithRange:NSMakeRange(i, seplen)] isEqualToString:sep]) {
            point = YES;
            i += seplen - 1;
            continue;
        }
        break;
    }
    if (!any)
        return NO;
    if (i < n && ([s characterAtIndex:i] == 'e' || [s characterAtIndex:i] == 'E')) {
        NSUInteger j = i + 1;
        BOOL eneg = NO;
        if (j < n && ([s characterAtIndex:j] == '-' || [s characterAtIndex:j] == '+'))
            eneg = [s characterAtIndex:j++] == '-';
        if (j < n && [s characterAtIndex:j] >= '0' && [s characterAtIndex:j] <= '9') {
            long e = 0;
            while (j < n && [s characterAtIndex:j] >= '0' && [s characterAtIndex:j] <= '9') {
                if (e < 100000)
                    e = e * 10 + ([s characterAtIndex:j] - '0');
                j++;
            }
            shift += (int)(eneg ? -e : e);
            i = j;
        }
    }
    *at = i;
    for (int k = 0; k < nd; k++)
        b->d[k] = digits[nd - 1 - k];
    b->n = nd;
    b->exp = shift;
    if (sticky) {   /* a last digit past the kept ones, so that rounding sees them */
        memmove(b->d + 1, b->d, b->n);
        b->d[0] = 1;
        b->n++;
        b->exp--;
    }
    if (!nd)
        b->neg = 0;
    return YES;
}

static void decimal_from_string(NSString *s, id locale, NSDecimal *out)
{
    Big b;
    NSUInteger at = 0;
    if (![s isKindOfClass:[NSString class]] || !read_number(s, &at, decimal_separator(locale), &b)) {
        memset(&b, 0, offsetof(Big, d));
        b.nan = 1;
    }
    big_finish(&b, out, NSRoundPlain);
}

/* The shortest digits that read back as the same double. */
static void decimal_from_double(double v, NSDecimal *out)
{
    if (isnan(v) || isinf(v)) {
        Big b = {0};
        b.nan = 1;
        big_store(&b, out);
        return;
    }
    char buf[64];
    for (int prec = 1; prec <= 17; prec++) {
        snprintf(buf, sizeof buf, "%.*e", prec - 1, v);
        if (strtod(buf, NULL) == v)
            break;
    }
    decimal_from_string([NSString stringWithUTF8String:buf], nil, out);
}

static void decimal_from_integer(unsigned long long u, BOOL neg, NSDecimal *out)
{
    Big b = {0};
    b.neg = neg;
    while (u) {
        b.d[b.n++] = (unsigned char)(u % 10);
        u /= 10;
    }
    big_finish(&b, out, NSRoundPlain);
}

@implementation NSNumber (NSDecimalNumberExtensions)
- (NSDecimal)decimalValue
{
    NSDecimal d;
    const char *t = [self objCType];
    switch (t ? *t : 'd') {
    case 'c': case 's': case 'i': case 'l': case 'q': case 'B': {
        long long v = [self longLongValue];
        decimal_from_integer(v < 0 ? 0ULL - (unsigned long long)v : (unsigned long long)v, v < 0, &d);
        break;
    }
    case 'C': case 'S': case 'I': case 'L': case 'Q':
        decimal_from_integer([self unsignedLongLongValue], NO, &d);
        break;
    default:
        decimal_from_double([self doubleValue], &d);
    }
    return d;
}
@end

@implementation NSScanner (NSDecimalNumberScanning)
- (BOOL)scanDecimal:(NSDecimal *)dcm
{
    NSString *s = [self string];
    NSUInteger at = [self scanLocation], n = [s length];
    NSCharacterSet *skip = [self charactersToBeSkipped];
    while (at < n && skip && [skip characterIsMember:[s characterAtIndex:at]])
        at++;
    Big b;
    if (!read_number(s, &at, decimal_separator([self locale]), &b))
        return NO;
    if (dcm)
        big_finish(&b, dcm, NSRoundPlain);
    [self setScanLocation:at];
    return YES;
}
@end

/* ---- NSDecimalNumberHandler ------------------------------------------------------------------- */

@implementation NSDecimalNumberHandler {
    NSRoundingMode _mode;
    short _scale;
    BOOL _exact, _overflow, _underflow, _divide;
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (NSDecimalNumberHandler *)defaultDecimalNumberHandler
{
    static NSDecimalNumberHandler *handler;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handler = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundPlain
                                                                 scale:NSDecimalNoScale
                                                      raiseOnExactness:NO
                                                       raiseOnOverflow:YES
                                                      raiseOnUnderflow:YES
                                                   raiseOnDivideByZero:YES];
    });
    return handler;
}
+ (instancetype)decimalNumberHandlerWithRoundingMode:(NSRoundingMode)roundingMode
                                               scale:(short)scale
                                    raiseOnExactness:(BOOL)exact
                                     raiseOnOverflow:(BOOL)overflow
                                    raiseOnUnderflow:(BOOL)underflow
                                 raiseOnDivideByZero:(BOOL)divideByZero
{
    return [[[self alloc] initWithRoundingMode:roundingMode
                                         scale:scale
                              raiseOnExactness:exact
                               raiseOnOverflow:overflow
                              raiseOnUnderflow:underflow
                           raiseOnDivideByZero:divideByZero] autorelease];
}
- (instancetype)init
{
    return [self initWithRoundingMode:NSRoundPlain
                                scale:NSDecimalNoScale
                     raiseOnExactness:NO
                      raiseOnOverflow:YES
                     raiseOnUnderflow:YES
                  raiseOnDivideByZero:YES];
}
- (instancetype)initWithRoundingMode:(NSRoundingMode)roundingMode
                               scale:(short)scale
                    raiseOnExactness:(BOOL)exact
                     raiseOnOverflow:(BOOL)overflow
                    raiseOnUnderflow:(BOOL)underflow
                 raiseOnDivideByZero:(BOOL)divideByZero
{
    if ((self = [super init])) {
        _mode = roundingMode;
        _scale = scale;
        _exact = exact;
        _overflow = overflow;
        _underflow = underflow;
        _divide = divideByZero;
    }
    return self;
}
- (NSRoundingMode)roundingMode { return _mode; }
- (short)scale { return _scale; }
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation
                                        error:(NSCalculationError)error
                                  leftOperand:(NSDecimalNumber *)leftOperand
                                 rightOperand:(NSDecimalNumber *)rightOperand
{
    NSString *what = NSStringFromSelector(operation);
    switch (error) {
    case NSCalculationLossOfPrecision:
        if (_exact)
            FRaise(NSDecimalNumberExactnessException, @"NSDecimalNumber lost precision in %@", what);
        break;
    case NSCalculationUnderflow:
        if (_underflow)
            FRaise(NSDecimalNumberUnderflowException, @"NSDecimalNumber underflow in %@", what);
        break;
    case NSCalculationOverflow:
        if (_overflow)
            FRaise(NSDecimalNumberOverflowException, @"NSDecimalNumber overflow in %@", what);
        break;
    case NSCalculationDivideByZero:
        if (_divide)
            FRaise(NSDecimalNumberDivideByZeroException, @"NSDecimalNumber divide by zero in %@", what);
        break;
    default: break;
    }
    return nil;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeInteger:_mode forKey:@"NS.roundingMode"];
    [coder encodeInteger:_scale forKey:@"NS.scale"];
    [coder encodeBool:_exact forKey:@"NS.raise.exactness"];
    [coder encodeBool:_overflow forKey:@"NS.raise.overflow"];
    [coder encodeBool:_underflow forKey:@"NS.raise.underflow"];
    [coder encodeBool:_divide forKey:@"NS.raise.dividebyzero"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithRoundingMode:[coder decodeIntegerForKey:@"NS.roundingMode"]
                                scale:(short)[coder decodeIntegerForKey:@"NS.scale"]
                     raiseOnExactness:[coder decodeBoolForKey:@"NS.raise.exactness"]
                      raiseOnOverflow:[coder decodeBoolForKey:@"NS.raise.overflow"]
                     raiseOnUnderflow:[coder decodeBoolForKey:@"NS.raise.underflow"]
                  raiseOnDivideByZero:[coder decodeBoolForKey:@"NS.raise.dividebyzero"]];
}
@end

/* ---- NSDecimalNumber -------------------------------------------------------------------------- */

static id<NSDecimalNumberBehaviors> default_behavior;

@implementation NSDecimalNumber {
    NSDecimal _d;
}
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)init
{
    NSDecimal zero;
    decimal_from_integer(0, NO, &zero);
    return [self initWithDecimal:zero];
}
- (instancetype)initWithDecimal:(NSDecimal)dcm
{
    if ((self = [super init])) {
        _d = dcm;
        NSDecimalCompact(&_d);
    }
    return self;
}
- (instancetype)initWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag
{
    Big b = {0};
    b.neg = flag;
    b.exp = exponent;
    while (mantissa) {
        b.d[b.n++] = (unsigned char)(mantissa % 10);
        mantissa /= 10;
    }
    NSDecimal d;
    big_finish(&b, &d, NSRoundPlain);
    return [self initWithDecimal:d];
}
- (instancetype)initWithString:(NSString *)numberValue { return [self initWithString:numberValue locale:nil]; }
- (instancetype)initWithString:(NSString *)numberValue locale:(id)locale
{
    NSDecimal d;
    decimal_from_string(numberValue, locale, &d);
    return [self initWithDecimal:d];
}
- (instancetype)initWithDouble:(double)v
{
    NSDecimal d;
    decimal_from_double(v, &d);
    return [self initWithDecimal:d];
}
- (instancetype)initWithInt:(int)v { return [self initWithInteger:v]; }
- (instancetype)initWithInteger:(NSInteger)v
{
    NSDecimal d;
    decimal_from_integer(v < 0 ? 0ULL - (unsigned long long)v : (unsigned long long)v, v < 0, &d);
    return [self initWithDecimal:d];
}
- (instancetype)initWithBool:(BOOL)v { return [self initWithInteger:v ? 1 : 0]; }
+ (NSDecimalNumber *)decimalNumberWithMantissa:(unsigned long long)mantissa exponent:(short)exponent isNegative:(BOOL)flag
{
    return [[[self alloc] initWithMantissa:mantissa exponent:exponent isNegative:flag] autorelease];
}
+ (NSDecimalNumber *)decimalNumberWithDecimal:(NSDecimal)dcm { return [[[self alloc] initWithDecimal:dcm] autorelease]; }
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue
{
    return [[[self alloc] initWithString:numberValue locale:nil] autorelease];
}
+ (NSDecimalNumber *)decimalNumberWithString:(NSString *)numberValue locale:(id)locale
{
    return [[[self alloc] initWithString:numberValue locale:locale] autorelease];
}
static NSDecimalNumber *shared(NSDecimalNumber **slot, void (^make)(NSDecimal *))
{
    if (!*slot) {
        NSDecimal d;
        make(&d);
        NSDecimalNumber *n = [[NSDecimalNumber alloc] initWithDecimal:d];
        if (!__sync_bool_compare_and_swap(slot, nil, n))
            [n release];
    }
    return *slot;
}
+ (NSDecimalNumber *)zero
{
    static NSDecimalNumber *n;
    return shared(&n, ^(NSDecimal *d) { decimal_from_integer(0, NO, d); });
}
+ (NSDecimalNumber *)one
{
    static NSDecimalNumber *n;
    return shared(&n, ^(NSDecimal *d) { decimal_from_integer(1, NO, d); });
}
+ (NSDecimalNumber *)notANumber
{
    static NSDecimalNumber *n;
    return shared(&n, ^(NSDecimal *d) {
        memset(d, 0, sizeof *d);
        d->_isNegative = 1;
    });
}
static void extreme_decimal(NSDecimal *d, BOOL neg)
{
    memset(d, 0, sizeof *d);
    for (int i = 0; i < NSDecimalMaxSize; i++)
        d->_mantissa[i] = 0xffff;
    d->_length = NSDecimalMaxSize;
    d->_exponent = 127;
    d->_isNegative = neg;
    d->_isCompact = 1;
}
+ (NSDecimalNumber *)maximumDecimalNumber
{
    static NSDecimalNumber *n;
    return shared(&n, ^(NSDecimal *d) { extreme_decimal(d, NO); });
}
+ (NSDecimalNumber *)minimumDecimalNumber
{
    static NSDecimalNumber *n;
    return shared(&n, ^(NSDecimal *d) { extreme_decimal(d, YES); });
}
+ (id<NSDecimalNumberBehaviors>)defaultBehavior
{
    return default_behavior ?: (id<NSDecimalNumberBehaviors>)[NSDecimalNumberHandler defaultDecimalNumberHandler];
}
+ (void)setDefaultBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    id old = default_behavior;
    default_behavior = [(id)behavior retain];
    [old release];
}

typedef NSCalculationError (*FDecimalOp)(NSDecimal *, const NSDecimal *, const NSDecimal *, NSRoundingMode);

/* The result of an operation, rounded to the behaviour's scale, its errors handed to the behaviour. */
static NSDecimalNumber *finish_operation(NSDecimal result, NSCalculationError err, SEL sel, NSDecimalNumber *l,
                                         NSDecimalNumber *r, id<NSDecimalNumberBehaviors> behavior)
{
    short scale = [behavior scale];
    if (scale != NSDecimalNoScale && !NSDecimalIsNotANumber(&result)) {
        NSDecimal rounded;
        NSDecimalRound(&rounded, &result, scale, [behavior roundingMode]);
        if (NSDecimalCompare(&rounded, &result) != NSOrderedSame && err == NSCalculationNoError)
            err = NSCalculationLossOfPrecision;
        result = rounded;
    }
    if (err != NSCalculationNoError) {
        NSDecimalNumber *other = [behavior exceptionDuringOperation:sel error:err leftOperand:l rightOperand:r];
        if (other)
            return other;
    }
    return [NSDecimalNumber decimalNumberWithDecimal:result];
}

static NSDecimalNumber *operate(NSDecimalNumber *l, NSDecimalNumber *r, SEL sel, FDecimalOp op,
                                id<NSDecimalNumberBehaviors> behavior)
{
    if (!behavior)
        behavior = [NSDecimalNumber defaultBehavior];
    if (!r)
        FRaise(NSInvalidArgumentException, @"*** -[NSDecimalNumber %@]: the other number is nil", NSStringFromSelector(sel));
    NSDecimal a = [l decimalValue], b = [r decimalValue], result;
    NSCalculationError err = op(&result, &a, &b, [behavior roundingMode]);
    return finish_operation(result, err, sel, l, r, behavior);
}

- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)n { return [self decimalNumberByAdding:n withBehavior:nil]; }
- (NSDecimalNumber *)decimalNumberByAdding:(NSDecimalNumber *)n withBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    return operate(self, n, _cmd, NSDecimalAdd, behavior);
}
- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)n
{
    return [self decimalNumberBySubtracting:n withBehavior:nil];
}
- (NSDecimalNumber *)decimalNumberBySubtracting:(NSDecimalNumber *)n withBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    return operate(self, n, _cmd, NSDecimalSubtract, behavior);
}
- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)n
{
    return [self decimalNumberByMultiplyingBy:n withBehavior:nil];
}
- (NSDecimalNumber *)decimalNumberByMultiplyingBy:(NSDecimalNumber *)n withBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    return operate(self, n, _cmd, NSDecimalMultiply, behavior);
}
- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)n
{
    return [self decimalNumberByDividingBy:n withBehavior:nil];
}
- (NSDecimalNumber *)decimalNumberByDividingBy:(NSDecimalNumber *)n withBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    return operate(self, n, _cmd, NSDecimalDivide, behavior);
}
- (NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)power
{
    return [self decimalNumberByRaisingToPower:power withBehavior:nil];
}
- (NSDecimalNumber *)decimalNumberByRaisingToPower:(NSUInteger)power withBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    if (!behavior)
        behavior = [NSDecimalNumber defaultBehavior];
    NSDecimal result;
    NSCalculationError err = NSDecimalPower(&result, &_d, power, [behavior roundingMode]);
    return finish_operation(result, err, _cmd, self, nil, behavior);
}
- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power
{
    return [self decimalNumberByMultiplyingByPowerOf10:power withBehavior:nil];
}
- (NSDecimalNumber *)decimalNumberByMultiplyingByPowerOf10:(short)power
                                              withBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    if (!behavior)
        behavior = [NSDecimalNumber defaultBehavior];
    NSDecimal result;
    NSCalculationError err = NSDecimalMultiplyByPowerOf10(&result, &_d, power, [behavior roundingMode]);
    return finish_operation(result, err, _cmd, self, nil, behavior);
}
- (NSDecimalNumber *)decimalNumberByRoundingAccordingToBehavior:(id<NSDecimalNumberBehaviors>)behavior
{
    if (!behavior)
        behavior = [NSDecimalNumber defaultBehavior];
    NSDecimal result;
    NSDecimalRound(&result, &_d, [behavior scale], [behavior roundingMode]);
    return [NSDecimalNumber decimalNumberWithDecimal:result];
}

- (NSDecimal)decimalValue { return _d; }
- (NSString *)description { return NSDecimalString(&_d, nil); }
- (NSString *)descriptionWithLocale:(id)locale { return NSDecimalString(&_d, locale); }
- (NSString *)stringValue { return [self description]; }
- (const char *)objCType { return "d"; }
- (double)doubleValue
{
    if (NSDecimalIsNotANumber(&_d))
        return NAN;
    return strtod([NSDecimalString(&_d, nil) UTF8String], NULL);
}
- (float)floatValue { return (float)[self doubleValue]; }
/* The integer part, exactly when it fits. */
- (long long)longLongValue
{
    Big b;
    big_from_decimal(&b, &_d);
    if (b.nan)
        return 0;
    if (b.exp < 0)
        big_drop(&b, -b.exp, b.neg ? NSRoundUp : NSRoundDown);   /* towards zero */
    if (b.n + b.exp > 19)
        return (long long)[self doubleValue];
    unsigned long long u = 0;
    for (int i = b.n - 1; i >= 0; i--)
        u = u * 10 + b.d[i];
    for (int i = 0; i < b.exp; i++)
        u *= 10;
    return b.neg ? -(long long)u : (long long)u;
}
- (unsigned long long)unsignedLongLongValue
{
    Big b;
    big_from_decimal(&b, &_d);
    if (b.nan || b.neg)
        return (unsigned long long)[self longLongValue];
    if (b.exp < 0)
        big_drop(&b, -b.exp, NSRoundDown);
    if (b.n + b.exp > 20)
        return (unsigned long long)[self doubleValue];
    unsigned long long u = 0;
    for (int i = b.n - 1; i >= 0; i--)
        u = u * 10 + b.d[i];
    for (int i = 0; i < b.exp; i++)
        u *= 10;
    return u;
}
- (BOOL)boolValue { return !NSDecimalIsNotANumber(&_d) && _d._length != 0; }
- (NSComparisonResult)compare:(NSNumber *)other
{
    if (![other isKindOfClass:[NSNumber class]])
        FRaise(NSInvalidArgumentException, @"*** -[NSDecimalNumber compare:]: the other number is %@", other);
    NSDecimal o = [other decimalValue];
    return NSDecimalCompare(&_d, &o);
}
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSNumber class]])
        return NO;
    return [self compare:other] == NSOrderedSame;
}
- (NSUInteger)hash
{
    double v = [self doubleValue];
    if (v == floor(v) && fabs(v) < 9.2e18)
        return (NSUInteger)(long long)v;
    union {
        double d;
        NSUInteger u;
    } bits = {.d = v};
    return bits.u;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (Class)classForCoder { return [NSDecimalNumber class]; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:[self description] forKey:@"NS.decimal"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *s = [coder decodeObjectForKey:@"NS.decimal"];
    return [self initWithString:[s isKindOfClass:[NSString class]] ? s : @"NaN" locale:nil];
}
@end
