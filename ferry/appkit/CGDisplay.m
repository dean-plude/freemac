/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Quartz Display Services (CGDirectDisplay.h), from AppKit's screens
 * (freemac 1.233, Ferry 0.57.0). */
#import "AInternal.h"

static NSArray<NSScreen *> *screens(void)
{
    NSArray *s = [NSScreen screens];
    return [s count] ? s : nil;
}
static CGDirectDisplayID number_of(NSScreen *s)
{
    return (CGDirectDisplayID)[[s deviceDescription][@"NSScreenNumber"] unsignedIntValue];
}
static NSScreen *screen_numbered(CGDirectDisplayID d)
{
    for (NSScreen *s in screens())
        if (number_of(s) == d)
            return s;
    return nil;
}

CGDirectDisplayID CGMainDisplayID(void)
{
    NSScreen *s = [screens() firstObject];
    return s ? number_of(s) : 1;
}
CGError CGGetOnlineDisplayList(uint32_t max, CGDirectDisplayID *displays, uint32_t *count)
{
    NSArray *all = screens();
    uint32_t n = 0;
    if (!all) {
        /* no display server: the one display a Mac always has */
        if (displays && max > 0)
            displays[n] = 1;
        n = 1;
    } else
        for (NSScreen *s in all) {
            if (displays && n >= max)
                break;
            if (displays)
                displays[n] = number_of(s);
            n++;
        }
    if (count)
        *count = displays ? MIN(n, max) : n;
    return kCGErrorSuccess;
}
CGError CGGetActiveDisplayList(uint32_t max, CGDirectDisplayID *displays, uint32_t *count)
{
    return CGGetOnlineDisplayList(max, displays, count);
}
/* the global display space: the main display's top left corner is 0,0 and y
 * runs down */
CGRect CGDisplayBounds(CGDirectDisplayID d)
{
    NSScreen *s = screen_numbered(d);
    NSScreen *main = [screens() firstObject];
    if (!s)
        return d == CGMainDisplayID() ? CGRectMake(0, 0, 1280, 800) : CGRectZero;
    NSRect f = [s frame];
    CGFloat top = NSMaxY([main frame]);
    return CGRectMake(f.origin.x, top - NSMaxY(f), f.size.width, f.size.height);
}
CGError CGGetDisplaysWithPoint(CGPoint p, uint32_t max, CGDirectDisplayID *displays, uint32_t *count)
{
    uint32_t all_n = 0;
    CGDirectDisplayID all[16];
    CGGetOnlineDisplayList(16, all, &all_n);
    uint32_t n = 0;
    for (uint32_t i = 0; i < all_n; i++)
        if (CGRectContainsPoint(CGDisplayBounds(all[i]), p)) {
            if (displays && n < max)
                displays[n] = all[i];
            n++;
        }
    if (count)
        *count = displays ? MIN(n, max) : n;
    return kCGErrorSuccess;
}
size_t CGDisplayPixelsWide(CGDirectDisplayID d)
{
    NSScreen *s = screen_numbered(d);
    return (size_t)(CGDisplayBounds(d).size.width * (s ? [s backingScaleFactor] : 1));
}
size_t CGDisplayPixelsHigh(CGDirectDisplayID d)
{
    NSScreen *s = screen_numbered(d);
    return (size_t)(CGDisplayBounds(d).size.height * (s ? [s backingScaleFactor] : 1));
}
boolean_t CGDisplayIsMain(CGDirectDisplayID d) { return d == CGMainDisplayID(); }
boolean_t CGDisplayIsActive(CGDirectDisplayID d) { return screen_numbered(d) != nil || d == CGMainDisplayID(); }
boolean_t CGDisplayIsOnline(CGDirectDisplayID d) { return CGDisplayIsActive(d); }
boolean_t CGDisplayIsBuiltin(CGDirectDisplayID d) { return CGDisplayIsMain(d); }
boolean_t CGDisplayUsesOpenGLAcceleration(CGDirectDisplayID d) { return CGDisplayIsActive(d); }
/* Grayscale and inverted colours are accessibility display settings that
 * Ferry's displays never turn on. */
boolean_t CGDisplayUsesForceToGray(void) { return 0; }
boolean_t CGDisplayUsesInvertedPolarity(void) { return 0; }

/* ---- fades: a borderless window over every screen, its alpha the blend ----------------- */

static CGDisplayFadeReservationToken reserved;
static NSDate *reserved_until;
static NSMutableArray<NSWindow *> *fade_windows;
static BOOL fading;

CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval seconds, CGDisplayFadeReservationToken *token)
{
    if (!token || seconds <= 0 || seconds > kCGMaxDisplayReservationInterval)
        return kCGErrorIllegalArgument;
    if (reserved && [reserved_until timeIntervalSinceNow] > 0)
        return kCGErrorNoneAvailable;
    static uint32_t next = 1;
    reserved = next++;
    [reserved_until release];
    reserved_until = [[NSDate dateWithTimeIntervalSinceNow:seconds] retain];
    *token = reserved;
    return kCGErrorSuccess;
}
static void set_fade(CGFloat blend, NSColor *color)
{
    if (!fade_windows)
        fade_windows = [[NSMutableArray alloc] init];
    if (blend <= 0) {
        for (NSWindow *w in fade_windows)
            [w orderOut:nil];
        [fade_windows removeAllObjects];
        return;
    }
    if (![fade_windows count])
        for (NSScreen *s in screens()) {
            NSWindow *w = [[[NSWindow alloc] initWithContentRect:[s frame] styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO] autorelease];
            [w setReleasedWhenClosed:NO];
            [w setOpaque:NO];
            [w setIgnoresMouseEvents:YES];
            [w setLevel:NSScreenSaverWindowLevel];
            [fade_windows addObject:w];
        }
    for (NSWindow *w in fade_windows) {
        [w setBackgroundColor:color];
        [w setAlphaValue:blend];
        [w orderFrontRegardless];
    }
}
CGError CGDisplayFade(CGDisplayFadeReservationToken token, CGDisplayFadeInterval duration, CGDisplayBlendFraction start,
                      CGDisplayBlendFraction end, float r, float g, float b, boolean_t synchronous)
{
    if (!token || token != reserved)
        return kCGErrorIllegalArgument;
    NSColor *color = [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
    if (!screens() || duration <= 0) {
        set_fade(end, color);
        return kCGErrorSuccess;
    }
    /* in steps of a sixtieth of a second; an asynchronous fade runs on the main run loop */
    int steps = MAX(1, (int)(duration * 60));
    fading = YES;
    if (synchronous || ![NSThread isMainThread]) {
        for (int i = 1; i <= steps; i++) {
            CGFloat f = start + (end - start) * i / steps;
            dispatch_sync(dispatch_get_main_queue(), ^{ set_fade(f, color); });
            usleep((useconds_t)(duration * 1e6 / steps));
        }
        fading = NO;
    } else {
        __block int i = 0;
        [NSTimer scheduledTimerWithTimeInterval:duration / steps repeats:YES block:^(NSTimer *t) {
            i++;
            set_fade(start + (end - start) * i / steps, color);
            if (i >= steps) {
                fading = NO;
                [t invalidate];
            }
        }];
    }
    return kCGErrorSuccess;
}
CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken token)
{
    if (!token || token != reserved)
        return kCGErrorIllegalArgument;
    reserved = 0;
    return kCGErrorSuccess;
}
boolean_t CGDisplayFadeOperationInProgress(void) { return fading; }

/* The Metal device that drives a display, retained, as the reference says
 * (freemac Godot work): Ferry's one software device, from the program's own
 * Metal framework, or nil when the program doesn't have Metal loaded. */
#include <dlfcn.h>
id<MTLDevice> CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID display)
{
    id (*create)(void) = (id (*)(void))dlsym(RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
    return create ? create() : nil;
}

/* The window server connection of a program's own windows: a private
 * call (Godot sets window properties through it), so there is one
 * connection, numbered 1, and nothing is sent on it. */
int CGSMainConnectionID(void) { return 1; }
/* Spaces, also private calls: kitty asks which Space its windows are on, to
 * find its own window on the Space being shown. Ferry's desktop has one
 * Space, numbered 1, which every window is on and which is always the
 * active one (freemac 1.268). */
uint64_t CGSGetActiveSpace(int connection) { return 1; }
CFArrayRef CGSCopySpacesForWindows(int connection, int mask, CFArrayRef windows)
{
    if (!windows || !CFArrayGetCount(windows))
        return CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);
    long long one = 1;
    CFNumberRef space = CFNumberCreate(NULL, kCFNumberLongLongType, &one);
    CFArrayRef r = CFArrayCreate(NULL, (const void **)&space, 1, &kCFTypeArrayCallBacks);
    CFRelease(space);
    return r;
}
/* A blur of what shows through a window's transparent background (Zed asks
 * for one under its translucent themes). Ferry's windows draw no blur yet,
 * so the request is accepted and the background stays as the app drew it
 * (freemac 1.268). */
int CGSSetWindowBackgroundBlurRadius(int connection, long window, int radius)
{
    (void)connection, (void)window, (void)radius;
    return 0;
}
