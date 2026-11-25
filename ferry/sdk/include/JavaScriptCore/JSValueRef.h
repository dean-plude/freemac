/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's values (freemac 1.222, Ferry 0.46.0), from
 * the C API's public documentation; not Apple's header. */
#ifndef _FERRY_JSVALUEREF_H_
#define _FERRY_JSVALUEREF_H_
#include <JavaScriptCore/JSBase.h>

__FERRY_BEGIN

typedef enum {
    kJSTypeUndefined,
    kJSTypeNull,
    kJSTypeBoolean,
    kJSTypeNumber,
    kJSTypeString,
    kJSTypeObject,
    kJSTypeSymbol,
    kJSTypeBigInt,
} JSType;

typedef enum {
    kJSTypedArrayTypeInt8Array,
    kJSTypedArrayTypeInt16Array,
    kJSTypedArrayTypeInt32Array,
    kJSTypedArrayTypeUint8Array,
    kJSTypedArrayTypeUint8ClampedArray,
    kJSTypedArrayTypeUint16Array,
    kJSTypedArrayTypeUint32Array,
    kJSTypedArrayTypeFloat32Array,
    kJSTypedArrayTypeFloat64Array,
    kJSTypedArrayTypeArrayBuffer,
    kJSTypedArrayTypeNone,
    kJSTypedArrayTypeBigInt64Array,
    kJSTypedArrayTypeBigUint64Array,
} JSTypedArrayType;

JS_EXPORT JSType JSValueGetType(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsUndefined(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsNull(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsBoolean(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsNumber(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsString(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsSymbol(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsObject(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsObjectOfClass(JSContextRef ctx, JSValueRef value, JSClassRef jsClass);
JS_EXPORT bool JSValueIsArray(JSContextRef ctx, JSValueRef value);
JS_EXPORT bool JSValueIsDate(JSContextRef ctx, JSValueRef value);
JS_EXPORT JSTypedArrayType JSValueGetTypedArrayType(JSContextRef ctx, JSValueRef value, JSValueRef *exception);
JS_EXPORT bool JSValueIsEqual(JSContextRef ctx, JSValueRef a, JSValueRef b, JSValueRef *exception);
JS_EXPORT bool JSValueIsStrictEqual(JSContextRef ctx, JSValueRef a, JSValueRef b);
JS_EXPORT bool JSValueIsInstanceOfConstructor(JSContextRef ctx, JSValueRef value, JSObjectRef constructor,
                                              JSValueRef *exception);
JS_EXPORT JSValueRef JSValueMakeUndefined(JSContextRef ctx);
JS_EXPORT JSValueRef JSValueMakeNull(JSContextRef ctx);
JS_EXPORT JSValueRef JSValueMakeBoolean(JSContextRef ctx, bool boolean);
JS_EXPORT JSValueRef JSValueMakeNumber(JSContextRef ctx, double number);
JS_EXPORT JSValueRef JSValueMakeString(JSContextRef ctx, JSStringRef string);
JS_EXPORT JSValueRef JSValueMakeSymbol(JSContextRef ctx, JSStringRef description);
JS_EXPORT JSValueRef JSValueMakeFromJSONString(JSContextRef ctx, JSStringRef string);
JS_EXPORT JSStringRef JSValueCreateJSONString(JSContextRef ctx, JSValueRef value, unsigned indent,
                                              JSValueRef *exception);
JS_EXPORT bool JSValueToBoolean(JSContextRef ctx, JSValueRef value);
JS_EXPORT double JSValueToNumber(JSContextRef ctx, JSValueRef value, JSValueRef *exception);
JS_EXPORT JSStringRef JSValueToStringCopy(JSContextRef ctx, JSValueRef value, JSValueRef *exception);
JS_EXPORT JSObjectRef JSValueToObject(JSContextRef ctx, JSValueRef value, JSValueRef *exception);
JS_EXPORT void JSValueProtect(JSContextRef ctx, JSValueRef value);
JS_EXPORT void JSValueUnprotect(JSContextRef ctx, JSValueRef value);

__FERRY_END
#endif
