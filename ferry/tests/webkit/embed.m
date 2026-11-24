/* SPDX-License-Identifier: GPL-3.0-or-later
 * The GTK web view inside AppKit's window, with this system's WebKitGTK:
 * placed over the NSView and sized to it, clipped to the part of it that
 * its superviews show, following it when it moves, is resized or hidden,
 * taking the keyboard when it becomes the first responder, and kept (page
 * and all) when its window is closed and opened again or it moves to
 * another window. Placements are GTK's {x, y, width, height} of the shown
 * part, from the window's top left, then the page's offset in it. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/* Ferry's own, for tests: where WKEmbed put the GTK view, and whether it has the keyboard */
@interface WKWebView (FerryTesting)
- (NSArray *)_ferryPlacement;
- (BOOL)_ferryHasFocus;
@end

/* a turn of the event loop, as [NSApp run] takes it */
static void turn(void)
{
    NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                       inMode:NSDefaultRunLoopMode
                                      dequeue:YES];
    if (e)
        [NSApp sendEvent:e];
}

static void pump(void)
{
    for (int i = 0; i < 10; i++)
        turn();
}

static BOOL spin_until(BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done() && [end timeIntervalSinceNow] > 0)
        turn();
    return done();
}

static WKWebView *web;

static NSString *placement(void)
{
    NSArray *p = [web _ferryPlacement];
    return [p count] ? [p componentsJoinedByString:@", "] : @"not shown";
}

static void show(const char *what)
{
    pump();
    printf("%s: %s\n", what, [placement() UTF8String]);
}

static NSString *evaluate(NSString *script)
{
    __block NSString *out = nil;
    [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        out = error ? @"error" : result ? [result description] : @"nil";
    }];
    if (!spin_until(^{ return (BOOL)(out != nil); }))
        return @"(timed out)";
    return out;
}

/* the page's own idea of its size, once GTK has given it */
static void page_size(const char *what, NSString *want)
{
    spin_until(^{ return [evaluate(@"window.innerWidth + 'x' + window.innerHeight") isEqualToString:want]; });
    printf("%s: the page is %s\n", what, [evaluate(@"window.innerWidth + 'x' + window.innerHeight") UTF8String]);
}

@interface Plain : NSView
@end
@implementation Plain
- (BOOL)acceptsFirstResponder { return YES; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                                 NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.releasedWhenClosed = NO;
        NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(20, 20, 200, 150)];
        Plain *other = [[Plain alloc] initWithFrame:NSMakeRect(250, 20, 100, 100)];
        [window.contentView addSubview:box];
        [window.contentView addSubview:other];
        web = [[WKWebView alloc] initWithFrame:box.bounds];
        [box addSubview:web];
        show("before the window is shown");
        [window makeKeyAndOrderFront:nil];
        [web loadHTMLString:@"<title>Embedded</title><body style='margin:0'><input id=i></body>" baseURL:nil];
        spin_until(^{ return [web.title isEqualToString:@"Embedded"]; });
        show("shown, filling its box");
        page_size("shown", @"200x150");

        [web setFrame:NSMakeRect(-50, -30, 300, 200)];
        show("larger than its box, which clips it");
        page_size("clipped", @"300x200");

        [web setFrame:NSMakeRect(10, 10, 100, 80)];
        show("moved and made smaller");
        page_size("smaller", @"100x80");

        web.hidden = YES;
        show("hidden");
        web.hidden = NO;
        show("shown again");
        box.hidden = YES;
        show("its box hidden");
        box.hidden = NO;
        show("its box shown again");

        [web setFrame:box.bounds];
        web.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        box.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [window setContentSize:NSMakeSize(500, 400)];
        show("its window made larger");
        page_size("larger window", @"300x250");

        printf("first responder before: the web view %d\n", window.firstResponder == web);
        [window makeFirstResponder:web];
        pump();
        printf("made the first responder: %d, the GTK view has the keyboard %d\n", window.firstResponder == web,
               web._ferryHasFocus);
        [window makeFirstResponder:other];
        pump();
        printf("another view made the first responder: the GTK view has the keyboard %d\n",
               web._ferryHasFocus);

        [window orderOut:nil];
        show("its window ordered out (the view stays in it)");
        [window makeKeyAndOrderFront:nil];
        show("its window ordered in");
        printf("the page is still there: %s\n", [evaluate(@"document.title + ', ' + !!document.getElementById('i')") UTF8String]);

        /* closed with the web view in it: GTK's window goes, the web view stays */
        [window close];
        show("its window closed");
        printf("the page is still there: %s\n", [evaluate(@"document.title") UTF8String]);
        NSWindow *second = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        second.releasedWhenClosed = NO;
        [second makeKeyAndOrderFront:nil];
        [web removeFromSuperview];
        web.autoresizingMask = NSViewNotSizable;
        [web setFrame:NSMakeRect(0, 0, 300, 200)];
        [second.contentView addSubview:web];
        show("put in a new window");
        printf("still the same page: %s\n", [evaluate(@"document.title + ', ' + !!document.getElementById('i')") UTF8String]);
        page_size("in the new window", @"300x200");

        NSWindow *third = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 200)
                                                      styleMask:NSWindowStyleMaskTitled
                                                        backing:NSBackingStoreBuffered
                                                          defer:NO];
        third.releasedWhenClosed = NO;
        [third makeKeyAndOrderFront:nil];
        [web removeFromSuperview];
        show("taken out of its window");
        [web setFrame:NSMakeRect(50, 50, 100, 100)];
        [third.contentView addSubview:web];
        show("moved to a third window");
        [web removeFromSuperview];
        web = nil;
        pump();
        [second close];
        [third close];
        printf("done\n");
    }
    return 0;
}
