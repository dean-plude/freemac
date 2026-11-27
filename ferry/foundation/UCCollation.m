/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * CoreServices' collator (freemac 1.232, Ferry 0.56.0), written from
 * Apple's public documentation of UnicodeUtilities: UCCreateCollator,
 * UCCompareText and collation keys. Qt's QCollator sorts with it on a Mac,
 * and so OBS sorts its scene and source lists.
 *
 * Ferry's collator knows no locale's own rules. It compares letters before
 * case, so "apple" < "Banana" < "cherry"; puts punctuation and spaces
 * first when they count and leaves them to break ties when they don't;
 * puts digits before letters; and, with kUCCollateDigitsAsNumberMask,
 * reads a run of digits as one number, so "file2" < "file10". A text's key
 * is a list of such weights, so comparing two keys orders their texts as
 * UCCompareText does.
 */
#include <CoreServices/CoreServices.h>
#include <stdlib.h>
#include <string.h>
#include <wctype.h>

struct OpaqueCollatorRef {
    UCCollateOptions options;
};

/* Every locale is served the same way, so any name gives the one locale. */
static struct OpaqueLocaleRef { int unused; } the_locale;

OSStatus LocaleRefFromLocaleString(const char *localeString, LocaleRef *localeRef)
{
    if (!localeRef)
        return paramErr;
    *localeRef = localeString ? &the_locale : NULL;
    return localeString ? noErr : paramErr;
}

OSStatus UCCreateCollator(LocaleRef locale, LocaleOperationVariant opVariant, UCCollateOptions options,
                          CollatorRef *collatorRef)
{
    (void)locale;
    (void)opVariant;
    if (!collatorRef)
        return paramErr;
    CollatorRef c = calloc(1, sizeof *c);
    if (!c)
        return memFullErr;
    c->options = options;
    *collatorRef = c;
    return noErr;
}

OSStatus UCDisposeCollator(CollatorRef *collatorRef)
{
    if (!collatorRef)
        return paramErr;
    free(*collatorRef);
    *collatorRef = NULL;
    return noErr;
}

/* Weights: 0 ends a level, punctuation and spaces from 0x1000, digits from
 * 0x20000, letters and the rest from 0x30000. */
enum { W_PUNCT = 0x1000, W_DIGIT = 0x20000, W_NUMBER = 0x21000, W_LETTER = 0x30000 };

static int is_digit(UniChar c) { return c >= '0' && c <= '9'; }
static int is_punct(UniChar c) { return c < 0x80 ? !iswalnum(c) : iswspace(c) || iswpunct(c); }

/* Writes the key into out when it fits and gives its length either way. */
static ItemCount make_key(UCCollateOptions o, const UniChar *t, UniCharCount n, UCCollationValue *out,
                          ItemCount max)
{
    ItemCount len = 0;
#define PUT(v) do { if (len < max && out) out[len] = (v); len++; } while (0)
    int numbers = (o & kUCCollateDigitsAsNumberMask) != 0;
    int punct_counts = (o & kUCCollatePunctuationSignificantMask) != 0;
    /* the first level: what the text spells */
    for (UniCharCount i = 0; i < n;) {
        UniChar c = t[i];
        if (numbers && is_digit(c)) {
            UniCharCount j = i;
            while (j < n && t[j] == '0')
                j++;
            UniCharCount k = j;
            while (k < n && is_digit(t[k]))
                k++;
            PUT(W_NUMBER + (UCCollationValue)(k - j)); /* fewer digits, smaller number */
            for (UniCharCount d = j; d < k; d++)
                PUT(W_DIGIT + (t[d] - '0'));
            i = k;
            continue;
        }
        if (is_digit(c))
            PUT(W_DIGIT + (c - '0'));
        else if (is_punct(c)) {
            if (punct_counts)
                PUT(W_PUNCT + c);
        } else
            PUT(W_LETTER + (UCCollationValue)towlower(c));
        i++;
    }
    PUT(0);
    /* the second level: case, lower before upper, unless case doesn't count */
    if (!(o & kUCCollateCaseInsensitiveMask)) {
        for (UniCharCount i = 0; i < n; i++)
            if (iswalpha(t[i]))
                PUT(iswupper(t[i]) ? 2 : 1);
        PUT(0);
    }
    /* the last level: punctuation that didn't count above, and where it stands */
    if (!punct_counts)
        for (UniCharCount i = 0; i < n; i++)
            if (!is_digit(t[i]) && is_punct(t[i])) {
                PUT(W_PUNCT + t[i]);
                PUT((UCCollationValue)i + 1);
            }
#undef PUT
    return len;
}

static void compare_keys(const UCCollationValue *a, ItemCount na, const UCCollationValue *b, ItemCount nb,
                         Boolean *equivalent, SInt32 *order)
{
    ItemCount n = na < nb ? na : nb;
    SInt32 r = 0;
    for (ItemCount i = 0; i < n && !r; i++)
        if (a[i] != b[i])
            r = a[i] < b[i] ? -1 : 1;
    if (!r && na != nb)
        r = na < nb ? -1 : 1;
    if (equivalent)
        *equivalent = r == 0;
    if (order)
        *order = r;
}

OSStatus UCGetCollationKey(CollatorRef collatorRef, const UniChar *textPtr, UniCharCount textLength,
                           ItemCount maxKeySize, ItemCount *actualKeySize, UCCollationValue collationKey[])
{
    if (!collatorRef || (!textPtr && textLength) || !actualKeySize)
        return paramErr;
    ItemCount len = make_key(collatorRef->options, textPtr, textLength, collationKey, maxKeySize);
    *actualKeySize = len;
    return len > maxKeySize ? kUCOutputBufferTooSmall : noErr;
}

OSStatus UCCompareText(CollatorRef collatorRef, const UniChar *text1Ptr, UniCharCount text1Length,
                       const UniChar *text2Ptr, UniCharCount text2Length, Boolean *equivalent, SInt32 *order)
{
    if (!collatorRef || (!text1Ptr && text1Length) || (!text2Ptr && text2Length))
        return paramErr;
    UCCollateOptions o = collatorRef->options;
    ItemCount n1 = make_key(o, text1Ptr, text1Length, NULL, 0);
    ItemCount n2 = make_key(o, text2Ptr, text2Length, NULL, 0);
    UCCollationValue *k1 = malloc((n1 + n2) * sizeof *k1);
    if (!k1)
        return memFullErr;
    UCCollationValue *k2 = k1 + n1;
    make_key(o, text1Ptr, text1Length, k1, n1);
    make_key(o, text2Ptr, text2Length, k2, n2);
    compare_keys(k1, n1, k2, n2, equivalent, order);
    free(k1);
    return noErr;
}

/* Comparing with the default locale's collator, or with none: Ferry's one
 * collator serves both (GLib's g_utf8_collate on a Mac; darktable) */
OSStatus UCCompareTextDefault(UCCollateOptions options, const UniChar *text1Ptr, UniCharCount text1Length,
                              const UniChar *text2Ptr, UniCharCount text2Length, Boolean *equivalent,
                              SInt32 *order)
{
    struct OpaqueCollatorRef c = {options};
    return UCCompareText(&c, text1Ptr, text1Length, text2Ptr, text2Length, equivalent, order);
}

OSStatus UCCompareTextNoLocale(UCCollateOptions options, const UniChar *text1Ptr, UniCharCount text1Length,
                               const UniChar *text2Ptr, UniCharCount text2Length, Boolean *equivalent,
                               SInt32 *order)
{
    return UCCompareTextDefault(options, text1Ptr, text1Length, text2Ptr, text2Length, equivalent, order);
}

OSStatus UCCompareCollationKeys(const UCCollationValue *key1Ptr, ItemCount key1Length,
                                const UCCollationValue *key2Ptr, ItemCount key2Length, Boolean *equivalent,
                                SInt32 *order)
{
    if ((!key1Ptr && key1Length) || (!key2Ptr && key2Length))
        return paramErr;
    compare_keys(key1Ptr, key1Length, key2Ptr, key2Length, equivalent, order);
    return noErr;
}
