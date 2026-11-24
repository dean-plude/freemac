/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
#ifndef _SYS_IOCTL_H_
#define _SYS_IOCTL_H_
#include <_ferry.h>
__FERRY_BEGIN
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
#define TIOCGWINSZ 0x40087468ul
#define FIONREAD 0x4004667ful
#define FIONBIO 0x8004667eul
int ioctl(int, unsigned long, ...);
__FERRY_END
#endif
