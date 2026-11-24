// SPDX-License-Identifier: GPL-3.0-or-later
// Menu bar items (NSStatusBar): two items, one with a menu and one that is
// a button, read and clicked over D-Bus by statusbar.sh, as the desktop's
// menu bar would.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface Helper : NSObject <NSMenuDelegate, NSApplicationDelegate>
@property (strong) NSStatusItem *weather, *timer;
@property (strong) NSMenuItem *notify;
@end

@implementation Helper
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    printf("thickness %g, vertical %d\n", [bar thickness], [bar isVertical]);

    self.weather = [bar statusItemWithLength:NSVariableStatusItemLength];
    self.weather.button.title = @"21°";
    self.weather.button.toolTip = @"Weather";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.delegate = self;
    [menu addItemWithTitle:@"Open_Forecast" action:@selector(open:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    self.notify = [menu addItemWithTitle:@"Notify Me" action:@selector(toggle:) keyEquivalent:@""];
    self.notify.state = NSControlStateValueOn;
    [menu addItemWithTitle:@"Not Now" action:@selector(nothing:) keyEquivalent:@""];
    NSMenu *units = [[NSMenu alloc] initWithTitle:@"Units"];
    [units addItemWithTitle:@"Celsius" action:@selector(open:) keyEquivalent:@""].state = NSControlStateValueOn;
    [units addItemWithTitle:@"Fahrenheit" action:@selector(open:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Units" action:NULL keyEquivalent:@""].submenu = units;
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    for (NSMenuItem *mi in menu.itemArray)
        if (mi.action != @selector(terminate:))
            mi.target = self;
    for (NSMenuItem *mi in units.itemArray)
        mi.target = self;
    self.weather.menu = menu;

    self.timer = [bar statusItemWithLength:NSSquareStatusItemLength];
    NSImage *dot = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [[NSColor blackColor] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 2, 2)] fill];
        return YES;
    }];
    dot.template = YES;
    self.timer.button.image = dot;
    self.timer.button.target = self;
    self.timer.button.action = @selector(clicked:);
    printf("items made, menu %s, timer length %g\n", self.weather.menu ? "yes" : "no", self.timer.length);
    fflush(stdout);
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return item.action != @selector(nothing:); }
- (void)menuNeedsUpdate:(NSMenu *)menu { printf("menu needs update\n"); fflush(stdout); }
- (void)open:(id)sender { printf("open: %s\n", [[sender title] UTF8String]); fflush(stdout); }
- (void)nothing:(id)sender { printf("nothing: should not be sent\n"); }
- (void)toggle:(NSMenuItem *)sender
{
    sender.state = sender.state == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
    printf("toggle: now %ld\n", (long)sender.state);
    fflush(stdout);
}
- (void)clicked:(id)sender
{
    printf("clicked: %s\n", sender == self.timer.button ? "the timer's button" : "something else");
    self.timer.visible = NO;
    fflush(stdout);
}
- (void)applicationWillTerminate:(NSNotification *)n
{
    [[NSStatusBar systemStatusBar] removeStatusItem:self.weather];
    printf("quitting\n");
    fflush(stdout);
}
@end

int main(void)
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        Helper *helper = [Helper new];
        app.delegate = helper;
        [app run];
    }
    return 0;
}
