/* SPDX-License-Identifier: GPL-3.0-or-later
 * String encodings (freemac 1.219, Ferry 0.43.0): the table of the
 * encodings NSString and CFString know, the conversions between a string's
 * UTF-16 and bytes in each of them, and the NSString and CFString calls
 * built on those. Written for freemac from Apple's public documentation of
 * NSString, CFString and CFStringEncodingExt.
 *
 * ASCII, ISO Latin 1, UTF-8, UTF-16, UTF-32 and the non-lossy ASCII form are
 * converted here; the rest go through this system's ICU converters (reached
 * the way NSRegularExpression reaches ICU), and an encoding whose converter
 * ICU lacks is reported as unavailable. Decoding is strict: bytes that aren't
 * in the encoding give nil, as on a Mac. Only -initWithUTF8String: and the
 * other UTF-8 shortcuts stay lenient, putting U+FFFD for a bad byte, as
 * Ferry always has. */
#import "FInternal.h"

void *ferry_twin_symbol(const char *install_name, const char *name);

/* ---- ICU's converters ---------------------------------------------------------------- */

typedef int UErrorCode;
#define U_FAILURE(e) ((e) > 0)
#define U_BUFFER_OVERFLOW_ERROR 15
typedef struct UConverter UConverter;
typedef void (*UConvCallback)(void);

static struct {
    BOOL tried, ok;
    UConverter *(*open)(const char *name, UErrorCode *err);
    void (*close)(UConverter *cnv);
    int32_t (*toUChars)(UConverter *cnv, unichar *dest, int32_t cap, const char *src, int32_t len, UErrorCode *err);
    int32_t (*fromUChars)(UConverter *cnv, char *dest, int32_t cap, const unichar *src, int32_t len, UErrorCode *err);
    void (*setToUCallBack)(UConverter *cnv, UConvCallback action, const void *ctx, UConvCallback *old,
                           const void **oldCtx, UErrorCode *err);
    void (*setFromUCallBack)(UConverter *cnv, UConvCallback action, const void *ctx, UConvCallback *old,
                             const void **oldCtx, UErrorCode *err);
    void (*setSubstChars)(UConverter *cnv, const char *sub, int8_t len, UErrorCode *err);
    UConvCallback toUStop, fromUStop, fromUSubstitute;
} icu;

static BOOL load_icu(void)
{
    if (icu.tried)
        return icu.ok;
    icu.tried = YES;
    const char *lib = "/usr/lib/libicucore.A.dylib";
#define LOAD(field, name) *(void **)&icu.field = ferry_twin_symbol(lib, name)
    LOAD(open, "ucnv_open");
    LOAD(close, "ucnv_close");
    LOAD(toUChars, "ucnv_toUChars");
    LOAD(fromUChars, "ucnv_fromUChars");
    LOAD(setToUCallBack, "ucnv_setToUCallBack");
    LOAD(setFromUCallBack, "ucnv_setFromUCallBack");
    LOAD(setSubstChars, "ucnv_setSubstChars");
    LOAD(toUStop, "UCNV_TO_U_CALLBACK_STOP");
    LOAD(fromUStop, "UCNV_FROM_U_CALLBACK_STOP");
    LOAD(fromUSubstitute, "UCNV_FROM_U_CALLBACK_SUBSTITUTE");
#undef LOAD
    icu.ok = icu.open && icu.close && icu.toUChars && icu.fromUChars && icu.setToUCallBack && icu.setFromUCallBack &&
             icu.setSubstChars && icu.toUStop && icu.fromUStop && icu.fromUSubstitute;
    return icu.ok;
}

/* ---- the table ----------------------------------------------------------------------- */

enum { BUILTIN_ASCII = 1, BUILTIN_LATIN1, BUILTIN_UTF8, BUILTIN_UTF16, BUILTIN_UTF16BE, BUILTIN_UTF16LE,
       BUILTIN_UTF32, BUILTIN_UTF32BE, BUILTIN_UTF32LE, BUILTIN_NONLOSSY };

typedef struct {
    CFStringEncoding cf;
    int builtin;          /* converted here, or 0 to go through ICU's converter named icu */
    const char *icu;
    const char *iana;     /* the IANA character set name, or NULL */
    const char *name;     /* the name a person reads, as in an encoding menu */
    UInt32 codepage;      /* the Windows code page, or 0 */
} FEncoding;

static const FEncoding encodings[] = {
    {kCFStringEncodingASCII, BUILTIN_ASCII, NULL, "us-ascii", "Western (ASCII)", 20127},
    {kCFStringEncodingUTF8, BUILTIN_UTF8, NULL, "utf-8", "Unicode (UTF-8)", 65001},
    {kCFStringEncodingISOLatin1, BUILTIN_LATIN1, NULL, "iso-8859-1", "Western (ISO Latin 1)", 28591},
    {kCFStringEncodingMacRoman, 0, "macintosh", "macintosh", "Western (Mac OS Roman)", 10000},
    {kCFStringEncodingWindowsLatin1, 0, "windows-1252", "windows-1252", "Western (Windows Latin 1)", 1252},
    {kCFStringEncodingUTF16, BUILTIN_UTF16, NULL, "utf-16", "Unicode (UTF-16)", 1200},
    {kCFStringEncodingUTF16BE, BUILTIN_UTF16BE, NULL, "utf-16be", "Unicode (UTF-16BE)", 1201},
    {kCFStringEncodingUTF16LE, BUILTIN_UTF16LE, NULL, "utf-16le", "Unicode (UTF-16LE)", 1200},
    {kCFStringEncodingUTF32, BUILTIN_UTF32, NULL, "utf-32", "Unicode (UTF-32)", 12000},
    {kCFStringEncodingUTF32BE, BUILTIN_UTF32BE, NULL, "utf-32be", "Unicode (UTF-32BE)", 12001},
    {kCFStringEncodingUTF32LE, BUILTIN_UTF32LE, NULL, "utf-32le", "Unicode (UTF-32LE)", 12000},
    {kCFStringEncodingNonLossyASCII, BUILTIN_NONLOSSY, NULL, NULL, "Non-lossy ASCII", 0},
    {kCFStringEncodingMacCentralEurRoman, 0, "x-mac-centraleurroman", "x-mac-ce", "Central European (Mac OS)", 10029},
    {kCFStringEncodingMacCyrillic, 0, "x-mac-cyrillic", "x-mac-cyrillic", "Cyrillic (Mac OS)", 10007},
    {kCFStringEncodingMacGreek, 0, "x-mac-greek", "x-mac-greek", "Greek (Mac OS)", 10006},
    {kCFStringEncodingMacTurkish, 0, "x-mac-turkish", "x-mac-turkish", "Turkish (Mac OS)", 10081},
    {kCFStringEncodingISOLatin2, 0, "iso-8859-2", "iso-8859-2", "Central European (ISO Latin 2)", 28592},
    {kCFStringEncodingISOLatin3, 0, "iso-8859-3", "iso-8859-3", "Western (ISO Latin 3)", 28593},
    {kCFStringEncodingISOLatin4, 0, "iso-8859-4", "iso-8859-4", "Central European (ISO Latin 4)", 28594},
    {kCFStringEncodingISOLatinCyrillic, 0, "iso-8859-5", "iso-8859-5", "Cyrillic (ISO 8859-5)", 28595},
    {kCFStringEncodingISOLatinArabic, 0, "iso-8859-6", "iso-8859-6", "Arabic (ISO 8859-6)", 28596},
    {kCFStringEncodingISOLatinGreek, 0, "iso-8859-7", "iso-8859-7", "Greek (ISO 8859-7)", 28597},
    {kCFStringEncodingISOLatinHebrew, 0, "iso-8859-8", "iso-8859-8", "Hebrew (ISO 8859-8)", 28598},
    {kCFStringEncodingISOLatin5, 0, "iso-8859-9", "iso-8859-9", "Turkish (ISO Latin 5)", 28599},
    {kCFStringEncodingISOLatin6, 0, "iso-8859-10", "iso-8859-10", "Nordic (ISO Latin 6)", 0},
    {kCFStringEncodingISOLatinThai, 0, "iso-8859-11", "iso-8859-11", "Thai (ISO 8859-11)", 0},
    {kCFStringEncodingISOLatin7, 0, "iso-8859-13", "iso-8859-13", "Baltic (ISO Latin 7)", 28603},
    {kCFStringEncodingISOLatin8, 0, "iso-8859-14", "iso-8859-14", "Celtic (ISO Latin 8)", 0},
    {kCFStringEncodingISOLatin9, 0, "iso-8859-15", "iso-8859-15", "Western (ISO Latin 9)", 28605},
    {kCFStringEncodingISOLatin10, 0, "iso-8859-16", "iso-8859-16", "Romanian (ISO Latin 10)", 0},
    {kCFStringEncodingDOSLatinUS, 0, "ibm-437", "ibm437", "Latin-US (DOS)", 437},
    {kCFStringEncodingDOSGreek, 0, "ibm-737", "ibm737", "Greek (DOS)", 737},
    {kCFStringEncodingDOSBalticRim, 0, "ibm-775", "ibm775", "Baltic (DOS)", 775},
    {kCFStringEncodingDOSLatin1, 0, "ibm-850", "ibm850", "Western (DOS Latin 1)", 850},
    {kCFStringEncodingDOSGreek1, 0, "ibm-851", "ibm851", "Greek (DOS Greek 1)", 851},
    {kCFStringEncodingDOSLatin2, 0, "ibm-852", "ibm852", "Central European (DOS Latin 2)", 852},
    {kCFStringEncodingDOSCyrillic, 0, "ibm-855", "ibm855", "Cyrillic (DOS)", 855},
    {kCFStringEncodingDOSTurkish, 0, "ibm-857", "ibm857", "Turkish (DOS)", 857},
    {kCFStringEncodingDOSPortuguese, 0, "ibm-860", "ibm860", "Portuguese (DOS)", 860},
    {kCFStringEncodingDOSIcelandic, 0, "ibm-861", "ibm861", "Icelandic (DOS)", 861},
    {kCFStringEncodingDOSHebrew, 0, "ibm-862", "ibm862", "Hebrew (DOS)", 862},
    {kCFStringEncodingDOSCanadianFrench, 0, "ibm-863", "ibm863", "Canadian French (DOS)", 863},
    {kCFStringEncodingDOSArabic, 0, "ibm-864", "ibm864", "Arabic (DOS)", 864},
    {kCFStringEncodingDOSNordic, 0, "ibm-865", "ibm865", "Nordic (DOS)", 865},
    {kCFStringEncodingDOSRussian, 0, "ibm-866", "ibm866", "Russian (DOS)", 866},
    {kCFStringEncodingDOSGreek2, 0, "ibm-869", "ibm869", "Greek (DOS Greek 2)", 869},
    {kCFStringEncodingDOSThai, 0, "windows-874", "windows-874", "Thai (Windows, DOS)", 874},
    {kCFStringEncodingDOSJapanese, 0, "windows-932", "windows-31j", "Japanese (Windows, DOS)", 932},
    {kCFStringEncodingDOSChineseSimplif, 0, "windows-936", "gbk", "Simplified Chinese (Windows, DOS)", 936},
    {kCFStringEncodingDOSKorean, 0, "windows-949", "ks_c_5601-1987", "Korean (Windows, DOS)", 949},
    {kCFStringEncodingDOSChineseTrad, 0, "windows-950", "big5", "Traditional Chinese (Windows, DOS)", 950},
    {kCFStringEncodingWindowsLatin2, 0, "windows-1250", "windows-1250", "Central European (Windows Latin 2)", 1250},
    {kCFStringEncodingWindowsCyrillic, 0, "windows-1251", "windows-1251", "Cyrillic (Windows)", 1251},
    {kCFStringEncodingWindowsGreek, 0, "windows-1253", "windows-1253", "Greek (Windows)", 1253},
    {kCFStringEncodingWindowsLatin5, 0, "windows-1254", "windows-1254", "Turkish (Windows Latin 5)", 1254},
    {kCFStringEncodingWindowsHebrew, 0, "windows-1255", "windows-1255", "Hebrew (Windows)", 1255},
    {kCFStringEncodingWindowsArabic, 0, "windows-1256", "windows-1256", "Arabic (Windows)", 1256},
    {kCFStringEncodingWindowsBalticRim, 0, "windows-1257", "windows-1257", "Baltic (Windows)", 1257},
    {kCFStringEncodingWindowsVietnamese, 0, "windows-1258", "windows-1258", "Vietnamese (Windows)", 1258},
    {kCFStringEncodingGBK_95, 0, "GBK", "gbk", "Chinese (GBK)", 0},
    {kCFStringEncodingGB_18030_2000, 0, "GB18030", "gb18030", "Chinese (GB 18030)", 54936},
    {kCFStringEncodingISO_2022_JP, 0, "ISO-2022-JP", "iso-2022-jp", "Japanese (ISO 2022-JP)", 50220},
    {kCFStringEncodingISO_2022_KR, 0, "ISO-2022-KR", "iso-2022-kr", "Korean (ISO 2022-KR)", 50225},
    {kCFStringEncodingEUC_JP, 0, "EUC-JP", "euc-jp", "Japanese (EUC)", 51932},
    {kCFStringEncodingEUC_CN, 0, "GB2312", "gb2312", "Simplified Chinese (GB 2312)", 51936},
    {kCFStringEncodingEUC_TW, 0, "EUC-TW", "euc-tw", "Traditional Chinese (EUC)", 0},
    {kCFStringEncodingEUC_KR, 0, "EUC-KR", "euc-kr", "Korean (EUC)", 51949},
    {kCFStringEncodingShiftJIS, 0, "Shift_JIS", "shift_jis", "Japanese (Shift JIS)", 0},
    {kCFStringEncodingKOI8_R, 0, "KOI8-R", "koi8-r", "Cyrillic (KOI8-R)", 20866},
    {kCFStringEncodingBig5, 0, "Big5", "big5", "Traditional Chinese (Big 5)", 0},
    {kCFStringEncodingHZ_GB_2312, 0, "HZ-GB-2312", "hz-gb-2312", "Simplified Chinese (HZ GB 2312)", 52936},
    {kCFStringEncodingBig5_HKSCS_1999, 0, "Big5-HKSCS", "big5-hkscs", "Traditional Chinese (Big 5 HKSCS)", 0},
    {kCFStringEncodingKOI8_U, 0, "KOI8-U", "koi8-u", "Ukrainian (KOI8-U)", 21866},
    {kCFStringEncodingEBCDIC_CP037, 0, "ibm-37", "ibm037", "Western (EBCDIC Latin 1)", 37},
};
#define N_ENCODINGS (sizeof encodings / sizeof encodings[0])

static const FEncoding *find_cf(CFStringEncoding cf)
{
    for (size_t i = 0; i < N_ENCODINGS; i++)
        if (encodings[i].cf == cf)
            return &encodings[i];
    return NULL;
}

/* The NSStringEncoding values that aren't simply 0x80000000 and the
 * CFStringEncoding (the documented correspondence). */
static const struct { NSStringEncoding ns; CFStringEncoding cf; } ns_cf[] = {
    {NSASCIIStringEncoding, kCFStringEncodingASCII},
    {NSNEXTSTEPStringEncoding, kCFStringEncodingNextStepLatin},
    {NSJapaneseEUCStringEncoding, kCFStringEncodingEUC_JP},
    {NSUTF8StringEncoding, kCFStringEncodingUTF8},
    {NSISOLatin1StringEncoding, kCFStringEncodingISOLatin1},
    {NSSymbolStringEncoding, kCFStringEncodingMacSymbol},
    {NSNonLossyASCIIStringEncoding, kCFStringEncodingNonLossyASCII},
    {NSShiftJISStringEncoding, kCFStringEncodingDOSJapanese},
    {NSISOLatin2StringEncoding, kCFStringEncodingISOLatin2},
    {NSUnicodeStringEncoding, kCFStringEncodingUnicode},
    {NSWindowsCP1251StringEncoding, kCFStringEncodingWindowsCyrillic},
    {NSWindowsCP1252StringEncoding, kCFStringEncodingWindowsLatin1},
    {NSWindowsCP1253StringEncoding, kCFStringEncodingWindowsGreek},
    {NSWindowsCP1254StringEncoding, kCFStringEncodingWindowsLatin5},
    {NSWindowsCP1250StringEncoding, kCFStringEncodingWindowsLatin2},
    {NSISO2022JPStringEncoding, kCFStringEncodingISO_2022_JP},
    {NSMacOSRomanStringEncoding, kCFStringEncodingMacRoman},
};

unsigned long CFStringConvertEncodingToNSStringEncoding(CFStringEncoding cf)
{
    if (cf == kCFStringEncodingInvalidId)
        return kCFStringEncodingInvalidId;
    for (size_t i = 0; i < sizeof ns_cf / sizeof ns_cf[0]; i++)
        if (ns_cf[i].cf == cf)
            return ns_cf[i].ns;
    return 0x80000000UL | cf;
}

CFStringEncoding CFStringConvertNSStringEncodingToEncoding(unsigned long ns)
{
    for (size_t i = 0; i < sizeof ns_cf / sizeof ns_cf[0]; i++)
        if (ns_cf[i].ns == ns)
            return ns_cf[i].cf;
    if ((ns & 0x80000000UL) && ns <= 0xffffffffUL)
        return (CFStringEncoding)(ns & 0x7fffffffUL);
    return kCFStringEncodingInvalidId;
}

/* Whether the converter of an ICU encoding opens here (remembered). */
static BOOL available(const FEncoding *e)
{
    if (!e)
        return NO;
    if (e->builtin)
        return YES;
    static signed char known[N_ENCODINGS];
    size_t i = (size_t)(e - encodings);
    if (!known[i]) {
        known[i] = -1;
        if (load_icu()) {
            UErrorCode err = 0;
            UConverter *c = icu.open(e->icu, &err);
            if (c && !U_FAILURE(err))
                known[i] = 1;
            if (c)
                icu.close(c);
        }
    }
    return known[i] == 1;
}

/* ---- converting ---------------------------------------------------------------------- */

static void put16(unsigned char *p, uint32_t v, BOOL big)
{
    p[big ? 0 : 1] = (unsigned char)(v >> 8);
    p[big ? 1 : 0] = (unsigned char)v;
}
static void put32(unsigned char *p, uint32_t v, BOOL big)
{
    for (int i = 0; i < 4; i++)
        p[big ? 3 - i : i] = (unsigned char)(v >> (8 * i));
}

/* Characters from bytes: a malloc'd buffer, or NULL when the bytes aren't
 * text in the encoding. */
static unichar *decode(const void *bytes, NSUInteger len, const FEncoding *e, NSUInteger *outLen)
{
    const unsigned char *b = bytes;
    unichar *out = NULL;
    NSUInteger n = 0;
    if (!available(e))
        return NULL;
    switch (e->builtin) {
    case BUILTIN_ASCII:
    case BUILTIN_LATIN1:
        out = malloc((len + 1) * sizeof(unichar));
        for (NSUInteger i = 0; i < len; i++) {
            if (e->builtin == BUILTIN_ASCII && b[i] > 0x7f) {
                free(out);
                return NULL;
            }
            out[n++] = b[i];
        }
        break;
    case BUILTIN_UTF8: {
        out = malloc((len + 1) * sizeof(unichar));
        NSUInteger i = 0;
        while (i < len) {
            uint32_t c = b[i];
            int extra = 0;
            uint32_t min = 0;
            if (c < 0x80) {
                extra = 0;
            } else if (c >= 0xc2 && c <= 0xdf) {
                extra = 1, c &= 0x1f, min = 0x80;
            } else if (c >= 0xe0 && c <= 0xef) {
                extra = 2, c &= 0x0f, min = 0x800;
            } else if (c >= 0xf0 && c <= 0xf4) {
                extra = 3, c &= 0x07, min = 0x10000;
            } else {
                free(out);
                return NULL;
            }
            if (extra && i + (NSUInteger)extra >= len) {
                free(out);
                return NULL;
            }
            for (int k = 1; k <= extra; k++) {
                if ((b[i + k] & 0xc0) != 0x80) {
                    free(out);
                    return NULL;
                }
                c = (c << 6) | (b[i + k] & 0x3f);
            }
            if (c < min || c > 0x10ffff || (c >= 0xd800 && c < 0xe000)) {
                free(out);
                return NULL;
            }
            i += 1 + extra;
            if (c >= 0x10000) {
                c -= 0x10000;
                out[n++] = (unichar)(0xd800 + (c >> 10));
                out[n++] = (unichar)(0xdc00 + (c & 0x3ff));
            } else {
                out[n++] = (unichar)c;
            }
        }
        break;
    }
    case BUILTIN_UTF16:
    case BUILTIN_UTF16BE:
    case BUILTIN_UTF16LE: {
        BOOL big = e->builtin == BUILTIN_UTF16BE;
        if (e->builtin == BUILTIN_UTF16) {
            /* A byte order mark says which; with none, the bytes are taken in
             * this computer's order (little-endian), as Ferry always has. */
            if (len >= 2 && b[0] == 0xfe && b[1] == 0xff)
                big = YES, b += 2, len -= 2;
            else if (len >= 2 && b[0] == 0xff && b[1] == 0xfe)
                b += 2, len -= 2;
        } else if (len % 2) {
            return NULL;
        }
        n = len / 2;
        out = malloc((n + 1) * sizeof(unichar));
        for (NSUInteger i = 0; i < n; i++)
            out[i] = big ? (unichar)((b[2 * i] << 8) | b[2 * i + 1]) : (unichar)(b[2 * i] | (b[2 * i + 1] << 8));
        break;
    }
    case BUILTIN_UTF32:
    case BUILTIN_UTF32BE:
    case BUILTIN_UTF32LE: {
        BOOL big = e->builtin == BUILTIN_UTF32BE;
        if (e->builtin == BUILTIN_UTF32) {
            if (len >= 4 && b[0] == 0 && b[1] == 0 && b[2] == 0xfe && b[3] == 0xff)
                big = YES, b += 4, len -= 4;
            else if (len >= 4 && b[0] == 0xff && b[1] == 0xfe && b[2] == 0 && b[3] == 0)
                b += 4, len -= 4;
        }
        if (len % 4)
            return NULL;
        out = malloc((len / 2 + 1) * sizeof(unichar));
        for (NSUInteger i = 0; i < len; i += 4) {
            uint32_t c = big ? ((uint32_t)b[i] << 24) | ((uint32_t)b[i + 1] << 16) | ((uint32_t)b[i + 2] << 8) | b[i + 3]
                             : ((uint32_t)b[i + 3] << 24) | ((uint32_t)b[i + 2] << 16) | ((uint32_t)b[i + 1] << 8) | b[i];
            if (c > 0x10ffff || (c >= 0xd800 && c < 0xe000)) {
                free(out);
                return NULL;
            }
            if (c >= 0x10000) {
                c -= 0x10000;
                out[n++] = (unichar)(0xd800 + (c >> 10));
                out[n++] = (unichar)(0xdc00 + (c & 0x3ff));
            } else {
                out[n++] = (unichar)c;
            }
        }
        break;
    }
    case BUILTIN_NONLOSSY:
        out = malloc((len + 1) * sizeof(unichar));
        for (NSUInteger i = 0; i < len;) {
            unsigned char c = b[i];
            if (c > 0x7f) {
                free(out);
                return NULL;
            }
            if (c != '\\') {
                out[n++] = c, i++;
            } else if (i + 1 < len && b[i + 1] == '\\') {
                out[n++] = '\\', i += 2;
            } else if (i + 5 < len + 0 && b[i + 1] == 'u' && isxdigit(b[i + 2]) && isxdigit(b[i + 3]) &&
                       isxdigit(b[i + 4]) && isxdigit(b[i + 5])) {
                char hex[5] = {(char)b[i + 2], (char)b[i + 3], (char)b[i + 4], (char)b[i + 5], 0};
                out[n++] = (unichar)strtoul(hex, NULL, 16), i += 6;
            } else if (i + 3 < len && b[i + 1] >= '0' && b[i + 1] <= '3' && b[i + 2] >= '0' && b[i + 2] <= '7' &&
                       b[i + 3] >= '0' && b[i + 3] <= '7') {
                out[n++] = (unichar)(((b[i + 1] - '0') << 6) | ((b[i + 2] - '0') << 3) | (b[i + 3] - '0')), i += 4;
            } else {
                out[n++] = '\\', i++;
            }
        }
        break;
    default: {
        UErrorCode err = 0;
        UConverter *c = icu.open(e->icu, &err);
        if (!c || U_FAILURE(err))
            return NULL;
        icu.setToUCallBack(c, icu.toUStop, NULL, NULL, NULL, &err);
        int32_t cap = (int32_t)len * 2 + 1;
        out = malloc(((NSUInteger)cap + 1) * sizeof(unichar));
        err = 0;
        int32_t got = icu.toUChars(c, out, cap, (const char *)b, (int32_t)len, &err);
        icu.close(c);
        if (U_FAILURE(err)) {
            free(out);
            return NULL;
        }
        n = (NSUInteger)got;
        break;
    }
    }
    *outLen = n;
    return out;
}

/* Bytes from characters: nil when one can't be written, unless lossByte
 * (from 1 to 255) stands in for it. external adds the byte order mark to
 * UTF-16 and UTF-32. */
static NSData *encode(const unichar *c, NSUInteger n, const FEncoding *e, int lossByte, BOOL external)
{
    if (!available(e))
        return nil;
    NSMutableData *d;
    switch (e->builtin) {
    case BUILTIN_ASCII:
    case BUILTIN_LATIN1: {
        unichar top = e->builtin == BUILTIN_ASCII ? 0x7f : 0xff;
        d = [NSMutableData dataWithLength:n];
        unsigned char *out = [d mutableBytes];
        NSUInteger k = 0;
        for (NSUInteger i = 0; i < n; i++) {
            if (c[i] <= top)
                out[k++] = (unsigned char)c[i];
            else if (lossByte > 0) {
                out[k++] = (unsigned char)lossByte;
                if (c[i] >= 0xd800 && c[i] < 0xdc00 && i + 1 < n && c[i + 1] >= 0xdc00 && c[i + 1] < 0xe000)
                    i++;
            } else
                return nil;
        }
        [d setLength:k];
        return d;
    }
    case BUILTIN_UTF8:
        d = [NSMutableData dataWithCapacity:n * 3];
        for (NSUInteger i = 0; i < n; i++) {
            uint32_t u = c[i];
            if (u >= 0xd800 && u < 0xe000) {
                if (u < 0xdc00 && i + 1 < n && c[i + 1] >= 0xdc00 && c[i + 1] < 0xe000) {
                    u = 0x10000 + ((u - 0xd800) << 10) + (c[i + 1] - 0xdc00u);
                    i++;
                } else if (lossByte > 0) {
                    unsigned char lb = (unsigned char)lossByte;
                    [d appendBytes:&lb length:1];
                    continue;
                } else {
                    return nil;
                }
            }
            unsigned char buf[4];
            NSUInteger k;
            if (u < 0x80)
                buf[0] = (unsigned char)u, k = 1;
            else if (u < 0x800)
                buf[0] = (unsigned char)(0xc0 | (u >> 6)), buf[1] = (unsigned char)(0x80 | (u & 0x3f)), k = 2;
            else if (u < 0x10000)
                buf[0] = (unsigned char)(0xe0 | (u >> 12)), buf[1] = (unsigned char)(0x80 | ((u >> 6) & 0x3f)),
                buf[2] = (unsigned char)(0x80 | (u & 0x3f)), k = 3;
            else
                buf[0] = (unsigned char)(0xf0 | (u >> 18)), buf[1] = (unsigned char)(0x80 | ((u >> 12) & 0x3f)),
                buf[2] = (unsigned char)(0x80 | ((u >> 6) & 0x3f)), buf[3] = (unsigned char)(0x80 | (u & 0x3f)), k = 4;
            [d appendBytes:buf length:k];
        }
        return d;
    case BUILTIN_UTF16:
    case BUILTIN_UTF16BE:
    case BUILTIN_UTF16LE: {
        BOOL big = e->builtin == BUILTIN_UTF16BE, bom = external && e->builtin == BUILTIN_UTF16;
        d = [NSMutableData dataWithLength:(n + bom) * 2];
        unsigned char *out = [d mutableBytes];
        if (bom)
            put16(out, 0xfeff, big), out += 2;
        for (NSUInteger i = 0; i < n; i++)
            put16(out + 2 * i, c[i], big);
        return d;
    }
    case BUILTIN_UTF32:
    case BUILTIN_UTF32BE:
    case BUILTIN_UTF32LE: {
        BOOL big = e->builtin == BUILTIN_UTF32BE;
        d = [NSMutableData dataWithCapacity:(n + 1) * 4];
        unsigned char buf[4];
        if (external && e->builtin == BUILTIN_UTF32) {
            put32(buf, 0xfeff, big);
            [d appendBytes:buf length:4];
        }
        for (NSUInteger i = 0; i < n; i++) {
            uint32_t u = c[i];
            if (u >= 0xd800 && u < 0xe000) {
                if (u < 0xdc00 && i + 1 < n && c[i + 1] >= 0xdc00 && c[i + 1] < 0xe000)
                    u = 0x10000 + ((u - 0xd800) << 10) + (c[i + 1] - 0xdc00u), i++;
                else if (lossByte > 0)
                    u = (uint32_t)lossByte;
                else
                    return nil;
            }
            put32(buf, u, big);
            [d appendBytes:buf length:4];
        }
        return d;
    }
    case BUILTIN_NONLOSSY:
        d = [NSMutableData dataWithCapacity:n];
        for (NSUInteger i = 0; i < n; i++) {
            char buf[8];
            if (c[i] == '\\')
                strcpy(buf, "\\\\");
            else if (c[i] < 0x80)
                buf[0] = (char)c[i], buf[1] = 0;
            else if (c[i] < 0x100)
                snprintf(buf, sizeof buf, "\\%03o", c[i]);
            else
                snprintf(buf, sizeof buf, "\\u%04x", c[i]);
            [d appendBytes:buf length:strlen(buf)];
        }
        return d;
    default: {
        UErrorCode err = 0;
        UConverter *cv = icu.open(e->icu, &err);
        if (!cv || U_FAILURE(err))
            return nil;
        if (lossByte > 0) {
            char sub = (char)lossByte;
            icu.setSubstChars(cv, &sub, 1, &err);
            icu.setFromUCallBack(cv, icu.fromUSubstitute, NULL, NULL, NULL, &err);
        } else {
            icu.setFromUCallBack(cv, icu.fromUStop, NULL, NULL, NULL, &err);
        }
        err = 0;
        int32_t cap = (int32_t)n * 4 + 16;
        d = [NSMutableData dataWithLength:(NSUInteger)cap];
        int32_t got = icu.fromUChars(cv, [d mutableBytes], cap, c, (int32_t)n, &err);
        if (err == U_BUFFER_OVERFLOW_ERROR) {
            err = 0;
            cap = got + 1;
            [d setLength:(NSUInteger)cap];
            got = icu.fromUChars(cv, [d mutableBytes], cap, c, (int32_t)n, &err);
        }
        icu.close(cv);
        if (U_FAILURE(err))
            return nil;
        [d setLength:(NSUInteger)got];
        return d;
    }
    }
}

static const FEncoding *find_ns(NSStringEncoding enc) { return find_cf(CFStringConvertNSStringEncodingToEncoding(enc)); }

unichar *FDecodeBytes(const void *bytes, NSUInteger len, NSStringEncoding enc, NSUInteger *outLen)
{
    return decode(bytes, len, find_ns(enc), outLen);
}
NSData *FEncodeChars(const unichar *c, NSUInteger n, NSStringEncoding enc, int lossByte, BOOL external)
{
    return encode(c, n, find_ns(enc), lossByte, external);
}
BOOL FStringEncodingIsAvailable(NSStringEncoding enc) { return available(find_ns(enc)); }

static unichar *copy_chars(NSString *s, NSUInteger *n)
{
    *n = [s length];
    unichar *c = malloc((*n + 1) * sizeof(unichar));
    [s getCharacters:c range:NSMakeRange(0, *n)];
    return c;
}

/* ---- NSString ------------------------------------------------------------------------ */

@implementation NSString (FerryEncodings)

+ (const NSStringEncoding *)availableStringEncodings
{
    static NSStringEncoding *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = calloc(N_ENCODINGS + 1, sizeof(NSStringEncoding));
        size_t k = 0;
        for (size_t i = 0; i < N_ENCODINGS; i++)
            if (available(&encodings[i]))
                list[k++] = CFStringConvertEncodingToNSStringEncoding(encodings[i].cf);
    });
    return list;
}
+ (NSString *)localizedNameOfStringEncoding:(NSStringEncoding)enc
{
    const FEncoding *e = find_ns(enc);
    return e ? [NSString stringWithUTF8String:e->name] : @"";
}
+ (NSStringEncoding)defaultCStringEncoding { return NSUTF8StringEncoding; }
- (NSStringEncoding)fastestEncoding { return NSUnicodeStringEncoding; }
- (NSStringEncoding)smallestEncoding
{
    NSUInteger n;
    unichar *c = copy_chars(self, &n);
    unichar top = 0;
    for (NSUInteger i = 0; i < n; i++)
        if (c[i] > top)
            top = c[i];
    free(c);
    return top < 0x80 ? NSASCIIStringEncoding : top < 0x100 ? NSISOLatin1StringEncoding : NSUnicodeStringEncoding;
}
- (BOOL)canBeConvertedToEncoding:(NSStringEncoding)enc
{
    return [self dataUsingEncoding:enc allowLossyConversion:NO] != nil;
}
- (NSData *)dataUsingEncoding:(NSStringEncoding)enc { return [self dataUsingEncoding:enc allowLossyConversion:NO]; }
/* A character the encoding lacks gives nil, or '?' when a lossy
 * conversion is allowed, as on a Mac. UTF-16 data starts with a byte order
 * mark. */
- (NSData *)dataUsingEncoding:(NSStringEncoding)enc allowLossyConversion:(BOOL)lossy
{
    NSUInteger n;
    unichar *c = copy_chars(self, &n);
    NSData *d = FEncodeChars(c, n, enc, lossy ? '?' : 0, YES);
    free(c);
    return d;
}
static NSUInteger terminator_size(NSStringEncoding enc)
{
    CFStringEncoding cf = CFStringConvertNSStringEncodingToEncoding(enc);
    if (cf == kCFStringEncodingUTF16 || cf == kCFStringEncodingUTF16BE || cf == kCFStringEncodingUTF16LE)
        return 2;
    if (cf == kCFStringEncodingUTF32 || cf == kCFStringEncodingUTF32BE || cf == kCFStringEncodingUTF32LE)
        return 4;
    return 1;
}
- (const char *)cStringUsingEncoding:(NSStringEncoding)enc
{
    if (enc == NSUTF8StringEncoding)
        return [self UTF8String];
    NSUInteger n;
    unichar *c = copy_chars(self, &n);
    NSData *d = FEncodeChars(c, n, enc, 0, NO);
    free(c);
    if (!d)
        return NULL;
    NSUInteger z = terminator_size(enc);
    NSMutableData *m = [NSMutableData dataWithData:d];
    [m setLength:[d length] + z];
    return [m bytes];
}
- (BOOL)getCString:(char *)buffer maxLength:(NSUInteger)max encoding:(NSStringEncoding)enc
{
    NSUInteger n;
    unichar *c = copy_chars(self, &n);
    NSData *d = FEncodeChars(c, n, enc, 0, NO);
    free(c);
    NSUInteger z = terminator_size(enc);
    if (!d || [d length] + z > max)
        return NO;
    memcpy(buffer, [d bytes], [d length]);
    memset(buffer + [d length], 0, z);
    return YES;
}
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)enc
{
    NSUInteger n;
    unichar *c = copy_chars(self, &n);
    NSData *d = FEncodeChars(c, n, enc, 0, NO);
    free(c);
    return [d length];
}
- (NSUInteger)maximumLengthOfBytesUsingEncoding:(NSStringEncoding)enc
{
    return (NSUInteger)CFStringGetMaximumSizeForEncoding((CFIndex)[self length], CFStringConvertNSStringEncodingToEncoding(enc));
}
- (BOOL)getBytes:(void *)buffer maxLength:(NSUInteger)max usedLength:(NSUInteger *)used
        encoding:(NSStringEncoding)enc options:(NSStringEncodingConversionOptions)options range:(NSRange)range
  remainingRange:(NSRangePointer)left
{
    CFIndex usedLen = 0;
    CFIndex got = CFStringGetBytes((CFStringRef)self, CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                   CFStringConvertNSStringEncodingToEncoding(enc),
                                   (options & NSStringEncodingConversionAllowLossy) ? '?' : 0,
                                   (options & NSStringEncodingConversionExternalRepresentation) != 0, buffer,
                                   (CFIndex)max, &usedLen);
    if (used)
        *used = (NSUInteger)usedLen;
    if (left)
        *left = NSMakeRange(range.location + (NSUInteger)got, range.length - (NSUInteger)got);
    return got > 0 || range.length == 0;
}
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)len encoding:(NSStringEncoding)enc
{
    NSUInteger n = 0;
    unichar *c = FDecodeBytes(bytes, len, enc, &n);
    if (!c) {
        [self release];
        return nil;
    }
    id r = [self initWithCharacters:c length:n];
    free(c);
    return r;
}
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)len encoding:(NSStringEncoding)enc
                       freeWhenDone:(BOOL)freeBuffer
{
    id r = [self initWithBytes:bytes length:len encoding:enc];
    if (freeBuffer)
        free(bytes);
    return r;
}
/* Which encoding a file is in: what its byte order mark says, UTF-8 when
 * its bytes are UTF-8, and Windows Latin 1 (which any bytes are) when not. */
static NSStringEncoding guess_encoding(NSData *d, NSUInteger *skip)
{
    const unsigned char *b = [d bytes];
    NSUInteger len = [d length];
    *skip = 0;
    if (len >= 3 && b[0] == 0xef && b[1] == 0xbb && b[2] == 0xbf) {
        *skip = 3;
        return NSUTF8StringEncoding;
    }
    if (len >= 4 && ((b[0] == 0xff && b[1] == 0xfe && b[2] == 0 && b[3] == 0) ||
                     (b[0] == 0 && b[1] == 0 && b[2] == 0xfe && b[3] == 0xff)))
        return NSUTF32StringEncoding;
    if (len >= 2 && ((b[0] == 0xff && b[1] == 0xfe) || (b[0] == 0xfe && b[1] == 0xff)))
        return NSUTF16StringEncoding;
    NSUInteger n;
    unichar *c = FDecodeBytes(b, len, NSUTF8StringEncoding, &n);
    if (c) {
        free(c);
        return NSUTF8StringEncoding;
    }
    return NSWindowsCP1252StringEncoding;
}
- (instancetype)initWithContentsOfFile:(NSString *)path usedEncoding:(NSStringEncoding *)enc error:(NSError **)error
{
    NSData *d = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!d) {
        [self release];
        return nil;
    }
    NSUInteger skip;
    NSStringEncoding e = guess_encoding(d, &skip);
    if (enc)
        *enc = e;
    return [self initWithBytes:(const char *)[d bytes] + skip length:[d length] - skip encoding:e];
}
+ (instancetype)stringWithContentsOfFile:(NSString *)path usedEncoding:(NSStringEncoding *)enc error:(NSError **)error
{
    return [[[self alloc] initWithContentsOfFile:path usedEncoding:enc error:error] autorelease];
}
@end

/* ---- CFString's encoding calls ---------------------------------------------------------- */

CFStringEncoding CFStringGetSystemEncoding(void) { return kCFStringEncodingMacRoman; }
CFStringEncoding CFStringGetMostCompatibleMacStringEncoding(CFStringEncoding enc)
{
    switch (enc) {
    case kCFStringEncodingISOLatin1:
    case kCFStringEncodingWindowsLatin1:
    case kCFStringEncodingASCII:
    case kCFStringEncodingISOLatin9:
        return kCFStringEncodingMacRoman;
    case kCFStringEncodingISOLatin2:
    case kCFStringEncodingWindowsLatin2:
        return kCFStringEncodingMacCentralEurRoman;
    case kCFStringEncodingISOLatinCyrillic:
    case kCFStringEncodingWindowsCyrillic:
    case kCFStringEncodingKOI8_R:
        return kCFStringEncodingMacCyrillic;
    case kCFStringEncodingISOLatinGreek:
    case kCFStringEncodingWindowsGreek:
        return kCFStringEncodingMacGreek;
    case kCFStringEncodingISOLatin5:
    case kCFStringEncodingWindowsLatin5:
        return kCFStringEncodingMacTurkish;
    case kCFStringEncodingShiftJIS:
    case kCFStringEncodingDOSJapanese:
    case kCFStringEncodingEUC_JP:
    case kCFStringEncodingISO_2022_JP:
        return kCFStringEncodingMacJapanese;
    default:
        return find_cf(enc) && enc <= 0xff ? enc : kCFStringEncodingInvalidId;
    }
}
Boolean CFStringIsEncodingAvailable(CFStringEncoding enc) { return available(find_cf(enc)); }
const CFStringEncoding *CFStringGetListOfAvailableEncodings(void)
{
    static CFStringEncoding *list;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        list = malloc((N_ENCODINGS + 1) * sizeof(CFStringEncoding));
        size_t k = 0;
        for (size_t i = 0; i < N_ENCODINGS; i++)
            if (available(&encodings[i]))
                list[k++] = encodings[i].cf;
        list[k] = kCFStringEncodingInvalidId;
    });
    return list;
}
CFStringRef CFStringGetNameOfEncoding(CFStringEncoding enc)
{
    const FEncoding *e = find_cf(enc);
    if (!e)
        return NULL;
    static NSMutableDictionary *names;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    if (!names)
        names = [[NSMutableDictionary alloc] init];
    NSNumber *k = [NSNumber numberWithUnsignedInt:enc];
    NSString *s = [names objectForKey:k];
    if (!s) {
        s = [NSString stringWithUTF8String:e->name];
        [names setObject:s forKey:k];
    }
    os_unfair_lock_unlock(&lock);
    return (CFStringRef)s;
}
UInt32 CFStringConvertEncodingToWindowsCodepage(CFStringEncoding enc)
{
    const FEncoding *e = find_cf(enc);
    return e && e->codepage ? e->codepage : kCFStringEncodingInvalidId;
}
CFStringEncoding CFStringConvertWindowsCodepageToEncoding(UInt32 codepage)
{
    for (size_t i = 0; i < N_ENCODINGS; i++)
        if (encodings[i].codepage == codepage)
            return encodings[i].cf;
    return kCFStringEncodingInvalidId;
}
CFStringEncoding CFStringConvertIANACharSetNameToEncoding(CFStringRef name)
{
    NSString *n = [(NSString *)name lowercaseString];
    if ([n isEqualToString:@"utf8"] || [n isEqualToString:@"unicode-1-1-utf-8"])
        return kCFStringEncodingUTF8;
    if ([n isEqualToString:@"latin1"] || [n isEqualToString:@"iso_8859-1"] || [n isEqualToString:@"iso8859-1"])
        return kCFStringEncodingISOLatin1;
    if ([n isEqualToString:@"ascii"] || [n isEqualToString:@"us"] || [n isEqualToString:@"iso646-us"])
        return kCFStringEncodingASCII;
    if ([n isEqualToString:@"x-mac-roman"] || [n isEqualToString:@"mac"])
        return kCFStringEncodingMacRoman;
    if ([n isEqualToString:@"sjis"] || [n isEqualToString:@"x-sjis"])
        return kCFStringEncodingShiftJIS;
    if ([n isEqualToString:@"cp1252"])
        return kCFStringEncodingWindowsLatin1;
    const char *c = [n UTF8String];
    for (size_t i = 0; i < N_ENCODINGS; i++)
        if (encodings[i].iana && strcmp(encodings[i].iana, c) == 0)
            return encodings[i].cf;
    return kCFStringEncodingInvalidId;
}
CFStringRef CFStringConvertEncodingToIANACharSetName(CFStringEncoding enc)
{
    const FEncoding *e = find_cf(enc);
    if (!e || !e->iana)
        return NULL;
    return (CFStringRef)[NSString stringWithUTF8String:e->iana];
}
CFIndex CFStringGetMaximumSizeForEncoding(CFIndex length, CFStringEncoding enc)
{
    switch (enc) {
    case kCFStringEncodingASCII:
    case kCFStringEncodingISOLatin1:
    case kCFStringEncodingMacRoman:
    case kCFStringEncodingWindowsLatin1:
        return length;
    case kCFStringEncodingUTF8:
        return length * 3;
    case kCFStringEncodingUTF16:
    case kCFStringEncodingUTF16BE:
    case kCFStringEncodingUTF16LE:
        return length * 2;
    case kCFStringEncodingUTF32:
    case kCFStringEncodingUTF32BE:
    case kCFStringEncodingUTF32LE:
        return length * 4;
    case kCFStringEncodingNonLossyASCII:
        return length * 6;
    default:
        return length * 4;
    }
}
CFStringEncoding CFStringGetSmallestEncoding(CFStringRef s)
{
    return CFStringConvertNSStringEncodingToEncoding([(NSString *)s smallestEncoding]);
}
CFStringEncoding CFStringGetFastestEncoding(CFStringRef s) { return kCFStringEncodingUnicode; }

/* As many characters of range as convert and fit in the buffer (all of
 * them, with a NULL buffer), from the start; the bytes it takes go in
 * usedBufLen. A character the encoding lacks stops it, unless lossByte
 * stands in for it. */
CFIndex CFStringGetBytes(CFStringRef str, CFRange range, CFStringEncoding enc, UInt8 lossByte, Boolean external,
                         UInt8 *buffer, CFIndex maxBufLen, CFIndex *usedBufLen)
{
    const FEncoding *e = find_cf(enc);
    NSUInteger n = (NSUInteger)range.length;
    unichar *c = malloc((n + 1) * sizeof(unichar));
    [(NSString *)str getCharacters:c range:NSMakeRange((NSUInteger)range.location, n)];
    NSData *d = encode(c, n, e, lossByte, external);
    NSUInteger done = n;
    if (!d || (buffer && (CFIndex)[d length] > maxBufLen)) {
        /* the longest start that converts and fits */
        NSUInteger lo = 0, hi = n;
        NSData *best = [NSData data];
        while (lo < hi) {
            NSUInteger mid = (lo + hi + 1) / 2;
            if (mid < n && c[mid] >= 0xdc00 && c[mid] < 0xe000 && mid > 0 && c[mid - 1] >= 0xd800 && c[mid - 1] < 0xdc00)
                mid--;
            if (mid <= lo) {
                hi = lo;
                break;
            }
            NSData *t = encode(c, mid, e, lossByte, external);
            if (t && (!buffer || (CFIndex)[t length] <= maxBufLen))
                lo = mid, best = t;
            else
                hi = mid - 1;
        }
        done = lo;
        d = lo ? best : [NSData data];
        if (lo == 0 && external) /* nothing fits: not even the mark */
            d = [NSData data];
    }
    free(c);
    if (buffer)
        memcpy(buffer, [d bytes], [d length]);
    if (usedBufLen)
        *usedBufLen = (CFIndex)[d length];
    return (CFIndex)done;
}
CFStringRef CFStringCreateWithBytes(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes, CFStringEncoding enc,
                                    Boolean external)
{
    NSUInteger n;
    unichar *c = decode(bytes, (NSUInteger)numBytes, find_cf(enc), &n);
    if (!c)
        return NULL;
    NSString *s = [[NSString alloc] initWithCharacters:c length:n];
    free(c);
    return (CFStringRef)s;
}
CFStringRef CFStringCreateWithBytesNoCopy(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes,
                                          CFStringEncoding enc, Boolean external, CFAllocatorRef deallocator)
{
    /* the bytes are copied; Ferry can't tell kCFAllocatorNull from the default allocator, so frees nothing */
    return CFStringCreateWithBytes(alloc, bytes, numBytes, enc, external);
}
CFStringRef CFStringCreateWithCStringNoCopy(CFAllocatorRef alloc, const char *cStr, CFStringEncoding enc,
                                            CFAllocatorRef deallocator)
{
    return CFStringCreateWithBytes(alloc, (const UInt8 *)cStr, (CFIndex)strlen(cStr), enc, false);
}
CFDataRef CFStringCreateExternalRepresentation(CFAllocatorRef alloc, CFStringRef s, CFStringEncoding enc, UInt8 lossByte)
{
    NSUInteger n;
    unichar *c = copy_chars((NSString *)s, &n);
    NSData *d = encode(c, n, find_cf(enc), lossByte, YES);
    free(c);
    return (CFDataRef)[d retain];
}
CFStringRef CFStringCreateFromExternalRepresentation(CFAllocatorRef alloc, CFDataRef data, CFStringEncoding enc)
{
    return CFStringCreateWithBytes(alloc, [(NSData *)data bytes], (CFIndex)[(NSData *)data length], enc, true);
}
