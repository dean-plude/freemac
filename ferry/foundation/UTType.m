/* SPDX-License-Identifier: GPL-3.0-or-later
 * Uniform type identifiers (freemac 1.223, Ferry 0.47.0), written from
 * Apple's public "UTType Reference" and its list of system-declared types.
 * A type is known from the table in UTCoreTypes.inc (written by
 * sdk/gen-uttypes.py) or from the main bundle's UTExportedTypeDeclarations
 * and UTImportedTypeDeclarations; the program's own come first. A tag Ferry
 * doesn't know gets a dynamic identifier, "dyn." and the tag class's short
 * name and the tag, which conforms to public.data (a filename extension or
 * MIME type) and is equal only to itself. Identifiers compare without
 * regard to case, as on a Mac. Served as part of CoreServices. */
#import "FInternal.h"
#include <CoreServices/UTType.h>

struct known_type {
    const char *uti, *parents, *extensions, *mimes, *description;
};
#include "UTCoreTypes.inc"

const CFStringRef kUTTagClassFilenameExtension = (CFStringRef)@"public.filename-extension";
const CFStringRef kUTTagClassMIMEType = (CFStringRef)@"public.mime-type";
const CFStringRef kUTTagClassNSPboardType = (CFStringRef)@"com.apple.nspboard-type";
const CFStringRef kUTTagClassOSType = (CFStringRef)@"com.apple.ostype";
const CFStringRef kUTExportedTypeDeclarationsKey = (CFStringRef)@"UTExportedTypeDeclarations";
const CFStringRef kUTImportedTypeDeclarationsKey = (CFStringRef)@"UTImportedTypeDeclarations";
const CFStringRef kUTTypeIdentifierKey = (CFStringRef)@"UTTypeIdentifier";
const CFStringRef kUTTypeTagSpecificationKey = (CFStringRef)@"UTTypeTagSpecification";
const CFStringRef kUTTypeConformsToKey = (CFStringRef)@"UTTypeConformsTo";
const CFStringRef kUTTypeDescriptionKey = (CFStringRef)@"UTTypeDescription";
const CFStringRef kUTTypeIconFileKey = (CFStringRef)@"UTTypeIconFile";
const CFStringRef kUTTypeReferenceURLKey = (CFStringRef)@"UTTypeReferenceURL";
const CFStringRef kUTTypeVersionKey = (CFStringRef)@"UTTypeVersion";

static NSArray *words(const char *s)
{
    if (!*s)
        return @[];
    return [[NSString stringWithUTF8String:s] componentsSeparatedByString:@" "];
}

/* Every declaration, as the dictionaries of an Info.plist: the program's
 * own, then the system's. */
static NSArray *declarations(void)
{
    static NSArray *system;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *all = [NSMutableArray array];
        for (size_t i = 0; i < sizeof known_types / sizeof known_types[0]; i++) {
            const struct known_type *k = &known_types[i];
            NSMutableDictionary *tags = [NSMutableDictionary dictionary];
            if (*k->extensions)
                tags[@"public.filename-extension"] = words(k->extensions);
            if (*k->mimes)
                tags[@"public.mime-type"] = words(k->mimes);
            [all addObject:@{
                @"UTTypeIdentifier" : [NSString stringWithUTF8String:k->uti],
                @"UTTypeConformsTo" : words(k->parents),
                @"UTTypeTagSpecification" : tags,
                @"UTTypeDescription" : [NSString stringWithUTF8String:k->description],
            }];
        }
        system = [all copy];
    });
    NSMutableArray *out = [NSMutableArray array];
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ])
        for (id d in info[key])
            if ([d isKindOfClass:[NSDictionary class]] && [d[@"UTTypeIdentifier"] isKindOfClass:[NSString class]])
                [out addObject:d];
    [out addObjectsFromArray:system];
    return out;
}

static NSDictionary *declaration(NSString *uti)
{
    if (![uti isKindOfClass:[NSString class]])
        return nil;
    for (NSDictionary *d in declarations())
        if ([d[@"UTTypeIdentifier"] caseInsensitiveCompare:uti] == NSOrderedSame)
            return d;
    return nil;
}

/* A declaration's value as a list, whether it was written as one string
 * or a list of them. */
static NSArray *as_list(id v)
{
    if ([v isKindOfClass:[NSString class]])
        return @[ v ];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}

static NSString *dynamic_prefix(NSString *tagClass)
{
    if ([tagClass isEqualToString:@"public.filename-extension"])
        return @"dyn.ext.";
    if ([tagClass isEqualToString:@"public.mime-type"])
        return @"dyn.mime.";
    if ([tagClass isEqualToString:@"com.apple.ostype"])
        return @"dyn.ostype.";
    if ([tagClass isEqualToString:@"com.apple.nspboard-type"])
        return @"dyn.pboard.";
    return nil;
}

static BOOL conforms(NSString *uti, NSString *other, int depth)
{
    if (!uti || !other || depth > 32)
        return NO;
    if ([uti caseInsensitiveCompare:other] == NSOrderedSame)
        return YES;
    NSDictionary *d = declaration(uti);
    if (!d) {
        /* a dynamic type of a file's extension or MIME type is data */
        if ([uti hasPrefix:@"dyn.ext."] || [uti hasPrefix:@"dyn.mime."])
            return conforms(@"public.data", other, depth + 1);
        return NO;
    }
    for (NSString *parent in as_list(d[@"UTTypeConformsTo"]))
        if ([parent isKindOfClass:[NSString class]] && conforms(parent, other, depth + 1))
            return YES;
    return NO;
}

Boolean UTTypeConformsTo(CFStringRef uti, CFStringRef conformsToUTI)
{
    return conforms((NSString *)uti, (NSString *)conformsToUTI, 0);
}

Boolean UTTypeEqual(CFStringRef a, CFStringRef b)
{
    if (!a || !b)
        return a == b;
    return [(NSString *)a caseInsensitiveCompare:(NSString *)b] == NSOrderedSame;
}

static NSArray *identifiers_for_tag(NSString *tagClass, NSString *tag, NSString *conformingTo)
{
    NSMutableArray *out = [NSMutableArray array];
    if (![tagClass isKindOfClass:[NSString class]] || ![tag isKindOfClass:[NSString class]])
        return out;
    for (NSDictionary *d in declarations()) {
        NSDictionary *spec = d[@"UTTypeTagSpecification"];
        if (![spec isKindOfClass:[NSDictionary class]])
            continue;
        for (NSString *t in as_list(spec[tagClass]))
            if ([t isKindOfClass:[NSString class]] && [t caseInsensitiveCompare:tag] == NSOrderedSame) {
                NSString *uti = d[@"UTTypeIdentifier"];
                if ((!conformingTo || conforms(uti, conformingTo, 0)) && ![out containsObject:uti])
                    [out addObject:uti];
                break;
            }
    }
    return out;
}

CFStringRef UTTypeCreatePreferredIdentifierForTag(CFStringRef tagClass, CFStringRef tag, CFStringRef conformingToUTI)
{
    NSArray *found = identifiers_for_tag((NSString *)tagClass, (NSString *)tag, (NSString *)conformingToUTI);
    if ([found count])
        return (CFStringRef)[[found objectAtIndex:0] copy];
    NSString *prefix = dynamic_prefix((NSString *)tagClass);
    if (!prefix || !tag)
        return NULL;
    return (CFStringRef)[[prefix stringByAppendingString:[(NSString *)tag lowercaseString]] retain];
}

CFArrayRef UTTypeCreateAllIdentifiersForTag(CFStringRef tagClass, CFStringRef tag, CFStringRef conformingToUTI)
{
    NSArray *found = identifiers_for_tag((NSString *)tagClass, (NSString *)tag, (NSString *)conformingToUTI);
    if (![found count]) {
        CFStringRef dyn = UTTypeCreatePreferredIdentifierForTag(tagClass, tag, conformingToUTI);
        if (!dyn)
            return NULL;
        found = @[ (NSString *)dyn ];
        CFRelease(dyn);
    }
    return (CFArrayRef)[found copy];
}

static NSArray *tags(NSString *uti, NSString *tagClass)
{
    NSDictionary *spec = declaration(uti)[@"UTTypeTagSpecification"];
    if ([spec isKindOfClass:[NSDictionary class]])
        return as_list(spec[tagClass]);
    NSString *prefix = dynamic_prefix(tagClass);
    if (prefix && [uti hasPrefix:prefix])
        return @[ [uti substringFromIndex:[prefix length]] ];
    return @[];
}

CFStringRef UTTypeCopyPreferredTagWithClass(CFStringRef uti, CFStringRef tagClass)
{
    NSString *t = [tags((NSString *)uti, (NSString *)tagClass) firstObject];
    return [t isKindOfClass:[NSString class]] ? (CFStringRef)[t copy] : NULL;
}

CFArrayRef UTTypeCopyAllTagsWithClass(CFStringRef uti, CFStringRef tagClass)
{
    NSArray *t = tags((NSString *)uti, (NSString *)tagClass);
    return [t count] ? (CFArrayRef)[t copy] : NULL;
}

CFStringRef UTTypeCopyDescription(CFStringRef uti)
{
    NSString *d = declaration((NSString *)uti)[@"UTTypeDescription"];
    return [d isKindOfClass:[NSString class]] ? (CFStringRef)[d copy] : NULL;
}

CFDictionaryRef UTTypeCopyDeclaration(CFStringRef uti)
{
    NSDictionary *d = declaration((NSString *)uti);
    return d ? (CFDictionaryRef)[d copy] : NULL;
}

CFURLRef UTTypeCopyDeclaringBundleURL(CFStringRef uti)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ])
        for (id d in info[key])
            if ([d isKindOfClass:[NSDictionary class]] && UTTypeEqual((CFStringRef)d[@"UTTypeIdentifier"], uti))
                return (CFURLRef)[[[NSBundle mainBundle] bundleURL] copy];
    return NULL;
}

Boolean UTTypeIsDeclared(CFStringRef uti) { return declaration((NSString *)uti) != nil; }
Boolean UTTypeIsDynamic(CFStringRef uti) { return uti && [(NSString *)uti hasPrefix:@"dyn."]; }

CFStringRef UTCreateStringForOSType(OSType type)
{
    char s[5] = {(char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, 0};
    return (CFStringRef)[[NSString alloc] initWithBytes:s length:4 encoding:NSMacOSRomanStringEncoding];
}

OSType UTGetOSTypeFromString(CFStringRef string)
{
    const char *s = [(NSString *)string cStringUsingEncoding:NSMacOSRomanStringEncoding];
    if (!s || strlen(s) != 4)
        return 0;
    return ((OSType)(unsigned char)s[0] << 24) | ((OSType)(unsigned char)s[1] << 16) |
           ((OSType)(unsigned char)s[2] << 8) | (unsigned char)s[3];
}
