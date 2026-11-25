/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's strings to and from CFStrings (freemac
 * 1.222, Ferry 0.46.0), from the C API's public documentation; not
 * Apple's header. */
#ifndef _FERRY_JSSTRINGREFCF_H_
#define _FERRY_JSSTRINGREFCF_H_
#include <CoreFoundation/CoreFoundation.h>
#include <JavaScriptCore/JSStringRef.h>

__FERRY_BEGIN
JS_EXPORT JSStringRef JSStringCreateWithCFString(CFStringRef string);
JS_EXPORT CFStringRef JSStringCopyCFString(CFAllocatorRef allocator, JSStringRef string);
__FERRY_END
#endif
