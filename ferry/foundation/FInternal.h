/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: shared internals. Ferry's Foundation is our own code,
 * written from Apple's public API documentation; it is built as a Mach-O
 * library with ferry-cc and runs on Ferry's Objective-C runtime. Built
 * without ARC: memory is managed by hand, as in Apple's frameworks. */
#ifndef FERRY_FOUNDATION_INTERNAL_H
#define FERRY_FOUNDATION_INTERNAL_H
#include <Foundation/Foundation.h>
#include <objc/message.h>
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

/* Property lists */
id FParsePlist(NSData *data, NSPropertyListMutabilityOptions opt, NSPropertyListFormat *format);
NSData *FWriteXMLPlist(id plist);

/* Paths for Mac folders on freemac */
NSString *FHome(void);
NSString *FConfigHome(void);
NSString *FUserFolder(NSSearchPathDirectory dir);

/* Collections */
void FSortObjects(id *items, NSUInteger n, SEL selector);

@interface NSUserDefaults (FerryInternal)
- (NSString *)_ferryDomain; /* the application id the defaults are saved under */
@end

#endif
