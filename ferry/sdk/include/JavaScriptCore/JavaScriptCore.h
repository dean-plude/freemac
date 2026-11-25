/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the JavaScriptCore framework (freemac 1.222, Ferry 0.46.0):
 * its C API, and in Objective-C its JSContext, JSValue, JSExport,
 * JSManagedValue and JSVirtualMachine. Written for freemac from
 * JavaScriptCore's public documentation; not Apple's header. Ferry's
 * framework runs scripts with this system's JavaScriptCore
 * (libjavascriptcoregtk-4.1); see javascriptcore/ in Ferry's tree. */
#ifndef _FERRY_JAVASCRIPTCORE_H_
#define _FERRY_JAVASCRIPTCORE_H_
#include <JavaScriptCore/JavaScript.h>
#include <JavaScriptCore/JSStringRefCF.h>
#if defined(__OBJC__)
#import <JavaScriptCore/JSContext.h>
#import <JavaScriptCore/JSExport.h>
#import <JavaScriptCore/JSManagedValue.h>
#import <JavaScriptCore/JSValue.h>
#import <JavaScriptCore/JSVirtualMachine.h>
#endif
#endif
