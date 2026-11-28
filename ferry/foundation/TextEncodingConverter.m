/* SPDX-License-Identifier: GPL-3.0-or-later
 * CoreServices' text encodings and Text Encoding Converter, and a locale's
 * name in parts (freemac 1.NEXT), written from Apple's public documentation
 * of TextCommon, TextEncodingConverter and LocaleRefGetPartString. Vim
 * uses them to turn the decomposed UTF-8 of file names into composed UTF-8
 * and UTF-16 into UTF-8, and to learn the user's language.
 *
 * A converter goes through CFString: the input becomes a string, which is
 * normalized when the output is a Unicode variant that asks for it
 * (composed or decomposed) and written out in the output encoding. A text
 * encoding below the Unicode ones is the same number as a CFString
 * encoding. Our own code; no Apple code was used. */
#import "FInternal.h"
#include <CoreServices/CoreServices.h>
#include <stdlib.h>
#include <string.h>

struct OpaqueTECObjectRef {
    TextEncoding in, out;
};

TextEncoding CreateTextEncoding(TextEncodingBase base, TextEncodingVariant variant, TextEncodingFormat format)
{
    return (base & 0xffff) | ((variant & 0x3ff) << 16) | ((format & 0x3f) << 26);
}
TextEncodingBase GetTextEncodingBase(TextEncoding e) { return e & 0xffff; }
TextEncodingVariant GetTextEncodingVariant(TextEncoding e) { return (e >> 16) & 0x3ff; }
TextEncodingFormat GetTextEncodingFormat(TextEncoding e) { return (e >> 26) & 0x3f; }

static BOOL is_unicode(TextEncoding e)
{
    TextEncodingBase b = GetTextEncodingBase(e);
    return b >= 0x100 && b <= 0x10f;
}

/* The CFString encoding of a text encoding; kCFStringEncodingInvalidId when there is none. */
static CFStringEncoding cf_encoding(TextEncoding e)
{
    if (!is_unicode(e))
        return GetTextEncodingBase(e);
    switch (GetTextEncodingFormat(e)) {
    case kUnicode16BitFormat:
        return kCFStringEncodingUTF16LE;
    case kUnicodeUTF8Format:
        return kCFStringEncodingUTF8;
    case kUnicode32BitFormat:
        return kCFStringEncodingUTF32LE;
    default:
        return kCFStringEncodingInvalidId;
    }
}

OSStatus TECCreateConverter(TECObjectRef *conv, TextEncoding in, TextEncoding out)
{
    if (!conv)
        return paramErr;
    *conv = NULL;
    if (cf_encoding(in) == kCFStringEncodingInvalidId || cf_encoding(out) == kCFStringEncodingInvalidId ||
        !CFStringIsEncodingAvailable(cf_encoding(in)) || !CFStringIsEncodingAvailable(cf_encoding(out)))
        return kTECNoConversionPathErr;
    struct OpaqueTECObjectRef *c = calloc(1, sizeof *c);
    if (!c)
        return memFullErr;
    c->in = in;
    c->out = out;
    *conv = c;
    return noErr;
}

OSStatus TECDisposeConverter(TECObjectRef conv)
{
    free(conv);
    return noErr;
}

OSStatus TECClearConverterContextInfo(TECObjectRef conv) { return conv ? noErr : paramErr; }

OSStatus TECConvertText(TECObjectRef conv, ConstTextPtr in, ByteCount inLen, ByteCount *inUsed, TextPtr out,
                        ByteCount outLen, ByteCount *outUsed)
{
    if (inUsed)
        *inUsed = 0;
    if (outUsed)
        *outUsed = 0;
    if (!conv || (!in && inLen) || (!out && outLen))
        return paramErr;
    if (!inLen)
        return noErr;
    CFStringRef s = CFStringCreateWithBytes(NULL, in, (CFIndex)inLen, cf_encoding(conv->in), false);
    if (!s)
        return kTextUnsupportedEncodingErr;
    CFMutableStringRef m = CFStringCreateMutableCopy(NULL, 0, s);
    CFRelease(s);
    if (is_unicode(conv->out)) {
        switch (GetTextEncodingVariant(conv->out)) {
        case kUnicodeCanonicalCompVariant:
        case kUnicodeHFSPlusCompVariant:
            CFStringNormalize(m, kCFStringNormalizationFormC);
            break;
        case kUnicodeCanonicalDecompVariant:
        case kUnicodeHFSPlusDecompVariant:
            CFStringNormalize(m, kCFStringNormalizationFormD);
            break;
        }
    }
    CFIndex length = CFStringGetLength(m), used = 0;
    CFIndex done = CFStringGetBytes(m, CFRangeMake(0, length), cf_encoding(conv->out), '?', false, out,
                                    (CFIndex)outLen, &used);
    OSStatus status = noErr;
    ByteCount taken = inLen;
    if (done < length) {
        /* what fit came from this much of the input */
        CFIndex back = 0;
        CFStringGetBytes(m, CFRangeMake(0, done), cf_encoding(conv->in), '?', false, NULL, 0, &back);
        taken = (ByteCount)back < inLen ? (ByteCount)back : inLen;
        status = kTECOutputBufferFullStatus;
    }
    CFRelease(m);
    if (inUsed)
        *inUsed = taken;
    if (outUsed)
        *outUsed = (ByteCount)used;
    return status;
}

/* A converter keeps nothing back between calls, so there is nothing to flush. */
OSStatus TECFlushText(TECObjectRef conv, TextPtr out, ByteCount outLen, ByteCount *outUsed)
{
    if (outUsed)
        *outUsed = 0;
    return conv ? noErr : paramErr;
}

OSStatus LocaleRefGetPartString(LocaleRef ref, LocalePartMask mask, ByteCount max, char *buf)
{
    if (!buf || !max)
        return paramErr;
    buf[0] = 0;
    NSLocale *l = [NSLocale currentLocale];
    NSString *lang = [l objectForKey:NSLocaleLanguageCode], *script = [l objectForKey:NSLocaleScriptCode];
    NSString *region = [l objectForKey:NSLocaleCountryCode], *variant = [l objectForKey:NSLocaleVariantCode];
    NSMutableString *s = [NSMutableString string];
    if ((mask & kLocaleLanguageMask) && [lang length])
        [s appendString:lang];
    if ((mask & kLocaleScriptMask) && [script length])
        [s appendFormat:@"%@%@", [s length] ? @"_" : @"", script];
    if ((mask & kLocaleRegionMask) && [region length])
        [s appendFormat:@"%@%@", [s length] ? @"_" : @"", region];
    if ((mask & kLocaleRegionVariantMask) && [variant length])
        [s appendFormat:@"%@%@", [s length] ? @"_" : @"", variant];
    const char *u = [s UTF8String];
    size_t n = strlen(u);
    if (n >= max)
        n = max - 1;
    memcpy(buf, u, n);
    buf[n] = 0;
    return noErr;
}
