/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The loaded images and the program's own path, from the dyld(3) man
 * page. */
#ifndef _MACH_O_DYLD_H_
#define _MACH_O_DYLD_H_
#include <_ferry.h>
__FERRY_BEGIN
struct mach_header;
uint32_t _dyld_image_count(void);
const struct mach_header *_dyld_get_image_header(uint32_t image_index);
intptr_t _dyld_get_image_vmaddr_slide(uint32_t image_index);
const char *_dyld_get_image_name(uint32_t image_index);
void _dyld_register_func_for_add_image(void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide));
void _dyld_register_func_for_remove_image(void (*func)(const struct mach_header *mh, intptr_t vmaddr_slide));
int _NSGetExecutablePath(char *buf, uint32_t *bufsize);
__FERRY_END
#endif
