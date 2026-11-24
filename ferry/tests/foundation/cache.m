/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSCache (limits, least recently used first, the delegate,
 * keys that aren't copied, discardable content) and NSProgress (a tree of
 * progress, the current progress, fractionCompleted and its notifications,
 * cancelling and pausing). */
#import <Foundation/Foundation.h>

@interface Evictions : NSObject <NSCacheDelegate>
@end
@implementation Evictions
- (void)cache:(NSCache *)cache willEvictObject:(id)obj { printf("  evicting %s\n", [[obj description] UTF8String]); }
@end

/* A key that can't be copied: NSCache doesn't copy its keys. */
@interface Plain : NSObject
@property int n;
@end
@implementation Plain
- (NSUInteger)hash { return (NSUInteger)self.n; }
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[Plain class]] && ((Plain *)o).n == self.n; }
@end

@interface Discardable : NSObject <NSDiscardableContent>
@property BOOL gone;
@end
@implementation Discardable
- (BOOL)beginContentAccess { return !self.gone; }
- (void)endContentAccess {}
- (void)discardContentIfPossible { self.gone = YES; }
- (BOOL)isContentDiscarded { return self.gone; }
- (NSString *)description { return @"discardable"; }
@end

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)obj change:(NSDictionary *)change context:(void *)ctx
{
    printf("  %s: %s %s\n", (const char *)ctx, [path UTF8String], [[[obj valueForKey:path] description] UTF8String]);
}
@end

int main(void)
{
    @autoreleasepool {
        NSCache *cache = [[[NSCache alloc] init] autorelease];
        Evictions *ev = [[[Evictions alloc] init] autorelease];
        printf("defaults: name \"%s\", count limit %lu, cost limit %lu, evicts discarded %d\n",
               [[cache name] UTF8String], (unsigned long)[cache countLimit], (unsigned long)[cache totalCostLimit],
               [cache evictsObjectsWithDiscardedContent]);
        [cache setDelegate:ev];
        [cache setCountLimit:3];
        [cache setObject:@"one" forKey:@1];
        [cache setObject:@"two" forKey:@2];
        [cache setObject:@"three" forKey:@3];
        printf("1 is %s\n", [[cache objectForKey:@1] UTF8String]); /* 1 is now the most recently used */
        printf("adding a fourth:\n");
        [cache setObject:@"four" forKey:@4];
        printf("2 is %s, 1 is %s\n", [[[cache objectForKey:@2] description] UTF8String],
               [[cache objectForKey:@1] UTF8String]);
        printf("replacing 3:\n");
        [cache setObject:@"THREE" forKey:@3];
        printf("lowering the limit to 1:\n");
        [cache setCountLimit:1];
        printf("removing 3:\n");
        [cache removeObjectForKey:@3];
        printf("left: %s\n", [[[cache objectForKey:@3] description] UTF8String]);

        [cache setCountLimit:0];
        [cache setTotalCostLimit:10];
        [cache setObject:@"big" forKey:@"big" cost:6];
        [cache setObject:@"small" forKey:@"small" cost:3];
        printf("cost 6 + 3, then 4 more:\n");
        [cache setObject:@"medium" forKey:@"medium" cost:4];
        printf("removing all:\n");
        [cache removeAllObjects];

        Plain *k = [[[Plain alloc] init] autorelease];
        k.n = 9;
        [cache setObject:@"plain" forKey:k];
        Plain *same = [[[Plain alloc] init] autorelease];
        same.n = 9;
        printf("an uncopyable key: %s\n", [[cache objectForKey:same] UTF8String]);
        Discardable *dc = [[[Discardable alloc] init] autorelease];
        [cache setObject:dc forKey:@"d"];
        [dc discardContentIfPossible];
        printf("discarded content:\n");
        printf("  gives %s\n", [[[cache objectForKey:@"d"] description] UTF8String]);
        [cache setDelegate:nil];

        /* NSProgress */
        Watcher *w = [[[Watcher alloc] init] autorelease];
        NSProgress *top = [NSProgress progressWithTotalUnitCount:10];
        printf("progress: %lld of %lld, fraction %g, indeterminate %d, finished %d, cancellable %d, pausable %d, "
               "\"%s\" \"%s\"\n",
               [top completedUnitCount], [top totalUnitCount], [top fractionCompleted], [top isIndeterminate],
               [top isFinished], [top isCancellable], [top isPausable], [[top localizedDescription] UTF8String],
               [[top localizedAdditionalDescription] UTF8String]);
        [top addObserver:w forKeyPath:@"fractionCompleted" options:0 context:"top"];
        [top setCompletedUnitCount:2];
        printf("after 2: \"%s\" \"%s\"\n", [[top localizedDescription] UTF8String],
               [[top localizedAdditionalDescription] UTF8String]);

        [top becomeCurrentWithPendingUnitCount:4];
        printf("current is top: %d\n", [NSProgress currentProgress] == top);
        NSProgress *child = [NSProgress progressWithTotalUnitCount:2];
        NSProgress *second = [NSProgress progressWithTotalUnitCount:2]; /* only the first becomes a child */
        [top resignCurrent];
        printf("current after resigning: %s\n", [NSProgress currentProgress] ? "set" : "none");
        [child addObserver:w forKeyPath:@"completedUnitCount" options:0 context:"child"];
        [child setCompletedUnitCount:1];
        printf("child half done: top %g\n", [top fractionCompleted]);
        [second setCompletedUnitCount:2];
        printf("the second (no parent) done: top %g\n", [top fractionCompleted]);
        [child setCompletedUnitCount:2];
        printf("child done: top %lld of %lld, %g\n", [top completedUnitCount], [top totalUnitCount],
               [top fractionCompleted]);
        [child removeObserver:w forKeyPath:@"completedUnitCount"];

        [top becomeCurrentWithPendingUnitCount:1];
        [top resignCurrent];
        printf("current with no child: top %lld\n", [top completedUnitCount]);

        NSProgress *explicit = [NSProgress progressWithTotalUnitCount:4 parent:top pendingUnitCount:3];
        __block int cancels = 0;
        [explicit setCancellationHandler:^{ cancels++; }];
        [explicit setPausable:YES];
        [explicit setPausingHandler:^{ printf("  explicit paused\n"); }];
        [explicit setResumingHandler:^{ printf("  explicit resumed\n"); }];
        [explicit setCompletedUnitCount:1];
        printf("explicit quarter: top %g\n", [top fractionCompleted]);
        [top pause];
        printf("paused: %d %d\n", [top isPaused], [explicit isPaused]);
        [top resume];
        [top cancel];
        printf("cancelled: %d %d, handler ran %d\n", [top isCancelled], [explicit isCancelled], cancels);
        [top removeObserver:w forKeyPath:@"fractionCompleted"];

        NSProgress *ind = [NSProgress discreteProgressWithTotalUnitCount:-1];
        printf("indeterminate: %d, fraction %g, current none %d\n", [ind isIndeterminate], [ind fractionCompleted],
               [NSProgress currentProgress] == nil);
        [ind setTotalUnitCount:3];
        [ind setCompletedUnitCount:3];
        printf("finished: %d, fraction %g, \"%s\"\n", [ind isFinished], [ind fractionCompleted],
               [[ind localizedDescription] UTF8String]);
        [ind setKind:NSProgressKindFile];
        [ind setFileTotalCount:@5];
        [ind setUserInfoObject:@"x" forKey:@"mine"];
        printf("user info: %lu keys, file total %s\n", (unsigned long)[[ind userInfo] count],
               [[[ind fileTotalCount] description] UTF8String]);

        NSProgress *p = [NSProgress progressWithTotalUnitCount:1];
        [p performAsCurrentWithPendingUnitCount:1
                                     usingBlock:^{
                                         NSProgress *inner = [NSProgress progressWithTotalUnitCount:5];
                                         [inner setCompletedUnitCount:5];
                                     }];
        printf("performAsCurrent: %lld of %lld\n", [p completedUnitCount], [p totalUnitCount]);
    }
    return 0;
}
