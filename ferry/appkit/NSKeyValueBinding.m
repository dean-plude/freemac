/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Cocoa bindings. A binding ties a property of a view (a
 * control's value, say) to a key path of another object (a controller, or
 * the user's defaults). The bound property is set from the key path's
 * value when the binding is made and again whenever the observed object
 * announces a change of it (key-value observing, in Ferry's Foundation);
 * what the user changes in a control (a click, a choice, an edit ended) is
 * written back to the key path with setValue:forKeyPath:.
 *
 * The options: a value transformer, by name or as an object, turns the
 * key path's value into the view's (and back, if it can, for a write);
 * NSNullPlaceholderBindingOption stands in for nil (a text field shows it
 * greyed, as its placeholder); the no-selection, multiple-values and
 * not-applicable placeholders stand in for a controller's markers;
 * NSContinuouslyUpdatesValueBindingOption writes a text field's value back
 * as it is typed, not when the editing ends. Several enabled bindings
 * (enabled, enabled2, ...) are combined with AND, hidden ones with OR.
 * Pop-up buttons take content, contentObjects and contentValues for their
 * items and selectedIndex, selectedObject, selectedValue and selectedTag
 * for the choice. A key the observed object doesn't have leaves the
 * property as it is, unless NSRaisesForNotApplicableKeysBindingOption is
 * YES.
 *
 * Tables (Ferry 0.18.0): a table column's value bound to
 * "arrangedObjects.key" of an array controller shows each arranged
 * object's key in its row, and an edited cell sets it on that object.
 * Binding a column so binds its table's content, selectionIndexes and
 * sortDescriptors to the same controller, unless they are bound already,
 * and gives the column a sort descriptor for the key (compare:), unless
 * NSCreatesSortDescriptorBindingOption is NO; so the user's selection and
 * a click on a column's title reach the controller.
 *
 * Validation and conditions (Ferry 0.20.0): with
 * NSValidatesImmediatelyBindingOption a value is validated
 * (validateValue:forKeyPath:error:, so validate<Key>:error:) before it is
 * written back; a value refused is not written, the error is presented
 * (presentError:, from the view up the responder chain) and the view shows
 * the model's value again; a value the validation changes is written and
 * shown as changed. A continuously updated value that fails is skipped
 * quietly until the editing ends. NSConditionallySetsEditable (YES by
 * default) makes a bound text field editable only while its value can be
 * edited (there is a selection, its controller is editable, multiple
 * values are allowed to be edited, the key applies); NSConditionallySetsEnabled
 * (YES by default except for text fields) does the same for the view's
 * enabled state, ANDed with its enabled bindings. NSRaisesForNotApplicableKeys
 * YES raises for a key a controller's selection doesn't have; NO shows the
 * not-applicable placeholder ("Not Applicable" in a text field); left out,
 * Ferry leaves the view as it is (a Mac raises).
 *
 * Trees and rows (Ferry 0.19.0): in an outline view whose content is bound
 * to a tree controller, a column's "arrangedObjects.key" is the key of
 * each row's node's represented object, and the outline's selection is
 * bound as selectionIndexPaths. A column's editable and enabled bindings
 * are read for each row's object, like its value; an edited cell is
 * written back only when they are true for its row and the value's
 * controller is editable (unless NSConditionallySetsEditable is NO).
 *
 * Written from Apple's public documentation of NSKeyValueBindingCreation
 * and the Cocoa Bindings Reference; no Apple code was used. */
#import "AInternal.h"

NSString *const NSObservedObjectKey = @"NSObservedObject";
NSString *const NSObservedKeyPathKey = @"NSObservedKeyPath";
NSString *const NSOptionsKey = @"NSOptions";

NSString *const NSValueBinding = @"value";
NSString *const NSAttributedStringBinding = @"attributedString";
NSString *const NSDataBinding = @"data";
NSString *const NSEnabledBinding = @"enabled";
NSString *const NSHiddenBinding = @"hidden";
NSString *const NSTitleBinding = @"title";
NSString *const NSAlternateTitleBinding = @"alternateTitle";
NSString *const NSContentBinding = @"content";
NSString *const NSContentValuesBinding = @"contentValues";
NSString *const NSContentObjectsBinding = @"contentObjects";
NSString *const NSContentObjectBinding = @"contentObject";
NSString *const NSSelectedIndexBinding = @"selectedIndex";
NSString *const NSSelectedObjectBinding = @"selectedObject";
NSString *const NSSelectedValueBinding = @"selectedValue";
NSString *const NSSelectedTagBinding = @"selectedTag";
NSString *const NSToolTipBinding = @"toolTip";
NSString *const NSEditableBinding = @"editable";
NSString *const NSMinValueBinding = @"minValue";
NSString *const NSMaxValueBinding = @"maxValue";
NSString *const NSTextColorBinding = @"textColor";
NSString *const NSImageBinding = @"image";
NSString *const NSFontBinding = @"font";
NSString *const NSHeaderTitleBinding = @"headerTitle";
NSString *const NSMaxWidthBinding = @"maxWidth";
NSString *const NSMinWidthBinding = @"minWidth";
NSString *const NSWidthBinding = @"width";

NSString *const NSNullPlaceholderBindingOption = @"NSNullPlaceholder";
NSString *const NSNoSelectionPlaceholderBindingOption = @"NSNoSelectionPlaceholder";
NSString *const NSMultipleValuesPlaceholderBindingOption = @"NSMultipleValuesPlaceholder";
NSString *const NSNotApplicablePlaceholderBindingOption = @"NSNotApplicablePlaceholder";
NSString *const NSValueTransformerNameBindingOption = @"NSValueTransformerName";
NSString *const NSValueTransformerBindingOption = @"NSValueTransformer";
NSString *const NSContinuouslyUpdatesValueBindingOption = @"NSContinuouslyUpdatesValue";
NSString *const NSRaisesForNotApplicableKeysBindingOption = @"NSRaisesForNotApplicableKeys";
NSString *const NSConditionallySetsEnabledBindingOption = @"NSConditionallySetsEnabled";
NSString *const NSConditionallySetsEditableBindingOption = @"NSConditionallySetsEditable";
NSString *const NSAllowsEditingMultipleValuesSelectionBindingOption = @"NSAllowsEditingMultipleValuesSelection";
NSString *const NSValidatesImmediatelyBindingOption = @"NSValidatesImmediately";
NSString *const NSCreatesSortDescriptorBindingOption = @"NSCreatesSortDescriptor";

/* ---- the markers a controller's selection answers ---- */

@interface ABindingMarker : NSObject <NSCopying> {
    const char *_name;
}
@end

id NSMultipleValuesMarker, NSNoSelectionMarker, NSNotApplicableMarker;

@implementation ABindingMarker
+ (void)load
{
    ABindingMarker *m;
    m = [[ABindingMarker alloc] init], m->_name = "NSMultipleValuesMarker", NSMultipleValuesMarker = m;
    m = [[ABindingMarker alloc] init], m->_name = "NSNoSelectionMarker", NSNoSelectionMarker = m;
    m = [[ABindingMarker alloc] init], m->_name = "NSNotApplicableMarker", NSNotApplicableMarker = m;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)description { return [NSString stringWithFormat:@"<%s>", _name]; }
/* a key path through a marker stays the marker */
- (id)valueForKey:(NSString *)key { return self; }
- (id)valueForKeyPath:(NSString *)keyPath { return self; }
@end

BOOL NSIsControllerMarker(id object)
{
    return object && (object == NSMultipleValuesMarker || object == NSNoSelectionMarker ||
                      object == NSNotApplicableMarker);
}

/* ---- one binding ---- */

@interface ABinding : NSObject {
@public
    id view;                 /* not retained: it owns us */
    NSString *name;
    id observed;             /* retained, as the binding's info holds it */
    NSString *keyPath;
    NSDictionary *options;
    NSDictionary *info;
    BOOL observing, pushing, placeholderShown;
    BOOL watchingEditable;        /* observing the controller's "editable" (Ferry 0.20.0) */
    BOOL condDisabled;            /* the view disabled as its value can't be edited */
    BOOL condUneditable, savedEditable;   /* a text field made not editable, and what it was */
    NSString *savedPlaceholder;   /* a text field's own, while a binding's shows */
}
- (void)stop;
@end

static char bindings_key;

static NSMutableDictionary *bindings_of(id view, BOOL create)
{
    NSMutableDictionary *all = objc_getAssociatedObject(view, &bindings_key);
    if (!all && create) {
        all = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(view, &bindings_key, all, OBJC_ASSOCIATION_RETAIN);
    }
    return all;
}

static id option(ABinding *b, NSString *key)
{
    id v = [b->options objectForKey:key];
    return v == [NSNull null] ? nil : v;
}

static NSValueTransformer *transformer_of(ABinding *b)
{
    id t = option(b, NSValueTransformerBindingOption);
    if ([t isKindOfClass:[NSValueTransformer class]])
        return t;
    NSString *n = option(b, NSValueTransformerNameBindingOption);
    return [n isKindOfClass:[NSString class]] && [n length] ? [NSValueTransformer valueTransformerForName:n] : nil;
}

/* "enabled2" is an enabled binding, "hidden3" a hidden one. */
static NSString *base_name(NSString *name)
{
    NSUInteger n = [name length];
    while (n > 1 && [name characterAtIndex:n - 1] >= '0' && [name characterAtIndex:n - 1] <= '9')
        n--;
    return n == [name length] ? name : [name substringToIndex:n];
}

/* The key path's value; the not-applicable marker for a key the object
 * doesn't have (unless the binding asks for the exception, which is raised
 * too for a key a controller's selection answers it for). */
static id model_value(ABinding *b)
{
    id v;
    @try {
        v = [b->observed valueForKeyPath:b->keyPath];
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException] ||
            [option(b, NSRaisesForNotApplicableKeysBindingOption) boolValue])
            @throw;
        return NSNotApplicableMarker;
    }
    if (v == NSNotApplicableMarker && [option(b, NSRaisesForNotApplicableKeysBindingOption) boolValue])
        [NSException raise:NSUndefinedKeyException
                    format:@"[<%@ %p> valueForUndefinedKey:]: the selection is not key value coding-compliant "
                           @"for the key path %@ (the %@ binding of a %@).",
                           [b->observed class], b->observed, b->keyPath, b->name, [b->view class]];
    return v;
}

static BOOL is_text_value(ABinding *b)
{
    return [b->view isKindOfClass:[NSTextField class]] && [b->name isEqualToString:NSValueBinding];
}

/* What the view is given for the key path's value v. *keep: leave the view
 * as it is; *placeholder: a text field shows this greyed instead. */
static id shown_value(ABinding *b, id v, BOOL *keep, NSString **placeholder)
{
    *keep = NO;
    *placeholder = nil;
    if (NSIsControllerMarker(v)) {
        NSString *key = v == NSNoSelectionMarker        ? NSNoSelectionPlaceholderBindingOption
                        : v == NSMultipleValuesMarker ? NSMultipleValuesPlaceholderBindingOption
                                                      : NSNotApplicablePlaceholderBindingOption;
        id p = option(b, key);
        if (!p && v == NSNotApplicableMarker) {
            /* left out, Ferry keeps the view as it is; NO (YES has raised) shows the placeholder */
            if (!option(b, NSRaisesForNotApplicableKeysBindingOption)) {
                *keep = YES;
                return nil;
            }
            if (is_text_value(b))
                *placeholder = @"Not Applicable";
            return nil;
        }
        if (is_text_value(b)) {
            *placeholder = p ?: (v == NSNoSelectionMarker ? @"No Selection" : @"Multiple Values");
            return nil;
        }
        return p;
    }
    NSValueTransformer *t = transformer_of(b);
    if (t)
        v = [t transformedValue:v];
    if (v == [NSNull null])
        v = nil;
    if (!v) {
        id p = option(b, NSNullPlaceholderBindingOption);
        if (p && is_text_value(b))
            *placeholder = [p description];
        else
            v = p;
    }
    return v;
}

static BOOL truth(id v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : v != nil; }

/* The bindings that set a view's value and write it back. */
static BOOL writable(NSString *name)
{
    return [name isEqualToString:NSValueBinding] || [name isEqualToString:NSSelectedIndexBinding] ||
           [name isEqualToString:NSSelectedObjectBinding] || [name isEqualToString:NSSelectedValueBinding] ||
           [name isEqualToString:NSSelectedTagBinding] || [name isEqualToString:NSAttributedStringBinding];
}

/* Whether a value binding of the view now disables it (Ferry 0.20.0). */
static BOOL any_condition_disables(id view)
{
    NSDictionary *all = bindings_of(view, NO);
    for (NSString *name in all)
        if (((ABinding *)[all objectForKey:name])->condDisabled)
            return YES;
    return NO;
}
static BOOL has_bound(id view, NSString *base)
{
    NSDictionary *all = bindings_of(view, NO);
    for (NSString *name in all)
        if ([base_name(name) isEqualToString:base] && ((ABinding *)[all objectForKey:name])->observed)
            return YES;
    return NO;
}

/* enabled, enabled2, ... together: all must be true (and no value binding
 * disabling the view). hidden ones: any. */
static void apply_combined(id view, NSString *base)
{
    BOOL hidden = [base isEqualToString:NSHiddenBinding], result = !hidden;
    NSDictionary *all = bindings_of(view, NO);
    for (NSString *name in all) {
        ABinding *b = [all objectForKey:name];
        if (![base_name(name) isEqualToString:base] || !b->observed)
            continue;
        BOOL keep;
        NSString *placeholder;
        id v = shown_value(b, model_value(b), &keep, &placeholder);
        if (keep)
            continue;
        if (hidden)
            result = result || truth(v);
        else
            result = result && truth(v);
    }
    if (!hidden && any_condition_disables(view))
        result = NO;
    if (hidden && [view respondsToSelector:@selector(setHidden:)])
        [(NSView *)view setHidden:result];
    else if (!hidden && [view respondsToSelector:@selector(setEnabled:)])
        [(NSControl *)view setEnabled:result];
}

/* ---- conditionally enabled and editable (Ferry 0.20.0) ---- */

static char saved_enabled_key;

static BOOL condition_option(ABinding *b, NSString *key, BOOL fallback)
{
    id o = option(b, key);
    return o ? [o boolValue] : fallback;
}

/* Whether the bound value can be edited: there is a selection, multiple
 * values may be edited, the key applies (when not-applicable keys don't
 * raise), and the value's controller is editable. */
static BOOL value_can_be_edited(ABinding *b, id raw)
{
    if (raw == NSNoSelectionMarker)
        return NO;
    if (raw == NSMultipleValuesMarker && !condition_option(b, NSAllowsEditingMultipleValuesSelectionBindingOption, YES))
        return NO;
    if (raw == NSNotApplicableMarker && option(b, NSRaisesForNotApplicableKeysBindingOption))
        return NO;
    if ([b->observed isKindOfClass:[NSController class]] && [b->observed respondsToSelector:@selector(isEditable)] &&
        ![b->observed isEditable])
        return NO;
    return YES;
}

/* The view's enabled state after a value binding started or stopped
 * disabling it: its enabled bindings decide, or else what it was before. */
static void conditions_changed(id view, BOOL wasDisabled)
{
    BOOL now = any_condition_disables(view);
    if (has_bound(view, NSEnabledBinding)) {
        apply_combined(view, NSEnabledBinding);
        return;
    }
    if (now && !wasDisabled) {
        objc_setAssociatedObject(view, &saved_enabled_key, @([(NSControl *)view isEnabled]), OBJC_ASSOCIATION_RETAIN);
        [(NSControl *)view setEnabled:NO];
    } else if (!now && wasDisabled) {
        NSNumber *saved = objc_getAssociatedObject(view, &saved_enabled_key);
        [(NSControl *)view setEnabled:saved ? [saved boolValue] : YES];
        objc_setAssociatedObject(view, &saved_enabled_key, nil, OBJC_ASSOCIATION_RETAIN);
    }
}

static BOOL conditions_apply(ABinding *b)
{
    return writable(b->name) && ![b->view isKindOfClass:[NSTableColumn class]] &&
           [b->view respondsToSelector:@selector(setEnabled:)] && [b->view respondsToSelector:@selector(isEnabled)];
}

static void set_conditions(ABinding *b, id raw)
{
    if (!conditions_apply(b))
        return;
    id view = b->view;
    BOOL ok = value_can_be_edited(b, raw);
    if ([view isKindOfClass:[NSTextField class]] && condition_option(b, NSConditionallySetsEditableBindingOption, YES)) {
        NSTextField *f = view;
        if (!ok && !b->condUneditable) {
            b->savedEditable = [f isEditable];
            b->condUneditable = YES;
            [f setEditable:NO];
        } else if (ok && b->condUneditable) {
            b->condUneditable = NO;
            [f setEditable:b->savedEditable];
        }
    }
    BOOL enabling = condition_option(b, NSConditionallySetsEnabledBindingOption, ![view isKindOfClass:[NSTextField class]]);
    BOOL disable = enabling && !ok;
    if (disable != b->condDisabled) {
        BOOL was = any_condition_disables(view);
        b->condDisabled = disable;
        conditions_changed(view, was);
    }
}

/* A binding going away gives the view back what it took. */
static void release_conditions(ABinding *b)
{
    if (b->condUneditable) {
        b->condUneditable = NO;
        [(NSTextField *)b->view setEditable:b->savedEditable];
    }
    if (b->condDisabled) {
        b->condDisabled = NO;
        conditions_changed(b->view, YES);
    }
}

static BOOL is_column_value(ABinding *b)
{
    return [b->view isKindOfClass:[NSTableColumn class]] && [b->name isEqualToString:NSValueBinding];
}
/* A column's value, editable and enabled bindings give a value for each
 * row (Ferry 0.19.0 for the last two). */
static BOOL is_column_rows(ABinding *b)
{
    if (![b->view isKindOfClass:[NSTableColumn class]])
        return NO;
    NSString *base = base_name(b->name);
    return [b->name isEqualToString:NSValueBinding] || [base isEqualToString:NSEditableBinding] ||
           [base isEqualToString:NSEnabledBinding];
}

static void apply(ABinding *b)
{
    if (!b->observed)
        return;
    if (is_column_rows(b)) {
        /* a value for each row: the table reads them as it draws */
        [[(NSTableColumn *)b->view tableView] _ferryBoundRowsChanged];
        return;
    }
    NSString *base = base_name(b->name);
    if ([base isEqualToString:NSEnabledBinding] || [base isEqualToString:NSHiddenBinding]) {
        apply_combined(b->view, base);
        return;
    }
    BOOL keep;
    NSString *placeholder;
    id raw = model_value(b);
    id v = shown_value(b, raw, &keep, &placeholder);
    if (!keep) {
        if (is_text_value(b)) {
            NSTextField *f = b->view;
            if (placeholder) {
                if (!b->placeholderShown) {
                    b->savedPlaceholder = [[f placeholderString] copy];
                    b->placeholderShown = YES;
                }
                [f setPlaceholderString:placeholder];
            } else if (b->placeholderShown) {
                [f setPlaceholderString:b->savedPlaceholder];
                [b->savedPlaceholder release];
                b->savedPlaceholder = nil;
                b->placeholderShown = NO;
            }
        }
        [b->view _ferrySetValue:v forBinding:b->name];
    }
    set_conditions(b, raw);
}

/* An error presented for a view: up the responder chain from it (a
 * table's column from its table), else by the application. */
static void present_error(id view, NSError *error)
{
    if ([view isKindOfClass:[NSTableColumn class]])
        view = [(NSTableColumn *)view tableView];
    if ([view respondsToSelector:@selector(presentError:)])
        [view presentError:error];
    else
        [NSApp presentError:error];
}

/* With NSValidatesImmediately, *v validated for the key path on observed
 * (it may be changed); NO when it is refused, the error presented unless
 * quiet. A key path validation can't follow counts as valid. */
static BOOL validated(id view, NSDictionary *options, id observed, NSString *keyPath, id *v, BOOL quiet)
{
    id o = [options objectForKey:NSValidatesImmediatelyBindingOption];
    if (o == [NSNull null] || ![o boolValue])
        return YES;
    id checked = *v;
    NSError *error = nil;
    BOOL ok;
    @try {
        ok = [observed validateValue:&checked forKeyPath:keyPath error:&error];
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException])
            @throw;
        ok = YES;
    }
    if (!ok) {
        if (!quiet && error)
            present_error(view, error);
        return NO;
    }
    *v = checked;
    return YES;
}

/* Writes what the view now shows back to the key path; continuous: as it
 * is typed, with the editing going on. */
static void push(ABinding *b, BOOL continuous)
{
    id v = [b->view _ferryValueForBinding:b->name];
    if (is_text_value(b) && option(b, NSNullPlaceholderBindingOption) && [v isKindOfClass:[NSString class]] &&
        ![v length])
        v = nil;   /* an emptied field stands for nil, as its placeholder shows */
    NSValueTransformer *t = transformer_of(b);
    if (t) {
        if (![[t class] allowsReverseTransformation])
            return;
        v = [t reverseTransformedValue:v];
    }
    id now = model_value(b);
    if (now == NSNotApplicableMarker || now == v || [now isEqual:v])
        return;
    id typed = v;
    if (!validated(b->view, b->options, b->observed, b->keyPath, &v, continuous)) {
        /* refused: not written, and the view shows the model's value again */
        if (!continuous)
            apply(b);
        return;
    }
    BOOL changed = !(typed == v || [typed isEqual:v]);
    if (!(now == v || [now isEqual:v])) {
        b->pushing = YES;
        @try {
            [b->observed setValue:v forKeyPath:b->keyPath];
        } @finally {
            b->pushing = NO;
        }
    }
    /* shown again as the model now has it (a placeholder for nil, or a
     * value the validation changed), unless the text is still being typed */
    if ((changed && !continuous) || ![b->view isKindOfClass:[NSTextField class]] ||
        ![(NSTextField *)b->view _isEditing])
        apply(b);
}

void ABindingsPush(id view, BOOL continuousOnly)
{
    NSDictionary *all = bindings_of(view, NO);
    if (![all count])
        return;
    [[view retain] autorelease];
    for (NSString *name in [[all allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        ABinding *b = [all objectForKey:name];
        if (!b || !b->observed || !writable(name))
            continue;
        if (continuousOnly && ![option(b, NSContinuouslyUpdatesValueBindingOption) boolValue])
            continue;
        push(b, continuousOnly);
    }
}

/* ---- one binding, by name ---- */

static ABinding *binding_named(id view, NSString *name)
{
    ABinding *b = [bindings_of(view, NO) objectForKey:name];
    return b && b->observed ? b : nil;
}

BOOL ABindingIsBound(id view, NSString *name) { return binding_named(view, name) != nil; }

id ABindingModelValue(id view, NSString *name, BOOL *bound)
{
    ABinding *b = binding_named(view, name);
    if (bound)
        *bound = b != nil;
    if (!b)
        return nil;
    BOOL keep;
    NSString *placeholder;
    id v = shown_value(b, model_value(b), &keep, &placeholder);
    return keep ? nil : v;
}

void ABindingPush(id view, NSString *name)
{
    ABinding *b = binding_named(view, name);
    if (b && !b->pushing) {
        [[b retain] autorelease];
        push(b, NO);
    }
}

void ABindingRefresh(id view, NSString *name)
{
    ABinding *b = binding_named(view, name);
    if (b)
        apply(b);
}

/* "arrangedObjects.name": the rows are arrangedObjects, the cell is name. */
static NSArray *column_rows(ABinding *b, NSString **rest)
{
    NSRange dot = [b->keyPath rangeOfString:@"."];
    *rest = dot.location == NSNotFound ? nil : [b->keyPath substringFromIndex:dot.location + 1];
    id rows;
    @try {
        rows = [b->observed valueForKeyPath:dot.location == NSNotFound ? b->keyPath
                                                                       : [b->keyPath substringToIndex:dot.location]];
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException])
            @throw;
        return nil;
    }
    if ([rows isKindOfClass:[NSSet class]])
        rows = [rows allObjects];
    return [rows isKindOfClass:[NSArray class]] ? rows : nil;
}

/* The object a column binding reads in a row: in an outline view, the
 * row's item (a tree controller's node stands for its represented
 * object); in a table, that row of the bound rows. *rest is the key path
 * read on it. */
static id row_object(ABinding *b, NSInteger row, NSString **rest, BOOL *found)
{
    *found = NO;
    NSTableView *tv = [(NSTableColumn *)b->view tableView];
    if ([tv isKindOfClass:[NSOutlineView class]]) {
        NSRange dot = [b->keyPath rangeOfString:@"."];
        *rest = dot.location == NSNotFound ? nil : [b->keyPath substringFromIndex:dot.location + 1];
        if (row < 0 || row >= [tv numberOfRows])
            return nil;
        id item = [(NSOutlineView *)tv itemAtRow:row];
        *found = item != nil;
        return [item isKindOfClass:[NSTreeNode class]] ? [item representedObject] : item;
    }
    NSArray *rows = column_rows(b, rest);
    if (row < 0 || (NSUInteger)row >= [rows count])
        return nil;
    *found = YES;
    return [rows objectAtIndex:(NSUInteger)row];
}

/* The value at the rest of b's key path on obj (transformed), and whether
 * it was there. */
static id row_value(ABinding *b, id obj, NSString *rest, BOOL *ok)
{
    id v = obj;
    *ok = YES;
    if (rest) {
        @try {
            v = [obj valueForKeyPath:rest];
        } @catch (NSException *e) {
            if (![[e name] isEqualToString:NSUndefinedKeyException] ||
                [option(b, NSRaisesForNotApplicableKeysBindingOption) boolValue])
                @throw;
            *ok = NO;
            return nil;
        }
    }
    NSValueTransformer *t = transformer_of(b);
    if (t)
        v = [t transformedValue:v];
    return v == [NSNull null] ? nil : v;
}

id ABindingCellValue(NSTableColumn *column, NSInteger row, BOOL *bound)
{
    ABinding *b = binding_named(column, NSValueBinding);
    if (bound)
        *bound = b != nil;
    if (!b || row < 0)
        return nil;
    NSString *rest;
    BOOL found, ok;
    id obj = row_object(b, row, &rest, &found);
    if (!found)
        return nil;
    id v = row_value(b, obj, rest, &ok);
    if (!ok)
        return nil;
    return v ?: option(b, NSNullPlaceholderBindingOption);
}

/* Each of the column's bindings named so (enabled, enabled2...) true for
 * the row's object: YES when none is bound. */
BOOL ABindingCellAllows(NSTableColumn *column, NSString *name, NSInteger row)
{
    NSDictionary *all = bindings_of(column, NO);
    for (NSString *n in all) {
        ABinding *b = [all objectForKey:n];
        if (![base_name(n) isEqualToString:name] || !b->observed)
            continue;
        NSString *rest;
        BOOL found, ok;
        id obj = row_object(b, row, &rest, &found);
        if (!found)
            continue;
        id v = row_value(b, obj, rest, &ok);
        if (ok && !truth(v))
            return NO;
    }
    return YES;
}

BOOL ABindingCellHas(NSTableColumn *column, NSString *name)
{
    NSDictionary *all = bindings_of(column, NO);
    for (NSString *n in all)
        if ([base_name(n) isEqualToString:name] && ((ABinding *)[all objectForKey:n])->observed)
            return YES;
    return NO;
}

/* Whether the row's cell may be edited through the column's bindings: its
 * value's controller is editable (unless NSConditionallySetsEditable is
 * NO), and its editable and enabled bindings are true for the row. */
BOOL ABindingCellEditable(NSTableColumn *column, NSInteger row)
{
    ABinding *b = binding_named(column, NSValueBinding);
    if (b) {
        id conditional = option(b, NSConditionallySetsEditableBindingOption);
        if ((!conditional || [conditional boolValue]) && [b->observed respondsToSelector:@selector(isEditable)] &&
            ![b->observed isEditable])
            return NO;
    }
    return ABindingCellAllows(column, NSEditableBinding, row) && ABindingCellAllows(column, NSEnabledBinding, row);
}

BOOL ABindingSetCellValue(NSTableColumn *column, NSInteger row, id value)
{
    ABinding *b = binding_named(column, NSValueBinding);
    if (!b || row < 0)
        return NO;
    if (!ABindingCellEditable(column, row))
        return NO;   /* the controller (or the row) doesn't take edits */
    NSString *rest;
    BOOL found;
    id obj = row_object(b, row, &rest, &found);
    if (!rest || !found || !obj)
        return NO;
    NSValueTransformer *t = transformer_of(b);
    if (t) {
        if (![[t class] allowsReverseTransformation])
            return NO;
        value = [t reverseTransformedValue:value];
    }
    id now = [obj valueForKeyPath:rest];
    if (now == value || [now isEqual:value])
        return YES;
    /* validated first, with NSValidatesImmediately (Ferry 0.20.0) */
    if (!validated(column, b->options, obj, rest, &value, NO))
        return NO;
    if (now == value || [now isEqual:value])
        return YES;
    [obj setValue:value forKeyPath:rest];
    return YES;
}

void ABindingColumnJoinedTable(NSTableColumn *column)
{
    ABinding *b = binding_named(column, NSValueBinding);
    NSTableView *table = [column tableView];
    if (!b || !table)
        return;
    NSRange dot = [b->keyPath rangeOfString:@"."];
    if (dot.location == NSNotFound)
        return;
    id controller = b->observed;
    if (!binding_named(table, NSContentBinding))
        [table bind:NSContentBinding toObject:controller withKeyPath:[b->keyPath substringToIndex:dot.location]
            options:nil];
    if ([table isKindOfClass:[NSOutlineView class]] && [controller respondsToSelector:@selector(selectionIndexPaths)]) {
        if (!binding_named(table, NSSelectionIndexPathsBinding))
            [table bind:NSSelectionIndexPathsBinding toObject:controller withKeyPath:@"selectionIndexPaths" options:nil];
    } else if ([controller respondsToSelector:@selector(selectionIndexes)] &&
               !binding_named(table, NSSelectionIndexesBinding)) {
        [table bind:NSSelectionIndexesBinding toObject:controller withKeyPath:@"selectionIndexes" options:nil];
    }
    if ([controller respondsToSelector:@selector(sortDescriptors)] && !binding_named(table, NSSortDescriptorsBinding))
        [table bind:NSSortDescriptorsBinding toObject:controller withKeyPath:@"sortDescriptors" options:nil];
}

BOOL ABindingsWantContinuous(id view)
{
    NSDictionary *all = bindings_of(view, NO);
    for (NSString *name in all)
        if ([option([all objectForKey:name], NSContinuouslyUpdatesValueBindingOption) boolValue])
            return YES;
    return NO;
}

static char editable_context;

@implementation ABinding
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    if (context == &editable_context) {
        /* the controller became editable or not: the conditions again */
        [[self retain] autorelease];
        apply(self);
        return;
    }
    if (pushing)
        return;   /* the view already shows it */
    [[self retain] autorelease];
    apply(self);
    /* a pop-up's items changed: its choice is set again from its bindings */
    if ([view isKindOfClass:[NSPopUpButton class]] &&
        ([name isEqualToString:NSContentBinding] || [name isEqualToString:NSContentObjectsBinding] ||
         [name isEqualToString:NSContentValuesBinding])) {
        NSDictionary *all = bindings_of(view, NO);
        for (NSString *n in @[ NSSelectedIndexBinding, NSSelectedObjectBinding, NSSelectedValueBinding,
                               NSSelectedTagBinding ])
            if ([all objectForKey:n])
                apply([all objectForKey:n]);
    }
}
- (void)stop
{
    if (observing)
        [observed removeObserver:self forKeyPath:keyPath];
    observing = NO;
    if (watchingEditable)
        [observed removeObserver:self forKeyPath:@"editable" context:&editable_context];
    watchingEditable = NO;
    if (view)
        release_conditions(self);
    if (placeholderShown && [view isKindOfClass:[NSTextField class]])
        [(NSTextField *)view setPlaceholderString:savedPlaceholder];
    placeholderShown = NO;
}
- (void)dealloc
{
    condDisabled = condUneditable = NO;   /* the view is going too */
    [self stop];
    [name release];
    [observed release];
    [keyPath release];
    [options release];
    [info release];
    [savedPlaceholder release];
    [super dealloc];
}
@end

/* ---- what each kind of view binds ---- */

static NSMutableDictionary *exposed; /* class name -> bindings */

static void expose(NSString *cls, NSArray *names)
{
    NSMutableArray *list = [exposed objectForKey:cls];
    if (!list) {
        list = [NSMutableArray array];
        [exposed setObject:list forKey:cls];
    }
    for (NSString *n in names)
        if (![list containsObject:n])
            [list addObject:n];
}

/* The bindings Apple's Cocoa Bindings Reference lists for Ferry's views
 * and controllers. */
static void expose_defaults(void)
{
    if (exposed)
        return;
    exposed = [[NSMutableDictionary alloc] init];
    expose(@"NSView", @[ NSHiddenBinding, NSToolTipBinding ]);
    expose(@"NSControl", @[ NSEnabledBinding ]);
    expose(@"NSTextField", @[ NSValueBinding, NSEditableBinding, NSTextColorBinding, NSFontBinding ]);
    expose(@"NSButton", @[ NSValueBinding, NSTitleBinding, NSAlternateTitleBinding, NSImageBinding ]);
    expose(@"NSPopUpButton", @[ NSContentBinding, NSContentObjectsBinding, NSContentValuesBinding,
                                NSSelectedIndexBinding, NSSelectedObjectBinding, NSSelectedTagBinding,
                                NSSelectedValueBinding ]);
    expose(@"NSSlider", @[ NSValueBinding, NSMinValueBinding, NSMaxValueBinding ]);
    expose(@"NSObjectController", @[ NSContentObjectBinding, NSEditableBinding ]);
    expose(@"NSArrayController", @[ NSContentBinding, NSContentArrayBinding, NSContentSetBinding,
                                    NSSelectionIndexesBinding, NSSortDescriptorsBinding, NSFilterPredicateBinding ]);
    expose(@"NSTreeController", @[ NSContentBinding, NSContentArrayBinding, NSContentObjectBinding,
                                   NSContentSetBinding, NSSelectionIndexPathsBinding, NSSortDescriptorsBinding ]);
    expose(@"NSDictionaryController", @[ NSContentDictionaryBinding, NSIncludedKeysBinding, NSExcludedKeysBinding,
                                         NSInitialKeyBinding, NSInitialValueBinding,
                                         NSLocalizedKeyDictionaryBinding ]);
    expose(@"NSTableView", @[ NSContentBinding, NSSelectionIndexesBinding, NSSortDescriptorsBinding ]);
    expose(@"NSOutlineView", @[ NSSelectionIndexPathsBinding ]);
    expose(@"NSTableColumn", @[ NSValueBinding, NSEditableBinding, NSEnabledBinding, NSHiddenBinding,
                                NSHeaderTitleBinding, NSMaxWidthBinding, NSMinWidthBinding, NSWidthBinding ]);
}

@implementation NSObject (NSKeyValueBindingCreation)
+ (void)exposeBinding:(NSString *)binding
{
    if (!binding)
        return;
    expose_defaults();
    expose(NSStringFromClass(self), @[ binding ]);
}
- (NSArray *)exposedBindings
{
    expose_defaults();
    NSMutableArray *all = [NSMutableArray array];
    for (Class c = [self class]; c; c = class_getSuperclass(c))
        for (NSString *b in [exposed objectForKey:NSStringFromClass(c)])
            if (![all containsObject:b])
                [all addObject:b];
    return all;
}
- (Class)valueClassForBinding:(NSString *)binding { return Nil; }

- (void)bind:(NSString *)binding toObject:(id)observable withKeyPath:(NSString *)keyPath
     options:(NSDictionary *)options
{
    if (!binding || !keyPath)
        return;
    [self unbind:binding];
    ABinding *b = [[[ABinding alloc] init] autorelease];
    b->view = self;
    b->name = [binding copy];
    b->observed = [observable retain];
    b->keyPath = [keyPath copy];
    b->options = [(options ?: [NSDictionary dictionary]) copy];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (observable)
        [info setObject:observable forKey:NSObservedObjectKey];
    [info setObject:keyPath forKey:NSObservedKeyPathKey];
    [info setObject:b->options forKey:NSOptionsKey];
    b->info = [info copy];
    [bindings_of(self, YES) setObject:b forKey:binding];
    if (!observable)
        return;
    @try {
        [observable addObserver:b forKeyPath:keyPath options:0 context:NULL];
        b->observing = YES;
    } @catch (NSException *e) {
        if (![[e name] isEqualToString:NSUndefinedKeyException] ||
            [option(b, NSRaisesForNotApplicableKeysBindingOption) boolValue])
            @throw;
    }
    /* a value bound through a controller follows its editable state */
    if (conditions_apply(b) && [observable isKindOfClass:[NSController class]] &&
        [observable respondsToSelector:@selector(isEditable)]) {
        [observable addObserver:b forKeyPath:@"editable" options:0 context:&editable_context];
        b->watchingEditable = YES;
    }
    if (is_column_value(b)) {
        /* sorting by the column's key, unless asked not to */
        NSRange dot = [keyPath rangeOfString:@"."];
        id creates = option(b, NSCreatesSortDescriptorBindingOption);
        if (dot.location != NSNotFound && ![(NSTableColumn *)self sortDescriptorPrototype] &&
            (!creates || [creates boolValue]))
            [(NSTableColumn *)self
                setSortDescriptorPrototype:[NSSortDescriptor sortDescriptorWithKey:[keyPath substringFromIndex:dot.location + 1]
                                                                         ascending:YES
                                                                          selector:@selector(compare:)]];
        ABindingColumnJoinedTable((NSTableColumn *)self);
    }
    apply(b);
}
- (void)unbind:(NSString *)binding
{
    NSMutableDictionary *all = bindings_of(self, NO);
    ABinding *b = [all objectForKey:binding];
    if (!b)
        return;
    [b stop];
    [all removeObjectForKey:binding];
}
- (NSDictionary *)infoForBinding:(NSString *)binding
{
    ABinding *b = [bindings_of(self, NO) objectForKey:binding];
    return b ? b->info : nil;
}
- (NSArray *)optionDescriptionsForBinding:(NSString *)binding { return [NSArray array]; }
@end

/* How a binding sets and reads the view's property: its value is the
 * objectValue of a control, anything else the property of that name. */
@implementation NSObject (FerryBindings)
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding] && [self respondsToSelector:@selector(setObjectValue:)]) {
        [(NSControl *)self setObjectValue:value];
        return;
    }
    NSString *key = base_name(binding);
    NSString *setter = [NSString stringWithFormat:@"set%@%@:", [[key substringToIndex:1] uppercaseString],
                                                  [key substringFromIndex:1]];
    if (![self respondsToSelector:NSSelectorFromString(setter)])
        return;
    @try {
        [self setValue:value forKey:key];
    } @catch (NSException *e) {
        /* nil for a number, say: the property is left as it is */
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding] && [self respondsToSelector:@selector(objectValue)])
        return [(NSControl *)self objectValue];
    @try {
        return [self valueForKey:base_name(binding)];
    } @catch (NSException *e) {
        return nil;
    }
}
@end

/* A button cell's value is its state, as a button's is (a check box in a
 * matrix, say, 1.229): its string value is its title. */
@implementation NSButtonCell (FerryBindings)
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding])
        [self setState:[value respondsToSelector:@selector(integerValue)] ? [value integerValue] : NSControlStateValueOff];
    else
        [super _ferrySetValue:value forBinding:binding];
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSValueBinding])
        return @([self state]);
    return [super _ferryValueForBinding:binding];
}
@end

/* A pop-up's items come from its content bindings; its choice from the
 * selection ones. */
@implementation NSPopUpButton (FerryBindings)
- (id)_ferryBoundValue:(NSString *)binding
{
    ABinding *b = [bindings_of(self, NO) objectForKey:binding];
    if (!b || !b->observed)
        return nil;
    BOOL keep;
    NSString *placeholder;
    id v = shown_value(b, model_value(b), &keep, &placeholder);
    if ([v isKindOfClass:[NSSet class]])
        v = [v allObjects];
    return [v isKindOfClass:[NSArray class]] ? v : nil;
}
- (void)_ferryRebuildItems
{
    NSArray *content = [self _ferryBoundValue:NSContentBinding];
    NSArray *objects = [self _ferryBoundValue:NSContentObjectsBinding] ?: content;
    NSArray *titles = [self _ferryBoundValue:NSContentValuesBinding];
    NSUInteger n = MAX([objects count], [titles count]);
    if (!titles && !objects)
        return;
    [self removeAllItems];
    NSMenu *menu = [self menu];
    for (NSUInteger i = 0; i < n; i++) {
        id obj = i < [objects count] ? [objects objectAtIndex:i] : nil;
        id title = i < [titles count] ? [titles objectAtIndex:i] : obj;
        NSString *s = title == [NSNull null] || !title ? @"" : [title description];
        NSMenuItem *item = [menu addItemWithTitle:s action:NULL keyEquivalent:@""];
        [item setRepresentedObject:obj == [NSNull null] ? nil : obj];
    }
    if ([self numberOfItems])
        [self selectItemAtIndex:0];
}
- (void)_ferrySelectIndex:(NSInteger)i
{
    if (i >= 0 && i < [self numberOfItems])
        [self selectItemAtIndex:i];
    else
        [self selectItem:nil];
}
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSContentBinding] || [binding isEqualToString:NSContentObjectsBinding] ||
        [binding isEqualToString:NSContentValuesBinding]) {
        [self _ferryRebuildItems];
    } else if ([binding isEqualToString:NSSelectedIndexBinding]) {
        [self _ferrySelectIndex:value ? [value integerValue] : -1];
    } else if ([binding isEqualToString:NSSelectedObjectBinding]) {
        NSInteger found = -1;
        for (NSInteger i = 0; i < [self numberOfItems] && value; i++) {
            id obj = [[self itemAtIndex:i] representedObject];
            if (obj == value || [obj isEqual:value]) {
                found = i;
                break;
            }
        }
        [self _ferrySelectIndex:found];
    } else if ([binding isEqualToString:NSSelectedValueBinding]) {
        [self _ferrySelectIndex:value ? [self indexOfItemWithTitle:[value description]] : -1];
    } else if ([binding isEqualToString:NSSelectedTagBinding]) {
        [self _ferrySelectIndex:value ? [self indexOfItemWithTag:[value integerValue]] : -1];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
    [self setNeedsDisplay:YES];
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSSelectedIndexBinding])
        return @([self indexOfSelectedItem]);
    if ([binding isEqualToString:NSSelectedObjectBinding])
        return [[self selectedItem] representedObject];
    if ([binding isEqualToString:NSSelectedValueBinding])
        return [self selectedItem] ? [self titleOfSelectedItem] : nil;
    if ([binding isEqualToString:NSSelectedTagBinding])
        return [self selectedItem] ? @([self selectedTag]) : nil;
    return [super _ferryValueForBinding:binding];
}
@end
