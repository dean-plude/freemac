/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: sending messages by hand. Written for freemac from Apple's
 * public documentation; not Apple's header. As on a Mac, cast objc_msgSend
 * to the method's real type before calling it. */
#ifndef _FERRY_OBJC_MESSAGE_H_
#define _FERRY_OBJC_MESSAGE_H_
#include <objc/objc.h>
#include <objc/runtime.h>

struct objc_super {
    __unsafe_unretained id receiver;
    __unsafe_unretained Class super_class;
};

__FERRY_BEGIN
void objc_msgSend(void);
void objc_msgSendSuper(void);
void objc_msgSend_stret(void);
void objc_msgSendSuper_stret(void);
void objc_msgSend_fpret(void);
void _objc_msgForward(void);
__FERRY_END
#endif
