/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Mach-O structures and constants that Ferry needs, written for freemac from
 * the publicly documented file format (the format is described in open
 * documentation and in permissively licensed open-source toolchains such as
 * LLVM). Only x86-64, 64-bit images are covered.
 */
#ifndef FERRY_MACHO_H
#define FERRY_MACHO_H
#include <stdint.h>

#define MACHO_MAGIC_64      0xfeedfacfu
#define MACHO_FAT_MAGIC     0xcafebabeu   /* stored big-endian */
#define MACHO_CPU_X86_64    0x01000007
#define MACHO_EXECUTE       0x2
#define MACHO_DYLIB         0x6
#define MACHO_BUNDLE        0x8   /* a plug-in, loaded with dlopen or NSBundle */
#define MACHO_FLAG_PIE      0x00200000u

#define LC_REQ_DYLD              0x80000000u
#define LC_SEGMENT_64            0x19
#define LC_SYMTAB                0x2
#define LC_DYSYMTAB              0xb
#define LC_UNIXTHREAD            0x5
#define LC_LOAD_DYLIB            0xc
#define LC_LOAD_WEAK_DYLIB       (0x18 | LC_REQ_DYLD)
#define LC_REEXPORT_DYLIB        (0x1f | LC_REQ_DYLD)
#define LC_DYLD_INFO             0x22
#define LC_DYLD_INFO_ONLY        (0x22 | LC_REQ_DYLD)
#define LC_MAIN                  (0x28 | LC_REQ_DYLD)
#define LC_DYLD_CHAINED_FIXUPS   (0x34 | LC_REQ_DYLD)
#define LC_DYLD_EXPORTS_TRIE     (0x33 | LC_REQ_DYLD)
#define LC_ID_DYLIB              0xd
#define LC_RPATH                 (0x1c | LC_REQ_DYLD)

/* section types (low byte of a section's flags) */
#define S_MOD_INIT_FUNC_POINTERS 0x9
#define S_INIT_FUNC_OFFSETS      0x16
/* thread-local variables (src/tlv.c) */
#define S_THREAD_LOCAL_REGULAR                0x11
#define S_THREAD_LOCAL_ZEROFILL               0x12
#define S_THREAD_LOCAL_VARIABLES              0x13
#define S_THREAD_LOCAL_VARIABLE_POINTERS      0x14
#define S_THREAD_LOCAL_INIT_FUNCTION_POINTERS 0x15

/* export trie */
#define EXPORT_KIND_MASK         0x3
#define EXPORT_KIND_ABSOLUTE     0x2
#define EXPORT_REEXPORT          0x8
#define EXPORT_STUB_AND_RESOLVER 0x10

struct macho_rpath { uint32_t cmd, cmdsize, path_offset; };

struct macho_header {
    uint32_t magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved;
};

struct macho_fat_header { uint32_t magic, nfat_arch; };            /* big-endian */
struct macho_fat_arch { uint32_t cputype, cpusubtype, offset, size, align; };

struct macho_load_command { uint32_t cmd, cmdsize; };

struct macho_segment {
    uint32_t cmd, cmdsize;
    char segname[16];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    uint32_t maxprot, initprot, nsects, flags;
};

struct macho_section {
    char sectname[16], segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};

struct macho_dylib_command {
    uint32_t cmd, cmdsize, name_offset, timestamp, current_version, compat_version;
};

struct macho_dyld_info {
    uint32_t cmd, cmdsize;
    uint32_t rebase_off, rebase_size, bind_off, bind_size;
    uint32_t weak_bind_off, weak_bind_size, lazy_bind_off, lazy_bind_size;
    uint32_t export_off, export_size;
};

struct macho_linkedit_data { uint32_t cmd, cmdsize, dataoff, datasize; };

struct macho_entry_point { uint32_t cmd, cmdsize; uint64_t entryoff, stacksize; };

/* The symbol table, and how its entries are grouped (LC_SYMTAB, LC_DYSYMTAB).
 * Libraries built before Mac OS X 10.6 have no LC_DYLD_INFO: they list
 * their fixups as relocation entries and symbol-pointer sections instead. */
struct macho_symtab { uint32_t cmd, cmdsize, symoff, nsyms, stroff, strsize; };
struct macho_dysymtab {
    uint32_t cmd, cmdsize;
    uint32_t ilocalsym, nlocalsym, iextdefsym, nextdefsym, iundefsym, nundefsym;
    uint32_t tocoff, ntoc, modtaboff, nmodtab, extrefsymoff, nextrefsyms;
    uint32_t indirectsymoff, nindirectsyms, extreloff, nextrel, locreloff, nlocrel;
};
struct macho_nlist { uint32_t n_strx; uint8_t n_type, n_sect; uint16_t n_desc; uint64_t n_value; };
struct macho_reloc { int32_t r_address; uint32_t r_info; };   /* symbolnum:24 pcrel:1 length:2 extern:1 type:4 */
#define N_TYPE_MASK   0x0e
#define N_ABS         0x2
#define N_SECT        0xe
#define N_EXT         0x01
#define N_STAB_MASK   0xe0
#define N_WEAK_REF    0x0040
#define S_TYPE_MASK               0xff
#define S_NON_LAZY_SYMBOL_POINTERS 0x6
#define S_LAZY_SYMBOL_POINTERS     0x7
#define INDIRECT_SYMBOL_LOCAL 0x80000000u
#define INDIRECT_SYMBOL_ABS   0x40000000u

/* Rebase and bind opcode streams (LC_DYLD_INFO). */
#define OPCODE_MASK     0xf0
#define IMMEDIATE_MASK  0x0f

#define REBASE_DONE                          0x00
#define REBASE_SET_TYPE_IMM                  0x10
#define REBASE_SET_SEGMENT_AND_OFFSET_ULEB   0x20
#define REBASE_ADD_ADDR_ULEB                 0x30
#define REBASE_ADD_ADDR_IMM_SCALED           0x40
#define REBASE_DO_REBASE_IMM_TIMES           0x50
#define REBASE_DO_REBASE_ULEB_TIMES          0x60
#define REBASE_DO_REBASE_ADD_ADDR_ULEB       0x70
#define REBASE_DO_REBASE_ULEB_TIMES_SKIPPING 0x80

#define BIND_DONE                            0x00
#define BIND_SET_DYLIB_ORDINAL_IMM           0x10
#define BIND_SET_DYLIB_ORDINAL_ULEB          0x20
#define BIND_SET_DYLIB_SPECIAL_IMM           0x30
#define BIND_SET_SYMBOL_FLAGS_IMM            0x40
#define BIND_SET_TYPE_IMM                    0x50
#define BIND_SET_ADDEND_SLEB                 0x60
#define BIND_SET_SEGMENT_AND_OFFSET_ULEB     0x70
#define BIND_ADD_ADDR_ULEB                   0x80
#define BIND_DO_BIND                         0x90
#define BIND_DO_BIND_ADD_ADDR_ULEB           0xa0
#define BIND_DO_BIND_ADD_ADDR_IMM_SCALED     0xb0
#define BIND_DO_BIND_ULEB_TIMES_SKIPPING     0xc0
#define BIND_THREADED                        0xd0

/* Chained fixups (LC_DYLD_CHAINED_FIXUPS). */
struct chained_fixups_header {
    uint32_t fixups_version, starts_offset, imports_offset, symbols_offset;
    uint32_t imports_count, imports_format, symbols_format;
};
struct chained_starts_in_segment {
    uint32_t size;
    uint16_t page_size, pointer_format;
    uint64_t segment_offset;
    uint32_t max_valid_pointer;
    uint16_t page_count;
    uint16_t page_start[];
};
#define CHAINED_PTR_START_NONE   0xffff
#define CHAINED_PTR_START_MULTI  0x8000
#define CHAINED_PTR_64           2
#define CHAINED_PTR_64_OFFSET    6
#define CHAINED_IMPORT           1
#define CHAINED_IMPORT_ADDEND    2
#define CHAINED_IMPORT_ADDEND64  3

#endif
