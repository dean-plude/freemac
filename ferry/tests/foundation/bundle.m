/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: a program inside a Mac app bundle (Hello.app) finds its
 * Info.plist, resources and localized strings through NSBundle, and its
 * preferences are named after its bundle identifier. run.sh copies
 * tests/foundation/Hello.app and puts this program at Contents/MacOS/Hello. */
#import <Foundation/Foundation.h>

int main(void)
{
    @autoreleasepool {
        NSBundle *b = [NSBundle mainBundle];
        printf("bundle %s\n", [[[b bundlePath] lastPathComponent] UTF8String]);
        printf("identifier %s, version %s\n", [[b bundleIdentifier] UTF8String],
               [[b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String]);
        printf("executable ends with Contents/MacOS/Hello: %d\n", [[b executablePath] hasSuffix:@"Contents/MacOS/Hello"]);
        printf("resources ends with Contents/Resources: %d\n", [[b resourcePath] hasSuffix:@"Contents/Resources"]);
        NSString *data = [b pathForResource:@"data" ofType:@"txt"];
        printf("data.txt: %s", [[NSString stringWithContentsOfFile:data encoding:NSUTF8StringEncoding error:NULL] UTF8String]);
        printf("missing resource nil: %d\n", [b pathForResource:@"nothing" ofType:@"png"] == nil);
        printf("strings file in %s\n",
               [[[[b pathForResource:@"Localizable" ofType:@"strings"] stringByDeletingLastPathComponent] lastPathComponent]
                   UTF8String]);
        printf("greeting: %s\n", [NSLocalizedString(@"greeting", @"") UTF8String]);
        printf("farewell: %s\n", [NSLocalizedString(@"farewell", @"") UTF8String]);
        printf("untranslated: %s\n", [NSLocalizedString(@"Untranslated key", @"") UTF8String]);
        printf("CFBundle identifier %s\n", [(NSString *)CFBundleGetIdentifier(CFBundleGetMainBundle()) UTF8String]);
        [[NSUserDefaults standardUserDefaults] setObject:@"saved" forKey:@"where"];
        NSString *prefs = [NSHomeDirectory() stringByAppendingPathComponent:
                                                 @".config/ferry/preferences/org.freemac.ferry.hello.plist"];
        printf("preferences named after the bundle: %d\n", [[NSFileManager defaultManager] fileExistsAtPath:prefs]);
    }
    return 0;
}
