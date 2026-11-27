/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Foundation and SystemConfiguration calls that Chromium makes at
 * start (freemac 1.265, Ferry 0.88.0; first seen in Obsidian), from Apple's
 * public documentation of each:
 *
 * - CFBinaryHeap: a priority queue, ordered by the heap's compare callback.
 * - CFStringTokenizer: words (runs of letters and digits), word
 *   boundaries, sentences, paragraphs and line-break opportunities.
 *   Ferry has no dictionaries, so words in scripts written without spaces
 *   (Chinese, Japanese, Thai) come out as whole runs.
 * - CFCharacterSetCreateBitmapRepresentation, CFAllocatorCreate (kept, as
 *   the other allocators are: Ferry's memory always comes from malloc).
 * - Hyphenation: none is available, as on a Mac without its dictionaries.
 * - SCDynamicStore: a store with the keys Chromium watches. The proxies
 *   are SCDynamicStoreCopyProxies' (SystemConfiguration.m); other keys
 *   have no value, and no change is ever reported, as the network isn't
 *   watched here.
 * - A few private-to-Apple calls Chromium declares itself:
 *   _CSCheckFixDisable, _LSSetApplicationLaunchServicesServerConnectionStatus.
 */
#import "FInternal.h"
#include <SystemConfiguration/SystemConfiguration.h>

/* ---- allocators ---------------------------------------------------------------------- */

@interface FAllocator : NSObject {
@public
    CFAllocatorContext context;
}
@end
@implementation FAllocator
- (void)dealloc
{
    if (context.release && context.info)
        context.release(context.info);
    [super dealloc];
}
@end

CFAllocatorRef CFAllocatorCreate(CFAllocatorRef allocator, CFAllocatorContext *context)
{
    (void)allocator;
    FAllocator *a = [[FAllocator alloc] init];
    if (context) {
        a->context = *context;
        if (context->retain && context->info)
            a->context.info = (void *)context->retain(context->info);
    }
    return (CFAllocatorRef)a;
}

void CFAllocatorGetContext(CFAllocatorRef allocator, CFAllocatorContext *context)
{
    if (!context)
        return;
    if ([(id)allocator isKindOfClass:[FAllocator class]])
        *context = ((FAllocator *)allocator)->context;
    else
        memset(context, 0, sizeof *context);
}

/* ---- binary heaps -------------------------------------------------------------------- */

@interface FBinaryHeap : NSObject {
@public
    CFBinaryHeapCallBacks cb;
    CFBinaryHeapCompareContext cmp;
    const void **v;
    CFIndex n, cap;
}
@end
@implementation FBinaryHeap
- (CFTypeID)_ferryCFTypeID { return CFBinaryHeapGetTypeID(); }
- (void)dealloc
{
    for (CFIndex i = 0; i < n; i++)
        if (cb.release)
            cb.release(NULL, v[i]);
    free(v);
    if (cmp.release && cmp.info)
        cmp.release(cmp.info);
    [super dealloc];
}
@end

#define HEAP(h) ((FBinaryHeap *)(h))

CFTypeID CFBinaryHeapGetTypeID(void) { return 0x46520030; }

static CFComparisonResult heap_compare(FBinaryHeap *h, const void *a, const void *b)
{
    if (h->cb.compare)
        return h->cb.compare(a, b, h->cmp.info);
    return a < b ? kCFCompareLessThan : a > b ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

CFBinaryHeapRef CFBinaryHeapCreate(CFAllocatorRef allocator, CFIndex capacity, const CFBinaryHeapCallBacks *callBacks,
                                   const CFBinaryHeapCompareContext *compareContext)
{
    (void)allocator;
    (void)capacity;
    FBinaryHeap *h = [[FBinaryHeap alloc] init];
    if (callBacks)
        h->cb = *callBacks;
    if (compareContext) {
        h->cmp = *compareContext;
        if (compareContext->retain && compareContext->info)
            h->cmp.info = (void *)compareContext->retain(compareContext->info);
    }
    return (CFBinaryHeapRef)h;
}

void CFBinaryHeapAddValue(CFBinaryHeapRef heap, const void *value)
{
    FBinaryHeap *h = HEAP(heap);
    if (h->n == h->cap) {
        CFIndex c = h->cap ? h->cap * 2 : 16;
        const void **nv = realloc(h->v, (size_t)c * sizeof *nv);
        if (!nv)
            return;
        h->v = nv;
        h->cap = c;
    }
    if (h->cb.retain)
        value = h->cb.retain(NULL, value);
    CFIndex i = h->n++;
    while (i > 0) {
        CFIndex parent = (i - 1) / 2;
        if (heap_compare(h, h->v[parent], value) != kCFCompareGreaterThan)
            break;
        h->v[i] = h->v[parent];
        i = parent;
    }
    h->v[i] = value;
}

CFIndex CFBinaryHeapGetCount(CFBinaryHeapRef heap) { return HEAP(heap)->n; }

const void *CFBinaryHeapGetMinimum(CFBinaryHeapRef heap) { return HEAP(heap)->n ? HEAP(heap)->v[0] : NULL; }

Boolean CFBinaryHeapGetMinimumIfPresent(CFBinaryHeapRef heap, const void **value)
{
    if (!HEAP(heap)->n)
        return false;
    if (value)
        *value = HEAP(heap)->v[0];
    return true;
}

void CFBinaryHeapRemoveMinimumValue(CFBinaryHeapRef heap)
{
    FBinaryHeap *h = HEAP(heap);
    if (!h->n)
        return;
    if (h->cb.release)
        h->cb.release(NULL, h->v[0]);
    const void *last = h->v[--h->n];
    CFIndex i = 0;
    for (;;) {
        CFIndex c = 2 * i + 1;
        if (c >= h->n)
            break;
        if (c + 1 < h->n && heap_compare(h, h->v[c + 1], h->v[c]) == kCFCompareLessThan)
            c++;
        if (heap_compare(h, last, h->v[c]) != kCFCompareGreaterThan)
            break;
        h->v[i] = h->v[c];
        i = c;
    }
    if (h->n)
        h->v[i] = last;
}

Boolean CFBinaryHeapContainsValue(CFBinaryHeapRef heap, const void *value)
{
    FBinaryHeap *h = HEAP(heap);
    for (CFIndex i = 0; i < h->n; i++)
        if (heap_compare(h, h->v[i], value) == kCFCompareEqualTo)
            return true;
    return false;
}

void CFBinaryHeapRemoveAllValues(CFBinaryHeapRef heap)
{
    while (HEAP(heap)->n)
        CFBinaryHeapRemoveMinimumValue(heap);
}

/* the values in order, smallest first */
void CFBinaryHeapGetValues(CFBinaryHeapRef heap, const void **values)
{
    FBinaryHeap *h = HEAP(heap);
    const void **copy = malloc((size_t)(h->n ? h->n : 1) * sizeof *copy);
    if (!copy)
        return;
    memcpy(copy, h->v, (size_t)h->n * sizeof *copy);
    CFIndex n = h->n;
    for (CFIndex k = 0; k < n; k++) {
        CFIndex best = k;
        for (CFIndex j = k + 1; j < n; j++)
            if (heap_compare(h, copy[j], copy[best]) == kCFCompareLessThan)
                best = j;
        const void *t = copy[k];
        copy[k] = copy[best];
        copy[best] = t;
        values[k] = copy[k];
    }
    free(copy);
}

/* ---- character sets as bitmaps ---------------------------------------------------- */

/* The Basic Multilingual Plane, a bit for each character (8192 bytes). */
CFDataRef CFCharacterSetCreateBitmapRepresentation(CFAllocatorRef allocator, CFCharacterSetRef set)
{
    (void)allocator;
    NSMutableData *d = [[NSMutableData alloc] initWithLength:8192];
    uint8_t *b = [d mutableBytes];
    NSCharacterSet *s = (NSCharacterSet *)set;
    for (unsigned c = 0; c < 65536; c++)
        if ([s characterIsMember:(unichar)c])
            b[c >> 3] |= (uint8_t)(1u << (c & 7));
    return (CFDataRef)d;
}

/* ---- hyphenation -------------------------------------------------------------------- */

Boolean CFStringIsHyphenationAvailableForLocale(CFLocaleRef locale)
{
    (void)locale;
    return false;
}

CFIndex CFStringGetHyphenationLocationBeforeIndex(CFStringRef string, CFIndex location, CFRange limitRange,
                                                  CFOptionFlags options, CFLocaleRef locale, UTF32Char *character)
{
    (void)string; (void)location; (void)limitRange; (void)options; (void)locale;
    if (character)
        *character = 0;
    return kCFNotFound;
}

/* ---- string tokenizers -------------------------------------------------------------- */

@interface FTokenizer : NSObject {
@public
    NSString *string;
    CFRange range;
    CFOptionFlags unit;
    CFRange token;
    CFIndex next;
}
@end
@implementation FTokenizer
- (void)dealloc
{
    [string release];
    [super dealloc];
}
@end

static BOOL is_word_char(unichar c)
{
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c] || c == '_' || c == '\'';
}
static BOOL is_space(unichar c) { return [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]; }

CFStringTokenizerRef CFStringTokenizerCreate(CFAllocatorRef alloc, CFStringRef string, CFRange range,
                                             CFOptionFlags options, CFLocaleRef locale)
{
    (void)alloc;
    (void)locale;
    FTokenizer *t = [[FTokenizer alloc] init];
    t->string = [(NSString *)string copy];
    t->range = range;
    t->unit = options & 0xff;
    t->next = range.location;
    t->token = CFRangeMake(kCFNotFound, 0);
    return (CFStringTokenizerRef)t;
}

void CFStringTokenizerSetString(CFStringTokenizerRef tokenizer, CFStringRef string, CFRange range)
{
    FTokenizer *t = (FTokenizer *)tokenizer;
    [t->string release];
    t->string = [(NSString *)string copy];
    t->range = range;
    t->next = range.location;
    t->token = CFRangeMake(kCFNotFound, 0);
}

/* the token starting at or after i, by the tokenizer's unit */
static CFStringTokenizerTokenType token_from(FTokenizer *t, CFIndex i)
{
    NSString *s = t->string;
    CFIndex end = t->range.location + t->range.length;
    if ((NSUInteger)end > [s length])
        end = (CFIndex)[s length];
    CFIndex start;
    switch (t->unit) {
    case kCFStringTokenizerUnitWordBoundary:
        if (i >= end)
            return kCFStringTokenizerTokenNone;
        start = i;
        if (is_word_char([s characterAtIndex:i]))
            while (i < end && is_word_char([s characterAtIndex:i]))
                i++;
        else
            i++;
        break;
    case kCFStringTokenizerUnitSentence:
        while (i < end && is_space([s characterAtIndex:i]))
            i++;
        if (i >= end)
            return kCFStringTokenizerTokenNone;
        start = i;
        while (i < end) {
            unichar c = [s characterAtIndex:i++];
            if ((c == '.' || c == '!' || c == '?') && (i >= end || is_space([s characterAtIndex:i]))) {
                while (i < end && is_space([s characterAtIndex:i]))
                    i++;
                break;
            }
        }
        break;
    case kCFStringTokenizerUnitParagraph:
        if (i >= end)
            return kCFStringTokenizerTokenNone;
        start = i;
        while (i < end && [s characterAtIndex:i] != '\n')
            i++;
        if (i < end)
            i++;
        break;
    case kCFStringTokenizerUnitLineBreak:
        if (i >= end)
            return kCFStringTokenizerTokenNone;
        start = i;
        while (i < end && !is_space([s characterAtIndex:i]))
            i++;
        while (i < end && is_space([s characterAtIndex:i]))
            i++;
        break;
    default: /* words */
        while (i < end && !is_word_char([s characterAtIndex:i]))
            i++;
        if (i >= end)
            return kCFStringTokenizerTokenNone;
        start = i;
        while (i < end && is_word_char([s characterAtIndex:i]))
            i++;
        break;
    }
    t->token = CFRangeMake(start, i - start);
    t->next = i;
    BOOL digits = YES, letters = NO;
    for (CFIndex k = start; k < i; k++) {
        unichar c = [s characterAtIndex:k];
        digits &= c >= '0' && c <= '9';
        letters |= is_word_char(c);
    }
    CFStringTokenizerTokenType type = kCFStringTokenizerTokenNormal;
    if (t->unit == kCFStringTokenizerUnitWord || t->unit == kCFStringTokenizerUnitWordBoundary) {
        if (digits)
            type |= kCFStringTokenizerTokenHasHasNumbersMask;
        else if (!letters)
            type |= kCFStringTokenizerTokenHasNonLettersMask; /* punctuation */
    }
    return type;
}

CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer)
{
    FTokenizer *t = (FTokenizer *)tokenizer;
    CFStringTokenizerTokenType type = token_from(t, t->next);
    if (type == kCFStringTokenizerTokenNone)
        t->token = CFRangeMake(kCFNotFound, 0);
    return type;
}

CFStringTokenizerTokenType CFStringTokenizerGoToTokenAtIndex(CFStringTokenizerRef tokenizer, CFIndex index)
{
    FTokenizer *t = (FTokenizer *)tokenizer;
    for (CFIndex i = t->range.location;;) {
        CFStringTokenizerTokenType type = token_from(t, i);
        if (type == kCFStringTokenizerTokenNone || t->token.location > index) {
            t->token = CFRangeMake(kCFNotFound, 0);
            return kCFStringTokenizerTokenNone;
        }
        if (index < t->token.location + t->token.length)
            return type;
        i = t->next;
    }
}

CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer)
{
    return ((FTokenizer *)tokenizer)->token;
}

CFTypeRef CFStringTokenizerCopyCurrentTokenAttribute(CFStringTokenizerRef tokenizer, CFOptionFlags attribute)
{
    (void)tokenizer;
    (void)attribute;
    return NULL;
}

CFIndex CFStringTokenizerGetCurrentSubTokens(CFStringTokenizerRef tokenizer, CFRange *ranges, CFIndex maxRangeLength,
                                             CFMutableArrayRef derivedSubTokens)
{
    (void)tokenizer; (void)ranges; (void)maxRangeLength; (void)derivedSubTokens;
    return 0;
}

/* The language of the text: the user's own when nothing better is known. */
CFStringRef CFStringTokenizerCopyBestStringLanguage(CFStringRef string, CFRange range)
{
    (void)string;
    (void)range;
    NSString *lang = [[NSLocale preferredLanguages] firstObject];
    if (!lang)
        return NULL;
    NSRange dash = [lang rangeOfString:@"-"];
    return (CFStringRef)[(dash.location == NSNotFound ? lang : [lang substringToIndex:dash.location]) copy];
}

CFTypeID CFStringTokenizerGetTypeID(void) { return (CFTypeID)[FTokenizer class]; }

/* ---- Apple's private calls that Chromium declares ------------------------------------- */

int _CSCheckFixDisable(void) { return 0; }
void _LSSetApplicationLaunchServicesServerConnectionStatus(uint64_t flags, void *block)
{
    (void)flags;
    (void)block;
}
const CFStringRef _kCFBundleNumericVersionKey = (CFStringRef)@"CFBundleNumericVersion";

/* ---- the dynamic store ------------------------------------------------------------------ */

const CFStringRef kSCDynamicStoreDomainState = (CFStringRef)@"State:";
const CFStringRef kSCDynamicStoreDomainSetup = (CFStringRef)@"Setup:";
const CFStringRef kSCDynamicStoreDomainFile = (CFStringRef)@"File:";
const CFStringRef kSCDynamicStoreDomainPlugin = (CFStringRef)@"Plugin:";
const CFStringRef kSCDynamicStoreDomainPrefs = (CFStringRef)@"Prefs:";
const CFStringRef kSCCompNetwork = (CFStringRef)@"Network";
const CFStringRef kSCCompGlobal = (CFStringRef)@"Global";
const CFStringRef kSCCompService = (CFStringRef)@"Service";
const CFStringRef kSCCompInterface = (CFStringRef)@"Interface";
const CFStringRef kSCCompAnyRegex = (CFStringRef)@"[^/]+";
const CFStringRef kSCEntNetIPv4 = (CFStringRef)@"IPv4";
const CFStringRef kSCEntNetIPv6 = (CFStringRef)@"IPv6";
const CFStringRef kSCEntNetDNS = (CFStringRef)@"DNS";
const CFStringRef kSCEntNetProxies = (CFStringRef)@"Proxies";
const CFStringRef kSCEntNetInterface = (CFStringRef)@"Interface";
const CFStringRef kSCEntNetLink = (CFStringRef)@"Link";
const CFStringRef kSCEntNetAirPort = (CFStringRef)@"AirPort";
const CFStringRef kSCPropNetIPv4Addresses = (CFStringRef)@"Addresses";
const CFStringRef kSCPropNetIPv6Addresses = (CFStringRef)@"Addresses";
const CFStringRef kSCPropNetInterfaces = (CFStringRef)@"Interfaces";
const CFStringRef kSCPropInterfaceName = (CFStringRef)@"InterfaceName";
const CFStringRef kSCPropNetDNSServerAddresses = (CFStringRef)@"ServerAddresses";
const CFStringRef kSCPropNetDNSSearchDomains = (CFStringRef)@"SearchDomains";
const CFStringRef kSCPropNetDNSDomainName = (CFStringRef)@"DomainName";
const CFStringRef kSCDynamicStorePropNetPrimaryInterface = (CFStringRef)@"PrimaryInterface";
const CFStringRef kSCDynamicStorePropNetPrimaryService = (CFStringRef)@"PrimaryService";

@interface FDynamicStore : NSObject {
@public
    SCDynamicStoreCallBack callout;
    SCDynamicStoreContext context;
}
@end
@implementation FDynamicStore
- (CFTypeID)_ferryCFTypeID { return SCDynamicStoreGetTypeID(); }
- (void)dealloc
{
    if (context.release && context.info)
        context.release(context.info);
    [super dealloc];
}
@end

CFTypeID SCDynamicStoreGetTypeID(void) { return 0x46520031; }

SCDynamicStoreRef SCDynamicStoreCreate(CFAllocatorRef allocator, CFStringRef name, SCDynamicStoreCallBack callout,
                                       SCDynamicStoreContext *context)
{
    (void)allocator;
    (void)name;
    FDynamicStore *s = [[FDynamicStore alloc] init];
    s->callout = callout;
    if (context) {
        s->context = *context;
        if (context->retain && context->info)
            s->context.info = (void *)context->retain(context->info);
    }
    return (SCDynamicStoreRef)s;
}

SCDynamicStoreRef SCDynamicStoreCreateWithOptions(CFAllocatorRef allocator, CFStringRef name,
                                                  CFDictionaryRef options, SCDynamicStoreCallBack callout,
                                                  SCDynamicStoreContext *context)
{
    (void)options;
    return SCDynamicStoreCreate(allocator, name, callout, context);
}

CFStringRef SCDynamicStoreKeyCreateNetworkGlobalEntity(CFAllocatorRef allocator, CFStringRef domain, CFStringRef entity)
{
    (void)allocator;
    return (CFStringRef)[[NSString alloc] initWithFormat:@"%@/Network/Global/%@", domain, entity];
}

CFStringRef SCDynamicStoreKeyCreateNetworkInterfaceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                          CFStringRef ifname, CFStringRef entity)
{
    (void)allocator;
    return (CFStringRef)[[NSString alloc]
        initWithFormat:entity ? @"%@/Network/Interface/%@/%@" : @"%@/Network/Interface/%@", domain, ifname, entity];
}

CFStringRef SCDynamicStoreKeyCreateNetworkServiceEntity(CFAllocatorRef allocator, CFStringRef domain,
                                                        CFStringRef serviceID, CFStringRef entity)
{
    (void)allocator;
    return (CFStringRef)[[NSString alloc]
        initWithFormat:entity ? @"%@/Network/Service/%@/%@" : @"%@/Network/Service/%@", domain, serviceID, entity];
}

CFStringRef SCDynamicStoreKeyCreateProxies(CFAllocatorRef allocator)
{
    return SCDynamicStoreKeyCreateNetworkGlobalEntity(allocator, kSCDynamicStoreDomainState, kSCEntNetProxies);
}

CFPropertyListRef SCDynamicStoreCopyValue(SCDynamicStoreRef store, CFStringRef key)
{
    if ([(NSString *)key isEqualToString:@"State:/Network/Global/Proxies"])
        return SCDynamicStoreCopyProxies(store);
    return NULL;
}

CFDictionaryRef SCDynamicStoreCopyMultiple(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns)
{
    NSMutableDictionary *d = [[NSMutableDictionary alloc] init];
    for (NSString *k in (NSArray *)keys) {
        id v = (id)SCDynamicStoreCopyValue(store, (CFStringRef)k);
        if (v) {
            d[k] = v;
            [v release];
        }
    }
    (void)patterns;
    return (CFDictionaryRef)d;
}

CFArrayRef SCDynamicStoreCopyKeyList(SCDynamicStoreRef store, CFStringRef pattern)
{
    (void)store;
    (void)pattern;
    return (CFArrayRef)[[NSArray alloc] init];
}

Boolean SCDynamicStoreSetNotificationKeys(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns)
{
    (void)keys;
    (void)patterns;
    return store != NULL;
}

Boolean SCDynamicStoreSetDispatchQueue(SCDynamicStoreRef store, void *queue)
{
    (void)queue;
    return store != NULL;
}

static void store_source_perform(void *info) { (void)info; }

CFRunLoopSourceRef SCDynamicStoreCreateRunLoopSource(CFAllocatorRef allocator, SCDynamicStoreRef store, CFIndex order)
{
    if (!store)
        return NULL;
    CFRunLoopSourceContext c = {0};
    c.perform = store_source_perform;
    return CFRunLoopSourceCreate(allocator, order, &c);
}

int SCError(void) { return 0; }

CFStringRef SCErrorString(int status) { return (CFStringRef)(status ? @"Failed!" : @"Success!"); }
