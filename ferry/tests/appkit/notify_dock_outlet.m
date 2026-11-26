// SPDX-License-Identifier: GPL-3.0-or-later
// A Dock menu given the way VLC gives its own (freemac 1.NEXT): a nib
// connects the application's dockMenu outlet to a menu, and the delegate
// has no applicationDockMenu:. Run by notifications.sh, whose stand-in Dock
// (fake_notify.py --dock) restarts once, then opens the Dock menu and
// clicks Play.
#import <Cocoa/Cocoa.h>

static BOOL clicked;

static BOOL wait_until(double seconds, BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

@interface Player : NSObject
@end

@implementation Player
- (void)play:(NSMenuItem *)item
{
    printf("Dock menu: %s chosen\n", item.title.UTF8String);
    clicked = YES;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Player *player = [[Player alloc] init];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
        [menu addItemWithTitle:@"Play" action:@selector(play:) keyEquivalent:@""].target = player;
        [menu addItemWithTitle:@"Stop" action:@selector(play:) keyEquivalent:@""].target = player;
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItemWithTitle:@"Mute" action:@selector(play:) keyEquivalent:@""].target = player;
        // what loading a nib does with an outlet connection
        [NSApp setValue:menu forKey:@"dockMenu"];
        printf("outlet kept: %s\n", [NSApp valueForKey:@"dockMenu"] == menu ? "yes" : "no");
        [NSApp finishLaunching];
        [NSApp deactivate];
        if (!wait_until(10, ^{ return clicked; }))
            printf("the Dock menu wasn't clicked\n");
        wait_until(0.2, ^{ return NO; });
        printf("done\n");
    }
    return 0;
}
