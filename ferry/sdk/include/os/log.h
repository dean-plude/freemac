/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* os_log, as Apple's public os_log(3) documents it (freemac 1.223, Ferry
 * 0.47.0). The macros pass the format and arguments to ferry_os_log, which
 * writes the message to this system's log (src/objc/oslog.c). As on a
 * Mac, the format must be a string literal. */
#ifndef _OS_LOG_H_
#define _OS_LOG_H_
#include <_ferry.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
__FERRY_BEGIN

typedef struct os_log_s *os_log_t;
#if defined(__OBJC__) && defined(__swift__)
/* As Swift sees them on a Mac (freemac 1.260): a log is an object of the
 * class OS_os_log, and a level a value of its own type, so that an app built
 * there finds what the os overlay adds to them (swift/overlays/os/Mac.swift).
 * The C calls keep taking os_log_t. */
#include <objc/NSObject.h>
@interface OS_os_log : NSObject
@end
typedef uint8_t os_log_type_t __attribute__((swift_wrapper(struct)));
static inline os_log_t _ferry_os_log_ref(OS_os_log *log) { return (__bridge os_log_t)log; }
#else
typedef uint8_t os_log_type_t;
#endif

#define OS_LOG_TYPE_DEFAULT ((os_log_type_t)0x00)
#define OS_LOG_TYPE_INFO ((os_log_type_t)0x01)
#define OS_LOG_TYPE_DEBUG ((os_log_type_t)0x02)
#define OS_LOG_TYPE_ERROR ((os_log_type_t)0x10)
#define OS_LOG_TYPE_FAULT ((os_log_type_t)0x11)

extern struct os_log_s _os_log_default;
extern struct os_log_s _os_log_disabled;
#define OS_LOG_DEFAULT (&_os_log_default)
#define OS_LOG_DISABLED (&_os_log_disabled)
#if defined(__OBJC__) && defined(__swift__)
static inline OS_os_log *_ferry_os_log_default(void) { return (__bridge OS_os_log *)(void *)&_os_log_default; }
static inline OS_os_log *_ferry_os_log_disabled(void) { return (__bridge OS_os_log *)(void *)&_os_log_disabled; }
#endif

os_log_t os_log_create(const char *subsystem, const char *category);
bool os_log_type_enabled(os_log_t log, os_log_type_t type);
void ferry_os_log(os_log_t log, os_log_type_t type, const char *format, ...);
/* The same with the arguments in a va_list, and a message already
 * formatted, for Swift's os_log and Logger (freemac 1.230). */
void ferry_os_logv(os_log_t log, os_log_type_t type, const char *format, va_list ap);
void ferry_os_log_message(os_log_t log, os_log_type_t type, const char *message);

#define os_log_with_type(log, type, format, ...) ferry_os_log((log), (type), format, ##__VA_ARGS__)
#define os_log(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_DEFAULT, format, ##__VA_ARGS__)
#define os_log_info(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_INFO, format, ##__VA_ARGS__)
#define os_log_debug(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_DEBUG, format, ##__VA_ARGS__)
#define os_log_error(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_ERROR, format, ##__VA_ARGS__)
#define os_log_fault(log, format, ...) os_log_with_type(log, OS_LOG_TYPE_FAULT, format, ##__VA_ARGS__)

__FERRY_END
#endif
