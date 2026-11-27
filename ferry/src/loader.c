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
#include <setjmp.h>
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
#include "objc/objc-private.h"
#include "cxx.h"

#define PAGE 4096ul
#define ALIGN_DOWN(x) ((x) & ~(PAGE - 1))
#define ALIGN_UP(x) (((x) + PAGE - 1) & ~(PAGE - 1))
#define MAX_SEGMENTS 32
#define MAX_DYLIBS 256 /* IINA's program names 80 (freemac 1.262) */
#define MAX_SECTIONS 128

struct section {
    char segname[17], name[17];
    uint64_t addr, size;
    uint32_t flags, reserved1, align;
};

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
    struct macho_symtab *symtab;        /* for libraries from before 10.6 */
    struct macho_dysymtab *dysymtab;
    uint64_t entryoff;
    uint64_t thread_pc;      /* LC_UNIXTHREAD: the start address, unslid */
    int unixthread;
    int has_main;
    struct section sect[MAX_SECTIONS];
    int nsect;
    /* libraries */
    int is_dylib;
    struct image *deps[MAX_DYLIBS];     /* NULL: one of Ferry's built-in libraries */
    int dep_weak[MAX_DYLIBS];
    const uint8_t *exports;
    uint32_t exports_size;
    const char *rpaths[16];
    int nrpaths;
    struct ferry_objc_image objc;
    int has_objc;
    int initialized;
    int is_bundle;
    int complete;                       /* loaded, fixed up and protected */
    char *real;                         /* real path, to load each file once */
};

#define MAX_IMAGES 512
static struct image *images[MAX_IMAGES];
static int nimages;
static struct image *main_image;

int ferry_verbose;

/* While dlopen loads a library, a problem that would stop the program at
 * start-up is that dlopen's failure instead: die() jumps back to it. */
static __thread jmp_buf *load_failed;
static __thread char load_error[1024];

__attribute__((noreturn, format(printf, 1, 2))) static void die(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    if (load_failed) {
        vsnprintf(load_error, sizeof load_error, fmt, ap);
        va_end(ap);
        longjmp(*load_failed, 1);
    }
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
    if (im->header->filetype == MACHO_DYLIB)
        im->is_dylib = 1;
    else if (im->header->filetype == MACHO_BUNDLE && main_image)
        im->is_dylib = im->is_bundle = 1; /* a plug-in: a library, as far as loading goes */
    else if (im->header->filetype == MACHO_BUNDLE)
        die("%s is a plug-in (a bundle), which an app loads; it isn't a program", path);
    else if (im->header->filetype != MACHO_EXECUTE)
        die("%s is not a program or a library", path);
    else if (main_image)
        die("%s is a program, which can't be loaded into another one", path);
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
            const struct macho_section *sec = (const void *)(s + 1);
            if ((const uint8_t *)(sec + s->nsects) > (const uint8_t *)lc + lc->cmdsize)
                die("%s: damaged section list in %s", im->path, seg->name);
            for (uint32_t k = 0; k < s->nsects && im->nsect < MAX_SECTIONS; k++) {
                struct section *d = &im->sect[im->nsect++];
                memcpy(d->segname, sec[k].segname, 16);
                memcpy(d->name, sec[k].sectname, 16);
                d->segname[16] = d->name[16] = 0;
                d->addr = sec[k].addr;
                d->size = sec[k].size;
                d->flags = sec[k].flags;
                d->reserved1 = sec[k].reserved1;
                d->align = sec[k].align;
            }
            break;
        }
        case LC_LOAD_DYLIB:
        case LC_LOAD_WEAK_DYLIB:
        case LC_REEXPORT_DYLIB: {
            struct macho_dylib_command *d = (void *)lc;
            if (im->ndylibs == MAX_DYLIBS)
                die("%s uses too many libraries", im->path);
            im->dep_weak[im->ndylibs] = lc->cmd == LC_LOAD_WEAK_DYLIB;
            im->dylibs[im->ndylibs++] = (const char *)lc + d->name_offset;
            break;
        }
        case LC_RPATH:
            if (im->nrpaths < 16)
                im->rpaths[im->nrpaths++] = (const char *)lc + ((struct macho_rpath *)lc)->path_offset;
            break;
        case LC_DYLD_EXPORTS_TRIE:
            im->exports = im->file + ((struct macho_linkedit_data *)lc)->dataoff;
            im->exports_size = ((struct macho_linkedit_data *)lc)->datasize;
            break;
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY:
            im->dyld_info = (void *)lc;
            if (im->dyld_info->export_size && !im->exports) {
                im->exports = im->file + im->dyld_info->export_off;
                im->exports_size = im->dyld_info->export_size;
            }
            break;
        case LC_DYLD_CHAINED_FIXUPS:
            im->chained = (void *)lc;
            break;
        case LC_SYMTAB:
            im->symtab = (void *)lc;
            if ((uint64_t)im->symtab->symoff + (uint64_t)im->symtab->nsyms * sizeof(struct macho_nlist) > im->size ||
                (uint64_t)im->symtab->stroff + im->symtab->strsize > im->size)
                die("%s: damaged symbol table", im->path);
            break;
        case LC_DYSYMTAB:
            im->dysymtab = (void *)lc;
            break;
        case LC_MAIN:
            im->entryoff = ((struct macho_entry_point *)lc)->entryoff;
            im->has_main = 1;
            break;
        case LC_UNIXTHREAD: {
            /* Mac OS X 10.7 and earlier: the start address is the
             * instruction pointer of the thread state (x86_THREAD_STATE64,
             * flavor 4: rax ... r15, then rip) */
            const uint32_t *t = (const uint32_t *)(lc + 1);
            if (lc->cmdsize >= sizeof *lc + 8 + 17 * 8 && t[0] == 4) {
                memcpy(&im->thread_pc, (const uint8_t *)(t + 2) + 16 * 8, 8);
                im->has_main = im->unixthread = 1;
            }
            break;
        }
        default:
            break;
        }
        p += lc->cmdsize;
    }
    if (!im->nseg)
        die("%s has nothing to load", im->path);
    if (!im->has_main && !im->is_dylib)
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
    void *want = (im->is_dylib || (im->header->flags & MACHO_FLAG_PIE)) ? NULL : (void *)low;
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

static void *trie_lookup(struct image *im, const char *raw, int depth);

/* Two-level namespace: a bind names the library (by its position in the
 * image's load commands) as well as the symbol. Ordinal 0 is the image
 * itself, -1 the main program, -2 "search everywhere". If the named library
 * doesn't have it (Ferry's libraries are organised differently from
 * Apple's), every loaded library is searched, then Ferry's own tables. */
static void *lookup_symbol(struct image *im, const char *raw, int ordinal)
{
    void *addr = NULL;
    if (ordinal == 0)
        addr = trie_lookup(im, raw, 0);
    else if (ordinal == -1 && main_image)
        addr = trie_lookup(main_image, raw, 0);
    else if (ordinal > 0 && ordinal <= im->ndylibs && im->deps[ordinal - 1])
        addr = trie_lookup(im->deps[ordinal - 1], raw, 0);
    if (addr)
        return addr;
    char name[256];
    strip_symbol(raw, name, sizeof name);
    if ((addr = ferry_lookup(name)))
        return addr;
    for (int i = 0; i < nimages && !addr; i++)
        if (images[i] != im || ordinal != 0)
            addr = trie_lookup(images[i], raw, 0);
    return addr;
}

/* Objective-C classes Ferry doesn't have are bound to nil, as a Mac binds a
 * weakly linked class that the system lacks: messages to them do nothing,
 * and a class built on one is left out (runtime.c says which). A
 * function stub in their place would be read as a class and crash. */
static int missing_classes;

static int is_class_symbol(const char *raw)
{
    return !strncmp(raw, "_OBJC_CLASS_$_", 14) || !strncmp(raw, "_OBJC_METACLASS_$_", 18);
}

/* A missing variable named like one of Apple's string constants
 * (NSWorkspaceDidActivateApplicationNotification, NSStringPboardType,
 * kAXTrustedCheckOptionPrompt...)
 * gets a string whose text is its own name, which is what most of them
 * hold on a Mac. A function stub in its place would be read as an object
 * and crash. */
static int looks_like_string_constant(const char *raw)
{
    static const char *const ends[] = {"Key", "Notification", "Name", "Operation", "Attribute", "Identifier",
                                       "Binding", "Option", "Domain", "AccountID", "Mode", "Type", "Template",
                                       NULL};
    const char *n = raw[0] == '_' ? raw + 1 : raw;
    if (n[0] == 'k' && n[1] >= 'A' && n[1] <= 'Z')
        return 1;
    /* a framework's prefix (NS, MP, AV...) and a word: MPMediaItemPropertyMediaType
     * as much as NSImageNameTouchBarPlayTemplate (freemac 1.262) */
    size_t upper = 0;
    while (n[upper] >= 'A' && n[upper] <= 'Z')
        upper++;
    if (upper < 3 || upper > 4 || n[upper] < 'a' || n[upper] > 'z')
        return 0;
    size_t len = strlen(n);
    for (int i = 0; ends[i]; i++) {
        size_t e = strlen(ends[i]);
        if (len > e && !strcmp(n + len - e, ends[i]))
            return 1;
    }
    return 0;
}

static void *missing_string_constant(struct image *im, const char *raw)
{
    void *cls = lookup_symbol(im, "___CFConstantStringClassReference", -2);
    if (!cls)
        return NULL;
    struct constant_string {
        void *isa;
        int32_t flags;
        const char *bytes;
        long length;
    } *str = calloc(1, sizeof *str);
    void **cell = calloc(1, sizeof *cell);
    const char *n = raw[0] == '_' ? raw + 1 : raw;
    str->isa = cls;
    str->flags = 0x7c8;
    str->bytes = strdup(n);
    str->length = (long)strlen(n);
    *cell = str;
    note("  missing %s (a string constant holding its name)", raw);
    return cell;
}

static void *resolve(struct image *im, const char *raw, int weak, int ordinal)
{
    void *addr = lookup_symbol(im, raw, ordinal);
    if (!addr) {
        if (weak)
            return NULL;
        if (looks_like_string_constant(raw) && (addr = missing_string_constant(im, raw)))
            return addr;
        if (!strncmp(raw, "_OBJC_EHTYPE_$_", 15)) {
            /* a @catch of a class Ferry doesn't have: one that never matches */
            note("  missing %s (its @catch never matches)", raw);
            return (void *)&ferry_ehtype_missing;
        }
        if (is_class_symbol(raw)) {
            const char *name = raw[6] == 'C' ? raw + 14 : raw + 18;
            static const char *seen[1024];
            int known = 0;
            for (int i = 0; i < missing_classes && i < 1024 && !known; i++)
                known = !strcmp(seen[i], name);
            if (!known) {
                if (missing_classes < 1024)
                    seen[missing_classes] = name;
                missing_classes++;
                note("  missing class %s (it will be nil)", name);
            }
            return NULL;
        }
        addr = ferry_missing_stub(raw);
        note("  missing %s", raw);
    }
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
    int weak = 0, count = 0, ordinal = 0;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t op = byte & OPCODE_MASK, imm = byte & IMMEDIATE_MASK;
        switch (op) {
        case BIND_DONE:
            if (!lazy)
                p = end;
            break;
        case BIND_SET_DYLIB_ORDINAL_IMM:
            ordinal = imm;
            break;
        case BIND_SET_DYLIB_SPECIAL_IMM:
            ordinal = imm ? (int)(int8_t)(OPCODE_MASK | imm) : 0;
            break;
        case BIND_SET_DYLIB_ORDINAL_ULEB:
            ordinal = (int)uleb(&p, end);
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
                void *target = resolve(im, symbol, weak || weak_stream, weak_stream ? -2 : ordinal);
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
        int weak, ordinal;
        if (h->imports_format == CHAINED_IMPORT) {
            uint32_t v = ((const uint32_t *)(data + h->imports_offset))[i];
            ordinal = (int8_t)(v & 0xff);
            weak = (v >> 8) & 1;
            name_off = v >> 9;
        } else if (h->imports_format == CHAINED_IMPORT_ADDEND) {
            const uint32_t *v = (const uint32_t *)(data + h->imports_offset) + i * 2;
            ordinal = (int8_t)(v[0] & 0xff);
            weak = (v[0] >> 8) & 1;
            name_off = v[0] >> 9;
            addends[i] = (int32_t)v[1];
        } else if (h->imports_format == CHAINED_IMPORT_ADDEND64) {
            const uint64_t *v = (const uint64_t *)(data + h->imports_offset) + i * 2;
            ordinal = (int16_t)(v[0] & 0xffff);
            weak = (v[0] >> 16) & 1;
            name_off = (uint32_t)(v[0] >> 32);
            addends[i] = (int64_t)v[1];
        } else {
            die("%s: unknown import format %u", im->path, h->imports_format);
        }
        targets[i] = resolve(im, symbols + name_off, weak, ordinal);
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

/* ---- Objective-C ----------------------------------------------------------------
 * The __objc_* sections go to the runtime (src/objc) once fixups are done. */

static void *objc_section(struct image *im, const char *name, size_t *count)
{
    for (int i = 0; i < im->nsect; i++)
        if (!strcmp(im->sect[i].name, name) && !strncmp(im->sect[i].segname, "__DATA", 6)) {
            *count = im->sect[i].size / sizeof(void *);
            return (void *)(im->sect[i].addr + im->slide);
        }
    *count = 0;
    return NULL;
}

static int objc_find(struct image *im, struct ferry_objc_image *oi)
{
    size_t n;
    memset(oi, 0, sizeof *oi);
    oi->path = im->path;
    oi->selrefs = objc_section(im, "__objc_selrefs", &oi->nselrefs);
    oi->classlist = objc_section(im, "__objc_classlist", &oi->nclasses);
    oi->nlclslist = objc_section(im, "__objc_nlclslist", &oi->nnlcls);
    oi->catlist = objc_section(im, "__objc_catlist", &oi->ncats);
    oi->nlcatlist = objc_section(im, "__objc_nlcatlist", &oi->nnlcats);
    oi->protolist = objc_section(im, "__objc_protolist", &oi->nprotos);
    oi->protorefs = objc_section(im, "__objc_protorefs", &oi->nprotorefs);
    oi->msgrefs = objc_section(im, "__objc_msgrefs", &oi->nmsgrefs);
    uint32_t *info = objc_section(im, "__objc_imageinfo", &n);
    if (info)
        oi->imageinfo_flags = info[1];
    return info || oi->nselrefs || oi->nclasses || oi->ncats;
}

/* ---- exported symbols ------------------------------------------------------
 * A library lists what it exports in a prefix tree ("export trie"): each
 * node has the data for the name spelled so far (if one ends there) and
 * edges labelled with the next characters. */

static uint64_t image_base(struct image *im)
{
    for (int i = 0; i < im->nseg; i++)
        if (im->seg[i].fileoff == 0 && im->seg[i].filesize)
            return im->seg[i].vmaddr + im->slide;
    return im->seg[0].vmaddr + im->slide;
}

/* ---- unwinding ----------------------------------------------------------------
 * For the exception unwinder (src/objc/exception.c): which loaded image holds
 * a code address, and where its unwind tables are. */

int ferry_find_unwind(uint64_t pc, struct ferry_unwind_sections *out)
{
    for (int i = 0; i < nimages; i++) {
        struct image *im = images[i];
        int in_text = 0;
        for (int s = 0; s < im->nseg && !in_text; s++)
            if ((im->seg[s].prot & 4) && pc >= im->seg[s].vmaddr + im->slide &&
                pc < im->seg[s].vmaddr + im->slide + im->seg[s].vmsize)
                in_text = 1;
        if (!in_text)
            continue;
        memset(out, 0, sizeof *out);
        out->path = im->path;
        out->base = image_base(im);
        for (int s = 0; s < im->nsect; s++) {
            if (strcmp(im->sect[s].segname, "__TEXT"))
                continue;
            if (!strcmp(im->sect[s].name, "__unwind_info")) {
                out->unwind_info = (const uint8_t *)(im->sect[s].addr + im->slide);
                out->unwind_size = im->sect[s].size;
            } else if (!strcmp(im->sect[s].name, "__eh_frame")) {
                out->eh_frame = (const uint8_t *)(im->sect[s].addr + im->slide);
                out->eh_size = im->sect[s].size;
            }
        }
        return 1;
    }
    return 0;
}

/* A library with no export trie (built before 10.6): its exported symbols
 * are the symbol table's "externally defined" group. */
static void *symtab_lookup(struct image *im, const char *raw)
{
    if (!im->symtab || !im->dysymtab)
        return NULL;
    const struct macho_nlist *syms = (const void *)(im->file + im->symtab->symoff);
    const char *strs = (const char *)im->file + im->symtab->stroff;
    uint32_t first = im->dysymtab->iextdefsym, n = im->dysymtab->nextdefsym;
    if (first > im->symtab->nsyms || n > im->symtab->nsyms - first)
        return NULL;
    for (uint32_t i = first; i < first + n; i++) {
        const struct macho_nlist *sym = &syms[i];
        if (sym->n_strx >= im->symtab->strsize || (sym->n_type & N_STAB_MASK) || !(sym->n_type & N_EXT))
            continue;
        if (strcmp(strs + sym->n_strx, raw))
            continue;
        if ((sym->n_type & N_TYPE_MASK) == N_ABS)
            return (void *)sym->n_value;
        if ((sym->n_type & N_TYPE_MASK) == N_SECT)
            return (void *)(sym->n_value + im->slide);
    }
    return NULL;
}

static void *trie_lookup(struct image *im, const char *raw, int depth)
{
    if (im && !im->exports && !im->dyld_info && !im->chained)
        return symtab_lookup(im, raw);
    if (!im || !im->exports || depth > 8)
        return NULL;
    const uint8_t *start = im->exports, *end = start + im->exports_size, *p = start;
    const char *s = raw;
    for (;;) {
        if (p >= end)
            return NULL;
        const uint8_t *node = p;
        uint64_t terminal = uleb(&p, end);
        const uint8_t *children = p + terminal;
        if (!*s) {
            if (!terminal)
                return NULL;
            uint64_t flags = uleb(&p, end);
            if (flags & EXPORT_REEXPORT) {
                uint64_t ordinal = uleb(&p, end);
                const char *other = (const char *)p;
                if (!*other)
                    other = raw;
                if (ordinal >= 1 && ordinal <= (uint64_t)im->ndylibs) {
                    if (im->deps[ordinal - 1])
                        return trie_lookup(im->deps[ordinal - 1], other, depth + 1);
                    char name[256];
                    strip_symbol(other, name, sizeof name);
                    return ferry_lookup(name);
                }
                return NULL;
            }
            uint64_t value = uleb(&p, end);
            if (flags & EXPORT_STUB_AND_RESOLVER)
                uleb(&p, end);  /* the resolver; the stub address is fine */
            if ((flags & EXPORT_KIND_MASK) == EXPORT_KIND_ABSOLUTE)
                return (void *)value;
            return (void *)(image_base(im) + value);
        }
        (void)node;
        p = children;
        if (p >= end)
            return NULL;
        uint8_t count = *p++;
        const uint8_t *next = NULL;
        for (uint8_t c = 0; c < count && p < end; c++) {
            const char *edge = (const char *)p;
            size_t len = strnlen(edge, end - p);
            p += len + 1;
            uint64_t off = uleb(&p, end);
            if (!next && !strncmp(s, edge, len)) {
                next = start + off;
                s += len;
            }
        }
        if (!next)
            return NULL;
        p = next;
    }
}

/* ---- finding libraries -------------------------------------------------------
 * Apple's frameworks are replaced by Ferry's own (written from public
 * documentation), installed as <dir>/<Name>.framework/<Name> in the
 * directory named by $FERRY_FRAMEWORKS, next to the ferry program
 * (frameworks/), or in /usr/lib/ferry/frameworks. A few Apple libraries are
 * served by one of Ferry's: CoreFoundation, SystemConfiguration and
 * CoreServices (Gestalt and login items), ServiceManagement, IOKit (foundation/IOKit.m) and
 * UniformTypeIdentifiers live inside Foundation, and CoreText, ApplicationServices and ImageIO inside CoreGraphics, and Carbon
 * (the few calls Cocoa apps still make, appkit/Carbon.m) inside AppKit, and
 * AudioToolbox and AudioUnit inside CoreAudio. */

static const struct { const char *name, *served_by; } framework_aliases[] = {
    {"CoreFoundation", "Foundation"},
    {"SystemConfiguration", "Foundation"},
    {"CFNetwork", "Foundation"},        /* the socket streams' properties, next to CFStream */
    {"CoreServices", "Foundation"}, /* Gestalt, next to NSProcessInfo, and login items (LoginItems.m) */
    {"ServiceManagement", "Foundation"}, /* SMLoginItemSetEnabled, foundation/LoginItems.m */
    {"IOKit", "Foundation"},             /* the registry and power assertions, foundation/IOKit.m */
    {"UniformTypeIdentifiers", "Foundation"}, /* UTType, foundation/UTTypes.m (freemac 1.225) */
    {"CoreText", "CoreGraphics"},
    {"ApplicationServices", "CoreGraphics"},
    {"ImageIO", "CoreGraphics"},
    {"Cocoa", "AppKit"},
    {"Carbon", "AppKit"},
    {"UserNotifications", "AppKit"}, /* appkit/UNUserNotificationCenter.m, beside the Dock and D-Bus */
    {"AVFoundation", "AppKit"},      /* AVAudioPlayer over NSSound, appkit/AVAudioPlayer.m (1.230) */
    {"Quartz", "AppKit"},            /* Quick Look's panel and QCView, appkit/QuickLook.m */
    {"QuickLook", "AppKit"},         /* the generator calls and thumbnails, appkit/QuickLook.m */
    {"CoreImage", "AppKit"},         /* images, CIAffineTransform and detectors, appkit/CoreImage.m (1.225) */
    {"ScriptingBridge", "AppKit"},   /* apps that can't be scripted here, appkit/ScriptingBridge.m */
    {"AudioToolbox", "CoreAudio"},   /* audio units and queues beside the HAL, coreaudio/ (1.232, 1.234) */
    {"AudioUnit", "CoreAudio"},
    {"CoreMIDI", "CoreAudio"},      /* a system with no MIDI devices, coreaudio/CoreMIDI.m (1.263) */
    {"MediaPlayer", "AppKit"},       /* remote commands and Now Playing, appkit/MediaPlayer.m (1.233) */
    {"CoreMedia", "AppKit"},         /* CMTime, appkit/CoreMedia.m (1.233) */
    {"CoreMediaIO", "AppKit"},       /* the system object, appkit/CoreMediaIO.m (1.257) */
    {"AddressBook", "AppKit"},       /* an empty book, appkit/AddressBook.m (1.233) */
    {"PIP", "AppKit"},               /* picture in picture (a private framework), appkit/PIP.m (1.262) */
    {"VideoToolbox", "AppKit"},      /* no hardware codecs, appkit/VideoToolbox.m (1.262) */
    {NULL, NULL},
};

static int file_exists(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static int find_framework(const char *name, char *out, size_t size)
{
    for (int i = 0; framework_aliases[i].name; i++)
        if (!strcmp(name, framework_aliases[i].name))
            name = framework_aliases[i].served_by;
    char self[4096];
    const char *dirs[3] = {getenv("FERRY_FRAMEWORKS"), NULL, "/usr/lib/ferry/frameworks"};
    ssize_t n = readlink("/proc/self/exe", self, sizeof self - 16);
    if (n > 0) {
        self[n] = 0;
        char *slash = strrchr(self, '/');
        if (slash) {
            strcpy(slash + 1, "frameworks");
            dirs[1] = self;
        }
    }
    for (int i = 0; i < 3; i++) {
        if (!dirs[i] || !*dirs[i])
            continue;
        snprintf(out, size, "%s/%s.framework/%s", dirs[i], name, name);
        if (file_exists(out))
            return 1;
    }
    return 0;
}

static void dir_of(const char *path, char *out, size_t size)
{
    snprintf(out, size, "%s", path);
    char *slash = strrchr(out, '/');
    if (slash)
        *slash = 0;
    else
        snprintf(out, size, ".");
}

/* @executable_path, @loader_path and @rpath, as in a Mac app bundle.
 * Returns 0 if the name can't be expanded. */
static int expand_path(struct image *loader, const char *name, char *out, size_t size)
{
    char dir[4096];
    /* an rpath may be the folder itself, with no slash after it */
    if (!strcmp(name, "@executable_path") || !strcmp(name, "@loader_path")) {
        dir_of(name[1] == 'e' && main_image ? main_image->path : loader->path, out, size);
        return 1;
    }
    if (!strncmp(name, "@executable_path/", 17)) {
        dir_of(main_image ? main_image->path : loader->path, dir, sizeof dir);
        snprintf(out, size, "%s/%s", dir, name + 17);
        return 1;
    }
    if (!strncmp(name, "@loader_path/", 13)) {
        dir_of(loader->path, dir, sizeof dir);
        snprintf(out, size, "%s/%s", dir, name + 13);
        return 1;
    }
    if (!strncmp(name, "@rpath/", 7)) {
        struct image *search[2] = {loader, main_image};
        for (int k = 0; k < 2; k++) {
            if (!search[k])
                continue;
            for (int i = 0; i < search[k]->nrpaths; i++) {
                char base[4096];
                if (!expand_path(search[k], search[k]->rpaths[i], base, sizeof base))
                    continue;
                snprintf(out, size, "%s/%s", base, name + 7);
                /* /usr/lib/swift: on a Mac, the system's copy of Swift's
                 * libraries, taken before an app's own older copies (an app
                 * built for macOS 10.13 lists it first); here, Ferry's copy,
                 * when Ferry has that library (freemac 1.262) */
                if (!strcmp(base, "/usr/lib/swift") || !strcmp(base, "/usr/lib/swift/")) {
                    char mine[4096];
                    if (ferry_find_swift_library(out, mine, sizeof mine)) {
                        snprintf(out, size, "%s", mine);
                        return 1;
                    }
                    continue;
                }
                if (file_exists(out))
                    return 1;
            }
        }
        return 0;
    }
    snprintf(out, size, "%s", name);
    return name[0] != '@';
}

static struct image *load_image(const char *path);

/* "Sparkle" for ".../Sparkle.framework/Versions/A/Sparkle". */
static const char *short_name(const char *path)
{
    const char *b = strrchr(path, '/');
    return b ? b + 1 : path;
}

static struct image *load_library(struct image *loader, const char *install_name, int weak)
{
    if (ferry_library_supported(install_name))
        return NULL;    /* libSystem, libobjc: built into Ferry */
    char path[4096];
    const char *fw = strstr(install_name, ".framework/");
    int found = 0;
    if (!strncmp(install_name, "/System/Library/", 16) || !strncmp(install_name, "/usr/lib/", 9)) {
        const char *base = strrchr(install_name, '/');
        if (fw && base)
            found = find_framework(base + 1, path, sizeof path);
        else if (!strncmp(install_name, "/usr/lib/swift/", 15))
            found = ferry_find_swift_library(install_name, path, sizeof path);   /* swiftsupport.c */
    } else {
        found = expand_path(loader, install_name, path, sizeof path) && file_exists(path);
        if (!found)     /* an app that expects its own copy of Swift's libraries */
            found = ferry_find_swift_library(install_name, path, sizeof path);
    }
    if (!found) {
        if (weak)
            return NULL;
        /* A system framework Ferry lacks: carry on, so that a program which
         * never calls into it still runs. Its functions stop the program
         * with their names if they are called, as other missing calls do. */
        if (!strncmp(install_name, "/System/Library/", 16) || !strncmp(install_name, "/usr/lib/", 9)) {
            static char warned[32][128];
            static int nwarned;
            const char *name = short_name(install_name);
            for (int i = 0; i < nwarned; i++)
                if (!strcmp(warned[i], name))
                    return NULL;
            if (nwarned < 32)
                snprintf(warned[nwarned++], sizeof warned[0], "%s", name);
            fprintf(stderr, "ferry: %s uses %s, which Ferry doesn't provide yet; carrying on without it\n",
                    short_name(loader->path), name);
            return NULL;
        }
        die("%s needs %s, which Ferry doesn't provide yet", loader->path, install_name);
    }
    return load_image(path);
}

/* ---- fixups in the old form ----------------------------------------------------
 * Before 10.6 a library listed its fixups as relocation entries: local ones
 * (add the slide) and external ones (a symbol's address, plus what is
 * stored), at offsets from its first writable segment, as on Intel Macs.
 * Pointers to imported symbols sit in symbol-pointer sections, named one
 * by one in the indirect symbol table. */

static int classic_ordinal(uint16_t desc)
{
    int o = (desc >> 8) & 0xff;
    return o == 0xfe ? -2 : o == 0xff ? -1 : o;
}

static void do_classic(struct image *im)
{
    if (!im->symtab || !im->dysymtab)
        return;
    const struct macho_dysymtab *d = im->dysymtab;
    const struct macho_nlist *syms = (const void *)(im->file + im->symtab->symoff);
    const char *strs = (const char *)im->file + im->symtab->stroff;
    uint64_t reloc_base = 0;
    for (int i = 0; i < im->nseg; i++)
        if (im->seg[i].prot & 2) {
            reloc_base = im->seg[i].vmaddr + im->slide;
            break;
        }
    int count = 0;
    if ((uint64_t)d->locreloff + (uint64_t)d->nlocrel * 8 > im->size ||
        (uint64_t)d->extreloff + (uint64_t)d->nextrel * 8 > im->size ||
        (uint64_t)d->indirectsymoff + (uint64_t)d->nindirectsyms * 4 > im->size)
        die("%s: damaged relocation tables", im->path);
    const struct macho_reloc *loc = (const void *)(im->file + d->locreloff);
    for (uint32_t i = 0; i < d->nlocrel && im->slide; i++) {
        uint32_t info = loc[i].r_info;
        if (loc[i].r_address < 0 || (info >> 27) & 1 || ((info >> 25) & 3) != 3 || (info >> 28) != 0)
            continue; /* only 64-bit absolute pointers need moving */
        *(uint64_t *)(reloc_base + loc[i].r_address) += im->slide;
        count++;
    }
    const struct macho_reloc *ext = (const void *)(im->file + d->extreloff);
    for (uint32_t i = 0; i < d->nextrel; i++) {
        uint32_t info = ext[i].r_info, symnum = info & 0xffffff;
        if (!((info >> 27) & 1) || ((info >> 25) & 3) != 3 || (info >> 28) != 0 || symnum >= im->symtab->nsyms)
            continue;
        const struct macho_nlist *sym = &syms[symnum];
        if (sym->n_strx >= im->symtab->strsize)
            continue;
        uint64_t *where = (uint64_t *)(reloc_base + ext[i].r_address);
        void *addr = resolve(im, strs + sym->n_strx, sym->n_desc & N_WEAK_REF, classic_ordinal(sym->n_desc));
        *where = (uint64_t)addr + (addr ? *where : 0);
        count++;
    }
    const uint32_t *indirect = (const void *)(im->file + d->indirectsymoff);
    for (int s = 0; s < im->nsect; s++) {
        uint32_t type = im->sect[s].flags & S_TYPE_MASK;
        if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS)
            continue;
        uint64_t *slots = (uint64_t *)(im->sect[s].addr + im->slide);
        for (uint64_t k = 0; k < im->sect[s].size / 8; k++) {
            uint64_t idx = im->sect[s].reserved1 + k;
            if (idx >= d->nindirectsyms)
                break;
            uint32_t symnum = indirect[idx];
            if (symnum & INDIRECT_SYMBOL_ABS)
                continue;
            if (symnum & INDIRECT_SYMBOL_LOCAL) {
                if (type == S_NON_LAZY_SYMBOL_POINTERS)
                    slots[k] += im->slide;
                continue;
            }
            if (symnum >= im->symtab->nsyms || syms[symnum].n_strx >= im->symtab->strsize)
                continue;
            const struct macho_nlist *sym = &syms[symnum];
            slots[k] = (uint64_t)resolve(im, strs + sym->n_strx, sym->n_desc & N_WEAK_REF,
                                         classic_ordinal(sym->n_desc));
            count++;
        }
    }
    note("applied %d fixups in the old (relocation entry) form", count);
}

/* ---- thread-local variables ----------------------------------------------------
 * The image's template and descriptors go to src/tlv.c, which binds each
 * descriptor to its own thunk once the image's fixups are done. */

static void find_tlv(struct image *im)
{
    struct ferry_tlv_section tlv[MAX_SECTIONS];
    int n = 0;
    for (int i = 0; i < im->nsect; i++) {
        uint32_t type = im->sect[i].flags & S_TYPE_MASK;
        if (type != S_THREAD_LOCAL_REGULAR && type != S_THREAD_LOCAL_ZEROFILL && type != S_THREAD_LOCAL_VARIABLES)
            continue;
        tlv[n].addr = (uint8_t *)(im->sect[i].addr + im->slide);
        tlv[n].size = im->sect[i].size;
        tlv[n].type = type;
        tlv[n].align = im->sect[i].align;
        n++;
    }
    if (n && ferry_tlv_image_loaded(im->path, tlv, n) < 0)
        die("%s: can't set up its thread-local variables", im->path);
}

/* ---- loading ----------------------------------------------------------------- */

static void apply_fixups(struct image *im)
{
    if (im->chained) {
        do_chained(im);
    } else if (im->dyld_info) {
        do_rebases(im);
        do_binds(im, im->dyld_info->bind_off, im->dyld_info->bind_size, 0, 0);
        do_binds(im, im->dyld_info->lazy_bind_off, im->dyld_info->lazy_bind_size, 1, 0);
        do_binds(im, im->dyld_info->weak_bind_off, im->dyld_info->weak_bind_size, 0, 1);
    } else {
        do_classic(im);
    }
}

static struct image *load_image(const char *path)
{
    char real[4096];
    if (!realpath(path, real))
        snprintf(real, sizeof real, "%s", path);
    for (int i = 0; i < nimages; i++)
        if (!strcmp(images[i]->real, real))
            return images[i];
    if (nimages == (int)(sizeof images / sizeof images[0]))
        die("the program uses too many libraries");
    struct image *im = calloc(1, sizeof *im);
    im->real = strdup(real);
    read_file(im, strdup(path));
    if (!main_image && im->is_dylib)
        die("%s is a library, not a program", path);
    images[nimages++] = im;
    if (!main_image)
        main_image = im;
    parse_commands(im);
    map_segments(im);
    for (int i = 0; i < im->ndylibs; i++)
        im->deps[i] = load_library(im, im->dylibs[i], im->dep_weak[i]);
    apply_fixups(im);
    find_tlv(im);
    ferry_cxx_image_loaded(im);   /* its unwind tables, once a program uses C++ */
    im->has_objc = objc_find(im, &im->objc);
    if (im->has_objc) {
        note("setting up Objective-C in %s: %zu classes, %zu categories, %zu selectors", im->path,
             im->objc.nclasses, im->objc.ncats, im->objc.nselrefs);
        ferry_objc_map_image(&im->objc);
    }
    protect_segments(im);
    im->complete = 1;
    return im;
}

typedef void (*initializer)(int, char **, char **, char **);

/* Libraries are set up before whatever uses them: +load methods, then C
 * and C++ initializers (__mod_init_func, __init_offsets). */
static void initialize_image(struct image *im, int argc, char **argv, char **envp, char **apple)
{
    if (im->initialized)
        return;
    im->initialized = 1;
    for (int i = 0; i < im->ndylibs; i++)
        if (im->deps[i])
            initialize_image(im->deps[i], argc, argv, envp, apple);
    if (im->has_objc)
        ferry_objc_load_image(&im->objc);
    /* thread-local variables' set-up functions, once, ahead of the rest */
    for (int i = 0; i < im->nsect; i++) {
        struct section *sec = &im->sect[i];
        if ((sec->flags & 0xff) != S_THREAD_LOCAL_INIT_FUNCTION_POINTERS)
            continue;
        initializer *f = (initializer *)(sec->addr + im->slide);
        for (uint64_t k = 0; k < sec->size / sizeof *f; k++)
            f[k](argc, argv, envp, apple);
    }
    for (int i = 0; i < im->nsect; i++) {
        struct section *sec = &im->sect[i];
        uint8_t type = sec->flags & 0xff;
        if (type == S_MOD_INIT_FUNC_POINTERS) {
            initializer *f = (initializer *)(sec->addr + im->slide);
            for (uint64_t k = 0; k < sec->size / sizeof *f; k++)
                f[k](argc, argv, envp, apple);
        } else if (type == S_INIT_FUNC_OFFSETS) {
            const uint32_t *off = (const uint32_t *)(sec->addr + im->slide);
            for (uint64_t k = 0; k < sec->size / sizeof *off; k++)
                ((initializer)(image_base(im) + off[k]))(argc, argv, envp, apple);
        }
    }
}

/* ---- loading while the program runs ---------------------------------------------
 * dlopen, NSBundle and CFBundle (src/dyld.c, Foundation) load libraries and
 * plug-in bundles once the program has started, the same way as the ones it
 * links, and set them up (+load, then C and C++ initializers) before they
 * are handed back. A library that can't be loaded is a failure for the
 * caller to report, not the end of the program. Images are never unloaded,
 * as on a Mac for anything with Objective-C in it. */

static int start_argc;
static char **start_argv, **start_envp;

int ferry_image_count(void) { return nimages; }
struct image *ferry_image_at(int index) { return index >= 0 && index < nimages ? images[index] : NULL; }
struct image *ferry_main_image(void) { return main_image; }
const char *ferry_image_path(struct image *im) { return im ? im->path : NULL; }
void *ferry_image_header(struct image *im) { return im ? (void *)image_base(im) : NULL; }
intptr_t ferry_image_slide(struct image *im) { return im ? (intptr_t)im->slide : 0; }
int ferry_image_is_bundle(struct image *im) { return im && im->is_bundle; }

struct image *ferry_image_containing(const void *addr)
{
    uint64_t a = (uint64_t)addr;
    for (int i = 0; i < nimages; i++) {
        struct image *im = images[i];
        for (int s = 0; s < im->nseg; s++)
            if (a >= im->seg[s].vmaddr + im->slide && a < im->seg[s].vmaddr + im->slide + im->seg[s].vmsize)
                return im;
    }
    return NULL;
}

/* A symbol the image exports, by its Mach-O name ("_main"), for dlsym. A
 * thread-local variable is exported as its descriptor; what the caller
 * gets is the calling thread's variable. */
void *ferry_image_symbol(struct image *im, const char *macho_name)
{
    void *addr = im && macho_name ? trie_lookup(im, macho_name, 0) : NULL;
    struct image *owner = addr ? ferry_image_containing(addr) : NULL;
    for (int i = 0; owner && i < owner->nsect; i++) {
        struct section *sec = &owner->sect[i];
        uint64_t a = (uint64_t)addr - owner->slide;
        if ((sec->flags & S_TYPE_MASK) == S_THREAD_LOCAL_VARIABLES && a >= sec->addr && a < sec->addr + sec->size)
            return ferry_tlv_address(addr);
    }
    return addr;
}

/* The libraries it links that are files Ferry loaded; *builtin says whether
 * it also links one of Ferry's built-in ones (libSystem, libobjc). */
int ferry_image_dependencies(struct image *im, struct image **out, int max, int *builtin)
{
    int n = 0;
    *builtin = 0;
    for (int i = 0; i < im->ndylibs; i++) {
        if (!im->deps[i])
            *builtin = 1;
        else if (n < max)
            out[n++] = im->deps[i];
    }
    return n;
}

/* The symbol at or just below an address, from the image's symbol table,
 * without Mach-O's leading underscore. */
const char *ferry_image_nearest(struct image *im, const void *addr, void **symbol_addr)
{
    *symbol_addr = NULL;
    if (!im || !im->symtab)
        return NULL;
    const struct macho_nlist *syms = (const void *)(im->file + im->symtab->symoff);
    const char *strs = (const char *)im->file + im->symtab->stroff;
    const char *best = NULL;
    uint64_t best_value = 0, a = (uint64_t)addr;
    for (uint32_t i = 0; i < im->symtab->nsyms; i++) {
        const struct macho_nlist *sym = &syms[i];
        if ((sym->n_type & N_STAB_MASK) || (sym->n_type & N_TYPE_MASK) != N_SECT || sym->n_strx >= im->symtab->strsize)
            continue;
        uint64_t value = sym->n_value + im->slide;
        const char *name = strs + sym->n_strx;
        if (value > a || !*name || (best && value < best_value))
            continue;
        /* of two names for one address, the exported one */
        if (best && value == best_value && !(sym->n_type & N_EXT))
            continue;
        best = name;
        best_value = value;
    }
    if (!best)
        return NULL;
    *symbol_addr = (void *)best_value;
    return best[0] == '_' ? best + 1 : best;
}

/* Each function or datum the image defines, local or exported, by its
 * Mach-O name and address. */
void ferry_image_each_symbol(struct image *im, void (*fn)(const char *name, void *addr, void *ctx), void *ctx)
{
    if (!im || !im->symtab)
        return;
    const struct macho_nlist *syms = (const void *)(im->file + im->symtab->symoff);
    const char *strs = (const char *)im->file + im->symtab->stroff;
    for (uint32_t i = 0; i < im->symtab->nsyms; i++) {
        const struct macho_nlist *sym = &syms[i];
        if ((sym->n_type & N_STAB_MASK) || (sym->n_type & N_TYPE_MASK) != N_SECT || sym->n_strx >= im->symtab->strsize)
            continue;
        fn(strs + sym->n_strx, (void *)(sym->n_value + im->slide), ctx);
    }
}

static int address_order(const void *a, const void *b)
{
    uintptr_t x = *(const uintptr_t *)a, y = *(const uintptr_t *)b;
    return x < y ? -1 : x > y;
}

/* Points every pointer in the image's data (its sections outside __TEXT,
 * zero-filled ones aside) that holds from[i] at to[i] instead, as virtual
 * tables hold their functions. from is sorted here, with to alongside. */
int ferry_image_replace_pointers(struct image *im, uintptr_t (*pairs)[2], int n)
{
    if (!im || n <= 0)
        return 0;
    qsort(pairs, (size_t)n, sizeof *pairs, address_order);
    int replaced = 0;
    for (int i = 0; i < im->nsect; i++) {
        struct section *sec = &im->sect[i];
        uint8_t type = sec->flags & 0xff;
        if (!strcmp(sec->segname, "__TEXT") || !strcmp(sec->segname, "__LINKEDIT") || type == 0x1 ||
            type == 0xc || type == 0x12 || sec->size < 8)
            continue;
        uintptr_t start = sec->addr + im->slide, end = start + sec->size;
        uintptr_t page = start & ~(PAGE - 1), page_end = ALIGN_UP(end);
        int opened = 0;
        for (uintptr_t *w = (uintptr_t *)((start + 7) & ~(uintptr_t)7); (uintptr_t)(w + 1) <= end; w++) {
            uintptr_t key = *w;
            uintptr_t (*hit)[2] = bsearch(&key, pairs, (size_t)n, sizeof *pairs, address_order);
            if (!hit)
                continue;
            if (!opened) {
                if (mprotect((void *)page, page_end - page, PROT_READ | PROT_WRITE))
                    break;
                opened = 1;
            }
            *w = (*hit)[1];
            replaced++;
        }
        if (opened && im->complete) {
            for (int s = 0; s < im->nseg; s++)
                if (!strcmp(im->seg[s].name, sec->segname))
                    mprotect((void *)page, page_end - page, to_prot(im->seg[s].prot));
        }
    }
    return replaced;
}

/* NSBundle's principal class when Info.plist names none: the first class
 * the bundle defines that the runtime kept. */
void *ferry_image_first_class(struct image *im)
{
    if (!im || !im->has_objc)
        return NULL;
    for (size_t i = 0; i < im->objc.nclasses; i++) {
        Class cls = im->objc.classlist[i];
        if (!cls)
            continue;
        const struct c_class_ro *ro = (const void *)(cls->bits & ~(uintptr_t)7);
        if (cls->superclass || (ro && (ro->flags & RO_ROOT)))
            return cls;
    }
    return NULL;
}

/* @executable_path, @loader_path and @rpath, as for a library the caller
 * (or the program, if the caller isn't one of its images) links. */
int ferry_image_resolve(struct image *caller, const char *name, char *out, size_t size)
{
    struct image *from = caller ? caller : main_image;
    if (!from) {
        snprintf(out, size, "%s", name);
        return name[0] != '@';
    }
    return expand_path(from, name, out, size);
}

/* Where Ferry keeps its own version of a system framework, by the
 * framework's Mac path. */
int ferry_find_system_framework(const char *install_name, char *out, size_t size)
{
    if (strncmp(install_name, "/System/Library/", 16) && strncmp(install_name, "/usr/lib/", 9))
        return 0;
    if (!strstr(install_name, ".framework/"))
        return 0;
    return find_framework(short_name(install_name), out, size);
}

struct image *ferry_image_load(const char *path, char *err, size_t errsize)
{
    int before = nimages;
    jmp_buf jb;
    jmp_buf *outer = load_failed;
    load_failed = &jb;
    if (setjmp(jb)) {
        load_failed = outer;
        snprintf(err, errsize, "%s", load_error);
        /* Forget the images that didn't finish loading (their memory stays
         * mapped); the ones that did are kept, set up when first used. */
        int n = before;
        for (int i = before; i < nimages; i++)
            if (images[i]->complete)
                images[n++] = images[i];
        nimages = n;
        ferry_seal_stubs();
        return NULL;
    }
    struct image *im = load_image(path);
    load_failed = outer;
    ferry_seal_stubs();
    char *apple[] = {NULL};
    initialize_image(im, start_argc, start_argv, start_envp, apple);
    return im;
}

/* ---- running ------------------------------------------------------------------- */

typedef int (*mac_main)(int, char **, char **, char **);

/* A program with LC_UNIXTHREAD starts at its own start routine (the
 * compiler's crt1), which expects the stack the kernel builds: argc, the
 * argument pointers, NULL, the environment, NULL, the "apple" strings,
 * NULL. It calls main and then exit itself, so this never returns. */
__attribute__((noreturn)) void ferry_jump_to_start(uint64_t pc, uint64_t *sp);
__asm__(".text\n"
        ".globl ferry_jump_to_start\n"
        "ferry_jump_to_start:\n"
        "    movq %rsi, %rsp\n"
        "    xorl %ebp, %ebp\n"
        "    xorl %eax, %eax\n"
        "    xorl %edx, %edx\n"
        "    jmpq *%rdi\n");

static __attribute__((noreturn)) void start_unixthread(uint64_t pc, int argc, char **argv, char **envp)
{
    int nenv = 0;
    while (envp && envp[nenv])
        nenv++;
    size_t words = 1 + (size_t)argc + 1 + (size_t)nenv + 1 + 2;
    size_t size = 1 << 20; /* the start routine's own stack, then main's */
    uint8_t *stack = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (stack == MAP_FAILED)
        die("can't make a stack for the program");
    uint64_t *sp = (uint64_t *)(((uintptr_t)(stack + size) - words * 8) & ~(uintptr_t)15);
    uint64_t *w = sp;
    *w++ = (uint64_t)argc;
    for (int i = 0; i < argc; i++)
        *w++ = (uint64_t)argv[i];
    *w++ = 0;
    for (int i = 0; i < nenv; i++)
        *w++ = (uint64_t)envp[i];
    *w++ = 0;
    *w++ = 0; /* no apple strings */
    note("jumping to the start routine at %p", (void *)pc);
    ferry_jump_to_start(pc, sp);
}

int ferry_run(const char *path, int argc, char **argv, char **envp)
{
    start_argc = argc;
    start_argv = argv;
    start_envp = envp;
    struct image *im = load_image(path);
    ferry_seal_stubs();
    if (missing_classes)
        fprintf(stderr, "ferry: %s uses %d Objective-C class%s Ferry doesn't have yet; %s nil "
                        "(FERRY_VERBOSE=1 lists them)\n", short_name(path), missing_classes,
                missing_classes == 1 ? "" : "es", missing_classes == 1 ? "it is" : "they are");
    mac_main entry = (mac_main)(image_base(im) + im->entryoff);
    char *apple[] = {NULL};
    ferry_program_started(path, argc, argv);
    initialize_image(im, argc, argv, envp, apple);
    if (im->unixthread)
        start_unixthread(im->thread_pc + im->slide, argc, argv, envp);
    note("calling main at %p", (void *)entry);
    int status = entry(argc, argv, envp, apple);
    ferry_tlv_exit();   /* as exit would: the main thread's thread-local destructors */
    return status;
}
