/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the few Carbon calls Cocoa apps still make, written from
 * Apple's public documentation (freemac 1.215, Ferry 0.41.0): the Carbon
 * Event Manager as far as global hotkeys need it, and the Mac's virtual
 * key codes and modifier bits. Served from AppKit's file. */
#ifndef _FERRY_CARBON_H_
#define _FERRY_CARBON_H_
#include <ApplicationServices/ApplicationServices.h>
/* noErr and paramErr come from CoreServices, as on a Mac. */
#include <CoreServices/CoreServices.h>
/* In Objective-C a Mac's Carbon.h brings Foundation's classes with it
 * (window managers such as Spectacle import Carbon alone). */
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

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
    eventNotHandledErr = -9874,
    eventParameterNotFoundErr = -9870,
    eventHotKeyExistsErr = -9878,
    eventHotKeyInvalidErr = -9879,
    eventInternalErr = -9868,
};

enum { kEventClassKeyboard = 'keyb', kEventClassApplication = 'appl' };
enum { kEventHotKeyPressed = 5, kEventHotKeyReleased = 6 };
/* the raw keyboard events and their parameters, which Ferry doesn't send yet (freemac 1.230) */
enum { kEventRawKeyDown = 1, kEventRawKeyRepeat = 2, kEventRawKeyUp = 3, kEventRawKeyModifiersChanged = 4 };
enum { kEventParamKeyCode = 'kcod', kEventParamKeyMacCharCodes = 'kchr', kEventParamKeyModifiers = 'kmod',
       kEventParamKeyUnicodes = 'kuni', kEventParamKeyboardType = 'kbdt' };
enum { kEventParamDirectObject = '----', typeEventHotKeyID = 'hkid' }; /* typeWildCard: AppleEvents.h */
enum { kEventHotKeyNoOptions = 0, kEventHotKeyExclusive = 1 };

/* modifier bits (Events.h) */
typedef UInt16 EventModifiers;
enum {
    cmdKey = 1 << 8,
    shiftKey = 1 << 9,
    alphaLock = 1 << 10,
    optionKey = 1 << 11,
    controlKey = 1 << 12,
    /* the window-active and mouse button bits (freemac OBS work) */
    activeFlag = 1 << 0,
    btnState = 1 << 7,
};
/* the parts of a key event's message: its character and key codes
 * (Events.h; freemac OBS work, whose hotkey table is keyCodeMask >> 8 long) */
enum {
    charCodeMask = 0x000000FF,
    keyCodeMask = 0x0000FF00,
    adbAddrMask = 0x00FF0000,
    osEvtMessageMask = (int)0xFF000000,
};

/* the character codes of the special keys (Events.h) */
enum {
    kNullCharCode = 0, kHomeCharCode = 1, kEnterCharCode = 3, kEndCharCode = 4, kHelpCharCode = 5,
    kBellCharCode = 7, kBackspaceCharCode = 8, kTabCharCode = 9, kLineFeedCharCode = 10,
    kVerticalTabCharCode = 11, kPageUpCharCode = 11, kFormFeedCharCode = 12, kPageDownCharCode = 12,
    kReturnCharCode = 13, kFunctionKeyCharCode = 16, kCommandCharCode = 17, kCheckCharCode = 18,
    kDiamondCharCode = 19, kAppleLogoCharCode = 20, kEscapeCharCode = 27, kClearCharCode = 27,
    kLeftArrowCharCode = 28, kRightArrowCharCode = 29, kUpArrowCharCode = 30, kDownArrowCharCode = 31,
    kSpaceCharCode = 32, kDeleteCharCode = 127, kBulletCharCode = 165, kNonBreakingSpaceCharCode = 202
};

/* the virtual key codes (Events.h); complete from freemac 1.221, Ferry 0.45.0 */
enum {
    kVK_ANSI_A = 0x00, kVK_ANSI_S = 0x01, kVK_ANSI_D = 0x02, kVK_ANSI_F = 0x03, kVK_ANSI_H = 0x04,
    kVK_ANSI_G = 0x05, kVK_ANSI_Z = 0x06, kVK_ANSI_X = 0x07, kVK_ANSI_C = 0x08, kVK_ANSI_V = 0x09,
    kVK_ANSI_B = 0x0B, kVK_ANSI_Q = 0x0C, kVK_ANSI_W = 0x0D, kVK_ANSI_E = 0x0E, kVK_ANSI_R = 0x0F,
    kVK_ANSI_Y = 0x10, kVK_ANSI_T = 0x11, kVK_ANSI_1 = 0x12, kVK_ANSI_2 = 0x13, kVK_ANSI_3 = 0x14,
    kVK_ANSI_4 = 0x15, kVK_ANSI_6 = 0x16, kVK_ANSI_5 = 0x17, kVK_ANSI_Equal = 0x18, kVK_ANSI_9 = 0x19,
    kVK_ANSI_7 = 0x1A, kVK_ANSI_Minus = 0x1B, kVK_ANSI_8 = 0x1C, kVK_ANSI_0 = 0x1D,
    kVK_ANSI_RightBracket = 0x1E, kVK_ANSI_O = 0x1F, kVK_ANSI_U = 0x20, kVK_ANSI_LeftBracket = 0x21,
    kVK_ANSI_I = 0x22, kVK_ANSI_P = 0x23, kVK_ANSI_L = 0x25, kVK_ANSI_J = 0x26, kVK_ANSI_Quote = 0x27,
    kVK_ANSI_K = 0x28, kVK_ANSI_Semicolon = 0x29, kVK_ANSI_Backslash = 0x2A, kVK_ANSI_Comma = 0x2B,
    kVK_ANSI_Slash = 0x2C, kVK_ANSI_N = 0x2D, kVK_ANSI_M = 0x2E, kVK_ANSI_Period = 0x2F, kVK_ANSI_Grave = 0x32,
    kVK_ANSI_KeypadDecimal = 0x41, kVK_ANSI_KeypadMultiply = 0x43, kVK_ANSI_KeypadPlus = 0x45,
    kVK_ANSI_KeypadClear = 0x47, kVK_ANSI_KeypadDivide = 0x4B, kVK_ANSI_KeypadEnter = 0x4C,
    kVK_ANSI_KeypadMinus = 0x4E, kVK_ANSI_KeypadEquals = 0x51, kVK_ANSI_Keypad0 = 0x52, kVK_ANSI_Keypad1 = 0x53,
    kVK_ANSI_Keypad2 = 0x54, kVK_ANSI_Keypad3 = 0x55, kVK_ANSI_Keypad4 = 0x56, kVK_ANSI_Keypad5 = 0x57,
    kVK_ANSI_Keypad6 = 0x58, kVK_ANSI_Keypad7 = 0x59, kVK_ANSI_Keypad8 = 0x5B, kVK_ANSI_Keypad9 = 0x5C,
    kVK_Return = 0x24, kVK_Tab = 0x30, kVK_Space = 0x31, kVK_Delete = 0x33, kVK_Escape = 0x35,
    kVK_RightCommand = 0x36, kVK_Command = 0x37, kVK_Shift = 0x38, kVK_CapsLock = 0x39, kVK_Option = 0x3A,
    kVK_Control = 0x3B, kVK_RightShift = 0x3C, kVK_RightOption = 0x3D, kVK_RightControl = 0x3E,
    kVK_Function = 0x3F, kVK_F17 = 0x40, kVK_VolumeUp = 0x48, kVK_VolumeDown = 0x49, kVK_Mute = 0x4A,
    kVK_F18 = 0x4F, kVK_F19 = 0x50, kVK_F20 = 0x5A, kVK_F5 = 0x60, kVK_F6 = 0x61, kVK_F7 = 0x62, kVK_F3 = 0x63,
    kVK_F8 = 0x64, kVK_F9 = 0x65, kVK_F11 = 0x67, kVK_F13 = 0x69, kVK_F16 = 0x6A, kVK_F14 = 0x6B,
    kVK_F10 = 0x6D, kVK_F12 = 0x6F, kVK_F15 = 0x71, kVK_Help = 0x72, kVK_Home = 0x73, kVK_PageUp = 0x74,
    kVK_ForwardDelete = 0x75, kVK_F4 = 0x76, kVK_End = 0x77, kVK_F2 = 0x78, kVK_PageDown = 0x79, kVK_F1 = 0x7A,
    kVK_LeftArrow = 0x7B, kVK_RightArrow = 0x7C, kVK_DownArrow = 0x7D, kVK_UpArrow = 0x7E,
    kVK_ISO_Section = 0x0A, kVK_JIS_Yen = 0x5D, kVK_JIS_Underscore = 0x5E, kVK_JIS_KeypadComma = 0x5F,
    kVK_JIS_Eisu = 0x66, kVK_JIS_Kana = 0x68,
};

/* the modifier bits' numbers, and the right-hand ones (Events.h) */
enum {
    cmdKeyBit = 8, shiftKeyBit = 9, alphaLockBit = 10, optionKeyBit = 11, controlKeyBit = 12,
    rightShiftKeyBit = 13, rightOptionKeyBit = 14, rightControlKeyBit = 15,
    rightShiftKey = 1 << 13, rightOptionKey = 1 << 14, rightControlKey = 1 << 15, kEventKeyModifierFnBit = 17,
    kEventKeyModifierFnMask = 1 << 17, kEventKeyModifierNumLockMask = 1 << 16,
};

/* The characters menus show for the modifier keys (Menus.h), freemac 1.221, Ferry 0.45.0. */
enum {
    kCommandUnicode = 0x2318,
    kOptionUnicode = 0x2325,
    kControlUnicode = 0x2303,
    kShiftUnicode = 0x21E7,
    kCheckUnicode = 0x2713,
    kDiamondUnicode = 0x25C6,
    kBulletUnicode = 0x2022,
};

/* The glyph numbers of NSMenuItem's keyEquivalentGlyph and Carbon menus (Menus.h). */
enum {
    kMenuNullGlyph = 0x00, kMenuTabRightGlyph = 0x02, kMenuTabLeftGlyph = 0x03, kMenuEnterGlyph = 0x04,
    kMenuShiftGlyph = 0x05, kMenuControlGlyph = 0x06, kMenuOptionGlyph = 0x07, kMenuSpaceGlyph = 0x09,
    kMenuDeleteRightGlyph = 0x0A, kMenuReturnGlyph = 0x0B, kMenuReturnR2LGlyph = 0x0C,
    kMenuNonmarkingReturnGlyph = 0x0D, kMenuPencilGlyph = 0x0F, kMenuDownwardArrowDashedGlyph = 0x10,
    kMenuCommandGlyph = 0x11, kMenuCheckmarkGlyph = 0x12, kMenuDiamondGlyph = 0x13, kMenuAppleLogoFilledGlyph = 0x14,
    kMenuParagraphKoreanGlyph = 0x15, kMenuDeleteLeftGlyph = 0x17, kMenuLeftArrowDashedGlyph = 0x18,
    kMenuUpArrowDashedGlyph = 0x19, kMenuRightArrowDashedGlyph = 0x1A, kMenuEscapeGlyph = 0x1B,
    kMenuClearGlyph = 0x1C, kMenuLeftDoubleQuotesJapaneseGlyph = 0x1D, kMenuRightDoubleQuotesJapaneseGlyph = 0x1E,
    kMenuTrademarkJapaneseGlyph = 0x1F, kMenuBlankGlyph = 0x61, kMenuPageUpGlyph = 0x62,
    kMenuCapsLockGlyph = 0x63, kMenuLeftArrowGlyph = 0x64, kMenuRightArrowGlyph = 0x65,
    kMenuNorthwestArrowGlyph = 0x66, kMenuHelpGlyph = 0x67, kMenuUpArrowGlyph = 0x68,
    kMenuSoutheastArrowGlyph = 0x69, kMenuDownArrowGlyph = 0x6A, kMenuPageDownGlyph = 0x6B,
    kMenuContextualMenuGlyph = 0x6D, kMenuPowerGlyph = 0x6E, kMenuF1Glyph = 0x6F, kMenuF2Glyph = 0x70,
    kMenuF3Glyph = 0x71, kMenuF4Glyph = 0x72, kMenuF5Glyph = 0x73, kMenuF6Glyph = 0x74, kMenuF7Glyph = 0x75,
    kMenuF8Glyph = 0x76, kMenuF9Glyph = 0x77, kMenuF10Glyph = 0x78, kMenuF11Glyph = 0x79, kMenuF12Glyph = 0x7A,
    kMenuF13Glyph = 0x87, kMenuF14Glyph = 0x88, kMenuF15Glyph = 0x89, kMenuControlISOGlyph = 0x8A,
    kMenuEjectGlyph = 0x8C, kMenuEisuGlyph = 0x8D, kMenuKanaGlyph = 0x8E, kMenuF16Glyph = 0x8F,
    kMenuF17Glyph = 0x90, kMenuF18Glyph = 0x91, kMenuF19Glyph = 0x92,
};

EventTargetRef GetApplicationEventTarget(void);
EventTargetRef GetEventDispatcherTarget(void);
EventTargetRef GetEventMonitorTarget(void);
EventHandlerUPP NewEventHandlerUPP(EventHandlerProcPtr proc);
void DisposeEventHandlerUPP(EventHandlerUPP upp);
OSStatus InvokeEventHandlerUPP(EventHandlerCallRef call, EventRef event, void *userData, EventHandlerUPP upp);
OSStatus InstallEventHandler(EventTargetRef target, EventHandlerUPP handler, ItemCount numTypes, const EventTypeSpec *list,
                             void *userData, EventHandlerRef *outRef);
OSStatus RemoveEventHandler(EventHandlerRef handler);
OSStatus AddEventTypesToHandler(EventHandlerRef handler, ItemCount numTypes, const EventTypeSpec *list);
OSStatus RemoveEventTypesFromHandler(EventHandlerRef handler, ItemCount numTypes, const EventTypeSpec *list);
OSStatus CallNextEventHandler(EventHandlerCallRef call, EventRef event);
OSStatus RegisterEventHotKey(UInt32 keyCode, UInt32 modifiers, EventHotKeyID hotKeyID, EventTargetRef target,
                             OptionBits options, EventHotKeyRef *outRef);
OSStatus UnregisterEventHotKey(EventHotKeyRef hotKey);
OSStatus GetEventParameter(EventRef event, EventParamName name, EventParamType desiredType, EventParamType *actualType,
                           ByteCount bufferSize, ByteCount *actualSize, void *data);
UInt32 GetEventClass(EventRef event);
UInt32 GetEventKind(EventRef event);
EventTime GetEventTime(EventRef event);
EventRef RetainEvent(EventRef event);
void ReleaseEvent(EventRef event);

#define InstallApplicationEventHandler(h, n, l, u, r) \
    InstallEventHandler(GetApplicationEventTarget(), (h), (n), (l), (u), (r))

/* ---- keyboard layouts (TextInputSources.h, UnicodeUtilities.h) ---------------------
 * From freemac 1.221 (Ferry 0.45.0): the current input source is the
 * keyboard layout freemac's compositor has selected (English (US) when it
 * can't be asked), and while it is English (US) its key layout data lets
 * UCKeyTranslate turn a key code into the characters it types, with Shift,
 * Caps Lock and Control. Option types the same as without it, and there
 * are no dead keys. Other layouts have no key layout data. */
typedef struct __TISInputSource *TISInputSourceRef;

extern const CFStringRef kTISPropertyUnicodeKeyLayoutData;
extern const CFStringRef kTISPropertyInputSourceID;
extern const CFStringRef kTISPropertyLocalizedName;
extern const CFStringRef kTISPropertyInputSourceType;
extern const CFStringRef kTISPropertyInputSourceCategory;
extern const CFStringRef kTISPropertyInputSourceLanguages;
extern const CFStringRef kTISPropertyInputSourceIsASCIICapable;
extern const CFStringRef kTISPropertyInputSourceIsEnabled;
extern const CFStringRef kTISPropertyInputSourceIsSelected;
extern const CFStringRef kTISPropertyInputSourceIsSelectCapable;
extern const CFStringRef kTISPropertyBundleID;
extern const CFStringRef kTISCategoryKeyboardInputSource;
extern const CFStringRef kTISTypeKeyboardLayout;
extern const CFStringRef kTISNotifySelectedKeyboardInputSourceChanged;
extern const CFStringRef kTISNotifyEnabledKeyboardInputSourcesChanged;

CFTypeID TISInputSourceGetTypeID(void);
TISInputSourceRef TISCopyCurrentKeyboardInputSource(void);
TISInputSourceRef TISCopyCurrentKeyboardLayoutInputSource(void);
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardInputSource(void);
TISInputSourceRef TISCopyCurrentASCIICapableKeyboardLayoutInputSource(void);
TISInputSourceRef TISCopyInputSourceForLanguage(CFStringRef language);
CFArrayRef TISCreateInputSourceList(CFDictionaryRef properties, Boolean includeAllInstalled);
CFArrayRef TISCreateASCIICapableInputSourceList(void);
void *TISGetInputSourceProperty(TISInputSourceRef source, CFStringRef key);
OSStatus TISSelectInputSource(TISInputSourceRef source);
/* An input method's own keyboard layout: freemac's input methods have none
 * of their own, so this gives NULL and the current layout serves. */
TISInputSourceRef TISCopyInputMethodKeyboardLayoutOverride(void);

/* Which kind of layout data a keyboard layout has (Keyboards.h): Ferry's
 * layouts hold only 'uchr' data. */
typedef SInt32 KeyboardLayoutKind;
enum { kKLKCHRuchrKind = 0, kKLKCHRKind = 1, kKLuchrKind = 2 };

/* UCKeyTranslate and LMGetKbdType: CoreServices/UnicodeUtilities.h */

/* ---- the system's own hotkeys (CarbonEvents.h) ---------------------------------------
 * There are none Ferry knows of, and turning them off changes nothing. */
#ifdef __swift__
#define kHISymbolicHotKeyCode CFSTR("kHISymbolicHotKeyCode")
#define kHISymbolicHotKeyModifiers CFSTR("kHISymbolicHotKeyModifiers")
#define kHISymbolicHotKeyEnabled CFSTR("kHISymbolicHotKeyEnabled")
#else
extern const CFStringRef kHISymbolicHotKeyCode;
extern const CFStringRef kHISymbolicHotKeyModifiers;
extern const CFStringRef kHISymbolicHotKeyEnabled;
#endif
enum {
    kHIHotKeyModeAllEnabled = 0,
    kHIHotKeyModeAllDisabled = 1 << 0,
    kHIHotKeyModeAllDisabledExceptUniversalAccess = 1 << 1,
};
OSStatus CopySymbolicHotKeys(CFArrayRef *outHotKeyArray);
void *PushSymbolicHotKeyMode(OptionBits inOptions);
void PopSymbolicHotKeyMode(void *inToken);
OptionBits GetSymbolicHotKeyMode(void);

/* ---- the keyboard's state (Events.h) --------------------------------------------- */
#ifndef _FERRY_BIGENDIAN_TYPES
#define _FERRY_BIGENDIAN_TYPES
typedef struct BigEndianUInt32 { UInt32 bigEndianValue; } BigEndianUInt32;
#endif
typedef BigEndianUInt32 KeyMap[4];
UInt32 GetCurrentEventKeyModifiers(void);
UInt32 GetCurrentEventButtonState(void);
UInt32 GetCurrentButtonState(void);
UInt32 GetCurrentKeyModifiers(void);
void GetKeys(KeyMap theKeys);

#ifdef __cplusplus
}
#endif
#endif
