/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSAnimationContext and the animator proxies. A grouping
 * is a Core Animation transaction: beginGrouping begins one and pushes a
 * context, endGrouping pops it and commits, and what is set on a grouped
 * context (duration, timing function, completion handler) is set on its
 * transaction too, so layer animations made in the group follow it and
 * the completion handler runs once every animation in the group is done.
 * Outside any group the current context is a standing one, with the
 * default quarter-second duration.
 *
 * [object animator] is a proxy. A setter sent to it (setFoo:, or
 * setValue:forKey:) whose key the object has an animation for (see
 * -animationForKey:) and whose value is a number, point, size or rect is
 * animated: the object's own setter is then called on every step of Core
 * Animation's clock with the value in between, over the current context's
 * duration, and with the final value at the end. Any other message goes
 * straight to the object. */
#import "AInternal.h"

@implementation NSAnimationContext {
    NSTimeInterval _duration;
    CAMediaTimingFunction *_timing;
    void (^_completion)(void);
    BOOL _implicit, _grouped;
}

static NSMutableArray *contexts;   /* the open groupings, innermost last */
static NSAnimationContext *standing;

- (instancetype)init
{
    if ((self = [super init]))
        _duration = 0.25;
    return self;
}

- (void)dealloc
{
    [_timing release];
    [_completion release];
    [super dealloc];
}

+ (NSAnimationContext *)currentContext
{
    NSAnimationContext *c = [contexts lastObject];
    if (c)
        return c;
    if (!standing)
        standing = [[NSAnimationContext alloc] init];
    return standing;
}

+ (void)beginGrouping
{
    if (!contexts)
        contexts = [[NSMutableArray alloc] init];
    [CATransaction begin];
    NSAnimationContext *c = [[NSAnimationContext alloc] init];
    c->_grouped = YES;
    [CATransaction setAnimationDuration:c->_duration];
    [contexts addObject:c];
    [c release];
}

+ (void)endGrouping
{
    if (![contexts count]) {
        NSLog(@"+[NSAnimationContext endGrouping] without a matching beginGrouping");
        return;
    }
    [contexts removeLastObject];
    [CATransaction commit];
}

+ (void)runAnimationGroup:(void (^)(NSAnimationContext *context))changes
        completionHandler:(void (^)(void))completionHandler
{
    [self beginGrouping];
    NSAnimationContext *c = [self currentContext];
    if (completionHandler)
        [c setCompletionHandler:completionHandler];
    if (changes)
        changes(c);
    [self endGrouping];
}

+ (void)runAnimationGroup:(void (^)(NSAnimationContext *context))changes
{
    [self runAnimationGroup:changes completionHandler:nil];
}

- (NSTimeInterval)duration { return _duration; }
- (void)setDuration:(NSTimeInterval)duration
{
    _duration = duration;
    if (_grouped)
        [CATransaction setAnimationDuration:duration];
}
- (CAMediaTimingFunction *)timingFunction { return _timing; }
- (void)setTimingFunction:(CAMediaTimingFunction *)function
{
    id wasTiming = _timing;
    _timing = [function retain];
    [wasTiming release];
    if (_grouped)
        [CATransaction setAnimationTimingFunction:function];
}
- (void (^)(void))completionHandler { return _completion; }
- (void)setCompletionHandler:(void (^)(void))handler
{
    id wasCompletion = _completion;
    _completion = [handler copy];
    [wasCompletion release];
    if (_grouped)
        [CATransaction setCompletionBlock:handler];
}
- (BOOL)allowsImplicitAnimation { return _implicit; }
- (void)setAllowsImplicitAnimation:(BOOL)flag { _implicit = flag; }
@end

/* ---- the animator proxy ---- */

@interface AAnimator : NSProxy {
@public
    id _target;
}
@end

static BOOL type_is(const char *t, const char *a, const char *b, const char *c)
{
    return !strncmp(t, a, strlen(a)) || !strncmp(t, b, strlen(b)) || !strncmp(t, c, strlen(c));
}

/* The setter's one argument as an object, or nil if it isn't one the clock
 * can step through. */
static id boxed_argument(NSInvocation *inv, NSUInteger i)
{
    const char *t = [[inv methodSignature] getArgumentTypeAtIndex:i];
    while (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'V')
        t++;
    switch (*t) {
    case 'd': { double v; [inv getArgument:&v atIndex:i]; return @(v); }
    case 'f': { float v; [inv getArgument:&v atIndex:i]; return @(v); }
    case 'i': { int v; [inv getArgument:&v atIndex:i]; return @(v); }
    case 'I': { unsigned v; [inv getArgument:&v atIndex:i]; return @(v); }
    case 'l':
    case 'q': { long long v; [inv getArgument:&v atIndex:i]; return @(v); }
    case 'L':
    case 'Q': { unsigned long long v; [inv getArgument:&v atIndex:i]; return @(v); }
    case '{':
        if (type_is(t, "{CGRect=", "{_NSRect=", "{NSRect=")) {
            NSRect r;
            [inv getArgument:&r atIndex:i];
            return [NSValue valueWithRect:r];
        }
        if (type_is(t, "{CGPoint=", "{_NSPoint=", "{NSPoint=")) {
            NSPoint p;
            [inv getArgument:&p atIndex:i];
            return [NSValue valueWithPoint:p];
        }
        if (type_is(t, "{CGSize=", "{_NSSize=", "{NSSize=")) {
            NSSize s;
            [inv getArgument:&s atIndex:i];
            return [NSValue valueWithSize:s];
        }
        return nil;
    }
    return nil;
}

@implementation AAnimator
- (void)dealloc
{
    [_target release];
    [super dealloc];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel { return [_target methodSignatureForSelector:sel]; }
- (BOOL)respondsToSelector:(SEL)sel { return [_target respondsToSelector:sel]; }
- (BOOL)isKindOfClass:(Class)cls { return [_target isKindOfClass:cls]; }
- (NSString *)description { return [NSString stringWithFormat:@"<animator for %@>", _target]; }

- (void)forwardInvocation:(NSInvocation *)inv
{
    SEL sel = [inv selector];
    NSString *name = NSStringFromSelector(sel);
    NSString *key = nil;
    id to = nil;
    if (sel == @selector(setValue:forKey:)) {
        id v, k;
        [inv getArgument:&v atIndex:2];
        [inv getArgument:&k atIndex:3];
        key = k;
        to = [v isKindOfClass:[NSNumber class]] || [v isKindOfClass:[NSValue class]] ? v : nil;
    } else if ([[inv methodSignature] numberOfArguments] == 3 && [name length] > 4 && [name hasPrefix:@"set"] &&
               [name rangeOfString:@":"].location == [name length] - 1) {
        NSString *rest = [name substringWithRange:NSMakeRange(3, [name length] - 4)];
        key = [[[rest substringToIndex:1] lowercaseString] stringByAppendingString:[rest substringFromIndex:1]];
        to = boxed_argument(inv, 2);
    }
    NSAnimationContext *context = [NSAnimationContext currentContext];
    CAAnimation *animation = key && to && [_target respondsToSelector:@selector(animationForKey:)]
                                 ? [_target animationForKey:key]
                                 : nil;
    if (![animation isKindOfClass:[CAAnimation class]] || [context duration] <= 0) {
        [inv invokeWithTarget:_target];
        return;
    }
    id from = nil;
    @try {
        from = [_target valueForKey:key];
    } @catch (NSException *e) {
        from = nil;
    }
    if (!from) {
        [inv invokeWithTarget:_target];
        return;
    }
    animation = [[animation copy] autorelease];
    if ([animation duration] <= 0)
        [animation setDuration:[context duration]];
    if (![animation timingFunction])
        [animation setTimingFunction:[context timingFunction]
                                         ?: [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
    FerryCADriveValue(_target, key, from, to, animation);
}
@end

id AAnimatorFor(id target)
{
    AAnimator *a = [AAnimator alloc];
    a->_target = [target retain];
    return [a autorelease];
}
