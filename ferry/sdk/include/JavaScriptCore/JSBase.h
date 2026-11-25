/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's C API, its types and script evaluation
 * (freemac 1.222, Ferry 0.46.0). Written for freemac from the public
 * documentation of JavaScriptCore's C API; not Apple's header. Ferry's
 * JavaScriptCore framework passes each call to this system's
 * JavaScriptCore (libjavascriptcoregtk-4.1, which WebKitGTK uses too),
 * opened the first time a program makes one; see javascriptcore/JSC.m. */
#ifndef _FERRY_JSBASE_H_
#define _FERRY_JSBASE_H_
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <_ferry.h>

__FERRY_BEGIN

#define JS_EXPORT extern
#define JSC_API_AVAILABLE(...)
#define JSC_CLASS_AVAILABLE(...)
#define JSC_API_DEPRECATED(...)

typedef const struct OpaqueJSContextGroup *JSContextGroupRef;
typedef const struct OpaqueJSContext *JSContextRef;
typedef struct OpaqueJSContext *JSGlobalContextRef;
typedef struct OpaqueJSString *JSStringRef;
typedef struct OpaqueJSClass *JSClassRef;
typedef struct OpaqueJSPropertyNameArray *JSPropertyNameArrayRef;
typedef struct OpaqueJSPropertyNameAccumulator *JSPropertyNameAccumulatorRef;
typedef void (*JSTypedArrayBytesDeallocator)(void *bytes, void *deallocatorContext);
typedef const struct OpaqueJSValue *JSValueRef;
typedef struct OpaqueJSValue *JSObjectRef;

JS_EXPORT JSValueRef JSEvaluateScript(JSContextRef ctx, JSStringRef script, JSObjectRef thisObject,
                                      JSStringRef sourceURL, int startingLineNumber, JSValueRef *exception);
JS_EXPORT bool JSCheckScriptSyntax(JSContextRef ctx, JSStringRef script, JSStringRef sourceURL,
                                   int startingLineNumber, JSValueRef *exception);
JS_EXPORT void JSGarbageCollect(JSContextRef ctx);

__FERRY_END
#endif
