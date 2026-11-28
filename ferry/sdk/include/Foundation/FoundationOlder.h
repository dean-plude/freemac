/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Older Foundation classes that apps written for Mac OS X 10.6 to 10.10
 * still use, Sequel Pro's among them (freemac 1.226, Ferry 0.50.0):
 * NSCalendarDate, the scripting execution context, and NSConnection.
 * Written from Apple's public documentation; not Apple's header.
 * Implemented in foundation/FoundationOlder.m. Imported by Foundation.h. */
#ifndef _FERRY_FOUNDATION_OLDER_H_
#define _FERRY_FOUNDATION_OLDER_H_

/* ---- calendar dates ----------------------------------------------------------------------
 * A date with a time zone and a calendar format, the strftime-like
 * conversions of NSCalendarDate's documentation (%Y %y %m %B %b %d %e %j
 * %H %I %M %S %F %p %A %a %w %Z %z %c %x %X %%), in the Gregorian calendar.
 * The default format is "%Y-%m-%d %H:%M:%S %z". */
@interface NSCalendarDate : NSDate
+ (instancetype)calendarDate;
+ (instancetype)dateWithString:(NSString *)description calendarFormat:(NSString *)format;
+ (instancetype)dateWithString:(NSString *)description calendarFormat:(NSString *)format locale:(id)locale;
+ (instancetype)dateWithYear:(NSInteger)year month:(NSUInteger)month day:(NSUInteger)day hour:(NSUInteger)hour
                      minute:(NSUInteger)minute second:(NSUInteger)second timeZone:(NSTimeZone *)aTimeZone;
- (instancetype)initWithYear:(NSInteger)year month:(NSUInteger)month day:(NSUInteger)day hour:(NSUInteger)hour
                      minute:(NSUInteger)minute second:(NSUInteger)second timeZone:(NSTimeZone *)aTimeZone;
- (instancetype)initWithString:(NSString *)description;
- (instancetype)initWithString:(NSString *)description calendarFormat:(NSString *)format;
- (instancetype)initWithString:(NSString *)description calendarFormat:(NSString *)format locale:(id)locale;
@property (copy) NSString *calendarFormat;
@property (retain) NSTimeZone *timeZone;
- (NSInteger)yearOfCommonEra;
- (NSInteger)monthOfYear;
- (NSInteger)dayOfMonth;
- (NSInteger)dayOfWeek;
- (NSInteger)dayOfYear;
- (NSInteger)dayOfCommonEra;
- (NSInteger)hourOfDay;
- (NSInteger)minuteOfHour;
- (NSInteger)secondOfMinute;
- (NSCalendarDate *)dateByAddingYears:(NSInteger)year months:(NSInteger)month days:(NSInteger)day
                                hours:(NSInteger)hour minutes:(NSInteger)minute seconds:(NSInteger)second;
- (void)years:(NSInteger *)yp months:(NSInteger *)mop days:(NSInteger *)dp hours:(NSInteger *)hp
      minutes:(NSInteger *)mip seconds:(NSInteger *)sp sinceDate:(NSDate *)date;
- (NSString *)descriptionWithCalendarFormat:(NSString *)format;
- (NSString *)descriptionWithCalendarFormat:(NSString *)format locale:(id)locale;
- (NSString *)descriptionWithLocale:(id)locale;
@end

@interface NSDate (NSCalendarDateExtras)
- (NSCalendarDate *)dateWithCalendarFormat:(NSString *)format timeZone:(NSTimeZone *)aTimeZone;
- (NSString *)descriptionWithCalendarFormat:(NSString *)format timeZone:(NSTimeZone *)aTimeZone locale:(id)locale;
@end

/* ---- the scripting execution context ------------------------------------------------------
 * Ferry runs no AppleScript; the context only keeps what it is given. */
@interface NSScriptExecutionContext : NSObject
+ (NSScriptExecutionContext *)sharedScriptExecutionContext;
@property (retain) id topLevelObject;
@property (retain) id objectBeingTested;
@property (retain) id rangeContainerObject;
@end

/* ---- connections (Distributed Objects) ----------------------------------------------------
 * A connection registered under a name serves its root object. Within the
 * one program rootProxyForConnectionWithRegisteredName:host: answers that
 * object itself. Another program on the same computer reaches it over a
 * local socket named after it (since freemac 1.NEXT): its root proxy is an
 * NSDistantObject, messages to it are sent across and answered, and the
 * objects they carry go by copy (strings, numbers, data, dates, and
 * collections of them, or any object a bycopy argument names) or by
 * reference, as a proxy the other side sends messages back through. There
 * are no other hosts. */
@class NSPortNameServer, NSConnection;
FOUNDATION_EXPORT NSString *const NSConnectionReplyMode;
FOUNDATION_EXPORT NSNotificationName const NSConnectionDidDieNotification;
FOUNDATION_EXPORT NSNotificationName const NSConnectionDidInitializeNotification;
@protocol NSConnectionDelegate <NSObject>
@optional
- (BOOL)connection:(NSConnection *)parentConnection shouldMakeNewConnection:(NSConnection *)newConnection;
- (BOOL)makeNewConnection:(NSConnection *)conn sender:(NSConnection *)ancestor;
@end
@interface NSConnection : NSObject
+ (instancetype)defaultConnection;
+ (NSArray<NSConnection *> *)allConnections;
+ (instancetype)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName;
+ (instancetype)connectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
                            usingNameServer:(NSPortNameServer *)server;
+ (id)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName;
+ (id)rootProxyForConnectionWithRegisteredName:(NSString *)name host:(NSString *)hostName
                              usingNameServer:(NSPortNameServer *)server;
+ (instancetype)serviceConnectionWithName:(NSString *)name rootObject:(id)root;
+ (id)currentConversation;
- (instancetype)initWithReceivePort:(NSPort *)receivePort sendPort:(NSPort *)sendPort;
@property (retain) id rootObject;
@property (readonly, retain) id rootProxy;
@property (assign) id delegate;
@property NSTimeInterval requestTimeout;
@property NSTimeInterval replyTimeout;
@property BOOL independentConversationQueueing;
@property (readonly, getter=isValid) BOOL valid;
@property (readonly, copy) NSArray *requestModes;
@property (readonly, copy) NSArray *remoteObjects;
@property (readonly, copy) NSArray *localObjects;
@property (readonly, retain) NSPort *receivePort;
@property (readonly, retain) NSPort *sendPort;
- (BOOL)registerName:(NSString *)name;
- (BOOL)registerName:(NSString *)name withNameServer:(NSPortNameServer *)server;
- (void)addRequestMode:(NSString *)rmode;
- (void)removeRequestMode:(NSString *)rmode;
- (void)addRunLoop:(NSRunLoop *)runloop;
- (void)removeRunLoop:(NSRunLoop *)runloop;
- (void)runInNewThread;
- (void)enableMultipleThreads;
@property (readonly) BOOL multipleThreadsEnabled;
- (void)invalidate;
- (NSDictionary<NSString *, NSNumber *> *)statistics;
@end

/* A stand-in for an object in another program (or for one of ours, there). */
@interface NSDistantObject : NSProxy
+ (id)proxyWithTarget:(id)target connection:(NSConnection *)connection;
+ (id)proxyWithLocal:(id)target connection:(NSConnection *)connection;
- (instancetype)initWithTarget:(id)target connection:(NSConnection *)connection;
- (instancetype)initWithLocal:(id)target connection:(NSConnection *)connection;
- (void)setProtocolForProxy:(Protocol *)proto;
@property (readonly, retain) NSConnection *connectionForProxy;
@end

/* Passes on to its target only the messages its protocol names. */
@interface NSProtocolChecker : NSProxy
+ (instancetype)protocolCheckerWithTarget:(NSObject *)target protocol:(Protocol *)protocol;
- (instancetype)initWithTarget:(NSObject *)target protocol:(Protocol *)protocol;
@property (readonly) Protocol *protocol;
@property (readonly, retain) NSObject *target;
@end

#endif
