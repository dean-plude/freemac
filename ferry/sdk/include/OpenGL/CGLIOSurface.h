/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: an IOSurface as an OpenGL texture (freemac 1.235, Ferry
 * 0.59.0). Written for freemac from Apple's public CGL reference. Ferry
 * copies the plane into the texture when this is called (see
 * docs/ferry-compat.md); on a Mac the texture shares the surface's memory. */
#ifndef _FERRY_OPENGL_CGLIOSURFACE_H_
#define _FERRY_OPENGL_CGLIOSURFACE_H_
#include <OpenGL/CGLTypes.h>

__FERRY_BEGIN
#ifndef _FERRY_IOSURFACEREF_DEFINED
#define _FERRY_IOSURFACEREF_DEFINED
#if defined(__has_attribute) && __has_attribute(objc_bridge)
typedef struct __attribute__((objc_bridge(id))) __IOSurface *IOSurfaceRef;
#else
typedef struct __IOSurface *IOSurfaceRef;
#endif
#endif
CGLError CGLTexImageIOSurface2D(CGLContextObj ctx, GLenum target, GLenum internal_format, GLsizei width,
                                GLsizei height, GLenum format, GLenum type, IOSurfaceRef ioSurface, GLuint plane);
__FERRY_END

#endif
