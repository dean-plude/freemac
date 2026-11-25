/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's JSExport (freemac 1.222, Ferry 0.46.0), from
 * the public documentation of JavaScriptCore's Objective-C API; not
 * Apple's header.
 *
 * The methods and properties of a protocol that adopts JSExport are the
 * ones JavaScript sees on an object whose class adopts that protocol. A
 * method's JavaScript name is its selector with the colons taken out and
 * the letter after each one made a capital; JSExportAs gives a method
 * another name. */
#ifndef _FERRY_JSEXPORT_H_
#define _FERRY_JSEXPORT_H_
#import <Foundation/Foundation.h>

@protocol JSExport
@end

#define JSExportAs(PropertyName, Selector)                                                                  \
    @optional                                                                                               \
    Selector __JS_EXPORT_AS__##PropertyName : (id)argument;                                                 \
    @required                                                                                               \
    Selector

#endif
