/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: OpenGL's calls and constants for the legacy profile (OpenGL
 * 2.1 and the extensions), as a Mac program includes them (freemac 1.235,
 * Ferry 0.59.0). Ferry's OpenGL framework passes the calls to this
 * system's OpenGL, so the declarations are this system's own OpenGL
 * headers (the Khronos registry's), laid out in the SDK when Ferry is
 * built (sdk/gen-opengl-headers.sh) as libxml2's are. As on a Mac, every
 * call is declared with no need for GL_GLEXT_PROTOTYPES. */
#ifndef _FERRY_OPENGL_GL_H_
#define _FERRY_OPENGL_GL_H_
#include <OpenGL/gltypes.h>
#if __has_include("../../usr/include/GL/gl.h")
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES 1
#endif
#include "../../usr/include/GL/gl.h"
#include "../../usr/include/GL/glext.h"
#elif defined(__building_module) && __building_module(OpenGL)
/* building the OpenGL module, which CoreVideo's and AppKit's import, where
 * Ferry was built without this system's OpenGL headers: the module has
 * CGL's calls and types but no GL calls (freemac 1.258) */
#else
#error "Ferry's SDK has no OpenGL headers: this system's OpenGL headers (libgl-dev) weren't installed when Ferry was built"
#endif
#endif
