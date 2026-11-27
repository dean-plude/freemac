/* SPDX-License-Identifier: GPL-3.0-or-later
 * Literal numbers and arrays that newer clang writes into a program as
 * objects of their own (NSConstantIntegerNumber, NSConstantArray), and the
 * empty array and booleans it refers to by their storage. OBS's own download
 * holds these in Qt and its plugins (freemac 1.263). The objects are laid out
 * here by hand, as they sit in those programs: the class, then the fields. */
#import <Foundation/Foundation.h>

extern char number_class __asm__("_OBJC_CLASS_$_NSConstantIntegerNumber");
extern char array_class __asm__("_OBJC_CLASS_$_NSConstantArray");
extern char empty_array __asm__("___NSArray0__struct");
extern char true_storage __asm__("___kCFBooleanTrue");
extern char false_storage __asm__("___kCFBooleanFalse");

struct number { void *isa; const char *encoding; long long value; };
struct array { void *isa; unsigned long count; void *const *objects; };

static struct number three = {&number_class, "i", 3};
static struct number big = {&number_class, "I", 1111970369};
static struct number minus = {&number_class, "q", -7};
static void *const items[] = {&three, &minus};
static struct array pair = {&array_class, 2, items};

int main(void)
{
    @autoreleasepool {
        NSNumber *n = (__bridge NSNumber *)(void *)&three;
        printf("class: %s, is a number: %s\n", object_getClassName(n), [n isKindOfClass:[NSNumber class]] ? "yes" : "no");
        printf("@3: %d, type %s, says %s\n", [n intValue], [n objCType], [[n description] UTF8String]);
        NSNumber *b = (__bridge NSNumber *)(void *)&big;
        printf("big: %u, type %s, double %.0f\n", [b unsignedIntValue], [b objCType], [b doubleValue]);
        NSNumber *m = (__bridge NSNumber *)(void *)&minus;
        printf("minus: %lld, type %s\n", [m longLongValue], [m objCType]);
        printf("@3 equals [NSNumber numberWithInt:3]: %s, and back: %s\n", [n isEqual:@3] ? "yes" : "no",
               [@3 isEqual:n] ? "yes" : "no");
        printf("compare -7 with 3: %ld, hash matches: %s\n", (long)[m compare:n], [n hash] == [@3 hash] ? "yes" : "no");
        [n retain];
        [n release];
        [n release];
        printf("still there after release: %d\n", [n intValue]);
        NSDictionary *d = @{n : @"three"};
        printf("as a dictionary key: %s\n", [d[@3] UTF8String]);

        NSArray *a = (__bridge NSArray *)(void *)&pair;
        printf("array: %lu items, first %d, last %d, contains @-7: %s\n", (unsigned long)[a count],
               [[a objectAtIndex:0] intValue], [[a lastObject] intValue], [a containsObject:@-7] ? "yes" : "no");
        printf("array says %s\n", [[[a componentsJoinedByString:@","] description] UTF8String]);
        NSMutableArray *copy = [a mutableCopy];
        [copy addObject:@9];
        printf("mutable copy: %lu items\n", (unsigned long)[copy count]);
        @try {
            [a objectAtIndex:2];
        } @catch (NSException *e) {
            printf("out of range: %s\n", [[e name] UTF8String]);
        }

        NSArray *e = (__bridge NSArray *)(void *)&empty_array;
        printf("empty array: %lu items, is an array: %s\n", (unsigned long)[e count],
               [e isKindOfClass:[NSArray class]] ? "yes" : "no");
        printf("true storage is kCFBooleanTrue: %s, false: %s\n",
               (void *)&true_storage == (void *)kCFBooleanTrue ? "yes" : "no",
               (void *)&false_storage == (void *)kCFBooleanFalse ? "yes" : "no");
        printf("@YES is it: %s, boolValue %d\n", (void *)@YES == (void *)&true_storage ? "yes" : "no",
               [(__bridge NSNumber *)(void *)&true_storage boolValue]);
    }
    return 0;
}
