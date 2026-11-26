/* Core Text's font descriptors, a font's traits, names and tables, and the
 * font manager's family list, as Qt's font database uses them on a Mac. */
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool {
        NSArray *families = (__bridge_transfer NSArray *)CTFontManagerCopyAvailableFontFamilyNames();
        printf("families listed %d, no generic names %d\n", families.count > 3,
               ![families containsObject:@"Sans"] && ![families containsObject:@"Monospace"]);

        /* a Mac family that isn't installed finds its stand-in's faces */
        CTFontDescriptorRef fam = CTFontDescriptorCreateWithAttributes(
            (__bridge CFDictionaryRef) @{(id)kCTFontFamilyNameAttribute : @"Helvetica"});
        NSArray *faces = (__bridge_transfer NSArray *)CTFontDescriptorCreateMatchingFontDescriptors(fam, NULL);
        printf("Helvetica's faces %d\n", faces.count >= 2);
        BOOL bold = NO, regular = NO, named = YES;
        for (id d in faces) {
            NSDictionary *t = (__bridge_transfer NSDictionary *)CTFontDescriptorCopyAttribute(
                (__bridge CTFontDescriptorRef)d, kCTFontTraitsAttribute);
            NSString *style = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute(
                (__bridge CTFontDescriptorRef)d, kCTFontStyleNameAttribute);
            named = named && style.length > 0;
            unsigned s = [t[(id)kCTFontSymbolicTrait] unsignedIntValue];
            double w = [t[(id)kCTFontWeightTrait] doubleValue];
            if ((s & kCTFontBoldTrait) && w >= kCTFontWeightSemibold)
                bold = YES;
            if (!(s & (kCTFontBoldTrait | kCTFontItalicTrait)) && w == kCTFontWeightRegular)
                regular = YES;
        }
        printf("a bold face %d, a regular face %d, all named %d\n", bold, regular, named);

        /* a bold descriptor makes a bold font, at its size */
        CTFontDescriptorRef b = CTFontDescriptorCreateCopyWithSymbolicTraits(fam, kCTFontBoldTrait, kCTFontBoldTrait);
        CTFontRef font = CTFontCreateWithFontDescriptor(b, 15, NULL);
        printf("bold font %d, size %g\n", (CTFontGetSymbolicTraits(font) & kCTFontBoldTrait) != 0, CTFontGetSize(font));

        /* its own descriptor names it and gives its size and traits */
        CTFontDescriptorRef own = CTFontCopyFontDescriptor(font);
        NSString *family = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute(own, kCTFontFamilyNameAttribute);
        NSString *mine = (__bridge_transfer NSString *)CTFontCopyFamilyName(font);
        NSNumber *size = (__bridge_transfer NSNumber *)CTFontDescriptorCopyAttribute(own, kCTFontSizeAttribute);
        NSDictionary *traits = (__bridge_transfer NSDictionary *)CTFontCopyTraits(font);
        printf("own family %d, size %g, weight bold %d\n", [family isEqual:mine], size.doubleValue,
               [traits[(id)kCTFontWeightTrait] doubleValue] >= kCTFontWeightSemibold);
        NSString *style = (__bridge_transfer NSString *)CTFontCopyAttribute(font, kCTFontStyleNameAttribute);
        printf("style name %d\n", style.length > 0);

        /* the font file's tables and names */
        NSData *os2 = (__bridge_transfer NSData *)CTFontCopyTable(font, kCTFontTableOS2, 0);
        NSData *head = (__bridge_transfer NSData *)CTFontCopyTable(font, kCTFontTableHead, 0);
        const unsigned char *h = head.bytes;
        printf("OS/2 %d, head magic %d\n", os2.length >= 78,
               head.length >= 16 && h[12] == 0x5F && h[13] == 0x0F && h[14] == 0x3C && h[15] == 0xF5);
        NSString *unique = (__bridge_transfer NSString *)CTFontCopyName(font, kCTFontUniqueNameKey);
        NSString *ps = (__bridge_transfer NSString *)CTFontCopyName(font, kCTFontPostScriptNameKey);
        printf("unique name %d, PostScript name %d\n", unique.length > 0, ps.length > 0);
        NSArray *tables = (__bridge_transfer NSArray *)CTFontCopyAvailableTables(font, 0);
        printf("tables include cmap %d\n", [tables containsObject:@((uint32_t)kCTFontTableCmap)]);

        /* glyph names both ways */
        UniChar a = 'A';
        CGGlyph g = 0;
        CTFontGetGlyphsForCharacters(font, &a, &g, 1);
        NSString *gname = (__bridge_transfer NSString *)CTFontCopyNameForGlyph(font, g);
        printf("glyph name round trip %d\n", !gname || CTFontGetGlyphWithName(font, (__bridge CFStringRef)gname) == g);

        /* a missing family matches nothing; a family's best match keeps the size */
        CTFontDescriptorRef none = CTFontDescriptorCreateWithAttributes(
            (__bridge CFDictionaryRef) @{(id)kCTFontFamilyNameAttribute : @"No Such Family 42"});
        printf("missing family %d\n", CTFontDescriptorCreateMatchingFontDescriptors(none, NULL) == NULL &&
                                          CTFontDescriptorCreateMatchingFontDescriptor(none, NULL) == NULL);
        CTFontDescriptorRef sized = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef) @{
            (id)kCTFontFamilyNameAttribute : @"Menlo", (id)kCTFontSizeAttribute : @11
        });
        CTFontDescriptorRef best = CTFontDescriptorCreateMatchingFontDescriptor(sized, NULL);
        NSNumber *bs = (__bridge_transfer NSNumber *)CTFontDescriptorCopyAttribute(best, kCTFontSizeAttribute);
        NSDictionary *bt = (__bridge_transfer NSDictionary *)CTFontDescriptorCopyAttribute(best, kCTFontTraitsAttribute);
        printf("Menlo's best %g pt, monospace %d\n", bs.doubleValue,
               ([bt[(id)kCTFontSymbolicTrait] unsignedIntValue] & kCTFontMonoSpaceTrait) != 0);

        /* the UI font's descriptor, as Qt's theme fonts start */
        CTFontRef ui = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, 0, NULL);
        CTFontDescriptorRef uid = CTFontCopyFontDescriptor(ui);
        NSNumber *us = (__bridge_transfer NSNumber *)CTFontDescriptorCopyAttribute(uid, kCTFontSizeAttribute);
        printf("system font %g pt\n", us.doubleValue);

        /* fallbacks, and a CGFont made from a font file's data */
        NSArray *cascade = (__bridge_transfer NSArray *)CTFontCopyDefaultCascadeListForLanguages(font, NULL);
        printf("cascade list %d\n", cascade != nil);
        NSURL *url = (__bridge_transfer NSURL *)CTFontCopyAttribute(font, kCTFontURLAttribute);
        (void)url;
        CGFontRef cg = CTFontCopyGraphicsFont(font, NULL);
        CFDataRef cmap = CGFontCopyTableForTag(cg, kCTFontTableCmap);
        printf("graphics font upem %d, cmap %d\n", CGFontGetUnitsPerEm(cg) == (int)CTFontGetUnitsPerEm(font),
               cmap != NULL);
        CTFontRef again = CTFontCreateWithGraphicsFont(cg, 20, NULL, NULL);
        NSString *again_family = (__bridge_transfer NSString *)CTFontCopyFamilyName(again);
        printf("font from graphics font %d, size %g\n", [again_family isEqual:mine], CTFontGetSize(again));

        /* descriptors from data: build a font file from the font's own tables */
        NSArray *fromData = nil;
        {
            NSMutableData *file = [NSMutableData data];
            uint32_t tags[] = {'OS/2', 'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'post'};
            int n = 8;
            NSMutableArray *datas = [NSMutableArray array];
            for (int i = 0; i < n; i++)
                [datas addObject:(__bridge_transfer NSData *)CTFontCopyTable(font, tags[i], 0) ?: [NSData data]];
            unsigned char hdr[12] = {0, 1, 0, 0, 0, (unsigned char)n, 0, 0, 0, 0, 0, 0};
            [file appendBytes:hdr length:12];
            uint32_t off = 12 + 16 * n;
            for (int i = 0; i < n; i++) {
                uint32_t len = (uint32_t)[datas[i] length];
                unsigned char rec[16] = {tags[i] >> 24, tags[i] >> 16, tags[i] >> 8, tags[i], 0, 0, 0, 0,
                                         off >> 24, off >> 16, off >> 8, off, len >> 24, len >> 16, len >> 8, len};
                [file appendBytes:rec length:16];
                off += (len + 3) & ~3u;
            }
            for (int i = 0; i < n; i++) {
                [file appendData:datas[i]];
                unsigned pad = (4 - [datas[i] length] % 4) % 4;
                [file appendBytes:"\0\0\0" length:pad];
            }
            fromData = (__bridge_transfer NSArray *)CTFontManagerCreateFontDescriptorsFromData((__bridge CFDataRef)file);
            CGDataProviderRef p = CGDataProviderCreateWithCFData((__bridge CFDataRef)file);
            CGFontRef dataFont = CGFontCreateWithDataProvider(p);
            CTFontRef drawn = CTFontCreateWithGraphicsFont(dataFont, 13, NULL, NULL);
            printf("font from data drawn %d at %g pt\n", drawn != NULL, CTFontGetSize(drawn));
        }
        NSString *df = (__bridge_transfer NSString *)CTFontDescriptorCopyAttribute(
            (__bridge CTFontDescriptorRef)fromData.firstObject, kCTFontFamilyNameAttribute);
        printf("descriptors from data %d, family from its name table %d\n", (int)fromData.count, df.length > 0);
    }
    return 0;
}
