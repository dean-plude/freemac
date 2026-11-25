/* SPDX-License-Identifier: GPL-3.0-or-later
 * File references and the trash (freemac 1.221, Ferry 0.45.0): the File
 * Manager calls of CoreServices that Gas Mask and Sequel Pro make, a file
 * reference made from a path and from a URL, the path back, comparing two,
 * and moving files to the trash (the desktop's, in a home of the test's
 * own). */
#import <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>

int main(void)
{
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        NSString *file = [home stringByAppendingPathComponent:@"hosts.txt"];
        NSString *dir = [home stringByAppendingPathComponent:@"folder"];
        [@"127.0.0.1 localhost\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        chdir([home fileSystemRepresentation]);

        FSRef ref, same, other;
        Boolean isDir = true;
        OSStatus r = FSPathMakeRef((const UInt8 *)[file fileSystemRepresentation], &ref, &isDir);
        printf("file: %d, directory %d\n", (int)r, isDir);
        r = FSPathMakeRef((const UInt8 *)"folder/../folder", &other, &isDir);
        printf("folder (relative): %d, directory %d\n", (int)r, isDir);
        printf("missing: %d, empty: %d\n", (int)FSPathMakeRef((const UInt8 *)"/no/such/file", &same, NULL),
               (int)FSPathMakeRef((const UInt8 *)"", &same, NULL));

        UInt8 path[1024];
        r = FSRefMakePath(&other, path, sizeof path);
        printf("path back: %d, is the folder %d\n", (int)r, [@((char *)path) isEqual:dir]);
        printf("small buffer: %d\n", (int)FSRefMakePath(&ref, path, 4));
        FSRef junk;
        memset(&junk, 0x5a, sizeof junk);
        printf("not a reference: %d\n", (int)FSRefMakePath(&junk, path, sizeof path));

        CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:file];
        printf("from URL: %d, same as from path: %d, different: %d\n", CFURLGetFSRef(url, &same),
               (int)FSCompareFSRefs(&ref, &same), (int)FSCompareFSRefs(&ref, &other));
        printf("not a file URL: %d\n",
               CFURLGetFSRef((__bridge CFURLRef)[NSURL URLWithString:@"https://example.org/"], &junk));
        NSURL *back = CFBridgingRelease(CFURLCreateFromFSRef(NULL, &other));
        printf("URL back: %s, directory %d\n", [[back lastPathComponent] UTF8String], [back hasDirectoryPath]);

        FSRef trashed;
        r = FSMoveObjectToTrashSync(&ref, &trashed, kFSFileOperationDefaultOptions);
        r = r ?: FSRefMakePath(&trashed, path, sizeof path);
        NSString *where = @((char *)path);
        printf("to the trash: %d, gone %d, in the trash %d, named %s\n", (int)r,
               ![[NSFileManager defaultManager] fileExistsAtPath:file],
               [where rangeOfString:@"/Trash/files/"].location != NSNotFound, [[where lastPathComponent] UTF8String]);
        char *target = NULL;
        r = FSPathMoveObjectToTrashSync([dir fileSystemRepresentation], &target, kFSFileOperationDefaultOptions);
        printf("folder to the trash: %d, gone %d, named %s\n", (int)r,
               ![[NSFileManager defaultManager] fileExistsAtPath:dir], target ? strrchr(target, '/') + 1 : "(none)");
        free(target);
        printf("again: %d\n", (int)FSPathMoveObjectToTrashSync([dir fileSystemRepresentation], NULL, 0));

        UnsignedWide w = UInt64ToUnsignedWide(0x1122334455667788ULL);
        printf("wide %08x %08x, back %d\n", w.hi, w.lo, UnsignedWideToUInt64(w) == 0x1122334455667788ULL);
    }
    return 0;
}
