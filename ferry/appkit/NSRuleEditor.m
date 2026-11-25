/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSRuleEditor (freemac 1.222, Ferry 0.46.0), written
 * from Apple's public NSRuleEditor documentation and from how the control
 * behaves on a Mac; no Apple code, artwork or headers were used.
 *
 * The rows are a tree of rowClass objects (dictionaries unless told
 * otherwise), each holding its type, its criteria, their display values
 * and its subrows under the four key paths; with the "rows" binding the
 * top of the tree is the model's own array, changed through
 * mutableArrayValueForKeyPath: so the model hears of each change. Rows are
 * numbered in the order they're shown: a row, then its subrows.
 *
 * A new row's criteria are the delegate's first child at each step, from
 * no criterion, until a criterion has no children. Each criterion's
 * display value is shown as it is: a string as a pop-up menu of it and its
 * siblings' strings when it has siblings, a label otherwise; a view as
 * itself; a menu item as a pop-up of it and its siblings. Choosing another
 * entry in a pop-up makes that sibling the row's criterion there, with
 * first children after it. Each row ends with a button that removes it and
 * one that adds a row after it (a compound row's adds a subrow). The
 * predicate is made from the delegate's predicate parts for each row's
 * criteria. Built without ARC. */
#import "AInternal.h"

NSRuleEditorPredicatePartKey const NSRuleEditorPredicateLeftExpression = @"NSRuleEditorPredicateLeftExpression";
NSRuleEditorPredicatePartKey const NSRuleEditorPredicateRightExpression = @"NSRuleEditorPredicateRightExpression";
NSRuleEditorPredicatePartKey const NSRuleEditorPredicateComparisonModifier = @"NSRuleEditorPredicateComparisonModifier";
NSRuleEditorPredicatePartKey const NSRuleEditorPredicateOptions = @"NSRuleEditorPredicateOptions";
NSRuleEditorPredicatePartKey const NSRuleEditorPredicateOperatorType = @"NSRuleEditorPredicateOperatorType";
NSRuleEditorPredicatePartKey const NSRuleEditorPredicateCustomSelector = @"NSRuleEditorPredicateCustomSelector";
NSRuleEditorPredicatePartKey const NSRuleEditorPredicateCompoundType = @"NSRuleEditorPredicateCompoundType";
NSNotificationName const NSRuleEditorRowsDidChangeNotification = @"NSRuleEditorRowsDidChangeNotification";

static char rows_context;
static const CGFloat kIndent = 16, kButton = 22, kGap = 4;

/* a pop-up of one criterion's siblings, which knows its place */
@interface ARuleEditorPopUp : NSPopUpButton {
@public
    NSInteger row, level;
    NSArray *choices; /* the siblings, in the menu's order */
}
@end
@implementation ARuleEditorPopUp
- (void)dealloc
{
    [choices release];
    [super dealloc];
}
@end

@interface ARuleEditorButton : NSButton {
@public
    NSInteger row;
}
@end
@implementation ARuleEditorButton
@end

/* the rows, flattened */
@interface ARuleRow : NSObject {
@public
    id object;
    NSInteger parent, depth;
}
@end
@implementation ARuleRow
- (void)dealloc
{
    [object release];
    [super dealloc];
}
@end

@interface NSRuleEditor ()
- (void)_rebuild;
- (void)_changed;
@end

@implementation NSRuleEditor {
    id<NSRuleEditorDelegate> _delegate;
    NSString *_formattingFile;
    NSDictionary *_formatting;
    NSRuleEditorNestingMode _nesting;
    CGFloat _rowHeight;
    BOOL _editable, _canRemoveAll, _mutating;
    NSPredicate *_predicate;
    NSMutableArray *_ownRows;      /* the top rows, when not bound */
    id _boundObject;
    NSString *_boundKeyPath;
    NSDictionary *_boundInfo;
    NSMutableArray *_flat;         /* ARuleRow, in the order shown */
    NSMutableIndexSet *_selected;
    Class _rowClass;
    NSString *_typeKey, *_subrowsKey, *_criteriaKey, *_valuesKey;
}

- (void)_setUp
{
    _rowHeight = 25;
    _editable = YES;
    _nesting = NSRuleEditorNestingModeCompound;
    _ownRows = [[NSMutableArray alloc] init];
    _flat = [[NSMutableArray alloc] init];
    _selected = [[NSMutableIndexSet alloc] init];
    _rowClass = [NSMutableDictionary class];
    _typeKey = @"rowType";
    _subrowsKey = @"subrows";
    _criteriaKey = @"criteria";
    _valuesKey = @"displayValues";
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _setUp];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUp];
        if ([coder allowsKeyedCoding] && [coder containsValueForKey:@"NSRowHeight"])
            _rowHeight = [coder decodeDoubleForKey:@"NSRowHeight"];
        if ([coder allowsKeyedCoding] && [coder containsValueForKey:@"NSNestingMode"])
            _nesting = (NSRuleEditorNestingMode)[coder decodeIntegerForKey:@"NSNestingMode"];
        if ([coder allowsKeyedCoding] && [coder containsValueForKey:@"NSEditable"])
            _editable = [coder decodeBoolForKey:@"NSEditable"];
        if ([coder allowsKeyedCoding] && [coder containsValueForKey:@"NSCanRemoveAllRows"])
            _canRemoveAll = [coder decodeBoolForKey:@"NSCanRemoveAllRows"];
    }
    return self;
}
- (void)dealloc
{
    [self unbind:@"rows"];
    if (_delegate)
        [[NSNotificationCenter defaultCenter] removeObserver:_delegate name:NSRuleEditorRowsDidChangeNotification
                                                      object:self];
    [_formattingFile release];
    [_formatting release];
    [_predicate release];
    [_ownRows release];
    [_flat release];
    [_selected release];
    [_typeKey release];
    [_subrowsKey release];
    [_criteriaKey release];
    [_valuesKey release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }

/* ---- properties ---- */

- (id<NSRuleEditorDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSRuleEditorDelegate>)delegate
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_delegate)
        [nc removeObserver:_delegate name:NSRuleEditorRowsDidChangeNotification object:self];
    _delegate = delegate;
    if ([delegate respondsToSelector:@selector(ruleEditorRowsDidChange:)])
        [nc addObserver:delegate selector:@selector(ruleEditorRowsDidChange:)
                   name:NSRuleEditorRowsDidChangeNotification object:self];
}
- (NSString *)formattingStringsFilename { return _formattingFile; }
- (void)setFormattingStringsFilename:(NSString *)name
{
    [_formattingFile autorelease];
    _formattingFile = [name copy];
    NSString *path = name ? [[NSBundle mainBundle] pathForResource:[name stringByDeletingPathExtension]
                                                            ofType:@"strings"] : nil;
    [self setFormattingDictionary:path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil];
}
- (NSDictionary *)formattingDictionary { return _formatting; }
- (void)setFormattingDictionary:(NSDictionary *)d
{
    [_formatting autorelease];
    _formatting = [d copy];
    [self _rebuild];
}
- (NSRuleEditorNestingMode)nestingMode { return _nesting; }
- (void)setNestingMode:(NSRuleEditorNestingMode)mode { _nesting = mode; }
- (CGFloat)rowHeight { return _rowHeight; }
- (void)setRowHeight:(CGFloat)h
{
    _rowHeight = h > 0 ? h : 25;
    [self _rebuild];
}
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)flag
{
    _editable = flag;
    [self _rebuild];
}
- (BOOL)canRemoveAllRows { return _canRemoveAll; }
- (void)setCanRemoveAllRows:(BOOL)flag
{
    _canRemoveAll = flag;
    [self _rebuild];
}
- (Class)rowClass { return _rowClass; }
- (void)setRowClass:(Class)c { _rowClass = c ?: [NSMutableDictionary class]; }
#define KEY_PROPERTY(getter, setter, ivar)                                                                         \
    -(NSString *)getter { return ivar; }                                                                           \
    -(void)setter:(NSString *)key                                                                                  \
    {                                                                                                              \
        [ivar autorelease];                                                                                        \
        ivar = [key copy];                                                                                         \
    }
KEY_PROPERTY(rowTypeKeyPath, setRowTypeKeyPath, _typeKey)
KEY_PROPERTY(subrowsKeyPath, setSubrowsKeyPath, _subrowsKey)
KEY_PROPERTY(criteriaKeyPath, setCriteriaKeyPath, _criteriaKey)
KEY_PROPERTY(displayValuesKeyPath, setDisplayValuesKeyPath, _valuesKey)

- (void)setEnabled:(BOOL)flag
{
    [super setEnabled:flag];
    for (NSView *rowView in [self subviews])
        for (NSView *v in [rowView subviews])
            if ([v isKindOfClass:[NSControl class]])
                [(NSControl *)v setEnabled:flag];
}

/* ---- the "rows" binding ---- */

- (void)bind:(NSString *)binding toObject:(id)observable withKeyPath:(NSString *)keyPath
     options:(NSDictionary *)options
{
    if (![binding isEqualToString:@"rows"]) {
        [super bind:binding toObject:observable withKeyPath:keyPath options:options];
        return;
    }
    [self unbind:@"rows"];
    if (!observable || !keyPath)
        return;
    _boundObject = [observable retain];
    _boundKeyPath = [keyPath copy];
    _boundInfo = [@{
        NSObservedObjectKey : observable,
        NSObservedKeyPathKey : keyPath,
        NSOptionsKey : options ?: @{}
    } copy];
    [observable addObserver:self forKeyPath:keyPath options:0 context:&rows_context];
    [self _rebuild];
}
- (void)unbind:(NSString *)binding
{
    if (![binding isEqualToString:@"rows"]) {
        [super unbind:binding];
        return;
    }
    if (!_boundObject)
        return;
    [_boundObject removeObserver:self forKeyPath:_boundKeyPath context:&rows_context];
    [_boundObject release];
    _boundObject = nil;
    [_boundKeyPath release];
    _boundKeyPath = nil;
    [_boundInfo release];
    _boundInfo = nil;
    [self _rebuild];
}
- (NSDictionary *)infoForBinding:(NSString *)binding
{
    return [binding isEqualToString:@"rows"] ? _boundInfo : [super infoForBinding:binding];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (context != &rows_context) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (!_mutating)
        [self _rebuild];
}

/* ---- the tree ---- */

- (NSArray *)_topRows
{
    if (_boundObject) {
        id v = [_boundObject valueForKeyPath:_boundKeyPath];
        return [v isKindOfClass:[NSArray class]] ? v : @[];
    }
    return _ownRows;
}
- (NSMutableArray *)_mutableTopRows
{
    return _boundObject ? [_boundObject mutableArrayValueForKeyPath:_boundKeyPath] : _ownRows;
}
- (NSArray *)_subrowsOf:(id)row
{
    id v = [row valueForKeyPath:_subrowsKey];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}
/* a row's own subrows array, made mutable in place (a dictionary has no
 * mutable-array accessors to go through) */
- (NSMutableArray *)_mutableSubrowsOf:(id)row
{
    id v = [row valueForKeyPath:_subrowsKey];
    if ([v isKindOfClass:[NSMutableArray class]])
        return v;
    NSMutableArray *m = [NSMutableArray arrayWithArray:[v isKindOfClass:[NSArray class]] ? v : @[]];
    [row setValue:m forKeyPath:_subrowsKey];
    return m;
}
- (NSMutableArray *)_siblingsOfRow:(NSInteger)i
{
    NSInteger p = ((ARuleRow *)_flat[i])->parent;
    return p < 0 ? [self _mutableTopRows] : [self _mutableSubrowsOf:((ARuleRow *)_flat[p])->object];
}

static void flatten(NSRuleEditor *self, NSArray *rows, NSInteger parent, NSInteger depth, NSMutableArray *out)
{
    for (id row in rows) {
        ARuleRow *r = [[[ARuleRow alloc] init] autorelease];
        r->object = [row retain];
        r->parent = parent;
        r->depth = depth;
        NSInteger me = (NSInteger)[out count];
        [out addObject:r];
        flatten(self, [self _subrowsOf:row], me, depth + 1, out);
    }
}
- (void)_flatten
{
    [_flat removeAllObjects];
    flatten(self, [self _topRows], -1, 0, _flat);
}

- (id)_object:(NSInteger)row
{
    if (row < 0 || row >= (NSInteger)[_flat count])
        [NSException raise:NSRangeException format:@"-[NSRuleEditor] row %ld is beyond the %lu rows", (long)row,
                           (unsigned long)[_flat count]];
    return ((ARuleRow *)_flat[row])->object;
}

- (NSInteger)numberOfRows { return (NSInteger)[_flat count]; }
- (NSRuleEditorRowType)rowTypeForRow:(NSInteger)row
{
    return (NSRuleEditorRowType)[[[self _object:row] valueForKeyPath:_typeKey] unsignedIntegerValue];
}
- (NSInteger)parentRowForRow:(NSInteger)row
{
    [self _object:row];
    return ((ARuleRow *)_flat[row])->parent;
}
- (NSIndexSet *)subrowIndexesForRow:(NSInteger)row
{
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < [_flat count]; i++)
        if (((ARuleRow *)_flat[i])->parent == row)
            [set addIndex:i];
    return set;
}
- (NSArray *)criteriaForRow:(NSInteger)row
{
    id v = [[self _object:row] valueForKeyPath:_criteriaKey];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}
- (NSArray *)displayValuesForRow:(NSInteger)row
{
    id v = [[self _object:row] valueForKeyPath:_valuesKey];
    return [v isKindOfClass:[NSArray class]] ? v : @[];
}
- (NSInteger)rowForDisplayValue:(id)value
{
    for (NSUInteger i = 0; i < [_flat count]; i++)
        for (id v in [self displayValuesForRow:i])
            if (v == value)
                return (NSInteger)i;
    return NSNotFound;
}

/* ---- criteria ---- */

- (NSInteger)_childCount:(id)criterion type:(NSRuleEditorRowType)type
{
    return MAX([_delegate ruleEditor:self numberOfChildrenForCriterion:criterion withRowType:type], 0);
}
- (id)_child:(NSInteger)i of:(id)criterion type:(NSRuleEditorRowType)type
{
    return [_delegate ruleEditor:self child:i forCriterion:criterion withRowType:type];
}
/* the criteria kept up to level, then first children */
- (NSArray *)_criteriaFrom:(NSArray *)kept type:(NSRuleEditorRowType)type
{
    NSMutableArray *out = [NSMutableArray arrayWithArray:kept ?: @[]];
    id c = [out lastObject];
    for (int guard = 0; guard < 64; guard++) {
        if (![self _childCount:c type:type])
            break;
        c = [self _child:0 of:c type:type];
        if (!c)
            break;
        [out addObject:c];
    }
    return out;
}
- (NSArray *)_displayValuesFor:(NSArray *)criteria row:(NSInteger)row
{
    NSMutableArray *out = [NSMutableArray array];
    for (id c in criteria)
        [out addObject:[_delegate ruleEditor:self displayValueForCriterion:c inRow:row] ?: @""];
    return out;
}

- (id)_newRowOfType:(NSRuleEditorRowType)type
{
    id row = [[[_rowClass alloc] init] autorelease];
    [row setValue:@(type) forKeyPath:_typeKey];
    [row setValue:[NSMutableArray array] forKeyPath:_subrowsKey];
    [row setValue:@[] forKeyPath:_criteriaKey];
    [row setValue:@[] forKeyPath:_valuesKey];
    return row;
}

- (void)insertRowAtIndex:(NSInteger)index withType:(NSRuleEditorRowType)type asSubrowOfRow:(NSInteger)parent
                 animate:(BOOL)animate
{
    NSInteger n = [self numberOfRows];
    if (parent >= n || parent < -1 || index < 0 || index > n || (parent >= 0 && index <= parent))
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSRuleEditor insertRowAtIndex:withType:asSubrowOfRow:animate:] row %ld can't go "
                           @"under row %ld",
                           (long)index, (long)parent];
    if (parent >= 0 && [self rowTypeForRow:parent] != NSRuleEditorRowTypeCompound)
        [NSException raise:NSInvalidArgumentException format:@"-[NSRuleEditor] only a compound row has subrows"];
    /* its place among its parent's rows: after those shown before it */
    NSUInteger at = 0;
    for (NSInteger i = parent + 1; i < index; i++)
        if (((ARuleRow *)_flat[i])->parent == parent)
            at++;
    id row = [self _newRowOfType:type];
    NSArray *criteria = [self _criteriaFrom:nil type:type];
    [row setValue:criteria forKeyPath:_criteriaKey];
    _mutating = YES;
    NSMutableArray *siblings =
        parent < 0 ? [self _mutableTopRows] : [self _mutableSubrowsOf:((ARuleRow *)_flat[parent])->object];
    [siblings insertObject:row atIndex:MIN(at, [siblings count])];
    _mutating = NO;
    [self _flatten];
    [row setValue:[self _displayValuesFor:criteria row:index] forKeyPath:_valuesKey];
    [self _changed];
}

- (void)addRow:(id)sender
{
    NSInteger n = [self numberOfRows];
    if (_nesting == NSRuleEditorNestingModeSingle && n)
        return;
    if (!n) {
        NSRuleEditorRowType type = _nesting == NSRuleEditorNestingModeCompound ||
                                           _nesting == NSRuleEditorNestingModeSimple
                                       ? NSRuleEditorRowTypeCompound
                                       : NSRuleEditorRowTypeSimple;
        [self insertRowAtIndex:0 withType:type asSubrowOfRow:-1 animate:NO];
        if (type == NSRuleEditorRowTypeCompound && _nesting == NSRuleEditorNestingModeSimple)
            [self insertRowAtIndex:1 withType:NSRuleEditorRowTypeSimple asSubrowOfRow:0 animate:NO];
        return;
    }
    /* a simple row at the end: under the first row, if that's compound */
    if ([self rowTypeForRow:0] == NSRuleEditorRowTypeCompound && [[self _topRows] count] == 1)
        [self insertRowAtIndex:n withType:NSRuleEditorRowTypeSimple asSubrowOfRow:0 animate:NO];
    else
        [self insertRowAtIndex:n withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
}

- (void)setCriteria:(NSArray *)criteria andDisplayValues:(NSArray *)values forRowAtIndex:(NSInteger)row
{
    if (!criteria || !values || [criteria count] != [values count])
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSRuleEditor setCriteria:andDisplayValues:forRowAtIndex:] needs as many criteria as "
                           @"display values"];
    if (row < 0 || row > [self numberOfRows])
        [NSException raise:NSRangeException format:@"-[NSRuleEditor] no row %ld", (long)row];
    if (row == [self numberOfRows]) {
        /* one past the end makes a row */
        [self insertRowAtIndex:row withType:NSRuleEditorRowTypeSimple asSubrowOfRow:-1 animate:NO];
    }
    id object = [self _object:row];
    _mutating = YES;
    [object setValue:[[criteria copy] autorelease] forKeyPath:_criteriaKey];
    [object setValue:[[values copy] autorelease] forKeyPath:_valuesKey];
    _mutating = NO;
    [self _changed];
}

- (void)_removeRows:(NSIndexSet *)rows includeSubrows:(BOOL)includeSubrows
{
    if (![rows count])
        return;
    if ([rows lastIndex] >= [_flat count])
        [NSException raise:NSRangeException format:@"-[NSRuleEditor] no row %lu", (unsigned long)[rows lastIndex]];
    _mutating = YES;
    /* from the last up, so the indexes before stay right */
    for (NSUInteger i = [rows lastIndex]; i != NSNotFound; i = [rows indexLessThanIndex:i]) {
        ARuleRow *r = _flat[i];
        NSMutableArray *siblings = [self _siblingsOfRow:i];
        NSUInteger at = [siblings indexOfObjectIdenticalTo:r->object];
        if (at == NSNotFound)
            continue;
        NSArray *children = includeSubrows ? @[] : [[[self _subrowsOf:r->object] copy] autorelease];
        [siblings removeObjectAtIndex:at];
        /* its subrows, kept, take its place */
        for (NSUInteger k = 0; k < [children count]; k++)
            [siblings insertObject:children[k] atIndex:at + k];
    }
    _mutating = NO;
    [_selected removeAllIndexes];
    [self _changed];
}
- (void)removeRowAtIndex:(NSInteger)row
{
    [self _object:row];
    [self _removeRows:[NSIndexSet indexSetWithIndex:row] includeSubrows:NO];
}
- (void)removeRowsAtIndexes:(NSIndexSet *)rows includeSubrows:(BOOL)includeSubrows
{
    [self _removeRows:rows includeSubrows:includeSubrows];
}

- (NSIndexSet *)selectedRowIndexes { return [[_selected copy] autorelease]; }
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
    if (!extend)
        [_selected removeAllIndexes];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < [self->_flat count])
            [self->_selected addIndex:i];
    }];
    [self setNeedsDisplay:YES];
}

/* each row's criteria checked against what the delegate offers now */
- (void)reloadCriteria
{
    [self _flatten];
    _mutating = YES;
    for (NSUInteger i = 0; i < [_flat count]; i++) {
        NSRuleEditorRowType type = [self rowTypeForRow:i];
        NSArray *old = [self criteriaForRow:i];
        NSMutableArray *kept = [NSMutableArray array];
        id parent = nil;
        for (id c in old) {
            NSInteger n = [self _childCount:parent type:type];
            BOOL found = NO;
            for (NSInteger k = 0; k < n && !found; k++)
                found = [[self _child:k of:parent type:type] isEqual:c];
            if (!found)
                break;
            [kept addObject:c];
            parent = c;
        }
        NSArray *criteria = [self _criteriaFrom:kept type:type];
        id object = ((ARuleRow *)_flat[i])->object;
        [object setValue:criteria forKeyPath:_criteriaKey];
        [object setValue:[self _displayValuesFor:criteria row:i] forKeyPath:_valuesKey];
    }
    _mutating = NO;
    [self _changed];
}

/* ---- predicates ---- */

- (NSDictionary *)_partsForRow:(NSInteger)row
{
    if (![_delegate respondsToSelector:@selector(ruleEditor:predicatePartsForCriterion:withDisplayValue:inRow:)])
        return nil;
    NSMutableDictionary *parts = [NSMutableDictionary dictionary];
    NSArray *criteria = [self criteriaForRow:row], *values = [self displayValuesForRow:row];
    for (NSUInteger i = 0; i < [criteria count]; i++) {
        NSDictionary *p = [_delegate ruleEditor:self predicatePartsForCriterion:criteria[i]
                               withDisplayValue:i < [values count] ? values[i] : nil
                                          inRow:row];
        if (p)
            [parts addEntriesFromDictionary:p];
    }
    return parts;
}
- (NSPredicate *)predicateForRow:(NSInteger)row
{
    NSDictionary *parts = [self _partsForRow:row];
    if (!parts)
        return nil;
    if ([self rowTypeForRow:row] == NSRuleEditorRowTypeCompound) {
        NSMutableArray *subs = [NSMutableArray array];
        [[self subrowIndexesForRow:row] enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
            NSPredicate *p = [self predicateForRow:i];
            if (p)
                [subs addObject:p];
        }];
        NSNumber *type = parts[NSRuleEditorPredicateCompoundType];
        return [[[NSCompoundPredicate alloc]
            initWithType:type ? (NSCompoundPredicateType)[type unsignedIntegerValue] : NSAndPredicateType
           subpredicates:subs] autorelease];
    }
    NSExpression *lhs = parts[NSRuleEditorPredicateLeftExpression], *rhs = parts[NSRuleEditorPredicateRightExpression];
    if (!lhs || !rhs)
        return nil;
    NSString *custom = parts[NSRuleEditorPredicateCustomSelector];
    if (custom)
        return [NSComparisonPredicate predicateWithLeftExpression:lhs rightExpression:rhs
                                                   customSelector:NSSelectorFromString(custom)];
    return [NSComparisonPredicate
        predicateWithLeftExpression:lhs
                    rightExpression:rhs
                           modifier:(NSComparisonPredicateModifier)[parts[NSRuleEditorPredicateComparisonModifier]
                                        unsignedIntegerValue]
                               type:(NSPredicateOperatorType)[parts[NSRuleEditorPredicateOperatorType]
                                        unsignedIntegerValue]
                            options:[parts[NSRuleEditorPredicateOptions] unsignedIntegerValue]];
}
- (void)reloadPredicate
{
    NSMutableArray *top = [NSMutableArray array];
    for (NSUInteger i = 0; i < [_flat count]; i++)
        if (((ARuleRow *)_flat[i])->parent < 0) {
            NSPredicate *p = [self predicateForRow:i];
            if (p)
                [top addObject:p];
        }
    NSPredicate *p = [top count] == 1 ? top[0] : [top count] ? [NSCompoundPredicate andPredicateWithSubpredicates:top] : nil;
    [_predicate autorelease];
    _predicate = [p retain];
}
- (NSPredicate *)predicate { return _predicate; }

/* ---- what's shown ---- */

- (NSString *)_shown:(NSString *)s { return _formatting[s] ?: s; }

- (NSView *)_viewForValue:(id)value row:(NSInteger)row level:(NSInteger)level
{
    NSRuleEditorRowType type = [self rowTypeForRow:row];
    NSArray *criteria = [self criteriaForRow:row];
    id parent = level > 0 ? criteria[level - 1] : nil;
    if ([value isKindOfClass:[NSView class]])
        return value;
    NSInteger n = [self _childCount:parent type:type];
    if (n <= 1 && ![value isKindOfClass:[NSMenuItem class]]) {
        NSTextField *label = [NSTextField labelWithString:[self _shown:[value description]]];
        [label sizeToFit];
        return label;
    }
    ARuleEditorPopUp *pop = [[[ARuleEditorPopUp alloc] initWithFrame:NSMakeRect(0, 0, 100, 22) pullsDown:NO]
        autorelease];
    pop->row = row;
    pop->level = level;
    NSMutableArray *choices = [NSMutableArray array];
    NSInteger chosen = 0;
    for (NSInteger k = 0; k < n; k++) {
        id child = [self _child:k of:parent type:type];
        if (!child)
            continue;
        if ([child isEqual:criteria[level]])
            chosen = (NSInteger)[choices count];
        [choices addObject:child];
        id shown = [child isEqual:criteria[level]] ? value
                                                     : [_delegate ruleEditor:self displayValueForCriterion:child
                                                                       inRow:row];
        if ([shown isKindOfClass:[NSMenuItem class]]) {
            NSMenuItem *item = [[(NSMenuItem *)shown copy] autorelease];
            [[pop menu] addItem:item];
        } else
            [pop addItemWithTitle:[self _shown:[shown description] ?: @""]];
    }
    pop->choices = [choices copy];
    [pop selectItemAtIndex:chosen];
    [pop setTarget:self];
    [pop setAction:@selector(_choose:)];
    [pop sizeToFit];
    return pop;
}

- (void)_choose:(ARuleEditorPopUp *)pop
{
    NSInteger k = [pop indexOfSelectedItem], row = pop->row, level = pop->level;
    if (k < 0 || k >= (NSInteger)[pop->choices count] || row >= [self numberOfRows])
        return;
    NSArray *criteria = [self criteriaForRow:row];
    if (level >= (NSInteger)[criteria count] || [criteria[level] isEqual:pop->choices[k]])
        return;
    NSMutableArray *kept = [[[criteria subarrayWithRange:NSMakeRange(0, level)] mutableCopy] autorelease];
    [kept addObject:pop->choices[k]];
    NSArray *now = [self _criteriaFrom:kept type:[self rowTypeForRow:row]];
    [self setCriteria:now andDisplayValues:[self _displayValuesFor:now row:row] forRowAtIndex:row];
}

- (void)_removeButton:(ARuleEditorButton *)b
{
    if (b->row < [self numberOfRows])
        [self _removeRows:[NSIndexSet indexSetWithIndex:b->row] includeSubrows:YES];
}
- (void)_addButton:(ARuleEditorButton *)b
{
    NSInteger row = b->row;
    if (row >= [self numberOfRows])
        return;
    if ([self rowTypeForRow:row] == NSRuleEditorRowTypeCompound) {
        /* a subrow, after its last one */
        NSInteger end = row + 1;
        while (end < [self numberOfRows] && ((ARuleRow *)_flat[end])->depth > ((ARuleRow *)_flat[row])->depth)
            end++;
        [self insertRowAtIndex:end withType:NSRuleEditorRowTypeSimple asSubrowOfRow:row animate:YES];
        return;
    }
    [self insertRowAtIndex:row + 1 withType:NSRuleEditorRowTypeSimple
             asSubrowOfRow:((ARuleRow *)_flat[row])->parent
                   animate:YES];
}

- (void)_rebuild
{
    if (!_flat)
        return;
    [self _flatten];
    for (NSView *v in [[[self subviews] copy] autorelease])
        [v removeFromSuperview];
    CGFloat width = NSWidth([self bounds]);
    NSInteger n = [self numberOfRows];
    for (NSInteger i = 0; i < n; i++) {
        ARuleRow *r = _flat[i];
        NSView *rowView = [[[NSView alloc] initWithFrame:NSMakeRect(0, i * _rowHeight, width, _rowHeight)]
            autorelease];
        [rowView setAutoresizingMask:NSViewWidthSizable];
        CGFloat x = kGap + (_nesting == NSRuleEditorNestingModeCompound ? r->depth * kIndent : 0);
        NSArray *values = [self displayValuesForRow:i];
        for (NSUInteger level = 0; level < [values count]; level++) {
            NSView *v = [self _viewForValue:values[level] row:i level:(NSInteger)level];
            NSRect f = [v frame];
            f.origin = NSMakePoint(x, MAX(floor((_rowHeight - NSHeight(f)) / 2), 0));
            [v removeFromSuperview];
            [v setFrame:f];
            [rowView addSubview:v];
            x += NSWidth(f) + kGap;
        }
        if (_editable) {
            BOOL removable = _canRemoveAll || n > 1;
            ARuleEditorButton *minus = [ARuleEditorButton buttonWithTitle:@"−" target:self
                                                                   action:@selector(_removeButton:)];
            ARuleEditorButton *plus = [ARuleEditorButton buttonWithTitle:@"+" target:self
                                                                  action:@selector(_addButton:)];
            minus->row = plus->row = i;
            [minus setEnabled:removable && [self isEnabled]];
            [plus setEnabled:[self isEnabled] && _nesting != NSRuleEditorNestingModeSingle];
            CGFloat y = floor((_rowHeight - kButton) / 2);
            [minus setFrame:NSMakeRect(width - 2 * (kButton + kGap), y, kButton, kButton)];
            [plus setFrame:NSMakeRect(width - (kButton + kGap), y, kButton, kButton)];
            [minus setAutoresizingMask:NSViewMinXMargin];
            [plus setAutoresizingMask:NSViewMinXMargin];
            [rowView addSubview:minus];
            [rowView addSubview:plus];
        }
        [self addSubview:rowView];
    }
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, [self numberOfRows] * _rowHeight); }

/* after every change: the views, the predicate, then the news */
- (void)_changed
{
    [self _rebuild];
    [self reloadPredicate];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSRuleEditorRowsDidChangeNotification object:self];
}

- (void)drawRect:(NSRect)dirty
{
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirty);
    [[NSColor selectedContentBackgroundColor] setFill];
    [_selected enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        NSRectFill(NSMakeRect(0, i * self->_rowHeight, NSWidth([self bounds]), self->_rowHeight));
    }];
}
@end
