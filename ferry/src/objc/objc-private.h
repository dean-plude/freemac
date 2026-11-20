/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Objective-C runtime: shared definitions.
 *
 * The "compiled" structures below are the ones clang emits into a Mach-O
 * file for the x86-64 macOS (non-fragile) Objective-C ABI. Their layout was
 * taken from what clang produces for our own test programs, as printed by
 * LLVM's llvm-objdump --objc-meta-data, never from Apple's runtime sources.
 * Everything else here is Ferry's own design.
 */
#ifndef FERRY_OBJC_PRIVATE_H
#define FERRY_OBJC_PRIVATE_H

#include <pthread.h>
#include <stddef.h>
#include <stdint.h>

typedef struct fobjc_class *Class;
typedef struct fobjc_object { Class isa; } *id;
typedef const char *SEL;            /* a selector is its uniqued name */
typedef id (*IMP)(id, SEL, ...);
typedef signed char BOOL;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)

/* ---- what the compiler emits ------------------------------------------------ */

/* A class (and a metaclass): five words. The runtime keeps its own state in
 * the two middle words: "cache" points at the method cache's buckets and
 * "vtable" holds the cache's index mask (see msgsend.S). */
struct fobjc_class {
    Class isa;
    Class superclass;
    struct fbucket *cache;
    uintptr_t mask16;               /* (capacity - 1) << 4 */
    uintptr_t bits;                 /* struct c_class_ro *, low bits are flags */
};

#define RO_META             0x1
#define RO_ROOT             0x2
#define RO_HAS_CXX_STRUCTORS 0x4

struct c_class_ro {
    uint32_t flags, instance_start, instance_size, reserved;
    const uint8_t *ivar_layout;
    const char *name;
    struct c_method_list *methods;
    struct c_protocol_list *protocols;
    struct c_ivar_list *ivars;
    const uint8_t *weak_ivar_layout;
    struct c_property_list *properties;
};

struct c_method_list { uint32_t entsize_flags, count; };
struct c_method { const char *name; const char *types; IMP imp; };
/* "Small" method lists hold 32-bit offsets relative to each field. */
struct c_small_method { int32_t name, types, imp; };
#define METHOD_LIST_SMALL 0x80000000u
#define METHOD_LIST_FLAGS 0xffff0000u

struct c_ivar_list { uint32_t entsize, count; };
struct c_ivar { uint64_t *offset; const char *name, *type; uint32_t align_log2, size; };

struct c_property_list { uint32_t entsize, count; };
struct c_property { const char *name, *attributes; };

struct c_protocol_list { uint64_t count; struct c_protocol *list[]; };

struct c_protocol {
    Class isa;
    const char *name;
    struct c_protocol_list *protocols;
    struct c_method_list *instance_methods, *class_methods;
    struct c_method_list *opt_instance_methods, *opt_class_methods;
    struct c_property_list *properties;
    uint32_t size, flags;
    const char **extended_types;
    const char *demangled_name;
    struct c_property_list *class_properties;
};

struct c_category {
    const char *name;
    Class cls;
    struct c_method_list *instance_methods, *class_methods;
    struct c_protocol_list *protocols;
    struct c_property_list *instance_properties, *class_properties;
};

#define IMAGEINFO_HAS_CATEGORY_CLASS_PROPERTIES 0x40

/* ---- the runtime's own records -------------------------------------------- */

struct fbucket { SEL sel; IMP imp; };

struct fmethod { SEL name; const char *types; IMP imp; };
struct fmlist { struct fmlist *next; uint32_t count; struct fmethod m[]; };

struct fivar {
    uint64_t *offset;               /* the program's offset variable, or own_offset */
    uint64_t own_offset;
    const char *name, *type;
    uint32_t align_log2, size;
};

struct fprop { const char *name, *attributes; };
struct fplist { struct fplist *next; uint32_t count; struct fprop p[]; };

enum {
    RT_META = 1 << 0,
    RT_ROOT = 1 << 1,
    RT_INITIALIZING = 1 << 2,
    RT_INITIALIZED = 1 << 3,
    RT_HAS_CXX = 1 << 4,
    RT_RR_KNOWN = 1 << 5,           /* RT_DEFAULT_RR below is up to date */
    RT_DEFAULT_RR = 1 << 6,         /* retain/release are NSObject's own */
    RT_STATIC_INSTANCES = 1 << 7,   /* instances have no object header */
    RT_CONSTRUCTING = 1 << 8,       /* objc_allocateClassPair, not registered yet */
    RT_LOADED = 1 << 9,             /* +load has run */
    RT_FUTURE = 1 << 10,
};

struct fclass_rt {
    Class cls;
    Class nonmeta;                  /* the class itself, or for a metaclass its class */
    const char *name;
    uint32_t flags;
    uint32_t instance_size;
    uint32_t occupied;
    int version;
    struct fmlist *methods;         /* categories first */
    struct fivar *ivars;
    uint32_t nivars;
    struct fplist *props;
    struct c_protocol **protos;
    uint32_t nprotos;
    struct fclass_rt *next_all;
    const char *image;
};

/* The bucket array is preceded by one header bucket whose first word points
 * back at the class's record. */
struct fcache_head { struct fclass_rt *rt; uintptr_t capacity; };

static inline struct fclass_rt *class_rt(Class cls)
{
    return ((struct fcache_head *)cls->cache - 1)->rt;
}

extern struct fbucket _objc_empty_cache_storage[2];
static inline int class_is_realized(Class cls)
{
    return cls->cache != _objc_empty_cache_storage && cls->cache != NULL;
}

/* Every object the runtime allocates has this header in front of it. */
struct fobj_header {
    uintptr_t extra_rc;             /* retain count minus one */
    uint32_t flags;
    uint32_t reserved;
};
#define OBJ_DEALLOCATING 1u
#define OBJ_WEAKLY_REFERENCED 2u
#define OBJ_HAS_ASSOC 4u
#define OBJ_HEADER(o) ((struct fobj_header *)(o) - 1)

/* ---- small hash tables (runtime.c) ------------------------------------------ */

struct ftable_entry { const void *key; void *value; };
struct ftable { struct ftable_entry *e; size_t cap, used; int strings; };
void *ferry_table_get(struct ftable *t, const void *key);
void ferry_table_put(struct ftable *t, const void *key, void *value);  /* NULL removes */

/* ---- shared state and helpers ------------------------------------------------ */

extern pthread_mutex_t ferry_objc_lock;
#define LOCK() pthread_mutex_lock(&ferry_objc_lock)
#define UNLOCK() pthread_mutex_unlock(&ferry_objc_lock)

/* Message sending from C. */
void ferry_objc_msgSend(void);
/* Calls a function through a pointer of another type: the IMP or
 * objc_msgSend is cast to the method's real signature first. */
static inline void *ferry_fnptr(void (*f)(void))
{
    void *p = (void *)f;
    __asm__("" : "+r"(p));      /* hide the original type from the compiler */
    return p;
}
#define FN(type, f) ((type)ferry_fnptr((void (*)(void))(f)))
#define SEND0(r, o, s) FN(r(*)(id, SEL), ferry_objc_msgSend)((id)(o), (s))
#define SEND1(r, o, s, a) FN(r(*)(id, SEL, __typeof__(a)), ferry_objc_msgSend)((id)(o), (s), (a))

/* Selectors the runtime itself uses. */
extern SEL SEL_alloc, SEL_allocWithZone, SEL_init, SEL_new, SEL_dealloc, SEL_retain, SEL_release,
    SEL_autorelease, SEL_retainCount, SEL_initialize, SEL_load, SEL_copy, SEL_copyWithZone,
    SEL_mutableCopyWithZone, SEL_resolveInstanceMethod, SEL_resolveClassMethod,
    SEL_forwardingTargetForSelector, SEL_doesNotRecognizeSelector, SEL_cxx_construct,
    SEL_cxx_destruct, SEL_isKindOfClass, SEL_respondsToSelector, SEL_class, SEL_forwardInvocation;

/* runtime.c */
SEL sel_registerName(const char *name);
const char *sel_getName(SEL sel);
Class object_getClass(id obj);
const char *class_getName(Class cls);
const char *object_getClassName(id obj);
Class objc_getClass(const char *name);
void ferry_objc_flush_caches(void);
struct fmethod *ferry_objc_find_own_method(Class cls, SEL sel);
IMP ferry_objc_find_imp(Class cls, SEL sel);
void ferry_objc_make_class(Class cls, Class meta, Class superclass, const char *name, uint32_t instance_size,
                           const struct fmethod *imethods, unsigned nimethods,
                           const struct fmethod *cmethods, unsigned ncmethods, uint32_t extra_flags);
int ferry_objc_has_default_rr(Class cls);
id class_createInstance(Class cls, size_t extra);
id ferry_objc_alloc_sized(Class cls, size_t size);
id object_dispose(id obj);
void *objc_destructInstance(id obj);
extern void *const ferry_objc_msgForward_ptr;
void ferry_objc_runtime_init(void);

/* nsobject.c */
id objc_retain(id obj);
void objc_release(id obj);
id objc_autorelease(id obj);
void ferry_objc_nsobject_init(void);
void ferry_objc_weak_clear(id obj);
void ferry_objc_assoc_clear(id obj);
extern struct fobjc_class ferry_class_NSObject, ferry_meta_NSObject;
extern struct fobjc_class ferry_class_Protocol, ferry_meta_Protocol;
extern const struct fmethod ferry_static_rr_methods[];
extern const unsigned ferry_static_rr_count;

/* blocks.c */
void ferry_blocks_init(void);
void *_Block_copy(const void *block);
void _Block_release(const void *block);

/* Loading an image's Objective-C sections (called by the loader). */
struct ferry_objc_image {
    const char *path;
    SEL *selrefs; size_t nselrefs;
    Class *classlist; size_t nclasses;
    Class *nlclslist; size_t nnlcls;
    struct c_category **catlist; size_t ncats;
    struct c_category **nlcatlist; size_t nnlcats;
    struct c_protocol **protolist; size_t nprotos;
    struct c_protocol **protorefs; size_t nprotorefs;
    uint32_t imageinfo_flags;
};
void ferry_objc_map_image(struct ferry_objc_image *im);
void ferry_objc_load_image(struct ferry_objc_image *im);

#endif
