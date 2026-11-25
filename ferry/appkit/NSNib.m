/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: loading nib files. A compiled nib for the Mac is a keyed
 * archive (see Foundation's NSCoder.m) whose top object, under the key
 * "IB.objectdata", is an NSIBObjectData: the nib's root (File's Owner),
 * every object with its parent, the outlet and action connections, the
 * windows to show at launch, and names for special objects. A nib can be
 * a single file or a folder holding keyedobjects.nib. Nibs compiled by
 * current versions of Xcode hold the same objects in the "NIBArchive" form,
 * which ANibArchive.m reads.
 *
 * Interface Builder writes stand-ins for some objects: NSCustomObject for
 * File's Owner, First Responder, the Application and custom objects;
 * NSCustomView and NSClassSwapper for views of the app's own classes; and
 * NSWindowTemplate for each window. Loading turns those into the real
 * objects, makes the connections, sends awakeFromNib, and shows the
 * windows marked visible at launch.
 *
 * The class and key names follow Apple's public documentation of nib
 * loading (NSNib, awakeFromNib, File's Owner, outlets and actions) and
 * descriptions of the archive's contents published by developers and by the
 * GNUstep project. No Apple code or nib was copied. */
#import "AInternal.h"

/* Stand-ins replace themselves with other objects in initWithCoder:. */
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

/* ---- the load in progress --------------------------------------------------------------- */

typedef struct {
    NSMutableDictionary *namedMenus;   /* "_NSMainMenu" -> menu */
} ANibLoad;

static ANibLoad *current_load;

void ANibNoteNamedMenu(NSMenu *menu, NSString *name)
{
    if (current_load && menu && name)
        [current_load->namedMenus setObject:menu forKey:name];
}

static void warn_class(NSString *what, NSString *name)
{
    static NSMutableSet *warned;
    if (!warned)
        warned = [[NSMutableSet alloc] init];
    if ([warned containsObject:name])
        return;
    [warned addObject:name];
    fprintf(stderr, "ferry: a nib uses %s %s, which this program doesn't have\n", [what UTF8String],
            [name UTF8String]);
}

/* ---- colours and fonts ---------------------------------------------------------------------- */

/* "NSColorSpace": 1 and 2 are RGB in "NSRGB" (text, "r g b a"), 3 and 4
 * grey in "NSWhite" ("w a"), 5 CMYK in "NSCMYK", 6 a named colour
 * ("NSCatalogName", "NSColorName", with "NSColor" as a fallback). */
static int parse_components(NSData *d, CGFloat *out, int max)
{
    if (![d isKindOfClass:[NSData class]])
        return 0;
    char buf[256];
    NSUInteger n = [d length] < sizeof buf - 1 ? [d length] : sizeof buf - 1;
    memcpy(buf, [d bytes], n);
    buf[n] = 0;
    int count = 0;
    char *p = buf, *end;
    while (count < max) {
        double v = strtod(p, &end);
        if (end == p)
            break;
        out[count++] = v;
        p = end;
    }
    return count;
}

@implementation NSColor (NSNibCoding)
- (instancetype)initWithCoder:(NSCoder *)c
{
    [self release];
    NSColor *color = nil;
    CGFloat v[5] = {0, 0, 0, 1, 1};
    int space = [c decodeIntForKey:@"NSColorSpace"];
    switch (space) {
    case 1:
    case 2: {
        NSData *d = [c decodeObjectForKey:@"NSRGB"] ?: [c decodeObjectForKey:@"NSComponents"];
        int n = parse_components(d, v, 4);
        if (n < 4)
            v[3] = 1;
        color = [NSColor colorWithSRGBRed:v[0] green:v[1] blue:v[2] alpha:v[3]];
        break;
    }
    case 3:
    case 4: {
        int n = parse_components([c decodeObjectForKey:@"NSWhite"], v, 2);
        if (n < 2)
            v[1] = 1;
        color = [NSColor colorWithCalibratedWhite:v[0] alpha:v[1]];
        break;
    }
    case 5: {
        int n = parse_components([c decodeObjectForKey:@"NSCMYK"], v, 5);
        if (n < 5)
            v[4] = 1;
        color = [NSColor colorWithSRGBRed:(1 - v[0]) * (1 - v[3]) green:(1 - v[1]) * (1 - v[3])
                                     blue:(1 - v[2]) * (1 - v[3]) alpha:v[4]];
        break;
    }
    case 6: {
        NSString *name = [c decodeObjectForKey:@"NSColorName"];
        SEL sel = [name isKindOfClass:[NSString class]] ? NSSelectorFromString(name) : NULL;
        if (sel && [NSColor respondsToSelector:sel])
            color = ((id (*)(id, SEL))objc_msgSend)([NSColor class], sel);
        if (![color isKindOfClass:[NSColor class]]) {
            color = [c decodeObjectForKey:@"NSColor"];
            if (![color isKindOfClass:[NSColor class]])
                color = nil;
        }
        break;
    }
    }
    return [color ?: [NSColor blackColor] retain];
}
- (void)encodeWithCoder:(NSCoder *)c
{
    CGFloat rgba[4];
    AColorRGBA(self, rgba);
    [c encodeInt:1 forKey:@"NSColorSpace"];
    NSString *s = [NSString stringWithFormat:@"%g %g %g %g", rgba[0], rgba[1], rgba[2], rgba[3]];
    [c encodeObject:[s dataUsingEncoding:NSASCIIStringEncoding] forKey:@"NSRGB"];
}
@end

@implementation NSFont (NSNibCoding)
- (instancetype)initWithCoder:(NSCoder *)c
{
    [self release];
    NSString *name = [c decodeObjectForKey:@"NSName"];
    CGFloat points = [c decodeDoubleForKey:@"NSSize"];
    NSFont *f = [name isKindOfClass:[NSString class]] ? [NSFont fontWithName:name size:points] : nil;
    return [f ?: [NSFont systemFontOfSize:points] retain];
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:[self fontName] forKey:@"NSName"];
    [c encodeDouble:[self pointSize] forKey:@"NSSize"];
}
@end

@implementation NSObject (FerryNibImage)
- (NSString *)_imageName { return nil; }
@end

/* Image references: "NSButtonImageSource" names a system image (NSSwitch,
 * NSRadioButton), which only says what kind of button it is in, and
 * "NSCustomResource" an image in the app's resources, which becomes that
 * NSImage. An image that can't be found becomes an empty image with the
 * name, and a warning. */
@interface NSButtonImageSource : NSObject <NSCoding> {
    NSString *_name;
}
@end
@implementation NSButtonImageSource
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init]))
        _name = [[c decodeObjectForKey:@"NSImageName"] copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:_name forKey:@"NSImageName"]; }
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (NSString *)_imageName { return _name; }
@end

@interface NSCustomResource : NSObject <NSCoding> {
    NSString *_class, *_name;
}
@end
@implementation NSCustomResource
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        _class = [[c decodeObjectForKey:@"NSClassName"] copy];
        _name = [[c decodeObjectForKey:@"NSResourceName"] copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_class forKey:@"NSClassName"];
    [c encodeObject:_name forKey:@"NSResourceName"];
}
- (void)dealloc
{
    [_class release];
    [_name release];
    [super dealloc];
}
- (NSString *)_imageName { return _name; }
- (id)awakeAfterUsingCoder:(NSCoder *)coder
{
    if (![_class isEqualToString:@"NSImage"] || ![_name isKindOfClass:[NSString class]])
        return self;
    NSImage *image = [NSImage imageNamed:_name];
    if (image)
        return image;
    fprintf(stderr, "ferry: the nib names an image, \"%s\", that Ferry can't find or read; left empty\n",
            [_name UTF8String]);
    image = [[[NSImage alloc] initWithSize:NSZeroSize] autorelease];
    [image setName:_name];
    return image;
}
@end

/* ---- stand-ins ------------------------------------------------------------------------- */

/* File's Owner, First Responder, the Application, or an object of the
 * app's own class. Replaced by the real object when the nib is loaded. */
@interface NSCustomObject : NSObject <NSCoding> {
@public
    NSString *_className;
}
@end
@implementation NSCustomObject
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init]))
        _className = [[c decodeObjectForKey:@"NSClassName"] copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:_className forKey:@"NSClassName"]; }
- (void)dealloc
{
    [_className release];
    [super dealloc];
}
@end

/* A stand-in (a class swapper, a custom view) hands its place in the
 * archive to the object it makes, before that object decodes, so that the
 * objects it holds which point back at it (a table's columns) get the new
 * object, not the stand-in that is gone (freemac 1.225). */
@interface NSCoder (FerryHandOver)
- (void)_ferryReplaceObjectInProgress:(id)old with:(id)object;
@end
static void hand_over(NSCoder *c, id old, id object)
{
    if (object && [c respondsToSelector:@selector(_ferryReplaceObjectInProgress:with:)])
        [c _ferryReplaceObjectInProgress:old with:object];
}

/* A view of the app's own class, made with initWithFrame: as on a Mac. */
@interface NSCustomView : NSView
@end
@implementation NSCustomView
- (instancetype)initWithCoder:(NSCoder *)c
{
    NSString *name = [c decodeObjectForKey:@"NSClassName"];
    Class cls = [name isKindOfClass:[NSString class]] ? NSClassFromString(name) : Nil;
    if (!cls || ![cls isSubclassOfClass:[NSView class]]) {
        if (name)
            warn_class(@"the view class", name);
        cls = [NSView class];
    }
    NSView *v = [cls alloc];
    hand_over(c, self, v);
    [self release];
    v = [v initWithFrame:AViewFrameFromCoder(c)];
    AViewDecode(v, c);
    return (id)v;
}
@end

/* An object of the app's own class that Interface Builder knows by one of
 * AppKit's classes: it is decoded as the app's class from the same keys. */
@interface NSClassSwapper : NSObject <NSCoding>
@end
@implementation NSClassSwapper
- (instancetype)initWithCoder:(NSCoder *)c
{
    NSString *name = [c decodeObjectForKey:@"NSClassName"];
    NSString *original = [c decodeObjectForKey:@"NSOriginalClassName"];
    Class cls = [name isKindOfClass:[NSString class]] ? NSClassFromString(name) : Nil;
    if (!cls) {
        if (name)
            warn_class(@"the class", name);
        cls = [original isKindOfClass:[NSString class]] ? NSClassFromString(original) : Nil;
    }
    id obj = cls ? [cls alloc] : nil;
    hand_over(c, self, obj);
    [self release];
    return [obj initWithCoder:c];
}
- (void)encodeWithCoder:(NSCoder *)c {}
@end

/* A window as Interface Builder describes it. Decoding makes the window
 * itself, so outlets to it get the window. */
@interface NSWindowTemplate : NSObject <NSCoding>
@end
@implementation NSWindowTemplate
- (instancetype)initWithCoder:(NSCoder *)c
{
    [self release];
    NSString *name = [c decodeObjectForKey:@"NSWindowClass"];
    Class cls = [name isKindOfClass:[NSString class]] ? NSClassFromString(name) : Nil;
    if (!cls || ![cls isSubclassOfClass:[NSWindow class]]) {
        if (name)
            warn_class(@"the window class", name);
        cls = [NSWindow class];
    }
    NSRect rect = [c decodeRectForKey:@"NSWindowRect"];
    NSWindowStyleMask style = (NSWindowStyleMask)[c decodeInt64ForKey:@"NSWindowStyleMask"];
    NSWindow *w = [[cls alloc] initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:YES];
    NSString *title = [c decodeObjectForKey:@"NSWindowTitle"];
    if ([title isKindOfClass:[NSString class]])
        [w setTitle:title];
    NSView *content = [c decodeObjectForKey:@"NSWindowView"];
    if ([content isKindOfClass:[NSView class]])
        [w setContentView:content];
    /* the toolbar ("NSViewClass" in some descriptions of the format) */
    NSToolbar *toolbar = [c containsValueForKey:@"NSToolbar"] ? [c decodeObjectForKey:@"NSToolbar"] : nil;
    if (![toolbar isKindOfClass:[NSToolbar class]] && [c containsValueForKey:@"NSViewClass"])
        toolbar = [c decodeObjectForKey:@"NSViewClass"];
    if ([toolbar isKindOfClass:[NSToolbar class]])
        [w setToolbar:toolbar];
    if ([c containsValueForKey:@"NSMinSize"])
        [w setMinSize:[c decodeSizeForKey:@"NSMinSize"]];
    if ([c containsValueForKey:@"NSMaxSize"]) {
        NSSize max = [c decodeSizeForKey:@"NSMaxSize"];
        if (max.width > 0 && max.height > 0)
            [w setMaxSize:max];
    }
    if ([c containsValueForKey:@"NSWindowContentMinSize"])
        [w setContentMinSize:[c decodeSizeForKey:@"NSWindowContentMinSize"]];
    if ([c containsValueForKey:@"NSWindowIsRestorable"])
        (void)[c decodeBoolForKey:@"NSWindowIsRestorable"];
    NSString *autosave = [c decodeObjectForKey:@"NSFrameAutosaveName"];
    if ([autosave isKindOfClass:[NSString class]] && [autosave length])
        [w setFrameAutosaveName:autosave];
    return (id)w;
}
- (void)encodeWithCoder:(NSCoder *)c {}
@end

/* Connections. Outlets are set with the setter or instance variable of
 * that name (key-value coding); actions set a control's or menu item's
 * target and action. */
@interface NSNibConnector : NSObject <NSCoding> {
@public
    id _source, _destination;
    NSString *_label;
}
- (void)_connectWith:(NSDictionary *)map;
@end

static id resolve(id obj, NSDictionary *map)
{
    if (!obj)
        return nil;
    id real = [map objectForKey:[NSValue valueWithPointer:obj]];
    if (real)
        return real == [NSNull null] ? nil : real;
    return obj;
}

@implementation NSNibConnector
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        _source = [c decodeObjectForKey:@"NSSource"];
        _destination = [c decodeObjectForKey:@"NSDestination"];
        _label = [[c decodeObjectForKey:@"NSLabel"] copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc
{
    [_label release];
    [super dealloc];
}
- (void)_connectWith:(NSDictionary *)map {}
@end

@interface NSNibOutletConnector : NSNibConnector
@end
@implementation NSNibOutletConnector
- (void)_connectWith:(NSDictionary *)map
{
    id src = resolve(_source, map), dst = resolve(_destination, map);
    if (!src || ![_label length])
        return;
    const char *k = [_label UTF8String];
    char setter[256], ivar[256];
    snprintf(setter, sizeof setter, "set%c%s:", toupper((unsigned char)k[0]), k + 1);
    snprintf(ivar, sizeof ivar, "_%s", k);
    Class cls = object_getClass(src);
    if ([src respondsToSelector:sel_registerName(setter)] || class_getInstanceVariable(cls, ivar) ||
        class_getInstanceVariable(cls, k))
        [src setValue:dst forKey:_label];
    else
        fprintf(stderr, "ferry: a nib connects the outlet \"%s\" of a %s, which has no such outlet\n", k,
                object_getClassName(src));
}
@end

@interface NSNibControlConnector : NSNibConnector
@end
@implementation NSNibControlConnector
- (void)_connectWith:(NSDictionary *)map
{
    id src = resolve(_source, map), dst = resolve(_destination, map);
    if (![src respondsToSelector:@selector(setAction:)])
        return;
    [src setTarget:dst];
    [src setAction:NSSelectorFromString(_label)];
}
@end

@interface NSNibAXRelationshipConnector : NSNibConnector
@end
@implementation NSNibAXRelationshipConnector
@end

/* A binding: the source (a view) bound to a key path of the destination (a
 * controller, usually), with its options. "NSBinding", "NSKeyPath" and
 * "NSOptions" are the names descriptions of the format give; NSLabel holds
 * the two together ("value: selection.name") for older nibs. */
@interface NSNibBindingConnector : NSNibConnector {
    NSString *_binding, *_keyPath;
    NSDictionary *_options;
}
@end
@implementation NSNibBindingConnector
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super initWithCoder:c])) {
        id b = [c decodeObjectForKey:@"NSBinding"], k = [c decodeObjectForKey:@"NSKeyPath"];
        id o = [c decodeObjectForKey:@"NSOptions"];
        if (![b isKindOfClass:[NSString class]] && [_label isKindOfClass:[NSString class]]) {
            NSRange colon = [_label rangeOfString:@":"];
            if (colon.location != NSNotFound) {
                b = [[_label substringToIndex:colon.location]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                k = [[_label substringFromIndex:NSMaxRange(colon)]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
        }
        _binding = [b isKindOfClass:[NSString class]] ? [b copy] : nil;
        _keyPath = [k isKindOfClass:[NSString class]] ? [k copy] : nil;
        _options = [o isKindOfClass:[NSDictionary class]] ? [o copy] : nil;
    }
    return self;
}
- (void)dealloc
{
    [_binding release];
    [_keyPath release];
    [_options release];
    [super dealloc];
}
- (void)_connectWith:(NSDictionary *)map
{
    id src = resolve(_source, map), dst = resolve(_destination, map);
    if (!src || !dst || ![_binding length] || ![_keyPath length])
        return;
    [src bind:_binding toObject:dst withKeyPath:_keyPath options:_options];
}
@end

/* "User Defined Runtime Attributes": key paths set on an object. */
@interface NSIBUserDefinedRuntimeAttributesConnector : NSNibConnector {
    id _object;
    NSArray *_keyPaths, *_values;
}
@end
@implementation NSIBUserDefinedRuntimeAttributesConnector
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super initWithCoder:c])) {
        _object = [c decodeObjectForKey:@"NSObject"];
        _keyPaths = [[c decodeObjectForKey:@"NSKeyPaths"] retain];
        _values = [[c decodeObjectForKey:@"NSValues"] retain];
    }
    return self;
}
- (void)dealloc
{
    [_keyPaths release];
    [_values release];
    [super dealloc];
}
- (void)_connectWith:(NSDictionary *)map
{
    id obj = resolve(_object, map);
    NSUInteger n = MIN([_keyPaths count], [_values count]);
    for (NSUInteger i = 0; i < n; i++) {
        id target = obj;
        NSArray *parts = [[_keyPaths objectAtIndex:i] componentsSeparatedByString:@"."];
        for (NSUInteger j = 0; j + 1 < [parts count] && target; j++)
            target = [target valueForKey:[parts objectAtIndex:j]];
        [target setValue:[_values objectAtIndex:i] forKey:[parts lastObject]];
    }
}
@end

/* The nib's table of contents. */
@interface NSIBObjectData : NSObject <NSCoding> {
@public
    id _root;
    NSArray *_objects, *_parents, *_connections, *_visibleWindows;
}
@end
@implementation NSIBObjectData
- (instancetype)initWithCoder:(NSCoder *)c
{
    if ((self = [super init])) {
        _root = [[c decodeObjectForKey:@"NSRoot"] retain];
        _objects = [[(ANibArchive *)c _decodeArrayKeepingNullsForKey:@"NSObjectsKeys"] retain];
        _parents = [[(ANibArchive *)c _decodeArrayKeepingNullsForKey:@"NSObjectsValues"] retain];
        _connections = [[c decodeObjectForKey:@"NSConnections"] retain];
        id visible = [c decodeObjectForKey:@"NSVisibleWindows"];
        _visibleWindows = [([visible isKindOfClass:[NSSet class]] ? [visible allObjects] : visible) retain];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c {}
- (void)dealloc
{
    [_root release];
    [_objects release];
    [_parents release];
    [_connections release];
    [_visibleWindows release];
    [super dealloc];
}
@end

/* ---- copying a collection view's item prototype ----------------------------------------- */

/* A collection view of the older kind makes an item for each of its
 * content objects by copying its item prototype, which usually comes from
 * a nib with its view, the view's subviews, and outlets and bindings among
 * them. Ferry's views can't be archived again, so a copy is made by
 * decoding the prototype's part of the nib once more. When a nib holds a
 * collection view item, what that takes is kept with the item: the nib's
 * bytes, where the item and the connections touching its part are in the
 * archive, and the nib's other objects (weakly), which the new reader
 * reuses instead of making them again, so that a binding to File's Owner
 * or an outlet to a window still reaches the one there is. */
@interface NSCoder (FerryNibCopying)
- (NSUInteger)_ferryObjectCount;
- (id)_ferryDecodedObjectAtIndex:(NSUInteger)index;
- (void)_ferrySeedObject:(id)object atIndex:(NSUInteger)index;
- (id)_ferryDecodeObjectAtIndex:(NSUInteger)index;
@end

@interface ANibPrototype : NSObject {
@public
    NSData *_data;
    BOOL _nibArchive;
    NSUInteger _item;          /* the item's place in the archive */
    NSUInteger _nseeds, *_seedAt;
    id *_seeds;                /* weak: the nib's other objects */
    NSMutableArray *_placeholders; /* its stand-ins, kept */
    id *_reals;                /* weak: what each stand-in stood for */
    NSArray *_connectors;      /* the places of the connections */
}
@end
@implementation ANibPrototype
- (void)dealloc
{
    for (NSUInteger i = 0; i < _nseeds; i++)
        objc_storeWeak(&_seeds[i], nil);
    for (NSUInteger i = 0; i < [_placeholders count]; i++)
        objc_storeWeak(&_reals[i], nil);
    free(_seeds);
    free(_seedAt);
    free(_reals);
    [_data release];
    [_placeholders release];
    [_connectors release];
    [super dealloc];
}
@end

static const char prototype_key = 0;

static void note_member(NSMutableSet *members, id o)
{
    if (o)
        [members addObject:[NSValue valueWithPointer:o]];
}
static BOOL is_member(NSSet *members, id o) { return o && [members containsObject:[NSValue valueWithPointer:o]]; }
static void note_view_tree(NSMutableSet *members, NSView *v)
{
    if (!v)
        return;
    note_member(members, v);
    if ([v isKindOfClass:[NSControl class]])
        note_member(members, [(NSControl *)v cell]);
    for (NSView *s in [v subviews])
        note_view_tree(members, s);
}

/* The object a runtime-attributes connection sets values on. */
static id connector_object(id conn)
{
    if (![conn isKindOfClass:[NSIBUserDefinedRuntimeAttributesConnector class]])
        return nil;
    id object = nil;
    @try {
        object = [conn valueForKey:@"object"];
    } @catch (NSException *e) {
        object = nil;
    }
    return object;
}

/* After a nib is loaded: for each collection view item in it, what copying
 * it takes (see above). */
static void record_prototypes(NSIBObjectData *nib, NSDictionary *map, NSCoder *u, NSData *data, BOOL nibArchive)
{
    Class itemClass = NSClassFromString(@"NSCollectionViewItem");
    if (!itemClass || ![u respondsToSelector:@selector(_ferryObjectCount)])
        return;
    NSMutableDictionary *where = nil; /* object -> its place in the archive */
    NSArray *objs = nib->_objects, *parents = nib->_parents;
    NSUInteger n = MIN([objs count], [parents count]);
    for (id o in objs) {
        id real = resolve(o, map);
        if (![real isKindOfClass:itemClass] || objc_getAssociatedObject(real, &prototype_key))
            continue;
        if (!where) {
            where = [NSMutableDictionary dictionary];
            NSUInteger count = [u _ferryObjectCount];
            for (NSUInteger i = 0; i < count; i++) {
                id d = [u _ferryDecodedObjectAtIndex:i];
                NSValue *key = d ? [NSValue valueWithPointer:d] : nil;
                if (key && ![where objectForKey:key])
                    [where setObject:[NSNumber numberWithUnsignedInteger:i] forKey:key];
            }
        }
        NSNumber *at = [where objectForKey:[NSValue valueWithPointer:o]];
        if (!at)
            continue;
        /* The item's part: the item, its view and what is inside them. */
        NSMutableSet *members = [NSMutableSet set];
        note_member(members, o);
        note_view_tree(members, [(NSViewController *)real viewIfLoaded]);
        for (BOOL grew = YES; grew;) {
            grew = NO;
            for (NSUInteger i = 0; i < n; i++) {
                id obj = [objs objectAtIndex:i], parent = [parents objectAtIndex:i];
                if (is_member(members, parent) && !is_member(members, obj)) {
                    note_member(members, obj);
                    grew = YES;
                }
            }
        }
        NSMutableArray *connectors = [NSMutableArray array];
        for (id c in nib->_connections) {
            if (![c isKindOfClass:[NSNibConnector class]])
                continue;
            NSNibConnector *conn = c;
            NSNumber *ci = [where objectForKey:[NSValue valueWithPointer:c]];
            /* only those from the part: an outlet to the prototype from outside stays as it is */
            if (ci && (is_member(members, conn->_source) || is_member(members, connector_object(c))))
                [connectors addObject:ci];
        }
        /* Everything else the nib lists is reused. */
        NSMutableArray *others = [NSMutableArray arrayWithArray:objs];
        [others addObjectsFromArray:parents];
        if (nib->_root)
            [others addObject:nib->_root];
        ANibPrototype *t = [[ANibPrototype alloc] init];
        t->_data = [data retain];
        t->_nibArchive = nibArchive;
        t->_item = [at unsignedIntegerValue];
        t->_connectors = [connectors copy];
        t->_seeds = calloc([others count] + 1, sizeof(id));
        t->_seedAt = calloc([others count] + 1, sizeof(NSUInteger));
        t->_placeholders = [[NSMutableArray alloc] init];
        NSMutableSet *seen = [NSMutableSet set];
        for (id obj in others) {
            NSValue *key = [NSValue valueWithPointer:obj];
            NSNumber *place = [where objectForKey:key];
            if (obj == [NSNull null] || is_member(members, obj) || !place || [seen containsObject:key])
                continue;
            [seen addObject:key];
            t->_seedAt[t->_nseeds] = [place unsignedIntegerValue];
            objc_storeWeak(&t->_seeds[t->_nseeds++], obj);
            if ([obj isKindOfClass:[NSCustomObject class]])
                [t->_placeholders addObject:obj];
        }
        t->_reals = calloc([t->_placeholders count] + 1, sizeof(id));
        for (NSUInteger i = 0; i < [t->_placeholders count]; i++) {
            id stand = [t->_placeholders objectAtIndex:i];
            id r = [map objectForKey:[NSValue valueWithPointer:stand]];
            objc_storeWeak(&t->_reals[i], r == [NSNull null] ? nil : r);
        }
        objc_setAssociatedObject(real, &prototype_key, t, OBJC_ASSOCIATION_RETAIN);
        [t release];
    }
}

/* ---- NSNib ----------------------------------------------------------------------------- */

@implementation NSNib {
    NSData *_data;
    NSBundle *_bundle;
}

/* A nib is a file, or a folder with keyedobjects.nib (or a variant for a
 * newer system, keyedobjects-NNNNNN.nib) inside. */
static NSData *read_nib(NSString *path)
{
    BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir])
        return nil;
    if (!dir)
        return [NSData dataWithContentsOfFile:path];
    NSData *d = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"keyedobjects.nib"]];
    if (d)
        return d;
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:NULL]
        sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *n in [names reverseObjectEnumerator])
        if ([n hasPrefix:@"keyedobjects"] && [n hasSuffix:@".nib"])
            return [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:n]];
    return nil;
}

- (instancetype)initWithNibData:(NSData *)data bundle:(NSBundle *)bundle
{
    if (!data) {
        [self release];
        return nil;
    }
    if ((self = [super init])) {
        _data = [data retain];
        _bundle = [bundle ?: [NSBundle mainBundle] retain];
    }
    return self;
}
/* A nib kept inside another nib, as table views keep their cell views'
 * prototypes: the inner nib's bytes, under "NSNibFileData". */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSData *data = [coder containsValueForKey:@"NSNibFileData"] ? [coder decodeObjectForKey:@"NSNibFileData"] : nil;
    if (![data isKindOfClass:[NSData class]]) {
        [self release];
        return nil;
    }
    return [self initWithNibData:data bundle:nil];
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_data forKey:@"NSNibFileData"]; }
- (instancetype)initWithNibNamed:(NSString *)name bundle:(NSBundle *)bundle
{
    bundle = bundle ?: [NSBundle mainBundle];
    NSString *path = [name isAbsolutePath] ? name : [bundle pathForResource:name ofType:@"nib"];
    if (!path && [[name pathExtension] isEqualToString:@"nib"])
        path = [bundle pathForResource:[name stringByDeletingPathExtension] ofType:@"nib"];
    return [self initWithNibData:path ? read_nib(path) : nil bundle:bundle];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url
{
    return [self initWithNibData:read_nib([url path]) bundle:nil];
}
- (void)dealloc
{
    [_data release];
    [_bundle release];
    [super dealloc];
}

/* Makes the real object for a stand-in: File's Owner is the owner, First
 * Responder is nil (an action with no target), the Application is NSApp,
 * and anything else is a new object of its class. */
static id instantiate(NSCustomObject *placeholder, BOOL isRoot, id owner)
{
    if (isRoot)
        return owner;
    NSString *name = placeholder->_className;
    if ([name isEqualToString:@"FirstResponder"])
        return nil;
    Class cls = name ? NSClassFromString(name) : Nil;
    if (!cls) {
        warn_class(@"the class", name ?: @"(unnamed)");
        return nil;
    }
    if ([cls isSubclassOfClass:[NSApplication class]])
        return [cls sharedApplication];
    return [[[cls alloc] init] autorelease];
}

- (BOOL)instantiateWithOwner:(id)owner topLevelObjects:(NSArray **)topLevelObjects
{
    if (topLevelObjects)
        *topLevelObjects = nil;
    ANibLoad load = {[NSMutableDictionary dictionary]};
    ANibLoad *outer = current_load;
    current_load = &load;
    /* Both readers answer _decodeArrayKeepingNullsForKey:, which NSIBObjectData uses. */
    NSCoder *u;
    BOOL nibArchive = [ANibArchive isNibArchive:_data];
    if (nibArchive) {
        u = [[ANibArchive alloc] initForReadingWithData:_data];
    } else {
        u = [[NSKeyedUnarchiver alloc] initForReadingFromData:_data error:NULL];
        [(NSKeyedUnarchiver *)u setRequiresSecureCoding:NO];
    }
    NSIBObjectData *nib = [u decodeObjectForKey:@"IB.objectdata"];
    current_load = outer;
    if (![nib isKindOfClass:[NSIBObjectData class]]) {
        fprintf(stderr, "ferry: this nib couldn't be read%s\n",
                !u || (!nibArchive && [u error]) ? " (it isn't a keyed archive or a NIBArchive)" : "");
        [u release];
        return NO;
    }
    [nib retain];

    /* Stand-ins to real objects. */
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    NSMutableArray *made = [NSMutableArray array]; /* keeps the new objects alive */
    NSMutableArray *all = [NSMutableArray arrayWithArray:nib->_objects ?: [NSArray array]];
    if (nib->_root && ![all containsObject:nib->_root])
        [all addObject:nib->_root];
    [all removeObject:[NSNull null]];
    for (id o in all) {
        if (![o isKindOfClass:[NSCustomObject class]])
            continue;
        id real = instantiate(o, o == nib->_root, owner);
        [map setObject:real ?: (id)[NSNull null] forKey:[NSValue valueWithPointer:o]];
        if (real)
            [made addObject:real];
    }

    /* Menu items, cells and toolbar items whose target is a stand-in, and
     * toolbars whose delegate is. */
    for (id o in all) {
        if ([o isKindOfClass:[NSToolbar class]] && [o delegate] &&
            [map objectForKey:[NSValue valueWithPointer:[o delegate]]])
            [o setDelegate:resolve([o delegate], map)];
        if ([o isKindOfClass:[NSMenuItem class]] || [o isKindOfClass:[NSCell class]] ||
            [o isKindOfClass:[NSToolbarItem class]]) {
            id t = [o target];
            if (t && [map objectForKey:[NSValue valueWithPointer:t]])
                [o setTarget:resolve(t, map)];
        }
        if ([o isKindOfClass:[NSControl class]] && [o target] &&
            [map objectForKey:[NSValue valueWithPointer:[o target]]])
            [o setTarget:resolve([o target], map)];
    }

    for (NSNibConnector *conn in nib->_connections)
        if ([conn isKindOfClass:[NSNibConnector class]])
            [conn _connectWith:map];

    /* Top-level objects: those whose parent is File's Owner, apart from the
     * stand-ins for the owner, First Responder and the Application. */
    NSMutableArray *top = [NSMutableArray array];
    NSUInteger n = MIN([nib->_objects count], [nib->_parents count]);
    for (NSUInteger i = 0; i < n; i++) {
        id o = [nib->_objects objectAtIndex:i];
        if ([nib->_parents objectAtIndex:i] != nib->_root || o == nib->_root)
            continue;
        if ([o isKindOfClass:[NSCustomObject class]]) {
            NSString *cn = ((NSCustomObject *)o)->_className;
            if ([cn isEqualToString:@"FirstResponder"] || NSClassFromString(cn) == [NSApplication class] ||
                [NSClassFromString(cn) isSubclassOfClass:[NSApplication class]])
                continue;
        }
        id real = resolve(o, map);
        if (real && ![top containsObject:real])
            [top addObject:real];
    }

    /* The main menu, when loading for the application. */
    NSMenu *main = [load.namedMenus objectForKey:@"_NSMainMenu"];
    if (main && (owner == NSApp || ![NSApp mainMenu]))
        [NSApp setMainMenu:main];
    NSMenu *windows = [load.namedMenus objectForKey:@"_NSWindowsMenu"];
    if (windows && owner == NSApp)
        [NSApp setWindowsMenu:windows];
    NSMenu *recent = [load.namedMenus objectForKey:@"_NSRecentDocumentsMenu"];
    if (recent)
        ANoteRecentDocumentsMenu(recent);

    /* awakeFromNib, to every object the nib made and to the owner. */
    NSMutableArray *awake = [NSMutableArray array];
    for (id o in all) {
        id real = resolve(o, map);
        if (real && real != owner && real != NSApp && ![awake containsObject:real])
            [awake addObject:real];
    }
    for (id o in awake)
        if ([o respondsToSelector:@selector(awakeFromNib)])
            [o awakeFromNib];
    if ([owner respondsToSelector:@selector(awakeFromNib)])
        [owner awakeFromNib];

    for (NSWindow *w in nib->_visibleWindows) {
        if (![w isKindOfClass:[NSWindow class]])
            continue;
        [w retain]; /* a shown window stays until it is closed */
        [w makeKeyAndOrderFront:nil];
    }

    record_prototypes(nib, map, u, _data, nibArchive);
    [u release];

    if (topLevelObjects)
        *topLevelObjects = top;
    [nib release];
    return YES;
}
- (BOOL)instantiateNibWithOwner:(id)owner topLevelObjects:(NSArray **)objects
{
    return [self instantiateWithOwner:owner topLevelObjects:objects];
}
@end

/* A new copy of an item prototype that came from a nib, or nil when it
 * didn't (see record_prototypes). */
id ANibCopyItemPrototype(id item)
{
    ANibPrototype *t = objc_getAssociatedObject(item, &prototype_key);
    if (!t)
        return nil;
    NSCoder *u;
    if (t->_nibArchive) {
        u = [[ANibArchive alloc] initForReadingWithData:t->_data];
    } else {
        u = [[NSKeyedUnarchiver alloc] initForReadingFromData:t->_data error:NULL];
        [(NSKeyedUnarchiver *)u setRequiresSecureCoding:NO];
    }
    if (![u respondsToSelector:@selector(_ferrySeedObject:atIndex:)]) {
        [u release];
        return nil;
    }
    for (NSUInteger i = 0; i < t->_nseeds; i++) {
        id obj = objc_loadWeak(&t->_seeds[i]);
        if (obj)
            [u _ferrySeedObject:obj atIndex:t->_seedAt[i]];
    }
    ANibLoad load = {[NSMutableDictionary dictionary]};
    ANibLoad *outer = current_load;
    current_load = &load;
    id made = [u _ferryDecodeObjectAtIndex:t->_item];
    NSMutableArray *connectors = [NSMutableArray array];
    for (NSNumber *ci in t->_connectors) {
        id c = [u _ferryDecodeObjectAtIndex:[ci unsignedIntegerValue]];
        if (c)
            [connectors addObject:c];
    }
    current_load = outer;
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < [t->_placeholders count]; i++)
        [map setObject:objc_loadWeak(&t->_reals[i]) ?: (id)[NSNull null]
                forKey:[NSValue valueWithPointer:[t->_placeholders objectAtIndex:i]]];
    id real = made;
    if ([made isKindOfClass:[NSCustomObject class]]) {
        real = instantiate(made, NO, nil);
        [map setObject:real ?: (id)[NSNull null] forKey:[NSValue valueWithPointer:made]];
    }
    [real retain];
    /* Controls in the copy whose target is a stand-in, as when loading. */
    NSUInteger count = [u _ferryObjectCount];
    for (NSUInteger i = 0; i < count; i++) {
        id o = [u _ferryDecodedObjectAtIndex:i];
        if (([o isKindOfClass:[NSControl class]] || [o isKindOfClass:[NSCell class]]) && [o target] &&
            [map objectForKey:[NSValue valueWithPointer:[o target]]])
            [o setTarget:resolve([o target], map)];
    }
    for (NSNibConnector *conn in connectors)
        if ([conn isKindOfClass:[NSNibConnector class]])
            [conn _connectWith:map];
    if (real)
        objc_setAssociatedObject(real, &prototype_key, t, OBJC_ASSOCIATION_RETAIN);
    [u release];
    return real;
}

@implementation NSObject (NSNibAwaking)
- (void)awakeFromNib {}
- (void)prepareForInterfaceBuilder {}
@end

@implementation NSBundle (NSNibLoading)
- (BOOL)loadNibNamed:(NSString *)name owner:(id)owner topLevelObjects:(NSArray **)objects
{
    NSNib *nib = [[NSNib alloc] initWithNibNamed:name bundle:self];
    if (!nib) {
        fprintf(stderr, "ferry: couldn't find the nib %s\n", [name UTF8String]);
        return NO;
    }
    BOOL ok = [nib instantiateWithOwner:owner topLevelObjects:objects];
    [nib release];
    return ok;
}
/* The old way: the top-level objects are kept (the caller releases them). */
+ (BOOL)loadNibNamed:(NSString *)name owner:(id)owner
{
    NSArray *top = nil;
    BOOL ok = [[NSBundle mainBundle] loadNibNamed:name owner:owner topLevelObjects:&top];
    for (id o in top)
        [o retain];
    return ok;
}
+ (BOOL)loadNibFile:(NSString *)path externalNameTable:(NSDictionary *)context withZone:(NSZone *)zone
{
    NSNib *nib = [[NSNib alloc] initWithNibData:read_nib(path) bundle:nil];
    NSArray *top = nil;
    BOOL ok = [nib instantiateWithOwner:[context objectForKey:@"NSOwner"] topLevelObjects:&top];
    for (id o in top)
        [o retain];
    [nib release];
    return ok;
}
@end
