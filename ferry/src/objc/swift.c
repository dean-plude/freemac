/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * What Swift's runtime asks of the Objective-C runtime on a Mac (freemac
 * 1.227). Swift's runtime, built for an Intel Mac from the open-source
 * Swift project's sources (swift/build-runtime.sh), makes some classes
 * while the program runs (generic classes, and classes whose superclass's
 * size is only known then) and hands them to the Objective-C runtime to be
 * realized; it also offers classes by name that it hasn't made yet, names
 * the generic ones only when asked, and moves the stand-in root classes of
 * its own bridged collections and strings under Foundation's. The calls
 * are the documented ones in the Objective-C runtime reference and in
 * <objc/runtime.h>'s published comments: objc_readClassPair,
 * class_setSuperclass, objc_setHook_getClass, objc_setHook_getImageName
 * and objc_setHook_lazyClassNamer, and _objc_realizeClassFromSwift, which
 * Swift's runtime declares for itself. Their implementation here is
 * Ferry's own.
 *
 * A Swift class looks to the runtime like any compiled class: its first
 * five words are an Objective-C class, and Swift marks it as its own in
 * the low bits of the class's data pointer, which Ferry already masks off.
 */
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "objc-private.h"

typedef BOOL (*objc_hook_getClass)(const char *name, Class *out);
typedef BOOL (*objc_hook_getImageName)(Class cls, const char **out);
typedef const char *(*objc_hook_lazyClassNamer)(Class cls);

/* Each hook a caller installs passes what it can't answer on to the one
 * it replaced, so the first one is the runtime's own, answering nothing. */
static BOOL no_class(const char *name, Class *out) { return NO; }
static BOOL no_image_name(Class cls, const char **out) { return NO; }
static const char *no_class_name(Class cls) { return NULL; }

static objc_hook_getClass get_class_hook = no_class;
static objc_hook_getImageName get_image_name_hook = no_image_name;
static objc_hook_lazyClassNamer lazy_namer = no_class_name;
static __thread int in_get_class_hook;

void objc_setHook_getClass(objc_hook_getClass hook, objc_hook_getClass *old)
{
    LOCK();
    if (old)
        *old = get_class_hook;
    get_class_hook = hook;
    UNLOCK();
}

/* Kept, but class_getImageName answers from the image the class came in,
 * which is right for Swift's classes too. */
void objc_setHook_getImageName(objc_hook_getImageName hook, objc_hook_getImageName *old)
{
    LOCK();
    if (old)
        *old = get_image_name_hook;
    get_image_name_hook = hook;
    UNLOCK();
}

void objc_setHook_lazyClassNamer(objc_hook_lazyClassNamer hook, objc_hook_lazyClassNamer *old)
{
    LOCK();
    if (old)
        *old = lazy_namer;
    lazy_namer = hook;
    UNLOCK();
}

/* objc_getClass's last resort: a class Swift can make from its name (its
 * mangled name, as NSClassFromString and nibs give it). The hook may look
 * classes up itself, so it isn't asked again from inside itself. */
Class ferry_objc_class_from_hook(const char *name)
{
    objc_hook_getClass hook = __atomic_load_n(&get_class_hook, __ATOMIC_ACQUIRE);
    if (hook == no_class || in_get_class_hook)
        return NULL;
    Class out = NULL;
    in_get_class_hook = 1;
    BOOL found = hook(name, &out);
    in_get_class_hook = 0;
    return found ? out : NULL;
}

/* The name of a class whose description carries none (Swift's generic
 * classes), from Swift's namer, called while the class is realized. */
const char *ferry_objc_lazy_class_name(Class cls)
{
    objc_hook_lazyClassNamer namer = __atomic_load_n(&lazy_namer, __ATOMIC_ACQUIRE);
    const char *name = namer ? namer(cls) : NULL;
    return name ? name : "(unnamed Swift class)";
}

/* A class and its metaclass laid out by the compiler or by Swift's runtime,
 * registered and realized. */
Class objc_readClassPair(Class cls, const void *image_info)
{
    (void)image_info;
    return ferry_objc_realize_runtime_class(cls, NULL);
}

/* A class whose metadata Swift's runtime initialized; "previously" is where
 * it was before Swift moved it, if it did, which Ferry never saw. */
Class _objc_realizeClassFromSwift(Class cls, void *previously)
{
    (void)previously;
    return ferry_objc_realize_runtime_class(cls, NULL);
}

/* Deprecated, but Swift's runtime uses it once, at start, to put its
 * bridged collections' and strings' root classes under Foundation's. */
Class class_setSuperclass(Class cls, Class super)
{
    if (!cls || !super)
        return NULL;
    LOCK();
    Class old = cls->superclass, meta = cls->isa;
    cls->superclass = super;
    if (meta && super->isa) {
        meta->superclass = super->isa;
        meta->isa = super->isa->isa;        /* the root metaclass */
    }
    if (class_is_realized(cls))
        class_rt(cls)->flags &= ~(uint32_t)RT_ROOT;
    if (meta && class_is_realized(meta))
        class_rt(meta)->flags &= ~(uint32_t)RT_ROOT;
    UNLOCK();
    ferry_objc_flush_caches();
    return old;
}
