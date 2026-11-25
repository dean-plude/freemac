/* SPDX-License-Identifier: GPL-3.0-or-later
 * Quartz Display Services, from Apple's public documentation: the list of
 * displays, their bounds and modes. In Ferry they are the screens AppKit's
 * NSScreen sees (appkit/CGDirectDisplay.m), so a display's ID is the one
 * its NSScreen's deviceDescription gives as NSScreenNumber. Displays can't
 * be captured, mirrored or reconfigured from a program. */
#ifndef FERRY_CGDIRECTDISPLAY_H
#define FERRY_CGDIRECTDISPLAY_H
#include <CoreGraphics/CGEvent.h>
#include <mach/boolean.h>
/* as on a Mac, the display calls bring IOKit's registry types (freemac 1.232) */
#include <IOKit/IOKitLib.h>

typedef uint32_t CGDirectDisplayID;
typedef uint32_t CGOpenGLDisplayMask;
typedef double CGRefreshRate;
typedef uint32_t CGDisplayCount;
typedef CGError CGDisplayErr;
typedef struct CF_BRIDGED_TYPE(id) CGDisplayMode *CGDisplayModeRef;
typedef uint32_t CGCaptureOptions;
typedef struct _CGDisplayConfigRef *CGDisplayConfigRef;

#define kCGNullDirectDisplay ((CGDirectDisplayID)0)
#define kCGDirectMainDisplay CGMainDisplayID()

typedef uint32_t CGDisplayChangeSummaryFlags;
enum {
    kCGDisplayBeginConfigurationFlag = 1 << 0,
    kCGDisplayMovedFlag = 1 << 1,
    kCGDisplaySetMainFlag = 1 << 2,
    kCGDisplaySetModeFlag = 1 << 3,
    kCGDisplayAddFlag = 1 << 4,
    kCGDisplayRemoveFlag = 1 << 5,
    kCGDisplayEnabledFlag = 1 << 8,
    kCGDisplayDisabledFlag = 1 << 9,
    kCGDisplayMirrorFlag = 1 << 10,
    kCGDisplayUnMirrorFlag = 1 << 11,
    kCGDisplayDesktopShapeChangedFlag = 1 << 12,
};
typedef void (*CGDisplayReconfigurationCallBack)(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo);

extern const CFStringRef kCGDisplayShowDuplicateLowResolutionModes;

CGDirectDisplayID CGMainDisplayID(void);
CGError CGGetOnlineDisplayList(uint32_t maxDisplays, CGDirectDisplayID *onlineDisplays, uint32_t *displayCount);
CGError CGGetActiveDisplayList(uint32_t maxDisplays, CGDirectDisplayID *activeDisplays, uint32_t *displayCount);
CGError CGGetDisplaysWithRect(CGRect rect, uint32_t maxDisplays, CGDirectDisplayID *displays, uint32_t *matchingDisplayCount);
CGError CGGetDisplaysWithPoint(CGPoint point, uint32_t maxDisplays, CGDirectDisplayID *displays, uint32_t *matchingDisplayCount);
CGError CGGetDisplaysWithOpenGLDisplayMask(CGOpenGLDisplayMask mask, uint32_t maxDisplays, CGDirectDisplayID *displays, uint32_t *matchingDisplayCount);
CGDirectDisplayID CGOpenGLDisplayMaskToDisplayID(CGOpenGLDisplayMask mask);
CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID display);
CGRect CGDisplayBounds(CGDirectDisplayID display);
size_t CGDisplayPixelsWide(CGDirectDisplayID display);
size_t CGDisplayPixelsHigh(CGDirectDisplayID display);
CGSize CGDisplayScreenSize(CGDirectDisplayID display);
double CGDisplayRotation(CGDirectDisplayID display);
boolean_t CGDisplayIsActive(CGDirectDisplayID display);
boolean_t CGDisplayIsAsleep(CGDirectDisplayID display);
boolean_t CGDisplayIsOnline(CGDirectDisplayID display);
boolean_t CGDisplayIsMain(CGDirectDisplayID display);
boolean_t CGDisplayIsBuiltin(CGDirectDisplayID display);
boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID display);
boolean_t CGDisplayIsAlwaysInMirrorSet(CGDirectDisplayID display);
boolean_t CGDisplayIsInHWMirrorSet(CGDirectDisplayID display);
boolean_t CGDisplayUsesOpenGLAcceleration(CGDirectDisplayID display);
boolean_t CGDisplayIsStereo(CGDirectDisplayID display);
CGDirectDisplayID CGDisplayMirrorsDisplay(CGDirectDisplayID display);
CGDirectDisplayID CGDisplayPrimaryDisplay(CGDirectDisplayID display);
uint32_t CGDisplayUnitNumber(CGDirectDisplayID display);
uint32_t CGDisplayVendorNumber(CGDirectDisplayID display);
uint32_t CGDisplayModelNumber(CGDirectDisplayID display);
uint32_t CGDisplaySerialNumber(CGDirectDisplayID display);
CGColorSpaceRef CGDisplayCopyColorSpace(CGDirectDisplayID display);

CFTypeID CGDisplayModeGetTypeID(void);
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID display);
CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID display, CFDictionaryRef options);
CGError CGDisplaySetDisplayMode(CGDirectDisplayID display, CGDisplayModeRef mode, CFDictionaryRef options);
size_t CGDisplayModeGetWidth(CGDisplayModeRef mode);
size_t CGDisplayModeGetHeight(CGDisplayModeRef mode);
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef mode);
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef mode);
double CGDisplayModeGetRefreshRate(CGDisplayModeRef mode);
uint32_t CGDisplayModeGetIOFlags(CGDisplayModeRef mode);
int32_t CGDisplayModeGetIODisplayModeID(CGDisplayModeRef mode);
bool CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef mode);
CGDisplayModeRef CGDisplayModeRetain(CGDisplayModeRef mode);
void CGDisplayModeRelease(CGDisplayModeRef mode);

CGError CGDisplayRegisterReconfigurationCallback(CGDisplayReconfigurationCallBack callback, void *userInfo);
CGError CGDisplayRemoveReconfigurationCallback(CGDisplayReconfigurationCallBack callback, void *userInfo);

CGError CGDisplayCapture(CGDirectDisplayID display);
CGError CGDisplayRelease(CGDirectDisplayID display);
CGError CGCaptureAllDisplays(void);
CGError CGReleaseAllDisplays(void);
boolean_t CGDisplayIsCaptured(CGDirectDisplayID display);
CGError CGDisplayHideCursor(CGDirectDisplayID display);
CGError CGDisplayShowCursor(CGDirectDisplayID display);
CGError CGDisplayMoveCursorToPoint(CGDirectDisplayID display, CGPoint point);
CGImageRef CGDisplayCreateImage(CGDirectDisplayID display);
CGImageRef CGDisplayCreateImageForRect(CGDirectDisplayID display, CGRect rect);

/* the UUID a Mac gives each display (ColorSync's call, kept here as there) */
CFUUIDRef CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID displayID);
CGDirectDisplayID CGDisplayGetDisplayIDFromUUID(CFUUIDRef uuid);

#endif
