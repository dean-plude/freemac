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
 * changes (Save, Cancel, Don't Save, in a sheet on its window).
 *
 * Autosaving, for a class whose autosavesInPlace answers YES: each change
 * starts a one-shot timer of the document controller's autosavingDelay,
 * and when it fires the document is saved over its own file
 * (NSAutosaveInPlaceOperation) or, while untitled, into the Autosave
 * Information folder (NSAutosaveElsewhereOperation, its URL kept as
 * autosavedContentsFileURL). An autosave leaves the document edited (the
 * title keeps "Edited" until a real save) and only hasUnautosavedChanges
 * goes back to NO. Before its file is first written over, the file as it
 * was last saved is copied aside, which is what Revert To > Last Saved
 * Version (revertDocumentToSaved:) puts back; such a document with a file
 * closes without asking, after an autosave. Versions (preservesVersions,
 * Browse All Versions) are left out. Classes that don't autosave in place
 * are not autosaved at all.
 *
 * Printing: each document keeps its own print info (a copy of the shared
 * one until Page Setup changes it). Print… asks the subclass for a print
 * operation (printOperationWithSettings:error:, which NSDocument itself
 * answers with an error, as on a Mac) and runs it in a sheet on the
 * document's window; Page Setup… runs the page layout there. Built without
 * ARC. */
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

/* A print operation run in a sheet calls this back, which calls the
 * document's delegate as document:didPrint:contextInfo: does. */
@interface ADocumentPrinted : NSObject {
@public
    id document, delegate;
    SEL selector;
    void *context;
}
@end
@implementation ADocumentPrinted
- (void)printOperationDidRun:(NSPrintOperation *)op success:(BOOL)success contextInfo:(void *)unused
{
    if (delegate && selector)
        ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, document, success, context);
    [document release];
    [self release];
}
@end

@implementation NSDocument {
    NSURL *_fileURL, *_autosavedURL;
    NSString *_fileType, *_displayName, *_lastPanelType;
    NSDate *_modified;
    NSUndoManager *_undo;
    BOOL _hasUndo, _draft, _closing;
    NSInteger _changes;        /* changes since the last save; 0 is clean */
    NSUInteger _untitled;      /* "Untitled n", once shown */
    NSMutableArray *_controllers;
    /* autosaving */
    NSInteger _autosavedChanges;     /* _changes as it was last autosaved (or saved) */
    NSTimer *_autosaveTimer;
    BOOL _autosaving, _autosaveCancellable;
    NSURL *_lastSaved;               /* the file as last saved, kept aside once autosaving writes over it */
    NSPrintInfo *_printInfo;
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
    _changes = _autosavedChanges = 0;
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
    [_autosaveTimer invalidate];
    [_autosaveTimer release];
    [_lastSaved release];
    [_printInfo release];
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
- (BOOL)hasUnautosavedChanges { return _changes != _autosavedChanges; }

- (void)updateChangeCount:(NSDocumentChangeType)change
{
    BOOL was = [self isDocumentEdited];
    NSDocumentChangeType kind = change & ~(NSDocumentChangeType)NSChangeDiscardable;
    switch (kind) {
    case NSChangeDone:
    case NSChangeRedone:
        _changes++;
        break;
    case NSChangeUndone:
        _changes--;
        break;
    case NSChangeCleared:
        _changes = _autosavedChanges = 0;
        break;
    case NSChangeReadOtherContents:
        _changes = NSIntegerMax / 2;   /* edited until it's saved */
        break;
    case NSChangeAutosaved:
        _autosavedChanges = _changes;
        break;
    default:
        break;
    }
    if (was != [self isDocumentEdited] || change == NSChangeCleared)
        for (NSWindowController *wc in _controllers)
            [wc setDocumentEdited:[self isDocumentEdited]];
    if (kind != NSChangeCleared && kind != NSChangeAutosaved)
        [self scheduleAutosaving];
}

- (id)changeCountTokenForSaveOperation:(NSSaveOperationType)operation { return @(_changes); }
- (void)updateChangeCountWithToken:(id)token forSaveOperation:(NSSaveOperationType)operation
{
    NSInteger was = [token integerValue];
    if (operation == NSSaveToOperation)
        return;
    if (operation == NSAutosaveElsewhereOperation || operation == NSAutosaveInPlaceOperation) {
        _autosavedChanges = was;   /* still edited: only a save makes it clean */
        return;
    }
    if (_changes == was) {
        [self updateChangeCount:NSChangeCleared];
    } else {
        _changes -= was;   /* what was changed while it saved stays a change */
        _autosavedChanges = 0;
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
    if (operation == NSAutosaveInPlaceOperation && ![self _keepLastSavedVersionOf:url error:error])
        return NO;
    if (operation == NSAutosaveElsewhereOperation &&
        ![[NSFileManager defaultManager] createDirectoryAtPath:[[url path] stringByDeletingLastPathComponent]
                                   withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    if (![self writeSafelyToURL:url ofType:type forSaveOperation:operation error:error])
        return NO;
    switch (operation) {
    case NSSaveOperation:
    case NSSaveAsOperation:
    case NSAutosaveAsOperation:
        [self setFileType:type];
        [self setFileURL:url];
        [self _noteFileDate:url];
        _draft = NO;
        [self updateChangeCountWithToken:token forSaveOperation:operation];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocument:self];
        /* the file is now the last saved version, and the autosaved copy of an untitled one is done with */
        [self _forgetLastSavedVersion];
        [self _removeAutosavedContents];
        break;
    case NSAutosaveInPlaceOperation:
        [self _noteFileDate:url];
        [self updateChangeCountWithToken:token forSaveOperation:operation];
        break;
    case NSAutosaveElsewhereOperation:
        [self setAutosavedContentsFileURL:url];
        [self updateChangeCountWithToken:token forSaveOperation:operation];
        break;
    default:
        break;
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
        /* an autosaved file is put back as it was last saved first */
        if (![self _putBackLastSavedVersion:&error] ||
            ![self revertToContentsOfURL:_fileURL ofType:_fileType error:&error]) {
            if (error)
                [self presentError:error];
        }
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

/* ---- printing ---- */

/* The document's own print info, a copy of the shared one until it is set. */
- (NSPrintInfo *)printInfo
{
    if (!_printInfo)
        _printInfo = [[NSPrintInfo sharedPrintInfo] copy];
    return _printInfo;
}
- (void)setPrintInfo:(NSPrintInfo *)info
{
    if (!info || info == _printInfo)
        return;
    NSPrintInfo *copy = [info copy];
    [_printInfo release];
    _printInfo = copy;
}
- (BOOL)shouldChangePrintInfo:(NSPrintInfo *)info { return YES; }
- (BOOL)preparePageLayout:(NSPageLayout *)layout { return YES; }

/* Page Setup, in a sheet on the document's window when it has one; the
 * print info, as changed, becomes the document's if the user accepts. */
- (void)runModalPageLayoutWithPrintInfo:(NSPrintInfo *)info delegate:(id)delegate didRunSelector:(SEL)selector
                            contextInfo:(void *)context
{
    NSPageLayout *layout = [NSPageLayout pageLayout];
    [self retain];
    void (^done)(NSInteger) = ^(NSInteger r) {
      BOOL accepted = r == NSModalResponseOK;
      if (accepted && [self shouldChangePrintInfo:info])
          [self setPrintInfo:info];
      if (delegate && selector)
          ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, self, accepted, context);
      [self release];
    };
    if (![self preparePageLayout:layout]) {
        done(NSModalResponseCancel);
        return;
    }
    NSWindow *w = [self windowForSheet];
    if (w)
        [layout beginSheetUsingPrintInfo:info onWindow:w completionHandler:done];
    else
        done([layout runModalWithPrintInfo:info]);
}
- (IBAction)runPageLayout:(id)sender
{
    [self runModalPageLayoutWithPrintInfo:[[[self printInfo] copy] autorelease] delegate:nil didRunSelector:NULL
                              contextInfo:NULL];
}

/* A subclass makes the print operation: NSDocument itself has nothing to
 * print, as on a Mac. */
- (NSPrintOperation *)printOperationWithSettings:(NSDictionary *)settings error:(NSError **)error
{
    if (error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFeatureUnsupportedError
                                 userInfo:@{NSLocalizedDescriptionKey : @"This document can't be printed."}];
    return nil;
}

/* In a sheet on the document's window when it has one. */
- (void)runModalPrintOperation:(NSPrintOperation *)op delegate:(id)delegate didRunSelector:(SEL)selector
                   contextInfo:(void *)context
{
    NSWindow *w = [self windowForSheet];
    if (!w) {
        BOOL ok = [op runOperation];
        if (delegate && selector)
            ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, self, ok, context);
        return;
    }
    ADocumentPrinted *done = [[ADocumentPrinted alloc] init];
    done->document = [self retain];
    done->delegate = delegate;
    done->selector = selector;
    done->context = context;
    [op runOperationModalForWindow:w delegate:done didRunSelector:@selector(printOperationDidRun:success:contextInfo:)
                       contextInfo:NULL];
}

- (void)printDocumentWithSettings:(NSDictionary *)settings showPrintPanel:(BOOL)show delegate:(id)delegate
                 didPrintSelector:(SEL)selector contextInfo:(void *)context
{
    NSError *error = nil;
    NSPrintOperation *op = [self printOperationWithSettings:settings ?: @{} error:&error];
    if (!op) {
        if (error)
            [self presentError:error];
        if (delegate && selector)
            ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, self, NO, context);
        return;
    }
    if ([settings count])
        [[[op printInfo] dictionary] addEntriesFromDictionary:settings];
    [op setShowsPrintPanel:show];
    [self runModalPrintOperation:op delegate:delegate didRunSelector:selector contextInfo:context];
}

/* The call of Mac OS X 10.3 and before does nothing, unless the subclass
 * prints there; printDocument: then calls it. */
- (void)printShowingPrintPanel:(BOOL)show {}

- (IBAction)printDocument:(id)sender
{
    if ([[self class] instanceMethodForSelector:@selector(printShowingPrintPanel:)] !=
        [NSDocument instanceMethodForSelector:@selector(printShowingPrintPanel:)])
        [self printShowingPrintPanel:YES];
    else
        [self printDocumentWithSettings:@{} showPrintPanel:YES delegate:nil didPrintSelector:NULL contextInfo:NULL];
}

/* ---- autosaving ---- */

- (NSURL *)autosavedContentsFileURL { return _autosavedURL; }
- (void)setAutosavedContentsFileURL:(NSURL *)url
{
    url = [url copy];
    [_autosavedURL release];
    _autosavedURL = url;
}
- (NSString *)autosavingFileType { return _fileType ?: [[NSDocumentController sharedDocumentController] defaultType]; }
- (BOOL)autosavingIsImplicitlyCancellable { return _autosaving && _autosaveCancellable; }
- (BOOL)checkAutosavingSafetyAndReturnError:(NSError **)error { return YES; }

/* Where autosaved copies of untitled documents, and the last saved
 * versions of autosaved ones, are kept: the Mac's Library/Autosave
 * Information, in freemac's place for the Library. */
static NSString *autosave_folder(void)
{
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    return [lib ?: NSTemporaryDirectory() stringByAppendingPathComponent:@"Autosave Information"];
}
/* A name in that folder no file has yet: "name (what).ext", or with a number. */
static NSURL *autosave_url(NSString *name, NSString *what, NSString *ext)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = autosave_folder();
    name = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByDeletingPathExtension];
    for (NSUInteger n = 1;; n++) {
        NSString *file = n == 1 ? [NSString stringWithFormat:@"%@ (%@)", name, what]
                                : [NSString stringWithFormat:@"%@ (%@ %lu)", name, what, (unsigned long)n];
        if ([ext length])
            file = [file stringByAppendingPathExtension:ext];
        NSString *path = [dir stringByAppendingPathComponent:file];
        if (![fm fileExistsAtPath:path] && ![fm fileExistsAtPath:[path stringByAppendingString:@"~"]])
            return [NSURL fileURLWithPath:path];
    }
}

/* Before autosaving first writes over the file, the file as last saved is
 * copied aside, for Revert To > Last Saved Version. */
- (BOOL)_keepLastSavedVersionOf:(NSURL *)url error:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ((_lastSaved && [fm fileExistsAtPath:[_lastSaved path]]) || ![url isFileURL] || ![fm fileExistsAtPath:[url path]])
        return YES;
    [fm createDirectoryAtPath:autosave_folder() withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *copy = autosave_url([[url path] lastPathComponent], @"Last Saved", [[url path] pathExtension]);
    if (![fm copyItemAtPath:[url path] toPath:[copy path] error:error])
        return NO;
    [_lastSaved release];
    _lastSaved = [copy retain];
    return YES;
}
- (void)_forgetLastSavedVersion
{
    if (_lastSaved)
        [[NSFileManager defaultManager] removeItemAtPath:[_lastSaved path] error:NULL];
    [_lastSaved release];
    _lastSaved = nil;
}
/* Puts the last saved version back over the file, if autosaving wrote over it. */
- (BOOL)_putBackLastSavedVersion:(NSError **)error
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!_lastSaved || ![_fileURL isFileURL] || ![fm fileExistsAtPath:[_lastSaved path]])
        return YES;
    NSString *path = [_fileURL path];
    NSString *temp = [[path stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.ferry-revert-%d", [path lastPathComponent],
                                                                  (int)getpid()]];
    [fm removeItemAtPath:temp error:NULL];
    if (![fm copyItemAtPath:[_lastSaved path] toPath:temp error:error])
        return NO;
    BOOL dir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&dir] && dir)
        [fm removeItemAtPath:path error:NULL];
    if (rename([temp fileSystemRepresentation], [path fileSystemRepresentation]) != 0) {
        [fm removeItemAtPath:temp error:NULL];
        if (error)
            *error = doc_error(NSFileWriteUnknownError,
                               [NSString stringWithFormat:@"The document “%@” couldn’t be reverted.", [self displayName]],
                               _fileURL);
        return NO;
    }
    [self _forgetLastSavedVersion];
    return YES;
}
- (void)_removeAutosavedContents
{
    if (_autosavedURL && ![[[_autosavedURL path] stringByStandardizingPath]
                             isEqualToString:[[_fileURL path] stringByStandardizingPath]])
        [[NSFileManager defaultManager] removeItemAtPath:[_autosavedURL path] error:NULL];
    [self setAutosavedContentsFileURL:nil];
}

/* Saves the changes not yet autosaved: over the document's file, or, for
 * an untitled document, into the Autosave Information folder. *saved says
 * whether anything was written. */
- (NSError *)_autosaveCancellable:(BOOL)cancellable saved:(BOOL *)saved
{
    *saved = NO;
    if (![[self class] autosavesInPlace] || ![self hasUnautosavedChanges] || _autosaving)
        return nil;
    NSError *error = nil;
    if (![self checkAutosavingSafetyAndReturnError:&error])
        return error ?: doc_error(NSFileWriteUnknownError, nil, _fileURL);
    NSString *type = [self autosavingFileType];
    NSURL *url;
    NSSaveOperationType op;
    if (_fileURL && !_draft) {
        url = _fileURL;
        op = NSAutosaveInPlaceOperation;
    } else {
        NSString *ext = [self fileNameExtensionForType:type saveOperation:NSAutosaveElsewhereOperation];
        url = _autosavedURL ?: autosave_url([self displayName], @"Autosaved", ext);
        op = NSAutosaveElsewhereOperation;
    }
    [self retain];
    _autosaving = YES;
    _autosaveCancellable = cancellable;
    BOOL ok = [self saveToURL:url ofType:type forSaveOperation:op error:&error];
    _autosaving = NO;
    [self autorelease];
    if (!ok)
        return error ?: doc_error(NSFileWriteUnknownError, nil, url);
    *saved = YES;
    return nil;
}
- (void)autosaveWithImplicitCancellability:(BOOL)cancellable completionHandler:(void (^)(NSError *))handler
{
    BOOL saved;
    NSError *error = [self _autosaveCancellable:cancellable saved:&saved];
    if (handler)
        handler(error);
}
- (void)autosaveDocumentWithDelegate:(id)delegate didAutosaveSelector:(SEL)selector contextInfo:(void *)context
{
    BOOL saved;
    NSError *error = [self _autosaveCancellable:NO saved:&saved];
    call_back(callback(delegate, selector, context), self, error == nil && (saved || ![self hasUnautosavedChanges]));
}

/* After a change, an autosave in autosavingDelay seconds (none while one
 * is due, and none when the delay is 0). */
- (void)scheduleAutosaving
{
    if (![[self class] autosavesInPlace] || _autosaveTimer || _closing || ![self hasUnautosavedChanges])
        return;
    NSTimeInterval delay = [[NSDocumentController sharedDocumentController] autosavingDelay];
    if (delay <= 0)
        return;
    _autosaveTimer = [[NSTimer scheduledTimerWithTimeInterval:delay target:self
                                                     selector:@selector(_autosaveTimerFired:) userInfo:nil
                                                      repeats:NO] retain];
}
- (void)_autosaveTimerFired:(NSTimer *)timer
{
    [[self retain] autorelease];
    [_autosaveTimer release];
    _autosaveTimer = nil;
    [self autosaveWithImplicitCancellability:YES completionHandler:^(NSError *error) {
        if (error)
            fprintf(stderr, "ferry: autosaving the document “%s” failed: %s\n", [[self displayName] UTF8String],
                    [[error localizedDescription] UTF8String]);
    }];
    [self scheduleAutosaving];   /* for what changed while it saved */
}
- (void)_stopAutosaving
{
    [_autosaveTimer invalidate];
    [_autosaveTimer release];
    _autosaveTimer = nil;
}

/* Revert To > Last Saved Version, for a document that autosaves in place. */
- (IBAction)_revertToLastSavedVersion:(id)sender { [self revertDocumentToSaved:sender]; }

/* ---- closing ---- */

- (void)canCloseDocumentWithDelegate:(id)delegate shouldCloseSelector:(SEL)selector contextInfo:(void *)context
{
    ADocumentCallback *cb = callback(delegate, selector, context);
    if (![self isDocumentEdited]) {
        call_back(cb, self, YES);
        return;
    }
    /* a document that autosaves in place, with a file, is autosaved and
     * closes without asking; if that fails, it asks */
    if ([self _closesWithoutAsking]) {
        BOOL saved;
        NSError *error = [self _autosaveCancellable:NO saved:&saved];
        if (!error) {
            call_back(cb, self, YES);
            return;
        }
        fprintf(stderr, "ferry: autosaving the document “%s” failed: %s\n", [[self displayName] UTF8String],
                [[error localizedDescription] UTF8String]);
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
- (BOOL)_closesWithoutAsking { return [[self class] autosavesInPlace] && _fileURL && !_draft; }
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
    /* no more autosaves; what was kept for them goes */
    [self _stopAutosaving];
    [self _forgetLastSavedVersion];
    [self _removeAutosavedContents];
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

/* The menu of a Revert To item: Last Saved Version, and Browse All
 * Versions (dimmed: versions aren't kept). */
static NSMenu *revert_to_menu(void)
{
    NSMenu *m = [[[NSMenu alloc] initWithTitle:@"Revert To"] autorelease];
    [m addItemWithTitle:@"Last Saved Version" action:@selector(_revertToLastSavedVersion:) keyEquivalent:@""];
    [m addItemWithTitle:@"Browse All Versions…" action:@selector(browseDocumentVersions:) keyEquivalent:@""];
    return m;
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
{
    SEL a = [item action];
    if (a == @selector(revertDocumentToSaved:) || a == @selector(_revertToLastSavedVersion:)) {
        /* for a document that autosaves in place, the File menu's Revert to
         * Saved becomes Revert To, with its menu, as on a Mac */
        if (a == @selector(revertDocumentToSaved:) && [[self class] autosavesInPlace] &&
            [(id)item isKindOfClass:[NSMenuItem class]] && ![(NSMenuItem *)item hasSubmenu]) {
            [(NSMenuItem *)item setTitle:@"Revert To"];
            [(NSMenuItem *)item setSubmenu:revert_to_menu()];
            return YES;   /* an item with a menu stays enabled; its items are validated */
        }
        return _fileURL != nil && [self isDocumentEdited];
    }
    if (a == @selector(saveDocument:))
        return [self isDocumentEdited] || !_fileURL;
    if (a == @selector(renameDocument:) || a == @selector(moveDocument:) || a == @selector(lockDocument:) ||
        a == @selector(unlockDocument:) || a == @selector(browseDocumentVersions:))
        return NO;
    return YES;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return [self validateUserInterfaceItem:item]; }
@end
