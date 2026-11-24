/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSCache (foundation/NSCache.m). Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSCACHE_H_
#define _FERRY_FOUNDATION_NSCACHE_H_
#include <Foundation/Foundation.h>

@protocol NSCacheDelegate;

@protocol NSDiscardableContent
- (BOOL)beginContentAccess;
- (void)endContentAccess;
- (void)discardContentIfPossible;
- (BOOL)isContentDiscarded;
@end

/* Ferry's cache evicts the least recently used objects first once a limit is passed. */
@interface NSCache<KeyType, ObjectType> : NSObject
@property (copy) NSString *name;
@property (assign) id<NSCacheDelegate> delegate;
- (ObjectType)objectForKey:(KeyType)key;
- (void)setObject:(ObjectType)obj forKey:(KeyType)key;
- (void)setObject:(ObjectType)obj forKey:(KeyType)key cost:(NSUInteger)g;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeAllObjects;
@property NSUInteger totalCostLimit;
@property NSUInteger countLimit;
@property BOOL evictsObjectsWithDiscardedContent;
@end

@protocol NSCacheDelegate <NSObject>
@optional
- (void)cache:(NSCache *)cache willEvictObject:(id)obj;
@end

#endif
