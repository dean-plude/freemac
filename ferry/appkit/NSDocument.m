/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSDocument. Ferry's own code, written from Apple's public
 * NSDocument documentation and its document-based app programming guide;
 * no Apple code or headers were used. A document reads its file as a URL,
 * a file wrapper or data (each step calling the next, as documented, and
 * the calls of Mac OS X 10.3 and before when the app's subclass overrides
 * those instead), writes it safely (to a file beside it, then moved into
 * place), keeps a change count that its undo manager's notifications move
 * and its windows show with the edited dot, runs the Save panel for an
 * untitled document or Save As, and asks before closing with unsaved
 * changes (Save, Cancel, Don't Save, in a sheet on its window). Autosaving
 * and versions are left out: autosavesInPlace answers NO and the autosave
 * calls save nothing. Built without ARC. */
#import "AInternal.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>

@interface NSWindow (FerryDocumentClose)
- (void)_document:(NSDocument *)document shouldClose:(BOOL)shouldClose contextInfo:(void *)context;
@end

/* Whether obj's class replaced NSDocument's own method for sel. */
static BOOL overrides(id obj, SEL sel)
{
    return [obj methodForSelector:sel] != [NSDocument instanceMethodForSelector:sel];
}

static NSError *doc_error(NSInteger code, NSString *description, NSURL *url)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (description)
        info[NSLocalizedDescriptionKey] = description;
    if (url)
        info[NSURLErrorKey] = url;
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

static NSString *app_name(void)
{
    NSBundle *b = [NSBundle mainBundle];
    return [b objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [b objectForInfoDictionaryKey:@"CFBundleName"]
                                                                  ?: [[NSProcessInfo processInfo] processName];
}

/* What a close or save that waits on a sheet has to call when it ends. */
@interface ADocumentCallback : NSObject {
  @public
    id delegate;
    SEL selector;
    void *context;
}
@end
@implementation ADocumentCallback
@end

static ADocumentCallback *callback(id delegate, SEL selector, void *context)
{
    ADocumentCallback *c = [[[ADocumentCallback alloc] init] autorelease];
    c->delegate = delegate;
    c->selector = selector;
    c->context = context;
    return c;
}
/* the shape of a did-save, should-close or did-present call: (object, BOOL, context) */
static void call_back(ADocumentCallback *c, id object, BOOL flag)
{
    if (c->delegate && c->selector)
        ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(c->delegate, c->selector, object, flag, c->context);
}

@implementation NSDocument {
    NSURL *_fileURL, *_autosavedURL;
    NSString *_fileType, *_displayName, *_lastPanelType;
    NSDate *_modified;
    NSUndoManager *_undo;
    BOOL _hasUndo, _draft, _closing;
    NSInteger _changes;        /* changes since the last save; 0 is clean */
    NSUInteger _untitled;      /* "Untitled n", once shown */
    NSMutableArray *_controllers;
}

/* ---- types ---- */

+ (NSArray *)readableTypes
{
    return [[NSDocumentController sharedDocumentController] _typesForClass:self editorsOnly:NO];
}
+ (NSArray *)writableTypes
{
    return [[NSDocumentController sharedDocumentController] _typesForClass:self editorsOnly:YES];
}
+ (BOOL)isNativeType:(NSString *)type { return [[self writableTypes] containsObject:type]; }
+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)type { return NO; }
+ (BOOL)autosavesInPlace { return NO; }
+ (BOOL)autosavesDrafts { return NO; }
+ (BOOL)preservesVersions { return NO; }

/* ---- making one ---- */

- (instancetype)init
{
    if ((self = [super init])) {
        _hasUndo = YES;
        _controllers = [[NSMutableArray alloc] init];
    }
    return self;
}

- (instancetype)initWithType:(NSString *)type error:(NSError **)error
{
    if ((self = [self init]))
        [self setFileType:type];
    return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    return [self initForURL:url withContentsOfURL:url ofType:type error:error];
}

- (instancetype)initForURL:(NSURL *)url withContentsOfURL:(NSURL *)contents ofType:(NSString *)type
                     error:(NSError **)error
{
    if (!(self = [self init]))
        return nil;
    [self setFileType:type];
    [self setFileURL:url];
    NSError *e = nil;
    if (![self readFromURL:contents ofType:type error:&e]) {
        if (error)
            *error = e ?: doc_error(NSFileReadUnknownError,
                                    [NSString stringWithFormat:@"The document “%@” couldn’t be opened.",
                                                               [[contents path] lastPathComponent]],
                                    contents);
        [self release];
        return nil;
    }
    [self _noteFileDate:contents];
    [_undo removeAllActions];
    _changes = 0;
    if (url && ![[url path] isEqualToString:[contents path]])
        [self updateChangeCount:NSChangeReadOtherContents];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSWindowController *wc in _controllers)
        if ([wc document] == self)
            [wc setDocument:nil];
    [_fileURL release];
    [_autosavedURL release];
    [_fileType release];
    [_displayName release];
    [_lastPanelType release];
    [_modified release];
    [_undo release];
    [_controllers release];
    [super dealloc];
}

/* ---- what it is ---- */

- (NSURL *)fileURL { return _fileURL; }
- (void)setFileURL:(NSURL *)url
{
    url = [url copy];
    [_fileURL release];
    _fileURL = url;
    [self _synchronizeTitles];
}
- (NSString *)fileType { return _fileType; }
- (void)setFileType:(NSString *)type
{
    type = [type copy];
    [_fileType release];
    _fileType = type;
}
- (NSDate *)fileModificationDate { return _modified; }
- (void)setFileModificationDate:(NSDate *)date
{
    date = [date copy];
    [_modified release];
    _modified = date;
}
- (void)_noteFileDate:(NSURL *)url
{
    if ([url isFileURL])
        [self setFileModificationDate:[[[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL]
                                          fileModificationDate]];
}
- (NSString *)fileName { return [_fileURL path]; }
- (void)setFileName:(NSString *)name { [self setFileURL:name ? [NSURL fileURLWithPath:name] : nil]; }
- (BOOL)isDraft { return _draft; }
- (void)setDraft:(BOOL)draft { _draft = draft; }
- (BOOL)isEntireFileLoaded { return YES; }
- (BOOL)isLocked { return NO; }
- (BOOL)isInViewingMode { return NO; }
- (BOOL)_isClosing { return _closing; }

- (NSString *)defaultDraftName { return @"Untitled"; }
- (NSString *)displayName
{
    if (_displayName)
        return _displayName;
    if (_fileURL)
        return [[_fileURL path] lastPathComponent];
    if (!_untitled)
        _untitled = [[NSDocumentController sharedDocumentController] _nextUntitledNumber];
    return _untitled > 1 ? [NSString stringWithFormat:@"%@ %lu", [self defaultDraftName], (unsigned long)_untitled]
                         : [self defaultDraftName];
}
- (void)setDisplayName:(NSString *)name
{
    name = [name copy];
    [_displayName release];
    _displayName = name;
    [self _synchronizeTitles];
}
- (void)_synchronizeTitles
{
    for (NSWindowController *wc in _controllers)
        [wc synchronizeWindowTitleWithDocumentName];
}

/* ---- the change count and the undo manager ---- */

- (BOOL)isDocumentEdited { return _changes != 0; }
- (BOOL)hasUnautosavedChanges { return [self isDocumentEdited]; }

- (void)updateChangeCount:(NSDocumentChangeType)change
{
    BOOL was = [self isDocumentEdited];
    switch (change & ~(NSDocumentChangeType)NSChangeDiscardable) {
    case NSChangeDone:
    case NSChangeRedone:
        _changes++;
        break;
    case NSChangeUndone:
        _changes--;
        break;
    case NSChangeCleared:
        _changes = 0;
        break;
    case NSChangeReadOtherContents:
        _changes = NSIntegerMax / 2;   /* edited until it's saved */
        break;
    default:   /* NSChangeAutosaved */
        break;
    }
    if (was != [self isDocumentEdited] || change == NSChangeCleared)
        for (NSWindowController *wc in _controllers)
            [wc setDocumentEdited:[self isDocumentEdited]];
}

- (id)changeCountTokenForSaveOperation:(NSSaveOperationType)operation { return @(_changes); }
- (void)updateChangeCountWithToken:(id)token forSaveOperation:(NSSaveOperationType)operation
{
    if (operation == NSSaveToOperation || operation == NSAutosaveElsewhereOperation)
        return;
    NSInteger was = [token integerValue];
    if (_changes == was) {
        [self updateChangeCount:NSChangeCleared];
    } else {
        _changes -= was;   /* what was changed while it saved stays a change */
        for (NSWindowController *wc in _controllers)
            [wc setDocumentEdited:[self isDocumentEdited]];
    }
}

- (BOOL)hasUndoManager { return _hasUndo; }
- (void)setHasUndoManager:(BOOL)flag
{
    _hasUndo = flag;
    if (!flag)
        [self setUndoManager:nil];
}
- (NSUndoManager *)undoManager
{
    if (!_undo && _hasUndo) {
        NSUndoManager *u = [[NSUndoManager alloc] init];
        [self setUndoManager:u];
        [u release];
    }
    return _undo;
}
- (void)setUndoManager:(NSUndoManager *)undo
{
    if (undo == _undo)
        return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_undo) {
        [nc removeObserver:self name:NSUndoManagerDidCloseUndoGroupNotification object:_undo];
        [nc removeObserver:self name:NSUndoManagerDidUndoChangeNotification object:_undo];
        [nc removeObserver:self name:NSUndoManagerDidRedoChangeNotification object:_undo];
    }
    [undo retain];
    [_undo release];
    _undo = undo;
    if (undo) {
        [nc addObserver:self selector:@selector(_undoGroupClosed:) name:NSUndoManagerDidCloseUndoGroupNotification
                 object:undo];
        [nc addObserver:self selector:@selector(_undone:) name:NSUndoManagerDidUndoChangeNotification object:undo];
        [nc addObserver:self selector:@selector(_redone:) name:NSUndoManagerDidRedoChangeNotification object:undo];
    }
}
- (void)_undoGroupClosed:(NSNotification *)n
{
    NSUndoManager *u = [n object];
    if ([u isUndoing] || [u isRedoing] || [u groupingLevel] > 0)
        return;
    BOOL discardable = [[n userInfo][NSUndoManagerGroupIsDiscardableKey] boolValue];
    [self updateChangeCount:discardable ? NSChangeDone | NSChangeDiscardable : NSChangeDone];
}
- (void)_undone:(NSNotification *)n { [self updateChangeCount:NSChangeUndone]; }
- (void)_redone:(NSNotification *)n { [self updateChangeCount:NSChangeRedone]; }

/* ---- reading ---- */

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    if (overrides(self, @selector(readFromFile:ofType:)) && [url isFileURL])
        return [self readFromFile:[url path] ofType:type];
    if (overrides(self, @selector(readFromURL:ofType:)))
        return [self readFromURL:url ofType:type];
    NSFileWrapper *w = [[[NSFileWrapper alloc] initWithURL:url options:0 error:error] autorelease];
    if (!w)
        return NO;
    return [self readFromFileWrapper:w ofType:type error:error];
}

- (BOOL)readFromFileWrapper:(NSFileWrapper *)wrapper ofType:(NSString *)type error:(NSError **)error
{
    if (overrides(self, @selector(loadFileWrapperRepresentation:ofType:)))
        return [self loadFileWrapperRepresentation:wrapper ofType:type];
    if (![wrapper isRegularFile]) {
        if (error)
            *error = doc_error(NSFileReadCorruptFileError,
                               [NSString stringWithFormat:@"%@ can’t open a folder as a document.", app_name()],
                               nil);
        return NO;
    }
    return [self readFromData:[wrapper regularFileContents] ofType:type error:error];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
    if (overrides(self, @selector(loadDataRepresentation:ofType:)))
        return [self loadDataRepresentation:data ofType:type];
    fprintf(stderr, "ferry: %s reads no documents: it overrides none of NSDocument's reading methods\n",
            [NSStringFromClass([self class]) UTF8String]);
    if (error)
        *error = doc_error(NSFeatureUnsupportedError, nil, nil);
    return NO;
}

- (BOOL)revertToContentsOfURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    [_undo removeAllActions];
    if (![self readFromURL:url ofType:type error:error])
        return NO;
    [self setFileType:type];
    [self _noteFileDate:url];
    [self updateChangeCount:NSChangeCleared];
    return YES;
}

/* the calls before Mac OS X 10.4: each one calls the newer one, which
 * calls back only when the subclass overrides the old one */
- (BOOL)readFromFile:(NSString *)path ofType:(NSString *)type
{
    return [self readFromURL:[NSURL fileURLWithPath:path] ofType:type error:NULL];
}
- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)type
{
    NSFileWrapper *w = [[[NSFileWrapper alloc] initWithURL:url options:0 error:NULL] autorelease];
    return w && [self readFromFileWrapper:w ofType:type error:NULL];
}
- (BOOL)loadDataRepresentation:(NSData *)data ofType:(NSString *)type
{
    return [self readFromData:data ofType:type error:NULL];
}
- (BOOL)loadFileWrapperRepresentation:(NSFileWrapper *)wrapper ofType:(NSString *)type
{
    if (![wrapper isRegularFile])
        return NO;
    return [self readFromData:[wrapper regularFileContents] ofType:type error:NULL];
}
- (NSData *)dataRepresentationOfType:(NSString *)type { return [self dataOfType:type error:NULL]; }
- (NSFileWrapper *)fileWrapperRepresentationOfType:(NSString *)type { return [self fileWrapperOfType:type error:NULL]; }
- (BOOL)writeToFile:(NSString *)path ofType:(NSString *)type
{
    NSFileWrapper *w = [self fileWrapperOfType:type error:NULL];
    return [w writeToURL:[NSURL fileURLWithPath:path] options:0 originalContentsURL:nil error:NULL];
}
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type
{
    NSFileWrapper *w = [self fileWrapperOfType:type error:NULL];
    return [w writeToURL:url options:0 originalContentsURL:nil error:NULL];
}

/* ---- writing ---- */

- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
    if (overrides(self, @selector(dataRepresentationOfType:)))
        return [self dataRepresentationOfType:type];
    fprintf(stderr, "ferry: %s writes no documents: it overrides none of NSDocument's writing methods\n",
            [NSStringFromClass([self class]) UTF8String]);
    if (error)
        *error = doc_error(NSFeatureUnsupportedError, nil, nil);
    return nil;
}

- (NSFileWrapper *)fileWrapperOfType:(NSString *)type error:(NSError **)error
{
    if (overrides(self, @selector(fileWrapperRepresentationOfType:)))
        return [self fileWrapperRepresentationOfType:type];
    NSData *data = [self dataOfType:type error:error];
    if (!data)
        return nil;
    return [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type error:(NSError **)error
{
    if (overrides(self, @selector(writeToFile:ofType:)) && [url isFileURL])
        return [self writeToFile:[url path] ofType:type];
    if (overrides(self, @selector(writeToURL:ofType:)))
        return [self writeToURL:url ofType:type];
    NSFileWrapper *w = [self fileWrapperOfType:type error:error];
    if (!w)
        return NO;
    return [w writeToURL:url options:0 originalContentsURL:nil error:error];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
    originalContentsURL:(NSURL *)original error:(NSError **)error
{
    return [self writeToURL:url ofType:type error:error];
}

- (NSDictionary *)fileAttributesToWriteToURL:(NSURL *)url ofType:(NSString *)type
                            forSaveOperation:(NSSaveOperationType)operation originalContentsURL:(NSURL *)original
                                       error:(NSError **)error
{
    NSDictionary *old = original ? [[NSFileManager defaultManager] attributesOfItemAtPath:[original path] error:NULL]
                                 : nil;
    return old[NSFilePosixPermissions] ? @{NSFilePosixPermissions : old[NSFilePosixPermissions]} : @{};
}
- (BOOL)keepBackupFile { return NO; }

/* Written beside the file first, then moved over it, so a failed save
 * leaves the old file as it was. */
- (BOOL)writeSafelyToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
                   error:(NSError **)error
{
    if (![url isFileURL]) {
        if (error)
            *error = doc_error(NSFileWriteUnknownError, nil, url);
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [[url path] stringByStandardizingPath];
    NSString *dir = [path stringByDeletingLastPathComponent];
    BOOL existed = [fm fileExistsAtPath:path];
    NSURL *original = existed ? [NSURL fileURLWithPath:path] : nil;
    NSString *temp = [dir stringByAppendingPathComponent:
                              [NSString stringWithFormat:@".%@.ferry-save-%d", [path lastPathComponent], (int)getpid()]];
    [fm removeItemAtPath:temp error:NULL];
    NSURL *tempURL = [NSURL fileURLWithPath:temp];
    if (![self writeToURL:tempURL ofType:type forSaveOperation:operation originalContentsURL:original error:error]) {
        [fm removeItemAtPath:temp error:NULL];
        return NO;
    }
    NSDictionary *attrs = [self fileAttributesToWriteToURL:url ofType:type forSaveOperation:operation
                                       originalContentsURL:original error:NULL];
    if (attrs[NSFilePosixPermissions])
        chmod([temp fileSystemRepresentation], (mode_t)[attrs[NSFilePosixPermissions] unsignedIntegerValue]);
    NSString *backup = existed && [self keepBackupFile] ? [path stringByAppendingString:@"~"] : nil;
    BOOL dir_ = NO;
    if (existed && ([fm fileExistsAtPath:path isDirectory:&dir_] && dir_)) {
        /* a package: rename() can't replace a folder that has things in it */
        NSString *aside = backup ?: [temp stringByAppendingString:@"-old"];
        [fm removeItemAtPath:aside error:NULL];
        if (![fm moveItemAtPath:path toPath:aside error:error]) {
            [fm removeItemAtPath:temp error:NULL];
            return NO;
        }
        if (![fm moveItemAtPath:temp toPath:path error:error]) {
            [fm moveItemAtPath:aside toPath:path error:NULL];
            return NO;
        }
        if (!backup)
            [fm removeItemAtPath:aside error:NULL];
        return YES;
    }
    if (backup) {
        [fm removeItemAtPath:backup error:NULL];
        [fm copyItemAtPath:path toPath:backup error:NULL];
    }
    if (rename([temp fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        [fm removeItemAtPath:temp error:NULL];
        if (error)
            *error = doc_error(NSFileWriteUnknownError,
                               [NSString stringWithFormat:@"The document “%@” couldn’t be saved.",
                                                          [path lastPathComponent]],
                               url);
        return NO;
    }
    return YES;
}

- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)operation
{
    return [[self class] writableTypes];
}
- (NSString *)fileNameExtensionForType:(NSString *)type saveOperation:(NSSaveOperationType)operation
{
    for (NSString *e in [[NSDocumentController sharedDocumentController] fileExtensionsFromType:type])
        if (![e isEqualToString:@"*"])
            return e;
    return nil;
}

/* ---- saving ---- */

- (BOOL)saveToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
            error:(NSError **)error
{
    id token = [self changeCountTokenForSaveOperation:operation];
    if (![self writeSafelyToURL:url ofType:type forSaveOperation:operation error:error])
        return NO;
    if (operation == NSSaveOperation || operation == NSSaveAsOperation || operation == NSAutosaveInPlaceOperation) {
        [self setFileType:type];
        [self setFileURL:url];
        [self _noteFileDate:url];
        _draft = NO;
        [self updateChangeCountWithToken:token forSaveOperation:operation];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocument:self];
    }
    return YES;
}

- (void)saveToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
    completionHandler:(void (^)(NSError *))handler
{
    NSError *error = nil;
    BOOL ok = [self saveToURL:url ofType:type forSaveOperation:operation error:&error];
    if (handler)
        handler(ok ? nil : (error ?: doc_error(NSFileWriteUnknownError, nil, url)));
}

- (void)saveToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)operation
             delegate:(id)delegate didSaveSelector:(SEL)selector contextInfo:(void *)context
{
    ADocumentCallback *cb = [callback(delegate, selector, context) retain];
    [self saveToURL:url ofType:type forSaveOperation:operation completionHandler:^(NSError *error) {
        if (error && !([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSUserCancelledError)) {
            NSWindow *w = [self windowForSheet];
            if (w) {
                [self presentError:error modalForWindow:w delegate:self
                    didPresentSelector:@selector(_didPresentSaveError:context:) contextInfo:cb];
                return;   /* the callback is made once the error has been seen */
            }
            [self presentError:error];
        }
        call_back(cb, self, error == nil);
        [cb release];
    }];
}
- (void)_didPresentSaveError:(BOOL)recovered context:(void *)context
{
    ADocumentCallback *cb = context;
    call_back(cb, self, NO);
    [cb release];
}

- (void)saveDocumentWithDelegate:(id)delegate didSaveSelector:(SEL)selector contextInfo:(void *)context
{
    if (_fileURL && !_draft)
        [self saveToURL:_fileURL ofType:_fileType ?: [[NSDocumentController sharedDocumentController] defaultType]
             forSaveOperation:NSSaveOperation delegate:delegate didSaveSelector:selector contextInfo:context];
    else
        [self runModalSavePanelForSaveOperation:NSSaveOperation delegate:delegate didSaveSelector:selector
                                    contextInfo:context];
}

- (IBAction)saveDocument:(id)sender { [self saveDocumentWithDelegate:nil didSaveSelector:NULL contextInfo:NULL]; }
- (IBAction)saveDocumentAs:(id)sender
{
    [self runModalSavePanelForSaveOperation:NSSaveAsOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
}
- (IBAction)saveDocumentTo:(id)sender
{
    [self runModalSavePanelForSaveOperation:NSSaveToOperation delegate:nil didSaveSelector:NULL contextInfo:NULL];
}

- (BOOL)prepareSavePanel:(NSSavePanel *)panel { return YES; }
- (BOOL)shouldRunSavePanelWithAccessoryView { return YES; }
- (BOOL)fileNameExtensionWasHiddenInLastRunSavePanel { return NO; }
- (NSString *)fileTypeFromLastRunSavePanel { return _lastPanelType; }

- (void)runModalSavePanelForSaveOperation:(NSSaveOperationType)operation delegate:(id)delegate
                          didSaveSelector:(SEL)selector contextInfo:(void *)context
{
    NSArray *types = [self writableTypesForSaveOperation:operation];
    NSString *type = _fileType && [types containsObject:_fileType] ? _fileType : [types firstObject] ?: _fileType;
    NSString *ext = [self fileNameExtensionForType:type saveOperation:operation];
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *name = _fileURL ? [[[_fileURL path] lastPathComponent] stringByDeletingPathExtension] : [self displayName];
    [panel setNameFieldStringValue:ext ? [name stringByAppendingPathExtension:ext] : name];
    if (ext)
        [panel setAllowedFileTypes:@[ ext ]];
    [panel setAllowsOtherFileTypes:YES];
    if ([_fileURL isFileURL])
        [panel setDirectoryURL:[NSURL fileURLWithPath:[[_fileURL path] stringByDeletingLastPathComponent]]];
    ADocumentCallback *cb = [callback(delegate, selector, context) retain];
    if (![self prepareSavePanel:panel]) {
        call_back(cb, self, NO);
        [cb release];
        return;
    }
    [self retain];
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
        NSURL *url = r == NSModalResponseOK ? [panel URL] : nil;
        if (!url) {
            call_back(cb, self, NO);
        } else {
            if (ext && ![[url pathExtension] length])
                url = [url URLByAppendingPathExtension:ext];
            [_lastPanelType release];
            _lastPanelType = [type copy];
            [self saveToURL:url ofType:type forSaveOperation:operation delegate:cb->delegate
                 didSaveSelector:cb->selector contextInfo:cb->context];
        }
        [cb release];
        [self autorelease];
    };
    NSWindow *w = [self windowForSheet];
    if (w)
        [panel beginSheetModalForWindow:w completionHandler:done];
    else
        done([panel runModal]);
}

- (IBAction)revertDocumentToSaved:(id)sender
{
    if (!_fileURL)
        return;
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText:[NSString stringWithFormat:@"Do you want to revert to the most recently saved version of the "
                                                 @"document “%@”?",
                                                 [self displayName]]];
    [a setInformativeText:@"Your current changes will be lost."];
    [a addButtonWithTitle:@"Revert"];
    [a addButtonWithTitle:@"Cancel"];
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn)
            return;
        NSError *error = nil;
        if (![self revertToContentsOfURL:_fileURL ofType:_fileType error:&error] && error)
            [self presentError:error];
    };
    NSWindow *w = [self windowForSheet];
    if (w)
        [a beginSheetModalForWindow:w completionHandler:done];
    else
        done([a runModal]);
}

- (NSDocument *)duplicateAndReturnError:(NSError **)error
{
    NSString *temp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                                                 [NSString stringWithFormat:@"ferry-duplicate-%d-%p", (int)getpid(), self]];
    NSURL *url = [NSURL fileURLWithPath:temp];
    if (![self writeToURL:url ofType:_fileType error:error])
        return nil;
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    NSDocument *copy = [dc makeDocumentForURL:nil withContentsOfURL:url ofType:_fileType error:error];
    [[NSFileManager defaultManager] removeItemAtPath:temp error:NULL];
    if (!copy)
        return nil;
    [copy updateChangeCount:NSChangeReadOtherContents];
    [dc addDocument:copy];
    [copy makeWindowControllers];
    [copy showWindows];
    return copy;
}
- (IBAction)duplicateDocument:(id)sender
{
    NSError *error = nil;
    if (![self duplicateAndReturnError:&error] && error)
        [self presentError:error];
}
- (IBAction)renameDocument:(id)sender { AWarnOnce("renaming a document from its title bar"); }
- (IBAction)moveDocument:(id)sender { AWarnOnce("moving a document from its title bar"); }
- (IBAction)lockDocument:(id)sender { AWarnOnce("locking documents"); }
- (IBAction)unlockDocument:(id)sender { AWarnOnce("locking documents"); }
- (IBAction)browseDocumentVersions:(id)sender { AWarnOnce("document versions"); }
- (IBAction)printDocument:(id)sender { AWarnOnce("printing documents"); }
- (IBAction)runPageLayout:(id)sender { AWarnOnce("page setup for documents"); }

/* ---- autosaving: left out ---- */

- (NSURL *)autosavedContentsFileURL { return _autosavedURL; }
- (void)setAutosavedContentsFileURL:(NSURL *)url
{
    url = [url copy];
    [_autosavedURL release];
    _autosavedURL = url;
}
- (NSString *)autosavingFileType { return _fileType; }
- (BOOL)autosavingIsImplicitlyCancellable { return YES; }
- (void)autosaveWithImplicitCancellability:(BOOL)cancellable completionHandler:(void (^)(NSError *))handler
{
    if (handler)
        handler(nil);
}
- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)selector contextInfo:(void *)context
{
    call_back(callback(delegate, selector, context), self, NO);
}
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)error { return YES; }
- (void)scheduleAutosaving {}

/* ---- closing ---- */

- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)context
{
    ADocumentCallback *cb = callback(delegate, selector, context);
    if (![self isDocumentEdited]) {
        call_back(cb, self, YES);
        return;
    }
    [cb retain];
    [self retain];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText:[NSString stringWithFormat:@"Do you want to save the changes made to the document “%@”?",
                                                 [self displayName]]];
    [a setInformativeText:@"Your changes will be lost if you don’t save them."];
    [a addButtonWithTitle:@"Save"];
    [a addButtonWithTitle:@"Cancel"];
    [a addButtonWithTitle:@"Don’t Save"];
    void (^done)(NSModalResponse) = ^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn) {
            [self saveDocumentWithDelegate:self didSaveSelector:@selector(_document:didSaveToClose:contextInfo:)
                               contextInfo:[cb retain]];
        } else {
            call_back(cb, self, r == NSAlertThirdButtonReturn);
        }
        [cb release];
        [self autorelease];
    };
    NSWindow *w = [self windowForSheet];
    if (w && ![w attachedSheet])
        [a beginSheetModalForWindow:w completionHandler:done];
    else
        done([a runModal]);
}
- (void)_document:(NSDocument *)doc didSaveToClose:(BOOL)saved contextInfo:(void *)context
{
    ADocumentCallback *cb = context;
    call_back(cb, self, saved);
    [cb release];
}

- (void)shouldCloseWindowController:(NSWindowController *)controller delegate:(id)delegate
                shouldCloseSelector:(SEL)selector contextInfo:(void *)context
{
    BOOL last = YES;
    for (NSWindowController *wc in _controllers)
        if (wc != controller && [[wc window] isVisible])
            last = NO;
    if ([controller shouldCloseDocument] || last)
        [self canCloseDocumentWithDelegate:delegate shouldCloseSelector:selector contextInfo:context];
    else
        call_back(callback(delegate, selector, context), self, YES);
}

- (void)close
{
    if (_closing)
        return;
    _closing = YES;
    [self retain];
    for (NSWindowController *wc in [[_controllers copy] autorelease]) {
        [wc close];
        [self removeWindowController:wc];
    }
    [[NSDocumentController sharedDocumentController] removeDocument:self];
    [self autorelease];
}

/* ---- windows ---- */

- (NSString *)windowNibName { return nil; }
- (void)makeWindowControllers
{
    NSString *nib = [self windowNibName];
    if (![nib length])
        return;
    NSWindowController *wc = [[NSWindowController alloc] initWithWindowNibName:nib owner:self];
    [self addWindowController:wc];
    [wc release];
}
- (void)windowControllerWillLoadNib:(NSWindowController *)controller {}
- (void)windowControllerDidLoadNib:(NSWindowController *)controller {}

/* The nib's "window" outlet: the window of the controller loading it. */
- (void)setWindow:(NSWindow *)window
{
    NSWindowController *wc = nil;
    for (NSWindowController *c in _controllers)
        if ([c owner] == self && ![c isWindowLoaded])
            wc = c;
    [(wc ?: [_controllers firstObject]) setWindow:window];
}

- (void)addWindowController:(NSWindowController *)controller
{
    if (!controller || [_controllers containsObject:controller])
        return;
    [_controllers addObject:controller];
    if ([controller document] != self)
        [controller setDocument:self];
}
- (void)removeWindowController:(NSWindowController *)controller
{
    if (![_controllers containsObject:controller])
        return;
    [[controller retain] autorelease];
    if ([controller document] == self)
        [controller setDocument:nil];
    [_controllers removeObject:controller];
}
- (NSArray *)windowControllers { return [[_controllers copy] autorelease]; }
- (void)showWindows
{
    for (NSWindowController *wc in [[_controllers copy] autorelease])
        [wc showWindow:self];
}
- (NSWindow *)windowForSheet
{
    for (NSWindowController *wc in _controllers)
        if ([wc isWindowLoaded] && [[wc window] isVisible])
            return [wc window];
    return nil;
}

/* ---- errors ---- */

- (NSError *)willPresentError:(NSError *)error { return error; }
- (BOOL)presentError:(NSError *)error
{
    return [[NSDocumentController sharedDocumentController] presentError:[self willPresentError:error]];
}
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)selector contextInfo:(void *)context
{
    [[NSDocumentController sharedDocumentController] presentError:[self willPresentError:error]
                                                    modalForWindow:window delegate:delegate
                                                didPresentSelector:selector contextInfo:context];
}

/* ---- validation ---- */

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    SEL a = [item action];
    if (a == @selector(revertDocumentToSaved:))
        return _fileURL != nil && [self isDocumentEdited];
    if (a == @selector(saveDocument:))
        return [self isDocumentEdited] || !_fileURL;
    if (a == @selector(renameDocument:) || a == @selector(moveDocument:) || a == @selector(lockDocument:) ||
        a == @selector(unlockDocument:) || a == @selector(browseDocumentVersions:) || a == @selector(printDocument:) ||
        a == @selector(runPageLayout:))
        return NO;
    return YES;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return [self validateUserInterfaceItem:item]; }
@end
