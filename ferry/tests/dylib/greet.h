#include <objc/NSObject.h>
extern int greet_count;
int greet_add(int a, int b);
@interface Greeter : NSObject
- (const char *)hello;
- (int)times:(int)n;
@end
