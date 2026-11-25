/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The system limits with the Mac's values, as sysconf(3) and intro(2)
 * document them (freemac 1.221, Ferry 0.45.0). */
#ifndef _FERRY_SYS_SYSLIMITS_H_
#define _FERRY_SYS_SYSLIMITS_H_
#define ARG_MAX (1024 * 1024)
#define CHILD_MAX 266
#define GID_MAX 2147483647U
#define LINK_MAX 32767
#define MAX_CANON 1024
#define MAX_INPUT 1024
#define NAME_MAX 255
#define NGROUPS_MAX 16
#define UID_MAX 2147483647U
#define OPEN_MAX 10240
#define PATH_MAX 1024
#define PIPE_BUF 512
#define BC_BASE_MAX 99
#define BC_DIM_MAX 2048
#define BC_SCALE_MAX 99
#define BC_STRING_MAX 1000
#define CHARCLASS_NAME_MAX 14
#define COLL_WEIGHTS_MAX 2
#define EQUIV_CLASS_MAX 2
#define EXPR_NEST_MAX 32
#define LINE_MAX 2048
#define RE_DUP_MAX 255
#define NZERO 20
#define IOV_MAX 1024
#endif
