/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry M2 test: property lists, NSFileManager, NSUserDefaults, NSURL,
 * NSDate, NSError and NSProcessInfo. run.sh points HOME at an empty folder. */
#import <Foundation/Foundation.h>

static void show(const char *label, id value) { printf("%s: %s\n", label, [[value description] UTF8String]); }
static const char *tilde(NSString *path) { return [[path stringByAbbreviatingWithTildeInPath] UTF8String]; }

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *home = NSHomeDirectory();
        printf("home is HOME: %d\n", [home isEqualToString:[[[NSProcessInfo processInfo] environment] objectForKey:@"HOME"]]);

        /* property lists */
        NSDictionary *plist = @{@"name": @"Ferry & <friends>", @"count": @3, @"ratio": @0.5, @"on": @YES,
                                @"list": @[@"a", @1, @{}], @"blob": [@"hi" dataUsingEncoding:NSUTF8StringEncoding],
                                @"when": [NSDate dateWithTimeIntervalSince1970:1700000000], @"unicode": @"\u00e9t\u00e9"};
        NSError *err = nil;
        NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0
                                                                options:0 error:&err];
        fwrite([xml bytes], 1, [xml length], stdout);
        NSPropertyListFormat fmt = 0;
        id back = [NSPropertyListSerialization propertyListWithData:xml options:0 format:&fmt error:&err];
        printf("xml round trip %d format %lu\n", [back isEqual:plist], (unsigned long)fmt);
        NSData *bin = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0
                                                                options:0 error:&err];
        printf("binary starts %.8s\n", (const char *)[bin bytes]);
        back = [NSPropertyListSerialization propertyListWithData:bin options:NSPropertyListMutableContainers format:&fmt
                                                           error:&err];
        printf("binary round trip %d format %lu mutable %d\n", [back isEqual:plist], (unsigned long)fmt,
               [back isKindOfClass:[NSMutableDictionary class]]);
        NSString *old = @"{ title = \"Old style\"; items = (one, \"two words\", <0a0b>); /* comment */ n = 12; }";
        show("openstep", [NSPropertyListSerialization propertyListWithData:[old dataUsingEncoding:NSUTF8StringEncoding]
                                                                   options:0 format:&fmt error:&err]);
        NSString *strings = @"/* Localizable.strings */\n\"Hello\" = \"Bonjour\";\n\"Quote\" = \"\\\"q\\\"\\n\";\n";
        show("strings", [NSPropertyListSerialization propertyListWithData:[strings dataUsingEncoding:NSUTF8StringEncoding]
                                                                  options:0 format:&fmt error:&err]);
        id bad = [NSPropertyListSerialization propertyListWithData:[@"<plist><dict><key>x</key></dict></plist>"
                                                                       dataUsingEncoding:NSUTF8StringEncoding]
                                                           options:0 format:&fmt error:&err];
        printf("bad plist %d, error %s %ld\n", bad == nil, [[err domain] UTF8String], (long)[err code]);

        /* files */
        NSString *dir = [home stringByAppendingPathComponent:@"work/deep/er"];
        printf("mkdir %d\n", [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]);
        NSString *file = [dir stringByAppendingPathComponent:@"note.txt"];
        printf("write %d\n", [@"line one\nline two\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        BOOL isDir = YES;
        printf("exists %d dir %d\n", [fm fileExistsAtPath:file isDirectory:&isDir], isDir);
        NSDictionary *attrs = [fm attributesOfItemAtPath:file error:NULL];
        printf("size %llu type %s\n", [attrs fileSize], [[attrs fileType] UTF8String]);
        printf("read back: %s", [[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:NULL] UTF8String]);
        [fm copyItemAtPath:file toPath:[dir stringByAppendingPathComponent:@"copy.txt"] error:NULL];
        [fm moveItemAtPath:[dir stringByAppendingPathComponent:@"copy.txt"]
                    toPath:[dir stringByAppendingPathComponent:@"moved.txt"] error:NULL];
        show("listing", [fm contentsOfDirectoryAtPath:dir error:NULL]);
        show("subpaths", [fm subpathsOfDirectoryAtPath:[home stringByAppendingPathComponent:@"work"] error:NULL]);
        printf("copy onto existing %d: %s\n",
               [fm copyItemAtPath:file toPath:[dir stringByAppendingPathComponent:@"moved.txt"] error:&err],
               [[err localizedDescription] UTF8String]);
        printf("missing file %d: %s (code %ld)\n",
               [NSData dataWithContentsOfFile:@"/nonexistent/x" options:0 error:&err] != nil,
               [[err localizedDescription] UTF8String], (long)[err code]);
        printf("remove %d, gone %d\n", [fm removeItemAtPath:[home stringByAppendingPathComponent:@"work"] error:NULL],
               ![fm fileExistsAtPath:dir]);
        printf("dict file %d\n", [@{@"k": @"v"} writeToFile:[home stringByAppendingPathComponent:@"d.plist"] atomically:YES]);
        show("dict read", [NSDictionary dictionaryWithContentsOfFile:[home stringByAppendingPathComponent:@"d.plist"]]);

        /* standard folders */
        printf("documents %s\n", tilde([NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]));
        printf("app support %s\n", tilde([[[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask]
                                              firstObject] path]));
        printf("caches %s\n", [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, NO) firstObject] UTF8String]);
        /* the computer's own folders, as OBS's libobs asks for its program data (freemac 1.239) */
        printf("local app support %s\n", [[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                              NSLocalDomainMask, YES) componentsJoinedByString:@" "] UTF8String]);
        printf("all app support %s\n", tilde([NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                              NSAllDomainsMask, YES) componentsJoinedByString:@" "]));
        printf("local applications %s, system documents %lu\n",
               [[[[fm URLsForDirectory:NSApplicationDirectory inDomains:NSLocalDomainMask] firstObject] path] UTF8String],
               (unsigned long)[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSSystemDomainMask, YES) count]);

        /* user defaults: written through to ~/.config/ferry/preferences */
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{@"volume": @7, @"theme": @"light"}];
        printf("registered %ld %s\n", (long)[defaults integerForKey:@"volume"], [[defaults stringForKey:@"theme"] UTF8String]);
        [defaults setInteger:11 forKey:@"volume"];
        [defaults setBool:YES forKey:@"enabled"];
        [defaults setObject:@[@"recent1", @"recent2"] forKey:@"recent"];
        [defaults setDouble:1.5 forKey:@"zoom"];
        printf("set %ld %d %s %.1f\n", (long)[defaults integerForKey:@"volume"], [defaults boolForKey:@"enabled"],
               [[[defaults arrayForKey:@"recent"] lastObject] UTF8String], [defaults doubleForKey:@"zoom"]);
        /* a program outside an app bundle is named by its process name */
        NSString *prefs = [[home stringByAppendingPathComponent:@".config/ferry/preferences"]
            stringByAppendingPathComponent:[[[NSProcessInfo processInfo] processName] stringByAppendingString:@".plist"]];
        show("stored", [NSDictionary dictionaryWithContentsOfFile:prefs]);
        [NSUserDefaults resetStandardUserDefaults];
        printf("reloaded %ld, missing key %ld\n", (long)[[NSUserDefaults standardUserDefaults] integerForKey:@"volume"],
               (long)[[NSUserDefaults standardUserDefaults] integerForKey:@"nothing"]);
        printf("from arguments %s\n", [[[NSUserDefaults standardUserDefaults] stringForKey:@"Mode"] UTF8String]);

        /* the CFPreferences calls read and write the same store */
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("volume"), kCFPreferencesCurrentApplication);
        Boolean valid;
        printf("CFPreferences volume %s, enabled %d\n", [[(id)v description] UTF8String],
               CFPreferencesGetAppBooleanValue(CFSTR("enabled"), kCFPreferencesCurrentApplication, &valid));
        CFRelease(v);
        CFPreferencesSetAppValue(CFSTR("fromCF"), CFSTR("yes"), kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        printf("set from CF %s\n", [[[NSUserDefaults standardUserDefaults] stringForKey:@"fromCF"] UTF8String]);
        CFArrayRef keys = CFPreferencesCopyKeyList(kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser,
                                                   kCFPreferencesAnyHost);
        printf("keys %s\n", [[[(NSArray *)keys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]
                                 UTF8String]);
        CFRelease(keys);
        CFPreferencesSetAppValue(CFSTR("other"), CFSTR("x"), CFSTR("org.example.Other"));
        printf("another app %s, ours %s\n",
               [[(id)CFPreferencesCopyAppValue(CFSTR("other"), CFSTR("org.example.Other")) autorelease] UTF8String],
               CFPreferencesCopyAppValue(CFSTR("other"), kCFPreferencesCurrentApplication) ? "set" : "unset");
        printf("compare: %d %d %d %d\n", [@3 isLessThan:@4], [@"b" isGreaterThanOrEqualTo:@"a"], [@"a" isEqualTo:@"a"],
               [[NSObject new] isLessThan:@1]);

        /* URLs */
        NSURL *u = [NSURL URLWithString:@"https://user@example.com:8443/a/b/c.html?x=1&y=2#top"];
        printf("url %s | %s | %s | %s | %s | %s | %s | %s\n", [[u scheme] UTF8String], [[u host] UTF8String],
               [[[u port] description] UTF8String], [[u path] UTF8String], [[u query] UTF8String],
               [[u fragment] UTF8String], [[u lastPathComponent] UTF8String], [[u pathExtension] UTF8String]);
        show("relative", [[NSURL URLWithString:@"../d/e.png" relativeToURL:u] absoluteString]);
        NSURL *f = [NSURL fileURLWithPath:@"/tmp/some file.txt"];
        printf("file url %s path %s isFile %d\n", [[f absoluteString] UTF8String], [[f path] UTF8String], [f isFileURL]);
        show("appended", [[NSURL URLWithString:@"file:///tmp/"] URLByAppendingPathComponent:@"x.txt"]);
        printf("bad url nil %d\n", [NSURL URLWithString:@"has space"] == nil);

        /* dates */
        NSDate *epoch = [NSDate dateWithTimeIntervalSince1970:0];
        NSDate *later = [epoch dateByAddingTimeInterval:86400 * 365.25 * 30];
        show("epoch", epoch);
        show("later", later);
        printf("reference %.0f, since %.0f, compare %ld, now is recent %d\n", [epoch timeIntervalSinceReferenceDate],
               [later timeIntervalSinceDate:epoch], (long)[epoch compare:later],
               fabs([[NSDate date] timeIntervalSinceNow]) < 5);

        /* errors and process */
        NSError *e = [NSError errorWithDomain:@"MyDomain" code:7 userInfo:@{NSLocalizedDescriptionKey: @"Broke"}];
        show("error", e);
        NSProcessInfo *pi = [NSProcessInfo processInfo];
        printf("process %s args %lu last %s pid ok %d cpus ok %d\n", [[pi processName] UTF8String],
               (unsigned long)[[pi arguments] count], [[[pi arguments] lastObject] UTF8String],
               [pi processIdentifier] > 0, [pi processorCount] > 0);
        printf("unique strings differ %d\n", ![[pi globallyUniqueString] isEqualToString:[pi globallyUniqueString]]);
    }
    return 0;
}
