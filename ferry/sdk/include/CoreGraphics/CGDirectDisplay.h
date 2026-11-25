/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Quartz Display Services (freemac 1.NEXT, Ferry 0.NEXT), the
 * calls that list the displays and fade them, written for freemac from
 * Apple's public documentation; not Apple's header. Served from AppKit's
 * file (appkit/CGDisplay.m). A display's number is its NSScreen's
 * NSScreenNumber. freemac doesn't let an app take over or reconfigure a
 * display, so a fade is drawn as a window over the screens. */
#ifndef _FERRY_CGDIRECTDISPLAY_H_
#define _FERRY_CGDIRECTDISPLAY_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>
#include <mach/boolean.h>
#include <CoreGraphics/CGEvent.h> /* CGError */

__FERRY_BEGIN

typedef uint32_t CGDirectDisplayID;
#define kCGNullDirectDisplay ((CGDirectDisplayID)0)

CGDirectDisplayID CGMainDisplayID(void);
CGError CGGetOnlineDisplayList(uint32_t maxDisplays, CGDirectDisplayID *onlineDisplays, uint32_t *displayCount);
CGError CGGetActiveDisplayList(uint32_t maxDisplays, CGDirectDisplayID *activeDisplays, uint32_t *displayCount);
CGError CGGetDisplaysWithPoint(CGPoint point, uint32_t maxDisplays, CGDirectDisplayID *displays,
                               uint32_t *matchingDisplayCount);
CGRect CGDisplayBounds(CGDirectDisplayID display);
size_t CGDisplayPixelsWide(CGDirectDisplayID display);
size_t CGDisplayPixelsHigh(CGDirectDisplayID display);
boolean_t CGDisplayIsMain(CGDirectDisplayID display);
boolean_t CGDisplayIsActive(CGDirectDisplayID display);
boolean_t CGDisplayIsOnline(CGDirectDisplayID display);
boolean_t CGDisplayIsBuiltin(CGDirectDisplayID display);
boolean_t CGDisplayUsesOpenGLAcceleration(CGDirectDisplayID display);

/* fades */
typedef uint32_t CGDisplayFadeReservationToken;
typedef float CGDisplayFadeInterval;
typedef float CGDisplayReservationInterval;
typedef float CGDisplayBlendFraction;
#define kCGDisplayFadeReservationInvalidToken (0)
#define kCGDisplayBlendNormal (0.0f)
#define kCGDisplayBlendSolidColor (1.0f)
#define kCGMaxDisplayReservationInterval (15.0f)
CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval seconds,
                                        CGDisplayFadeReservationToken *token);
CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken token);
CGError CGDisplayFade(CGDisplayFadeReservationToken token, CGDisplayFadeInterval duration,
                      CGDisplayBlendFraction startBlend, CGDisplayBlendFraction endBlend, float redBlend,
                      float greenBlend, float blueBlend, boolean_t synchronous);
boolean_t CGDisplayFadeOperationInProgress(void);

__FERRY_END
#endif
