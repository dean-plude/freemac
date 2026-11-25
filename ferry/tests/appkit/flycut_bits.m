/* Ferry test: the AppKit and Carbon calls Flycut makes as it starts: the
 * Process Manager for the program itself (PSN from Cocoa through Core
 * Services, as on a Mac), remote notification registration (which fails,
 * with no push service, next time round the run loop), NSCell's
 * performClick:, a menu item's view, a menu's change messages, the
 * application's hidden state and a search field's button cells. */
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include <stdio.h>
#include <unistd.h>

@interface Delegate : NSObject <NSApplicationDelegate>
@end
@implementation Delegate
- (void)application:(NSApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    printf("remote notifications failed: %s %ld\n", [error.domain UTF8String], (long)error.code);
}
@end

@interface Target : NSObject
@property int clicks;
@property (weak) id lastSender;
@end
@implementation Target
- (void)clicked:(id)sender
{
    self.clicks++;
    self.lastSender = sender;
}
@end

static void processes(void)
{
    ProcessSerialNumber psn = {0, 0}, me = {0, kCurrentProcess}, next = {0, kNoProcess};
    printf("GetCurrentProcess: %d, a number %d\n", GetCurrentProcess(&psn), psn.lowLongOfPSN != 0);
    pid_t pid = 0;
    printf("its pid is ours: %d %d\n", (int)GetProcessPID(&psn, &pid), pid == getpid());
    Boolean same = false;
    SameProcess(&psn, &me, &same);
    printf("the same as kCurrentProcess: %d\n", same);
    ProcessSerialNumber byPid;
    printf("GetProcessForPID: %d\n", (int)GetProcessForPID(getpid(), &byPid));
    printf("GetNextProcess: %d", GetNextProcess(&next));
    printf(", then %d\n", GetNextProcess(&next));
    CFStringRef name = NULL;
    printf("CopyProcessName: %d %s\n", (int)CopyProcessName(&me, &name),
           name ? [(__bridge NSString *)name UTF8String] : "(null)");
    if (name)
        CFRelease(name);
    ProcessInfoRec info;
    Str255 pname;
    memset(&info, 0, sizeof info);
    info.processInfoLength = sizeof info;
    info.processName = pname;
    printf("GetProcessInformation: %d, type %s, name length %d\n", GetProcessInformation(&me, &info),
           info.processType == 'APPL' ? "APPL" : "?", pname[0]);
    CFDictionaryRef d = ProcessInformationCopyDictionary(&me, kProcessDictionaryIncludeAllInformationMask);
    printf("its dictionary: pid ours %d\n", [((__bridge NSDictionary *)d)[@"pid"] intValue] == getpid());
    if (d)
        CFRelease(d);
    ProcessSerialNumber other = {0, 99999};
    printf("another process: %d\n", (int)GetProcessPID(&other, &pid));
    printf("SetFrontProcess: %d\n", SetFrontProcess(&me));
}

static void cells(void)
{
    Target *t = [Target new];
    NSButtonCell *cell = [[NSButtonCell alloc] initTextCell:@"Copy"];
    cell.target = t;
    cell.action = @selector(clicked:);
    [cell setButtonType:NSButtonTypeSwitch];
    [cell performClick:nil];
    printf("performClick: %d click, state %ld, sender is the cell %d\n", t.clicks, (long)cell.state,
           t.lastSender == cell);
    cell.enabled = NO;
    [cell performClick:nil];
    printf("disabled: still %d\n", t.clicks);
    cell.showsFirstResponder = YES;
    printf("showsFirstResponder: %d\n", cell.showsFirstResponder);
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)];
    button.target = t;
    button.action = @selector(clicked:);
    button.cell = [[NSButtonCell alloc] initTextCell:@"Paste"]; /* as a nib gives it one */
    [button.cell performClick:nil];
    printf("a button's cell: %d clicks, sender is the button %d\n", t.clicks, t.lastSender == button);
}

static void menus(void)
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Flycut"];
    printf("menu change messages: %d", menu.menuChangedMessagesEnabled);
    menu.menuChangedMessagesEnabled = NO;
    printf(" -> %d\n", menu.menuChangedMessagesEnabled);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Search" action:NULL keyEquivalent:@""];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
    item.view = view;
    [menu addItem:item];
    printf("item view: %d, width %.0f\n", item.view == view, item.view.frame.size.width);
    item.view = nil;
    printf("view removed: %d\n", item.view == nil);
}

static void search(void)
{
    NSSearchField *field = [[NSSearchField alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
    NSSearchFieldCell *cell = field.cell;
    printf("search button cell: %d, cancel button cell: %d\n", cell.searchButtonCell != nil,
           cell.cancelButtonCell != nil);
    field.stringValue = @"clip";
    [cell.cancelButtonCell performClick:nil];
    printf("cancel button clears: \"%s\"\n", [field.stringValue UTF8String]);
    [cell resetSearchButtonCell];
    printf("after a reset: %d, has an action %d\n", cell.searchButtonCell != nil,
           cell.searchButtonCell.action != NULL);
}

int main(void)
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        Delegate *delegate = [Delegate new];
        app.delegate = delegate;
        printf("hidden: %d\n", app.hidden);
        processes();
        cells();
        menus();
        search();
        [app registerForRemoteNotifications];
        printf("registered: %d, types %lu (the answer comes later)\n", app.registeredForRemoteNotifications,
               (unsigned long)app.enabledRemoteNotificationTypes);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        printf("done\n");
    }
    return 0;
}
