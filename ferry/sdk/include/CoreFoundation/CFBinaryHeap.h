/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * More of CoreFoundation (freemac 1.265, Ferry 0.88.0): allocators made
 * from a context, binary heaps, string tokenizers, character sets as
 * bitmaps and hyphenation. Written from Apple's public API documentation
 * of CFAllocator, CFBinaryHeap, CFStringTokenizer and CFString; not
 * Apple's header. Served from foundation/CFElectron.m. Included by
 * <CoreFoundation/CoreFoundation.h>. */
#ifndef _FERRY_CFBINARYHEAP_H_
#define _FERRY_CFBINARYHEAP_H_

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
/* ---- allocators ---------------------------------------------------------------------- */
typedef const void *(*CFAllocatorRetainCallBack)(const void *info);
typedef void (*CFAllocatorReleaseCallBack)(const void *info);
typedef CFStringRef (*CFAllocatorCopyDescriptionCallBack)(const void *info);
typedef void *(*CFAllocatorAllocateCallBack)(CFIndex allocSize, CFOptionFlags hint, void *info);
typedef void *(*CFAllocatorReallocateCallBack)(void *ptr, CFIndex newsize, CFOptionFlags hint, void *info);
typedef void (*CFAllocatorDeallocateCallBack)(void *ptr, void *info);
typedef CFIndex (*CFAllocatorPreferredSizeCallBack)(CFIndex size, CFOptionFlags hint, void *info);
typedef struct {
    CFIndex version;
    void *info;
    CFAllocatorRetainCallBack retain;
    CFAllocatorReleaseCallBack release;
    CFAllocatorCopyDescriptionCallBack copyDescription;
    CFAllocatorAllocateCallBack allocate;
    CFAllocatorReallocateCallBack reallocate;
    CFAllocatorDeallocateCallBack deallocate;
    CFAllocatorPreferredSizeCallBack preferredSize;
} CFAllocatorContext;
/* Ferry's memory always comes from malloc; the context is kept and given back */
CFAllocatorRef CFAllocatorCreate(CFAllocatorRef allocator, CFAllocatorContext *context);
void CFAllocatorGetContext(CFAllocatorRef allocator, CFAllocatorContext *context);

/* ---- binary heaps -------------------------------------------------------------------- */
typedef struct __CFBinaryHeap *CFBinaryHeapRef;
typedef struct {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} CFBinaryHeapCompareContext;
typedef struct {
    CFIndex version;
    const void *(*retain)(CFAllocatorRef allocator, const void *ptr);
    void (*release)(CFAllocatorRef allocator, const void *ptr);
    CFStringRef (*copyDescription)(const void *ptr);
    CFComparisonResult (*compare)(const void *ptr1, const void *ptr2, void *context);
} CFBinaryHeapCallBacks;
CFTypeID CFBinaryHeapGetTypeID(void);
CFBinaryHeapRef CFBinaryHeapCreate(CFAllocatorRef allocator, CFIndex capacity, const CFBinaryHeapCallBacks *callBacks,
                                   const CFBinaryHeapCompareContext *compareContext);
void CFBinaryHeapAddValue(CFBinaryHeapRef heap, const void *value);
CFIndex CFBinaryHeapGetCount(CFBinaryHeapRef heap);
const void *CFBinaryHeapGetMinimum(CFBinaryHeapRef heap);
Boolean CFBinaryHeapGetMinimumIfPresent(CFBinaryHeapRef heap, const void **value);
void CFBinaryHeapRemoveMinimumValue(CFBinaryHeapRef heap);
Boolean CFBinaryHeapContainsValue(CFBinaryHeapRef heap, const void *value);
void CFBinaryHeapRemoveAllValues(CFBinaryHeapRef heap);
void CFBinaryHeapGetValues(CFBinaryHeapRef heap, const void **values); /* smallest first */

/* ---- character sets as bitmaps (8192 bytes: the Basic Multilingual Plane) ----------- */
CFDataRef CFCharacterSetCreateBitmapRepresentation(CFAllocatorRef allocator, CFCharacterSetRef set);

/* ---- hyphenation: none is available ------------------------------------------------- */
Boolean CFStringIsHyphenationAvailableForLocale(CFLocaleRef locale);
CFIndex CFStringGetHyphenationLocationBeforeIndex(CFStringRef string, CFIndex location, CFRange limitRange,
                                                  CFOptionFlags options, CFLocaleRef locale, UTF32Char *character);

/* ---- string tokenizers --------------------------------------------------------------- */
typedef struct __CFStringTokenizer *CFStringTokenizerRef;
enum {
    kCFStringTokenizerUnitWord = 0,
    kCFStringTokenizerUnitSentence = 1,
    kCFStringTokenizerUnitParagraph = 2,
    kCFStringTokenizerUnitLineBreak = 3,
    kCFStringTokenizerUnitWordBoundary = 4,
    kCFStringTokenizerAttributeLatinTranscription = 1UL << 16,
    kCFStringTokenizerAttributeLanguage = 1UL << 17,
};
typedef CFOptionFlags CFStringTokenizerTokenType;
enum {
    kCFStringTokenizerTokenNone = 0,
    kCFStringTokenizerTokenNormal = 1UL << 0,
    kCFStringTokenizerTokenHasSubTokensMask = 1UL << 1,
    kCFStringTokenizerTokenHasDerivedSubTokensMask = 1UL << 2,
    kCFStringTokenizerTokenHasHasNumbersMask = 1UL << 3,
    kCFStringTokenizerTokenHasNonLettersMask = 1UL << 4,
    kCFStringTokenizerTokenIsCJWordMask = 1UL << 5,
};
CFTypeID CFStringTokenizerGetTypeID(void);
CFStringTokenizerRef CFStringTokenizerCreate(CFAllocatorRef alloc, CFStringRef string, CFRange range,
                                             CFOptionFlags options, CFLocaleRef locale);
void CFStringTokenizerSetString(CFStringTokenizerRef tokenizer, CFStringRef string, CFRange range);
CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer);
CFStringTokenizerTokenType CFStringTokenizerGoToTokenAtIndex(CFStringTokenizerRef tokenizer, CFIndex index);
CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer);
CFTypeRef CFStringTokenizerCopyCurrentTokenAttribute(CFStringTokenizerRef tokenizer, CFOptionFlags attribute);
CFIndex CFStringTokenizerGetCurrentSubTokens(CFStringTokenizerRef tokenizer, CFRange *ranges, CFIndex maxRangeLength,
                                             CFMutableArrayRef derivedSubTokens);
CFStringRef CFStringTokenizerCopyBestStringLanguage(CFStringRef string, CFRange range);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
