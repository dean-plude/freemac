/* SPDX-License-Identifier: GPL-3.0-or-later
 * Global hotkeys (freemac 1.215, Ferry 0.41.0), as Spectacle, ShiftIt and
 * Flycut register them: RegisterEventHotKey through Strata (here the
 * stand-in Wayfire, tests/tools/fake_wayfire.py), each press reaching the
 * app's Carbon event handlers, newest first, with its hot-key ID, and its
 * global key-down monitors; the errors for a combination that is taken and
 * one that isn't a hotkey; local monitors, which see the app's own events.
 * Run with "plain" against a Wayfire without Strata: the hotkey is kept but
 * never pressed, as before. */
#import <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>
#include "wayfire_fake.h"

static volatile int presses;

static void print_id(const char *who, EventRef event)
{
    EventHotKeyID hk = {0, 0};
    OSStatus r = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof hk, NULL, &hk);
    printf("  %s: %s, '%c%c%c%c' %u (%d)\n", who,
           GetEventKind(event) == kEventHotKeyPressed ? "pressed" : "released", (char)(hk.signature >> 24),
           (char)(hk.signature >> 16), (char)(hk.signature >> 8), (char)hk.signature, hk.id, (int)r);
}

static OSStatus inner(EventHandlerCallRef call, EventRef event, void *data)
{
    print_id((const char *)data, event);
    if (GetEventKind(event) == kEventHotKeyReleased)
        presses++;
    return noErr;
}

static OSStatus outer(EventHandlerCallRef call, EventRef event, void *data)
{
    print_id((const char *)data, event);
    EventHotKeyID hk;
    GetEventParameter(event, kEventParamDirectObject, typeWildCard, NULL, sizeof hk, NULL, &hk);
    if (hk.id == 2)
        return eventNotHandledErr;
    if (hk.id == 3) {
        OSStatus r = CallNextEventHandler(call, event);
        printf("  outer: next handler answered %d\n", (int)r);
        return r;
    }
    if (GetEventKind(event) == kEventHotKeyReleased)
        presses++;
    return noErr;
}

static void press(int key, NSArray *mods)
{
    int before = presses;
    id r = fake_call(@"fake/press", @{@"key" : @(key), @"modifiers" : mods});
    printf("press %d %s: sent %d\n", key, [[mods componentsJoinedByString:@"+"] UTF8String],
           [r[@"sent"] boolValue]);
    if ([r[@"sent"] boolValue])
        wait_for(&presses, before);
    else
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
}

static EventHotKeyRef reg(UInt32 code, UInt32 mods, UInt32 n, const char *what)
{
    EventHotKeyRef ref = NULL;
    OSStatus r = RegisterEventHotKey(code, mods, (EventHotKeyID){'Spct', n}, GetApplicationEventTarget(), 0, &ref);
    printf("register %s: %d, ref %s\n", what, (int)r, ref ? "yes" : "no");
    return ref;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc > 1 && !strcmp(argv[1], "plain")) {
            EventHotKeyRef ref = reg(kVK_LeftArrow, cmdKey | optionKey, 1, "command-option-left");
            printf("unregister %d\n", (int)UnregisterEventHotKey(ref));
            return 0;
        }
        EventTypeSpec types[] = {{kEventClassKeyboard, kEventHotKeyPressed}, {kEventClassKeyboard, kEventHotKeyReleased}};
        EventHandlerRef first = NULL, second = NULL;
        printf("install %d\n", (int)InstallEventHandler(GetApplicationEventTarget(), NewEventHandlerUPP(inner), 2,
                                                        types, "inner", &first));
        printf("install %d\n", (int)InstallApplicationEventHandler(NewEventHandlerUPP(outer), 2, types, "outer",
                                                                   &second));
        EventHotKeyRef left = reg(kVK_LeftArrow, cmdKey | optionKey, 1, "command-option-left");
        EventHotKeyRef paste = reg(kVK_ANSI_V, cmdKey | shiftKey, 2, "shift-command-v");
        EventHotKeyRef f5 = reg(kVK_F5, 0, 3, "f5");
        reg(kVK_LeftArrow, cmdKey | optionKey, 4, "command-option-left again");
        reg(kVK_ANSI_A, 0, 5, "a");
        reg(kVK_ANSI_A, shiftKey, 6, "shift-a");

        __block int global = 0;
        id monitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *e) {
            printf("  global monitor: key %u '%s'%s%s%s%s\n", e.keyCode,
                   [e.charactersIgnoringModifiers isEqual:@"v"] ? "v" : [e.characters length] ? "fn" : "",
                   e.modifierFlags & NSEventModifierFlagCommand ? " command" : "",
                   e.modifierFlags & NSEventModifierFlagOption ? " option" : "",
                   e.modifierFlags & NSEventModifierFlagControl ? " control" : "",
                   e.modifierFlags & NSEventModifierFlagShift ? " shift" : "");
            global++;
        }];
        printf("global monitor %s\n", monitor ? "yes" : "no");

        press(105, @[ @"command", @"option" ]);
        press(47, @[ @"command", @"shift" ]);
        press(63, @[]);
        press(30, @[]);
        printf("global monitor saw %d\n", global);

        [NSEvent removeMonitor:monitor];
        printf("unregister left %d\n", (int)UnregisterEventHotKey(left));
        press(105, @[ @"command", @"option" ]);
        printf("remove outer %d\n", (int)RemoveEventHandler(second));
        press(47, @[ @"command", @"shift" ]);
        printf("global monitor saw %d\n", global);
        UnregisterEventHotKey(paste);
        UnregisterEventHotKey(f5);
        RemoveEventHandler(first);

        /* A local monitor sees the app's own events, and can keep one from
         * going further. */
        __block int local = 0;
        id lm = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
            local++;
            return [e.characters isEqual:@"q"] ? nil : e;
        }];
        for (NSString *c in @[ @"q", @"w" ])
            [NSApp sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                             timestamp:0 windowNumber:0 context:nil characters:c
                           charactersIgnoringModifiers:c isARepeat:NO keyCode:12]];
        [NSEvent removeMonitor:lm];
        [NSApp sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                         timestamp:0 windowNumber:0 context:nil characters:@"e"
                       charactersIgnoringModifiers:@"e" isARepeat:NO keyCode:14]];
        printf("local monitor saw %d\n", local);

        for (NSString *line in fake_call(@"fake/log", nil)[@"log"])
            printf("wayfire: %s\n", [line UTF8String]);
    }
    return 0;
}
