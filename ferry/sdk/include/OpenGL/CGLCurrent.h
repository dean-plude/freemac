/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the current CGL context of a thread (freemac 1.235, Ferry
 * 0.59.0). Written for freemac from Apple's public CGL reference. */
#ifndef _FERRY_OPENGL_CGLCURRENT_H_
#define _FERRY_OPENGL_CGLCURRENT_H_
#include <OpenGL/CGLTypes.h>

__FERRY_BEGIN
CGLError CGLSetCurrentContext(CGLContextObj ctx);
CGLContextObj CGLGetCurrentContext(void);
__FERRY_END

#endif
