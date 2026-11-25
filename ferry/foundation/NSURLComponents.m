/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSURLComponents and NSURLQueryItem (freemac 1.225, Ferry 0.49.0): a URL
 * taken apart into its scheme, user, password, host, port, path, query and
 * fragment by RFC 3986's grammar, each kept as it is written (percent
 * encoded), and put together again. Written for freemac from Apple's public
 * API documentation and RFC 3986. KeePassKit builds its otpauth: URLs with
 * these. */
#import "FInternal.h"
#import <Foundation/NSURLComponents.h>

@implementation NSURLQueryItem {
    NSString *_name, *_value;
}
+ (instancetype)queryItemWithName:(NSString *)name value:(NSString *)value
{
    return [[[self alloc] initWithName:name value:value] autorelease];
}
- (instancetype)initWithName:(NSString *)name value:(NSString *)value
{
    if ((self = [super init])) {
        _name = [name copy];
        _value = [value copy];
    }
    return self;
}
- (void)dealloc
{
    [_name release];
    [_value release];
    [super dealloc];
}
- (NSString *)name { return _name; }
- (NSString *)value { return _value; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_name forKey:@"NS.name"];
    [coder encodeObject:_value forKey:@"NS.value"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    return [self initWithName:[coder decodeObjectForKey:@"NS.name"] value:[coder decodeObjectForKey:@"NS.value"]];
}
- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[NSURLQueryItem class]])
        return NO;
    NSURLQueryItem *o = other;
    return (_name == o->_name || [_name isEqual:o->_name]) && (_value == o->_value || [_value isEqual:o->_value]);
}
- (NSUInteger)hash { return [_name hash]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSURLQueryItem %p> {name = %@, value = %@}", self, _name,
                                      _value ? _value : @"(null)"];
}
@end

/* The characters each part may hold as they are, beyond the unreserved ones */
static NSCharacterSet *allowed(NSCharacterSet *base, NSString *without)
{
    NSMutableCharacterSet *s = [[base mutableCopy] autorelease];
    if (without)
        [s removeCharactersInString:without];
    return s;
}
static NSString *encode(NSString *s, NSCharacterSet *set)
{
    return s ? [s stringByAddingPercentEncodingWithAllowedCharacters:set] : nil;
}
static NSString *decode(NSString *s) { return s ? [s stringByRemovingPercentEncoding] : nil; }

@implementation NSURLComponents {
    NSString *_scheme, *_user, *_password, *_host, *_path, *_query, *_fragment;
    NSNumber *_port;
}
+ (instancetype)componentsWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve
{
    return [[[self alloc] initWithURL:url resolvingAgainstBaseURL:resolve] autorelease];
}
+ (instancetype)componentsWithString:(NSString *)string { return [[[self alloc] initWithString:string] autorelease]; }
- (instancetype)init
{
    if ((self = [super init]))
        _path = @"";
    return self;
}
- (instancetype)initWithURL:(NSURL *)url resolvingAgainstBaseURL:(BOOL)resolve
{
    return [self initWithString:resolve ? [url absoluteString] : [url relativeString]];
}
static BOOL valid_url_chars(NSString *s)
{
    for (NSUInteger i = 0, n = [s length]; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c <= ' ' || c >= 0x7f || c == '"' || c == '<' || c == '>' || c == '\\' || c == '^' || c == '`'
            || c == '{' || c == '|' || c == '}')
            return NO;
    }
    return YES;
}
/* RFC 3986, appendix B: scheme ":" "//" authority path "?" query "#" fragment */
- (instancetype)initWithString:(NSString *)string
{
    if (!(self = [self init]))
        return nil;
    if (!string || !valid_url_chars(string)) {
        [self release];
        return nil;
    }
    NSString *s = string;
    NSRange hash = [s rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        _fragment = [[s substringFromIndex:hash.location + 1] copy];
        s = [s substringToIndex:hash.location];
    }
    NSRange q = [s rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        _query = [[s substringFromIndex:q.location + 1] copy];
        s = [s substringToIndex:q.location];
    }
    NSRange colon = [s rangeOfString:@":"];
    if (colon.location != NSNotFound && colon.location > 0) {
        NSString *scheme = [s substringToIndex:colon.location];
        if ([scheme rangeOfString:@"/"].location == NSNotFound) {
            unichar c0 = [scheme characterAtIndex:0];
            if (!((c0 >= 'a' && c0 <= 'z') || (c0 >= 'A' && c0 <= 'Z'))) {
                [self release];
                return nil;
            }
            _scheme = [scheme copy];
            s = [s substringFromIndex:colon.location + 1];
        }
    }
    if ([s hasPrefix:@"//"]) {
        s = [s substringFromIndex:2];
        NSRange slash = [s rangeOfString:@"/"];
        NSString *authority = slash.location == NSNotFound ? s : [s substringToIndex:slash.location];
        s = slash.location == NSNotFound ? @"" : [s substringFromIndex:slash.location];
        NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
        if (at.location != NSNotFound) {
            NSString *info = [authority substringToIndex:at.location];
            authority = [authority substringFromIndex:at.location + 1];
            NSRange c = [info rangeOfString:@":"];
            if (c.location != NSNotFound) {
                _user = [[info substringToIndex:c.location] copy];
                _password = [[info substringFromIndex:c.location + 1] copy];
            } else
                _user = [info copy];
        }
        /* the port follows the last colon, outside an IPv6 literal's brackets */
        NSRange pc = [authority rangeOfString:@":" options:NSBackwardsSearch];
        NSRange br = [authority rangeOfString:@"]" options:NSBackwardsSearch];
        if (pc.location != NSNotFound && (br.location == NSNotFound || pc.location > br.location)) {
            NSString *port = [authority substringFromIndex:pc.location + 1];
            authority = [authority substringToIndex:pc.location];
            for (NSUInteger i = 0; i < [port length]; i++)
                if ([port characterAtIndex:i] < '0' || [port characterAtIndex:i] > '9') {
                    [self release];
                    return nil;
                }
            if ([port length])
                _port = [[NSNumber numberWithInteger:[port integerValue]] retain];
        }
        _host = [authority copy];
    }
    [_path release];
    _path = [s copy];
    return self;
}
- (void)dealloc
{
    [_scheme release];
    [_user release];
    [_password release];
    [_host release];
    [_port release];
    [_path release];
    [_query release];
    [_fragment release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSURLComponents *c = [[NSURLComponents alloc] init];
    c.scheme = _scheme;
    c.percentEncodedUser = _user;
    c.percentEncodedPassword = _password;
    c.percentEncodedHost = _host;
    c.port = _port;
    c.percentEncodedPath = _path;
    c.percentEncodedQuery = _query;
    c.percentEncodedFragment = _fragment;
    return c;
}

/* The URL's text, and where each part is in it (index 0 to 7: scheme, user,
 * password, host, port, path, query, fragment). */
- (NSString *)stringWithRanges:(NSRange *)ranges
{
    NSMutableString *m = [NSMutableString string];
    for (int i = 0; i < 8; i++)
        ranges[i] = NSMakeRange(NSNotFound, 0);
#define PART(i, s)                                                                                            \
    do {                                                                                                      \
        ranges[i] = NSMakeRange([m length], [(s) length]);                                                    \
        [m appendString:(s)];                                                                                 \
    } while (0)
    if (_scheme) {
        PART(0, _scheme);
        [m appendString:@":"];
    }
    if (_host || _user || _password || _port) {
        [m appendString:@"//"];
        if (_user || _password) {
            if (_user)
                PART(1, _user);
            if (_password) {
                [m appendString:@":"];
                PART(2, _password);
            }
            [m appendString:@"@"];
        }
        if (_host)
            PART(3, _host);
        if (_port) {
            [m appendString:@":"];
            PART(4, [_port stringValue]);
        }
    }
    PART(5, _path ? _path : @"");
    if (_query) {
        [m appendString:@"?"];
        PART(6, _query);
    }
    if (_fragment) {
        [m appendString:@"#"];
        PART(7, _fragment);
    }
#undef PART
    return m;
}
- (NSString *)string
{
    NSRange r[8];
    return [self stringWithRanges:r];
}
- (NSURL *)URL { return [self URLRelativeToURL:nil]; }
- (NSURL *)URLRelativeToURL:(NSURL *)baseURL
{
    /* with an authority, a path must be empty or begin with a slash */
    if ((_host || _user || _password || _port) && [_path length] && ![_path hasPrefix:@"/"])
        return nil;
    /* without one, a path can't begin with two slashes */
    if (!(_host || _user || _password || _port) && [_path hasPrefix:@"//"])
        return nil;
    return [NSURL URLWithString:[self string] relativeToURL:baseURL];
}
- (NSRange)rangeOf:(int)i
{
    NSRange r[8];
    [self stringWithRanges:r];
    return r[i];
}
- (NSRange)rangeOfScheme { return [self rangeOf:0]; }
- (NSRange)rangeOfUser { return [self rangeOf:1]; }
- (NSRange)rangeOfPassword { return [self rangeOf:2]; }
- (NSRange)rangeOfHost { return [self rangeOf:3]; }
- (NSRange)rangeOfPort { return [self rangeOf:4]; }
- (NSRange)rangeOfPath { return [self rangeOf:5]; }
- (NSRange)rangeOfQuery { return [self rangeOf:6]; }
- (NSRange)rangeOfFragment { return [self rangeOf:7]; }

#define SETTER(name, ivar)                                                                                    \
    -(void)name:(NSString *)v                                                                                 \
    {                                                                                                         \
        if (v != ivar) {                                                                                      \
            [ivar release];                                                                                   \
            ivar = [v copy];                                                                                  \
        }                                                                                                     \
    }
SETTER(setPercentEncodedUser, _user)
SETTER(setPercentEncodedPassword, _password)
SETTER(setPercentEncodedHost, _host)
SETTER(setPercentEncodedQuery, _query)
SETTER(setPercentEncodedFragment, _fragment)
#undef SETTER
- (void)setPercentEncodedPath:(NSString *)v
{
    [_path release];
    _path = [(v ? v : @"") copy];
}
- (NSString *)scheme { return _scheme; }
- (void)setScheme:(NSString *)v
{
    for (NSUInteger i = 0; i < [v length]; i++) {
        unichar c = [v characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
               || (i && ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.'));
        if (!ok)
            FRaise(NSInvalidArgumentException, @"-[NSURLComponents setScheme:]: invalid characters in scheme");
    }
    [_scheme release];
    _scheme = [v copy];
}
- (NSNumber *)port { return _port; }
- (void)setPort:(NSNumber *)v
{
    if (v && [v integerValue] < 0)
        FRaise(NSInvalidArgumentException, @"-[NSURLComponents setPort:]: negative port");
    [_port release];
    _port = [v copy];
}
- (NSString *)percentEncodedUser { return _user; }
- (NSString *)percentEncodedPassword { return _password; }
- (NSString *)percentEncodedHost { return _host; }
- (NSString *)percentEncodedPath { return _path; }
- (NSString *)percentEncodedQuery { return _query; }
- (NSString *)percentEncodedFragment { return _fragment; }
- (NSString *)user { return decode(_user); }
- (NSString *)password { return decode(_password); }
- (NSString *)host { return decode(_host); }
- (NSString *)path { return decode(_path); }
- (NSString *)query { return decode(_query); }
- (NSString *)fragment { return decode(_fragment); }
- (void)setUser:(NSString *)v { self.percentEncodedUser = encode(v, [NSCharacterSet URLUserAllowedCharacterSet]); }
- (void)setPassword:(NSString *)v
{
    self.percentEncodedPassword = encode(v, [NSCharacterSet URLPasswordAllowedCharacterSet]);
}
- (void)setHost:(NSString *)v { self.percentEncodedHost = encode(v, [NSCharacterSet URLHostAllowedCharacterSet]); }
- (void)setPath:(NSString *)v { self.percentEncodedPath = encode(v, [NSCharacterSet URLPathAllowedCharacterSet]); }
- (void)setQuery:(NSString *)v { self.percentEncodedQuery = encode(v, [NSCharacterSet URLQueryAllowedCharacterSet]); }
- (void)setFragment:(NSString *)v
{
    self.percentEncodedFragment = encode(v, [NSCharacterSet URLFragmentAllowedCharacterSet]);
}

/* The query as name=value pairs, split at each & and the first = */
- (NSArray *)itemsDecoded:(BOOL)decoded
{
    if (!_query)
        return nil;
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *pair in [_query componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        NSString *name = eq.location == NSNotFound ? pair : [pair substringToIndex:eq.location];
        NSString *value = eq.location == NSNotFound ? nil : [pair substringFromIndex:eq.location + 1];
        if (decoded) {
            name = decode(name);
            value = decode(value);
        }
        [items addObject:[NSURLQueryItem queryItemWithName:name ? name : @"" value:value]];
    }
    return items;
}
- (void)setItems:(NSArray *)items encode:(BOOL)encoding
{
    if (!items) {
        self.percentEncodedQuery = nil;
        return;
    }
    NSCharacterSet *names = allowed([NSCharacterSet URLQueryAllowedCharacterSet], @"&=#");
    NSCharacterSet *values = allowed([NSCharacterSet URLQueryAllowedCharacterSet], @"&#");
    NSMutableArray *parts = [NSMutableArray array];
    for (NSURLQueryItem *item in items) {
        NSString *name = item.name ? item.name : @"", *value = item.value;
        if (encoding) {
            name = encode(name, names);
            value = encode(value, values);
        }
        [parts addObject:value ? [NSString stringWithFormat:@"%@=%@", name, value] : name];
    }
    self.percentEncodedQuery = [parts componentsJoinedByString:@"&"];
}
- (NSArray *)queryItems { return [self itemsDecoded:YES]; }
- (NSArray *)percentEncodedQueryItems { return [self itemsDecoded:NO]; }
- (void)setQueryItems:(NSArray *)items { [self setItems:items encode:YES]; }
- (void)setPercentEncodedQueryItems:(NSArray *)items { [self setItems:items encode:NO]; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSURLComponents %p> {scheme = %@, user = %@, password = %@, host = %@, "
                                      @"port = %@, path = %@, query = %@, fragment = %@}",
                                      self, _scheme, self.user, self.password, self.host, _port, self.path,
                                      self.query, self.fragment];
}
@end
