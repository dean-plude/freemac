/* SPDX-License-Identifier: GPL-3.0-or-later
 * Light and dark (freemac 1.245, Ferry 0.68.0): a Mac app is in freemac's
 * appearance (FERRY_APPEARANCE stands for Dials here), its system colours
 * are drawn in the appearance drawing is in, a colour from a provider asks
 * it once for each, and setting the app's own appearance tells observers
 * of effectiveAppearance, its views, the defaults and the distributed
 * notification centre's observers. Run once dark and once light. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static void rgba(const char *what, NSColor *c)
{
    CGFloat r, g, b, a;
    [c getRed:&r green:&g blue:&b alpha:&a];
    printf("%s %.2f %.2f %.2f %.2f\n", what, r, g, b, a);
}

@interface Watcher : NSObject
@property int changes, themes;
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)ctx
{
    self.changes++;
}
- (void)themeChanged:(NSNotification *)note { self.themes++; }
@end

@interface Told : NSView
@property int told;
@end
@implementation Told
- (void)viewDidChangeEffectiveAppearance { self.told++; }
@end

static const char *name_of(NSAppearance *a)
{
    return [[a bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] UTF8String];
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("app %s, current %s\n", name_of([NSApp effectiveAppearance]), name_of([NSAppearance currentAppearance]));
        printf("AppleInterfaceStyle %s\n",
               [[[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"] ?: @"(none)" UTF8String]);
        NSColor *label = [NSColor labelColor], *window = [NSColor windowBackgroundColor];
        rgba("labelColor", label);
        rgba("windowBackgroundColor", window);
        printf("type catalog %d, list %s, name %s\n", [label type] == NSColorTypeCatalog,
               [[label catalogNameComponent] UTF8String], [[label colorNameComponent] UTF8String]);
        rgba("in sRGB", [label colorUsingColorSpace:[NSColorSpace sRGBColorSpace]]);
        rgba("with alpha 0.5", [label colorWithAlphaComponent:0.5]);

        /* the same colours drawn in the other appearance */
        NSAppearance *aqua = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSAppearance *dark = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        [aqua performAsCurrentDrawingAppearance:^{
          rgba("in Aqua: labelColor", label);
          rgba("in Aqua: textBackgroundColor", [NSColor textBackgroundColor]);
        }];
        [dark performAsCurrentDrawingAppearance:^{
          rgba("in DarkAqua: labelColor", label);
          rgba("in DarkAqua: textBackgroundColor", [NSColor textBackgroundColor]);
          rgba("in DarkAqua: with alpha 0.5", [label colorWithAlphaComponent:0.5]);
        }];
        printf("current again %s\n", name_of([NSAppearance currentAppearance]));

        /* a provider is asked once for each appearance */
        __block int asked = 0;
        NSColor *mine = [NSColor colorWithName:@"mine" dynamicProvider:^NSColor *(NSAppearance *a) {
          asked++;
          BOOL d = [[a bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
              isEqual:NSAppearanceNameDarkAqua];
          return d ? [NSColor colorWithSRGBRed:0.1 green:0.2 blue:0.3 alpha:1]
                   : [NSColor colorWithSRGBRed:0.9 green:0.8 blue:0.7 alpha:1];
        }];
        [aqua performAsCurrentDrawingAppearance:^{
          rgba("mine in Aqua", mine);
          rgba("mine in Aqua again", mine);
        }];
        [dark performAsCurrentDrawingAppearance:^{
          rgba("mine in DarkAqua", mine);
        }];
        printf("asked %d\n", asked);
        printf("equal to itself %d, labelColor to textColor %d, plain colours %d\n", [label isEqual:[NSColor labelColor]],
               [label isEqual:[NSColor textColor]],
               [[NSColor colorWithWhite:0.5 alpha:1] isEqual:[NSColor colorWithWhite:0.5 alpha:1]]);

        /* a view with its own appearance, and one inside it */
        NSView *outer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSView *inner = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
        [outer addSubview:inner];
        [outer setAppearance:aqua];
        printf("inner view %s\n", name_of([inner effectiveAppearance]));
        [outer setAppearance:nil];
        printf("inner view after %s\n", name_of([inner effectiveAppearance]));

        /* the app choosing an appearance of its own */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
        Told *told = [[Told alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [[w contentView] addSubview:told];
        Watcher *watcher = [[Watcher alloc] init];
        [NSApp addObserver:watcher forKeyPath:@"effectiveAppearance" options:0 context:NULL];
        [[NSDistributedNotificationCenter defaultCenter] addObserver:watcher
                                                            selector:@selector(themeChanged:)
                                                                name:@"AppleInterfaceThemeChangedNotification"
                                                              object:nil];
        NSAppearance *other = [[NSApp effectiveAppearance] isEqual:dark] ? aqua : dark;
        [NSApp setAppearance:other];
        printf("after setAppearance: app %s, window %s, told %d, observed %d, theme %d\n",
               name_of([NSApp effectiveAppearance]), name_of([w effectiveAppearance]), told.told, watcher.changes,
               watcher.themes);
        rgba("labelColor now", label);
        printf("AppleInterfaceStyle now %s\n",
               [[[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"] ?: @"(none)" UTF8String]);
        [NSApp setAppearance:nil];
        printf("back: app %s, told %d, observed %d, theme %d\n", name_of([NSApp effectiveAppearance]), told.told,
               watcher.changes, watcher.themes);
        [NSApp removeObserver:watcher forKeyPath:@"effectiveAppearance"];
    }
    return 0;
}
