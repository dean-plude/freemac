/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Anki (Python, PyQt6 and Qt WebEngine) needs (freemac 1.NEXT):
 * Python's ctypes asks dyld's shared cache whether a system library is
 * there; status codes as names; a bundle's folders as URLs relative to the
 * bundle, whose file system path is the part inside it (Qt WebEngine joins
 * the two); a video's clean aperture; fonts' file formats; Times among the
 * available families, as Chromium's last resort font; and the printer
 * and screen forms of a font. */
#import <Cocoa/Cocoa.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreServices/CoreServices.h>
#import <CoreText/CoreText.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void cache(void)
{
    printf("libSystem in the cache: %d, Foundation: %d, a file of its own: %d\n",
           _dyld_shared_cache_contains_path("/usr/lib/libSystem.B.dylib"),
           _dyld_shared_cache_contains_path("/System/Library/Frameworks/Foundation.framework/Foundation"),
           _dyld_shared_cache_contains_path("/tmp/libnothing.dylib"));
    size_t n = 7;
    printf("cache range: %d %zu\n", _dyld_get_shared_cache_range(&n) == NULL, n);
}

static void statuses(void)
{
    printf("-43: %s (%s); -50: %s; unknown: \"%s\"\n", GetMacOSStatusErrorString(-43),
           GetMacOSStatusCommentString(-43), GetMacOSStatusErrorString(-50), GetMacOSStatusErrorString(12345));
}

static void bundles(void)
{
    char dir[] = "/tmp/ferry-anki-XXXXXX";
    if (!mkdtemp(dir))
        return;
    NSString *app = [@(dir) stringByAppendingPathComponent:@"Test App.app"];
    [[NSFileManager defaultManager] createDirectoryAtPath:[app stringByAppendingPathComponent:@"Contents/Resources"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:[app stringByAppendingPathComponent:@"Contents/MacOS"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [@{@"CFBundleIdentifier" : @"org.freemac.test-app", @"CFBundleExecutable" : @"Test App"}
        writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
    CFBundleRef b = CFBundleCreate(NULL, (CFURLRef)[NSURL fileURLWithPath:app]);
    CFURLRef res = CFBundleCopyResourcesDirectoryURL(b);
    CFStringRef rel = CFURLCopyFileSystemPath(res, kCFURLPOSIXPathStyle);
    CFURLRef abs = CFURLCopyAbsoluteURL(res);
    CFStringRef full = CFURLCopyFileSystemPath(abs, kCFURLPOSIXPathStyle);
    char path[1024] = "";
    CFURLGetFileSystemRepresentation(res, true, (UInt8 *)path, sizeof path);
    printf("resources: relative to the bundle %d, path %s, full path right %d, resolved right %d\n",
           CFURLGetBaseURL(res) != NULL, [(NSString *)rel UTF8String],
           [(NSString *)full isEqual:[app stringByAppendingPathComponent:@"Contents/Resources"]],
           !strcmp(path, [[app stringByAppendingPathComponent:@"Contents/Resources"] fileSystemRepresentation]));
    NSURL *base = [NSURL fileURLWithPath:@"/Applications/A%20B.app/" isDirectory:YES];
    NSURL *u = [NSURL URLWithString:@"Contents/Frameworks/" relativeToURL:base];
    printf("relativePath: %s; with no base: %s\n", [[u relativePath] UTF8String],
           [[[NSURL fileURLWithPath:@"/tmp/x"] relativePath] UTF8String]);
    CFRelease(full);
    CFRelease(abs);
    CFRelease(rel);
    CFRelease(res);
    CFRelease(b);
    [[NSFileManager defaultManager] removeItemAtPath:@(dir) error:NULL];
}

static void aperture(void)
{
    CMVideoFormatDescriptionRef d = NULL;
    CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_H264, 1920, 1080, NULL, &d);
    CGRect r = CMVideoFormatDescriptionGetCleanAperture(d, true);
    printf("clean aperture: %.0f %.0f %.0f %.0f\n", r.origin.x, r.origin.y, r.size.width, r.size.height);
    CFRelease(d);
}

static void fonts(void)
{
    NSArray *ct = [(NSArray *)CTFontManagerCopyAvailableFontFamilyNames() autorelease];
    NSFontManager *m = [NSFontManager sharedFontManager];
    printf("Times listed: Core Text %d, font manager %d\n", [ct containsObject:@"Times"],
           [[m availableFontFamilies] containsObject:@"Times"]);
    NSArray *members = [m availableMembersOfFontFamily:@"times"];
    NSFont *f = members.count ? [NSFont fontWithName:members[0][0] size:12] : nil;
    printf("Times members: %d, the first one's name %s, makes a font %d\n", members.count > 0,
           members.count ? [members[0][0] UTF8String] : "", f != nil);
    printf("printer and screen forms: %d %d\n", [f printerFont] == f, [f screenFont] == f);
    CTFontDescriptorRef d = CTFontDescriptorCreateWithAttributes(
        (CFDictionaryRef) @{(id)kCTFontFamilyNameAttribute : @"Times"});
    NSArray *list = [(NSArray *)CTFontDescriptorCreateMatchingFontDescriptors(d, NULL) autorelease];
    NSNumber *format = list.count ? [(NSNumber *)CTFontDescriptorCopyAttribute(
                                        (CTFontDescriptorRef)list[0], kCTFontFormatAttribute) autorelease] : nil;
    printf("a Times face's format is known: %d\n", [format intValue] != kCTFontFormatUnrecognized);
    CFRelease(d);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        cache();
        statuses();
        bundles();
        aperture();
        fonts();
    }
    return 0;
}
