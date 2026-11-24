/* SPDX-License-Identifier: GPL-3.0-or-later
 * The program of a plug-in bundle (Greeter.bundle, built by run.sh with
 * -bundle) for the libsystem_plugin test. Its Info.plist names Greeter as
 * the principal class. */
#import <Foundation/Foundation.h>

@interface GreeterHelper : NSObject
@end
@implementation GreeterHelper
@end

@interface Greeter : NSObject
- (NSString *)greeting;
@end
@implementation Greeter
- (NSString *)greeting
{
    NSBundle *mine = [NSBundle bundleForClass:[self class]];
    return [NSString stringWithFormat:@"hello from %@", [mine objectForInfoDictionaryKey:@"CFBundleName"]];
}
@end

int greeter_answer(void) { return 42; }
const char greeter_word[] = "plug-in";
