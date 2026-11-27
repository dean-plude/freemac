/* SPDX-License-Identifier: GPL-3.0-or-later
 * What kitty's official download asks for before it opens a window
 * (freemac, Ferry, kitty 0.37.0): the old dyld calls that look up a
 * symbol by its linker name ("_strlen"), literal dictionaries and
 * floating-point numbers that newer clang writes into a program as objects
 * of their own (laid out here by hand, as they sit in its GLFW module), the
 * HIToolbox framework's bundle (where the keyboard layout calls live), and
 * the Mac's Menlo among Core Text's available fonts, marked monospaced. */
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>   /* where HIToolbox lives */
#include <string.h>

typedef void *NSSymbol, *NSModule;
extern int NSIsSymbolNameDefined(const char *name);
extern NSSymbol NSLookupAndBindSymbol(const char *name);
extern void *NSAddressOfSymbol(NSSymbol symbol);
extern NSModule NSModuleForSymbol(NSSymbol symbol);
extern const char *NSNameOfSymbol(NSSymbol symbol);
extern const char *NSLibraryNameForModule(NSModule module);

extern char dictionary_class __asm__("_OBJC_CLASS_$_NSConstantDictionary");
extern char double_class __asm__("_OBJC_CLASS_$_NSConstantDoubleNumber");
extern char float_class __asm__("_OBJC_CLASS_$_NSConstantFloatNumber");
extern char integer_class __asm__("_OBJC_CLASS_$_NSConstantIntegerNumber");

struct dictionary { void *isa; unsigned long options, count; id const *keys, *objects; };
struct double_number { void *isa; double value; };
struct float_number { void *isa; float value; };
struct integer_number { void *isa; const char *encoding; long long value; };

static struct double_number half = {&double_class, 0.5};
static struct float_number quarter = {&float_class, 0.25f};
static struct integer_number seven = {&integer_class, "i", 7};
static id const keys[] = {@"blend", @"scale", @"count"};
static id const objects[] = {(id)&half, (id)&quarter, (id)&seven};
static struct dictionary options = {&dictionary_class, 1, 3, keys, objects};

int main(void)
{
    @autoreleasepool {
        printf("_strlen is defined: %d, _no_such_call_here: %d\n", NSIsSymbolNameDefined("_strlen"),
               NSIsSymbolNameDefined("_no_such_call_here"));
        NSSymbol s = NSLookupAndBindSymbol("_strlen");
        printf("bound to strlen: %s, named %s\n", NSAddressOfSymbol(s) == (void *)strlen ? "yes" : "no",
               NSNameOfSymbol(s));
        const char *lib = NSLibraryNameForModule(NSModuleForSymbol(s));
        printf("in a library: %s\n", lib && *lib ? "yes" : "no");

        NSDictionary *d = (NSDictionary *)&options;
        printf("dictionary: %s, %lu entries, is a dictionary: %s\n", object_getClassName(d),
               (unsigned long)[d count], [d isKindOfClass:[NSDictionary class]] ? "yes" : "no");
        printf("blend %g (%s), scale %g (%s), count %d\n", [d[@"blend"] doubleValue], [d[@"blend"] objCType],
               [d[@"scale"] floatValue], [d[@"scale"] objCType], [d[@"count"] intValue]);
        printf("missing key: %s\n", d[@"other"] ? "found" : "nil");
        NSMutableArray *seen = [NSMutableArray array];
        for (NSString *k in d)
            [seen addObject:k];
        printf("keys in order: %s\n", [[seen componentsJoinedByString:@","] UTF8String]);
        printf("equals a dictionary made at run time: %s\n",
               [d isEqual:@{@"blend" : @0.5, @"scale" : @0.25f, @"count" : @7}] ? "yes" : "no");
        printf("0.5 equals @0.5: %s, 0.25 compares with @1: %ld\n", [(id)&half isEqual:@0.5] ? "yes" : "no",
               (long)[(NSNumber *)&quarter compare:@1]);
        [d retain];
        [d release];
        [d release];
        printf("still there after release: %lu entries\n", (unsigned long)[d count]);

        NSBundle *hi = [NSBundle bundleWithIdentifier:@"com.apple.HIToolbox"];
        printf("HIToolbox bundle: %s, identifier %s, has an executable: %s\n", hi ? "yes" : "no",
               [[hi bundleIdentifier] UTF8String], [hi executablePath] ? "yes" : "no");

        CTFontCollectionRef all = CTFontCollectionCreateFromAvailableFonts(NULL);
        NSArray *faces = (NSArray *)CTFontCollectionCreateMatchingFontDescriptors(all);
        CFRelease(all);
        int menlo = 0, mono = 0, bold = 0;
        for (id f in faces) {
            NSString *family = (NSString *)CTFontDescriptorCopyAttribute(
                (CTFontDescriptorRef)f, kCTFontFamilyNameAttribute);
            if (![family isEqual:@"Menlo"])
                continue;
            menlo++;
            NSDictionary *traits = (NSDictionary *)CTFontDescriptorCopyAttribute(
                (CTFontDescriptorRef)f, kCTFontTraitsAttribute);
            unsigned t = [traits[(id)kCTFontSymbolicTrait] unsignedIntValue];
            mono += !!(t & kCTFontTraitMonoSpace);
            NSString *name = (NSString *)CTFontDescriptorCopyAttribute(
                (CTFontDescriptorRef)f, kCTFontNameAttribute);
            if ([name isEqual:@"Menlo-Bold"]) {
                bold = 1;
                CTFontRef font = CTFontCreateWithFontDescriptor((CTFontDescriptorRef)f, 12, NULL);
                CGGlyph gi, gm;
                UniChar ci = 'i', cm = 'M';
                CTFontGetGlyphsForCharacters(font, &ci, &gi, 1);
                CTFontGetGlyphsForCharacters(font, &cm, &gm, 1);
                double ai = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &gi, NULL, 1);
                double am = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &gm, NULL, 1);
                printf("Menlo-Bold opens, i as wide as M: %s, bold: %s\n", ai == am && ai > 0 ? "yes" : "no",
                       CTFontGetSymbolicTraits(font) & kCTFontTraitBold ? "yes" : "no");
                CFRelease(font);
            }
        }
        printf("Menlo listed: %s, every face monospaced: %s, Menlo-Bold among them: %s\n", menlo >= 2 ? "yes" : "no",
               menlo && mono == menlo ? "yes" : "no", bold ? "yes" : "no");
    }
    return 0;
}
