/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSPredicateEditor and NSPredicateEditorRowTemplate
 * (sdk/include/AppKit/NSPredicateEditor.h; freemac 1.232, Ferry 0.56.0),
 * written from Apple's public documentation; no Apple code was used.
 *
 * The editor is an NSRuleEditor that gives its rows' criteria itself, from
 * its row templates, while its delegate still hears of changed rows. A
 * row's criteria are one or two: when its row type has more than one
 * template, a choice of template (a pop-up of their first titles), then
 * the row's own copy of the chosen template, whose display value is a view
 * holding the copy's template views side by side. The row's predicate is
 * the copy's, from the predicates of its subrows when it is compound.
 *
 * Setting the editor's object value makes the rows: each predicate gets a
 * copy of the template that matches it best (the first of equals), told
 * the predicate, and a compound template's displayable subpredicates
 * become its subrows. In list or single nesting mode a compound predicate
 * is shown as its subpredicates, one row each, and the editor's predicate
 * joins the rows the same way again. The action is sent when a row is
 * added, removed or changed by hand, not when the object value is set.
 * Built without ARC. */
#import "AInternal.h"

@interface NSRuleEditor (FerryCriteria)
- (id)_criteriaSource;
- (void)_changed;
@end

@interface NSPredicateEditorRowTemplate ()
- (NSRuleEditorRowType)_ferryRowType;
- (NSString *)_ferryChoiceTitle;
- (void)_ferryHookViewsTo:(id)target;
@end

/* ---- the row's criteria ---- */

/* the choice of a template, or the row's copy of one; equal when they are
 * of the same template */
@interface APredicateCriterion : NSObject {
@public
    NSUInteger origin;
    NSPredicateEditorRowTemplate *copy;   /* nil for a choice */
    NSView *views;
}
@end
@implementation APredicateCriterion
- (void)dealloc
{
    [copy release];
    [views release];
    [super dealloc];
}
- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[APredicateCriterion class]])
        return NO;
    APredicateCriterion *o = other;
    return o->origin == origin && (o->copy == nil) == (copy == nil);
}
- (NSUInteger)hash { return origin * 2 + (copy != nil); }
@end

/* gives an editor's criteria from its templates */
@interface APredicateCriteria : NSObject <NSRuleEditorDelegate> {
@public
    NSPredicateEditor *editor;   /* not retained: the editor owns this */
}
@end

@interface NSPredicateEditor ()
- (NSArray *)_templatesOfType:(NSRuleEditorRowType)type;
- (APredicateCriterion *)_rowCopyOfTemplate:(NSUInteger)i;
- (NSView *)_viewsOf:(APredicateCriterion *)c;
@end

@implementation NSPredicateEditor {
    NSArray *_templates;
    APredicateCriteria *_criteria;
    NSCompoundPredicateType _listType;
    BOOL _quiet;
}

- (void)_ferrySetUp
{
    _criteria = [[APredicateCriteria alloc] init];
    _criteria->editor = self;
    _listType = NSAndPredicateType;
    if (!_templates)
        _templates = [[NSArray alloc] init];
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        [self _ferrySetUp];
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        if ([coder allowsKeyedCoding] && [coder containsValueForKey:@"NSPredicateTemplates"])
            _templates = [[coder decodeObjectForKey:@"NSPredicateTemplates"] copy];
        [self _ferrySetUp];
    }
    return self;
}
- (void)dealloc
{
    [_templates release];
    _criteria->editor = nil;
    [_criteria release];
    [super dealloc];
}

- (id)_criteriaSource { return _criteria; }

- (NSArray *)rowTemplates { return _templates; }
- (void)setRowTemplates:(NSArray *)templates
{
    NSArray *t = [[NSArray alloc] initWithArray:templates ?: @[]];
    [_templates release];
    _templates = t;
    _quiet = YES;
    [self reloadCriteria];
    _quiet = NO;
}

/* the templates of a row type, by their place among all */
- (NSArray *)_templatesOfType:(NSRuleEditorRowType)type
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < [_templates count]; i++)
        if ([_templates[i] _ferryRowType] == type)
            [out addObject:@(i)];
    return out;
}

- (APredicateCriterion *)_rowCopyOfTemplate:(NSUInteger)i
{
    APredicateCriterion *c = [[[APredicateCriterion alloc] init] autorelease];
    c->origin = i;
    c->copy = [_templates[i] copy];
    return c;
}

/* the view showing a row's copy: its template views side by side */
- (NSView *)_viewsOf:(APredicateCriterion *)c
{
    if (c->views)
        return c->views;
    NSArray *views = [c->copy templateViews];
    CGFloat x = 0, h = 0;
    for (NSView *v in views)
        h = MAX(h, NSHeight([v frame]));
    NSView *box = [[NSView alloc] initWithFrame:NSZeroRect];
    for (NSView *v in views) {
        NSRect f = [v frame];
        f.origin = NSMakePoint(x, floor((h - NSHeight(f)) / 2));
        [v removeFromSuperview];
        [v setFrame:f];
        [box addSubview:v];
        x += NSWidth(f) + 4;
    }
    [box setFrameSize:NSMakeSize(MAX(x - 4, 0), h)];
    [c->copy _ferryHookViewsTo:self];
    c->views = box;
    return box;
}

/* the copy that shows a row */
- (NSPredicateEditorRowTemplate *)_templateForRow:(NSInteger)row
{
    for (id c in [self criteriaForRow:row])
        if ([c isKindOfClass:[APredicateCriterion class]] && ((APredicateCriterion *)c)->copy)
            return ((APredicateCriterion *)c)->copy;
    return nil;
}

- (NSPredicate *)predicateForRow:(NSInteger)row
{
    NSPredicateEditorRowTemplate *t = [self _templateForRow:row];
    if (!t)
        return nil;
    NSMutableArray *subs = nil;
    if ([self rowTypeForRow:row] == NSRuleEditorRowTypeCompound) {
        subs = [NSMutableArray array];
        [[self subrowIndexesForRow:row] enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
            NSPredicate *p = [self predicateForRow:(NSInteger)i];
            if (p)
                [subs addObject:p];
        }];
    }
    return [t predicateWithSubpredicates:subs];
}

- (NSPredicate *)predicate
{
    NSMutableArray *top = [NSMutableArray array];
    for (NSInteger i = 0; i < [self numberOfRows]; i++)
        if ([self parentRowForRow:i] < 0) {
            NSPredicate *p = [self predicateForRow:i];
            if (p)
                [top addObject:p];
        }
    if (![top count])
        return nil;
    if ([top count] == 1 && _listType != NSNotPredicateType)
        return top[0];
    return [[[NSCompoundPredicate alloc] initWithType:_listType subpredicates:top] autorelease];
}
- (id)objectValue { return [self predicate]; }

/* the best template for a predicate, or NSNotFound */
- (NSUInteger)_bestTemplateFor:(NSPredicate *)p
{
    NSUInteger best = NSNotFound;
    double score = 0;
    for (NSUInteger i = 0; i < [_templates count]; i++) {
        double m = [_templates[i] matchForPredicate:p];
        if (m > score) {
            score = m;
            best = i;
        }
    }
    return best;
}

- (void)_addRowFor:(NSPredicate *)p under:(NSInteger)parent
{
    NSUInteger best = [self _bestTemplateFor:p];
    if (best == NSNotFound) {
        NSLog(@"NSPredicateEditor: no row template shows the predicate %@", p);
        return;
    }
    NSPredicateEditorRowTemplate *t = _templates[best];
    NSRuleEditorRowType type = [t _ferryRowType];
    if (type == NSRuleEditorRowTypeCompound && parent >= 0 && [self rowTypeForRow:parent] != NSRuleEditorRowTypeCompound)
        return;
    /* after the parent's last row */
    NSInteger at = [self numberOfRows];
    if (parent >= 0) {
        at = parent + 1;
        while (at < [self numberOfRows]) {
            NSInteger up = [self parentRowForRow:at];
            while (up >= 0 && up != parent)
                up = [self parentRowForRow:up];
            if (up != parent)
                break;
            at++;
        }
    }
    [self insertRowAtIndex:at withType:type asSubrowOfRow:parent animate:NO];
    APredicateCriterion *c = [self _rowCopyOfTemplate:best];
    [c->copy setPredicate:p];
    NSMutableArray *criteria = [NSMutableArray array], *values = [NSMutableArray array];
    if ([[self _templatesOfType:type] count] > 1) {
        APredicateCriterion *choice = [[[APredicateCriterion alloc] init] autorelease];
        choice->origin = best;
        [criteria addObject:choice];
        [values addObject:[t _ferryChoiceTitle]];
    }
    [criteria addObject:c];
    [values addObject:[self _viewsOf:c]];
    [self setCriteria:criteria andDisplayValues:values forRowAtIndex:at];
    if (type == NSRuleEditorRowTypeCompound)
        for (NSPredicate *sub in [c->copy displayableSubpredicatesOfPredicate:p] ?: @[])
            [self _addRowFor:sub under:at];
}

- (void)setObjectValue:(id)value
{
    _quiet = YES;
    if ([self numberOfRows])
        [self removeRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self numberOfRows])]
                   includeSubrows:YES];
    _listType = NSAndPredicateType;
    if ([value isKindOfClass:[NSPredicate class]]) {
        NSRuleEditorNestingMode mode = [self nestingMode];
        BOOL flat = mode == NSRuleEditorNestingModeList || mode == NSRuleEditorNestingModeSingle;
        if (flat && [value isKindOfClass:[NSCompoundPredicate class]]) {
            _listType = [(NSCompoundPredicate *)value compoundPredicateType];
            for (NSPredicate *sub in [(NSCompoundPredicate *)value subpredicates])
                [self _addRowFor:sub under:-1];
        } else
            [self _addRowFor:value under:-1];
    }
    _quiet = NO;
}

- (void)_changed
{
    [super _changed];
    if (!_quiet && [self action])
        [self sendAction:[self action] to:[self target]];
}

/* one of a row's own views was changed by hand */
- (void)_templateViewChanged:(id)sender
{
    [self reloadPredicate];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSRuleEditorRowsDidChangeNotification object:self];
    if ([self action])
        [self sendAction:[self action] to:[self target]];
}
@end

@implementation APredicateCriteria
- (NSInteger)ruleEditor:(NSRuleEditor *)e numberOfChildrenForCriterion:(id)criterion withRowType:(NSRuleEditorRowType)type
{
    NSUInteger n = [[editor _templatesOfType:type] count];
    if (!criterion)
        return (NSInteger)n;
    APredicateCriterion *c = criterion;
    return c->copy ? 0 : 1;
}
- (id)ruleEditor:(NSRuleEditor *)e child:(NSInteger)index forCriterion:(id)criterion withRowType:(NSRuleEditorRowType)type
{
    NSArray *of = [editor _templatesOfType:type];
    if (!criterion) {
        if (index < 0 || index >= (NSInteger)[of count])
            return nil;
        NSUInteger i = [of[index] unsignedIntegerValue];
        if ([of count] == 1)
            return [editor _rowCopyOfTemplate:i];
        APredicateCriterion *choice = [[[APredicateCriterion alloc] init] autorelease];
        choice->origin = i;
        return choice;
    }
    return [editor _rowCopyOfTemplate:((APredicateCriterion *)criterion)->origin];
}
- (id)ruleEditor:(NSRuleEditor *)e displayValueForCriterion:(id)criterion inRow:(NSInteger)row
{
    APredicateCriterion *c = criterion;
    if (c->copy)
        return [editor _viewsOf:c];
    return [[editor rowTemplates][c->origin] _ferryChoiceTitle];
}
@end

/* ---- row templates ---- */

static NSString *operator_title(NSPredicateOperatorType t)
{
    switch (t) {
    case NSLessThanPredicateOperatorType: return @"is less than";
    case NSLessThanOrEqualToPredicateOperatorType: return @"is less than or equal to";
    case NSGreaterThanPredicateOperatorType: return @"is greater than";
    case NSGreaterThanOrEqualToPredicateOperatorType: return @"is greater than or equal to";
    case NSEqualToPredicateOperatorType: return @"is";
    case NSNotEqualToPredicateOperatorType: return @"is not";
    case NSMatchesPredicateOperatorType: return @"matches";
    case NSLikePredicateOperatorType: return @"is like";
    case NSBeginsWithPredicateOperatorType: return @"begins with";
    case NSEndsWithPredicateOperatorType: return @"ends with";
    case NSInPredicateOperatorType: return @"is in";
    case NSContainsPredicateOperatorType: return @"contains";
    case NSBetweenPredicateOperatorType: return @"is between";
    default: return [NSString stringWithFormat:@"operator %lu", (unsigned long)t];
    }
}
static NSString *compound_title(NSCompoundPredicateType t)
{
    return t == NSNotPredicateType ? @"None" : t == NSOrPredicateType ? @"Any" : @"All";
}
static NSString *expression_title(NSExpression *e)
{
    if ([e expressionType] == NSKeyPathExpressionType)
        return [e keyPath];
    if ([e expressionType] == NSConstantValueExpressionType)
        return [[e constantValue] description] ?: @"";
    return [e description];
}

/* whether two expressions are the same key path, constant or other */
static BOOL same_expression(NSExpression *a, NSExpression *b)
{
    if ([a expressionType] != [b expressionType])
        return NO;
    if ([a expressionType] == NSKeyPathExpressionType)
        return [[a keyPath] isEqual:[b keyPath]];
    if ([a expressionType] == NSConstantValueExpressionType)
        return [a constantValue] == [b constantValue] || [[a constantValue] isEqual:[b constantValue]];
    return [[a description] isEqual:[b description]];
}
static NSUInteger index_of_expression(NSArray *list, NSExpression *e)
{
    for (NSUInteger i = 0; i < [list count]; i++)
        if (same_expression(list[i], e))
            return i;
    return NSNotFound;
}

/* Core Data's attribute types, as numbers (CoreData.h has their names) */
enum { kInt16 = 100, kInt32 = 200, kInt64 = 300, kDecimal = 400, kDouble = 500, kFloat = 600, kBoolean = 800, kDate = 900 };

@implementation NSPredicateEditorRowTemplate {
    NSRuleEditorRowType _rowType;
    NSArray *_left, *_right, *_operators, *_compoundTypes;
    NSArray *_titles;   /* each pop-up's titles, from a nib; nil for the usual ones */
    NSUInteger _attributeType, _options;
    NSComparisonPredicateModifier _modifier;
    NSArray *_views;
    NSPopUpButton *_leftPop, *_operatorPop, *_rightPop;
    NSTextField *_rightField, *_label;
    NSButton *_rightCheck;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _left = [[NSArray alloc] init];
        _operators = [[NSArray alloc] init];
    }
    return self;
}
- (instancetype)initWithLeftExpressions:(NSArray *)left rightExpressions:(NSArray *)right
                               modifier:(NSComparisonPredicateModifier)modifier
                              operators:(NSArray *)operators
                                options:(NSUInteger)options
{
    if ((self = [self init])) {
        [_left release];
        [_operators release];
        _left = [left copy] ?: [[NSArray alloc] init];
        _right = [right copy];
        _modifier = modifier;
        _operators = [operators copy] ?: [[NSArray alloc] init];
        _options = options;
    }
    return self;
}
- (instancetype)initWithLeftExpressions:(NSArray *)left rightExpressionAttributeType:(NSUInteger)type
                               modifier:(NSComparisonPredicateModifier)modifier
                              operators:(NSArray *)operators
                                options:(NSUInteger)options
{
    if ((self = [self initWithLeftExpressions:left rightExpressions:nil modifier:modifier operators:operators
                                      options:options]))
        _attributeType = type;
    return self;
}
- (instancetype)initWithCompoundTypes:(NSArray *)types
{
    if ((self = [self init])) {
        _rowType = NSRuleEditorRowTypeCompound;
        _compoundTypes = [types copy];
    }
    return self;
}

/* A nib's template keeps these, as ferry-ibtool writes them from the
 * document: its row type, its left expressions' key paths (or constants),
 * the right side's attribute type or constants, the operators, the
 * modifier and options, the compound types and each pop-up's titles. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [self init]))
        return nil;
    if (![coder allowsKeyedCoding])
        return self;
    _rowType = [coder decodeIntegerForKey:@"NSPredicateTemplateRowType"] == 1 ? NSRuleEditorRowTypeCompound
                                                                                : NSRuleEditorRowTypeSimple;
    NSMutableArray *left = [NSMutableArray array];
    for (id k in [coder decodeObjectForKey:@"NSPredicateTemplateLeftKeyPaths"] ?: @[])
        [left addObject:[NSExpression expressionForKeyPath:k]];
    id wasLeft = _left;
    _left = [left copy];
    [wasLeft release];
    NSArray *constants = [coder decodeObjectForKey:@"NSPredicateTemplateRightConstants"];
    if ([constants count]) {
        NSMutableArray *right = [NSMutableArray array];
        for (id k in constants)
            [right addObject:[NSExpression expressionForConstantValue:k]];
        _right = [right copy];
    }
    _attributeType = (NSUInteger)[coder decodeIntegerForKey:@"NSPredicateTemplateRightAttributeType"];
    NSArray *ops = [coder decodeObjectForKey:@"NSPredicateTemplateOperators"];
    if (ops) {
        id wasOperators = _operators;
        _operators = [ops copy];
        [wasOperators release];
    }
    _modifier = (NSComparisonPredicateModifier)[coder decodeIntegerForKey:@"NSPredicateTemplateModifier"];
    _options = (NSUInteger)[coder decodeIntegerForKey:@"NSPredicateTemplateOptions"];
    _compoundTypes = [[coder decodeObjectForKey:@"NSPredicateTemplateCompoundTypes"] copy];
    _titles = [[coder decodeObjectForKey:@"NSPredicateTemplateTitles"] copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding])
        return;
    [coder encodeInteger:_rowType forKey:@"NSPredicateTemplateRowType"];
    NSMutableArray *keys = [NSMutableArray array];
    for (NSExpression *e in _left)
        if ([e expressionType] == NSKeyPathExpressionType)
            [keys addObject:[e keyPath]];
    [coder encodeObject:keys forKey:@"NSPredicateTemplateLeftKeyPaths"];
    if (_right) {
        NSMutableArray *k = [NSMutableArray array];
        for (NSExpression *e in _right)
            if ([e expressionType] == NSConstantValueExpressionType && [e constantValue])
                [k addObject:[e constantValue]];
        [coder encodeObject:k forKey:@"NSPredicateTemplateRightConstants"];
    }
    [coder encodeInteger:(NSInteger)_attributeType forKey:@"NSPredicateTemplateRightAttributeType"];
    [coder encodeObject:_operators forKey:@"NSPredicateTemplateOperators"];
    [coder encodeInteger:(NSInteger)_modifier forKey:@"NSPredicateTemplateModifier"];
    [coder encodeInteger:(NSInteger)_options forKey:@"NSPredicateTemplateOptions"];
    if (_compoundTypes)
        [coder encodeObject:_compoundTypes forKey:@"NSPredicateTemplateCompoundTypes"];
    if (_titles)
        [coder encodeObject:_titles forKey:@"NSPredicateTemplateTitles"];
}

/* a copy is a template of the same class and settings with views of its own */
- (id)copyWithZone:(NSZone *)zone
{
    NSPredicateEditorRowTemplate *c = [[[self class] allocWithZone:zone] init];
    c->_rowType = _rowType;
    [c->_left release];
    c->_left = [_left copy];
    c->_right = [_right copy];
    [c->_operators release];
    c->_operators = [_operators copy];
    c->_compoundTypes = [_compoundTypes copy];
    c->_titles = [_titles copy];
    c->_attributeType = _attributeType;
    c->_options = _options;
    c->_modifier = _modifier;
    return c;
}

- (void)dealloc
{
    [_left release];
    [_right release];
    [_operators release];
    [_compoundTypes release];
    [_titles release];
    [_views release];
    [super dealloc];
}

- (NSArray *)leftExpressions { return _left; }
- (NSArray *)rightExpressions { return _right; }
- (NSUInteger)rightExpressionAttributeType { return _attributeType; }
- (NSComparisonPredicateModifier)modifier { return _modifier; }
- (NSArray *)operators { return _operators; }
- (NSUInteger)options { return _options; }
- (NSArray *)compoundTypes { return _compoundTypes; }

- (NSRuleEditorRowType)_ferryRowType { return _rowType; }

/* a pop-up's titles: the nib's, else the usual ones */
- (NSString *)_title:(NSUInteger)menu item:(NSUInteger)i usual:(NSString *)usual
{
    if (menu < [_titles count] && i < [_titles[menu] count])
        return _titles[menu][i];
    return usual;
}
- (NSString *)_ferryChoiceTitle
{
    if (_rowType == NSRuleEditorRowTypeCompound)
        return [self _title:0 item:0 usual:compound_title([[_compoundTypes firstObject] unsignedIntegerValue])];
    return [self _title:0 item:0 usual:[_left count] ? expression_title(_left[0]) : @""];
}

- (NSPopUpButton *)_popUpOf:(NSArray *)titles
{
    NSPopUpButton *pop = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 22) pullsDown:NO] autorelease];
    for (NSString *t in titles)
        [pop addItemWithTitle:t];
    [pop sizeToFit];
    return pop;
}

- (NSArray *)templateViews
{
    if (_views)
        return _views;
    NSMutableArray *views = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    if (_rowType == NSRuleEditorRowTypeCompound) {
        for (NSUInteger i = 0; i < [_compoundTypes count]; i++)
            [titles addObject:[self _title:0 item:i usual:compound_title([_compoundTypes[i] unsignedIntegerValue])]];
        _leftPop = [self _popUpOf:titles];
        [views addObject:_leftPop];
        _label = [NSTextField labelWithString:[self _title:1 item:0 usual:@"of the following are true"]];
        [_label sizeToFit];
        [views addObject:_label];
    } else {
        for (NSUInteger i = 0; i < [_left count]; i++)
            [titles addObject:[self _title:0 item:i usual:expression_title(_left[i])]];
        _leftPop = [self _popUpOf:titles];
        [views addObject:_leftPop];
        [titles removeAllObjects];
        for (NSUInteger i = 0; i < [_operators count]; i++)
            [titles addObject:[self _title:1 item:i usual:operator_title([_operators[i] unsignedIntegerValue])]];
        _operatorPop = [self _popUpOf:titles];
        [views addObject:_operatorPop];
        if (_right) {
            [titles removeAllObjects];
            for (NSUInteger i = 0; i < [_right count]; i++)
                [titles addObject:[self _title:2 item:i usual:expression_title(_right[i])]];
            _rightPop = [self _popUpOf:titles];
            [views addObject:_rightPop];
        } else if (_attributeType == kBoolean) {
            _rightCheck = [NSButton checkboxWithTitle:@"" target:nil action:NULL];
            [views addObject:_rightCheck];
        } else {
            _rightField = [NSTextField textFieldWithString:@""];
            [_rightField setFrame:NSMakeRect(0, 0, 120, 22)];
            [views addObject:_rightField];
        }
    }
    _views = [views copy];
    return _views;
}

/* the controls send their changes to the editor, unless they have an action */
- (void)_ferryHookViewsTo:(id)target
{
    for (NSView *v in [self templateViews])
        if ([v isKindOfClass:[NSControl class]] && ![(NSControl *)v action]) {
            [(NSControl *)v setTarget:target];
            [(NSControl *)v setAction:@selector(_templateViewChanged:)];
        }
}

- (double)matchForPredicate:(NSPredicate *)p
{
    if (_rowType == NSRuleEditorRowTypeCompound) {
        if (![p isKindOfClass:[NSCompoundPredicate class]])
            return 0;
        return [_compoundTypes containsObject:@([(NSCompoundPredicate *)p compoundPredicateType])] ? 1 : 0;
    }
    if (![p isKindOfClass:[NSComparisonPredicate class]])
        return 0;
    NSComparisonPredicate *c = (NSComparisonPredicate *)p;
    if (index_of_expression(_left, [c leftExpression]) == NSNotFound || ![_operators containsObject:@([c predicateOperatorType])])
        return 0;
    NSExpression *rhs = [c rightExpression];
    if ([rhs expressionType] != NSConstantValueExpressionType)
        return 0;
    if (_right)
        return index_of_expression(_right, rhs) != NSNotFound ? 1 : 0;
    id v = [rhs constantValue];
    switch (_attributeType) {
    case kInt16: case kInt32: case kInt64: case kDecimal: case kDouble: case kFloat: case kBoolean:
        return [v isKindOfClass:[NSNumber class]] ? 1 : 0;
    case kDate:
        return [v isKindOfClass:[NSDate class]] ? 1 : 0;
    default:
        return [v isKindOfClass:[NSString class]] ? 1 : 0.5;
    }
}

- (void)setPredicate:(NSPredicate *)p
{
    [self templateViews];
    if (_rowType == NSRuleEditorRowTypeCompound) {
        if ([p isKindOfClass:[NSCompoundPredicate class]]) {
            NSUInteger i = [_compoundTypes indexOfObject:@([(NSCompoundPredicate *)p compoundPredicateType])];
            if (i != NSNotFound)
                [_leftPop selectItemAtIndex:(NSInteger)i];
        }
        return;
    }
    if (![p isKindOfClass:[NSComparisonPredicate class]])
        return;
    NSComparisonPredicate *c = (NSComparisonPredicate *)p;
    NSUInteger i = index_of_expression(_left, [c leftExpression]);
    if (i != NSNotFound)
        [_leftPop selectItemAtIndex:(NSInteger)i];
    i = [_operators indexOfObject:@([c predicateOperatorType])];
    if (i != NSNotFound)
        [_operatorPop selectItemAtIndex:(NSInteger)i];
    NSExpression *rhs = [c rightExpression];
    if (_rightPop) {
        i = index_of_expression(_right, rhs);
        if (i != NSNotFound)
            [_rightPop selectItemAtIndex:(NSInteger)i];
    } else if (_rightCheck)
        [_rightCheck setState:[[rhs constantValue] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
    else if ([rhs expressionType] == NSConstantValueExpressionType)
        [_rightField setStringValue:[[rhs constantValue] description] ?: @""];
}

- (NSPredicate *)predicateWithSubpredicates:(NSArray *)subpredicates
{
    [self templateViews];
    if (_rowType == NSRuleEditorRowTypeCompound) {
        NSInteger i = [_leftPop indexOfSelectedItem];
        NSCompoundPredicateType type =
            i >= 0 && i < (NSInteger)[_compoundTypes count] ? [_compoundTypes[i] unsignedIntegerValue] : NSAndPredicateType;
        NSArray *subs = subpredicates ?: @[];
        if (type == NSNotPredicateType && [subs count] != 1)
            subs = @[ [NSCompoundPredicate orPredicateWithSubpredicates:subs] ];
        return [[[NSCompoundPredicate alloc] initWithType:type subpredicates:subs] autorelease];
    }
    NSInteger l = [_leftPop indexOfSelectedItem], o = [_operatorPop indexOfSelectedItem];
    if (l < 0 || l >= (NSInteger)[_left count] || o < 0 || o >= (NSInteger)[_operators count])
        return nil;
    NSExpression *rhs;
    if (_rightPop) {
        NSInteger r = [_rightPop indexOfSelectedItem];
        if (r < 0 || r >= (NSInteger)[_right count])
            return nil;
        rhs = _right[r];
    } else if (_rightCheck)
        rhs = [NSExpression expressionForConstantValue:@([_rightCheck state] == NSControlStateValueOn)];
    else {
        NSString *s = [_rightField stringValue] ?: @"";
        id v = s;
        switch (_attributeType) {
        case kInt16: case kInt32: case kInt64:
            v = @([s longLongValue]);
            break;
        case kDecimal: case kDouble: case kFloat:
            v = @([s doubleValue]);
            break;
        case kDate: {
            /* typed as the user's medium date */
            NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
            [f setDateStyle:NSDateFormatterMediumStyle];
            v = [f dateFromString:s] ?: [NSDate date];
            break;
        }
        }
        rhs = [NSExpression expressionForConstantValue:v];
    }
    return [NSComparisonPredicate predicateWithLeftExpression:_left[l] rightExpression:rhs modifier:_modifier
                                                         type:[_operators[o] unsignedIntegerValue]
                                                      options:_options];
}

- (NSArray *)displayableSubpredicatesOfPredicate:(NSPredicate *)p
{
    if (_rowType != NSRuleEditorRowTypeCompound || ![p isKindOfClass:[NSCompoundPredicate class]])
        return nil;
    NSArray *subs = [(NSCompoundPredicate *)p subpredicates];
    /* None of one Any: its subpredicates, as predicateWithSubpredicates: makes it */
    if ([(NSCompoundPredicate *)p compoundPredicateType] == NSNotPredicateType && [subs count] == 1 &&
        [subs[0] isKindOfClass:[NSCompoundPredicate class]] &&
        [(NSCompoundPredicate *)subs[0] compoundPredicateType] == NSOrPredicateType)
        return [(NSCompoundPredicate *)subs[0] subpredicates];
    return subs;
}
@end
