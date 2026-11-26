/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: OpenGL's calls and constants for the core profiles (3.2 and
 * 4.1 on a Mac), as a Mac program includes them (freemac 1.235, Ferry
 * 0.59.0). The declarations are this system's own core-profile header
 * (the Khronos registry's glcorearb.h), laid out in the SDK when Ferry is
 * built (sdk/gen-opengl-headers.sh); see <OpenGL/gl.h>. */
#ifndef _FERRY_OPENGL_GL3_H_
#define _FERRY_OPENGL_GL3_H_
#define __gl3_h_ 1
#include <OpenGL/gltypes.h>
#if __has_include("../../usr/include/GL/glcorearb.h")
#ifndef GL_GLEXT_PROTOTYPES
#define GL_GLEXT_PROTOTYPES 1
#endif
#include "../../usr/include/GL/glcorearb.h"
#elif defined(__building_module) && __building_module(OpenGL)
/* building the OpenGL module, which CoreVideo's and AppKit's import, where
 * Ferry was built without this system's OpenGL headers: the module has
 * CGL's calls and types but no GL calls (freemac 1.258) */
#else
#error "Ferry's SDK has no OpenGL headers: this system's OpenGL headers (libgl-dev) weren't installed when Ferry was built"
#endif
#endif
