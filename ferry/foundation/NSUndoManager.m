/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSUndoManager, written from Apple's public
 * documentation; no Apple code was used. Undo actions are kept in groups
 * on an undo stack; undoing a group runs its actions last first, and the
 * actions they register while undoing make the group that redo runs. A
 * new action registered outside undo and redo empties the redo stack. With
 * groupsByEvent (the default), the first action registered outside any
 * group opens one, and it closes the next time the run loop turns, as a
 * Mac's closes at the end of the event. Actions are kept as a selector
 * with one object, or a block; prepareWithInvocationTarget: needs
 * NSInvocation (message forwarding with its arguments), which Ferry doesn't
 * have yet, so it answers nil: the messages sent to it do nothing, and the
 * first time Ferry says so. Targets aren't retained, as on a Mac. Built
 * without ARC. */
#import "FInternal.h"

NSNotificationName const NSUndoManagerCheckpointNotification = @"NSUndoManagerCheckpointNotification";
NSNotificationName const NSUndoManagerWillUndoChangeNotification = @"NSUndoManagerWillUndoChangeNotification";
NSNotificationName const NSUndoManagerWillRedoChangeNotification = @"NSUndoManagerWillRedoChangeNotification";
NSNotificationName const NSUndoManagerDidUndoChangeNotification = @"NSUndoManagerDidUndoChangeNotification";
NSNotificationName const NSUndoManagerDidRedoChangeNotification = @"NSUndoManagerDidRedoChangeNotification";
NSNotificationName const NSUndoManagerDidOpenUndoGroupNotification = @"NSUndoManagerDidOpenUndoGroupNotification";
NSNotificationName const NSUndoManagerWillCloseUndoGroupNotification = @"NSUndoManagerWillCloseUndoGroupNotification";
NSNotificationName const NSUndoManagerDidCloseUndoGroupNotification = @"NSUndoManagerDidCloseUndoGroupNotification";
NSString *const NSUndoManagerGroupIsDiscardableKey = @"NSUndoManagerGroupIsDiscardableKey";

/* One action, or a group of them (a nested group is an action of its parent). */
@interface FUndoAction : NSObject {
@public
    id target;          /* not retained */
    SEL selector;
    id object;
    void (^handler)(id);
    NSMutableArray *actions;   /* a group's */
    NSString *name;
    BOOL discardable;
}
@end
@implementation FUndoAction
- (void)dealloc
{
    [object release];
    [handler release];
    [actions release];
    [name release];
    [super dealloc];
}
- (void)run
{
    if (actions) {
        for (FUndoAction *a in [[[actions reverseObjectEnumerator] allObjects] copy])
            [a run];
        return;
    }
    if (handler)
        handler(target);
    else if (selector)
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, object);
}
/* Drops target's actions; YES if nothing is left. */
- (BOOL)dropTarget:(id)t
{
    if (!actions)
        return target == t;
    for (FUndoAction *a in [[actions copy] autorelease])
        if ([a dropTarget:t])
            [actions removeObjectIdenticalTo:a];
    return [actions count] == 0;
}
@end

static FUndoAction *new_group(void)
{
    FUndoAction *g = [[FUndoAction alloc] init];
    g->actions = [[NSMutableArray alloc] init];
    return g;
}

@implementation NSUndoManager {
    NSMutableArray *_undo, *_redo;     /* closed groups, newest last */
    NSMutableArray *_open;             /* the groups open now, innermost last */
    NSInteger _disabled;
    NSUInteger _levels;
    BOOL _byEvent, _autoOpened, _undoing, _redoing;
    NSArray *_modes;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _undo = [[NSMutableArray alloc] init];
        _redo = [[NSMutableArray alloc] init];
        _open = [[NSMutableArray alloc] init];
        _byEvent = YES;
        _modes = [[NSArray alloc] initWithObjects:NSDefaultRunLoopMode, nil];
    }
    return self;
}
- (void)dealloc
{
    [_undo release];
    [_redo release];
    [_open release];
    [_modes release];
    [super dealloc];
}

- (void)_post:(NSNotificationName)name
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self];
}

/* ---- groups ---- */

- (NSInteger)groupingLevel { return (NSInteger)[_open count]; }
- (BOOL)groupsByEvent { return _byEvent; }
- (void)setGroupsByEvent:(BOOL)f { _byEvent = f; }
- (NSUInteger)levelsOfUndo { return _levels; }
- (void)setLevelsOfUndo:(NSUInteger)n
{
    _levels = n;
    [self _trim];
}
- (NSArray *)runLoopModes { return _modes; }
- (void)setRunLoopModes:(NSArray *)modes
{
    [_modes release];
    _modes = [modes copy];
}

- (void)_trim
{
    if (_levels)
        while ([_undo count] > _levels)
            [_undo removeObjectAtIndex:0];
}

- (void)beginUndoGrouping
{
    if (![_open count])
        [self _post:NSUndoManagerCheckpointNotification];
    FUndoAction *g = new_group();
    [_open addObject:g];
    [g release];
    [self _post:NSUndoManagerDidOpenUndoGroupNotification];
}

- (void)endUndoGrouping
{
    if (![_open count])
        FRaise(NSInternalInconsistencyException, @"-[NSUndoManager endUndoGrouping] called with no open group");
    [self _post:NSUndoManagerCheckpointNotification];
    FUndoAction *g = [[[_open lastObject] retain] autorelease];
    BOOL top = [_open count] == 1;
    NSDictionary *info = g->discardable ? @{NSUndoManagerGroupIsDiscardableKey : @YES} : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUndoManagerWillCloseUndoGroupNotification
                                                        object:self userInfo:info];
    [_open removeLastObject];
    if (top)
        _autoOpened = NO;
    if ([g->actions count]) {
        if (!top)
            [((FUndoAction *)[_open lastObject])->actions addObject:g];
        else if (_undoing)
            [_redo addObject:g];
        else {
            [_undo addObject:g];
            [self _trim];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUndoManagerDidCloseUndoGroupNotification
                                                        object:self userInfo:info];
}

/* The group opened for an event closes the next time the run loop turns. */
- (void)_endEventGroup
{
    if (_autoOpened && [_open count] == 1)
        [self endUndoGrouping];
    _autoOpened = NO;
}

- (void)disableUndoRegistration { _disabled++; }
- (void)enableUndoRegistration
{
    if (_disabled > 0)
        _disabled--;
}
- (BOOL)isUndoRegistrationEnabled { return _disabled == 0; }

/* ---- registering ---- */

- (FUndoAction *)_groupForNewAction
{
    if (![_open count]) {
        if (!_byEvent)
            FRaise(NSInternalInconsistencyException, @"-[NSUndoManager registerUndoWithTarget:...] called with no "
                                                     @"open group and groupsByEvent off");
        [self beginUndoGrouping];
        _autoOpened = YES;
        [self performSelector:@selector(_endEventGroup) withObject:nil afterDelay:0 inModes:_modes];
    }
    if (!_undoing && !_redoing)
        [_redo removeAllObjects];
    return [_open lastObject];
}

- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)object
{
    if (_disabled)
        return;
    FUndoAction *a = [[FUndoAction alloc] init];
    a->target = target;
    a->selector = selector;
    a->object = [object retain];
    [[self _groupForNewAction]->actions addObject:a];
    [a release];
}

- (void)registerUndoWithTarget:(id)target handler:(void (^)(id))handler
{
    if (_disabled || !handler)
        return;
    FUndoAction *a = [[FUndoAction alloc] init];
    a->target = target;
    a->handler = [handler copy];
    [[self _groupForNewAction]->actions addObject:a];
    [a release];
}

- (id)prepareWithInvocationTarget:(id)target
{
    static BOOL warned;
    if (!warned) {
        warned = YES;
        fflush(stdout);
        fprintf(stderr, "ferry: -[NSUndoManager prepareWithInvocationTarget:] needs NSInvocation, which Ferry "
                        "doesn't have yet; those undo actions aren't kept\n");
    }
    return nil;
}

- (void)setActionIsDiscardable:(BOOL)discardable
{
    FUndoAction *g = [_open firstObject] ?: [_undo lastObject];
    if (g)
        g->discardable = discardable;
}
- (BOOL)undoActionIsDiscardable { return ((FUndoAction *)[_undo lastObject])->discardable; }
- (BOOL)redoActionIsDiscardable { return ((FUndoAction *)[_redo lastObject])->discardable; }

/* ---- undo and redo ---- */

- (BOOL)canUndo
{
    if ([_undo count])
        return YES;
    FUndoAction *g = [_open firstObject];
    return g && [g->actions count];
}
- (BOOL)canRedo
{
    [self _post:NSUndoManagerCheckpointNotification];
    return [_redo count] > 0;
}
- (BOOL)isUndoing { return _undoing; }
- (BOOL)isRedoing { return _redoing; }

- (void)undo
{
    if ([_open count] == 1)
        [self endUndoGrouping];
    if ([_open count])
        FRaise(NSInternalInconsistencyException, @"-[NSUndoManager undo] called with a nested group open");
    [self undoNestedGroup];
}

- (void)undoNestedGroup
{
    FUndoAction *g = [[[_undo lastObject] retain] autorelease];
    if (!g)
        return;
    [self _post:NSUndoManagerCheckpointNotification];
    [self _post:NSUndoManagerWillUndoChangeNotification];
    [_undo removeLastObject];
    _undoing = YES;
    [self beginUndoGrouping];
    [g run];
    [self setActionName:g->name];
    [self endUndoGrouping];
    _undoing = NO;
    [self _post:NSUndoManagerDidUndoChangeNotification];
}

- (void)redo
{
    if ([_open count])
        FRaise(NSInternalInconsistencyException, @"-[NSUndoManager redo] called with a group open");
    FUndoAction *g = [[[_redo lastObject] retain] autorelease];
    if (!g)
        return;
    [self _post:NSUndoManagerCheckpointNotification];
    [self _post:NSUndoManagerWillRedoChangeNotification];
    [_redo removeLastObject];
    _redoing = YES;
    [self beginUndoGrouping];
    [g run];
    [self setActionName:g->name];
    [self endUndoGrouping];
    _redoing = NO;
    [self _post:NSUndoManagerDidRedoChangeNotification];
}

- (void)removeAllActions
{
    [_undo removeAllObjects];
    [_redo removeAllObjects];
    [_open removeAllObjects];
    _autoOpened = NO;
    _disabled = 0;
}

- (void)removeAllActionsWithTarget:(id)target
{
    for (NSMutableArray *stack in @[ _undo, _redo, _open ])
        for (FUndoAction *g in [[stack copy] autorelease])
            if ([g dropTarget:target] && stack != _open)
                [stack removeObjectIdenticalTo:g];
}

/* ---- names ---- */

- (void)setActionName:(NSString *)name
{
    FUndoAction *g = [_open firstObject];
    if (!g)
        g = _undoing ? [_redo lastObject] : [_undo lastObject];
    if (!g)
        return;
    [g->name release];
    g->name = [name copy];
}
- (NSString *)undoActionName
{
    FUndoAction *g = [_open firstObject] && !_undoing && !_redoing ? [_open firstObject] : [_undo lastObject];
    return g && g->name ? g->name : @"";
}
- (NSString *)redoActionName
{
    FUndoAction *g = [_redo lastObject];
    return g && g->name ? g->name : @"";
}
- (NSString *)undoMenuTitleForUndoActionName:(NSString *)name
{
    return [name length] ? [NSString stringWithFormat:@"Undo %@", name] : @"Undo";
}
- (NSString *)redoMenuTitleForUndoActionName:(NSString *)name
{
    return [name length] ? [NSString stringWithFormat:@"Redo %@", name] : @"Redo";
}
- (NSString *)undoMenuItemTitle { return [self undoMenuTitleForUndoActionName:[self undoActionName]]; }
- (NSString *)redoMenuItemTitle { return [self redoMenuTitleForUndoActionName:[self redoActionName]]; }
@end
