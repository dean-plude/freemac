/* SPDX-License-Identifier: GPL-3.0-or-later
 * Quartz Display Services (freemac 1.232), written from Apple's public
 * documentation of CGDirectDisplay. They are Core Graphics calls on a Mac,
 * but the displays are the ones NSScreen sees (Wayfire's outputs on
 * freemac, or GTK's one screen), so they live in AppKit's file beside
 * CGServices.m and reach programs through it and ApplicationServices.
 *
 * A display's ID is its screen's NSScreenNumber, the main display's first.
 * Its bounds are in a Mac's global display space: points, from the main
 * display's top left, y running down. Its one mode is its current size in
 * points and in pixels (points times the backing scale) at 60 Hz, as
 * freemac's compositor doesn't say a refresh rate. Reconfiguration
 * callbacks are kept but never called, as displays are read afresh at
 * every call. Displays can't be captured or have their modes set, as on a
 * Mac where the user hasn't allowed it; no picture of a display is taken
 * (the Screen Recording say isn't Ferry's to give). */
#import "AInternal.h"
#include <CoreGraphics/CGDirectDisplay.h>

const CFStringRef kCGDisplayShowDuplicateLowResolutionModes = (CFStringRef)@"kCGDisplayShowDuplicateLowResolutionModes";

static NSArray *all_screens(void) { return [NSScreen screens]; }

static CGDirectDisplayID screen_id(NSScreen *s)
{
    return (CGDirectDisplayID)[[s deviceDescription][@"NSScreenNumber"] unsignedIntValue];
}

static NSScreen *screen_for(CGDirectDisplayID d)
{
    for (NSScreen *s in all_screens())
        if (screen_id(s) == d)
            return s;
    return nil;
}

/* NSScreen frames run up from the main screen's bottom left; a display's
 * bounds run down from its top left */
static CGRect bounds_of(NSScreen *s)
{
    NSRect main = [all_screens()[0] frame], f = [s frame];
    return CGRectMake(f.origin.x, NSMaxY(main) - NSMaxY(f), f.size.width, f.size.height);
}

CGDirectDisplayID CGMainDisplayID(void) { return screen_id(all_screens()[0]); }

static CGError list(uint32_t max, CGDirectDisplayID *out, uint32_t *count, BOOL (^keep)(NSScreen *))
{
    uint32_t n = 0;
    for (NSScreen *s in all_screens()) {
        if (keep && !keep(s))
            continue;
        if (out && n < max)
            out[n] = screen_id(s);
        n++;
    }
    if (count)
        *count = out ? MIN(n, max) : n;
    return kCGErrorSuccess;
}

CGError CGGetOnlineDisplayList(uint32_t max, CGDirectDisplayID *out, uint32_t *count) { return list(max, out, count, nil); }
CGError CGGetActiveDisplayList(uint32_t max, CGDirectDisplayID *out, uint32_t *count) { return list(max, out, count, nil); }
CGError CGGetDisplaysWithRect(CGRect rect, uint32_t max, CGDirectDisplayID *out, uint32_t *count)
{
    return list(max, out, count, ^BOOL(NSScreen *s) { return CGRectIntersectsRect(bounds_of(s), rect); });
}
CGError CGGetDisplaysWithPoint(CGPoint point, uint32_t max, CGDirectDisplayID *out, uint32_t *count)
{
    return list(max, out, count, ^BOOL(NSScreen *s) { return CGRectContainsPoint(bounds_of(s), point); });
}

/* a display's OpenGL mask is its place in the list, as one bit */
CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID d)
{
    NSArray *screens = all_screens();
    for (NSUInteger i = 0; i < [screens count] && i < 32; i++)
        if (screen_id(screens[i]) == d)
            return 1u << i;
    return 0;
}
CGDirectDisplayID CGOpenGLDisplayMaskToDisplayID(CGOpenGLDisplayMask mask)
{
    NSArray *screens = all_screens();
    for (NSUInteger i = 0; i < [screens count] && i < 32; i++)
        if (mask & (1u << i))
            return screen_id(screens[i]);
    return kCGNullDirectDisplay;
}
CGError CGGetDisplaysWithOpenGLDisplayMask(CGOpenGLDisplayMask mask, uint32_t max, CGDirectDisplayID *out, uint32_t *count)
{
    return list(max, out, count, ^BOOL(NSScreen *s) { return (CGDisplayIDToOpenGLDisplayMask(screen_id(s)) & mask) != 0; });
}

CGRect CGDisplayBounds(CGDirectDisplayID d)
{
    NSScreen *s = screen_for(d);
    return s ? bounds_of(s) : CGRectZero;
}
size_t CGDisplayPixelsWide(CGDirectDisplayID d) { return (size_t)CGDisplayBounds(d).size.width; }
size_t CGDisplayPixelsHigh(CGDirectDisplayID d) { return (size_t)CGDisplayBounds(d).size.height; }
/* the size in millimetres, at a Mac's nominal 72 points an inch scaled to
 * a typical desktop display's 96 */
CGSize CGDisplayScreenSize(CGDirectDisplayID d)
{
    NSScreen *s = screen_for(d);
    if (!s)
        return CGSizeZero;
    NSSize p = [s frame].size;
    CGFloat mm = 25.4 / 96.0 * [s backingScaleFactor];
    return CGSizeMake(p.width * mm, p.height * mm);
}
double CGDisplayRotation(CGDirectDisplayID d) { return 0; }
boolean_t CGDisplayIsActive(CGDirectDisplayID d) { return screen_for(d) != nil; }
boolean_t CGDisplayIsAsleep(CGDirectDisplayID d) { return false; }
boolean_t CGDisplayIsOnline(CGDirectDisplayID d) { return screen_for(d) != nil; }
boolean_t CGDisplayIsMain(CGDirectDisplayID d) { return d == CGMainDisplayID(); }
boolean_t CGDisplayIsBuiltin(CGDirectDisplayID d) { return false; }
boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID d) { return false; }
boolean_t CGDisplayIsAlwaysInMirrorSet(CGDirectDisplayID d) { return false; }
boolean_t CGDisplayIsInHWMirrorSet(CGDirectDisplayID d) { return false; }
boolean_t CGDisplayUsesOpenGLAcceleration(CGDirectDisplayID d) { return screen_for(d) != nil; }
boolean_t CGDisplayIsStereo(CGDirectDisplayID d) { return false; }
CGDirectDisplayID CGDisplayMirrorsDisplay(CGDirectDisplayID d) { return kCGNullDirectDisplay; }
CGDirectDisplayID CGDisplayPrimaryDisplay(CGDirectDisplayID d) { return d; }
uint32_t CGDisplayUnitNumber(CGDirectDisplayID d)
{
    NSArray *screens = all_screens();
    for (NSUInteger i = 0; i < [screens count]; i++)
        if (screen_id(screens[i]) == d)
            return (uint32_t)i;
    return 0;
}
/* no EDID is read: unknown vendor and model, as for a display that has none */
uint32_t CGDisplayVendorNumber(CGDirectDisplayID d) { return 0xFFFFFFFF; }
uint32_t CGDisplayModelNumber(CGDirectDisplayID d) { return 0xFFFFFFFF; }
uint32_t CGDisplaySerialNumber(CGDirectDisplayID d) { return 0; }
CGColorSpaceRef CGDisplayCopyColorSpace(CGDirectDisplayID d) { return CGColorSpaceCreateWithName(kCGColorSpaceSRGB); }

/* ---- display modes ---- */

@interface FDisplayMode : NSObject {
@public
    size_t width, height, pixelWidth, pixelHeight;
}
@end
@implementation FDisplayMode
@end

static Class mode_class(void) { return [FDisplayMode class]; }
CFTypeID CGDisplayModeGetTypeID(void) { return (CFTypeID)(uintptr_t)mode_class(); }

CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID d)
{
    NSScreen *s = screen_for(d);
    if (!s)
        return NULL;
    FDisplayMode *m = [[FDisplayMode alloc] init];
    NSSize size = [s frame].size;
    CGFloat scale = [s backingScaleFactor];
    m->width = (size_t)size.width;
    m->height = (size_t)size.height;
    m->pixelWidth = (size_t)(size.width * scale);
    m->pixelHeight = (size_t)(size.height * scale);
    return (__bridge CGDisplayModeRef)m;
}
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID d, CFDictionaryRef options)
{
    CGDisplayModeRef m = CGDisplayCopyDisplayMode(d);
    if (!m)
        return NULL;
    NSArray *a = [[NSArray alloc] initWithObjects:(__bridge id)m, nil];
    CGDisplayModeRelease(m);
    return (__bridge CFArrayRef)a;
}
CGError CGDisplaySetDisplayMode(CGDirectDisplayID d, CGDisplayModeRef mode, CFDictionaryRef options) { return kCGErrorFailure; }
#define M(ref) ((__bridge FDisplayMode *)(ref))
size_t CGDisplayModeGetWidth(CGDisplayModeRef m) { return m ? M(m)->width : 0; }
size_t CGDisplayModeGetHeight(CGDisplayModeRef m) { return m ? M(m)->height : 0; }
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef m) { return m ? M(m)->pixelWidth : 0; }
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef m) { return m ? M(m)->pixelHeight : 0; }
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m) { return m ? 60.0 : 0; }
uint32_t CGDisplayModeGetIOFlags(CGDisplayModeRef m) { return m ? 0x3 : 0; } /* valid, safe */
int32_t CGDisplayModeGetIODisplayModeID(CGDisplayModeRef m) { return m ? 1 : 0; }
bool CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef m) { return m != NULL; }
CGDisplayModeRef CGDisplayModeRetain(CGDisplayModeRef m) { if (m) [M(m) retain]; return m; }
void CGDisplayModeRelease(CGDisplayModeRef m) { if (m) [M(m) release]; }

/* ---- reconfiguration, capture, the cursor ---- */

static NSMutableArray *callbacks;

CGError CGDisplayRegisterReconfigurationCallback(CGDisplayReconfigurationCallBack cb, void *info)
{
    if (!cb)
        return kCGErrorIllegalArgument;
    if (!callbacks)
        callbacks = [[NSMutableArray alloc] init];
    [callbacks addObject:@[ [NSValue valueWithPointer:(void *)cb], [NSValue valueWithPointer:info] ]];
    return kCGErrorSuccess;
}
CGError CGDisplayRemoveReconfigurationCallback(CGDisplayReconfigurationCallBack cb, void *info)
{
    for (NSArray *pair in [[callbacks copy] autorelease])
        if ([pair[0] pointerValue] == (void *)cb && [pair[1] pointerValue] == info)
            [callbacks removeObject:pair];
    return kCGErrorSuccess;
}

CGError CGDisplayCapture(CGDirectDisplayID d) { return kCGErrorFailure; }
CGError CGDisplayRelease(CGDirectDisplayID d) { return kCGErrorSuccess; }
CGError CGCaptureAllDisplays(void) { return kCGErrorFailure; }
CGError CGReleaseAllDisplays(void) { return kCGErrorSuccess; }
boolean_t CGDisplayIsCaptured(CGDirectDisplayID d) { return false; }
CGError CGDisplayHideCursor(CGDirectDisplayID d) { [NSCursor hide]; return kCGErrorSuccess; }
CGError CGDisplayShowCursor(CGDirectDisplayID d) { [NSCursor unhide]; return kCGErrorSuccess; }
/* Wayland lets no program move the pointer */
CGError CGDisplayMoveCursorToPoint(CGDirectDisplayID d, CGPoint point) { return kCGErrorFailure; }
CGImageRef CGDisplayCreateImage(CGDirectDisplayID d) { return NULL; }
CGImageRef CGDisplayCreateImageForRect(CGDirectDisplayID d, CGRect rect) { return NULL; }

/* A display's UUID is made from its ID, so it is the same at every call
 * and turns back into the ID. */
CFUUIDRef CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID d)
{
    if (!screen_for(d))
        return NULL;
    CFUUIDBytes b = {0x46, 0x45, 0x52, 0x52, 0x59, 0x44, 0x49, 0x53, 0x50, 0x4c, 0x41, 0x59,
                     (UInt8)(d >> 24), (UInt8)(d >> 16), (UInt8)(d >> 8), (UInt8)d};
    return CFUUIDCreateFromUUIDBytes(NULL, b);
}
CGDirectDisplayID CGDisplayGetDisplayIDFromUUID(CFUUIDRef uuid)
{
    if (!uuid)
        return kCGNullDirectDisplay;
    CFUUIDBytes b = CFUUIDGetUUIDBytes(uuid);
    static const UInt8 prefix[12] = {0x46, 0x45, 0x52, 0x52, 0x59, 0x44, 0x49, 0x53, 0x50, 0x4c, 0x41, 0x59};
    if (memcmp(&b, prefix, 12))
        return kCGNullDirectDisplay;
    CGDirectDisplayID d = ((CGDirectDisplayID)b.byte12 << 24) | ((CGDirectDisplayID)b.byte13 << 16) | ((CGDirectDisplayID)b.byte14 << 8) | b.byte15;
    return screen_for(d) ? d : kCGNullDirectDisplay;
}
