/* SPDX-License-Identifier: GPL-3.0-or-later
 * The app's icon for the dock (M7): an app bundle with an icon file,
 * started on a display (a headless Weston), writes a hidden desktop entry
 * named after its bundle identifier, with its icon as a 256-pixel PNG
 * beside it, into the user's data folder (run.sh points HOME at a scratch
 * folder). */
#import <Cocoa/Cocoa.h>

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        NSString *share = [NSHomeDirectory() stringByAppendingPathComponent:@".local/share"];
        NSString *entry = [NSString stringWithContentsOfFile:[share stringByAppendingPathComponent:
                                                                  @"applications/org.freemac.ferry.iconapp.desktop"]
                                                    encoding:NSUTF8StringEncoding error:NULL];
        entry = [entry stringByReplacingOccurrencesOfString:[[NSBundle mainBundle] bundlePath] withString:@"<bundle>"];
        printf("%s", entry ? [entry UTF8String] : "no desktop entry\n");
        NSData *png = [NSData dataWithContentsOfFile:[share stringByAppendingPathComponent:
                                                              @"icons/hicolor/256x256/apps/org.freemac.ferry.iconapp.png"]];
        NSBitmapImageRep *rep = png ? [NSBitmapImageRep imageRepWithData:png] : nil;
        printf("icon: %ldx%ld\n", (long)[rep pixelsWide], (long)[rep pixelsHigh]);
        /* the middle of the blue dot */
        NSColor *c = [rep colorAtX:128 y:128];
        printf("middle: r %.0f g %.0f b %.0f a %.0f\n", [c redComponent], [c greenComponent], [c blueComponent],
               [c alphaComponent]);
    }
    return 0;
}
