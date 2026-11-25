/* SPDX-License-Identifier: GPL-3.0-or-later
 * An app's asset catalogue as ferry-actool compiles it (freemac 1.224,
 * Ferry 0.48.0), in AssetApp.app, made by make_assets.py: images found by
 * +[NSImage imageNamed:] and -[NSBundle imageForResource:], with a
 * representation for each scale at the image's size in points, the mac
 * idiom over the universal one, the light version over the dark one, and
 * template images by the catalogue's say or by name; names in a folder that
 * provides a namespace; colours by +[NSColor colorNamed:] in each way a
 * catalogue writes them; NSDataAsset; and the app icon, an .icns file named
 * in Info.plist, as the application's icon. */
#import <Cocoa/Cocoa.h>

static void rgba(NSColor *c, CGFloat *v)
{
    v[0] = v[1] = v[2] = v[3] = 0;
    [c getRed:&v[0] green:&v[1] blue:&v[2] alpha:&v[3]];
}

static void show_image(NSString *name, NSImage *im)
{
    if (!im) {
        printf("%s: none\n", [name UTF8String]);
        return;
    }
    printf("%s: %gx%g points, template %d, reps", [name UTF8String], im.size.width, im.size.height, im.isTemplate);
    for (NSImageRep *rep in im.representations)
        printf(" %ldx%ld@%gx%g", (long)rep.pixelsWide, (long)rep.pixelsHigh, rep.size.width, rep.size.height);
    NSBitmapImageRep *rep = (NSBitmapImageRep *)im.representations.firstObject;
    if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
        CGFloat v[4];
        rgba([rep colorAtX:0 y:0], v);
        printf(", first pixel %.0f %.0f %.0f", v[0] * 255, v[1] * 255, v[2] * 255);
    }
    printf("\n");
}

static void show_color(NSString *name)
{
    NSColor *c = [NSColor colorNamed:name];
    if (!c) {
        printf("color %s: none\n", [name UTF8String]);
        return;
    }
    CGFloat v[4];
    rgba(c, v);
    printf("color %s: %.3f %.3f %.3f alpha %.2f\n", [name UTF8String], v[0], v[1], v[2], v[3]);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (NSString *name in @[ @"StatusIcon", @"Badge", @"ArrowTemplate", @"Toolbar/Star", @"Star", @"Dot",
                                  @"Group/Dot", @"Gear", @"NoSuchImage" ])
            show_image(name, [NSImage imageNamed:name]);
        show_image(@"bundle StatusIcon", [[NSBundle mainBundle] imageForResource:@"StatusIcon"]);
        printf("same image each time %d\n", [NSImage imageNamed:@"StatusIcon"] == [NSImage imageNamed:@"StatusIcon"]);

        for (NSString *name in @[ @"AccentColor", @"Brand", @"Hex", @"Shade", @"NoSuchColor" ])
            show_color(name);
        NSColor *link = [NSColor colorNamed:@"LinkColor"];
        printf("color LinkColor is the system blue %d\n", link != nil && [link isEqual:[NSColor systemBlueColor]]);
        printf("color in another bundle: %s\n", [NSColor colorNamed:@"Brand" bundle:[NSBundle bundleWithPath:NSTemporaryDirectory()]] ? "found" : "none");

        NSDataAsset *notes = [[NSDataAsset alloc] initWithName:@"Notes"];
        printf("data %s, %s: %s", [notes.name UTF8String], [notes.typeIdentifier UTF8String],
               [[[NSString alloc] initWithData:notes.data encoding:NSUTF8StringEncoding] UTF8String]);
        printf("data NoSuchData: %s\n", [[NSDataAsset alloc] initWithName:@"NoSuchData"] ? "found" : "none");

        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        printf("icon file %s, icon name %s\n", [info[@"CFBundleIconFile"] UTF8String],
               [info[@"CFBundleIconName"] UTF8String]);
        NSString *path = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        NSData *icns = [NSData dataWithContentsOfFile:path];
        const unsigned char *b = icns.bytes;
        printf("icns %.4s, length %s, entries", icns.length >= 8 ? (const char *)b : "",
               icns.length >= 8 && (NSUInteger)((b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]) == icns.length ? "right" : "wrong");
        for (NSUInteger at = 8; at + 8 <= icns.length;) {
            NSUInteger n = (NSUInteger)((b[at + 4] << 24) | (b[at + 5] << 16) | (b[at + 6] << 8) | b[at + 7]);
            printf(" %.4s", (const char *)b + at);
            if (n < 8)
                break;
            at += n;
        }
        printf("\n");
        NSImage *appIcon = [NSApp applicationIconImage];
        NSBitmapImageRep *rep = (NSBitmapImageRep *)appIcon.representations.firstObject;
        CGFloat v[4] = {0, 0, 0, 0};
        if ([rep isKindOfClass:[NSBitmapImageRep class]])
            rgba([rep colorAtX:rep.pixelsWide / 2 y:rep.pixelsHigh / 2], v);
        printf("application icon from the icns %d\n", fabs(v[2] * 255 - 200) < 2 && fabs(v[0] * 255 - 40) < 2);
    }
    return 0;
}
