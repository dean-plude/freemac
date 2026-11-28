/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSFontManager and NSFontPanel, written from Apple's
 * public NSFontManager and NSFontPanel documentation and its font handling
 * guide; no Apple code or headers were used.
 *
 * The font manager lists the families and faces installed on this system
 * (Pango asks fontconfig), makes fonts by family, traits and weight, and
 * converts fonts the way its last action says: adding or removing a trait,
 * a size up or down, heavier or lighter, or what the font panel shows. Its
 * actions (addFontTrait:, removeFontTrait:, modifyFont: and the panel's
 * modifyFontViaPanel:) send changeFont: down the responder chain, where a
 * text view converts the fonts of its selection with convertFont:. Font
 * weights are Apple's scale from 0 to 15, 5 being regular and 9 bold; a
 * family's member is [PostScript name, face name, weight, traits], as on a
 * Mac.
 *
 * The font panel is GTK's font chooser. Choosing a font in it changes, in
 * the selection, only what differs from the font the panel was showing: a
 * new size keeps each run's family, a new family keeps each run's size.
 * With no display, FERRY_FONT_ANSWER gives the font chosen, as Pango
 * writes one ("DejaVu Serif Bold 18"). Built without ARC. */
#import "AInternal.h"

static NSFontManager *shared_manager;
static Class manager_factory, panel_factory;
static NSFontPanel *shared_panel;

NSFontManager *AExistingFontManager(void) { return shared_manager; }

/* ---- weights and traits --------------------------------------------------------------- */

/* Pango's weight (100 to 1000) on Apple's scale (0 to 15). */
static NSInteger apple_weight(int pango)
{
    static const struct { int pango; NSInteger apple; } scale[] = {
        {100, 2}, {200, 3}, {300, 4}, {350, 4}, {380, 5}, {400, 5}, {500, 6},
        {600, 8}, {700, 9}, {800, 10}, {900, 11}, {1000, 12},
    };
    NSInteger best = 5;
    int distance = 10000;
    for (size_t i = 0; i < sizeof scale / sizeof scale[0]; i++)
        if (abs(scale[i].pango - pango) < distance) {
            distance = abs(scale[i].pango - pango);
            best = scale[i].apple;
        }
    return best;
}

/* Apple's weight as Pango's. */
static int pango_weight(NSInteger apple)
{
    if (apple <= 2)
        return 100;
    static const int scale[] = {100, 100, 100, 200, 300, 400, 500, 600, 600, 700, 800, 900, 1000};
    return apple < 13 ? scale[apple] : 1000;
}

static NSFontTraitMask traits_of(GFont *f)
{
    NSFontTraitMask t = 0;
    t |= f->weight >= PANGO_WEIGHT_SEMIBOLD ? NSBoldFontMask : 0;
    t |= f->style != PANGO_STYLE_NORMAL ? NSItalicFontMask : 0;
    t |= f->monospace ? NSFixedPitchFontMask : 0;
    return t;
}

/* The PostScript name Ferry gives a face (CTFontCopyPostScriptName does
 * the same for a font). */
static NSString *ps_name(NSString *family, int weight, int style)
{
    const char *w = weight >= 800   ? "Black"
                    : weight >= 700 ? "Bold"
                    : weight >= 600 ? "SemiBold"
                    : weight >= 500 ? "Medium"
                    : weight <= 200 ? "Thin"
                    : weight <= 300 ? "Light"
                                    : "";
    BOOL italic = style != PANGO_STYLE_NORMAL;
    NSString *face = !*w && !italic ? @"Regular" : [NSString stringWithFormat:@"%s%s", w, italic ? "Italic" : ""];
    return [NSString stringWithFormat:@"%@-%@", [family stringByReplacingOccurrencesOfString:@" " withString:@""], face];
}

/* Generic names fontconfig answers to, which aren't families of their own. */
static BOOL generic_family(NSString *name)
{
    static NSSet *names;
    if (!names)
        names = [[NSSet setWithArray:@[ @"sans", @"sans-serif", @"serif", @"monospace", @"mono",
                                               @"system-ui", @"cursive", @"fantasy", @"emoji", @"math" ]] retain];
    return [names containsObject:[name lowercaseString]];
}

/* The installed families, Pango's objects by name. */
static NSDictionary *installed_families(void)
{
    static NSDictionary *families;
    if (families)
        return families;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    PangoFontFamily **list = NULL;
    int count = 0;
    pango_font_map_list_families(pango_cairo_font_map_get_default(), &list, &count);
    for (int i = 0; i < count; i++) {
        const char *name = pango_font_family_get_name(list[i]);
        if (name && !generic_family(@(name)))
            [d setObject:[NSValue valueWithPointer:list[i]] forKey:@(name)];
    }
    g_free(list);
    families = [d copy];
    return families;
}

/* An installed family by any case of its name, as it is installed. */
static NSString *installed_name(NSString *family)
{
    if (!family)
        return nil;
    NSDictionary *all = installed_families();
    if ([all objectForKey:family])
        return family;
    for (NSString *name in all)
        if ([name caseInsensitiveCompare:family] == NSOrderedSame)
            return name;
    return nil;
}

/* The family a font of that name would be: installed, or a Mac family's
 * stand-in, as installed. */
static NSString *resolved_family(NSString *family)
{
    NSString *name = installed_name(family);
    if (name)
        return name;
    NSString *mac = GFontMacFamily(family);
    if (!mac)
        return nil;
    GFont *f = GFontCreate(mac, PANGO_WEIGHT_NORMAL, PANGO_STYLE_NORMAL, 12);
    name = [[f->family copy] autorelease];
    [f release];
    return name;
}

static NSFont *make_font(NSString *family, int weight, int style, CGFloat size)
{
    return [(NSFont *)GFontCreate(family, weight, style, size > 0 ? size : 12) autorelease];
}

/* ---- NSFontManager -------------------------------------------------------------------- */

@implementation NSFontManager {
    BOOL _ready;
    NSFont *_selected;
    BOOL _multiple, _enabled;
    NSFontAction _fontAction;
    NSFontTraitMask _trait;
    SEL _action;
    id _target, _delegate;
    NSMenu *_menu;
    NSMutableDictionary *_members;
}

/* There is one font manager: making another (in a nib, say) gives it. */
+ (id)allocWithZone:(NSZone *)zone
{
    if (shared_manager)
        return [shared_manager retain];
    return [super allocWithZone:zone];
}
+ (NSFontManager *)sharedFontManager
{
    if (!shared_manager)
        [[[(manager_factory ?: [NSFontManager class]) alloc] init] release];
    return shared_manager;
}
+ (void)setFontManagerFactory:(Class)c
{
    if (!shared_manager)
        manager_factory = c;
}
+ (void)setFontPanelFactory:(Class)c
{
    if (!shared_panel)
        panel_factory = c;
}

- (instancetype)init
{
    if (_ready)
        return self;
    if ((self = [super init])) {
        _ready = YES;
        _enabled = YES;
        _action = @selector(changeFont:);
        _members = [[NSMutableDictionary alloc] init];
        if (!shared_manager)
            shared_manager = [self retain]; /* kept for good */
    }
    return self;
}

/* ---- what is installed ---- */

/* The Mac families that installed stand-ins answer for (Times where only
 * DejaVu Serif is installed), which the available fonts list too: Chromium
 * finds its last resort font, Times, in this list (freemac 1.NEXT). */
static NSString *stand_in_family(NSString *family)
{
    if (!family || installed_name(family))
        return nil;
    for (NSString *mac in GFontStandInFamilyNames())
        if ([mac caseInsensitiveCompare:family] == NSOrderedSame)
            return mac;
    return nil;
}

- (NSArray *)availableFontFamilies
{
    NSMutableArray *names = [NSMutableArray arrayWithArray:[installed_families() allKeys]];
    for (NSString *mac in GFontStandInFamilyNames())
        if (!installed_name(mac))
            [names addObject:mac];
    return [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (NSArray *)availableMembersOfFontFamily:(NSString *)family
{
    NSString *name = installed_name(family), *listed = name;
    if (!name && (listed = stand_in_family(family)))
        name = resolved_family(listed); /* a Mac family's members are its stand-in's, under the Mac name */
    if (!name || !listed)
        return nil;
    NSArray *cached = [_members objectForKey:listed];
    if (cached)
        return cached;
    PangoFontFamily *pf = [[installed_families() objectForKey:name] pointerValue];
    if (!pf)
        return nil;
    PangoFontFace **faces = NULL;
    int count = 0;
    pango_font_family_list_faces(pf, &faces, &count);
    NSMutableArray *members = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    BOOL mono = pango_font_family_is_monospace(pf);
    for (int i = 0; i < count; i++) {
        if (pango_font_face_is_synthesized(faces[i]))
            continue;
        PangoFontDescription *d = pango_font_face_describe(faces[i]);
        int weight = pango_font_description_get_weight(d), style = pango_font_description_get_style(d);
        pango_font_description_free(d);
        const char *face = pango_font_face_get_face_name(faces[i]);
        NSString *ps = ps_name(listed, weight, style);
        if ([seen containsObject:ps])
            continue;
        [seen addObject:ps];
        NSFontTraitMask traits = (weight >= PANGO_WEIGHT_SEMIBOLD ? NSBoldFontMask : 0) |
                                 (style != PANGO_STYLE_NORMAL ? NSItalicFontMask : 0) |
                                 (mono ? NSFixedPitchFontMask : 0);
        [members addObject:@[ ps, @(face ?: "Regular"), @(apple_weight(weight)), @(traits) ]];
    }
    g_free(faces);
    /* lighter first, upright before italic, as a Mac lists them */
    [members sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
      NSInteger wa = [a[2] integerValue], wb = [b[2] integerValue];
      if (wa != wb)
          return wa < wb ? NSOrderedAscending : NSOrderedDescending;
      NSUInteger ia = [a[3] unsignedIntegerValue] & NSItalicFontMask, ib = [b[3] unsignedIntegerValue] & NSItalicFontMask;
      return ia == ib ? NSOrderedSame : ia < ib ? NSOrderedAscending : NSOrderedDescending;
    }];
    [_members setObject:members forKey:listed];
    return members;
}

- (NSArray *)availableFonts
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *family in [self availableFontFamilies])
        for (NSArray *m in [self availableMembersOfFontFamily:family])
            [names addObject:m[0]];
    return names;
}

- (NSArray *)availableFontNamesWithTraits:(NSFontTraitMask)traits
{
    NSFontTraitMask want = traits & ~(NSUnboldFontMask | NSUnitalicFontMask);
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *family in [self availableFontFamilies])
        for (NSArray *m in [self availableMembersOfFontFamily:family]) {
            NSFontTraitMask t = [m[3] unsignedIntegerValue];
            if ((t & want) != want)
                continue;
            if (((traits & NSUnboldFontMask) && (t & NSBoldFontMask)) ||
                ((traits & NSUnitalicFontMask) && (t & NSItalicFontMask)))
                continue;
            [names addObject:m[0]];
        }
    return names;
}

/* ---- making and converting fonts ---- */

- (NSFont *)fontWithFamily:(NSString *)family traits:(NSFontTraitMask)traits weight:(NSInteger)weight
                      size:(CGFloat)size
{
    NSString *name = resolved_family(family);
    if (!name)
        return nil;
    int w = pango_weight(weight);
    if (traits & NSBoldFontMask)
        w = MAX(w, PANGO_WEIGHT_BOLD);
    if (traits & NSUnboldFontMask)
        w = MIN(w, PANGO_WEIGHT_NORMAL);
    int style = (traits & NSItalicFontMask) && !(traits & NSUnitalicFontMask) ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL;
    return make_font(name, w, style, size);
}

- (NSFontTraitMask)traitsOfFont:(NSFont *)font { return font ? traits_of((GFont *)font) : 0; }
- (NSInteger)weightOfFont:(NSFont *)font { return font ? apple_weight(((GFont *)font)->weight) : 5; }

- (NSFont *)convertFont:(NSFont *)font toFamily:(NSString *)family
{
    NSString *name = resolved_family(family);
    if (!font || !name)
        return font;
    GFont *f = (GFont *)font;
    return make_font(name, f->weight, f->style, f->size) ?: font;
}

- (NSFont *)convertFont:(NSFont *)font toFace:(NSString *)typeface
{
    if (!font || ![typeface length])
        return font;
    GFont *f = (GFont *)font;
    /* a face of the font's own family, by face or PostScript name */
    for (NSArray *m in [self availableMembersOfFontFamily:f->family])
        if ([m[0] caseInsensitiveCompare:typeface] == NSOrderedSame ||
            [m[1] caseInsensitiveCompare:typeface] == NSOrderedSame) {
            NSFontTraitMask t = [m[3] unsignedIntegerValue];
            return make_font(f->family, pango_weight([m[2] integerValue]),
                             t & NSItalicFontMask ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL, f->size);
        }
    return [NSFont fontWithName:typeface size:f->size] ?: font;
}

- (NSFont *)convertFont:(NSFont *)font toHaveTrait:(NSFontTraitMask)trait
{
    if (!font)
        return nil;
    GFont *f = (GFont *)font;
    int weight = f->weight, style = f->style;
    NSString *family = f->family;
    if (trait & NSBoldFontMask)
        weight = MAX(weight, PANGO_WEIGHT_BOLD);
    if (trait & NSUnboldFontMask)
        weight = PANGO_WEIGHT_NORMAL;
    if (trait & NSItalicFontMask)
        style = PANGO_STYLE_ITALIC;
    if (trait & NSUnitalicFontMask)
        style = PANGO_STYLE_NORMAL;
    if ((trait & NSFixedPitchFontMask) && !f->monospace)
        family = resolved_family(@"Menlo") ?: family;
    if (weight == f->weight && style == f->style && family == f->family)
        return font;
    return make_font(family, weight, style, f->size) ?: font;
}

- (NSFont *)convertFont:(NSFont *)font toNotHaveTrait:(NSFontTraitMask)trait
{
    NSFontTraitMask opposite = 0;
    if (trait & NSBoldFontMask)
        opposite |= NSUnboldFontMask;
    if (trait & NSItalicFontMask)
        opposite |= NSUnitalicFontMask;
    if (trait & NSUnboldFontMask)
        opposite |= NSBoldFontMask;
    if (trait & NSUnitalicFontMask)
        opposite |= NSItalicFontMask;
    return opposite ? [self convertFont:font toHaveTrait:opposite] : font;
}

- (NSFont *)convertFont:(NSFont *)font toSize:(CGFloat)size
{
    if (!font || size <= 0)
        return font;
    GFont *f = (GFont *)font;
    return make_font(f->family, f->weight, f->style, size) ?: font;
}

/* The next weight the family has, in the font's style. */
- (NSFont *)convertWeight:(BOOL)up ofFont:(NSFont *)font
{
    if (!font)
        return nil;
    GFont *f = (GFont *)font;
    NSInteger now = apple_weight(f->weight), best = -1;
    BOOL italic = f->style != PANGO_STYLE_NORMAL;
    for (NSArray *m in [self availableMembersOfFontFamily:f->family]) {
        NSInteger w = [m[2] integerValue];
        if ((([m[3] unsignedIntegerValue] & NSItalicFontMask) != 0) != italic)
            continue;
        if (up ? (w > now && (best < 0 || w < best)) : (w < now && (best < 0 || w > best)))
            best = w;
    }
    if (best < 0)
        return font;
    return make_font(f->family, pango_weight(best), f->style, f->size) ?: font;
}

- (BOOL)fontNamed:(NSString *)name hasTraits:(NSFontTraitMask)traits
{
    NSFont *font = [NSFont fontWithName:name size:12];
    if (!font)
        return NO;
    NSFontTraitMask t = traits_of((GFont *)font);
    if ((traits & NSUnboldFontMask) && (t & NSBoldFontMask))
        return NO;
    if ((traits & NSUnitalicFontMask) && (t & NSItalicFontMask))
        return NO;
    traits &= ~(NSUnboldFontMask | NSUnitalicFontMask);
    return (t & traits) == traits;
}

- (NSString *)localizedNameForFamily:(NSString *)family face:(NSString *)face
{
    if (![face length] || [face isEqual:@"Regular"])
        return family;
    return [NSString stringWithFormat:@"%@ %@", family, face];
}

/* The font as the action being sent asks. */
- (NSFont *)convertFont:(NSFont *)font
{
    switch (_fontAction) {
    case NSViaPanelFontAction:
        return shared_panel ? [shared_panel panelConvertFont:font] : font;
    case NSAddTraitFontAction:
        return [self convertFont:font toHaveTrait:_trait];
    case NSRemoveTraitFontAction:
        return [self convertFont:font toNotHaveTrait:_trait];
    case NSSizeUpFontAction:
        return [self convertFont:font toSize:[font pointSize] + 1];
    case NSSizeDownFontAction:
        return [font pointSize] > 1 ? [self convertFont:font toSize:[font pointSize] - 1] : font;
    case NSHeavierFontAction:
        return [self convertWeight:YES ofFont:font];
    case NSLighterFontAction:
        return [self convertWeight:NO ofFont:font];
    default:
        return font;
    }
}

/* ---- the selection and the actions ---- */

- (NSFont *)selectedFont { return _selected; }
- (BOOL)isMultiple { return _multiple; }
- (void)setSelectedFont:(NSFont *)font isMultiple:(BOOL)multiple
{
    [font retain];
    [_selected release];
    _selected = font;
    _multiple = multiple;
    if (shared_panel)
        [shared_panel setPanelFont:font isMultiple:multiple];
}
- (NSFontAction)currentFontAction { return _fontAction; }
- (SEL)action { return _action; }
- (void)setAction:(SEL)a { _action = a; }
- (id)target { return _target; }
- (void)setTarget:(id)t { _target = t; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)f
{
    _enabled = f;
    if (shared_panel)
        [shared_panel setEnabled:f];
}

- (BOOL)sendAction
{
    if (!_action)
        return NO;
    BOOL sent = [NSApp sendAction:_action to:_target from:self];
    _fontAction = NSNoFontChangeAction;
    return sent;
}

- (BOOL)_send:(NSFontAction)action trait:(NSFontTraitMask)trait
{
    if (!_enabled)
        return NO;
    _fontAction = action;
    _trait = trait;
    return [self sendAction];
}

/* Bold and Italic take the trait off again where the selected font has
 * it, so the menu items turn it on and off. */
- (IBAction)addFontTrait:(id)sender
{
    NSFontTraitMask trait = [sender respondsToSelector:@selector(tag)] ? (NSFontTraitMask)[sender tag] : 0;
    NSFontTraitMask has = _selected ? traits_of((GFont *)_selected) : 0;
    if (trait && (trait & (NSBoldFontMask | NSItalicFontMask)) == trait && (has & trait) == trait)
        [self _send:NSRemoveTraitFontAction trait:trait];
    else
        [self _send:NSAddTraitFontAction trait:trait];
}
- (IBAction)removeFontTrait:(id)sender
{
    NSFontTraitMask trait = [sender respondsToSelector:@selector(tag)] ? (NSFontTraitMask)[sender tag] : 0;
    [self _send:NSRemoveTraitFontAction trait:trait];
}
- (IBAction)modifyFont:(id)sender
{
    NSFontAction action = [sender respondsToSelector:@selector(tag)] ? (NSFontAction)[sender tag] : 0;
    if (action == NSSizeUpFontAction || action == NSSizeDownFontAction || action == NSHeavierFontAction ||
        action == NSLighterFontAction)
        [self _send:action trait:0];
}
- (IBAction)modifyFontViaPanel:(id)sender { [self _send:NSViaPanelFontAction trait:0]; }
- (IBAction)orderFrontFontPanel:(id)sender
{
    NSFontPanel *panel = [self fontPanel:YES];
    [panel setPanelFont:_selected ?: [NSFont userFontOfSize:12] isMultiple:_multiple];
    [panel orderFront:sender];
}
- (IBAction)orderFrontStylesPanel:(id)sender { AWarnOnce("the Styles panel"); }

- (NSFontPanel *)fontPanel:(BOOL)create { return create ? [NSFontPanel sharedFontPanel] : shared_panel; }

- (NSMenu *)fontMenu:(BOOL)create
{
    if (_menu || !create)
        return _menu;
    _menu = [[NSMenu alloc] initWithTitle:@"Font"];
    struct {
        NSString *title, *key;
        SEL action;
        NSInteger tag;
    } items[] = {
        {@"Show Fonts", @"t", @selector(orderFrontFontPanel:), 0},
        {@"Bold", @"b", @selector(addFontTrait:), NSBoldFontMask},
        {@"Italic", @"i", @selector(addFontTrait:), NSItalicFontMask},
        {nil, nil, NULL, 0},
        {@"Bigger", @"+", @selector(modifyFont:), NSSizeUpFontAction},
        {@"Smaller", @"-", @selector(modifyFont:), NSSizeDownFontAction},
    };
    for (size_t i = 0; i < sizeof items / sizeof items[0]; i++) {
        if (!items[i].title) {
            [_menu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:items[i].title action:items[i].action
                                               keyEquivalent:items[i].key];
        [item setTag:items[i].tag];
        [item setTarget:self];
        [_menu addItem:item];
        [item release];
    }
    return _menu;
}
- (NSMenu *)fontMenu { return [self fontMenu:NO]; }
- (void)setFontMenu:(NSMenu *)menu
{
    [menu retain];
    [_menu release];
    _menu = menu;
}

/* Bold and Italic show a check where the selected font has the trait. */
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(addFontTrait:)) {
        NSFontTraitMask trait = (NSFontTraitMask)[item tag];
        BOOL has = _selected && trait && (traits_of((GFont *)_selected) & trait) == trait;
        [item setState:has ? NSControlStateValueOn : NSControlStateValueOff];
    }
    return _enabled;
}
@end

/* ---- NSFontPanel ---------------------------------------------------------------------- */

@implementation NSFontPanel {
    NSFont *_font, *_chosen;
    BOOL _multiple, _shown, _enabled, _sending;
    NSView *_accessory;
    GtkWidget *_chooser;
}

+ (NSFontPanel *)sharedFontPanel
{
    if (!shared_panel)
        shared_panel = [[(panel_factory ?: [NSFontPanel class]) alloc]
            initWithContentRect:NSMakeRect(0, 0, 320, 400)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered
                          defer:YES];
    return shared_panel;
}
+ (BOOL)sharedFontPanelExists { return shared_panel != nil; }

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)backing
                              defer:(BOOL)defer
{
    if ((self = [super initWithContentRect:rect styleMask:style backing:backing defer:defer])) {
        _enabled = YES;
        [self setTitle:@"Fonts"];
    }
    return self;
}
- (void)dealloc
{
    [_font release];
    [_chosen release];
    [_accessory release];
    if (_chooser)
        gtk_widget_destroy(_chooser);
    [super dealloc];
}

- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)f { _enabled = f; }
- (NSView *)accessoryView { return _accessory; }
- (void)setAccessoryView:(NSView *)v
{
    [v retain];
    [_accessory release];
    _accessory = v;
    if (v)
        AWarnOnce("accessory views in the font panel");
}
- (void)reloadDefaultFontFamilies {}
- (BOOL)isVisible { return _shown; }
- (BOOL)isFloatingPanel { return YES; }
- (BOOL)worksWhenModal { return YES; }

/* What the panel shows: nothing is sent. */
- (void)setPanelFont:(NSFont *)font isMultiple:(BOOL)multiple
{
    if (_sending)
        return; /* the selection taking the chosen font, as it is sent */
    [font retain];
    [_font release];
    _font = font;
    _multiple = multiple;
    [_chosen release];
    _chosen = nil;
    if (_chooser && font) {
        PangoFontDescription *d = pango_font_description_copy(((GFont *)font)->desc);
        pango_font_description_set_size(d, (int)([font pointSize] * PANGO_SCALE));
        gtk_font_chooser_set_font_desc(_chooser, d);
        pango_font_description_free(d);
    }
}

/* The font with what the user changed in the panel: the family, the face
 * or the size, each only where it differs from the font the panel showed. */
- (NSFont *)panelConvertFont:(NSFont *)font
{
    if (!_chosen || !font)
        return font;
    GFont *c = (GFont *)_chosen, *f = (GFont *)font, *shown = (GFont *)_font;
    NSString *family = f->family;
    int weight = f->weight, style = f->style;
    CGFloat size = f->size;
    if (!shown || ![c->family isEqual:shown->family])
        family = c->family;
    if (!shown || c->weight != shown->weight || c->style != shown->style) {
        weight = c->weight;
        style = c->style;
    }
    if (!shown || fabs(c->size - shown->size) > 0.01)
        size = c->size;
    return make_font(family, weight, style, size) ?: font;
}

/* The user chose a font, as Pango describes it. */
- (void)_chose:(const PangoFontDescription *)d
{
    if (!d)
        return;
    GFont *shown = (GFont *)_font;
    const char *family = pango_font_description_get_family(d);
    int size = pango_font_description_get_size(d);
    CGFloat points = size > 0 ? (CGFloat)size / PANGO_SCALE : (shown ? shown->size : 12);
    NSFont *chosen = make_font(family ? @(family) : (shown ? shown->family : @"sans-serif"),
                               pango_font_description_get_weight(d), pango_font_description_get_style(d), points);
    if (!chosen)
        return;
    [self retain];
    [chosen retain];
    id wasChosen = _chosen;
    _chosen = [chosen retain];
    [wasChosen release];
    _sending = YES;
    if (_enabled)
        [[NSFontManager sharedFontManager] modifyFontViaPanel:self];
    _sending = NO;
    /* the panel now shows what was chosen */
    [_font release];
    _font = chosen;
    [_chosen release];
    _chosen = nil;
    [self release];
}

static void on_response(GtkWidget *dialog, int response, void *data)
{
    NSFontPanel *panel = data;
    A_REPORTING({
        if (response == GTK_RESPONSE_OK) {
            PangoFontDescription *d = gtk_font_chooser_get_font_desc(dialog);
            [panel _chose:d];
            if (d)
                pango_font_description_free(d);
        }
        [panel orderOut:nil];
    })
}
static int on_delete(GtkWidget *dialog, GdkEvent *event, void *data)
{
    A_REPORTING([(NSFontPanel *)data orderOut:nil];)
    return 1;
}

/* No display: the answer the environment gives, if any. */
- (void)_answerFromEnvironment
{
    const char *answer = getenv("FERRY_FONT_ANSWER");
    if (!_shown || !answer || !*answer)
        return;
    PangoFontDescription *d = pango_font_description_from_string(answer);
    [self _chose:d];
    pango_font_description_free(d);
    [self orderOut:nil];
}

- (void)orderFront:(id)sender
{
    BOOL was = _shown;
    _shown = YES;
    if (ADisplayAvailable()) {
        if (!_chooser) {
            _chooser = gtk_font_chooser_dialog_new([[self title] UTF8String], NULL);
            g_signal_connect_data(_chooser, "response", (GCallback)on_response, self, NULL, 0);
            g_signal_connect_data(_chooser, "delete-event", (GCallback)on_delete, self, NULL, 0);
        }
        [self setPanelFont:_font isMultiple:_multiple];
        gtk_widget_show_all(_chooser);
        gtk_window_present(_chooser);
    } else if (!was) {
        [self performSelector:@selector(_answerFromEnvironment) withObject:nil afterDelay:0];
    }
}
- (void)makeKeyAndOrderFront:(id)sender { [self orderFront:sender]; }
- (void)orderFrontRegardless { [self orderFront:nil]; }
- (void)orderOut:(id)sender
{
    if (!_shown)
        return;
    _shown = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_answerFromEnvironment) object:nil];
    if (_chooser)
        gtk_widget_hide(_chooser);
}
- (void)close { [self orderOut:nil]; }
- (void)performClose:(id)sender { [self orderOut:nil]; }
@end
