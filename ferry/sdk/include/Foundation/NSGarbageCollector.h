/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: garbage collection, which Mac OS X once had and Ferry never
 * runs (freemac 1.219, Ferry 0.43.0). Apps written for both kinds of memory
 * management call these; here there is no collector (+defaultCollector is
 * nil), NSMakeCollectable gives its object back, and the collectable
 * allocations are plain calloc and realloc, freed by the caller's free().
 * Written for freemac from Apple's public documentation. */
#ifndef _FERRY_FOUNDATION_NSGARBAGECOLLECTOR_H_
#define _FERRY_FOUNDATION_NSGARBAGECOLLECTOR_H_
#include <Foundation/Foundation.h>

@interface NSGarbageCollector : NSObject
+ (id)defaultCollector; /* nil: there is no collector */
- (BOOL)isCollecting;
- (BOOL)isEnabled;
- (void)disable;
- (void)enable;
- (void)collectIfNeeded;
- (void)collectExhaustively;
- (void)disableCollectorForPointer:(const void *)ptr;
- (void)enableCollectorForPointer:(const void *)ptr;
- (NSZone *)zone;
@end

enum { NSScannedOption = 1 << 0, NSCollectorDisabledOption = 1 << 1 };
__FERRY_BEGIN
id NSMakeCollectable(CFTypeRef cf);
void *NSAllocateCollectable(NSUInteger size, NSUInteger options);
void *NSReallocateCollectable(void *ptr, NSUInteger size, NSUInteger options);
__FERRY_END
#endif
