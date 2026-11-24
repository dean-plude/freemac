/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: cookies. NSHTTPCookie (made from properties or read
 * from Set-Cookie fields, as RFC 6265 describes them) and
 * NSHTTPCookieStorage. The shared storage is kept in memory and saves the
 * cookies that outlive the session to ~/.config/ferry/cookies/<app id>.plist,
 * beside the program's preferences (as a Mac keeps them in
 * ~/Library/Cookies); it is read back the next time the program asks for
 * it. Sessions send and store cookies through it (NSURLSession.m). Written
 * from Apple's public API documentation and RFC 6265. */
#import "FURLInternal.h"

NSHTTPCookiePropertyKey const NSHTTPCookieName = @"Name";
NSHTTPCookiePropertyKey const NSHTTPCookieValue = @"Value";
NSHTTPCookiePropertyKey const NSHTTPCookieOriginURL = @"OriginURL";
NSHTTPCookiePropertyKey const NSHTTPCookieVersion = @"Version";
NSHTTPCookiePropertyKey const NSHTTPCookieDomain = @"Domain";
NSHTTPCookiePropertyKey const NSHTTPCookiePath = @"Path";
NSHTTPCookiePropertyKey const NSHTTPCookieSecure = @"Secure";
NSHTTPCookiePropertyKey const NSHTTPCookieExpires = @"Expires";
NSHTTPCookiePropertyKey const NSHTTPCookieComment = @"Comment";
NSHTTPCookiePropertyKey const NSHTTPCookieCommentURL = @"CommentURL";
NSHTTPCookiePropertyKey const NSHTTPCookieDiscard = @"Discard";
NSHTTPCookiePropertyKey const NSHTTPCookieMaximumAge = @"Max-Age";
NSHTTPCookiePropertyKey const NSHTTPCookiePort = @"Port";
NSHTTPCookiePropertyKey const NSHTTPCookieSameSitePolicy = @"SameSite";
NSHTTPCookieStringPolicy const NSHTTPCookieSameSiteLax = @"lax";
NSHTTPCookieStringPolicy const NSHTTPCookieSameSiteStrict = @"strict";
static NSString *const HTTPOnlyKey = @"HttpOnly"; /* not a named constant on a Mac */
NSNotificationName const NSHTTPCookieManagerAcceptPolicyChangedNotification =
    @"NSHTTPCookieManagerAcceptPolicyChangedNotification";
NSNotificationName const NSHTTPCookieManagerCookiesChangedNotification =
    @"NSHTTPCookieManagerCookiesChangedNotification";

static NSString *trimmed(NSString *s)
{
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

/* ---- dates: RFC 6265's reading, which also takes the three forms of RFC 9110 ------------ */

static BOOL date_delimiter(unichar c)
{
    return c == 0x09 || (c >= 0x20 && c <= 0x2f) || (c >= 0x3b && c <= 0x40) || (c >= 0x5b && c <= 0x60) ||
           (c >= 0x7b && c <= 0x7e);
}

/* Leading digits of a token, at least min and at most max of them. */
static int leading_digits(const char *t, int min, int max, int *value)
{
    int n = 0, v = 0;
    while (t[n] >= '0' && t[n] <= '9') {
        v = v * 10 + (t[n] - '0');
        n++;
    }
    if (n < min || n > max)
        return 0;
    *value = v;
    return n;
}

NSDate *FParseHTTPDate(NSString *text)
{
    const char *s = [text UTF8String];
    if (!s)
        return nil;
    BOOL have_time = NO, have_day = NO, have_month = NO, have_year = NO;
    int hour = 0, minute = 0, second = 0, day = 0, month = 0, year = 0;
    static const char *const months[] = {"jan", "feb", "mar", "apr", "may", "jun",
                                         "jul", "aug", "sep", "oct", "nov", "dec"};
    size_t i = 0, n = strlen(s);
    while (i < n) {
        while (i < n && date_delimiter((unsigned char)s[i]))
            i++;
        size_t start = i;
        while (i < n && !date_delimiter((unsigned char)s[i]))
            i++;
        if (i == start)
            continue;
        char tok[64];
        size_t len = i - start < sizeof tok - 1 ? i - start : sizeof tok - 1;
        memcpy(tok, s + start, len);
        tok[len] = 0;
        int a, b, c, k;
        if (!have_time && (k = leading_digits(tok, 1, 2, &a)) && tok[k] == ':') {
            int k2 = leading_digits(tok + k + 1, 1, 2, &b);
            if (k2 && tok[k + 1 + k2] == ':' && leading_digits(tok + k + 2 + k2, 1, 2, &c)) {
                have_time = YES;
                hour = a;
                minute = b;
                second = c;
                continue;
            }
        }
        if (!have_day && (k = leading_digits(tok, 1, 2, &a)) && !(tok[k] >= '0' && tok[k] <= '9')) {
            have_day = YES;
            day = a;
            continue;
        }
        if (!have_month && len >= 3) {
            int m;
            for (m = 0; m < 12; m++)
                if (!strncasecmp(tok, months[m], 3))
                    break;
            if (m < 12) {
                have_month = YES;
                month = m + 1;
                continue;
            }
        }
        if (!have_year && (k = leading_digits(tok, 2, 4, &a)) && !(tok[k] >= '0' && tok[k] <= '9')) {
            have_year = YES;
            year = a;
            continue;
        }
    }
    if (have_year && year >= 70 && year <= 99)
        year += 1900;
    else if (have_year && year < 70)
        year += 2000;
    if (!have_time || !have_day || !have_month || !have_year || day < 1 || day > 31 || year < 1601 || hour > 23 ||
        minute > 59 || second > 59)
        return nil;
    int64_t t = FDaysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second;
    return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)t];
}

/* ---- matching hosts and paths (RFC 6265, 5.1.3 and 5.1.4) -------------------------------- */

/* The path of a URL as it is written, with a trailing slash kept. */
static NSString *raw_path(NSURL *url)
{
    NSString *s = [url absoluteString];
    NSRange r = [s rangeOfString:@"://"];
    if (r.location == NSNotFound)
        return @"/";
    s = [s substringFromIndex:NSMaxRange(r)];
    NSRange slash = [s rangeOfString:@"/"];
    if (slash.location == NSNotFound)
        return @"/";
    s = [s substringFromIndex:slash.location];
    NSRange end = [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"?#"]];
    if (end.location != NSNotFound)
        s = [s substringToIndex:end.location];
    return [s length] ? s : @"/";
}

static NSString *default_path(NSURL *url)
{
    NSString *p = raw_path(url);
    NSRange last = [p rangeOfString:@"/" options:NSBackwardsSearch];
    if (![p hasPrefix:@"/"] || last.location == 0 || last.location == NSNotFound)
        return @"/";
    return [p substringToIndex:last.location];
}

static BOOL is_ip_address(NSString *host)
{
    return [host rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789."]
                                             invertedSet]].location == NSNotFound ||
           [host hasPrefix:@"["] || [host rangeOfString:@":"].location != NSNotFound;
}

/* Whether a host is in a cookie's domain: the domain itself, or with a
 * leading dot (a cookie that named its domain) any host within it. */
static BOOL domain_matches(NSString *host, NSString *domain)
{
    host = [host lowercaseString];
    domain = [domain lowercaseString];
    if (!host || !domain)
        return NO;
    if (![domain hasPrefix:@"."])
        return [host isEqualToString:domain];
    NSString *bare = [domain substringFromIndex:1];
    return [host isEqualToString:bare] || ([host hasSuffix:domain] && !is_ip_address(host));
}

static BOOL path_matches(NSString *request, NSString *cookie)
{
    if ([request isEqualToString:cookie])
        return YES;
    return [request hasPrefix:cookie] &&
           ([cookie hasSuffix:@"/"] || [request characterAtIndex:[cookie length]] == '/');
}

static BOOL truthy(id v)
{
    if ([v isKindOfClass:[NSNumber class]])
        return [v boolValue];
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [v uppercaseString];
        return [s isEqualToString:@"TRUE"] || [s isEqualToString:@"YES"] || [s isEqualToString:@"1"];
    }
    return v != nil;
}

/* ---- NSHTTPCookie --------------------------------------------------------------------------- */

@interface NSHTTPCookie () {
    NSDictionary *_properties;
    NSString *_name, *_value, *_domain, *_path, *_comment, *_sameSite;
    NSURL *_commentURL;
    NSDate *_expires, *_created;
    NSArray *_ports;
    NSUInteger _version;
    BOOL _secure, _httpOnly, _session;
}
@end

@implementation NSHTTPCookie
+ (NSHTTPCookie *)cookieWithProperties:(NSDictionary *)properties
{
    return [[[self alloc] initWithProperties:properties] autorelease];
}
- (instancetype)initWithProperties:(NSDictionary *)p
{
    id name = [p objectForKey:NSHTTPCookieName], value = [p objectForKey:NSHTTPCookieValue];
    id domain = [p objectForKey:NSHTTPCookieDomain], origin = [p objectForKey:NSHTTPCookieOriginURL];
    id path = [p objectForKey:NSHTTPCookiePath];
    if ([origin isKindOfClass:[NSString class]])
        origin = [NSURL URLWithString:origin];
    if (![domain isKindOfClass:[NSString class]] || ![domain length])
        domain = [origin isKindOfClass:[NSURL class]] ? [origin host] : nil;
    if (![name isKindOfClass:[NSString class]] || ![name length] || ![value isKindOfClass:[NSString class]] ||
        ![domain length] || [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@";=,\r\n"]]
                                    .location != NSNotFound ||
        [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@";\r\n"]].location !=
            NSNotFound) {
        [self release];
        return nil;
    }
    if (![path isKindOfClass:[NSString class]] || ![path length])
        path = [origin isKindOfClass:[NSURL class]] ? default_path(origin) : @"/";
    _name = [name copy];
    _value = [value copy];
    _domain = [[domain lowercaseString] copy];
    _path = [path copy];
    id version = [p objectForKey:NSHTTPCookieVersion];
    _version = version ? (NSUInteger)[version integerValue] : 0;
    id max = [p objectForKey:NSHTTPCookieMaximumAge];
    id expires = [p objectForKey:NSHTTPCookieExpires];
    if (max && [[max description] length])
        _expires = [[NSDate dateWithTimeIntervalSinceNow:[[max description] doubleValue]] retain];
    else if ([expires isKindOfClass:[NSDate class]])
        _expires = [expires retain];
    else if ([expires isKindOfClass:[NSString class]])
        _expires = [FParseHTTPDate(expires) retain];
    _session = !_expires || truthy([p objectForKey:NSHTTPCookieDiscard]);
    _secure = truthy([p objectForKey:NSHTTPCookieSecure]);
    _httpOnly = truthy([p objectForKey:HTTPOnlyKey]);
    id comment = [p objectForKey:NSHTTPCookieComment];
    _comment = [comment isKindOfClass:[NSString class]] ? [comment copy] : nil;
    id curl = [p objectForKey:NSHTTPCookieCommentURL];
    _commentURL = [curl isKindOfClass:[NSURL class]] ? [curl copy]
                  : [curl isKindOfClass:[NSString class]] ? [[NSURL alloc] initWithString:curl] : nil;
    id ports = [p objectForKey:NSHTTPCookiePort];
    if ([ports isKindOfClass:[NSString class]]) {
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *part in [ports componentsSeparatedByString:@","])
            if ([trimmed(part) length])
                [list addObject:[NSNumber numberWithInteger:[trimmed(part) integerValue]]];
        _ports = [list copy];
    }
    id same = [p objectForKey:NSHTTPCookieSameSitePolicy];
    if ([same isKindOfClass:[NSString class]]) {
        if ([same caseInsensitiveCompare:@"lax"] == NSOrderedSame)
            _sameSite = [NSHTTPCookieSameSiteLax retain];
        else if ([same caseInsensitiveCompare:@"strict"] == NSOrderedSame)
            _sameSite = [NSHTTPCookieSameSiteStrict retain];
    }
    _created = [[NSDate date] retain];

    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    [props setObject:_name forKey:NSHTTPCookieName];
    [props setObject:_value forKey:NSHTTPCookieValue];
    [props setObject:_domain forKey:NSHTTPCookieDomain];
    [props setObject:_path forKey:NSHTTPCookiePath];
    [props setObject:[NSString stringWithFormat:@"%lu", (unsigned long)_version] forKey:NSHTTPCookieVersion];
    if (_expires)
        [props setObject:_expires forKey:NSHTTPCookieExpires];
    if (max)
        [props setObject:[max description] forKey:NSHTTPCookieMaximumAge];
    if (_secure)
        [props setObject:@"TRUE" forKey:NSHTTPCookieSecure];
    if (_httpOnly)
        [props setObject:@"TRUE" forKey:HTTPOnlyKey];
    if (_session && _expires)
        [props setObject:@"TRUE" forKey:NSHTTPCookieDiscard];
    if (_comment)
        [props setObject:_comment forKey:NSHTTPCookieComment];
    if (_commentURL)
        [props setObject:_commentURL forKey:NSHTTPCookieCommentURL];
    if ([ports isKindOfClass:[NSString class]])
        [props setObject:ports forKey:NSHTTPCookiePort];
    if (_sameSite)
        [props setObject:_sameSite forKey:NSHTTPCookieSameSitePolicy];
    if ([origin isKindOfClass:[NSURL class]])
        [props setObject:origin forKey:NSHTTPCookieOriginURL];
    _properties = [props copy];
    return self;
}
- (void)dealloc
{
    [_properties release];
    [_name release];
    [_value release];
    [_domain release];
    [_path release];
    [_comment release];
    [_sameSite release];
    [_commentURL release];
    [_expires release];
    [_created release];
    [_ports release];
    [super dealloc];
}
- (NSDictionary *)properties { return _properties; }
- (NSUInteger)version { return _version; }
- (NSString *)name { return _name; }
- (NSString *)value { return _value; }
- (NSDate *)expiresDate { return _expires; }
- (BOOL)isSessionOnly { return _session; }
- (NSString *)domain { return _domain; }
- (NSString *)path { return _path; }
- (BOOL)isSecure { return _secure; }
- (BOOL)isHTTPOnly { return _httpOnly; }
- (NSString *)comment { return _comment; }
- (NSURL *)commentURL { return _commentURL; }
- (NSArray *)portList { return _ports; }
- (NSString *)sameSitePolicy { return _sameSite; }
- (NSDate *)_created { return _created; }
- (BOOL)_expired { return _expires && [_expires timeIntervalSinceNow] <= 0; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSHTTPCookie class]])
        return NO;
    NSHTTPCookie *o = other;
    return [_name isEqualToString:o->_name] && [_domain isEqualToString:o->_domain] && [_path isEqualToString:o->_path];
}
- (NSUInteger)hash { return [_name hash] ^ [_domain hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSHTTPCookie version:%lu name:%@ value:%@ expiresDate:%@ sessionOnly:%s "
                                      @"domain:%@ path:%@ isSecure:%s isHTTPOnly:%s>",
                                      (unsigned long)_version, _name, _value, _expires ?: (id)@"(null)",
                                      _session ? "TRUE" : "FALSE", _domain, _path, _secure ? "TRUE" : "FALSE",
                                      _httpOnly ? "TRUE" : "FALSE"];
}
- (BOOL)_matchesURL:(NSURL *)url
{
    if ([self _expired] || !domain_matches([url host], _domain))
        return NO;
    if (_secure && ![[[url scheme] lowercaseString] isEqualToString:@"https"])
        return NO;
    if (_ports && [url port] && ![_ports containsObject:[url port]])
        return NO;
    return path_matches(raw_path(url), _path);
}

/* One Set-Cookie field's value (RFC 6265, 5.2). */
static NSHTTPCookie *parse_cookie(NSString *line, NSURL *url)
{
    NSArray *parts = [line componentsSeparatedByString:@";"];
    NSString *pair = [parts objectAtIndex:0];
    NSRange eq = [pair rangeOfString:@"="];
    if (eq.location == NSNotFound)
        return nil;
    NSString *name = trimmed([pair substringToIndex:eq.location]);
    NSString *value = trimmed([pair substringFromIndex:eq.location + 1]);
    if (![name length])
        return nil;
    NSString *host = [[url host] lowercaseString];
    if (![host length])
        return nil;
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:name forKey:NSHTTPCookieName];
    [p setObject:value forKey:NSHTTPCookieValue];
    [p setObject:@"0" forKey:NSHTTPCookieVersion];
    NSString *domain = nil, *path = nil;
    for (NSUInteger i = 1; i < [parts count]; i++) {
        NSString *attr = [parts objectAtIndex:i];
        NSRange e = [attr rangeOfString:@"="];
        NSString *key = trimmed(e.location == NSNotFound ? attr : [attr substringToIndex:e.location]);
        NSString *val = e.location == NSNotFound ? @"" : trimmed([attr substringFromIndex:e.location + 1]);
        NSString *k = [key lowercaseString];
        if ([k isEqualToString:@"expires"]) {
            NSDate *d = FParseHTTPDate(val);
            if (d)
                [p setObject:d forKey:NSHTTPCookieExpires];
        } else if ([k isEqualToString:@"max-age"]) {
            NSString *digits = [val hasPrefix:@"-"] ? [val substringFromIndex:1] : val;
            if ([digits length] && [digits rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet]
                                                                       invertedSet]].location == NSNotFound)
                [p setObject:[NSString stringWithFormat:@"%lld", [val longLongValue] > 0 ? [val longLongValue] : 0]
                      forKey:NSHTTPCookieMaximumAge];
        } else if ([k isEqualToString:@"domain"] && [val length]) {
            domain = [([val hasPrefix:@"."] ? [val substringFromIndex:1] : val) lowercaseString];
        } else if ([k isEqualToString:@"path"]) {
            path = [val hasPrefix:@"/"] ? val : nil;
        } else if ([k isEqualToString:@"secure"]) {
            [p setObject:@"TRUE" forKey:NSHTTPCookieSecure];
        } else if ([k isEqualToString:@"httponly"]) {
            [p setObject:@"TRUE" forKey:HTTPOnlyKey];
        } else if ([k isEqualToString:@"samesite"]) {
            [p setObject:val forKey:NSHTTPCookieSameSitePolicy];
        } else if ([k isEqualToString:@"comment"]) {
            [p setObject:val forKey:NSHTTPCookieComment];
        }
    }
    if (domain) {
        /* a domain the host isn't in is refused */
        if (![host isEqualToString:domain] && !([host hasSuffix:[@"." stringByAppendingString:domain]] &&
                                               !is_ip_address(host)))
            return nil;
        [p setObject:[@"." stringByAppendingString:domain] forKey:NSHTTPCookieDomain];
    } else
        [p setObject:host forKey:NSHTTPCookieDomain];
    [p setObject:path ?: default_path(url) forKey:NSHTTPCookiePath];
    return [NSHTTPCookie cookieWithProperties:p];
}

+ (NSArray *)_cookiesFromValues:(NSArray *)values forURL:(NSURL *)url
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *v in values) {
        NSHTTPCookie *c = parse_cookie(v, url);
        if (c)
            [out addObject:c];
    }
    return out;
}

/* Several Set-Cookie fields joined with commas, as allHeaderFields gives
 * them: a comma ends a cookie, except the one after an Expires date's
 * weekday. */
static NSArray *split_joined(NSString *joined)
{
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger start = 0, attr = 0, n = [joined length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [joined characterAtIndex:i];
        if (c == ';')
            attr = i + 1;
        else if (c == ',') {
            NSString *current = [trimmed([joined substringWithRange:NSMakeRange(attr, i - attr)]) lowercaseString];
            if ([current hasPrefix:@"expires="] && [current rangeOfString:@","].location == NSNotFound &&
                [current length] <= 8 + 9)
                continue;
            [out addObject:[joined substringWithRange:NSMakeRange(start, i - start)]];
            start = attr = i + 1;
        }
    }
    if (start < n)
        [out addObject:[joined substringFromIndex:start]];
    return out;
}

+ (NSArray *)cookiesWithResponseHeaderFields:(NSDictionary *)headerFields forURL:(NSURL *)URL
{
    NSMutableArray *values = [NSMutableArray array];
    for (NSString *k in headerFields)
        if ([k isKindOfClass:[NSString class]] && [k caseInsensitiveCompare:@"Set-Cookie"] == NSOrderedSame)
            [values addObjectsFromArray:split_joined([headerFields objectForKey:k])];
    return [self _cookiesFromValues:values forURL:URL];
}

+ (NSDictionary *)requestHeaderFieldsWithCookies:(NSArray *)cookies
{
    if (![cookies count])
        return [NSDictionary dictionary];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSHTTPCookie *c in cookies)
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [c name], [c value]]];
    return [NSDictionary dictionaryWithObject:[pairs componentsJoinedByString:@"; "] forKey:@"Cookie"];
}
@end

/* ---- NSHTTPCookieStorage -------------------------------------------------------------------- */

@interface NSHTTPCookieStorage () {
    NSMutableArray *_cookies;
    NSHTTPCookieAcceptPolicy _policy;
    NSString *_file; /* where the shared storage saves; nil for one in memory only */
}
@end

@implementation NSHTTPCookieStorage
static NSHTTPCookieStorage *shared_storage;

+ (NSHTTPCookieStorage *)sharedHTTPCookieStorage
{
    if (!shared_storage) {
        shared_storage = [[self alloc] init];
        NSString *dir = [[FConfigHome() stringByAppendingPathComponent:@"ferry"] stringByAppendingPathComponent:@"cookies"];
        shared_storage->_file = [[dir stringByAppendingPathComponent:[FURLAppID() stringByAppendingPathExtension:@"plist"]]
            copy];
        for (NSDictionary *p in [NSArray arrayWithContentsOfFile:shared_storage->_file]) {
            NSHTTPCookie *c = [p isKindOfClass:[NSDictionary class]] ? [NSHTTPCookie cookieWithProperties:p] : nil;
            if (c && ![c _expired] && ![c isSessionOnly])
                [shared_storage->_cookies addObject:c];
        }
    }
    return shared_storage;
}
+ (NSHTTPCookieStorage *)sharedCookieStorageForGroupContainerIdentifier:(NSString *)identifier
{
    return [self sharedHTTPCookieStorage];
}
+ (instancetype)_privateStorage { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    _cookies = [[NSMutableArray alloc] init];
    _policy = NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain;
    return self;
}
- (void)dealloc
{
    [_cookies release];
    [_file release];
    [super dealloc];
}
- (void)_save
{
    if (!_file)
        return;
    NSMutableArray *keep = [NSMutableArray array];
    for (NSHTTPCookie *c in _cookies)
        if (![c isSessionOnly] && ![c _expired]) {
            NSMutableDictionary *p = [[[c properties] mutableCopy] autorelease];
            [p removeObjectForKey:NSHTTPCookieMaximumAge]; /* the expiry date says it */
            if ([[p objectForKey:NSHTTPCookieOriginURL] isKindOfClass:[NSURL class]])
                [p setObject:[[p objectForKey:NSHTTPCookieOriginURL] absoluteString] forKey:NSHTTPCookieOriginURL];
            if ([[p objectForKey:NSHTTPCookieCommentURL] isKindOfClass:[NSURL class]])
                [p setObject:[[p objectForKey:NSHTTPCookieCommentURL] absoluteString] forKey:NSHTTPCookieCommentURL];
            [keep addObject:p];
        }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![keep count]) {
        if ([fm fileExistsAtPath:_file])
            [fm removeItemAtPath:_file error:NULL];
        return;
    }
    [fm createDirectoryAtPath:[_file stringByDeletingLastPathComponent] withIntermediateDirectories:YES
                   attributes:nil error:NULL];
    [keep writeToFile:_file atomically:YES];
}
- (void)_changed
{
    [self _save];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSHTTPCookieManagerCookiesChangedNotification
                                                        object:self];
}
- (void)_drop:(NSHTTPCookie *)cookie
{
    NSUInteger i = [_cookies indexOfObject:cookie];
    if (i != NSNotFound)
        [_cookies removeObjectAtIndex:i];
}
- (NSArray *)cookies
{
    NSMutableArray *live = [NSMutableArray array];
    for (NSHTTPCookie *c in _cookies)
        if (![c _expired])
            [live addObject:c];
    return live;
}
/* Puts a cookie in, replacing one of the same name, domain and path; an
 * expired one only takes the old one out. */
- (BOOL)_put:(NSHTTPCookie *)cookie
{
    if (!cookie)
        return NO;
    [self _drop:cookie];
    if (![cookie _expired])
        [_cookies addObject:cookie];
    return YES;
}
- (void)setCookie:(NSHTTPCookie *)cookie
{
    if (_policy == NSHTTPCookieAcceptPolicyNever || !cookie)
        return;
    [self _put:cookie];
    [self _changed];
}
- (void)deleteCookie:(NSHTTPCookie *)cookie
{
    if (!cookie || [_cookies indexOfObject:cookie] == NSNotFound)
        return;
    [self _drop:cookie];
    [self _changed];
}
- (void)removeCookiesSinceDate:(NSDate *)date
{
    NSUInteger before = [_cookies count];
    for (NSHTTPCookie *c in [[_cookies copy] autorelease])
        if ([[c _created] compare:date] != NSOrderedAscending)
            [_cookies removeObjectIdenticalTo:c];
    if ([_cookies count] != before)
        [self _changed];
}
static NSInteger by_path_then_age(id a, id b, void *ctx)
{
    NSUInteger la = [[a path] length], lb = [[b path] length];
    if (la != lb)
        return la > lb ? NSOrderedAscending : NSOrderedDescending;
    return [[a _created] compare:[b _created]];
}
- (NSArray *)cookiesForURL:(NSURL *)URL
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSHTTPCookie *c in _cookies)
        if ([c _matchesURL:URL])
            [out addObject:c];
    return [out sortedArrayUsingFunction:by_path_then_age context:NULL];
}
static BOOL same_site(NSString *host, NSString *main)
{
    host = [host lowercaseString];
    main = [main lowercaseString];
    return [host isEqualToString:main] || [host hasSuffix:[@"." stringByAppendingString:main]] ||
           [main hasSuffix:[@"." stringByAppendingString:host]];
}
- (void)_setCookies:(NSArray *)cookies forURL:(NSURL *)url mainDocumentURL:(NSURL *)main
             policy:(NSHTTPCookieAcceptPolicy)policy
{
    if (policy == NSHTTPCookieAcceptPolicyNever || ![cookies count])
        return;
    if (policy == NSHTTPCookieAcceptPolicyOnlyFromMainDocumentDomain && main && !same_site([url host], [main host]))
        return;
    BOOL any = NO;
    for (NSHTTPCookie *c in cookies)
        if ([c isKindOfClass:[NSHTTPCookie class]] && (!url || domain_matches([url host], [c domain]) ||
                                                       domain_matches([c domain], [url host])))
            any |= [self _put:c];
    if (any)
        [self _changed];
}
- (void)setCookies:(NSArray *)cookies forURL:(NSURL *)URL mainDocumentURL:(NSURL *)mainDocumentURL
{
    [self _setCookies:cookies forURL:URL mainDocumentURL:mainDocumentURL policy:_policy];
}
- (NSHTTPCookieAcceptPolicy)cookieAcceptPolicy { return _policy; }
- (void)setCookieAcceptPolicy:(NSHTTPCookieAcceptPolicy)policy
{
    if (policy == _policy)
        return;
    _policy = policy;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSHTTPCookieManagerAcceptPolicyChangedNotification
                                                        object:self];
}
- (NSArray *)sortedCookiesUsingDescriptors:(NSArray *)sortOrder
{
    return [[self cookies] sortedArrayUsingDescriptors:sortOrder];
}
- (void)storeCookies:(NSArray *)cookies forTask:(NSURLSessionTask *)task
{
    NSURLRequest *r = [task currentRequest];
    [self setCookies:cookies forURL:[r URL] mainDocumentURL:[r mainDocumentURL]];
}
- (void)getCookiesForTask:(NSURLSessionTask *)task completionHandler:(void (^)(NSArray<NSHTTPCookie *> *))completionHandler
{
    if (completionHandler)
        completionHandler([self cookiesForURL:[[task currentRequest] URL]]);
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSHTTPCookieStorage %p>: %lu cookies", self, (unsigned long)[_cookies count]];
}
@end
