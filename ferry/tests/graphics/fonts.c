/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.NEXT): Core Text's font descriptors, collections and
 * font manager, as VLC's subtitle text uses them to find font files for
 * FreeType: a collection matched by family finds the family's installed
 * faces, each with its file's URL and its traits; the file's own faces
 * include it; a descriptor made from just a PostScript name answers its file
 * and traits from the face it names; a Mac family that isn't installed
 * matches nothing; CTFontCreateForString keeps a font that has the
 * character. */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <unistd.h>

static CFStringRef attr(CTFontDescriptorRef d, CFStringRef key)
{
    return (CFStringRef)CTFontDescriptorCopyAttribute(d, key);
}

static float trait(CTFontDescriptorRef d, CFStringRef key)
{
    CFDictionaryRef traits = (CFDictionaryRef)CTFontDescriptorCopyAttribute(d, kCTFontTraitsAttribute);
    float v = -9;
    if (traits) {
        CFNumberRef n = (CFNumberRef)CFDictionaryGetValue(traits, key);
        if (n)
            CFNumberGetValue(n, kCFNumberFloatType, &v);
        CFRelease(traits);
    }
    return v;
}

static CFArrayRef matching(CFStringRef key, CFStringRef value)
{
    CFMutableDictionaryRef a = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    CFDictionaryAddValue(a, key, value);
    CTFontDescriptorRef d = CTFontDescriptorCreateWithAttributes(a);
    CFArrayRef list = CFArrayCreate(NULL, (const void **)&d, 1, NULL);
    CTFontCollectionRef c = CTFontCollectionCreateWithFontDescriptors(list, NULL);
    CFArrayRef found = CTFontCollectionCreateMatchingFontDescriptors(c);
    CFRelease(c);
    CFRelease(list);
    CFRelease(d);
    CFRelease(a);
    return found;
}

int main(void)
{
    CTFontRef sans = CTFontCreateWithName(CFSTR("Helvetica"), 12, NULL);
    CFStringRef family = CTFontCopyFamilyName(sans);
    CFArrayRef faces = matching(kCTFontFamilyNameAttribute, family);
    CFIndex n = faces ? CFArrayGetCount(faces) : 0;
    printf("the sans-serif family has faces: %d\n", n > 0);

    int urls = 1, ours = 1, bold = 0, regular = 0, byname = 1;
    for (CFIndex i = 0; i < n; i++) {
        CTFontDescriptorRef d = CFArrayGetValueAtIndex(faces, i);
        CFURLRef url = (CFURLRef)CTFontDescriptorCopyAttribute(d, kCTFontURLAttribute);
        char path[1024] = "";
        CFStringRef p = url ? CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle) : NULL;
        if (p)
            CFStringGetCString(p, path, sizeof path, kCFStringEncodingUTF8);
        urls &= path[0] == '/' && access(path, R_OK) == 0;

        CFArrayRef inFile = url ? CTFontManagerCreateFontDescriptorsFromURL(url) : NULL;
        int found = 0;
        for (CFIndex j = 0; inFile && j < CFArrayGetCount(inFile); j++) {
            CFStringRef f = attr(CFArrayGetValueAtIndex(inFile, j), kCTFontFamilyNameAttribute);
            found |= f && CFStringCompare(f, family, kCFCompareCaseInsensitive) == kCFCompareEqualTo;
            if (f)
                CFRelease(f);
        }
        ours &= found;

        float w = trait(d, kCTFontWeightTrait), s = trait(d, kCTFontSlantTrait);
        bold |= w > 0.23f;
        regular |= w > -0.01f && w < 0.01f && s < 0.03f;

        CFStringRef ps = attr(d, kCTFontNameAttribute);
        CTFontDescriptorRef named = CTFontDescriptorCreateWithNameAndSize(ps, 0);
        CFURLRef again = (CFURLRef)CTFontDescriptorCopyAttribute(named, kCTFontURLAttribute);
        byname &= again && CFEqual(again, url) && trait(named, kCTFontWeightTrait) == w;
        if (again)
            CFRelease(again);
        CFRelease(named);
        CFRelease(ps);
        if (inFile)
            CFRelease(inFile);
        if (p)
            CFRelease(p);
        if (url)
            CFRelease(url);
    }
    printf("each face's file is there: %d, and holds it: %d\n", urls, ours);
    printf("a regular face and a bold one: %d %d\n", regular, bold);
    printf("a PostScript name finds the same file and traits: %d\n", byname);

    CFArrayRef none = matching(kCTFontFamilyNameAttribute, CFSTR("No Such Family Here"));
    printf("a family that isn't installed matches nothing: %d\n", none == NULL);

    CFStringRef a = CFSTR("A");
    CTFontRef same = CTFontCreateForString(sans, a, CFRangeMake(0, 1));
    CFStringRef sameFamily = CTFontCopyFamilyName(same);
    printf("a font with the character is kept: %d\n", CFEqual(sameFamily, family));

    CFRelease(sameFamily);
    CFRelease(same);
    if (faces)
        CFRelease(faces);
    CFRelease(family);
    CFRelease(sans);
    return 0;
}
