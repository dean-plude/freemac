/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSStoryboard (freemac 1.260). Our own code, written from
 * Apple's public documentation of NSStoryboard and from what a compiled
 * storyboard in an app's own bundle holds.
 *
 * Xcode compiles a storyboard into a folder, Name.storyboardc, with an
 * Info.plist and one nib for each scene. The Info.plist names the nib of
 * each controller ("NSViewControllerIdentifiersToNibNames", by the
 * controller's storyboard identifier) and of the main menu
 * ("NSStoryboardMainMenu"). A scene's nib has a plain object as File's
 * Owner whose "sceneController" outlet is the controller, and is handed the
 * storyboard as the outside object "NSStoryboardPlaceholder". A view
 * controller's view is in a nib of its own, which the controller loads as
 * File's Owner when its view is first asked for, handing it the outside
 * objects in its "NSExternalObjectsTableForViewLoading" (itself, by name).
 * Built without ARC. */
#import "AInternal.h"

/* File's Owner of a scene's nib. */
@interface AStoryboardScene : NSObject {
@public
    id _sceneController;
}
@end
@implementation AStoryboardScene
- (void)setSceneController:(id)c
{
    [c retain];
    [_sceneController release];
    _sceneController = c;
}
- (id)sceneController { return _sceneController; }
- (void)dealloc
{
    [_sceneController release];
    [super dealloc];
}
@end

static NSStoryboard *loading; /* the storyboard whose scene is being loaded */
static const char scene_objects_key = 0;

NSStoryboard *AStoryboardLoading(void) { return loading; }

@implementation NSStoryboard {
    NSString *_path;   /* the .storyboardc folder */
    NSDictionary *_info;
    NSBundle *_bundle;
}

static NSStoryboard *main_storyboard;

+ (instancetype)storyboardWithName:(NSStoryboardName)name bundle:(NSBundle *)bundle
{
    bundle = bundle ?: [NSBundle mainBundle];
    if (![name isKindOfClass:[NSString class]] || ![name length])
        return nil;
    if ([[name pathExtension] isEqualToString:@"storyboardc"] || [[name pathExtension] isEqualToString:@"storyboard"])
        name = [name stringByDeletingPathExtension];
    NSString *path = [name isAbsolutePath] ? [name stringByAppendingPathExtension:@"storyboardc"]
                                           : [bundle pathForResource:name ofType:@"storyboardc"];
    NSDictionary *info = path ? [NSDictionary dictionaryWithContentsOfFile:
                                                  [path stringByAppendingPathComponent:@"Info.plist"]]
                              : nil;
    if (![info isKindOfClass:[NSDictionary class]]) {
        /* On a Mac this is an exception the app is expected not to cause. */
        [NSException raise:NSInvalidArgumentException
                    format:@"Storyboard (%@) doesn't exist in bundle %@", name, [bundle bundlePath]];
        return nil;
    }
    NSStoryboard *s = [[[self alloc] init] autorelease];
    s->_path = [path copy];
    s->_info = [info retain];
    s->_bundle = [bundle retain];
    return s;
}

+ (NSStoryboard *)mainStoryboard
{
    if (!main_storyboard) {
        NSString *name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSMainStoryboardFile"];
        if ([name isKindOfClass:[NSString class]] && [name length]) {
            @try {
                main_storyboard = [[self storyboardWithName:name bundle:[NSBundle mainBundle]] retain];
            } @catch (NSException *e) {
                main_storyboard = nil;
            }
        }
    }
    return main_storyboard;
}

- (void)dealloc
{
    [_path release];
    [_info release];
    [_bundle release];
    [super dealloc];
}

- (NSString *)description { return [NSString stringWithFormat:@"<NSStoryboard %@>", [_path lastPathComponent]]; }

- (NSString *)_pathForNibNamed:(NSString *)name
{
    if (![name length])
        return nil;
    NSString *p = [_path stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"nib"]];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? p : nil;
}

/* Loads one of the storyboard's nibs; the scene's controller, or nil. */
- (id)_loadNib:(NSString *)nibName owner:(id)owner
{
    NSString *path = [self _pathForNibNamed:nibName];
    if (!path) {
        fprintf(stderr, "ferry: the storyboard %s has no nib %s\n", [[_path lastPathComponent] UTF8String],
                [nibName UTF8String]);
        return nil;
    }
    NSNib *nib = [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
    NSStoryboard *outer = loading;
    loading = self;
    NSArray *top = nil;
    BOOL ok = [nib _instantiateWithOwner:owner
                          externalObjects:[NSDictionary dictionaryWithObject:self forKey:@"NSStoryboardPlaceholder"]
                          topLevelObjects:&top];
    loading = outer;
    [nib release];
    return ok ? (top ?: @[]) : nil;
}

- (id)instantiateControllerWithIdentifier:(NSStoryboardSceneIdentifier)identifier
{
    return [self instantiateControllerWithIdentifier:identifier creator:nil];
}
- (id)instantiateControllerWithIdentifier:(NSStoryboardSceneIdentifier)identifier
                                  creator:(NSStoryboardControllerCreator)block
{
    NSDictionary *nibs = [_info objectForKey:@"NSViewControllerIdentifiersToNibNames"];
    NSString *nibName = [nibs isKindOfClass:[NSDictionary class]] ? [nibs objectForKey:identifier] : nil;
    if (![nibName isKindOfClass:[NSString class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Storyboard (%@) doesn't contain a controller with identifier '%@'",
                           [_path lastPathComponent], identifier];
        return nil;
    }
    if (block) {
        static BOOL told;
        if (!told) {
            told = YES;
            fprintf(stderr, "ferry: a storyboard was asked to make a controller with the app's own creator; "
                            "Ferry makes it the usual way\n");
        }
    }
    AStoryboardScene *scene = [[AStoryboardScene alloc] init];
    NSArray *top = [self _loadNib:nibName owner:scene];
    id controller = [[scene->_sceneController retain] autorelease];
    [scene release];
    /* the scene's other top-level objects live as long as its controller */
    if (controller && [top count])
        objc_setAssociatedObject(controller, &scene_objects_key, top, OBJC_ASSOCIATION_RETAIN);
    if (!controller)
        fprintf(stderr, "ferry: the storyboard scene %s made no controller\n", [identifier UTF8String]);
    return controller;
}

/* The scene to start with. The compiled storyboard names it under a key
 * of its Info.plist about the entry point or initial controller; any such
 * key naming one of its scenes is taken. */
- (NSString *)_initialIdentifier
{
    NSDictionary *nibs = [_info objectForKey:@"NSViewControllerIdentifiersToNibNames"];
    if (![nibs isKindOfClass:[NSDictionary class]])
        return nil;
    for (NSString *key in _info) {
        id value = [_info objectForKey:key];
        if (![value isKindOfClass:[NSString class]] || ![nibs objectForKey:value])
            continue;
        if ([key rangeOfString:@"EntryPoint"].location != NSNotFound ||
            [key rangeOfString:@"Initial"].location != NSNotFound)
            return value;
    }
    return nil;
}
- (id)instantiateInitialController { return [self instantiateInitialControllerWithCreator:nil]; }
- (id)instantiateInitialControllerWithCreator:(NSStoryboardControllerCreator)block
{
    NSString *identifier = [self _initialIdentifier];
    return identifier ? [self instantiateControllerWithIdentifier:identifier creator:block] : nil;
}

/* At launch: the main menu, then the first scene, shown. */
- (void)_loadForApplication
{
    NSString *menu = [_info objectForKey:@"NSStoryboardMainMenu"];
    if ([menu isKindOfClass:[NSString class]] && [menu length]) {
        NSDictionary *nibs = [_info objectForKey:@"NSViewControllerIdentifiersToNibNames"];
        NSString *nibName = [nibs isKindOfClass:[NSDictionary class]] ? [nibs objectForKey:menu] : nil;
        NSArray *top = [self _loadNib:[nibName isKindOfClass:[NSString class]] ? nibName : menu owner:NSApp];
        if (!top)
            fprintf(stderr, "ferry: the main storyboard's menu couldn't be loaded\n");
        for (id o in top) /* the app delegate and the rest stay, as the main nib's do */
            [o retain];
    }
    id first = [self instantiateInitialController];
    if ([first isKindOfClass:[NSWindowController class]]) {
        [first retain]; /* kept, as the shown window is */
        [first showWindow:nil];
    } else if ([first isKindOfClass:[NSViewController class]]) {
        NSWindow *w = [[NSWindow windowWithContentViewController:first] retain];
        [w makeKeyAndOrderFront:nil];
    }
}
@end

void ALoadMainStoryboard(void)
{
    @try {
        NSStoryboard *s = [NSStoryboard mainStoryboard];
        if (s)
            [s _loadForApplication];
        else
            fprintf(stderr, "ferry: the app's main storyboard couldn't be found\n");
    } @catch (NSException *e) {
        fprintf(stderr, "ferry: the app's main storyboard couldn't be loaded: %s\n", [[e reason] UTF8String]);
    }
}
