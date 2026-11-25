/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* os_activity, as Apple's public documentation of it describes it (freemac
 * 1.224, Ferry 0.48.0). An activity only groups log messages; this
 * system's log has no activities, so an activity's block or function is
 * simply run, and the rest does nothing. */
#ifndef _OS_ACTIVITY_H_
#define _OS_ACTIVITY_H_
#include <_ferry.h>
#include <stdint.h>
__FERRY_BEGIN

typedef struct os_activity_s *os_activity_t;
typedef uint64_t os_activity_id_t;
typedef struct os_activity_scope_state_s {
    uint64_t opaque[2];
} *os_activity_scope_state_t;
typedef uint32_t os_activity_flag_t;
#define OS_ACTIVITY_FLAG_DEFAULT ((os_activity_flag_t)0)
#define OS_ACTIVITY_FLAG_DETACHED ((os_activity_flag_t)1)
#define OS_ACTIVITY_FLAG_IF_NONE_PRESENT ((os_activity_flag_t)2)
#define OS_ACTIVITY_NONE ((os_activity_t)0)
#define OS_ACTIVITY_CURRENT ((os_activity_t)0)

static inline os_activity_t ferry_os_activity_create(const char *description, os_activity_t parent,
                                                     os_activity_flag_t flags)
{
    return OS_ACTIVITY_NONE;
}
#define os_activity_create(description, parent, flags) ferry_os_activity_create((description), (parent), (flags))
static inline void os_activity_scope_enter(os_activity_t activity, os_activity_scope_state_t state) {}
static inline void os_activity_scope_leave(os_activity_scope_state_t state) {}
static inline void os_activity_initiate_f(const char *description, os_activity_flag_t flags, void *context,
                                          void (*function)(void *))
{
    function(context);
}
static inline void os_activity_apply_f(os_activity_t activity, void *context, void (*function)(void *))
{
    function(context);
}
#if __BLOCKS__
static inline void ferry_os_activity_initiate(const char *description, os_activity_flag_t flags, void (^block)(void))
{
    block();
}
/* the block may hold commas, so it is passed on as the macro's rest */
#define os_activity_initiate(description, flags, ...) ferry_os_activity_initiate((description), (flags), __VA_ARGS__)
static inline void os_activity_apply(os_activity_t activity, void (^block)(void)) { block(); }
#endif
static inline void os_activity_label_useraction(const char *name) {}

__FERRY_END
#endif
