/* A small Mac library for the dylib test: a C function, a global, a
 * constructor and an Objective-C class. */
#include <stdio.h>
#include <objc/NSObject.h>
#include "greet.h"

int greet_count = 0;

__attribute__((constructor)) static void greet_setup(void)
{
    greet_count = 100;
    printf("library initializer ran\n");
}

int greet_add(int a, int b) { return a + b + greet_count; }

@implementation Greeter
+ (void)load { printf("+load Greeter (library)\n"); }
- (const char *)hello { return "hello from the library"; }
- (int)times:(int)n { greet_count++; return n * 2; }
@end
