/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Quartz Window Services (freemac 1.220, Ferry 0.44.0), written
 * for freemac from Apple's public documentation of CGWindowList...; not
 * Apple's header. Served from AppKit's file (appkit/CGServices.m).
 *
 * An app always sees its own windows. Other apps' windows come from
 * freemac's compositor (Wayfire, with Strata saying which program each
 * belongs to) and are listed only once the user has allowed the app to
 * control other windows (Dials > Privacy & Security). A window's number is
 * then Wayfire's view number with bit 30 set, so it never meets one of the
 * app's own window numbers. Pictures are taken of the app's own windows
 * only: freemac doesn't let apps record the screen. */
#ifndef _FERRY_CGWINDOW_H_
#define _FERRY_CGWINDOW_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>

__FERRY_BEGIN

typedef uint32_t CGWindowID;
#define kCGNullWindowID ((CGWindowID)0)

typedef uint32_t CGWindowListOption;
enum {
    kCGWindowListOptionAll = 0, kCGWindowListOptionOnScreenOnly = (1 << 0),
    kCGWindowListOptionOnScreenAboveWindow = (1 << 1), kCGWindowListOptionOnScreenBelowWindow = (1 << 2),
    kCGWindowListOptionIncludingWindow = (1 << 3), kCGWindowListExcludeDesktopElements = (1 << 4),
};
typedef uint32_t CGWindowImageOption;
enum {
    kCGWindowImageDefault = 0, kCGWindowImageBoundsIgnoreFraming = (1 << 0),
    kCGWindowImageShouldBeOpaque = (1 << 1), kCGWindowImageOnlyShadows = (1 << 2),
    kCGWindowImageBestResolution = (1 << 3), kCGWindowImageNominalResolution = (1 << 4),
};
typedef uint32_t CGWindowSharingType;
enum { kCGWindowSharingNone = 0, kCGWindowSharingReadOnly = 1, kCGWindowSharingReadWrite = 2 };
typedef uint32_t CGWindowBackingType;
enum { kCGBackingStoreRetained = 0, kCGBackingStoreNonretained = 1, kCGBackingStoreBuffered = 2 };

typedef int32_t CGWindowLevel;
typedef int32_t CGWindowLevelKey;
enum {
    kCGBaseWindowLevelKey = 0, kCGMinimumWindowLevelKey, kCGDesktopWindowLevelKey, kCGBackstopMenuLevelKey,
    kCGNormalWindowLevelKey, kCGFloatingWindowLevelKey, kCGTornOffMenuWindowLevelKey, kCGDockWindowLevelKey,
    kCGMainMenuWindowLevelKey, kCGStatusWindowLevelKey, kCGModalPanelWindowLevelKey, kCGPopUpMenuWindowLevelKey,
    kCGDraggingWindowLevelKey, kCGScreenSaverWindowLevelKey, kCGMaximumWindowLevelKey, kCGOverlayWindowLevelKey,
    kCGHelpWindowLevelKey, kCGUtilityWindowLevelKey, kCGDesktopIconWindowLevelKey, kCGCursorWindowLevelKey,
    kCGAssistiveTechHighWindowLevelKey, kCGNumberOfWindowLevelKeys,
};
CGWindowLevel CGWindowLevelForKey(CGWindowLevelKey key);
#define kCGNormalWindowLevel CGWindowLevelForKey(kCGNormalWindowLevelKey)
#define kCGFloatingWindowLevel CGWindowLevelForKey(kCGFloatingWindowLevelKey)
#define kCGStatusWindowLevel CGWindowLevelForKey(kCGStatusWindowLevelKey)
#define kCGMainMenuWindowLevel CGWindowLevelForKey(kCGMainMenuWindowLevelKey)
#define kCGPopUpMenuWindowLevel CGWindowLevelForKey(kCGPopUpMenuWindowLevelKey)
#define kCGModalPanelWindowLevel CGWindowLevelForKey(kCGModalPanelWindowLevelKey)
#define kCGScreenSaverWindowLevel CGWindowLevelForKey(kCGScreenSaverWindowLevelKey)
#define kCGDesktopWindowLevel CGWindowLevelForKey(kCGDesktopWindowLevelKey)
/* the rest of the levels (freemac 1.225, Ferry 0.49.0) */
#define kCGBaseWindowLevel CGWindowLevelForKey(kCGBaseWindowLevelKey)
#define kCGMinimumWindowLevel CGWindowLevelForKey(kCGMinimumWindowLevelKey)
#define kCGBackstopMenuLevel CGWindowLevelForKey(kCGBackstopMenuLevelKey)
#define kCGTornOffMenuWindowLevel CGWindowLevelForKey(kCGTornOffMenuWindowLevelKey)
#define kCGDockWindowLevel CGWindowLevelForKey(kCGDockWindowLevelKey)
#define kCGDraggingWindowLevel CGWindowLevelForKey(kCGDraggingWindowLevelKey)
#define kCGMaximumWindowLevel CGWindowLevelForKey(kCGMaximumWindowLevelKey)
#define kCGOverlayWindowLevel CGWindowLevelForKey(kCGOverlayWindowLevelKey)
#define kCGHelpWindowLevel CGWindowLevelForKey(kCGHelpWindowLevelKey)
#define kCGUtilityWindowLevel CGWindowLevelForKey(kCGUtilityWindowLevelKey)
#define kCGDesktopIconWindowLevel CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)
#define kCGCursorWindowLevel CGWindowLevelForKey(kCGCursorWindowLevelKey)
#define kCGAssistiveTechHighWindowLevel CGWindowLevelForKey(kCGAssistiveTechHighWindowLevelKey)

/* The keys of a window's description. */
extern const CFStringRef kCGWindowNumber;               /* CFNumber, the window's CGWindowID */
extern const CFStringRef kCGWindowStoreType;            /* CFNumber, a CGWindowBackingType */
extern const CFStringRef kCGWindowLayer;                /* CFNumber, its level */
extern const CFStringRef kCGWindowBounds;               /* a CGRect's dictionary, from the main display's top left */
extern const CFStringRef kCGWindowSharingState;         /* CFNumber, a CGWindowSharingType */
extern const CFStringRef kCGWindowAlpha;                /* CFNumber */
extern const CFStringRef kCGWindowOwnerPID;             /* CFNumber */
extern const CFStringRef kCGWindowMemoryUsage;          /* CFNumber */
extern const CFStringRef kCGWindowWorkspace;            /* never given */
extern const CFStringRef kCGWindowOwnerName;            /* CFString */
extern const CFStringRef kCGWindowName;                 /* CFString, its title */
extern const CFStringRef kCGWindowIsOnscreen;           /* CFBoolean */
extern const CFStringRef kCGWindowBackingLocationVideoMemory; /* CFBoolean */

CFArrayRef CGWindowListCopyWindowInfo(CGWindowListOption option, CGWindowID relativeToWindow);
/* The windows' numbers, as CGWindowIDs stored straight in the array. */
CFArrayRef CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow);
CFArrayRef CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray);
/* A picture of this app's own window (kCGWindowListOptionIncludingWindow
 * with its number); NULL for anything else. */
struct CGImage;
struct CGImage *CGWindowListCreateImage(CGRect screenBounds, CGWindowListOption listOption, CGWindowID windowID,
                                        CGWindowImageOption imageOption);
struct CGImage *CGWindowListCreateImageFromArray(CGRect screenBounds, CFArrayRef windowArray,
                                                 CGWindowImageOption imageOption);
/* Screen recording is never allowed. */
bool CGPreflightScreenCaptureAccess(void);
bool CGRequestScreenCaptureAccess(void);

__FERRY_END

#endif
