/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSUUID (foundation/NSUUID.m). Written for freemac from Apple's
 * public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSUUID_H_
#define _FERRY_FOUNDATION_NSUUID_H_
#include <Foundation/Foundation.h>
#include <uuid/uuid.h>

/* A universally unique identifier: random (version 4, RFC 4122) when made
 * with UUID or init, or read from its string or bytes. */
@interface NSUUID : NSObject <NSCopying, NSSecureCoding>
+ (instancetype FERRY_SWIFT_NONNULL)UUID;
- (instancetype FERRY_SWIFT_NONNULL)init;
- (instancetype)initWithUUIDString:(NSString *)string;
- (instancetype)initWithUUIDBytes:(const unsigned char *)bytes;
- (void)getUUIDBytes:(unsigned char *)uuid;
- (NSComparisonResult)compare:(NSUUID *)otherUUID;
@property (readonly, copy) NSString *UUIDString;
@end

#endif
