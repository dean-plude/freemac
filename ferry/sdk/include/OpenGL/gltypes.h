/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: OpenGL's basic types (freemac 1.235, Ferry 0.59.0), as the
 * OpenGL specification's type table defines them for a 64-bit Intel Mac.
 * Written for freemac; not Apple's header. The full OpenGL headers
 * (gl.h, gl3.h, glext.h) define the same types again, identically. */
#ifndef _FERRY_OPENGL_GLTYPES_H_
#define _FERRY_OPENGL_GLTYPES_H_
#include <stdint.h>
#include <stddef.h>

typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef float GLfloat;
typedef float GLclampf;
typedef double GLdouble;
typedef double GLclampd;
typedef void GLvoid;
typedef char GLchar;
typedef char GLcharARB;
typedef uint16_t GLhalf;
typedef uint16_t GLhalfARB;
typedef int32_t GLfixed;
typedef long GLintptr;
typedef long GLsizeiptr;
typedef long GLintptrARB;
typedef long GLsizeiptrARB;
typedef int64_t GLint64;
typedef uint64_t GLuint64;
typedef int64_t GLint64EXT;
typedef uint64_t GLuint64EXT;
typedef struct __GLsync *GLsync;
/* a pointer on a Mac, as the specification's headers have it there */
typedef void *GLhandleARB;

#endif
