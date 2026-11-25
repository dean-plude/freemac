/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSAssertionHandler, and the garbage-collection calls that do nothing here
 * (freemac 1.219, Ferry 0.43.0). Written for freemac from Apple's public
 * documentation of NSAssertionHandler and NSGarbageCollector. */
#import "FInternal.h"

NSString *const NSAssertionHandlerKey = @"NSAssertionHandler";

/* "*** Assertion failure in -[Class method], file:line" goes to standard
 * error, then the exception is raised with the description as its reason. */
@implementation NSAssertionHandler
+ (NSAssertionHandler *)currentHandler
{
    NSMutableDictionary *d = [[NSThread currentThread] threadDictionary];
    NSAssertionHandler *h = [d objectForKey:NSAssertionHandlerKey];
    if (!h) {
        h = [[[NSAssertionHandler alloc] init] autorelease];
        [d setObject:h forKey:NSAssertionHandlerKey];
    }
    return h;
}
static NSString *base_name(NSString *file) { return [file lastPathComponent]; }
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)file lineNumber:(NSInteger)line
                  description:(NSString *)format, ...
{
    BOOL isClass = object && object_getClass(object) && class_isMetaClass(object_getClass(object));
    fflush(stdout);
    fprintf(stderr, "*** Assertion failure in %c[%s %s], %s:%ld\n", isClass ? '+' : '-',
            object ? class_getName(isClass ? (Class)object : [object class]) : "nil",
            selector ? sel_getName(selector) : "(null)", [base_name(file) UTF8String], (long)line);
    va_list ap;
    va_start(ap, format);
    NSString *reason = format ? FFormat(format, ap) : @"";
    va_end(ap);
    NSString *name = [format hasPrefix:@"Invalid parameter not satisfying"] ? NSInvalidArgumentException
                                                                             : NSInternalInconsistencyException;
    @throw [NSException exceptionWithName:name reason:reason userInfo:nil];
}
- (void)handleFailureInFunction:(NSString *)function file:(NSString *)file lineNumber:(NSInteger)line
                    description:(NSString *)format, ...
{
    fflush(stdout);
    fprintf(stderr, "*** Assertion failure in %s, %s:%ld\n", [function UTF8String], [base_name(file) UTF8String],
            (long)line);
    va_list ap;
    va_start(ap, format);
    NSString *reason = format ? FFormat(format, ap) : @"";
    va_end(ap);
    NSString *name = [format hasPrefix:@"Invalid parameter not satisfying"] ? NSInvalidArgumentException
                                                                             : NSInternalInconsistencyException;
    @throw [NSException exceptionWithName:name reason:reason userInfo:nil];
}
@end

@implementation NSGarbageCollector
+ (id)defaultCollector { return nil; }
- (BOOL)isCollecting { return NO; }
- (BOOL)isEnabled { return NO; }
- (void)disable {}
- (void)enable {}
- (void)collectIfNeeded {}
- (void)collectExhaustively {}
- (void)disableCollectorForPointer:(const void *)ptr {}
- (void)enableCollectorForPointer:(const void *)ptr {}
- (NSZone *)zone { return NULL; }
@end

id NSMakeCollectable(CFTypeRef cf) { return (id)cf; }
void *NSAllocateCollectable(NSUInteger size, NSUInteger options) { return calloc(1, size ? size : 1); }
void *NSReallocateCollectable(void *ptr, NSUInteger size, NSUInteger options) { return realloc(ptr, size ? size : 1); }
