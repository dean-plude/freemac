/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the few Carbon calls Cocoa apps still make, written from
 * Apple's public documentation (freemac 1.215, Ferry 0.41.0): the Carbon
 * Event Manager as far as global hotkeys need it, and the Mac's virtual
 * key codes and modifier bits. Served from AppKit's file. */
#ifndef _FERRY_CARBON_H_
#define _FERRY_CARBON_H_
#include <ApplicationServices/ApplicationServices.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t OSStatus;
typedef uint32_t OSType;
typedef uint32_t OptionBits;
typedef uint32_t UInt32;
typedef uint32_t EventParamName;
typedef uint32_t EventParamType;
typedef double EventTime;

typedef struct OpaqueEventRef *EventRef;
typedef struct OpaqueEventTargetRef *EventTargetRef;
typedef struct OpaqueEventHandlerRef *EventHandlerRef;
typedef struct OpaqueEventHandlerCallRef *EventHandlerCallRef;
typedef struct OpaqueEventHotKeyRef *EventHotKeyRef;
typedef OSStatus (*EventHandlerProcPtr)(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData);
typedef EventHandlerProcPtr EventHandlerUPP;

typedef struct EventTypeSpec {
    OSType eventClass;
    UInt32 eventKind;
} EventTypeSpec;

typedef struct EventHotKeyID {
    OSType signature;
    UInt32 id;
} EventHotKeyID;

enum {
    noErr = 0,
    paramErr = -50,
    eventNotHandledErr = -9874,
    eventParameterNotFoundErr = -9870,
    eventHotKeyExistsErr = -9878,
    eventHotKeyInvalidErr = -9879,
    eventInternalErr = -9868,
};

enum { kEventClassKeyboard = 'keyb', kEventClassApplication = 'appl' };
enum { kEventHotKeyPressed = 5, kEventHotKeyReleased = 6 };
enum { kEventParamDirectObject = '----', typeEventHotKeyID = 'hkid', typeWildCard = '****' };
enum { kEventHotKeyNoOptions = 0, kEventHotKeyExclusive = 1 };

/* modifier bits (Events.h) */
enum {
    cmdKey = 1 << 8,
    shiftKey = 1 << 9,
    alphaLock = 1 << 10,
    optionKey = 1 << 11,
    controlKey = 1 << 12,
};

/* some of the virtual key codes (Events.h) */
enum {
    kVK_ANSI_A = 0x00, kVK_ANSI_S = 0x01, kVK_ANSI_D = 0x02, kVK_ANSI_F = 0x03, kVK_ANSI_H = 0x04,
    kVK_ANSI_G = 0x05, kVK_ANSI_Z = 0x06, kVK_ANSI_X = 0x07, kVK_ANSI_C = 0x08, kVK_ANSI_V = 0x09,
    kVK_ANSI_B = 0x0B, kVK_ANSI_Q = 0x0C, kVK_ANSI_W = 0x0D, kVK_ANSI_E = 0x0E, kVK_ANSI_R = 0x0F,
    kVK_ANSI_Y = 0x10, kVK_ANSI_T = 0x11, kVK_ANSI_1 = 0x12, kVK_ANSI_2 = 0x13, kVK_ANSI_3 = 0x14,
    kVK_ANSI_4 = 0x15, kVK_ANSI_6 = 0x16, kVK_ANSI_5 = 0x17, kVK_ANSI_9 = 0x19, kVK_ANSI_7 = 0x1A,
    kVK_ANSI_8 = 0x1C, kVK_ANSI_0 = 0x1D, kVK_ANSI_O = 0x1F, kVK_ANSI_U = 0x20, kVK_ANSI_I = 0x22,
    kVK_ANSI_P = 0x23, kVK_ANSI_L = 0x25, kVK_ANSI_J = 0x26, kVK_ANSI_K = 0x28, kVK_ANSI_N = 0x2D,
    kVK_ANSI_M = 0x2E, kVK_Return = 0x24, kVK_Tab = 0x30, kVK_Space = 0x31, kVK_Delete = 0x33,
    kVK_Escape = 0x35, kVK_F1 = 0x7A, kVK_F2 = 0x78, kVK_F3 = 0x63, kVK_F4 = 0x76, kVK_F5 = 0x60,
    kVK_LeftArrow = 0x7B, kVK_RightArrow = 0x7C, kVK_DownArrow = 0x7D, kVK_UpArrow = 0x7E,
};

EventTargetRef GetApplicationEventTarget(void);
EventTargetRef GetEventDispatcherTarget(void);
EventTargetRef GetEventMonitorTarget(void);
EventHandlerUPP NewEventHandlerUPP(EventHandlerProcPtr proc);
void DisposeEventHandlerUPP(EventHandlerUPP upp);
OSStatus InvokeEventHandlerUPP(EventHandlerCallRef call, EventRef event, void *userData, EventHandlerUPP upp);
OSStatus InstallEventHandler(EventTargetRef target, EventHandlerUPP handler, UInt32 numTypes, const EventTypeSpec *list,
                             void *userData, EventHandlerRef *outRef);
OSStatus RemoveEventHandler(EventHandlerRef handler);
OSStatus AddEventTypesToHandler(EventHandlerRef handler, UInt32 numTypes, const EventTypeSpec *list);
OSStatus RemoveEventTypesFromHandler(EventHandlerRef handler, UInt32 numTypes, const EventTypeSpec *list);
OSStatus CallNextEventHandler(EventHandlerCallRef call, EventRef event);
OSStatus RegisterEventHotKey(UInt32 keyCode, UInt32 modifiers, EventHotKeyID hotKeyID, EventTargetRef target,
                             OptionBits options, EventHotKeyRef *outRef);
OSStatus UnregisterEventHotKey(EventHotKeyRef hotKey);
OSStatus GetEventParameter(EventRef event, EventParamName name, EventParamType desiredType, EventParamType *actualType,
                           unsigned long bufferSize, unsigned long *actualSize, void *data);
UInt32 GetEventClass(EventRef event);
UInt32 GetEventKind(EventRef event);
EventTime GetEventTime(EventRef event);
EventRef RetainEvent(EventRef event);
void ReleaseEvent(EventRef event);

#define InstallApplicationEventHandler(h, n, l, u, r) \
    InstallEventHandler(GetApplicationEventTarget(), (h), (n), (l), (u), (r))

#ifdef __cplusplus
}
#endif
#endif
