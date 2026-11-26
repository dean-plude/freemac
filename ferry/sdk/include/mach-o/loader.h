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
#define LC_VERSION_MIN_IPHONEOS 0x25
#define LC_VERSION_MIN_TVOS 0x2f
#define LC_VERSION_MIN_WATCHOS 0x30
#define LC_ENCRYPTION_INFO 0x21
#define LC_ENCRYPTION_INFO_64 0x2C
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
/* where an encrypted program's encrypted part lies; cryptid 0 is not encrypted */
struct encryption_info_command { uint32_t cmd, cmdsize, cryptoff, cryptsize, cryptid; };
struct encryption_info_command_64 { uint32_t cmd, cmdsize, cryptoff, cryptsize, cryptid, pad; };
struct build_version_command { uint32_t cmd, cmdsize, platform, minos, sdk, ntools; };
/* the older form of the system version a program was built for and against (freemac 1.232) */
struct version_min_command { uint32_t cmd, cmdsize, version, sdk; };
#define PLATFORM_MACOS 1
#define PLATFORM_IOS 2
#define PLATFORM_TVOS 3
#define PLATFORM_WATCHOS 4
#define PLATFORM_BRIDGEOS 5
#define PLATFORM_MACCATALYST 6
#define PLATFORM_IOSSIMULATOR 7
#define PLATFORM_TVOSSIMULATOR 8
#define PLATFORM_WATCHOSSIMULATOR 9
#define PLATFORM_DRIVERKIT 10
#define PLATFORM_VISIONOS 11
#define PLATFORM_VISIONOSSIMULATOR 12
/* the dynamic symbol table, and the types of sections (freemac 1.227) */
struct dysymtab_command {
    uint32_t cmd, cmdsize;
    uint32_t ilocalsym, nlocalsym, iextdefsym, nextdefsym, iundefsym, nundefsym;
    uint32_t tocoff, ntoc, modtaboff, nmodtab, extrefsymoff, nextrefsyms;
    uint32_t indirectsymoff, nindirectsyms, extreloff, nextrel, locreloff, nlocrel;
};
#define LC_ROUTINES 0x11
#define LC_ROUTINES_64 0x1a
#define INDIRECT_SYMBOL_LOCAL 0x80000000
#define INDIRECT_SYMBOL_ABS 0x40000000
#define SECTION_TYPE 0x000000ff
#define SECTION_ATTRIBUTES 0xffffff00
#define S_REGULAR 0x0
#define S_ZEROFILL 0x1
#define S_CSTRING_LITERALS 0x2
#define S_NON_LAZY_SYMBOL_POINTERS 0x6
#define S_LAZY_SYMBOL_POINTERS 0x7
#define S_SYMBOL_STUBS 0x8
#define S_MOD_INIT_FUNC_POINTERS 0x9
#define S_THREAD_LOCAL_VARIABLES 0x13
__FERRY_END
#endif
