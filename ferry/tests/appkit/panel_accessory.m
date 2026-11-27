/* SPDX-License-Identifier: GPL-3.0-or-later
 * An Open or Save panel's accessory view, with no display (freemac 1.252,
 * Ferry 0.75.0). The system's chooser can't hold an app's view, so its
 * pop-up menus and check boxes become the chooser's choices, named by the
 * label beside a pop-up or a check box's title; what was chosen goes back
 * into the controls as clicks would, before the file is taken. Here
 * FERRY_PANEL_CHOICES answers them as the chooser would: a format menu whose
 * action changes the allowed types gives the saved file its new extension,
 * as a Mac's panel does, and a check box's action and binding see it. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>

@interface Saver : NSObject
@property(weak) NSSavePanel *panel;
@property BOOL alpha;
@property int formatChanges;
@end
@implementation Saver
- (void)formatChanged:(NSPopUpButton *)sender
{
    self.formatChanges++;
    self.panel.allowedFileTypes = @[ @[ @"png", @"jpg", @"tiff", @"gif" ][[sender indexOfSelectedItem]] ];
}
- (void)alphaChanged:(NSButton *)sender { printf("check box action: %s\n", sender.state ? "on" : "off"); }
@end

static NSTextField *label(NSString *s, NSRect r)
{
    NSTextField *t = [NSTextField labelWithString:s];
    t.frame = r;
    return t;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Saver *saver = [[Saver alloc] init];
        NSSavePanel *panel = [NSSavePanel savePanel];
        saver.panel = panel;
        panel.allowedFileTypes = @[ @"png" ];

        NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 60)];
        [accessory addSubview:label(@"Format:", NSMakeRect(20, 32, 60, 17))];
        NSPopUpButton *format = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(86, 28, 120, 26) pullsDown:NO];
        [format addItemsWithTitles:@[ @"PNG", @"JPEG", @"TIFF" ]];
        [[format menu] addItem:[NSMenuItem separatorItem]];
        [format addItemWithTitle:@"GIF"];
        [[format lastItem] setEnabled:NO];
        format.autoenablesItems = NO;
        format.target = saver;
        format.action = @selector(formatChanged:);
        [accessory addSubview:format];
        NSButton *alpha = [NSButton checkboxWithTitle:@"Alpha" target:saver action:@selector(alphaChanged:)];
        alpha.frame = NSMakeRect(220, 30, 80, 18);
        [alpha bind:NSValueBinding toObject:saver withKeyPath:@"alpha" options:nil];
        [accessory addSubview:alpha];
        NSButton *hidden = [NSButton checkboxWithTitle:@"Hidden" target:nil action:nil];
        hidden.hidden = YES;
        [accessory addSubview:hidden];
        panel.accessoryView = accessory;

        for (NSDictionary *c in [panel performSelector:@selector(_choices)]) {
            printf("choice %s:", [c[@"label"] UTF8String]);
            for (NSString *t in c[@"titles"] ?: @[ @"(check box)" ])
                printf(" %s", [t UTF8String]);
            printf("\n");
        }

        NSString *dir = NSTemporaryDirectory();
        setenv("FERRY_PANEL_ANSWER", [[dir stringByAppendingPathComponent:@"picture.png"] UTF8String], 1);
        unsetenv("FERRY_PANEL_CHOICES");
        NSModalResponse r = [panel runModal];
        printf("nothing changed: %s, %s, format actions %d\n", r == NSModalResponseOK ? "OK" : "Cancel",
               [[panel.URL lastPathComponent] UTF8String], saver.formatChanges);

        setenv("FERRY_PANEL_CHOICES", "Format=JPEG\nAlpha=true\nNo such=thing", 1);
        r = [panel runModal];
        printf("JPEG with alpha: %s, %s, format %s, format actions %d, alpha bound %d\n",
               r == NSModalResponseOK ? "OK" : "Cancel", [[panel.URL lastPathComponent] UTF8String],
               [[format titleOfSelectedItem] UTF8String], saver.formatChanges, saver.alpha);

        setenv("FERRY_PANEL_ANSWER", [[dir stringByAppendingPathComponent:@"notes"] UTF8String], 1);
        setenv("FERRY_PANEL_CHOICES", "Format=TIFF\nFormat=GIF", 1);
        r = [panel runModal];
        printf("TIFF, no extension typed: %s, format %s (GIF can't be chosen)\n",
               [[panel.URL lastPathComponent] UTF8String], [[format titleOfSelectedItem] UTF8String]);
    }
    return 0;
}
