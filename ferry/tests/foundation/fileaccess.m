/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.219, Ferry 0.43.0): the file calls Gas Mask,
 * MacDown, Sequel Pro and MacPass make. Directory enumerators by path and
 * by URL (skipping descendants, hidden files and package contents, the
 * level and the attributes), display names, the attributes set and read
 * back, hard and symbolic links, URL resource values, reachability and its
 * error, the trash (the freedesktop.org one, in a data folder of the test's
 * own), bundle resources by URL, and a file coordinator telling a presenter
 * about a write. run.sh gives the test a home of its own. */
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *yn(BOOL b) { return b ? "yes" : "no"; }

@interface Watcher : NSObject <NSFilePresenter>
@property (copy) NSURL *presentedItemURL;
@property (retain) NSOperationQueue *presentedItemOperationQueue;
@property int changes, relinquished;
@end
@implementation Watcher
- (void)relinquishPresentedItemToWriter:(void (^)(void (^)(void)))writer
{
    self.relinquished++;
    writer(^{
    });
}
- (void)presentedItemDidChange { self.changes++; }
@end

int main(void)
{
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *home = [NSString stringWithUTF8String:getenv("HOME")];
        NSString *root = [home stringByAppendingPathComponent:@"tree"];
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"b/deep"] withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"Thing.app/Contents/Resources/sub"]
            withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *f in @[ @"a.txt", @"b/one.txt", @"b/deep/two.txt", @".hidden", @"Thing.app/Contents/Info.plist", @"Thing.app/Contents/Resources/sub/r.txt" ])
            [@"x" writeToFile:[root stringByAppendingPathComponent:f] atomically:NO encoding:NSUTF8StringEncoding
                        error:NULL];

        NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
        NSMutableArray *seen = [NSMutableArray array];
        for (NSString *p in e) {
            [seen addObject:[NSString stringWithFormat:@"%@(%lu)", p, (unsigned long)[e level]]];
            if ([p isEqualToString:@"a.txt"])
                printf("a.txt is a %s of %llu bytes\n",
                       [[e fileAttributes] fileType] == NSFileTypeRegular ? "regular file" : "something else",
                       [[e fileAttributes] fileSize]);
        }
        printf("by path: %s\n", [[seen componentsJoinedByString:@" "] UTF8String]);
        e = [fm enumeratorAtPath:root];
        [seen removeAllObjects];
        for (NSString *p in e) {
            [seen addObject:p];
            if ([p isEqualToString:@"b"])
                [e skipDescendants];
        }
        printf("skipping b: %s\n", [[seen componentsJoinedByString:@" "] UTF8String]);
        [seen removeAllObjects];
        NSDirectoryEnumerator *ue = [fm enumeratorAtURL:[NSURL fileURLWithPath:root]
                             includingPropertiesForKeys:@[ NSURLIsDirectoryKey ]
                                                options:NSDirectoryEnumerationSkipsHiddenFiles |
                                                        NSDirectoryEnumerationSkipsPackageDescendants
                                           errorHandler:nil];
        for (NSURL *u in ue)
            [seen addObject:[[u path] substringFromIndex:[root length] + 1]];
        printf("by URL, no hidden files or package contents: %s\n", [[seen componentsJoinedByString:@" "] UTF8String]);
        [seen removeAllObjects];
        for (NSURL *u in [fm enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:nil
                                     options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                errorHandler:nil])
            [seen addObject:[u lastPathComponent]];
        printf("top level only: %s\n", [[seen componentsJoinedByString:@" "] UTF8String]);
        __block int errors = 0;
        NSDirectoryEnumerator *missing = [fm enumeratorAtURL:[NSURL fileURLWithPath:@"/no/such/dir"]
                                  includingPropertiesForKeys:nil
                                                     options:0
                                                errorHandler:^BOOL(NSURL *url, NSError *error) {
                                                    errors++;
                                                    return YES;
                                                }];
        printf("missing directory: first object %s, errors %d\n", [missing nextObject] ? "something" : "nil", errors);

        printf("display names: %s, %s, %s\n", [[fm displayNameAtPath:[root stringByAppendingPathComponent:@"Thing.app"]] UTF8String],
               [[fm displayNameAtPath:[root stringByAppendingPathComponent:@"a.txt"]] UTF8String],
               [[[fm componentsToDisplayForPath:[root stringByAppendingPathComponent:@"b/one.txt"]]
                   subarrayWithRange:NSMakeRange(0, 0)] count] == 0 ? "components ok" : "?");
        NSArray *comps = [fm componentsToDisplayForPath:[root stringByAppendingPathComponent:@"b/one.txt"]];
        printf("last components: %s\n",
               [[[comps subarrayWithRange:NSMakeRange([comps count] - 3, 3)] componentsJoinedByString:@" > "] UTF8String]);

        /* Attributes. */
        NSString *a = [root stringByAppendingPathComponent:@"a.txt"];
        NSDate *when = [NSDate dateWithTimeIntervalSince1970:1000000000];
        BOOL set = [fm setAttributes:@{NSFilePosixPermissions : @0640, NSFileModificationDate : when} ofItemAtPath:a
                               error:NULL];
        NSDictionary *attrs = [fm attributesOfItemAtPath:a error:NULL];
        printf("set: %s, permissions %lo, modified %.0f, links %lu, owner is me %s\n", yn(set),
               (unsigned long)[attrs filePosixPermissions], [[attrs fileModificationDate] timeIntervalSince1970],
               (unsigned long)[[attrs objectForKey:NSFileReferenceCount] unsignedLongValue],
               yn([[attrs fileOwnerAccountID] unsignedIntValue] == getuid()));
        NSString *hard = [root stringByAppendingPathComponent:@"hard.txt"];
        BOOL linked = [fm linkItemAtPath:a toPath:hard error:NULL];
        printf("hard link: %s, links now %lu, same file number %s\n", yn(linked),
               (unsigned long)[[[fm attributesOfItemAtPath:a error:NULL] objectForKey:NSFileReferenceCount] unsignedLongValue],
               yn([[fm attributesOfItemAtPath:a error:NULL] fileSystemFileNumber] ==
                  [[fm attributesOfItemAtPath:hard error:NULL] fileSystemFileNumber]));
        NSURL *sym = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"sym"]];
        BOOL madeSym = [fm createSymbolicLinkAtURL:sym withDestinationURL:[NSURL fileURLWithPath:a] error:NULL];
        printf("symbolic link: %s, points at a.txt %s\n", yn(madeSym),
               yn([[[fm destinationOfSymbolicLinkAtPath:[sym path] error:NULL] lastPathComponent] isEqualToString:@"a.txt"]));

        /* Resource values. */
        NSURL *au = [NSURL fileURLWithPath:a];
        id v = nil;
        NSError *err = nil;
        [au getResourceValue:&v forKey:NSURLFileSizeKey error:NULL];
        printf("size %s", [[v description] UTF8String]);
        [au getResourceValue:&v forKey:NSURLIsDirectoryKey error:NULL];
        printf(", directory %s", [[v description] UTF8String]);
        [au getResourceValue:&v forKey:NSURLNameKey error:NULL];
        printf(", name %s", [v UTF8String]);
        [[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Thing.app"]] getResourceValue:&v
                                                                                             forKey:NSURLIsPackageKey
                                                                                              error:NULL];
        printf(", Thing.app a package %s", [[v description] UTF8String]);
        [[NSURL fileURLWithPath:[root stringByAppendingPathComponent:@".hidden"]] getResourceValue:&v
                                                                                           forKey:NSURLIsHiddenKey
                                                                                            error:NULL];
        printf(", .hidden hidden %s", [[v description] UTF8String]);
        [sym getResourceValue:&v forKey:NSURLIsSymbolicLinkKey error:NULL];
        printf(", sym a link %s\n", [[v description] UTF8String]);
        [au getResourceValue:&v forKey:NSURLParentDirectoryURLKey error:NULL];
        printf("parent is tree: %s\n", yn([[v lastPathComponent] isEqualToString:@"tree"]));
        NSDictionary *rv = [au resourceValuesForKeys:@[ NSURLIsRegularFileKey, NSURLContentModificationDateKey ]
                                               error:NULL];
        printf("several: regular %s, modified %.0f\n", [[[rv objectForKey:NSURLIsRegularFileKey] description] UTF8String],
               [[rv objectForKey:NSURLContentModificationDateKey] timeIntervalSince1970]);
        printf("reachable: %s", yn([au checkResourceIsReachableAndReturnError:NULL]));
        BOOL r = [[NSURL fileURLWithPath:@"/no/such/file"] checkResourceIsReachableAndReturnError:&err];
        printf(", missing: %s (%s %ld)", yn(r), [[err domain] UTF8String], (long)[err code]);
        err = nil;
        r = [[NSURL URLWithString:@"https://example.org/"] checkResourceIsReachableAndReturnError:&err];
        printf(", web: %s (%ld)\n", yn(r), (long)[err code]);
        printf("file path URL is itself: %s, reference URL: %s\n", yn([[au filePathURL] isEqual:au]),
               yn([au isFileReferenceURL]));
        printf("from components: %s\n", [[[NSURL fileURLWithPathComponents:@[ @"/", @"tmp", @"x y" ]] absoluteString]
                                            UTF8String]);
        BOOL hid = [au setResourceValue:@YES forKey:NSURLHasHiddenExtensionKey error:NULL];
        printf("a resource value Ferry does not keep (hidden extension) accepted: %s\n", yn(hid));

        /* Data written through a URL. */
        NSURL *du = [NSURL fileURLWithPath:[home stringByAppendingPathComponent:@"data.bin"]];
        BOOL wrote = [[@"hello" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:du options:NSDataWritingAtomic
                                                                              error:NULL];
        printf("wrote through a URL: %s, then %s\n", yn(wrote),
               [[NSString stringWithContentsOfURL:du encoding:NSUTF8StringEncoding error:NULL] UTF8String]);
        err = nil;
        wrote = [[NSData data] writeToURL:[NSURL fileURLWithPath:@"/no/such/dir/f"] options:0 error:&err];
        printf("into a missing folder: %s, an error %s\n", yn(wrote), yn(err != nil));

        /* The trash. */
        NSURL *trashed = nil;
        NSString *doomed = [root stringByAppendingPathComponent:@"b/one.txt"];
        BOOL t = [fm trashItemAtURL:[NSURL fileURLWithPath:doomed] resultingItemURL:&trashed error:NULL];
        NSString *trashDir = [home stringByAppendingPathComponent:@".local/share/Trash"];
        printf("trashed: %s, gone %s, now in the trash %s, info written %s\n", yn(t), yn(![fm fileExistsAtPath:doomed]),
               yn([[trashed path] isEqualToString:[trashDir stringByAppendingPathComponent:@"files/one.txt"]]),
               yn([fm fileExistsAtPath:[trashDir stringByAppendingPathComponent:@"info/one.txt.trashinfo"]]));
        NSString *info = [NSString stringWithContentsOfFile:[trashDir stringByAppendingPathComponent:@"info/one.txt.trashinfo"]
                                                   encoding:NSUTF8StringEncoding error:NULL];
        printf("info names the old path: %s\n", yn([info rangeOfString:@"Path="].location != NSNotFound &&
                                                   [info rangeOfString:@"tree/b/one.txt"].location != NSNotFound));
        [@"y" writeToFile:doomed atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        [fm trashItemAtURL:[NSURL fileURLWithPath:doomed] resultingItemURL:&trashed error:NULL];
        printf("a second one.txt goes in as %s\n", [[trashed lastPathComponent] UTF8String]);

        /* Bundles by URL. */
        NSURL *bu = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"Thing.app"]];
        NSURL *res = [NSBundle URLForResource:@"r" withExtension:@"txt" subdirectory:@"sub" inBundleWithURL:bu];
        printf("resource by URL found: %s\n", yn([[res path] hasSuffix:@"Thing.app/Contents/Resources/sub/r.txt"]));
        NSArray *all = [[NSBundle bundleWithURL:bu] URLsForResourcesWithExtension:@"txt" subdirectory:@"sub"];
        printf("resources with the extension: %lu\n", (unsigned long)[all count]);

        /* A coordinator and a presenter. */
        Watcher *w = [Watcher new];
        w.presentedItemURL = au;
        w.presentedItemOperationQueue = [NSOperationQueue new];
        [NSFileCoordinator addFilePresenter:w];
        printf("presenters: %lu\n", (unsigned long)[[NSFileCoordinator filePresenters] count]);
        NSFileCoordinator *c = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block BOOL ran = NO;
        [c coordinateWritingItemAtURL:au options:0 error:NULL byAccessor:^(NSURL *u) {
            ran = YES;
            [@"new" writeToURL:u atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        }];
        [w.presentedItemOperationQueue waitUntilAllOperationsAreFinished];
        printf("write ran: %s, presenter let go %d time(s) and heard of %d change(s)\n", yn(ran), w.relinquished,
               w.changes);
        NSFileCoordinator *own = [[NSFileCoordinator alloc] initWithFilePresenter:w];
        [own coordinateWritingItemAtURL:au options:0 error:NULL byAccessor:^(NSURL *u) {
        }];
        [w.presentedItemOperationQueue waitUntilAllOperationsAreFinished];
        printf("its own coordinator's write isn't told to it: %d change(s)\n", w.changes);
        __block NSString *read = nil;
        [c coordinateReadingItemAtURL:au options:0 error:NULL byAccessor:^(NSURL *u) {
            read = [NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:NULL];
        }];
        printf("read: %s\n", [read UTF8String]);
        [NSFileCoordinator removeFilePresenter:w];
        printf("presenters after removing: %lu\n", (unsigned long)[[NSFileCoordinator filePresenters] count]);
    }
    @autoreleasepool {
        /* the mounted volumes, the system disk first (Godot's file dialogs) */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *all = [fm mountedVolumeURLsIncludingResourceValuesForKeys:@[ NSURLVolumeNameKey ] options:0];
        NSArray *shown = [fm mountedVolumeURLsIncludingResourceValuesForKeys:nil
                                                                     options:NSVolumeEnumerationSkipHiddenVolumes];
        BOOL urls = YES;
        for (NSURL *u in all)
            urls = urls && [u isFileURL];
        printf("volumes: first %s, all file URLs %s, shown ones no more than all %s\n",
               [[all.firstObject path] UTF8String], yn(urls), yn(shown.count >= 1 && shown.count <= all.count));
    }
    return 0;
}
