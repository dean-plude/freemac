/* SPDX-License-Identifier: GPL-3.0-or-later
 * The few Carbon and Accessibility calls that Cocoa apps still make, served
 * from AppKit's file (Carbon links here, as Cocoa does), written from
 * Apple's public documentation of each call. What they ask for mostly can't
 * be had on this desktop, so each call answers the way a Mac does when the
 * thing isn't available, and the app carries on:
 *
 * - Global hotkeys (RegisterEventHotKey): accepted, but never pressed.
 *   Wayland doesn't let one app see the keys pressed in another.
 * - Keyboard layouts (TIS..., UCKeyTranslate): there is a current input
 *   source, but it has no Mac key layout data, so key names can't be
 *   translated from it (apps then fall back to their own tables).
 * - Accessibility (AX...): this process is never trusted, as on a Mac
 *   before the user allows it; one app may not move another's windows.
 * - Processes (GetCurrentProcess, TransformProcessType...): the process
 *   itself only. */
#import "AInternal.h"
#include <unistd.h>

typedef int32_t OSStatus;
typedef uint32_t OptionBits;
typedef struct {
    uint32_t highLongOfPSN, lowLongOfPSN;
} ProcessSerialNumber;
typedef struct {
    uint32_t signature, id;
} EventHotKeyID;

enum {
    noErr = 0,
    paramErr = -50,
    procNotFound = -600,
    eventNotHandledErr = -9874,
    eventParameterNotFoundErr = -9870,
    kAXErrorAPIDisabled = -25211,
};

/* Something to hand out where Carbon hands out an opaque reference. */
@interface ACarbonRef : NSObject
@end
@implementation ACarbonRef
@end

static id carbon_ref(void)
{
    static ACarbonRef *ref;
    if (!ref)
        ref = [[ACarbonRef alloc] init];
    return ref;
}

/* ---- Carbon events and hotkeys -------------------------------------------------- */

void *GetApplicationEventTarget(void) { return carbon_ref(); }
void *GetEventDispatcherTarget(void) { return carbon_ref(); }
void *GetEventMonitorTarget(void) { return carbon_ref(); }

OSStatus InstallEventHandler(void *target, void *handler, unsigned long count, const void *types, void *userData,
                             void **outRef)
{
    if (outRef)
        *outRef = [[ACarbonRef alloc] init];
    return noErr;
}
OSStatus RemoveEventHandler(void *ref)
{
    [(id)ref release];
    return noErr;
}
OSStatus RegisterEventHotKey(uint32_t keyCode, uint32_t modifiers, EventHotKeyID hotKeyID, void *target,
                             OptionBits options, void **outRef)
{
    AWarnOnce("global keyboard shortcuts (the app's shortcut is kept but never pressed)");
    if (outRef)
        *outRef = [[ACarbonRef alloc] init];
    return noErr;
}
OSStatus UnregisterEventHotKey(void *ref)
{
    [(id)ref release];
    return noErr;
}
OSStatus GetEventParameter(void *event, uint32_t name, uint32_t type, uint32_t *outType, unsigned long size,
                           unsigned long *outSize, void *data)
{
    return eventParameterNotFoundErr;
}
uint32_t GetEventClass(void *event) { return 0; }
uint32_t GetEventKind(void *event) { return 0; }
OSStatus CallNextEventHandler(void *next, void *event) { return eventNotHandledErr; }
OSStatus CopySymbolicHotKeys(CFArrayRef *out)
{
    if (out)
        *out = (CFArrayRef)[[NSArray alloc] init];
    return noErr;
}

/* ---- keyboard input sources ---------------------------------------------------- */

void *TISCopyCurrentKeyboardInputSource(void) { return [carbon_ref() retain]; }
void *TISCopyCurrentKeyboardLayoutInputSource(void) { return [carbon_ref() retain]; }
void *TISCopyCurrentASCIICapableKeyboardInputSource(void) { return [carbon_ref() retain]; }
void *TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void) { return [carbon_ref() retain]; }
void *TISGetInputSourceProperty(void *source, CFStringRef key) { return NULL; }
OSStatus UCKeyTranslate(const void *layout, uint16_t keyCode, uint16_t action, uint32_t modifiers, uint32_t kbdType,
                        OptionBits options, uint32_t *deadKeyState, unsigned long max, unsigned long *actualLength,
                        uint16_t *chars)
{
    if (actualLength)
        *actualLength = 0;
    return paramErr;
}
uint8_t LMGetKbdType(void) { return 0; }
int16_t GetMBarHeight(void) { return 0; }

/* ---- processes ----------------------------------------------------------------- */

OSStatus GetCurrentProcess(ProcessSerialNumber *psn)
{
    if (!psn)
        return paramErr;
    psn->highLongOfPSN = 0;
    psn->lowLongOfPSN = 2;    /* kCurrentProcess */
    return noErr;
}
OSStatus GetFrontProcess(ProcessSerialNumber *psn) { return GetCurrentProcess(psn); }
OSStatus GetNextProcess(ProcessSerialNumber *psn) { return procNotFound; }
OSStatus GetProcessPID(const ProcessSerialNumber *psn, pid_t *pid)
{
    if (!pid)
        return paramErr;
    *pid = getpid();
    return noErr;
}
OSStatus GetProcessForPID(pid_t pid, ProcessSerialNumber *psn)
{
    return pid == getpid() ? GetCurrentProcess(psn) : procNotFound;
}
OSStatus TransformProcessType(const ProcessSerialNumber *psn, uint32_t type) { return noErr; }
OSStatus SetFrontProcess(const ProcessSerialNumber *psn) { return noErr; }
CFDictionaryRef ProcessInformationCopyDictionary(const ProcessSerialNumber *psn, uint32_t mask) { return NULL; }
const char *GetMacOSStatusCommentString(OSStatus err) { return ""; }
const char *GetMacOSStatusErrorString(OSStatus err) { return ""; }

/* ---- Accessibility --------------------------------------------------------------- */

Boolean AXIsProcessTrusted(void) { return false; }
Boolean AXIsProcessTrustedWithOptions(CFDictionaryRef options) { return false; }
Boolean AXAPIEnabled(void) { return false; }
void *AXUIElementCreateApplication(pid_t pid) { return [[ACarbonRef alloc] init]; }
void *AXUIElementCreateSystemWide(void) { return [[ACarbonRef alloc] init]; }
OSStatus AXUIElementCopyAttributeValue(void *element, CFStringRef attribute, CFTypeRef *value)
{
    if (value)
        *value = NULL;
    return kAXErrorAPIDisabled;
}
OSStatus AXUIElementSetAttributeValue(void *element, CFStringRef attribute, CFTypeRef value)
{
    return kAXErrorAPIDisabled;
}
OSStatus AXUIElementIsAttributeSettable(void *element, CFStringRef attribute, Boolean *settable)
{
    if (settable)
        *settable = false;
    return kAXErrorAPIDisabled;
}
OSStatus AXUIElementPerformAction(void *element, CFStringRef action) { return kAXErrorAPIDisabled; }
unsigned long AXUIElementGetTypeID(void) { return 0x4158; }
void *AXValueCreate(uint32_t type, const void *value) { return NULL; }
uint32_t AXValueGetType(void *value) { return 0; }
Boolean AXValueGetValue(void *value, uint32_t type, void *out) { return false; }

/* The keys these calls take, defined where the calls are (a program that
 * checks for a call before using it weak-links its key too). */
const CFStringRef kAXTrustedCheckOptionPrompt = (CFStringRef)@"AXTrustedCheckOptionPrompt";
const CFStringRef kTISPropertyUnicodeKeyLayoutData = (CFStringRef)@"TISPropertyUnicodeKeyLayoutData";
const CFStringRef kTISPropertyInputSourceID = (CFStringRef)@"TISPropertyInputSourceID";
const CFStringRef kTISPropertyLocalizedName = (CFStringRef)@"TISPropertyLocalizedName";
const CFStringRef kTISNotifySelectedKeyboardInputSourceChanged =
    (CFStringRef)@"TISNotifySelectedKeyboardInputSourceChanged";
