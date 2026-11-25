/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK) */
/* The Apple System Log calls of asl(3) (freemac 1.223, Ferry 0.47.0), which
 * older Mac programs log with. A message goes to this system's log (syslog),
 * and to standard error as well when the client was opened with
 * ASL_OPT_STDERR. Searching the log isn't supported: asl_search finds
 * nothing. */
#ifndef _ASL_H_
#define _ASL_H_
#include <_ferry.h>
#include <stdarg.h>
__FERRY_BEGIN

typedef struct __ferry_asl_object *asl_object_t;
typedef asl_object_t aslclient;
typedef asl_object_t aslmsg;
typedef asl_object_t aslresponse;

#define ASL_TYPE_MSG 0
#define ASL_TYPE_QUERY 1

#define ASL_LEVEL_EMERG 0
#define ASL_LEVEL_ALERT 1
#define ASL_LEVEL_CRIT 2
#define ASL_LEVEL_ERR 3
#define ASL_LEVEL_WARNING 4
#define ASL_LEVEL_NOTICE 5
#define ASL_LEVEL_INFO 6
#define ASL_LEVEL_DEBUG 7

#define ASL_STRING_EMERG "Emergency"
#define ASL_STRING_ALERT "Alert"
#define ASL_STRING_CRIT "Critical"
#define ASL_STRING_ERR "Error"
#define ASL_STRING_WARNING "Warning"
#define ASL_STRING_NOTICE "Notice"
#define ASL_STRING_INFO "Info"
#define ASL_STRING_DEBUG "Debug"

#define ASL_FILTER_MASK(level) (1 << (level))
#define ASL_FILTER_MASK_UPTO(level) ((1 << ((level) + 1)) - 1)

#define ASL_OPT_STDERR 0x00000001
#define ASL_OPT_NO_DELAY 0x00000002
#define ASL_OPT_NO_REMOTE 0x00000004

#define ASL_KEY_TIME "Time"
#define ASL_KEY_HOST "Host"
#define ASL_KEY_SENDER "Sender"
#define ASL_KEY_FACILITY "Facility"
#define ASL_KEY_PID "PID"
#define ASL_KEY_UID "UID"
#define ASL_KEY_GID "GID"
#define ASL_KEY_LEVEL "Level"
#define ASL_KEY_MSG "Message"

aslclient asl_open(const char *ident, const char *facility, uint32_t opts);
void asl_close(asl_object_t client);
aslmsg asl_new(uint32_t type);
void asl_free(asl_object_t obj);
void asl_release(asl_object_t obj);
int asl_set(aslmsg msg, const char *key, const char *value);
const char *asl_get(aslmsg msg, const char *key);
int asl_unset(aslmsg msg, const char *key);
int asl_send(aslclient client, aslmsg msg);
int asl_log(aslclient client, aslmsg msg, int level, const char *format, ...) __attribute__((format(printf, 4, 5)));
int asl_vlog(aslclient client, aslmsg msg, int level, const char *format, va_list ap)
    __attribute__((format(printf, 4, 0)));
int asl_set_filter(aslclient client, int filter);
int asl_add_log_file(aslclient client, int fd);
int asl_remove_log_file(aslclient client, int fd);
aslresponse asl_search(aslclient client, aslmsg query);
aslmsg aslresponse_next(aslresponse r);
void aslresponse_free(aslresponse r);

__FERRY_END
#endif
