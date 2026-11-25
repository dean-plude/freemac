/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* os_trace, the older form of os_log, as Apple's public documentation of
 * os_trace and os_log describes it (freemac 1.224, Ferry 0.48.0): each
 * message goes to this system's log as os_log's does (os/log.h). A
 * payload block, which on a Mac adds fields to the message, is never
 * called here, and the few XPC dictionary calls such a block makes are
 * declared below only for it (there is no XPC on this system). As on a
 * Mac, the format must be a string literal. */
#ifndef _OS_TRACE_H_
#define _OS_TRACE_H_
#include <os/log.h>
#include <stdint.h>
#include <stdbool.h>
__FERRY_BEGIN

#ifndef _FERRY_XPC_PAYLOAD_
#define _FERRY_XPC_PAYLOAD_
typedef void *xpc_object_t;
static inline void xpc_dictionary_set_uint64(xpc_object_t d, const char *key, uint64_t value) {}
static inline void xpc_dictionary_set_int64(xpc_object_t d, const char *key, int64_t value) {}
static inline void xpc_dictionary_set_bool(xpc_object_t d, const char *key, bool value) {}
static inline void xpc_dictionary_set_double(xpc_object_t d, const char *key, double value) {}
static inline void xpc_dictionary_set_string(xpc_object_t d, const char *key, const char *value) {}
#endif

#define os_trace(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, format, ##__VA_ARGS__)
#define os_trace_info(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO, format, ##__VA_ARGS__)
#define os_trace_debug(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_DEBUG, format, ##__VA_ARGS__)
#define os_trace_error(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, format, ##__VA_ARGS__)
#define os_trace_fault(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_FAULT, format, ##__VA_ARGS__)
/* the payload block is the last argument, which the format doesn't use */
#define os_trace_with_payload(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, format, __VA_ARGS__)
#define os_trace_info_with_payload(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_INFO, format, __VA_ARGS__)
#define os_trace_debug_with_payload(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_DEBUG, format, __VA_ARGS__)
#define os_trace_error_with_payload(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, format, __VA_ARGS__)
#define os_trace_fault_with_payload(format, ...) ferry_os_log(OS_LOG_DEFAULT, OS_LOG_TYPE_FAULT, format, __VA_ARGS__)
#define os_trace_info_enabled() true
#define os_trace_debug_enabled() false

__FERRY_END
#endif
