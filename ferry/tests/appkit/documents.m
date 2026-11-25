/* SPDX-License-Identifier: GPL-3.0-or-later
 * Documents, alerts and the workspace (1.167), with no display, run from
 * DocApp.app (make_nibs.py), whose Info.plist declares four document types
 * and whose main nib holds the File and Edit menus and the app's own
 * NSDocumentController subclass. A note named on the command line opens at
 * launch; then: the types; New; edits, the change count and the edited
 * dot through the undo manager; menu validation; Save and Save As through
 * the Save panel (answered from FERRY_PANEL_ANSWER) as a sheet; Revert;
 * closing with unsaved changes (Cancel, Don't Save, Save in the sheet);
 * Open through the Open panel, a file already open, a type the app can't
 * open and a file it can't read; a package read and written as a file
 * wrapper; a document class with the calls of Mac OS X 10.3; the Recent
 * Documents list and the Open Recent menu; alerts run modally in a nested
 * loop and answered by Return, Escape and Command-D, their layouts, the
 * old return codes, FERRY_ALERT_ANSWER, sheets and their queue; the
 * workspace, opening through a stand-in "gio" on the PATH that logs what
 * it is given; and quitting with two unsaved documents (the review alert,
 * each document's sheet, then NSTerminateLater). Pictures of an alert, a
 * sheet and an edited document window go to the directory
 * FERRY_DOCUMENTS_PNG names, if it is set. Ferry's own test, written for
 * Ferry from Apple's public documentation. */
#import <Cocoa/Cocoa.h>
#include <stdlib.h>
#include <unistd.h>

@interface NSWindow (FerryPicture)
- (NSBitmapImageRep *)_pictureWithTitleBar:(BOOL)titleBar;
@end

static const char *str(NSString *s) { return s ? [s UTF8String] : "(nil)"; }
static NSString *work(NSString *name) { return [[NSHomeDirectory() stringByAppendingPathComponent:@"work"]
                                                   stringByAppendingPathComponent:name]; }
static NSString *contents(NSString *path)
{
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    return s ?: @"(none)";
}
static void spin(double seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
static void key(NSWindow *w, NSString *chars, NSEventModifierFlags flags)
{
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:chars
               charactersIgnoringModifiers:chars isARepeat:NO keyCode:0]];
}
static NSArray *views_of(NSWindow *w, Class cls)
{
    NSMutableArray *found = [NSMutableArray array];
    for (NSView *v in [[w contentView] subviews])
        if ([v isKindOfClass:cls])
            [found addObject:v];
    return found;
}
static void show_alert(NSWindow *w)
{
    for (NSTextField *t in views_of(w, [NSTextField class]))
        printf("  text: %s\n", str([t stringValue]));
    for (NSButton *b in views_of(w, [NSButton class])) {
        NSString *k = [b keyEquivalent];
        NSString *shown = [k isEqualToString:@"\r"] ? @"Return" : [k isEqualToString:@"\e"] ? @"Escape"
                          : [k length] ? [@"Cmd-" stringByAppendingString:k] : @"-";
        NSRect f = [b frame];
        printf("  button: %s (%s) tag %ld at %.0f,%.0f %.0fx%.0f\n", str([b title]), str(shown), (long)[b tag],
               f.origin.x, f.origin.y, f.size.width, f.size.height);
    }
}
static void picture(NSWindow *w, BOOL bar, const char *name)
{
    const char *dir = getenv("FERRY_DOCUMENTS_PNG");
    if (!dir)
        return;
    NSBitmapImageRep *rep = [w _pictureWithTitleBar:bar];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:[NSString stringWithFormat:@"%s/documents-%s.png", dir, name] atomically:YES];
}
static NSMenu *menu_named(NSString *title)
{
    return [[[NSApp mainMenu] itemWithTitle:title] submenu];
}
static void show_menu(NSMenu *m)
{
    [m update];
    for (NSMenuItem *i in [m itemArray]) {
        if ([i isSeparatorItem])
            printf("  ----\n");
        else
            printf("  %s%s\n", str([i title]), [i isEnabled] ? "" : " (disabled)");
    }
}
static void show_recent(void)
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSURL *u in [[NSDocumentController sharedDocumentController] recentDocumentURLs])
        [names addObject:[u lastPathComponent]];
    printf("recent: %s\n", str([names componentsJoinedByString:@", "]));
}

/* ---- the app's document classes ---- */

@interface DocController : NSDocumentController
@end
@implementation DocController
- (instancetype)init
{
    self = [super init];
    printf("DocController made; shared: %s\n", [NSDocumentController sharedDocumentController] == self ? "yes" : "no");
    return self;
}
- (void)noteNewRecentDocumentURL:(NSURL *)url
{
    printf("  (noted as recent: %s)\n", str([url lastPathComponent]));
    [super noteNewRecentDocumentURL:url];
}
@end

@interface NoteDocument : NSDocument
@property (copy) NSString *text;
@property (strong) IBOutlet NSTextField *textField;
@end
@implementation NoteDocument
- (NSString *)windowNibName { return @"Document"; }
- (void)windowControllerDidLoadNib:(NSWindowController *)wc
{
    [self.textField setStringValue:self.text ?: @""];
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    printf("  NoteDocument reads %s: \"%s\"\n", str(type), str(s));
    if ([s hasPrefix:@"BAD"]) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                                     userInfo:@{NSLocalizedDescriptionKey : @"The note is damaged."}];
        return NO;
    }
    self.text = s;
    [self.textField setStringValue:s];
    return YES;
}
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
    printf("  NoteDocument writes %s\n", str(type));
    return [self.text ?: @"" dataUsingEncoding:NSUTF8StringEncoding];
}
- (void)edit:(NSString *)text
{
    [[self undoManager] registerUndoWithTarget:self selector:@selector(edit:) object:self.text ?: @""];
    [[self undoManager] setActionName:@"Typing"];
    self.text = text;
    [self.textField setStringValue:text];
}
@end

@interface BundleDocument : NSDocument
@property (copy) NSString *text;
@end
@implementation BundleDocument
- (BOOL)readFromFileWrapper:(NSFileWrapper *)w ofType:(NSString *)type error:(NSError **)error
{
    NSFileWrapper *index = [w fileWrappers][@"index.txt"];
    printf("  BundleDocument reads a %s with %lu files\n", [w isDirectory] ? "folder" : "file",
           (unsigned long)[[w fileWrappers] count]);
    self.text = [[NSString alloc] initWithData:[index regularFileContents] encoding:NSUTF8StringEncoding];
    return index != nil;
}
- (NSFileWrapper *)fileWrapperOfType:(NSString *)type error:(NSError **)error
{
    NSFileWrapper *index = [[NSFileWrapper alloc] initRegularFileWithContents:[self.text dataUsingEncoding:NSUTF8StringEncoding]];
    NSFileWrapper *info = [[NSFileWrapper alloc] initRegularFileWithContents:[@"v1" dataUsingEncoding:NSUTF8StringEncoding]];
    return [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"index.txt" : index, @"version" : info}];
}
@end

/* A document written for Mac OS X 10.3: only the old calls. */
@interface OldDocument : NSDocument
@property (copy) NSString *text;
@end
@implementation OldDocument
- (BOOL)loadDataRepresentation:(NSData *)data ofType:(NSString *)type
{
    self.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    printf("  OldDocument loadDataRepresentation: \"%s\"\n", str(self.text));
    return YES;
}
- (NSData *)dataRepresentationOfType:(NSString *)type
{
    printf("  OldDocument dataRepresentationOfType: %s\n", str(type));
    return [[self.text stringByAppendingString:@" (saved)"] dataUsingEncoding:NSUTF8StringEncoding];
}
@end

/* ---- pressing keys while an alert runs modally ---- */

@interface Presser : NSObject
@property (copy) NSString *keys;
@property NSEventModifierFlags flags;
@property const char *pictureName;
@end
@implementation Presser
+ (void)press:(NSString *)keys flags:(NSEventModifierFlags)flags picture:(const char *)name
{
    Presser *p = [Presser new];
    p.keys = keys;
    p.flags = flags;
    p.pictureName = name;
    [p performSelector:@selector(go) withObject:nil afterDelay:0.01];
}
- (void)go
{
    NSWindow *w = [NSApp modalWindow];
    printf("  modal window: %s, %.0fx%.0f\n", w ? "yes" : "no", [w frame].size.width, [w frame].size.height);
    show_alert(w);
    if (self.pictureName)
        picture(w, NO, self.pictureName);
    key(w, self.keys, self.flags);
}
@end

/* ---- the app ---- */

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) IBOutlet DocController *documents;
@property (strong) NSTimer *watcher;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)n
{
    printf("will finish launching; controller in the nib: %s\n", [self.documents isKindOfClass:[DocController class]]
                                                                     ? "yes" : "no");
}

- (void)showDocuments
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSDocument *d in [[NSDocumentController sharedDocumentController] documents])
        [names addObject:[NSString stringWithFormat:@"%@%@", [d displayName], [d isDocumentEdited] ? @"*" : @""]];
    printf("documents: %s\n", str([names componentsJoinedByString:@", "]));
}

- (void)applicationDidFinishLaunching:(NSNotification *)n
{
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    printf("== launch\n");
    printf("shared controller: %s\n", str(NSStringFromClass([dc class])));
    [self showDocuments];
    NoteDocument *launched = [[dc documents] firstObject];
    NSWindow *lw = [[[launched windowControllers] firstObject] window];
    printf("window \"%s\", field \"%s\", represented %s\n", str([lw title]), str([[launched textField] stringValue]),
           str([[lw representedURL] lastPathComponent]));
    show_recent();

    [self types:dc];
    [self newAndEdit:dc];
    [self saving:dc];
    [self closing:dc];
    [self opening:dc];
    [self packages:dc];
    [self recent:dc];
    [self alerts];
    [self workspace];
    [self quit:dc];
}

- (void)types:(NSDocumentController *)dc
{
    printf("== types\n");
    printf("classes: %s\n", str([[dc documentClassNames] componentsJoinedByString:@", "]));
    printf("default type: %s\n", str([dc defaultType]));
    for (NSString *ext in @[ @"note", @"NOTE", @"txt", @"notes", @"onote", @"xyz" ])
        printf("type for .%s: %s\n", str(ext), str([dc typeFromFileExtension:ext]));
    printf("extensions of the note type: %s\n",
           str([[dc fileExtensionsFromType:@"org.freemac.ferry.note"] componentsJoinedByString:@", "]));
    printf("display name: %s\n", str([dc displayNameForType:@"org.freemac.ferry.note"]));
    printf("class for Plain Text: %s\n", str(NSStringFromClass([dc documentClassForType:@"Plain Text"])));
    printf("NoteDocument reads %s; writes %s\n", str([[NoteDocument readableTypes] componentsJoinedByString:@", "]),
           str([[NoteDocument writableTypes] componentsJoinedByString:@", "]));
    printf("native: note %d, plain text %d\n", [NoteDocument isNativeType:@"org.freemac.ferry.note"],
           [NoteDocument isNativeType:@"Plain Text"]);
    printf("autosaves in place: %d, versions: %d\n", [NoteDocument autosavesInPlace], [NoteDocument preservesVersions]);
}

- (void)newAndEdit:(NSDocumentController *)dc
{
    printf("== new\n");
    [NSApp sendAction:@selector(newDocument:) to:nil from:nil];
    [NSApp sendAction:@selector(newDocument:) to:nil from:nil];
    [self showDocuments];
    NoteDocument *doc = [dc documents][2];
    NSWindow *w = [[[doc windowControllers] firstObject] window];
    printf("window \"%s\", key %d, current document %s\n", str([w title]), [w isKeyWindow],
           str([[dc currentDocument] displayName]));
    printf("untitled: fileURL %s, type %s, edited %d\n", str([[doc fileURL] path]), str([doc fileType]),
           [doc isDocumentEdited]);

    printf("== edits\n");
    [doc edit:@"first words"];
    printf("before the run loop turns: edited %d\n", [doc isDocumentEdited]);
    spin(0.05);
    printf("after: edited %d, window shows it %d\n", [doc isDocumentEdited], [w isDocumentEdited]);
    picture(w, YES, "edited");
    printf("undo manager: the window's is the document's %d; %s\n", [w undoManager] == [doc undoManager],
           str([[doc undoManager] undoMenuItemTitle]));
    show_menu(menu_named(@"Edit"));
    [NSApp sendAction:@selector(undo:) to:nil from:nil];
    printf("undone: text \"%s\", edited %d, window %d\n", str(doc.text), [doc isDocumentEdited], [w isDocumentEdited]);
    [NSApp sendAction:@selector(redo:) to:nil from:nil];
    printf("redone: text \"%s\", edited %d\n", str(doc.text), [doc isDocumentEdited]);
    [doc updateChangeCount:NSChangeCleared];
    printf("cleared: edited %d\n", [doc isDocumentEdited]);
    [doc updateChangeCount:NSChangeUndone];
    printf("undone past the save: edited %d\n", [doc isDocumentEdited]);
    [doc updateChangeCount:NSChangeDone];
    printf("done again: edited %d\n", [doc isDocumentEdited]);
    [doc updateChangeCount:NSChangeDone];
    printf("File menu, an edited untitled document:\n");
    show_menu(menu_named(@"File"));
}

- (void)saving:(NSDocumentController *)dc
{
    printf("== save\n");
    NoteDocument *doc = [dc documents][2];
    NSWindow *w = [[[doc windowControllers] firstObject] window];
    setenv("FERRY_PANEL_ANSWER", [work(@"First.note") UTF8String], 1);
    [NSApp sendAction:@selector(saveDocument:) to:nil from:nil];
    printf("the Save panel is a sheet, answered when the loop turns: saved yet %d\n", [doc fileURL] != nil);
    spin(0.05);
    printf("saved as %s (%s), edited %d, window \"%s\" edited %d\n", str([[doc fileURL] lastPathComponent]),
           str([doc fileType]), [doc isDocumentEdited], str([w title]), [w isDocumentEdited]);
    printf("file: \"%s\", modification date known %d\n", str(contents(work(@"First.note"))),
           [doc fileModificationDate] != nil);
    printf("File menu, saved:\n");
    show_menu(menu_named(@"File"));

    printf("== save again\n");
    [doc edit:@"second words"];
    spin(0.05);
    [NSApp sendAction:@selector(saveDocument:) to:nil from:nil];
    printf("saved in place at once: edited %d, file \"%s\"\n", [doc isDocumentEdited],
           str(contents(work(@"First.note"))));
    NSArray *left = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:work(@"") error:NULL];
    printf("nothing left beside it: %s\n", str([[left sortedArrayUsingSelector:@selector(compare:)]
                                                   componentsJoinedByString:@", "]));

    printf("== save as\n");
    setenv("FERRY_PANEL_ANSWER", [work(@"Second") UTF8String], 1);
    [NSApp sendAction:@selector(saveDocumentAs:) to:nil from:nil];
    spin(0.05);
    printf("now %s; file \"%s\"; the first is still \"%s\"\n", str([[doc fileURL] lastPathComponent]),
           str(contents(work(@"Second.note"))), str(contents(work(@"First.note"))));
    show_recent();

    printf("== revert\n");
    [doc edit:@"unwanted words"];
    spin(0.05);
    [NSApp sendAction:@selector(revertDocumentToSaved:) to:nil from:nil];
    NSWindow *sheet = [w attachedSheet];
    printf("a sheet: %d, is a sheet %d, its parent is the window %d\n", sheet != nil, [sheet isSheet],
           [sheet sheetParent] == w);
    show_alert(sheet);
    picture(w, YES, "sheet");
    key(sheet, @"\r", 0);
    printf("reverted: text \"%s\", edited %d, sheet gone %d\n", str(doc.text), [doc isDocumentEdited],
           [w attachedSheet] == nil);
    [doc edit:@"kept words"];
    spin(0.05);
    [NSApp sendAction:@selector(revertDocumentToSaved:) to:nil from:nil];
    key([w attachedSheet], @"\e", 0);
    printf("Cancel: text \"%s\", edited %d\n", str(doc.text), [doc isDocumentEdited]);
}

- (void)closing:(NSDocumentController *)dc
{
    printf("== close\n");
    NoteDocument *doc = [dc documents][2];
    NSWindow *w = [[[doc windowControllers] firstObject] window];
    [w makeKeyAndOrderFront:nil];
    [NSApp sendAction:@selector(performClose:) to:nil from:nil];
    NSWindow *sheet = [w attachedSheet];
    printf("asks: %d\n", sheet != nil);
    show_alert(sheet);
    printf("File menu with the sheet up:\n");
    show_menu(menu_named(@"File"));
    key(sheet, @"\e", 0);
    printf("Cancel: still open %d, documents %lu\n", [w isVisible], (unsigned long)[[dc documents] count]);
    [NSApp sendAction:@selector(performClose:) to:nil from:nil];
    key([w attachedSheet], @"d", NSEventModifierFlagCommand);
    printf("Don't Save: closed %d, file still \"%s\"\n", ![w isVisible], str(contents(work(@"Second.note"))));
    [self showDocuments];

    NoteDocument *other = [dc documents][1];   /* Untitled */
    NSWindow *ow = [[[other windowControllers] firstObject] window];
    [other edit:@"saved on closing"];
    spin(0.05);
    setenv("FERRY_PANEL_ANSWER", [work(@"Closing.note") UTF8String], 1);
    [ow performClose:nil];
    key([ow attachedSheet], @"\r", 0);
    printf("Save: the Save panel comes next; open %d\n", [ow isVisible]);
    spin(0.05);
    printf("saved \"%s\" and closed %d\n", str(contents(work(@"Closing.note"))), ![ow isVisible]);
    [self showDocuments];

    NoteDocument *clean = [dc documents][0];
    NSWindow *cw = [[[clean windowControllers] firstObject] window];
    [cw performClose:nil];
    printf("an unedited document closes without asking: %d\n", ![cw isVisible]);
    [self showDocuments];
}

- (void)opening:(NSDocumentController *)dc
{
    printf("== open\n");
    [@"plain words" writeToFile:work(@"Plain.txt") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    setenv("FERRY_PANEL_ANSWER", [work(@"Plain.txt") UTF8String], 1);
    [NSApp sendAction:@selector(openDocument:) to:nil from:nil];
    spin(0.05);
    [self showDocuments];
    NSDocument *plain = [dc documentForURL:[NSURL fileURLWithPath:work(@"Plain.txt")]];
    printf("Plain.txt: type %s, class %s, window \"%s\"\n", str([plain fileType]),
           str(NSStringFromClass([plain class])), str([[[[plain windowControllers] firstObject] window] title]));
    [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath:work(@"Plain.txt")] display:YES
                    completionHandler:^(NSDocument *d, BOOL already, NSError *e) {
                        printf("again: the same %d, already open %d\n", d == plain, already);
                    }];
    [@"?" writeToFile:work(@"Strange.xyz") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath:work(@"Strange.xyz")] display:YES
                    completionHandler:^(NSDocument *d, BOOL already, NSError *e) {
                        printf("Strange.xyz: %s, error %ld: %s\n", d ? "opened" : "not opened", (long)[e code],
                               str([e localizedDescription]));
                    }];
    [@"BAD note" writeToFile:work(@"Bad.note") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSError *error = nil;
    id bad = [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath:work(@"Bad.note")] display:YES error:&error];
    printf("Bad.note: %s, error: %s\n", bad ? "opened" : "not opened", str([error localizedDescription]));
    [self showDocuments];
}

- (void)packages:(NSDocumentController *)dc
{
    printf("== a package, as a file wrapper\n");
    NSError *error = nil;
    BundleDocument *b = [dc makeUntitledDocumentOfType:@"Note Bundle" error:&error];
    b.text = @"inside the package";
    BOOL ok = [b saveToURL:[NSURL fileURLWithPath:work(@"Pack.notes")] ofType:@"Note Bundle"
          forSaveOperation:NSSaveOperation error:&error];
    NSArray *inside = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:work(@"Pack.notes") error:NULL];
    printf("saved %d: %s, index \"%s\"\n", ok, str([[inside sortedArrayUsingSelector:@selector(compare:)]
                                                    componentsJoinedByString:@", "]),
           str(contents(work(@"Pack.notes/index.txt"))));
    b.text = @"saved over";
    ok = [b saveToURL:[b fileURL] ofType:@"Note Bundle" forSaveOperation:NSSaveOperation error:&error];
    printf("saved over %d: \"%s\"\n", ok, str(contents(work(@"Pack.notes/index.txt"))));
    BundleDocument *again = [dc makeDocumentWithContentsOfURL:[NSURL fileURLWithPath:work(@"Pack.notes")]
                                                       ofType:[dc typeForContentsOfURL:[NSURL fileURLWithPath:work(@"Pack.notes")]
                                                                                 error:NULL]
                                                        error:&error];
    printf("read back: \"%s\"; a package to the workspace %d\n", str(again.text),
           [[NSWorkspace sharedWorkspace] isFilePackageAtPath:work(@"Pack.notes")]);

    printf("== the calls of Mac OS X 10.3\n");
    [@"old words" writeToFile:work(@"Old.onote") atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    OldDocument *old = [dc openDocumentWithContentsOfURL:[NSURL fileURLWithPath:work(@"Old.onote")] display:NO
                                                   error:&error];
    printf("opened %s, file name %s\n", str(old.text), str([[old fileName] lastPathComponent]));
    [old saveToURL:[old fileURL] ofType:[old fileType] forSaveOperation:NSSaveOperation error:&error];
    printf("file: \"%s\"\n", str(contents(work(@"Old.onote"))));
    [old close];
}

- (void)recent:(NSDocumentController *)dc
{
    printf("== recent documents\n");
    show_recent();
    NSMenu *recentMenu = [[menu_named(@"File") itemWithTitle:@"Open Recent"] submenu];
    printf("Open Recent:\n");
    show_menu(recentMenu);
    printf("kept in the defaults: %lu\n",
           (unsigned long)[[[NSUserDefaults standardUserDefaults] arrayForKey:@"FerryRecentDocuments"] count]);
    /* choosing one opens it */
    NSMenuItem *first = [recentMenu itemAtIndex:0];
    [NSApp sendAction:[first action] to:[first target] from:first];
    [self showDocuments];
    [dc clearRecentDocuments:nil];
    printf("cleared:\n");
    show_menu(recentMenu);
    show_recent();
    [dc noteNewRecentDocumentURL:[NSURL fileURLWithPath:work(@"Plain.txt")]];
    show_recent();
}

- (void)alerts
{
    printf("== alerts\n");
    NSAlert *a = [NSAlert new];
    [a setMessageText:@"Do you want to save the changes made to the document \u201cReport\u201d?"];
    [a setInformativeText:@"Your changes will be lost if you don\u2019t save them."];
    [a addButtonWithTitle:@"Save"];
    [a addButtonWithTitle:@"Cancel"];
    [a addButtonWithTitle:@"Don\u2019t Save"];
    printf("three buttons, Return:\n");
    [Presser press:@"\r" flags:0 picture:"alert"];
    printf("returned %ld\n", (long)[a runModal]);
    printf("Escape:\n");
    [Presser press:@"\e" flags:0 picture:NULL];
    printf("returned %ld\n", (long)[a runModal]);
    printf("Command-D:\n");
    [Presser press:@"d" flags:NSEventModifierFlagCommand picture:NULL];
    printf("returned %ld\n", (long)[a runModal]);
    printf("a click on the second button:\n");
    [a performSelector:@selector(_pressSecond) withObject:nil afterDelay:0.01];
    printf("returned %ld\n", (long)[a runModal]);

    NSAlert *two = [NSAlert new];
    [two setMessageText:@"Delete the note?"];
    [two setAlertStyle:NSAlertStyleCritical];
    [two addButtonWithTitle:@"Delete"];
    [two addButtonWithTitle:@"Cancel"];
    [two setShowsSuppressionButton:YES];
    [two setAccessoryView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 40)]];
    [two layout];
    printf("two buttons, critical, an accessory and the check box: %.0fx%.0f, icon %s\n",
           [[two window] frame].size.width, [[two window] frame].size.height,
           [[[views_of([two window], [NSImageView class]) firstObject] image] isValid] ? "valid" : "missing");
    printf("  check box \"%s\" at %.0f,%.0f; accessory at %.0f,%.0f\n", str([[two suppressionButton] title]),
           [[two suppressionButton] frame].origin.x, [[two suppressionButton] frame].origin.y,
           [[two accessoryView] frame].origin.x, [[two accessoryView] frame].origin.y);
    [[two suppressionButton] setState:NSControlStateValueOn];
    [Presser press:@"\r" flags:0 picture:NULL];
    printf("returned %ld, suppress next time %d\n", (long)[two runModal],
           [[two suppressionButton] state] == NSControlStateValueOn);

    NSAlert *old = [NSAlert alertWithMessageText:@"Old style" defaultButton:@"OK" alternateButton:@"Cancel"
                                     otherButton:@"Other" informativeTextWithFormat:@"%d things", 3];
    [Presser press:@"\e" flags:0 picture:NULL];
    printf("old-style codes, Escape: %ld\n", (long)[old runModal]);

    setenv("FERRY_ALERT_ANSWER", "Don't Save", 1);
    printf("FERRY_ALERT_ANSWER \"Don't Save\": %ld\n", (long)[a runModal]);
    /* a tall alert, as ShiftIt's with its picture, is kept on the screen (1.229) */
    NSAlert *tall = [NSAlert new];
    [tall setMessageText:@"Authorization"];
    [tall addButtonWithTitle:@"OK"];
    [tall setAccessoryView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 640)]];
    setenv("FERRY_ALERT_ANSWER", "OK", 1);
    [tall runModal];
    NSRect tf = [[tall window] frame], vis = [[NSScreen mainScreen] visibleFrame];
    printf("a tall alert: %.0f high on a screen %.0f high, its top %s the screen's, its bottom %s\n", tf.size.height,
           vis.size.height, NSMaxY(tf) <= NSMaxY(vis) ? "within" : "above",
           NSMinY(tf) >= NSMinY(vis) ? "on the screen" : "below it");
    setenv("FERRY_ALERT_ANSWER", "2", 1);
    printf("NSRunAlertPanel answered \"2\": %ld\n", (long)NSRunAlertPanel(@"Title", @"%@", @"OK", @"No", nil, @"x"));
    setenv("FERRY_ALERT_ANSWER", "1", 1);
    NSError *err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                   userInfo:@{NSLocalizedDescriptionKey : @"The file couldn\u2019t be found.",
                                              NSLocalizedRecoverySuggestionErrorKey : @"Check the name."}];
    NSAlert *fromError = [NSAlert alertWithError:err];
    printf("from an error: \"%s\" / \"%s\" / %s\n", str([fromError messageText]), str([fromError informativeText]),
           str([[[fromError buttons] firstObject] title]));
    printf("presentError: %d\n", [NSApp presentError:err]);
    unsetenv("FERRY_ALERT_ANSWER");

    printf("== sheets\n");
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:NO];
    [w setTitle:@"Sheets"];
    [w makeKeyAndOrderFront:nil];
    NSAlert *s1 = [NSAlert new];
    [s1 setMessageText:@"First sheet"];
    [s1 addButtonWithTitle:@"OK"];
    [s1 addButtonWithTitle:@"Cancel"];
    NSAlert *s2 = [NSAlert new];
    [s2 setMessageText:@"Second sheet"];
    [s1 beginSheetModalForWindow:w completionHandler:^(NSModalResponse r) {
        printf("first sheet ended: %ld\n", (long)r);
    }];
    [s2 beginSheetModalForWindow:w completionHandler:^(NSModalResponse r) {
        printf("second sheet ended: %ld\n", (long)r);
    }];
    NSRect f = [[w attachedSheet] frame];
    printf("attached: the first %d; sheets %lu; key window is the sheet %d; at %.0f,%.0f %.0fx%.0f\n",
           [w attachedSheet] == [s1 window], (unsigned long)[[w sheets] count], [[s1 window] isKeyWindow],
           f.origin.x - [w frame].origin.x, f.origin.y - [w frame].origin.y, f.size.width, f.size.height);
    printf("closing the window while it has a sheet: ");
    [w performClose:nil];
    printf("still open %d\n", [w isVisible]);
    key([w attachedSheet], @"\e", 0);
    printf("then the second: %d\n", [w attachedSheet] == [s2 window]);
    key([w attachedSheet], @"\r", 0);
    printf("none left %d, key again %d\n", [w attachedSheet] == nil, [w isKeyWindow]);
    NSPanel *custom = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 80) styleMask:NSWindowStyleMaskTitled
                                                   backing:NSBackingStoreBuffered defer:NO];
    [NSApp beginSheet:custom modalForWindow:w modalDelegate:self
       didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:) contextInfo:(void *)"the context"];
    printf("an old-style sheet: attached %d\n", [w attachedSheet] == custom);
    [NSApp endSheet:custom returnCode:42];
    [custom orderOut:nil];
    printf("after endSheet: attached %d\n", [w attachedSheet] != nil);
    [w close];
}
- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)context
{
    printf("old-style sheet ended: %ld, %s, still up %d\n", (long)code, (const char *)context, [sheet isVisible]);
}

- (void)workspace
{
    printf("== workspace\n");
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    printf("shared: %d; its own notification centre %d\n", ws == [NSWorkspace sharedWorkspace],
           [ws notificationCenter] && [ws notificationCenter] != [NSNotificationCenter defaultCenter]);
    printf("notifications: %s, %s, %s\n", str(NSWorkspaceWillSleepNotification), str(NSWorkspaceDidWakeNotification),
           str(NSWorkspaceDidLaunchApplicationNotification));
    printf("open a web address: %d\n", [ws openURL:[NSURL URLWithString:@"https://example.org/page?q=1"]]);
    printf("open a file: %d\n", [ws openFile:work(@"Plain.txt")]);
    printf("open a missing file: %d\n", [ws openFile:work(@"Missing.txt")]);
    printf("open an address with no scheme: %d\n", [ws openURL:[NSURL URLWithString:@"no-scheme"]]);
    printf("show in the file viewer: %d\n", [ws selectFile:work(@"Plain.txt") inFileViewerRootedAtPath:@""]);
    [ws openURL:[NSURL URLWithString:@"mailto:someone@example.org"]
        configuration:[NSWorkspaceOpenConfiguration configuration]
        completionHandler:^(NSRunningApplication *app, NSError *e) {
            printf("opened with a configuration: error %s\n", e ? "yes" : "none");
        }];
    spin(0.01);
    printf("launch another app: %d\n", [ws launchApplication:@"TextEdit"]);
    NSString *log = [NSHomeDirectory() stringByAppendingPathComponent:@"gio.log"];
    /* the launcher runs on its own: wait (up to ten seconds) for its four lines */
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    while ([[contents(log) componentsSeparatedByString:@"\n"] count] < 5 && [until timeIntervalSinceNow] > 0)
        usleep(10000);
    NSArray *lines = [[contents(log) stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@"~"]
        componentsSeparatedByString:@"\n"];
    for (NSString *l in [lines sortedArrayUsingSelector:@selector(compare:)])
        if ([l length])
            printf("  the launcher was given: %s\n", str(l));
    for (NSString *p in @[ work(@"Plain.txt"), work(@""), work(@"Pack.notes"), work(@"Missing.zzz") ]) {
        NSImage *i = [ws iconForFile:p];
        printf("icon for %s: %.0fx%.0f, %s\n", str([[p lastPathComponent] length] ? [p lastPathComponent] : @"work"),
               [i size].width, [i size].height, [i isValid] ? "valid" : "invalid");
    }
    for (NSString *t in @[ @"txt", @"public.folder", @"org.freemac.ferry.note", @"'TEXT'" ]) {
        NSImage *i = [ws iconForFileType:t];
        printf("icon for type %s: %.0fx%.0f, %s\n", str(t), [i size].width, [i size].height,
               [i isValid] ? "valid" : "invalid");
    }
    NSString *me = [[NSBundle mainBundle] bundleIdentifier];
    printf("this app by its identifier: %s\n",
           str([[ws URLForApplicationWithBundleIdentifier:me] lastPathComponent]));
    printf("an unknown app: %s\n", str([[ws URLForApplicationWithBundleIdentifier:@"com.example.nothing"] path]));
    printf("this app by name: %s\n", str([[ws fullPathForApplication:@"DocApp"] lastPathComponent]));
    printf("types: %s, %s, %s\n", str([ws typeOfFile:work(@"First.note") error:NULL]),
           str([ws typeOfFile:work(@"") error:NULL]), str([ws typeOfFile:work(@"Plain.txt") error:NULL]));
    printf("a note is text %d, an image %d\n", [ws type:@"org.freemac.ferry.note" conformsToType:@"public.text"],
           [ws type:@"org.freemac.ferry.note" conformsToType:@"public.image"]);
    printf("described: %s\n", str([ws localizedDescriptionForType:@"org.freemac.ferry.note"]));
}

- (void)quit:(NSDocumentController *)dc
{
    printf("== quit\n");
    [NSApp sendAction:@selector(newDocument:) to:nil from:nil];
    NSArray *docs = [dc documents];
    for (NSUInteger i = 0; i < [docs count]; i++)
        if ([docs[i] isKindOfClass:[NoteDocument class]])
            [(NoteDocument *)docs[i] edit:[NSString stringWithFormat:@"unsaved %lu", (unsigned long)i]];
    spin(0.05);
    [self showDocuments];
    self.watcher = [NSTimer scheduledTimerWithTimeInterval:0.01 target:self selector:@selector(watch:) userInfo:nil
                                                   repeats:YES];
    [NSApp terminate:nil];
    printf("terminate: returned; the sheets wait\n");
}
/* Answers the review alert with Review Changes, and each document's
 * sheet with Don't Save. */
- (void)watch:(NSTimer *)t
{
    if ([NSApp modalWindow]) {
        printf("review alert:\n");
        show_alert([NSApp modalWindow]);
        key([NSApp modalWindow], @"\r", 0);
        return;
    }
    for (NSWindow *w in [NSApp windows]) {
        NSWindow *s = [w attachedSheet];
        if (!s)
            continue;
        printf("sheet on \"%s\": %s\n", str([w title]), str([[views_of(s, [NSTextField class]) firstObject] stringValue]));
        key(s, @"d", NSEventModifierFlagCommand);
        [self showDocuments];
        return;
    }
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app
{
    [self.watcher invalidate];
    printf("should terminate? later\n");
    [self performSelector:@selector(reply) withObject:nil afterDelay:0.02];
    return NSTerminateLater;
}
- (void)reply
{
    printf("replying: yes\n");
    [NSApp replyToApplicationShouldTerminate:YES];
}
- (void)applicationWillTerminate:(NSNotification *)n
{
    [self showDocuments];
    printf("will terminate\n");
}
@end

@interface NSAlert (TestClick)
- (void)_pressSecond;
@end
@implementation NSAlert (TestClick)
- (void)_pressSecond { [[[self buttons] objectAtIndex:1] performClick:nil]; }
@end

/* unbuffered, so that what was printed is there even if the app stops */
int main(int argc, const char *argv[])
{
    setvbuf(stdout, NULL, _IONBF, 0);
    return NSApplicationMain(argc, argv);
}
