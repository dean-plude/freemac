/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: CATransaction. Transactions nest; each keeps its
 * own values (duration, timing function, whether actions are off, the
 * completion block), and a value not set in one is looked up in the ones
 * around it. A change made with no transaction open opens an implicit one,
 * committed at the end of the run loop's pass. A completion block runs
 * once its transaction is committed and every animation added while it was
 * open has finished or been removed, at once if there were none. */
#import "QInternal.h"

NSString *const kCATransactionAnimationDuration = @"animationDuration";
NSString *const kCATransactionDisableActions = @"disableActions";
NSString *const kCATransactionAnimationTimingFunction = @"animationTimingFunction";
NSString *const kCATransactionCompletionBlock = @"completionBlock";

@implementation QTransaction
- (instancetype)init
{
    static NSUInteger next_serial;
    if ((self = [super init])) {
        values = [[NSMutableDictionary alloc] init];
        serial = ++next_serial;
    }
    return self;
}
- (void)dealloc
{
    [values release];
    [super dealloc];
}
@end

static NSMutableArray *stack;   /* of QTransaction, outermost first */
static BOOL implicit_scheduled;

static void finish(QTransaction *t)
{
    if (t->done || !t->committed || t->pending > 0)
        return;
    t->done = YES;
    void (^block)(void) = t->values[kCATransactionCompletionBlock];
    if (block) {
        [block retain];
        block();
        [block release];
    }
}

static void commit_top(void)
{
    QTransaction *t = [[stack lastObject] retain];
    [stack removeLastObject];
    t->committed = YES;
    finish(t);
    [t release];
}

void QCommitImplicitTransaction(void)
{
    implicit_scheduled = NO;
    if ([stack count] == 1 && ((QTransaction *)stack[0])->implicit)
        commit_top();
}

NSArray *QOpenTransactions(void)
{
    if (!stack)
        stack = [[NSMutableArray alloc] init];
    if (![stack count]) {
        QTransaction *t = [[QTransaction alloc] init];
        t->implicit = YES;
        [stack addObject:t];
        [t release];
        if (!implicit_scheduled) {
            implicit_scheduled = YES;
            [[NSRunLoop mainRunLoop] performBlock:^{
              QCommitImplicitTransaction();
            }];
        }
    }
    return stack;
}

void QTransactionRelease(NSArray *transactions)
{
    for (QTransaction *t in transactions) {
        t->pending--;
        finish(t);
    }
}

NSUInteger QCurrentTransactionSerial(void) { return ((QTransaction *)[QOpenTransactions() lastObject])->serial; }

BOOL QTransactionIsOpen(NSUInteger serial)
{
    for (QTransaction *t in stack)
        if (t->serial == serial)
            return YES;
    return NO;
}

static id lookup(NSString *key)
{
    for (QTransaction *t in [QOpenTransactions() reverseObjectEnumerator]) {
        id v = t->values[key];
        if (v)
            return v;
    }
    return nil;
}

static void store(NSString *key, id value)
{
    QTransaction *t = [QOpenTransactions() lastObject];
    if (value)
        t->values[key] = value;
    else
        [t->values removeObjectForKey:key];
}

@implementation CATransaction

+ (void)begin
{
    if (!stack)
        stack = [[NSMutableArray alloc] init];
    QTransaction *t = [[QTransaction alloc] init];
    [stack addObject:t];
    [t release];
}

+ (void)commit
{
    if (![stack count])
        return;
    if (((QTransaction *)[stack lastObject])->implicit) {
        /* nothing begun is left to commit; the implicit one ends at the end of the pass */
        return;
    }
    commit_top();
}

+ (void)flush { QCommitImplicitTransaction(); }
+ (void)lock {}
+ (void)unlock {}

+ (CFTimeInterval)animationDuration
{
    id v = lookup(kCATransactionAnimationDuration);
    return v ? [v doubleValue] : 0.25;
}
+ (void)setAnimationDuration:(CFTimeInterval)duration { store(kCATransactionAnimationDuration, @(duration)); }
+ (CAMediaTimingFunction *)animationTimingFunction { return lookup(kCATransactionAnimationTimingFunction); }
+ (void)setAnimationTimingFunction:(CAMediaTimingFunction *)function
{
    store(kCATransactionAnimationTimingFunction, function);
}
+ (BOOL)disableActions { return [lookup(kCATransactionDisableActions) boolValue]; }
+ (void)setDisableActions:(BOOL)flag { store(kCATransactionDisableActions, @(flag)); }
+ (void (^)(void))completionBlock
{
    return ((QTransaction *)[QOpenTransactions() lastObject])->values[kCATransactionCompletionBlock];
}
+ (void)setCompletionBlock:(void (^)(void))block
{
    id copy = [block copy];
    store(kCATransactionCompletionBlock, copy);
    [copy release];
}
+ (id)valueForKey:(NSString *)key
{
    if ([key isEqualToString:kCATransactionAnimationDuration])
        return @([self animationDuration]);
    if ([key isEqualToString:kCATransactionDisableActions])
        return @([self disableActions]);
    return lookup(key);
}
+ (void)setValue:(id)value forKey:(NSString *)key
{
    if ([key isEqualToString:kCATransactionCompletionBlock])
        [self setCompletionBlock:value];
    else
        store(key, value);
}
@end
