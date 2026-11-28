/* SPDX-License-Identifier: GPL-3.0-or-later
 * An app's asset catalogue (freemac 1.224, Ferry 0.48.0): the images,
 * colours and data that ferry-actool compiled from the app's .xcassets
 * folders into the bundle's Resources/Assets.ferryassets, an Index.plist of
 * Ferry's own with the files beside it (sdk/ferry-actool says what it
 * holds). +[NSImage imageNamed:], -[NSBundle imageForResource:],
 * +[NSColor colorNamed:bundle:] and NSDataAsset look here first, as a Mac
 * looks in its compiled catalogue. Since 1.271 an app built on a Mac,
 * with its compiled catalogue (Resources/Assets.car), is read too, through
 * AAssetCar.m.
 *
 * Ferry draws in the light appearance only, so an asset's "any" (or
 * "light") variant is the one used, and a dark one only when it is the
 * only one. */
#import "AInternal.h"
#include "AAssetCar.h"

@interface AAssetCatalog : NSObject {
@public
    NSString *dir;
    NSDictionary *images, *colors, *data;
    struct acar *car;    /* the Mac's compiled catalogue, if there is one */
}
@end
@implementation AAssetCatalog
- (void)dealloc
{
    [dir release];
    [images release];
    [colors release];
    [data release];
    acar_close(car);
    [super dealloc];
}
@end

static NSMutableDictionary *catalogs;     /* bundle path -> AAssetCatalog or NSNull */

static AAssetCatalog *catalog_for(NSBundle *bundle)
{
    NSString *res = [bundle resourcePath];
    if (!res)
        return nil;
    @synchronized([AAssetCatalog class]) {
        if (!catalogs)
            catalogs = [[NSMutableDictionary alloc] init];
        id found = catalogs[res];
        if (found)
            return found == [NSNull null] ? nil : found;
        NSString *dir = [res stringByAppendingPathComponent:@"Assets.ferryassets"];
        NSDictionary *index = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"Index.plist"]];
        AAssetCatalog *c = nil;
        if ([index isKindOfClass:[NSDictionary class]] && [index[@"Format"] integerValue] == 1) {
            c = [[[AAssetCatalog alloc] init] autorelease];
            c->dir = [dir copy];
            id v = index[@"Images"];
            c->images = [[v isKindOfClass:[NSDictionary class]] ? v : @{} retain];
            v = index[@"Colors"];
            c->colors = [[v isKindOfClass:[NSDictionary class]] ? v : @{} retain];
            v = index[@"Data"];
            c->data = [[v isKindOfClass:[NSDictionary class]] ? v : @{} retain];
        }
        struct acar *car = acar_open([[res stringByAppendingPathComponent:@"Assets.car"] fileSystemRepresentation]);
        if (car) {
            if (!c) {
                c = [[[AAssetCatalog alloc] init] autorelease];
                c->images = [@{} retain];
                c->colors = [@{} retain];
                c->data = [@{} retain];
            }
            c->car = car;
        }
        catalogs[res] = c ?: (id)[NSNull null];
        return c;
    }
}

/* The variants to use: the "any" and "light" ones, or failing those all. */
static NSArray *light_variants(NSArray *all)
{
    if (![all isKindOfClass:[NSArray class]])
        return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *v in all)
        if ([v isKindOfClass:[NSDictionary class]] && ![v[@"appearance"] isEqual:@"dark"])
            [out addObject:v];
    if (![out count])
        for (NSDictionary *v in all)
            if ([v isKindOfClass:[NSDictionary class]])
                [out addObject:v];
    return out;
}

/* An image from the Mac's compiled catalogue: a bitmap for each size and
 * scale it holds, or its drawing (PDF or SVG). */
static NSImage *car_image(struct acar *car, NSString *name)
{
    struct acar_bitmap b[16];
    int n = acar_image(car, [name UTF8String], b, 16);
    NSImage *im = [[[NSImage alloc] init] autorelease];
    NSSize size = NSZeroSize;
    for (int i = 0; i < n; i++) {
        NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:b[i].width
                                                                         pixelsHigh:b[i].height bitsPerSample:8
                                                                    samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                     colorSpaceName:NSDeviceRGBColorSpace
                                                                        bytesPerRow:b[i].width * 4
                                                                       bitsPerPixel:32] autorelease];
        if (rep && [rep bitmapData]) {
            memcpy([rep bitmapData], b[i].rgba, (size_t)b[i].width * b[i].height * 4);
            NSSize points = NSMakeSize((CGFloat)b[i].width / b[i].scale, (CGFloat)b[i].height / b[i].scale);
            [rep setSize:points];
            /* the 1x size, or the first one's, is the image's own */
            if (size.width <= 0 || b[i].scale == 1)
                size = points;
            [im addRepresentation:rep];
        }
        free(b[i].rgba);
    }
    if (!n) {
        size_t length;
        uint8_t *bytes = acar_vector(car, [name UTF8String], &length);
        NSData *data = bytes ? [NSData dataWithBytesNoCopy:bytes length:length freeWhenDone:YES] : nil;
        for (NSImageRep *rep in data ? [NSImageRep imageRepsWithData:data] : @[]) {
            if (size.width <= 0)
                size = [rep size];
            [im addRepresentation:rep];
        }
    }
    if (![[im representations] count])
        return nil;
    [im setSize:size];
    if ([name hasSuffix:@"Template"])
        [im setTemplate:YES];
    return im;
}

NSImage *AAssetImage(NSBundle *bundle, NSString *name)
{
    if (![name isKindOfClass:[NSString class]] || ![name length])
        return nil;
    AAssetCatalog *c = catalog_for(bundle ?: [NSBundle mainBundle]);
    NSDictionary *entry = c ? c->images[name] : nil;
    if (![entry isKindOfClass:[NSDictionary class]])
        return c && c->car ? car_image(c->car, name) : nil;
    NSImage *im = [[[NSImage alloc] init] autorelease];
    NSSize size = NSZeroSize;
    for (NSDictionary *v in light_variants(entry[@"files"])) {
        NSString *file = v[@"file"];
        if (![file isKindOfClass:[NSString class]])
            continue;
        CGFloat scale = [v[@"scale"] doubleValue];
        if (scale <= 0)
            scale = 1;
        NSData *bytes = [NSData dataWithContentsOfFile:[c->dir stringByAppendingPathComponent:[file lastPathComponent]]];
        for (NSImageRep *rep in bytes ? [NSImageRep imageRepsWithData:bytes] : @[]) {
            if ([rep isKindOfClass:[NSBitmapImageRep class]])
                [rep setSize:NSMakeSize([rep pixelsWide] / scale, [rep pixelsHigh] / scale)];
            if (size.width <= 0)
                size = [rep size];
            [im addRepresentation:rep];
        }
    }
    if (![[im representations] count])
        return nil;
    [im setSize:size];
    id template = entry[@"template"];
    if (template)
        [im setTemplate:[template boolValue]];
    else if ([name hasSuffix:@"Template"])
        [im setTemplate:YES];
    return im;
}

NSColor *AAssetColor(NSBundle *bundle, NSString *name)
{
    if (![name isKindOfClass:[NSString class]] || ![name length])
        return nil;
    AAssetCatalog *c = catalog_for(bundle ?: [NSBundle mainBundle]);
    NSArray *variants = c ? light_variants(c->colors[name]) : nil;
    NSDictionary *v = [variants firstObject];
    double rgba[4];
    if (!v)
        return c && c->car && acar_color(c->car, [name UTF8String], rgba)
                   ? [NSColor colorWithSRGBRed:rgba[0] green:rgba[1] blue:rgba[2] alpha:rgba[3]]
                   : nil;
    NSString *system = v[@"system"];
    if ([system isKindOfClass:[NSString class]]) {
        SEL sel = NSSelectorFromString(system);
        if ([NSColor respondsToSelector:sel]) {
            id color = ((id (*)(id, SEL))objc_msgSend)([NSColor class], sel);
            if ([color isKindOfClass:[NSColor class]])
                return color;
        }
        return nil;
    }
    CGFloat r = [v[@"red"] doubleValue], g = [v[@"green"] doubleValue], b = [v[@"blue"] doubleValue];
    CGFloat a = v[@"alpha"] ? [v[@"alpha"] doubleValue] : 1;
    NSString *space = v[@"space"];
    if ([space hasPrefix:@"gray"] || [space hasPrefix:@"extended-gray"])
        return [NSColor colorWithGenericGamma22White:r alpha:a];
    /* Display P3 and the extended spaces are drawn as sRGB: Ferry's colours
     * are sRGB throughout. */
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:a];
}

/* ---- NSDataAsset --------------------------------------------------------------- */

@implementation NSDataAsset {
    NSString *_name, *_type;
    NSData *_data;
}
- (instancetype)initWithName:(NSDataAssetName)name { return [self initWithName:name bundle:[NSBundle mainBundle]]; }
- (instancetype)initWithName:(NSDataAssetName)name bundle:(NSBundle *)bundle
{
    if (!(self = [super init]))
        return nil;
    AAssetCatalog *c = [name isKindOfClass:[NSString class]] ? catalog_for(bundle ?: [NSBundle mainBundle]) : nil;
    NSDictionary *v = c ? [light_variants(c->data[name]) firstObject] : nil;
    NSString *file = v[@"file"];
    NSData *bytes = [file isKindOfClass:[NSString class]]
                        ? [NSData dataWithContentsOfFile:[c->dir stringByAppendingPathComponent:[file lastPathComponent]]]
                        : nil;
    if (!bytes && !v && c && c->car) {
        /* the Mac's compiled catalogue */
        size_t length;
        char uti[256];
        uint8_t *raw = acar_data(c->car, [name UTF8String], &length, uti, sizeof uti);
        if (raw && length) {
            bytes = [NSData dataWithBytesNoCopy:raw length:length freeWhenDone:YES];
            v = uti[0] ? @{@"type" : @(uti)} : @{};
        } else
            free(raw);
    }
    if (!bytes) {
        [self release];
        return nil;
    }
    _name = [name copy];
    _data = [bytes copy];
    _type = [([v[@"type"] isKindOfClass:[NSString class]] ? v[@"type"] : @"public.data") copy];
    return self;
}
- (void)dealloc
{
    [_name release];
    [_type release];
    [_data release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSDataAssetName)name { return _name; }
- (NSData *)data { return _data; }
- (NSString *)typeIdentifier { return _type; }
@end
