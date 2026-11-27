/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * A loaded image's sections and segments, from the getsectiondata(3) man
 * page. */
#ifndef _MACH_O_GETSECT_H_
#define _MACH_O_GETSECT_H_
#include <_ferry.h>
#include <mach-o/loader.h>
__FERRY_BEGIN
uint8_t *getsectiondata(const struct mach_header_64 *mhp, const char *segname, const char *sectname,
                        unsigned long *size);
uint8_t *getsegmentdata(const struct mach_header_64 *mhp, const char *segname, unsigned long *size);
const struct section_64 *getsectbynamefromheader_64(const struct mach_header_64 *mhp, const char *segname,
                                                    const char *sectname);
/* the main program's own (freemac Godot work) */
const struct segment_command_64 *getsegbyname(const char *segname);
const struct section_64 *getsectbyname(const char *segname, const char *sectname);
__FERRY_END
#endif
