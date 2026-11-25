/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSNumberFormatter and NSByteCountFormatter, written
 * from Apple's public documentation of both classes, from the number
 * patterns of the public Unicode standard (Unicode Technical Standard #35,
 * Part 3) and from the Unicode CLDR's public English data (patterns,
 * currency symbols and names, plural rules); no Apple code was used.
 *
 * Numbers are written and read in English (United States) for every locale,
 * as Ferry's dates are; a locale's country only picks the default currency.
 * Doubles are first turned into the shortest decimal that reads back as the
 * same double, then rounded in decimal, so 2.675 to two places is 2.68 with
 * the default (half-even) rounding, as the decimal number it stands for.
 * Built without ARC. */
#import "FInternal.h"
#include <math.h>

/* ---- currencies ----------------------------------------------------------------------- */

static const struct currency {
    const char *code, *symbol, *one, *other;
    int digits;
} currencies[] = {
    {"USD", "$", "US dollar", "US dollars", 2},
    {"EUR", "\xe2\x82\xac", "euro", "euros", 2},
    {"GBP", "\xc2\xa3", "British pound", "British pounds", 2},
    {"JPY", "\xc2\xa5", "Japanese yen", "Japanese yen", 0},
    {"CAD", "CA$", "Canadian dollar", "Canadian dollars", 2},
    {"AUD", "A$", "Australian dollar", "Australian dollars", 2},
    {"NZD", "NZ$", "New Zealand dollar", "New Zealand dollars", 2},
    {"CHF", "CHF", "Swiss franc", "Swiss francs", 2},
    {"CNY", "CN\xc2\xa5", "Chinese yuan", "Chinese yuan", 2},
    {"HKD", "HK$", "Hong Kong dollar", "Hong Kong dollars", 2},
    {"TWD", "NT$", "New Taiwan dollar", "New Taiwan dollars", 2},
    {"INR", "\xe2\x82\xb9", "Indian rupee", "Indian rupees", 2},
    {"KRW", "\xe2\x82\xa9", "South Korean won", "South Korean won", 0},
    {"MXN", "MX$", "Mexican peso", "Mexican pesos", 2},
    {"BRL", "R$", "Brazilian real", "Brazilian reals", 2},
    {"ILS", "\xe2\x82\xaa", "Israeli new shekel", "Israeli new shekels", 2},
    {"VND", "\xe2\x82\xab", "Vietnamese dong", "Vietnamese dong", 0},
    {"PHP", "\xe2\x82\xb1", "Philippine peso", "Philippine pesos", 2},
    {"SEK", "SEK", "Swedish krona", "Swedish kronor", 2},
    {"NOK", "NOK", "Norwegian krone", "Norwegian kroner", 2},
    {"DKK", "DKK", "Danish krone", "Danish kroner", 2},
    {"PLN", "PLN", "Polish zloty", "Polish zlotys", 2},
    {"CZK", "CZK", "Czech koruna", "Czech korunas", 2},
    {"HUF", "HUF", "Hungarian forint", "Hungarian forints", 2},
    {"RUB", "RUB", "Russian ruble", "Russian rubles", 2},
    {"TRY", "TRY", "Turkish lira", "Turkish Lira", 2},
    {"ZAR", "ZAR", "South African rand", "South African rand", 2},
    {"SGD", "SGD", "Singapore dollar", "Singapore dollars", 2},
    {"THB", "THB", "Thai baht", "Thai baht", 2},
    {"ISK", "ISK", "Icelandic kr\xc3\xb3na", "Icelandic kr\xc3\xb3nur", 0},
    {"CLP", "CLP", "Chilean peso", "Chilean pesos", 0},
};

static const struct currency *currency_named(NSString *code)
{
    const char *c = [code UTF8String];
    for (size_t i = 0; c && i < sizeof currencies / sizeof currencies[0]; i++)
        if (!strcmp(currencies[i].code, c))
            return &currencies[i];
    return NULL;
}

NSString *FCurrencySymbol(NSString *code, int *digits)
{
    const struct currency *c = currency_named(code);
    if (digits)
        *digits = c ? c->digits : 2;
    return c ? [NSString stringWithUTF8String:c->symbol] : code;
}

NSString *FCurrencyOfCountry(NSString *country)
{
    static const char *const pairs[] = {
        "US USD", "GB GBP", "JP JPY", "CA CAD", "AU AUD", "NZ NZD", "CH CHF", "LI CHF", "CN CNY", "HK HKD", "TW TWD",
        "IN INR", "KR KRW", "MX MXN", "BR BRL", "IL ILS", "VN VND", "PH PHP", "SE SEK", "NO NOK", "DK DKK", "PL PLN",
        "CZ CZK", "HU HUF", "RU RUB", "TR TRY", "ZA ZAR", "SG SGD", "TH THB", "IS ISK", "CL CLP", "PR USD", "EC USD",
        "AT EUR", "BE EUR", "CY EUR", "DE EUR", "EE EUR", "ES EUR", "FI EUR", "FR EUR", "GR EUR", "HR EUR", "IE EUR",
        "IT EUR", "LT EUR", "LU EUR", "LV EUR", "MT EUR", "NL EUR", "PT EUR", "SI EUR", "SK EUR", "AD EUR", "MC EUR",
        "SM EUR", "VA EUR", "ME EUR",
    };
    const char *c = [country UTF8String];
    if (!c || strlen(c) != 2)
        return nil;
    for (size_t i = 0; i < sizeof pairs / sizeof pairs[0]; i++)
        if (!strncmp(pairs[i], c, 2))
            return [NSString stringWithUTF8String:pairs[i] + 3];
    return nil;
}

/* ---- decimal numbers -------------------------------------------------------------------- */

/* value = 0.d[0]d[1]...d[n-1] x 10^exp; no trailing zeros; n == 0 is zero. */
struct dec {
    BOOL neg;
    int special;   /* 1 NaN, 2 infinity */
    int n, exp;
    char d[400];
};

static void dec_trim(struct dec *x)
{
    int lead = 0;
    while (lead < x->n && x->d[lead] == '0')
        lead++;
    if (lead) {
        memmove(x->d, x->d + lead, x->n - lead);
        x->n -= lead;
        x->exp -= lead;
    }
    while (x->n && x->d[x->n - 1] == '0')
        x->n--;
    if (!x->n)
        x->exp = 0;
}

static void dec_from_double(double v, struct dec *x)
{
    memset(x, 0, sizeof *x);
    x->neg = __builtin_signbit(v) != 0;
    if (isnan(v)) {
        x->special = 1;
        x->neg = NO;
        return;
    }
    if (isinf(v)) {
        x->special = 2;
        return;
    }
    if (v == 0)
        return;
    char buf[64];
    for (int prec = 0; prec < 17; prec++) {   /* the shortest that reads back the same */
        snprintf(buf, sizeof buf, "%.*e", prec, fabs(v));
        if (strtod(buf, NULL) == fabs(v))
            break;
    }
    char *e = strchr(buf, 'e');
    for (char *p = buf; p < e; p++)
        if (*p >= '0' && *p <= '9')
            x->d[x->n++] = *p;
    x->exp = atoi(e + 1) + 1;
    dec_trim(x);
}

static void dec_from_integer(unsigned long long u, BOOL neg, struct dec *x)
{
    memset(x, 0, sizeof *x);
    x->neg = neg;
    char buf[32];
    snprintf(buf, sizeof buf, "%llu", u);
    x->n = (int)strlen(buf);
    memcpy(x->d, buf, x->n);
    x->exp = x->n;
    dec_trim(x);
}

/* An NSDecimalNumber's digits, exactly, from its description. */
static void dec_from_decimal_number(NSNumber *num, struct dec *x)
{
    memset(x, 0, sizeof *x);
    const char *s = [[num description] UTF8String];
    if (!strcmp(s, "NaN")) {
        x->special = 1;
        return;
    }
    if (*s == '-')
        x->neg = YES, s++;
    BOOL point = NO;
    for (; *s && x->n < (int)sizeof x->d; s++) {
        if (*s == '.') {
            point = YES;
            continue;
        }
        x->d[x->n++] = *s;
        if (!point)
            x->exp++;
    }
    dec_trim(x);
}

static void dec_from_number(NSNumber *num, struct dec *x)
{
    if ([num isKindOfClass:[NSDecimalNumber class]]) {
        dec_from_decimal_number(num, x);
        return;
    }
    const char *t = [num objCType];
    switch (t ? *t : 'd') {
    case 'c': case 's': case 'i': case 'l': case 'q': case 'B': {
        long long v = [num longLongValue];
        dec_from_integer(v < 0 ? 0ULL - (unsigned long long)v : (unsigned long long)v, v < 0, x);
        break;
    }
    case 'C': case 'S': case 'I': case 'L': case 'Q':
        dec_from_integer([num unsignedLongLongValue], NO, x);
        break;
    default:
        dec_from_double([num doubleValue], x);
    }
}

static double dec_value(const struct dec *x)
{
    if (x->special == 1)
        return NAN;
    if (x->special == 2)
        return x->neg ? -INFINITY : INFINITY;
    char buf[440];
    int k = snprintf(buf, sizeof buf, "%s0.", x->neg ? "-" : "");
    memcpy(buf + k, x->d, x->n);
    snprintf(buf + k + x->n, sizeof buf - k - x->n, "e%d", x->exp);
    return strtod(buf, NULL);
}

/* Keeps the first `keep` digits (exp + the fraction digits wanted, or the
 * significant digits wanted), rounding the rest away in the given mode. */
static void dec_round(struct dec *x, int keep, NSNumberFormatterRoundingMode mode)
{
    if (x->special || keep >= x->n)
        return;
    int first = keep >= 0 ? x->d[keep] - '0' : 0;
    BOOL rest = NO;
    for (int i = keep >= 0 ? keep + 1 : 0; i < x->n; i++)
        rest |= x->d[i] != '0';
    if (keep < 0)
        rest = YES;   /* every digit is dropped and they aren't all zero */
    BOOL any = first || rest, up;
    int last = keep > 0 ? x->d[keep - 1] - '0' : 0;
    switch (mode) {
    case NSNumberFormatterRoundCeiling: up = any && !x->neg; break;
    case NSNumberFormatterRoundFloor: up = any && x->neg; break;
    case NSNumberFormatterRoundDown: up = NO; break;
    case NSNumberFormatterRoundUp: up = any; break;
    case NSNumberFormatterRoundHalfDown: up = first > 5 || (first == 5 && rest); break;
    case NSNumberFormatterRoundHalfUp: up = first >= 5; break;
    default: up = first > 5 || (first == 5 && (rest || (last & 1))); break;
    }
    if (keep < 0 && first == 0 && mode >= NSNumberFormatterRoundHalfEven)
        up = NO;
    if (keep <= 0) {
        int unit = x->exp - keep;   /* where the kept part ends */
        x->n = 0;
        if (up) {
            x->d[0] = '1';
            x->n = 1;
            x->exp = unit + 1;
        } else {
            x->exp = 0;
        }
        return;
    }
    x->n = keep;
    for (int i = keep - 1; up && i >= 0; i--) {
        if (x->d[i] == '9') {
            x->d[i] = '0';
        } else {
            x->d[i]++;
            up = NO;
        }
    }
    if (up) {   /* 999 became 1000 */
        memmove(x->d + 1, x->d, x->n);
        x->d[0] = '1';
        x->n++;
        x->exp++;
    }
    dec_trim(x);
}

/* ---- the formatter's settings ---------------------------------------------------------------- */

static long fdiv_i(long a, long b) { return a / b - ((a % b) && ((a < 0) != (b < 0))); }

static NSNumberFormatterBehavior default_behavior = NSNumberFormatterBehavior10_4;

@implementation NSNumberFormatter {
    NSNumberFormatterStyle _style;
    NSNumberFormatterBehavior _behavior;
    NSLocale *_locale;
    NSUInteger _minInt, _maxInt, _minFrac, _maxFrac, _minSig, _maxSig, _width, _group, _group2;
    BOOL _usesSig, _grouping, _alwaysDecimal, _lenient, _partial, _allowsFloats, _decimalNumbers, _localizes;
    BOOL _sciAll, _negSet;
    int _expDigits;   /* 0: not scientific */
    NSNumberFormatterRoundingMode _rounding;
    NSNumberFormatterPadPosition _padPos;
    NSNumber *_increment, *_multiplier, *_min, *_max;
    /* prefixes and suffixes in pattern form: a currency sign, percent and minus sign stand for the symbols */
    NSString *_pp, *_ps, *_np, *_ns;
    NSString *_pad, *_currencyCode, *_currencySymbol, *_intlSymbol, *_currencyDecimal, *_currencyGrouping;
    NSString *_percent, *_perMill, *_minus, *_plus, *_exponent, *_zero, *_nil, *_nan, *_posInf, *_negInf;
    NSString *_decimal, *_groupingSep;
}

+ (NSNumberFormatterBehavior)defaultFormatterBehavior { return default_behavior; }
+ (void)setDefaultFormatterBehavior:(NSNumberFormatterBehavior)b { default_behavior = b; }

+ (NSString *)localizedStringFromNumber:(NSNumber *)num numberStyle:(NSNumberFormatterStyle)style
{
    NSNumberFormatter *f = [[[NSNumberFormatter alloc] init] autorelease];
    [f setNumberStyle:style];
    return [f stringFromNumber:num];
}

#define SETSTR(ivar, value)                                                                                            \
    do {                                                                                                               \
        NSString *_v = [(value) copy];                                                                                 \
        [ivar release];                                                                                                \
        ivar = _v;                                                                                                     \
    } while (0)

- (instancetype)init
{
    if ((self = [super init])) {
        _behavior = default_behavior;
        _allowsFloats = YES;
        _minSig = 1;
        _maxSig = 6;
        _pad = @" ";
        _rounding = NSNumberFormatterRoundHalfEven;
        _localizes = YES;
        [self setNumberStyle:NSNumberFormatterNoStyle];
    }
    return self;
}

- (void)dealloc
{
    NSObject *const objs[] = {_locale, _increment, _multiplier, _min, _max, _pp, _ps, _np, _ns, _pad,
                              _currencyCode, _currencySymbol, _intlSymbol, _currencyDecimal, _currencyGrouping,
                              _percent, _perMill, _minus, _plus, _exponent, _zero, _nil, _nan, _posInf, _negInf,
                              _decimal, _groupingSep};
    for (size_t i = 0; i < sizeof objs / sizeof objs[0]; i++)
        [objs[i] release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f->_style = _style;
    f->_behavior = _behavior;
    f->_minInt = _minInt;
    f->_maxInt = _maxInt;
    f->_minFrac = _minFrac;
    f->_maxFrac = _maxFrac;
    f->_minSig = _minSig;
    f->_maxSig = _maxSig;
    f->_width = _width;
    f->_group = _group;
    f->_group2 = _group2;
    f->_usesSig = _usesSig;
    f->_grouping = _grouping;
    f->_alwaysDecimal = _alwaysDecimal;
    f->_lenient = _lenient;
    f->_partial = _partial;
    f->_allowsFloats = _allowsFloats;
    f->_decimalNumbers = _decimalNumbers;
    f->_localizes = _localizes;
    f->_sciAll = _sciAll;
    f->_negSet = _negSet;
    f->_expDigits = _expDigits;
    f->_rounding = _rounding;
    f->_padPos = _padPos;
#define COPY(ivar)                                                                                                     \
    [f->ivar release];                                                                                                 \
    f->ivar = [ivar copy];
    COPY(_locale) COPY(_increment) COPY(_multiplier) COPY(_min) COPY(_max) COPY(_pp) COPY(_ps) COPY(_np) COPY(_ns)
    COPY(_pad) COPY(_currencyCode) COPY(_currencySymbol) COPY(_intlSymbol) COPY(_currencyDecimal)
    COPY(_currencyGrouping) COPY(_percent) COPY(_perMill) COPY(_minus) COPY(_plus) COPY(_exponent) COPY(_zero)
    COPY(_nil) COPY(_nan) COPY(_posInf) COPY(_negInf) COPY(_decimal) COPY(_groupingSep)
#undef COPY
    return f;
}

static BOOL is_currency_style(NSNumberFormatterStyle s)
{
    return s == NSNumberFormatterCurrencyStyle || s == NSNumberFormatterCurrencyISOCodeStyle ||
           s == NSNumberFormatterCurrencyPluralStyle || s == NSNumberFormatterCurrencyAccountingStyle;
}

- (int)_currencyDigits
{
    int digits;
    FCurrencySymbol([self currencyCode], &digits);
    return digits;
}

/* Every setting goes back to the style's own, from CLDR's English patterns. */
- (void)setNumberStyle:(NSNumberFormatterStyle)style
{
    _style = style;
    _minInt = 1;
    _maxInt = 2000000000;
    _minFrac = _maxFrac = 0;
    _grouping = YES;
    _group = 3;
    _group2 = 0;
    _usesSig = NO;
    _sciAll = NO;
    _expDigits = 0;
    _negSet = NO;
    _alwaysDecimal = NO;
    [_multiplier release];
    _multiplier = nil;
    NSString *pp = @"", *ps = @"";
    switch (style) {
    case NSNumberFormatterDecimalStyle:
        _maxFrac = 3;
        break;
    case NSNumberFormatterPercentStyle:
        ps = @"%";
        _multiplier = [[NSNumber numberWithInt:100] retain];
        break;
    case NSNumberFormatterCurrencyStyle:
    case NSNumberFormatterCurrencyAccountingStyle:
        pp = @"¤";
        _minFrac = _maxFrac = [self _currencyDigits];
        break;
    case NSNumberFormatterCurrencyISOCodeStyle:
        pp = @"¤¤ ";
        _minFrac = _maxFrac = [self _currencyDigits];
        break;
    case NSNumberFormatterCurrencyPluralStyle:
        ps = @" ¤¤¤";
        _minFrac = _maxFrac = [self _currencyDigits];
        break;
    case NSNumberFormatterScientificStyle:
        _minInt = 0;
        _maxInt = 1;
        _grouping = NO;
        _expDigits = 1;
        _sciAll = YES;
        break;
    case NSNumberFormatterSpellOutStyle:
        _grouping = NO;
        break;
    case NSNumberFormatterOrdinalStyle:
        break;
    default:   /* no style */
        _minInt = 0;
        _maxInt = 42;
        _grouping = NO;
        break;
    }
    SETSTR(_pp, pp);
    SETSTR(_ps, ps);
    SETSTR(_np, [@"-" stringByAppendingString:pp]);
    SETSTR(_ns, ps);
    if (style == NSNumberFormatterCurrencyAccountingStyle) {
        SETSTR(_np, @"(¤");
        SETSTR(_ns, @")");
        _negSet = YES;
    }
}
- (NSNumberFormatterStyle)numberStyle { return _style; }

/* ---- patterns ---- */

/* An affix in pattern form, expanded: the currency sign (one, two or three
 * of them: the symbol, the ISO code, the plural name), percent, per mille,
 * minus and plus signs, and quoted text. */
- (NSString *)_expand:(NSString *)raw plural:(BOOL)one prefix:(BOOL)prefix
{
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = [raw length];
    BOOL quoted = NO;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == '\'') {
            if (i + 1 < n && [raw characterAtIndex:i + 1] == '\'') {
                [out appendString:@"'"];
                i++;
            } else {
                quoted = !quoted;
            }
        } else if (quoted) {
            [out appendFormat:@"%C", c];
        } else if (c == 0xa4) {
            int k = 1;
            while (i + 1 < n && [raw characterAtIndex:i + 1] == 0xa4 && k < 3) {
                k++;
                i++;
            }
            if (k == 1) {
                /* CLDR's currency spacing: a symbol that ends (or starts) with a
                 * letter is kept apart from the digits by a no-break space */
                NSString *sym = [self currencySymbol];
                NSUInteger len = [sym length];
                NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
                if (len && i == n - 1 && prefix && [letters characterIsMember:[sym characterAtIndex:len - 1]])
                    sym = [sym stringByAppendingString:@"\u00a0"];
                else if (len && i + 1 == (NSUInteger)k && !prefix && [letters characterIsMember:[sym characterAtIndex:0]])
                    sym = [@"\u00a0" stringByAppendingString:sym];
                [out appendString:sym];
            } else if (k == 2) {
                [out appendString:[self internationalCurrencySymbol]];
            } else {
                const struct currency *cur = currency_named([self currencyCode]);
                [out appendString:cur ? [NSString stringWithUTF8String:one ? cur->one : cur->other]
                                      : [self currencyCode]];
            }
        } else if (c == '%') {
            [out appendString:[self percentSymbol]];
        } else if (c == 0x2030) {
            [out appendString:[self perMillSymbol]];
        } else if (c == '-') {
            [out appendString:[self minusSign]];
        } else if (c == '+') {
            [out appendString:[self plusSign]];
        } else {
            [out appendFormat:@"%C", c];
        }
    }
    return out;
}

static NSString *quote_affix(NSString *literal)
{
    if (!literal)
        return @"";
    NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@"¤%‰-+'"];
    if ([literal rangeOfCharacterFromSet:special].location == NSNotFound)
        return literal;
    return [NSString stringWithFormat:@"'%@'", [literal stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
}

static BOOL number_char(unichar c) { return c == '#' || c == '0' || c == ',' || c == '.' || c == '@' || (c >= '1' && c <= '9'); }

/* Reads one subpattern: prefix, number, suffix. */
static void split_pattern(NSString *pat, NSString **prefix, NSString **number, NSString **suffix)
{
    NSUInteger n = [pat length], i = 0, a, b;
    BOOL quoted = NO;
    for (; i < n; i++) {
        unichar c = [pat characterAtIndex:i];
        if (c == '\'')
            quoted = !quoted;
        else if (!quoted && number_char(c))
            break;
    }
    a = i;
    for (; i < n; i++) {
        unichar c = [pat characterAtIndex:i];
        if (number_char(c))
            continue;
        if (c == 'E' && i + 1 < n &&
            ([pat characterAtIndex:i + 1] == '0' || [pat characterAtIndex:i + 1] == '+')) {
            i++;
            while (i + 1 < n && ([pat characterAtIndex:i + 1] == '0' || [pat characterAtIndex:i + 1] == '+'))
                i++;
            continue;
        }
        break;
    }
    b = i;
    *prefix = [pat substringToIndex:a];
    *number = [pat substringWithRange:NSMakeRange(a, b - a)];
    *suffix = [pat substringFromIndex:b];
}

- (void)_applyPattern:(NSString *)pattern negative:(BOOL)negative
{
    if (!pattern)
        return;
    NSArray *parts = [pattern componentsSeparatedByString:@";"];
    NSString *prefix, *number, *suffix;
    split_pattern([parts objectAtIndex:0], &prefix, &number, &suffix);
    if (negative) {
        SETSTR(_np, prefix);
        SETSTR(_ns, suffix);
        _negSet = YES;
        return;
    }
    SETSTR(_pp, prefix);
    SETSTR(_ps, suffix);
    if ([parts count] > 1) {
        NSString *np, *nn, *ns;
        split_pattern([parts objectAtIndex:1], &np, &nn, &ns);
        SETSTR(_np, np);
        SETSTR(_ns, ns);
        _negSet = YES;
    } else if (!_negSet) {
        SETSTR(_np, [@"-" stringByAppendingString:prefix]);
        SETSTR(_ns, suffix);
    }
    NSUInteger len = [number length], i;
    NSUInteger hashes = 0, zeros = 0, fz = 0, fh = 0, ats = 0, sigHash = 0, lastComma = NSNotFound, prevComma = NSNotFound;
    NSUInteger intChars = 0;
    BOOL frac = NO, sci = NO;
    int expDigits = 0;
    for (i = 0; i < len; i++) {
        unichar c = [number characterAtIndex:i];
        if (sci) {
            if (c == '0')
                expDigits++;
        } else if (c == 'E') {
            sci = YES;
        } else if (c == '.') {
            frac = YES;
        } else if (frac) {
            if (c == '0' || (c >= '1' && c <= '9'))
                fz++;
            else if (c == '#')
                fh++;
        } else if (c == ',') {
            prevComma = lastComma;
            lastComma = intChars;
        } else if (c == '@') {
            ats++;
            intChars++;
        } else if (c == '#') {
            if (ats)
                sigHash++;
            else
                hashes++;
            intChars++;
        } else {
            zeros++;
            intChars++;
        }
    }
    _usesSig = ats > 0;
    if (_usesSig) {
        _minSig = ats;
        _maxSig = ats + sigHash;
    }
    _minInt = zeros;
    _minFrac = fz;
    _maxFrac = fz + fh;
    _alwaysDecimal = frac && !fz && !fh;
    _grouping = lastComma != NSNotFound;
    if (_grouping) {
        _group = intChars - lastComma;
        _group2 = prevComma != NSNotFound && lastComma - prevComma != _group ? lastComma - prevComma : 0;
    }
    _expDigits = sci ? (expDigits ? expDigits : 1) : 0;
    _maxInt = sci ? hashes + zeros : 2000000000;
    _sciAll = sci && !_minInt && !_maxFrac;
    NSString *affixes = [prefix stringByAppendingString:suffix];
    if ([affixes rangeOfString:@"%"].location != NSNotFound) {
        [_multiplier release];
        _multiplier = [[NSNumber numberWithInt:100] retain];
    } else if ([affixes rangeOfString:@"‰"].location != NSNotFound) {
        [_multiplier release];
        _multiplier = [[NSNumber numberWithInt:1000] retain];
    }
}

/* The pattern the current settings stand for. */
- (NSString *)_numberPattern
{
    NSMutableString *s = [NSMutableString string];
    if (_usesSig) {
        for (NSUInteger i = 0; i < _maxSig; i++)
            [s appendString:i < _minSig ? @"@" : @"#"];
    } else {
        NSUInteger total = _grouping ? MAX(_group + 1, _minInt) : MAX(_minInt, 1);
        if (_expDigits && _maxInt > total)
            total = _maxInt;
        for (NSUInteger i = 0; i < total; i++) {
            NSUInteger fromRight = total - i;
            [s appendString:fromRight <= _minInt ? @"0" : @"#"];
            if (_grouping && fromRight > 1 && (fromRight - 1) % _group == 0 && fromRight - 1 == _group)
                [s appendString:@","];
        }
        if (_maxFrac || _alwaysDecimal) {
            [s appendString:@"."];
            for (NSUInteger i = 0; i < _maxFrac; i++)
                [s appendString:i < _minFrac ? @"0" : @"#"];
        }
    }
    if (_expDigits) {
        [s appendString:@"E"];
        for (int i = 0; i < _expDigits; i++)
            [s appendString:@"0"];
    }
    return s;
}

- (NSString *)positiveFormat { return [NSString stringWithFormat:@"%@%@%@", _pp, [self _numberPattern], _ps]; }
- (void)setPositiveFormat:(NSString *)f { [self _applyPattern:f negative:NO]; }
- (NSString *)negativeFormat { return [NSString stringWithFormat:@"%@%@%@", _np, [self _numberPattern], _ns]; }
- (void)setNegativeFormat:(NSString *)f { [self _applyPattern:f negative:YES]; }
- (NSString *)format
{
    NSString *zero = _zero ? [NSString stringWithFormat:@";%@", quote_affix(_zero)] : @";0";
    return [NSString stringWithFormat:@"%@%@;%@", [self positiveFormat], zero, [self negativeFormat]];
}
/* "positive;zero;negative", or "positive;negative" */
- (void)setFormat:(NSString *)f
{
    NSArray *p = [f componentsSeparatedByString:@";"];
    [self _applyPattern:[p objectAtIndex:0] negative:NO];
    if ([p count] == 2)
        [self _applyPattern:[p objectAtIndex:1] negative:YES];
    if ([p count] >= 3) {
        NSString *zp, *zn, *zs;
        split_pattern([p objectAtIndex:1], &zp, &zn, &zs);
        if (![zn isEqualToString:@"0"] && ![zn length])
            [self setZeroSymbol:[self _expand:[p objectAtIndex:1] plural:NO prefix:NO]];
        [self _applyPattern:[p objectAtIndex:2] negative:YES];
    }
}

- (NSString *)positivePrefix { return [self _expand:_pp plural:NO prefix:YES]; }
- (void)setPositivePrefix:(NSString *)s { SETSTR(_pp, quote_affix(s)); }
- (NSString *)positiveSuffix { return [self _expand:_ps plural:NO prefix:NO]; }
- (void)setPositiveSuffix:(NSString *)s { SETSTR(_ps, quote_affix(s)); }
- (NSString *)negativePrefix { return [self _expand:_np plural:NO prefix:YES]; }
- (void)setNegativePrefix:(NSString *)s
{
    SETSTR(_np, quote_affix(s));
    _negSet = YES;
}
- (NSString *)negativeSuffix { return [self _expand:_ns plural:NO prefix:NO]; }
- (void)setNegativeSuffix:(NSString *)s
{
    SETSTR(_ns, quote_affix(s));
    _negSet = YES;
}

/* ---- plain properties ---- */

- (NSNumberFormatterBehavior)formatterBehavior { return _behavior; }
- (void)setFormatterBehavior:(NSNumberFormatterBehavior)b { _behavior = b; }
- (NSLocale *)locale { return _locale ?: [NSLocale currentLocale]; }
- (void)setLocale:(NSLocale *)l
{
    [l retain];
    [_locale release];
    _locale = l;
    if (is_currency_style(_style) && !_currencyCode)
        _minFrac = _maxFrac = [self _currencyDigits];
}
- (BOOL)generatesDecimalNumbers { return _decimalNumbers; }
- (void)setGeneratesDecimalNumbers:(BOOL)b { _decimalNumbers = b; }
- (NSNumberFormatterRoundingMode)roundingMode { return _rounding; }
- (void)setRoundingMode:(NSNumberFormatterRoundingMode)m { _rounding = m; }
- (NSNumber *)roundingIncrement { return _increment ?: [NSNumber numberWithInt:0]; }
- (void)setRoundingIncrement:(NSNumber *)n
{
    [n retain];
    [_increment release];
    _increment = n;
}
- (NSUInteger)minimumIntegerDigits { return _minInt; }
- (void)setMinimumIntegerDigits:(NSUInteger)n
{
    _minInt = n;
    if (_maxInt < n)
        _maxInt = n;
}
- (NSUInteger)maximumIntegerDigits { return _maxInt; }
- (void)setMaximumIntegerDigits:(NSUInteger)n
{
    _maxInt = n;
    if (_minInt > n)
        _minInt = n;
}
- (NSUInteger)minimumFractionDigits { return _minFrac; }
- (void)setMinimumFractionDigits:(NSUInteger)n
{
    _minFrac = n;
    if (_maxFrac < n)
        _maxFrac = n;
    _sciAll = NO;
}
- (NSUInteger)maximumFractionDigits { return _maxFrac; }
- (void)setMaximumFractionDigits:(NSUInteger)n
{
    _maxFrac = n;
    if (_minFrac > n)
        _minFrac = n;
    _sciAll = NO;
}
- (BOOL)usesSignificantDigits { return _usesSig; }
- (void)setUsesSignificantDigits:(BOOL)b { _usesSig = b; }
- (NSUInteger)minimumSignificantDigits { return _minSig; }
- (void)setMinimumSignificantDigits:(NSUInteger)n
{
    _minSig = n ? n : 1;
    if (_maxSig < _minSig)
        _maxSig = _minSig;
    _usesSig = YES;
}
- (NSUInteger)maximumSignificantDigits { return _maxSig; }
- (void)setMaximumSignificantDigits:(NSUInteger)n
{
    _maxSig = n ? n : 1;
    if (_minSig > _maxSig)
        _minSig = _maxSig;
    _usesSig = YES;
}
- (NSUInteger)formatWidth { return _width; }
- (void)setFormatWidth:(NSUInteger)n { _width = n; }
- (NSString *)paddingCharacter { return _pad; }
- (void)setPaddingCharacter:(NSString *)s { SETSTR(_pad, [s length] ? s : @" "); }
- (NSNumberFormatterPadPosition)paddingPosition { return _padPos; }
- (void)setPaddingPosition:(NSNumberFormatterPadPosition)p { _padPos = p; }
- (NSNumber *)multiplier { return _multiplier; }
- (void)setMultiplier:(NSNumber *)n
{
    [n retain];
    [_multiplier release];
    _multiplier = n;
}
- (BOOL)alwaysShowsDecimalSeparator { return _alwaysDecimal; }
- (void)setAlwaysShowsDecimalSeparator:(BOOL)b { _alwaysDecimal = b; }
- (BOOL)usesGroupingSeparator { return _grouping; }
- (void)setUsesGroupingSeparator:(BOOL)b { _grouping = b; }
- (NSUInteger)groupingSize { return _group; }
- (void)setGroupingSize:(NSUInteger)n { _group = n; }
- (NSUInteger)secondaryGroupingSize { return _group2; }
- (void)setSecondaryGroupingSize:(NSUInteger)n { _group2 = n; }
- (BOOL)isLenient { return _lenient; }
- (void)setLenient:(BOOL)b { _lenient = b; }
- (BOOL)isPartialStringValidationEnabled { return _partial; }
- (void)setPartialStringValidationEnabled:(BOOL)b { _partial = b; }
- (NSNumber *)minimum { return _min; }
- (void)setMinimum:(NSNumber *)n
{
    [n retain];
    [_min release];
    _min = n;
}
- (NSNumber *)maximum { return _max; }
- (void)setMaximum:(NSNumber *)n
{
    [n retain];
    [_max release];
    _max = n;
}
- (BOOL)allowsFloats { return _allowsFloats; }
- (void)setAllowsFloats:(BOOL)b { _allowsFloats = b; }
- (BOOL)hasThousandSeparators { return _grouping; }
- (void)setHasThousandSeparators:(BOOL)b { _grouping = b; }
- (NSString *)thousandSeparator { return [self groupingSeparator]; }
- (void)setThousandSeparator:(NSString *)s { [self setGroupingSeparator:s]; }
- (BOOL)localizesFormat { return _localizes; }
- (void)setLocalizesFormat:(BOOL)b { _localizes = b; }

/* The symbols, English (United States) unless set */
- (NSString *)currencyCode
{
    return _currencyCode ?: [[self locale] currencyCode] ?: @"USD";
}
- (void)setCurrencyCode:(NSString *)s
{
    SETSTR(_currencyCode, [s uppercaseString]);
    if (is_currency_style(_style))
        _minFrac = _maxFrac = [self _currencyDigits];
}
- (NSString *)currencySymbol { return _currencySymbol ?: FCurrencySymbol([self currencyCode], NULL); }
- (void)setCurrencySymbol:(NSString *)s { SETSTR(_currencySymbol, s); }
- (NSString *)internationalCurrencySymbol { return _intlSymbol ?: [self currencyCode]; }
- (void)setInternationalCurrencySymbol:(NSString *)s { SETSTR(_intlSymbol, s); }
- (NSString *)decimalSeparator { return _decimal ?: @"."; }
- (void)setDecimalSeparator:(NSString *)s { SETSTR(_decimal, s); }
- (NSString *)groupingSeparator { return _groupingSep ?: @","; }
- (void)setGroupingSeparator:(NSString *)s { SETSTR(_groupingSep, s); }
- (NSString *)currencyDecimalSeparator { return _currencyDecimal ?: [self decimalSeparator]; }
- (void)setCurrencyDecimalSeparator:(NSString *)s { SETSTR(_currencyDecimal, s); }
- (NSString *)currencyGroupingSeparator { return _currencyGrouping ?: [self groupingSeparator]; }
- (void)setCurrencyGroupingSeparator:(NSString *)s { SETSTR(_currencyGrouping, s); }
- (NSString *)percentSymbol { return _percent ?: @"%"; }
- (void)setPercentSymbol:(NSString *)s { SETSTR(_percent, s); }
- (NSString *)perMillSymbol { return _perMill ?: @"‰"; }
- (void)setPerMillSymbol:(NSString *)s { SETSTR(_perMill, s); }
- (NSString *)minusSign { return _minus ?: @"-"; }
- (void)setMinusSign:(NSString *)s { SETSTR(_minus, s); }
- (NSString *)plusSign { return _plus ?: @"+"; }
- (void)setPlusSign:(NSString *)s { SETSTR(_plus, s); }
- (NSString *)exponentSymbol { return _exponent ?: @"E"; }
- (void)setExponentSymbol:(NSString *)s { SETSTR(_exponent, s); }
- (NSString *)zeroSymbol { return _zero; }
- (void)setZeroSymbol:(NSString *)s { SETSTR(_zero, s); }
- (NSString *)nilSymbol { return _nil ?: @""; }
- (void)setNilSymbol:(NSString *)s { SETSTR(_nil, s); }
- (NSString *)notANumberSymbol { return _nan ?: @"NaN"; }
- (void)setNotANumberSymbol:(NSString *)s { SETSTR(_nan, s); }
- (NSString *)positiveInfinitySymbol { return _posInf ?: @"+∞"; }
- (void)setPositiveInfinitySymbol:(NSString *)s { SETSTR(_posInf, s); }
- (NSString *)negativeInfinitySymbol { return _negInf ?: @"-∞"; }
- (void)setNegativeInfinitySymbol:(NSString *)s { SETSTR(_negInf, s); }

/* ---- writing ---- */

static NSString *const ones[] = {@"zero",    @"one",     @"two",       @"three",    @"four",
                                 @"five",    @"six",     @"seven",     @"eight",    @"nine",
                                 @"ten",     @"eleven",  @"twelve",    @"thirteen", @"fourteen",
                                 @"fifteen", @"sixteen", @"seventeen", @"eighteen", @"nineteen"};
static NSString *const tens[] = {@"", @"", @"twenty", @"thirty", @"forty", @"fifty", @"sixty", @"seventy", @"eighty",
                                 @"ninety"};

static void spell_below_1000(NSMutableString *out, int v)
{
    if (v >= 100) {
        [out appendFormat:@"%@ hundred", ones[v / 100]];
        v %= 100;
        if (!v)
            return;
        [out appendString:@" "];
    }
    if (v < 20)
        [out appendString:ones[v]];
    else if (v % 10)
        [out appendFormat:@"%@-%@", tens[v / 10], ones[v % 10]];
    else
        [out appendString:tens[v / 10]];
}

/* English words for a whole number, as CLDR's "spellout-numbering" rules
 * write it ("one thousand two hundred thirty-four"). */
static NSString *spell_integer(unsigned long long v)
{
    static NSString *const scales[] = {@"", @" thousand", @" million", @" billion", @" trillion", @" quadrillion",
                                       @" quintillion"};
    if (!v)
        return @"zero";
    int groups[7], n = 0;
    while (v) {
        groups[n++] = (int)(v % 1000);
        v /= 1000;
    }
    NSMutableString *out = [NSMutableString string];
    for (int i = n - 1; i >= 0; i--) {
        if (!groups[i])
            continue;
        if ([out length])
            [out appendString:@" "];
        spell_below_1000(out, groups[i]);
        [out appendString:scales[i]];
    }
    return out;
}

static NSString *ordinal_suffix(unsigned long long v)
{
    if (v % 100 >= 11 && v % 100 <= 13)
        return @"th";
    switch (v % 10) {
    case 1: return @"st";
    case 2: return @"nd";
    case 3: return @"rd";
    default: return @"th";
    }
}

/* The digits of a value already rounded: integer part (minimum digits, the
 * maximum cut from the left, grouped) and fraction. */
- (void)_digitsOf:(const struct dec *)x into:(NSMutableString *)out minFrac:(NSUInteger)minFrac
             currency:(BOOL)currency
{
    NSMutableString *intPart = [NSMutableString string];
    for (int i = 0; i < x->exp; i++)
        [intPart appendFormat:@"%c", i < x->n ? x->d[i] : '0'];
    while ([intPart length] < _minInt)
        [intPart insertString:@"0" atIndex:0];
    if ([intPart length] > _maxInt)
        [intPart deleteCharactersInRange:NSMakeRange(0, [intPart length] - _maxInt)];
    NSMutableString *frac = [NSMutableString string];
    for (int i = x->exp; i < x->n; i++)
        [frac appendFormat:@"%c", i < 0 ? '0' : x->d[i]];
    if (x->exp < 0) {   /* zeros between the point and the first digit */
        [frac setString:@""];
        for (int i = x->exp; i < 0; i++)
            [frac appendString:@"0"];
        for (int i = 0; i < x->n; i++)
            [frac appendFormat:@"%c", x->d[i]];
    }
    while ([frac length] < minFrac)
        [frac appendString:@"0"];
    if (![intPart length] && (![frac length] || _usesSig))
        [intPart setString:@"0"];
    NSString *gsep = currency ? [self currencyGroupingSeparator] : [self groupingSeparator];
    if (_grouping && _group > 0 && [intPart length] > _group) {
        NSUInteger len = [intPart length], next = _group2 ? _group2 : _group;
        NSUInteger at = len - _group;
        NSMutableArray *cuts = [NSMutableArray array];
        while (at > 0) {
            [cuts addObject:[NSNumber numberWithUnsignedInteger:at]];
            at = at > next ? at - next : 0;
        }
        for (NSNumber *c in cuts)
            [intPart insertString:gsep atIndex:[c unsignedIntegerValue]];
    }
    [out appendString:intPart];
    if ([frac length] || _alwaysDecimal)
        [out appendString:currency ? [self currencyDecimalSeparator] : [self decimalSeparator]];
    [out appendString:frac];
}

- (NSString *)_body:(struct dec *)x one:(BOOL *)one
{
    NSMutableString *out = [NSMutableString string];
    BOOL currency = is_currency_style(_style);
    *one = NO;
    if (_style == NSNumberFormatterSpellOutStyle) {
        char intDigits[400] = "";
        int k = 0;
        for (int i = 0; i < x->exp && k < 30; i++)
            intDigits[k++] = i < x->n ? x->d[i] : '0';
        intDigits[k] = 0;
        if (x->exp > 21)
            return nil;   /* beyond the quintillions: digits instead */
        [out appendString:spell_integer(k ? strtoull(intDigits, NULL, 10) : 0)];
        if (x->n > x->exp) {
            [out appendString:@" point"];
            for (int i = x->exp; i < x->n; i++)
                [out appendFormat:@" %@", ones[i < 0 ? 0 : x->d[i] - '0']];
        }
        return out;
    }
    if (_expDigits) {   /* scientific: a mantissa and a power of ten */
        int intDigits = (int)MAX(_minInt, 1), e = 0;
        BOOL engineering = _maxInt > 1 && _maxInt > _minInt;
        if (x->n) {
            if (_usesSig)
                dec_round(x, (int)_maxSig, _rounding);
            else if (!_sciAll)
                dec_round(x, intDigits + (int)_maxFrac, _rounding);
            if (engineering) {
                e = (int)fdiv_i(x->exp - 1, (int)_maxInt) * (int)_maxInt;
                intDigits = x->exp - e;
            } else {
                e = x->exp - intDigits;
            }
        }
        struct dec m = *x;
        m.exp = x->n ? intDigits : 0;
        NSUInteger saveMin = _minInt;
        NSUInteger minFrac = _usesSig ? (_minSig > (NSUInteger)intDigits ? _minSig - intDigits : 0) : _minFrac;
        _minInt = intDigits;
        [self _digitsOf:&m into:out minFrac:minFrac currency:currency];
        _minInt = saveMin;
        [out appendString:[self exponentSymbol]];
        if (e < 0)
            [out appendString:[self minusSign]];
        [out appendFormat:@"%0*d", _expDigits, abs(e)];
        return out;
    }
    if (_increment && [_increment doubleValue] > 0) {
        double inc = [_increment doubleValue];
        struct dec q;
        dec_from_double(dec_value(x) / inc, &q);
        dec_round(&q, q.exp, _rounding);
        double r = dec_value(&q) * inc;
        dec_from_double(r, x);
        x->neg = q.neg;
        dec_round(x, x->exp + 15, NSNumberFormatterRoundHalfEven);   /* the multiplication's dust */
    }
    NSUInteger minFrac = _minFrac;
    if (_style == NSNumberFormatterOrdinalStyle) {
        dec_round(x, x->exp, _rounding);
        minFrac = 0;
    } else if (_usesSig) {
        dec_round(x, (int)_maxSig, _rounding);
        /* enough fraction digits to show the minimum: the digits from the
         * first one that isn't zero (a zero shows one of them itself) */
        int want = x->n ? (int)_minSig - x->exp : (int)_minSig - 1;
        minFrac = want > 0 ? (NSUInteger)want : 0;
    } else {
        dec_round(x, x->exp + (int)_maxFrac, _rounding);
    }
    [self _digitsOf:x into:out minFrac:minFrac currency:currency];
    if (_style == NSNumberFormatterOrdinalStyle) {
        unsigned long long v = 0;
        for (int i = 0; i < x->exp; i++)
            v = v * 10 + (unsigned long long)(i < x->n ? x->d[i] - '0' : 0);
        [out appendString:ordinal_suffix(v)];
    }
    /* CLDR's English plural rule: "one" is 1 with no fraction digits shown */
    *one = [out isEqualToString:@"1"];
    return out;
}


- (NSString *)stringFromNumber:(NSNumber *)number
{
    if (!number)
        return nil;
    struct dec x;
    dec_from_number(number, &x);
    if (x.special == 1)
        return [self notANumberSymbol];
    if (x.special == 2)
        return x.neg ? [self negativeInfinitySymbol] : [self positiveInfinitySymbol];
    if (!x.n && _zero)
        return _zero;
    if (_multiplier) {
        double m = [_multiplier doubleValue];
        double l = log10(fabs(m));
        if (m > 0 && l == floor(l) && fabs(l) < 30) {
            if (x.n)
                x.exp += (int)l;
        } else if (m != 1) {
            BOOL neg = x.neg;
            dec_from_double(dec_value(&x) * m, &x);
            if (!x.n)
                x.neg = neg != (m < 0);
        }
    }
    BOOL one;
    NSString *body = [self _body:&x one:&one];
    if (!body) {   /* too big to spell out */
        NSNumberFormatter *plain = [[[NSNumberFormatter alloc] init] autorelease];
        return [plain stringFromNumber:number];
    }
    if (_style == NSNumberFormatterSpellOutStyle)
        return x.neg && x.n ? [@"minus " stringByAppendingString:body] : body;
    NSString *prefix = [self _expand:x.neg ? _np : _pp plural:one prefix:YES];
    NSString *suffix = [self _expand:x.neg ? _ns : _ps plural:one prefix:NO];
    NSUInteger len = [prefix length] + [body length] + [suffix length];
    if (_width > len) {
        NSMutableString *padding = [NSMutableString string];
        for (NSUInteger i = len; i < _width; i++)
            [padding appendString:[_pad substringToIndex:1]];
        switch (_padPos) {
        case NSNumberFormatterPadBeforePrefix: prefix = [padding stringByAppendingString:prefix]; break;
        case NSNumberFormatterPadAfterPrefix: prefix = [prefix stringByAppendingString:padding]; break;
        case NSNumberFormatterPadBeforeSuffix: suffix = [padding stringByAppendingString:suffix]; break;
        default: suffix = [suffix stringByAppendingString:padding]; break;
        }
    }
    return [NSString stringWithFormat:@"%@%@%@", prefix, body, suffix];
}

- (NSString *)stringForObjectValue:(id)obj
{
    if (!obj)
        return [self nilSymbol];
    if ([obj isKindOfClass:[NSNumber class]])
        return [self stringFromNumber:obj];
    return nil;
}

/* ---- reading ---- */

static BOOL is_space(unichar c) { return c == ' ' || c == '\t' || c == 0xa0 || c == 0x202f || c == 0x2009; }

static BOOL take(NSString *s, NSUInteger *pos, NSUInteger end, NSString *word, BOOL fold)
{
    NSUInteger n = [word length];
    if (!n)
        return YES;
    if (*pos + n > end)
        return NO;
    NSString *part = [s substringWithRange:NSMakeRange(*pos, n)];
    if (fold ? [part caseInsensitiveCompare:word] == NSOrderedSame : [part isEqualToString:word]) {
        *pos += n;
        return YES;
    }
    return NO;
}

/* Reads [digits, groups][.digits][E[-]digits] from pos. */
- (BOOL)_readDigits:(NSString *)s at:(NSUInteger *)pos end:(NSUInteger)end into:(NSMutableString *)num
           fraction:(BOOL *)hasFrac
{
    BOOL currency = is_currency_style(_style), any = NO;
    NSString *dsep = currency ? [self currencyDecimalSeparator] : [self decimalSeparator];
    NSString *gsep = currency ? [self currencyGroupingSeparator] : [self groupingSeparator];
    NSUInteger p = *pos;
    *hasFrac = NO;
    while (p < end) {
        unichar c = [s characterAtIndex:p];
        if (c >= '0' && c <= '9') {
            [num appendFormat:@"%C", c];
            any = YES;
            p++;
        } else if (any && [gsep length] && (_grouping || _lenient) && take(s, &p, end, gsep, NO)) {
            if (p >= end || [s characterAtIndex:p] < '0' || [s characterAtIndex:p] > '9') {
                p -= [gsep length];
                break;
            }
        } else {
            break;
        }
    }
    NSUInteger save = p;
    if (take(s, &p, end, dsep, NO)) {
        BOOL fd = NO;
        [num appendString:@"."];
        while (p < end && [s characterAtIndex:p] >= '0' && [s characterAtIndex:p] <= '9') {
            [num appendFormat:@"%C", [s characterAtIndex:p]];
            p++;
            fd = YES;
        }
        if (!any && !fd) {
            p = save;
            [num deleteCharactersInRange:NSMakeRange([num length] - 1, 1)];
        } else {
            *hasFrac = fd;
            any = YES;
        }
    }
    if (!any)
        return NO;
    save = p;
    if (take(s, &p, end, [self exponentSymbol], YES)) {
        NSMutableString *e = [NSMutableString stringWithString:@"e"];
        if (take(s, &p, end, [self minusSign], NO))
            [e appendString:@"-"];
        else
            take(s, &p, end, [self plusSign], NO);
        BOOL ed = NO;
        while (p < end && [s characterAtIndex:p] >= '0' && [s characterAtIndex:p] <= '9') {
            [e appendFormat:@"%C", [s characterAtIndex:p]];
            p++;
            ed = YES;
        }
        if (ed) {
            [num appendString:e];
            *hasFrac = YES;
        } else {
            p = save;
        }
    }
    *pos = p;
    return YES;
}

/* The number in s[start, end), the whole of it. */
- (NSNumber *)_parse:(NSString *)s from:(NSUInteger)start to:(NSUInteger)end
{
    if (_lenient) {
        while (start < end && is_space([s characterAtIndex:start]))
            start++;
        while (end > start && is_space([s characterAtIndex:end - 1]))
            end--;
    }
    NSString *whole = [s substringWithRange:NSMakeRange(start, end - start)];
    if (_zero && [whole isEqualToString:_zero])
        return [NSNumber numberWithInt:0];
    if ([whole isEqualToString:[self notANumberSymbol]])
        return [NSNumber numberWithDouble:NAN];
    if ([whole isEqualToString:[self positiveInfinitySymbol]] || [whole isEqualToString:@"∞"])
        return [NSNumber numberWithDouble:INFINITY];
    if ([whole isEqualToString:[self negativeInfinitySymbol]])
        return [NSNumber numberWithDouble:-INFINITY];
    if (_style == NSNumberFormatterSpellOutStyle)
        return nil;
    /* the affixes, most specific first: negative, then positive, then (leniently) none */
    struct {
        NSString *pre, *suf;
        BOOL neg;
    } tries[6];
    int n = 0;
    BOOL bothOne[] = {NO, YES};
    for (int k = 0; k < 2; k++) {
        tries[n].pre = [self _expand:_np plural:bothOne[k] prefix:YES];
        tries[n].suf = [self _expand:_ns plural:bothOne[k] prefix:NO];
        tries[n++].neg = YES;
        tries[n].pre = [self _expand:_pp plural:bothOne[k] prefix:YES];
        tries[n].suf = [self _expand:_ps plural:bothOne[k] prefix:NO];
        tries[n++].neg = NO;
    }
    if (_lenient) {
        tries[n].pre = [self minusSign];
        tries[n].suf = @"";
        tries[n++].neg = YES;
        tries[n].pre = @"";
        tries[n].suf = @"";
        tries[n++].neg = NO;
    }
    for (int k = 0; k < n; k++) {
        NSUInteger p = start, e = end;
        NSString *pre = tries[k].pre, *suf = tries[k].suf;
        if (_lenient) {
            pre = [pre stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            suf = [suf stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            pre = [pre stringByReplacingOccurrencesOfString:@" " withString:@""];
            suf = [suf stringByReplacingOccurrencesOfString:@" " withString:@""];
        }
        if (!take(s, &p, e, pre, _lenient))
            continue;
        if ([suf length]) {
            if (e - p < [suf length])
                continue;
            NSString *tail = [s substringWithRange:NSMakeRange(e - [suf length], [suf length])];
            if (!(_lenient ? [tail caseInsensitiveCompare:suf] == NSOrderedSame : [tail isEqualToString:suf]))
                continue;
            e -= [suf length];
        }
        if (_lenient) {
            while (p < e && is_space([s characterAtIndex:p]))
                p++;
            while (e > p && is_space([s characterAtIndex:e - 1]))
                e--;
        }
        if (_style == NSNumberFormatterOrdinalStyle && e - p > 2) {
            NSString *tail = [[s substringWithRange:NSMakeRange(e - 2, 2)] lowercaseString];
            if ([@[ @"st", @"nd", @"rd", @"th" ] containsObject:tail])
                e -= 2;
        }
        NSMutableString *num = [NSMutableString string];
        BOOL frac;
        NSUInteger q = p;
        if (![self _readDigits:s at:&q end:e into:num fraction:&frac] || q != e)
            continue;
        double v = strtod([num UTF8String], NULL);
        if (_decimalNumbers) {   /* the digits read, exactly */
            NSDecimalNumber *d = [NSDecimalNumber decimalNumberWithString:num];
            if (_multiplier && [_multiplier doubleValue] != 0 && [_multiplier doubleValue] != 1)
                d = [d decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithDecimal:[_multiplier decimalValue]]];
            if (tries[k].neg)
                d = [[NSDecimalNumber zero] decimalNumberBySubtracting:d];
            if (!_allowsFloats && [d compare:[d decimalNumberByRoundingAccordingToBehavior:
                                                     [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundDown
                                                                                                            scale:0
                                                                                                 raiseOnExactness:NO
                                                                                                  raiseOnOverflow:NO
                                                                                                 raiseOnUnderflow:NO
                                                                                              raiseOnDivideByZero:NO]]] != NSOrderedSame)
                return nil;
            if ((_min && [d compare:_min] == NSOrderedAscending) || (_max && [d compare:_max] == NSOrderedDescending))
                return nil;
            return d;
        }
        if (_multiplier && [_multiplier doubleValue] != 0 && [_multiplier doubleValue] != 1) {
            double m = [_multiplier doubleValue], l = log10(fabs(m));
            if (m > 0 && l == floor(l) && fabs(l) < 30) {   /* moving the point, in decimal */
                char buf[64];
                snprintf(buf, sizeof buf, "%se-%d", [num UTF8String], (int)l);
                v = strtod(buf, NULL);
            } else {
                v /= m;
            }
            frac = frac || v != floor(v);
        }
        if (tries[k].neg)
            v = -v;
        if (!_allowsFloats && v != floor(v))
            return nil;
        if ((_min && v < [_min doubleValue]) || (_max && v > [_max doubleValue]))
            return nil;
        if (v == floor(v) && fabs(v) < 9007199254740992.0 && !(v == 0 && __builtin_signbit(v)))
            return [NSNumber numberWithLongLong:(long long)v];
        return [NSNumber numberWithDouble:v];
    }
    return nil;
}

- (NSNumber *)numberFromString:(NSString *)string
{
    if (!string)
        return nil;
    return [self _parse:string from:0 to:[string length]];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)range error:(NSError **)error
{
    NSRange r = range ? *range : NSMakeRange(0, [string length]);
    NSNumber *n = string ? [self _parse:string from:r.location to:NSMaxRange(r)] : nil;
    if (!n) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:2048
                                     userInfo:@{
                                         NSLocalizedDescriptionKey : [NSString
                                             stringWithFormat:@"The value “%@” is invalid.",
                                                              [string substringWithRange:r] ?: @""]
                                     }];
        return NO;
    }
    if (obj)
        *obj = n;
    return YES;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error
{
    NSNumber *n = [self numberFromString:string];
    if (!n) {
        if (error)
            *error = @"Invalid number";
        return NO;
    }
    if (obj)
        *obj = n;
    return YES;
}

- (BOOL)isPartialStringValid:(NSString *)partial newEditingString:(NSString **)newString
            errorDescription:(NSString **)error
{
    if (newString)
        *newString = nil;
    if (!_partial || ![partial length])
        return YES;
    /* digits, signs, separators and the affixes' characters */
    NSMutableString *allowed = [NSMutableString stringWithString:@"0123456789"];
    for (NSString *s in @[ [self decimalSeparator], [self groupingSeparator], [self minusSign], [self plusSign],
                           [self positivePrefix], [self positiveSuffix], [self negativePrefix],
                           [self negativeSuffix], [self exponentSymbol] ])
        [allowed appendString:s];
    NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:allowed] invertedSet];
    if ([partial rangeOfCharacterFromSet:bad].location != NSNotFound) {
        if (error)
            *error = @"Invalid number";
        return NO;
    }
    return YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s: %p> %@", object_getClassName(self), self, [self positiveFormat]];
}

/* ---- archiving, for nibs ---------------------------------------------------------------------------- */

/* A nib's formatter keeps its settings in "NS.attributes", named as the
 * properties are; older ones have a few keys of their own. The behavior and
 * style go first, since a style sets the formats it implies. */
void FApplyFormatterAttributes(id formatter, NSDictionary *attrs, NSArray *first)
{
    NSMutableArray *keys = [NSMutableArray arrayWithArray:first];
    for (NSString *k in attrs)
        if (![keys containsObject:k])
            [keys addObject:k];
    for (NSString *k in keys) {
        id v = [attrs objectForKey:k];
        if (!v || ![k isKindOfClass:[NSString class]] || ![k length])
            continue;
        NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[k substringToIndex:1] uppercaseString],
                                                      [k substringFromIndex:1]];
        if (![formatter respondsToSelector:NSSelectorFromString(setter)])
            continue;
        if ([v isKindOfClass:[NSAttributedString class]])
            v = [v string];
        @try {
            [formatter setValue:v forKey:k];
        } @catch (NSException *e) {
        }
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [self init]))
        return nil;
    NSDictionary *attrs = [coder decodeObjectForKey:@"NS.attributes"];
    if ([attrs isKindOfClass:[NSDictionary class]] && [attrs count]) {
        FApplyFormatterAttributes(self, attrs, @[ @"formatterBehavior", @"numberStyle" ]);
        return self;
    }
    NSString *pos = [coder decodeObjectForKey:@"NS.positiveformat"];
    NSString *neg = [coder decodeObjectForKey:@"NS.negativeformat"];
    if ([pos isKindOfClass:[NSString class]])
        [self setPositiveFormat:pos];
    if ([neg isKindOfClass:[NSString class]])
        [self setNegativeFormat:neg];
    NSString *dec = [coder decodeObjectForKey:@"NS.decimal"];
    NSString *thou = [coder decodeObjectForKey:@"NS.thousand"];
    if ([dec isKindOfClass:[NSString class]])
        [self setDecimalSeparator:dec];
    if ([thou isKindOfClass:[NSString class]])
        [self setGroupingSeparator:thou];
    [self setUsesGroupingSeparator:[coder decodeBoolForKey:@"NS.hasthousands"]];
    if ([coder containsValueForKey:@"NS.allowsfloats"])
        [self setAllowsFloats:[coder decodeBoolForKey:@"NS.allowsfloats"]];
    /* A limit of no digits is "not a number": no limit. */
    NSNumber *min = [coder decodeObjectForKey:@"NS.min"], *max = [coder decodeObjectForKey:@"NS.max"];
    if ([min isKindOfClass:[NSNumber class]] && ![min isEqual:[NSDecimalNumber notANumber]])
        [self setMinimum:min];
    if ([max isKindOfClass:[NSNumber class]] && ![max isEqual:[NSDecimalNumber notANumber]])
        [self setMaximum:max];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    [attrs setObject:@([self formatterBehavior]) forKey:@"formatterBehavior"];
    [attrs setObject:@([self numberStyle]) forKey:@"numberStyle"];
    static NSString *const keys[] = {@"positiveFormat", @"negativeFormat", @"decimalSeparator", @"groupingSeparator",
                                     @"minimum", @"maximum", @"nilSymbol", @"zeroSymbol", nil};
    for (int i = 0; keys[i]; i++) {
        id v = [self valueForKey:keys[i]];
        if (v)
            [attrs setObject:v forKey:keys[i]];
    }
    [attrs setObject:@([self usesGroupingSeparator]) forKey:@"usesGroupingSeparator"];
    [attrs setObject:@([self allowsFloats]) forKey:@"allowsFloats"];
    [attrs setObject:@([self minimumFractionDigits]) forKey:@"minimumFractionDigits"];
    [attrs setObject:@([self maximumFractionDigits]) forKey:@"maximumFractionDigits"];
    [attrs setObject:@([self generatesDecimalNumbers]) forKey:@"generatesDecimalNumbers"];
    [coder encodeObject:attrs forKey:@"NS.attributes"];
}
@end

/* ---- NSByteCountFormatter ---------------------------------------------------------------------- */

@implementation NSByteCountFormatter {
    NSByteCountFormatterUnits _units;
    NSByteCountFormatterCountStyle _countStyle;
    BOOL _nonnumeric, _unit, _count, _actual, _adaptive, _zeroPads;
}

+ (NSString *)stringFromByteCount:(long long)count countStyle:(NSByteCountFormatterCountStyle)style
{
    NSByteCountFormatter *f = [[[NSByteCountFormatter alloc] init] autorelease];
    [f setCountStyle:style];
    return [f stringFromByteCount:count];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _nonnumeric = _unit = _count = _adaptive = YES;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSByteCountFormatter *f = [[NSByteCountFormatter alloc] init];
    f->_units = _units;
    f->_countStyle = _countStyle;
    f->_nonnumeric = _nonnumeric;
    f->_unit = _unit;
    f->_count = _count;
    f->_actual = _actual;
    f->_adaptive = _adaptive;
    f->_zeroPads = _zeroPads;
    return f;
}

- (NSByteCountFormatterUnits)allowedUnits { return _units; }
- (void)setAllowedUnits:(NSByteCountFormatterUnits)u { _units = u; }
- (NSByteCountFormatterCountStyle)countStyle { return _countStyle; }
- (void)setCountStyle:(NSByteCountFormatterCountStyle)s { _countStyle = s; }
- (BOOL)allowsNonnumericFormatting { return _nonnumeric; }
- (void)setAllowsNonnumericFormatting:(BOOL)b { _nonnumeric = b; }
- (BOOL)includesUnit { return _unit; }
- (void)setIncludesUnit:(BOOL)b { _unit = b; }
- (BOOL)includesCount { return _count; }
- (void)setIncludesCount:(BOOL)b { _count = b; }
- (BOOL)includesActualByteCount { return _actual; }
- (void)setIncludesActualByteCount:(BOOL)b { _actual = b; }
- (BOOL)isAdaptive { return _adaptive; }
- (void)setAdaptive:(BOOL)b { _adaptive = b; }
- (BOOL)zeroPadsFractionDigits { return _zeroPads; }
- (void)setZeroPadsFractionDigits:(BOOL)b { _zeroPads = b; }

/* Files and decimal counts are in thousands, memory and binary ones in
 * 1,024s (still written KB, MB and so on, as on a Mac). */
- (NSString *)stringFromByteCount:(long long)count
{
    static NSString *const names[] = {@"bytes", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB", @"ZB", @"YB"};
    double base = _countStyle == NSByteCountFormatterCountStyleMemory || _countStyle == NSByteCountFormatterCountStyleBinary
                      ? 1024
                      : 1000;
    NSUInteger allowed = _units ? _units : NSByteCountFormatterUseAll;
    int lowest = -1, chosen = -1;
    double mag = fabs((double)count);
    for (int u = 0; u <= 8; u++) {
        BOOL ok = u < 8 ? (allowed & (1UL << u)) != 0 : (allowed & NSByteCountFormatterUseYBOrHigher) != 0;
        if (!ok)
            continue;
        if (lowest < 0)
            lowest = u;
        if (mag >= pow(base, u))
            chosen = u;
    }
    if (lowest < 0)
        lowest = 0;
    if (chosen < 0)
        chosen = lowest;
    if (!count && _nonnumeric && _count && _unit) {
        int u = (allowed & NSByteCountFormatterUseKB) || !(allowed & NSByteCountFormatterUseBytes) ? (lowest > 1 ? lowest : 1) : 0;
        return [NSString stringWithFormat:@"Zero %@", names[u]];
    }
    double value = (double)count / pow(base, chosen);
    int digits = !_adaptive ? (chosen ? 2 : 0) : chosen <= 1 ? 0 : chosen == 2 ? 1 : 2;
    /* a count that rounds up to a whole unit more is written in that unit (999,999 bytes: 1 MB) */
    double scale = digits == 0 ? 1 : digits == 1 ? 10 : 100;
    if (chosen < 8 && fabs(round(value * scale) / scale) >= base) {
        BOOL ok = chosen + 1 < 8 ? (allowed & (1UL << (chosen + 1))) != 0
                                 : (allowed & NSByteCountFormatterUseYBOrHigher) != 0;
        if (ok) {
            chosen++;
            value = (double)count / pow(base, chosen);
            digits = !_adaptive ? 2 : chosen == 2 ? 1 : 2;
        }
    }
    NSNumberFormatter *nf = [[[NSNumberFormatter alloc] init] autorelease];
    [nf setNumberStyle:NSNumberFormatterDecimalStyle];
    [nf setMaximumFractionDigits:digits];
    [nf setMinimumFractionDigits:_zeroPads ? digits : 0];
    NSString *num = [nf stringFromNumber:[NSNumber numberWithDouble:value]];
    NSString *unit = names[chosen];
    if (!chosen && [num isEqualToString:@"1"])
        unit = @"byte";
    NSString *s;
    if (_count && _unit)
        s = [NSString stringWithFormat:@"%@ %@", num, unit];
    else if (_count)
        s = num;
    else
        s = _unit ? unit : @"";
    if (_actual && chosen) {
        NSString *exact = [nf stringFromNumber:[NSNumber numberWithLongLong:count]];
        s = [NSString stringWithFormat:@"%@ (%@ %@)", s, exact, llabs(count) == 1 ? @"byte" : @"bytes"];
    }
    return s;
}

- (NSString *)stringForObjectValue:(id)obj
{
    return [obj isKindOfClass:[NSNumber class]] ? [self stringFromByteCount:[obj longLongValue]] : nil;
}
@end
