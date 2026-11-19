/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Mach-O loader: maps an x86-64 Mach-O executable into this process,
 * applies its rebases and binds (classic opcode streams or chained fixups),
 * points every imported libSystem symbol at Ferry's own implementation, and
 * calls its main().
 *
 * Both macOS and Linux use the System V AMD64 calling convention, so a Mac
 * program can call C functions here directly; shim.c converts the places
 * where the two systems' data layouts or numbers differ.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ferry.h"
#include "macho.h"

#define PAGE 4096ul
#define ALIGN_DOWN(x) ((x) & ~(PAGE - 1))
#define ALIGN_UP(x) (((x) + PAGE - 1) & ~(PAGE - 1))
#define MAX_SEGMENTS 32
#define MAX_DYLIBS 64

struct segment {
    char name[17];
    uint64_t vmaddr, vmsize, fileoff, filesize;
    uint32_t prot;
};

struct image {
    const char *path;
    uint8_t *file;          /* the whole file (or fat slice) in memory */
    size_t size;
    struct macho_header *header;
    struct segment seg[MAX_SEGMENTS];
    int nseg;
    int64_t slide;
    const char *dylibs[MAX_DYLIBS];
    int ndylibs;
    struct macho_dyld_info *dyld_info;
    struct macho_linkedit_data *chained;
    uint64_t entryoff;
    int has_main;
};

int ferry_verbose;

__attribute__((noreturn, format(printf, 1, 2))) static void die(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fputs("ferry: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
    exit(126);
}

__attribute__((format(printf, 1, 2))) static void note(const char *fmt, ...)
{
    if (!ferry_verbose)
        return;
    va_list ap;
    va_start(ap, fmt);
    fputs("ferry: ", stderr);
    vfprintf(stderr, fmt, ap);
    fputc('\n', stderr);
    va_end(ap);
}

static uint64_t uleb(const uint8_t **p, const uint8_t *end)
{
    uint64_t value = 0;
    int shift = 0;
    while (*p < end) {
        uint8_t byte = *(*p)++;
        if (shift < 64)
            value |= (uint64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    return value;
}

static int64_t sleb(const uint8_t **p, const uint8_t *end)
{
    int64_t value = 0;
    int shift = 0;
    uint8_t byte = 0;
    while (*p < end) {
        byte = *(*p)++;
        if (shift < 64)
            value |= (int64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    if (shift < 64 && (byte & 0x40))
        value |= -((int64_t)1 << shift);
    return value;
}

/* ---- reading the file ------------------------------------------------------ */

static void read_file(struct image *im, const char *path)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        die("can't open %s: %s", path, strerror(errno));
    struct stat st;
    if (fstat(fd, &st) < 0 || st.st_size < (off_t)sizeof(struct macho_header))
        die("%s is not a Mac program", path);
    uint8_t *data = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (data == MAP_FAILED)
        die("can't read %s: %s", path, strerror(errno));
    im->path = path;
    im->file = data;
    im->size = st.st_size;

    /* A universal ("fat") file holds several architectures; pick x86-64. */
    if (__builtin_bswap32(*(uint32_t *)data) == MACHO_FAT_MAGIC) {
        struct macho_fat_header *fat = (void *)data;
        uint32_t n = __builtin_bswap32(fat->nfat_arch);
        struct macho_fat_arch *arch = (void *)(fat + 1);
        int found = 0;
        for (uint32_t i = 0; i < n && (uint8_t *)(arch + i + 1) <= data + im->size; i++) {
            if (__builtin_bswap32(arch[i].cputype) == MACHO_CPU_X86_64) {
                uint32_t off = __builtin_bswap32(arch[i].offset);
                uint32_t size = __builtin_bswap32(arch[i].size);
                if ((uint64_t)off + size > im->size)
                    die("%s: damaged universal file", path);
                im->file = data + off;
                im->size = size;
                found = 1;
                break;
            }
        }
        if (!found)
            die("%s has no Intel (x86-64) version; programs built only for Apple silicon can't run on a PC", path);
    }
    im->header = (void *)im->file;
    if (im->header->magic != MACHO_MAGIC_64)
        die("%s is not a 64-bit Mac program", path);
    if (im->header->cputype != MACHO_CPU_X86_64)
        die("%s is built for Apple silicon (arm64), not for a PC's Intel/AMD processor", path);
    if (im->header->filetype != MACHO_EXECUTE)
        die("%s is a library or other Mach-O file, not a program", path);
}

static void parse_commands(struct image *im)
{
    uint8_t *p = (uint8_t *)(im->header + 1);
    uint8_t *end = p + im->header->sizeofcmds;
    if (end > im->file + im->size)
        die("%s: load commands run past the end of the file", im->path);
    for (uint32_t i = 0; i < im->header->ncmds; i++) {
        struct macho_load_command *lc = (void *)p;
        if (p + sizeof *lc > end || lc->cmdsize < sizeof *lc || p + lc->cmdsize > end)
            die("%s: damaged load command", im->path);
        switch (lc->cmd) {
        case LC_SEGMENT_64: {
            struct macho_segment *s = (void *)lc;
            if (s->vmsize == 0 || (s->initprot == 0 && s->filesize == 0 && s->vmaddr == 0))
                break;      /* __PAGEZERO: nothing to map */
            if (im->nseg == MAX_SEGMENTS)
                die("%s: too many segments", im->path);
            struct segment *seg = &im->seg[im->nseg++];
            memcpy(seg->name, s->segname, 16);
            seg->name[16] = 0;
            seg->vmaddr = s->vmaddr;
            seg->vmsize = s->vmsize;
            seg->fileoff = s->fileoff;
            seg->filesize = s->filesize;
            seg->prot = s->initprot;
            if (s->fileoff + s->filesize > im->size)
                die("%s: segment %s runs past the end of the file", im->path, seg->name);
            break;
        }
        case LC_LOAD_DYLIB:
        case LC_LOAD_WEAK_DYLIB:
        case LC_REEXPORT_DYLIB: {
            struct macho_dylib_command *d = (void *)lc;
            if (im->ndylibs < MAX_DYLIBS)
                im->dylibs[im->ndylibs++] = (const char *)lc + d->name_offset;
            if (lc->cmd != LC_LOAD_WEAK_DYLIB && !ferry_library_supported((const char *)lc + d->name_offset))
                die("%s needs %s, which Ferry doesn't provide yet", im->path,
                    (const char *)lc + d->name_offset);
            break;
        }
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY:
            im->dyld_info = (void *)lc;
            break;
        case LC_DYLD_CHAINED_FIXUPS:
            im->chained = (void *)lc;
            break;
        case LC_MAIN:
            im->entryoff = ((struct macho_entry_point *)lc)->entryoff;
            im->has_main = 1;
            break;
        case LC_UNIXTHREAD:
            die("%s uses an old start-up format (LC_UNIXTHREAD) that Ferry doesn't support", im->path);
        default:
            break;
        }
        p += lc->cmdsize;
    }
    if (!im->nseg)
        die("%s has nothing to load", im->path);
    if (!im->has_main)
        die("%s has no main entry point", im->path);
}

/* ---- mapping ----------------------------------------------------------------- */

static int to_prot(uint32_t vmprot)
{
    return (vmprot & 1 ? PROT_READ : 0) | (vmprot & 2 ? PROT_WRITE : 0) | (vmprot & 4 ? PROT_EXEC : 0);
}

static void map_segments(struct image *im)
{
    uint64_t low = UINT64_MAX, high = 0;
    for (int i = 0; i < im->nseg; i++) {
        if (im->seg[i].vmaddr < low)
            low = im->seg[i].vmaddr;
        if (im->seg[i].vmaddr + im->seg[i].vmsize > high)
            high = im->seg[i].vmaddr + im->seg[i].vmsize;
    }
    low = ALIGN_DOWN(low);
    high = ALIGN_UP(high);
    void *want = (im->header->flags & MACHO_FLAG_PIE) ? NULL : (void *)low;
    int flags = MAP_PRIVATE | MAP_ANONYMOUS | (want ? MAP_FIXED_NOREPLACE : 0);
    uint8_t *base = mmap(want, high - low, PROT_NONE, flags, -1, 0);
    if (base == MAP_FAILED)
        die("can't reserve memory for %s at %#lx: %s", im->path, (unsigned long)low, strerror(errno));
    if (want && base != want)
        die("%s must load at %#lx, which is in use", im->path, (unsigned long)low);
    im->slide = (int64_t)((uint64_t)base - low);
    note("loading %s at %p (slide %#lx)", im->path, (void *)base, (unsigned long)im->slide);
    for (int i = 0; i < im->nseg; i++) {
        struct segment *s = &im->seg[i];
        uint8_t *addr = (uint8_t *)(s->vmaddr + im->slide);
        uint64_t len = ALIGN_UP(s->vmsize);
        /* Writable while fixups are applied; final protection comes later. */
        if (mprotect(addr, len, PROT_READ | PROT_WRITE) < 0)
            die("mprotect failed for %s: %s", s->name, strerror(errno));
        if (s->filesize)
            memcpy(addr, im->file + s->fileoff, s->filesize < s->vmsize ? s->filesize : s->vmsize);
        note("  %-16s %p %#lx bytes", s->name, (void *)addr, (unsigned long)s->vmsize);
    }
}

static void protect_segments(struct image *im)
{
    for (int i = 0; i < im->nseg; i++) {
        struct segment *s = &im->seg[i];
        if (mprotect((void *)(s->vmaddr + im->slide), ALIGN_UP(s->vmsize), to_prot(s->prot)) < 0)
            die("mprotect failed for %s: %s", s->name, strerror(errno));
    }
}

static uint8_t *seg_addr(struct image *im, unsigned index, uint64_t offset)
{
    /* Segment indexes in fixups count every LC_SEGMENT_64, __PAGEZERO included;
     * we skipped __PAGEZERO, so look the segment up by walking the commands. */
    uint8_t *p = (uint8_t *)(im->header + 1);
    unsigned seen = 0;
    for (uint32_t i = 0; i < im->header->ncmds; i++) {
        struct macho_load_command *lc = (void *)p;
        if (lc->cmd == LC_SEGMENT_64) {
            if (seen == index) {
                struct macho_segment *s = (void *)lc;
                if (offset >= s->vmsize)
                    die("%s: fixup outside segment %.16s", im->path, s->segname);
                return (uint8_t *)(s->vmaddr + im->slide + offset);
            }
            seen++;
        }
        p += lc->cmdsize;
    }
    die("%s: fixup names a missing segment %u", im->path, index);
    return NULL;
}

static const char *strip_symbol(const char *name, char *buf, size_t size)
{
    /* Mac C symbols start with an underscore; drop it. Some carry a variant
     * suffix such as "$INODE64" or "$DARWIN_EXTSN", which keeps its meaning. */
    if (name[0] == '_')
        name++;
    snprintf(buf, size, "%s", name);
    return buf;
}

static void *resolve(struct image *im, const char *raw, int weak)
{
    char name[256];
    strip_symbol(raw, name, sizeof name);
    void *addr = ferry_lookup(name);
    if (!addr) {
        if (weak)
            return NULL;
        addr = ferry_missing_stub(raw);
        note("  missing %s", raw);
    }
    (void)im;
    return addr;
}

/* ---- classic rebase and bind opcodes ---------------------------------------- */

static void do_rebases(struct image *im)
{
    if (!im->dyld_info || !im->dyld_info->rebase_size || !im->slide)
        return;
    const uint8_t *p = im->file + im->dyld_info->rebase_off;
    const uint8_t *end = p + im->dyld_info->rebase_size;
    unsigned seg = 0;
    uint64_t off = 0;
    int count = 0;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t op = byte & OPCODE_MASK, imm = byte & IMMEDIATE_MASK;
        uint64_t times, skip;
        switch (op) {
        case REBASE_DONE:
            p = end;
            break;
        case REBASE_SET_TYPE_IMM:
            break;
        case REBASE_SET_SEGMENT_AND_OFFSET_ULEB:
            seg = imm;
            off = uleb(&p, end);
            break;
        case REBASE_ADD_ADDR_ULEB:
            off += uleb(&p, end);
            break;
        case REBASE_ADD_ADDR_IMM_SCALED:
            off += imm * 8;
            break;
        case REBASE_DO_REBASE_IMM_TIMES:
        case REBASE_DO_REBASE_ULEB_TIMES:
            times = op == REBASE_DO_REBASE_IMM_TIMES ? imm : uleb(&p, end);
            while (times--) {
                *(uint64_t *)seg_addr(im, seg, off) += im->slide;
                off += 8;
                count++;
            }
            break;
        case REBASE_DO_REBASE_ADD_ADDR_ULEB:
            *(uint64_t *)seg_addr(im, seg, off) += im->slide;
            off += 8 + uleb(&p, end);
            count++;
            break;
        case REBASE_DO_REBASE_ULEB_TIMES_SKIPPING:
            times = uleb(&p, end);
            skip = uleb(&p, end);
            while (times--) {
                *(uint64_t *)seg_addr(im, seg, off) += im->slide;
                off += 8 + skip;
                count++;
            }
            break;
        default:
            die("%s: unknown rebase opcode %#x", im->path, op);
        }
    }
    note("applied %d rebases", count);
}

static void do_binds(struct image *im, uint32_t offset, uint32_t size, int lazy, int weak_stream)
{
    if (!size)
        return;
    const uint8_t *p = im->file + offset;
    const uint8_t *end = p + size;
    unsigned seg = 0;
    uint64_t off = 0, times, skip;
    int64_t addend = 0;
    const char *symbol = NULL;
    int weak = 0, count = 0;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t op = byte & OPCODE_MASK, imm = byte & IMMEDIATE_MASK;
        switch (op) {
        case BIND_DONE:
            if (!lazy)
                p = end;
            break;
        case BIND_SET_DYLIB_ORDINAL_IMM:
        case BIND_SET_DYLIB_SPECIAL_IMM:
            break;
        case BIND_SET_DYLIB_ORDINAL_ULEB:
            uleb(&p, end);
            break;
        case BIND_SET_SYMBOL_FLAGS_IMM:
            symbol = (const char *)p;
            weak = imm & 1;
            p += strnlen(symbol, end - p) + 1;
            break;
        case BIND_SET_TYPE_IMM:
            break;
        case BIND_SET_ADDEND_SLEB:
            addend = sleb(&p, end);
            break;
        case BIND_SET_SEGMENT_AND_OFFSET_ULEB:
            seg = imm;
            off = uleb(&p, end);
            break;
        case BIND_ADD_ADDR_ULEB:
            off += uleb(&p, end);
            break;
        case BIND_DO_BIND:
        case BIND_DO_BIND_ADD_ADDR_ULEB:
        case BIND_DO_BIND_ADD_ADDR_IMM_SCALED:
        case BIND_DO_BIND_ULEB_TIMES_SKIPPING:
            if (op == BIND_DO_BIND_ULEB_TIMES_SKIPPING) {
                times = uleb(&p, end);
                skip = uleb(&p, end);
            } else {
                times = 1;
                skip = 0;
            }
            while (times--) {
                if (!symbol)
                    die("%s: bind without a symbol", im->path);
                void *target = resolve(im, symbol, weak || weak_stream);
                if (target || !weak_stream)
                    *(uint64_t *)seg_addr(im, seg, off) = (uint64_t)target + addend;
                off += 8 + skip;
                count++;
            }
            if (op == BIND_DO_BIND_ADD_ADDR_ULEB)
                off += uleb(&p, end);
            else if (op == BIND_DO_BIND_ADD_ADDR_IMM_SCALED)
                off += imm * 8;
            break;
        case BIND_THREADED:
            die("%s uses threaded binds, which Ferry doesn't support", im->path);
        default:
            die("%s: unknown bind opcode %#x", im->path, op);
        }
    }
    note("applied %d %s binds", count, lazy ? "lazy" : weak_stream ? "weak" : "regular");
}

/* ---- chained fixups ------------------------------------------------------------ */

static void do_chained(struct image *im)
{
    const uint8_t *data = im->file + im->chained->dataoff;
    const struct chained_fixups_header *h = (const void *)data;
    if (h->fixups_version != 0)
        die("%s: unknown chained fixups version %u", im->path, h->fixups_version);
    if (h->symbols_format != 0)
        die("%s: compressed symbol names aren't supported", im->path);
    const char *symbols = (const char *)data + h->symbols_offset;
    void **targets = calloc(h->imports_count ? h->imports_count : 1, sizeof *targets);
    int64_t *addends = calloc(h->imports_count ? h->imports_count : 1, sizeof *addends);
    for (uint32_t i = 0; i < h->imports_count; i++) {
        uint32_t name_off;
        int weak;
        if (h->imports_format == CHAINED_IMPORT) {
            uint32_t v = ((const uint32_t *)(data + h->imports_offset))[i];
            weak = (v >> 8) & 1;
            name_off = v >> 9;
        } else if (h->imports_format == CHAINED_IMPORT_ADDEND) {
            const uint32_t *v = (const uint32_t *)(data + h->imports_offset) + i * 2;
            weak = (v[0] >> 8) & 1;
            name_off = v[0] >> 9;
            addends[i] = (int32_t)v[1];
        } else if (h->imports_format == CHAINED_IMPORT_ADDEND64) {
            const uint64_t *v = (const uint64_t *)(data + h->imports_offset) + i * 2;
            weak = (v[0] >> 16) & 1;
            name_off = (uint32_t)(v[0] >> 32);
            addends[i] = (int64_t)v[1];
        } else {
            die("%s: unknown import format %u", im->path, h->imports_format);
        }
        targets[i] = resolve(im, symbols + name_off, weak);
    }
    const uint32_t *starts = (const uint32_t *)(data + h->starts_offset);
    uint32_t seg_count = starts[0];
    int count = 0;
    for (uint32_t s = 0; s < seg_count; s++) {
        uint32_t info_off = starts[1 + s];
        if (!info_off)
            continue;
        const struct chained_starts_in_segment *si = (const void *)(data + h->starts_offset + info_off);
        if (si->pointer_format != CHAINED_PTR_64 && si->pointer_format != CHAINED_PTR_64_OFFSET)
            die("%s: pointer format %u isn't supported", im->path, si->pointer_format);
        for (uint16_t page = 0; page < si->page_count; page++) {
            uint16_t start = si->page_start[page];
            if (start == CHAINED_PTR_START_NONE)
                continue;
            if (start & CHAINED_PTR_START_MULTI)
                die("%s: multi-start pages aren't supported", im->path);
            uint8_t *loc = seg_addr(im, s, (uint64_t)page * si->page_size + start);
            for (;;) {
                uint64_t raw = *(uint64_t *)loc;
                uint64_t next = (raw >> 51) & 0xfff;
                if (raw >> 63) {
                    uint32_t ordinal = raw & 0xffffff;
                    int64_t add = (raw >> 24) & 0xff;
                    if (ordinal >= h->imports_count)
                        die("%s: bind ordinal out of range", im->path);
                    *(uint64_t *)loc = (uint64_t)targets[ordinal] + addends[ordinal] + add;
                } else {
                    uint64_t target = raw & 0xfffffffffull;
                    uint64_t high8 = (raw >> 36) & 0xff;
                    uint64_t value = si->pointer_format == CHAINED_PTR_64_OFFSET
                        ? target + im->seg[0].vmaddr : target;
                    *(uint64_t *)loc = (value + im->slide) | (high8 << 56);
                }
                count++;
                if (!next)
                    break;
                loc += next * 4;
            }
        }
    }
    free(targets);
    free(addends);
    note("applied %d chained fixups", count);
}

/* ---- running ------------------------------------------------------------------- */

typedef int (*mac_main)(int, char **, char **, char **);

int ferry_run(const char *path, int argc, char **argv, char **envp)
{
    struct image im = {0};
    read_file(&im, path);
    parse_commands(&im);
    map_segments(&im);
    if (im.chained) {
        do_chained(&im);
    } else if (im.dyld_info) {
        do_rebases(&im);
        do_binds(&im, im.dyld_info->bind_off, im.dyld_info->bind_size, 0, 0);
        do_binds(&im, im.dyld_info->lazy_bind_off, im.dyld_info->lazy_bind_size, 1, 0);
        do_binds(&im, im.dyld_info->weak_bind_off, im.dyld_info->weak_bind_size, 0, 1);
    }
    ferry_seal_stubs();
    protect_segments(&im);
    /* __TEXT starts at the Mach-O header (file offset 0). */
    uint64_t text = 0;
    for (int i = 0; i < im.nseg; i++)
        if (im.seg[i].fileoff == 0 && im.seg[i].filesize)
            text = im.seg[i].vmaddr;
    mac_main entry = (mac_main)(text + im.slide + im.entryoff);
    char *apple[] = {NULL};
    ferry_program_started(path, argc, argv);
    note("calling main at %p", (void *)entry);
    return entry(argc, argv, envp, apple);
}
