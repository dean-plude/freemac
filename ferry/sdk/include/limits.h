/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The compiler's own limits.h, and with it the system limits a Mac's
 * limits.h gives through sys/syslimits.h (freemac 1.221, Ferry 0.45.0). */
#ifndef _FERRY_LIMITS_H_
#define _FERRY_LIMITS_H_
#include_next <limits.h>
#include <sys/syslimits.h>
/* the least POSIX lets a system give (freemac 1.232, Ferry 0.56.0) */
#ifndef _POSIX_ARG_MAX
#define _POSIX_ARG_MAX 4096
#endif
#ifndef _POSIX_CHILD_MAX
#define _POSIX_CHILD_MAX 25
#endif
#ifndef _POSIX_HOST_NAME_MAX
#define _POSIX_HOST_NAME_MAX 255
#endif
#ifndef _POSIX_LINK_MAX
#define _POSIX_LINK_MAX 8
#endif
#ifndef _POSIX_LOGIN_NAME_MAX
#define _POSIX_LOGIN_NAME_MAX 9
#endif
#ifndef _POSIX_MAX_CANON
#define _POSIX_MAX_CANON 255
#endif
#ifndef _POSIX_MAX_INPUT
#define _POSIX_MAX_INPUT 255
#endif
#ifndef _POSIX_NAME_MAX
#define _POSIX_NAME_MAX 14
#endif
#ifndef _POSIX_NGROUPS_MAX
#define _POSIX_NGROUPS_MAX 8
#endif
#ifndef _POSIX_OPEN_MAX
#define _POSIX_OPEN_MAX 20
#endif
#ifndef _POSIX_PATH_MAX
#define _POSIX_PATH_MAX 256
#endif
#ifndef _POSIX_PIPE_BUF
#define _POSIX_PIPE_BUF 512
#endif
#ifndef _POSIX_SSIZE_MAX
#define _POSIX_SSIZE_MAX 32767
#endif
#ifndef _POSIX_STREAM_MAX
#define _POSIX_STREAM_MAX 8
#endif
#ifndef _POSIX_SYMLINK_MAX
#define _POSIX_SYMLINK_MAX 255
#endif
#ifndef _POSIX_SYMLOOP_MAX
#define _POSIX_SYMLOOP_MAX 8
#endif
#ifndef _POSIX_THREAD_KEYS_MAX
#define _POSIX_THREAD_KEYS_MAX 128
#endif
#ifndef _POSIX_THREAD_THREADS_MAX
#define _POSIX_THREAD_THREADS_MAX 64
#endif
#ifndef _POSIX_TTY_NAME_MAX
#define _POSIX_TTY_NAME_MAX 9
#endif
#ifndef _POSIX_TZNAME_MAX
#define _POSIX_TZNAME_MAX 6
#endif
#endif
