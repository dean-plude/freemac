/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSDocumentController. Ferry's own code, written from
 * Apple's public NSDocumentController documentation, its document-based
 * app programming guide and its description of the Info.plist keys; no
 * Apple code or headers were used. The first controller made, of whatever
 * class (an app's own subclass in its nib, say), is the shared one. The
 * types come from CFBundleDocumentTypes: each entry's LSItemContentTypes
 * (or its CFBundleTypeName) name the types, CFBundleTypeExtensions (or the
 * extensions the type declarations give) the file names, CFBundleTypeRole
 * whether the app edits or only views them, and NSDocumentClass the
 * NSDocument subclass that holds them. The Recent Documents list is kept
 * in the user's defaults (and given to the desktop's recent files when
 * there's a display) and fills the Open Recent menu: the menu a nib names
 * _NSRecentDocumentsMenu, or the one holding Clear Menu. Built without
 * ARC. */
#import "AInternal.h"

static NSDocumentController *shared;
static NSMenu *recent_menu;    /* not retained: the main menu keeps it */
static NSString *const kRecentKey = @"FerryRecentDocuments";

void ANoteRecentDocumentsMenu(NSMenu *menu)
{
    recent_menu = menu;
    [shared _fillRecentMenu];
}

/* What one name in CFBundleDocumentTypes stands for. */
@interface ADocumentType : NSObject {
  @public
    NSString *name, *displayName, *className, *role;
    NSArray *extensions;
}
@end
@implementation ADocumentType
- (void)dealloc
{
    [name release];
    [displayName release];
    [className release];
    [role release];
    [extensions release];
    [super dealloc];
}
- (BOOL)edits { return [role isEqualToString:@"Editor"]; }
- (BOOL)reads { return [role isEqualToString:@"Editor"] || [role isEqualToString:@"Viewer"]; }
@end

/* The extensions a type declaration (exported or imported) gives a type. */
static NSArray *declared_extensions(NSDictionary *info, NSString *uti)
{
    for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ]) {
        for (NSDictionary *d in info[key]) {
            if (![d isKindOfClass:[NSDictionary class]] || ![d[@"UTTypeIdentifier"] isEqual:uti])
                continue;
            id e = d[@"UTTypeTagSpecification"][@"public.filename-extension"];
            if ([e isKindOfClass:[NSString class]])
                return @[ e ];
            if ([e isKindOfClass:[NSArray class]])
                return e;
        }
    }
    return nil;
}

static NSArray *parse_types(void)
{
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSMutableArray *types = [NSMutableArray array];
    id list = info[@"CFBundleDocumentTypes"];
    if (![list isKindOfClass:[NSArray class]])
        return types;
    for (NSDictionary *d in list) {
        if (![d isKindOfClass:[NSDictionary class]])
            continue;
        NSString *typeName = [d[@"CFBundleTypeName"] isKindOfClass:[NSString class]] ? d[@"CFBundleTypeName"] : nil;
        NSArray *utis = [d[@"LSItemContentTypes"] isKindOfClass:[NSArray class]] ? d[@"LSItemContentTypes"] : nil;
        NSArray *names = [utis count] ? utis : typeName ? @[ typeName ] : @[];
        NSMutableArray *exts = [NSMutableArray array];
        for (NSString *e in d[@"CFBundleTypeExtensions"])
            if ([e isKindOfClass:[NSString class]])
                [exts addObject:e];
        for (NSString *n in names) {
            if (![n isKindOfClass:[NSString class]])
                continue;
            ADocumentType *t = [[[ADocumentType alloc] init] autorelease];
            t->name = [n copy];
            t->displayName = [typeName ?: n copy];
            t->className = [d[@"NSDocumentClass"] isKindOfClass:[NSString class]] ? [d[@"NSDocumentClass"] copy] : nil;
            t->role = [d[@"CFBundleTypeRole"] isKindOfClass:[NSString class]] ? [d[@"CFBundleTypeRole"] copy]
                                                                               : [@"Editor" copy];
            NSMutableArray *mine = [[exts mutableCopy] autorelease];
            if (utis) {
                for (NSString *e in declared_extensions(info, n) ?: AExtensionsForType(n) ?: @[])
                    if ([e isKindOfClass:[NSString class]] && ![mine containsObject:e])
                        [mine addObject:e];
            }
            t->extensions = [mine copy];
            [types addObject:t];
        }
    }
    return types;
}

@implementation NSDocumentController {
    NSMutableArray *_documents;
    NSArray *_types;
    NSMutableArray *_recent;
    NSTimeInterval _autosaveDelay;
    NSUInteger _untitled;
}

+ (id)sharedDocumentController
{
    if (!shared)
        [[[NSDocumentController alloc] init] release];   /* becomes the shared one, and stays */
    return shared;
}
+ (NSDocumentController *)_existingSharedController { return shared; }

- (instancetype)init
{
    if ((self = [super init])) {
        _documents = [[NSMutableArray alloc] init];
        _autosaveDelay = 30;
        if (!shared)
            shared = [self retain];   /* kept for good */
        [self _fillRecentMenu];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder { return [self init]; }
- (void)encodeWithCoder:(NSCoder *)coder {}

- (void)dealloc
{
    if (shared == self)
        shared = nil;
    [_documents release];
    [_types release];
    [_recent release];
    [super dealloc];
}

/* ---- documents ---- */

- (NSArray *)documents { return [[_documents copy] autorelease]; }
- (void)addDocument:(NSDocument *)document
{
    if (document && ![_documents containsObject:document]) {
        [_documents addObject:document];
        if ([document respondsToSelector:@selector(_startPresenting)])
            [document _startPresenting];
    }
}
- (void)removeDocument:(NSDocument *)document
{
    if (document && [_documents indexOfObjectIdenticalTo:document] != NSNotFound) {
        if ([document respondsToSelector:@selector(_stopPresenting)])
            [document _stopPresenting];
        [_documents removeObjectIdenticalTo:document];
    }
}
- (id)documentForURL:(NSURL *)url
{
    NSString *want = [[url path] stringByStandardizingPath];
    for (NSDocument *d in _documents)
        if (want && [[[[d fileURL] path] stringByStandardizingPath] isEqualToString:want])
            return d;
    return nil;
}
- (id)documentForWindow:(NSWindow *)window
{
    id doc = [[window windowController] document];
    return [_documents containsObject:doc] ? doc : nil;
}
- (id)currentDocument
{
    return [self documentForWindow:[NSApp mainWindow]] ?: [self documentForWindow:[NSApp keyWindow]];
}
- (NSString *)currentDirectory
{
    NSURL *u = [[self currentDocument] fileURL];
    if ([u isFileURL])
        return [[u path] stringByDeletingLastPathComponent];
    NSString *docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    BOOL dir = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:docs isDirectory:&dir] && dir ? docs : NSHomeDirectory();
}
- (BOOL)hasEditedDocuments
{
    for (NSDocument *d in _documents)
        if ([d isDocumentEdited])
            return YES;
    return NO;
}
- (NSUInteger)_nextUntitledNumber { return ++_untitled; }

/* ---- types ---- */

- (NSArray *)_types
{
    if (!_types)
        _types = [parse_types() retain];
    return _types;
}
- (ADocumentType *)_type:(NSString *)name
{
    for (ADocumentType *t in [self _types])
        if ([t->name isEqualToString:name])
            return t;
    for (ADocumentType *t in [self _types])
        if ([t->name caseInsensitiveCompare:name] == NSOrderedSame || [t->displayName isEqualToString:name])
            return t;
    return nil;
}
- (NSArray *)_typesForClass:(Class)cls editorsOnly:(BOOL)editors
{
    NSMutableArray *names = [NSMutableArray array];
    for (ADocumentType *t in [self _types]) {
        Class c = t->className ? NSClassFromString(t->className) : Nil;
        if (c == cls && (editors ? [t edits] : [t reads]) && ![names containsObject:t->name])
            [names addObject:t->name];
    }
    return names;
}
- (NSArray *)documentClassNames
{
    NSMutableArray *names = [NSMutableArray array];
    for (ADocumentType *t in [self _types])
        if (t->className && ![names containsObject:t->className])
            [names addObject:t->className];
    return names;
}
- (NSString *)defaultType
{
    for (ADocumentType *t in [self _types])
        if ([t edits] && t->className && NSClassFromString(t->className))
            return t->name;
    return nil;
}
- (Class)documentClassForType:(NSString *)type
{
    ADocumentType *t = [self _type:type];
    return t && t->className ? NSClassFromString(t->className) : Nil;
}
- (NSString *)displayNameForType:(NSString *)type { return [self _type:type] ? [self _type:type]->displayName : type; }
- (NSArray *)fileExtensionsFromType:(NSString *)type
{
    ADocumentType *t = [self _type:type];
    return t ? t->extensions : AExtensionsForType(type);
}
- (NSString *)typeFromFileExtension:(NSString *)ext
{
    ADocumentType *any = nil;
    for (int pass = 0; pass < 2; pass++)   /* the types the app edits first */
        for (ADocumentType *t in [self _types]) {
            if (pass == 0 && ![t edits])
                continue;
            for (NSString *e in t->extensions) {
                if ([e caseInsensitiveCompare:ext] == NSOrderedSame)
                    return t->name;
                if ([e isEqualToString:@"*"] && !any)
                    any = t;
            }
        }
    return any ? any->name : nil;
}
- (NSString *)typeForContentsOfURL:(NSURL *)url error:(NSError **)error
{
    NSString *type = [self typeFromFileExtension:[[url path] pathExtension]];
    if (!type && error) {
        NSString *app = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"] ?: @"This app";
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
            NSLocalizedDescriptionKey : [NSString stringWithFormat:@"The document “%@” couldn’t be "
                                                                   @"opened. %@ can’t open files of this kind.",
                                                                   [[url path] lastPathComponent], app],
            NSURLErrorKey : url ?: [NSNull null],
        }];
    }
    return type;
}

/* ---- making documents ---- */

- (NSError *)_noClassError:(NSString *)type
{
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{
        NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No document class is set for the type “%@”.",
                                                               type ?: @""]
    }];
}

- (id)makeUntitledDocumentOfType:(NSString *)type error:(NSError **)error
{
    Class cls = [self documentClassForType:type];
    if (!cls) {
        if (error)
            *error = [self _noClassError:type];
        return nil;
    }
    return [[[cls alloc] initWithType:type error:error] autorelease];
}
- (id)makeDocumentWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    Class cls = [self documentClassForType:type];
    if (!cls) {
        if (error)
            *error = [self _noClassError:type];
        return nil;
    }
    return [[[cls alloc] initWithContentsOfURL:url ofType:type error:error] autorelease];
}
- (id)makeDocumentForURL:(NSURL *)url withContentsOfURL:(NSURL *)contents ofType:(NSString *)type
                   error:(NSError **)error
{
    Class cls = [self documentClassForType:type];
    if (!cls) {
        if (error)
            *error = [self _noClassError:type];
        return nil;
    }
    return [[[cls alloc] initForURL:url withContentsOfURL:contents ofType:type error:error] autorelease];
}

- (id)openUntitledDocumentAndDisplay:(BOOL)display error:(NSError **)error
{
    NSDocument *doc = [self makeUntitledDocumentOfType:[self defaultType] error:error];
    if (!doc)
        return nil;
    [self addDocument:doc];
    if (display) {
        [doc makeWindowControllers];
        [doc showWindows];
    }
    return doc;
}
- (IBAction)newDocument:(id)sender
{
    NSError *error = nil;
    if (![self openUntitledDocumentAndDisplay:YES error:&error] && error)
        [self presentError:error];
}

/* ---- opening ---- */

- (NSArray *)_openPanelExtensions
{
    NSMutableArray *exts = [NSMutableArray array];
    for (ADocumentType *t in [self _types]) {
        if (![t reads])
            continue;
        if (![t->extensions count] || [t->extensions containsObject:@"*"])
            return nil;   /* any file */
        for (NSString *e in t->extensions)
            if (![exts containsObject:e])
                [exts addObject:e];
    }
    return [exts count] ? exts : nil;
}
- (NSOpenPanel *)_openPanel
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
    [panel setCanChooseFiles:YES];
    [panel setDirectoryURL:[NSURL fileURLWithPath:[self currentDirectory]]];
    return panel;
}
- (NSInteger)runModalOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray *)types
{
    [panel setAllowedFileTypes:types];
    return [panel runModal];
}
- (NSArray *)URLsFromRunningOpenPanel
{
    NSOpenPanel *panel = [self _openPanel];
    return [self runModalOpenPanel:panel forTypes:[self _openPanelExtensions]] == NSModalResponseOK ? [panel URLs]
                                                                                                    : nil;
}
- (void)beginOpenPanel:(NSOpenPanel *)panel forTypes:(NSArray *)types completionHandler:(void (^)(NSInteger))handler
{
    [panel setAllowedFileTypes:types];
    [panel beginWithCompletionHandler:handler];
}
- (void)beginOpenPanelWithCompletionHandler:(void (^)(NSArray<NSURL *> *))handler
{
    NSOpenPanel *panel = [self _openPanel];
    void (^h)(NSArray<NSURL *> *) = [[handler copy] autorelease];
    [self beginOpenPanel:panel forTypes:[self _openPanelExtensions] completionHandler:^(NSInteger r) {
        if (h)
            h(r == NSModalResponseOK ? [panel URLs] : nil);
    }];
}

- (void)_openURLs:(NSArray *)urls
{
    for (NSURL *u in urls)
        [self openDocumentWithContentsOfURL:u display:YES
                          completionHandler:^(NSDocument *d, BOOL already, NSError *error) {
                              if (!d && error &&
                                  !([[error domain] isEqualToString:NSCocoaErrorDomain] &&
                                    [error code] == NSUserCancelledError))
                                  [self presentError:error];
                          }];
}

/* An app that replaced the older, modal calls gets them. */
- (IBAction)openDocument:(id)sender
{
    Class base = [NSDocumentController class];
    if ([self methodForSelector:@selector(URLsFromRunningOpenPanel)] !=
            [base instanceMethodForSelector:@selector(URLsFromRunningOpenPanel)] ||
        [self methodForSelector:@selector(runModalOpenPanel:forTypes:)] !=
            [base instanceMethodForSelector:@selector(runModalOpenPanel:forTypes:)]) {
        [self _openURLs:[self URLsFromRunningOpenPanel]];
        return;
    }
    [self beginOpenPanelWithCompletionHandler:^(NSArray *urls) {
        [self _openURLs:urls];
    }];
}

- (id)_openURL:(NSURL *)url display:(BOOL)display alreadyOpen:(BOOL *)already error:(NSError **)error
{
    NSDocument *doc = [self documentForURL:url];
    if (doc) {
        *already = YES;
        if (display)
            [doc showWindows];
        return doc;
    }
    *already = NO;
    NSString *type = [self typeForContentsOfURL:url error:error];
    if (!type)
        return nil;
    doc = [self makeDocumentWithContentsOfURL:url ofType:type error:error];
    if (!doc)
        return nil;
    [self addDocument:doc];
    [self noteNewRecentDocument:doc];
    if (display) {
        [doc makeWindowControllers];
        [doc showWindows];
    }
    return doc;
}
- (void)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display
                    completionHandler:(void (^)(NSDocument *, BOOL, NSError *))handler
{
    NSError *error = nil;
    BOOL already = NO;
    NSDocument *doc;
    if ([self methodForSelector:@selector(openDocumentWithContentsOfURL:display:error:)] !=
        [NSDocumentController instanceMethodForSelector:@selector(openDocumentWithContentsOfURL:display:error:)]) {
        doc = [self openDocumentWithContentsOfURL:url display:display error:&error];
    } else {
        doc = [self _openURL:url display:display alreadyOpen:&already error:&error];
    }
    if (handler)
        handler(doc, already, doc ? nil : error);
}
- (id)openDocumentWithContentsOfURL:(NSURL *)url display:(BOOL)display error:(NSError **)error
{
    BOOL already = NO;
    return [self _openURL:url display:display alreadyOpen:&already error:error];
}
- (id)openDocumentWithContentsOfFile:(NSString *)path display:(BOOL)display
{
    __block NSDocument *result = nil;
    [self openDocumentWithContentsOfURL:[NSURL fileURLWithPath:path] display:display
                      completionHandler:^(NSDocument *d, BOOL already, NSError *error) {
                          result = d;
                      }];
    return result;
}

/* ---- closing ---- */

/* The documents still to ask, and who to tell at the end. */
- (void)_closeNext:(NSMutableDictionary *)state
{
    NSMutableArray *left = state[@"left"];
    while ([left count] && ![_documents containsObject:[left firstObject]])
        [left removeObjectAtIndex:0];
    if (![left count]) {
        [self _finishClosing:state all:YES];
        return;
    }
    NSDocument *doc = [left firstObject];
    [state retain];
    [doc canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(_document:shouldCloseInTurn:contextInfo:)
                          contextInfo:state];
}
- (void)_document:(NSDocument *)doc shouldCloseInTurn:(BOOL)shouldClose contextInfo:(void *)context
{
    NSMutableDictionary *state = [(id)context autorelease];
    if (!shouldClose) {
        [self _finishClosing:state all:NO];
        return;
    }
    [state[@"left"] removeObjectIdenticalTo:doc];
    [doc close];
    [self _closeNext:state];
}
- (void)_finishClosing:(NSMutableDictionary *)state all:(BOOL)all
{
    id delegate = [state[@"delegate"] nonretainedObjectValue];
    SEL sel = NSSelectorFromString(state[@"selector"]);
    void *context = [state[@"context"] pointerValue];
    if (delegate && sel)
        ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, sel, self, all, context);
}
- (NSMutableDictionary *)_stateFor:(NSArray *)docs delegate:(id)delegate selector:(SEL)sel context:(void *)context
{
    return [NSMutableDictionary dictionaryWithDictionary:@{
        @"left" : [[docs mutableCopy] autorelease],
        @"delegate" : [NSValue valueWithNonretainedObject:delegate],
        @"selector" : sel ? NSStringFromSelector(sel) : @"",
        @"context" : [NSValue valueWithPointer:context],
    }];
}

- (void)closeAllDocumentsWithDelegate:(id)delegate didCloseAllSelector:(SEL)selector contextInfo:(void *)context
{
    [self _closeNext:[self _stateFor:_documents delegate:delegate selector:selector context:context]];
}

- (void)reviewUnsavedDocumentsWithAlertTitle:(NSString *)title cancellable:(BOOL)cancellable delegate:(id)delegate
                        didReviewAllSelector:(SEL)selector contextInfo:(void *)context
{
    /* all the edited documents are gone through (those that autosave in
     * place are autosaved without asking); the review is offered when two
     * or more of them would ask */
    NSMutableArray *edited = [NSMutableArray array];
    NSUInteger asking = 0;
    for (NSDocument *d in _documents)
        if ([d isDocumentEdited]) {
            [edited addObject:d];
            if (![d _closesWithoutAsking])
                asking++;
        }
    NSMutableDictionary *state = [self _stateFor:edited delegate:delegate selector:selector context:context];
    if (asking < 2) {
        [self _closeNext:state];
        return;
    }
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText:title ?: [NSString stringWithFormat:@"You have %lu documents with unsaved changes. Do you want "
                                                          @"to review these changes before quitting?",
                                                          (unsigned long)asking]];
    [a setInformativeText:@"If you don’t review your documents, all your changes will be lost."];
    [a addButtonWithTitle:@"Review Changes…"];
    if (cancellable)
        [a addButtonWithTitle:@"Cancel"];
    [a addButtonWithTitle:@"Discard Changes"];
    NSModalResponse r = [a runModal];
    if (r == NSAlertFirstButtonReturn)
        [self _closeNext:state];
    else
        [self _finishClosing:state all:!(cancellable && r == NSAlertSecondButtonReturn)];
}

- (IBAction)saveAllDocuments:(id)sender
{
    for (NSDocument *d in [[_documents copy] autorelease])
        if ([d isDocumentEdited])
            [d saveDocumentWithDelegate:nil didSaveSelector:NULL contextInfo:NULL];
}

/* ---- the Recent Documents list ---- */

- (NSMutableArray *)_recent
{
    if (!_recent) {
        _recent = [[NSMutableArray alloc] init];
        for (NSString *p in [[NSUserDefaults standardUserDefaults] arrayForKey:kRecentKey])
            if ([p isKindOfClass:[NSString class]] && [p isAbsolutePath])
                [_recent addObject:[NSURL fileURLWithPath:p]];
    }
    return _recent;
}
- (void)_saveRecent
{
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *u in _recent)
        [paths addObject:[u path]];
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:kRecentKey];
    [self _fillRecentMenu];
}
- (NSUInteger)maximumRecentDocumentCount
{
    id limit = [[NSUserDefaults standardUserDefaults] objectForKey:@"NSRecentDocumentsLimit"];
    return limit ? (NSUInteger)MAX(0, [limit integerValue]) : 10;
}
- (NSArray *)recentDocumentURLs { return [[[self _recent] copy] autorelease]; }
- (void)noteNewRecentDocument:(NSDocument *)document
{
    if ([[document fileURL] isFileURL])
        [self noteNewRecentDocumentURL:[document fileURL]];
}
- (void)noteNewRecentDocumentURL:(NSURL *)url
{
    if (![url isFileURL])
        return;
    NSURL *u = [NSURL fileURLWithPath:[[url path] stringByStandardizingPath]];
    NSMutableArray *recent = [self _recent];
    for (NSURL *old in [[recent copy] autorelease])
        if ([[old path] isEqualToString:[u path]])
            [recent removeObject:old];
    [recent insertObject:u atIndex:0];
    while ([recent count] > [self maximumRecentDocumentCount])
        [recent removeLastObject];
    [self _saveRecent];
    if (ADisplayAvailable()) {
        GtkRecentManager *m = gtk_recent_manager_get_default();
        if (m)
            gtk_recent_manager_add_item(m, [[u absoluteString] UTF8String]);
    }
}
- (IBAction)clearRecentDocuments:(id)sender
{
    [[self _recent] removeAllObjects];
    [self _saveRecent];
}

static NSMenu *find_recent_menu(NSMenu *menu)
{
    for (NSMenuItem *item in [menu itemArray]) {
        if ([item action] == @selector(clearRecentDocuments:))
            return menu;
        NSMenu *found = [item submenu] ? find_recent_menu([item submenu]) : nil;
        if (found)
            return found;
    }
    return nil;
}

/* The recent files, newest first, then Clear Menu. */
- (void)_fillRecentMenu
{
    NSMenu *menu = recent_menu ?: find_recent_menu([NSApp mainMenu]);
    if (!menu)
        return;
    NSMenuItem *clear = nil;
    for (NSMenuItem *item in [menu itemArray])
        if ([item action] == @selector(clearRecentDocuments:))
            clear = [[item retain] autorelease];
    [menu removeAllItems];
    for (NSURL *u in [self _recent]) {
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:[[u path] lastPathComponent]
                                                       action:@selector(_openRecentDocument:) keyEquivalent:@""]
            autorelease];
        [item setTarget:self];
        [item setRepresentedObject:u];
        [menu addItem:item];
    }
    if ([[self _recent] count])
        [menu addItem:[NSMenuItem separatorItem]];
    if (!clear) {
        clear = [[[NSMenuItem alloc] initWithTitle:@"Clear Menu" action:@selector(clearRecentDocuments:)
                                     keyEquivalent:@""] autorelease];
    }
    [menu addItem:clear];
}

- (void)_openRecentDocument:(NSMenuItem *)sender
{
    NSURL *u = [sender representedObject];
    if ([u isKindOfClass:[NSURL class]])
        [self _openURLs:@[ u ]];
}

- (NSTimeInterval)autosavingDelay { return _autosaveDelay; }
- (void)setAutosavingDelay:(NSTimeInterval)delay { _autosaveDelay = delay; }

/* ---- errors ---- */

- (NSError *)willPresentError:(NSError *)error { return error; }
- (BOOL)presentError:(NSError *)error { return [NSApp presentError:[self willPresentError:error]]; }
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)selector contextInfo:(void *)context
{
    [NSApp presentError:[self willPresentError:error] modalForWindow:window delegate:delegate
        didPresentSelector:selector contextInfo:context];
}

/* ---- validation ---- */

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    SEL a = [item action];
    if (a == @selector(newDocument:))
        return [self defaultType] != nil;
    if (a == @selector(clearRecentDocuments:))
        return [[self _recent] count] > 0;
    if (a == @selector(saveAllDocuments:))
        return [self hasEditedDocuments];
    if (a == @selector(_openRecentDocument:)) {
        NSURL *u = [(id)item respondsToSelector:@selector(representedObject)] ? [(id)item representedObject] : nil;
        return [u isFileURL] && [[NSFileManager defaultManager] fileExistsAtPath:[u path]];
    }
    return YES;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return [self validateUserInterfaceItem:item]; }
@end
