/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSUUID, as Apple's NSUUID reference describes it,
 * with RFC 4122's layout and string form (freemac 1.209, Ferry 0.35.0,
 * for Core Data's UUID attributes). A new UUID is version 4: random bytes
 * from arc4random_buf with the version and variant bits set. Strings are
 * written in upper case, as on a Mac, and read in either case. Our own
 * code; no Apple code was used. */
#import "FInternal.h"
#include <Foundation/NSUUID.h>

void arc4random_buf(void *buf, size_t n);

static int hexval(unichar c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

@implementation NSUUID {
    unsigned char _bytes[16];
}
+ (BOOL)supportsSecureCoding { return YES; }
+ (instancetype)UUID { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        arc4random_buf(_bytes, 16);
        _bytes[6] = (_bytes[6] & 0x0f) | 0x40;
        _bytes[8] = (_bytes[8] & 0x3f) | 0x80;
    }
    return self;
}
- (instancetype)initWithUUIDBytes:(const unsigned char *)bytes
{
    if ((self = [super init]) && bytes)
        memcpy(_bytes, bytes, 16);
    return self;
}
- (instancetype)initWithUUIDString:(NSString *)string
{
    if (![string isKindOfClass:[NSString class]] || [string length] != 36) {
        [self release];
        return nil;
    }
    unsigned char b[16];
    NSUInteger k = 0;
    for (NSUInteger i = 0; i < 36;) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            if ([string characterAtIndex:i] != '-') {
                [self release];
                return nil;
            }
            i++;
            continue;
        }
        int hi = hexval([string characterAtIndex:i]), lo = hexval([string characterAtIndex:i + 1]);
        if (hi < 0 || lo < 0) {
            [self release];
            return nil;
        }
        b[k++] = (unsigned char)(hi << 4 | lo);
        i += 2;
    }
    return [self initWithUUIDBytes:b];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSUInteger n = 0;
    const uint8_t *b = [coder decodeBytesForKey:@"NS.uuidbytes" returnedLength:&n];
    if (!b || n != 16) {
        [self release];
        return nil;
    }
    return [self initWithUUIDBytes:b];
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeBytes:_bytes length:16 forKey:@"NS.uuidbytes"]; }
- (void)getUUIDBytes:(unsigned char *)uuid { memcpy(uuid, _bytes, 16); }
- (NSString *)UUIDString
{
    const unsigned char *b = _bytes;
    return [NSString stringWithFormat:@"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X", b[0],
                                      b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13],
                                      b[14], b[15]];
}
- (NSString *)description { return [self UUIDString]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSUUID class]])
        return NO;
    unsigned char b[16];
    [other getUUIDBytes:b];
    return memcmp(b, _bytes, 16) == 0;
}
- (NSUInteger)hash
{
    NSUInteger h;
    memcpy(&h, _bytes, sizeof h);
    return h;
}
- (NSComparisonResult)compare:(NSUUID *)other
{
    unsigned char b[16];
    [other getUUIDBytes:b];
    int c = memcmp(_bytes, b, 16);
    return c < 0 ? NSOrderedAscending : c > 0 ? NSOrderedDescending : NSOrderedSame;
}
@end
