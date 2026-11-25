/* SPDX-License-Identifier: GPL-3.0-or-later
 * Quartz Window Services and Quartz Event Services (freemac 1.220, Ferry
 * 0.44.0), written from Apple's public documentation of CGWindowList...,
 * CGEvent, CGEventSource and CGEventTap. They are Core Graphics calls on a
 * Mac, but here they need the compositor and the user's say, so they live
 * in AppKit's file beside the Accessibility API (Carbon.m), as AX does.
 *
 * Windows (ShiftIt finds the front window this way, MacPass picks the
 * window to type into, Sequel Pro and Flycut picture their own windows):
 * an app always sees its own windows, from its own NSWindows. Other apps'
 * windows come from freemac's Wayfire (window-rules/list-views, with
 * Strata's strata/view-pids saying whose each is), most recently focused
 * first, and only once the user has allowed the app to control other
 * windows: the same say, kept in ~/.config/freemac/window-control.json,
 * that AXIsProcessTrusted answers from, and that Dials > Privacy &
 * Security turns off again. Their bounds are the Accessibility API's, from
 * the main display's top left, so ShiftIt matches them with AXPosition and
 * AXSize. The shell's own surfaces (the menu bar, the Dock, the desktop)
 * are never listed. Pictures are taken of the app's own windows only.
 *
 * Events (Flycut and MacPass paste with Command-V, MacPass types text):
 * a key event posted with CGEventPost goes, with the same say, through
 * Strata's strata/press-key, which presses keys on the computer's own
 * keyboard, so the window that has the keyboard gets them as typed keys
 * and freemac's Command key turns Command-V into the paste of a Linux app.
 * Each key-down presses its modifiers, taps the key and lets the modifiers
 * go again, so a key is never left held; key-ups and modifier changes are
 * then nothing more to do. Text set with CGEventKeyboardSetUnicodeString is
 * typed key by key while the keyboard's layout is English (US), whose keys
 * Ferry knows; with any other layout it isn't typed at all, rather than
 * typed wrongly. Mouse events can't be posted to other apps (Wayland, and
 * Strata, offer no way for an app to move the pointer or click for
 * another), and event taps are never made (no app may watch another's
 * keys): both answer as a Mac does for an app the user hasn't allowed.
 * CGEventPostToPid with the app's own process id hands the event to the
 * app itself, with no say needed. */
#import "AInternal.h"
#import "AWayfire.h"
#include <Carbon/Carbon.h>
#include <HIServices/Accessibility.h>
#include <stdarg.h>

/* ---- saying what isn't done, once ------------------------------------------------ */

static void say_once(int *said, const char *fmt, const char *arg)
{
    if (*said)
        return;
    *said = 1;
    fflush(stdout);
    fprintf(stderr, "AppKit (Ferry): ");
    fprintf(stderr, fmt, arg);
    fprintf(stderr, "\n");
}

static NSString *own_name(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *k in @[ @"CFBundleDisplayName", @"CFBundleName" ])
        if ([info[k] isKindOfClass:[NSString class]] && [info[k] length])
            return info[k];
    return [[NSProcessInfo processInfo] processName];
}

/* ---- window levels ------------------------------------------------------------------- */

CGWindowLevel CGWindowLevelForKey(CGWindowLevelKey key)
{
    static const int32_t levels[kCGNumberOfWindowLevelKeys] = {
        [kCGBaseWindowLevelKey] = INT32_MIN,
        [kCGMinimumWindowLevelKey] = INT32_MIN + 1,
        [kCGDesktopWindowLevelKey] = INT32_MIN + 21,
        [kCGBackstopMenuLevelKey] = -20,
        [kCGNormalWindowLevelKey] = 0,
        [kCGFloatingWindowLevelKey] = 3,
        [kCGTornOffMenuWindowLevelKey] = 3,
        [kCGDockWindowLevelKey] = 20,
        [kCGMainMenuWindowLevelKey] = 24,
        [kCGStatusWindowLevelKey] = 25,
        [kCGModalPanelWindowLevelKey] = 8,
        [kCGPopUpMenuWindowLevelKey] = 101,
        [kCGDraggingWindowLevelKey] = 500,
        [kCGScreenSaverWindowLevelKey] = 1000,
        [kCGMaximumWindowLevelKey] = INT32_MAX - 15,
        [kCGOverlayWindowLevelKey] = 102,
        [kCGHelpWindowLevelKey] = 200,
        [kCGUtilityWindowLevelKey] = 19,
        [kCGDesktopIconWindowLevelKey] = INT32_MIN + 41,
        [kCGCursorWindowLevelKey] = INT32_MAX - 16,
        [kCGAssistiveTechHighWindowLevelKey] = 1500,
    };
    return key >= 0 && key < kCGNumberOfWindowLevelKeys ? levels[key] : 0;
}

/* ---- the window list ------------------------------------------------------------------ */

const CFStringRef kCGWindowNumber = (CFStringRef)@"kCGWindowNumber";
const CFStringRef kCGWindowStoreType = (CFStringRef)@"kCGWindowStoreType";
const CFStringRef kCGWindowLayer = (CFStringRef)@"kCGWindowLayer";
const CFStringRef kCGWindowBounds = (CFStringRef)@"kCGWindowBounds";
const CFStringRef kCGWindowSharingState = (CFStringRef)@"kCGWindowSharingState";
const CFStringRef kCGWindowAlpha = (CFStringRef)@"kCGWindowAlpha";
const CFStringRef kCGWindowOwnerPID = (CFStringRef)@"kCGWindowOwnerPID";
const CFStringRef kCGWindowMemoryUsage = (CFStringRef)@"kCGWindowMemoryUsage";
const CFStringRef kCGWindowWorkspace = (CFStringRef)@"kCGWindowWorkspace";
const CFStringRef kCGWindowOwnerName = (CFStringRef)@"kCGWindowOwnerName";
const CFStringRef kCGWindowName = (CFStringRef)@"kCGWindowName";
const CFStringRef kCGWindowIsOnscreen = (CFStringRef)@"kCGWindowIsOnscreen";
const CFStringRef kCGWindowBackingLocationVideoMemory = (CFStringRef)@"kCGWindowBackingLocationVideoMemory";

/* Other apps' windows are numbered with this bit, so their numbers never
 * meet the app's own window numbers (which count up from 1). */
static const CGWindowID other_bit = 0x40000000;

/* One window of the list. */
@interface ACGWindowEntry : NSObject {
@public
    CGWindowID number;
    pid_t pid;
    NSString *owner, *title;
    NSRect bounds;          /* from the main display's top left, y down */
    NSInteger layer;
    CGFloat alpha;
    BOOL onscreen;
    NSWindow *window;       /* the app's own, not retained */
}
@end
@implementation ACGWindowEntry
- (void)dealloc
{
    [owner release];
    [title release];
    [super dealloc];
}
- (NSDictionary *)description_
{
    CFDictionaryRef b = CGRectCreateDictionaryRepresentation(bounds);
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:@{
        (id)kCGWindowNumber : @(number),
        (id)kCGWindowStoreType : @(kCGBackingStoreBuffered),
        (id)kCGWindowLayer : @(layer),
        (id)kCGWindowBounds : (id)b,
        (id)kCGWindowSharingState : @(window ? kCGWindowSharingReadOnly : kCGWindowSharingNone),
        (id)kCGWindowAlpha : @(alpha),
        (id)kCGWindowOwnerPID : @(pid),
        (id)kCGWindowMemoryUsage : @((long long)(bounds.size.width * bounds.size.height * 4)),
        (id)kCGWindowOwnerName : owner ?: @"",
        (id)kCGWindowIsOnscreen : @(onscreen),
        (id)kCGWindowBackingLocationVideoMemory : @NO,
    }];
    if (title)
        d[(id)kCGWindowName] = title;
    CFRelease(b);
    return d;
}
@end

static NSRect json_rect(id j)
{
    if (![j isKindOfClass:[NSDictionary class]])
        return NSZeroRect;
    return NSMakeRect([j[@"x"] doubleValue], [j[@"y"] doubleValue], [j[@"width"] doubleValue],
                      [j[@"height"] doubleValue]);
}

/* {view id: process id} from Strata, or nil when Wayfire can't say. */
static NSDictionary *view_pids(void)
{
    id reply = AWayfireCall(@"strata/view-pids", nil);
    id views = [reply isKindOfClass:[NSDictionary class]] ? reply[@"views"] : nil;
    if (![views isKindOfClass:[NSArray class]])
        return nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id v in views)
        if ([v isKindOfClass:[NSDictionary class]] && v[@"id"] && v[@"pid"])
            out[@([v[@"id"] longLongValue])] = @([v[@"pid"] intValue]);
    return out;
}

/* An app's name from its Wayland app id: the last part of a reverse-DNS id. */
static NSString *owner_from_app_id(id appID)
{
    if (![appID isKindOfClass:[NSString class]] || ![appID length])
        return @"";
    NSString *s = appID;
    NSRange dot = [s rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound && dot.location + 1 < [s length] && [[s componentsSeparatedByString:@"."] count] > 2)
        return [s substringFromIndex:dot.location + 1];
    return s;
}

/* An NSWindow's frame as the window list gives it. */
static NSRect top_left_frame(NSWindow *w)
{
    NSRect f = [w frame], main = AScreenFrame(NO);
    return NSMakeRect(f.origin.x - main.origin.x, NSMaxY(main) - NSMaxY(f), f.size.width, f.size.height);
}

static BOOL is_app_window(NSWindow *w)
{
    return [w windowNumber] > 0;
}

/* Every window the app may list, front to back: Wayfire's, most recently
 * focused first, then the app's own windows Wayfire doesn't show. Other
 * apps' windows only with the user's say. */
static NSArray *all_windows(void)
{
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *own = [NSMutableArray array];
    for (NSWindow *w in AAllWindows())
        if (is_app_window(w))
            [own addObject:w];
    BOOL others = AXIsProcessTrusted();
    pid_t me = getpid();
    NSString *myName = own_name();
    NSMutableSet *matched = [NSMutableSet set];

    id list = AWayfireAvailable() ? AWayfireCall(@"window-rules/list-views", nil) : nil;
    NSDictionary *pids = [list isKindOfClass:[NSArray class]] ? view_pids() : nil;
    NSArray *outputs = pids ? AWayfireOutputs() : nil;
    if (pids && outputs) {
        NSMutableArray *views = [NSMutableArray array];
        for (id v in list) {
            if (![v isKindOfClass:[NSDictionary class]])
                continue;
            id kind = v[@"role"] ?: v[@"type"];
            if (![kind isEqual:@"toplevel"])
                continue;       /* the shell's own surfaces */
            [views addObject:v];
        }
        [views sortUsingComparator:^NSComparisonResult(id a, id b) {
            double ta = [a[@"last-focus-timestamp"] doubleValue], tb = [b[@"last-focus-timestamp"] doubleValue];
            return ta > tb ? NSOrderedAscending : ta < tb ? NSOrderedDescending : NSOrderedSame;
        }];
        NSRect main = [[outputs firstObject][@"frame"] rectValue];
        for (NSDictionary *v in views) {
            int64_t view = [v[@"id"] longLongValue];
            NSNumber *pid = pids[@(view)];
            if (!pid)
                continue;
            NSString *title = [v[@"title"] isKindOfClass:[NSString class]] ? v[@"title"] : @"";
            NSWindow *mine = nil;
            if ([pid intValue] == me) {
                for (NSWindow *w in own)
                    if (!mine && ![matched containsObject:w] && [[w title] isEqual:title])
                        mine = w;
                if (!mine)
                    continue;   /* a surface of the app's that isn't one of its windows */
                [matched addObject:mine];
            } else if (!others) {
                continue;
            }
            NSRect r = json_rect(v[@"geometry"]);
            NSRect of = main;
            for (NSDictionary *o in outputs)
                if ([o[@"id"] longLongValue] == [v[@"output-id"] longLongValue])
                    of = [o[@"frame"] rectValue];
            r.origin.x += of.origin.x - main.origin.x;
            r.origin.y += of.origin.y - main.origin.y;
            id minimized = v[@"minimized"];
            id mapped = v[@"mapped"];
            ACGWindowEntry *e = [[[ACGWindowEntry alloc] init] autorelease];
            e->pid = [pid intValue];
            e->title = [title copy];
            e->bounds = r;
            e->onscreen = (!mapped || [mapped boolValue]) && ![minimized boolValue];
            if (mine) {
                e->window = mine;
                e->number = (CGWindowID)[mine windowNumber];
                e->owner = [myName copy];
                e->layer = [mine level];
                e->alpha = [mine alphaValue];
                e->onscreen = e->onscreen && [mine isVisible] && ![mine isMiniaturized];
            } else {
                e->number = other_bit | (CGWindowID)(view & 0x3fffffff);
                e->owner = [owner_from_app_id(v[@"app-id"]) copy];
                e->layer = 0;
                e->alpha = 1;
            }
            [out addObject:e];
        }
    }
    for (NSWindow *w in own) {
        if ([matched containsObject:w])
            continue;
        ACGWindowEntry *e = [[[ACGWindowEntry alloc] init] autorelease];
        e->window = w;
        e->number = (CGWindowID)[w windowNumber];
        e->pid = me;
        e->owner = [myName copy];
        e->title = [([w title] ?: @"") copy];
        e->bounds = top_left_frame(w);
        e->layer = [w level];
        e->alpha = [w alphaValue];
        e->onscreen = [w isVisible] && ![w isMiniaturized];
        [out addObject:e];
    }
    return out;
}

static NSArray *chosen_windows(CGWindowListOption option, CGWindowID relative)
{
    NSArray *all = all_windows();
    if (!(option & (kCGWindowListOptionOnScreenOnly | kCGWindowListOptionOnScreenAboveWindow |
                    kCGWindowListOptionOnScreenBelowWindow | kCGWindowListOptionIncludingWindow)))
        return all;
    NSUInteger at = NSNotFound;
    for (NSUInteger i = 0; i < [all count] && at == NSNotFound; i++)
        if (((ACGWindowEntry *)all[i])->number == relative)
            at = i;
    BOOL above = (option & kCGWindowListOptionOnScreenAboveWindow) != 0;
    BOOL below = (option & kCGWindowListOptionOnScreenBelowWindow) != 0;
    BOOL including = (option & kCGWindowListOptionIncludingWindow) != 0;
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < [all count]; i++) {
        ACGWindowEntry *e = all[i];
        BOOL take;
        if (above || below) {
            if (at == NSNotFound)
                take = e->onscreen;     /* no such window: every one on screen */
            else
                take = (i == at && including) || (above && i < at && e->onscreen) || (below && i > at && e->onscreen);
        } else if (including) {
            take = i == at;
        } else {
            take = e->onscreen;
        }
        if (take)
            [out addObject:e];
    }
    return out;
}

CFArrayRef CGWindowListCopyWindowInfo(CGWindowListOption option, CGWindowID relativeToWindow)
{
    @autoreleasepool {
        NSMutableArray *out = [[NSMutableArray alloc] init];
        for (ACGWindowEntry *e in chosen_windows(option, relativeToWindow))
            [out addObject:[e description_]];
        return (CFArrayRef)out;
    }
}

CFArrayRef CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow)
{
    @autoreleasepool {
        NSArray *chosen = chosen_windows(option, relativeToWindow);
        NSUInteger n = [chosen count];
        const void **ids = calloc(n ? n : 1, sizeof *ids);
        for (NSUInteger i = 0; i < n; i++)
            ids[i] = (const void *)(uintptr_t)((ACGWindowEntry *)chosen[i])->number;
        CFArrayRef a = CFArrayCreate(NULL, ids, (CFIndex)n, NULL);
        free(ids);
        return a;
    }
}

CFArrayRef CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray)
{
    @autoreleasepool {
        NSMutableArray *out = [[NSMutableArray alloc] init];
        if (!windowArray)
            return (CFArrayRef)out;
        NSArray *all = all_windows();
        for (CFIndex i = 0; i < CFArrayGetCount(windowArray); i++) {
            CGWindowID wanted = (CGWindowID)(uintptr_t)CFArrayGetValueAtIndex(windowArray, i);
            for (ACGWindowEntry *e in all)
                if (e->number == wanted) {
                    [out addObject:[e description_]];
                    break;
                }
        }
        return (CFArrayRef)out;
    }
}

/* ---- pictures of windows ------------------------------------------------------------ */

static CGImageRef picture_of(CGWindowID number)
{
    if (!number || (number & other_bit))
        return NULL;
    NSWindow *w = [NSApp windowWithWindowNumber:(NSInteger)number];
    NSView *v = w ? [w contentView] : nil;
    if (!v || !is_app_window(w))
        return NULL;
    NSRect bounds = [v bounds];
    if (bounds.size.width < 1 || bounds.size.height < 1)
        return NULL;
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:bounds];
    [v cacheDisplayInRect:bounds toBitmapImageRep:rep];
    CGImageRef image = [rep CGImage];
    return image ? CGImageRetain(image) : NULL;
}

CGImageRef CGWindowListCreateImage(CGRect screenBounds, CGWindowListOption listOption, CGWindowID windowID,
                                   CGWindowImageOption imageOption)
{
    @autoreleasepool {
        if (listOption == kCGWindowListOptionIncludingWindow)
            return picture_of(windowID);
        return NULL;    /* the screen, or other apps' windows: never */
    }
}

CGImageRef CGWindowListCreateImageFromArray(CGRect screenBounds, CFArrayRef windowArray, CGWindowImageOption imageOption)
{
    @autoreleasepool {
        if (!windowArray || CFArrayGetCount(windowArray) != 1)
            return NULL;
        return picture_of((CGWindowID)(uintptr_t)CFArrayGetValueAtIndex(windowArray, 0));
    }
}

bool CGPreflightScreenCaptureAccess(void) { return false; }
bool CGRequestScreenCaptureAccess(void) { return false; }

/* ---- events ---------------------------------------------------------------------------- */

@interface ACGEventSource : NSObject {
@public
    CGEventSourceStateID state;
    int64_t userData;
    CGEventSourceKeyboardType keyboardType;
    double pixelsPerLine;
    CFTimeInterval suppression;
}
@end
@implementation ACGEventSource
- (CFTypeID)_ferryCFTypeID { return (CFTypeID)[ACGEventSource class]; }
- (NSString *)description { return [NSString stringWithFormat:@"<CGEventSource state %d>", (int)state]; }
@end

enum { MAX_TEXT = 20 };      /* a Mac keeps at most 20 characters with a key event */

@interface ACGEvent : NSObject {
@public
    CGEventType type;
    CGEventFlags flags;
    CGEventTimestamp timestamp;
    CGPoint location;
    CGMouseButton button;
    UniChar text[MAX_TEXT];
    UniCharCount textLength;
    BOOL hasText;
    ACGEventSource *source;
    NSMutableDictionary *fields;    /* field -> NSNumber */
    NSEvent *nsEvent;               /* the NSEvent this was made from, if any */
}
@end
@implementation ACGEvent
- (CFTypeID)_ferryCFTypeID { return (CFTypeID)[ACGEvent class]; }
- (void)dealloc
{
    [source release];
    [fields release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<CGEvent type %u flags 0x%llx>", type, (unsigned long long)flags];
}
@end

static CGEventTimestamp now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (CGEventTimestamp)t.tv_sec * 1000000000ull + (CGEventTimestamp)t.tv_nsec;
}

static BOOL is_event(CGEventRef e) { return e && [(id)e isKindOfClass:[ACGEvent class]]; }
#define EV(e) ((ACGEvent *)(e))

/* The pointer as a Core Graphics event gives it: from the main display's
 * top left, y down. */
static CGPoint cg_mouse_location(void)
{
    NSPoint p = [NSEvent mouseLocation];
    NSRect main = AScreenFrame(NO);
    return CGPointMake(p.x - main.origin.x, NSMaxY(main) - p.y);
}

static ACGEvent *new_event(CGEventSourceRef source, CGEventType type)
{
    ACGEvent *e = [[ACGEvent alloc] init];
    e->type = type;
    e->timestamp = now_ns();
    e->location = cg_mouse_location();
    e->fields = [[NSMutableDictionary alloc] init];
    if (source && [(id)source isKindOfClass:[ACGEventSource class]]) {
        e->source = [(ACGEventSource *)source retain];
        e->fields[@(kCGEventSourceUserData)] = @(e->source->userData);
        e->fields[@(kCGEventSourceStateID)] = @(e->source->state);
        if (e->source->state != kCGEventSourceStatePrivate)
            e->flags = [NSEvent modifierFlags] & 0x00ff0000;
    }
    e->fields[@(kCGEventSourceUnixProcessID)] = @(getpid());
    return e;
}

CFTypeID CGEventGetTypeID(void) { return (CFTypeID)[ACGEvent class]; }
CGEventRef CGEventCreate(CGEventSourceRef source) { return (CGEventRef)new_event(source, kCGEventNull); }

CGEventRef CGEventCreateKeyboardEvent(CGEventSourceRef source, CGKeyCode virtualKey, bool keyDown)
{
    ACGEvent *e = new_event(source, keyDown ? kCGEventKeyDown : kCGEventKeyUp);
    e->fields[@(kCGKeyboardEventKeycode)] = @(virtualKey);
    return (CGEventRef)e;
}

CGEventRef CGEventCreateMouseEvent(CGEventSourceRef source, CGEventType mouseType, CGPoint position,
                                   CGMouseButton mouseButton)
{
    ACGEvent *e = new_event(source, mouseType);
    e->location = position;
    e->button = mouseButton;
    e->fields[@(kCGMouseEventButtonNumber)] = @(mouseButton);
    if (mouseType != kCGEventMouseMoved)
        e->fields[@(kCGMouseEventClickState)] = @1;
    return (CGEventRef)e;
}

static CGEventRef scroll_event(CGEventSourceRef source, CGScrollEventUnit units, uint32_t count, const int32_t *w)
{
    ACGEvent *e = new_event(source, kCGEventScrollWheel);
    for (uint32_t i = 0; i < count && i < 3; i++) {
        e->fields[@(kCGScrollWheelEventDeltaAxis1 + i)] =
            @(units == kCGScrollEventUnitLine ? w[i] : w[i] / 10);
        e->fields[@(kCGScrollWheelEventPointDeltaAxis1 + i)] =
            @(units == kCGScrollEventUnitLine ? w[i] * 10 : w[i]);
    }
    e->fields[@(kCGScrollWheelEventIsContinuous)] = @(units == kCGScrollEventUnitPixel);
    return (CGEventRef)e;
}

CGEventRef CGEventCreateScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount,
                                         int32_t wheel1, ...)
{
    int32_t w[3] = {wheel1, 0, 0};
    va_list ap;
    va_start(ap, wheel1);
    for (uint32_t i = 1; i < wheelCount && i < 3; i++)
        w[i] = va_arg(ap, int32_t);
    va_end(ap);
    return scroll_event(source, units, wheelCount, w);
}

CGEventRef CGEventCreateScrollWheelEvent2(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount,
                                          int32_t wheel1, int32_t wheel2, int32_t wheel3)
{
    int32_t w[3] = {wheel1, wheel2, wheel3};
    return scroll_event(source, units, wheelCount, w);
}

CGEventRef CGEventCreateCopy(CGEventRef event)
{
    if (!is_event(event))
        return NULL;
    ACGEvent *from = EV(event), *e = [[ACGEvent alloc] init];
    e->type = from->type;
    e->flags = from->flags;
    e->timestamp = from->timestamp;
    e->location = from->location;
    e->button = from->button;
    memcpy(e->text, from->text, sizeof e->text);
    e->textLength = from->textLength;
    e->hasText = from->hasText;
    e->source = [from->source retain];
    e->fields = [from->fields mutableCopy];
    return (CGEventRef)e;
}

CGEventSourceRef CGEventCreateSourceFromEvent(CGEventRef event)
{
    if (!is_event(event) || !EV(event)->source)
        return NULL;
    return (CGEventSourceRef)[EV(event)->source retain];
}
void CGEventSetSource(CGEventRef event, CGEventSourceRef source)
{
    if (!is_event(event) || (source && ![(id)source isKindOfClass:[ACGEventSource class]]))
        return;
    [(id)source retain];
    [EV(event)->source release];
    EV(event)->source = (ACGEventSource *)source;
    if (source)
        EV(event)->fields[@(kCGEventSourceUserData)] = @(((ACGEventSource *)source)->userData);
}

CGEventType CGEventGetType(CGEventRef event) { return is_event(event) ? EV(event)->type : kCGEventNull; }
void CGEventSetType(CGEventRef event, CGEventType type)
{
    if (is_event(event))
        EV(event)->type = type;
}
CGEventTimestamp CGEventGetTimestamp(CGEventRef event) { return is_event(event) ? EV(event)->timestamp : 0; }
void CGEventSetTimestamp(CGEventRef event, CGEventTimestamp t)
{
    if (is_event(event))
        EV(event)->timestamp = t;
}
CGPoint CGEventGetLocation(CGEventRef event) { return is_event(event) ? EV(event)->location : CGPointZero; }
CGPoint CGEventGetUnflippedLocation(CGEventRef event)
{
    CGPoint p = CGEventGetLocation(event);
    NSRect main = AScreenFrame(NO);
    return CGPointMake(p.x, main.size.height - p.y);
}
void CGEventSetLocation(CGEventRef event, CGPoint location)
{
    if (is_event(event))
        EV(event)->location = location;
}
CGEventFlags CGEventGetFlags(CGEventRef event) { return is_event(event) ? EV(event)->flags : 0; }
void CGEventSetFlags(CGEventRef event, CGEventFlags flags)
{
    if (is_event(event))
        EV(event)->flags = flags;
}

void CGEventKeyboardGetUnicodeString(CGEventRef event, UniCharCount max, UniCharCount *actual, UniChar *out)
{
    if (actual)
        *actual = 0;
    if (!is_event(event))
        return;
    ACGEvent *e = EV(event);
    UniCharCount n = e->textLength;
    if (!e->hasText) {
        /* the characters the key types, as far as Ferry knows them */
        NSString *s = nil;
        if (e->nsEvent)
            s = [e->nsEvent characters];
        n = (UniCharCount)MIN([s length], (NSUInteger)MAX_TEXT);
        if (out && s)
            [s getCharacters:out range:NSMakeRange(0, MIN((NSUInteger)n, (NSUInteger)max))];
    } else if (out) {
        memcpy(out, e->text, sizeof(UniChar) * MIN(n, max));
    }
    if (actual)
        *actual = MIN(n, max);
}

void CGEventKeyboardSetUnicodeString(CGEventRef event, UniCharCount length, const UniChar *string)
{
    if (!is_event(event))
        return;
    ACGEvent *e = EV(event);
    e->textLength = string ? MIN(length, (UniCharCount)MAX_TEXT) : 0;
    if (e->textLength)
        memcpy(e->text, string, sizeof(UniChar) * e->textLength);
    e->hasText = e->textLength > 0;
}

int64_t CGEventGetIntegerValueField(CGEventRef event, CGEventField field)
{
    return is_event(event) ? [EV(event)->fields[@(field)] longLongValue] : 0;
}
void CGEventSetIntegerValueField(CGEventRef event, CGEventField field, int64_t value)
{
    if (!is_event(event))
        return;
    EV(event)->fields[@(field)] = @(value);
    if (field == kCGMouseEventButtonNumber)
        EV(event)->button = (CGMouseButton)value;
}
double CGEventGetDoubleValueField(CGEventRef event, CGEventField field)
{
    return is_event(event) ? [EV(event)->fields[@(field)] doubleValue] : 0;
}
void CGEventSetDoubleValueField(CGEventRef event, CGEventField field, double value)
{
    if (is_event(event))
        EV(event)->fields[@(field)] = @(value);
}

/* ---- posting keys through Strata ---------------------------------------------------------- */

/* A Mac virtual key code's Linux key number (AMacKeyCode, read backwards). */
static int linux_key(unsigned mac)
{
    static int16_t table[128];
    static BOOL made;
    if (!made) {
        for (int i = 0; i < 128; i++)
            table[i] = -1;
        for (int key = 1; key < 256; key++) {
            unsigned short code = AMacKeyCode((uint16_t)(key + 8));
            if (code < 128 && table[code] < 0)
                table[code] = (int16_t)key;
        }
        table[0] = 30;     /* A */
        made = YES;
    }
    return mac < 128 ? table[mac] : -1;
}

enum { KEY_LEFTCTRL = 29, KEY_LEFTSHIFT = 42, KEY_LEFTALT = 56, KEY_LEFTMETA = 125 };

/* The modifier keys a Mac event's flags hold down: Command is the Super
 * key, which freemac's Command key setting makes Command. */
static int modifier_keys(CGEventFlags flags, int *keys)
{
    int n = 0;
    if (flags & kCGEventFlagMaskCommand)
        keys[n++] = KEY_LEFTMETA;
    if (flags & kCGEventFlagMaskControl)
        keys[n++] = KEY_LEFTCTRL;
    if (flags & kCGEventFlagMaskAlternate)
        keys[n++] = KEY_LEFTALT;
    if (flags & kCGEventFlagMaskShift)
        keys[n++] = KEY_LEFTSHIFT;
    return n;
}

static BOOL is_modifier_key(int key)
{
    return key == KEY_LEFTCTRL || key == KEY_LEFTSHIFT || key == KEY_LEFTALT || key == KEY_LEFTMETA || key == 97 ||
           key == 54 || key == 100 || key == 126 || key == 58;
}

static int said_no_strata, said_not_allowed, said_layout, said_mouse, said_taps;

static BOOL press(int key, NSString *action)
{
    id reply = AWayfireCall(@"strata/press-key", @{@"key" : @(key), @"action" : action});
    NSString *error = AWayfireError(reply);
    if (error && [error hasPrefix:@"No such method"])
        say_once(&said_no_strata, "%s", "posting keys needs freemac's Strata in the compositor; the keys were dropped");
    return reply && !error;
}

/* Presses the modifiers, taps each key (with Shift too where shifted[i]),
 * and lets the modifiers go, whatever happened on the way. */
static BOOL press_keys(CGEventFlags flags, const int *keys, const BOOL *shifted, NSUInteger count)
{
    int mods[4];
    int n = modifier_keys(flags, mods);
    BOOL ok = YES;
    int held = 0;
    for (; held < n && ok; held++)
        ok = press(mods[held], @"press");
    if (!ok)
        held--;
    BOOL shift_held = (flags & kCGEventFlagMaskShift) != 0;
    for (NSUInteger i = 0; i < count && ok; i++) {
        BOOL shift = shifted && shifted[i] && !shift_held;
        if (shift && !(ok = press(KEY_LEFTSHIFT, @"press")))
            break;
        ok = press(keys[i], @"tap");
        if (shift)
            ok = press(KEY_LEFTSHIFT, @"release") && ok;
    }
    for (int i = held - 1; i >= 0; i--)
        if (!press(mods[i], @"release"))
            ok = NO;
    if (!ok)
        AWayfireCall(@"strata/release-keys", nil);  /* nothing of ours stays held */
    return ok;
}

/* The key and Shift that type a character on an English (US) keyboard. */
static BOOL us_key_for(UniChar c, int *key, BOOL *shift)
{
    static const char ansi[] = "asdfhgzxcv\0bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.\t `";
    static const char shifted_from[] = "!@#$%^&*()_+{}|:\"<>?~", shifted_to[] = "1234567890-=[]\\;',./`";
    *shift = NO;
    if (c == '\n')
        c = '\r';
    if (c >= 'A' && c <= 'Z') {
        c = (UniChar)(c - 'A' + 'a');
        *shift = YES;
    } else if (c < 128 && c && strchr(shifted_from, (int)c)) {
        c = (UniChar)shifted_to[strchr(shifted_from, (int)c) - shifted_from];
        *shift = YES;
    }
    for (unsigned mac = 0; mac < sizeof ansi - 1; mac++)
        if (ansi[mac] && (UniChar)(unsigned char)ansi[mac] == c) {
            *key = linux_key(mac);
            return *key > 0;
        }
    return NO;
}

static BOOL layout_is_us(void)
{
    id reply = AWayfireCall(@"strata/input-source", nil);
    id names = [reply isKindOfClass:[NSDictionary class]] ? reply[@"names"] : nil;
    if (![names isKindOfClass:[NSArray class]] || ![names count])
        return NO;
    NSUInteger i = [reply[@"index"] unsignedIntegerValue];
    id name = i < [names count] ? names[i] : nil;
    return [name isEqual:@"English (US)"];
}

static void post_key(ACGEvent *e)
{
    if (e->type != kCGEventKeyDown)
        return;     /* the key-down tapped it already; a key is never left held */
    if (e->hasText) {
        if (!layout_is_us()) {
            say_once(&said_layout, "%s", "text posted as key events is typed only with the English (US) keyboard "
                                         "layout; it was dropped");
            return;
        }
        int keys[MAX_TEXT];
        BOOL shifted[MAX_TEXT];
        for (UniCharCount i = 0; i < e->textLength; i++)
            if (!us_key_for(e->text[i], &keys[i], &shifted[i])) {
                say_once(&said_layout, "%s", "text posted as key events can hold only what an English (US) "
                                             "keyboard types; it was dropped");
                return;
            }
        press_keys(e->flags & ~(CGEventFlags)kCGEventFlagMaskShift, keys, shifted, e->textLength);
        return;
    }
    int key = linux_key((unsigned)[e->fields[@(kCGKeyboardEventKeycode)] unsignedIntValue]);
    if (key <= 0 || key > 255)
        return;
    CGEventFlags flags = e->flags;
    if (is_modifier_key(key))
        flags = 0;          /* a modifier on its own is tapped */
    press_keys(flags, &key, NULL, 1);
}

static BOOL may_post(void)
{
    if (AXIsProcessTrusted())
        return YES;
    say_once(&said_not_allowed, "%s may not press keys in other apps' windows (Dials > Privacy & Security > Control "
                                "Other Windows); the keys were dropped", [own_name() UTF8String]);
    return NO;
}

void CGEventPost(CGEventTapLocation tap, CGEventRef event)
{
    @autoreleasepool {
        if (!is_event(event))
            return;
        ACGEvent *e = EV(event);
        if (e->type == kCGEventKeyDown || e->type == kCGEventKeyUp || e->type == kCGEventFlagsChanged) {
            if (e->type != kCGEventKeyDown || !may_post())
                return;
            if (!AWayfireAvailable()) {
                say_once(&said_no_strata, "%s", "posting keys needs freemac's compositor; the keys were dropped");
                return;
            }
            post_key(e);
        } else if (e->type != kCGEventNull) {
            say_once(&said_mouse, "%s", "mouse and scroll events can't be posted to other apps (Wayland lets no app "
                                        "move the pointer or click for another); they were dropped");
        }
    }
}

/* The process whose window has the keyboard, or 0 when Wayfire can't say. */
static pid_t focused_pid(void)
{
    id reply = AWayfireCall(@"window-rules/get-focused-view", nil);
    id info = [reply isKindOfClass:[NSDictionary class]] ? reply[@"info"] : nil;
    if (![info isKindOfClass:[NSDictionary class]])
        return 0;
    return [view_pids()[@([info[@"id"] longLongValue])] intValue];
}

void CGEventPostToPid(pid_t pid, CGEventRef event)
{
    @autoreleasepool {
        if (!is_event(event))
            return;
        if (pid == getpid()) {
            NSEvent *ns = [NSEvent eventWithCGEvent:event];
            if (ns)
                [NSApp postEvent:ns atStart:NO];
            return;
        }
        if (!may_post() || !AWayfireAvailable())
            return;
        if (focused_pid() != pid)
            return;     /* keys reach only the window that has the keyboard */
        CGEventPost(kCGHIDEventTap, event);
    }
}

/* ---- event taps: never ------------------------------------------------------------------- */

CFMachPortRef CGEventTapCreate(CGEventTapLocation tap, CGEventTapPlacement place, CGEventTapOptions options,
                               CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo)
{
    say_once(&said_taps, "%s", "event taps aren't made (Wayland lets no app watch another app's keys and clicks); "
                               "CGEventTapCreate gave NULL");
    return NULL;
}
CFMachPortRef CGEventTapCreateForPid(pid_t pid, CGEventTapPlacement place, CGEventTapOptions options,
                                     CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo)
{
    return CGEventTapCreate(kCGSessionEventTap, place, options, eventsOfInterest, callback, userInfo);
}
void CGEventTapEnable(CFMachPortRef tap, bool enable) {}
bool CGEventTapIsEnabled(CFMachPortRef tap) { return false; }
void CGEventTapPostEvent(CGEventTapProxy proxy, CGEventRef event) {}
CGError CGGetEventTapList(uint32_t max, CGEventTapInformation *list, uint32_t *count)
{
    if (count)
        *count = 0;
    return kCGErrorSuccess;
}

bool CGPreflightPostEventAccess(void) { return AXIsProcessTrusted(); }
bool CGRequestPostEventAccess(void)
{
    NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt : @YES};
    return AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
}
bool CGPreflightListenEventAccess(void) { return false; }
bool CGRequestListenEventAccess(void) { return false; }

/* ---- event sources ------------------------------------------------------------------------ */

CFTypeID CGEventSourceGetTypeID(void) { return (CFTypeID)[ACGEventSource class]; }
CGEventSourceRef CGEventSourceCreate(CGEventSourceStateID stateID)
{
    if (stateID < kCGEventSourceStatePrivate || stateID > kCGEventSourceStateHIDSystemState)
        return NULL;
    ACGEventSource *s = [[ACGEventSource alloc] init];
    s->state = stateID;
    s->pixelsPerLine = 10;
    s->suppression = 0.25;
    s->keyboardType = 40;   /* an ANSI keyboard */
    return (CGEventSourceRef)s;
}
static ACGEventSource *as_source(CGEventSourceRef s)
{
    return s && [(id)s isKindOfClass:[ACGEventSource class]] ? (ACGEventSource *)s : (ACGEventSource *)NULL;
}
#define SRC(s) as_source(s)
CGEventSourceStateID CGEventSourceGetSourceStateID(CGEventSourceRef s)
{
    return SRC(s) ? SRC(s)->state : kCGEventSourceStatePrivate;
}
int64_t CGEventSourceGetUserData(CGEventSourceRef s) { return SRC(s) ? SRC(s)->userData : 0; }
void CGEventSourceSetUserData(CGEventSourceRef s, int64_t d)
{
    if (SRC(s))
        SRC(s)->userData = d;
}
CGEventSourceKeyboardType CGEventSourceGetKeyboardType(CGEventSourceRef s) { return SRC(s) ? SRC(s)->keyboardType : 0; }
void CGEventSourceSetKeyboardType(CGEventSourceRef s, CGEventSourceKeyboardType t)
{
    if (SRC(s))
        SRC(s)->keyboardType = t;
}
double CGEventSourceGetPixelsPerLine(CGEventSourceRef s) { return SRC(s) ? SRC(s)->pixelsPerLine : 0; }
void CGEventSourceSetPixelsPerLine(CGEventSourceRef s, double p)
{
    if (SRC(s) && p > 0)
        SRC(s)->pixelsPerLine = p;
}
CFTimeInterval CGEventSourceGetLocalEventsSuppressionInterval(CGEventSourceRef s)
{
    return SRC(s) ? SRC(s)->suppression : 0;
}
void CGEventSourceSetLocalEventsSuppressionInterval(CGEventSourceRef s, CFTimeInterval seconds)
{
    if (SRC(s) && seconds >= 0)
        SRC(s)->suppression = seconds;
}
CGEventFlags CGEventSourceFlagsState(CGEventSourceStateID stateID)
{
    return stateID == kCGEventSourceStatePrivate ? 0 : ([NSEvent modifierFlags] & 0x00ff0000);
}
bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key)
{
    if (stateID == kCGEventSourceStatePrivate)
        return false;
    CGEventFlags f = [NSEvent modifierFlags];
    switch (key) {
    case 0x37: case 0x36: return (f & kCGEventFlagMaskCommand) != 0;
    case 0x38: case 0x3C: return (f & kCGEventFlagMaskShift) != 0;
    case 0x3A: case 0x3D: return (f & kCGEventFlagMaskAlternate) != 0;
    case 0x3B: case 0x3E: return (f & kCGEventFlagMaskControl) != 0;
    default: return false;     /* Wayland doesn't say which other keys are down */
    }
}
bool CGEventSourceButtonState(CGEventSourceStateID stateID, CGMouseButton button)
{
    return stateID != kCGEventSourceStatePrivate && button < 32 && ([NSEvent pressedMouseButtons] >> button & 1);
}
CFTimeInterval CGEventSourceSecondsSinceLastEventType(CGEventSourceStateID stateID, CGEventType eventType)
{
    NSEvent *last = [NSApp currentEvent];
    if (!last || stateID == kCGEventSourceStatePrivate)
        return 1e9;
    return MAX(0, [[NSProcessInfo processInfo] systemUptime] - [last timestamp]);
}
uint32_t CGEventSourceCounterForEventType(CGEventSourceStateID stateID, CGEventType eventType) { return 0; }

/* ---- NSEvent and CGEvent ------------------------------------------------------------------- */

static NSString *characters_of(ACGEvent *e, BOOL ignoringModifiers)
{
    if (e->hasText && !ignoringModifiers)
        return [NSString stringWithCharacters:e->text length:e->textLength];
    static const char ansi[] = "asdfhgzxcv\0bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.\t `";
    unsigned mac = (unsigned)[e->fields[@(kCGKeyboardEventKeycode)] unsignedIntValue];
    if (e->hasText)
        return [NSString stringWithCharacters:e->text length:e->textLength];
    if (mac == 0x33)
        return [NSString stringWithFormat:@"%C", (unichar)NSDeleteCharacter];
    if (mac == 0x35)
        return @"\x1b";
    if (mac >= 0x7B && mac <= 0x7E) {
        static const unichar arrows[] = {NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSDownArrowFunctionKey,
                                         NSUpArrowFunctionKey};
        return [NSString stringWithCharacters:&arrows[mac - 0x7B] length:1];
    }
    if (mac < sizeof ansi - 1 && ansi[mac]) {
        unichar c = (unsigned char)ansi[mac];
        if (!ignoringModifiers && (e->flags & kCGEventFlagMaskShift) && c >= 'a' && c <= 'z')
            c = (unichar)(c - 'a' + 'A');
        return [NSString stringWithCharacters:&c length:1];
    }
    return @"";
}

static NSEventType ns_type(CGEventType t)
{
    switch (t) {
    case kCGEventLeftMouseDown: return NSEventTypeLeftMouseDown;
    case kCGEventLeftMouseUp: return NSEventTypeLeftMouseUp;
    case kCGEventRightMouseDown: return NSEventTypeRightMouseDown;
    case kCGEventRightMouseUp: return NSEventTypeRightMouseUp;
    case kCGEventMouseMoved: return NSEventTypeMouseMoved;
    case kCGEventLeftMouseDragged: return NSEventTypeLeftMouseDragged;
    case kCGEventRightMouseDragged: return NSEventTypeRightMouseDragged;
    case kCGEventKeyDown: return NSEventTypeKeyDown;
    case kCGEventKeyUp: return NSEventTypeKeyUp;
    case kCGEventFlagsChanged: return NSEventTypeFlagsChanged;
    case kCGEventScrollWheel: return NSEventTypeScrollWheel;
    case kCGEventOtherMouseDown: return NSEventTypeOtherMouseDown;
    case kCGEventOtherMouseUp: return NSEventTypeOtherMouseUp;
    case kCGEventOtherMouseDragged: return NSEventTypeOtherMouseDragged;
    default: return 0;
    }
}

static CGEventType cg_type(NSEventType t)
{
    for (CGEventType c = 1; c <= kCGEventOtherMouseDragged; c++)
        if (ns_type(c) == t)
            return c;
    return kCGEventNull;
}

@implementation NSEvent (NSEventCGEvent)

+ (NSEvent *)eventWithCGEvent:(CGEventRef)cgEvent
{
    if (!is_event(cgEvent))
        return nil;
    ACGEvent *e = EV(cgEvent);
    NSEventType type = ns_type(e->type);
    if (!type)
        return nil;
    NSEventModifierFlags flags = (NSEventModifierFlags)(e->flags & 0x00ff0000);
    NSTimeInterval time = (NSTimeInterval)e->timestamp / 1e9;
    NSWindow *key = AKeyWindow();
    NSEvent *out;
    if (type == NSEventTypeKeyDown || type == NSEventTypeKeyUp || type == NSEventTypeFlagsChanged) {
        out = [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:time
                           windowNumber:[key windowNumber] context:nil characters:characters_of(e, NO)
            charactersIgnoringModifiers:characters_of(e, YES)
                              isARepeat:[e->fields[@(kCGKeyboardEventAutorepeat)] boolValue]
                                keyCode:(unsigned short)[e->fields[@(kCGKeyboardEventKeycode)] unsignedIntValue]];
    } else if (type == NSEventTypeScrollWheel) {
        return nil;     /* Ferry's scroll events come from GTK only */
    } else {
        /* the screen point, as AppKit has it, then in the window's terms */
        NSRect main = AScreenFrame(NO);
        NSPoint screen = NSMakePoint(e->location.x + main.origin.x, NSMaxY(main) - e->location.y);
        NSWindow *w = nil;
        for (NSWindow *c in AAllWindows())
            if (!w && [c isVisible] && NSPointInRect(screen, [c frame]))
                w = c;
        NSPoint at = w ? NSMakePoint(screen.x - [w frame].origin.x, screen.y - [w frame].origin.y) : screen;
        NSInteger clicks = [e->fields[@(kCGMouseEventClickState)] integerValue];
        out = [NSEvent mouseEventWithType:type location:at modifierFlags:flags timestamp:time
                             windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:clicks
                                 pressure:(type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown ||
                                           type == NSEventTypeOtherMouseDown)
                                              ? 1
                                              : 0];
    }
    return out;
}

- (CGEventRef)CGEvent
{
    static char key;
    id kept = objc_getAssociatedObject(self, &key);
    if (kept)
        return (CGEventRef)kept;
    ACGEvent *e = new_event(NULL, cg_type([self type]));
    e->flags = [self modifierFlags] & 0x00ff0000;
    e->timestamp = (CGEventTimestamp)([self timestamp] * 1e9);
    e->nsEvent = self;
    NSEventType t = [self type];
    if (t == NSEventTypeKeyDown || t == NSEventTypeKeyUp || t == NSEventTypeFlagsChanged) {
        e->fields[@(kCGKeyboardEventKeycode)] = @([self keyCode]);
        if (t != NSEventTypeFlagsChanged)
            e->fields[@(kCGKeyboardEventAutorepeat)] = @([self isARepeat]);
    } else {
        NSWindow *w = [self window];
        NSPoint p = [self locationInWindow];
        if (w)
            p = NSMakePoint(p.x + [w frame].origin.x, p.y + [w frame].origin.y);
        NSRect main = AScreenFrame(NO);
        e->location = CGPointMake(p.x - main.origin.x, NSMaxY(main) - p.y);
        if (t != NSEventTypeScrollWheel && t != NSEventTypeMouseMoved && t != NSEventTypeMouseEntered &&
            t != NSEventTypeMouseExited) {
            e->fields[@(kCGMouseEventClickState)] = @([self clickCount]);
            e->fields[@(kCGMouseEventButtonNumber)] = @([self buttonNumber]);
            e->button = (CGMouseButton)[self buttonNumber];
        }
    }
    objc_setAssociatedObject(self, &key, e, OBJC_ASSOCIATION_RETAIN);
    [e release];
    return (CGEventRef)e;
}

@end
