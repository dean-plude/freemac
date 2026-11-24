/* SPDX-License-Identifier: GPL-3.0-or-later
 * NSDocument autosaving, with no display, in a home of its own: a class
 * that autosaves in place is autosaved by the timer (the document
 * controller's autosavingDelay after a change) and by
 * autosaveWithImplicitCancellability:completionHandler:, over its own
 * file, staying edited with no unautosaved changes; the file as it was
 * last saved is kept aside and put back by Revert To > Last Saved Version
 * (the File menu item becoming Revert To, with its menu); Save makes it
 * clean; it closes without asking, autosaving first, and so does quitting
 * with two of them; an untitled one is autosaved into Autosave Information
 * and still asks; a class that doesn't autosave in place isn't autosaved,
 * and NSChangeAutosaved and NSChangeCleared move the counts. */
#import <Cocoa/Cocoa.h>

static NSMutableArray *writes;

static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static NSString *shown(NSURL *url)
{
    if (!url)
        return @"(none)";
    NSString *p = [url path], *home = NSHomeDirectory();
    return [p hasPrefix:home] ? [@"~" stringByAppendingString:[p substringFromIndex:[home length]]] : p;
}
static NSString *contents(NSString *path)
{
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return s ? [NSString stringWithFormat:@"\"%@\"", s] : @"(no file)";
}
static const char *operation(NSSaveOperationType op)
{
    switch (op) {
    case NSSaveOperation: return "save";
    case NSSaveAsOperation: return "save as";
    case NSSaveToOperation: return "save to";
    case NSAutosaveElsewhereOperation: return "autosave elsewhere";
    case NSAutosaveInPlaceOperation: return "autosave in place";
    case NSAutosaveAsOperation: return "autosave as";
    }
    return "?";
}
static void dump(void)
{
    if (![writes count])
        printf("  (nothing written)\n");
    for (NSString *s in writes)
        printf("  %s\n", [s UTF8String]);
    [writes removeAllObjects];
}

@interface Note : NSDocument
@property (copy) NSString *text;
@end
@implementation Note
+ (BOOL)autosavesInPlace { return YES; }
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
    self.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return YES;
}
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error { return [self.text dataUsingEncoding:NSUTF8StringEncoding]; }
- (NSString *)fileNameExtensionForType:(NSString *)type saveOperation:(NSSaveOperationType)op { return @"txt"; }
- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)type forSaveOperation:(NSSaveOperationType)op
    originalContentsURL:(NSURL *)original error:(NSError **)error
{
    [writes addObject:[NSString stringWithFormat:@"%s: \"%@\" (implicitly cancellable: %d)", operation(op), self.text,
                                                 [self autosavingIsImplicitlyCancellable]]];
    return [super writeToURL:url ofType:type forSaveOperation:op originalContentsURL:original error:error];
}
- (void)change:(NSString *)text
{
    self.text = text;
    [self updateChangeCount:NSChangeDone];
}
- (void)show:(const char *)what
{
    NSWindow *w = [[[self windowControllers] firstObject] window];
    printf("%s: edited %d, unautosaved %d, window edited %d, text \"%s\"\n", what, [self isDocumentEdited],
           [self hasUnautosavedChanges], w ? [w isDocumentEdited] : -1, [self.text UTF8String]);
}
@end

@interface Plain : Note
@end
@implementation Plain
+ (BOOL)autosavesInPlace { return NO; }
@end

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)context
{
    printf("  %s: should close %d\n", [[doc displayName] UTF8String], shouldClose);
}
- (void)document:(NSDocument *)doc didAutosave:(BOOL)didAutosave contextInfo:(void *)context
{
    printf("  %s: did autosave %d\n", [[doc displayName] UTF8String], didAutosave);
}
- (void)documentController:(NSDocumentController *)dc didReviewAll:(BOOL)all contextInfo:(void *)context
{
    printf("  reviewed all %d, documents left %lu\n", all, (unsigned long)[[dc documents] count]);
}
@end

static Note *open_note(Class cls, NSString *path, BOOL window)
{
    NSError *error = nil;
    Note *doc = [[cls alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] ofType:@"public.plain-text" error:&error];
    if (!doc) {
        printf("can't open %s: %s\n", [path UTF8String], [[error description] UTF8String]);
        exit(1);
    }
    [[NSDocumentController sharedDocumentController] addDocument:doc];
    if (window) {
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                    backing:NSBackingStoreBuffered defer:NO];
        NSWindowController *wc = [[NSWindowController alloc] initWithWindow:w];
        [doc addWindowController:wc];
        [doc showWindows];
    }
    return doc;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        writes = [NSMutableArray array];
        Watcher *watcher = [[Watcher alloc] init];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *work = [NSHomeDirectory() stringByAppendingPathComponent:@"work"];
        [fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *path = [work stringByAppendingPathComponent:@"Note.txt"];
        [@"first" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDocumentController *dc = [NSDocumentController sharedDocumentController];
        printf("autosaving delay %.0f; autosaves in place: Note %d, Plain %d; drafts %d, versions %d\n",
               [dc autosavingDelay], [Note autosavesInPlace], [Plain autosavesInPlace], [Note autosavesDrafts],
               [Note preservesVersions]);
        [dc setAutosavingDelay:0.3];

        /* ---- autosaving in place ---- */
        Note *doc = open_note([Note class], path, YES);
        NSWindow *w = [[[doc windowControllers] firstObject] window];
        [doc show:"opened"];
        [doc change:@"second"];
        [doc show:"changed"];
        spin(0.05);
        printf("before the delay: file %s\n", [contents(path) UTF8String]);
        dump();
        spin(0.7);
        [doc show:"after the delay"];
        printf("file %s, autosaved contents %s\n", [contents(path) UTF8String],
               [shown([doc autosavedContentsFileURL]) UTF8String]);
        dump();
        NSString *kept = [NSHomeDirectory() stringByAppendingPathComponent:@".local/share/Autosave Information/Note (Last Saved).txt"];
        printf("the last saved version kept aside: %s\n", [contents(kept) UTF8String]);
        spin(0.7);
        printf("no change, no autosave:\n");
        dump();
        [doc change:@"third"];
        [doc autosaveWithImplicitCancellability:NO completionHandler:^(NSError *error) {
            printf("autosaveWithImplicitCancellability: error %s\n", error ? "some" : "none");
        }];
        [doc show:"autosaved by hand"];
        printf("file %s, the last saved version %s, implicitly cancellable now %d\n", [contents(path) UTF8String],
               [contents(kept) UTF8String], [doc autosavingIsImplicitlyCancellable]);
        dump();
        [doc autosaveDocumentWithDelegate:watcher didAutosaveSelector:@selector(document:didAutosave:contextInfo:)
                              contextInfo:NULL];
        dump();

        /* ---- the File menu's Revert ---- */
        NSMenuItem *revert = [[NSMenuItem alloc] initWithTitle:@"Revert to Saved" action:@selector(revertDocumentToSaved:)
                                                 keyEquivalent:@""];
        BOOL enabled = [doc validateMenuItem:revert];
        printf("the Revert item: \"%s\", enabled %d, its menu:", [[revert title] UTF8String], enabled);
        for (NSMenuItem *item in [[revert submenu] itemArray])
            printf(" \"%s\" (%d)", [[item title] UTF8String], [doc validateMenuItem:item]);
        printf("\n");
        NSMenuItem *last = [[revert submenu] itemAtIndex:0];
        setenv("FERRY_ALERT_ANSWER", "Revert", 1);
        [NSApp sendAction:[last action] to:doc from:last];
        spin(0.05);
        [doc show:"Revert To > Last Saved Version"];
        printf("file %s, the copy kept aside %s\n", [contents(path) UTF8String], [contents(kept) UTF8String]);
        dump();

        /* ---- Save ---- */
        [doc change:@"fourth"];
        spin(0.7);
        [doc show:"changed and autosaved"];
        printf("the last saved version %s\n", [contents(kept) UTF8String]);
        [doc saveDocument:nil];
        spin(0.05);
        [doc show:"saved"];
        printf("file %s, the copy kept aside %s\n", [contents(path) UTF8String], [contents(kept) UTF8String]);
        dump();

        /* ---- closing ---- */
        [doc change:@"fifth"];
        unsetenv("FERRY_ALERT_ANSWER");
        [doc canCloseDocumentWithDelegate:watcher shouldCloseSelector:@selector(document:shouldClose:contextInfo:)
                              contextInfo:NULL];
        printf("closing without asking: file %s, sheet %s\n", [contents(path) UTF8String], [w attachedSheet] ? "up" : "none");
        dump();
        [doc close];
        printf("closed: documents %lu, the copy kept aside %s\n", (unsigned long)[[dc documents] count],
               [contents(kept) UTF8String]);

        /* ---- an untitled document ---- */
        Note *untitled = [[Note alloc] initWithType:@"public.plain-text" error:NULL];
        [dc addDocument:untitled];
        [untitled change:@"draft"];
        spin(0.7);
        [untitled show:"untitled, after the delay"];
        NSString *autosaved = [[untitled autosavedContentsFileURL] path];
        printf("autosaved to %s: %s; its file %s\n", [shown([untitled autosavedContentsFileURL]) UTF8String],
               [contents(autosaved) UTF8String], [shown([untitled fileURL]) UTF8String]);
        dump();
        [untitled change:@"draft 2"];
        spin(0.7);
        printf("autosaved again to the same file: %s\n", [contents(autosaved) UTF8String]);
        dump();
        setenv("FERRY_ALERT_ANSWER", "Don't Save", 1);
        [untitled canCloseDocumentWithDelegate:watcher shouldCloseSelector:@selector(document:shouldClose:contextInfo:)
                                   contextInfo:NULL];
        [untitled close];
        printf("closed: the autosaved file %s\n", [contents(autosaved) UTF8String]);

        /* ---- a class that doesn't autosave in place ---- */
        NSString *plainPath = [work stringByAppendingPathComponent:@"Plain.txt"];
        [@"plain" writeToFile:plainPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        Note *plain = open_note([Plain class], plainPath, NO);
        [plain change:@"plain 2"];
        spin(0.7);
        [plain show:"not autosaving, after the delay"];
        dump();
        [plain autosaveDocumentWithDelegate:watcher didAutosaveSelector:@selector(document:didAutosave:contextInfo:)
                                contextInfo:NULL];
        NSMenuItem *revert2 = [[NSMenuItem alloc] initWithTitle:@"Revert to Saved" action:@selector(revertDocumentToSaved:)
                                                  keyEquivalent:@""];
        printf("its Revert item: \"%s\", enabled %d, menu %s\n", [[revert2 title] UTF8String],
               [plain validateMenuItem:revert2], [revert2 submenu] ? "some" : "none");
        [plain updateChangeCount:NSChangeAutosaved];
        [plain show:"NSChangeAutosaved"];
        [plain updateChangeCount:NSChangeDone];
        [plain show:"NSChangeDone"];
        [plain updateChangeCount:NSChangeCleared];
        [plain show:"NSChangeCleared"];
        [plain close];

        /* ---- quitting with two edited documents that autosave ---- */
        NSString *a = [work stringByAppendingPathComponent:@"A.txt"], *b = [work stringByAppendingPathComponent:@"B.txt"];
        [@"a" writeToFile:a atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"b" writeToFile:b atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [dc setAutosavingDelay:0];
        Note *da = open_note([Note class], a, NO), *db = open_note([Note class], b, NO);
        [da change:@"a 2"];
        [db change:@"b 2"];
        spin(0.1);
        printf("with no delay, nothing is autosaved: %s %s\n", [contents(a) UTF8String], [contents(b) UTF8String]);
        setenv("FERRY_ALERT_ANSWER", "Cancel", 1);   /* would cancel a review, if one were offered */
        [dc reviewUnsavedDocumentsWithAlertTitle:nil cancellable:YES delegate:watcher
                            didReviewAllSelector:@selector(documentController:didReviewAll:contextInfo:)
                                     contextInfo:NULL];
        printf("quitting: %s %s\n", [contents(a) UTF8String], [contents(b) UTF8String]);
        dump();
    }
    return 0;
}
