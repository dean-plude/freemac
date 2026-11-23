/* A program linked against a system framework Ferry doesn't have (M6):
 * it still starts, the framework's classes are nil, a class of the
 * program's own built on one of them is left out, string constants hold
 * their own names, and calling one of its functions stops the program
 * with that function's name. Imaginary.framework is only a description
 * (a .tbd) for the linker; no such framework exists anywhere. */
#import <Foundation/Foundation.h>

@interface IMThing : NSObject
@end
extern NSString *const NSImaginaryDidChangeNotification;
extern NSString *const kIMImaginaryKey;
void IMDoSomething(void);

@interface MyThing : IMThing
@end
@implementation MyThing
@end

int main(void)
{
    @autoreleasepool {
        printf("started\n");
        printf("IMThing is nil: %s\n", [IMThing class] == nil ? "yes" : "no");
        printf("a new IMThing is nil: %s\n", [IMThing new] == nil ? "yes" : "no");
        printf("MyThing is registered: %s\n", objc_getClass("MyThing") ? "yes" : "no");
        printf("notification name: %s\n", [NSImaginaryDidChangeNotification UTF8String]);
        NSDictionary *d = @{kIMImaginaryKey : @"value"};
        printf("constant as a key: %s\n", [[d objectForKey:@"kIMImaginaryKey"] UTF8String]);
        printf("calling IMDoSomething\n");
        fflush(stdout);
        IMDoSomething();
        printf("still running (should have stopped)\n");
    }
    return 0;
}
