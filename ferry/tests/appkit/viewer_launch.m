/* SPDX-License-Identifier: GPL-3.0-or-later
 * An app that keeps the shared document controller only for its recent
 * documents, with no document class (VLC), opens nothing untitled at
 * launch and shows no error. */
#import <Cocoa/Cocoa.h>

@interface Recents : NSDocumentController
@end
@implementation Recents
- (BOOL)presentError:(NSError *)error
{
    printf("error shown: %s\n", [[error localizedDescription] UTF8String]);
    return NO;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        Recents *dc = [[Recents alloc] init];
        printf("shared controller is ours: %d\n", [NSDocumentController sharedDocumentController] == dc);
        printf("default type: %s\n", [dc defaultType] ? [[dc defaultType] UTF8String] : "(none)");
        [NSApp finishLaunching];
        printf("launched: documents %lu\n", (unsigned long)[[dc documents] count]);
    }
    return 0;
}
