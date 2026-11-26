/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSNumberFormatter and NSByteCountFormatter in English (United States): the
 * number styles, fraction, integer and significant digits, the rounding
 * modes, grouping, multipliers, padding, patterns, the special symbols,
 * currencies other than the dollar, reading numbers back strictly and
 * leniently, and file and memory sizes. */
#import <Foundation/Foundation.h>
#include <stdio.h>

static NSNumberFormatter *styled(NSNumberFormatterStyle style)
{
    NSNumberFormatter *f = [[[NSNumberFormatter alloc] init] autorelease];
    [f setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    [f setNumberStyle:style];
    return f;
}

static void writes(NSNumberFormatter *f, NSNumber *n)
{
    NSString *s = [f stringFromNumber:n];
    printf("    %s -> \"%s\"\n", [[n description] UTF8String], s ? [s UTF8String] : "(nil)");
}

static void reads(NSNumberFormatter *f, NSString *s)
{
    NSNumber *n = [f numberFromString:s];
    printf("    \"%s\" -> %s%s\n", [s UTF8String], n ? [[n description] UTF8String] : "(nil)",
           n ? (strchr("dfFD", *[n objCType]) ? " (double)" : " (integer)") : "");
}

int main(void)
{
    @autoreleasepool {
        NSNumber *big = [NSNumber numberWithDouble:1234567.891];
        NSNumber *neg = [NSNumber numberWithDouble:-1234.5678];
        NSNumber *small = [NSNumber numberWithDouble:0.000123];
        NSNumber *one = [NSNumber numberWithInt:1];
        NSNumber *zero = [NSNumber numberWithInt:0];
        NSArray *some = @[ big, neg, small, one, zero, [NSNumber numberWithDouble:0.5],
                           [NSNumber numberWithLongLong:9007199254740993LL] ];
        const struct {
            const char *name;
            NSNumberFormatterStyle style;
        } styles[] = {{"no style", NSNumberFormatterNoStyle},
                      {"decimal", NSNumberFormatterDecimalStyle},
                      {"percent", NSNumberFormatterPercentStyle},
                      {"currency", NSNumberFormatterCurrencyStyle},
                      {"accounting", NSNumberFormatterCurrencyAccountingStyle},
                      {"ISO code", NSNumberFormatterCurrencyISOCodeStyle},
                      {"plural", NSNumberFormatterCurrencyPluralStyle},
                      {"scientific", NSNumberFormatterScientificStyle},
                      {"spell-out", NSNumberFormatterSpellOutStyle},
                      {"ordinal", NSNumberFormatterOrdinalStyle}};
        printf("styles\n");
        for (size_t i = 0; i < sizeof styles / sizeof styles[0]; i++) {
            NSNumberFormatter *f = styled(styles[i].style);
            printf("  %s (%s; fraction digits %lu..%lu, integer digits %lu..%lu)\n", styles[i].name,
                   [[f positiveFormat] UTF8String], (unsigned long)[f minimumFractionDigits],
                   (unsigned long)[f maximumFractionDigits], (unsigned long)[f minimumIntegerDigits],
                   (unsigned long)[f maximumIntegerDigits]);
            for (NSNumber *n in some)
                writes(f, n);
        }
        printf("  class method: %s, %s\n",
               [[NSNumberFormatter localizedStringFromNumber:big numberStyle:NSNumberFormatterDecimalStyle] UTF8String],
               [[NSNumberFormatter localizedStringFromNumber:[NSNumber numberWithDouble:0.256]
                                                 numberStyle:NSNumberFormatterPercentStyle] UTF8String]);
        NSNumberFormatter *plural = styled(NSNumberFormatterCurrencyPluralStyle);
        [plural setMaximumFractionDigits:0];
        [plural setMinimumFractionDigits:0];
        printf("  plural with no fraction digits:\n");
        writes(plural, one);
        writes(plural, [NSNumber numberWithInt:2]);
        NSNumberFormatter *sp = styled(NSNumberFormatterSpellOutStyle);
        printf("  spelled out:\n");
        writes(sp, [NSNumber numberWithInt:21]);
        writes(sp, [NSNumber numberWithInt:100]);
        writes(sp, [NSNumber numberWithLongLong:1000000005LL]);
        writes(sp, [NSNumber numberWithInt:-40]);
        writes(sp, [NSNumber numberWithDouble:3.14]);
        NSNumberFormatter *ord = styled(NSNumberFormatterOrdinalStyle);
        printf("  ordinals:");
        for (int i = 1; i <= 24; i++)
            printf(" %s", [[ord stringFromNumber:[NSNumber numberWithInt:i == 24 ? 111 : i]] UTF8String]);
        printf("\n");

        printf("digits\n");
        NSNumberFormatter *d = styled(NSNumberFormatterDecimalStyle);
        [d setMinimumFractionDigits:2];
        [d setMaximumFractionDigits:4];
        printf("  2 to 4 fraction digits (%s)\n", [[d positiveFormat] UTF8String]);
        writes(d, [NSNumber numberWithDouble:3]);
        writes(d, [NSNumber numberWithDouble:3.14159]);
        writes(d, [NSNumber numberWithDouble:2.5e-5]);
        [d setMinimumIntegerDigits:4];
        [d setUsesGroupingSeparator:NO];
        printf("  4 integer digits, no grouping (%s)\n", [[d positiveFormat] UTF8String]);
        writes(d, [NSNumber numberWithDouble:7.5]);
        writes(d, [NSNumber numberWithDouble:123456.5]);
        [d setMaximumIntegerDigits:2];
        printf("  at most 2 integer digits\n");
        writes(d, [NSNumber numberWithDouble:123456.5]);
        NSNumberFormatter *sig = styled(NSNumberFormatterDecimalStyle);
        [sig setUsesSignificantDigits:YES];
        [sig setMinimumSignificantDigits:2];
        [sig setMaximumSignificantDigits:3];
        printf("  2 to 3 significant digits\n");
        writes(sig, [NSNumber numberWithDouble:1234567]);
        writes(sig, [NSNumber numberWithDouble:3.14159]);
        writes(sig, [NSNumber numberWithDouble:0.0012345]);
        writes(sig, [NSNumber numberWithDouble:5]);
        writes(sig, zero);
        NSNumberFormatter *sci = styled(NSNumberFormatterScientificStyle);
        [sci setMaximumFractionDigits:2];
        printf("  scientific, 2 fraction digits\n");
        writes(sci, big);
        writes(sci, small);
        writes(sci, [NSNumber numberWithDouble:-0.5]);

        printf("rounding\n");
        const struct {
            const char *name;
            NSNumberFormatterRoundingMode mode;
        } modes[] = {{"ceiling", NSNumberFormatterRoundCeiling},   {"floor", NSNumberFormatterRoundFloor},
                     {"down", NSNumberFormatterRoundDown},         {"up", NSNumberFormatterRoundUp},
                     {"half even", NSNumberFormatterRoundHalfEven}, {"half down", NSNumberFormatterRoundHalfDown},
                     {"half up", NSNumberFormatterRoundHalfUp}};
        double values[] = {2.5, 3.5, -2.5, 2.51, -2.49, 0.4, -0.4};
        NSNumberFormatter *r = styled(NSNumberFormatterDecimalStyle);
        [r setMaximumFractionDigits:0];
        printf("  %-10s", "");
        for (size_t j = 0; j < sizeof values / sizeof values[0]; j++)
            printf(" %6g", values[j]);
        printf("\n");
        for (size_t i = 0; i < sizeof modes / sizeof modes[0]; i++) {
            [r setRoundingMode:modes[i].mode];
            printf("  %-10s", modes[i].name);
            for (size_t j = 0; j < sizeof values / sizeof values[0]; j++)
                printf(" %6s", [[r stringFromNumber:[NSNumber numberWithDouble:values[j]]] UTF8String]);
            printf("\n");
        }
        NSNumberFormatter *two = styled(NSNumberFormatterDecimalStyle);
        [two setMaximumFractionDigits:2];
        printf("  2.675 and 1.005 to two places (half even, as decimals): %s, %s\n",
               [[two stringFromNumber:[NSNumber numberWithDouble:2.675]] UTF8String],
               [[two stringFromNumber:[NSNumber numberWithDouble:1.005]] UTF8String]);
        printf("  999.999 to two places: %s\n", [[two stringFromNumber:[NSNumber numberWithDouble:999.999]] UTF8String]);
        NSNumberFormatter *inc = styled(NSNumberFormatterDecimalStyle);
        [inc setRoundingIncrement:[NSNumber numberWithDouble:0.25]];
        [inc setMaximumFractionDigits:2];
        printf("  to the nearest 0.25: %s, %s\n", [[inc stringFromNumber:[NSNumber numberWithDouble:1.13]] UTF8String],
               [[inc stringFromNumber:[NSNumber numberWithDouble:1.9]] UTF8String]);

        printf("settings\n");
        NSNumberFormatter *g = styled(NSNumberFormatterDecimalStyle);
        [g setGroupingSize:4];
        printf("  groups of 4: %s\n", [[g stringFromNumber:[NSNumber numberWithLongLong:123456789]] UTF8String]);
        [g setGroupingSize:3];
        [g setSecondaryGroupingSize:2];
        printf("  3 then 2 (Indian style): %s\n",
               [[g stringFromNumber:[NSNumber numberWithLongLong:123456789]] UTF8String]);
        NSNumberFormatter *sep = styled(NSNumberFormatterDecimalStyle);
        [sep setGroupingSeparator:@"."];
        [sep setDecimalSeparator:@","];
        printf("  other separators: %s\n", [[sep stringFromNumber:big] UTF8String]);
        NSNumberFormatter *mul = styled(NSNumberFormatterDecimalStyle);
        [mul setMultiplier:[NSNumber numberWithInt:1000]];
        [mul setPositiveSuffix:@" per mille"];
        printf("  multiplier 1000: %s\n", [[mul stringFromNumber:[NSNumber numberWithDouble:0.0425]] UTF8String]);
        NSNumberFormatter *pad = styled(NSNumberFormatterDecimalStyle);
        [pad setFormatWidth:10];
        [pad setPaddingCharacter:@"*"];
        const char *positions[] = {"before prefix", "after prefix", "before suffix", "after suffix"};
        for (int i = 0; i < 4; i++) {
            [pad setPaddingPosition:(NSNumberFormatterPadPosition)i];
            printf("  padded %s: %s\n", positions[i], [[pad stringFromNumber:[NSNumber numberWithInt:-42]] UTF8String]);
        }
        NSNumberFormatter *always = styled(NSNumberFormatterNoStyle);
        [always setAlwaysShowsDecimalSeparator:YES];
        printf("  always the decimal separator: %s\n", [[always stringFromNumber:[NSNumber numberWithInt:5]] UTF8String]);
        NSNumberFormatter *affix = styled(NSNumberFormatterDecimalStyle);
        [affix setPositivePrefix:@"+"];
        [affix setNegativePrefix:@"("];
        [affix setNegativeSuffix:@")"];
        printf("  own prefixes: %s, %s (%s)\n", [[affix stringFromNumber:big] UTF8String],
               [[affix stringFromNumber:neg] UTF8String], [[affix negativeFormat] UTF8String]);

        printf("patterns\n");
        NSString *patterns[] = {@"#,##0.00",   @"0.###E0",       @"00.00%",  @"#,##0.00 ¤¤",
                                @"'#'0;'-'0",   @"#,##0.00;(#,##0.00)", @"@@#", @"##0.##E0"};
        for (size_t i = 0; i < sizeof patterns / sizeof patterns[0]; i++) {
            NSNumberFormatter *p = styled(NSNumberFormatterNoStyle);
            [p setPositiveFormat:patterns[i]];
            printf("  %s: %s, %s, %s\n", [patterns[i] UTF8String], [[p stringFromNumber:big] UTF8String],
                   [[p stringFromNumber:neg] UTF8String], [[p stringFromNumber:small] UTF8String]);
        }
        NSNumberFormatter *fmt = styled(NSNumberFormatterNoStyle);
        [fmt setFormat:@"#,##0.00;zero;-#,##0.00"];
        printf("  format with a zero: %s, %s, %s\n", [[fmt stringFromNumber:big] UTF8String],
               [[fmt stringFromNumber:zero] UTF8String], [[fmt stringFromNumber:neg] UTF8String]);

        printf("symbols\n");
        NSNumberFormatter *sym = styled(NSNumberFormatterDecimalStyle);
        printf("  %s %s %s %s %s %s %s %s\n", [[sym decimalSeparator] UTF8String], [[sym groupingSeparator] UTF8String],
               [[sym percentSymbol] UTF8String], [[sym perMillSymbol] UTF8String], [[sym minusSign] UTF8String],
               [[sym plusSign] UTF8String], [[sym exponentSymbol] UTF8String], [[sym currencySymbol] UTF8String]);
        writes(sym, [NSNumber numberWithDouble:NAN]);
        writes(sym, [NSNumber numberWithDouble:INFINITY]);
        writes(sym, [NSNumber numberWithDouble:-INFINITY]);
        writes(sym, [NSNumber numberWithDouble:-0.0001]);
        [sym setZeroSymbol:@"nothing"];
        writes(sym, zero);
        [sym setNilSymbol:@"none"];
        printf("    nil -> \"%s\", nil string -> %s\n", [[sym stringForObjectValue:nil] UTF8String],
               [sym stringFromNumber:nil] ? "a string" : "(nil)");

        printf("currencies\n");
        NSString *codes[] = {@"EUR", @"GBP", @"JPY", @"CAD", @"INR", @"CHF", @"XYZ"};
        for (size_t i = 0; i < sizeof codes / sizeof codes[0]; i++) {
            NSNumberFormatter *c = styled(NSNumberFormatterCurrencyStyle);
            [c setCurrencyCode:codes[i]];
            NSNumberFormatter *p = styled(NSNumberFormatterCurrencyPluralStyle);
            [p setCurrencyCode:codes[i]];
            printf("  %s: %s, %s; %s\n", [codes[i] UTF8String], [[c stringFromNumber:neg] UTF8String],
                   [[c currencySymbol] UTF8String], [[p stringFromNumber:big] UTF8String]);
        }
        NSNumberFormatter *fr = [[[NSNumberFormatter alloc] init] autorelease];
        [fr setLocale:[NSLocale localeWithLocaleIdentifier:@"fr_FR"]];
        [fr setNumberStyle:NSNumberFormatterCurrencyStyle];
        printf("  a fr_FR locale (written in English): %s %s\n", [[fr currencyCode] UTF8String],
               [[fr stringFromNumber:big] UTF8String]);
        NSLocale *jp = [NSLocale localeWithLocaleIdentifier:@"ja_JP"];
        printf("  locales: ja_JP %s %s, en_GB %s, de_CH %s, en %s\n", [[jp currencyCode] UTF8String],
               [[jp currencySymbol] UTF8String],
               [[[NSLocale localeWithLocaleIdentifier:@"en_GB"] objectForKey:NSLocaleCurrencyCode] UTF8String],
               [[[NSLocale localeWithLocaleIdentifier:@"de_CH"] currencyCode] UTF8String],
               [[NSLocale localeWithLocaleIdentifier:@"en"] currencyCode] ? "a code" : "(nil)");
        printf("  keyword: %s\n",
               [[[NSLocale localeWithLocaleIdentifier:@"en_US@currency=EUR"] currencyCode] UTF8String]);

        printf("reading\n");
        NSNumberFormatter *dec = styled(NSNumberFormatterDecimalStyle);
        printf("  decimal\n");
        NSString *texts[] = {@"1,234.5", @"1234.5", @"-42", @"12abc", @" 7", @"1.5E3", @"", @"1,23", @".5"};
        for (size_t i = 0; i < sizeof texts / sizeof texts[0]; i++)
            reads(dec, texts[i]);
        [dec setLenient:YES];
        printf("  decimal, lenient\n");
        reads(dec, @" 7 ");
        reads(dec, @"$12");
        NSNumberFormatter *cur = styled(NSNumberFormatterCurrencyStyle);
        printf("  currency\n");
        reads(cur, @"$1,234.57");
        reads(cur, @"-$3.10");
        reads(cur, @"1234.57");
        [cur setLenient:YES];
        printf("  currency, lenient\n");
        reads(cur, @"1234.57");
        NSNumberFormatter *pct = styled(NSNumberFormatterPercentStyle);
        printf("  percent\n");
        reads(pct, @"25%");
        reads(pct, @"12.5%");
        reads(pct, @"25");
        /* An old (Mac OS X 10.0 style) formatter keeps % as it is: VLC's
         * opacity field shows 100 as "100%" (freemac 1.238) */
        NSNumberFormatter *old = [[NSNumberFormatter alloc] init];
        [old setFormatterBehavior:NSNumberFormatterBehavior10_0];
        [old setPositiveFormat:@"0%"];
        printf("  10.0 style percent: %s\n", [[old stringFromNumber:[NSNumber numberWithInt:100]] UTF8String]);
        reads(old, @"40%");
        NSNumberFormatter *acc = styled(NSNumberFormatterCurrencyAccountingStyle);
        printf("  accounting\n");
        reads(acc, @"($5.00)");
        NSNumberFormatter *lim = styled(NSNumberFormatterDecimalStyle);
        [lim setMinimum:[NSNumber numberWithInt:0]];
        [lim setMaximum:[NSNumber numberWithInt:100]];
        [lim setAllowsFloats:NO];
        printf("  integers from 0 to 100\n");
        reads(lim, @"50");
        reads(lim, @"150");
        reads(lim, @"5.5");
        NSNumberFormatter *spec = styled(NSNumberFormatterDecimalStyle);
        printf("  symbols\n");
        reads(spec, @"NaN");
        reads(spec, @"-∞");
        id obj = nil;
        NSError *err = nil;
        BOOL ok = [spec getObjectValue:&obj forString:@"nope" range:NULL error:&err];
        printf("  error: %s, %s %ld \"%s\"\n", ok ? "yes" : "no", [[err domain] UTF8String], (long)[err code],
               [[err localizedDescription] UTF8String]);
        NSRange part = NSMakeRange(4, 3);
        ok = [spec getObjectValue:&obj forString:@"abc 123 def" range:&part error:&err];
        printf("  a range: %s %s\n", ok ? "yes" : "no", [[obj description] UTF8String]);

        printf("copies\n");
        NSNumberFormatter *orig = styled(NSNumberFormatterCurrencyStyle);
        [orig setCurrencyCode:@"EUR"];
        NSNumberFormatter *copy = [[orig copy] autorelease];
        [orig setCurrencyCode:@"USD"];
        printf("  %s, %s\n", [[copy stringFromNumber:one] UTF8String], [[orig stringFromNumber:one] UTF8String]);

        printf("byte counts\n");
        long long sizes[] = {0, 1, 999, 1000, 1023, 1024, 1536, 999999, 1234567, 1500000000, 123456789012345LL,
                             -2048};
        const struct {
            const char *name;
            NSByteCountFormatterCountStyle style;
        } counts[] = {{"file", NSByteCountFormatterCountStyleFile},
                      {"memory", NSByteCountFormatterCountStyleMemory},
                      {"decimal", NSByteCountFormatterCountStyleDecimal},
                      {"binary", NSByteCountFormatterCountStyleBinary}};
        for (size_t i = 0; i < sizeof counts / sizeof counts[0]; i++) {
            printf("  %s:", counts[i].name);
            for (size_t j = 0; j < sizeof sizes / sizeof sizes[0]; j++)
                printf("%s %s", j ? "," : "",
                       [[NSByteCountFormatter stringFromByteCount:sizes[j] countStyle:counts[i].style] UTF8String]);
            printf("\n");
        }
        NSByteCountFormatter *bc = [[[NSByteCountFormatter alloc] init] autorelease];
        [bc setAllowedUnits:NSByteCountFormatterUseMB];
        printf("  only MB: %s, %s\n", [[bc stringFromByteCount:1234567] UTF8String],
               [[bc stringFromByteCount:5000] UTF8String]);
        [bc setAllowedUnits:NSByteCountFormatterUseDefault];
        [bc setIncludesActualByteCount:YES];
        printf("  with the byte count: %s\n", [[bc stringFromByteCount:1234567] UTF8String]);
        [bc setIncludesActualByteCount:NO];
        [bc setIncludesUnit:NO];
        printf("  without the unit: %s\n", [[bc stringFromByteCount:1234567] UTF8String]);
        [bc setIncludesUnit:YES];
        [bc setIncludesCount:NO];
        printf("  without the count: %s\n", [[bc stringFromByteCount:1234567] UTF8String]);
        [bc setIncludesCount:YES];
        [bc setAllowsNonnumericFormatting:NO];
        printf("  zero, numeric: %s\n", [[bc stringFromByteCount:0] UTF8String]);
        [bc setAdaptive:NO];
        printf("  not adaptive: %s, %s\n", [[bc stringFromByteCount:1234567] UTF8String],
               [[bc stringFromByteCount:2000] UTF8String]);
        [bc setAdaptive:YES];
        [bc setZeroPadsFractionDigits:YES];
        printf("  zero-padded: %s, %s\n", [[bc stringFromByteCount:2000000] UTF8String],
               [[bc stringFromByteCount:3000000000LL] UTF8String]);
    }
    return 0;
}
