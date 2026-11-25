/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Grand Central Dispatch, as far as Ferry's libSystem provides it
 * (ferry/src/objc/dispatch.c). Written for freemac from Apple's public
 * documentation of libdispatch; not Apple's header. In Objective-C,
 * dispatch objects are objects, so ARC retains and releases them. */
#ifndef _FERRY_DISPATCH_H_
#define _FERRY_DISPATCH_H_
#include <_ferry.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <time.h>

#if defined(__OBJC__) && defined(__swift__)
/* Seen from Swift (freemac 1.230), dispatch objects are NSObjects rather
 * than "id", which Swift would see as Any: Ferry's Dispatch overlay
 * (swift/overlays/Dispatch) wraps them in DispatchQueue and the like. */
#include <objc/NSObject.h>
typedef NSObject *dispatch_object_t;
typedef NSObject *dispatch_queue_t;
typedef NSObject *dispatch_queue_global_t;
typedef NSObject *dispatch_queue_main_t;
typedef NSObject *dispatch_queue_serial_t;
typedef NSObject *dispatch_queue_concurrent_t;
typedef void *dispatch_queue_attr_t;   /* not an object here */
typedef NSObject *dispatch_group_t;
typedef NSObject *dispatch_semaphore_t;
typedef NSObject *dispatch_source_t;
#define DISPATCH_RETURNS_RETAINED __attribute__((ns_returns_retained))
#elif defined(__OBJC__)
/* As a Mac's os/object.h does: dispatch objects are NSObjects, so anything
 * that includes dispatch (Core Services, Carbon) declares NSObject. */
#include <objc/NSObject.h>
#ifndef OS_OBJECT_USE_OBJC
#define OS_OBJECT_USE_OBJC 1 /* as os/object.h has it (freemac 1.NEXT, VLC) */
#endif
typedef id dispatch_object_t;
typedef id dispatch_queue_t;
typedef id dispatch_queue_global_t;
typedef id dispatch_queue_main_t;
typedef id dispatch_queue_serial_t;
typedef id dispatch_queue_concurrent_t;
typedef id dispatch_queue_attr_t;
typedef id dispatch_group_t;
typedef id dispatch_semaphore_t;
typedef id dispatch_source_t;
#define DISPATCH_RETURNS_RETAINED __attribute__((ns_returns_retained))
#else
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef struct dispatch_queue_s *dispatch_queue_global_t;
typedef struct dispatch_queue_s *dispatch_queue_main_t;
typedef struct dispatch_queue_s *dispatch_queue_serial_t;
typedef struct dispatch_queue_s *dispatch_queue_concurrent_t;
typedef struct dispatch_queue_attr_s *dispatch_queue_attr_t;
typedef struct dispatch_group_s *dispatch_group_t;
typedef struct dispatch_semaphore_s *dispatch_semaphore_t;
typedef struct dispatch_source_s *dispatch_source_t;
#ifdef __cplusplus
/* In C++ (freemac 1.230), as on a Mac, each kind of object is a kind of
 * dispatch_object_s, so that any of them is a dispatch_object_t. */
struct dispatch_object_s {};
struct dispatch_queue_s : public dispatch_object_s {};
struct dispatch_queue_attr_s : public dispatch_object_s {};
struct dispatch_group_s : public dispatch_object_s {};
struct dispatch_semaphore_s : public dispatch_object_s {};
struct dispatch_source_s : public dispatch_object_s {};
typedef struct dispatch_object_s *dispatch_object_t;
#else
/* Any dispatch object, as C's transparent union lets it be passed. */
typedef union {
    struct dispatch_object_s *_do;
    struct dispatch_queue_s *_dq;
    struct dispatch_queue_attr_s *_dqa;
    struct dispatch_group_s *_dg;
    struct dispatch_semaphore_s *_dsema;
    struct dispatch_source_s *_ds;
} dispatch_object_t __attribute__((transparent_union));
#endif
#define DISPATCH_RETURNS_RETAINED
#endif

typedef uint64_t dispatch_time_t;
typedef long dispatch_once_t;
typedef long dispatch_queue_priority_t;
typedef const struct dispatch_source_type_s *dispatch_source_type_t;
typedef void (*dispatch_function_t)(void *);
#if __BLOCKS__
typedef void (^dispatch_block_t)(void);
#endif

#define DISPATCH_TIME_NOW (0ull)
#define DISPATCH_TIME_FOREVER (~0ull)
#define NSEC_PER_SEC 1000000000ull
#define NSEC_PER_MSEC 1000000ull
#define USEC_PER_SEC 1000000ull
#define NSEC_PER_USEC 1000ull

#define DISPATCH_QUEUE_PRIORITY_HIGH 2
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#define DISPATCH_QUEUE_PRIORITY_LOW (-2)
#define DISPATCH_QUEUE_PRIORITY_BACKGROUND (-32768)
#define QOS_CLASS_USER_INTERACTIVE 0x21
#define QOS_CLASS_USER_INITIATED 0x19
#define QOS_CLASS_DEFAULT 0x15
#define QOS_CLASS_UTILITY 0x11
#define QOS_CLASS_BACKGROUND 0x09
typedef unsigned int dispatch_qos_class_t;

__FERRY_BEGIN
extern struct dispatch_queue_s _dispatch_main_q;
extern struct dispatch_queue_attr_s _dispatch_queue_attr_concurrent;
extern const struct dispatch_source_type_s _dispatch_source_type_timer, _dispatch_source_type_data_add,
    _dispatch_source_type_data_or, _dispatch_source_type_data_replace, _dispatch_source_type_read,
    _dispatch_source_type_write, _dispatch_source_type_signal, _dispatch_source_type_proc,
    _dispatch_source_type_vnode;
__FERRY_END

#ifdef __OBJC__
#define dispatch_get_main_queue() ((__bridge dispatch_queue_main_t)(void *)&_dispatch_main_q)
#define DISPATCH_QUEUE_CONCURRENT ((__bridge dispatch_queue_attr_t)(void *)&_dispatch_queue_attr_concurrent)
#else
#define dispatch_get_main_queue() (&_dispatch_main_q)
#define DISPATCH_QUEUE_CONCURRENT (&_dispatch_queue_attr_concurrent)
#endif
#if defined(__OBJC__) && defined(__swift__)
/* What the macros above stand for, as functions Swift can call. */
static inline dispatch_queue_main_t _ferry_dispatch_main_queue(void) { return dispatch_get_main_queue(); }
static inline dispatch_queue_attr_t _ferry_dispatch_queue_concurrent(void) { return &_dispatch_queue_attr_concurrent; }
static inline dispatch_source_type_t _ferry_dispatch_source_type(int which) {
    switch (which) {
    case 0: return &_dispatch_source_type_timer;
    case 1: return &_dispatch_source_type_data_add;
    case 2: return &_dispatch_source_type_data_or;
    case 3: return &_dispatch_source_type_data_replace;
    case 4: return &_dispatch_source_type_read;
    case 5: return &_dispatch_source_type_write;
    case 6: return &_dispatch_source_type_signal;
    case 7: return &_dispatch_source_type_proc;
    default: return &_dispatch_source_type_vnode;
    }
}
#endif
#define DISPATCH_QUEUE_SERIAL NULL
#define DISPATCH_QUEUE_SERIAL_INACTIVE dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_SERIAL)
#define DISPATCH_QUEUE_CONCURRENT_INACTIVE dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_CONCURRENT)
#define DISPATCH_APPLY_AUTO NULL
#define DISPATCH_TARGET_QUEUE_DEFAULT NULL
#define DISPATCH_SOURCE_TYPE_TIMER (&_dispatch_source_type_timer)
#define DISPATCH_SOURCE_TYPE_DATA_ADD (&_dispatch_source_type_data_add)
#define DISPATCH_SOURCE_TYPE_DATA_OR (&_dispatch_source_type_data_or)
#define DISPATCH_SOURCE_TYPE_DATA_REPLACE (&_dispatch_source_type_data_replace)
#define DISPATCH_SOURCE_TYPE_READ (&_dispatch_source_type_read)
#define DISPATCH_SOURCE_TYPE_WRITE (&_dispatch_source_type_write)
#define DISPATCH_SOURCE_TYPE_SIGNAL (&_dispatch_source_type_signal)
#define DISPATCH_SOURCE_TYPE_PROC (&_dispatch_source_type_proc)
typedef unsigned long dispatch_source_proc_flags_t;
#define DISPATCH_PROC_EXIT 0x80000000ul
#define DISPATCH_PROC_FORK 0x40000000ul
#define DISPATCH_PROC_EXEC 0x20000000ul
#define DISPATCH_PROC_SIGNAL 0x08000000ul
#define DISPATCH_SOURCE_TYPE_VNODE (&_dispatch_source_type_vnode)
typedef unsigned long dispatch_source_vnode_flags_t;
#define DISPATCH_VNODE_DELETE 0x1ul
#define DISPATCH_VNODE_WRITE 0x2ul
#define DISPATCH_VNODE_EXTEND 0x4ul
#define DISPATCH_VNODE_ATTRIB 0x8ul
#define DISPATCH_VNODE_LINK 0x10ul
#define DISPATCH_VNODE_RENAME 0x20ul
#define DISPATCH_VNODE_REVOKE 0x40ul
#define DISPATCH_VNODE_FUNLOCK 0x100ul

__FERRY_BEGIN
dispatch_time_t dispatch_time(dispatch_time_t when, int64_t delta);
dispatch_time_t dispatch_walltime(const struct timespec *when, int64_t delta);

dispatch_queue_global_t dispatch_get_global_queue(long identifier, unsigned long flags);
DISPATCH_RETURNS_RETAINED dispatch_queue_t dispatch_queue_create(const char *label, dispatch_queue_attr_t attr);
DISPATCH_RETURNS_RETAINED dispatch_queue_t dispatch_queue_create_with_target(const char *label,
                                                                             dispatch_queue_attr_t attr,
                                                                             dispatch_queue_t target);
dispatch_queue_attr_t dispatch_queue_attr_make_with_qos_class(dispatch_queue_attr_t attr,
                                                              dispatch_qos_class_t qos, int priority);
dispatch_queue_attr_t dispatch_queue_attr_make_initially_inactive(dispatch_queue_attr_t attr);
const char *dispatch_queue_get_label(dispatch_queue_t queue);
dispatch_queue_t dispatch_get_current_queue(void);
/* stop the program unless the work running now runs on the queue (or, for
 * _not, unless it doesn't) */
void dispatch_assert_queue(dispatch_queue_t queue);
void dispatch_assert_queue_not(dispatch_queue_t queue);
void dispatch_assert_queue_barrier(dispatch_queue_t queue);
#define DISPATCH_CURRENT_QUEUE_LABEL NULL
void dispatch_set_target_queue(dispatch_object_t object, dispatch_queue_t queue);
void dispatch_suspend(dispatch_object_t object);
void dispatch_resume(dispatch_object_t object);
void dispatch_activate(dispatch_object_t object);
void *dispatch_get_context(dispatch_object_t object);
void dispatch_set_context(dispatch_object_t object, void *context);
void dispatch_set_finalizer_f(dispatch_object_t object, dispatch_function_t finalizer);
void dispatch_queue_set_specific(dispatch_queue_t queue, const void *key, void *context,
                                 dispatch_function_t destructor);
void *dispatch_queue_get_specific(dispatch_queue_t queue, const void *key);
void *dispatch_get_specific(const void *key);
void dispatch_main(void) __attribute__((noreturn));

void dispatch_async_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_sync_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_barrier_async_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_barrier_sync_f(dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_after_f(dispatch_time_t when, dispatch_queue_t queue, void *context, dispatch_function_t work);
void dispatch_apply_f(size_t iterations, dispatch_queue_t queue, void *context, void (*work)(void *, size_t));
void dispatch_once_f(dispatch_once_t *predicate, void *context, dispatch_function_t function);

DISPATCH_RETURNS_RETAINED dispatch_group_t dispatch_group_create(void);
void dispatch_group_enter(dispatch_group_t group);
void dispatch_group_leave(dispatch_group_t group);
long dispatch_group_wait(dispatch_group_t group, dispatch_time_t timeout);
void dispatch_group_async_f(dispatch_group_t group, dispatch_queue_t queue, void *context,
                            dispatch_function_t work);
void dispatch_group_notify_f(dispatch_group_t group, dispatch_queue_t queue, void *context,
                             dispatch_function_t work);

DISPATCH_RETURNS_RETAINED dispatch_semaphore_t dispatch_semaphore_create(long value);
long dispatch_semaphore_wait(dispatch_semaphore_t semaphore, dispatch_time_t timeout);
long dispatch_semaphore_signal(dispatch_semaphore_t semaphore);

DISPATCH_RETURNS_RETAINED dispatch_source_t dispatch_source_create(dispatch_source_type_t type, uintptr_t handle,
                                                                   unsigned long mask, dispatch_queue_t queue);
void dispatch_source_set_timer(dispatch_source_t source, dispatch_time_t start, uint64_t interval,
                               uint64_t leeway);
void dispatch_source_cancel(dispatch_source_t source);
long dispatch_source_testcancel(dispatch_source_t source);
unsigned long dispatch_source_get_data(dispatch_source_t source);
unsigned long dispatch_source_get_mask(dispatch_source_t source);
uintptr_t dispatch_source_get_handle(dispatch_source_t source);
void dispatch_source_merge_data(dispatch_source_t source, unsigned long value);
void dispatch_source_set_event_handler_f(dispatch_source_t source, dispatch_function_t handler);
void dispatch_source_set_cancel_handler_f(dispatch_source_t source, dispatch_function_t handler);

#if __BLOCKS__
void dispatch_async(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_sync(dispatch_queue_t queue, __attribute__((noescape)) dispatch_block_t block);
void dispatch_barrier_async(dispatch_queue_t queue, dispatch_block_t block);
void dispatch_barrier_sync(dispatch_queue_t queue, __attribute__((noescape)) dispatch_block_t block);
void dispatch_after(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
void dispatch_apply(size_t iterations, dispatch_queue_t queue, __attribute__((noescape)) void (^block)(size_t));
void dispatch_once(dispatch_once_t *predicate, __attribute__((noescape)) dispatch_block_t block);
void dispatch_group_async(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block);
void dispatch_group_notify(dispatch_group_t group, dispatch_queue_t queue, dispatch_block_t block);
void dispatch_source_set_event_handler(dispatch_source_t source, dispatch_block_t handler);
void dispatch_source_set_cancel_handler(dispatch_source_t source, dispatch_block_t handler);
#endif

#if !defined(__OBJC__) || !__has_feature(objc_arc)
void dispatch_retain(dispatch_object_t object);
void dispatch_release(dispatch_object_t object);
#endif
__FERRY_END
#endif
