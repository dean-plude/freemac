/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreFoundation's sets and bags (freemac 1.220, Ferry 0.44.0),
 * written for freemac from Apple's public API documentation of CFSet and
 * CFBag; not Apple's header. Included by <CoreFoundation/CoreFoundation.h>.
 *
 * A set made with kCFTypeSetCallBacks is an NSSet (an NSMutableSet when
 * mutable). One made with other callbacks, or none (plain pointers, told
 * apart by their values), holds values that may not be objects and calls
 * the callbacks to keep, compare, hash and describe them, as a bag always
 * does; a bag holds each value with a count. */
#ifndef _FERRY_CFSET_H_
#define _FERRY_CFSET_H_

__FERRY_BEGIN
typedef const struct __CFSet *CFSetRef;
typedef struct __CFSet *CFMutableSetRef;
typedef const struct __CFBag *CFBagRef;
typedef struct __CFBag *CFMutableBagRef;

typedef const void *(*CFSetRetainCallBack)(CFAllocatorRef allocator, const void *value);
typedef void (*CFSetReleaseCallBack)(CFAllocatorRef allocator, const void *value);
typedef CFStringRef (*CFSetCopyDescriptionCallBack)(const void *value);
typedef Boolean (*CFSetEqualCallBack)(const void *value1, const void *value2);
typedef CFHashCode (*CFSetHashCallBack)(const void *value);
typedef struct {
    CFIndex version;
    CFSetRetainCallBack retain;
    CFSetReleaseCallBack release;
    CFSetCopyDescriptionCallBack copyDescription;
    CFSetEqualCallBack equal;
    CFSetHashCallBack hash;
} CFSetCallBacks;
extern const CFSetCallBacks kCFTypeSetCallBacks;
extern const CFSetCallBacks kCFCopyStringSetCallBacks;
typedef void (*CFSetApplierFunction)(const void *value, void *context);

CFTypeID CFSetGetTypeID(void);
CFSetRef CFSetCreate(CFAllocatorRef alloc, const void **values, CFIndex count, const CFSetCallBacks *callBacks);
CFSetRef CFSetCreateCopy(CFAllocatorRef alloc, CFSetRef set);
CFMutableSetRef CFSetCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const CFSetCallBacks *callBacks);
CFMutableSetRef CFSetCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFSetRef set);
CFIndex CFSetGetCount(CFSetRef set);
CFIndex CFSetGetCountOfValue(CFSetRef set, const void *value);
Boolean CFSetContainsValue(CFSetRef set, const void *value);
const void *CFSetGetValue(CFSetRef set, const void *value);
Boolean CFSetGetValueIfPresent(CFSetRef set, const void *candidate, const void **value);
void CFSetGetValues(CFSetRef set, const void **values);
void CFSetApplyFunction(CFSetRef set, CFSetApplierFunction applier, void *context);
void CFSetAddValue(CFMutableSetRef set, const void *value);
void CFSetReplaceValue(CFMutableSetRef set, const void *value);
void CFSetSetValue(CFMutableSetRef set, const void *value);
void CFSetRemoveValue(CFMutableSetRef set, const void *value);
void CFSetRemoveAllValues(CFMutableSetRef set);

typedef CFSetRetainCallBack CFBagRetainCallBack;
typedef CFSetReleaseCallBack CFBagReleaseCallBack;
typedef CFSetCopyDescriptionCallBack CFBagCopyDescriptionCallBack;
typedef CFSetEqualCallBack CFBagEqualCallBack;
typedef CFSetHashCallBack CFBagHashCallBack;
typedef struct {
    CFIndex version;
    CFBagRetainCallBack retain;
    CFBagReleaseCallBack release;
    CFBagCopyDescriptionCallBack copyDescription;
    CFBagEqualCallBack equal;
    CFBagHashCallBack hash;
} CFBagCallBacks;
extern const CFBagCallBacks kCFTypeBagCallBacks;
extern const CFBagCallBacks kCFCopyStringBagCallBacks;
typedef void (*CFBagApplierFunction)(const void *value, void *context);

CFTypeID CFBagGetTypeID(void);
CFBagRef CFBagCreate(CFAllocatorRef alloc, const void **values, CFIndex count, const CFBagCallBacks *callBacks);
CFBagRef CFBagCreateCopy(CFAllocatorRef alloc, CFBagRef bag);
CFMutableBagRef CFBagCreateMutable(CFAllocatorRef alloc, CFIndex capacity, const CFBagCallBacks *callBacks);
CFMutableBagRef CFBagCreateMutableCopy(CFAllocatorRef alloc, CFIndex capacity, CFBagRef bag);
CFIndex CFBagGetCount(CFBagRef bag);              /* every value, as many times as it is held */
CFIndex CFBagGetCountOfValue(CFBagRef bag, const void *value);
Boolean CFBagContainsValue(CFBagRef bag, const void *value);
const void *CFBagGetValue(CFBagRef bag, const void *value);
Boolean CFBagGetValueIfPresent(CFBagRef bag, const void *candidate, const void **value);
void CFBagGetValues(CFBagRef bag, const void **values);    /* each value as many times as it is held */
void CFBagApplyFunction(CFBagRef bag, CFBagApplierFunction applier, void *context);
void CFBagAddValue(CFMutableBagRef bag, const void *value);
void CFBagReplaceValue(CFMutableBagRef bag, const void *value);
void CFBagSetValue(CFMutableBagRef bag, const void *value);
void CFBagRemoveValue(CFMutableBagRef bag, const void *value);   /* once */
void CFBagRemoveAllValues(CFMutableBagRef bag);
__FERRY_END

#endif
