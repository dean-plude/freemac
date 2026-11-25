/* SPDX-License-Identifier: GPL-3.0-or-later
 * Font descriptors and traits (freemac 1.222, Ferry 0.46.0): a descriptor
 * by name and size, by family and traits, by family and weight, with a
 * face, from a font and back, with another size and family; matching the
 * installed faces of a family; the traits a descriptor asks for and the
 * ones a named font has; archiving one; the system font's designs; and
 * applyFontTraits:range: making runs bold and taking italic off, as
 * MacDown's highlighter does. Like appkit_fonts, it uses the DejaVu
 * families, which fontconfig on the test system has. */
#import <Cocoa/Cocoa.h>

static void show(const char *what, NSFont *f)
{
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSFontTraitMask t = [fm traitsOfFont:f];
    printf("%s: %s %g, %s%s%sweight %ld\n", what, f ? [[f familyName] UTF8String] : "no font", [f pointSize],
           t & NSBoldFontMask ? "bold " : "", t & NSItalicFontMask ? "italic " : "",
           t & NSFixedPitchFontMask ? "fixed " : "", (long)[fm weightOfFont:f]);
}

static void runs(const char *what, NSAttributedString *s)
{
    printf("%s:", what);
    for (NSUInteger i = 0; i < [s length];) {
        NSRange r;
        NSFont *f = [s attribute:NSFontAttributeName atIndex:i longestEffectiveRange:&r
                         inRange:NSMakeRange(0, [s length])];
        NSFontTraitMask t = [[NSFontManager sharedFontManager] traitsOfFont:f];
        printf(" [%s|%s%s%s%g]", [[[s string] substringWithRange:r] UTF8String], [[f familyName] UTF8String],
               t & NSBoldFontMask ? " B" : "", t & NSItalicFontMask ? " I" : "", [f pointSize]);
        i = NSMaxRange(r);
    }
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("names: %s %s %s %s\n", [NSFontFamilyAttribute UTF8String], [NSFontTraitsAttribute UTF8String],
               [NSFontSymbolicTrait UTF8String], [NSFontWeightTrait UTF8String]);
        printf("traits: bold %u, italic %u, monospace %u, old names the same %d\n", NSFontDescriptorTraitBold,
               NSFontDescriptorTraitItalic, NSFontDescriptorTraitMonoSpace,
               NSFontBoldTrait == NSFontDescriptorTraitBold && NSFontItalicTrait == NSFontDescriptorTraitItalic);

        /* by name and size */
        NSFontDescriptor *named = [NSFontDescriptor fontDescriptorWithName:@"DejaVuSerif-Bold" size:14];
        NSFont *f = [NSFont fontWithDescriptor:named size:0];
        show("by name", f);
        printf("name %s, size %g, its traits bold %d\n", [named.postscriptName UTF8String], named.pointSize,
               (named.symbolicTraits & NSFontDescriptorTraitBold) != 0);

        /* by family and traits */
        NSFontDescriptor *family = [NSFontDescriptor fontDescriptorWithFontAttributes:@{
            NSFontFamilyAttribute : @"DejaVu Sans",
            NSFontTraitsAttribute : @{NSFontSymbolicTrait : @(NSFontDescriptorTraitBold)}
        }];
        show("family, bold", [NSFont fontWithDescriptor:family size:11]);
        show("family, bold italic",
             [NSFont fontWithDescriptor:[family fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitBold |
                                                                                 NSFontDescriptorTraitItalic]
                                   size:11]);
        show("family, monospace",
             [NSFont fontWithDescriptor:[family fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitMonoSpace]
                                   size:11]);
        NSFontDescriptor *heavy = [NSFontDescriptor fontDescriptorWithFontAttributes:@{
            NSFontFamilyAttribute : @"DejaVu Serif",
            NSFontTraitsAttribute : @{NSFontWeightTrait : @(NSFontWeightBold)}
        }];
        show("family, weight", [NSFont fontWithDescriptor:heavy size:13]);
        show("family, face", [NSFont fontWithDescriptor:[[NSFontDescriptor fontDescriptorWithFontAttributes:@{
                                                            NSFontFamilyAttribute : @"DejaVu Serif"
                                                        }] fontDescriptorWithFace:@"Bold"]
                                                   size:13]);
        /* a named font made bold: its family's bold face */
        NSFontDescriptor *plain = [NSFontDescriptor fontDescriptorWithName:@"DejaVuSans" size:10];
        NSFontDescriptor *bolder = [plain fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitBold];
        show("named, made bold", [NSFont fontWithDescriptor:bolder size:0]);
        printf("made bold: family %s, name dropped %d, traits %u\n",
               [[bolder objectForKey:NSFontFamilyAttribute] UTF8String], bolder.postscriptName == nil,
               bolder.symbolicTraits);

        /* a font's own descriptor, and back */
        NSFont *serif = [[NSFontManager sharedFontManager] fontWithFamily:@"DejaVu Serif" traits:NSBoldFontMask
                                                                   weight:5 size:16];
        NSFontDescriptor *own = serif.fontDescriptor;
        printf("a font's own: name %s, size %g, bold %d\n", [own.postscriptName UTF8String], own.pointSize,
               (own.symbolicTraits & NSFontDescriptorTraitBold) != 0);
        show("and back", [NSFont fontWithDescriptor:own size:0]);
        show("another size", [NSFont fontWithDescriptor:[own fontDescriptorWithSize:9] size:0]);
        show("another family", [NSFont fontWithDescriptor:[own fontDescriptorWithFamily:@"DejaVu Sans"] size:0]);
        show("fontWithSize:", [serif fontWithSize:20]);
        printf("equal descriptors %d, copies the same %d\n",
               [[NSFontDescriptor fontDescriptorWithName:@"DejaVuSans" size:10] isEqual:plain],
               [plain copy] == plain);

        /* matching */
        NSArray *faces = [[NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute : @"DejaVu Sans"}]
            matchingFontDescriptorsWithMandatoryKeys:[NSSet setWithObject:NSFontFamilyAttribute]];
        NSMutableArray *names = [NSMutableArray array];
        for (NSFontDescriptor *d in faces)
            [names addObject:d.postscriptName];
        [names sortUsingSelector:@selector(compare:)];
        printf("faces of DejaVu Sans: %s; family %s, face %s\n", [[names componentsJoinedByString:@" "] UTF8String],
               [[own objectForKey:NSFontFamilyAttribute] UTF8String], [[own objectForKey:NSFontFaceAttribute] UTF8String]);
        NSFontDescriptor *none = [[NSFontDescriptor fontDescriptorWithFontAttributes:@{
            NSFontFamilyAttribute : @"No Such Family"
        }] matchingFontDescriptorWithMandatoryKeys:[NSSet setWithObject:NSFontFamilyAttribute]];
        printf("no such family: %s\n", none ? "found" : "none");

        /* archived and back */
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:family requiringSecureCoding:YES error:NULL];
        NSFontDescriptor *back = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSFontDescriptor class] fromData:data
                                                                      error:NULL];
        printf("archived: equal %d\n", [back isEqual:family]);

        /* the system font's designs */
        NSFontDescriptor *system = [NSFont systemFontOfSize:12].fontDescriptor;
        NSFont *mono = [NSFont fontWithDescriptor:[system fontDescriptorWithDesign:NSFontDescriptorSystemDesignMonospaced]
                                             size:12];
        printf("monospaced design: fixed %d, default design the same %d\n", (int)mono.isFixedPitch,
               [system fontDescriptorWithDesign:NSFontDescriptorSystemDesignDefault] == system);

        /* applyFontTraits:range: */
        NSFont *sans = [NSFont fontWithName:@"DejaVuSans" size:12];
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:@"one two three"
                                                                              attributes:@{NSFontAttributeName : sans}];
        [s applyFontTraits:NSBoldFontMask range:NSMakeRange(4, 3)];
        runs("bold two", s);
        [s applyFontTraits:NSItalicFontMask range:NSMakeRange(0, 7)];
        runs("italic one two", s);
        [s applyFontTraits:NSUnboldFontMask | NSUnitalicFontMask range:NSMakeRange(0, 13)];
        runs("plain again", s);
        NSMutableAttributedString *bare = [[NSMutableAttributedString alloc] initWithString:@"bare"];
        [bare applyFontTraits:NSBoldFontMask range:NSMakeRange(0, 4)];
        printf("no font at first: bold %d\n",
               ([[NSFontManager sharedFontManager] traitsOfFont:[bare attribute:NSFontAttributeName atIndex:0
                                                                   effectiveRange:NULL]] &
                NSBoldFontMask) != 0);
    }
    return 0;
}
