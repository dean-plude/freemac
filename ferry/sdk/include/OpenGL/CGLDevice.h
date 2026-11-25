/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: share groups and the Metal device behind a renderer
 * (freemac 1.235, Ferry 0.59.0). Written for freemac from Apple's public
 * CGL reference. Ferry has no Metal, so the device is always NULL. */
#ifndef _FERRY_OPENGL_CGLDEVICE_H_
#define _FERRY_OPENGL_CGLDEVICE_H_
#include <OpenGL/CGLTypes.h>

__FERRY_BEGIN
CGLShareGroupObj CGLGetShareGroup(CGLContextObj ctx);
void *CGLGetDeviceFromGLRenderer(GLint rendererID);
__FERRY_END

#endif
