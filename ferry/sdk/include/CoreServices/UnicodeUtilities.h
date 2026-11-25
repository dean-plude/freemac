/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: turning a key code into what it types (UnicodeUtilities.h),
 * written from Apple's public documentation. Part of CoreServices, as on a
 * Mac, so that Swift code can name CoreServices.UCKeyTranslate (freemac
 * 1.230); the code is Carbon's (appkit/Carbon.m, freemac 1.221), which a
 * program links to get it, and the layout data comes from Carbon's
 * TISGetInputSourceProperty. */
#ifndef _FERRY_UNICODEUTILITIES_H_
#define _FERRY_UNICODEUTILITIES_H_
#include <MacTypes.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The header of a key layout ('uchr') as Apple documents it. Ferry's own
 * layout data (Carbon's English (US) source) is in a form of its own,
 * which only UCKeyTranslate reads; code only passes the pointer on. */
typedef struct UCKeyboardTypeHeader {
    UInt32 keyboardTypeFirst;
    UInt32 keyboardTypeLast;
    UInt32 keyModifiersToTableNumOffset;
    UInt32 keyToCharTableIndexOffset;
    UInt32 keyStateRecordsIndexOffset;
    UInt32 keyStateTerminatorsOffset;
    UInt32 keySequenceDataIndexOffset;
} UCKeyboardTypeHeader;
typedef struct UCKeyboardLayout {
    UInt16 keyLayoutHeaderFormat;
    UInt16 keyLayoutDataVersion;
    UInt32 keyLayoutFeatureInfoOffset;
    UInt32 keyboardTypeCount;
    UCKeyboardTypeHeader keyboardTypeList[1];
} UCKeyboardLayout;
typedef unsigned long UniCharCount;
#ifndef _FERRY_OPTIONBITS
#define _FERRY_OPTIONBITS
typedef uint32_t OptionBits;
#endif

enum { kUCKeyActionDown = 0, kUCKeyActionUp = 1, kUCKeyActionAutoKey = 2, kUCKeyActionDisplay = 3 };
enum { kUCKeyTranslateNoDeadKeysBit = 0, kUCKeyTranslateNoDeadKeysMask = 1 << 0 };
enum { kUCKeyLayoutHeaderFormat = 0x1002 };
OSStatus UCKeyTranslate(const UCKeyboardLayout *keyLayoutPtr, UInt16 virtualKeyCode, UInt16 keyAction,
                        UInt32 modifierKeyState, UInt32 keyboardType, OptionBits keyTranslateOptions,
                        UInt32 *deadKeyState, UniCharCount maxStringLength, UniCharCount *actualStringLength,
                        UniChar unicodeString[]);
UInt8 LMGetKbdType(void);

#ifdef __cplusplus
}
#endif
#endif
