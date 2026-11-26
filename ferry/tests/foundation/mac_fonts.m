/* A Mac's Fonts folders (freemac 1.248, Ferry 0.71.0): the user's Library
 * Fonts folder, as NSSearchPathForDirectoriesInDomains gives the Library and
 * as ~/Library/Fonts, lists every font file in this system's user fonts
 * folder and the folders in it, by name, and each opens, stats and reads as
 * the file itself. OBS's Text source lists and opens fonts this way. */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

static void put(NSString *path, NSString *text)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}

int main(void)
{
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        NSString *mine = [home stringByAppendingPathComponent:@".local/share/fonts"];
        [[NSFileManager defaultManager] removeItemAtPath:mine error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[home stringByAppendingPathComponent:@".cache/freemac"] error:NULL];
        put([mine stringByAppendingPathComponent:@"Plain.ttf"], @"plain");
        put([mine stringByAppendingPathComponent:@"family/Bold.otf"], @"bold");
        put([mine stringByAppendingPathComponent:@"family/deeper/Set.ttc"], @"set");
        put([mine stringByAppendingPathComponent:@"family/README.txt"], @"not a font");

        NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
        NSString *fonts = [lib stringByAppendingPathComponent:@"Fonts"];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL dir = NO;
        BOOL there = [fm fileExistsAtPath:fonts isDirectory:&dir];
        printf("Library/Fonts: there %d, folder %d\n", there, dir);
        printf("lists: %s\n", [[[fm contentsOfDirectoryAtPath:fonts error:NULL] componentsJoinedByString:@" "] UTF8String]);

        NSString *bold = [fonts stringByAppendingPathComponent:@"Bold.otf"];
        FILE *f = fopen([bold fileSystemRepresentation], "r");
        char buf[32] = {0};
        if (f) {
            fgets(buf, sizeof buf, f);
            fclose(f);
        }
        struct stat st;
        int plain = lstat([[fonts stringByAppendingPathComponent:@"Plain.ttf"] fileSystemRepresentation], &st) == 0 &&
                    S_ISREG(st.st_mode);
        printf("Bold.otf reads \"%s\"; Plain.ttf is a file %d; README.txt there %d\n", buf, plain,
               [fm fileExistsAtPath:[fonts stringByAppendingPathComponent:@"README.txt"]]);

        NSString *mac = [home stringByAppendingPathComponent:@"Library/Fonts/Set.ttc"];
        NSData *d = [NSData dataWithContentsOfFile:mac];
        printf("~/Library/Fonts/Set.ttc reads \"%s\", readable %d\n",
               d ? [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] UTF8String] : "(nothing)",
               access([mac fileSystemRepresentation], R_OK) == 0);
        printf("missing font: %d\n", [fm fileExistsAtPath:[fonts stringByAppendingPathComponent:@"None.ttf"]]);
        printf("other Library folders as they were: %d\n",
               ![fm fileExistsAtPath:[lib stringByAppendingPathComponent:@"Fontsy"]]);
    }
    return 0;
}
