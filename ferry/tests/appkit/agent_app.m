/* SPDX-License-Identifier: GPL-3.0-or-later
 * An agent app's shortcuts, as Spectacle and Flycut use them (freemac
 * 1.224, Ferry 0.48.0), against the stand-in Wayfire (tests/tools/
 * fake_wayfire.py). AgentApp.app says LSUIElement, so it starts as an
 * accessory app and isn't made active by starting; the frontmost
 * application is then the one whose window Wayfire has focused, which is
 * what Spectacle checks before it keeps its shortcuts. A hotkey registered
 * on the event dispatcher target reaches a handler on the application
 * target. A control class of the app's own whose +cellClass is a cell class
 * of the app's own gets that cell from -initWithFrame:, as ShortcutRecorder's
 * recorder needs, and +setCellClass: chooses one for a class. NSSet's
 * -initWithObjects:, -initWithArray: and -initWithSet:. */
#import <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>
#include <unistd.h>
#include "wayfire_fake.h"

static volatile int presses;

static OSStatus handler(EventHandlerCallRef call, EventRef event, void *data)
{
    EventHotKeyID hk = {0, 0};
    GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof hk, NULL, &hk);
    printf("  application target: %s, id %u\n", GetEventKind(event) == kEventHotKeyPressed ? "pressed" : "released",
           hk.id);
    if (GetEventKind(event) == kEventHotKeyReleased)
        presses++;
    return noErr;
}

static void show_front(const char *when)
{
    NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
    pid_t pid = front ? front.processIdentifier : 0;
    char p[32];
    snprintf(p, sizeof p, "%d", (int)pid);
    printf("%s: frontmost %s, name %s, pid %s, active %d, is this app %d\n", when,
           front.bundleIdentifier ? [front.bundleIdentifier UTF8String] : "(none)",
           front.localizedName ? [front.localizedName UTF8String] : "(none)", pid == getpid() ? "this one's" : p,
           front ? (int)front.isActive : 0, [front isEqual:[NSRunningApplication currentApplication]]);
}

@interface RecorderCell : NSActionCell
@property NSInteger code;
@end
@implementation RecorderCell
- (instancetype)init
{
    if ((self = [super init]))
        _code = 47;
    return self;
}
@end

@interface Recorder : NSControl
@end
@implementation Recorder
+ (Class)cellClass { return [RecorderCell class]; }
- (NSInteger)code { return [(RecorderCell *)[self cell] code]; }
@end

@interface Chooser : NSControl
@end
@implementation Chooser
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        printf("policy accessory %d\n", [NSApp activationPolicy] == NSApplicationActivationPolicyAccessory);
        [NSApp finishLaunching];
        printf("active after launching %d\n", [NSApp isActive]);
        printf("this app active %d\n", [[NSRunningApplication currentApplication] isActive]);
        show_front("at launch");

        /* A window of this process's own in front, then the other app's
         * again */
        fake_call(@"fake/add-view", @{@"id" : @30, @"app-id" : @"org.freemac.ferry.agentapp", @"title" : @"Prefs",
                                      @"pid" : @(getpid()), @"output" : @1,
                                      @"geometry" : @{@"x" : @0, @"y" : @0, @"width" : @300, @"height" : @200}});
        fake_call(@"window-rules/focus-view", @{@"id" : @30});
        show_front("own window focused");
        fake_call(@"window-rules/focus-view", @{@"id" : @12});
        show_front("browser focused");

        EventTypeSpec types[] = {{kEventClassKeyboard, kEventHotKeyPressed}, {kEventClassKeyboard, kEventHotKeyReleased}};
        printf("install %d\n", (int)InstallApplicationEventHandler(NewEventHandlerUPP(handler), 2, types, NULL, NULL));
        EventHotKeyRef ref = NULL;
        OSStatus r = RegisterEventHotKey(kVK_LeftArrow, cmdKey | optionKey, (EventHotKeyID){'Spct', 7},
                                         GetEventDispatcherTarget(), 0, &ref);
        printf("register on the dispatcher target %d\n", (int)r);
        id sent = fake_call(@"fake/press", @{@"key" : @105, @"modifiers" : @[ @"command", @"option" ]});
        printf("press: sent %d\n", [sent[@"sent"] boolValue]);
        wait_for(&presses, 0);
        printf("presses %d\n", presses);
        UnregisterEventHotKey(ref);

        Recorder *rec = [[Recorder alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        printf("recorder cell %s, its control %d, code %ld\n", [NSStringFromClass([[rec cell] class]) UTF8String],
               [[rec cell] controlView] == rec, (long)[rec code]);
        printf("chooser cell class before %s\n", [NSStringFromClass([Chooser cellClass]) UTF8String]);
        [Chooser setCellClass:[RecorderCell class]];
        Chooser *ch = [[Chooser alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        printf("chooser cell class %s, cell %s\n", [NSStringFromClass([Chooser cellClass]) UTF8String],
               [NSStringFromClass([[ch cell] class]) UTF8String]);
        printf("control cell class %s\n", [NSStringFromClass([NSControl cellClass]) UTF8String]);
        NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [button setTitle:@"OK"];
        printf("button title %s\n", [[button title] UTF8String]);

        NSSet *a = [[NSSet alloc] initWithObjects:@"x", @"y", @"x", nil];
        NSSet *b = [[NSSet alloc] initWithArray:@[ @"y", @"z" ]];
        NSMutableSet *c = [[NSMutableSet alloc] initWithSet:a];
        [c unionSet:b];
        printf("sets %lu %lu %lu %d\n", (unsigned long)[a count], (unsigned long)[b count], (unsigned long)[c count],
               [c containsObject:@"z"]);

        for (NSString *line in fake_call(@"fake/log", nil)[@"log"])
            printf("wayfire: %s\n", [line UTF8String]);
    }
    return 0;
}
