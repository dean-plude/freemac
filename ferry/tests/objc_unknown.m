/* Sending a message nothing implements stops the program the way a Mac
 * does: doesNotRecognizeSelector: reports it and the program aborts. */
#include <stdio.h>
#include <objc/NSObject.h>

@interface Quiet : NSObject
@end
@implementation Quiet
@end

@interface Quiet (Missing)
- (void)speak;
@end

int main(void)
{
    Quiet *q = [Quiet new];
    printf("about to send speak\n");
    [q speak];
    printf("not reached\n");
    return 0;
}
