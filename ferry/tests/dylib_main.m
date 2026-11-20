/* A program that uses a Mac library (dylib) found through @rpath: a C
 * function and a global from it, a class it defines, a subclass of that
 * class here, and a category added here to the library's class. */
#include <stdio.h>
#include "dylib/greet.h"

@interface Loud : Greeter
@end
@implementation Loud
+ (void)load { printf("+load Loud (program)\n"); }
- (const char *)hello { return "HELLO FROM THE PROGRAM"; }
@end

@interface Greeter (Extra)
- (const char *)extra;
@end
@implementation Greeter (Extra)
- (const char *)extra { return "category from the program"; }
@end

int main(void)
{
    printf("main starts, count %d\n", greet_count);
    printf("add %d\n", greet_add(1, 2));
    Greeter *g = [Greeter new];
    printf("%s, %d\n", [g hello], [g times:21]);
    printf("count now %d\n", greet_count);
    printf("%s\n", [g extra]);
    Greeter *l = [Loud new];
    printf("%s, %s\n", [l hello], [l extra]);
    printf("Loud is a Greeter: %d\n", [l isKindOfClass:[Greeter class]]);
    return 0;
}
