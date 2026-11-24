/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: the animation clock. Animations added to layers,
 * and properties AppKit's animator proxies drive, are stepped by a timer
 * on the main run loop, sixty times a second while any is running, on the
 * program's one thread. Each step tells delegates when an animation starts
 * and stops, removes finished animations (unless removedOnCompletion is
 * NO), settles the transactions they were counted against, and asks the
 * layers' hosts to draw again. A layer's animations are applied when it is
 * drawn or its presentation layer is asked for, not here. With the test
 * hook's manual clock there is no timer: each FerryCAAdvanceTime steps. */
#import "QInternal.h"

@interface CAPropertyAnimation (FerryKinds)
- (id)_ferryValueAt:(double)p time:(double)t beneath:(id)beneath model:(id)model;
@end

@implementation QRunning
- (void)dealloc
{
    [animation release];
    [key release];
    [target release];
    [targetKey release];
    [targetFrom release];
    [targetTo release];
    [transactions release];
    [super dealloc];
}
@end

static NSMutableArray *running;   /* QRunning not yet stopped, in the order added */
static NSTimer *timer;

static void schedule(void)
{
    if (timer || QClockIsManual() || ![running count])
        return;
    timer = [[NSTimer scheduledTimerWithTimeInterval:1.0 / 60
                                             repeats:YES
                                               block:^(NSTimer *t) {
                                                 QAnimatorTick();
                                               }] retain];
}

static void unschedule(void)
{
    if (timer && ![running count]) {
        [timer invalidate];
        [timer release];
        timer = nil;
    }
}

void QAnimatorAdd(QRunning *r)
{
    if (!running)
        running = [[NSMutableArray alloc] init];
    [running addObject:r];
    schedule();
}

/* Tells the delegate it stopped and settles its transactions, once. */
static void stop(QRunning *r, BOOL finished)
{
    if (r->stopped)
        return;
    r->stopped = YES;
    id d = [r->animation delegate];
    /* one that ran its whole time between two steps still started */
    if (!r->started && finished && [d respondsToSelector:@selector(animationDidStart:)])
        [d animationDidStart:r->animation];
    r->started = YES;
    if ([d respondsToSelector:@selector(animationDidStop:finished:)])
        [d animationDidStop:r->animation finished:finished];
    QTransactionRelease(r->transactions);
}

void QAnimatorRemove(QRunning *r, BOOL finished)
{
    [r retain];
    stop(r, finished);
    [running removeObjectIdenticalTo:r];
    [r release];
    unschedule();
}

static double time_for(QRunning *r, double now)
{
    return r->layer ? [r->layer convertTime:now fromLayer:nil] : now;
}

/* a driven property's value now */
static id driven_value(QRunning *r, struct qtime *q)
{
    CAAnimation *a = r->animation;
    double dur = [a duration] > 0 ? [a duration] : [a _ferryDefaultDuration];
    double p = QTimingSolve([a timingFunction], q->progress);
    if ([a isKindOfClass:[CAPropertyAnimation class]]) {
        id v = [(CAPropertyAnimation *)a _ferryValueAt:p time:q->progress * dur beneath:r->targetFrom model:r->targetTo];
        if (v)
            return v;
    }
    return QBlend(r->targetFrom, r->targetTo, p);
}

void QAnimatorTick(void)
{
    double now = QNow();
    NSArray *all = [[running copy] autorelease];
    NSMutableSet *changed = [NSMutableSet set];
    for (QRunning *r in all) {
        if (r->stopped || ![running containsObject:r])
            continue;
        [[r retain] autorelease];
        CAAnimation *a = r->animation;
        struct qtime q;
        QTimingEvaluate(a, time_for(r, now), [a _ferryDefaultDuration], &q);
        if (!r->started && q.phase != Q_BEFORE) {
            r->started = YES;
            id d = [a delegate];
            if ([d respondsToSelector:@selector(animationDidStart:)])
                [d animationDidStart:a];
        }
        if (r->target) {
            if (q.phase == Q_AFTER) {
                [r->target setValue:r->targetTo forKey:r->targetKey];
                QAnimatorRemove(r, YES);
            } else if (q.phase == Q_ACTIVE || q.applies) {
                [r->target setValue:driven_value(r, &q) forKey:r->targetKey];
            }
            continue;
        }
        if (r->layer)
            [changed addObject:[NSValue valueWithPointer:r->layer]];
        if (q.phase == Q_AFTER) {
            if ([a isRemovedOnCompletion] && r->layer)
                [r->layer _ferryAnimationEnded:r];
            QAnimatorRemove(r, YES);
        }
    }
    for (NSValue *v in changed)
        [(CALayer *)[v pointerValue] _ferryChanged];
    unschedule();
}

void FerryCADriveValue(id target, NSString *key, id from, id to, CAAnimation *animation)
{
    if (!target || !key)
        return;
    for (QRunning *old in [[running copy] autorelease])
        if (old->target == target && [old->targetKey isEqualToString:key])
            QAnimatorRemove(old, NO);
    QRunning *r = [[QRunning alloc] init];
    r->animation = animation ? [animation copy] : [[CABasicAnimation alloc] init];
    if ([r->animation beginTime] == 0)
        [r->animation setBeginTime:QNow()];
    r->target = [target retain];
    r->targetKey = [key copy];
    r->targetFrom = [from retain];
    r->targetTo = [to retain];
    NSArray *open = QOpenTransactions();
    for (QTransaction *t in open)
        t->pending++;
    r->transactions = [open copy];
    QAnimatorAdd(r);
    [r release];
}
