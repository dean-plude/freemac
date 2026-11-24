/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSAttributedString and CFAttributedString: text with attributes (fonts,
 * colours and so on) attached to ranges of it. The text is kept as one
 * string and the attributes as a list of runs, each a length and a
 * dictionary; neighbouring runs with equal attributes are merged, so a
 * run's extent is also the longest range its attributes cover. */
#import "FInternal.h"

struct frun {
    NSUInteger len;
    NSDictionary *attrs;
};

@interface NSAttributedString () {
@public
    NSMutableString *_text;
    struct frun *_runs;
    NSUInteger _count, _cap;
}
@end

static NSDictionary *empty_attrs(void)
{
    static NSDictionary *empty;
    static dispatch_once_t empty_once;
    dispatch_once(&empty_once, ^{
      empty = [[NSDictionary alloc] init];
    });
    return empty;
}

static BOOL same_value(id a, id b) { return a == b || (a && b && [a isEqual:b]); }

static void range_check(NSAttributedString *s, SEL cmd, NSRange r)
{
    if (r.location > s->_text.length || r.length > s->_text.length - r.location)
        FRaise(NSRangeException, @"*** -[%s %s]: Range {%lu, %lu} out of bounds; string length %lu",
               object_getClassName(s), sel_getName(cmd), (unsigned long)r.location, (unsigned long)r.length,
               (unsigned long)s->_text.length);
}

static void grow(NSAttributedString *s, NSUInteger need)
{
    if (need <= s->_cap)
        return;
    s->_cap = need < 8 ? 8 : need * 2;
    s->_runs = realloc(s->_runs, s->_cap * sizeof *s->_runs);
}

static void insert_run(NSAttributedString *s, NSUInteger at, NSUInteger len, NSDictionary *attrs)
{
    grow(s, s->_count + 1);
    memmove(&s->_runs[at + 1], &s->_runs[at], (s->_count - at) * sizeof *s->_runs);
    s->_runs[at].len = len;
    s->_runs[at].attrs = [attrs copy];
    s->_count++;
}

static void remove_runs(NSAttributedString *s, NSUInteger at, NSUInteger n)
{
    for (NSUInteger i = at; i < at + n; i++)
        [s->_runs[i].attrs release];
    memmove(&s->_runs[at], &s->_runs[at + n], (s->_count - at - n) * sizeof *s->_runs);
    s->_count -= n;
}

/* The run that holds character index (or _count at the very end), and where it starts. */
static NSUInteger find_run(NSAttributedString *s, NSUInteger index, NSUInteger *start)
{
    NSUInteger pos = 0, i = 0;
    for (; i < s->_count; i++) {
        if (index < pos + s->_runs[i].len)
            break;
        pos += s->_runs[i].len;
    }
    if (start)
        *start = pos;
    return i;
}

/* Makes a run start at index; returns that run's position in the list. */
static NSUInteger split_at(NSAttributedString *s, NSUInteger index)
{
    NSUInteger start, i = find_run(s, index, &start);
    if (i == s->_count || start == index)
        return i;
    NSUInteger first = index - start;
    insert_run(s, i + 1, s->_runs[i].len - first, s->_runs[i].attrs);
    s->_runs[i].len = first;
    return i + 1;
}

static void coalesce(NSAttributedString *s)
{
    NSUInteger out = 0;
    for (NSUInteger i = 0; i < s->_count; i++) {
        if (!s->_runs[i].len) {
            [s->_runs[i].attrs release];
            continue;
        }
        if (out && [s->_runs[out - 1].attrs isEqualToDictionary:s->_runs[i].attrs]) {
            s->_runs[out - 1].len += s->_runs[i].len;
            [s->_runs[i].attrs release];
            continue;
        }
        s->_runs[out++] = s->_runs[i];
    }
    s->_count = out;
}

/* Calls change(attrs) for each run inside range and stores what it returns. */
static void change_attrs(NSAttributedString *s, NSRange range, NSDictionary *(^change)(NSDictionary *))
{
    if (!range.length)
        return;
    NSUInteger first = split_at(s, range.location);
    NSUInteger last = split_at(s, range.location + range.length);
    for (NSUInteger i = first; i < last; i++) {
        NSDictionary *next = [change(s->_runs[i].attrs) copy];
        [s->_runs[i].attrs release];
        s->_runs[i].attrs = next;
    }
    coalesce(s);
}

static void replace_text(NSAttributedString *s, NSRange range, NSString *str, NSDictionary *attrs)
{
    NSUInteger first = split_at(s, range.location);
    NSUInteger last = split_at(s, range.location + range.length);
    remove_runs(s, first, last - first);
    [s->_text replaceCharactersInRange:range withString:str];
    if (str.length)
        insert_run(s, first, str.length, attrs ? attrs : empty_attrs());
    coalesce(s);
}

@implementation NSAttributedString

- (instancetype)init { return [self initWithString:@"" attributes:nil]; }
- (instancetype)initWithString:(NSString *)str { return [self initWithString:str attributes:nil]; }

- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary *)attrs
{
    if (!(self = [super init]))
        return nil;
    if (!str)
        FRaise(NSInvalidArgumentException, @"*** -[%s initWithString:attributes:]: nil value",
               object_getClassName(self));
    _text = [str mutableCopy];
    if (_text.length)
        insert_run(self, 0, _text.length, attrs ? attrs : empty_attrs());
    return self;
}

- (instancetype)initWithAttributedString:(NSAttributedString *)other
{
    if (!(self = [super init]))
        return nil;
    _text = [other->_text mutableCopy];
    for (NSUInteger i = 0; i < other->_count; i++)
        insert_run(self, i, other->_runs[i].len, other->_runs[i].attrs);
    return self;
}

- (void)dealloc
{
    remove_runs(self, 0, _count);
    free(_runs);
    [_text release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    if ([self isMemberOfClass:[NSAttributedString class]])
        return [self retain];
    return [[NSAttributedString alloc] initWithAttributedString:self];
}

- (id)mutableCopyWithZone:(NSZone *)zone
{
    return [[NSMutableAttributedString alloc] initWithAttributedString:self];
}

- (NSString *)string { return [[_text copy] autorelease]; }
- (NSUInteger)length { return _text.length; }

- (NSDictionary *)attributesAtIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range
{
    if (location >= _text.length)
        FRaise(NSRangeException, @"*** -[%s attributesAtIndex:effectiveRange:]: Index %lu out of bounds; "
                                 @"string length %lu",
               object_getClassName(self), (unsigned long)location, (unsigned long)_text.length);
    NSUInteger start, i = find_run(self, location, &start);
    if (range)
        *range = NSMakeRange(start, _runs[i].len);
    return _runs[i].attrs;
}

- (NSDictionary *)attributesAtIndex:(NSUInteger)location
              longestEffectiveRange:(NSRangePointer)range
                            inRange:(NSRange)limit
{
    NSRange r;
    NSDictionary *attrs = [self attributesAtIndex:location effectiveRange:&r];
    if (range) {
        NSUInteger lo = MAX(r.location, limit.location);
        NSUInteger hi = MIN(r.location + r.length, limit.location + limit.length);
        *range = NSMakeRange(lo, hi > lo ? hi - lo : 0);
    }
    return attrs;
}

- (id)attribute:(NSString *)name atIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range
{
    return [self attribute:name atIndex:location longestEffectiveRange:range inRange:NSMakeRange(0, _text.length)];
}

- (id)attribute:(NSString *)name
                  atIndex:(NSUInteger)location
    longestEffectiveRange:(NSRangePointer)range
                  inRange:(NSRange)limit
{
    NSUInteger start;
    [self attributesAtIndex:location effectiveRange:NULL];
    NSUInteger i = find_run(self, location, &start);
    id value = [_runs[i].attrs objectForKey:name];
    if (range) {
        NSUInteger lo = start, hi = start + _runs[i].len;
        for (NSUInteger j = i; j > 0 && same_value([_runs[j - 1].attrs objectForKey:name], value); j--)
            lo -= _runs[j - 1].len;
        for (NSUInteger j = i + 1; j < _count && same_value([_runs[j].attrs objectForKey:name], value); j++)
            hi += _runs[j].len;
        lo = MAX(lo, limit.location);
        hi = MIN(hi, limit.location + limit.length);
        *range = NSMakeRange(lo, hi > lo ? hi - lo : 0);
    }
    return value;
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
    range_check(self, _cmd, range);
    NSMutableAttributedString *sub = [[NSMutableAttributedString alloc] initWithAttributedString:self];
    replace_text(sub, NSMakeRange(range.location + range.length, _text.length - range.location - range.length),
                 @"", nil);
    replace_text(sub, NSMakeRange(0, range.location), @"", nil);
    NSAttributedString *result = [[NSAttributedString alloc] initWithAttributedString:sub];
    [sub release];
    return [result autorelease];
}

- (void)enumerateAttributesInRange:(NSRange)range
                           options:(NSAttributedStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSDictionary<NSAttributedStringKey, id> *, NSRange, BOOL *))block
{
    range_check(self, _cmd, range);
    NSUInteger n = 0, pos = 0;
    NSRange *spans = malloc((_count + 1) * sizeof *spans);
    NSDictionary **attrs = malloc((_count + 1) * sizeof *attrs);
    for (NSUInteger i = 0; i < _count; i++) {
        NSUInteger lo = MAX(pos, range.location), hi = MIN(pos + _runs[i].len, range.location + range.length);
        if (hi > lo) {
            spans[n] = NSMakeRange(lo, hi - lo);
            attrs[n++] = [[_runs[i].attrs retain] autorelease];
        }
        pos += _runs[i].len;
    }
    BOOL stop = NO;
    for (NSUInteger k = 0; k < n && !stop; k++) {
        NSUInteger i = (opts & NSAttributedStringEnumerationReverse) ? n - 1 - k : k;
        block(attrs[i], spans[i], &stop);
    }
    free(spans);
    free(attrs);
}

- (void)enumerateAttribute:(NSString *)name
                   inRange:(NSRange)range
                   options:(NSAttributedStringEnumerationOptions)opts
                usingBlock:(void (^)(id, NSRange, BOOL *))block
{
    range_check(self, _cmd, range);
    NSMutableArray *values = [NSMutableArray array];
    NSMutableArray *spans = [NSMutableArray array];
    NSUInteger pos = range.location, end = range.location + range.length;
    while (pos < end) {
        NSRange r;
        id value = [self attribute:name atIndex:pos longestEffectiveRange:&r inRange:range];
        [values addObject:value ? value : [NSNull null]];
        [spans addObject:[NSValue valueWithRange:r]];
        pos = r.location + r.length;
    }
    BOOL stop = NO;
    NSUInteger n = values.count;
    for (NSUInteger k = 0; k < n && !stop; k++) {
        NSUInteger i = (opts & NSAttributedStringEnumerationReverse) ? n - 1 - k : k;
        id value = values[i];
        block(value == [NSNull null] ? nil : value, [spans[i] rangeValue], &stop);
    }
}

- (BOOL)isEqualToAttributedString:(NSAttributedString *)other
{
    if (other == self)
        return YES;
    if (![other isKindOfClass:[NSAttributedString class]] || ![_text isEqualToString:other->_text])
        return NO;
    if (_count != other->_count)
        return NO;
    for (NSUInteger i = 0; i < _count; i++)
        if (_runs[i].len != other->_runs[i].len || ![_runs[i].attrs isEqualToDictionary:other->_runs[i].attrs])
            return NO;
    return YES;
}

- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSAttributedString class]] && [self isEqualToAttributedString:other];
}

- (NSUInteger)hash { return [_text hash]; }

- (NSString *)description
{
    NSMutableString *out = [NSMutableString string];
    NSUInteger pos = 0;
    for (NSUInteger i = 0; i < _count; i++) {
        [out appendString:[_text substringWithRange:NSMakeRange(pos, _runs[i].len)]];
        [out appendString:FDescribe(_runs[i].attrs, 0)];
        pos += _runs[i].len;
    }
    return out;
}

@end

@implementation NSMutableAttributedString

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str
{
    range_check(self, _cmd, range);
    NSDictionary *attrs = nil;
    if (range.length)
        attrs = [self attributesAtIndex:range.location effectiveRange:NULL];
    else if (range.location > 0)
        attrs = [self attributesAtIndex:range.location - 1 effectiveRange:NULL];
    else if (_text.length)
        attrs = [self attributesAtIndex:0 effectiveRange:NULL];
    replace_text(self, range, str ? str : @"", [[attrs retain] autorelease]);
}

- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)other
{
    range_check(self, _cmd, range);
    NSAttributedString *copy = [other copy];
    replace_text(self, range, @"", nil);
    NSUInteger at = split_at(self, range.location);
    [_text replaceCharactersInRange:NSMakeRange(range.location, 0) withString:copy->_text];
    for (NSUInteger i = 0; i < copy->_count; i++)
        insert_run(self, at + i, copy->_runs[i].len, copy->_runs[i].attrs);
    coalesce(self);
    [copy release];
}

- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range
{
    range_check(self, _cmd, range);
    NSDictionary *value = attrs ? attrs : empty_attrs();
    change_attrs(self, range, ^NSDictionary *(NSDictionary *old) { return value; });
}

- (void)addAttribute:(NSString *)name value:(id)value range:(NSRange)range
{
    if (!value)
        FRaise(NSInvalidArgumentException, @"*** -[%s addAttribute:value:range:]: nil value",
               object_getClassName(self));
    range_check(self, _cmd, range);
    change_attrs(self, range, ^NSDictionary *(NSDictionary *old) {
        NSMutableDictionary *d = [[old mutableCopy] autorelease];
        [d setObject:value forKey:name];
        return d;
    });
}

- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range
{
    range_check(self, _cmd, range);
    change_attrs(self, range, ^NSDictionary *(NSDictionary *old) {
        NSMutableDictionary *d = [[old mutableCopy] autorelease];
        [d addEntriesFromDictionary:attrs];
        return d;
    });
}

- (void)removeAttribute:(NSString *)name range:(NSRange)range
{
    range_check(self, _cmd, range);
    change_attrs(self, range, ^NSDictionary *(NSDictionary *old) {
        NSMutableDictionary *d = [[old mutableCopy] autorelease];
        [d removeObjectForKey:name];
        return d;
    });
}

- (void)appendAttributedString:(NSAttributedString *)other
{
    [self replaceCharactersInRange:NSMakeRange(_text.length, 0) withAttributedString:other];
}

- (void)insertAttributedString:(NSAttributedString *)other atIndex:(NSUInteger)loc
{
    [self replaceCharactersInRange:NSMakeRange(loc, 0) withAttributedString:other];
}

- (void)deleteCharactersInRange:(NSRange)range
{
    range_check(self, _cmd, range);
    replace_text(self, range, @"", nil);
}

- (void)setAttributedString:(NSAttributedString *)other
{
    [self replaceCharactersInRange:NSMakeRange(0, _text.length) withAttributedString:other];
}

- (void)beginEditing {}
- (void)endEditing {}

@end

/* ---- CFAttributedString --------------------------------------------------------- */

#define AS(x) ((NSAttributedString *)(x))
#define MAS(x) ((NSMutableAttributedString *)(x))

static NSRange ns_range(CFRange r) { return NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length); }

CFAttributedStringRef CFAttributedStringCreate(CFAllocatorRef alloc, CFStringRef str, CFDictionaryRef attributes)
{
    return (CFAttributedStringRef)[[NSAttributedString alloc] initWithString:(NSString *)str
                                                                  attributes:(NSDictionary *)attributes];
}

CFAttributedStringRef CFAttributedStringCreateCopy(CFAllocatorRef alloc, CFAttributedStringRef str)
{
    return (CFAttributedStringRef)[AS(str) copy];
}

CFMutableAttributedStringRef CFAttributedStringCreateMutable(CFAllocatorRef alloc, CFIndex maxLength)
{
    return (CFMutableAttributedStringRef)[[NSMutableAttributedString alloc] init];
}

CFMutableAttributedStringRef CFAttributedStringCreateMutableCopy(CFAllocatorRef alloc, CFIndex maxLength,
                                                                 CFAttributedStringRef str)
{
    return (CFMutableAttributedStringRef)[AS(str) mutableCopy];
}

CFStringRef CFAttributedStringGetString(CFAttributedStringRef str)
{
    return (CFStringRef)AS(str)->_text;
}

CFIndex CFAttributedStringGetLength(CFAttributedStringRef str) { return (CFIndex)AS(str).length; }

CFDictionaryRef CFAttributedStringGetAttributes(CFAttributedStringRef str, CFIndex loc, CFRange *effectiveRange)
{
    NSRange r;
    NSDictionary *d = [AS(str) attributesAtIndex:loc effectiveRange:&r];
    if (effectiveRange)
        *effectiveRange = CFRangeMake(r.location, r.length);
    return (CFDictionaryRef)d;
}

CFTypeRef CFAttributedStringGetAttribute(CFAttributedStringRef str, CFIndex loc, CFStringRef name,
                                         CFRange *effectiveRange)
{
    NSRange r;
    id v = [AS(str) attribute:(NSString *)name atIndex:loc effectiveRange:&r];
    if (effectiveRange)
        *effectiveRange = CFRangeMake(r.location, r.length);
    return (CFTypeRef)v;
}

void CFAttributedStringReplaceString(CFMutableAttributedStringRef str, CFRange range, CFStringRef replacement)
{
    [MAS(str) replaceCharactersInRange:ns_range(range) withString:(NSString *)replacement];
}

void CFAttributedStringSetAttributes(CFMutableAttributedStringRef str, CFRange range, CFDictionaryRef attributes,
                                     Boolean clearOtherAttributes)
{
    if (clearOtherAttributes)
        [MAS(str) setAttributes:(NSDictionary *)attributes range:ns_range(range)];
    else
        [MAS(str) addAttributes:(NSDictionary *)attributes range:ns_range(range)];
}

void CFAttributedStringSetAttribute(CFMutableAttributedStringRef str, CFRange range, CFStringRef name,
                                    CFTypeRef value)
{
    [MAS(str) addAttribute:(NSString *)name value:(id)value range:ns_range(range)];
}

void CFAttributedStringRemoveAttribute(CFMutableAttributedStringRef str, CFRange range, CFStringRef name)
{
    [MAS(str) removeAttribute:(NSString *)name range:ns_range(range)];
}

void CFAttributedStringBeginEditing(CFMutableAttributedStringRef str) {}
void CFAttributedStringEndEditing(CFMutableAttributedStringRef str) {}
