/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Installer: packages, payloads and disk images (see IPackage.h). */
#import "IPackage.h"
#import <AppKit/AppKit.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <ctype.h>
#include <signal.h>
int execlp(const char *file, const char *arg, ...);
int kill(pid_t pid, int sig);

/* ---- zlib and liblzma, served by this system's copies --------------------------------
 * The few declarations used, from the libraries' public headers. */
typedef struct {
    const uint8_t *next_in;
    unsigned avail_in;
    unsigned long total_in;
    uint8_t *next_out;
    unsigned avail_out;
    unsigned long total_out;
    const char *msg;
    void *state, *zalloc, *zfree, *opaque;
    int data_type;
    unsigned long adler, reserved;
} z_stream;
int inflateInit2_(z_stream *strm, int windowBits, const char *version, int size);
int inflate(z_stream *strm, int flush);
int inflateEnd(z_stream *strm);
int inflateReset(z_stream *strm);
const char *zlibVersion(void);
#define Z_OK 0
#define Z_STREAM_END 1
#define Z_BUF_ERROR (-5)
#define Z_NO_FLUSH 0

typedef struct {
    const uint8_t *next_in;
    size_t avail_in;
    uint64_t total_in;
    uint8_t *next_out;
    size_t avail_out;
    uint64_t total_out;
    const void *allocator;
    void *internal;
    void *reserved[4];
    uint64_t reserved_int[2];
    size_t reserved_size[2];
    int reserved_enum[2];
    uint8_t spare[64];   /* room for fields newer versions add */
} lzma_stream;
int lzma_stream_decoder(lzma_stream *strm, uint64_t memlimit, uint32_t flags);
int lzma_code(lzma_stream *strm, int action);
void lzma_end(lzma_stream *strm);
#define LZMA_OK 0
#define LZMA_STREAM_END 1
#define LZMA_RUN 0
#define LZMA_FINISH 3
#define LZMA_CONCATENATED 0x08

/* ---- XML --------------------------------------------------------------------------------- */

@interface IXMLNode ()
@property (copy) NSString *name;
@property (retain) NSMutableDictionary *mattributes;
@property (retain) NSMutableArray *mchildren;
@property (retain) NSMutableString *mtext;
@end

@implementation IXMLNode
- (instancetype)init
{
    if ((self = [super init])) {
        self.mattributes = [NSMutableDictionary dictionary];
        self.mchildren = [NSMutableArray array];
        self.mtext = [NSMutableString string];
    }
    return self;
}
- (void)dealloc
{
    [_name release];
    [_mattributes release];
    [_mchildren release];
    [_mtext release];
    [super dealloc];
}
- (NSDictionary *)attributes { return _mattributes; }
- (NSArray *)children { return _mchildren; }
- (NSString *)text { return [_mtext stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]; }
- (NSString *)attr:(NSString *)n { return [_mattributes objectForKey:n]; }
- (IXMLNode *)child:(NSString *)n
{
    for (IXMLNode *c in _mchildren)
        if ([c.name isEqualToString:n])
            return c;
    return nil;
}
- (void)_collect:(NSString *)n into:(NSMutableArray *)out
{
    for (IXMLNode *c in _mchildren) {
        if ([c.name isEqualToString:n])
            [out addObject:c];
        [c _collect:n into:out];
    }
}
- (NSArray *)all:(NSString *)n
{
    NSMutableArray *out = [NSMutableArray array];
    [self _collect:n into:out];
    return out;
}

static NSString *xml_unescape(NSString *s)
{
    if ([s rangeOfString:@"&"].location == NSNotFound)
        return s;
    NSMutableString *m = [NSMutableString string];
    NSUInteger i = 0, n = [s length];
    while (i < n) {
        unichar c = [s characterAtIndex:i];
        if (c == '&') {
            NSRange semi = [s rangeOfString:@";" options:0 range:NSMakeRange(i, MIN(n - i, 12))];
            if (semi.location != NSNotFound) {
                NSString *e = [s substringWithRange:NSMakeRange(i + 1, semi.location - i - 1)];
                NSString *r = nil;
                if ([e isEqualToString:@"amp"]) r = @"&";
                else if ([e isEqualToString:@"lt"]) r = @"<";
                else if ([e isEqualToString:@"gt"]) r = @">";
                else if ([e isEqualToString:@"quot"]) r = @"\"";
                else if ([e isEqualToString:@"apos"]) r = @"'";
                else if ([e hasPrefix:@"#"]) {
                    unsigned v = [e hasPrefix:@"#x"] ? (unsigned)strtoul([[e substringFromIndex:2] UTF8String], NULL, 16)
                                                     : (unsigned)strtoul([[e substringFromIndex:1] UTF8String], NULL, 10);
                    unichar u = v > 0xffff ? 0xfffd : (unichar)v;
                    r = [NSString stringWithCharacters:&u length:1];
                }
                if (r) {
                    [m appendString:r];
                    i = NSMaxRange(semi);
                    continue;
                }
            }
        }
        [m appendFormat:@"%C", c];
        i++;
    }
    return m;
}

static BOOL starts_with(NSString *s, NSUInteger i, NSString *prefix)
{
    NSUInteger k = [prefix length];
    return i + k <= [s length] && [[s substringWithRange:NSMakeRange(i, k)] isEqualToString:prefix];
}

+ (IXMLNode *)parse:(NSData *)data
{
    NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!s)
        s = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (!s)
        return nil;
    NSMutableArray *stack = [NSMutableArray array];
    IXMLNode *root = nil;
    NSUInteger i = 0, n = [s length];
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (i < n) {
        NSRange lt = [s rangeOfString:@"<" options:0 range:NSMakeRange(i, n - i)];
        NSUInteger textEnd = lt.location == NSNotFound ? n : lt.location;
        if (textEnd > i && [stack count])
            [[[stack lastObject] mtext] appendString:xml_unescape([s substringWithRange:NSMakeRange(i, textEnd - i)])];
        if (lt.location == NSNotFound)
            break;
        i = lt.location;
        if (starts_with(s, i, @"<!--")) {
            NSRange e = [s rangeOfString:@"-->" options:0 range:NSMakeRange(i, n - i)];
            i = e.location == NSNotFound ? n : NSMaxRange(e);
            continue;
        }
        if (starts_with(s, i, @"<![CDATA[")) {
            NSRange e = [s rangeOfString:@"]]>" options:0 range:NSMakeRange(i, n - i)];
            NSUInteger end = e.location == NSNotFound ? n : e.location;
            if ([stack count])
                [[[stack lastObject] mtext] appendString:[s substringWithRange:NSMakeRange(i + 9, end - i - 9)]];
            i = e.location == NSNotFound ? n : NSMaxRange(e);
            continue;
        }
        if (i + 1 < n && ([s characterAtIndex:i + 1] == '?' || [s characterAtIndex:i + 1] == '!')) {
            NSRange e = [s rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            i = e.location == NSNotFound ? n : NSMaxRange(e);
            continue;
        }
        /* a tag; '>' inside quoted attribute values doesn't end it */
        NSUInteger j = i + 1;
        unichar quote = 0;
        while (j < n) {
            unichar c = [s characterAtIndex:j];
            if (quote) {
                if (c == quote)
                    quote = 0;
            } else if (c == '"' || c == '\'')
                quote = c;
            else if (c == '>')
                break;
            j++;
        }
        NSString *tag = [s substringWithRange:NSMakeRange(i + 1, MIN(j, n) - i - 1)];
        i = j + 1;
        if ([tag hasPrefix:@"/"]) {
            if ([stack count])
                [stack removeLastObject];
            continue;
        }
        BOOL selfClosing = [tag hasSuffix:@"/"];
        if (selfClosing)
            tag = [tag substringToIndex:[tag length] - 1];
        IXMLNode *node = [[[IXMLNode alloc] init] autorelease];
        NSRange sp = [tag rangeOfCharacterFromSet:space];
        node.name = sp.location == NSNotFound ? tag : [tag substringToIndex:sp.location];
        NSUInteger k = sp.location == NSNotFound ? [tag length] : sp.location, tn = [tag length];
        while (k < tn) {
            while (k < tn && [space characterIsMember:[tag characterAtIndex:k]])
                k++;
            NSRange eq = [tag rangeOfString:@"=" options:0 range:NSMakeRange(k, tn - k)];
            if (eq.location == NSNotFound)
                break;
            NSString *key = [[tag substringWithRange:NSMakeRange(k, eq.location - k)] stringByTrimmingCharactersInSet:space];
            k = NSMaxRange(eq);
            while (k < tn && [space characterIsMember:[tag characterAtIndex:k]])
                k++;
            if (k >= tn)
                break;
            unichar q = [tag characterAtIndex:k];
            NSUInteger vs = k + 1, ve;
            if (q == '"' || q == '\'') {
                NSRange e = [tag rangeOfString:[NSString stringWithCharacters:&q length:1] options:0
                                         range:NSMakeRange(vs, tn - vs)];
                ve = e.location == NSNotFound ? tn : e.location;
                k = ve + 1;
            } else {
                vs = k;
                ve = vs;
                while (ve < tn && ![space characterIsMember:[tag characterAtIndex:ve]])
                    ve++;
                k = ve;
            }
            [node.mattributes setObject:xml_unescape([tag substringWithRange:NSMakeRange(vs, ve - vs)]) forKey:key];
        }
        if ([stack count])
            [[[stack lastObject] mchildren] addObject:node];
        else if (!root)
            root = node;
        if (!selfClosing)
            [stack addObject:node];
    }
    return root;
}
@end

/* ---- xar --------------------------------------------------------------------------------- */

@implementation IXarEntry
- (void)dealloc
{
    [_path release];
    [_type release];
    [_encoding release];
    [super dealloc];
}
@end

static uint64_t be64(const uint8_t *p)
{
    uint64_t v = 0;
    for (int i = 0; i < 8; i++)
        v = v << 8 | p[i];
    return v;
}

/* Inflates a whole zlib or gzip buffer. */
static NSData *inflate_all(NSData *in, unsigned long long expected)
{
    z_stream z;
    memset(&z, 0, sizeof z);
    if (inflateInit2_(&z, 15 + 32, zlibVersion(), (int)sizeof z) != Z_OK)
        return nil;
    NSMutableData *out = [NSMutableData dataWithLength:expected ? (NSUInteger)expected : [in length] * 4 + 1024];
    z.next_in = [in bytes];
    z.avail_in = (unsigned)[in length];
    int r;
    do {
        if (z.total_out >= [out length])
            [out setLength:[out length] * 2];
        z.next_out = (uint8_t *)[out mutableBytes] + z.total_out;
        z.avail_out = (unsigned)([out length] - z.total_out);
        r = inflate(&z, Z_NO_FLUSH);
    } while (r == Z_OK || (r == Z_BUF_ERROR && z.avail_out == 0));
    [out setLength:z.total_out];
    inflateEnd(&z);
    return r == Z_STREAM_END ? out : nil;
}

@implementation IXar {
    int _fd;
    unsigned long long _heap;
    NSMutableArray *_entries;
}
- (void)_walk:(IXMLNode *)node prefix:(NSString *)prefix
{
    for (IXMLNode *f in [node children]) {
        if (![f.name isEqualToString:@"file"])
            continue;
        IXarEntry *e = [[[IXarEntry alloc] init] autorelease];
        NSString *name = [[f child:@"name"] text] ?: @"";
        e.path = [prefix length] ? [prefix stringByAppendingPathComponent:name] : name;
        e.type = [[f child:@"type"] text] ?: @"file";
        IXMLNode *data = [f child:@"data"];
        if (data) {
            e.offset = strtoull([[[data child:@"offset"] text] UTF8String] ?: "0", NULL, 10);
            e.length = strtoull([[[data child:@"length"] text] UTF8String] ?: "0", NULL, 10);
            e.size = strtoull([[[data child:@"size"] text] UTF8String] ?: "0", NULL, 10);
            e.encoding = [[data child:@"encoding"] attr:@"style"] ?: @"application/octet-stream";
        }
        [_entries addObject:e];
        [self _walk:f prefix:e.path];
    }
}
+ (instancetype)openFile:(NSString *)path error:(NSString **)error
{
    IXar *x = [[[IXar alloc] init] autorelease];
    x->_fd = open([path fileSystemRepresentation], O_RDONLY);
    uint8_t h[28];
    if (x->_fd < 0 || pread(x->_fd, h, sizeof h, 0) != (ssize_t)sizeof h || memcmp(h, "xar!", 4) != 0) {
        if (error)
            *error = x->_fd < 0 ? [NSString stringWithFormat:@"It can't be read (%s).", strerror(errno)]
                                : @"It isn't an installer package (a xar archive).";
        return nil;
    }
    unsigned headerSize = (unsigned)h[4] << 8 | h[5];
    uint64_t tocLength = be64(h + 8), tocSize = be64(h + 16);
    if (tocLength > (64u << 20) || tocSize > (256u << 20)) {
        if (error)
            *error = @"Its table of contents is too large.";
        return nil;
    }
    NSMutableData *toc = [NSMutableData dataWithLength:(NSUInteger)tocLength];
    if (pread(x->_fd, [toc mutableBytes], (size_t)tocLength, headerSize) != (ssize_t)tocLength) {
        if (error)
            *error = @"It is cut short.";
        return nil;
    }
    NSData *xml = inflate_all(toc, tocSize);
    IXMLNode *root = xml ? [IXMLNode parse:xml] : nil;
    IXMLNode *t = [root child:@"toc"];
    if (!t) {
        if (error)
            *error = @"Its table of contents can't be read.";
        return nil;
    }
    x->_heap = headerSize + tocLength;
    x->_entries = [[NSMutableArray alloc] init];
    [x _walk:t prefix:@""];
    return x;
}
- (void)dealloc
{
    if (_fd >= 0)
        close(_fd);
    [_entries release];
    [super dealloc];
}
- (NSArray *)entries { return _entries; }
- (IXarEntry *)entry:(NSString *)path
{
    for (IXarEntry *e in _entries)
        if ([e.path isEqualToString:path])
            return e;
    for (IXarEntry *e in _entries)  /* names are matched without regard to case, as on a Mac's disk */
        if ([e.path caseInsensitiveCompare:path] == NSOrderedSame)
            return e;
    return nil;
}
- (NSInteger)read:(IXarEntry *)e at:(unsigned long long)offset into:(void *)buffer length:(size_t)length
{
    if (offset >= e.length)
        return 0;
    if (length > e.length - offset)
        length = (size_t)(e.length - offset);
    return pread(_fd, buffer, length, (off_t)(_heap + e.offset + offset));
}
- (NSData *)dataOf:(IXarEntry *)e
{
    if (!e || e.length > (512u << 20))
        return nil;
    NSMutableData *raw = [NSMutableData dataWithLength:(NSUInteger)e.length];
    if ([self read:e at:0 into:[raw mutableBytes] length:(size_t)e.length] != (NSInteger)e.length)
        return nil;
    if ([e.encoding rangeOfString:@"gzip"].location != NSNotFound)
        return inflate_all(raw, e.size);
    if ([e.encoding rangeOfString:@"octet-stream"].location == NSNotFound)
        return nil;   /* bzip2 or lzma table encodings are rare; not read */
    return raw;
}
@end

/* ---- byte streams: the payload's layers ------------------------------------------------- */

@protocol IStream <NSObject>
- (NSInteger)read:(uint8_t *)buffer max:(size_t)n;   /* 0 at the end, -1 on error */
@end

@interface IXarStream : NSObject <IStream> {
@public
    IXar *xar;
    IXarEntry *entry;
    unsigned long long at;
}
@end
@implementation IXarStream
- (NSInteger)read:(uint8_t *)b max:(size_t)n
{
    NSInteger r = [xar read:entry at:at into:b length:n];
    if (r > 0)
        at += (unsigned long long)r;
    return r;
}
- (void)dealloc
{
    [xar release];
    [entry release];
    [super dealloc];
}
@end

@interface IFileStream : NSObject <IStream> {
@public
    int fd;
    unsigned long long at, total;
}
@end
@implementation IFileStream
- (NSInteger)read:(uint8_t *)b max:(size_t)n
{
    ssize_t r = read(fd, b, n);
    if (r > 0)
        at += (unsigned long long)r;
    return r;
}
- (void)dealloc
{
    if (fd >= 0)
        close(fd);
    [super dealloc];
}
@end

/* Looks at the first bytes of a stream without taking them. */
@interface IPeekStream : NSObject <IStream> {
@public
    id<IStream> source;
    uint8_t head[16];
    size_t have, given;
}
@end
@implementation IPeekStream
- (const uint8_t *)peek:(size_t)n
{
    while (have < n) {
        NSInteger r = [source read:head + have max:n - have];
        if (r <= 0)
            break;
        have += (size_t)r;
    }
    return head;
}
- (NSInteger)read:(uint8_t *)b max:(size_t)n
{
    if (given < have) {
        size_t k = MIN(n, have - given);
        memcpy(b, head + given, k);
        given += k;
        return (NSInteger)k;
    }
    return [source read:b max:n];
}
- (void)dealloc
{
    [(id)source release];
    [super dealloc];
}
@end

@interface IInflateStream : NSObject <IStream> {
@public
    id<IStream> source;
    z_stream z;
    uint8_t in[1 << 16];
    BOOL ended, failed;
}
@end
@implementation IInflateStream
- (instancetype)initWithSource:(id<IStream>)s
{
    if ((self = [super init])) {
        source = [(id)s retain];
        if (inflateInit2_(&z, 15 + 32, zlibVersion(), (int)sizeof z) != Z_OK)
            failed = YES;
    }
    return self;
}
- (NSInteger)read:(uint8_t *)b max:(size_t)n
{
    if (failed)
        return -1;
    z.next_out = b;
    z.avail_out = (unsigned)MIN(n, (size_t)1 << 30);
    while (z.avail_out == (unsigned)MIN(n, (size_t)1 << 30)) {
        if (ended)
            return 0;
        if (!z.avail_in) {
            NSInteger r = [source read:in max:sizeof in];
            if (r < 0)
                return -1;
            if (r == 0) {
                failed = YES;     /* cut short */
                return -1;
            }
            z.next_in = in;
            z.avail_in = (unsigned)r;
        }
        int r = inflate(&z, Z_NO_FLUSH);
        if (r == Z_STREAM_END) {
            /* another gzip member may follow */
            if (z.avail_in >= 2 && z.next_in[0] == 0x1f && z.next_in[1] == 0x8b)
                inflateReset(&z);
            else
                ended = YES;
        } else if (r != Z_OK && r != Z_BUF_ERROR) {
            failed = YES;
            return -1;
        }
    }
    return (NSInteger)(MIN(n, (size_t)1 << 30) - z.avail_out);
}
- (void)dealloc
{
    inflateEnd(&z);
    [(id)source release];
    [super dealloc];
}
@end

/* pbzx: "pbzx", a 64-bit chunk size, then chunks of (64-bit flags, 64-bit
 * length, data), each data an xz stream, or stored as it is when it is the
 * full chunk size. */
@interface IPbzxStream : NSObject <IStream> {
@public
    id<IStream> source;
    NSMutableData *chunk;
    size_t chunkAt;
    BOOL ended, failed;
}
@end
@implementation IPbzxStream
- (BOOL)_readExactly:(uint8_t *)b length:(size_t)n
{
    size_t got = 0;
    while (got < n) {
        NSInteger r = [source read:b + got max:n - got];
        if (r <= 0)
            return NO;
        got += (size_t)r;
    }
    return YES;
}
- (instancetype)initWithSource:(id<IStream>)s
{
    if ((self = [super init])) {
        source = [(id)s retain];
        uint8_t h[12];
        if (![self _readExactly:h length:12] || memcmp(h, "pbzx", 4) != 0)
            failed = YES;
    }
    return self;
}
- (BOOL)_nextChunk
{
    uint8_t h[16];
    NSInteger first = [source read:h max:1];
    if (first == 0) {
        ended = YES;
        return NO;
    }
    if (first < 0 || ![self _readExactly:h + 1 length:15])
        return NO;
    uint64_t length = be64(h + 8), size = be64(h);
    if (length > (64u << 20) || size > (64u << 20))
        return NO;
    NSMutableData *raw = [NSMutableData dataWithLength:(NSUInteger)length];
    if (![self _readExactly:[raw mutableBytes] length:(size_t)length])
        return NO;
    [chunk release];
    const uint8_t xz[6] = {0xfd, '7', 'z', 'X', 'Z', 0};
    if (length >= 6 && !memcmp([raw bytes], xz, 6)) {
        lzma_stream l;
        memset(&l, 0, sizeof l);
        if (lzma_stream_decoder(&l, UINT64_MAX, LZMA_CONCATENATED) != LZMA_OK)
            return NO;
        chunk = [[NSMutableData alloc] initWithLength:(NSUInteger)(size ? size : length * 8)];
        l.next_in = [raw bytes];
        l.avail_in = (size_t)length;
        int r;
        do {
            if (l.total_out >= [chunk length])
                [chunk setLength:[chunk length] * 2];
            l.next_out = (uint8_t *)[chunk mutableBytes] + l.total_out;
            l.avail_out = [chunk length] - (size_t)l.total_out;
            r = lzma_code(&l, LZMA_FINISH);
        } while (r == LZMA_OK);
        [chunk setLength:(NSUInteger)l.total_out];
        lzma_end(&l);
        if (r != LZMA_STREAM_END) {
            chunk = nil;
            return NO;
        }
    } else
        chunk = [raw retain];
    chunkAt = 0;
    return YES;
}
- (NSInteger)read:(uint8_t *)b max:(size_t)n
{
    if (failed)
        return -1;
    while (!chunk || chunkAt >= [chunk length]) {
        if (ended)
            return 0;
        if (![self _nextChunk]) {
            if (ended)
                return 0;
            failed = YES;
            return -1;
        }
    }
    size_t k = MIN(n, [chunk length] - chunkAt);
    memcpy(b, (const uint8_t *)[chunk bytes] + chunkAt, k);
    chunkAt += k;
    return (NSInteger)k;
}
- (void)dealloc
{
    [chunk release];
    [(id)source release];
    [super dealloc];
}
@end

/* ---- where things go ----------------------------------------------------------------------- */

@implementation IDestination
+ (instancetype)standard
{
    IDestination *d = [[[IDestination alloc] init] autorelease];
    NSString *home = NSHomeDirectory();
    const char *data = getenv("XDG_DATA_HOME");
    NSString *share = data && *data ? [NSString stringWithUTF8String:data] : [home stringByAppendingPathComponent:@".local/share"];
    d.applications = [home stringByAppendingPathComponent:@"Applications"];
    d.root = [[share stringByAppendingPathComponent:@"ferry"] stringByAppendingPathComponent:@"root"];
    return d;
}
- (void)dealloc
{
    [_applications release];
    [_root release];
    [super dealloc];
}
/* nil for a path that would climb out of where it belongs */
- (NSString *)placeFor:(NSString *)installPath app:(NSString **)app
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *p in [installPath componentsSeparatedByString:@"/"]) {
        if (![p length] || [p isEqualToString:@"."])
            continue;
        if ([p isEqualToString:@".."])
            return nil;
        [parts addObject:p];
    }
    if (app)
        *app = nil;
    for (NSUInteger i = 0; i < [parts count]; i++)
        if ([[[parts objectAtIndex:i] pathExtension] caseInsensitiveCompare:@"app"] == NSOrderedSame) {
            NSArray *rest = [parts subarrayWithRange:NSMakeRange(i, [parts count] - i)];
            if (app)
                *app = [_applications stringByAppendingPathComponent:[parts objectAtIndex:i]];
            return [_applications stringByAppendingPathComponent:[NSString pathWithComponents:rest]];
        }
    return [parts count] ? [_root stringByAppendingPathComponent:[NSString pathWithComponents:parts]] : _root;
}
@end

@implementation IComponent
- (void)dealloc
{
    [_identifier release];
    [_version release];
    [_member release];
    [_installLocation release];
    [super dealloc];
}
@end

/* ---- packages -------------------------------------------------------------------------------- */

@interface IPackage ()
@property (copy) NSString *path, *title, *imageDirectory;
@property (retain) NSArray *components, *apps;
@property (retain) NSAttributedString *welcome, *readme, *license, *conclusion;
@property (nonatomic) unsigned long long installKBytes;
@property (nonatomic) BOOL hasScripts;
@property BOOL hasChecks;
@property (retain) IXar *xar;
@property (copy) NSString *bundleArchive;   /* a bundle package's Archive.pax.gz */
@end

/* A pkg-ref names its component with %-escapes, as in a URL. */
static NSString *percent_decoded(NSString *s)
{
    const char *p = [s UTF8String];
    NSMutableData *out = [NSMutableData data];
    for (; p && *p; p++) {
        if (p[0] == '%' && isxdigit((unsigned char)p[1]) && isxdigit((unsigned char)p[2])) {
            char hex[3] = {p[1], p[2], 0};
            uint8_t b = (uint8_t)strtoul(hex, NULL, 16);
            [out appendBytes:&b length:1];
            p += 2;
        } else
            [out appendBytes:p length:1];
    }
    return [[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] autorelease] ?: s;
}

static NSAttributedString *text_document(NSData *data, NSString *name, NSString *mime)
{
    if (!data)
        return nil;
    NSString *ext = [[name pathExtension] lowercaseString];
    mime = [mime lowercaseString] ?: @"";   /* (a range found in nil would be at 0) */
    NSString *type = nil;
    if ([mime rangeOfString:@"rtf"].location != NSNotFound || [ext isEqualToString:@"rtf"] || [ext isEqualToString:@"rtfd"])
        type = NSRTFTextDocumentType;
    else if ([mime rangeOfString:@"html"].location != NSNotFound || [ext isEqualToString:@"html"] ||
             [ext isEqualToString:@"htm"])
        type = NSHTMLTextDocumentType;
    else if ([ext isEqualToString:@"txt"] || [mime rangeOfString:@"text/plain"].location != NSNotFound)
        type = NSPlainTextDocumentType;
    NSDictionary *o = type ? @{NSDocumentTypeDocumentOption : type} : @{};
    return [[[NSAttributedString alloc] initWithData:data options:o documentAttributes:NULL error:NULL] autorelease];
}

@implementation IPackage
- (void)dealloc
{
    [_path release];
    [_title release];
    [_imageDirectory release];
    [_components release];
    [_apps release];
    [_welcome release];
    [_readme release];
    [_license release];
    [_conclusion release];
    [_xar release];
    [_bundleArchive release];
    [super dealloc];
}

/* A resource in the preferred language's .lproj, or at the top of Resources. */
- (NSData *)_resource:(NSString *)file
{
    if (![file length])
        return nil;
    for (NSString *lang in @[ @"en.lproj", @"English.lproj", @"en_US.lproj", @"Base.lproj", @"" ]) {
        NSString *p = [[@"Resources" stringByAppendingPathComponent:lang] stringByAppendingPathComponent:file];
        IXarEntry *e = [_xar entry:p];
        if (e)
            return [_xar dataOf:e];
    }
    for (IXarEntry *e in [_xar entries])
        if ([e.path hasPrefix:@"Resources/"] && [[e.path lastPathComponent] isEqualToString:file])
            return [_xar dataOf:e];
    /* an .rtfd is a folder holding TXT.rtf */
    if ([[file pathExtension] isEqualToString:@"rtfd"])
        return [self _resource:[file stringByAppendingPathComponent:@"TXT.rtf"]];
    return nil;
}
- (NSAttributedString *)_document:(IXMLNode *)node
{
    NSString *file = [node attr:@"file"];
    return text_document([self _resource:file], file, [node attr:@"mime-type"]);
}

- (IComponent *)_componentAt:(NSString *)dir pkgRef:(IXMLNode *)ref
{
    NSString *payload = [dir length] ? [dir stringByAppendingPathComponent:@"Payload"] : @"Payload";
    if (![_xar entry:payload])
        return nil;
    IComponent *c = [[[IComponent alloc] init] autorelease];
    c.member = payload;
    NSString *infoPath = [dir length] ? [dir stringByAppendingPathComponent:@"PackageInfo"] : @"PackageInfo";
    IXMLNode *info = [IXMLNode parse:[_xar dataOf:[_xar entry:infoPath]] ?: [NSData data]];
    c.identifier = [info attr:@"identifier"] ?: [ref attr:@"id"] ?: [dir stringByDeletingPathExtension];
    c.version = [info attr:@"version"] ?: [ref attr:@"version"];
    c.installLocation = [info attr:@"install-location"] ?: @"/";
    c.installKBytes = strtoull([([[info child:@"payload"] attr:@"installKBytes"] ?: [ref attr:@"installKBytes"] ?: @"0")
                                   UTF8String], NULL, 10);
    NSString *scripts = [dir length] ? [dir stringByAppendingPathComponent:@"Scripts"] : @"Scripts";
    c.hasScripts = [_xar entry:scripts] != nil || [info child:@"scripts"] != nil;
    return c;
}

- (BOOL)_openFlat:(NSString **)error
{
    self.xar = [IXar openFile:_path error:error];
    if (!_xar)
        return NO;
    NSMutableArray *components = [NSMutableArray array];
    IXMLNode *dist = [IXMLNode parse:[_xar dataOf:[_xar entry:@"Distribution"]] ?: [NSData data]];
    if (dist) {
        NSString *t = [[dist child:@"title"] text];
        if ([t length] && ![t hasPrefix:@"SU_"] && ![t hasPrefix:@"DISTRIBUTION_TITLE"])
            self.title = t;
        self.welcome = [self _document:[dist child:@"welcome"]];
        self.readme = [self _document:[dist child:@"readme"]];
        self.license = [self _document:[dist child:@"license"]];
        self.conclusion = [self _document:[dist child:@"conclusion"]];
        self.hasChecks = [dist child:@"installation-check"] || [dist child:@"volume-check"] ||
                         [[dist all:@"script"] count] > 0;
        NSMutableSet *seen = [NSMutableSet set];
        for (IXMLNode *ref in [dist all:@"pkg-ref"]) {
            NSString *where = [ref text];
            if (![where hasPrefix:@"#"])
                continue;
            NSString *dir = percent_decoded([where substringFromIndex:1]);
            if ([seen containsObject:dir])
                continue;
            [seen addObject:dir];
            IComponent *c = [self _componentAt:dir pkgRef:ref];
            if (c)
                [components addObject:c];
        }
    } else {
        IComponent *c = [self _componentAt:@"" pkgRef:nil];   /* a component package on its own */
        if (c)
            [components addObject:c];
    }
    if (![components count]) {
        if (error)
            *error = @"It has nothing to install (no Payload).";
        return NO;
    }
    self.components = components;
    return YES;
}

/* An old-style bundle package: a folder with Contents/Archive.pax.gz. */
- (BOOL)_openBundle:(NSString **)error
{
    NSString *contents = [_path stringByAppendingPathComponent:@"Contents"];
    NSString *archive = [contents stringByAppendingPathComponent:@"Archive.pax.gz"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:archive]) {
        if (error)
            *error = @"This kind of package (with sub-packages, or without Archive.pax.gz) isn't supported yet.";
        return NO;
    }
    self.bundleArchive = archive;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[contents stringByAppendingPathComponent:@"Info.plist"]];
    IComponent *c = [[[IComponent alloc] init] autorelease];
    c.identifier = [info objectForKey:@"CFBundleIdentifier"] ?: [[_path lastPathComponent] stringByDeletingPathExtension];
    c.version = [info objectForKey:@"CFBundleShortVersionString"];
    c.installLocation = [info objectForKey:@"IFPkgFlagDefaultLocation"] ?: @"/";
    c.member = archive;
    NSString *res = [contents stringByAppendingPathComponent:@"Resources"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *lang in @[ @"en.lproj", @"English.lproj", @"" ]) {
        NSString *dir = [res stringByAppendingPathComponent:lang];
        for (NSString *f in [fm contentsOfDirectoryAtPath:dir error:NULL]) {
            NSString *base = [[f stringByDeletingPathExtension] lowercaseString];
            NSString *full = [dir stringByAppendingPathComponent:f];
            NSData *d = [[f pathExtension] isEqualToString:@"rtfd"]
                            ? [NSData dataWithContentsOfFile:[full stringByAppendingPathComponent:@"TXT.rtf"]]
                            : [NSData dataWithContentsOfFile:full];
            if ([base isEqualToString:@"welcome"] && !_welcome)
                self.welcome = text_document(d, f, nil);
            else if ([base isEqualToString:@"readme"] && !_readme)
                self.readme = text_document(d, f, nil);
            else if ([base isEqualToString:@"license"] && !_license)
                self.license = text_document(d, f, nil);
        }
        c.hasScripts = c.hasScripts || [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"postinstall"]] ||
                       [fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"preinstall"]];
    }
    self.components = @[ c ];
    return YES;
}

+ (instancetype)openPath:(NSString *)path error:(NSString **)error
{
    IPackage *p = [[[IPackage alloc] init] autorelease];
    p.path = path;
    p.title = [[path lastPathComponent] stringByDeletingPathExtension];
    BOOL dir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir];
    if ([[[path pathExtension] lowercaseString] isEqualToString:@"dmg"] || (!dir && [p _isDiskImage]))
        return [p _openDiskImage:error] ? p : nil;
    if (dir ? ![p _openBundle:error] : ![p _openFlat:error])
        return nil;
    unsigned long long kb = 0;
    BOOL scripts = NO;
    for (IComponent *c in p.components) {
        kb += c.installKBytes;
        scripts = scripts || c.hasScripts;
    }
    p.installKBytes = kb;
    p.hasScripts = scripts;
    return p;
}

- (BOOL)_isDiskImage
{
    int fd = open([_path fileSystemRepresentation], O_RDONLY);
    if (fd < 0)
        return NO;
    char magic[4] = {0};
    off_t end = lseek(fd, 0, SEEK_END);
    BOOL koly = end > 512 && pread(fd, magic, 4, end - 512) == 4 && !memcmp(magic, "koly", 4);
    close(fd);
    return koly;
}

/* What a disk image holds: a package to open, or apps to copy. Looks a few
 * folders deep, as a volume's top level often holds only one folder. */
static void find_installables(NSString *dir, int depth, NSMutableArray *pkgs, NSMutableArray *apps)
{
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."] || [n rangeOfString:@":"].location != NSNotFound || [n hasPrefix:@"[HFS+"])
            continue;
        NSString *full = [dir stringByAppendingPathComponent:n];
        NSString *ext = [[n pathExtension] lowercaseString];
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir];
        struct stat st;
        if (lstat([full fileSystemRepresentation], &st) == 0 && S_ISLNK(st.st_mode))
            continue;   /* the usual link to /Applications */
        if ([ext isEqualToString:@"pkg"] || [ext isEqualToString:@"mpkg"])
            [pkgs addObject:full];
        else if ([ext isEqualToString:@"app"] && isDir)
            [apps addObject:full];
        else if (isDir && depth > 0)
            find_installables(full, depth - 1, pkgs, apps);
    }
}

static BOOL (^disk_image_waiter)(void);
+ (void)setDiskImageWaiter:(BOOL (^)(void))waiter
{
    id wasDisk_image_waiter = disk_image_waiter;
    disk_image_waiter = [waiter copy];
    [wasDisk_image_waiter release];
}
- (BOOL)_openDiskImage:(NSString **)error
{
    NSString *dir = IOpenDiskImage(_path, error, disk_image_waiter);
    if (!dir)
        return NO;
    self.imageDirectory = dir;
    NSMutableArray *pkgs = [NSMutableArray array], *apps = [NSMutableArray array];
    find_installables(dir, 3, pkgs, apps);
    if ([pkgs count]) {
        /* the image's package does the installing */
        NSString *inner = [pkgs firstObject];
        IPackage *p = [IPackage openPath:inner error:error];
        if (!p)
            return NO;
        self.xar = p.xar;
        self.bundleArchive = p.bundleArchive;
        self.components = p.components;
        self.welcome = p.welcome;
        self.readme = p.readme;
        self.license = p.license;
        self.conclusion = p.conclusion;
        self.hasChecks = p.hasChecks;
        if (![p.title isEqualToString:[[inner lastPathComponent] stringByDeletingPathExtension]])
            self.title = p.title;
        return YES;
    }
    if (![apps count]) {
        if (error)
            *error = @"The disk image has no app or installer package in it.";
        return NO;
    }
    self.apps = apps;
    NSString *first = [[[apps firstObject] lastPathComponent] stringByDeletingPathExtension];
    self.title = first;
    unsigned long long kb = 0;
    for (NSString *a in apps)
        for (NSString *sub in [[NSFileManager defaultManager] subpathsAtPath:a]) {
            struct stat st;
            if (lstat([[a stringByAppendingPathComponent:sub] fileSystemRepresentation], &st) == 0 && S_ISREG(st.st_mode))
                kb += ((unsigned long long)st.st_size + 1023) / 1024;
        }
    self.installKBytes = kb;
    return YES;
}
- (unsigned long long)installKBytes
{
    if (_installKBytes)
        return _installKBytes;
    unsigned long long kb = 0;
    for (IComponent *c in _components)
        kb += c.installKBytes;
    return kb;
}
- (BOOL)hasScripts
{
    for (IComponent *c in _components)
        if (c.hasScripts)
            return YES;
    return _hasScripts;
}
@end

/* ---- installing ---------------------------------------------------------------------------- */

@interface IInstallJob ()
@property (copy) NSString *status, *error;
@end

@implementation IInstallJob {
    IPackage *_pkg;
    IDestination *_dest;
    NSUInteger _component, _app;
    id<IStream> _stream;
    IXarStream *_raw;            /* for progress through a flat package */
    IFileStream *_file;          /* or through a bundle package's archive */
    unsigned long long _rawTotal, _rawDone;
    /* the cpio archive */
    int _out;                    /* the file being written, or -1 */
    unsigned long long _left;    /* of its data */
    unsigned _pad;               /* bytes after it (newc) */
    BOOL _newc, _started, _done;
    NSMutableArray *_apps;
    NSMutableSet *_replaced;
    unsigned long long _files;
    unsigned long long _failures;
    double _fraction;
}
- (instancetype)initWithPackage:(IPackage *)pkg destination:(IDestination *)dest
{
    if ((self = [super init])) {
        _pkg = [pkg retain];
        _dest = [dest retain];
        _out = -1;
        _apps = [[NSMutableArray alloc] init];
        _replaced = [[NSMutableSet alloc] init];
        _rawTotal = [pkg.components count];
        self.status = @"Preparing…";
    }
    return self;
}
- (void)dealloc
{
    if (_out >= 0)
        close(_out);
    [_pkg release];
    [_dest release];
    [(id)_stream release];
    [_raw release];
    [_file release];
    [_apps release];
    [_replaced release];
    [_status release];
    [_error release];
    [super dealloc];
}
- (double)fraction { return _fraction; }
- (NSArray *)installedApps { return _apps; }
- (unsigned long long)filesWritten { return _files; }
- (BOOL)_fail:(NSString *)why
{
    self.error = why;
    _done = YES;
    return NO;
}

/* mkdir -p, refusing to go through a link the archive made */
static BOOL make_dirs(NSString *path, NSString *base)
{
    if (![path hasPrefix:base])
        return NO;
    NSString *rel = [path substringFromIndex:[base length]];
    NSString *at = base;
    /* the destination itself (ours, not the archive's): make every missing parent */
    char buf[4096];
    snprintf(buf, sizeof buf, "%s", [base fileSystemRepresentation]);
    for (char *q = buf + 1; *q; q++)
        if (*q == '/') {
            *q = 0;
            mkdir(buf, 0755);
            *q = '/';
        }
    mkdir(buf, 0755);
    for (NSString *p in [rel pathComponents]) {
        if ([p isEqualToString:@"/"] || ![p length])
            continue;
        at = [at stringByAppendingPathComponent:p];
        struct stat st;
        if (lstat([at fileSystemRepresentation], &st) == 0) {
            if (S_ISLNK(st.st_mode) || !S_ISDIR(st.st_mode))
                return NO;
            continue;
        }
        if (mkdir([at fileSystemRepresentation], 0755) != 0 && errno != EEXIST)
            return NO;
    }
    return YES;
}
- (NSString *)_baseFor:(NSString *)place
{
    return [place hasPrefix:_dest.applications] ? _dest.applications : _dest.root;
}

/* Opens the next component's payload. */
- (BOOL)_openComponent
{
    IComponent *c = [_pkg.components objectAtIndex:_component];
    id<IStream> raw;
    [_raw release];
    _raw = nil;
    [_file release];
    _file = nil;
    if (_pkg.bundleArchive && [c.member isEqualToString:_pkg.bundleArchive]) {
        _file = [[IFileStream alloc] init];
        _file->fd = open([c.member fileSystemRepresentation], O_RDONLY);
        struct stat st;
        if (_file->fd < 0 || fstat(_file->fd, &st) != 0)
            return [self _fail:@"The package's archive can't be read."];
        _file->total = (unsigned long long)st.st_size;
        raw = _file;
    } else {
        IXarEntry *e = [_pkg.xar entry:c.member];
        if (!e)
            return [self _fail:@"The package's Payload is missing."];
        _raw = [[IXarStream alloc] init];
        _raw->xar = [_pkg.xar retain];
        _raw->entry = [e retain];
        raw = _raw;
        if ([e.encoding rangeOfString:@"gzip"].location != NSNotFound)
            raw = [[[IInflateStream alloc] initWithSource:raw] autorelease];
    }
    IPeekStream *peek = [[[IPeekStream alloc] init] autorelease];
    peek->source = [(id)raw retain];
    const uint8_t *h = [peek peek:6];
    id<IStream> s;
    if (peek->have >= 2 && h[0] == 0x1f && h[1] == 0x8b)
        s = [[[IInflateStream alloc] initWithSource:peek] autorelease];
    else if (peek->have >= 4 && !memcmp(h, "pbzx", 4))
        s = [[[IPbzxStream alloc] initWithSource:peek] autorelease];
    else if (peek->have >= 6 && !memcmp(h, "07070", 5))
        s = peek;
    else
        return [self _fail:@"The package's Payload is in a form Ferry can't read yet."];
    [(id)_stream release];
    _stream = [(id)s retain];
    self.status = [NSString stringWithFormat:@"Installing %@…", c.identifier ?: @"the package"];
    return YES;
}

- (BOOL)_readExactly:(uint8_t *)b length:(size_t)n
{
    size_t got = 0;
    while (got < n) {
        NSInteger r = [_stream read:b + got max:n - got];
        if (r <= 0)
            return NO;
        got += (size_t)r;
    }
    return YES;
}
- (BOOL)_skip:(unsigned long long)n
{
    uint8_t buf[8192];
    while (n) {
        size_t k = (size_t)MIN(n, sizeof buf);
        if (![self _readExactly:buf length:k])
            return NO;
        n -= k;
    }
    return YES;
}
static unsigned long long field(const uint8_t *p, int len, int base)
{
    char s[24];
    memcpy(s, p, (size_t)len);
    s[len] = 0;
    return strtoull(s, NULL, base);
}

/* One cpio header and what it names; NO at the end of the archive. */
- (BOOL)_nextEntry:(BOOL *)failed
{
    uint8_t h[110];
    *failed = NO;
    if (![self _readExactly:h length:6]) {
        *failed = YES;
        return NO;
    }
    unsigned long long mode, size, nameSize;
    if (!memcmp(h, "070707", 6)) {
        if (![self _readExactly:h + 6 length:70]) {
            *failed = YES;
            return NO;
        }
        mode = field(h + 18, 6, 8);
        nameSize = field(h + 59, 6, 8);
        size = field(h + 65, 11, 8);
        _newc = NO;
    } else if (!memcmp(h, "070701", 6) || !memcmp(h, "070702", 6)) {
        if (![self _readExactly:h + 6 length:104]) {
            *failed = YES;
            return NO;
        }
        mode = field(h + 14, 8, 16);
        size = field(h + 54, 8, 16);
        nameSize = field(h + 94, 8, 16);
        _newc = YES;
    } else {
        *failed = YES;
        return NO;
    }
    if (nameSize == 0 || nameSize > 4096) {
        *failed = YES;
        return NO;
    }
    char name[4097];
    if (![self _readExactly:(uint8_t *)name length:(size_t)nameSize]) {
        *failed = YES;
        return NO;
    }
    name[nameSize] = 0;
    if (_newc && ![self _skip:(4 - (110 + nameSize) % 4) % 4]) {
        *failed = YES;
        return NO;
    }
    _pad = _newc ? (unsigned)((4 - size % 4) % 4) : 0;
    if (!strcmp(name, "TRAILER!!!"))
        return NO;
    IComponent *c = [_pkg.components objectAtIndex:_component];
    NSString *rel = [NSString stringWithUTF8String:name] ?: @"";
    NSString *app = nil;
    NSString *place = [_dest placeFor:[c.installLocation stringByAppendingPathComponent:rel] app:&app];
    _left = size;
    _out = -1;
    if (!place)
        return YES;    /* climbs out: its data is skipped */
    if (app && ![_replaced containsObject:app]) {
        [_replaced addObject:app];
        IRemoveTree(app);       /* a newer copy replaces the old one */
        [_apps addObject:app];
    }
    NSString *base = [self _baseFor:place];
    unsigned type = (unsigned)(mode & 0170000);
    if (type == 0040000) {
        if (!strcmp(name, ".") || !strcmp(name, "./"))
            return YES;     /* the install location itself: made when something goes in it */
        if (!make_dirs(place, base)) {
            NSLog(@"Installer: can't make the folder %@", place);
            _failures++;
        }
        return YES;
    }
    if (!make_dirs([place stringByDeletingLastPathComponent], base)) {
        _failures++;
        return YES;
    }
    if (type == 0120000) {
        char target[4097];
        if (size > 4096 || ![self _readExactly:(uint8_t *)target length:(size_t)size]) {
            *failed = YES;
            return NO;
        }
        target[size] = 0;
        _left = 0;
        unlink([place fileSystemRepresentation]);
        symlink(target, [place fileSystemRepresentation]);
        _files++;
        return YES;
    }
    if (type == 0100000 || type == 0) {
        unlink([place fileSystemRepresentation]);
        _out = open([place fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, (mode_t)(mode & 0777) | 0600);
        if (_out < 0) {
            NSLog(@"Installer: can't write %@ (%s)", place, strerror(errno));
            _failures++;
        }
        _files++;
    }
    return YES;   /* devices, fifos: their data (none) is skipped */
}

- (void)_updateFraction
{
    NSUInteger n = [_pkg.components count];
    double within = 0;
    if (_raw && _raw->entry.length)
        within = (double)_raw->at / (double)_raw->entry.length;
    else if (_file && _file->total)
        within = (double)_file->at / (double)_file->total;
    _fraction = n ? ((double)_component + within) / (double)n : 1;
}

- (BOOL)_stepApps
{
    if (_app >= [_pkg.apps count]) {
        _fraction = 1;
        self.status = @"Done";
        _done = YES;
        return NO;
    }
    NSString *from = [_pkg.apps objectAtIndex:_app++];
    NSString *to = [_dest.applications stringByAppendingPathComponent:[from lastPathComponent]];
    self.status = [NSString stringWithFormat:@"Copying %@…", [from lastPathComponent]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_dest.applications withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    IRemoveTree(to);
    NSString *why = nil;
    if (!ICopyTree(from, to, &why))
        return [self _fail:why ?: @"The app couldn't be copied."];
    [_apps addObject:to];
    _fraction = (double)_app / (double)[_pkg.apps count];
    return YES;
}

- (BOOL)step
{
    if (_done)
        return NO;
    if ([_pkg.apps count])
        return [self _stepApps];
    if (!_stream && _component < [_pkg.components count] && ![self _openComponent])
        return NO;
    /* about a megabyte of output at a time */
    size_t budget = 1 << 20;
    uint8_t buf[1 << 16];
    while (budget > 0) {
        if (_left || _out >= 0) {
            while (_left && budget > 0) {
                size_t k = (size_t)MIN(_left, MIN((unsigned long long)sizeof buf, (unsigned long long)budget));
                if (![self _readExactly:buf length:k])
                    return [self _fail:@"The package's Payload is cut short or damaged."];
                if (_out >= 0 && write(_out, buf, k) != (ssize_t)k) {
                    close(_out);
                    _out = -1;
                    return [self _fail:[NSString stringWithFormat:@"A file couldn't be written (%s).", strerror(errno)]];
                }
                _left -= k;
                budget -= k;
            }
            if (_left)
                break;
            if (_out >= 0) {
                close(_out);
                _out = -1;
            }
            if (_pad && ![self _skip:_pad])
                return [self _fail:@"The package's Payload is cut short or damaged."];
            _pad = 0;
            continue;
        }
        BOOL failed;
        if (![self _nextEntry:&failed]) {
            if (failed)
                return [self _fail:@"The package's Payload is cut short or damaged."];
            /* this component is done */
            [(id)_stream release];
            _stream = nil;
            _component++;
            if (_component >= [_pkg.components count]) {
                _fraction = 1;
                if (_failures)
                    return [self _fail:[NSString stringWithFormat:@"%llu of the package's files and folders couldn't be written.",
                                        _failures]];
                self.status = @"Done";
                _done = YES;
                return NO;
            }
            if (![self _openComponent])
                return NO;
            continue;
        }
        budget = budget > 512 ? budget - 512 : 0;
    }
    [self _updateFraction];
    return YES;
}
@end

/* ---- disk images, and copying ---------------------------------------------------------------- */

void IRemoveTree(NSString *path)
{
    struct stat st;
    const char *p = [path fileSystemRepresentation];
    if (lstat(p, &st) != 0)
        return;
    if (S_ISDIR(st.st_mode)) {
        DIR *d = opendir(p);
        NSMutableArray *names = [NSMutableArray array];
        for (struct dirent *e; d && (e = readdir(d));)
            if (strcmp(e->d_name, ".") && strcmp(e->d_name, ".."))
                [names addObject:[NSString stringWithUTF8String:e->d_name] ?: @""];
        if (d)
            closedir(d);
        for (NSString *n in names)
            if ([n length])
                IRemoveTree([path stringByAppendingPathComponent:n]);
        rmdir(p);
    } else
        unlink(p);
}

static BOOL finder_metadata(const char *name)
{
    /* 7-Zip writes a file's extended attributes and resource fork beside it, as "name:attribute" */
    const char *colon = strchr(name, ':');
    return (colon && (strstr(colon, ":com.apple.") || !strcmp(colon, ":rsrc") || strstr(colon, ":Zone"))) ||
           !strncmp(name, "[HFS+", 5) || !strcmp(name, ".DS_Store");
}

BOOL ICopyTree(NSString *from, NSString *to, NSString **error)
{
    struct stat st;
    const char *src = [from fileSystemRepresentation];
    if (lstat(src, &st) != 0) {
        if (error)
            *error = [NSString stringWithFormat:@"%@ can't be read.", from];
        return NO;
    }
    const char *dst = [to fileSystemRepresentation];
    if (S_ISLNK(st.st_mode)) {
        char target[4096];
        ssize_t n = readlink(src, target, sizeof target - 1);
        if (n < 0)
            return YES;
        target[n] = 0;
        return symlink(target, dst) == 0 || errno == EEXIST;
    }
    if (S_ISDIR(st.st_mode)) {
        if (mkdir(dst, (st.st_mode & 0777) | 0700) != 0 && errno != EEXIST) {
            if (error)
                *error = [NSString stringWithFormat:@"The folder %@ can't be made (%s).", to, strerror(errno)];
            return NO;
        }
        DIR *d = opendir(src);
        NSMutableArray *names = [NSMutableArray array];
        for (struct dirent *e; d && (e = readdir(d));)
            if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..") && !finder_metadata(e->d_name))
                [names addObject:[NSString stringWithUTF8String:e->d_name] ?: @""];
        if (d)
            closedir(d);
        for (NSString *n in names)
            if ([n length] && !ICopyTree([from stringByAppendingPathComponent:n], [to stringByAppendingPathComponent:n], error))
                return NO;
        return YES;
    }
    if (!S_ISREG(st.st_mode))
        return YES;
    int in = open(src, O_RDONLY), out = open(dst, O_WRONLY | O_CREAT | O_TRUNC, (st.st_mode & 0777) | 0600);
    BOOL ok = in >= 0 && out >= 0;
    char buf[1 << 16];
    ssize_t n;
    while (ok && (n = read(in, buf, sizeof buf)) > 0)
        ok = write(out, buf, (size_t)n) == n;
    if (in >= 0)
        close(in);
    if (out >= 0)
        close(out);
    if (!ok && error)
        *error = [NSString stringWithFormat:@"%@ can't be copied (%s).", from, strerror(errno)];
    return ok;
}

/* Runs 7-Zip to extract an archive into dir; the exit status, or -1 when 7z can't run. */
static int run_7z(NSString *archive, NSString *dir, BOOL (^keepWaiting)(void))
{
    NSString *outArg = [@"-o" stringByAppendingString:dir];
    pid_t pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) {
            dup2(null, 1);
            dup2(null, 2);
        }
        const char *names[] = {"7z", "7zz", NULL};
        for (int i = 0; names[i]; i++)
            execlp(names[i], names[i], "x", "-y", [outArg fileSystemRepresentation], [archive fileSystemRepresentation],
                   (char *)NULL);
        _exit(127);
    }
    int status = 0;
    for (;;) {
        pid_t r = waitpid(pid, &status, keepWaiting ? WNOHANG : 0);
        if (r == pid)
            break;
        if (r < 0)
            return -1;
        if (keepWaiting && !keepWaiting()) {
            kill(pid, 15);
            waitpid(pid, &status, 0);
            return -2;
        }
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void largest_file(NSString *dir, NSString **best, unsigned long long *size)
{
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        NSString *full = [dir stringByAppendingPathComponent:n];
        struct stat st;
        if (lstat([full fileSystemRepresentation], &st) != 0)
            continue;
        if (S_ISDIR(st.st_mode))
            largest_file(full, best, size);
        else if (S_ISREG(st.st_mode) && (unsigned long long)st.st_size > *size) {
            *size = (unsigned long long)st.st_size;
            *best = full;
        }
    }
}

NSString *IOpenDiskImage(NSString *dmg, NSString **error, BOOL (^keepWaiting)(void))
{
    const char *cache = getenv("XDG_CACHE_HOME");
    NSString *base = cache && *cache ? [NSString stringWithUTF8String:cache] : [NSHomeDirectory() stringByAppendingPathComponent:@".cache"];
    static int serial;
    NSString *dir = [[[base stringByAppendingPathComponent:@"ferry"] stringByAppendingPathComponent:@"installer"]
        stringByAppendingPathComponent:[NSString stringWithFormat:@"image-%d-%d", (int)getpid(), ++serial]];
    IRemoveTree(dir);
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    int r = run_7z(dmg, dir, keepWaiting);
    if (r == 127 || r == -1) {
        IRemoveTree(dir);
        if (error)
            *error = @"Opening disk images needs 7-Zip (the 7z command, in the 7zip or p7zip-full package), which isn't installed.";
        return nil;
    }
    /* Some images open as their partitions: then the volume is the largest one. */
    NSMutableArray *pkgs = [NSMutableArray array], *apps = [NSMutableArray array];
    find_installables(dir, 3, pkgs, apps);
    if (![pkgs count] && ![apps count]) {
        NSString *volume = nil;
        unsigned long long size = 0;
        largest_file(dir, &volume, &size);
        if (volume && size > 4096) {
            NSString *inner = [dir stringByAppendingPathComponent:@"volume"];
            [[NSFileManager defaultManager] createDirectoryAtPath:inner withIntermediateDirectories:YES attributes:nil
                                                            error:NULL];
            run_7z(volume, inner, keepWaiting);
            unlink([volume fileSystemRepresentation]);
        }
    }
    if (![[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL] count]) {
        IRemoveTree(dir);
        if (error)
            *error = @"7-Zip couldn't open this disk image (it may be encrypted, or in a form 7-Zip doesn't read).";
        return nil;
    }
    return dir;
}

NSString *IHumanSize(unsigned long long kb)
{
    if (kb < 1000)
        return [NSString stringWithFormat:@"%llu KB", kb ? kb : 1];
    if (kb < 1000 * 1000)
        return [NSString stringWithFormat:@"%.1f MB", kb / 1000.0];
    return [NSString stringWithFormat:@"%.2f GB", kb / 1000.0 / 1000.0];
}
