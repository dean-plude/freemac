/* SPDX-License-Identifier: GPL-3.0-or-later
 * Keyboard layouts (freemac 1.221, Ferry 0.45.0): the current input
 * source and its properties, UCKeyTranslate turning key codes into
 * characters as Flycut, Spectacle, KeyCastr and MacPass do to name their
 * shortcuts' keys, the glyphs Carbon names for the modifier keys, and the
 * symbolic hotkey mode a shortcut recorder sets. With no Strata to ask the
 * layout is English (US). */
#import <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>

static const UCKeyboardLayout *layout;

static NSString *type(UInt16 key, UInt32 carbonModifiers, UInt16 action)
{
    UInt32 dead = 7;
    UniChar chars[4];
    UniCharCount len = 9;
    OSStatus r = UCKeyTranslate(layout, key, action, (carbonModifiers >> 8) & 0xFF, LMGetKbdType(),
                                kUCKeyTranslateNoDeadKeysMask, &dead, 4, &len, chars);
    if (r != noErr)
        return [NSString stringWithFormat:@"error %d", (int)r];
    NSMutableString *s = [NSMutableString string];
    for (UniCharCount i = 0; i < len; i++)
        [s appendFormat:chars[i] >= 0x20 && chars[i] < 0x7F ? @"%C" : @"U+%04X", chars[i]];
    if (dead)
        [s appendString:@" (dead key)"];
    return len ? s : @"(nothing)";
}

int main(void)
{
    @autoreleasepool {
        TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
        printf("source: %s, %s\n", [(__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceID) UTF8String],
               [(__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyLocalizedName) UTF8String]);
        printf("type %s, category %s, languages %s\n",
               [(__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceType) UTF8String],
               [(__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) UTF8String],
               [[(__bridge NSArray *)TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
                   componentsJoinedByString:@","] UTF8String]);
        printf("ascii capable %d, selected %d, unknown property %s\n",
               TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) == kCFBooleanTrue,
               TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelected) == kCFBooleanTrue,
               TISGetInputSourceProperty(source, kTISPropertyBundleID) ? "set" : "NULL");
        CFDataRef data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
        layout = (const UCKeyboardLayout *)CFDataGetBytePtr(data);
        printf("layout data %s, keyboard type %u\n", data ? "yes" : "none", LMGetKbdType());

        printf("a %s, shift-a %s, caps-a %s, caps-shift-a %s, control-a %s, control-a shown %s\n",
               [type(kVK_ANSI_A, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_A, shiftKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_A, alphaLock, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_A, alphaLock | shiftKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_A, controlKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_A, controlKey, kUCKeyActionDisplay) UTF8String]);
        printf("1 %s, shift-1 %s, shift-/ %s, shift-` %s, caps-1 %s, option-v %s, command-v %s\n",
               [type(kVK_ANSI_1, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_1, shiftKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_Slash, shiftKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_Grave, shiftKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_1, alphaLock, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_V, optionKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_V, cmdKey, kUCKeyActionDown) UTF8String]);
        printf("keypad 7 %s, keypad * %s, ISO section %s and %s\n",
               [type(kVK_ANSI_Keypad7, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_ANSI_KeypadMultiply, shiftKey, kUCKeyActionDown) UTF8String],
               [type(kVK_ISO_Section, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_ISO_Section, shiftKey, kUCKeyActionDown) UTF8String]);
        printf("return %s, tab %s, space %s, delete %s, forward delete %s, escape %s\n",
               [type(kVK_Return, 0, kUCKeyActionDown) UTF8String], [type(kVK_Tab, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_Space, 0, kUCKeyActionDown) UTF8String], [type(kVK_Delete, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_ForwardDelete, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_Escape, 0, kUCKeyActionDown) UTF8String]);
        printf("left %s, up %s, home %s, page down %s, F5 %s, command key %s\n",
               [type(kVK_LeftArrow, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_UpArrow, 0, kUCKeyActionDown) UTF8String], [type(kVK_Home, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_PageDown, 0, kUCKeyActionDown) UTF8String], [type(kVK_F5, 0, kUCKeyActionDown) UTF8String],
               [type(kVK_Command, 0, kUCKeyActionDown) UTF8String]);
        printf("key up %s, auto key %s, NULL layout %d\n", [type(kVK_ANSI_A, 0, kUCKeyActionUp) UTF8String],
               [type(kVK_ANSI_A, 0, kUCKeyActionAutoKey) UTF8String],
               (int)UCKeyTranslate(NULL, 0, 0, 0, 0, 0, &(UInt32){0}, 4, &(UniCharCount){0}, (UniChar[4]){0}));
        CFRelease(source);

        NSArray *all = CFBridgingRelease(TISCreateInputSourceList(NULL, false));
        NSDictionary *filter = @{(__bridge id)kTISPropertyInputSourceID : @"com.apple.keylayout.US"};
        NSArray *us = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, false));
        NSDictionary *none = @{(__bridge id)kTISPropertyInputSourceID : @"com.example.none"};
        NSArray *nothing = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)none, false));
        printf("sources %lu, US %lu, none %lu\n", (unsigned long)all.count, (unsigned long)us.count,
               (unsigned long)nothing.count);
        TISInputSourceRef en = TISCopyInputSourceForLanguage(CFSTR("en"));
        TISInputSourceRef fr = TISCopyInputSourceForLanguage(CFSTR("fr"));
        printf("for English %s, for French %s, select %d\n", en ? "yes" : "none", fr ? "yes" : "none",
               (int)TISSelectInputSource(en));
        CFRelease(en);

        printf("glyphs %04X %04X %04X %04X, menu glyphs %d %d\n", kCommandUnicode, kOptionUnicode, kControlUnicode,
               kShiftUnicode, kMenuReturnGlyph, kMenuTabRightGlyph);
        void *token = PushSymbolicHotKeyMode(kHIHotKeyModeAllDisabled);
        printf("symbolic mode %u", (unsigned)GetSymbolicHotKeyMode());
        PopSymbolicHotKeyMode(token);
        printf(", after pop %u\n", (unsigned)GetSymbolicHotKeyMode());
        KeyMap keys;
        memset(keys, 0xff, sizeof keys);
        GetKeys(keys);
        printf("modifiers %u, keys held %s\n", (unsigned)GetCurrentKeyModifiers(),
               keys[0].bigEndianValue || keys[3].bigEndianValue ? "some" : "none");

        /* what Qt's key mapper asks: an input method's own layout (none
         * here) and what a key types with other modifiers */
        NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                  windowNumber:0 context:nil characters:@"a" charactersIgnoringModifiers:@"a"
                                     isARepeat:NO keyCode:kVK_ANSI_1];
        printf("input method layout %s, 1 with shift %s, without %s, layout kind %d\n",
               TISCopyInputMethodKeyboardLayoutOverride() ? "set" : "NULL",
               [[e charactersByApplyingModifiers:NSEventModifierFlagShift] UTF8String],
               [[e charactersByApplyingModifiers:0] UTF8String], (int)(KeyboardLayoutKind)kKLuchrKind);
    }
    return 0;
}
