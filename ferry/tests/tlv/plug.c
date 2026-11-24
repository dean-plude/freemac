/* SPDX-License-Identifier: GPL-3.0-or-later
 * A Mac library the tlv_dlopen program opens with dlopen (built by run.sh
 * into build/tlv_plug), with thread-local variables of its own and
 * destructors registered for a thread with libSystem's _tlv_atexit, the
 * call compilers make for C++ thread_local objects, and with the C++
 * ABI's __cxa_thread_atexit, which shares its order. */
#include <stdio.h>
#include <string.h>

void _tlv_atexit(void (*fn)(void *), void *obj);
int __cxa_thread_atexit(void (*fn)(void *), void *obj, void *dso);

__thread int plug_value = 100;
_Thread_local char plug_buf[256];
static __thread int plug_watched;

int plug_next(void) { return ++plug_value; }
const char *plug_note(const char *text)
{
    snprintf(plug_buf, sizeof plug_buf, "%s/%d", text, plug_value);
    return plug_buf;
}

/* Each thread that asks gets two destructors, which write into its log
 * when the thread ends: the last registered first. */
struct log { char text[64]; };

static void ended_first(void *obj) { strcat(((struct log *)obj)->text, " first"); }
static void ended_second(void *obj)
{
    /* a destructor may still reach the thread's variables */
    char tail[32];
    snprintf(tail, sizeof tail, " second(%d)", plug_value);
    strcat(((struct log *)obj)->text, tail);
}

void plug_watch(struct log *log)
{
    if (plug_watched++)
        return;
    __cxa_thread_atexit(ended_first, log, NULL);
    _tlv_atexit(ended_second, log);
}
