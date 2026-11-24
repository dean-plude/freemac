/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Objective-C runtime: the root class NSObject, reference counting,
 * the ARC entry points (as listed in clang's ARC specification), autorelease
 * pools, weak references, associated objects, @synchronized, property
 * accessors and the Protocol class. Behaviour follows Apple's public
 * documentation of each call.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "objc-private.h"


/* ---- allocation ------------------------------------------------------------ */

typedef id (*ctor_fn)(id, SEL);
typedef void (*dtor_fn)(id, SEL);

static id construct(Class cls, id obj)
{
    if (!cls)
        return obj;
    if (!construct(cls->superclass, obj))
        return nil;
    if (class_rt(cls)->flags & RT_HAS_CXX) {
        struct fmethod *m = ferry_objc_find_own_method(cls, SEL_cxx_construct);
        if (m && !FN(ctor_fn, m->imp)(obj, SEL_cxx_construct))
            return nil;
    }
    return obj;
}

id ferry_objc_alloc_sized(Class cls, size_t size)
{
    struct fobj_header *h = calloc(1, sizeof *h + (size < sizeof(Class) ? sizeof(Class) : size));
    if (!h) {
        fputs("ferry: out of memory\n", stderr);
        abort();
    }
    id obj = (id)(h + 1);
    obj->isa = cls;
    return obj;
}

id class_createInstance(Class cls, size_t extra)
{
    if (!cls)
        return nil;
    id obj = ferry_objc_alloc_sized(cls, class_rt(cls)->instance_size + extra);
    if (class_rt(cls)->flags & RT_HAS_CXX || cls->superclass)
        if (!construct(cls, obj)) {
            free(OBJ_HEADER(obj));
            return nil;
        }
    return obj;
}

id objc_constructInstance(Class cls, void *bytes)
{
    if (!cls || !bytes)
        return nil;
    id obj = bytes;
    obj->isa = cls;
    return construct(cls, obj);
}

void *objc_destructInstance(id obj)
{
    if (!obj)
        return NULL;
    for (Class c = obj->isa; c; c = c->superclass) {
        if (!(class_rt(c)->flags & RT_HAS_CXX))
            continue;
        struct fmethod *m = ferry_objc_find_own_method(c, SEL_cxx_destruct);
        if (m)
            FN(dtor_fn, m->imp)(obj, SEL_cxx_destruct);
    }
    /* Only objects with NSObject's own retain/release are known to have a
     * header, so the side tables are always checked. */
    ferry_objc_assoc_clear(obj);
    ferry_objc_weak_clear(obj);
    return obj;
}

id object_dispose(id obj)
{
    if (!obj)
        return nil;
    objc_destructInstance(obj);
    free(OBJ_HEADER(obj));
    return nil;
}

static int has_header(id obj)
{
    return !(class_rt(obj->isa)->flags & RT_STATIC_INSTANCES);
}

/* ---- retain and release ----------------------------------------------------- */

/* extra_rc counts the references beyond the first. When the last one goes,
 * the count is marked (its top bit) in the same atomic step, before dealloc
 * is sent, so that a weak reference being read on another thread at that
 * moment can tell the object is going and doesn't take it back. */
#define RC_GONE ((uintptr_t)1 << 63)

static id rr_retain(id obj)
{
    __atomic_fetch_add(&OBJ_HEADER(obj)->extra_rc, 1, __ATOMIC_RELAXED);
    return obj;
}

/* a retain that fails once the last release has begun (for weak references) */
static int rr_try_retain(id obj)
{
    struct fobj_header *h = OBJ_HEADER(obj);
    uintptr_t rc = __atomic_load_n(&h->extra_rc, __ATOMIC_RELAXED);
    do {
        if (rc & RC_GONE)
            return 0;
    } while (!__atomic_compare_exchange_n(&h->extra_rc, &rc, rc + 1, 1, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED));
    return 1;
}

static void rr_release(id obj)
{
    struct fobj_header *h = OBJ_HEADER(obj);
    uintptr_t rc = __atomic_load_n(&h->extra_rc, __ATOMIC_RELAXED);
    for (;;) {
        if (rc == 0) {
            if (!__atomic_compare_exchange_n(&h->extra_rc, &rc, RC_GONE, 1, __ATOMIC_ACQ_REL, __ATOMIC_RELAXED))
                continue;
            uint32_t old = __atomic_fetch_or(&h->flags, OBJ_DEALLOCATING, __ATOMIC_ACQ_REL);
            if (!(old & OBJ_DEALLOCATING))
                SEND0(void, obj, SEL_dealloc);
            return;
        }
        /* retains and releases while dealloc runs balance out; the last one does nothing more */
        if (rc == RC_GONE)
            return;
        if (__atomic_compare_exchange_n(&h->extra_rc, &rc, rc - 1, 1, __ATOMIC_RELEASE, __ATOMIC_RELAXED))
            return;
    }
}

static uintptr_t rr_count(id obj)
{
    return (__atomic_load_n(&OBJ_HEADER(obj)->extra_rc, __ATOMIC_RELAXED) & ~RC_GONE) + 1;
}

/* Autorelease pools: one stack of objects per thread; NULL marks where each
 * pool begins (nil is never autoreleased). The token a push returns is the
 * marker's index plus one. What is left on a thread's stack when the thread
 * ends is released then, as a Mac does. */
static __thread id *pool;
static __thread size_t pool_len, pool_cap;
static pthread_key_t pool_key;
static pthread_once_t pool_key_once = PTHREAD_ONCE_INIT;

static void pool_drain_at_exit(void *unused)
{
    (void)unused;
    while (pool_len) {
        id obj = pool[--pool_len];
        if (obj)
            objc_release(obj);
    }
    free(pool);
    pool = NULL;
    pool_cap = 0;
}

static void pool_key_make(void) { pthread_key_create(&pool_key, pool_drain_at_exit); }

static void pool_add(id obj)
{
    if (pool_len == pool_cap) {
        if (!pool) {
            pthread_once(&pool_key_once, pool_key_make);
            pthread_setspecific(pool_key, (void *)1);
        }
        pool_cap = pool_cap ? pool_cap * 2 : 256;
        pool = realloc(pool, pool_cap * sizeof *pool);
    }
    pool[pool_len++] = obj;
}

void *objc_autoreleasePoolPush(void)
{
    pool_add(nil);
    return (void *)(uintptr_t)pool_len;
}

void objc_autoreleasePoolPop(void *token)
{
    size_t mark = (uintptr_t)token;
    if (!mark || mark > pool_len)
        return;
    while (pool_len > mark) {
        id obj = pool[--pool_len];
        if (obj)
            objc_release(obj);
    }
    pool_len = mark - 1;
}

void _objc_autoreleasePoolPrint(void)
{
    fprintf(stderr, "objc[%d]: %zu entries in autorelease pools\n", getpid(), pool_len);
}

id objc_retain(id obj)
{
    if (!obj)
        return nil;
    if (ferry_objc_has_default_rr(obj->isa))
        return rr_retain(obj);
    return SEND0(id, obj, SEL_retain);
}

void objc_release(id obj)
{
    if (!obj)
        return;
    if (ferry_objc_has_default_rr(obj->isa))
        rr_release(obj);
    else
        SEND0(void, obj, SEL_release);
}

id objc_autorelease(id obj)
{
    if (!obj)
        return nil;
    if (ferry_objc_has_default_rr(obj->isa)) {
        pool_add(obj);
        return obj;
    }
    return SEND0(id, obj, SEL_autorelease);
}

/* ARC's return-value handshake. A method returning an object at +0 ends
 * with objc_autoreleaseReturnValue(); its ARC caller immediately takes the
 * object back with objc_retainAutoreleasedReturnValue(). When the code at
 * the return address is exactly that call (clang emits "mov %rax,%rdi" and
 * a call, usually through a stub that jumps through a pointer), the object
 * is handed over directly instead of going through the autorelease pool,
 * so it is freed as soon as the caller lets go of it, as on a Mac. Anything
 * else falls back to a real autorelease, which is always correct. */

id objc_retainAutoreleasedReturnValue(id obj);
id objc_claimAutoreleasedReturnValue(id obj);
id objc_unsafeClaimAutoreleasedReturnValue(id obj);

static __thread id handoff;

static void *call_target(const uint8_t *p)
{
    if (p[0] == 0xe8) {                          /* call rel32 */
        const uint8_t *t = p + 5 + *(const int32_t *)(p + 1);
        if (t[0] == 0xff && t[1] == 0x25)        /* stub: jmp *disp32(%rip) */
            return *(void *const *)(t + 6 + *(const int32_t *)(t + 2));
        return (void *)t;
    }
    if (p[0] == 0xff && p[1] == 0x15)            /* call *disp32(%rip) */
        return *(void *const *)(p + 6 + *(const int32_t *)(p + 2));
    return NULL;
}

static int caller_takes_back(const uint8_t *ra)
{
    if (!ra || ra[0] != 0x48 || ra[1] != 0x89 || ra[2] != 0xc7)   /* mov %rax,%rdi */
        return 0;
    void *t = call_target(ra + 3);
    return t == (void *)objc_retainAutoreleasedReturnValue || t == (void *)objc_claimAutoreleasedReturnValue
        || t == (void *)objc_unsafeClaimAutoreleasedReturnValue;
}

static id autorelease_return(id obj, const void *ra)
{
    if (obj && caller_takes_back(ra)) {
        handoff = obj;
        return obj;
    }
    return objc_autorelease(obj);
}

__attribute__((noinline)) id objc_autoreleaseReturnValue(id obj)
{
    return autorelease_return(obj, __builtin_return_address(0));
}

__attribute__((noinline)) id objc_retainAutoreleaseReturnValue(id obj)
{
    return autorelease_return(objc_retain(obj), __builtin_return_address(0));
}

id objc_retainAutoreleasedReturnValue(id obj)
{
    if (obj && handoff == obj) {
        handoff = nil;
        return obj;
    }
    handoff = nil;
    return objc_retain(obj);
}

id objc_claimAutoreleasedReturnValue(id obj) { return objc_retainAutoreleasedReturnValue(obj); }

id objc_unsafeClaimAutoreleasedReturnValue(id obj)
{
    if (obj && handoff == obj) {
        handoff = nil;
        objc_release(obj);
    }
    return obj;
}

id objc_retainAutorelease(id obj) { return objc_autorelease(objc_retain(obj)); }
id objc_retainedObject(void *p) { return p; }
id objc_unretainedObject(void *p) { return p; }
void *objc_unretainedPointer(id obj) { return obj; }
id objc_retainBlock(id block) { return _Block_copy(block); }

void objc_storeStrong(id *location, id obj)
{
    id prev = *location;
    if (prev == obj)
        return;
    objc_retain(obj);
    *location = obj;
    objc_release(prev);
}

/* ---- weak references --------------------------------------------------------
 * A table from each weakly referenced object to the variables pointing at
 * it, cleared when the object is deallocated. */

struct weak_entry { id **locs; size_t n, cap; };
static struct ftable weak_table;

static SEL SEL_isDeallocating;

static int is_deallocating(id obj)
{
    if (!has_header(obj))
        return 0;
    if (ferry_objc_has_default_rr(obj->isa))
        return (__atomic_load_n(&OBJ_HEADER(obj)->extra_rc, __ATOMIC_ACQUIRE) & RC_GONE) ||
               (__atomic_load_n(&OBJ_HEADER(obj)->flags, __ATOMIC_ACQUIRE) & OBJ_DEALLOCATING);
    /* a class with its own retain/release (perhaps static objects) */
    return SEND0(BOOL, obj, SEL_isDeallocating);
}

static void weak_unregister(id obj, id *loc)
{
    struct weak_entry *e = ferry_table_get(&weak_table, obj);
    if (!e)
        return;
    for (size_t i = 0; i < e->n; i++)
        if (e->locs[i] == loc) {
            e->locs[i] = e->locs[--e->n];
            return;
        }
}

static void weak_register(id obj, id *loc)
{
    struct weak_entry *e = ferry_table_get(&weak_table, obj);
    if (!e) {
        e = calloc(1, sizeof *e);
        ferry_table_put(&weak_table, obj, e);
    }
    if (e->n == e->cap) {
        e->cap = e->cap ? e->cap * 2 : 4;
        e->locs = realloc(e->locs, e->cap * sizeof *e->locs);
    }
    e->locs[e->n++] = loc;
}

id objc_storeWeak(id *location, id obj)
{
    LOCK();
    id old = *location;
    if (old)
        weak_unregister(old, location);
    if (obj && is_deallocating(obj))
        obj = nil;
    if (obj)
        weak_register(obj, location);
    *location = obj;
    UNLOCK();
    return obj;
}

id objc_initWeak(id *location, id obj)
{
    *location = nil;
    return obj ? objc_storeWeak(location, obj) : nil;
}

id objc_initWeakOrNil(id *location, id obj) { return objc_initWeak(location, obj); }
id objc_storeWeakOrNil(id *location, id obj) { return objc_storeWeak(location, obj); }

void objc_destroyWeak(id *location)
{
    if (*location)
        objc_storeWeak(location, nil);
}

id objc_loadWeakRetained(id *location)
{
    LOCK();
    id obj = *location;
    if (obj && has_header(obj) && ferry_objc_has_default_rr(obj->isa)) {
        if (!rr_try_retain(obj))
            obj = nil;
    } else {
        if (obj && is_deallocating(obj))
            obj = nil;
        obj = objc_retain(obj);
    }
    UNLOCK();
    return obj;
}

id objc_loadWeak(id *location)
{
    return objc_autorelease(objc_loadWeakRetained(location));
}

void objc_copyWeak(id *to, id *from)
{
    id obj = objc_loadWeakRetained(from);
    objc_initWeak(to, obj);
    objc_release(obj);
}

void objc_moveWeak(id *to, id *from)
{
    objc_copyWeak(to, from);
    objc_destroyWeak(from);
}

void ferry_objc_weak_clear(id obj)
{
    LOCK();
    struct weak_entry *e = ferry_table_get(&weak_table, obj);
    if (e) {
        for (size_t i = 0; i < e->n; i++)
            if (*e->locs[i] == obj)
                *e->locs[i] = nil;
        free(e->locs);
        free(e);
        ferry_table_put(&weak_table, obj, NULL);
    }
    UNLOCK();
}

/* ---- associated objects ------------------------------------------------------ */

#define ASSOC_RETAIN 1
#define ASSOC_COPY 3
#define ASSOC_ATOMIC 0x300

struct assoc { const void *key; id value; uintptr_t policy; };
struct assoc_entry { struct assoc *a; size_t n; };
static struct ftable assoc_table;

static id assoc_hold(id value, uintptr_t policy)
{
    if ((policy & 3) == ASSOC_COPY)
        return value ? SEND1(id, value, SEL_copyWithZone, (void *)NULL) : nil;
    if ((policy & 3) == ASSOC_RETAIN)
        return objc_retain(value);
    return value;
}

static void assoc_drop(struct assoc *a)
{
    if (a->policy & 1)
        objc_release(a->value);
}

void objc_setAssociatedObject(id obj, const void *key, id value, uintptr_t policy)
{
    if (!obj)
        return;
    value = assoc_hold(value, policy);
    struct assoc old = {0};
    LOCK();
    struct assoc_entry *e = ferry_table_get(&assoc_table, obj);
    if (!e && value) {
        e = calloc(1, sizeof *e);
        ferry_table_put(&assoc_table, obj, e);
    }
    if (e) {
        size_t i;
        for (i = 0; i < e->n && e->a[i].key != key; i++)
            ;
        if (i < e->n) {
            old = e->a[i];
            if (value) {
                e->a[i].value = value;
                e->a[i].policy = policy;
            } else {
                e->a[i] = e->a[--e->n];
            }
        } else if (value) {
            e->a = realloc(e->a, (e->n + 1) * sizeof *e->a);
            e->a[e->n++] = (struct assoc){key, value, policy};
        }
    }
    UNLOCK();
    if (old.key)
        assoc_drop(&old);
}

id objc_getAssociatedObject(id obj, const void *key)
{
    id value = nil;
    uintptr_t policy = 0;
    LOCK();
    struct assoc_entry *e = obj ? ferry_table_get(&assoc_table, obj) : NULL;
    for (size_t i = 0; e && i < e->n; i++)
        if (e->a[i].key == key) {
            value = e->a[i].value;
            policy = e->a[i].policy;
            if (policy & ASSOC_ATOMIC)
                objc_retain(value);
        }
    UNLOCK();
    return (policy & ASSOC_ATOMIC) ? objc_autorelease(value) : value;
}

void ferry_objc_assoc_clear(id obj)
{
    LOCK();
    struct assoc_entry *e = ferry_table_get(&assoc_table, obj);
    if (e)
        ferry_table_put(&assoc_table, obj, NULL);
    UNLOCK();
    if (!e)
        return;
    for (size_t i = 0; i < e->n; i++)
        assoc_drop(&e->a[i]);
    free(e->a);
    free(e);
}

void objc_removeAssociatedObjects(id obj)
{
    if (obj)
        ferry_objc_assoc_clear(obj);
}

/* ---- @synchronized ---------------------------------------------------------- */

static struct ftable sync_table;

static pthread_mutex_t *sync_mutex(id obj)
{
    LOCK();
    pthread_mutex_t *m = ferry_table_get(&sync_table, obj);
    if (!m) {
        m = malloc(sizeof *m);
        pthread_mutexattr_t a;
        pthread_mutexattr_init(&a);
        pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(m, &a);
        pthread_mutexattr_destroy(&a);
        ferry_table_put(&sync_table, obj, m);
    }
    UNLOCK();
    return m;
}

int objc_sync_enter(id obj)
{
    if (obj)
        pthread_mutex_lock(sync_mutex(obj));
    return 0;
}

int objc_sync_exit(id obj)
{
    if (!obj)
        return 0;
    return pthread_mutex_unlock(sync_mutex(obj)) ? -1 : 0;   /* -1: not owning thread */
}

/* ---- property accessors ------------------------------------------------------- */

static pthread_mutex_t prop_locks[64];

__attribute__((constructor)) static void prop_locks_init(void)
{
    for (int i = 0; i < 64; i++)
        pthread_mutex_init(&prop_locks[i], NULL);
}

static pthread_mutex_t *prop_lock(const void *p)
{
    return &prop_locks[((uintptr_t)p >> 4) & 63];
}

id objc_getProperty(id self, SEL _cmd, ptrdiff_t offset, BOOL atomic)
{
    (void)_cmd;
    if (!self)
        return nil;
    id *slot = (id *)((char *)self + offset);
    if (!atomic)
        return *slot;
    pthread_mutex_t *l = prop_lock(slot);
    pthread_mutex_lock(l);
    id value = objc_retain(*slot);
    pthread_mutex_unlock(l);
    return objc_autoreleaseReturnValue(value);
}

static void set_property(id self, ptrdiff_t offset, id value, BOOL atomic, int copy)
{
    if (!self)
        return;
    if (copy == 1)
        value = value ? SEND1(id, value, SEL_copyWithZone, (void *)NULL) : nil;
    else if (copy == 2)
        value = value ? SEND1(id, value, SEL_mutableCopyWithZone, (void *)NULL) : nil;
    else
        value = objc_retain(value);
    id *slot = (id *)((char *)self + offset);
    id old;
    if (atomic) {
        pthread_mutex_t *l = prop_lock(slot);
        pthread_mutex_lock(l);
        old = *slot;
        *slot = value;
        pthread_mutex_unlock(l);
    } else {
        old = *slot;
        *slot = value;
    }
    objc_release(old);
}

void objc_setProperty(id self, SEL _cmd, ptrdiff_t offset, id value, BOOL atomic, signed char copy)
{
    (void)_cmd;
    set_property(self, offset, value, atomic, copy);
}

void objc_setProperty_atomic(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, YES, 0); }
void objc_setProperty_nonatomic(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, NO, 0); }
void objc_setProperty_atomic_copy(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, YES, 1); }
void objc_setProperty_nonatomic_copy(id self, SEL _cmd, id value, ptrdiff_t offset) { (void)_cmd; set_property(self, offset, value, NO, 1); }

/* The write barriers of the old garbage collector, which apps built for
 * both memory models still call. Without a collector they are plain stores. */
id objc_assign_global(id value, id *dest) { *dest = value; return value; }
id objc_assign_threadlocal(id value, id *dest) { *dest = value; return value; }
id objc_assign_strongCast(id value, id *dest) { *dest = value; return value; }
id objc_assign_ivar(id value, id dest, ptrdiff_t offset) { *(id *)((char *)dest + offset) = value; return value; }
id objc_assign_weak(id value, id *dest) { *dest = value; return value; }
id objc_read_weak(id *location) { return *location; }
void *objc_memmove_collectable(void *dst, const void *src, size_t size) { return memmove(dst, src, size); }
BOOL objc_collectingEnabled(void) { return NO; }

void objc_copyStruct(void *dest, const void *src, ptrdiff_t size, BOOL atomic, BOOL has_strong)
{
    (void)has_strong;
    pthread_mutex_t *a = NULL, *b = NULL;
    if (atomic) {
        a = prop_lock(src);
        b = prop_lock(dest);
        if (a > b) {
            pthread_mutex_t *t = a;
            a = b;
            b = t;
        }
        pthread_mutex_lock(a);
        if (b != a)
            pthread_mutex_lock(b);
    }
    memmove(dest, src, size);
    if (atomic) {
        if (b != a)
            pthread_mutex_unlock(b);
        pthread_mutex_unlock(a);
    }
}

void objc_copyCppObjectAtomic(void *dest, const void *src, void (*copy)(void *, const void *))
{
    pthread_mutex_t *l = prop_lock(src);
    pthread_mutex_lock(l);
    copy(dest, src);
    pthread_mutex_unlock(l);
}

/* ---- allocation shortcuts newer compilers call ------------------------------- */

id objc_alloc(Class cls) { return cls ? SEND0(id, cls, SEL_alloc) : nil; }
id objc_allocWithZone(Class cls) { return cls ? SEND1(id, cls, SEL_allocWithZone, (void *)NULL) : nil; }
id objc_alloc_init(Class cls) { return cls ? SEND0(id, SEND0(id, cls, SEL_alloc), SEL_init) : nil; }
id objc_opt_new(Class cls) { return cls ? SEND0(id, cls, SEL_new) : nil; }
id objc_opt_self(id obj) { return obj; }
Class objc_opt_class(id obj) { return obj ? SEND0(Class, obj, SEL_class) : NULL; }
BOOL objc_opt_isKindOfClass(id obj, Class cls) { return obj ? SEND1(BOOL, obj, SEL_isKindOfClass, cls) : NO; }
BOOL objc_opt_respondsToSelector(id obj, SEL sel) { return obj ? SEND1(BOOL, obj, SEL_respondsToSelector, sel) : NO; }

/* ---- errors the compiler can call --------------------------------------------- */

static void (*mutation_handler)(id);

void objc_setEnumerationMutationHandler(void (*handler)(id)) { mutation_handler = handler; }

void objc_enumerationMutation(id obj)
{
    if (mutation_handler) {
        mutation_handler(obj);
        return;
    }
    fflush(stdout);
    fprintf(stderr, "objc[%d]: a collection (%s) was changed while it was being enumerated\n",
            getpid(), object_getClassName(obj));
    abort();
}

/* ---- NSObject ------------------------------------------------------------------ */

struct fobjc_class ferry_class_NSObject, ferry_meta_NSObject;
struct fobjc_class ferry_class_Protocol, ferry_meta_Protocol;

typedef void *NSZone;

static id i_self(id self, SEL _cmd) { (void)_cmd; return self; }
static id i_init(id self, SEL _cmd) { (void)_cmd; return self; }
static void i_noop(id self, SEL _cmd) { (void)self; (void)_cmd; }
static id i_retain(id self, SEL _cmd) { (void)_cmd; return rr_retain(self); }
static void i_release(id self, SEL _cmd) { (void)_cmd; rr_release(self); }
static id i_autorelease(id self, SEL _cmd) { (void)_cmd; pool_add(self); return self; }
static uintptr_t i_retainCount(id self, SEL _cmd) { (void)_cmd; return rr_count(self); }
static void i_dealloc(id self, SEL _cmd) { (void)_cmd; object_dispose(self); }
static Class i_class(id self, SEL _cmd) { (void)_cmd; return object_getClass(self); }
static Class i_superclass(id self, SEL _cmd) { (void)_cmd; return object_getClass(self)->superclass; }
static BOOL i_isEqual(id self, SEL _cmd, id other) { (void)_cmd; return self == other; }
static uintptr_t i_hash(id self, SEL _cmd) { (void)_cmd; return (uintptr_t)self; }
static BOOL i_no(id self, SEL _cmd) { (void)self; (void)_cmd; return NO; }
static BOOL i_isDeallocating(id self, SEL _cmd)
{
    (void)_cmd;
    return !!(__atomic_load_n(&OBJ_HEADER(self)->flags, __ATOMIC_ACQUIRE) & OBJ_DEALLOCATING);
}
static BOOL i_yes(id self, SEL _cmd) { (void)self; (void)_cmd; return YES; }
static NSZone i_zone(id self, SEL _cmd) { (void)self; (void)_cmd; return NULL; }
static id i_nil1(id self, SEL _cmd, id a) { (void)self; (void)_cmd; (void)a; return nil; }
static BOOL i_no1(id self, SEL _cmd, id a) { (void)self; (void)_cmd; (void)a; return NO; }

static BOOL i_isKindOfClass(id self, SEL _cmd, Class cls)
{
    (void)_cmd;
    for (Class c = object_getClass(self); c; c = c->superclass)
        if (c == cls)
            return YES;
    return NO;
}

/* by -class, so that an object in key-value observing's hidden subclass is still a member of its class */
static BOOL i_isMemberOfClass(id self, SEL _cmd, Class cls) { (void)_cmd; return SEND0(Class, self, SEL_class) == cls; }

BOOL class_respondsToSelector(Class cls, SEL sel);
BOOL class_conformsToProtocol(Class cls, struct c_protocol *p);
IMP class_getMethodImplementation(Class cls, SEL sel);

static BOOL i_respondsToSelector(id self, SEL _cmd, SEL sel)
{
    (void)_cmd;
    return sel && class_respondsToSelector(object_getClass(self), sel);
}

static BOOL c_conformsToProtocol(id self, SEL _cmd, struct c_protocol *p)
{
    (void)_cmd;
    for (Class c = (Class)self; c; c = c->superclass)
        if (class_conformsToProtocol(c, p))
            return YES;
    return NO;
}

static BOOL i_conformsToProtocol(id self, SEL _cmd, struct c_protocol *p)
{
    return c_conformsToProtocol((id)object_getClass(self), _cmd, p);
}

static id i_copy(id self, SEL _cmd) { (void)_cmd; return SEND1(id, self, SEL_copyWithZone, (void *)NULL); }
static id i_mutableCopy(id self, SEL _cmd) { (void)_cmd; return SEND1(id, self, SEL_mutableCopyWithZone, (void *)NULL); }

static id i_perform0(id self, SEL _cmd, SEL sel) { (void)_cmd; return SEND0(id, self, sel); }
static id i_perform1(id self, SEL _cmd, SEL sel, id a) { (void)_cmd; return SEND1(id, self, sel, a); }
static id i_perform2(id self, SEL _cmd, SEL sel, id a, id b)
{
    (void)_cmd;
    return FN(id(*)(id, SEL, id, id), ferry_objc_msgSend)(self, sel, a, b);
}

static IMP i_methodForSelector(id self, SEL _cmd, SEL sel)
{
    (void)_cmd;
    return class_getMethodImplementation(object_getClass(self), sel);
}

static IMP c_instanceMethodForSelector(id self, SEL _cmd, SEL sel)
{
    (void)_cmd;
    return class_getMethodImplementation((Class)self, sel);
}

static void i_doesNotRecognizeSelector(id self, SEL _cmd, SEL sel)
{
    (void)_cmd;
    Class cls = object_getClass(self);
    int meta = class_rt(cls)->flags & RT_META;
    char reason[512];
    snprintf(reason, sizeof reason, "%c[%s %s]: unrecognized selector sent to %s %p", meta ? '+' : '-',
             class_getName(cls), sel, meta ? "class" : "instance", (void *)self);
    fflush(stdout);
    fprintf(stderr, "%s\n*** Terminating app due to uncaught exception 'NSInvalidArgumentException', "
            "reason: '%s'\n", reason, reason);
    abort();
}

static id c_alloc(id self, SEL _cmd) { (void)_cmd; return SEND1(id, self, SEL_allocWithZone, (NSZone)NULL); }
static id c_allocWithZone(id self, SEL _cmd, NSZone z) { (void)_cmd; (void)z; return class_createInstance((Class)self, 0); }
static id c_new(id self, SEL _cmd) { (void)_cmd; return SEND0(id, SEND0(id, self, SEL_alloc), SEL_init); }
static Class c_superclass(id self, SEL _cmd) { (void)_cmd; return ((Class)self)->superclass; }
static uintptr_t c_retainCount(id self, SEL _cmd) { (void)self; (void)_cmd; return UINTPTR_MAX; }
static id c_copyWithZone(id self, SEL _cmd, NSZone z) { (void)_cmd; (void)z; return self; }

static BOOL c_respondsToSelector(id self, SEL _cmd, SEL sel)
{
    (void)_cmd;
    return sel && class_respondsToSelector(object_getClass(self), sel);
}

static BOOL c_instancesRespondToSelector(id self, SEL _cmd, SEL sel)
{
    (void)_cmd;
    return sel && class_respondsToSelector((Class)self, sel);
}

static BOOL c_isSubclassOfClass(id self, SEL _cmd, Class cls)
{
    (void)_cmd;
    for (Class c = (Class)self; c; c = c->superclass)
        if (c == cls)
            return YES;
    return NO;
}

#define M(sel, types, fn) {sel, types, (IMP)(void (*)(void))(fn)}

static const struct fmethod nsobject_instance[] = {
    M("init", "@16@0:8", i_init),
    M("dealloc", "v16@0:8", i_dealloc),
    M("finalize", "v16@0:8", i_noop),
    M("retain", "@16@0:8", i_retain),
    M("release", "Vv16@0:8", i_release),
    M("autorelease", "@16@0:8", i_autorelease),
    M("retainCount", "Q16@0:8", i_retainCount),
    M("_tryRetain", "c16@0:8", i_yes),
    M("_isDeallocating", "c16@0:8", i_isDeallocating),
    M("allowsWeakReference", "c16@0:8", i_yes),
    M("retainWeakReference", "c16@0:8", i_yes),
    M("self", "@16@0:8", i_self),
    M("class", "#16@0:8", i_class),
    M("superclass", "#16@0:8", i_superclass),
    M("isEqual:", "c24@0:8@16", i_isEqual),
    M("hash", "Q16@0:8", i_hash),
    M("isProxy", "c16@0:8", i_no),
    M("zone", "^{_NSZone=}16@0:8", i_zone),
    M("isKindOfClass:", "c24@0:8#16", i_isKindOfClass),
    M("isMemberOfClass:", "c24@0:8#16", i_isMemberOfClass),
    M("respondsToSelector:", "c24@0:8:16", i_respondsToSelector),
    M("conformsToProtocol:", "c24@0:8@16", i_conformsToProtocol),
    M("copy", "@16@0:8", i_copy),
    M("mutableCopy", "@16@0:8", i_mutableCopy),
    M("performSelector:", "@24@0:8:16", i_perform0),
    M("performSelector:withObject:", "@32@0:8:16@24", i_perform1),
    M("performSelector:withObject:withObject:", "@40@0:8:16@24@32", i_perform2),
    M("methodForSelector:", "^?24@0:8:16", i_methodForSelector),
    M("doesNotRecognizeSelector:", "v24@0:8:16", i_doesNotRecognizeSelector),
    M("forwardingTargetForSelector:", "@24@0:8:16", i_nil1),
    M("forwardInvocation:", "v24@0:8@16", i_nil1),
};

static const struct fmethod nsobject_class[] = {
    M("load", "v16@0:8", i_noop),
    M("initialize", "v16@0:8", i_noop),
    M("alloc", "@16@0:8", c_alloc),
    M("allocWithZone:", "@24@0:8^{_NSZone=}16", c_allocWithZone),
    M("new", "@16@0:8", c_new),
    M("self", "@16@0:8", i_self),
    M("class", "#16@0:8", i_self),
    M("superclass", "#16@0:8", c_superclass),
    M("retain", "@16@0:8", i_self),
    M("release", "Vv16@0:8", i_noop),
    M("autorelease", "@16@0:8", i_self),
    M("retainCount", "Q16@0:8", c_retainCount),
    M("copy", "@16@0:8", i_self),
    M("copyWithZone:", "@24@0:8^{_NSZone=}16", c_copyWithZone),
    M("mutableCopyWithZone:", "@24@0:8^{_NSZone=}16", c_copyWithZone),
    M("hash", "Q16@0:8", i_hash),
    M("isEqual:", "c24@0:8@16", i_isEqual),
    M("respondsToSelector:", "c24@0:8:16", c_respondsToSelector),
    M("instancesRespondToSelector:", "c24@0:8:16", c_instancesRespondToSelector),
    M("conformsToProtocol:", "c24@0:8@16", c_conformsToProtocol),
    M("isSubclassOfClass:", "c24@0:8#16", c_isSubclassOfClass),
    M("instanceMethodForSelector:", "^?24@0:8:16", c_instanceMethodForSelector),
    M("resolveClassMethod:", "c24@0:8:16", i_no1),
    M("resolveInstanceMethod:", "c24@0:8:16", i_no1),
};

/* Classes whose instances live in the program's data (blocks, protocols):
 * retain and release do nothing. */
const struct fmethod ferry_static_rr_methods[] = {
    M("retain", "@16@0:8", i_self),
    M("release", "Vv16@0:8", i_noop),
    M("autorelease", "@16@0:8", i_self),
    M("retainCount", "Q16@0:8", c_retainCount),
    M("dealloc", "v16@0:8", i_noop),
};
const unsigned ferry_static_rr_count = sizeof ferry_static_rr_methods / sizeof ferry_static_rr_methods[0];

static const char *p_name(struct c_protocol *self, SEL _cmd) { (void)_cmd; return self->name; }
BOOL protocol_conformsToProtocol(struct c_protocol *p, struct c_protocol *other);
BOOL protocol_isEqual(struct c_protocol *a, struct c_protocol *b);
static BOOL p_conforms(struct c_protocol *self, SEL _cmd, struct c_protocol *o) { (void)_cmd; return protocol_conformsToProtocol(self, o); }
static BOOL p_isEqual(struct c_protocol *self, SEL _cmd, struct c_protocol *o) { (void)_cmd; return protocol_isEqual(self, o); }

#define COUNT(a) (unsigned)(sizeof(a) / sizeof((a)[0]))

void ferry_objc_nsobject_init(void)
{
    SEL_isDeallocating = sel_registerName("_isDeallocating");
    ferry_objc_make_class(&ferry_class_NSObject, &ferry_meta_NSObject, NULL, "NSObject", sizeof(Class),
                          nsobject_instance, COUNT(nsobject_instance), nsobject_class, COUNT(nsobject_class), 0);
    struct fmethod proto[COUNT(ferry_static_rr_methods) + 3];
    memcpy(proto, ferry_static_rr_methods, sizeof ferry_static_rr_methods);
    proto[ferry_static_rr_count] = (struct fmethod)M("name", "*16@0:8", p_name);
    proto[ferry_static_rr_count + 1] = (struct fmethod)M("conformsTo:", "c24@0:8@16", p_conforms);
    proto[ferry_static_rr_count + 2] = (struct fmethod)M("isEqual:", "c24@0:8@16", p_isEqual);
    ferry_objc_make_class(&ferry_class_Protocol, &ferry_meta_Protocol, &ferry_class_NSObject, "Protocol",
                          sizeof(struct c_protocol), proto, COUNT(proto), NULL, 0, RT_STATIC_INSTANCES);
}
