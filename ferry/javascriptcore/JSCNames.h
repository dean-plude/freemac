/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The calls of JavaScriptCore's C API that Ferry's JavaScriptCore passes to
 * this system's JavaScriptCore (libjavascriptcoregtk-4.1), which has the
 * same C API: one X(name) for each. JSCForward.m makes a forwarder for each
 * one, and the Makefile builds src/jsc_names.h, the list of names
 * ferry_jsc_symbol() (src/host.c) serves, from the same lines. The two
 * calls that take or make CFStrings (JSStringRefCF.h) are Ferry's own. */
X(JSCheckScriptSyntax) X(JSClassCreate) X(JSClassRelease) X(JSClassRetain) X(JSContextGetGlobalContext)
X(JSContextGetGlobalObject) X(JSContextGetGroup) X(JSContextGroupCreate) X(JSContextGroupRelease)
X(JSContextGroupRetain) X(JSEvaluateScript) X(JSGarbageCollect) X(JSGlobalContextCopyName)
X(JSGlobalContextCreate) X(JSGlobalContextCreateInGroup) X(JSGlobalContextIsInspectable)
X(JSGlobalContextRelease) X(JSGlobalContextRetain) X(JSGlobalContextSetInspectable) X(JSGlobalContextSetName)
X(JSObjectCallAsConstructor) X(JSObjectCallAsFunction) X(JSObjectCopyPropertyNames) X(JSObjectDeleteProperty)
X(JSObjectDeletePropertyForKey) X(JSObjectGetArrayBufferByteLength) X(JSObjectGetArrayBufferBytesPtr)
X(JSObjectGetPrivate) X(JSObjectGetProperty) X(JSObjectGetPropertyAtIndex) X(JSObjectGetPropertyForKey)
X(JSObjectGetPrototype) X(JSObjectGetTypedArrayBuffer) X(JSObjectGetTypedArrayByteLength)
X(JSObjectGetTypedArrayByteOffset) X(JSObjectGetTypedArrayBytesPtr) X(JSObjectGetTypedArrayLength)
X(JSObjectHasProperty) X(JSObjectHasPropertyForKey) X(JSObjectIsConstructor) X(JSObjectIsFunction)
X(JSObjectMake) X(JSObjectMakeArray) X(JSObjectMakeArrayBufferWithBytesNoCopy) X(JSObjectMakeConstructor)
X(JSObjectMakeDate) X(JSObjectMakeDeferredPromise) X(JSObjectMakeError) X(JSObjectMakeFunction)
X(JSObjectMakeFunctionWithCallback) X(JSObjectMakeRegExp) X(JSObjectMakeTypedArray)
X(JSObjectMakeTypedArrayWithArrayBuffer) X(JSObjectMakeTypedArrayWithArrayBufferAndOffset)
X(JSObjectMakeTypedArrayWithBytesNoCopy) X(JSObjectSetPrivate) X(JSObjectSetProperty)
X(JSObjectSetPropertyAtIndex) X(JSObjectSetPropertyForKey) X(JSObjectSetPrototype)
X(JSPropertyNameAccumulatorAddName) X(JSPropertyNameArrayGetCount) X(JSPropertyNameArrayGetNameAtIndex)
X(JSPropertyNameArrayRelease) X(JSPropertyNameArrayRetain) X(JSStringCreateWithCharacters)
X(JSStringCreateWithUTF8CString) X(JSStringGetCharactersPtr) X(JSStringGetLength)
X(JSStringGetMaximumUTF8CStringSize) X(JSStringGetUTF8CString) X(JSStringIsEqual)
X(JSStringIsEqualToUTF8CString) X(JSStringRelease) X(JSStringRetain)
X(JSValueCreateJSONString) X(JSValueGetType) X(JSValueGetTypedArrayType) X(JSValueIsArray)
X(JSValueIsBoolean) X(JSValueIsDate) X(JSValueIsEqual) X(JSValueIsInstanceOfConstructor) X(JSValueIsNull)
X(JSValueIsNumber) X(JSValueIsObject) X(JSValueIsObjectOfClass) X(JSValueIsStrictEqual) X(JSValueIsString)
X(JSValueIsSymbol) X(JSValueIsUndefined) X(JSValueMakeBoolean) X(JSValueMakeFromJSONString)
X(JSValueMakeNull) X(JSValueMakeNumber) X(JSValueMakeString) X(JSValueMakeSymbol) X(JSValueMakeUndefined)
X(JSValueProtect) X(JSValueToBoolean) X(JSValueToNumber) X(JSValueToObject) X(JSValueToStringCopy)
X(JSValueUnprotect)
