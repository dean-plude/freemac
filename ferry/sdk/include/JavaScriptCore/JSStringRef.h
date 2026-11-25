/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's strings (freemac 1.222, Ferry 0.46.0), from
 * the C API's public documentation; not Apple's header. */
#ifndef _FERRY_JSSTRINGREF_H_
#define _FERRY_JSSTRINGREF_H_
#include <JavaScriptCore/JSValueRef.h>

__FERRY_BEGIN

typedef unsigned short JSChar;

JS_EXPORT JSStringRef JSStringCreateWithCharacters(const JSChar *chars, size_t numChars);
JS_EXPORT JSStringRef JSStringCreateWithUTF8CString(const char *string);
JS_EXPORT JSStringRef JSStringRetain(JSStringRef string);
JS_EXPORT void JSStringRelease(JSStringRef string);
JS_EXPORT size_t JSStringGetLength(JSStringRef string);
JS_EXPORT const JSChar *JSStringGetCharactersPtr(JSStringRef string);
JS_EXPORT size_t JSStringGetMaximumUTF8CStringSize(JSStringRef string);
JS_EXPORT size_t JSStringGetUTF8CString(JSStringRef string, char *buffer, size_t bufferSize);
JS_EXPORT bool JSStringIsEqual(JSStringRef a, JSStringRef b);
JS_EXPORT bool JSStringIsEqualToUTF8CString(JSStringRef a, const char *b);

__FERRY_END
#endif
