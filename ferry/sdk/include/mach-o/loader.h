/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The Mach-O file's header and load commands, as the public Mach-O file
 * format reference describes them (freemac 1.221, Ferry 0.45.0). Ferry
 * loads programs in this format, so the images that _dyld_get_image_header
 * names begin with these structures. */
#ifndef _FERRY_MACH_O_LOADER_H_
#define _FERRY_MACH_O_LOADER_H_
#include <_ferry.h>
/* the processor types a header names */
#include <mach/machine.h>
__FERRY_BEGIN
typedef int vm_prot_t;

struct mach_header {
    uint32_t magic;
    cpu_type_t cputype;
    cpu_subtype_t cpusubtype;
    uint32_t filetype, ncmds, sizeofcmds, flags;
};
struct mach_header_64 {
    uint32_t magic;
    cpu_type_t cputype;
    cpu_subtype_t cpusubtype;
    uint32_t filetype, ncmds, sizeofcmds, flags, reserved;
};
#define MH_MAGIC 0xfeedface
#define MH_CIGAM 0xcefaedfe
#define MH_MAGIC_64 0xfeedfacf
#define MH_CIGAM_64 0xcffaedfe

#define MH_OBJECT 0x1
#define MH_EXECUTE 0x2
#define MH_DYLIB 0x6
#define MH_DYLINKER 0x7
#define MH_BUNDLE 0x8
#define MH_DSYM 0xa

#define MH_NOUNDEFS 0x1
#define MH_DYLDLINK 0x4
#define MH_TWOLEVEL 0x80
#define MH_PIE 0x200000

struct load_command { uint32_t cmd, cmdsize; };
#define LC_REQ_DYLD 0x80000000
#define LC_SEGMENT 0x1
#define LC_SYMTAB 0x2
#define LC_UNIXTHREAD 0x5
#define LC_DYSYMTAB 0xb
#define LC_LOAD_DYLIB 0xc
#define LC_ID_DYLIB 0xd
#define LC_LOAD_DYLINKER 0xe
#define LC_LOAD_WEAK_DYLIB (0x18 | LC_REQ_DYLD)
#define LC_SEGMENT_64 0x19
#define LC_UUID 0x1b
#define LC_RPATH (0x1c | LC_REQ_DYLD)
#define LC_CODE_SIGNATURE 0x1d
#define LC_REEXPORT_DYLIB (0x1f | LC_REQ_DYLD)
#define LC_DYLD_INFO 0x22
#define LC_DYLD_INFO_ONLY (0x22 | LC_REQ_DYLD)
#define LC_VERSION_MIN_MACOSX 0x24
#define LC_FUNCTION_STARTS 0x26
#define LC_MAIN (0x28 | LC_REQ_DYLD)
#define LC_DATA_IN_CODE 0x29
#define LC_SOURCE_VERSION 0x2a
#define LC_BUILD_VERSION 0x32
#define LC_DYLD_EXPORTS_TRIE (0x33 | LC_REQ_DYLD)
#define LC_DYLD_CHAINED_FIXUPS (0x34 | LC_REQ_DYLD)

struct segment_command {
    uint32_t cmd, cmdsize;
    char segname[16];
    uint32_t vmaddr, vmsize, fileoff, filesize;
    vm_prot_t maxprot, initprot;
    uint32_t nsects, flags;
};
struct segment_command_64 {
    uint32_t cmd, cmdsize;
    char segname[16];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    vm_prot_t maxprot, initprot;
    uint32_t nsects, flags;
};
struct section {
    char sectname[16], segname[16];
    uint32_t addr, size, offset, align, reloff, nreloc, flags, reserved1, reserved2;
};
struct section_64 {
    char sectname[16], segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};
#define SEG_PAGEZERO "__PAGEZERO"
#define SEG_TEXT "__TEXT"
#define SEG_DATA "__DATA"
#define SEG_LINKEDIT "__LINKEDIT"
#define SECT_TEXT "__text"

struct uuid_command { uint32_t cmd, cmdsize; uint8_t uuid[16]; };
struct entry_point_command { uint32_t cmd, cmdsize; uint64_t entryoff, stacksize; };
struct symtab_command { uint32_t cmd, cmdsize, symoff, nsyms, stroff, strsize; };
union lc_str { uint32_t offset; };
struct dylib {
    union lc_str name;
    uint32_t timestamp, current_version, compatibility_version;
};
struct dylib_command { uint32_t cmd, cmdsize; struct dylib dylib; };
struct rpath_command { uint32_t cmd, cmdsize; union lc_str path; };
struct linkedit_data_command { uint32_t cmd, cmdsize, dataoff, datasize; };
struct build_version_command { uint32_t cmd, cmdsize, platform, minos, sdk, ntools; };
__FERRY_END
#endif
