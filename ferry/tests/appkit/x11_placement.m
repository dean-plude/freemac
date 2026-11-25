/* SPDX-License-Identifier: GPL-3.0-or-later
 * Where windows go on an X display (freemac 1.229, Ferry 0.53.0): run on
 * the tests' own Xvfb, with no window manager. A window put on screen goes
 * where its frame says, a centred one to the middle of the screen, a
 * window moved after it is shown moves on screen too, and a nib's window
 * starts at its place on the screen it was designed on, kept from the
 * edges its xib fixes. run.sh takes a picture of the screen once the
 * windows are up and writes the colours at a few points to a file, which
 * this program waits for and prints. */
#import <Cocoa/Cocoa.h>

@interface PlaceOwner : NSObject
@property (strong) IBOutlet NSWindow *window;
@end
@implementation PlaceOwner
@end

@interface Fill : NSView
@property (strong) NSColor *color;
@end
@implementation Fill
- (void)drawRect:(NSRect)r
{
    [self.color set];
    NSRectFill([self bounds]);
}
@end

static NSWindow *window(NSRect r, NSColor *c)
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:r styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:YES];
    [w setReleasedWhenClosed:NO];
    Fill *f = [[Fill alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
    f.color = c;
    [w setContentView:f];
    return w;
}

static void spin(double seconds)
{
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                                           inMode:NSDefaultRunLoopMode dequeue:YES];
        if (e)
            [NSApp sendEvent:e];
    }
}

static void print_frame(const char *what, NSWindow *w)
{
    NSRect f = [w frame];
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, f.origin.x, f.origin.y, f.size.width, f.size.height);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect screen = [[NSScreen mainScreen] frame];
        printf("screen: %.0fx%.0f\n", screen.size.width, screen.size.height);

        NSWindow *red = window(NSMakeRect(100, 300, 200, 100), [NSColor redColor]);
        [red orderFront:nil];
        NSWindow *blue = window(NSMakeRect(0, 0, 160, 80), [NSColor blueColor]);
        [blue center];
        [blue orderFront:nil];
        NSWindow *green = window(NSMakeRect(0, 0, 120, 60), [NSColor greenColor]);
        [green orderFront:nil];
        spin(0.5);
        [green setFrameOrigin:NSMakePoint(900, 100)];

        NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:[NSString
            stringWithFormat:@"%s/Placement.nib", getenv("FERRY_TEST_DATA")]]];
        PlaceOwner *owner = [PlaceOwner new];
        [nib instantiateWithOwner:owner topLevelObjects:NULL];
        NSWindow *fixed = owner.window;
        Fill *f = [[Fill alloc] initWithFrame:[[fixed contentView] frame]];
        f.color = [NSColor yellowColor];
        [fixed setContentView:f];
        [fixed orderFront:nil];
        spin(1.0);

        print_frame("red", red);
        print_frame("blue, centred", blue);
        print_frame("green, moved", green);
        print_frame("from the nib, fixed to the right and top", fixed);
        printf("shown\n");
        fflush(stdout);

        NSString *path = [NSString stringWithFormat:@"%s/pixels.txt", getenv("FERRY_TEST_DATA")];
        NSString *pixels = nil;
        for (int i = 0; i < 400 && !pixels; i++) {
            spin(0.05);
            pixels = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        }
        printf("%s", pixels ? [pixels UTF8String] : "no picture of the screen\n");
    }
    return 0;
}
