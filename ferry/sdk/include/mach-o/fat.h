/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The header of a universal ("fat") file, as the public Mach-O file format
 * reference describes it (freemac 1.232, Ferry 0.56.0). Its fields are
 * stored big-endian. */
#ifndef _FERRY_MACH_O_FAT_H_
#define _FERRY_MACH_O_FAT_H_
#include <_ferry.h>
#include <mach/machine.h>
__FERRY_BEGIN
#define FAT_MAGIC 0xcafebabe
#define FAT_CIGAM 0xbebafeca
#define FAT_MAGIC_64 0xcafebabf
#define FAT_CIGAM_64 0xbfbafeca
struct fat_header {
    uint32_t magic;
    uint32_t nfat_arch;
};
struct fat_arch {
    cpu_type_t cputype;
    cpu_subtype_t cpusubtype;
    uint32_t offset;
    uint32_t size;
    uint32_t align;
};
struct fat_arch_64 {
    cpu_type_t cputype;
    cpu_subtype_t cpusubtype;
    uint64_t offset;
    uint64_t size;
    uint32_t align;
    uint32_t reserved;
};
__FERRY_END
#endif
