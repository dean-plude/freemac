/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Core OpenGL (CGL), the Mac's own calls for OpenGL pixel
 * formats, contexts and drawables (freemac 1.235, Ferry 0.59.0). Written
 * for freemac from Apple's public CGL reference; not Apple's header. Every
 * call declared here is implemented in ferry/opengl, on this system's
 * OpenGL through EGL (see docs/ferry-compat.md, "OpenGL and Core Video").
 * The OpenGL calls themselves are in <OpenGL/gl.h> and <OpenGL/gl3.h>. */
#ifndef _FERRY_OPENGL_OPENGL_H_
#define _FERRY_OPENGL_OPENGL_H_
#include <OpenGL/CGLTypes.h>
#include <OpenGL/CGLCurrent.h>
#include <OpenGL/CGLRenderers.h>
#include <OpenGL/CGLIOSurface.h>
#include <OpenGL/CGLDevice.h>

__FERRY_BEGIN

#define CGL_VERSION_1_0 1
#define CGL_VERSION_1_1 1
#define CGL_VERSION_1_2 1
#define CGL_VERSION_1_3 1

/* pixel formats */
CGLError CGLChoosePixelFormat(const CGLPixelFormatAttribute *attribs, CGLPixelFormatObj *pix, GLint *npix);
CGLError CGLDestroyPixelFormat(CGLPixelFormatObj pix);
CGLError CGLDescribePixelFormat(CGLPixelFormatObj pix, GLint pix_num, CGLPixelFormatAttribute attrib, GLint *value);
void CGLReleasePixelFormat(CGLPixelFormatObj pix);
CGLPixelFormatObj CGLRetainPixelFormat(CGLPixelFormatObj pix);
GLuint CGLGetPixelFormatRetainCount(CGLPixelFormatObj pix);

/* renderers */
CGLError CGLQueryRendererInfo(GLuint display_mask, CGLRendererInfoObj *rend, GLint *nrend);
CGLError CGLDestroyRendererInfo(CGLRendererInfoObj rend);
CGLError CGLDescribeRenderer(CGLRendererInfoObj rend, GLint rend_num, CGLRendererProperty prop, GLint *value);

/* contexts */
CGLError CGLCreateContext(CGLPixelFormatObj pix, CGLContextObj share, CGLContextObj *ctx);
CGLError CGLDestroyContext(CGLContextObj ctx);
CGLError CGLCopyContext(CGLContextObj src, CGLContextObj dst, GLbitfield mask);
CGLContextObj CGLRetainContext(CGLContextObj ctx);
void CGLReleaseContext(CGLContextObj ctx);
GLuint CGLGetContextRetainCount(CGLContextObj ctx);
CGLPixelFormatObj CGLGetPixelFormat(CGLContextObj ctx);
CGLShareGroupObj CGLGetShareGroup(CGLContextObj ctx);

/* drawables */
CGLError CGLCreatePBuffer(GLsizei width, GLsizei height, GLenum target, GLenum internalFormat, GLint max_level,
                          CGLPBufferObj *pbuffer);
CGLError CGLDestroyPBuffer(CGLPBufferObj pbuffer);
CGLError CGLDescribePBuffer(CGLPBufferObj obj, GLsizei *width, GLsizei *height, GLenum *target,
                            GLenum *internalFormat, GLint *mipmap);
CGLError CGLTexImagePBuffer(CGLContextObj ctx, CGLPBufferObj pbuffer, GLenum source);
CGLPBufferObj CGLRetainPBuffer(CGLPBufferObj pbuffer);
void CGLReleasePBuffer(CGLPBufferObj pbuffer);
GLuint CGLGetPBufferRetainCount(CGLPBufferObj pbuffer);
CGLError CGLSetOffScreen(CGLContextObj ctx, GLsizei width, GLsizei height, GLint rowbytes, void *baseaddr);
CGLError CGLGetOffScreen(CGLContextObj ctx, GLsizei *width, GLsizei *height, GLint *rowbytes, void **baseaddr);
CGLError CGLSetFullScreen(CGLContextObj ctx);
CGLError CGLSetFullScreenOnDisplay(CGLContextObj ctx, GLuint display_mask);
CGLError CGLSetPBuffer(CGLContextObj ctx, CGLPBufferObj pbuffer, GLenum face, GLint level, GLint screen);
CGLError CGLGetPBuffer(CGLContextObj ctx, CGLPBufferObj *pbuffer, GLenum *face, GLint *level, GLint *screen);
CGLError CGLClearDrawable(CGLContextObj ctx);
CGLError CGLFlushDrawable(CGLContextObj ctx);

/* options */
CGLError CGLEnable(CGLContextObj ctx, CGLContextEnable pname);
CGLError CGLDisable(CGLContextObj ctx, CGLContextEnable pname);
CGLError CGLIsEnabled(CGLContextObj ctx, CGLContextEnable pname, GLint *enable);
CGLError CGLSetParameter(CGLContextObj ctx, CGLContextParameter pname, const GLint *params);
CGLError CGLGetParameter(CGLContextObj ctx, CGLContextParameter pname, GLint *params);
CGLError CGLSetVirtualScreen(CGLContextObj ctx, GLint screen);
CGLError CGLGetVirtualScreen(CGLContextObj ctx, GLint *screen);
CGLError CGLUpdateContext(CGLContextObj ctx);
CGLError CGLSetGlobalOption(CGLGlobalOption pname, const GLint *params);
CGLError CGLGetGlobalOption(CGLGlobalOption pname, GLint *params);
CGLError CGLSetOption(CGLGlobalOption pname, GLint param);
CGLError CGLGetOption(CGLGlobalOption pname, GLint *param);

/* locks: recursive, one per context */
CGLError CGLLockContext(CGLContextObj ctx);
CGLError CGLUnlockContext(CGLContextObj ctx);

void CGLGetVersion(GLint *majorvers, GLint *minorvers);
const char *CGLErrorString(CGLError error);

__FERRY_END

#endif
