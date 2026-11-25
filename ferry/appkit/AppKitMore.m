/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit names the nine apps' sources use that Ferry hadn't had (freemac
 * 1.221, Ferry 0.45.0; sdk/include/AppKit/AppKitMore.h): the run loop's
 * tracking and modal modes, the AppKit version, ending a field's editing,
 * and appearances. The rest of what that header declares is with the class
 * it belongs to. */
#import "AInternal.h"
#include <objc/runtime.h>

NSRunLoopMode const NSEventTrackingRunLoopMode = @"NSEventTrackingRunLoopMode";
NSRunLoopMode const NSModalPanelRunLoopMode = @"NSModalPanelRunLoopMode";

NSNotificationName const NSMenuDidBeginTrackingNotification = @"NSMenuDidBeginTrackingNotification";
NSNotificationName const NSMenuDidEndTrackingNotification = @"NSMenuDidEndTrackingNotification";
NSNotificationName const NSSystemColorsDidChangeNotification = @"NSSystemColorsDidChangeNotification";
NSNotificationName const NSFontSetChangedNotification = @"NSFontSetChangedNotification";
NSNotificationName const NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
NSNotificationName const NSMenuDidSendActionNotification = @"NSMenuDidSendActionNotification";
NSNotificationName const NSTextInputContextKeyboardSelectionDidChangeNotification =
    @"NSTextInputContextKeyboardSelectionDidChangeNotification";

/* A menu item chosen: its action, between the menu's two notifications. */
void ASendMenuItemAction(NSMenuItem *item)
{
    SEL action = [item action];
    if (!action)
        return;
    NSMenu *menu = [item menu];
    NSDictionary *info = @{@"MenuItem" : item};
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:NSMenuWillSendActionNotification object:menu userInfo:info];
    [NSApp sendAction:action to:[item target] from:item];
    [nc postNotificationName:NSMenuDidSendActionNotification object:menu userInfo:info];
}

NSImageName const NSImageNameComputer = @"NSComputer";
NSImageName const NSImageNameNetwork = @"NSNetwork";
NSImageName const NSImageNamePreferencesGeneral = @"NSPreferencesGeneral";
NSImageName const NSImageNameAdvanced = @"NSAdvanced";
NSImageName const NSImageNameEveryone = @"NSEveryone";
NSImageName const NSImageNameUser = @"NSUser";
NSImageName const NSImageNameUserGroup = @"NSUserGroup";

/* macOS 14's, the release Ferry answers as (FERRY_MACOS_VERSION) */
const double NSAppKitVersionNumber = 2487;

/* ---- ending a field's editing ---- */

@implementation NSWindow (FerryFieldEditor)
/* A text field being edited (object, or whichever one is when object is
 * nil) stops being edited, keeping its text, even if its delegate would
 * rather it went on: the window becomes the first responder. */
- (void)endEditingFor:(id)object
{
    NSResponder *first = [self firstResponder];
    if (object && first != object)
        return;
    if (![first isKindOfClass:[NSTextField class]])
        return;
    if (![self makeFirstResponder:self])
        [first resignFirstResponder];
}
/* Ferry's text fields edit their own text: there is no shared field editor */
- (NSText *)fieldEditor:(BOOL)create forObject:(id)object { return nil; }
@end

/* ---- appearances ---- */

NSAppearanceName const NSAppearanceNameAqua = @"NSAppearanceNameAqua";
NSAppearanceName const NSAppearanceNameDarkAqua = @"NSAppearanceNameDarkAqua";
NSAppearanceName const NSAppearanceNameVibrantLight = @"NSAppearanceNameVibrantLight";
NSAppearanceName const NSAppearanceNameVibrantDark = @"NSAppearanceNameVibrantDark";
NSAppearanceName const NSAppearanceNameAccessibilityHighContrastAqua = @"NSAppearanceNameAccessibilityHighContrastAqua";
NSAppearanceName const NSAppearanceNameAccessibilityHighContrastDarkAqua =
    @"NSAppearanceNameAccessibilityHighContrastDarkAqua";

/* An appearance is a name: Ferry draws everything in the light one, so an
 * app that asks which it is in hears Aqua, and one it sets is remembered and
 * answered back but changes no drawing. */
@implementation NSAppearance {
    NSString *_name;
}
static NSAppearance *current_appearance;

+ (NSAppearance *)appearanceNamed:(NSAppearanceName)name
{
    static NSMutableDictionary *known;
    static NSArray *names;
    if (!names)
        names = [@[
            NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameVibrantLight, NSAppearanceNameVibrantDark,
            NSAppearanceNameAccessibilityHighContrastAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua
        ] retain];
    if (![names containsObject:name])
        return nil;
    if (!known)
        known = [[NSMutableDictionary alloc] init];
    NSAppearance *a = known[name];
    if (!a) {
        a = [[[NSAppearance alloc] init] autorelease];
        a->_name = [name copy];
        known[name] = a;
    }
    return a;
}
+ (NSAppearance *)currentAppearance { return current_appearance ?: [self appearanceNamed:NSAppearanceNameAqua]; }
+ (void)setCurrentAppearance:(NSAppearance *)a
{
    [a retain];
    [current_appearance release];
    current_appearance = a;
}
+ (NSAppearance *)currentDrawingAppearance { return [self currentAppearance]; }
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (NSAppearanceName)name { return _name; }
- (BOOL)allowsVibrancy { return [_name hasPrefix:@"NSAppearanceNameVibrant"]; }
/* the first of the names that is this appearance, or the light or dark
 * appearance it is a kind of */
- (NSAppearanceName)bestMatchFromAppearancesWithNames:(NSArray<NSAppearanceName> *)names
{
    if ([names containsObject:_name])
        return _name;
    BOOL dark = [_name rangeOfString:@"Dark"].location != NSNotFound;
    NSAppearanceName family = dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
    if ([names containsObject:family])
        return family;
    for (NSAppearanceName n in names)
        if (([n rangeOfString:@"Dark"].location != NSNotFound) == dark)
            return n;
    return nil;
}
- (void)performAsCurrentDrawingAppearance:(void (^)(void))block
{
    NSAppearance *saved = [current_appearance retain];
    [NSAppearance setCurrentAppearance:self];
    @try {
        if (block)
            block();
    } @finally {
        [NSAppearance setCurrentAppearance:saved];
        [saved release];
    }
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_name forKey:@"NSAppearanceName"]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *name = [coder decodeObjectForKey:@"NSAppearanceName"];
    [self release];
    return [[NSAppearance appearanceNamed:name ?: NSAppearanceNameAqua] retain];
}
- (NSString *)description { return [NSString stringWithFormat:@"<NSAppearance %@>", _name]; }
@end

static NSAppearance *aqua(void) { return [NSAppearance appearanceNamed:NSAppearanceNameAqua]; }
static char appearance_key;
static NSAppearance *own_appearance(id object) { return objc_getAssociatedObject(object, &appearance_key); }
static void set_own_appearance(id object, NSAppearance *a)
{
    objc_setAssociatedObject(object, &appearance_key, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation NSApplication (FerryAppearance)
- (NSAppearance *)appearance { return own_appearance(self); }
- (void)setAppearance:(NSAppearance *)a { set_own_appearance(self, a); }
- (NSAppearance *)effectiveAppearance { return own_appearance(self) ?: aqua(); }
@end

@implementation NSWindow (FerryAppearance)
- (NSAppearance *)appearance { return own_appearance(self); }
- (void)setAppearance:(NSAppearance *)a { set_own_appearance(self, a); }
- (NSAppearance *)effectiveAppearance { return own_appearance(self) ?: (NSApp ? [NSApp effectiveAppearance] : aqua()); }
@end

/* a view's own, else its superview's, else its window's */
@implementation NSView (FerryAppearance)
- (NSAppearance *)appearance { return own_appearance(self); }
- (void)setAppearance:(NSAppearance *)a { set_own_appearance(self, a); }
- (NSAppearance *)effectiveAppearance
{
    for (NSView *v = self; v; v = [v superview])
        if (own_appearance(v))
            return own_appearance(v);
    NSWindow *w = [self window];
    return w ? [w effectiveAppearance] : NSApp ? [NSApp effectiveAppearance] : aqua();
}
@end
