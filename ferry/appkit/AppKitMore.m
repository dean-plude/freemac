/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit names the nine apps' sources use that Ferry hadn't had (freemac
 * 1.221, Ferry 0.45.0; sdk/include/AppKit/AppKitMore.h): the run loop's
 * tracking and modal modes, the AppKit version, ending a field's editing,
 * and appearances. The rest of what that header declares is with the class
 * it belongs to. */
#import "AInternal.h"
#include <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <string.h>

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
/* the colour and font panels' toolbar images (freemac 1.NEXT, MacVim) */
NSImageName const NSImageNameColorPanel = @"NSColorPanel";
NSImageName const NSImageNameFontPanel = @"NSFontPanel";

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

/* An appearance is a name, light (Aqua) or dark (DarkAqua), and a Mac app
 * is in freemac's own (freemac 1.245, Ferry 0.68.0): dark when Dials >
 * Appearance is Dark, or Auto after sunset (org.gnome.desktop.interface's
 * color-scheme is prefer-dark), and light otherwise, following each change
 * while it runs. FERRY_APPEARANCE=dark or light sets it instead. As on a
 * Mac, an app that says it needs the light appearance
 * (NSRequiresAquaSystemAppearance) or was built with an SDK older than
 * macOS 10.14's, from before dark mode, stays light; one that sets its own
 * appearance has that. The system colours (NSGraphics.m) are drawn in the
 * appearance drawing is in: the view's, its window's or the app's. */
@implementation NSAppearance {
    NSString *_name;
    BOOL _dark;
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
        a->_dark = [name rangeOfString:@"Dark"].location != NSNotFound;
        known[name] = a;
    }
    return a;
}
static NSAppearance *app_appearance(void);
/* the one drawing is in: set for drawing a view or by the app, else the
 * app's own */
+ (NSAppearance *)currentAppearance { return current_appearance ?: app_appearance(); }
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
    NSAppearanceName family = _dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua;
    if ([names containsObject:family])
        return family;
    for (NSAppearanceName n in names)
        if (([n rangeOfString:@"Dark"].location != NSNotFound) == _dark)
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

static BOOL is_dark(NSAppearance *a) { return a && a->_dark; }
@end

static NSAppearance *aqua(void) { return [NSAppearance appearanceNamed:NSAppearanceNameAqua]; }
static char appearance_key;
static NSAppearance *own_appearance(id object) { return object ? objc_getAssociatedObject(object, &appearance_key) : nil; }
static void set_own_appearance(id object, NSAppearance *a)
{
    objc_setAssociatedObject(object, &appearance_key, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
NSAppearance *AOwnAppearance(id object) { return own_appearance(object); }

/* Drawing a view or window that has an appearance of its own is in that
 * appearance: ABeginDrawingAppearance gives what to hand back to
 * AEndDrawingAppearance afterwards. */
NSAppearance *ABeginDrawingAppearance(id object)
{
    NSAppearance *own = own_appearance(object);
    if (!own)
        return nil;
    NSAppearance *saved = current_appearance ? [current_appearance retain] : (id)[NSNull null];
    [NSAppearance setCurrentAppearance:own];
    return saved;
}
void AEndDrawingAppearance(NSAppearance *saved)
{
    if (!saved)
        return;
    if ((id)saved == [NSNull null]) {
        [NSAppearance setCurrentAppearance:nil];
        return;
    }
    [NSAppearance setCurrentAppearance:saved];
    [saved release];
}

/* ---- freemac's light or dark appearance ---- */

static int desktop_dark = -1; /* not read yet */
static GSettings *interface_settings;

static int read_desktop_dark(void)
{
    const char *forced = getenv("FERRY_APPEARANCE");
    if (forced && !strcmp(forced, "dark"))
        return 1;
    if (forced && !strcmp(forced, "light"))
        return 0;
    BOOL made = NO;
    GSettings *settings = interface_settings;
    if (!settings) {
        GSettingsSchemaSource *source = g_settings_schema_source_get_default();
        GSettingsSchema *schema =
            source ? g_settings_schema_source_lookup(source, "org.gnome.desktop.interface", 1) : NULL;
        if (!schema)
            return 0;
        if (g_settings_schema_has_key(schema, "color-scheme")) {
            settings = g_settings_new_full(schema, NULL, NULL);
            made = YES;
        }
        g_settings_schema_unref(schema);
        if (!settings)
            return 0;
    }
    char *scheme = g_settings_get_string(settings, "color-scheme");
    int dark = scheme && !strcmp(scheme, "prefer-dark");
    g_free(scheme);
    if (made)
        g_object_unref(settings);
    return dark;
}

/* whether this program was built against macOS 10.14's SDK or a later one
 * (its LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX), as Apple's apps that
 * know dark mode are; a program whose SDK can't be told is taken as new */
static BOOL built_for_dark_mode(void)
{
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header_64 *h = (const void *)_dyld_get_image_header(i);
        if (!h || h->magic != MH_MAGIC_64 || h->filetype != MH_EXECUTE)
            continue;
        const uint8_t *p = (const uint8_t *)(h + 1);
        for (uint32_t n = 0; n < h->ncmds; n++) {
            const struct load_command *lc = (const void *)p;
            if (lc->cmd == LC_BUILD_VERSION)
                return ((const struct build_version_command *)lc)->sdk >= 0x000a0e00;
            if (lc->cmd == LC_VERSION_MIN_MACOSX)
                return ((const struct version_min_command *)lc)->sdk >= 0x000a0e00;
            p += lc->cmdsize;
        }
        return YES;
    }
    return YES;
}

static BOOL stays_light(void)
{
    static int light = -1;
    if (light < 0) {
        id says = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSRequiresAquaSystemAppearance"];
        light = ([says respondsToSelector:@selector(boolValue)] && [says boolValue]) || !built_for_dark_mode();
    }
    return light;
}

BOOL ADesktopDark(void)
{
    if (desktop_dark < 0)
        desktop_dark = read_desktop_dark();
    return desktop_dark;
}

static NSAppearance *app_appearance(void)
{
    NSAppearance *own = NSApp ? own_appearance(NSApp) : nil;
    if (own)
        return own;
    return ADesktopDark() && !stays_light() ? [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua] : aqua();
}

BOOL ADrawsDark(void) { return is_dark(current_appearance ?: app_appearance()); }

/* AppleInterfaceStyle, which apps written before NSAppearance read, is Dark
 * in the global domain while freemac is dark, and isn't there otherwise,
 * whatever appearance the app chose for itself, as on a Mac */
static void tell_defaults(void)
{
    [NSUserDefaults _ferrySetGlobalValue:ADesktopDark() ? @"Dark" : nil forKey:@"AppleInterfaceStyle"];
}

static void appearance_changed_views(NSView *view)
{
    if (own_appearance(view))
        return;
    if ([view respondsToSelector:@selector(viewDidChangeEffectiveAppearance)])
        [view viewDidChangeEffectiveAppearance];
    [view setNeedsDisplay:YES];
    for (NSView *v in [[[view subviews] copy] autorelease])
        appearance_changed_views(v);
}

/* The app's appearance changed (from the desktop's, or the app set its
 * own): observers of effectiveAppearance hear it, its views are told and
 * drawn again, and AppleInterfaceThemeChangedNotification goes to the
 * app's observers of the distributed centre, as on a Mac. */
static void app_appearance_changed(void (^change)(void))
{
    BOOL was = is_dark(app_appearance());
    NSArray *windows = [NSApp windows];
    [NSApp willChangeValueForKey:@"effectiveAppearance"];
    for (NSWindow *w in windows)
        if (!own_appearance(w))
            [w willChangeValueForKey:@"effectiveAppearance"];
    change();
    for (NSWindow *w in windows)
        if (!own_appearance(w))
            [w didChangeValueForKey:@"effectiveAppearance"];
    [NSApp didChangeValueForKey:@"effectiveAppearance"];
    if (was == is_dark(app_appearance()))
        return;
    tell_defaults();
    for (NSWindow *w in windows)
        if (!own_appearance(w) && [w contentView]) {
            NSView *top = [w contentView];
            while ([top superview])
                top = [top superview];
            appearance_changed_views(top);
        }
    [[NSNotificationCenter defaultCenter] postNotificationName:NSSystemColorsDidChangeNotification object:nil];
    NSNotification *note = [NSNotification notificationWithName:@"AppleInterfaceThemeChangedNotification" object:nil];
    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    if ([center respondsToSelector:@selector(_arrived:immediately:)])
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(center, @selector(_arrived:immediately:), note, YES);
}

static void on_color_scheme(GSettings *settings, const char *key, void *data)
{
    int now = read_desktop_dark();
    if (now == desktop_dark)
        return;
    app_appearance_changed(^{
      desktop_dark = now;
    });
}

/* Called as the app starts, on the main thread: the settings are watched
 * from its main context, which Ferry's run loop turns. */
void AAppearanceFollow(void)
{
    static BOOL following;
    if (following)
        return;
    following = YES;
    const char *forced = getenv("FERRY_APPEARANCE");
    if (!(forced && *forced)) {
        GSettingsSchemaSource *source = g_settings_schema_source_get_default();
        GSettingsSchema *schema =
            source ? g_settings_schema_source_lookup(source, "org.gnome.desktop.interface", 1) : NULL;
        if (schema) {
            if (g_settings_schema_has_key(schema, "color-scheme")) {
                interface_settings = g_settings_new_full(schema, NULL, NULL);
                g_signal_connect_data(interface_settings, "changed::color-scheme", (GCallback)on_color_scheme, NULL,
                                      NULL, 0);
                AGlibAttach(); /* the change comes through GLib's main context */
            }
            g_settings_schema_unref(schema);
        }
    }
    desktop_dark = read_desktop_dark();
    tell_defaults();
}

@implementation NSApplication (FerryAppearance)
- (NSAppearance *)appearance { return own_appearance(self); }
- (void)setAppearance:(NSAppearance *)a
{
    if (a == own_appearance(self))
        return;
    app_appearance_changed(^{
      set_own_appearance(self, a);
    });
}
- (NSAppearance *)effectiveAppearance { return app_appearance(); }
@end

@implementation NSWindow (FerryAppearance)
- (NSAppearance *)appearance { return own_appearance(self); }
- (void)setAppearance:(NSAppearance *)a
{
    [self willChangeValueForKey:@"effectiveAppearance"];
    set_own_appearance(self, a);
    [self didChangeValueForKey:@"effectiveAppearance"];
    NSView *top = [self contentView];
    while ([top superview])
        top = [top superview];
    if (top) {
        [top setNeedsDisplay:YES];
        for (NSView *v in [top subviews])
            [v setNeedsDisplay:YES];
    }
}
- (NSAppearance *)effectiveAppearance { return own_appearance(self) ?: app_appearance(); }
@end

/* a view's own, else its superview's, else its window's */
@implementation NSView (FerryAppearance)
- (NSAppearance *)appearance { return own_appearance(self); }
- (void)setAppearance:(NSAppearance *)a
{
    set_own_appearance(self, a);
    if ([self respondsToSelector:@selector(viewDidChangeEffectiveAppearance)])
        [self viewDidChangeEffectiveAppearance];
    [self setNeedsDisplay:YES];
}
- (NSAppearance *)effectiveAppearance
{
    for (NSView *v = self; v; v = [v superview])
        if (own_appearance(v))
            return own_appearance(v);
    NSWindow *w = [self window];
    return w ? [w effectiveAppearance] : app_appearance();
}
@end
