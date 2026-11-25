/* SPDX-License-Identifier: GPL-3.0-or-later
 * Foundation names the nine apps' sources use that Ferry hadn't had
 * (freemac 1.221, Ferry 0.45.0): searching without accents or widths,
 * copying collections' items, byte order, JSON through streams, messages
 * for the run loop's next turn, the defaults' volatile domains, the file
 * manager's delegate, scripting commands made in the program, and the
 * older names of a few options. */
#import <Foundation/Foundation.h>

@interface Copyable : NSObject <NSCopying>
@property int copies;
@end
@implementation Copyable
- (id)copyWithZone:(NSZone *)zone
{
    self.copies++;
    return [Copyable new];
}
@end

@interface Listener : NSObject
@property (strong) NSMutableArray *heard;
@end
@implementation Listener
- (void)hear:(id)what { [self.heard addObject:what]; }
@end

@interface Careful : NSObject <NSFileManagerDelegate>
@property (strong) NSMutableArray *asked;
@end
@implementation Careful
- (BOOL)fileManager:(NSFileManager *)fm shouldRemoveItemAtPath:(NSString *)path
{
    [self.asked addObject:[@"remove " stringByAppendingString:path.lastPathComponent]];
    return ![path.lastPathComponent isEqual:@"keep"];
}
- (BOOL)fileManager:(NSFileManager *)fm shouldCopyItemAtURL:(NSURL *)src toURL:(NSURL *)dst
{
    [self.asked addObject:[@"copy " stringByAppendingString:src.lastPathComponent]];
    return YES;
}
@end

int main(void)
{
    @autoreleasepool {
        /* searching */
        NSString *text = @"Crème Brûlée at the CAFÉ";
        printf("accents: %lu, %lu, without the option %d, case and accents %lu, compare %d, width %lu\n",
               (unsigned long)[text rangeOfString:@"Creme" options:NSDiacriticInsensitiveSearch].location,
               (unsigned long)[text rangeOfString:@"Brulee" options:NSDiacriticInsensitiveSearch].location,
               [text rangeOfString:@"Brulee"].location == NSNotFound,
               (unsigned long)[text rangeOfString:@"cafe" options:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch]
                   .location,
               (int)[@"Été" compare:@"ete" options:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch],
               (unsigned long)[@"ＡＢＣ" rangeOfString:@"BC" options:NSWidthInsensitiveSearch].location);

        /* copying items */
        Copyable *c = [Copyable new];
        NSArray *a = [[NSArray alloc] initWithArray:@[ c ] copyItems:YES];
        NSDictionary *d = [[NSDictionary alloc] initWithDictionary:@{@"k" : c} copyItems:YES];
        NSSet *s = [[NSSet alloc] initWithSet:[NSSet setWithObject:c] copyItems:YES];
        NSArray *same = [[NSArray alloc] initWithArray:@[ c ] copyItems:NO];
        printf("copied: %d times, array %d, dictionary %d, set %d, not copied %d\n", c.copies, a[0] != c,
               d[@"k"] != c, [s anyObject] != c, same[0] == c);

        /* byte order */
        printf("byte order: host %ld, big int %08x, big short %04x, little %08x, double back %.2f\n",
               NSHostByteOrder(), NSSwapBigIntToHost(0x11223344), NSSwapBigShortToHost(0xAABB),
               NSSwapLittleIntToHost(0x11223344), NSSwapBigDoubleToHost(NSSwapHostDoubleToBig(2.5)));

        /* JSON through streams */
        NSInputStream *in = [NSInputStream inputStreamWithData:[@"{\"n\": [1, 2, 3]}" dataUsingEncoding:NSUTF8StringEncoding]];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithStream:in options:0 error:NULL];
        NSOutputStream *out = [NSOutputStream outputStreamToMemory];
        [out open];
        NSInteger written = [NSJSONSerialization writeJSONObject:@[ @"x" ] toStream:out options:0 error:NULL];
        NSData *wrote = [out propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
        printf("JSON from a stream: %lu numbers; to a stream: %ld bytes, %s\n", (unsigned long)[json[@"n"] count],
               (long)written, [[[NSString alloc] initWithData:wrote encoding:NSUTF8StringEncoding] UTF8String]);

        /* messages for the run loop's next turn, lowest order first */
        Listener *l = [Listener new];
        l.heard = [NSMutableArray array];
        NSRunLoop *loop = [NSRunLoop currentRunLoop];
        NSArray *modes = @[ NSDefaultRunLoopMode ];
        [loop performSelector:@selector(hear:) target:l argument:@"third" order:30 modes:modes];
        [loop performSelector:@selector(hear:) target:l argument:@"first" order:10 modes:modes];
        [loop performSelector:@selector(hear:) target:l argument:@"cancelled" order:20 modes:modes];
        [loop performSelector:@selector(hear:) target:l argument:@"second" order:20 modes:modes];
        [loop cancelPerformSelector:@selector(hear:) target:l argument:@"cancelled"];
        printf("before the turn: %lu heard\n", (unsigned long)l.heard.count);
        [loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("after it: %s\n", [[l.heard componentsJoinedByString:@" "] UTF8String]);
        [loop performSelector:@selector(hear:) target:l argument:@"never" order:0 modes:modes];
        [loop cancelPerformSelectorsWithTarget:l];
        [loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("all cancelled: %lu heard\n", (unsigned long)l.heard.count);

        /* the defaults' domains */
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults registerDefaults:@{@"Colour" : @"blue"}];
        [defaults setObject:@"red" forKey:@"Colour"];
        printf("registered %s, set %s", [[defaults volatileDomainForName:NSRegistrationDomain][@"Colour"] UTF8String],
               [[defaults stringForKey:@"Colour"] UTF8String]);
        [defaults setVolatileDomain:@{@"a" : @1} forName:@"Mine"];
        printf(", mine %s, names %lu", [[[defaults volatileDomainForName:@"Mine"][@"a"] description] UTF8String],
               (unsigned long)[defaults volatileDomainNames].count);
        [defaults removeVolatileDomainForName:@"Mine"];
        printf(", removed %lu\n", (unsigned long)[defaults volatileDomainForName:@"Mine"].count);
        [defaults removeObjectForKey:@"Colour"];

        /* the file manager's delegate, asked once for what it was given */
        NSFileManager *fm = [[NSFileManager alloc] init];
        Careful *careful = [Careful new];
        careful.asked = [NSMutableArray array];
        fm.delegate = careful;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-delegate"];
        [fm removeItemAtPath:dir error:NULL];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"inner"] withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        [@"x" writeToFile:[dir stringByAppendingPathComponent:@"inner/file"] atomically:NO encoding:NSUTF8StringEncoding
                    error:NULL];
        NSString *keep = [dir stringByAppendingPathComponent:@"keep"];
        [@"x" writeToFile:keep atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        BOOL kept = [fm removeItemAtPath:keep error:NULL] && [fm fileExistsAtPath:keep];
        BOOL copied = [fm copyItemAtPath:[dir stringByAppendingPathComponent:@"inner"]
                                  toPath:[dir stringByAppendingPathComponent:@"copy"]
                                   error:NULL];
        BOOL removed = [fm removeItemAtPath:dir error:NULL] && ![fm fileExistsAtPath:dir];
        printf("delegate: kept %d, copied %d, removed %d, asked: %s\n", kept, copied, removed,
               [[careful.asked componentsJoinedByString:@", "] UTF8String]);

        /* a scripting command made in the program */
        NSScriptCommand *command = [[NSScriptCommand alloc] initWithCommandDescription:nil];
        command.directParameter = @"window 1";
        command.arguments = @{@"saving" : @"no"};
        command.scriptErrorNumber = NSArgumentsWrongScriptError;
        printf("script command: current %s, direct %s, evaluated %s, runs to %s, error %ld\n",
               [NSScriptCommand currentCommand] ? "some" : "none", [command.directParameter UTF8String],
               [command.evaluatedArguments[@"saving"] UTF8String], [command executeCommand] ? "something" : "nil",
               (long)command.scriptErrorNumber);

        /* older names */
        printf("names: mapped %d, uncached %d, atomic %d, change key %s, localized %s\n",
               NSMappedRead == NSDataReadingMappedIfSafe, NSUncachedRead == NSDataReadingUncached,
               NSAtomicWrite == NSDataWritingAtomic, [(NSKeyValueChangeKey)NSKeyValueChangeNewKey UTF8String],
               [NSLocalizedStringFromTable(@"Untranslated", @"Other", @"a comment") UTF8String]);
    }
    return 0;
}
