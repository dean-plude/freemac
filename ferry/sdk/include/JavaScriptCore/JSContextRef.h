/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's contexts and context groups (freemac 1.222,
 * Ferry 0.46.0), from the C API's public documentation; not Apple's
 * header. */
#ifndef _FERRY_JSCONTEXTREF_H_
#define _FERRY_JSCONTEXTREF_H_
#include <JavaScriptCore/JSObjectRef.h>
#include <JavaScriptCore/JSValueRef.h>

__FERRY_BEGIN

JS_EXPORT JSContextGroupRef JSContextGroupCreate(void);
JS_EXPORT JSContextGroupRef JSContextGroupRetain(JSContextGroupRef group);
JS_EXPORT void JSContextGroupRelease(JSContextGroupRef group);
JS_EXPORT JSGlobalContextRef JSGlobalContextCreate(JSClassRef globalObjectClass);
JS_EXPORT JSGlobalContextRef JSGlobalContextCreateInGroup(JSContextGroupRef group, JSClassRef globalObjectClass);
JS_EXPORT JSGlobalContextRef JSGlobalContextRetain(JSGlobalContextRef ctx);
JS_EXPORT void JSGlobalContextRelease(JSGlobalContextRef ctx);
JS_EXPORT JSObjectRef JSContextGetGlobalObject(JSContextRef ctx);
JS_EXPORT JSContextGroupRef JSContextGetGroup(JSContextRef ctx);
JS_EXPORT JSGlobalContextRef JSContextGetGlobalContext(JSContextRef ctx);
JS_EXPORT JSStringRef JSGlobalContextCopyName(JSGlobalContextRef ctx);
JS_EXPORT void JSGlobalContextSetName(JSGlobalContextRef ctx, JSStringRef name);
JS_EXPORT bool JSGlobalContextIsInspectable(JSGlobalContextRef ctx);
JS_EXPORT void JSGlobalContextSetInspectable(JSGlobalContextRef ctx, bool inspectable);

__FERRY_END
#endif
