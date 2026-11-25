/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Quartz Event Services (freemac 1.220, Ferry 0.44.0), written
 * for freemac from Apple's public documentation of CGEvent, CGEventSource
 * and CGEventTap; not Apple's header. The calls are served from AppKit's
 * file (appkit/CGServices.m), beside the Accessibility API, and need the
 * same say from the user before they reach other apps: Dials > Privacy &
 * Security > Control Other Windows.
 *
 * On freemac a posted key goes through Strata, freemac's compositor
 * plugin, to the window that has the keyboard, as if typed on the
 * computer's own keyboard. Mouse events can't be posted, and event taps
 * can't be made: Wayland lets no app watch another app's keys. */
#ifndef _FERRY_CGEVENT_H_
#define _FERRY_CGEVENT_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

__FERRY_BEGIN

typedef int32_t CGError;
enum {
    kCGErrorSuccess = 0, kCGErrorFailure = 1000, kCGErrorIllegalArgument = 1001, kCGErrorInvalidConnection = 1002,
    kCGErrorInvalidContext = 1003, kCGErrorCannotComplete = 1004, kCGErrorNotImplemented = 1006,
    kCGErrorRangeCheck = 1007, kCGErrorTypeCheck = 1008, kCGErrorInvalidOperation = 1010,
    kCGErrorNoneAvailable = 1011,
};

typedef struct __CGEvent *CGEventRef;
typedef struct __CGEventSource *CGEventSourceRef;
typedef struct __CGEventTapProxy *CGEventTapProxy;
#ifndef _FERRY_CFMACHPORT_
#define _FERRY_CFMACHPORT_
/* What an event tap is handed out as; Ferry never makes one. */
typedef struct __CFMachPort *CFMachPortRef;
#endif

typedef uint16_t CGKeyCode;
typedef uint16_t CGCharCode;
typedef uint64_t CGEventTimestamp;
typedef uint64_t CGEventMask;
typedef uint64_t CGEventFlags;
typedef uint32_t CGEventErr;
#ifndef _FERRY_UNICHARCOUNT_
#define _FERRY_UNICHARCOUNT_
typedef unsigned long UniCharCount;
#endif

typedef uint32_t CGEventType;
enum {
    kCGEventNull = 0, kCGEventLeftMouseDown = 1, kCGEventLeftMouseUp = 2, kCGEventRightMouseDown = 3,
    kCGEventRightMouseUp = 4, kCGEventMouseMoved = 5, kCGEventLeftMouseDragged = 6, kCGEventRightMouseDragged = 7,
    kCGEventKeyDown = 10, kCGEventKeyUp = 11, kCGEventFlagsChanged = 12, kCGEventScrollWheel = 22,
    kCGEventTabletPointer = 23, kCGEventTabletProximity = 24, kCGEventOtherMouseDown = 25,
    kCGEventOtherMouseUp = 26, kCGEventOtherMouseDragged = 27,
    kCGEventTapDisabledByTimeout = 0xFFFFFFFE, kCGEventTapDisabledByUserInput = 0xFFFFFFFF,
};
#define CGEventMaskBit(eventType) ((CGEventMask)1 << (eventType))
#define kCGEventMaskForAllEvents (~(CGEventMask)0)

enum {
    kCGEventFlagMaskAlphaShift = 0x00010000, kCGEventFlagMaskShift = 0x00020000,
    kCGEventFlagMaskControl = 0x00040000, kCGEventFlagMaskAlternate = 0x00080000,
    kCGEventFlagMaskCommand = 0x00100000, kCGEventFlagMaskNumericPad = 0x00200000,
    kCGEventFlagMaskHelp = 0x00400000, kCGEventFlagMaskSecondaryFn = 0x00800000,
    kCGEventFlagMaskNonCoalesced = 0x00000100,
};

typedef uint32_t CGMouseButton;
enum { kCGMouseButtonLeft = 0, kCGMouseButtonRight = 1, kCGMouseButtonCenter = 2 };
typedef uint32_t CGScrollEventUnit;
enum { kCGScrollEventUnitPixel = 0, kCGScrollEventUnitLine = 1 };
typedef uint32_t CGEventTapLocation;
enum { kCGHIDEventTap = 0, kCGSessionEventTap, kCGAnnotatedSessionEventTap };
typedef uint32_t CGEventTapPlacement;
enum { kCGHeadInsertEventTap = 0, kCGTailAppendEventTap };
typedef uint32_t CGEventTapOptions;
enum { kCGEventTapOptionDefault = 0, kCGEventTapOptionListenOnly = 1 };
typedef int32_t CGEventSourceStateID;
enum {
    kCGEventSourceStatePrivate = -1, kCGEventSourceStateCombinedSessionState = 0,
    kCGEventSourceStateHIDSystemState = 1,
};
typedef uint32_t CGEventSourceKeyboardType;
#define kCGAnyInputEventType ((CGEventType)(~0))

typedef uint32_t CGEventField;
enum {
    kCGMouseEventNumber = 0, kCGMouseEventClickState = 1, kCGMouseEventPressure = 2,
    kCGMouseEventButtonNumber = 3, kCGMouseEventDeltaX = 4, kCGMouseEventDeltaY = 5,
    kCGMouseEventInstantMouser = 6, kCGMouseEventSubtype = 7, kCGKeyboardEventAutorepeat = 8,
    kCGKeyboardEventKeycode = 9, kCGKeyboardEventKeyboardType = 10, kCGScrollWheelEventDeltaAxis1 = 11,
    kCGScrollWheelEventDeltaAxis2 = 12, kCGScrollWheelEventDeltaAxis3 = 13,
    kCGScrollWheelEventInstantMouser = 14, kCGEventTargetProcessSerialNumber = 39,
    kCGEventTargetUnixProcessID = 40, kCGEventSourceUnixProcessID = 41, kCGEventSourceUserData = 42,
    kCGEventSourceUserID = 43, kCGEventSourceGroupID = 44, kCGEventSourceStateID = 45,
    kCGScrollWheelEventIsContinuous = 88, kCGMouseEventWindowUnderMousePointer = 91,
    kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent = 92,
    kCGScrollWheelEventFixedPtDeltaAxis1 = 93, kCGScrollWheelEventFixedPtDeltaAxis2 = 94,
    kCGScrollWheelEventFixedPtDeltaAxis3 = 95, kCGScrollWheelEventPointDeltaAxis1 = 96,
    kCGScrollWheelEventPointDeltaAxis2 = 97, kCGScrollWheelEventPointDeltaAxis3 = 98,
    kCGScrollWheelEventScrollPhase = 99, kCGScrollWheelEventScrollCount = 100,
    kCGScrollWheelEventMomentumPhase = 123, kCGEventUnacceleratedPointerMovementX = 170,
    kCGEventUnacceleratedPointerMovementY = 171,
};

typedef CGEventRef (*CGEventTapCallBack)(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo);
typedef struct __CGEventTapInformation {
    uint32_t eventTapID;
    CGEventTapLocation tapPoint;
    CGEventTapOptions options;
    CGEventMask eventsOfInterest;
    pid_t tappingProcess;
    pid_t processBeingTapped;
    bool enabled;
    float minUsecLatency, avgUsecLatency, maxUsecLatency;
} CGEventTapInformation;

/* ---- events ------------------------------------------------------------------- */

CFTypeID CGEventGetTypeID(void);
CGEventRef CGEventCreate(CGEventSourceRef source);
CGEventRef CGEventCreateKeyboardEvent(CGEventSourceRef source, CGKeyCode virtualKey, bool keyDown);
CGEventRef CGEventCreateMouseEvent(CGEventSourceRef source, CGEventType mouseType, CGPoint mouseCursorPosition,
                                   CGMouseButton mouseButton);
CGEventRef CGEventCreateScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount,
                                         int32_t wheel1, ...);
CGEventRef CGEventCreateScrollWheelEvent2(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount,
                                          int32_t wheel1, int32_t wheel2, int32_t wheel3);
CGEventRef CGEventCreateCopy(CGEventRef event);
CGEventSourceRef CGEventCreateSourceFromEvent(CGEventRef event);
void CGEventSetSource(CGEventRef event, CGEventSourceRef source);
CGEventType CGEventGetType(CGEventRef event);
void CGEventSetType(CGEventRef event, CGEventType type);
CGEventTimestamp CGEventGetTimestamp(CGEventRef event);
void CGEventSetTimestamp(CGEventRef event, CGEventTimestamp timestamp);
CGPoint CGEventGetLocation(CGEventRef event);
CGPoint CGEventGetUnflippedLocation(CGEventRef event);
void CGEventSetLocation(CGEventRef event, CGPoint location);
CGEventFlags CGEventGetFlags(CGEventRef event);
void CGEventSetFlags(CGEventRef event, CGEventFlags flags);
void CGEventKeyboardGetUnicodeString(CGEventRef event, UniCharCount maxStringLength, UniCharCount *actualStringLength,
                                     UniChar *unicodeString);
void CGEventKeyboardSetUnicodeString(CGEventRef event, UniCharCount stringLength, const UniChar *unicodeString);
int64_t CGEventGetIntegerValueField(CGEventRef event, CGEventField field);
void CGEventSetIntegerValueField(CGEventRef event, CGEventField field, int64_t value);
double CGEventGetDoubleValueField(CGEventRef event, CGEventField field);
void CGEventSetDoubleValueField(CGEventRef event, CGEventField field, double value);

/* A key event goes to the window that has the keyboard, once the user has
 * allowed the app to control other windows; anything else is dropped. */
void CGEventPost(CGEventTapLocation tap, CGEventRef event);
/* To the app with that process id: this app's own events always reach it;
 * another app's only while its window has the keyboard. */
void CGEventPostToPid(pid_t pid, CGEventRef event);

/* Event taps: never made (NULL), as on a Mac that hasn't allowed the app. */
CFMachPortRef CGEventTapCreate(CGEventTapLocation tap, CGEventTapPlacement place, CGEventTapOptions options,
                               CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo);
CFMachPortRef CGEventTapCreateForPid(pid_t pid, CGEventTapPlacement place, CGEventTapOptions options,
                                     CGEventMask eventsOfInterest, CGEventTapCallBack callback, void *userInfo);
void CGEventTapEnable(CFMachPortRef tap, bool enable);
bool CGEventTapIsEnabled(CFMachPortRef tap);
void CGEventTapPostEvent(CGEventTapProxy proxy, CGEventRef event);
CGError CGGetEventTapList(uint32_t maxNumberOfTaps, CGEventTapInformation *tapList, uint32_t *eventTapCount);

/* Whether the app may post events (the user's say on controlling other
 * windows), and asking for it; listening is never allowed. */
bool CGPreflightPostEventAccess(void);
bool CGRequestPostEventAccess(void);
bool CGPreflightListenEventAccess(void);
bool CGRequestListenEventAccess(void);

/* ---- event sources ------------------------------------------------------------ */

CFTypeID CGEventSourceGetTypeID(void);
CGEventSourceRef CGEventSourceCreate(CGEventSourceStateID stateID);
CGEventSourceStateID CGEventSourceGetSourceStateID(CGEventSourceRef source);
int64_t CGEventSourceGetUserData(CGEventSourceRef source);
void CGEventSourceSetUserData(CGEventSourceRef source, int64_t userData);
CGEventSourceKeyboardType CGEventSourceGetKeyboardType(CGEventSourceRef source);
void CGEventSourceSetKeyboardType(CGEventSourceRef source, CGEventSourceKeyboardType keyboardType);
double CGEventSourceGetPixelsPerLine(CGEventSourceRef source);
void CGEventSourceSetPixelsPerLine(CGEventSourceRef source, double pixelsPerLine);
CFTimeInterval CGEventSourceGetLocalEventsSuppressionInterval(CGEventSourceRef source);
void CGEventSourceSetLocalEventsSuppressionInterval(CGEventSourceRef source, CFTimeInterval seconds);
/* This app's own idea of the keyboard and mouse: Wayland tells an app
 * about keys only while one of its windows has the keyboard. */
CGEventFlags CGEventSourceFlagsState(CGEventSourceStateID stateID);
bool CGEventSourceKeyState(CGEventSourceStateID stateID, CGKeyCode key);
bool CGEventSourceButtonState(CGEventSourceStateID stateID, CGMouseButton button);
CFTimeInterval CGEventSourceSecondsSinceLastEventType(CGEventSourceStateID stateID, CGEventType eventType);
uint32_t CGEventSourceCounterForEventType(CGEventSourceStateID stateID, CGEventType eventType);

__FERRY_END

#endif
