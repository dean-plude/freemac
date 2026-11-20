/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit on a real display: run under a Wayland compositor (the test runs
 * one, headless). A window opens, is drawn, resized and closed, timers fire
 * while GTK is waited on, and closing the last window ends the program. */
#import <Cocoa/Cocoa.h>

@interface Canvas : NSView
@property (retain) NSMutableSet *sizes;
@end
@implementation Canvas
- (void)drawRect:(NSRect)dirty
{
    [[NSColor systemBlueColor] set];
    NSRectFill(NSInsetRect([self bounds], 10, 10));
    [@"Hello from Ferry" drawAtPoint:NSMakePoint(20, 20)
                      withAttributes:@{NSFontAttributeName : [NSFont boldSystemFontOfSize:18],
                                       NSForegroundColorAttributeName : [NSColor whiteColor]}];
    NSString *size = NSStringFromSize([self bounds].size);
    if (![_sizes containsObject:size]) {
        [_sizes addObject:size];
        printf("drawn at %s, to the screen: %d\n", [size UTF8String], [NSGraphicsContext currentContextDrawingToScreen]);
        [[NSApp delegate] performSelector:@selector(drawnAt:) withObject:size afterDelay:0.3];
    }
}
@end

@interface Delegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (retain) NSWindow *window;
@property int ticks;
@end
@implementation Delegate
- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSRect screen = [[NSScreen mainScreen] frame];
    printf("screen has a size: %d, scale %g\n", screen.size.width > 0 && screen.size.height > 0,
           [[NSScreen mainScreen] backingScaleFactor]);
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 200)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered defer:NO];
    [_window setReleasedWhenClosed:NO];
    [_window setTitle:@"Ferry window test"];
    [_window setDelegate:self];
    Canvas *canvas = [[Canvas alloc] initWithFrame:NSZeroRect];
    canvas.sizes = [NSMutableSet set];
    [_window setContentView:canvas];
    [_window center];
    [_window makeKeyAndOrderFront:nil];
    printf("visible %d\n", [_window isVisible]);
    [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [self performSelector:@selector(giveUp) withObject:nil afterDelay:20];
}
- (void)tick:(NSTimer *)t { _ticks++; }
/* Once drawn, the window is made larger; once drawn at that size, closed. */
- (void)drawnAt:(NSString *)size
{
    if ([size isEqualToString:@"{320, 200}"])
        [_window setContentSize:NSMakeSize(400, 260)];
    else
        [_window performClose:nil];
}
- (void)giveUp
{
    printf("timed out\n");
    exit(1);
}
- (void)windowDidResize:(NSNotification *)n
{
    printf("resized to %s\n", [NSStringFromSize([[n object] frame].size) UTF8String]);
}
- (BOOL)windowShouldClose:(NSWindow *)w
{
    printf("should close\n");
    return YES;
}
- (void)windowWillClose:(NSNotification *)n
{
    printf("will close; timers fired meanwhile: %d\n", _ticks >= 3);
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)n { printf("terminating\n"); }
@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setDelegate:[[Delegate alloc] init]];
    }
    [NSApp run];
    printf("run returned\n");
    return 1;
}
