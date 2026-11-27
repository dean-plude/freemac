/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Picture in picture (freemac 1.262, Ferry 0.85.0): see PIP/PIP.h. The
 * view controller's view moves into a small window that floats above the
 * others in the screen's lower right corner, keeping the shape the app
 * asks for. Its close button asks the delegate, as the app expects, and
 * the app takes the view back. Clicking play or pause in the window: space
 * and the window's own menu are left to the app. Built without ARC. */
#import "AInternal.h"
#import <PIP/PIP.h>

@implementation PIPViewController {
    NSWindow *_floating;
    NSViewController *_shown;
}

@synthesize delegate = _delegate, name = _name, aspectRatio = _aspectRatio, minSize = _minSize,
            maxSize = _maxSize, playing = _playing, userCanResize = _userCanResize,
            replacementRect = _replacementRect, replacementWindow = _replacementWindow,
            replacementView = _replacementView;

- (instancetype)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _aspectRatio = NSMakeSize(16, 9);
        _minSize = NSMakeSize(160, 90);
        _userCanResize = YES;
    }
    return self;
}

- (void)loadView
{
    [self setView:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 270)] autorelease]];
}

- (void)dealloc
{
    [_floating setDelegate:nil];
    [_floating release];
    [_shown release];
    [_name release];
    [super dealloc];
}

- (NSSize)fittedSize
{
    NSSize r = _aspectRatio;
    if (r.width <= 0 || r.height <= 0)
        r = NSMakeSize(16, 9);
    CGFloat w = 400, h = w * r.height / r.width;
    if (h > 300) {
        h = 300;
        w = h * r.width / r.height;
    }
    return NSMakeSize(round(w), round(h));
}

- (void)setAspectRatio:(NSSize)ratio
{
    _aspectRatio = ratio;
    if (_floating && ratio.width > 0 && ratio.height > 0) {
        [_floating setContentAspectRatio:ratio];
        NSRect f = [_floating frame];
        NSSize s = [self fittedSize];
        [_floating setFrame:[_floating frameRectForContentRect:NSMakeRect(f.origin.x, f.origin.y, s.width, s.height)]
                    display:YES];
    }
}

- (void)presentViewControllerAsPictureInPicture:(NSViewController *)viewController
{
    if (!viewController)
        return;
    if (_shown != viewController) {
        id wasShown = _shown;
        _shown = [viewController retain];
        [wasShown release];
    }
    NSSize s = [self fittedSize];
    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    NSRect content = NSMakeRect(NSMaxX(screen) - s.width - 24, NSMinY(screen) + 24, s.width, s.height);
    if (!_floating) {
        NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                  (_userCanResize ? NSWindowStyleMaskResizable : 0);
        _floating = [[NSWindow alloc] initWithContentRect:content styleMask:style
                                                  backing:NSBackingStoreBuffered defer:NO];
        [_floating setReleasedWhenClosed:NO];
        [_floating setDelegate:self];
        [_floating setLevel:NSFloatingWindowLevel];
    }
    [_floating setTitle:_name ? _name : @"Picture in Picture"];
    if (_minSize.width > 0)
        [_floating setContentMinSize:_minSize];
    if (_maxSize.width > 0)
        [_floating setContentMaxSize:_maxSize];
    [_floating setContentAspectRatio:_aspectRatio.width > 0 ? _aspectRatio : NSMakeSize(16, 9)];
    NSView *box = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, s.width, s.height)] autorelease];
    [_floating setContentView:box];
    NSView *v = [viewController view];
    [v removeFromSuperview];
    [v setFrame:[box bounds]];
    [v setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [box addSubview:v];
    [_floating setFrame:[_floating frameRectForContentRect:content] display:YES];
    [_floating orderFront:nil];
}

/* The view goes back to the app, which has already taken it into its own
 * window, or takes it in pipWillClose. */
- (void)dismissViewController:(NSViewController *)viewController
{
    if (viewController && viewController != _shown) {
        [super dismissViewController:viewController];
        return;
    }
    NSView *v = [_shown view];
    if ([v window] == _floating)
        [v removeFromSuperview];
    [_floating orderOut:nil];
    [_shown release];
    _shown = nil;
}

- (BOOL)windowShouldClose:(NSWindow *)window
{
    (void)window;
    id<PIPViewControllerDelegate> d = _delegate;
    if ([d respondsToSelector:@selector(pipShouldClose:)] && ![d pipShouldClose:self])
        return NO;
    [self retain];
    if ([d respondsToSelector:@selector(pipWillClose:)])
        [d pipWillClose:self];
    if (_shown)
        [self dismissViewController:_shown];
    else
        [_floating orderOut:nil];
    if ([d respondsToSelector:@selector(pipDidClose:)])
        [d pipDidClose:self];
    [self release];
    return NO;   /* hidden above, kept for the next time */
}
@end
