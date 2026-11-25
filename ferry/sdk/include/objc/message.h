/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: sending messages by hand. Written for freemac from Apple's
 * public documentation; not Apple's header. As on a Mac, cast objc_msgSend
 * to the method's real type before calling it. Older code calls it as a
 * variadic function that returns id; as on a Mac that is what it is declared
 * as unless OBJC_OLD_DISPATCH_PROTOTYPES is 0, which Xcode's "strict
 * objc_msgSend calls" setting defines (freemac 1.223, Ferry 0.47.0). */
#ifndef _FERRY_OBJC_MESSAGE_H_
#define _FERRY_OBJC_MESSAGE_H_
#include <objc/objc.h>
#include <objc/runtime.h>

struct objc_super {
    __unsafe_unretained id receiver;
    __unsafe_unretained Class super_class;
};

#ifndef OBJC_OLD_DISPATCH_PROTOTYPES
#define OBJC_OLD_DISPATCH_PROTOTYPES 1
#endif

__FERRY_BEGIN
#if OBJC_OLD_DISPATCH_PROTOTYPES
id objc_msgSend(id self, SEL op, ...);
id objc_msgSendSuper(struct objc_super *super, SEL op, ...);
void objc_msgSend_stret(id self, SEL op, ...);
void objc_msgSendSuper_stret(struct objc_super *super, SEL op, ...);
double objc_msgSend_fpret(id self, SEL op, ...);
id _objc_msgForward(id receiver, SEL sel, ...);
void _objc_msgForward_stret(id receiver, SEL sel, ...);
#else
void objc_msgSend(void);
void objc_msgSendSuper(void);
void objc_msgSend_stret(void);
void objc_msgSendSuper_stret(void);
void objc_msgSend_fpret(void);
void _objc_msgForward(void);
void _objc_msgForward_stret(void);
#endif
__FERRY_END
#endif
