/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSData and NSMutableData, a byte buffer each. */
#import "FInternal.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

@interface FData : NSMutableData {
@public
    unsigned char *_bytes;
    NSUInteger _len, _cap;
    BOOL _mutable, _free;
}
@end

@implementation NSData
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSData class] || self == [NSMutableData class]) {
        FData *d = [FData allocWithZone:zone];
        d->_mutable = self == [NSMutableData class];
        return (id)d;
    }
    return [super allocWithZone:zone];
}
+ (instancetype)data { return [[[self alloc] init] autorelease]; }
+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length
{
    return [[[self alloc] initWithBytes:bytes length:length] autorelease];
}
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
{
    return [[[self alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:YES] autorelease];
}
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b
{
    return [[[self alloc] initWithBytesNoCopy:bytes length:length freeWhenDone:b] autorelease];
}
+ (instancetype)dataWithContentsOfFile:(NSString *)path
{
    return [[[self alloc] initWithContentsOfFile:path] autorelease];
}
+ (instancetype)dataWithContentsOfFile:(NSString *)path options:(NSUInteger)opts error:(NSError **)error
{
    id d = [[[self alloc] initWithContentsOfFile:path] autorelease];
    if (!d)
        FSetError(error, FPosixError(errno, path));
    return d;
}
+ (instancetype)dataWithContentsOfURL:(NSURL *)url
{
    return [url isFileURL] ? [self dataWithContentsOfFile:[url path]] : nil;
}
+ (instancetype)dataWithData:(NSData *)data { return [[[self alloc] initWithData:data] autorelease]; }
- (instancetype)init { return [self initWithBytes:NULL length:0]; }
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length { return self; }
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b { return self; }
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length
{
    return [self initWithBytesNoCopy:bytes length:length freeWhenDone:YES];
}
- (instancetype)initWithData:(NSData *)data { return [self initWithBytes:[data bytes] length:[data length]]; }
- (instancetype)initWithContentsOfFile:(NSString *)path
{
    int fd = open([path fileSystemRepresentation], O_RDONLY);
    if (fd < 0) {
        [self release];
        return nil;
    }
    struct stat st;
    size_t cap = fstat(fd, &st) == 0 && st.st_size > 0 ? (size_t)st.st_size : 4096, len = 0;
    unsigned char *buf = malloc(cap + 1);
    for (;;) {
        if (len == cap) {
            cap *= 2;
            buf = realloc(buf, cap + 1);
        }
        ssize_t got = read(fd, buf + len, cap - len);
        if (got < 0) {
            int e = errno;
            close(fd);
            free(buf);
            [self release];
            errno = e;
            return nil;
        }
        if (got == 0)
            break;
        len += got;
    }
    close(fd);
    return [self initWithBytesNoCopy:buf length:len freeWhenDone:YES];
}
- (NSUInteger)length { return 0; }
- (const void *)bytes { return NULL; }
- (id)copyWithZone:(NSZone *)zone { return [[NSData allocWithZone:zone] initWithData:self]; }
- (id)mutableCopyWithZone:(NSZone *)zone { return [[NSMutableData allocWithZone:zone] initWithData:self]; }
- (void)getBytes:(void *)buffer length:(NSUInteger)length
{
    NSUInteger n = [self length];
    memcpy(buffer, [self bytes], length < n ? length : n);
}
- (void)getBytes:(void *)buffer range:(NSRange)range
{
    if (NSMaxRange(range) > [self length])
        FRaise(NSRangeException, @"*** -[NSData getBytes:range:]: range {%lu, %lu} exceeds data length %lu",
               (unsigned long)range.location, (unsigned long)range.length, (unsigned long)[self length]);
    memcpy(buffer, (const char *)[self bytes] + range.location, range.length);
}
- (NSData *)subdataWithRange:(NSRange)range
{
    if (NSMaxRange(range) > [self length])
        FRaise(NSRangeException, @"*** -[NSData subdataWithRange:]: range {%lu, %lu} exceeds data length %lu",
               (unsigned long)range.location, (unsigned long)range.length, (unsigned long)[self length]);
    return [NSData dataWithBytes:(const char *)[self bytes] + range.location length:range.length];
}
- (NSRange)rangeOfData:(NSData *)needle options:(NSUInteger)opts range:(NSRange)range
{
    const unsigned char *h = [self bytes], *n = [needle bytes];
    NSUInteger nl = [needle length];
    if (nl == 0 || nl > range.length)
        return NSMakeRange(NSNotFound, 0);
    for (NSUInteger i = range.location; i + nl <= NSMaxRange(range); i++)
        if (memcmp(h + i, n, nl) == 0)
            return NSMakeRange(i, nl);
    return NSMakeRange(NSNotFound, 0);
}
- (BOOL)isEqualToData:(NSData *)other
{
    return [other length] == [self length] && memcmp([other bytes], [self bytes], [self length]) == 0;
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[NSData class]] && [self isEqualToData:other]; }
- (NSUInteger)hash
{
    const unsigned char *b = [self bytes];
    NSUInteger n = [self length], h = n;
    for (NSUInteger i = 0; i < n && i < 80; i++)
        h = h * 31 + b[i];
    return h;
}
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)opts error:(NSError **)error
{
    const char *fs = [path fileSystemRepresentation];
    char *tmp = NULL;
    const char *target = fs;
    if (opts & NSDataWritingAtomic) {
        asprintf(&tmp, "%s.ferry-%d", fs, (int)getpid());
        target = tmp;
    }
    int fd = open(target, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0)
        goto fail;
    const unsigned char *p = [self bytes];
    NSUInteger left = [self length];
    while (left) {
        ssize_t put = write(fd, p, left);
        if (put < 0) {
            int e = errno;
            close(fd);
            errno = e;
            goto fail;
        }
        p += put;
        left -= put;
    }
    if (close(fd) != 0)
        goto fail;
    if (tmp && rename(tmp, fs) != 0)
        goto fail;
    free(tmp);
    return YES;
fail:;
    int e = errno;
    if (tmp)
        unlink(tmp);
    free(tmp);
    FSetError(error, FPosixError(e, path));
    return NO;
}
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically
{
    return [self writeToFile:path options:atomically ? NSDataWritingAtomic : 0 error:NULL];
}
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically
{
    return [url isFileURL] && [self writeToFile:[url path] atomically:atomically];
}
- (NSString *)description
{
    const unsigned char *b = [self bytes];
    NSUInteger n = [self length];
    NSMutableString *s = [NSMutableString stringWithString:@"<"];
    for (NSUInteger i = 0; i < n; i++) {
        if (i && i % 4 == 0)
            [s appendString:@" "];
        [s appendFormat:@"%02x", b[i]];
    }
    [s appendString:@">"];
    return s;
}
- (NSString *)base64EncodedStringWithOptions:(NSUInteger)opts
{
    static const char abc[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const unsigned char *b = [self bytes];
    NSUInteger n = [self length], k = 0;
    char *out = malloc((n + 2) / 3 * 4 + 1);
    for (NSUInteger i = 0; i < n; i += 3) {
        unsigned v = b[i] << 16 | (i + 1 < n ? b[i + 1] << 8 : 0) | (i + 2 < n ? b[i + 2] : 0);
        out[k++] = abc[v >> 18];
        out[k++] = abc[(v >> 12) & 63];
        out[k++] = i + 1 < n ? abc[(v >> 6) & 63] : '=';
        out[k++] = i + 2 < n ? abc[v & 63] : '=';
    }
    NSString *s = FStringFromUTF8(out, k);
    free(out);
    return s;
}
- (instancetype)initWithBase64EncodedString:(NSString *)str options:(NSUInteger)opts
{
    const char *s = [str UTF8String];
    size_t n = strlen(s), k = 0;
    unsigned char *out = malloc(n / 4 * 3 + 3);
    unsigned v = 0;
    int bits = 0;
    for (size_t i = 0; i < n; i++) {
        const char *at = strchr("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", s[i]);
        if (s[i] == '=' || isspace((unsigned char)s[i]))
            continue;
        if (!at || !s[i]) {
            free(out);
            [self release];
            return nil;
        }
        v = v << 6 | (unsigned)(at - "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[k++] = (v >> bits) & 0xff;
        }
    }
    return [self initWithBytesNoCopy:out length:k freeWhenDone:YES];
}
@end

@implementation NSMutableData
+ (instancetype)dataWithCapacity:(NSUInteger)capacity { return [[[self alloc] initWithCapacity:capacity] autorelease]; }
+ (instancetype)dataWithLength:(NSUInteger)length { return [[[self alloc] initWithLength:length] autorelease]; }
- (instancetype)initWithCapacity:(NSUInteger)capacity { return [self init]; }
- (instancetype)initWithLength:(NSUInteger)length
{
    self = [self init];
    [self setLength:length];
    return self;
}
- (void *)mutableBytes { return NULL; }
- (void)setLength:(NSUInteger)length {}
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length {}
- (void)appendData:(NSData *)data { [self appendBytes:[data bytes] length:[data length]]; }
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes
{
    if (NSMaxRange(range) > [self length])
        [self setLength:NSMaxRange(range)];
    memmove((char *)[self mutableBytes] + range.location, bytes, range.length);
}
- (void)setData:(NSData *)data
{
    [data retain];
    [self setLength:0];
    [self appendData:data];
    [data release];
}
@end

@implementation FData
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length
{
    _cap = length ? length : 1;
    _bytes = malloc(_cap);
    if (length)
        memcpy(_bytes, bytes, length);
    _len = length;
    _free = YES;
    return self;
}
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b
{
    if (_mutable) {
        /* A mutable buffer must be able to grow, so it keeps its own copy. */
        self = [self initWithBytes:bytes length:length];
        if (b)
            free(bytes);
        return self;
    }
    _bytes = bytes;
    _len = _cap = length;
    _free = b;
    return self;
}
- (instancetype)initWithCapacity:(NSUInteger)capacity
{
    self = [self initWithBytes:NULL length:0];
    if (capacity > _cap) {
        _cap = capacity;
        _bytes = realloc(_bytes, _cap);
    }
    return self;
}
- (void)dealloc
{
    if (_free)
        free(_bytes);
    [super dealloc];
}
- (BOOL)isKindOfClass:(Class)cls
{
    if (!_mutable && cls == [NSMutableData class])
        return NO;
    return [super isKindOfClass:cls];
}
- (id)copyWithZone:(NSZone *)zone
{
    if (!_mutable)
        return [self retain];
    return [[NSData allocWithZone:zone] initWithData:self];
}
- (NSUInteger)length { return _len; }
- (const void *)bytes { return _bytes; }
- (void *)mutableBytes { return _mutable ? _bytes : NULL; }
static void need_mutable(FData *d, SEL sel)
{
    if (!d->_mutable)
        [d doesNotRecognizeSelector:sel];
}
static void reserve(FData *d, NSUInteger n)
{
    if (n <= d->_cap)
        return;
    NSUInteger cap = d->_cap * 2;
    d->_cap = cap > n ? cap : n;
    d->_bytes = realloc(d->_bytes, d->_cap);
}
- (void)setLength:(NSUInteger)length
{
    need_mutable(self, _cmd);
    reserve(self, length);
    if (length > _len)
        memset(_bytes + _len, 0, length - _len);
    _len = length;
}
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length
{
    need_mutable(self, _cmd);
    reserve(self, _len + length);
    memmove(_bytes + _len, bytes, length);
    _len += length;
}
@end
