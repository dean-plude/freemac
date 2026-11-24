/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Foundation, as far as Ferry's own Foundation provides it.
 * Written for freemac from Apple's public API documentation; not Apple's
 * header. Every class and call declared here is implemented in
 * ferry/foundation. */
#ifndef _FERRY_FOUNDATION_H_
#define _FERRY_FOUNDATION_H_
#include <stdarg.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <objc/NSObject.h>
#include <objc/NSObjCRuntime.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CGGeometry.h>

#ifndef NS_FORMAT_FUNCTION
#define NS_FORMAT_FUNCTION(F, A) __attribute__((format(__NSString__, F, A)))
#endif
#define NS_REQUIRES_NIL_TERMINATION __attribute__((sentinel(0, 1)))
#define NS_ENUM(type, name) enum name : type name; enum name : type
#define NS_OPTIONS(type, name) enum name : type name; enum name : type
#define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#define NS_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
#define NS_SWIFT_NAME(x)
#define NS_UNAVAILABLE __attribute__((unavailable))
#define NS_NOESCAPE __attribute__((noescape))
#define NS_RETURNS_INNER_POINTER __attribute__((objc_returns_inner_pointer))
#define FOUNDATION_EXPORT extern
#define FOUNDATION_EXTERN extern
#define NSNotFound ((NSInteger)__LONG_MAX__)

typedef double NSTimeInterval;
typedef unsigned short unichar;
typedef NSUInteger NSStringEncoding;

typedef struct _NSRange { NSUInteger location, length; } NSRange;
typedef NSRange *NSRangePointer;
static inline NSRange NSMakeRange(NSUInteger loc, NSUInteger len) { NSRange r = {loc, len}; return r; }
static inline NSUInteger NSMaxRange(NSRange r) { return r.location + r.length; }
static inline BOOL NSLocationInRange(NSUInteger loc, NSRange r) { return loc - r.location < r.length; }
static inline BOOL NSEqualRanges(NSRange a, NSRange b) { return a.location == b.location && a.length == b.length; }

/* ---- geometry (NSGeometry): the Core Graphics types, as on a 64-bit Mac ---- */

typedef CGPoint NSPoint;
typedef CGSize NSSize;
typedef CGRect NSRect;
typedef NSPoint *NSPointPointer;
typedef NSSize *NSSizePointer;
typedef NSRect *NSRectPointer;
typedef struct NSEdgeInsets { CGFloat top, left, bottom, right; } NSEdgeInsets;
typedef NS_ENUM(NSUInteger, NSRectEdge) {
    NSRectEdgeMinX = 0, NSRectEdgeMinY = 1, NSRectEdgeMaxX = 2, NSRectEdgeMaxY = 3,
    NSMinXEdge = 0, NSMinYEdge = 1, NSMaxXEdge = 2, NSMaxYEdge = 3,
};
extern const NSPoint NSZeroPoint;
extern const NSSize NSZeroSize;
extern const NSRect NSZeroRect;
extern const NSEdgeInsets NSEdgeInsetsZero;
static inline NSPoint NSMakePoint(CGFloat x, CGFloat y) { NSPoint p = {x, y}; return p; }
static inline NSSize NSMakeSize(CGFloat w, CGFloat h) { NSSize s = {w, h}; return s; }
static inline NSRect NSMakeRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { NSRect r = {{x, y}, {w, h}}; return r; }
static inline NSEdgeInsets NSEdgeInsetsMake(CGFloat t, CGFloat l, CGFloat b, CGFloat r)
{
    NSEdgeInsets e = {t, l, b, r};
    return e;
}
static inline CGFloat NSMinX(NSRect r) { return r.origin.x; }
static inline CGFloat NSMinY(NSRect r) { return r.origin.y; }
static inline CGFloat NSMaxX(NSRect r) { return r.origin.x + r.size.width; }
static inline CGFloat NSMaxY(NSRect r) { return r.origin.y + r.size.height; }
static inline CGFloat NSMidX(NSRect r) { return r.origin.x + r.size.width / 2; }
static inline CGFloat NSMidY(NSRect r) { return r.origin.y + r.size.height / 2; }
static inline CGFloat NSWidth(NSRect r) { return r.size.width; }
static inline CGFloat NSHeight(NSRect r) { return r.size.height; }
static inline NSRect NSRectFromCGRect(CGRect r) { return r; }
static inline CGRect NSRectToCGRect(NSRect r) { return r; }
static inline NSPoint NSPointFromCGPoint(CGPoint p) { return p; }
static inline CGPoint NSPointToCGPoint(NSPoint p) { return p; }
static inline NSSize NSSizeFromCGSize(CGSize s) { return s; }
static inline CGSize NSSizeToCGSize(NSSize s) { return s; }
BOOL NSEqualPoints(NSPoint a, NSPoint b);
BOOL NSEqualSizes(NSSize a, NSSize b);
BOOL NSEqualRects(NSRect a, NSRect b);
BOOL NSIsEmptyRect(NSRect r);
NSRect NSInsetRect(NSRect r, CGFloat dx, CGFloat dy);
NSRect NSIntegralRect(NSRect r);
NSRect NSUnionRect(NSRect a, NSRect b);
NSRect NSIntersectionRect(NSRect a, NSRect b);
NSRect NSOffsetRect(NSRect r, CGFloat dx, CGFloat dy);
void NSDivideRect(NSRect r, NSRect *slice, NSRect *remainder, CGFloat amount, NSRectEdge edge);
BOOL NSPointInRect(NSPoint p, NSRect r);
BOOL NSMouseInRect(NSPoint p, NSRect r, BOOL flipped);
BOOL NSContainsRect(NSRect a, NSRect b);
BOOL NSIntersectsRect(NSRect a, NSRect b);

typedef NS_ENUM(NSInteger, NSComparisonResult) {
    NSOrderedAscending = -1, NSOrderedSame = 0, NSOrderedDescending = 1
};
typedef NSComparisonResult (^NSComparator)(id obj1, id obj2);

enum {
    NSASCIIStringEncoding = 1,
    NSUTF8StringEncoding = 4,
    NSISOLatin1StringEncoding = 5,
    NSUnicodeStringEncoding = 10,
    NSUTF16StringEncoding = 10,
};

typedef NS_OPTIONS(NSUInteger, NSStringCompareOptions) {
    NSCaseInsensitiveSearch = 1,
    NSLiteralSearch = 2,
    NSBackwardsSearch = 4,
    NSAnchoredSearch = 8,
    NSNumericSearch = 64,
};

typedef NS_OPTIONS(NSUInteger, NSEnumerationOptions) {
    NSEnumerationConcurrent = 1, NSEnumerationReverse = 2
};

@class NSString, NSData, NSURL, NSError, NSDate, NSNumber, NSCharacterSet;
@class NSArray<ObjectType>, NSDictionary<KeyType, ObjectType>, NSEnumerator<ObjectType>;

/* ---- protocols ------------------------------------------------------------ */

@protocol NSCopying
- (id)copyWithZone:(NSZone *)zone;
@end

@protocol NSMutableCopying
- (id)mutableCopyWithZone:(NSZone *)zone;
@end

@class NSCoder;
@protocol NSCoding
- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
@end

@protocol NSSecureCoding <NSCoding>
@property (class, readonly) BOOL supportsSecureCoding;
@end

typedef struct {
    unsigned long state;
    id __unsafe_unretained *itemsPtr;
    unsigned long *mutationsPtr;
    unsigned long extra[5];
} NSFastEnumerationState;

@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained[])buffer
                                    count:(NSUInteger)len;
@end

/* ---- NSObject additions ------------------------------------------------------ */

/* Moving objects between Core Foundation and Objective-C ownership. */
#if __has_feature(objc_arc)
static inline id CFBridgingRelease(CFTypeRef X) { return (__bridge_transfer id)X; }
static inline CFTypeRef CFBridgingRetain(id X) { return (__bridge_retained CFTypeRef)X; }
#else
static inline id CFBridgingRelease(CFTypeRef X) { return [(id)X autorelease]; }
static inline CFTypeRef CFBridgingRetain(id X) { return (CFTypeRef)[X retain]; }
#endif

@interface NSObject (NSObjectFoundation)
- (NSString *)description;
- (NSString *)debugDescription;
+ (NSString *)description;
@property (readonly, copy) NSString *className;
@end

/* Key-value coding: getters, setters and instance variables by name, as
 * Apple's guide orders the search; scalars and NSPoint, NSSize, NSRect and
 * NSRange are boxed. Arrays and sets answer the collection operators in key
 * paths (@count, @sum, @avg, @min, @max, @unionOfObjects,
 * @distinctUnionOfObjects, @unionOfArrays, @distinctUnionOfArrays and
 * @distinctUnionOfSets). */
@class NSIndexSet, NSSet, NSMutableSet, NSDictionary, NSMutableArray, NSError;
@interface NSObject (NSKeyValueCoding)
@property (class, readonly) BOOL accessInstanceVariablesDirectly;
- (id)valueForKey:(NSString *)key;
- (void)setValue:(id)value forKey:(NSString *)key;
- (id)valueForKeyPath:(NSString *)keyPath;
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath;
- (id)valueForUndefinedKey:(NSString *)key;
- (void)setValue:(id)value forUndefinedKey:(NSString *)key;
- (void)setNilValueForKey:(NSString *)key;
- (BOOL)validateValue:(id *)value forKey:(NSString *)key error:(NSError **)error;
- (BOOL)validateValue:(id *)value forKeyPath:(NSString *)keyPath error:(NSError **)error;
- (NSMutableArray *)mutableArrayValueForKey:(NSString *)key;
- (NSMutableArray *)mutableArrayValueForKeyPath:(NSString *)keyPath;
- (NSMutableSet *)mutableSetValueForKey:(NSString *)key;
- (NSMutableSet *)mutableSetValueForKeyPath:(NSString *)keyPath;
- (NSDictionary *)dictionaryWithValuesForKeys:(NSArray *)keys;
- (void)setValuesForKeysWithDictionary:(NSDictionary *)keyedValues;
@end

/* Key-value observing: observers hear of changes the object announces
 * (will/didChangeValueForKey:), that its setters make (through a hidden
 * subclass, as on a Mac) and that setValue:forKey: makes. */
typedef NS_OPTIONS(NSUInteger, NSKeyValueObservingOptions) {
    NSKeyValueObservingOptionNew = 0x01, NSKeyValueObservingOptionOld = 0x02,
    NSKeyValueObservingOptionInitial = 0x04, NSKeyValueObservingOptionPrior = 0x08,
};
typedef NS_ENUM(NSUInteger, NSKeyValueChange) {
    NSKeyValueChangeSetting = 1, NSKeyValueChangeInsertion = 2, NSKeyValueChangeRemoval = 3,
    NSKeyValueChangeReplacement = 4,
};
typedef NS_ENUM(NSUInteger, NSKeyValueSetMutationKind) {
    NSKeyValueUnionSetMutation = 1, NSKeyValueMinusSetMutation = 2, NSKeyValueIntersectSetMutation = 3,
    NSKeyValueSetSetMutation = 4,
};
FOUNDATION_EXPORT NSString *const NSKeyValueChangeKindKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeNewKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeOldKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeIndexesKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeNotificationIsPriorKey;
@interface NSObject (NSKeyValueObserverRegistration)
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options context:(void *)context;
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context;
@end
@interface NSObject (NSKeyValueObserving)
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context;
- (void)willChangeValueForKey:(NSString *)key;
- (void)didChangeValueForKey:(NSString *)key;
- (void)willChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key;
- (void)didChange:(NSKeyValueChange)kind valuesAtIndexes:(NSIndexSet *)indexes forKey:(NSString *)key;
- (void)willChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutation
                 usingObjects:(NSSet *)objects;
- (void)didChangeValueForKey:(NSString *)key withSetMutation:(NSKeyValueSetMutationKind)mutation
                usingObjects:(NSSet *)objects;
+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key;
@property void *observationInfo;
@end

/* Comparison by isEqual: and compare:, as scripting and predicates use them */
@interface NSObject (NSComparisonMethods)
- (BOOL)isEqualTo:(id)object;
- (BOOL)isNotEqualTo:(id)object;
- (BOOL)isLessThan:(id)object;
- (BOOL)isLessThanOrEqualTo:(id)object;
- (BOOL)isGreaterThan:(id)object;
- (BOOL)isGreaterThanOrEqualTo:(id)object;
@end

@interface NSObject (NSDelayedPerforming)
- (void)performSelector:(SEL)aSelector withObject:(id)arg afterDelay:(NSTimeInterval)delay;
- (void)performSelector:(SEL)aSelector withObject:(id)arg afterDelay:(NSTimeInterval)delay inModes:(NSArray *)modes;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)target;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)target selector:(SEL)aSelector object:(id)arg;
- (void)performSelectorOnMainThread:(SEL)aSelector withObject:(id)arg waitUntilDone:(BOOL)wait;
@end

@interface NSNull : NSObject <NSCopying, NSSecureCoding>
+ (NSNull *)null;
@end

@protocol NSObject;

/* ---- NSString ------------------------------------------------------------------ */

@interface NSString : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>
@property (readonly) NSUInteger length;
- (unichar)characterAtIndex:(NSUInteger)index;
- (void)getCharacters:(unichar *)buffer range:(NSRange)range;
+ (instancetype)string;
+ (instancetype)stringWithString:(NSString *)string;
+ (instancetype)stringWithUTF8String:(const char *)s;
+ (instancetype)stringWithCString:(const char *)s encoding:(NSStringEncoding)enc;
+ (instancetype)stringWithCharacters:(const unichar *)chars length:(NSUInteger)length;
+ (instancetype)stringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (instancetype)stringWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
+ (instancetype)stringWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding)enc error:(NSError **)error;
- (instancetype)init;
- (instancetype)initWithString:(NSString *)string;
- (instancetype)initWithUTF8String:(const char *)s;
- (instancetype)initWithCString:(const char *)s encoding:(NSStringEncoding)enc;
- (instancetype)initWithCharacters:(const unichar *)chars length:(NSUInteger)length;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)len encoding:(NSStringEncoding)enc;
- (instancetype)initWithData:(NSData *)data encoding:(NSStringEncoding)enc;
- (instancetype)initWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)args NS_FORMAT_FUNCTION(1, 0);
+ (instancetype)stringWithContentsOfFile:(NSString *)path usedEncoding:(NSStringEncoding *)enc error:(NSError **)error;
- (instancetype)initWithContentsOfFile:(NSString *)path encoding:(NSStringEncoding)enc error:(NSError **)error;
@property (readonly) const char *UTF8String NS_RETURNS_INNER_POINTER;
- (const char *)cStringUsingEncoding:(NSStringEncoding)enc NS_RETURNS_INNER_POINTER;
- (BOOL)getCString:(char *)buffer maxLength:(NSUInteger)max encoding:(NSStringEncoding)enc;
- (NSUInteger)lengthOfBytesUsingEncoding:(NSStringEncoding)enc;
- (NSData *)dataUsingEncoding:(NSStringEncoding)enc;
- (BOOL)isEqualToString:(NSString *)other;
- (NSComparisonResult)compare:(NSString *)other;
- (NSComparisonResult)compare:(NSString *)other options:(NSStringCompareOptions)mask;
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)other;
- (NSComparisonResult)localizedCompare:(NSString *)other;
- (NSComparisonResult)localizedCaseInsensitiveCompare:(NSString *)other;
- (BOOL)hasPrefix:(NSString *)s;
- (BOOL)hasSuffix:(NSString *)s;
- (BOOL)containsString:(NSString *)s;
- (NSRange)rangeOfString:(NSString *)s;
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)mask;
- (NSRange)rangeOfString:(NSString *)s options:(NSStringCompareOptions)mask range:(NSRange)range;
- (NSRange)rangeOfCharacterFromSet:(NSCharacterSet *)set;
- (NSString *)substringFromIndex:(NSUInteger)from;
- (NSString *)substringToIndex:(NSUInteger)to;
- (NSString *)substringWithRange:(NSRange)range;
- (NSString *)stringByAppendingString:(NSString *)s;
- (NSString *)stringByAppendingFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target withString:(NSString *)replacement;
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSString *)stringByPaddingToLength:(NSUInteger)len withString:(NSString *)pad startingAtIndex:(NSUInteger)i;
- (NSArray<NSString *> *)componentsSeparatedByString:(NSString *)separator;
- (NSArray<NSString *> *)componentsSeparatedByCharactersInSet:(NSCharacterSet *)set;
@property (readonly, copy) NSString *uppercaseString;
@property (readonly, copy) NSString *lowercaseString;
@property (readonly, copy) NSString *capitalizedString;
@property (readonly) int intValue;
@property (readonly) NSInteger integerValue;
@property (readonly) long long longLongValue;
@property (readonly) double doubleValue;
@property (readonly) float floatValue;
@property (readonly) BOOL boolValue;
- (void)enumerateLinesUsingBlock:(void (^)(NSString *line, BOOL *stop))block;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically encoding:(NSStringEncoding)enc error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically encoding:(NSStringEncoding)enc error:(NSError **)error;
/* paths */
+ (NSString *)pathWithComponents:(NSArray<NSString *> *)components;
@property (readonly, copy) NSArray<NSString *> *pathComponents;
@property (readonly, copy) NSString *lastPathComponent;
@property (readonly, copy) NSString *pathExtension;
@property (readonly, copy) NSString *stringByDeletingLastPathComponent;
@property (readonly, copy) NSString *stringByDeletingPathExtension;
@property (readonly, copy) NSString *stringByExpandingTildeInPath;
@property (readonly, copy) NSString *stringByAbbreviatingWithTildeInPath;
@property (readonly, copy) NSString *stringByStandardizingPath;
@property (readonly) BOOL isAbsolutePath;
@property (readonly) const char *fileSystemRepresentation NS_RETURNS_INNER_POINTER;
- (NSString *)stringByAppendingPathComponent:(NSString *)component;
- (NSString *)stringByAppendingPathExtension:(NSString *)ext;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)appendString:(NSString *)s;
- (void)appendFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)setString:(NSString *)s;
- (void)insertString:(NSString *)s atIndex:(NSUInteger)index;
- (void)deleteCharactersInRange:(NSRange)range;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)s;
- (NSUInteger)replaceOccurrencesOfString:(NSString *)target withString:(NSString *)replacement
                                 options:(NSStringCompareOptions)options range:(NSRange)range;
@end

@interface NSCharacterSet : NSObject <NSCopying>
+ (NSCharacterSet *)whitespaceCharacterSet;
+ (NSCharacterSet *)whitespaceAndNewlineCharacterSet;
+ (NSCharacterSet *)newlineCharacterSet;
+ (NSCharacterSet *)decimalDigitCharacterSet;
+ (NSCharacterSet *)letterCharacterSet;
+ (NSCharacterSet *)alphanumericCharacterSet;
+ (NSCharacterSet *)punctuationCharacterSet;
+ (NSCharacterSet *)characterSetWithCharactersInString:(NSString *)s;
- (BOOL)characterIsMember:(unichar)c;
@property (readonly, copy) NSCharacterSet *invertedSet;
@end

/* ---- NSValue and NSNumber --------------------------------------------------------- */

@interface NSValue : NSObject <NSCopying, NSSecureCoding>
+ (NSValue *)valueWithRange:(NSRange)range;
+ (NSValue *)valueWithPointer:(const void *)pointer;
+ (NSValue *)valueWithNonretainedObject:(id)object;
+ (NSValue *)valueWithPoint:(NSPoint)point;
+ (NSValue *)valueWithSize:(NSSize)size;
+ (NSValue *)valueWithRect:(NSRect)rect;
+ (NSValue *)valueWithEdgeInsets:(NSEdgeInsets)insets;
@property (readonly) NSRange rangeValue;
@property (readonly) NSPoint pointValue;
@property (readonly) NSSize sizeValue;
@property (readonly) NSRect rectValue;
@property (readonly) NSEdgeInsets edgeInsetsValue;
@property (readonly) void *pointerValue;
@property (readonly) id nonretainedObjectValue;
@property (readonly) const char *objCType NS_RETURNS_INNER_POINTER;
@end

@interface NSNumber : NSValue
+ (NSNumber *)numberWithChar:(char)v;
+ (NSNumber *)numberWithUnsignedChar:(unsigned char)v;
+ (NSNumber *)numberWithShort:(short)v;
+ (NSNumber *)numberWithUnsignedShort:(unsigned short)v;
+ (NSNumber *)numberWithInt:(int)v;
+ (NSNumber *)numberWithUnsignedInt:(unsigned int)v;
+ (NSNumber *)numberWithLong:(long)v;
+ (NSNumber *)numberWithUnsignedLong:(unsigned long)v;
+ (NSNumber *)numberWithLongLong:(long long)v;
+ (NSNumber *)numberWithUnsignedLongLong:(unsigned long long)v;
+ (NSNumber *)numberWithFloat:(float)v;
+ (NSNumber *)numberWithDouble:(double)v;
+ (NSNumber *)numberWithBool:(BOOL)v;
+ (NSNumber *)numberWithInteger:(NSInteger)v;
+ (NSNumber *)numberWithUnsignedInteger:(NSUInteger)v;
- (instancetype)initWithInt:(int)v;
- (instancetype)initWithInteger:(NSInteger)v;
- (instancetype)initWithDouble:(double)v;
- (instancetype)initWithBool:(BOOL)v;
@property (readonly) char charValue;
@property (readonly) unsigned char unsignedCharValue;
@property (readonly) short shortValue;
@property (readonly) unsigned short unsignedShortValue;
@property (readonly) int intValue;
@property (readonly) unsigned int unsignedIntValue;
@property (readonly) long longValue;
@property (readonly) unsigned long unsignedLongValue;
@property (readonly) long long longLongValue;
@property (readonly) unsigned long long unsignedLongLongValue;
@property (readonly) float floatValue;
@property (readonly) double doubleValue;
@property (readonly) BOOL boolValue;
@property (readonly) NSInteger integerValue;
@property (readonly) NSUInteger unsignedIntegerValue;
@property (readonly, copy) NSString *stringValue;
@property (readonly) const char *objCType NS_RETURNS_INNER_POINTER;
- (NSComparisonResult)compare:(NSNumber *)other;
- (BOOL)isEqualToNumber:(NSNumber *)number;
@end

/* ---- collections -------------------------------------------------------------------- */

@interface NSEnumerator<ObjectType> : NSObject <NSFastEnumeration>
- (ObjectType)nextObject;
@property (readonly, copy) NSArray<ObjectType> *allObjects;
@end

@interface NSArray<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration, NSSecureCoding>
@property (readonly) NSUInteger count;
- (ObjectType)objectAtIndex:(NSUInteger)index;
+ (instancetype)array;
+ (instancetype)arrayWithObject:(ObjectType)obj;
+ (instancetype)arrayWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)arrayWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
+ (instancetype)arrayWithArray:(NSArray<ObjectType> *)array;
+ (NSArray<ObjectType> *)arrayWithContentsOfFile:(NSString *)path;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (instancetype)initWithContentsOfURL:(NSURL *)url;
- (instancetype)init;
- (instancetype)initWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
- (instancetype)initWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
- (instancetype)initWithArray:(NSArray<ObjectType> *)array;
- (ObjectType)objectAtIndexedSubscript:(NSUInteger)index;
- (void)getObjects:(ObjectType __unsafe_unretained[])objects range:(NSRange)range;
@property (readonly) ObjectType firstObject;
@property (readonly) ObjectType lastObject;
- (BOOL)containsObject:(ObjectType)obj;
- (NSUInteger)indexOfObject:(ObjectType)obj;
- (NSUInteger)indexOfObjectIdenticalTo:(ObjectType)obj;
- (NSUInteger)indexOfObjectPassingTest:(BOOL (^)(ObjectType obj, NSUInteger idx, BOOL *stop))predicate;
- (BOOL)isEqualToArray:(NSArray<ObjectType> *)other;
- (NSArray<ObjectType> *)arrayByAddingObject:(ObjectType)obj;
- (NSArray<ObjectType> *)arrayByAddingObjectsFromArray:(NSArray<ObjectType> *)other;
- (NSArray<ObjectType> *)subarrayWithRange:(NSRange)range;
- (NSString *)componentsJoinedByString:(NSString *)separator;
- (NSArray<ObjectType> *)sortedArrayUsingSelector:(SEL)comparator;
- (NSArray<ObjectType> *)sortedArrayUsingComparator:(NSComparator)cmptr;
- (NSArray<ObjectType> *)sortedArrayUsingFunction:(NSInteger (*)(ObjectType, ObjectType, void *))fn context:(void *)ctx;
- (NSArray<ObjectType> *)filteredArrayUsingBlock:(BOOL (^)(ObjectType obj))predicate;
- (void)makeObjectsPerformSelector:(SEL)sel;
- (void)makeObjectsPerformSelector:(SEL)sel withObject:(id)arg;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
- (void)enumerateObjectsWithOptions:(NSEnumerationOptions)opts
                         usingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (NSEnumerator<ObjectType> *)reverseObjectEnumerator;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
+ (instancetype)arrayWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)obj;
- (void)insertObject:(ObjectType)obj atIndex:(NSUInteger)index;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeLastObject;
- (void)removeObject:(ObjectType)obj;
- (void)removeObjectIdenticalTo:(ObjectType)obj;
- (void)removeAllObjects;
- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(ObjectType)obj;
- (void)setObject:(ObjectType)obj atIndexedSubscript:(NSUInteger)index;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)removeObjectsInArray:(NSArray<ObjectType> *)array;
- (void)removeObjectsInRange:(NSRange)range;
- (void)setArray:(NSArray<ObjectType> *)array;
- (void)exchangeObjectAtIndex:(NSUInteger)a withObjectAtIndex:(NSUInteger)b;
- (void)sortUsingSelector:(SEL)comparator;
- (void)sortUsingComparator:(NSComparator)cmptr;
@end

@interface NSDictionary<__covariant KeyType, __covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration, NSSecureCoding>
@property (readonly) NSUInteger count;
- (ObjectType)objectForKey:(KeyType)key;
- (NSEnumerator<KeyType> *)keyEnumerator;
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithObject:(ObjectType)object forKey:(KeyType<NSCopying>)key;
+ (instancetype)dictionaryWithObjects:(const ObjectType[])objects forKeys:(const KeyType<NSCopying>[])keys
                                count:(NSUInteger)count;
+ (instancetype)dictionaryWithObjectsAndKeys:(id)first, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)dictionaryWithDictionary:(NSDictionary<KeyType, ObjectType> *)dict;
+ (instancetype)dictionaryWithObjects:(NSArray<ObjectType> *)objects forKeys:(NSArray<KeyType> *)keys;
+ (NSDictionary<KeyType, ObjectType> *)dictionaryWithContentsOfFile:(NSString *)path;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (instancetype)initWithContentsOfURL:(NSURL *)url;
- (instancetype)init;
- (instancetype)initWithObjects:(const ObjectType[])objects forKeys:(const KeyType<NSCopying>[])keys
                          count:(NSUInteger)count;
- (instancetype)initWithDictionary:(NSDictionary<KeyType, ObjectType> *)dict;
- (instancetype)initWithObjectsAndKeys:(id)first, ... NS_REQUIRES_NIL_TERMINATION;
- (ObjectType)objectForKeyedSubscript:(KeyType)key;
- (ObjectType)valueForKey:(NSString *)key;
@property (readonly, copy) NSArray<KeyType> *allKeys;
@property (readonly, copy) NSArray<ObjectType> *allValues;
- (NSArray<KeyType> *)allKeysForObject:(ObjectType)obj;
- (NSArray<KeyType> *)keysSortedByValueUsingSelector:(SEL)comparator;
- (BOOL)isEqualToDictionary:(NSDictionary<KeyType, ObjectType> *)other;
- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(KeyType key, ObjectType obj, BOOL *stop))block;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically;
@end

@interface NSMutableDictionary<KeyType, ObjectType> : NSDictionary<KeyType, ObjectType>
+ (instancetype)dictionaryWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (void)setObject:(ObjectType)object forKey:(KeyType<NSCopying>)key;
- (void)setObject:(ObjectType)object forKeyedSubscript:(KeyType<NSCopying>)key;
- (void)setValue:(ObjectType)value forKey:(NSString *)key;
- (void)removeObjectForKey:(KeyType)key;
- (void)removeObjectsForKeys:(NSArray<KeyType> *)keys;
- (void)removeAllObjects;
- (void)addEntriesFromDictionary:(NSDictionary<KeyType, ObjectType> *)other;
- (void)setDictionary:(NSDictionary<KeyType, ObjectType> *)other;
@end

@interface NSSet<__covariant ObjectType> : NSObject <NSCopying, NSMutableCopying, NSFastEnumeration, NSSecureCoding>
@property (readonly) NSUInteger count;
+ (instancetype)set;
+ (instancetype)setWithObject:(ObjectType)obj;
+ (instancetype)setWithObjects:(ObjectType)first, ... NS_REQUIRES_NIL_TERMINATION;
+ (instancetype)setWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
+ (instancetype)setWithArray:(NSArray<ObjectType> *)array;
+ (instancetype)setWithSet:(NSSet<ObjectType> *)set;
- (instancetype)initWithObjects:(const ObjectType[])objects count:(NSUInteger)count;
- (BOOL)containsObject:(ObjectType)obj;
- (ObjectType)member:(ObjectType)obj;
- (ObjectType)anyObject;
@property (readonly, copy) NSArray<ObjectType> *allObjects;
- (NSEnumerator<ObjectType> *)objectEnumerator;
- (BOOL)isSubsetOfSet:(NSSet<ObjectType> *)other;
- (BOOL)isEqualToSet:(NSSet<ObjectType> *)other;
- (BOOL)intersectsSet:(NSSet<ObjectType> *)other;
- (NSSet<ObjectType> *)setByAddingObject:(ObjectType)obj;
- (NSSet<ObjectType> *)setByAddingObjectsFromSet:(NSSet<ObjectType> *)other;
- (NSSet<ObjectType> *)setByAddingObjectsFromArray:(NSArray<ObjectType> *)other;
@end

@interface NSMutableSet<ObjectType> : NSSet<ObjectType>
+ (instancetype)setWithCapacity:(NSUInteger)capacity;
- (void)addObject:(ObjectType)obj;
- (void)removeObject:(ObjectType)obj;
- (void)removeAllObjects;
- (void)addObjectsFromArray:(NSArray<ObjectType> *)array;
- (void)unionSet:(NSSet<ObjectType> *)other;
- (void)minusSet:(NSSet<ObjectType> *)other;
- (void)intersectSet:(NSSet<ObjectType> *)other;
- (void)setSet:(NSSet<ObjectType> *)other;
@end

/* Index sets: sorted, non-overlapping ranges of indexes (a table's selection). */
NSRange NSIntersectionRange(NSRange a, NSRange b);
NSRange NSUnionRange(NSRange a, NSRange b);
@interface NSIndexSet : NSObject <NSCopying, NSMutableCopying>
+ (instancetype)indexSet;
+ (instancetype)indexSetWithIndex:(NSUInteger)index;
+ (instancetype)indexSetWithIndexesInRange:(NSRange)range;
- (instancetype)init;
- (instancetype)initWithIndex:(NSUInteger)index;
- (instancetype)initWithIndexesInRange:(NSRange)range;
- (instancetype)initWithIndexSet:(NSIndexSet *)indexSet;
@property (readonly) NSUInteger count;
@property (readonly) NSUInteger firstIndex, lastIndex;
- (BOOL)containsIndex:(NSUInteger)index;
- (BOOL)containsIndexesInRange:(NSRange)range;
- (BOOL)containsIndexes:(NSIndexSet *)indexSet;
- (BOOL)intersectsIndexesInRange:(NSRange)range;
- (NSUInteger)countOfIndexesInRange:(NSRange)range;
- (NSUInteger)indexGreaterThanIndex:(NSUInteger)value;
- (NSUInteger)indexLessThanIndex:(NSUInteger)value;
- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)value;
- (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)value;
- (NSUInteger)getIndexes:(NSUInteger *)buffer maxCount:(NSUInteger)max inIndexRange:(NSRangePointer)range;
- (BOOL)isEqualToIndexSet:(NSIndexSet *)indexSet;
- (void)enumerateIndexesUsingBlock:(void (^)(NSUInteger idx, BOOL *stop))block;
- (void)enumerateIndexesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSUInteger idx, BOOL *stop))block;
- (void)enumerateRangesUsingBlock:(void (^)(NSRange range, BOOL *stop))block;
- (void)enumerateRangesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (^)(NSRange range, BOOL *stop))block;
- (NSUInteger)indexPassingTest:(BOOL (^)(NSUInteger idx, BOOL *stop))predicate;
- (NSIndexSet *)indexesPassingTest:(BOOL (^)(NSUInteger idx, BOOL *stop))predicate;
@end
@interface NSMutableIndexSet : NSIndexSet
- (void)addIndex:(NSUInteger)index;
- (void)addIndexes:(NSIndexSet *)indexSet;
- (void)addIndexesInRange:(NSRange)range;
- (void)removeIndex:(NSUInteger)index;
- (void)removeIndexes:(NSIndexSet *)indexSet;
- (void)removeIndexesInRange:(NSRange)range;
- (void)removeAllIndexes;
- (void)shiftIndexesStartingAtIndex:(NSUInteger)index by:(NSInteger)delta;
@end
@interface NSArray<ObjectType> (NSIndexSetAccess)
- (NSArray<ObjectType> *)objectsAtIndexes:(NSIndexSet *)indexes;
- (NSIndexSet *)indexesOfObjectsPassingTest:(BOOL (^)(ObjectType obj, NSUInteger idx, BOOL *stop))predicate;
- (void)enumerateObjectsAtIndexes:(NSIndexSet *)indexes options:(NSEnumerationOptions)opts
                       usingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;
@end
@interface NSMutableArray<ObjectType> (NSIndexSetAccess)
- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes;
- (void)insertObjects:(NSArray<ObjectType> *)objects atIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectsAtIndexes:(NSIndexSet *)indexes withObjects:(NSArray<ObjectType> *)objects;
@end

/* Sort descriptors: compare objects by the value at a key path. */
@interface NSSortDescriptor : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending;
+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector;
+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)cmptr;
- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending;
- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector;
- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)cmptr;
@property (readonly, copy) NSString *key;
@property (readonly) BOOL ascending;
@property (readonly) SEL selector;
@property (readonly) NSComparator comparator;
@property (readonly, retain) id reversedSortDescriptor;
- (NSComparisonResult)compareObject:(id)object1 toObject:(id)object2;
@end
@interface NSArray<ObjectType> (NSSortDescriptorSorting)
- (NSArray<ObjectType> *)sortedArrayUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;
@end
@interface NSMutableArray<ObjectType> (NSSortDescriptorSorting)
- (void)sortUsingDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors;
@end

/* Predicates (Ferry 0.18.0, a subset): comparisons of key paths and
 * constants (==, !=, <, <=, >, >=, BETWEEN, IN, CONTAINS, BEGINSWITH,
 * ENDSWITH and LIKE, with [c], [d] and [cd]), ANY, ALL and NONE, AND, OR and NOT,
 * TRUEPREDICATE and FALSEPREDICATE, the format arguments %@, %K, %d, %i,
 * %ld, %lu, %f and %s, $variables, and blocks. */
@interface NSPredicate : NSObject <NSCopying>
+ (NSPredicate *)predicateWithFormat:(NSString *)format, ...;
+ (NSPredicate *)predicateWithFormat:(NSString *)format argumentArray:(NSArray *)arguments;
+ (NSPredicate *)predicateWithFormat:(NSString *)format arguments:(va_list)args;
+ (NSPredicate *)predicateWithValue:(BOOL)value;
+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id evaluatedObject, NSDictionary *bindings))block;
@property (readonly, copy) NSString *predicateFormat;
- (BOOL)evaluateWithObject:(id)object;
- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings;
- (instancetype)predicateWithSubstitutionVariables:(NSDictionary *)variables;
@end
typedef NS_ENUM(NSUInteger, NSCompoundPredicateType) {
    NSNotPredicateType = 0, NSAndPredicateType, NSOrPredicateType,
};
@interface NSCompoundPredicate : NSPredicate
- (instancetype)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray<NSPredicate *> *)subpredicates;
+ (NSCompoundPredicate *)andPredicateWithSubpredicates:(NSArray<NSPredicate *> *)subpredicates;
+ (NSCompoundPredicate *)orPredicateWithSubpredicates:(NSArray<NSPredicate *> *)subpredicates;
+ (NSCompoundPredicate *)notPredicateWithSubpredicate:(NSPredicate *)predicate;
@property (readonly) NSCompoundPredicateType compoundPredicateType;
@property (readonly, copy) NSArray *subpredicates;
@end
@interface NSArray<ObjectType> (NSPredicateSupport)
- (NSArray<ObjectType> *)filteredArrayUsingPredicate:(NSPredicate *)predicate;
@end
@interface NSMutableArray<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate;
@end
@interface NSSet<ObjectType> (NSPredicateSupport)
- (NSSet<ObjectType> *)filteredSetUsingPredicate:(NSPredicate *)predicate;
@end
@interface NSMutableSet<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate;
@end

/* ---- NSData ------------------------------------------------------------------------- */

typedef NS_OPTIONS(NSUInteger, NSDataWritingOptions) { NSDataWritingAtomic = 1 };

@interface NSData : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>
@property (readonly) NSUInteger length;
@property (readonly) const void *bytes NS_RETURNS_INNER_POINTER;
+ (instancetype)data;
+ (instancetype)dataWithBytes:(const void *)bytes length:(NSUInteger)length;
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length;
+ (instancetype)dataWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b;
+ (instancetype)dataWithContentsOfFile:(NSString *)path;
+ (instancetype)dataWithContentsOfFile:(NSString *)path options:(NSUInteger)opts error:(NSError **)error;
+ (instancetype)dataWithContentsOfURL:(NSURL *)url;
+ (instancetype)dataWithData:(NSData *)data;
- (instancetype)initWithBytes:(const void *)bytes length:(NSUInteger)length;
- (instancetype)initWithBytesNoCopy:(void *)bytes length:(NSUInteger)length freeWhenDone:(BOOL)b;
- (instancetype)initWithContentsOfFile:(NSString *)path;
- (instancetype)initWithData:(NSData *)data;
- (void)getBytes:(void *)buffer length:(NSUInteger)length;
- (void)getBytes:(void *)buffer range:(NSRange)range;
- (NSData *)subdataWithRange:(NSRange)range;
- (NSRange)rangeOfData:(NSData *)data options:(NSUInteger)opts range:(NSRange)range;
- (NSString *)base64EncodedStringWithOptions:(NSUInteger)opts;
- (instancetype)initWithBase64EncodedString:(NSString *)string options:(NSUInteger)opts;
- (BOOL)isEqualToData:(NSData *)other;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically;
- (BOOL)writeToFile:(NSString *)path options:(NSDataWritingOptions)opts error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url atomically:(BOOL)atomically;
@end

@interface NSMutableData : NSData
@property (readonly) void *mutableBytes NS_RETURNS_INNER_POINTER;
@property NSUInteger length;
+ (instancetype)dataWithCapacity:(NSUInteger)capacity;
+ (instancetype)dataWithLength:(NSUInteger)length;
- (instancetype)initWithCapacity:(NSUInteger)capacity;
- (instancetype)initWithLength:(NSUInteger)length;
- (void)appendBytes:(const void *)bytes length:(NSUInteger)length;
- (void)appendData:(NSData *)data;
- (void)replaceBytesInRange:(NSRange)range withBytes:(const void *)bytes;
- (void)setData:(NSData *)data;
@end

/* ---- NSDate ------------------------------------------------------------------------- */

#define NSTimeIntervalSince1970 978307200.0

@interface NSDate : NSObject <NSCopying, NSSecureCoding>
@property (readonly) NSTimeInterval timeIntervalSinceReferenceDate;
+ (instancetype)date;
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)secs;
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)secs;
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs;
+ (instancetype)distantFuture;
+ (instancetype)distantPast;
+ (NSTimeInterval)timeIntervalSinceReferenceDate;
- (instancetype)init;
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secs;
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)secs;
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)secs;
@property (readonly) NSTimeInterval timeIntervalSince1970;
@property (readonly) NSTimeInterval timeIntervalSinceNow;
- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)other;
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)secs;
- (NSDate *)earlierDate:(NSDate *)other;
- (NSDate *)laterDate:(NSDate *)other;
- (NSComparisonResult)compare:(NSDate *)other;
- (BOOL)isEqualToDate:(NSDate *)other;
@end

/* ---- NSTimeZone, NSLocale (NSTimeZone.m) ------------------------------------------- */

/* Named zones come from this system's time zone database. NSLocale knows
 * identifiers only: Ferry formats everything in English (United States). */
@interface NSTimeZone : NSObject <NSCopying>
+ (NSTimeZone *)systemTimeZone;
+ (void)resetSystemTimeZone;
+ (NSTimeZone *)defaultTimeZone;
+ (void)setDefaultTimeZone:(NSTimeZone *)zone;
+ (NSTimeZone *)localTimeZone;
+ (NSArray *)knownTimeZoneNames;
+ (NSDictionary *)abbreviationDictionary;
+ (instancetype)timeZoneWithName:(NSString *)name;
+ (instancetype)timeZoneWithName:(NSString *)name data:(NSData *)data;
+ (instancetype)timeZoneForSecondsFromGMT:(NSInteger)seconds;
+ (instancetype)timeZoneWithAbbreviation:(NSString *)abbreviation;
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name data:(NSData *)data;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSData *data;
@property (readonly) NSInteger secondsFromGMT;
@property (readonly, copy) NSString *abbreviation;
@property (readonly, getter=isDaylightSavingTime) BOOL daylightSavingTime;
@property (readonly) NSTimeInterval daylightSavingTimeOffset;
@property (readonly, copy) NSDate *nextDaylightSavingTimeTransition;
- (NSInteger)secondsFromGMTForDate:(NSDate *)date;
- (NSString *)abbreviationForDate:(NSDate *)date;
- (BOOL)isDaylightSavingTimeForDate:(NSDate *)date;
- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)date;
- (NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)date;
- (BOOL)isEqualToTimeZone:(NSTimeZone *)other;
@end
FOUNDATION_EXPORT NSString *const NSSystemTimeZoneDidChangeNotification;

typedef NSString *NSLocaleKey;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleIdentifier;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleLanguageCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCountryCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleScriptCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleVariantCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleDecimalSeparator;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleGroupingSeparator;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleUsesMetricSystem;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCalendar;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCurrencyCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCurrencySymbol;
FOUNDATION_EXPORT NSString *const NSCurrentLocaleDidChangeNotification;

@interface NSLocale : NSObject <NSCopying>
+ (NSLocale *)currentLocale;
+ (NSLocale *)autoupdatingCurrentLocale;
+ (NSLocale *)systemLocale;
+ (instancetype)localeWithLocaleIdentifier:(NSString *)ident;
+ (NSArray *)availableLocaleIdentifiers;
+ (NSArray *)ISOLanguageCodes;
+ (NSArray *)preferredLanguages;
+ (NSDictionary *)componentsFromLocaleIdentifier:(NSString *)string;
+ (NSString *)canonicalLocaleIdentifierFromString:(NSString *)string;
- (instancetype)initWithLocaleIdentifier:(NSString *)string;
- (id)objectForKey:(NSLocaleKey)key;
- (NSString *)displayNameForKey:(NSLocaleKey)key value:(id)value;
@property (readonly, copy) NSString *localeIdentifier;
@property (readonly, copy) NSString *languageCode;
@property (readonly, copy) NSString *countryCode;
@property (readonly, copy) NSString *regionCode;
@property (readonly, copy) NSString *scriptCode;
@property (readonly, copy) NSString *variantCode;
@property (readonly, copy) NSString *decimalSeparator;
@property (readonly, copy) NSString *groupingSeparator;
@property (readonly) BOOL usesMetricSystem;
@property (readonly, copy) NSString *currencyCode;
@property (readonly, copy) NSString *currencySymbol;
@property (readonly, copy) NSString *calendarIdentifier;
@end

/* ---- NSFormatter, NSDateFormatter (NSDateFormatter.m) ------------------------------- */

@class NSCalendar;

@interface NSFormatter : NSObject <NSCopying>
- (NSString *)stringForObjectValue:(id)obj;
- (NSString *)editingStringForObjectValue:(id)obj;
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error;
- (BOOL)isPartialStringValid:(NSString *)partial newEditingString:(NSString **)newString
            errorDescription:(NSString **)error;
@end

typedef NS_ENUM(NSUInteger, NSDateFormatterStyle) {
    NSDateFormatterNoStyle = 0,
    NSDateFormatterShortStyle = 1,
    NSDateFormatterMediumStyle = 2,
    NSDateFormatterLongStyle = 3,
    NSDateFormatterFullStyle = 4,
};
typedef NS_ENUM(NSUInteger, NSDateFormatterBehavior) {
    NSDateFormatterBehaviorDefault = 0,
    NSDateFormatterBehavior10_0 = 1000,
    NSDateFormatterBehavior10_4 = 1040,
};

/* Patterns are Unicode date patterns (Unicode Technical Standard #35); text
 * is always English (United States), and the calendar is always Gregorian. */
@interface NSDateFormatter : NSFormatter
+ (NSString *)localizedStringFromDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)dstyle
                            timeStyle:(NSDateFormatterStyle)tstyle;
+ (NSString *)dateFormatFromTemplate:(NSString *)tmpl options:(NSUInteger)opts locale:(NSLocale *)locale;
+ (NSDateFormatterBehavior)defaultFormatterBehavior;
+ (void)setDefaultFormatterBehavior:(NSDateFormatterBehavior)behavior;
- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)range error:(NSError **)error;
- (void)setLocalizedDateFormatFromTemplate:(NSString *)tmpl;
@property (copy) NSString *dateFormat;
@property NSDateFormatterStyle dateStyle;
@property NSDateFormatterStyle timeStyle;
@property (copy) NSLocale *locale;
@property (copy) NSTimeZone *timeZone;
@property (getter=isLenient) BOOL lenient;
@property BOOL generatesCalendarDates;
@property BOOL doesRelativeDateFormatting;
@property NSDateFormatterBehavior formatterBehavior;
@property (copy) NSDate *defaultDate;
@property (copy) NSDate *twoDigitStartDate;
@property (copy) NSString *AMSymbol;
@property (copy) NSString *PMSymbol;
@property (copy) NSArray *eraSymbols;
@property (copy) NSArray *longEraSymbols;
@property (copy) NSArray *monthSymbols;
@property (copy) NSArray *shortMonthSymbols;
@property (copy) NSArray *veryShortMonthSymbols;
@property (copy) NSArray *standaloneMonthSymbols;
@property (copy) NSArray *shortStandaloneMonthSymbols;
@property (copy) NSArray *veryShortStandaloneMonthSymbols;
@property (copy) NSArray *weekdaySymbols;
@property (copy) NSArray *shortWeekdaySymbols;
@property (copy) NSArray *veryShortWeekdaySymbols;
@property (copy) NSArray *standaloneWeekdaySymbols;
@property (copy) NSArray *shortStandaloneWeekdaySymbols;
@property (copy) NSArray *veryShortStandaloneWeekdaySymbols;
@property (copy) NSArray *quarterSymbols;
@property (copy) NSArray *shortQuarterSymbols;
@property (copy) NSArray *standaloneQuarterSymbols;
@property (copy) NSArray *shortStandaloneQuarterSymbols;
@property (copy) NSCalendar *calendar;
@end

/* ---- NSCalendar, NSDateComponents (NSCalendar.m) ------------------------------------ */

/* The Gregorian calendar (proleptic: no Julian dates before 1582) and the
 * ISO 8601 one; other calendar identifiers give nil. */
typedef NSString *NSCalendarIdentifier;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierGregorian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierISO8601;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierBuddhist;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierChinese;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierCoptic;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteMihret;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteAlem;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierHebrew;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIndian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamic;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamicCivil;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamicTabular;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamicUmmAlQura;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierJapanese;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierPersian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierRepublicOfChina;
FOUNDATION_EXPORT NSString *const NSGregorianCalendar;
FOUNDATION_EXPORT NSString *const NSISO8601Calendar;
FOUNDATION_EXPORT NSString *const NSCalendarDayChangedNotification;

typedef NS_OPTIONS(NSUInteger, NSCalendarUnit) {
    NSCalendarUnitEra = 1UL << 1,
    NSCalendarUnitYear = 1UL << 2,
    NSCalendarUnitMonth = 1UL << 3,
    NSCalendarUnitDay = 1UL << 4,
    NSCalendarUnitHour = 1UL << 5,
    NSCalendarUnitMinute = 1UL << 6,
    NSCalendarUnitSecond = 1UL << 7,
    NSCalendarUnitWeekday = 1UL << 9,
    NSCalendarUnitWeekdayOrdinal = 1UL << 10,
    NSCalendarUnitQuarter = 1UL << 11,
    NSCalendarUnitWeekOfMonth = 1UL << 12,
    NSCalendarUnitWeekOfYear = 1UL << 13,
    NSCalendarUnitYearForWeekOfYear = 1UL << 14,
    NSCalendarUnitNanosecond = 1UL << 15,
    NSCalendarUnitDayOfYear = 1UL << 16,
    NSCalendarUnitCalendar = 1UL << 20,
    NSCalendarUnitTimeZone = 1UL << 21,
    /* the names of Mac OS X 10.4 to 10.9 */
    NSEraCalendarUnit = NSCalendarUnitEra,
    NSYearCalendarUnit = NSCalendarUnitYear,
    NSMonthCalendarUnit = NSCalendarUnitMonth,
    NSDayCalendarUnit = NSCalendarUnitDay,
    NSHourCalendarUnit = NSCalendarUnitHour,
    NSMinuteCalendarUnit = NSCalendarUnitMinute,
    NSSecondCalendarUnit = NSCalendarUnitSecond,
    NSWeekCalendarUnit = 1UL << 8,
    NSWeekdayCalendarUnit = NSCalendarUnitWeekday,
    NSWeekdayOrdinalCalendarUnit = NSCalendarUnitWeekdayOrdinal,
    NSQuarterCalendarUnit = NSCalendarUnitQuarter,
    NSWeekOfMonthCalendarUnit = NSCalendarUnitWeekOfMonth,
    NSWeekOfYearCalendarUnit = NSCalendarUnitWeekOfYear,
    NSYearForWeekOfYearCalendarUnit = NSCalendarUnitYearForWeekOfYear,
    NSCalendarCalendarUnit = NSCalendarUnitCalendar,
    NSTimeZoneCalendarUnit = NSCalendarUnitTimeZone,
};

typedef NS_OPTIONS(NSUInteger, NSCalendarOptions) {
    NSCalendarWrapComponents = 1UL << 0,
    NSCalendarMatchStrictly = 1UL << 1,
    NSCalendarSearchBackwards = 1UL << 2,
    NSCalendarMatchPreviousTimePreservingSmallerUnits = 1UL << 8,
    NSCalendarMatchNextTimePreservingSmallerUnits = 1UL << 9,
    NSCalendarMatchNextTime = 1UL << 10,
    NSCalendarMatchFirst = 1UL << 12,
    NSCalendarMatchLast = 1UL << 13,
};
enum { NSWrapCalendarComponents = NSCalendarWrapComponents };
enum { NSDateComponentUndefined = NSIntegerMax, NSUndefinedDateComponent = NSIntegerMax };

@class NSDateComponents;

/* Weeks start on the locale's first weekday (Sunday in the United States),
 * with the weekend on Saturday and Sunday everywhere. */
@interface NSCalendar : NSObject <NSCopying>
+ (NSCalendar *)currentCalendar;
+ (NSCalendar *)autoupdatingCurrentCalendar;
+ (NSCalendar *)calendarWithIdentifier:(NSCalendarIdentifier)ident;
- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)ident;
@property (readonly, copy) NSCalendarIdentifier calendarIdentifier;
@property (copy) NSLocale *locale;
@property (copy) NSTimeZone *timeZone;
@property NSUInteger firstWeekday;
@property NSUInteger minimumDaysInFirstWeek;
@property (readonly, copy) NSArray *eraSymbols;
@property (readonly, copy) NSArray *longEraSymbols;
@property (readonly, copy) NSArray *monthSymbols;
@property (readonly, copy) NSArray *shortMonthSymbols;
@property (readonly, copy) NSArray *veryShortMonthSymbols;
@property (readonly, copy) NSArray *standaloneMonthSymbols;
@property (readonly, copy) NSArray *shortStandaloneMonthSymbols;
@property (readonly, copy) NSArray *veryShortStandaloneMonthSymbols;
@property (readonly, copy) NSArray *weekdaySymbols;
@property (readonly, copy) NSArray *shortWeekdaySymbols;
@property (readonly, copy) NSArray *veryShortWeekdaySymbols;
@property (readonly, copy) NSArray *standaloneWeekdaySymbols;
@property (readonly, copy) NSArray *shortStandaloneWeekdaySymbols;
@property (readonly, copy) NSArray *veryShortStandaloneWeekdaySymbols;
@property (readonly, copy) NSArray *quarterSymbols;
@property (readonly, copy) NSArray *shortQuarterSymbols;
@property (readonly, copy) NSArray *standaloneQuarterSymbols;
@property (readonly, copy) NSArray *shortStandaloneQuarterSymbols;
@property (readonly, copy) NSString *AMSymbol;
@property (readonly, copy) NSString *PMSymbol;
- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)unit;
- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)unit;
- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
- (BOOL)rangeOfUnit:(NSCalendarUnit)unit startDate:(NSDate **)start interval:(NSTimeInterval *)interval
            forDate:(NSDate *)date;
- (NSDate *)dateFromComponents:(NSDateComponents *)comps;
- (NSDateComponents *)components:(NSCalendarUnit)units fromDate:(NSDate *)date;
- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date;
- (NSDateComponents *)componentsInTimeZone:(NSTimeZone *)zone fromDate:(NSDate *)date;
- (NSDateComponents *)components:(NSCalendarUnit)units fromDate:(NSDate *)start toDate:(NSDate *)end
                         options:(NSCalendarOptions)opts;
- (NSDateComponents *)components:(NSCalendarUnit)units fromDateComponents:(NSDateComponents *)start
                toDateComponents:(NSDateComponents *)end
                         options:(NSCalendarOptions)opts;
- (NSDate *)dateByAddingComponents:(NSDateComponents *)comps toDate:(NSDate *)date options:(NSCalendarOptions)opts;
- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)value toDate:(NSDate *)date
                     options:(NSCalendarOptions)opts;
- (NSDate *)dateWithEra:(NSInteger)era year:(NSInteger)year month:(NSInteger)month day:(NSInteger)day
                   hour:(NSInteger)hour minute:(NSInteger)minute second:(NSInteger)second
             nanosecond:(NSInteger)ns;
- (NSDate *)dateWithEra:(NSInteger)era yearForWeekOfYear:(NSInteger)year weekOfYear:(NSInteger)week
                weekday:(NSInteger)weekday hour:(NSInteger)hour minute:(NSInteger)minute
                 second:(NSInteger)second nanosecond:(NSInteger)ns;
- (void)getEra:(NSInteger *)era year:(NSInteger *)year month:(NSInteger *)month day:(NSInteger *)day
      fromDate:(NSDate *)date;
- (void)getEra:(NSInteger *)era yearForWeekOfYear:(NSInteger *)year weekOfYear:(NSInteger *)week
       weekday:(NSInteger *)weekday fromDate:(NSDate *)date;
- (void)getHour:(NSInteger *)hour minute:(NSInteger *)minute second:(NSInteger *)second
     nanosecond:(NSInteger *)ns fromDate:(NSDate *)date;
- (NSDate *)startOfDayForDate:(NSDate *)date;
- (BOOL)isDateInToday:(NSDate *)date;
- (BOOL)isDateInYesterday:(NSDate *)date;
- (BOOL)isDateInTomorrow:(NSDate *)date;
- (BOOL)isDateInWeekend:(NSDate *)date;
- (BOOL)isDate:(NSDate *)date1 inSameDayAsDate:(NSDate *)date2;
- (BOOL)isDate:(NSDate *)date1 equalToDate:(NSDate *)date2 toUnitGranularity:(NSCalendarUnit)unit;
- (NSComparisonResult)compareDate:(NSDate *)date1 toDate:(NSDate *)date2 toUnitGranularity:(NSCalendarUnit)unit;
- (BOOL)rangeOfWeekendStartDate:(NSDate **)start interval:(NSTimeInterval *)interval containingDate:(NSDate *)date;
- (BOOL)nextWeekendStartDate:(NSDate **)start interval:(NSTimeInterval *)interval options:(NSCalendarOptions)opts
                   afterDate:(NSDate *)date;
- (NSDate *)dateBySettingUnit:(NSCalendarUnit)unit value:(NSInteger)v ofDate:(NSDate *)date
                      options:(NSCalendarOptions)opts;
- (NSDate *)dateBySettingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s ofDate:(NSDate *)date
                      options:(NSCalendarOptions)opts;
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingComponents:(NSDateComponents *)comps
                      options:(NSCalendarOptions)opts;
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingUnit:(NSCalendarUnit)unit value:(NSInteger)value
                      options:(NSCalendarOptions)opts;
- (NSDate *)nextDateAfterDate:(NSDate *)date matchingHour:(NSInteger)h minute:(NSInteger)m second:(NSInteger)s
                      options:(NSCalendarOptions)opts;
- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)comps;
- (void)enumerateDatesStartingAfterDate:(NSDate *)start matchingComponents:(NSDateComponents *)comps
                                options:(NSCalendarOptions)opts
                             usingBlock:(void (^)(NSDate *date, BOOL exactMatch, BOOL *stop))block;
@end

@interface NSDateComponents : NSObject <NSCopying>
@property (copy) NSCalendar *calendar;
@property (copy) NSTimeZone *timeZone;
@property NSInteger era;
@property NSInteger year;
@property NSInteger month;
@property NSInteger day;
@property NSInteger hour;
@property NSInteger minute;
@property NSInteger second;
@property NSInteger nanosecond;
@property NSInteger weekday;
@property NSInteger weekdayOrdinal;
@property NSInteger quarter;
@property NSInteger weekOfMonth;
@property NSInteger weekOfYear;
@property NSInteger yearForWeekOfYear;
@property NSInteger dayOfYear;
@property NSInteger week;   /* the unit of Mac OS X 10.4 to 10.9 */
@property (getter=isLeapMonth) BOOL leapMonth;
@property (readonly, copy) NSDate *date;
@property (readonly, getter=isValidDate) BOOL validDate;
- (BOOL)isValidDateInCalendar:(NSCalendar *)calendar;
- (void)setValue:(NSInteger)value forComponent:(NSCalendarUnit)unit;
- (NSInteger)valueForComponent:(NSCalendarUnit)unit;
@end

/* ---- NSNumberFormatter, NSByteCountFormatter (NSNumberFormatter.m) ------------------ */

/* Numbers are written and read in English (United States), whatever the
 * locale; a locale's country only picks the default currency. */
typedef NS_ENUM(NSUInteger, NSNumberFormatterStyle) {
    NSNumberFormatterNoStyle = 0,
    NSNumberFormatterDecimalStyle = 1,
    NSNumberFormatterCurrencyStyle = 2,
    NSNumberFormatterPercentStyle = 3,
    NSNumberFormatterScientificStyle = 4,
    NSNumberFormatterSpellOutStyle = 5,
    NSNumberFormatterOrdinalStyle = 6,
    NSNumberFormatterCurrencyISOCodeStyle = 8,
    NSNumberFormatterCurrencyPluralStyle = 9,
    NSNumberFormatterCurrencyAccountingStyle = 10,
};
typedef NS_ENUM(NSUInteger, NSNumberFormatterBehavior) {
    NSNumberFormatterBehaviorDefault = 0,
    NSNumberFormatterBehavior10_0 = 1000,
    NSNumberFormatterBehavior10_4 = 1040,
};
typedef NS_ENUM(NSUInteger, NSNumberFormatterPadPosition) {
    NSNumberFormatterPadBeforePrefix = 0,
    NSNumberFormatterPadAfterPrefix = 1,
    NSNumberFormatterPadBeforeSuffix = 2,
    NSNumberFormatterPadAfterSuffix = 3,
};
typedef NS_ENUM(NSUInteger, NSNumberFormatterRoundingMode) {
    NSNumberFormatterRoundCeiling = 0,
    NSNumberFormatterRoundFloor = 1,
    NSNumberFormatterRoundDown = 2,
    NSNumberFormatterRoundUp = 3,
    NSNumberFormatterRoundHalfEven = 4,
    NSNumberFormatterRoundHalfDown = 5,
    NSNumberFormatterRoundHalfUp = 6,
};

@interface NSNumberFormatter : NSFormatter
+ (NSString *)localizedStringFromNumber:(NSNumber *)num numberStyle:(NSNumberFormatterStyle)style;
+ (NSNumberFormatterBehavior)defaultFormatterBehavior;
+ (void)setDefaultFormatterBehavior:(NSNumberFormatterBehavior)behavior;
- (NSString *)stringFromNumber:(NSNumber *)number;
- (NSNumber *)numberFromString:(NSString *)string;
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)range error:(NSError **)error;
@property NSNumberFormatterStyle numberStyle;
@property NSNumberFormatterBehavior formatterBehavior;
@property (copy) NSLocale *locale;
@property BOOL generatesDecimalNumbers;
@property NSNumberFormatterRoundingMode roundingMode;
@property (copy) NSNumber *roundingIncrement;
@property NSUInteger minimumIntegerDigits;
@property NSUInteger maximumIntegerDigits;
@property NSUInteger minimumFractionDigits;
@property NSUInteger maximumFractionDigits;
@property BOOL usesSignificantDigits;
@property NSUInteger minimumSignificantDigits;
@property NSUInteger maximumSignificantDigits;
@property NSUInteger formatWidth;
@property (copy) NSString *paddingCharacter;
@property NSNumberFormatterPadPosition paddingPosition;
@property (copy) NSNumber *multiplier;
@property (copy) NSString *positiveFormat;
@property (copy) NSString *negativeFormat;
@property (copy) NSString *positivePrefix;
@property (copy) NSString *positiveSuffix;
@property (copy) NSString *negativePrefix;
@property (copy) NSString *negativeSuffix;
@property (copy) NSString *currencyCode;
@property (copy) NSString *currencySymbol;
@property (copy) NSString *internationalCurrencySymbol;
@property (copy) NSString *currencyDecimalSeparator;
@property (copy) NSString *currencyGroupingSeparator;
@property (copy) NSString *percentSymbol;
@property (copy) NSString *perMillSymbol;
@property (copy) NSString *minusSign;
@property (copy) NSString *plusSign;
@property (copy) NSString *exponentSymbol;
@property (copy) NSString *zeroSymbol;
@property (copy) NSString *nilSymbol;
@property (copy) NSString *notANumberSymbol;
@property (copy) NSString *positiveInfinitySymbol;
@property (copy) NSString *negativeInfinitySymbol;
@property (copy) NSString *decimalSeparator;
@property BOOL alwaysShowsDecimalSeparator;
@property (copy) NSString *groupingSeparator;
@property BOOL usesGroupingSeparator;
@property NSUInteger groupingSize;
@property NSUInteger secondaryGroupingSize;
@property (getter=isLenient) BOOL lenient;
@property (getter=isPartialStringValidationEnabled) BOOL partialStringValidationEnabled;
@property (copy) NSNumber *minimum;
@property (copy) NSNumber *maximum;
@property BOOL allowsFloats;
/* the names of the Mac OS X 10.0 behaviour */
@property (copy) NSString *format;
@property BOOL hasThousandSeparators;
@property (copy) NSString *thousandSeparator;
@property BOOL localizesFormat;
@end

typedef NS_OPTIONS(NSUInteger, NSByteCountFormatterUnits) {
    NSByteCountFormatterUseDefault = 0,
    NSByteCountFormatterUseBytes = 1UL << 0,
    NSByteCountFormatterUseKB = 1UL << 1,
    NSByteCountFormatterUseMB = 1UL << 2,
    NSByteCountFormatterUseGB = 1UL << 3,
    NSByteCountFormatterUseTB = 1UL << 4,
    NSByteCountFormatterUsePB = 1UL << 5,
    NSByteCountFormatterUseEB = 1UL << 6,
    NSByteCountFormatterUseZB = 1UL << 7,
    NSByteCountFormatterUseYBOrHigher = 0x0FFUL << 8,
    NSByteCountFormatterUseAll = 0x0FFFFUL,
};
typedef NS_ENUM(NSInteger, NSByteCountFormatterCountStyle) {
    NSByteCountFormatterCountStyleFile = 0,
    NSByteCountFormatterCountStyleMemory = 1,
    NSByteCountFormatterCountStyleDecimal = 2,
    NSByteCountFormatterCountStyleBinary = 3,
};

@interface NSByteCountFormatter : NSFormatter
+ (NSString *)stringFromByteCount:(long long)count countStyle:(NSByteCountFormatterCountStyle)style;
- (NSString *)stringFromByteCount:(long long)count;
@property NSByteCountFormatterUnits allowedUnits;
@property NSByteCountFormatterCountStyle countStyle;
@property BOOL allowsNonnumericFormatting;
@property BOOL includesUnit;
@property BOOL includesCount;
@property BOOL includesActualByteCount;
@property (getter=isAdaptive) BOOL adaptive;
@property BOOL zeroPadsFractionDigits;
@end

/* ---- NSISO8601DateFormatter, NSDateComponentsFormatter (NSISO8601DateFormatter.m) ---- */

typedef NS_OPTIONS(NSUInteger, NSISO8601DateFormatOptions) {
    NSISO8601DateFormatWithYear = 1UL << 0,
    NSISO8601DateFormatWithMonth = 1UL << 1,
    NSISO8601DateFormatWithWeekOfYear = 1UL << 2,
    NSISO8601DateFormatWithDay = 1UL << 4,
    NSISO8601DateFormatWithTime = 1UL << 5,
    NSISO8601DateFormatWithTimeZone = 1UL << 6,
    NSISO8601DateFormatWithSpaceBetweenDateAndTime = 1UL << 7,
    NSISO8601DateFormatWithDashSeparatorInDate = 1UL << 8,
    NSISO8601DateFormatWithColonSeparatorInTime = 1UL << 9,
    NSISO8601DateFormatWithColonSeparatorInTimeZone = 1UL << 10,
    NSISO8601DateFormatWithFractionalSeconds = 1UL << 11,
    NSISO8601DateFormatWithFullDate = NSISO8601DateFormatWithYear | NSISO8601DateFormatWithMonth |
                                      NSISO8601DateFormatWithDay | NSISO8601DateFormatWithDashSeparatorInDate,
    NSISO8601DateFormatWithFullTime = NSISO8601DateFormatWithTime | NSISO8601DateFormatWithColonSeparatorInTime |
                                      NSISO8601DateFormatWithTimeZone |
                                      NSISO8601DateFormatWithColonSeparatorInTimeZone,
    NSISO8601DateFormatWithInternetDateTime = NSISO8601DateFormatWithFullDate | NSISO8601DateFormatWithFullTime,
};

@interface NSISO8601DateFormatter : NSFormatter
+ (NSString *)stringFromDate:(NSDate *)date timeZone:(NSTimeZone *)zone
                formatOptions:(NSISO8601DateFormatOptions)opts;
- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;
@property (copy) NSTimeZone *timeZone;
@property NSISO8601DateFormatOptions formatOptions;
@end

typedef NS_ENUM(NSInteger, NSDateComponentsFormatterUnitsStyle) {
    NSDateComponentsFormatterUnitsStylePositional = 0,
    NSDateComponentsFormatterUnitsStyleAbbreviated = 1,
    NSDateComponentsFormatterUnitsStyleShort = 2,
    NSDateComponentsFormatterUnitsStyleFull = 3,
    NSDateComponentsFormatterUnitsStyleSpellOut = 4,
    NSDateComponentsFormatterUnitsStyleBrief = 5,
};
typedef NS_OPTIONS(NSUInteger, NSDateComponentsFormatterZeroFormattingBehavior) {
    NSDateComponentsFormatterZeroFormattingBehaviorNone = 0,
    NSDateComponentsFormatterZeroFormattingBehaviorDefault = 1UL << 0,
    NSDateComponentsFormatterZeroFormattingBehaviorDropLeading = 1UL << 1,
    NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle = 1UL << 2,
    NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing = 1UL << 3,
    NSDateComponentsFormatterZeroFormattingBehaviorDropAll = (1UL << 1) | (1UL << 2) | (1UL << 3),
    NSDateComponentsFormatterZeroFormattingBehaviorPad = 1UL << 16,
};

@interface NSDateComponentsFormatter : NSFormatter
+ (NSString *)localizedStringFromDateComponents:(NSDateComponents *)comps
                                     unitsStyle:(NSDateComponentsFormatterUnitsStyle)style;
- (NSString *)stringFromDateComponents:(NSDateComponents *)comps;
- (NSString *)stringFromDate:(NSDate *)start toDate:(NSDate *)end;
- (NSString *)stringFromTimeInterval:(NSTimeInterval)interval;
@property NSDateComponentsFormatterUnitsStyle unitsStyle;
@property NSCalendarUnit allowedUnits;
@property NSDateComponentsFormatterZeroFormattingBehavior zeroFormattingBehavior;
@property (copy) NSCalendar *calendar;
@property (copy) NSDate *referenceDate;
@property BOOL allowsFractionalUnits;
@property NSInteger maximumUnitCount;
@property BOOL collapsesLargestUnit;
@property BOOL includesApproximationPhrase;
@property BOOL includesTimeRemainingPhrase;
@end

/* ---- NSURL ------------------------------------------------------------------------- */

@interface NSURL : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)URLWithString:(NSString *)s;
+ (instancetype)URLWithString:(NSString *)s relativeToURL:(NSURL *)base;
+ (NSURL *)fileURLWithPath:(NSString *)path;
+ (NSURL *)fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir;
- (instancetype)initWithString:(NSString *)s;
- (instancetype)initWithString:(NSString *)s relativeToURL:(NSURL *)base;
- (instancetype)initFileURLWithPath:(NSString *)path;
@property (readonly, copy) NSURL *absoluteURL;
@property (readonly, copy) NSURL *baseURL;
@property (readonly, copy) NSString *relativeString;
@property (readonly, copy) NSString *user;
@property (readonly) BOOL hasDirectoryPath;
@property (readonly, copy) NSURL *URLByStandardizingPath;
@property (readonly, copy) NSURL *URLByResolvingSymlinksInPath;
@property (readonly, copy) NSString *absoluteString;
@property (readonly, copy) NSString *scheme;
@property (readonly, copy) NSString *host;
@property (readonly, copy) NSNumber *port;
@property (readonly, copy) NSString *path;
@property (readonly, copy) NSString *query;
@property (readonly, copy) NSString *fragment;
@property (readonly, copy) NSString *lastPathComponent;
@property (readonly, copy) NSString *pathExtension;
@property (readonly, copy) NSArray<NSString *> *pathComponents;
@property (readonly) BOOL isFileURL;
@property (readonly, copy) NSURL *URLByDeletingLastPathComponent;
@property (readonly, copy) NSURL *URLByDeletingPathExtension;
@property (readonly) const char *fileSystemRepresentation NS_RETURNS_INNER_POINTER;
- (NSURL *)URLByAppendingPathComponent:(NSString *)component;
- (NSURL *)URLByAppendingPathComponent:(NSString *)component isDirectory:(BOOL)isDir;
- (NSURL *)URLByAppendingPathExtension:(NSString *)ext;
- (BOOL)isEqual:(id)other;
@end

/* ---- NSError and NSException ------------------------------------------------------- */

typedef NSString *NSErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSCocoaErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSPOSIXErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSOSStatusErrorDomain;
FOUNDATION_EXPORT NSString *const NSLocalizedDescriptionKey;
FOUNDATION_EXPORT NSString *const NSFilePathErrorKey;
FOUNDATION_EXPORT NSString *const NSUnderlyingErrorKey;

FOUNDATION_EXPORT NSString *const NSLocalizedFailureReasonErrorKey;
FOUNDATION_EXPORT NSString *const NSLocalizedRecoverySuggestionErrorKey;
FOUNDATION_EXPORT NSString *const NSLocalizedRecoveryOptionsErrorKey;
FOUNDATION_EXPORT NSString *const NSRecoveryAttempterErrorKey;
FOUNDATION_EXPORT NSString *const NSHelpAnchorErrorKey;
FOUNDATION_EXPORT NSString *const NSURLErrorKey;
FOUNDATION_EXPORT NSString *const NSStringEncodingErrorKey;

enum {
    NSFileNoSuchFileError = 4,
    NSFileReadUnknownError = 256,
    NSFileReadNoPermissionError = 257,
    NSFileReadCorruptFileError = 259,
    NSFileReadNoSuchFileError = 260,
    NSFileReadUnsupportedSchemeError = 262,
    NSFileWriteUnknownError = 512,
    NSFileWriteNoPermissionError = 513,
    NSFileWriteFileExistsError = 516,
    NSFileWriteVolumeReadOnlyError = 642,
    NSUserCancelledError = 3072,
    NSFeatureUnsupportedError = 3328,
};

@interface NSError : NSObject <NSCopying>
+ (instancetype)errorWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)dict;
- (instancetype)initWithDomain:(NSErrorDomain)domain code:(NSInteger)code userInfo:(NSDictionary *)dict;
@property (readonly, copy) NSErrorDomain domain;
@property (readonly) NSInteger code;
@property (readonly, copy) NSDictionary *userInfo;
@property (readonly, copy) NSString *localizedDescription;
@property (readonly, copy) NSString *localizedFailureReason;
@property (readonly, copy) NSString *localizedRecoverySuggestion;
@property (readonly, copy) NSArray<NSString *> *localizedRecoveryOptions;
@property (readonly, retain) id recoveryAttempter;
@property (readonly, copy) NSString *helpAnchor;
@end

typedef NSString *NSExceptionName;
FOUNDATION_EXPORT NSExceptionName const NSGenericException;
FOUNDATION_EXPORT NSExceptionName const NSRangeException;
FOUNDATION_EXPORT NSExceptionName const NSInvalidArgumentException;
FOUNDATION_EXPORT NSExceptionName const NSInternalInconsistencyException;

FOUNDATION_EXPORT NSExceptionName const NSMallocException, NSObjectInaccessibleException,
    NSObjectNotAvailableException, NSDestinationInvalidException, NSPortTimeoutException,
    NSInvalidSendPortException, NSInvalidReceivePortException, NSPortSendException, NSPortReceiveException,
    NSCharacterConversionException, NSFileHandleOperationException, NSParseErrorException,
    NSUndefinedKeyException, NSInvalidArchiveOperationException, NSInvalidUnarchiveOperationException;

/* Exceptions can be caught (@try/@catch) since Ferry M7. */
__attribute__((__objc_exception__))
@interface NSException : NSObject <NSCopying, NSCoding>
+ (NSException *)exceptionWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo;
+ (void)raise:(NSExceptionName)name format:(NSString *)format arguments:(va_list)args;
@property (readonly, copy) NSArray<NSNumber *> *callStackReturnAddresses;
@property (readonly, copy) NSArray<NSString *> *callStackSymbols;
- (instancetype)initWithName:(NSExceptionName)name reason:(NSString *)reason userInfo:(NSDictionary *)userInfo;
+ (void)raise:(NSExceptionName)name format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);
@property (readonly, copy) NSExceptionName name;
@property (readonly, copy) NSString *reason;
@property (readonly, copy) NSDictionary *userInfo;
- (void)raise __attribute__((noreturn));
@end

typedef void NSUncaughtExceptionHandler(NSException *exception);
#ifdef __cplusplus
extern "C" {
#endif
void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler);
NSUncaughtExceptionHandler *NSGetUncaughtExceptionHandler(void);
/* The old way of writing @try/@catch */
#define NS_DURING @try {
#define NS_HANDLER } @catch (NSException *localException) {
#define NS_ENDHANDLER }
#define NS_VALUERETURN(val, type) return (val)
#define NS_VOIDRETURN return
#ifdef __cplusplus
}
#endif

/* ---- NSAutoreleasePool --------------------------------------------------------------- */

@interface NSAutoreleasePool : NSObject
+ (void)addObject:(id)obj;
- (void)addObject:(id)obj;
- (void)drain;
@end

/* ---- NSProcessInfo, NSBundle, NSUserDefaults, NSFileManager ----------------------- */

@interface NSProcessInfo : NSObject
+ (NSProcessInfo *)processInfo;
@property (readonly, copy) NSArray<NSString *> *arguments;
@property (readonly, copy) NSDictionary<NSString *, NSString *> *environment;
@property (copy) NSString *processName;
@property (readonly) int processIdentifier;
@property (readonly, copy) NSString *hostName;
@property (readonly, copy) NSString *globallyUniqueString;
@property (readonly) NSUInteger processorCount;
@property (readonly) NSUInteger activeProcessorCount;
@property (readonly) unsigned long long physicalMemory;
@property (readonly) NSTimeInterval systemUptime;
@property (readonly, copy) NSString *operatingSystemVersionString;
@end

@interface NSBundle : NSObject
+ (NSBundle *)mainBundle;
+ (NSBundle *)bundleWithPath:(NSString *)path;
+ (NSBundle *)bundleForClass:(Class)cls;
- (instancetype)initWithPath:(NSString *)path;
@property (readonly, copy) NSString *bundlePath;
@property (readonly, copy) NSString *resourcePath;
@property (readonly, copy) NSString *executablePath;
@property (readonly, copy) NSURL *bundleURL;
@property (readonly, copy) NSURL *resourceURL;
@property (readonly, copy) NSString *bundleIdentifier;
@property (readonly, copy) NSDictionary<NSString *, id> *infoDictionary;
- (id)objectForInfoDictionaryKey:(NSString *)key;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext;
- (NSString *)pathForResource:(NSString *)name ofType:(NSString *)ext inDirectory:(NSString *)subpath;
- (NSURL *)URLForResource:(NSString *)name withExtension:(NSString *)ext;
- (NSArray<NSString *> *)pathsForResourcesOfType:(NSString *)ext inDirectory:(NSString *)subpath;
@property (readonly, copy) NSDictionary<NSString *, id> *localizedInfoDictionary;
- (BOOL)load;
@property (readonly, getter=isLoaded) BOOL loaded;
- (NSString *)localizedStringForKey:(NSString *)key value:(NSString *)value table:(NSString *)tableName;
@end
#define NSLocalizedString(key, comment) [[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

@interface NSUserDefaults : NSObject
+ (NSUserDefaults *)standardUserDefaults;
+ (void)resetStandardUserDefaults;
- (instancetype)initWithSuiteName:(NSString *)name;
- (id)objectForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (NSArray *)arrayForKey:(NSString *)key;
- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key;
- (NSDictionary<NSString *, id> *)persistentDomainForName:(NSString *)name;
- (void)removePersistentDomainForName:(NSString *)name;
- (NSDictionary<NSString *, id> *)dictionaryForKey:(NSString *)key;
- (NSData *)dataForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (NSURL *)URLForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (void)setFloat:(float)value forKey:(NSString *)key;
- (void)setDouble:(double)value forKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)setURL:(NSURL *)url forKey:(NSString *)key;
- (void)registerDefaults:(NSDictionary<NSString *, id> *)defaults;
- (NSDictionary<NSString *, id> *)dictionaryRepresentation;
- (BOOL)synchronize;
@end
FOUNDATION_EXPORT NSString *const NSUserDefaultsDidChangeNotification;

typedef NSString *NSFileAttributeKey;
FOUNDATION_EXPORT NSFileAttributeKey const NSFileSize;
FOUNDATION_EXPORT NSFileAttributeKey const NSFileType;
FOUNDATION_EXPORT NSFileAttributeKey const NSFileModificationDate;
FOUNDATION_EXPORT NSFileAttributeKey const NSFilePosixPermissions;
FOUNDATION_EXPORT NSString *const NSFileTypeDirectory;
FOUNDATION_EXPORT NSString *const NSFileTypeRegular;
FOUNDATION_EXPORT NSString *const NSFileTypeSymbolicLink;

typedef NS_ENUM(NSUInteger, NSSearchPathDirectory) {
    NSApplicationDirectory = 1,
    NSLibraryDirectory = 5,
    NSUserDirectory = 7,
    NSDocumentDirectory = 9,
    NSCachesDirectory = 13,
    NSApplicationSupportDirectory = 14,
    NSDownloadsDirectory = 15,
    NSDesktopDirectory = 12,
    NSMoviesDirectory = 17,
    NSMusicDirectory = 18,
    NSPicturesDirectory = 19,
};
typedef NS_OPTIONS(NSUInteger, NSSearchPathDomainMask) {
    NSUserDomainMask = 1, NSLocalDomainMask = 2, NSNetworkDomainMask = 4, NSSystemDomainMask = 8,
    NSAllDomainsMask = 0x0ffff
};

enum { NSDirectoryEnumerationSkipsSubdirectoryDescendants = 1, NSDirectoryEnumerationSkipsPackageDescendants = 2,
       NSDirectoryEnumerationSkipsHiddenFiles = 4 };

@interface NSFileManager : NSObject
+ (NSFileManager *)defaultManager;
@property (readonly, copy) NSString *currentDirectoryPath;
@property (readonly, copy) NSURL *homeDirectoryForCurrentUser;
@property (readonly, copy) NSURL *temporaryDirectory;
- (BOOL)changeCurrentDirectoryPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path;
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory;
- (BOOL)isReadableFileAtPath:(NSString *)path;
- (BOOL)isWritableFileAtPath:(NSString *)path;
- (BOOL)isExecutableFileAtPath:(NSString *)path;
- (BOOL)isDeletableFileAtPath:(NSString *)path;
- (BOOL)contentsEqualAtPath:(NSString *)a andPath:(NSString *)b;
- (NSArray<NSString *> *)subpathsAtPath:(NSString *)path;
- (BOOL)createSymbolicLinkAtPath:(NSString *)path withDestinationPath:(NSString *)dest error:(NSError **)error;
- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error;
- (NSURL *)URLForDirectory:(NSSearchPathDirectory)directory inDomain:(NSSearchPathDomainMask)domain
         appropriateForURL:(NSURL *)url create:(BOOL)create error:(NSError **)error;
- (const char *)fileSystemRepresentationWithPath:(NSString *)path NS_RETURNS_INNER_POINTER;
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)create
                   attributes:(NSDictionary *)attributes error:(NSError **)error;
- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)create
                  attributes:(NSDictionary *)attributes error:(NSError **)error;
- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary *)attr;
- (NSData *)contentsAtPath:(NSString *)path;
- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (NSArray<NSURL *> *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys
                                       options:(NSUInteger)mask error:(NSError **)error;
- (NSArray<NSString *> *)subpathsOfDirectoryAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError **)error;
- (BOOL)copyItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
- (BOOL)moveItemAtPath:(NSString *)src toPath:(NSString *)dst error:(NSError **)error;
- (BOOL)copyItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)error;
- (BOOL)moveItemAtURL:(NSURL *)src toURL:(NSURL *)dst error:(NSError **)error;
- (NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path error:(NSError **)error;
- (NSArray<NSURL *> *)URLsForDirectory:(NSSearchPathDirectory)directory inDomains:(NSSearchPathDomainMask)mask;
- (NSString *)stringWithFileSystemRepresentation:(const char *)s length:(NSUInteger)len;
@end

@interface NSDictionary (NSFileAttributes)
- (unsigned long long)fileSize;
- (NSString *)fileType;
- (NSDate *)fileModificationDate;
@end

/* ---- property lists -------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSPropertyListFormat) {
    NSPropertyListOpenStepFormat = 1,
    NSPropertyListXMLFormat_v1_0 = 100,
    NSPropertyListBinaryFormat_v1_0 = 200,
};
typedef NS_OPTIONS(NSUInteger, NSPropertyListMutabilityOptions) {
    NSPropertyListImmutable = 0,
    NSPropertyListMutableContainers = 1,
    NSPropertyListMutableContainersAndLeaves = 2,
};
typedef NSUInteger NSPropertyListReadOptions;
typedef NSUInteger NSPropertyListWriteOptions;

@interface NSPropertyListSerialization : NSObject
+ (id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)format error:(NSError **)error;
+ (NSData *)dataWithPropertyList:(id)plist format:(NSPropertyListFormat)format
                         options:(NSPropertyListWriteOptions)opt error:(NSError **)error;
+ (BOOL)propertyList:(id)plist isValidForFormat:(NSPropertyListFormat)format;
+ (id)propertyListFromData:(NSData *)data mutabilityOption:(NSPropertyListMutabilityOptions)opt
                    format:(NSPropertyListFormat *)format errorDescription:(NSString **)errorString;
@end

/* ---- NSJSONSerialization (NSJSONSerialization.m) ------------------------------------ */

typedef NS_OPTIONS(NSUInteger, NSJSONReadingOptions) {
    NSJSONReadingMutableContainers = 1 << 0,
    NSJSONReadingMutableLeaves = 1 << 1,
    NSJSONReadingFragmentsAllowed = 1 << 2,
    NSJSONReadingJSON5Allowed = 1 << 3,            /* accepted; only plain JSON is read */
    NSJSONReadingTopLevelDictionaryAssumed = 1 << 4, /* accepted; has no effect (it goes with JSON5) */
    NSJSONReadingAllowFragments = NSJSONReadingFragmentsAllowed,
};
typedef NS_OPTIONS(NSUInteger, NSJSONWritingOptions) {
    NSJSONWritingPrettyPrinted = 1 << 0,
    NSJSONWritingSortedKeys = 1 << 1,
    NSJSONWritingFragmentsAllowed = 1 << 2,
    NSJSONWritingWithoutEscapingSlashes = 1 << 3,
};
@interface NSJSONSerialization : NSObject
+ (BOOL)isValidJSONObject:(id)obj;
+ (NSData *)dataWithJSONObject:(id)obj options:(NSJSONWritingOptions)opt error:(NSError **)error;
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error;
@end

/* ---- archiving (NSCoder, NSKeyedArchiver, NSKeyedUnarchiver) --------------------- */

@interface NSCoder : NSObject
@property (readonly) BOOL allowsKeyedCoding;
@property (readonly) BOOL requiresSecureCoding;
- (void)encodeObject:(id)object forKey:(NSString *)key;
- (void)encodeConditionalObject:(id)object forKey:(NSString *)key;
- (void)encodeBool:(BOOL)value forKey:(NSString *)key;
- (void)encodeInt:(int)value forKey:(NSString *)key;
- (void)encodeInt32:(int32_t)value forKey:(NSString *)key;
- (void)encodeInt64:(int64_t)value forKey:(NSString *)key;
- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key;
- (void)encodeFloat:(float)value forKey:(NSString *)key;
- (void)encodeDouble:(double)value forKey:(NSString *)key;
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key;
- (void)encodePoint:(NSPoint)point forKey:(NSString *)key;
- (void)encodeSize:(NSSize)size forKey:(NSString *)key;
- (void)encodeRect:(NSRect)rect forKey:(NSString *)key;
- (BOOL)containsValueForKey:(NSString *)key;
- (id)decodeObjectForKey:(NSString *)key;
- (id)decodeObjectOfClass:(Class)cls forKey:(NSString *)key;
- (id)decodeObjectOfClasses:(NSSet *)classes forKey:(NSString *)key;
- (id)decodeTopLevelObjectForKey:(NSString *)key error:(NSError **)error;
- (NSArray *)decodeArrayOfObjectsOfClass:(Class)cls forKey:(NSString *)key;
- (BOOL)decodeBoolForKey:(NSString *)key;
- (int)decodeIntForKey:(NSString *)key;
- (int32_t)decodeInt32ForKey:(NSString *)key;
- (int64_t)decodeInt64ForKey:(NSString *)key;
- (NSInteger)decodeIntegerForKey:(NSString *)key;
- (float)decodeFloatForKey:(NSString *)key;
- (double)decodeDoubleForKey:(NSString *)key;
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)length;
- (NSPoint)decodePointForKey:(NSString *)key;
- (NSSize)decodeSizeForKey:(NSString *)key;
- (NSRect)decodeRectForKey:(NSString *)key;
- (void)failWithError:(NSError *)error;
@property (readonly, copy) NSError *error;
@end

FOUNDATION_EXPORT NSString *const NSKeyedArchiveRootObjectKey;
FOUNDATION_EXPORT NSString *const NSInvalidArchiveOperationException;
FOUNDATION_EXPORT NSString *const NSInvalidUnarchiveOperationException;

@interface NSKeyedArchiver : NSCoder
+ (NSData *)archivedDataWithRootObject:(id)root requiringSecureCoding:(BOOL)secure error:(NSError **)error;
+ (NSData *)archivedDataWithRootObject:(id)root;
+ (BOOL)archiveRootObject:(id)root toFile:(NSString *)path;
- (instancetype)initRequiringSecureCoding:(BOOL)secure;
- (instancetype)initForWritingWithMutableData:(NSMutableData *)data;
@property NSPropertyListFormat outputFormat;
@property (readonly, strong) NSData *encodedData;
- (void)finishEncoding;
+ (void)setClassName:(NSString *)name forClass:(Class)cls;
+ (NSString *)classNameForClass:(Class)cls;
- (void)setClassName:(NSString *)name forClass:(Class)cls;
- (NSString *)classNameForClass:(Class)cls;
@end

typedef NS_ENUM(NSInteger, NSDecodingFailurePolicy) {
    NSDecodingFailurePolicyRaiseException = 0,
    NSDecodingFailurePolicySetErrorAndReturn = 1,
};

@interface NSKeyedUnarchiver : NSCoder
+ (id)unarchiveObjectWithData:(NSData *)data;
+ (id)unarchiveObjectWithFile:(NSString *)path;
+ (id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error;
+ (id)unarchivedObjectOfClasses:(NSSet *)classes fromData:(NSData *)data error:(NSError **)error;
+ (id)unarchiveTopLevelObjectWithData:(NSData *)data error:(NSError **)error;
- (instancetype)initForReadingFromData:(NSData *)data error:(NSError **)error;
- (instancetype)initForReadingWithData:(NSData *)data;
@property (readwrite) BOOL requiresSecureCoding;
@property NSDecodingFailurePolicy decodingFailurePolicy;
- (void)finishDecoding;
+ (void)setClass:(Class)cls forClassName:(NSString *)name;
+ (Class)classForClassName:(NSString *)name;
- (void)setClass:(Class)cls forClassName:(NSString *)name;
- (Class)classForClassName:(NSString *)name;
@end

@interface NSObject (NSArchiving)
@property (readonly) Class classForCoder;
@property (readonly) Class classForKeyedArchiver;
- (id)replacementObjectForCoder:(NSCoder *)coder;
- (id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)archiver;
- (id)awakeAfterUsingCoder:(NSCoder *)coder;
+ (NSArray<NSString *> *)classFallbacksForKeyedArchiver;
@end

/* ---- notifications, run loops, timers ----------------------------------------------- */

/* ---- NSValueTransformer ---------------------------------------------------------- */

typedef NSString *NSValueTransformerName;
FOUNDATION_EXPORT NSValueTransformerName const NSNegateBooleanTransformerName, NSIsNilTransformerName,
    NSIsNotNilTransformerName, NSUnarchiveFromDataTransformerName, NSKeyedUnarchiveFromDataTransformerName,
    NSSecureUnarchiveFromDataTransformerName;
@interface NSValueTransformer : NSObject
+ (void)setValueTransformer:(NSValueTransformer *)transformer forName:(NSValueTransformerName)name;
+ (NSValueTransformer *)valueTransformerForName:(NSValueTransformerName)name;
+ (NSArray<NSValueTransformerName> *)valueTransformerNames;
+ (Class)transformedValueClass;
+ (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)value;
- (id)reverseTransformedValue:(id)value;
@end
@interface NSSecureUnarchiveFromDataTransformer : NSValueTransformer
@property (class, readonly, copy) NSArray<Class> *allowedTopLevelClasses;
@end

typedef NSString *NSNotificationName;

@interface NSNotification : NSObject <NSCopying>
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object;
+ (instancetype)notificationWithName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)info;
@property (readonly, copy) NSNotificationName name;
@property (readonly, retain) id object;
@property (readonly, copy) NSDictionary *userInfo;
@end

@class NSOperationQueue;

@interface NSNotificationCenter : NSObject
+ (NSNotificationCenter *)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)sel name:(NSNotificationName)name object:(id)object;
- (id<NSObject>)addObserverForName:(NSNotificationName)name object:(id)obj queue:(NSOperationQueue *)queue
                        usingBlock:(void (^)(NSNotification *note))block;
- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSNotificationName)name object:(id)object;
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)info;
- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(NSNotificationName)name object:(id)object;
@end

typedef NSString *NSRunLoopMode;
FOUNDATION_EXPORT NSRunLoopMode const NSDefaultRunLoopMode;
FOUNDATION_EXPORT NSRunLoopMode const NSRunLoopCommonModes;

@class NSTimer;

@interface NSRunLoop : NSObject
+ (NSRunLoop *)currentRunLoop;
+ (NSRunLoop *)mainRunLoop;
@property (readonly, copy) NSRunLoopMode currentMode;
- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode;
- (void)run;
- (void)runUntilDate:(NSDate *)limit;
- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limit;
- (void)performBlock:(void (^)(void))block;
- (void)removeTimer:(NSTimer *)timer; /* Ferry */
- (CFRunLoopRef)getCFRunLoop;
@end

@interface NSTimer : NSObject
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel userInfo:(id)info
                           repeats:(BOOL)repeats;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel
                                   userInfo:(id)info repeats:(BOOL)repeats;
+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti repeats:(BOOL)repeats block:(void (^)(NSTimer *timer))block;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti repeats:(BOOL)repeats
                                      block:(void (^)(NSTimer *timer))block;
- (instancetype)initWithFireDate:(NSDate *)date interval:(NSTimeInterval)ti target:(id)target selector:(SEL)sel
                        userInfo:(id)info repeats:(BOOL)repeats;
- (void)fire;
- (void)invalidate;
@property (readonly, getter=isValid) BOOL valid;
@property (readonly) NSTimeInterval timeInterval;
@property (copy) NSDate *fireDate;
@property (readonly, retain) id userInfo;
@property NSTimeInterval tolerance;
@end

/* ---- NSAttributedString ------------------------------------------------------------ */

typedef NSString *NSAttributedStringKey;
typedef NS_OPTIONS(NSUInteger, NSAttributedStringEnumerationOptions) {
    NSAttributedStringEnumerationReverse = (1UL << 1),
    NSAttributedStringEnumerationLongestEffectiveRangeNotRequired = (1UL << 20),
};

@interface NSAttributedString : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>
@property (readonly, copy) NSString *string;
@property (readonly) NSUInteger length;
- (instancetype)initWithString:(NSString *)str;
- (instancetype)initWithString:(NSString *)str attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs;
- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr;
- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                 effectiveRange:(NSRangePointer)range;
- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                          longestEffectiveRange:(NSRangePointer)range
                                                        inRange:(NSRange)rangeLimit;
- (id)attribute:(NSAttributedStringKey)name atIndex:(NSUInteger)location effectiveRange:(NSRangePointer)range;
- (id)attribute:(NSAttributedStringKey)name
                  atIndex:(NSUInteger)location
    longestEffectiveRange:(NSRangePointer)range
                  inRange:(NSRange)rangeLimit;
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range;
- (BOOL)isEqualToAttributedString:(NSAttributedString *)other;
- (void)enumerateAttributesInRange:(NSRange)range
                           options:(NSAttributedStringEnumerationOptions)opts
                        usingBlock:(void (^)(NSDictionary<NSAttributedStringKey, id> *attrs, NSRange range,
                                             BOOL *stop))block;
- (void)enumerateAttribute:(NSAttributedStringKey)name
                   inRange:(NSRange)range
                   options:(NSAttributedStringEnumerationOptions)opts
                usingBlock:(void (^)(id value, NSRange range, BOOL *stop))block;
@end

@interface NSMutableAttributedString : NSAttributedString
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str;
- (void)replaceCharactersInRange:(NSRange)range withAttributedString:(NSAttributedString *)attrString;
- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range;
- (void)addAttribute:(NSAttributedStringKey)name value:(id)value range:(NSRange)range;
- (void)addAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range;
- (void)removeAttribute:(NSAttributedStringKey)name range:(NSRange)range;
- (void)appendAttributedString:(NSAttributedString *)attrString;
- (void)insertAttributedString:(NSAttributedString *)attrString atIndex:(NSUInteger)loc;
- (void)deleteCharactersInRange:(NSRange)range;
- (void)setAttributedString:(NSAttributedString *)attrString;
- (void)beginEditing;
- (void)endEditing;
@end

/* ---- functions ------------------------------------------------------------------- */

#ifdef __cplusplus
extern "C" {
#endif
void NSLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void NSLogv(NSString *format, va_list args) NS_FORMAT_FUNCTION(1, 0);
NSString *NSStringFromClass(Class cls);
Class NSClassFromString(NSString *name);
NSString *NSStringFromSelector(SEL sel);
SEL NSSelectorFromString(NSString *name);
NSString *NSStringFromProtocol(Protocol *proto);
Protocol *NSProtocolFromString(NSString *name);
NSString *NSStringFromRange(NSRange range);
NSRange NSRangeFromString(NSString *s);
NSString *NSStringFromPoint(NSPoint p);
NSString *NSStringFromSize(NSSize s);
NSString *NSStringFromRect(NSRect r);
NSPoint NSPointFromString(NSString *s);
NSSize NSSizeFromString(NSString *s);
NSRect NSRectFromString(NSString *s);
NSString *NSHomeDirectory(void);
NSString *NSTemporaryDirectory(void);
NSString *NSUserName(void);
NSString *NSFullUserName(void);
NSArray<NSString *> *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory dir, NSSearchPathDomainMask mask,
                                                         BOOL expandTilde);
#ifdef __cplusplus
}
#endif

/* ---- NSFileWrapper ----------------------------------------------------------------- */

/* A file, folder or symbolic link held in memory, as documents read and
 * write them (NSFileWrapper.m). */
typedef NS_OPTIONS(NSUInteger, NSFileWrapperReadingOptions) {
    NSFileWrapperReadingImmediate = 1 << 0, NSFileWrapperReadingWithoutMapping = 1 << 1,
};
typedef NS_OPTIONS(NSUInteger, NSFileWrapperWritingOptions) {
    NSFileWrapperWritingAtomic = 1 << 0, NSFileWrapperWritingWithNameUpdating = 1 << 1,
};
@interface NSFileWrapper : NSObject <NSCoding>
- (instancetype)initWithURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)error;
- (instancetype)initDirectoryWithFileWrappers:(NSDictionary<NSString *, NSFileWrapper *> *)wrappers;
- (instancetype)initRegularFileWithContents:(NSData *)contents;
- (instancetype)initSymbolicLinkWithDestinationURL:(NSURL *)url;
- (instancetype)initWithSerializedRepresentation:(NSData *)data;
- (instancetype)initWithPath:(NSString *)path;
- (instancetype)initSymbolicLinkWithDestination:(NSString *)path;
@property (readonly, getter=isDirectory) BOOL directory;
@property (readonly, getter=isRegularFile) BOOL regularFile;
@property (readonly, getter=isSymbolicLink) BOOL symbolicLink;
@property (copy) NSString *preferredFilename;
@property (copy) NSString *filename;
@property (copy) NSDictionary<NSString *, id> *fileAttributes;
@property (readonly, copy) NSData *regularFileContents;
@property (readonly, copy) NSDictionary<NSString *, NSFileWrapper *> *fileWrappers;
@property (readonly, copy) NSURL *symbolicLinkDestinationURL;
@property (readonly, copy) NSData *serializedRepresentation;
- (NSString *)symbolicLinkDestination;
- (BOOL)matchesContentsOfURL:(NSURL *)url;
- (BOOL)readFromURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)error;
- (BOOL)writeToURL:(NSURL *)url options:(NSFileWrapperWritingOptions)options
    originalContentsURL:(NSURL *)original error:(NSError **)error;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically updateFilenames:(BOOL)update;
- (NSString *)addFileWrapper:(NSFileWrapper *)child;
- (NSString *)addRegularFileWithContents:(NSData *)data preferredFilename:(NSString *)name;
- (void)removeFileWrapper:(NSFileWrapper *)child;
- (NSString *)keyForFileWrapper:(NSFileWrapper *)child;
@end

/* ---- NSMethodSignature, NSInvocation, NSProxy, forwarding ------------------------------ */

/* Messages as objects (NSInvocation.m): a method signature is read from an
 * Objective-C type encoding, and an invocation holds a message's target,
 * selector, arguments and return value, laid out for the x86-64 calling
 * convention. A message nothing implements is offered to
 * forwardingTargetForSelector:, then (with the receiver's
 * methodSignatureForSelector:) to forwardInvocation: as an invocation. */
FOUNDATION_EXPORT const char *NSGetSizeAndAlignment(const char *typePtr, NSUInteger *sizep, NSUInteger *alignp);
@interface NSMethodSignature : NSObject
+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types;
@property (readonly) NSUInteger numberOfArguments;
- (const char *)getArgumentTypeAtIndex:(NSUInteger)idx NS_RETURNS_INNER_POINTER;
@property (readonly) NSUInteger frameLength;
- (BOOL)isOneway;
@property (readonly) const char *methodReturnType NS_RETURNS_INNER_POINTER;
@property (readonly) NSUInteger methodReturnLength;
@end

@interface NSInvocation : NSObject
+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)sig;
@property (readonly, retain) NSMethodSignature *methodSignature;
- (void)retainArguments;
@property (readonly) BOOL argumentsRetained;
@property (assign) id target;
@property SEL selector;
- (void)getReturnValue:(void *)retLoc;
- (void)setReturnValue:(void *)retLoc;
- (void)getArgument:(void *)argumentLocation atIndex:(NSInteger)idx;
- (void)setArgument:(void *)argumentLocation atIndex:(NSInteger)idx;
- (void)invoke;
- (void)invokeWithTarget:(id)target;
@end

@interface NSObject (NSForwarding)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
+ (NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)aSelector;
- (void)forwardInvocation:(NSInvocation *)anInvocation;
@end

/* A root class of its own for objects that stand in for others: a subclass
 * answers methodSignatureForSelector: and forwardInvocation:. */
OBJC_ROOT_CLASS
@interface NSProxy <NSObject> {
    Class isa;
}
+ (id)alloc;
+ (id)allocWithZone:(NSZone *)zone;
+ (Class)class;
+ (BOOL)respondsToSelector:(SEL)aSelector;
- (void)forwardInvocation:(NSInvocation *)invocation;
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel;
- (void)dealloc;
- (void)finalize;
@property (readonly, copy) NSString *description;
@property (readonly, copy) NSString *debugDescription;
@end

/* ---- NSUndoManager ----------------------------------------------------------------- */

/* Undo and redo stacks of groups of actions (NSUndoManager.m). Actions are
 * registered with a selector, a block, or prepareWithInvocationTarget:
 * and a message sent to what it returns (the undo manager itself), kept as
 * an NSInvocation. */
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerCheckpointNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerWillUndoChangeNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerWillRedoChangeNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerDidUndoChangeNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerDidRedoChangeNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerDidOpenUndoGroupNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerWillCloseUndoGroupNotification;
FOUNDATION_EXPORT NSNotificationName const NSUndoManagerDidCloseUndoGroupNotification;
FOUNDATION_EXPORT NSString *const NSUndoManagerGroupIsDiscardableKey;
enum { NSUndoCloseGroupingRunLoopOrdering = 350000 };
@interface NSUndoManager : NSObject
- (void)beginUndoGrouping;
- (void)endUndoGrouping;
@property (readonly) NSInteger groupingLevel;
@property BOOL groupsByEvent;
@property NSUInteger levelsOfUndo;
@property (copy) NSArray<NSRunLoopMode> *runLoopModes;
- (void)disableUndoRegistration;
- (void)enableUndoRegistration;
@property (readonly, getter=isUndoRegistrationEnabled) BOOL undoRegistrationEnabled;
@property (readonly) BOOL canUndo, canRedo;
@property (readonly, getter=isUndoing) BOOL undoing;
@property (readonly, getter=isRedoing) BOOL redoing;
- (void)undo;
- (void)redo;
- (void)undoNestedGroup;
- (void)removeAllActions;
- (void)removeAllActionsWithTarget:(id)target;
- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)object;
- (void)registerUndoWithTarget:(id)target handler:(void (^)(id target))handler;
- (id)prepareWithInvocationTarget:(id)target;
- (void)setActionIsDiscardable:(BOOL)discardable;
@property (readonly) BOOL undoActionIsDiscardable, redoActionIsDiscardable;
- (void)setActionName:(NSString *)name;
@property (readonly, copy) NSString *undoActionName, *redoActionName;
@property (readonly, copy) NSString *undoMenuItemTitle, *redoMenuItemTitle;
- (NSString *)undoMenuTitleForUndoActionName:(NSString *)name;
- (NSString *)redoMenuTitleForUndoActionName:(NSString *)name;
@end

#define NSAssert(cond, desc, ...) do { if (!(cond)) [NSException raise:NSInternalInconsistencyException format:(desc), ##__VA_ARGS__]; } while (0)
#define NSParameterAssert(cond) NSAssert((cond), @"Invalid parameter not satisfying: %s", #cond)
#define NSCAssert NSAssert

#endif
