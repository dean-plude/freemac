/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: more of CoreFoundation (Ferry 0.43.0): arrays and dictionaries
 * with callbacks, the rest of the string calls apps make, string encodings,
 * UUIDs, URLs, bundle keys and byte order. Written for freemac from Apple's
 * public API documentation of CFArray, CFDictionary, CFString,
 * CFStringEncodingExt, CFUUID, CFURL, CFBundle and CFByteOrder; not Apple's
 * header. Included by <CoreFoundation/CoreFoundation.h>. */
#ifndef _FERRY_CFMORE_H_
#define _FERRY_CFMORE_H_

__FERRY_BEGIN
CFTypeRef CFMakeCollectable(CFTypeRef cf); /* there is no garbage collector: gives cf back */
extern const double kCFCoreFoundationVersionNumber;
#define kCFCoreFoundationVersionNumber10_9 855.11
#define kCFCoreFoundationVersionNumber10_10 1151.16

/* ---- arrays ------------------------------------------------------------------------- */
typedef const void *(*CFArrayRetainCallBack)(CFAllocatorRef allocator, const void *value);
typedef void (*CFArrayReleaseCallBack)(CFAllocatorRef allocator, const void *value);
typedef CFStringRef (*CFArrayCopyDescriptionCallBack)(const void *value);
typedef Boolean (*CFArrayEqualCallBack)(const void *value1, const void *value2);
typedef struct {
    CFIndex version;
    CFArrayRetainCallBack retain;
    CFArrayReleaseCallBack release;
    CFArrayCopyDescriptionCallBack copyDescription;
    CFArrayEqualCallBack equal;
} CFArrayCallBacks;
extern const CFArrayCallBacks kCFTypeArrayCallBacks;
typedef void (*CFArrayApplierFunction)(const void *value, void *context);
typedef CFComparisonResult (*CFComparatorFunction)(const void *val1, const void *val2, void *context);

CFTypeID CFArrayGetTypeID(void);
CFArrayRef CFArrayCreate(CFAllocatorRef alloc, const void **values, CFIndex count, const CFArrayCallBacks *callBacks);
CFArrayRef CFArrayCreateCopy(CFAllocatorRef alloc, CFArrayRef array);
CFMutableArrayRef CFArrayCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const CFArrayCallBacks *callBacks);
CFMutableArrayRef CFArrayCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFArrayRef array);
void CFArrayGetValues(CFArrayRef array, CFRange range, const void **values);
Boolean CFArrayContainsValue(CFArrayRef array, CFRange range, const void *value);
CFIndex CFArrayGetCountOfValue(CFArrayRef array, CFRange range, const void *value);
CFIndex CFArrayGetFirstIndexOfValue(CFArrayRef array, CFRange range, const void *value);
CFIndex CFArrayGetLastIndexOfValue(CFArrayRef array, CFRange range, const void *value);
void CFArrayApplyFunction(CFArrayRef array, CFRange range, CFArrayApplierFunction applier, void *context);
CFIndex CFArrayBSearchValues(CFArrayRef array, CFRange range, const void *value, CFComparatorFunction comparator,
                             void *context);
void CFArraySetValueAtIndex(CFMutableArrayRef array, CFIndex idx, const void *value);
void CFArrayInsertValueAtIndex(CFMutableArrayRef array, CFIndex idx, const void *value);
void CFArrayRemoveValueAtIndex(CFMutableArrayRef array, CFIndex idx);
void CFArrayRemoveAllValues(CFMutableArrayRef array);
void CFArrayReplaceValues(CFMutableArrayRef array, CFRange range, const void **newValues, CFIndex newCount);
void CFArrayAppendArray(CFMutableArrayRef array, CFArrayRef other, CFRange otherRange);
void CFArrayExchangeValuesAtIndices(CFMutableArrayRef array, CFIndex idx1, CFIndex idx2);
void CFArraySortValues(CFMutableArrayRef array, CFRange range, CFComparatorFunction comparator, void *context);

/* ---- dictionaries -------------------------------------------------------------------- */
typedef CFHashCode (*CFDictionaryHashCallBack)(const void *value);
typedef struct {
    CFIndex version;
    CFArrayRetainCallBack retain;
    CFArrayReleaseCallBack release;
    CFArrayCopyDescriptionCallBack copyDescription;
    CFArrayEqualCallBack equal;
    CFDictionaryHashCallBack hash;
} CFDictionaryKeyCallBacks;
typedef struct {
    CFIndex version;
    CFArrayRetainCallBack retain;
    CFArrayReleaseCallBack release;
    CFArrayCopyDescriptionCallBack copyDescription;
    CFArrayEqualCallBack equal;
} CFDictionaryValueCallBacks;
extern const CFDictionaryKeyCallBacks kCFTypeDictionaryKeyCallBacks;
extern const CFDictionaryKeyCallBacks kCFCopyStringDictionaryKeyCallBacks;
extern const CFDictionaryValueCallBacks kCFTypeDictionaryValueCallBacks;
typedef void (*CFDictionaryApplierFunction)(const void *key, const void *value, void *context);

CFTypeID CFDictionaryGetTypeID(void);
CFDictionaryRef CFDictionaryCreate(CFAllocatorRef alloc, const void **keys, const void **values, CFIndex count,
                                   const CFDictionaryKeyCallBacks *keyCallBacks,
                                   const CFDictionaryValueCallBacks *valueCallBacks);
CFDictionaryRef CFDictionaryCreateCopy(CFAllocatorRef alloc, CFDictionaryRef dict);
CFMutableDictionaryRef CFDictionaryCreateMutable(CFAllocatorRef alloc, CFIndex capacity,
                                                 const CFDictionaryKeyCallBacks *keyCallBacks,
                                                 const CFDictionaryValueCallBacks *valueCallBacks);
CFMutableDictionaryRef CFDictionaryCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFDictionaryRef dict);
Boolean CFDictionaryGetValueIfPresent(CFDictionaryRef dict, const void *key, const void **value);
Boolean CFDictionaryContainsValue(CFDictionaryRef dict, const void *value);
CFIndex CFDictionaryGetCountOfKey(CFDictionaryRef dict, const void *key);
CFIndex CFDictionaryGetCountOfValue(CFDictionaryRef dict, const void *value);
void CFDictionaryGetKeysAndValues(CFDictionaryRef dict, const void **keys, const void **values);
void CFDictionaryApplyFunction(CFDictionaryRef dict, CFDictionaryApplierFunction applier, void *context);
void CFDictionaryAddValue(CFMutableDictionaryRef dict, const void *key, const void *value);
void CFDictionaryReplaceValue(CFMutableDictionaryRef dict, const void *key, const void *value);
void CFDictionaryRemoveAllValues(CFMutableDictionaryRef dict);

/* ---- strings ------------------------------------------------------------------------- */
typedef CF_OPTIONS(CFOptionFlags, CFStringCompareFlags){
    kCFCompareCaseInsensitive = 1, kCFCompareBackwards = 4,   kCFCompareAnchored = 8,
    kCFCompareNonliteral = 16,     kCFCompareLocalized = 32,  kCFCompareNumerically = 64,
    kCFCompareDiacriticInsensitive = 128, kCFCompareWidthInsensitive = 256, kCFCompareForcedOrdering = 512,
};
typedef CF_ENUM(CFIndex, CFStringNormalizationForm){
    kCFStringNormalizationFormD = 0, kCFStringNormalizationFormKD = 1,
    kCFStringNormalizationFormC = 2, kCFStringNormalizationFormKC = 3,
};

CFTypeID CFStringGetTypeID(void);
CFStringRef CFStringCreateWithBytes(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes,
                                    CFStringEncoding encoding, Boolean isExternalRepresentation);
CFStringRef CFStringCreateWithBytesNoCopy(CFAllocatorRef alloc, const UInt8 *bytes, CFIndex numBytes,
                                          CFStringEncoding encoding, Boolean isExternalRepresentation,
                                          CFAllocatorRef contentsDeallocator);
CFStringRef CFStringCreateWithCharactersNoCopy(CFAllocatorRef alloc, const UniChar *chars, CFIndex numChars,
                                               CFAllocatorRef contentsDeallocator);
CFStringRef CFStringCreateWithCStringNoCopy(CFAllocatorRef alloc, const char *cStr, CFStringEncoding encoding,
                                            CFAllocatorRef contentsDeallocator);
CFStringRef CFStringCreateWithSubstring(CFAllocatorRef alloc, CFStringRef str, CFRange range);
CFStringRef CFStringCreateWithFormatAndArguments(CFAllocatorRef alloc, CFDictionaryRef formatOptions,
                                                 CFStringRef format, va_list arguments);
CFMutableStringRef CFStringCreateMutableCopy(CFAllocatorRef alloc, CFIndex maxLength, CFStringRef theString);
/* Ferry copies the characters in, and again on each CFStringSetExternalCharactersNoCopy: the buffer
 * isn't written to when the string changes. */
CFMutableStringRef CFStringCreateMutableWithExternalCharactersNoCopy(CFAllocatorRef alloc, UniChar *chars,
                                                                     CFIndex numChars, CFIndex capacity,
                                                                     CFAllocatorRef externalCharactersAllocator);
void CFStringSetExternalCharactersNoCopy(CFMutableStringRef theString, UniChar *chars, CFIndex length,
                                         CFIndex capacity);
CFDataRef CFStringCreateExternalRepresentation(CFAllocatorRef alloc, CFStringRef theString,
                                               CFStringEncoding encoding, UInt8 lossByte);
CFStringRef CFStringCreateFromExternalRepresentation(CFAllocatorRef alloc, CFDataRef data, CFStringEncoding encoding);
CFIndex CFStringGetBytes(CFStringRef theString, CFRange range, CFStringEncoding encoding, UInt8 lossByte,
                         Boolean isExternalRepresentation, UInt8 *buffer, CFIndex maxBufLen, CFIndex *usedBufLen);
void CFStringAppendCharacters(CFMutableStringRef theString, const UniChar *chars, CFIndex numChars);
void CFStringAppendFormat(CFMutableStringRef theString, CFDictionaryRef formatOptions, CFStringRef format, ...);
void CFStringAppendFormatAndArguments(CFMutableStringRef theString, CFDictionaryRef formatOptions,
                                      CFStringRef format, va_list arguments);
void CFStringInsert(CFMutableStringRef str, CFIndex idx, CFStringRef insertedStr);
void CFStringDelete(CFMutableStringRef theString, CFRange range);
void CFStringReplace(CFMutableStringRef theString, CFRange range, CFStringRef replacement);
void CFStringReplaceAll(CFMutableStringRef theString, CFStringRef replacement);
CFIndex CFStringFindAndReplace(CFMutableStringRef theString, CFStringRef stringToFind, CFStringRef replacementString,
                               CFRange rangeToSearch, CFStringCompareFlags compareOptions);
CFRange CFStringFind(CFStringRef theString, CFStringRef stringToFind, CFStringCompareFlags compareOptions);
Boolean CFStringFindWithOptions(CFStringRef theString, CFStringRef stringToFind, CFRange rangeToSearch,
                                CFStringCompareFlags searchOptions, CFRange *result);
CFComparisonResult CFStringCompareWithOptions(CFStringRef theString1, CFStringRef theString2, CFRange rangeToCompare,
                                              CFStringCompareFlags compareOptions);
void CFStringUppercase(CFMutableStringRef theString, const void *locale);
void CFStringLowercase(CFMutableStringRef theString, const void *locale);
void CFStringCapitalize(CFMutableStringRef theString, const void *locale);
void CFStringTrimWhitespace(CFMutableStringRef theString);
void CFStringTrim(CFMutableStringRef theString, CFStringRef trimString);
void CFStringNormalize(CFMutableStringRef theString, CFStringNormalizationForm theForm);
CFArrayRef CFStringCreateArrayBySeparatingStrings(CFAllocatorRef alloc, CFStringRef theString,
                                                  CFStringRef separatorString);
CFStringRef CFStringCreateByCombiningStrings(CFAllocatorRef alloc, CFArrayRef theArray, CFStringRef separatorString);
Boolean CFStringGetFileSystemRepresentation(CFStringRef string, char *buffer, CFIndex maxBufLen);
CFIndex CFStringGetMaximumSizeOfFileSystemRepresentation(CFStringRef string);
CFIndex CFStringGetMaximumSizeForEncoding(CFIndex length, CFStringEncoding encoding);
CFStringEncoding CFStringGetSmallestEncoding(CFStringRef theString);
CFStringEncoding CFStringGetFastestEncoding(CFStringRef theString);

static inline Boolean CFStringIsSurrogateHighCharacter(UniChar c) { return c >= 0xD800 && c <= 0xDBFF; }
static inline Boolean CFStringIsSurrogateLowCharacter(UniChar c) { return c >= 0xDC00 && c <= 0xDFFF; }
static inline UInt32 CFStringGetLongCharacterForSurrogatePair(UniChar high, UniChar low)
{
    return ((UInt32)(high - 0xD800) << 10) + (UInt32)(low - 0xDC00) + 0x10000;
}
static inline Boolean CFStringGetSurrogatePairForLongCharacter(UInt32 c, UniChar *pair)
{
    if (c < 0x10000 || c > 0x10FFFF) {
        if (pair)
            pair[0] = (UniChar)c;
        return 0;
    }
    if (pair) {
        pair[0] = (UniChar)(((c - 0x10000) >> 10) + 0xD800);
        pair[1] = (UniChar)(((c - 0x10000) & 0x3FF) + 0xDC00);
    }
    return 1;
}

/* ---- string encodings (CFStringEncodingExt) --------------------------------------------
 * Which of them Ferry can convert: CFStringIsEncodingAvailable and
 * CFStringGetListOfAvailableEncodings. Most go through this system's ICU. */
#define kCFStringEncodingInvalidId 0xffffffffU
enum {
    kCFStringEncodingMacRoman = 0,
    kCFStringEncodingWindowsLatin1 = 0x0500,
    kCFStringEncodingNextStepLatin = 0x0B01,
    kCFStringEncodingNonLossyASCII = 0x0BFF,
    kCFStringEncodingUTF16 = 0x0100,
    kCFStringEncodingUTF16BE = 0x10000100,
    kCFStringEncodingUTF16LE = 0x14000100,
    kCFStringEncodingUTF32 = 0x0c000100,
    kCFStringEncodingUTF32BE = 0x18000100,
    kCFStringEncodingUTF32LE = 0x1c000100,
    kCFStringEncodingMacJapanese = 1, kCFStringEncodingMacChineseTrad = 2, kCFStringEncodingMacKorean = 3,
    kCFStringEncodingMacArabic = 4, kCFStringEncodingMacHebrew = 5, kCFStringEncodingMacGreek = 6,
    kCFStringEncodingMacCyrillic = 7, kCFStringEncodingMacThai = 21, kCFStringEncodingMacChineseSimp = 25,
    kCFStringEncodingMacCentralEurRoman = 29, kCFStringEncodingMacSymbol = 33, kCFStringEncodingMacTurkish = 35,
    kCFStringEncodingMacCroatian = 36, kCFStringEncodingMacIcelandic = 37, kCFStringEncodingMacRomanian = 38,
    kCFStringEncodingMacUkrainian = 0x98,
    kCFStringEncodingISOLatin2 = 0x0202, kCFStringEncodingISOLatin3 = 0x0203, kCFStringEncodingISOLatin4 = 0x0204,
    kCFStringEncodingISOLatinCyrillic = 0x0205, kCFStringEncodingISOLatinArabic = 0x0206,
    kCFStringEncodingISOLatinGreek = 0x0207, kCFStringEncodingISOLatinHebrew = 0x0208,
    kCFStringEncodingISOLatin5 = 0x0209, kCFStringEncodingISOLatin6 = 0x020A, kCFStringEncodingISOLatinThai = 0x020B,
    kCFStringEncodingISOLatin7 = 0x020D, kCFStringEncodingISOLatin8 = 0x020E, kCFStringEncodingISOLatin9 = 0x020F,
    kCFStringEncodingISOLatin10 = 0x0210,
    kCFStringEncodingDOSLatinUS = 0x0400, kCFStringEncodingDOSGreek = 0x0405, kCFStringEncodingDOSBalticRim = 0x0406,
    kCFStringEncodingDOSLatin1 = 0x0410, kCFStringEncodingDOSGreek1 = 0x0411, kCFStringEncodingDOSLatin2 = 0x0412,
    kCFStringEncodingDOSCyrillic = 0x0413, kCFStringEncodingDOSTurkish = 0x0414,
    kCFStringEncodingDOSPortuguese = 0x0415, kCFStringEncodingDOSIcelandic = 0x0416,
    kCFStringEncodingDOSHebrew = 0x0417, kCFStringEncodingDOSCanadianFrench = 0x0418,
    kCFStringEncodingDOSArabic = 0x0419, kCFStringEncodingDOSNordic = 0x041A, kCFStringEncodingDOSRussian = 0x041B,
    kCFStringEncodingDOSGreek2 = 0x041C, kCFStringEncodingDOSThai = 0x041D, kCFStringEncodingDOSJapanese = 0x0420,
    kCFStringEncodingDOSChineseSimplif = 0x0421, kCFStringEncodingDOSKorean = 0x0422,
    kCFStringEncodingDOSChineseTrad = 0x0423,
    kCFStringEncodingWindowsLatin2 = 0x0501, kCFStringEncodingWindowsCyrillic = 0x0502,
    kCFStringEncodingWindowsGreek = 0x0503, kCFStringEncodingWindowsLatin5 = 0x0504,
    kCFStringEncodingWindowsHebrew = 0x0505, kCFStringEncodingWindowsArabic = 0x0506,
    kCFStringEncodingWindowsBalticRim = 0x0507, kCFStringEncodingWindowsVietnamese = 0x0508,
    kCFStringEncodingWindowsKoreanJohab = 0x0510,
    kCFStringEncodingANSEL = 0x0601, kCFStringEncodingJIS_X0201_76 = 0x0620,
    kCFStringEncodingGB_2312_80 = 0x0630, kCFStringEncodingGBK_95 = 0x0631, kCFStringEncodingGB_18030_2000 = 0x0632,
    kCFStringEncodingISO_2022_JP = 0x0820, kCFStringEncodingISO_2022_CN = 0x0830, kCFStringEncodingISO_2022_KR = 0x0840,
    kCFStringEncodingEUC_JP = 0x0920, kCFStringEncodingEUC_CN = 0x0930, kCFStringEncodingEUC_TW = 0x0931,
    kCFStringEncodingEUC_KR = 0x0940,
    kCFStringEncodingShiftJIS = 0x0A01, kCFStringEncodingKOI8_R = 0x0A02, kCFStringEncodingBig5 = 0x0A03,
    kCFStringEncodingMacRomanLatin1 = 0x0A04, kCFStringEncodingHZ_GB_2312 = 0x0A05,
    kCFStringEncodingBig5_HKSCS_1999 = 0x0A06, kCFStringEncodingKOI8_U = 0x0A08,
    kCFStringEncodingEBCDIC_US = 0x0C01, kCFStringEncodingEBCDIC_CP037 = 0x0C02,
};

CFStringEncoding CFStringGetSystemEncoding(void);
CFStringEncoding CFStringGetMostCompatibleMacStringEncoding(CFStringEncoding encoding);
Boolean CFStringIsEncodingAvailable(CFStringEncoding encoding);
const CFStringEncoding *CFStringGetListOfAvailableEncodings(void);  /* ends with kCFStringEncodingInvalidId */
CFStringRef CFStringGetNameOfEncoding(CFStringEncoding encoding);
unsigned long CFStringConvertEncodingToNSStringEncoding(CFStringEncoding encoding);
CFStringEncoding CFStringConvertNSStringEncodingToEncoding(unsigned long encoding);
UInt32 CFStringConvertEncodingToWindowsCodepage(CFStringEncoding encoding);
CFStringEncoding CFStringConvertWindowsCodepageToEncoding(UInt32 codepage);
CFStringEncoding CFStringConvertIANACharSetNameToEncoding(CFStringRef theString);
CFStringRef CFStringConvertEncodingToIANACharSetName(CFStringEncoding encoding);

/* ---- UUIDs (on NSUUID) ----------------------------------------------------------------- */
typedef const struct __CFUUID *CFUUIDRef;
typedef struct {
    UInt8 byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7;
    UInt8 byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15;
} CFUUIDBytes;
CFTypeID CFUUIDGetTypeID(void);
CFUUIDRef CFUUIDCreate(CFAllocatorRef alloc);
CFUUIDRef CFUUIDCreateWithBytes(CFAllocatorRef alloc, UInt8 byte0, UInt8 byte1, UInt8 byte2, UInt8 byte3,
                                UInt8 byte4, UInt8 byte5, UInt8 byte6, UInt8 byte7, UInt8 byte8, UInt8 byte9,
                                UInt8 byte10, UInt8 byte11, UInt8 byte12, UInt8 byte13, UInt8 byte14, UInt8 byte15);
CFUUIDRef CFUUIDGetConstantUUIDWithBytes(CFAllocatorRef alloc, UInt8 byte0, UInt8 byte1, UInt8 byte2, UInt8 byte3,
                                         UInt8 byte4, UInt8 byte5, UInt8 byte6, UInt8 byte7, UInt8 byte8,
                                         UInt8 byte9, UInt8 byte10, UInt8 byte11, UInt8 byte12, UInt8 byte13,
                                         UInt8 byte14, UInt8 byte15);
CFUUIDRef CFUUIDCreateFromString(CFAllocatorRef alloc, CFStringRef uuidStr);
CFUUIDRef CFUUIDCreateFromUUIDBytes(CFAllocatorRef alloc, CFUUIDBytes bytes);
CFStringRef CFUUIDCreateString(CFAllocatorRef alloc, CFUUIDRef uuid);
CFUUIDBytes CFUUIDGetUUIDBytes(CFUUIDRef uuid);

/* ---- URLs (on NSURL) ----------------------------------------------------------------- */
typedef CF_ENUM(CFIndex, CFURLPathStyle){
    kCFURLPOSIXPathStyle = 0, kCFURLHFSPathStyle = 1, kCFURLWindowsPathStyle = 2,
};
CFTypeID CFURLGetTypeID(void);
CFURLRef CFURLCreateWithString(CFAllocatorRef alloc, CFStringRef URLString, CFURLRef baseURL);
CFURLRef CFURLCreateWithBytes(CFAllocatorRef alloc, const UInt8 *URLBytes, CFIndex length,
                              CFStringEncoding encoding, CFURLRef baseURL);
CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef alloc, CFStringRef filePath, CFURLPathStyle pathStyle,
                                       Boolean isDirectory);
CFURLRef CFURLCreateFromFileSystemRepresentation(CFAllocatorRef alloc, const UInt8 *buffer, CFIndex bufLen,
                                                 Boolean isDirectory);
CFURLRef CFURLCopyAbsoluteURL(CFURLRef relativeURL);
CFStringRef CFURLGetString(CFURLRef anURL);
CFURLRef CFURLGetBaseURL(CFURLRef anURL);
CFStringRef CFURLCopyFileSystemPath(CFURLRef anURL, CFURLPathStyle pathStyle);
Boolean CFURLGetFileSystemRepresentation(CFURLRef url, Boolean resolveAgainstBase, UInt8 *buffer, CFIndex maxBufLen);
CFStringRef CFURLCopyScheme(CFURLRef anURL);
CFStringRef CFURLCopyHostName(CFURLRef anURL);
SInt32 CFURLGetPortNumber(CFURLRef anURL);
CFStringRef CFURLCopyPath(CFURLRef anURL);
CFStringRef CFURLCopyQueryString(CFURLRef anURL, CFStringRef charactersToLeaveEscaped);
CFStringRef CFURLCopyFragment(CFURLRef anURL, CFStringRef charactersToLeaveEscaped);
CFStringRef CFURLCopyLastPathComponent(CFURLRef url);
CFStringRef CFURLCopyPathExtension(CFURLRef url);
Boolean CFURLHasDirectoryPath(CFURLRef anURL);
CFURLRef CFURLCreateCopyAppendingPathComponent(CFAllocatorRef alloc, CFURLRef url, CFStringRef pathComponent,
                                               Boolean isDirectory);
CFURLRef CFURLCreateCopyDeletingLastPathComponent(CFAllocatorRef alloc, CFURLRef url);
CFURLRef CFURLCreateCopyAppendingPathExtension(CFAllocatorRef alloc, CFURLRef url, CFStringRef extension);
CFURLRef CFURLCreateCopyDeletingPathExtension(CFAllocatorRef alloc, CFURLRef url);
Boolean CFURLResourceIsReachable(CFURLRef url, CFErrorRef *error);
Boolean CFURLCopyResourcePropertyForKey(CFURLRef url, CFStringRef key, void *propertyValueTypeRefPtr,
                                        CFErrorRef *error);
CFStringRef CFURLCreateStringByAddingPercentEscapes(CFAllocatorRef allocator, CFStringRef originalString,
                                                    CFStringRef charactersToLeaveUnescaped,
                                                    CFStringRef legalURLCharactersToBeEscaped,
                                                    CFStringEncoding encoding);
CFStringRef CFURLCreateStringByReplacingPercentEscapes(CFAllocatorRef allocator, CFStringRef originalString,
                                                       CFStringRef charactersToLeaveEscaped);
CFStringRef CFURLCreateStringByReplacingPercentEscapesUsingEncoding(CFAllocatorRef allocator,
                                                                    CFStringRef origString,
                                                                    CFStringRef charsToLeaveEscaped,
                                                                    CFStringEncoding encoding);
struct FSRef;
Boolean CFURLGetFSRef(CFURLRef url, struct FSRef *fsRef); /* no FSRefs here: always false */

/* ---- bundles ------------------------------------------------------------------------- */
extern const CFStringRef kCFBundleInfoDictionaryVersionKey, kCFBundleExecutableKey, kCFBundleIdentifierKey,
    kCFBundleVersionKey, kCFBundleDevelopmentRegionKey, kCFBundleNameKey, kCFBundleLocalizationsKey;
CFURLRef CFBundleCopyResourceURL(CFBundleRef bundle, CFStringRef resourceName, CFStringRef resourceType,
                                 CFStringRef subDirName);
CFStringRef CFBundleCopyLocalizedString(CFBundleRef bundle, CFStringRef key, CFStringRef value, CFStringRef tableName);
#define CFCopyLocalizedString(key, comment) \
    CFBundleCopyLocalizedString(CFBundleGetMainBundle(), (key), (key), NULL)
__FERRY_END

/* ---- byte order (CFByteOrder) ---------------------------------------------------------- */
enum { CFByteOrderUnknown = 0, CFByteOrderLittleEndian = 1, CFByteOrderBigEndian = 2 };
typedef CFIndex CFByteOrder;
static inline CFByteOrder CFByteOrderGetCurrent(void) { return CFByteOrderLittleEndian; }
static inline uint16_t CFSwapInt16(uint16_t v) { return __builtin_bswap16(v); }
static inline uint32_t CFSwapInt32(uint32_t v) { return __builtin_bswap32(v); }
static inline uint64_t CFSwapInt64(uint64_t v) { return __builtin_bswap64(v); }
static inline uint16_t CFSwapInt16BigToHost(uint16_t v) { return __builtin_bswap16(v); }
static inline uint32_t CFSwapInt32BigToHost(uint32_t v) { return __builtin_bswap32(v); }
static inline uint64_t CFSwapInt64BigToHost(uint64_t v) { return __builtin_bswap64(v); }
static inline uint16_t CFSwapInt16HostToBig(uint16_t v) { return __builtin_bswap16(v); }
static inline uint32_t CFSwapInt32HostToBig(uint32_t v) { return __builtin_bswap32(v); }
static inline uint64_t CFSwapInt64HostToBig(uint64_t v) { return __builtin_bswap64(v); }
static inline uint16_t CFSwapInt16LittleToHost(uint16_t v) { return v; }
static inline uint32_t CFSwapInt32LittleToHost(uint32_t v) { return v; }
static inline uint64_t CFSwapInt64LittleToHost(uint64_t v) { return v; }
static inline uint16_t CFSwapInt16HostToLittle(uint16_t v) { return v; }
static inline uint32_t CFSwapInt32HostToLittle(uint32_t v) { return v; }
static inline uint64_t CFSwapInt64HostToLittle(uint64_t v) { return v; }
#endif
