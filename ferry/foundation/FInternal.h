/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: shared internals. Ferry's Foundation is our own code,
 * written from Apple's public API documentation; it is built as a Mach-O
 * library with ferry-cc and runs on Ferry's Objective-C runtime. Built
 * without ARC: memory is managed by hand, as in Apple's frameworks. */
#ifndef FERRY_FOUNDATION_INTERNAL_H
#define FERRY_FOUNDATION_INTERNAL_H
#include <Foundation/Foundation.h>
#include <objc/message.h>
#include <dispatch/dispatch.h>
#include <os/lock.h>
#include <ctype.h>
#include <limits.h>
#include <time.h>

void objc_exception_throw(id exception);

/* The NSCoding methods of Foundation's classes are in NSCoder.m, as categories. */
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-property-implementation"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

#define F_EXPORT __attribute__((visibility("default")))

/* Strings */
NSString *FStringFromUTF8(const char *s, NSUInteger len);       /* autoreleased */
NSString *FStringFromChars(const unichar *c, NSUInteger len);   /* autoreleased */
NSString *FFormat(NSString *format, va_list ap);                 /* autoreleased */
NSString *FFormatC(const char *format, ...);                     /* autoreleased */
BOOL FKVOIsObserved(id object);   /* has key-value observers (NSKeyValueObserving.m) */
unichar *FDecodeUTF8(const char *s, NSUInteger len, NSUInteger *outLen);   /* malloc'd */
char *FEncodeUTF8(const unichar *c, NSUInteger len, NSUInteger *outLen);   /* malloc'd */
NSUInteger FHashChars(const unichar *c, NSUInteger len);

/* Descriptions in the old-style property list form Mac Foundation prints. */
NSString *FDescribe(id obj, int indent);

/* Errors */
NSError *FPosixError(int err, NSString *path);
void FSetError(NSError **out, NSError *e);
__attribute__((noreturn)) void FRaise(NSString *name, NSString *format, ...);

/* URL loading (NSURLSession.m): an http or https URL's body or text, for
 * NSData's and NSString's ...ContentsOfURL: calls, waiting for it; nil and
 * a Cocoa error holding the URL error otherwise. */
NSData *FDataWithContentsOfNetworkURL(NSURL *url, NSString **charset, NSError **error);
NSString *FStringWithContentsOfNetworkURL(NSURL *url, NSStringEncoding enc, NSStringEncoding *used, NSError **error);
/* Another poller for the run loop to wait on while active (NSRunLoop.m). */
struct pollfd;
void FRunLoopAddPoller(int (*prepare)(void *ctx, int *timeout_ms, struct pollfd *fds, int max),
                       BOOL (*dispatch)(void *ctx, struct pollfd *fds, int count), BOOL (*active)(void *ctx),
                       void *ctx);

/* Run loop sources other than timers and ports (NSRunLoop.m), for CFSocket,
 * CFRunLoopSource and the socket streams: a descriptor watched for some
 * poll() events, and a count of sources that keep the loop running while
 * they have nothing to poll for. */
@interface NSRunLoop (FerrySources)
- (void)_addDescriptor:(int)fd events:(short)events handler:(void (*)(int fd, short revents, void *ctx))handler
               context:(void *)ctx;
- (void)_removeDescriptor:(int)fd context:(void *)ctx;
- (void)_addKeepAlive;
- (void)_removeKeepAlive;
@end
/* Prints a note on standard error once, when FERRY_VERBOSE is set (CFSocket.m). */
void FVerboseOnce(NSString *message);

/* Blocks the calling thread on a pthread condition until it is signalled
 * or limit (seconds since the reference date) passes; returns 0 or
 * ETIMEDOUT. On the main thread a wait with no limit wakes every 250 ms
 * (so it may end early) and stops the program, naming what it waits for,
 * when nothing left could end it (NSOperation.m). */
#include <pthread.h>
int FCondWait(pthread_cond_t *c, pthread_mutex_t *m, NSTimeInterval limit, const char *what);

/* A shared object made on first use: the first thread to finish making
 * one publishes it, and any other lets its own go. */
static inline id FSharedObject(void *slot, id (^make)(void))
{
    void **s = (void **)slot;
    void *have = __atomic_load_n(s, __ATOMIC_ACQUIRE);
    if (have)
        return (id)have;
    id made = make();
    void *expected = NULL;
    if (__atomic_compare_exchange_n(s, &expected, (void *)made, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
        return made;
    [made release];
    return (id)expected;
}

/* A mutex that the thread holding it may take again, for an object's own
 * state (the URL cache, the cookie and credential storages). */
static inline void FRecursiveMutexInit(pthread_mutex_t *m)
{
    pthread_mutexattr_t a;
    pthread_mutexattr_init(&a);
    pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(m, &a);
    pthread_mutexattr_destroy(&a);
}

/* Property lists */
id FParsePlist(NSData *data, NSPropertyListMutabilityOptions opt, NSPropertyListFormat *format);
NSData *FWriteXMLPlist(id plist);

/* Paths for Mac folders on freemac */
NSString *FHome(void);
NSString *FConfigHome(void);
NSString *FUserFolder(NSSearchPathDirectory dir);

/* Collections */
void FSortObjects(id *items, NSUInteger n, SEL selector);

/* The proleptic Gregorian calendar, as days since 1 January 1970 (NSTimeZone.m) */
int64_t FDaysFromCivil(int64_t year, int month, int day);
void FCivilFromDays(int64_t days, int64_t *year, int *month, int *day);

/* The UTC time (*t, whole seconds since 1970) of a local wall-clock time in a
 * zone (seconds since 1970 as if the zone were UTC). A time the clocks pass
 * twice is the first of the two, or the later one if `later`. Returns 1 for a
 * time the clocks skip: *t is then the time moved forward by the jump (gap
 * 0), the moment of the jump (1), or the time moved back by it (2). Returns 0
 * otherwise (NSCalendar.m). */
int FLocalToUTC(NSTimeZone *tz, int64_t local, BOOL later, int gap, int64_t *t);

/* The default currency of a country (ISO 3166 code), and the symbol English
 * (United States) writes for a currency, with its usual fraction digits
 * (NSNumberFormatter.m). */
NSString *FCurrencyOfCountry(NSString *country);
NSString *FCurrencySymbol(NSString *code, int *digits);

@interface NSTimeZone (FerryInternal)
/* The offset (seconds east of UTC), daylight saving flag and abbreviation in
 * effect at t, in whole seconds since 1970. */
- (void)_at:(int64_t)t offset:(int32_t *)off dst:(BOOL *)dst abbreviation:(const char **)abbr;
@end

@interface NSUserDefaults (FerryInternal)
- (NSString *)_ferryDomain; /* the application id the defaults are saved under */
@end

#endif
