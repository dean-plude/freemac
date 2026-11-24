/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSRegularExpression and NSTextCheckingResult, and
 * NSString's NSRegularExpressionSearch.
 *
 * A Mac's NSRegularExpression is ICU's regular expressions, so Ferry's is
 * too: the patterns are compiled and matched by this system's ICU (the same
 * library a Mac program linking libicucore gets, see src/host.c), reached
 * through ferry_twin_symbol only when the first expression is made, so that
 * programs which never use one don't load ICU. ICU works on UTF-16 offsets,
 * which are NSString's, so its ranges are used as they are. Templates
 * ($1, ${name}, \$) are expanded here, as Apple documents them.
 *
 * Written from Apple's public documentation of these classes and ICU's of
 * its C interface (uregex.h); no Apple code was used. */
#import "FInternal.h"

void *ferry_twin_symbol(const char *install_name, const char *name);

typedef uint16_t UChar;
typedef int UErrorCode; /* > 0 is a failure */
typedef int8_t UBool;
typedef struct {
    int32_t line, offset;
    UChar preContext[16], postContext[16];
} UParseError;
typedef struct URegex URegex;

/* uregex_open's flags (ICU's URegexpFlag) */
enum {
    UREGEX_UNIX_LINES = 1,
    UREGEX_CASE_INSENSITIVE = 2,
    UREGEX_COMMENTS = 4,
    UREGEX_MULTILINE = 8,
    UREGEX_LITERAL = 16,
    UREGEX_DOTALL = 32,
    UREGEX_UWORD = 256,
};

static struct {
    BOOL tried, ok;
    URegex *(*open)(const UChar *, int32_t, uint32_t, UParseError *, UErrorCode *);
    URegex *(*clone)(const URegex *, UErrorCode *);
    void (*close)(URegex *);
    void (*setText)(URegex *, const UChar *, int32_t, UErrorCode *);
    void (*setRegion64)(URegex *, int64_t, int64_t, UErrorCode *);
    UBool (*findNext)(URegex *, UErrorCode *);
    int32_t (*start)(URegex *, int32_t, UErrorCode *);
    int32_t (*end)(URegex *, int32_t, UErrorCode *);
    int32_t (*groupCount)(URegex *, UErrorCode *);
    int32_t (*groupNumberFromName)(URegex *, const UChar *, int32_t, UErrorCode *);
    void (*useTransparentBounds)(URegex *, UBool, UErrorCode *);
    void (*useAnchoringBounds)(URegex *, UBool, UErrorCode *);
    UBool (*hitEnd)(URegex *, UErrorCode *);
    UBool (*requireEnd)(URegex *, UErrorCode *);
} icu;

static BOOL load_icu(void)
{
    if (icu.tried)
        return icu.ok;
    icu.tried = YES;
    const char *lib = "/usr/lib/libicucore.A.dylib";
#define LOAD(field, name) *(void **)&icu.field = ferry_twin_symbol(lib, name)
    LOAD(open, "uregex_open");
    LOAD(clone, "uregex_clone");
    LOAD(close, "uregex_close");
    LOAD(setText, "uregex_setText");
    LOAD(setRegion64, "uregex_setRegion64");
    LOAD(findNext, "uregex_findNext");
    LOAD(start, "uregex_start");
    LOAD(end, "uregex_end");
    LOAD(groupCount, "uregex_groupCount");
    LOAD(groupNumberFromName, "uregex_groupNumberFromName");
    LOAD(useTransparentBounds, "uregex_useTransparentBounds");
    LOAD(useAnchoringBounds, "uregex_useAnchoringBounds");
    LOAD(hitEnd, "uregex_hitEnd");
    LOAD(requireEnd, "uregex_requireEnd");
#undef LOAD
    icu.ok = icu.open && icu.clone && icu.close && icu.setText && icu.setRegion64 && icu.findNext && icu.start &&
             icu.end && icu.groupCount && icu.useTransparentBounds && icu.useAnchoringBounds && icu.hitEnd &&
             icu.requireEnd;
    return icu.ok;
}

static unichar *chars(NSString *s, NSUInteger *n)
{
    *n = [s length];
    unichar *c = malloc((*n + 1) * sizeof(unichar));
    [s getCharacters:c range:NSMakeRange(0, *n)];
    c[*n] = 0;
    return c;
}

/* ---- NSTextCheckingResult ---------------------------------------------------------- */

@interface FRegexResult : NSTextCheckingResult {
@public
    NSRange *_ranges;
    NSUInteger _count;
    NSRegularExpression *_regex;
}
@end

@interface NSRegularExpression ()
- (NSInteger)_groupNamed:(NSString *)name;
@end

@implementation NSTextCheckingResult
+ (NSTextCheckingResult *)regularExpressionCheckingResultWithRanges:(NSRangePointer)ranges
                                                              count:(NSUInteger)count
                                                  regularExpression:(NSRegularExpression *)regex
{
    FRegexResult *r = [[FRegexResult alloc] init];
    r->_count = count;
    r->_ranges = malloc((count ? count : 1) * sizeof(NSRange));
    memcpy(r->_ranges, ranges, count * sizeof(NSRange));
    r->_regex = [regex retain];
    return [r autorelease];
}
- (NSTextCheckingType)resultType { return 0; }
- (NSRange)range { return NSMakeRange(NSNotFound, 0); }
- (NSUInteger)numberOfRanges { return 1; }
- (NSRange)rangeAtIndex:(NSUInteger)idx { return idx == 0 ? [self range] : NSMakeRange(NSNotFound, 0); }
- (NSRange)rangeWithName:(NSString *)name { return NSMakeRange(NSNotFound, 0); }
- (NSRegularExpression *)regularExpression { return nil; }
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset { return self; }
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

@implementation FRegexResult
- (void)dealloc
{
    free(_ranges);
    [_regex release];
    [super dealloc];
}
- (NSTextCheckingType)resultType { return NSTextCheckingTypeRegularExpression; }
- (NSRange)range { return _count ? _ranges[0] : NSMakeRange(NSNotFound, 0); }
- (NSUInteger)numberOfRanges { return _count; }
- (NSRange)rangeAtIndex:(NSUInteger)idx
{
    if (idx >= _count)
        FRaise(NSRangeException, @"*** -[NSRegularExpressionCheckingResult rangeAtIndex:]: index %lu out of bounds",
               (unsigned long)idx);
    return _ranges[idx];
}
- (NSRange)rangeWithName:(NSString *)name
{
    NSInteger g = [_regex _groupNamed:name];
    if (g < 0 || (NSUInteger)g >= _count)
        FRaise(NSInvalidArgumentException, @"*** -[NSRegularExpressionCheckingResult rangeWithName:]: no capture "
                                            @"group named %@",
               name);
    return _ranges[g];
}
- (NSRegularExpression *)regularExpression { return _regex; }
- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset
{
    NSRange *moved = malloc((_count ? _count : 1) * sizeof(NSRange));
    for (NSUInteger i = 0; i < _count; i++) {
        moved[i] = _ranges[i];
        if (moved[i].location != NSNotFound) {
            if (offset < 0 && (NSUInteger)-offset > moved[i].location) {
                free(moved);
                FRaise(NSInvalidArgumentException,
                       @"*** -[NSRegularExpressionCheckingResult resultByAdjustingRangesWithOffset:]: offset %ld "
                       @"invalid for range {%lu, %lu}",
                       (long)offset, (unsigned long)_ranges[i].location, (unsigned long)_ranges[i].length);
            }
            moved[i].location += offset;
        }
    }
    NSTextCheckingResult *r = [NSTextCheckingResult regularExpressionCheckingResultWithRanges:moved
                                                                                        count:_count
                                                                            regularExpression:_regex];
    free(moved);
    return r;
}
- (NSString *)description
{
    NSRange r = [self range];
    return [NSString stringWithFormat:@"<NSRegularExpressionCheckingResult: %p>{%lu, %lu}{%@}", self,
                                      (unsigned long)r.location, (unsigned long)r.length, _regex];
}
@end

/* ---- NSRegularExpression ----------------------------------------------------------- */

@implementation NSRegularExpression {
    NSString *_pattern;
    NSRegularExpressionOptions _options;
    URegex *_re;
    NSUInteger _groups;
    BOOL _busy;
}

+ (instancetype)regularExpressionWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options
                                       error:(NSError **)error
{
    return [[[self alloc] initWithPattern:pattern options:options error:error] autorelease];
}

static NSError *invalid(NSString *pattern)
{
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:pattern ?: @"", @"NSInvalidValue", nil];
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFormattingError userInfo:info];
}

- (instancetype)initWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error
{
    if (!(self = [super init]))
        return nil;
    if (!pattern)
        FRaise(NSInvalidArgumentException, @"*** -[NSRegularExpression initWithPattern:options:error:]: nil argument");
    if (!load_icu()) {
        FSetError(error, invalid(pattern));
        [self release];
        return nil;
    }
    uint32_t flags = 0;
    if (options & NSRegularExpressionCaseInsensitive)
        flags |= UREGEX_CASE_INSENSITIVE;
    if (options & NSRegularExpressionAllowCommentsAndWhitespace)
        flags |= UREGEX_COMMENTS;
    if (options & NSRegularExpressionIgnoreMetacharacters)
        flags |= UREGEX_LITERAL;
    if (options & NSRegularExpressionDotMatchesLineSeparators)
        flags |= UREGEX_DOTALL;
    if (options & NSRegularExpressionAnchorsMatchLines)
        flags |= UREGEX_MULTILINE;
    if (options & NSRegularExpressionUseUnixLineSeparators)
        flags |= UREGEX_UNIX_LINES;
    if (options & NSRegularExpressionUseUnicodeWordBoundaries)
        flags |= UREGEX_UWORD;
    NSUInteger n;
    unichar *p = chars(pattern, &n);
    UParseError pe;
    UErrorCode status = 0;
    _re = icu.open(p, (int32_t)n, flags, &pe, &status);
    free(p);
    if (status > 0 || !_re) {
        if (_re)
            icu.close(_re);
        _re = NULL;
        FSetError(error, invalid(pattern));
        [self release];
        return nil;
    }
    status = 0;
    int32_t g = icu.groupCount(_re, &status);
    _groups = g > 0 ? g : 0;
    _pattern = [pattern copy];
    _options = options;
    return self;
}
- (void)dealloc
{
    if (_re)
        icu.close(_re);
    [_pattern release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)pattern { return _pattern; }
- (NSRegularExpressionOptions)options { return _options; }
- (NSUInteger)numberOfCaptureGroups { return _groups; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    return [other isKindOfClass:[NSRegularExpression class]] && [_pattern isEqual:[other pattern]] &&
           _options == [other options];
}
- (NSUInteger)hash { return [_pattern hash] ^ _options; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSRegularExpression: %p> %@ 0x%lx", self, _pattern, (unsigned long)_options];
}
- (NSInteger)_groupNamed:(NSString *)name
{
    if (!name || !icu.groupNumberFromName)
        return -1;
    NSUInteger n;
    unichar *c = chars(name, &n);
    UErrorCode status = 0;
    int32_t g = icu.groupNumberFromName(_re, c, (int32_t)n, &status);
    free(c);
    return status > 0 ? -1 : g;
}

+ (NSString *)escapedPatternForString:(NSString *)string
{
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = [string length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [string characterAtIndex:i];
        if (c < 0x80 && strchr("\\*?+[](){}^$|./", c) && c)
            [out appendString:@"\\"];
        [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return out;
}
+ (NSString *)escapedTemplateForString:(NSString *)string
{
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = [string length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '\\' || c == '$')
            [out appendString:@"\\"];
        [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return out;
}

/* The matching itself: every match in range, in order, until the block
 * says stop. */
- (void)enumerateMatchesInString:(NSString *)string
                         options:(NSMatchingOptions)options
                           range:(NSRange)range
                      usingBlock:(void (^)(NSTextCheckingResult *, NSMatchingFlags, BOOL *))block
{
    if (!string)
        FRaise(NSInvalidArgumentException, @"*** -[NSRegularExpression enumerateMatchesInString:options:range:"
                                            @"usingBlock:]: nil argument");
    NSUInteger len = [string length];
    if (NSMaxRange(range) > len || range.location > len)
        FRaise(NSRangeException, @"*** -[NSRegularExpression enumerateMatchesInString:options:range:usingBlock:]: "
                                  @"Range {%lu, %lu} out of bounds; string length %lu",
               (unsigned long)range.location, (unsigned long)range.length, (unsigned long)len);
    UErrorCode status = 0;
    URegex *re = _re;
    BOOL cloned = NO;
    if (_busy) { /* a match inside a block of this same expression's */
        re = icu.clone(_re, &status);
        cloned = YES;
    } else
        _busy = YES;
    [self retain];
    NSUInteger n;
    unichar *text = chars(string, &n);
    status = 0;
    icu.setText(re, text, (int32_t)n, &status);
    icu.setRegion64(re, range.location, NSMaxRange(range), &status);
    icu.useTransparentBounds(re, (options & NSMatchingWithTransparentBounds) != 0, &status);
    icu.useAnchoringBounds(re, (options & NSMatchingWithoutAnchoringBounds) == 0, &status);
    NSUInteger expected = range.location, count = _groups + 1;
    NSRange *ranges = malloc(count * sizeof(NSRange));
    BOOL stop = NO;
    while (!stop && status <= 0 && icu.findNext(re, &status) && status <= 0) {
        int32_t s = icu.start(re, 0, &status), e = icu.end(re, 0, &status);
        if ((options & NSMatchingAnchored) && (NSUInteger)s != expected)
            break;
        for (NSUInteger g = 0; g < count; g++) {
            int32_t gs = icu.start(re, (int32_t)g, &status), ge = icu.end(re, (int32_t)g, &status);
            ranges[g] = gs < 0 ? NSMakeRange(NSNotFound, 0) : NSMakeRange(gs, ge - gs);
        }
        expected = e;
        @autoreleasepool {
            NSTextCheckingResult *r = [NSTextCheckingResult regularExpressionCheckingResultWithRanges:ranges
                                                                                                count:count
                                                                                    regularExpression:self];
            block(r, 0, &stop);
        }
        if (options & NSMatchingReportProgress && !stop)
            block(nil, NSMatchingProgress, &stop);
    }
    if ((options & NSMatchingReportCompletion) && !stop) {
        NSMatchingFlags flags = NSMatchingCompleted;
        UErrorCode st2 = 0;
        if (icu.hitEnd(re, &st2))
            flags |= NSMatchingHitEnd;
        if (icu.requireEnd(re, &st2))
            flags |= NSMatchingRequiredEnd;
        if (status > 0)
            flags |= NSMatchingInternalError;
        block(nil, flags, &stop);
    }
    free(ranges);
    UErrorCode st3 = 0;
    static const UChar empty[1];
    icu.setText(re, empty, 0, &st3); /* forget the text, which is freed now */
    free(text);
    if (cloned)
        icu.close(re);
    else
        _busy = NO;
    [self release];
}

- (NSArray *)matchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range
{
    NSMutableArray *all = [NSMutableArray array];
    [self enumerateMatchesInString:string
                           options:options & ~(NSMatchingReportProgress | NSMatchingReportCompletion)
                             range:range
                        usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) {
                          if (r)
                              [all addObject:r];
                        }];
    return all;
}
- (NSUInteger)numberOfMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range
{
    __block NSUInteger n = 0;
    [self enumerateMatchesInString:string
                           options:options & ~(NSMatchingReportProgress | NSMatchingReportCompletion)
                             range:range
                        usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) {
                          if (r)
                              n++;
                        }];
    return n;
}
- (NSTextCheckingResult *)firstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range
{
    __block NSTextCheckingResult *first = nil;
    [self enumerateMatchesInString:string
                           options:options & ~(NSMatchingReportProgress | NSMatchingReportCompletion)
                             range:range
                        usingBlock:^(NSTextCheckingResult *r, NSMatchingFlags f, BOOL *stop) {
                          if (r) {
                              first = [r retain];
                              *stop = YES;
                          }
                        }];
    return [first autorelease];
}
- (NSRange)rangeOfFirstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range
{
    NSTextCheckingResult *r = [self firstMatchInString:string options:options range:range];
    return r ? [r range] : NSMakeRange(NSNotFound, 0);
}

/* $0..$n (as many digits as still name a group), ${name}, and \ before a
 * character that should be taken as it is. */
- (NSString *)replacementStringForResult:(NSTextCheckingResult *)result
                                inString:(NSString *)string
                                  offset:(NSInteger)offset
                                template:(NSString *)templ
{
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = [templ length], groups = [result numberOfRanges];
    NSUInteger i = 0;
    while (i < n) {
        unichar c = [templ characterAtIndex:i];
        if (c == '\\' && i + 1 < n) {
            unichar d = [templ characterAtIndex:i + 1];
            [out appendString:[NSString stringWithCharacters:&d length:1]];
            i += 2;
            continue;
        }
        NSInteger group = -1;
        if (c == '$' && i + 1 < n && [templ characterAtIndex:i + 1] >= '0' && [templ characterAtIndex:i + 1] <= '9') {
            group = [templ characterAtIndex:i + 1] - '0';
            i += 2;
            while (i < n) {
                unichar d = [templ characterAtIndex:i];
                if (d < '0' || d > '9' || (NSUInteger)(group * 10 + (d - '0')) >= groups)
                    break;
                group = group * 10 + (d - '0');
                i++;
            }
        } else if (c == '$' && i + 1 < n && [templ characterAtIndex:i + 1] == '{') {
            NSRange close = [templ rangeOfString:@"}" options:0 range:NSMakeRange(i + 2, n - i - 2)];
            if (close.location != NSNotFound) {
                NSString *name = [templ substringWithRange:NSMakeRange(i + 2, close.location - i - 2)];
                group = [self _groupNamed:name];
                if (group < 0)
                    group = NSIntegerMax; /* nothing */
                i = close.location + 1;
            }
        }
        if (group >= 0) {
            if ((NSUInteger)group < groups) {
                NSRange r = [result rangeAtIndex:group];
                if (r.location != NSNotFound)
                    [out appendString:[string substringWithRange:NSMakeRange(r.location + offset, r.length)]];
            }
            continue;
        }
        [out appendString:[NSString stringWithCharacters:&c length:1]];
        i++;
    }
    return out;
}
- (NSString *)stringByReplacingMatchesInString:(NSString *)string
                                       options:(NSMatchingOptions)options
                                         range:(NSRange)range
                                  withTemplate:(NSString *)templ
{
    NSArray *matches = [self matchesInString:string options:options range:range];
    NSMutableString *out = [NSMutableString string];
    NSUInteger at = 0;
    for (NSTextCheckingResult *m in matches) {
        NSRange r = [m range];
        [out appendString:[string substringWithRange:NSMakeRange(at, r.location - at)]];
        [out appendString:[self replacementStringForResult:m inString:string offset:0 template:templ]];
        at = NSMaxRange(r);
    }
    [out appendString:[string substringFromIndex:at]];
    return [[out copy] autorelease];
}
- (NSUInteger)replaceMatchesInString:(NSMutableString *)string
                             options:(NSMatchingOptions)options
                               range:(NSRange)range
                        withTemplate:(NSString *)templ
{
    NSArray *matches = [self matchesInString:string options:options range:range];
    NSMutableArray *replacements = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches)
        [replacements addObject:[self replacementStringForResult:m inString:string offset:0 template:templ]];
    for (NSUInteger i = [matches count]; i-- > 0;)
        [string replaceCharactersInRange:[[matches objectAtIndex:i] range] withString:[replacements objectAtIndex:i]];
    return [matches count];
}
@end

/* ---- NSString with NSRegularExpressionSearch ---------------------------------------- */

static NSRegularExpression *search_regex(NSString *pattern, NSStringCompareOptions mask)
{
    if (!pattern)
        return nil;
    return [NSRegularExpression regularExpressionWithPattern:pattern
                                                     options:(mask & NSCaseInsensitiveSearch)
                                                                 ? NSRegularExpressionCaseInsensitive
                                                                 : 0
                                                       error:NULL];
}

/* For -[NSString rangeOfString:options:range:] (NSString.m). */
NSRange FRegexSearch(NSString *string, NSString *pattern, NSStringCompareOptions mask, NSRange range)
{
    NSRegularExpression *re = search_regex(pattern, mask);
    if (!re)
        return NSMakeRange(NSNotFound, 0);
    return [re rangeOfFirstMatchInString:string options:(mask & NSAnchoredSearch) ? NSMatchingAnchored : 0 range:range];
}

/* For -[NSMutableString replaceOccurrencesOfString:withString:options:range:]. */
NSUInteger FRegexReplace(NSMutableString *string, NSString *pattern, NSString *templ, NSStringCompareOptions mask,
                         NSRange range)
{
    NSRegularExpression *re = search_regex(pattern, mask);
    if (!re)
        return 0;
    return [re replaceMatchesInString:string
                              options:(mask & NSAnchoredSearch) ? NSMatchingAnchored : 0
                                range:range
                         withTemplate:templ];
}

@implementation NSString (NSRegularExpressionSearch)
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target
                                        withString:(NSString *)replacement
                                           options:(NSStringCompareOptions)options
                                             range:(NSRange)searchRange
{
    NSMutableString *m = [[self mutableCopy] autorelease];
    [m replaceOccurrencesOfString:target withString:replacement options:options range:searchRange];
    return [[m copy] autorelease];
}
@end
