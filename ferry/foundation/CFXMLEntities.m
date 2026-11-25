/* SPDX-License-Identifier: GPL-3.0-or-later
 * XML entities in strings (freemac 1.226, Ferry 0.50.0):
 * CFXMLCreateStringByEscapingEntities and
 * CFXMLCreateStringByUnescapingEntities, written for freemac from Apple's
 * public documentation of them. Escaping writes XML's five predefined
 * entities; unescaping reads them, numeric character references and the
 * caller's dictionary of other entities. Sequel Pro writes its XML exports
 * with them. */
#import "FInternal.h"

CFStringRef CFXMLCreateStringByEscapingEntities(CFAllocatorRef allocator, CFStringRef string,
                                                CFDictionaryRef entitiesDictionary)
{
    (void)allocator;
    (void)entitiesDictionary;
    if (!string)
        return NULL;
    NSString *s = (NSString *)string;
    NSUInteger n = [s length];
    NSMutableString *out = [[NSMutableString alloc] initWithCapacity:n];
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < n; i++) {
        NSString *entity = nil;
        switch ([s characterAtIndex:i]) {
        case '&': entity = @"&amp;"; break;
        case '<': entity = @"&lt;"; break;
        case '>': entity = @"&gt;"; break;
        case '"': entity = @"&quot;"; break;
        case '\'': entity = @"&apos;"; break;
        default: break;
        }
        if (!entity)
            continue;
        if (i > start)
            [out appendString:[s substringWithRange:NSMakeRange(start, i - start)]];
        [out appendString:entity];
        start = i + 1;
    }
    if (n > start)
        [out appendString:[s substringWithRange:NSMakeRange(start, n - start)]];
    return (CFStringRef)out;
}

/* A numeric character reference's character (after "&#"), or nil. */
static NSString *numeric_reference(NSString *name)
{
    if ([name length] < 2 || [name characterAtIndex:0] != '#')
        return nil;
    BOOL hex = [name characterAtIndex:1] == 'x' || [name characterAtIndex:1] == 'X';
    NSString *digits = [name substringFromIndex:hex ? 2 : 1];
    if (![digits length])
        return nil;
    const char *d = [digits UTF8String];
    char *end = NULL;
    unsigned long code = strtoul(d, &end, hex ? 16 : 10);
    if (!end || *end || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF))
        return nil;
    if (code > 0xFFFF) {
        unichar pair[2] = {(unichar)(0xD800 + ((code - 0x10000) >> 10)), (unichar)(0xDC00 + ((code - 0x10000) & 0x3FF))};
        return [NSString stringWithCharacters:pair length:2];
    }
    unichar one = (unichar)code;
    return [NSString stringWithCharacters:&one length:1];
}

CFStringRef CFXMLCreateStringByUnescapingEntities(CFAllocatorRef allocator, CFStringRef string,
                                                  CFDictionaryRef entitiesDictionary)
{
    (void)allocator;
    if (!string)
        return NULL;
    NSString *s = (NSString *)string;
    NSDictionary *more = (NSDictionary *)entitiesDictionary;
    NSDictionary *named = @{@"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"", @"apos": @"'"};
    NSUInteger n = [s length], i = 0, start = 0;
    NSMutableString *out = [[NSMutableString alloc] initWithCapacity:n];
    while (i < n) {
        if ([s characterAtIndex:i] != '&') {
            i++;
            continue;
        }
        NSRange semi = [s rangeOfString:@";" options:0 range:NSMakeRange(i + 1, n - i - 1)];
        if (semi.location == NSNotFound)
            break;
        NSString *name = [s substringWithRange:NSMakeRange(i + 1, semi.location - i - 1)];
        id value = named[name] ?: (more ? more[name] : nil) ?: numeric_reference(name);
        if (![value isKindOfClass:[NSString class]]) {
            i++;
            continue;
        }
        if (i > start)
            [out appendString:[s substringWithRange:NSMakeRange(start, i - start)]];
        [out appendString:value];
        i = start = semi.location + 1;
    }
    if (n > start)
        [out appendString:[s substringWithRange:NSMakeRange(start, n - start)]];
    return (CFStringRef)out;
}
