/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Objective-C runtime: selectors, classes, protocols, loading the
 * Objective-C sections of a Mach-O image, method lookup and the public
 * <objc/runtime.h> API. Written for freemac from Apple's public API
 * documentation, the structures clang emits, and our own tests.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include "../ferry.h"
#include "objc-private.h"

pthread_mutex_t ferry_objc_lock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;

/* The compiler points every class's cache at this until the runtime has set
 * it up; an all-zero bucket is a cache miss. */
struct fbucket _objc_empty_cache_storage[2];

/* ---- small hash tables ------------------------------------------------------ */


static uint64_t hash_key(const struct ftable *t, const void *key)
{
    uint64_t h = 1469598103934665603ull;
    if (t->strings) {
        for (const unsigned char *p = key; *p; p++)
            h = (h ^ *p) * 1099511628211ull;
    } else {
        h = (uint64_t)(uintptr_t)key * 0x9e3779b97f4a7c15ull;
        h ^= h >> 29;
    }
    return h;
}

static int keys_equal(const struct ftable *t, const void *a, const void *b)
{
    return t->strings ? !strcmp(a, b) : a == b;
}

static struct ftable_entry *table_slot(struct ftable *t, const void *key)
{
    if (!t->cap)
        return NULL;
    size_t i = hash_key(t, key) & (t->cap - 1);
    for (;;) {
        struct ftable_entry *e = &t->e[i];
        if (!e->key || keys_equal(t, e->key, key))
            return e;
        i = (i + 1) & (t->cap - 1);
    }
}

void *ferry_table_get(struct ftable *t, const void *key)
{
    struct ftable_entry *e = table_slot(t, key);
    return e && e->key ? e->value : NULL;
}

void ferry_table_put(struct ftable *t, const void *key, void *value)
{
    if ((t->used + 1) * 4 >= t->cap * 3) {
        struct ftable old = *t;
        t->cap = old.cap ? old.cap * 2 : 64;
        t->e = calloc(t->cap, sizeof *t->e);
        t->used = 0;
        for (size_t i = 0; i < old.cap; i++)
            if (old.e[i].key && old.e[i].value)
                ferry_table_put(t, old.e[i].key, old.e[i].value);
        free(old.e);
    }
    struct ftable_entry *e = table_slot(t, key);
    if (!e->key) {
        e->key = key;
        t->used++;
    }
    e->value = value;   /* a NULL value marks a removed entry */
}

static struct ftable selectors = {.strings = 1};
static struct ftable classes = {.strings = 1};
static struct ftable protocols = {.strings = 1};
static struct fclass_rt *all_classes;

/* ---- selectors ----------------------------------------------------------- */

static SEL register_sel(const char *name, int copy)
{
    if (!name)
        return NULL;
    LOCK();
    SEL s = ferry_table_get(&selectors, name);
    if (!s) {
        s = copy ? strdup(name) : name;
        ferry_table_put(&selectors, s, (void *)s);
    }
    UNLOCK();
    return s;
}

SEL sel_registerName(const char *name) { return register_sel(name, 1); }
SEL sel_getUid(const char *name) { return register_sel(name, 1); }
const char *sel_getName(SEL sel) { return sel ? sel : "<null selector>"; }
BOOL sel_isEqual(SEL a, SEL b) { return a == b; }
BOOL sel_isMapped(SEL sel)
{
    if (!sel)
        return NO;
    LOCK();
    BOOL mapped = ferry_table_get(&selectors, sel) == sel;
    UNLOCK();
    return mapped;
}

SEL SEL_alloc, SEL_allocWithZone, SEL_init, SEL_new, SEL_dealloc, SEL_retain, SEL_release,
    SEL_autorelease, SEL_retainCount, SEL_initialize, SEL_load, SEL_copy, SEL_copyWithZone,
    SEL_mutableCopyWithZone, SEL_resolveInstanceMethod, SEL_resolveClassMethod,
    SEL_forwardingTargetForSelector, SEL_doesNotRecognizeSelector, SEL_cxx_construct,
    SEL_cxx_destruct, SEL_isKindOfClass, SEL_respondsToSelector, SEL_class, SEL_forwardInvocation;

/* ---- the method cache ------------------------------------------------------- */

/* Called with the runtime lock held. Messages are sent on other threads
 * without it (msgsend.S), so the stores are ordered for them: a bucket's
 * IMP before its selector, a new table before its mask. A table never gets
 * smaller, so a mask read with the table before it always fits. */
static void cache_alloc(Class cls, struct fclass_rt *rt, uintptr_t capacity)
{
    struct fcache_head *h = calloc(1, sizeof *h + capacity * sizeof(struct fbucket));
    h->rt = rt;
    h->capacity = capacity;
    /* The old table is left in place: a message being sent right now on
     * another thread may still be reading it. */
    __atomic_store_n(&cls->cache, (struct fbucket *)(h + 1), __ATOMIC_RELEASE);
    __atomic_store_n(&cls->mask16, (capacity - 1) << 4, __ATOMIC_RELEASE);
    rt->occupied = 0;
}

static void cache_fill(Class cls, SEL sel, IMP imp)
{
    struct fclass_rt *rt = class_rt(cls);
    uintptr_t cap = ((struct fcache_head *)cls->cache - 1)->capacity;
    if ((rt->occupied + 1) * 4 > cap * 3)
        cache_alloc(cls, rt, cap * 2);
    struct fbucket *b = cls->cache;
    uintptr_t mask = ((struct fcache_head *)cls->cache - 1)->capacity - 1;
    uintptr_t i = (uintptr_t)sel & mask;
    while (b[i].sel && b[i].sel != sel)
        i = (i + 1) & mask;
    if (b[i].sel)
        return;
    rt->occupied++;
    __atomic_store_n(&b[i].imp, imp, __ATOMIC_RELEASE);
    __atomic_store_n(&b[i].sel, sel, __ATOMIC_RELEASE);
}

void ferry_objc_flush_caches(void)
{
    LOCK();
    for (struct fclass_rt *rt = all_classes; rt; rt = rt->next_all) {
        uintptr_t cap = ((struct fcache_head *)rt->cls->cache - 1)->capacity;
        if (rt->occupied)
            cache_alloc(rt->cls, rt, cap);
        rt->flags &= ~RT_RR_KNOWN;
    }
    UNLOCK();
}

/* ---- method lists ------------------------------------------------------------ */

static struct fmlist *convert_methods(const struct c_method_list *ml)
{
    if (!ml || !ml->count)
        return NULL;
    struct fmlist *l = calloc(1, sizeof *l + ml->count * sizeof(struct fmethod));
    l->count = ml->count;
    uint32_t entsize = ml->entsize_flags & ~METHOD_LIST_FLAGS & ~3u;
    const uint8_t *p = (const uint8_t *)(ml + 1);
    for (uint32_t i = 0; i < ml->count; i++, p += entsize) {
        if (ml->entsize_flags & METHOD_LIST_SMALL) {
            const struct c_small_method *m = (const void *)p;
            /* name points at a selector reference; types and imp are direct */
            const char *const *ref = (const void *)((const uint8_t *)&m->name + m->name);
            l->m[i].name = register_sel(*ref, 0);
            l->m[i].types = (const char *)((const uint8_t *)&m->types + m->types);
            l->m[i].imp = (IMP)((const uint8_t *)&m->imp + m->imp);
        } else {
            const struct c_method *m = (const void *)p;
            l->m[i].name = register_sel(m->name, 0);
            l->m[i].types = m->types;
            l->m[i].imp = m->imp;
        }
    }
    return l;
}

static struct fmlist *make_methods(const struct fmethod *m, unsigned n)
{
    if (!n)
        return NULL;
    struct fmlist *l = calloc(1, sizeof *l + n * sizeof(struct fmethod));
    l->count = n;
    for (unsigned i = 0; i < n; i++) {
        l->m[i] = m[i];
        l->m[i].name = sel_registerName(m[i].name);
    }
    return l;
}

static void prepend_methods(struct fclass_rt *rt, struct fmlist *l)
{
    if (!l)
        return;
    l->next = rt->methods;
    rt->methods = l;
}

static struct fplist *convert_props(const struct c_property_list *pl)
{
    if (!pl || !pl->count)
        return NULL;
    struct fplist *l = calloc(1, sizeof *l + pl->count * sizeof(struct fprop));
    l->count = pl->count;
    const uint8_t *p = (const uint8_t *)(pl + 1);
    for (uint32_t i = 0; i < pl->count; i++, p += pl->entsize) {
        const struct c_property *cp = (const void *)p;
        l->p[i].name = cp->name;
        l->p[i].attributes = cp->attributes;
    }
    return l;
}

static void prepend_props(struct fclass_rt *rt, struct fplist *l)
{
    if (!l)
        return;
    l->next = rt->props;
    rt->props = l;
}

static void add_protocols(struct fclass_rt *rt, const struct c_protocol_list *pl);

struct fmethod *ferry_objc_find_own_method(Class cls, SEL sel)
{
    for (struct fmlist *l = class_rt(cls)->methods; l; l = l->next)
        for (uint32_t i = 0; i < l->count; i++)
            if (l->m[i].name == sel)
                return &l->m[i];
    return NULL;
}

static struct fmethod *find_method(Class cls, SEL sel)
{
    for (; cls; cls = cls->superclass) {
        struct fmethod *m = ferry_objc_find_own_method(cls, sel);
        if (m)
            return m;
    }
    return NULL;
}

IMP ferry_objc_find_imp(Class cls, SEL sel)
{
    LOCK();
    struct fmethod *m = find_method(cls, sel);
    UNLOCK();
    return m ? m->imp : NULL;
}

/* ---- classes ------------------------------------------------------------- */

static void register_class(struct fclass_rt *rt)
{
    rt->next_all = all_classes;
    all_classes = rt;
}

static void add_to_class_table(Class cls)
{
    const char *name = class_rt(cls)->name;
    if (ferry_table_get(&classes, name)) {
        if (ferry_verbose)
            fprintf(stderr, "ferry: class %s is defined twice; using the first\n", name);
        return;
    }
    ferry_table_put(&classes, name, cls);
}

static void realize_class(Class cls);

/* A Swift class's own metadata keeps its instance size as well, in the word
 * after the class's Objective-C part, and Swift's runtime starts a Swift
 * subclass's layout from it. When the ivars move, keep it as big as the
 * class now is, or a subclass laid out later puts its fields on top of
 * this class's (freemac 1.271, Stats' disk panel). */
static void swift_instance_size(Class cls, uint32_t size)
{
    if (!(cls->bits & 2))
        return;
    uint32_t *p = (uint32_t *)((uint8_t *)cls + 0x30);
    if (*p && *p < size)
        *p = size;
}

static void realize_compiled(Class cls)
{
    const struct c_class_ro *ro = (const void *)(cls->bits & ~(uintptr_t)7);
    struct fclass_rt *rt = calloc(1, sizeof *rt);
    rt->cls = cls;
    rt->name = ro->name ? ro->name : ferry_objc_lazy_class_name(cls);   /* Swift's generic classes (swift.c) */
    rt->image = NULL;
    if (ro->flags & RO_META)
        rt->flags |= RT_META | RT_STATIC_INSTANCES;
    if (ro->flags & RO_ROOT)
        rt->flags |= RT_ROOT;
    if (ro->flags & RO_HAS_CXX_STRUCTORS)
        rt->flags |= RT_HAS_CXX;
    /* Install the cache first, so recursion through isa sees it realized. */
    cache_alloc(cls, rt, 4);
    register_class(rt);

    Class super = cls->superclass;
    if (super)
        realize_class(super);
    if (!(rt->flags & RT_META)) {
        rt->nonmeta = cls;
        if (cls->isa) {
            realize_class(cls->isa);
            class_rt(cls->isa)->nonmeta = cls;
        }
    }

    rt->methods = convert_methods(ro->methods);
    rt->props = convert_props(ro->properties);
    add_protocols(rt, ro->protocols);

    /* Non-fragile ivars: if the superclass turned out bigger than the
     * compiler assumed, move this class's ivars down. */
    uint32_t start = ro->instance_start, size = ro->instance_size;
    uint32_t super_size = super ? class_rt(super)->instance_size : 0;
    const struct c_ivar_list *il = ro->ivars;
    uint32_t max_align = 1;
    if (il)
        for (uint32_t i = 0; i < il->count; i++) {
            const struct c_ivar *iv = (const void *)((const uint8_t *)(il + 1) + i * il->entsize);
            if ((1u << iv->align_log2) > max_align && iv->align_log2 < 16)
                max_align = 1u << iv->align_log2;
        }
    uint32_t diff = 0;
    if (!(rt->flags & RT_META) && super && super_size > start) {
        diff = super_size - start;
        diff = (diff + max_align - 1) & ~(max_align - 1);
        if (ferry_verbose)
            fprintf(stderr, "ferry: moving the ivars of %s by %u bytes\n", rt->name, diff);
    }
    rt->instance_size = size + diff;
    rt->slide = diff;
    if (il && il->count) {
        rt->ivars = calloc(il->count, sizeof *rt->ivars);
        rt->nivars = il->count;
        for (uint32_t i = 0; i < il->count; i++) {
            const struct c_ivar *iv = (const void *)((const uint8_t *)(il + 1) + i * il->entsize);
            struct fivar *v = &rt->ivars[i];
            v->offset = iv->offset ? iv->offset : &v->own_offset;
            if (iv->offset && diff)
                *iv->offset += diff;
            v->placed = *v->offset;
            v->name = iv->name;
            v->type = iv->type;
            v->align_log2 = iv->align_log2;
            v->size = iv->size;
        }
    }
    if (!(rt->flags & RT_META)) {
        if (diff)
            swift_instance_size(cls, rt->instance_size);
        add_to_class_table(cls);
    }
}

static void realize_class(Class cls)
{
    if (!cls || class_is_realized(cls))
        return;
    if (!cls->bits) {
        fprintf(stderr, "ferry: found a class with no description at %p\n", (void *)cls);
        exit(126);
    }
    realize_compiled(cls);
}

void ferry_objc_make_class(Class cls, Class meta, Class superclass, const char *name, uint32_t instance_size,
                           const struct fmethod *imethods, unsigned nimethods,
                           const struct fmethod *cmethods, unsigned ncmethods, uint32_t extra_flags)
{
    struct fclass_rt *rt = calloc(1, sizeof *rt), *mrt = calloc(1, sizeof *mrt);
    rt->cls = cls;
    rt->nonmeta = cls;
    rt->name = name;
    rt->flags = (superclass ? 0 : RT_ROOT) | extra_flags;
    rt->instance_size = instance_size;
    rt->methods = make_methods(imethods, nimethods);
    mrt->cls = meta;
    mrt->nonmeta = cls;
    mrt->name = name;
    mrt->flags = RT_META | RT_STATIC_INSTANCES | (superclass ? 0 : RT_ROOT);
    mrt->instance_size = sizeof(struct fobjc_class);
    mrt->methods = make_methods(cmethods, ncmethods);
    cls->isa = meta;
    cls->superclass = superclass;
    cls->bits = 0;
    if (superclass) {
        meta->isa = superclass->isa->isa;   /* the root metaclass */
        meta->superclass = superclass->isa;
    } else {
        meta->isa = meta;
        meta->superclass = cls;
    }
    meta->bits = 0;
    cache_alloc(cls, rt, 8);
    cache_alloc(meta, mrt, 8);
    LOCK();
    register_class(rt);
    register_class(mrt);
    if (!(extra_flags & RT_CONSTRUCTING))
        add_to_class_table(cls);
    UNLOCK();
}

/* Whether retain/release/autorelease on instances of cls are NSObject's
 * own, so objc_retain() and friends may do the work without a message. */
int ferry_objc_has_default_rr(Class cls)
{
    struct fclass_rt *rt = class_rt(cls);
    uint32_t f = __atomic_load_n(&rt->flags, __ATOMIC_ACQUIRE);
    if (f & RT_RR_KNOWN)
        return !!(f & RT_DEFAULT_RR);
    int def = 0;
    if (!(f & RT_STATIC_INSTANCES)) {
        Class root = &ferry_class_NSObject;
        def = ferry_objc_find_imp(cls, SEL_retain) == ferry_objc_find_imp(root, SEL_retain)
           && ferry_objc_find_imp(cls, SEL_release) == ferry_objc_find_imp(root, SEL_release)
           && ferry_objc_find_imp(cls, SEL_autorelease) == ferry_objc_find_imp(root, SEL_autorelease)
           && ferry_objc_find_imp(cls, SEL_retainCount) == ferry_objc_find_imp(root, SEL_retainCount);
    }
    LOCK();
    rt->flags = (rt->flags & ~RT_DEFAULT_RR) | RT_RR_KNOWN | (def ? RT_DEFAULT_RR : 0);
    UNLOCK();
    return def;
}

/* ---- protocols --------------------------------------------------------------- */

static struct c_protocol *canonical_protocol(struct c_protocol *p)
{
    if (!p)
        return NULL;
    struct c_protocol *c = ferry_table_get(&protocols, p->name);
    return c ? c : p;
}

static void add_protocol(struct fclass_rt *rt, struct c_protocol *p)
{
    p = canonical_protocol(p);
    for (uint32_t i = 0; i < rt->nprotos; i++)
        if (rt->protos[i] == p)
            return;
    rt->protos = realloc(rt->protos, (rt->nprotos + 1) * sizeof *rt->protos);
    rt->protos[rt->nprotos++] = p;
}

static void add_protocols(struct fclass_rt *rt, const struct c_protocol_list *pl)
{
    if (pl)
        for (uint64_t i = 0; i < pl->count; i++)
            add_protocol(rt, pl->list[i]);
}

static void register_protocol(struct c_protocol *p)
{
    if (!ferry_table_get(&protocols, p->name)) {
        p->isa = &ferry_class_Protocol;
        ferry_table_put(&protocols, p->name, p);
    }
}

/* ---- loading an image ------------------------------------------------------- */

static void attach_category(struct c_category *cat, uint32_t imageinfo_flags)
{
    Class cls = cat->cls;
    if (!cls) {
        if (ferry_verbose)
            fprintf(stderr, "ferry: category %s is for a class that isn't there; skipped\n", cat->name);
        return;
    }
    realize_class(cls);
    struct fclass_rt *rt = class_rt(cls), *mrt = class_rt(cls->isa);
    prepend_methods(rt, convert_methods(cat->instance_methods));
    prepend_methods(mrt, convert_methods(cat->class_methods));
    add_protocols(rt, cat->protocols);
    prepend_props(rt, convert_props(cat->instance_properties));
    if (imageinfo_flags & IMAGEINFO_HAS_CATEGORY_CLASS_PROPERTIES)
        prepend_props(mrt, convert_props(cat->class_properties));
}

/* Swift marks its classes in the low bits of the data word: bit 1 on a Mac
 * since Swift's stable ABI, bit 0 in code built for an older macOS, which
 * is how Swift's own libraries are built. Swift's runtime only takes bit 1
 * as "a Swift class", so classes with the older bit get the newer one, as
 * the Swift runtime's own comments say a Mac's does (freemac 1.227). */
static void swift_stable_bit(Class cls)
{
    if (cls && (cls->bits & 3) == 1)
        cls->bits ^= 3;
}

void ferry_objc_map_image(struct ferry_objc_image *im)
{
    LOCK();
    for (size_t i = 0; i < im->nclasses; i++)
        if (im->classlist[i]) {
            swift_stable_bit(im->classlist[i]);
            swift_stable_bit(im->classlist[i]->isa);
        }
    for (size_t i = 0; i < im->nselrefs; i++)
        im->selrefs[i] = register_sel(im->selrefs[i], 0);
    for (size_t i = 0; i + 1 < im->nmsgrefs; i += 2)
        im->msgrefs[i + 1] = (void *)register_sel(im->msgrefs[i + 1], 0);
    for (size_t i = 0; i < im->nprotos; i++)
        register_protocol(im->protolist[i]);
    for (size_t i = 0; i < im->nprotorefs; i++)
        im->protorefs[i] = canonical_protocol(im->protorefs[i]);
    for (size_t i = 0; i < im->nclasses; i++) {
        Class cls = im->classlist[i];
        if (!cls)
            continue;
        const struct c_class_ro *ro = (const void *)(cls->bits & ~(uintptr_t)7);
        if (!cls->superclass && !(ro->flags & RO_ROOT)) {
            fprintf(stderr, "ferry: the class %s is built on a class Ferry doesn't have yet; left out\n", ro->name);
            /* Its cache words may still hold what older linkers put there
             * (_objc_empty_cache and _objc_empty_vtable): make them an empty
             * cache, so a message to it misses and is reported, not a crash. */
            cls->cache = _objc_empty_cache_storage;
            cls->mask16 = 0;
            if (cls->isa) {
                cls->isa->cache = _objc_empty_cache_storage;
                cls->isa->mask16 = 0;
            }
            continue;
        }
        realize_class(cls);
        class_rt(cls)->image = im->path;
        class_rt(cls->isa)->image = im->path;
    }
    for (size_t i = 0; i < im->ncats; i++)
        attach_category(im->catlist[i], im->imageinfo_flags);
    for (size_t i = 0; i < im->nnlcats; i++) {
        /* non-lazy categories also appear in __objc_catlist; attach once */
        int seen = 0;
        for (size_t j = 0; j < im->ncats; j++)
            if (im->catlist[j] == im->nlcatlist[i])
                seen = 1;
        if (!seen)
            attach_category(im->nlcatlist[i], im->imageinfo_flags);
    }
    UNLOCK();
    if (im->ncats || im->nnlcats)
        ferry_objc_flush_caches();
}

typedef void (*load_fn)(id, SEL);

static void call_class_load(Class cls)
{
    if (!cls)
        return;
    struct fclass_rt *rt = class_rt(cls);
    if (rt->flags & RT_LOADED)
        return;
    rt->flags |= RT_LOADED;
    call_class_load(cls->superclass);
    struct fmethod *m = NULL;
    /* +load is never inherited: only the class's own (non-category) one. */
    for (struct fmlist *l = class_rt(cls->isa)->methods; l; l = l->next)
        for (uint32_t i = 0; i < l->count; i++)
            if (l->m[i].name == SEL_load)
                m = &l->m[i];   /* the last list is the class's own */
    const struct c_class_ro *ro = (const void *)(cls->bits & ~(uintptr_t)7);
    if (m && ro && ro->methods) {
        /* check that it came from the class itself, not a category */
        struct fmlist *own = class_rt(cls->isa)->methods;
        while (own && own->next)
            own = own->next;
        if (own && m >= own->m && m < own->m + own->count)
            FN(load_fn, m->imp)((id)cls, SEL_load);
    }
}

/* FERRY_REPORT_SELECTORS=<part of a program's path>: list the selectors
 * that program names which no class here implements, the messages it may
 * send that nothing would answer (a tool for finding what a Mac app needs
 * next; freemac 1.262). */
static int sel_has_imp(SEL sel)
{
    for (struct fclass_rt *rt = all_classes; rt; rt = rt->next_all)
        for (struct fmlist *l = rt->methods; l; l = l->next)
            for (uint32_t i = 0; i < l->count; i++)
                if (l->m[i].name == sel)
                    return 1;
    return 0;
}

static void report_selectors(struct ferry_objc_image *im)
{
    const char *want = getenv("FERRY_REPORT_SELECTORS");
    if (!want || !*want || !im->path || !strstr(im->path, want))
        return;
    size_t n = 0;
    LOCK();
    for (size_t i = 0; i < im->nselrefs; i++) {
        SEL s = im->selrefs[i];
        int dup = 0;
        for (size_t j = 0; j < i && !dup; j++)
            dup = im->selrefs[j] == s;
        if (!dup && s && !sel_has_imp(s)) {
            fprintf(stderr, "ferry: nothing implements %s\n", sel_getName(s));
            n++;
        }
    }
    UNLOCK();
    fprintf(stderr, "ferry: %zu of %s's selectors have no method anywhere\n", n, im->path);
}

void ferry_objc_load_image(struct ferry_objc_image *im)
{
    report_selectors(im);
    for (size_t i = 0; i < im->nnlcls; i++)
        call_class_load(im->nlclslist[i]);
    for (size_t i = 0; i < im->nnlcats; i++) {
        struct c_category *cat = im->nlcatlist[i];
        if (!cat->cls || !cat->class_methods)
            continue;
        struct fmlist *l = convert_methods(cat->class_methods);
        for (uint32_t j = 0; l && j < l->count; j++)
            if (l->m[j].name == SEL_load)
                FN(load_fn, l->m[j].imp)((id)cat->cls, SEL_load);
        free(l);
    }
}

/* ---- lookup (called from msgsend.S on a cache miss) ------------------------- */

void ferry_objc_msgForward(void);
void ferry_objc_msgForward_stret(void);
void ferry_objc_resend(void);
void ferry_objc_resend_stret(void);
void *const ferry_objc_msgForward_ptr = (void *)ferry_objc_msgForward;
__thread id ferry_objc_fwd_target;

/* +initialize runs once, on the thread that first sends the class a
 * message. Other threads that send it one meanwhile wait until it has
 * finished; the initializing thread itself goes on (its +initialize may
 * message the class). Nothing is cached for a class until then, so every
 * message to it on another thread comes here. */
static pthread_mutex_t init_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t init_done = PTHREAD_COND_INITIALIZER;

static uint32_t rt_flags(struct fclass_rt *rt) { return __atomic_load_n(&rt->flags, __ATOMIC_ACQUIRE); }

static void initialize_class(Class cls)
{
    if (cls->superclass)
        initialize_class(cls->superclass);
    LOCK();
    struct fclass_rt *rt = class_rt(cls);
    if (rt->flags & RT_INITIALIZED) {
        UNLOCK();
        return;
    }
    if (rt->flags & RT_INITIALIZING) {
        int mine = pthread_equal(rt->init_thread, pthread_self());
        UNLOCK();
        if (mine)
            return;
        pthread_mutex_lock(&init_lock);
        while (!(rt_flags(rt) & RT_INITIALIZED))
            pthread_cond_wait(&init_done, &init_lock);
        pthread_mutex_unlock(&init_lock);
        return;
    }
    rt->flags |= RT_INITIALIZING;
    rt->init_thread = pthread_self();
    UNLOCK();
    SEND0(void, cls, SEL_initialize);
    LOCK();
    rt->flags |= RT_INITIALIZED;
    UNLOCK();
    pthread_mutex_lock(&init_lock);
    pthread_cond_broadcast(&init_done);
    pthread_mutex_unlock(&init_lock);
}

IMP ferry_objc_lookup(id receiver, SEL sel, Class cls, int stret)
{
    (void)receiver;
    LOCK();
    if (!class_is_realized(cls))
        realize_class(cls);
    struct fclass_rt *rt = class_rt(cls);
    Class nonmeta = rt->nonmeta ? rt->nonmeta : cls;
    int initialized = (class_rt(nonmeta)->flags & RT_INITIALIZED) != 0;
    UNLOCK();
    if (!initialized) {
        initialize_class(nonmeta);
        initialized = (rt_flags(class_rt(nonmeta)) & RT_INITIALIZED) != 0;
    }
    LOCK();
    struct fmethod *m = find_method(cls, sel);
    UNLOCK();
    if (!m && sel != SEL_resolveInstanceMethod && sel != SEL_resolveClassMethod) {
        BOOL added;
        if (rt->flags & RT_META)
            added = FN(BOOL(*)(id, SEL, SEL), ferry_objc_msgSend)((id)nonmeta, SEL_resolveClassMethod, sel);
        else
            added = FN(BOOL(*)(id, SEL, SEL), ferry_objc_msgSend)((id)cls, SEL_resolveInstanceMethod, sel);
        if (added) {
            LOCK();
            m = find_method(cls, sel);
            UNLOCK();
        }
    }
    if (!m)
        return (IMP)(stret ? (void *)ferry_objc_msgForward_stret : (void *)ferry_objc_msgForward);
    /* while +initialize is still running, other threads must keep coming here to wait */
    if (initialized) {
        LOCK();
        cache_fill(cls, sel, m->imp);
        UNLOCK();
    }
    return m->imp;
}

/* Where a message nothing implements goes once forwardingTargetForSelector:
 * has found no other receiver: Ferry's Foundation sets these (through
 * ferry_objc_setForwardHandler, a call of Ferry's own that only its
 * Foundation uses) to its entry points, which are jumped to with the
 * message's registers and stack exactly as the sender left them. */
static void *forward_handler, *forward_handler_stret;

void ferry_objc_setForwardHandler(void *fwd, void *fwd_stret)
{
    forward_handler = fwd;
    forward_handler_stret = fwd_stret;
}

/* The receiver doesn't implement sel: try forwardingTargetForSelector:,
 * then Foundation's forwarding, then doesNotRecognizeSelector:, which
 * stops the program. */
IMP ferry_objc_forward_target(id self, SEL sel, Class unused, int stret)
{
    (void)unused;
    Class cls = object_getClass(self);
    IMP fwd = ferry_objc_find_imp(cls, SEL_forwardingTargetForSelector);
    if (fwd) {
        id target = FN(id(*)(id, SEL, SEL), fwd)(self, SEL_forwardingTargetForSelector, sel);
        if (target && target != self) {
            ferry_objc_fwd_target = target;
            return (IMP)(stret ? (void *)ferry_objc_resend_stret : (void *)ferry_objc_resend);
        }
    }
    if (!ferry_objc_find_imp(cls, SEL_doesNotRecognizeSelector)) {
        /* A class Ferry left out because its superclass is missing: it has
         * no methods at all, not even NSObject's. */
        const struct c_class_ro *ro = (const void *)(cls->bits & ~(uintptr_t)7);
        fflush(stdout);
        fprintf(stderr, "ferry: the program sent %s to %s, a class Ferry left out because it is built on a class "
                        "Ferry doesn't have yet\n", sel, ro && ro->name ? ro->name : "(unknown)");
        _exit(127);
    }
    /* Foundation's forwarding (methodSignatureForSelector: and
     * forwardInvocation:, with an NSInvocation), when Foundation is loaded. */
    void *handler = stret ? forward_handler_stret : forward_handler;
    if (handler)
        return (IMP)handler;
    IMP fi = ferry_objc_find_imp(cls, SEL_forwardInvocation);
    IMP root_fi = ferry_objc_find_imp(&ferry_class_NSObject, SEL_forwardInvocation);
    if (fi && fi != root_fi) {
        fflush(stdout);
        fprintf(stderr, "ferry: %s forwards %s with forwardInvocation:, which needs Foundation's NSInvocation; "
                "the program doesn't use Foundation\n", class_getName(cls), sel);
        _exit(127);
    }
    FN(void (*)(id, SEL, SEL), ferry_objc_msgSend)(self, SEL_doesNotRecognizeSelector, sel);
    fflush(stdout);
    fprintf(stderr, "ferry: doesNotRecognizeSelector: returned for %s\n", sel);
    abort();
}

/* ---- the public API: classes ------------------------------------------------- */

Class objc_getClass(const char *name)
{
    if (!name)
        return NULL;
    LOCK();
    Class c = ferry_table_get(&classes, name);
    UNLOCK();
    if (!c)
        c = ferry_objc_class_from_hook(name);   /* Swift's classes made on first use (swift.c) */
    return c;
}

/* A Swift class that derives from an Objective-C one, realized when its
 * image loaded, has its metadata filled in later by Swift's runtime, which
 * writes the ivar offsets it worked out, from where its description says
 * the class starts, into the offset variables realizing had moved. As
 * Apple's runtime does when Swift then hands it the class, move them again
 * if the superclass is really bigger than that, and take the class's size
 * from what Swift's runtime worked out (freemac 1.271: Stats' disk panel,
 * whose offsets were all still 0 when its image loaded). */
static void reslide_ivars(Class cls)
{
    struct fclass_rt *rt = class_rt(cls);
    if (rt->flags & RT_META)
        return;
    const struct c_class_ro *ro = (const void *)(cls->bits & ~(uintptr_t)7);
    uint32_t start = ro->instance_start, size = ro->instance_size;
    uint32_t super_size = cls->superclass ? class_rt(cls->superclass)->instance_size : 0;
    const struct c_ivar_list *il = ro->ivars;
    uint32_t diff = 0;
    if (il && start < super_size) {
        uint32_t max_align = 1, lowest = UINT32_MAX;
        for (uint32_t i = 0; i < il->count; i++) {
            const struct c_ivar *iv = (const void *)((const uint8_t *)(il + 1) + i * il->entsize);
            if ((1u << iv->align_log2) > max_align && iv->align_log2 < 16)
                max_align = 1u << iv->align_log2;
            if (iv->offset && iv->size && *iv->offset < lowest)
                lowest = (uint32_t)*iv->offset;
        }
        diff = super_size - start;
        diff = (diff + max_align - 1) & ~(max_align - 1);
        /* offsets already past the superclass were moved before */
        if (lowest != UINT32_MAX && lowest < super_size) {
            for (uint32_t i = 0; i < il->count; i++) {
                const struct c_ivar *iv = (const void *)((const uint8_t *)(il + 1) + i * il->entsize);
                if (iv->offset) {
                    *iv->offset += diff;
                    if (ferry_verbose)
                        fprintf(stderr, "ferry: moving %s's ivar %s again, by %u bytes\n", rt->name,
                                iv->name ? iv->name : "?", diff);
                }
            }
        }
        size += diff;
    }
    for (uint32_t i = 0; i < rt->nivars; i++)
        rt->ivars[i].placed = *rt->ivars[i].offset;
    if (size > rt->instance_size)
        rt->instance_size = size;
    swift_instance_size(cls, rt->instance_size);
}

/* For swift.c: a class whose description Swift's runtime filled in while
 * the program runs, realized as a compiled one is. */
Class ferry_objc_realize_runtime_class(Class cls, const char *image)
{
    if (!cls)
        return NULL;
    LOCK();
    int fresh = !class_is_realized(cls);
    if (fresh)
        realize_class(cls);
    else
        reslide_ivars(cls);
    if (image && fresh) {
        class_rt(cls)->image = image;
        class_rt(cls->isa)->image = image;
    }
    UNLOCK();
    return cls;
}

Class objc_lookUpClass(const char *name) { return objc_getClass(name); }

Class objc_getRequiredClass(const char *name)
{
    Class c = objc_getClass(name);
    if (!c) {
        fprintf(stderr, "objc[%d]: link error: class '%s' not found.\n", getpid(), name);
        abort();
    }
    return c;
}

Class objc_getMetaClass(const char *name)
{
    Class c = objc_getClass(name);
    return c ? c->isa : NULL;
}

int objc_getClassList(Class *buffer, int count)
{
    int n = 0;
    LOCK();
    for (struct fclass_rt *rt = all_classes; rt; rt = rt->next_all) {
        if (rt->flags & (RT_META | RT_CONSTRUCTING))
            continue;
        if (buffer && n < count)
            buffer[n] = rt->cls;
        n++;
    }
    UNLOCK();
    return n;
}

Class *objc_copyClassList(unsigned *out)
{
    int n = objc_getClassList(NULL, 0);
    Class *list = calloc(n + 1, sizeof *list);
    n = objc_getClassList(list, n);
    if (out)
        *out = n;
    return list;
}

/* the names of the classes a binary defines (Sparkle's installer looks up
 * its own; freemac 1.264); the caller frees the list, not the names */
const char **objc_copyClassNamesForImage(const char *image, unsigned *out)
{
    unsigned n = 0, k = 0;
    Class *all = objc_copyClassList(&n);
    const char **names = calloc(n + 1, sizeof *names);
    char want[4096];
    if (!image || !realpath(image, want))
        snprintf(want, sizeof want, "%s", image ? image : "");
    for (unsigned i = 0; i < n && names; i++) {
        const char *path = class_rt(all[i])->image;
        char real[4096];
        if (!path)
            continue;
        if (!realpath(path, real))
            snprintf(real, sizeof real, "%s", path);
        if (!strcmp(real, want))
            names[k++] = class_rt(all[i])->name;
    }
    free(all);
    if (out)
        *out = k;
    if (!k) {
        free(names);
        return NULL;
    }
    return names;
}

const char *class_getName(Class cls) { return cls ? class_rt(cls)->name : "nil"; }
Class class_getSuperclass(Class cls) { return cls ? cls->superclass : NULL; }
BOOL class_isMetaClass(Class cls) { return cls && (class_rt(cls)->flags & RT_META); }
size_t class_getInstanceSize(Class cls) { return cls ? class_rt(cls)->instance_size : 0; }
int class_getVersion(Class cls) { return cls ? class_rt(cls)->version : 0; }
void class_setVersion(Class cls, int v) { if (cls) class_rt(cls)->version = v; }
const uint8_t *class_getIvarLayout(Class cls) { (void)cls; return NULL; }
const uint8_t *class_getWeakIvarLayout(Class cls) { (void)cls; return NULL; }
void class_setIvarLayout(Class cls, const uint8_t *l) { (void)cls; (void)l; }
void class_setWeakIvarLayout(Class cls, const uint8_t *l) { (void)cls; (void)l; }

static char program_image[4096];
const char *class_getImageName(Class cls)
{
    if (!cls)
        return NULL;
    const char *image = class_rt(cls)->image;
    if (image) {
        if (!realpath(image, program_image))
            snprintf(program_image, sizeof program_image, "%s", image);
        return program_image;
    }
    return "/usr/lib/libobjc.A.dylib";
}

struct fmethod *class_getInstanceMethod(Class cls, SEL sel)
{
    if (!cls || !sel)
        return NULL;
    LOCK();
    struct fmethod *m = find_method(cls, sel);
    UNLOCK();
    return m;
}

struct fmethod *class_getClassMethod(Class cls, SEL sel)
{
    return cls ? class_getInstanceMethod(object_getClass((id)cls), sel) : NULL;
}

IMP class_getMethodImplementation(Class cls, SEL sel)
{
    if (!cls || !sel)
        return NULL;
    IMP imp = ferry_objc_lookup(nil, sel, cls, 0);
    return imp;
}

IMP class_getMethodImplementation_stret(Class cls, SEL sel)
{
    if (!cls || !sel)
        return NULL;
    return ferry_objc_lookup(nil, sel, cls, 1);
}

BOOL class_respondsToSelector(Class cls, SEL sel)
{
    if (!cls || !sel)
        return NO;
    IMP imp = ferry_objc_lookup(nil, sel, cls, 0);
    return imp != (IMP)ferry_objc_msgForward;
}

struct fmethod **class_copyMethodList(Class cls, unsigned *out)
{
    unsigned n = 0;
    struct fmethod **list = NULL;
    if (cls) {
        LOCK();
        for (struct fmlist *l = class_rt(cls)->methods; l; l = l->next)
            n += l->count;
        list = calloc(n + 1, sizeof *list);
        n = 0;
        for (struct fmlist *l = class_rt(cls)->methods; l; l = l->next)
            for (uint32_t i = 0; i < l->count; i++)
                list[n++] = &l->m[i];
        UNLOCK();
    }
    if (out)
        *out = n;
    if (!n) {
        free(list);
        return NULL;
    }
    return list;
}

BOOL class_addMethod(Class cls, SEL sel, IMP imp, const char *types)
{
    if (!cls || !sel)
        return NO;
    LOCK();
    if (ferry_objc_find_own_method(cls, sel)) {
        UNLOCK();
        return NO;
    }
    struct fmethod m = {sel, types ? strdup(types) : "", imp};
    struct fmlist *l = calloc(1, sizeof *l + sizeof(struct fmethod));
    l->count = 1;
    l->m[0] = m;
    l->m[0].name = sel_registerName(sel);
    prepend_methods(class_rt(cls), l);
    UNLOCK();
    ferry_objc_flush_caches();
    return YES;
}

IMP class_replaceMethod(Class cls, SEL sel, IMP imp, const char *types)
{
    if (!cls || !sel)
        return NULL;
    LOCK();
    struct fmethod *m = ferry_objc_find_own_method(cls, sel);
    if (m) {
        IMP old = m->imp;
        m->imp = imp;
        UNLOCK();
        ferry_objc_flush_caches();
        return old;
    }
    UNLOCK();
    class_addMethod(cls, sel, imp, types);
    return NULL;
}

static struct fivar *find_ivar(Class cls, const char *name)
{
    for (; cls; cls = cls->superclass) {
        struct fclass_rt *rt = class_rt(cls);
        for (uint32_t i = 0; i < rt->nivars; i++)
            if (rt->ivars[i].name && !strcmp(rt->ivars[i].name, name))
                return &rt->ivars[i];
    }
    return NULL;
}

struct fivar *class_getInstanceVariable(Class cls, const char *name)
{
    if (!cls || !name)
        return NULL;
    LOCK();
    struct fivar *v = find_ivar(cls, name);
    UNLOCK();
    return v;
}

struct fivar *class_getClassVariable(Class cls, const char *name)
{
    return cls ? class_getInstanceVariable(object_getClass((id)cls), name) : NULL;
}

struct fivar **class_copyIvarList(Class cls, unsigned *out)
{
    unsigned n = cls ? class_rt(cls)->nivars : 0;
    struct fivar **list = NULL;
    if (n) {
        list = calloc(n + 1, sizeof *list);
        for (unsigned i = 0; i < n; i++)
            list[i] = &class_rt(cls)->ivars[i];
    }
    if (out)
        *out = n;
    return list;
}

BOOL class_addIvar(Class cls, const char *name, size_t size, uint8_t align_log2, const char *types)
{
    if (!cls || !name)
        return NO;
    struct fclass_rt *rt = class_rt(cls);
    if (!(rt->flags & RT_CONSTRUCTING) || (rt->flags & RT_META) || find_ivar(cls, name))
        return NO;
    LOCK();
    uint32_t align = 1u << align_log2;
    uint32_t offset = (rt->instance_size + align - 1) & ~(align - 1);
    rt->ivars = realloc(rt->ivars, (rt->nivars + 1) * sizeof *rt->ivars);
    struct fivar *v = &rt->ivars[rt->nivars++];
    memset(v, 0, sizeof *v);
    for (uint32_t i = 0; i < rt->nivars; i++)       /* realloc moved them */
        rt->ivars[i].offset = &rt->ivars[i].own_offset;
    v->own_offset = offset;
    v->name = strdup(name);
    v->type = types ? strdup(types) : "";
    v->align_log2 = align_log2;
    v->size = size;
    rt->instance_size = offset + size;
    UNLOCK();
    return YES;
}

struct fprop *class_getProperty(Class cls, const char *name)
{
    if (!name)
        return NULL;
    LOCK();
    for (; cls; cls = cls->superclass)
        for (struct fplist *l = class_rt(cls)->props; l; l = l->next)
            for (uint32_t i = 0; i < l->count; i++)
                if (!strcmp(l->p[i].name, name)) {
                    UNLOCK();
                    return &l->p[i];
                }
    UNLOCK();
    return NULL;
}

struct fprop **class_copyPropertyList(Class cls, unsigned *out)
{
    unsigned n = 0;
    struct fprop **list = NULL;
    LOCK();
    if (cls) {
        for (struct fplist *l = class_rt(cls)->props; l; l = l->next)
            n += l->count;
        if (n) {
            list = calloc(n + 1, sizeof *list);
            n = 0;
            for (struct fplist *l = class_rt(cls)->props; l; l = l->next)
                for (uint32_t i = 0; i < l->count; i++)
                    list[n++] = &l->p[i];
        }
    }
    UNLOCK();
    if (out)
        *out = n;
    return list;
}

typedef struct { const char *name, *value; } objc_property_attribute_t;

BOOL class_addProperty(Class cls, const char *name, const objc_property_attribute_t *attrs, unsigned n)
{
    if (!cls || !name || class_getProperty(cls, name))
        return NO;
    size_t len = 1;
    for (unsigned i = 0; i < n; i++)
        len += strlen(attrs[i].name) + strlen(attrs[i].value ? attrs[i].value : "") + 1;
    char *s = calloc(1, len);
    for (unsigned i = 0; i < n; i++) {
        if (i)
            strcat(s, ",");
        strcat(s, attrs[i].name);
        strcat(s, attrs[i].value ? attrs[i].value : "");
    }
    struct fplist *l = calloc(1, sizeof *l + sizeof(struct fprop));
    l->count = 1;
    l->p[0].name = strdup(name);
    l->p[0].attributes = s;
    LOCK();
    prepend_props(class_rt(cls), l);
    UNLOCK();
    return YES;
}

/* ---- classes made at run time --------------------------------------------- */

Class objc_allocateClassPair(Class superclass, const char *name, size_t extra)
{
    if (!name || objc_getClass(name))
        return NULL;
    /* A subclass of a Swift class (KVO's, for one) carries a copy of its
     * superclass's Swift metadata, its table of methods above all, since
     * Swift calls them through the object's class (freemac 1.262). The
     * metadata's own words say how big it is and where the class starts
     * in it; with no description, Swift's runtime knows the copy as a
     * class made at run time and looks past it to the real one. */
    Class cls = NULL;
    int swift = superclass && (superclass->bits & 2);
    if (swift) {
        const uint8_t *sp = (const uint8_t *)superclass;
        uint32_t size = *(const uint32_t *)(sp + 0x38), point = *(const uint32_t *)(sp + 0x3c);
        if (size >= point + 0x50 && size < (1u << 20) && point <= 0x100) {
            uint8_t *mem = calloc(1, size + extra);
            memcpy(mem, sp - point, size);
            cls = (Class)(mem + point);
            *(void **)((uint8_t *)cls + 0x40) = NULL;     /* the description */
        } else {
            swift = 0;
        }
    }
    if (!cls)
        cls = calloc(1, sizeof *cls + extra);
    Class meta = calloc(1, sizeof *meta + extra);
    ferry_objc_make_class(cls, meta, superclass, strdup(name),
                          superclass ? class_rt(superclass)->instance_size : sizeof(Class),
                          NULL, 0, NULL, 0, RT_CONSTRUCTING);
    if (swift)
        cls->bits = 2;
    return cls;
}

/* objc_allocateClassPair in memory the caller gives (the class and its
 * metaclass), as Sparkle's runtime helpers do (freemac 1.264) */
Class objc_initializeClassPair(Class superclass, const char *name, Class cls, Class meta)
{
    if (!name || !cls || !meta || objc_getClass(name))
        return NULL;
    memset(cls, 0, sizeof *cls);
    memset(meta, 0, sizeof *meta);
    ferry_objc_make_class(cls, meta, superclass, strdup(name),
                          superclass ? class_rt(superclass)->instance_size : sizeof(Class),
                          NULL, 0, NULL, 0, RT_CONSTRUCTING);
    return cls;
}

void objc_registerClassPair(Class cls)
{
    if (!cls)
        return;
    LOCK();
    struct fclass_rt *rt = class_rt(cls);
    if (rt->flags & RT_CONSTRUCTING) {
        rt->flags &= ~RT_CONSTRUCTING;
        add_to_class_table(cls);
    }
    UNLOCK();
}

void objc_disposeClassPair(Class cls)
{
    /* The class's memory is kept: a stale pointer must not crash. */
    if (!cls)
        return;
    LOCK();
    struct fclass_rt *rt = class_rt(cls);
    if (ferry_table_get(&classes, rt->name) == cls)
        ferry_table_put(&classes, rt->name, NULL);
    rt->flags |= RT_CONSTRUCTING;
    UNLOCK();
}

Class objc_duplicateClass(Class original, const char *name, size_t extra)
{
    (void)original; (void)name; (void)extra;
    return NULL;
}

/* ---- methods ----------------------------------------------------------------- */

SEL method_getName(struct fmethod *m) { return m ? m->name : NULL; }
IMP method_getImplementation(struct fmethod *m) { return m ? m->imp : NULL; }
const char *method_getTypeEncoding(struct fmethod *m) { return m ? m->types : NULL; }

IMP method_setImplementation(struct fmethod *m, IMP imp)
{
    if (!m)
        return NULL;
    LOCK();
    IMP old = m->imp;
    m->imp = imp;
    UNLOCK();
    ferry_objc_flush_caches();
    return old;
}

void method_exchangeImplementations(struct fmethod *a, struct fmethod *b)
{
    if (!a || !b)
        return;
    LOCK();
    IMP t = a->imp;
    a->imp = b->imp;
    b->imp = t;
    UNLOCK();
    ferry_objc_flush_caches();
}

/* Skips one type in an Objective-C type encoding, and the frame offset
 * digits after it. */
static const char *skip_type(const char *t)
{
    while (*t && strchr("rnNoORV+-", *t))   /* qualifiers */
        t++;
    switch (*t) {
    case 0:
        return t;
    case '{': case '(': case '[': {
        char open = *t, close = open == '{' ? '}' : open == '(' ? ')' : ']';
        int depth = 0;
        do {
            if (*t == open)
                depth++;
            else if (*t == close)
                depth--;
            else if (*t == '"') {
                t++;
                while (*t && *t != '"')
                    t++;
            }
            t++;
        } while (*t && depth);
        break;
    }
    case '^':
        t = skip_type(t + 1);
        return t;
    case '@':
        t++;
        if (*t == '?')
            t++;
        else if (*t == '"') {
            t++;
            while (*t && *t != '"')
                t++;
            if (*t)
                t++;
        }
        break;
    case 'b':
        t++;
        while (*t >= '0' && *t <= '9')
            t++;
        return t;
    default:
        t++;
    }
    while (*t >= '0' && *t <= '9')
        t++;
    return t;
}

static const char *nth_type(const char *types, unsigned n)
{
    const char *t = types;
    for (unsigned i = 0; i < n && *t; i++)
        t = skip_type(t);
    return t;
}

static char *copy_type(const char *t)
{
    if (!t || !*t)
        return NULL;
    const char *end = skip_type(t);
    while (end > t && end[-1] >= '0' && end[-1] <= '9')
        end--;
    return strndup(t, end - t);
}

unsigned method_getNumberOfArguments(struct fmethod *m)
{
    if (!m || !m->types)
        return 0;
    unsigned n = 0;
    const char *t = skip_type(m->types);    /* the return type */
    while (*t) {
        t = skip_type(t);
        n++;
    }
    return n;
}

char *method_copyReturnType(struct fmethod *m) { return m ? copy_type(m->types) : NULL; }

char *method_copyArgumentType(struct fmethod *m, unsigned index)
{
    if (!m || index >= method_getNumberOfArguments(m))
        return NULL;
    return copy_type(nth_type(m->types, index + 1));
}

static void copy_into(char *dst, size_t len, char *src)
{
    if (!len)
        return;
    snprintf(dst, len, "%s", src ? src : "");
    if (!src)
        dst[0] = 0;
    free(src);
}

void method_getReturnType(struct fmethod *m, char *dst, size_t len) { copy_into(dst, len, method_copyReturnType(m)); }
void method_getArgumentType(struct fmethod *m, unsigned i, char *dst, size_t len)
{
    copy_into(dst, len, method_copyArgumentType(m, i));
}

struct objc_method_description { SEL name; char *types; };
struct objc_method_description *method_getDescription(struct fmethod *m)
{
    return (struct objc_method_description *)m;
}

/* ---- ivars, properties -------------------------------------------------------- */

const char *ivar_getName(struct fivar *v) { return v ? v->name : NULL; }
const char *ivar_getTypeEncoding(struct fivar *v) { return v ? v->type : NULL; }
ptrdiff_t ivar_getOffset(struct fivar *v) { return v ? (ptrdiff_t)*v->offset : 0; }

const char *property_getName(struct fprop *p) { return p ? p->name : NULL; }
const char *property_getAttributes(struct fprop *p) { return p ? p->attributes : NULL; }

/* Attributes look like "T@\"NSString\",C,N,V_name": one letter, then a value
 * up to the next comma (a quoted value may contain commas). */
static const char *next_attribute(const char *s, char *code, const char **value, size_t *vlen)
{
    if (!s || !*s)
        return NULL;
    *code = *s++;
    *value = s;
    int quoted = 0;
    while (*s && (quoted || *s != ',')) {
        if (*s == '"')
            quoted = !quoted;
        s++;
    }
    *vlen = s - *value;
    return *s ? s + 1 : s;
}

char *property_copyAttributeValue(struct fprop *p, const char *name)
{
    if (!p || !name)
        return NULL;
    const char *s = p->attributes, *value;
    char code;
    size_t vlen;
    while ((s = next_attribute(s, &code, &value, &vlen)))
        if (code == name[0] && !name[1])
            return strndup(value, vlen);
    return NULL;
}

objc_property_attribute_t *property_copyAttributeList(struct fprop *p, unsigned *out)
{
    unsigned n = 0;
    const char *s, *value;
    char code;
    size_t vlen;
    for (s = p ? p->attributes : NULL; (s = next_attribute(s, &code, &value, &vlen));)
        n++;
    objc_property_attribute_t *list = n ? calloc(n + 1, sizeof *list) : NULL;
    unsigned i = 0;
    for (s = p ? p->attributes : NULL; (s = next_attribute(s, &code, &value, &vlen)); i++) {
        char *nm = malloc(2);
        nm[0] = code;
        nm[1] = 0;
        list[i].name = nm;
        list[i].value = strndup(value, vlen);
    }
    if (out)
        *out = n;
    return list;
}

/* ---- protocols ------------------------------------------------------------------ */

typedef struct c_protocol Protocol;

Protocol *objc_getProtocol(const char *name)
{
    LOCK();
    Protocol *p = name ? ferry_table_get(&protocols, name) : NULL;
    UNLOCK();
    return p;
}

Protocol **objc_copyProtocolList(unsigned *out)
{
    LOCK();
    Protocol **list = calloc(protocols.used + 1, sizeof *list);
    unsigned n = 0;
    for (size_t i = 0; i < protocols.cap; i++)
        if (protocols.e[i].key && protocols.e[i].value)
            list[n++] = protocols.e[i].value;
    UNLOCK();
    if (out)
        *out = n;
    return list;
}

const char *protocol_getName(Protocol *p) { return p ? p->name : NULL; }

BOOL protocol_isEqual(Protocol *a, Protocol *b)
{
    return a == b || (a && b && !strcmp(a->name, b->name));
}

BOOL protocol_conformsToProtocol(Protocol *p, Protocol *other)
{
    if (!p || !other)
        return NO;
    if (protocol_isEqual(p, other))
        return YES;
    if (p->protocols)
        for (uint64_t i = 0; i < p->protocols->count; i++)
            if (protocol_conformsToProtocol(p->protocols->list[i], other))
                return YES;
    return NO;
}

BOOL class_conformsToProtocol(Class cls, Protocol *p)
{
    if (!cls || !p)
        return NO;
    LOCK();
    struct fclass_rt *rt = class_rt(cls);
    BOOL found = NO;
    for (uint32_t i = 0; i < rt->nprotos && !found; i++)
        found = protocol_conformsToProtocol(rt->protos[i], p);
    UNLOCK();
    return found;
}

Protocol **class_copyProtocolList(Class cls, unsigned *out)
{
    LOCK();
    unsigned n = cls ? class_rt(cls)->nprotos : 0;
    Protocol **list = NULL;
    if (n) {
        list = calloc(n + 1, sizeof *list);
        memcpy(list, class_rt(cls)->protos, n * sizeof *list);
    }
    UNLOCK();
    if (out)
        *out = n;
    return list;
}

BOOL class_addProtocol(Class cls, Protocol *p)
{
    if (!cls || !p || class_conformsToProtocol(cls, p))
        return NO;
    LOCK();
    add_protocol(class_rt(cls), p);
    UNLOCK();
    return YES;
}

Protocol **protocol_copyProtocolList(Protocol *p, unsigned *out)
{
    unsigned n = p && p->protocols ? p->protocols->count : 0;
    Protocol **list = NULL;
    if (n) {
        list = calloc(n + 1, sizeof *list);
        for (unsigned i = 0; i < n; i++)
            list[i] = canonical_protocol(p->protocols->list[i]);
    }
    if (out)
        *out = n;
    return list;
}

static const struct c_method_list *protocol_methods(Protocol *p, BOOL required, BOOL instance)
{
    if (required)
        return instance ? p->instance_methods : p->class_methods;
    return instance ? p->opt_instance_methods : p->opt_class_methods;
}

struct objc_method_description *protocol_copyMethodDescriptionList(Protocol *p, BOOL required, BOOL instance,
                                                                   unsigned *out)
{
    unsigned n = 0;
    struct objc_method_description *list = NULL;
    const struct c_method_list *ml = p ? protocol_methods(p, required, instance) : NULL;
    struct fmlist *l = convert_methods(ml);
    if (l) {
        n = l->count;
        list = calloc(n + 1, sizeof *list);
        for (unsigned i = 0; i < n; i++) {
            list[i].name = l->m[i].name;
            list[i].types = (char *)l->m[i].types;
        }
        free(l);
    }
    if (out)
        *out = n;
    return list;
}

struct objc_method_description protocol_getMethodDescription(Protocol *p, SEL sel, BOOL required, BOOL instance)
{
    struct objc_method_description d = {NULL, NULL};
    unsigned n;
    struct objc_method_description *list = protocol_copyMethodDescriptionList(p, required, instance, &n);
    for (unsigned i = 0; i < n; i++)
        if (list[i].name == sel)
            d = list[i];
    free(list);
    if (!d.name && p && p->protocols)
        for (uint64_t i = 0; i < p->protocols->count && !d.name; i++)
            d = protocol_getMethodDescription(p->protocols->list[i], sel, required, instance);
    return d;
}

/* A method's extended type encoding, which names its object arguments'
 * classes (@"JSValue"), as the compiler keeps it in the protocol: one entry
 * for each method of the four lists, in their order. JavaScriptCore's
 * Objective-C API reads it, as on a Mac (freemac 1.222, Ferry 0.46.0). */
const char *_protocol_getMethodTypeEncoding(Protocol *p, SEL sel, BOOL required, BOOL instance)
{
    if (!p || !sel)
        return NULL;
    const struct c_method_list *lists[4] = {p->instance_methods, p->class_methods, p->opt_instance_methods,
                                            p->opt_class_methods};
    int want = required ? (instance ? 0 : 1) : (instance ? 2 : 3);
    BOOL extended = p->size >= offsetof(struct c_protocol, extended_types) + sizeof(void *) && p->extended_types;
    unsigned before = 0;
    for (int k = 0; k < 4; k++) {
        struct fmlist *l = convert_methods(lists[k]);
        unsigned n = l ? l->count : 0;
        if (k == want)
            for (unsigned i = 0; i < n; i++)
                if (l->m[i].name == sel) {
                    const char *types = extended ? p->extended_types[before + i] : l->m[i].types;
                    free(l);
                    return types;
                }
        free(l);
        before += n;
    }
    if (p->protocols)
        for (uint64_t i = 0; i < p->protocols->count; i++) {
            const char *t = _protocol_getMethodTypeEncoding(p->protocols->list[i], sel, required, instance);
            if (t)
                return t;
        }
    return NULL;
}

struct fprop **protocol_copyPropertyList(Protocol *p, unsigned *out)
{
    struct fplist *l = p ? convert_props(p->properties) : NULL;
    unsigned n = l ? l->count : 0;
    struct fprop **list = NULL;
    if (n) {
        list = calloc(n + 1, sizeof *list);
        for (unsigned i = 0; i < n; i++)
            list[i] = &l->p[i];   /* the list itself stays allocated */
    }
    if (out)
        *out = n;
    return list;
}

Protocol *objc_allocateProtocol(const char *name)
{
    if (!name || objc_getProtocol(name))
        return NULL;
    Protocol *p = calloc(1, sizeof *p);
    p->name = strdup(name);
    p->size = sizeof *p;
    return p;
}

void objc_registerProtocol(Protocol *p)
{
    if (!p)
        return;
    LOCK();
    register_protocol(p);
    UNLOCK();
}

void protocol_addProtocol(Protocol *p, Protocol *add)
{
    if (!p || !add || objc_getProtocol(p->name) == p)
        return;
    uint64_t n = p->protocols ? p->protocols->count : 0;
    struct c_protocol_list *l = malloc(sizeof *l + (n + 1) * sizeof(Protocol *));
    l->count = n + 1;
    if (n)
        memcpy(l->list, p->protocols->list, n * sizeof(Protocol *));
    l->list[n] = add;
    p->protocols = l;
}

void protocol_addMethodDescription(Protocol *p, SEL sel, const char *types, BOOL required, BOOL instance)
{
    if (!p || !sel || objc_getProtocol(p->name) == p)
        return;
    struct c_method_list **slot = required ? (instance ? &p->instance_methods : &p->class_methods)
                                           : (instance ? &p->opt_instance_methods : &p->opt_class_methods);
    uint32_t n = *slot ? (*slot)->count : 0;
    struct c_method_list *l = malloc(sizeof *l + (n + 1) * sizeof(struct c_method));
    l->entsize_flags = sizeof(struct c_method);
    l->count = n + 1;
    if (n)
        memcpy(l + 1, *slot + 1, n * sizeof(struct c_method));
    struct c_method *m = (struct c_method *)(l + 1) + n;
    m->name = sel_registerName(sel);
    m->types = types ? strdup(types) : "";
    m->imp = NULL;
    *slot = l;
}

/* ---- objects ------------------------------------------------------------------ */

Class object_getClass(id obj) { return obj ? obj->isa : NULL; }

Class object_setClass(id obj, Class cls)
{
    if (!obj)
        return NULL;
    Class old = obj->isa;
    obj->isa = cls;
    return old;
}

const char *object_getClassName(id obj) { return class_getName(object_getClass(obj)); }
BOOL object_isClass(id obj) { return obj && class_isMetaClass(obj->isa); }

id object_getIvar(id obj, struct fivar *v)
{
    return obj && v ? *(id *)((char *)obj + *v->offset) : nil;
}

void object_setIvar(id obj, struct fivar *v, id value)
{
    if (obj && v)
        *(id *)((char *)obj + *v->offset) = value;
}

/* The older by-name calls, for code built without ARC (freemac 1.226,
 * Ferry 0.50.0; Sequel Pro's combo box cell): the variable's value is
 * copied out as raw bytes of the pointer's size, and set without retaining. */
struct fivar *object_getInstanceVariable(id obj, const char *name, void **out)
{
    struct fivar *v = obj && name ? class_getInstanceVariable(object_getClass(obj), name) : NULL;
    if (out)
        *out = v ? *(void **)((char *)obj + *v->offset) : NULL;
    return v;
}

struct fivar *object_setInstanceVariable(id obj, const char *name, void *value)
{
    struct fivar *v = obj && name ? class_getInstanceVariable(object_getClass(obj), name) : NULL;
    if (v)
        *(void **)((char *)obj + *v->offset) = value;
    return v;
}

void object_setIvarWithStrongDefault(id obj, struct fivar *v, id value)
{
    if (!obj || !v)
        return;
    id *slot = (id *)((char *)obj + *v->offset);
    id old = *slot;
    *slot = objc_retain(value);
    objc_release(old);
}

/* ---- run-time setup ----------------------------------------------------------- */

void ferry_objc_runtime_init(void)
{
#define S(var, name) var = sel_registerName(name)
    S(SEL_alloc, "alloc");
    S(SEL_allocWithZone, "allocWithZone:");
    S(SEL_init, "init");
    S(SEL_new, "new");
    S(SEL_dealloc, "dealloc");
    S(SEL_retain, "retain");
    S(SEL_release, "release");
    S(SEL_autorelease, "autorelease");
    S(SEL_retainCount, "retainCount");
    S(SEL_initialize, "initialize");
    S(SEL_load, "load");
    S(SEL_copy, "copy");
    S(SEL_copyWithZone, "copyWithZone:");
    S(SEL_mutableCopyWithZone, "mutableCopyWithZone:");
    S(SEL_resolveInstanceMethod, "resolveInstanceMethod:");
    S(SEL_resolveClassMethod, "resolveClassMethod:");
    S(SEL_forwardingTargetForSelector, "forwardingTargetForSelector:");
    S(SEL_doesNotRecognizeSelector, "doesNotRecognizeSelector:");
    S(SEL_cxx_construct, ".cxx_construct");
    S(SEL_cxx_destruct, ".cxx_destruct");
    S(SEL_isKindOfClass, "isKindOfClass:");
    S(SEL_respondsToSelector, "respondsToSelector:");
    S(SEL_class, "class");
    S(SEL_forwardInvocation, "forwardInvocation:");
#undef S
}

__attribute__((constructor)) static void objc_setup(void)
{
    ferry_objc_runtime_init();
    ferry_objc_nsobject_init();
    ferry_blocks_init();
    ferry_dispatch_init();
    ferry_oslog_init();
}
