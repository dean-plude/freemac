/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSDate (seconds since 1 January 2001 UTC, the Mac's
 * reference date) and NSURL. */
#import "FInternal.h"
#include <time.h>
#include <sys/time.h>

/* ---- NSDate ----------------------------------------------------------------------- */

static NSTimeInterval now_since_reference(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec + tv.tv_usec / 1e6 - NSTimeIntervalSince1970;
}

@interface FDate : NSDate {
@public
    NSTimeInterval _t;
}
@end

@implementation NSDate
+ (instancetype)allocWithZone:(NSZone *)zone
{
    if (self == [NSDate class])
        return [FDate allocWithZone:zone];
    return [super allocWithZone:zone];
}
+ (instancetype)date { return [[[self alloc] init] autorelease]; }
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)secs
{
    return [[[self alloc] initWithTimeIntervalSinceNow:secs] autorelease];
}
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)secs
{
    return [[[self alloc] initWithTimeIntervalSince1970:secs] autorelease];
}
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    return [[[self alloc] initWithTimeIntervalSinceReferenceDate:secs] autorelease];
}
+ (instancetype)distantFuture { return [self dateWithTimeIntervalSinceReferenceDate:63113904000.0]; }
+ (instancetype)distantPast { return [self dateWithTimeIntervalSinceReferenceDate:-63114076800.0]; }
+ (NSTimeInterval)timeIntervalSinceReferenceDate { return now_since_reference(); }
- (instancetype)init { return [self initWithTimeIntervalSinceReferenceDate:now_since_reference()]; }
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs { return self; }
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)secs
{
    return [self initWithTimeIntervalSinceReferenceDate:now_since_reference() + secs];
}
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)secs
{
    return [self initWithTimeIntervalSinceReferenceDate:secs - NSTimeIntervalSince1970];
}
- (NSTimeInterval)timeIntervalSinceReferenceDate { return 0; }
- (NSTimeInterval)timeIntervalSince1970 { return [self timeIntervalSinceReferenceDate] + NSTimeIntervalSince1970; }
- (NSTimeInterval)timeIntervalSinceNow { return [self timeIntervalSinceReferenceDate] - now_since_reference(); }
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)other
{
    return [self timeIntervalSinceReferenceDate] - [other timeIntervalSinceReferenceDate];
}
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)secs
{
    return [[[[self class] alloc] initWithTimeIntervalSinceReferenceDate:[self timeIntervalSinceReferenceDate] + secs]
        autorelease];
}
- (NSDate *)earlierDate:(NSDate *)other { return [self compare:other] == NSOrderedDescending ? other : self; }
- (NSDate *)laterDate:(NSDate *)other { return [self compare:other] == NSOrderedAscending ? other : self; }
- (NSComparisonResult)compare:(NSDate *)other
{
    NSTimeInterval a = [self timeIntervalSinceReferenceDate], b = [other timeIntervalSinceReferenceDate];
    return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}
- (BOOL)isEqualToDate:(NSDate *)other
{
    return other && [self timeIntervalSinceReferenceDate] == [other timeIntervalSinceReferenceDate];
}
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[NSDate class]] && [self isEqualToDate:other]; }
- (NSUInteger)hash { return (NSUInteger)(long long)[self timeIntervalSinceReferenceDate]; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)description
{
    time_t t = (time_t)floor([self timeIntervalSince1970]);
    struct tm tm;
    char buf[64];
    gmtime_r(&t, &tm);
    strftime(buf, sizeof buf, "%Y-%m-%d %H:%M:%S +0000", &tm);
    return [NSString stringWithUTF8String:buf];
}
/* nil gives the description; a locale (an NSLocale, or a dictionary such as
 * the user defaults, which means the user's own) gives the date and time in
 * the local time zone, written out in full. */
- (NSString *)descriptionWithLocale:(id)locale
{
    if (!locale)
        return [self description];
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setLocale:[locale isKindOfClass:[NSLocale class]] ? locale : [NSLocale currentLocale]];
    [f setDateStyle:NSDateFormatterFullStyle];
    [f setTimeStyle:NSDateFormatterFullStyle];
    NSString *s = [f stringFromDate:self];
    [f release];
    return s;
}
@end

@implementation FDate
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs
{
    _t = secs;
    return self;
}
- (NSTimeInterval)timeIntervalSinceReferenceDate { return _t; }
@end

/* ---- NSURL --------------------------------------------------------------------------- */

@interface NSURL () {
    NSString *_string;
    NSURL *_base;
    NSString *_scheme, *_host, *_path, *_query, *_fragment, *_user;
    NSNumber *_port;
}
@end

static NSString *percent_decode(NSString *s)
{
    if (!s || [s rangeOfString:@"%"].location == NSNotFound)
        return s;
    const char *in = [s UTF8String];
    size_t n = strlen(in), k = 0;
    char *out = malloc(n + 1);
    for (size_t i = 0; i < n; i++) {
        int hi, lo;
        if (in[i] == '%' && i + 2 < n && sscanf(in + i + 1, "%1x%1x", &hi, &lo) == 2) {
            out[k++] = (char)(hi << 4 | lo);
            i += 2;
        } else {
            out[k++] = in[i];
        }
    }
    NSString *r = FStringFromUTF8(out, k);
    free(out);
    return r;
}

static NSString *percent_encode_path(NSString *s)
{
    const unsigned char *in = (const unsigned char *)[s UTF8String];
    NSMutableString *out = [NSMutableString string];
    for (; *in; in++) {
        if ((*in >= 'a' && *in <= 'z') || (*in >= 'A' && *in <= 'Z') || (*in >= '0' && *in <= '9') ||
            strchr("/-._~!$&'()*+,;=:@", *in))
            [out appendFormat:@"%c", *in];
        else
            [out appendFormat:@"%%%02X", *in];
    }
    return out;
}

@implementation NSURL
+ (instancetype)URLWithString:(NSString *)s { return [[[self alloc] initWithString:s] autorelease]; }
+ (instancetype)URLWithString:(NSString *)s relativeToURL:(NSURL *)base
{
    return [[[self alloc] initWithString:s relativeToURL:base] autorelease];
}
+ (NSURL *)fileURLWithPath:(NSString *)path { return [[[self alloc] initFileURLWithPath:path] autorelease]; }
+ (NSURL *)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir
{
    if (isDir && ![path hasSuffix:@"/"])
        path = [path stringByAppendingString:@"/"];
    return [self fileURLWithPath:path];
}
- (instancetype)initFileURLWithPath:(NSString *)path
{
    if (![path isAbsolutePath])
        path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
    BOOL dir = NO;
    if (![path hasSuffix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] && dir)
        path = [path stringByAppendingString:@"/"];
    return [self initWithString:[@"file://" stringByAppendingString:percent_encode_path(path)]];
}
- (instancetype)initWithString:(NSString *)s { return [self initWithString:s relativeToURL:nil]; }
- (instancetype)initWithString:(NSString *)s relativeToURL:(NSURL *)base
{
    if (!s) {
        [self release];
        return nil;
    }
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c <= ' ' || c >= 0x7f || c == '"' || c == '<' || c == '>' || c == '\\' || c == '^' || c == '`' ||
            c == '{' || c == '|' || c == '}') {
            [self release];
            return nil;
        }
    }
    _string = [s copy];
    _base = [base retain];
    NSString *rest = s;
    NSRange r = [rest rangeOfString:@"#"];
    if (r.location != NSNotFound) {
        _fragment = [[rest substringFromIndex:r.location + 1] copy];
        rest = [rest substringToIndex:r.location];
    }
    r = [rest rangeOfString:@"?"];
    if (r.location != NSNotFound) {
        _query = [[rest substringFromIndex:r.location + 1] copy];
        rest = [rest substringToIndex:r.location];
    }
    r = [rest rangeOfString:@":"];
    NSRange slash = [rest rangeOfString:@"/"];
    if (r.location != NSNotFound && r.location > 0 && (slash.location == NSNotFound || r.location < slash.location)) {
        _scheme = [[rest substringToIndex:r.location] copy];
        rest = [rest substringFromIndex:r.location + 1];
    }
    if ([rest hasPrefix:@"//"]) {
        rest = [rest substringFromIndex:2];
        NSRange p = [rest rangeOfString:@"/"];
        NSString *auth = p.location == NSNotFound ? rest : [rest substringToIndex:p.location];
        rest = p.location == NSNotFound ? @"" : [rest substringFromIndex:p.location];
        NSRange at = [auth rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) {
            _user = [[auth substringToIndex:at.location] copy];
            auth = [auth substringFromIndex:at.location + 1];
        }
        NSRange colon = [auth rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location != NSNotFound && ![auth hasSuffix:@"]"]) {
            _port = [[NSNumber numberWithInteger:[[auth substringFromIndex:colon.location + 1] integerValue]] retain];
            auth = [auth substringToIndex:colon.location];
        }
        _host = [auth copy];
    }
    _path = [rest copy];
    if (!_scheme && base) {
        /* A relative reference: resolve it against the base (RFC 3986, 5.2). */
        NSString *bpath = base->_path ?: @"";
        NSString *path;
        if ([_path hasPrefix:@"/"])
            path = _path;
        else if ([_path length] == 0)
            path = bpath;
        else {
            NSRange last = [bpath rangeOfString:@"/" options:NSBackwardsSearch];
            path = [(last.location == NSNotFound ? @"" : [bpath substringToIndex:last.location + 1])
                stringByAppendingString:_path];
        }
        NSMutableArray *parts = [NSMutableArray array];
        NSArray *segs = [path componentsSeparatedByString:@"/"];
        for (NSUInteger i = 0; i < [segs count]; i++) {
            NSString *seg = [segs objectAtIndex:i];
            if ([seg isEqualToString:@"."])
                continue;
            if ([seg isEqualToString:@".."]) {
                if ([parts count] > 1)
                    [parts removeLastObject];
                continue;
            }
            [parts addObject:seg];
        }
        if ([segs count] && ([[segs lastObject] isEqualToString:@"."] || [[segs lastObject] isEqualToString:@".."]))
            [parts addObject:@""];
        [_path release];
        _path = [[parts componentsJoinedByString:@"/"] copy];
        _scheme = [base->_scheme copy];
        if (!_host) {
            _host = [base->_host copy];
            _port = [base->_port retain];
            _user = [base->_user copy];
        }
        if (!_query && [rest length] == 0)
            _query = [base->_query copy];
    }
    return self;
}
- (void)dealloc
{
    [_string release];
    [_base release];
    [_scheme release];
    [_host release];
    [_path release];
    [_query release];
    [_fragment release];
    [_user release];
    [_port release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)absoluteString
{
    if (!_base)
        return _string;
    NSMutableString *s = [NSMutableString string];
    if (_scheme)
        [s appendFormat:@"%@:", _scheme];
    if (_host) {
        [s appendString:@"//"];
        if (_user)
            [s appendFormat:@"%@@", _user];
        [s appendString:_host];
        if (_port)
            [s appendFormat:@":%@", _port];
    }
    [s appendString:_path ?: @""];
    if (_query)
        [s appendFormat:@"?%@", _query];
    if (_fragment)
        [s appendFormat:@"#%@", _fragment];
    return s;
}
- (NSURL *)absoluteURL { return _base ? [NSURL URLWithString:[self absoluteString]] : self; }
- (NSString *)relativeString { return _string; }
- (NSURL *)baseURL { return _base; }
- (NSString *)scheme { return _scheme; }
- (NSString *)host { return _host; }
- (NSNumber *)port { return _port; }
/* The user information is "user:password"; each part comes back decoded. */
- (NSString *)user
{
    if (!_user)
        return nil;
    NSRange colon = [_user rangeOfString:@":"];
    return percent_decode(colon.location == NSNotFound ? _user : [_user substringToIndex:colon.location]);
}
- (NSString *)password
{
    NSRange colon = _user ? [_user rangeOfString:@":"] : NSMakeRange(NSNotFound, 0);
    return colon.location == NSNotFound ? nil : percent_decode([_user substringFromIndex:colon.location + 1]);
}
- (NSString *)query { return _query; }
- (NSString *)fragment { return _fragment; }
- (NSString *)path
{
    NSString *p = percent_decode(_path);
    if ([p length] > 1 && [p hasSuffix:@"/"])
        p = [p substringToIndex:[p length] - 1];
    return p;
}
/* The path as the URL was written, not resolved against its base (freemac
 * 1.NEXT); the same as path for a URL with no base. */
- (NSString *)relativePath
{
    if (!_base)
        return [self path];
    NSString *rest = _string;
    NSRange r = [rest rangeOfString:@"#"];
    if (r.location != NSNotFound)
        rest = [rest substringToIndex:r.location];
    r = [rest rangeOfString:@"?"];
    if (r.location != NSNotFound)
        rest = [rest substringToIndex:r.location];
    NSRange colon = [rest rangeOfString:@":"], slash = [rest rangeOfString:@"/"];
    if ((colon.location != NSNotFound && colon.location > 0 &&
         (slash.location == NSNotFound || colon.location < slash.location)) ||
        [rest hasPrefix:@"//"])
        return [self path];
    NSString *p = percent_decode(rest);
    if ([p length] > 1 && [p hasSuffix:@"/"])
        p = [p substringToIndex:[p length] - 1];
    return p;
}
- (NSString *)lastPathComponent { return [[self path] lastPathComponent]; }
- (NSString *)pathExtension { return [[self path] pathExtension]; }
- (NSArray *)pathComponents { return [[self path] pathComponents]; }
- (BOOL)isFileURL { return [_scheme caseInsensitiveCompare:@"file"] == NSOrderedSame; }
- (BOOL)hasDirectoryPath { return [_path hasSuffix:@"/"]; }
- (const char *)fileSystemRepresentation { return [[self path] fileSystemRepresentation]; }
- (NSURL *)withPath:(NSString *)path
{
    NSMutableString *s = [NSMutableString string];
    if (_scheme)
        [s appendFormat:@"%@:", _scheme];
    if (_host) {
        [s appendString:@"//"];
        if (_user)
            [s appendFormat:@"%@@", _user];
        [s appendString:_host];
        if (_port)
            [s appendFormat:@":%@", _port];
    }
    [s appendString:percent_encode_path(path)];
    if (_query)
        [s appendFormat:@"?%@", _query];
    return [NSURL URLWithString:s];
}
- (NSURL *)URLByAppendingPathComponent:(NSString *)component isDirectory:(BOOL)isDir
{
    NSString *p = percent_decode(_path) ?: @"";
    if (![p hasSuffix:@"/"])
        p = [p stringByAppendingString:@"/"];
    p = [p stringByAppendingString:component];
    if (isDir && ![p hasSuffix:@"/"])
        p = [p stringByAppendingString:@"/"];
    return [self withPath:p];
}
- (NSURL *)URLByAppendingPathComponent:(NSString *)component
{
    BOOL dir = NO;
    if ([self isFileURL]) {
        NSString *full = [[self path] stringByAppendingPathComponent:component];
        [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&dir];
    }
    return [self URLByAppendingPathComponent:component isDirectory:dir];
}
- (NSURL *)URLByAppendingPathExtension:(NSString *)ext
{
    return [self withPath:[[self path] stringByAppendingPathExtension:ext]];
}
- (NSURL *)URLByDeletingLastPathComponent
{
    NSString *p = [[self path] stringByDeletingLastPathComponent];
    if (![p hasSuffix:@"/"])
        p = [p stringByAppendingString:@"/"];
    return [self withPath:p];
}
- (NSURL *)URLByDeletingPathExtension { return [self withPath:[[self path] stringByDeletingPathExtension]]; }
- (NSURL *)URLByStandardizingPath { return [self withPath:[[self path] stringByStandardizingPath]]; }
/* freemac 1.262 (IINA): the URL with . and .. taken out of its path */
- (NSURL *)standardizedURL { return [self path] ? [self URLByStandardizingPath] : self; }
- (NSURL *)URLByResolvingSymlinksInPath
{
    if (![self isFileURL])
        return self;
    char buf[4096];
    if (!realpath([[self path] fileSystemRepresentation], buf))
        return [self URLByStandardizingPath];
    return [self withPath:[NSString stringWithUTF8String:buf]];
}
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSURL class]] && [[self absoluteString] isEqualToString:[other absoluteString]];
}
- (NSUInteger)hash { return [[self absoluteString] hash]; }
- (NSString *)description
{
    if (_base)
        return [NSString stringWithFormat:@"%@ -- %@", _string, _base];
    return _string;
}
@end
