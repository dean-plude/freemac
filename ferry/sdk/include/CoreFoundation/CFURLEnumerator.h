/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: going through the mounted volumes (freemac 1.232, Ferry
 * 0.56.0), written for freemac from Apple's public CFURLEnumerator
 * documentation; not Apple's header. The volumes are those of this
 * system's mount table that hold files (foundation/CFQtCore.m). */
#ifndef _FERRY_CFURLENUMERATOR_H_
#define _FERRY_CFURLENUMERATOR_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
CF_IMPLICIT_BRIDGING_ENABLED
typedef const struct __CFURLEnumerator *CFURLEnumeratorRef;
typedef CF_OPTIONS(CFOptionFlags, CFURLEnumeratorOptions) {
    kCFURLEnumeratorDefaultBehavior = 0,
    kCFURLEnumeratorDescendRecursively = 1UL << 0,
    kCFURLEnumeratorSkipInvisibles = 1UL << 1,
    kCFURLEnumeratorGenerateFileReferenceURLs = 1UL << 2,
    kCFURLEnumeratorSkipPackageContents = 1UL << 3,
    kCFURLEnumeratorIncludeDirectoriesPreOrder = 1UL << 4,
    kCFURLEnumeratorIncludeDirectoriesPostOrder = 1UL << 5,
};
typedef CF_ENUM(CFIndex, CFURLEnumeratorResult) {
    kCFURLEnumeratorSuccess = 1,
    kCFURLEnumeratorEnd = 2,
    kCFURLEnumeratorError = 3,
    kCFURLEnumeratorDirectoryPostOrderSuccess = 4,
};
CFTypeID CFURLEnumeratorGetTypeID(void);
CFURLEnumeratorRef CFURLEnumeratorCreateForMountedVolumes(CFAllocatorRef alloc, CFURLEnumeratorOptions option,
                                                          CFArrayRef propertyKeys);
CFURLEnumeratorResult CFURLEnumeratorGetNextURL(CFURLEnumeratorRef enumerator, CFURLRef *url, CFErrorRef *error);
CF_IMPLICIT_BRIDGING_DISABLED
__FERRY_END
#endif
