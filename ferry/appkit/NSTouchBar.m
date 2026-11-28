/* SPDX-License-Identifier: GPL-3.0-or-later
 * The Touch Bar's classes (freemac 1.223, Ferry 0.47.0), written from
 * Apple's public NSTouchBar documentation. A PC has no Touch Bar, so a bar
 * is never shown: it keeps its identifiers and items, makes an item through
 * its template items or its delegate when asked for one, and answers
 * visible NO, as a Mac without a Touch Bar does. */
#import "AInternal.h"
#include <objc/runtime.h>

NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFixedSpaceSmall = @"NSTouchBarItemIdentifierFixedSpaceSmall";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFixedSpaceLarge = @"NSTouchBarItemIdentifierFixedSpaceLarge";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFlexibleSpace = @"NSTouchBarItemIdentifierFlexibleSpace";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierOtherItemsProxy = @"NSTouchBarItemIdentifierOtherItemsProxy";
/* the standard items' identifiers (freemac 1.NEXT; MacVim puts the emoji
 * and symbol picker in its bar) */
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierCharacterPicker = @"NSTouchBarItemIdentifierCharacterPicker";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierCandidateList = @"NSTouchBarItemIdentifierCandidateList";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierTextFormat = @"NSTouchBarItemIdentifierTextFormat";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierTextAlignment = @"NSTouchBarItemIdentifierTextAlignment";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierTextColorPicker = @"NSTouchBarItemIdentifierTextColorPicker";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierTextList = @"NSTouchBarItemIdentifierTextList";
NSTouchBarItemIdentifier const NSTouchBarItemIdentifierTextStyle = @"NSTouchBarItemIdentifierTextStyle";

static BOOL customize_item_enabled;

@implementation NSTouchBar {
    NSString *_customization, *_principal, *_escape;
    NSArray *_allowed, *_required, *_defaults;
    NSSet *_templates;
    NSMutableDictionary *_made;
    id _delegate;
}
+ (BOOL)isAutomaticCustomizeTouchBarMenuItemEnabled { return customize_item_enabled; }
+ (void)setAutomaticCustomizeTouchBarMenuItemEnabled:(BOOL)enabled { customize_item_enabled = enabled; }
- (instancetype)init
{
    if ((self = [super init])) {
        _made = [[NSMutableDictionary alloc] init];
        _allowed = [@[] retain];
        _required = [@[] retain];
        _defaults = [@[] retain];
        _templates = [[NSSet set] retain];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)dealloc
{
    [_customization release];
    [_principal release];
    [_escape release];
    [_allowed release];
    [_required release];
    [_defaults release];
    [_templates release];
    [_made release];
    [super dealloc];
}
#define COPY_PROPERTY(type, get, set, ivar)                                                                         \
    -(type)get { return ivar; }                                                                                     \
    -(void)set:(type)value                                                                                          \
    {                                                                                                               \
        type old = ivar;                                                                                            \
        ivar = [value copy];                                                                                        \
        [old release];                                                                                              \
    }
COPY_PROPERTY(NSString *, customizationIdentifier, setCustomizationIdentifier, _customization)
COPY_PROPERTY(NSString *, principalItemIdentifier, setPrincipalItemIdentifier, _principal)
COPY_PROPERTY(NSString *, escapeKeyReplacementItemIdentifier, setEscapeKeyReplacementItemIdentifier, _escape)
COPY_PROPERTY(NSArray *, customizationAllowedItemIdentifiers, setCustomizationAllowedItemIdentifiers, _allowed)
COPY_PROPERTY(NSArray *, customizationRequiredItemIdentifiers, setCustomizationRequiredItemIdentifiers, _required)
COPY_PROPERTY(NSArray *, defaultItemIdentifiers, setDefaultItemIdentifiers, _defaults)
COPY_PROPERTY(NSSet *, templateItems, setTemplateItems, _templates)
- (id<NSTouchBarDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSTouchBarDelegate>)delegate { _delegate = delegate; }
/* No one customizes a bar that isn't shown, so its items are the defaults. */
- (NSArray *)itemIdentifiers { return _defaults ?: @[]; }
- (BOOL)isVisible { return NO; }
- (NSTouchBarItem *)itemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if (!identifier)
        return nil;
    NSTouchBarItem *item = _made[identifier];
    if (item)
        return item;
    for (NSTouchBarItem *t in _templates)
        if ([[t identifier] isEqualToString:identifier])
            item = t;
    if (!item && [_delegate respondsToSelector:@selector(touchBar:makeItemForIdentifier:)])
        item = [_delegate touchBar:self makeItemForIdentifier:identifier];
    if (item)
        _made[identifier] = item;
    return item;
}
@end

@implementation NSTouchBarItem {
@protected
    NSString *_identifier;
    NSTouchBarItemPriority _priority;
}
- (instancetype)initWithIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ((self = [super init]))
        _identifier = [identifier copy];
    return self;
}
- (instancetype)init { return [self initWithIdentifier:@""]; }
- (instancetype)initWithCoder:(NSCoder *)coder { return [self initWithIdentifier:@""]; }
- (void)encodeWithCoder:(NSCoder *)coder {}
- (void)dealloc
{
    [_identifier release];
    [super dealloc];
}
- (NSTouchBarItemIdentifier)identifier { return _identifier; }
- (NSTouchBarItemPriority)visibilityPriority { return _priority; }
- (void)setVisibilityPriority:(NSTouchBarItemPriority)priority { _priority = priority; }
- (NSView *)view { return nil; }
- (NSViewController *)viewController { return nil; }
- (NSString *)customizationLabel { return @""; }
- (BOOL)isVisible { return NO; }
@end

@implementation NSCustomTouchBarItem {
    NSView *_view;
    NSViewController *_controller;
    NSString *_label;
}
- (void)dealloc
{
    [_view release];
    [_controller release];
    [_label release];
    [super dealloc];
}
- (NSView *)view { return _view ?: [_controller view]; }
- (void)setView:(NSView *)view
{
    [view retain];
    [_view release];
    _view = view;
}
- (NSViewController *)viewController { return _controller; }
- (void)setViewController:(NSViewController *)controller
{
    [controller retain];
    [_controller release];
    _controller = controller;
}
- (NSString *)customizationLabel { return _label ?: @""; }
- (void)setCustomizationLabel:(NSString *)label
{
    NSString *old = _label;
    _label = [label copy];
    [old release];
}
@end

@implementation NSGroupTouchBarItem {
    NSTouchBar *_group;
    NSString *_label;
}
+ (instancetype)groupItemWithIdentifier:(NSTouchBarItemIdentifier)identifier items:(NSArray *)items
{
    NSGroupTouchBarItem *g = [[[self alloc] initWithIdentifier:identifier] autorelease];
    NSTouchBar *bar = [[[NSTouchBar alloc] init] autorelease];
    NSMutableArray *ids = [NSMutableArray array];
    for (NSTouchBarItem *i in items)
        [ids addObject:[i identifier]];
    [bar setDefaultItemIdentifiers:ids];
    [bar setTemplateItems:[NSSet setWithArray:items]];
    [g setGroupTouchBar:bar];
    return g;
}
- (void)dealloc
{
    [_group release];
    [_label release];
    [super dealloc];
}
- (NSTouchBar *)groupTouchBar { return _group; }
- (void)setGroupTouchBar:(NSTouchBar *)bar
{
    [bar retain];
    [_group release];
    _group = bar;
}
- (NSString *)customizationLabel { return _label ?: @""; }
- (void)setCustomizationLabel:(NSString *)label
{
    NSString *old = _label;
    _label = [label copy];
    [old release];
}
@end

static char touch_bar_key;

@implementation NSResponder (NSTouchBarProvider)
- (NSTouchBar *)touchBar
{
    NSTouchBar *bar = objc_getAssociatedObject(self, &touch_bar_key);
    if (!bar) {
        bar = [self makeTouchBar];
        if (bar)
            objc_setAssociatedObject(self, &touch_bar_key, bar, OBJC_ASSOCIATION_RETAIN);
    }
    return bar;
}
- (void)setTouchBar:(NSTouchBar *)bar { objc_setAssociatedObject(self, &touch_bar_key, bar, OBJC_ASSOCIATION_RETAIN); }
- (NSTouchBar *)makeTouchBar { return nil; }
@end
