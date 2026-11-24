/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSWindowController and NSViewController. Our own code,
 * written from Apple's public documentation. Each controller loads its nib
 * the first time its window or view is asked for, as File's Owner, keeps
 * the nib's top-level objects alive, and takes its place in the responder
 * chain: a window's next responder is its window controller, and a view
 * controller comes between its view and the view's superview. A window
 * controller of a document shows the document's name and edited state in
 * its window, and when its window closes, closes the document too if it
 * was the document's last window (or shouldCloseDocument is set), else
 * leaves the document. Built without ARC. */
#import "AInternal.h"

/* What a window controller tells its document (an NSDocument, or an
 * app's own class) about loading its nib. */
@interface NSObject (FerryDocumentNibLoading)
- (void)windowControllerWillLoadNib:(NSWindowController *)wc;
- (void)windowControllerDidLoadNib:(NSWindowController *)wc;
- (NSString *)displayName;
- (NSArray *)windowControllers;
- (void)removeWindowController:(NSWindowController *)wc;
- (void)close;
- (BOOL)isDocumentEdited;
- (NSURL *)fileURL;
- (BOOL)_isClosing;
@end

/* Loads a nib with owner as File's Owner; nil if it isn't there. */
static NSArray *load_nib(NSString *name, NSString *path, NSBundle *bundle, id owner)
{
    NSNib *nib = path ? [[NSNib alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]]
                      : [[NSNib alloc] initWithNibNamed:name bundle:bundle ?: [NSBundle mainBundle]];
    NSArray *top = nil;
    BOOL ok = [nib instantiateWithOwner:owner topLevelObjects:&top];
    [nib release];
    return ok ? (top ?: @[]) : nil;
}

/* ---- NSWindowController --------------------------------------------------------------- */

@implementation NSWindowController {
    NSWindow *_window;
    NSString *_nibName, *_nibPath, *_autosaveName;
    id _owner;               /* not retained */
    id _document;            /* not retained, as on a Mac */
    NSArray *_topLevel;
    NSViewController *_contentViewController;
    BOOL _cascades, _closesWithDocument, _loading;
}

- (instancetype)init { return [self initWithWindow:nil]; }
- (instancetype)initWithWindow:(NSWindow *)window
{
    if ((self = [super init])) {
        _cascades = YES;
        [self setWindow:window];
    }
    return self;
}
- (instancetype)initWithWindowNibName:(NSNibName)name { return [self initWithWindowNibName:name owner:nil]; }
- (instancetype)initWithWindowNibName:(NSNibName)name owner:(id)owner
{
    if ((self = [self initWithWindow:nil])) {
        _nibName = [name copy];
        _owner = owner ?: self;
    }
    return self;
}
- (instancetype)initWithWindowNibPath:(NSString *)path owner:(id)owner
{
    if ((self = [self initWithWindow:nil])) {
        _nibPath = [path copy];
        _nibName = [[[path lastPathComponent] stringByDeletingPathExtension] copy];
        _owner = owner ?: self;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self initWithWindow:nil]) && [coder containsValueForKey:@"NSWindowNibName"])
        _nibName = [[coder decodeObjectForKey:@"NSWindowNibName"] copy];
    if (_nibName)
        _owner = self;
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_nibName forKey:@"NSWindowNibName"]; }

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if ([_window nextResponder] == self)
        [_window setNextResponder:nil];
    if ([_window _windowController] == self)
        [_window _setWindowController:nil];
    [_window release];
    [_nibName release];
    [_nibPath release];
    [_autosaveName release];
    [_topLevel release];
    [_contentViewController release];
    [super dealloc];
}

- (NSString *)windowNibName { return _nibName; }
- (NSString *)windowNibPath
{
    if (_nibPath)
        return _nibPath;
    return _nibName ? [[NSBundle bundleForClass:[_owner class]] pathForResource:_nibName ofType:@"nib"] : nil;
}
- (id)owner { return _owner; }
- (BOOL)isWindowLoaded { return _window != nil; }

- (void)windowWillLoad {}
- (void)windowDidLoad {}

/* The nib connects its window to the owner's "window" outlet. */
- (void)loadWindow
{
    if (_window || !_nibName)
        return;
    NSBundle *bundle = [NSBundle bundleForClass:[_owner class]];
    NSArray *top = load_nib(_nibName, _nibPath, bundle, _owner);
    if (!top && bundle != [NSBundle mainBundle])
        top = load_nib(_nibName, nil, [NSBundle mainBundle], _owner);
    if (!top) {
        fprintf(stderr, "ferry: a window controller couldn't load its window nib \"%s\"\n", [_nibName UTF8String]);
        return;
    }
    [_topLevel release];
    _topLevel = [top retain];
    if (!_window)
        fprintf(stderr, "ferry: the nib \"%s\" didn't connect a window to its window controller\n",
                [_nibName UTF8String]);
}

- (NSWindow *)window
{
    if (!_window && _nibName && !_loading) {
        _loading = YES;
        [self windowWillLoad];
        if ([_document respondsToSelector:@selector(windowControllerWillLoadNib:)])
            [_document windowControllerWillLoadNib:self];
        [self loadWindow];
        if (_window) {
            if (_autosaveName)
                [_window setFrameAutosaveName:_autosaveName];
            [self _showDocumentState];
            [self windowDidLoad];
            if ([_document respondsToSelector:@selector(windowControllerDidLoadNib:)])
                [_document windowControllerDidLoadNib:self];
        }
        _loading = NO;
    }
    return _window;
}

- (void)setWindow:(NSWindow *)window
{
    if (window == _window)
        return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_window)
        [nc removeObserver:self name:NSWindowWillCloseNotification object:_window];
    if ([_window nextResponder] == self)
        [_window setNextResponder:nil];
    if ([_window _windowController] == self)
        [_window _setWindowController:nil];
    [window retain];
    [_window release];
    _window = window;
    if (_window) {
        [_window _setWindowController:self];
        if (![_window nextResponder])
            [_window setNextResponder:self];
        [nc addObserver:self selector:@selector(_windowWillClose:) name:NSWindowWillCloseNotification object:_window];
        if (!_loading)
            [self _showDocumentState];
    }
}

/* The document's last window closing closes the document. */
- (void)_windowWillClose:(NSNotification *)n
{
    id doc = _document;
    if (!doc || ([doc respondsToSelector:@selector(_isClosing)] && [doc _isClosing]))
        return;
    [[self retain] autorelease];
    NSArray *controllers = [doc respondsToSelector:@selector(windowControllers)] ? [doc windowControllers] : nil;
    BOOL last = YES;
    for (NSWindowController *wc in controllers)
        if (wc != self && [[wc window] isVisible])
            last = NO;
    if ((_closesWithDocument || last) && [doc respondsToSelector:@selector(close)])
        [doc close];
    else if ([doc respondsToSelector:@selector(removeWindowController:)])
        [doc removeWindowController:self];
}

- (void)_showDocumentState
{
    if (!_document || !_window)
        return;
    [self synchronizeWindowTitleWithDocumentName];
    if ([_document respondsToSelector:@selector(isDocumentEdited)])
        [_window setDocumentEdited:[_document isDocumentEdited]];
}

/* Errors go to the document, then up to the application. */
- (BOOL)presentError:(NSError *)error
{
    if (_document && [_document respondsToSelector:@selector(presentError:)])
        return [_document presentError:[self willPresentError:error]];
    return [super presentError:error];
}

- (IBAction)showWindow:(id)sender
{
    NSWindow *w = [self window];
    if ([w isKindOfClass:[NSPanel class]] && [(NSPanel *)w becomesKeyOnlyIfNeeded])
        [w orderFront:sender];
    else
        [w makeKeyAndOrderFront:sender];
}
- (void)close { [_window close]; }
- (void)dismissController:(id)sender { [self close]; }

- (NSString *)windowFrameAutosaveName { return _autosaveName ?: @""; }
- (void)setWindowFrameAutosaveName:(NSString *)name
{
    [_autosaveName release];
    _autosaveName = [name copy];
    if (_window)
        [_window setFrameAutosaveName:name];
}
- (BOOL)shouldCascadeWindows { return _cascades; }
- (void)setShouldCascadeWindows:(BOOL)f { _cascades = f; }
- (BOOL)shouldCloseDocument { return _closesWithDocument; }
- (void)setShouldCloseDocument:(BOOL)f { _closesWithDocument = f; }

- (id)document { return _document; }
- (void)setDocument:(id)document
{
    _document = document;
    [self _showDocumentState];
}
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)name { return name; }
- (void)synchronizeWindowTitleWithDocumentName
{
    if (!_document || !_window || ![_document respondsToSelector:@selector(displayName)])
        return;
    [_window setTitle:[self windowTitleForDocumentDisplayName:[_document displayName]]];
    NSURL *url = [_document respondsToSelector:@selector(fileURL)] ? [_document fileURL] : nil;
    [_window setRepresentedURL:[url isFileURL] ? url : nil];
}
- (void)setDocumentEdited:(BOOL)edited { [_window setDocumentEdited:edited]; }

- (NSViewController *)contentViewController { return _contentViewController; }
- (void)setContentViewController:(NSViewController *)vc
{
    [vc retain];
    [_contentViewController release];
    _contentViewController = vc;
    [[self window] setContentViewController:vc];
}
- (NSStoryboard *)storyboard { return nil; }
@end

/* ---- NSViewController ------------------------------------------------------------------- */

@implementation NSViewController {
    NSView *_view;
    NSString *_nibName, *_title;
    NSBundle *_bundle;
    id _represented;
    NSArray *_topLevel;
    NSMutableArray *_children;
    NSViewController *_parent;       /* not retained */
    NSSize _preferred;
    BOOL _loading, _loaded;
}

- (instancetype)init { return [self initWithNibName:nil bundle:nil]; }
- (instancetype)initWithNibName:(NSNibName)name bundle:(NSBundle *)bundle
{
    if ((self = [super init])) {
        _nibName = [name copy];
        _bundle = [bundle retain];
        _children = [[NSMutableArray alloc] init];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *name = [coder containsValueForKey:@"NSNibName"] ? [coder decodeObjectForKey:@"NSNibName"] : nil;
    if ((self = [self initWithNibName:[name isKindOfClass:[NSString class]] ? name : nil bundle:nil])) {
        if ([coder containsValueForKey:@"NSView"])
            [self setView:[coder decodeObjectForKey:@"NSView"]];
        if ([coder containsValueForKey:@"NSTitle"])
            _title = [[coder decodeObjectForKey:@"NSTitle"] copy];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_nibName forKey:@"NSNibName"];
    [coder encodeObject:_title forKey:@"NSTitle"];
}

- (void)dealloc
{
    if ([_view _viewController] == self)
        [_view _setViewController:nil];
    [_view release];
    [_nibName release];
    [_title release];
    [_bundle release];
    [_represented release];
    [_topLevel release];
    for (NSViewController *c in _children)
        c->_parent = nil;
    [_children release];
    [super dealloc];
}

/* With no nib name, a nib named after the class is used if there is one. */
- (NSNibName)nibName
{
    if (_nibName)
        return _nibName;
    NSString *cls = NSStringFromClass([self class]);
    NSRange dot = [cls rangeOfString:@"." options:NSBackwardsSearch];   /* a Swift module prefix */
    if (dot.location != NSNotFound)
        cls = [cls substringFromIndex:dot.location + 1];
    NSBundle *b = [self nibBundle];
    if ([b pathForResource:cls ofType:@"nib"])
        return cls;
    return nil;
}
- (NSBundle *)nibBundle { return _bundle ?: [NSBundle bundleForClass:[self class]]; }

- (void)loadView
{
    NSString *name = [self nibName];
    if (!name) {
        fprintf(stderr, "ferry: a %s has no view and no nib to load one from\n", object_getClassName(self));
        return;
    }
    NSArray *top = load_nib(name, nil, [self nibBundle], self);
    if (!top && [self nibBundle] != [NSBundle mainBundle])
        top = load_nib(name, nil, [NSBundle mainBundle], self);
    if (!top) {
        fprintf(stderr, "ferry: a %s couldn't load its nib \"%s\"\n", object_getClassName(self), [name UTF8String]);
        return;
    }
    [_topLevel release];
    _topLevel = [top retain];
    if (!_view)
        fprintf(stderr, "ferry: the nib \"%s\" didn't connect a view to its %s\n", [name UTF8String],
                object_getClassName(self));
}

- (NSView *)view
{
    if (!_loaded && !_loading) {
        _loading = YES;
        if (!_view)
            [self loadView];
        _loaded = YES;
        _loading = NO;
        if (_view)
            [self viewDidLoad];
    }
    return _view;
}
- (void)setView:(NSView *)view
{
    if (view == _view)
        return;
    if ([_view _viewController] == self)
        [_view _setViewController:nil];
    [view retain];
    [_view release];
    _view = view;
    [_view _setViewController:self];
    if (!_loading && _view)
        _loaded = YES;
}
- (BOOL)isViewLoaded { return _loaded && _view; }
- (void)loadViewIfNeeded { [self view]; }
- (NSView *)viewIfLoaded { return _loaded ? _view : nil; }

- (void)viewDidLoad {}
- (void)viewWillAppear {}
- (void)viewDidAppear {}
- (void)viewWillDisappear {}
- (void)viewDidDisappear {}
- (void)updateViewConstraints {}
- (void)viewWillLayout {}
- (void)viewDidLayout {}

- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)t
{
    [_title release];
    _title = [t copy];
}
- (id)representedObject { return _represented; }
- (void)setRepresentedObject:(id)o
{
    [o retain];
    [_represented release];
    _represented = o;
}
- (NSSize)preferredContentSize { return _preferred; }
- (void)setPreferredContentSize:(NSSize)s { _preferred = s; }

- (NSArray *)childViewControllers { return [[_children copy] autorelease]; }
- (void)setChildViewControllers:(NSArray *)children
{
    for (NSViewController *c in [[_children copy] autorelease])
        [c removeFromParentViewController];
    for (NSViewController *c in children)
        [self addChildViewController:c];
}
- (void)addChildViewController:(NSViewController *)child { [self insertChildViewController:child atIndex:_children.count]; }
- (void)insertChildViewController:(NSViewController *)child atIndex:(NSInteger)index
{
    if (!child || child->_parent == self)
        return;
    [child retain];
    [child removeFromParentViewController];
    [_children insertObject:child atIndex:(NSUInteger)MIN(index, (NSInteger)_children.count)];
    child->_parent = self;
    [child release];
}
- (void)removeChildViewControllerAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)_children.count)
        return;
    ((NSViewController *)_children[(NSUInteger)index])->_parent = nil;
    [_children removeObjectAtIndex:(NSUInteger)index];
}
- (void)removeFromParentViewController
{
    NSViewController *p = _parent;
    if (!p)
        return;
    NSUInteger i = [p->_children indexOfObjectIdenticalTo:self];
    if (i != NSNotFound)
        [p removeChildViewControllerAtIndex:(NSInteger)i];
}
- (NSViewController *)parentViewController { return _parent; }
- (NSViewController *)presentingViewController { return nil; }
- (NSArray *)presentedViewControllers { return @[]; }

/* Shown as a window of its own: Ferry has no sheets or popovers yet. */
- (void)_presentInWindow:(NSViewController *)vc
{
    NSWindow *w = [NSWindow windowWithContentViewController:vc];
    [w makeKeyAndOrderFront:nil];
}
- (void)presentViewControllerAsSheet:(NSViewController *)vc
{
    AWarnOnce("sheets (a view controller presented as a sheet gets a window of its own)");
    [self _presentInWindow:vc];
}
- (void)presentViewControllerAsModalWindow:(NSViewController *)vc { [self _presentInWindow:vc]; }
- (void)presentViewController:(NSViewController *)vc asPopoverRelativeToRect:(NSRect)rect ofView:(NSView *)view
                preferredEdge:(NSRectEdge)edge behavior:(NSInteger)behavior
{
    AWarnOnce("popovers (a view controller presented as a popover gets a window of its own)");
    [self _presentInWindow:vc];
}
- (void)dismissViewController:(NSViewController *)vc { [[[vc viewIfLoaded] window] close]; }
- (void)dismissController:(id)sender { [[[self viewIfLoaded] window] close]; }
- (NSStoryboard *)storyboard { return nil; }
@end
