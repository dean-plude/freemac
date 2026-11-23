/* SPDX-License-Identifier: GPL-3.0-or-later
 * Window and view controllers (M7): a window controller that loads its
 * window from a nib when first asked for it, a view controller that loads
 * its view from the nib named after its class, the outlets and actions
 * those nibs connect, where each controller sits in the responder chain,
 * and windows made around a view controller. Runs from a copy of
 * NibApp.app, whose nibs come from make_nibs.py, with no display. */
#import <Cocoa/Cocoa.h>

@interface MyWindowController : NSWindowController
@property (strong) IBOutlet NSTextField *status;
@property int presses;
@end
@implementation MyWindowController
- (void)windowWillLoad { printf("windowWillLoad (loaded: %s)\n", [self isWindowLoaded] ? "yes" : "no"); }
- (void)windowDidLoad
{
    printf("windowDidLoad: \"%s\", status says \"%s\"\n", [[[self window] title] UTF8String],
           [[self.status stringValue] UTF8String]);
}
- (IBAction)press:(id)sender
{
    self.presses++;
    [self.status setStringValue:[NSString stringWithFormat:@"Pressed %d", self.presses]];
}
@end

@interface ListViewController : NSViewController
@property (strong) IBOutlet NSTextField *label;
@property BOOL didLoad;
@end
@implementation ListViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.didLoad = YES;
    printf("viewDidLoad: label says \"%s\"\n", [[self.label stringValue] UTF8String]);
}
@end

/* No nib of its own: it makes its view in code. */
@interface CodeViewController : NSViewController
@end
@implementation CodeViewController
- (void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 180)];
}
@end

static NSButton *find_button(NSView *v)
{
    if ([v isKindOfClass:[NSButton class]])
        return (NSButton *)v;
    for (NSView *s in [v subviews]) {
        NSButton *b = find_button(s);
        if (b)
            return b;
    }
    return nil;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* The window controller and its nib */
        MyWindowController *wc = [[MyWindowController alloc] initWithWindowNibName:@"Controlled"];
        printf("nib name %s, loaded before asking: %s\n", [[wc windowNibName] UTF8String],
               [wc isWindowLoaded] ? "yes" : "no");
        NSWindow *w = [wc window];
        printf("loaded after asking: %s; the window's controller is it: %s\n", [wc isWindowLoaded] ? "yes" : "no",
               [w windowController] == wc ? "yes" : "no");
        printf("window nextResponder is the controller: %s\n", [w nextResponder] == wc ? "yes" : "no");
        [find_button([w contentView]) performClick:nil];
        [find_button([w contentView]) performClick:nil];
        printf("after two clicks: %s\n", [[wc.status stringValue] UTF8String]);
        [wc showWindow:nil];
        printf("showWindow: visible %s\n", [w isVisible] ? "yes" : "no");
        /* An action nobody in the view sends reaches the controller through the chain. */
        BOOL sent = [NSApp sendAction:@selector(press:) to:nil from:[w contentView]];
        printf("sendAction to nil from the window's view: %s, %s\n", sent ? "sent" : "not sent",
               [[wc.status stringValue] UTF8String]);
        [wc close];
        printf("after close: visible %s\n", [w isVisible] ? "yes" : "no");

        /* The view controller: its nib is named after its class */
        ListViewController *vc = [[ListViewController alloc] init];
        printf("nibName %s, view loaded: %s\n", [[vc nibName] UTF8String], [vc isViewLoaded] ? "yes" : "no");
        NSView *v = [vc view];
        printf("view %.0fx%.0f, loaded: %s, viewDidLoad ran: %s\n", v.frame.size.width, v.frame.size.height,
               [vc isViewLoaded] ? "yes" : "no", vc.didLoad ? "yes" : "no");

        /* In the responder chain: view, then its controller, then the superview */
        NSView *holder = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        [holder addSubview:v];
        printf("view -> controller: %s; controller -> superview: %s\n", [v nextResponder] == vc ? "yes" : "no",
               [vc nextResponder] == holder ? "yes" : "no");
        printf("label -> view: %s\n", [vc.label nextResponder] == v ? "yes" : "no");

        /* A window around a view controller */
        CodeViewController *cvc = [[CodeViewController alloc] init];
        cvc.title = @"Made in code";
        NSWindow *w2 = [NSWindow windowWithContentViewController:cvc];
        NSRect content = [w2 contentRectForFrameRect:[w2 frame]];
        printf("window for a view controller: \"%s\", content %.0fx%.0f, contentViewController is it: %s\n",
               [[w2 title] UTF8String], content.size.width, content.size.height,
               [w2 contentViewController] == cvc ? "yes" : "no");
        printf("its content view is the controller's view: %s\n", [w2 contentView] == [cvc view] ? "yes" : "no");

        /* A window controller holding a view controller */
        NSWindowController *wc2 = [[NSWindowController alloc] initWithWindow:
            [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled
                                          backing:NSBackingStoreBuffered defer:NO]];
        ListViewController *vc2 = [[ListViewController alloc] init];
        wc2.contentViewController = vc2;
        printf("window controller's contentViewController: %s, window shows its view: %s\n",
               wc2.contentViewController == vc2 ? "yes" : "no",
               [[wc2 window] contentView] == [vc2 view] ? "yes" : "no");

        /* Children */
        [vc addChildViewController:vc2];
        printf("children %lu, parent is vc: %s\n", (unsigned long)[[vc childViewControllers] count],
               [vc2 parentViewController] == vc ? "yes" : "no");
        [vc2 removeFromParentViewController];
        printf("after removing: children %lu\n", (unsigned long)[[vc childViewControllers] count]);
    }
    return 0;
}
