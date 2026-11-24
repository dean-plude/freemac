// SPDX-License-Identifier: GPL-3.0-or-later
// The app's tile in the Dock: the badge, attention requests and the Dock
// menu, which reach the dock as com.canonical.Unity.LauncherEntry Update
// signals (and a dbusmenu menu) as freemac's Dock reads them. Run by
// notifications.sh, whose stand-in Dock (fake_notify.py --dock) restarts
// once, so the app sends its tile again, and then opens the Dock menu and
// clicks New Window.
#import <Cocoa/Cocoa.h>

static BOOL clicked, drawn;

static BOOL wait_until(double seconds, BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

static void pause_a_moment(void)
{
    wait_until(0.2, ^{ return NO; });
}

@interface Delegate : NSObject <NSApplicationDelegate>
@end

@implementation Delegate
- (NSMenu *)applicationDockMenu:(NSApplication *)sender
{
    printf("asked for the Dock menu\n");
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@""].target = self;
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *recent = [menu addItemWithTitle:@"Recent" action:NULL keyEquivalent:@""];
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@"Recent"];
    [sub addItemWithTitle:@"notes.txt" action:@selector(newWindow:) keyEquivalent:@""].target = self;
    recent.submenu = sub;
    return menu;
}

- (void)newWindow:(NSMenuItem *)item
{
    printf("Dock menu: %s chosen\n", item.title.UTF8String);
    clicked = YES;
}
@end

@interface TileView : NSView
@end

@implementation TileView
- (void)drawRect:(NSRect)rect
{
    [[NSColor systemBlueColor] setFill];
    NSRectFill(self.bounds);
    printf("tile view drawn at %.0fx%.0f\n", self.bounds.size.width, self.bounds.size.height);
    drawn = YES;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Delegate *delegate = [[Delegate alloc] init];
        NSApp.delegate = delegate;
        [NSApp finishLaunching];
        [NSApp deactivate];
        NSDockTile *tile = NSApp.dockTile;
        printf("tile: same each time %s, owner is NSApp %s, size %.0fx%.0f, shows the badge %s, label %s\n",
               tile == NSApp.dockTile ? "yes" : "no", tile.owner == NSApp ? "yes" : "no", tile.size.width,
               tile.size.height, tile.showsApplicationBadge ? "yes" : "no", tile.badgeLabel ? "some" : "none");
        // The Dock restarts, asks again, opens the menu and clicks New Window.
        if (!wait_until(10, ^{ return clicked; }))
            printf("the Dock menu wasn't clicked\n");
        pause_a_moment();

        tile.badgeLabel = @"7";
        pause_a_moment();
        tile.badgeLabel = @"7";         // the same again: nothing sent
        tile.badgeLabel = @"12";
        pause_a_moment();
        tile.showsApplicationBadge = NO;
        pause_a_moment();
        tile.showsApplicationBadge = YES;
        pause_a_moment();
        tile.badgeLabel = @"New";       // not a number: the dock can't show it
        printf("label kept: %s\n", tile.badgeLabel.UTF8String);
        pause_a_moment();
        tile.badgeLabel = nil;
        pause_a_moment();

        NSInteger critical = [NSApp requestUserAttention:NSCriticalRequest];
        printf("critical request: %s\n", critical ? "an id" : "none");
        pause_a_moment();
        [NSApp cancelUserAttentionRequest:critical];
        pause_a_moment();
        NSInteger info = [NSApp requestUserAttention:NSInformationalRequest];
        printf("informational request: %s\n", info ? "an id" : "none");
        pause_a_moment();
        printf("(waiting a second)\n");
        wait_until(1.3, ^{ return NO; });
        critical = [NSApp requestUserAttention:NSCriticalRequest];
        pause_a_moment();
        printf("(the app becomes active)\n");
        [NSApp activateIgnoringOtherApps:YES];
        pause_a_moment();
        printf("request while active: %s\n", [NSApp requestUserAttention:NSCriticalRequest] ? "an id" : "none");

        NSImage *icon = [[NSImage alloc] initWithSize:NSMakeSize(64, 64)];
        NSApp.applicationIconImage = icon;
        printf("application icon kept: %s\n", NSApp.applicationIconImage == icon ? "yes" : "no");
        TileView *view = [[TileView alloc] initWithFrame:NSZeroRect];
        tile.contentView = view;
        printf("content view kept: %s\n", tile.contentView == view ? "yes" : "no");
        [tile display];
        printf("drawn by display: %s\n", drawn ? "yes" : "no");
        pause_a_moment();
        printf("done\n");
    }
    return 0;
}
