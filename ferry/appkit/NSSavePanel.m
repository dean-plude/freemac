/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: Open and Save panels (M7), written from Apple's public
 * NSSavePanel and NSOpenPanel documentation. The panel is this system's
 * file chooser (GTK's, which on a desktop with a portal is the desktop's
 * own); the NSPanel object itself is never shown. Sheets and panels begun
 * with a completion handler run when the event loop next turns, as on a
 * Mac the handler is called after the begin call returns. With no display,
 * a panel answers Cancel, or with the paths in FERRY_PANEL_ANSWER (one per
 * line), for scripted runs and tests.
 *
 * An accessory view can't go inside the system's chooser, so its pop-up
 * menus and check boxes go there as the chooser's own choices (a Save
 * panel's Format menu, an Open panel's options), named by the label beside
 * each pop-up or the check box's title. What was chosen goes back into the
 * controls when the chooser closes, each changed one as if clicked, its
 * bindings told and its action sent, before the chosen file is taken: a
 * format menu's action that changes the allowed types gives the file its
 * new extension (freemac 1.252). With no display, FERRY_PANEL_CHOICES
 * ("Label=Option" lines) answers them. Built without ARC. */
#import "AInternal.h"
#include <dispatch/dispatch.h>

/* File name patterns for a type: an extension, or one of the common
 * uniform type identifiers. */
NSArray *AExtensionsForType(NSString *type)
{
    static NSDictionary *utis;
    if (!utis)
        utis = [@{
            @"public.plain-text" : @[ @"txt", @"text" ], @"public.text" : @[ @"txt", @"text" ],
            @"public.utf8-plain-text" : @[ @"txt" ], @"public.png" : @[ @"png" ],
            @"public.jpeg" : @[ @"jpg", @"jpeg" ], @"public.tiff" : @[ @"tif", @"tiff" ],
            @"com.compuserve.gif" : @[ @"gif" ], @"com.microsoft.bmp" : @[ @"bmp" ],
            @"public.image" : @[ @"png", @"jpg", @"jpeg", @"gif", @"tif", @"tiff", @"bmp", @"heic", @"webp" ],
            @"com.adobe.pdf" : @[ @"pdf" ], @"public.html" : @[ @"html", @"htm" ], @"public.rtf" : @[ @"rtf" ],
            @"public.xml" : @[ @"xml" ], @"public.json" : @[ @"json" ],
            @"public.comma-separated-values-text" : @[ @"csv" ], @"com.apple.property-list" : @[ @"plist" ],
            @"public.data" : @[], @"public.item" : @[], @"public.content" : @[],
        } retain];
    NSArray *known = [utis objectForKey:type];
    if (known)
        return known;
    if ([type rangeOfString:@"."].location != NSNotFound)
        return nil; /* an identifier Ferry doesn't know */
    return @[ type ];
}

@implementation NSSavePanel {
@protected
    NSURL *_directory;
    NSMutableArray *_chosen;
    NSString *_nameField, *_nameLabel, *_message, *_prompt;
    NSArray *_types, *_tagNames;
    BOOL _otherTypes, _createDirs, _hiddenExtension, _canHide, _showHidden, _packages, _tagField;
    NSView *_accessory;
    id _panelDelegate;
    NSArray *_startTypes;   /* the allowed types when the panel was run */
}

+ (NSSavePanel *)savePanel { return [[[self alloc] init] autorelease]; }

- (instancetype)init
{
    return [self initWithContentRect:NSMakeRect(0, 0, 640, 400)
                           styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                             backing:NSBackingStoreBuffered
                               defer:YES];
}

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)defer
{
    if ((self = [super initWithContentRect:rect styleMask:style backing:backing defer:defer])) {
        _chosen = [[NSMutableArray alloc] init];
        _createDirs = YES;
        _otherTypes = NO;
        _nameField = [@"" copy];
        [self setReleasedWhenClosed:NO];
    }
    return self;
}

- (void)dealloc
{
    [_directory release];
    [_chosen release];
    [_nameField release];
    [_nameLabel release];
    [_message release];
    [_prompt release];
    [_types release];
    [_tagNames release];
    [_accessory release];
    [_startTypes release];
    [super dealloc];
}

#define COPY_PROPERTY(getter, setter, ivar)                                                                       \
    -(id)getter { return ivar; }                                                                                  \
    -(void)setter:(id)v                                                                                           \
    {                                                                                                             \
        if (v != ivar) {                                                                                          \
            [ivar release];                                                                                       \
            ivar = [v copy];                                                                                      \
        }                                                                                                         \
    }
COPY_PROPERTY(directoryURL, setDirectoryURL, _directory)
COPY_PROPERTY(nameFieldLabel, setNameFieldLabel, _nameLabel)
COPY_PROPERTY(message, setMessage, _message)
COPY_PROPERTY(prompt, setPrompt, _prompt)
COPY_PROPERTY(allowedFileTypes, setAllowedFileTypes, _types)
COPY_PROPERTY(tagNames, setTagNames, _tagNames)
- (NSString *)nameFieldStringValue { return _nameField; }
- (void)setNameFieldStringValue:(NSString *)s
{
    id wasNameField = _nameField;
    _nameField = [s ?: @"" copy];
    [wasNameField release];
}
- (BOOL)allowsOtherFileTypes { return _otherTypes; }
- (void)setAllowsOtherFileTypes:(BOOL)f { _otherTypes = f; }
- (BOOL)canCreateDirectories { return _createDirs; }
- (void)setCanCreateDirectories:(BOOL)f { _createDirs = f; }
- (BOOL)canSelectHiddenExtension { return _canHide; }
- (void)setCanSelectHiddenExtension:(BOOL)f { _canHide = f; }
- (BOOL)isExtensionHidden { return _hiddenExtension; }
- (void)setExtensionHidden:(BOOL)f { _hiddenExtension = f; }
- (BOOL)showsHiddenFiles { return _showHidden; }
- (void)setShowsHiddenFiles:(BOOL)f { _showHidden = f; }
- (BOOL)treatsFilePackagesAsDirectories { return _packages; }
- (void)setTreatsFilePackagesAsDirectories:(BOOL)f { _packages = f; }
- (BOOL)showsTagField { return _tagField; }
- (void)setShowsTagField:(BOOL)f { _tagField = f; }
- (NSView *)accessoryView { return _accessory; }
- (void)setAccessoryView:(NSView *)v
{
    [_accessory autorelease];
    _accessory = [v retain];
}
- (id)delegate { return _panelDelegate; }
- (void)setDelegate:(id)d { _panelDelegate = d; }
- (BOOL)isExpanded { return YES; }

- (NSURL *)URL { return [_chosen firstObject]; }
- (NSString *)filename { return [[self URL] path]; }
- (NSString *)directory { return [_directory path]; }
- (void)setDirectory:(NSString *)path { [self setDirectoryURL:path ? [NSURL fileURLWithPath:path isDirectory:YES] : nil]; }
- (NSString *)requiredFileType { return [_types firstObject]; }
- (void)setRequiredFileType:(NSString *)type { [self setAllowedFileTypes:type ? @[ type ] : nil]; }

- (IBAction)ok:(id)sender {}
- (IBAction)cancel:(id)sender {}
- (void)validateVisibleColumns {}

/* What kind of chooser, and whether more than one file may be chosen. */
- (int)_action { return GTK_FILE_CHOOSER_ACTION_SAVE; }
- (BOOL)_multiple { return NO; }
- (NSString *)_defaultTitle { return @"Save"; }

/* A save panel's name gets the first allowed extension if it has none of
 * them, as on a Mac. */
- (NSURL *)_fixedURL:(NSURL *)url
{
    if ([self _action] != GTK_FILE_CHOOSER_ACTION_SAVE || ![_types count])
        return url;
    NSString *ext = [[url pathExtension] lowercaseString];
    for (NSString *t in _types)
        if ([AExtensionsForType(t) containsObject:ext])
            return url;
    if (_otherTypes && [ext length])
        return url;
    NSString *first = [AExtensionsForType([_types firstObject]) firstObject];
    if (!first)
        return url;
    /* the extension of a type allowed before the format was changed is
     * replaced, as a Mac's panel changes it as the format menu does */
    for (NSString *t in _startTypes)
        if ([ext length] && [AExtensionsForType(t) containsObject:ext])
            return [[url URLByDeletingPathExtension] URLByAppendingPathExtension:first];
    return [url URLByAppendingPathExtension:first];
}

/* ---- the accessory view's controls, as the chooser's choices ---- */

static void collect_controls(NSView *v, NSMutableArray *popups, NSMutableArray *boxes, NSMutableArray *labels)
{
    if ([v isHidden])
        return;
    if ([v isKindOfClass:[NSPopUpButton class]]) {
        if ([(NSPopUpButton *)v isEnabled] && ![(NSPopUpButton *)v pullsDown])
            [popups addObject:v];
        return;
    }
    if ([v isKindOfClass:[NSButton class]]) {
        if ([(NSButton *)v isEnabled] && [(id)v _buttonType] == NSButtonTypeSwitch && [[(NSButton *)v title] length])
            [boxes addObject:v];
        return;
    }
    if ([v isKindOfClass:[NSTextField class]]) {
        NSTextField *t = (NSTextField *)v;
        if (![t isEditable] && [[t stringValue] length])
            [labels addObject:v];
        return;
    }
    for (NSView *sub in [v subviews])
        collect_controls(sub, popups, boxes, labels);
}

/* The label on a pop-up's left on its line, nearest it ("Format:"). */
static NSString *label_for(NSView *popup, NSArray *labels, NSView *root)
{
    NSRect p = [root convertRect:[popup bounds] fromView:popup];
    NSTextField *best = nil;
    CGFloat gap = CGFLOAT_MAX;
    for (NSTextField *t in labels) {
        NSRect r = [root convertRect:[t bounds] fromView:t];
        if (NSMaxY(r) <= NSMinY(p) || NSMinY(r) >= NSMaxY(p) || NSMinX(r) > NSMinX(p))
            continue;
        CGFloat g = NSMinX(p) - NSMaxX(r);
        if (g < gap)
            gap = g, best = t;
    }
    NSString *s = [[best stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([s hasSuffix:@":"])
        s = [s substringToIndex:[s length] - 1];
    return [s length] ? s : nil;
}

/* Each choice: its label, its control, and for a pop-up the indexes and
 * titles of the items that can be chosen. */
- (NSArray *)_choices
{
    if (!_accessory)
        return @[];
    NSMutableArray *popups = [NSMutableArray array], *boxes = [NSMutableArray array], *labels = [NSMutableArray array];
    collect_controls(_accessory, popups, boxes, labels);
    NSMutableArray *out = [NSMutableArray array];
    for (NSPopUpButton *b in popups) {
        NSMutableArray *indexes = [NSMutableArray array], *titles = [NSMutableArray array];
        NSArray *items = [b itemArray];
        for (NSUInteger i = 0; i < [items count]; i++) {
            NSMenuItem *it = items[i];
            if ([it isSeparatorItem] || ![it isEnabled] || [it isHidden] || ![[it title] length])
                continue;
            [indexes addObject:@(i)];
            [titles addObject:[it title]];
        }
        if (![titles count])
            continue;
        NSString *label = label_for(b, labels, _accessory) ?: ([popups count] == 1 ? @"Format" : @"Option");
        [out addObject:@{ @"label" : label, @"control" : b, @"indexes" : indexes, @"titles" : titles }];
    }
    for (NSButton *b in boxes)
        [out addObject:@{ @"label" : [b title], @"control" : b }];
    return out;
}

/* The choice's value as it is now: a pop-up's item index, or "true". */
static NSString *current_value(NSDictionary *c)
{
    id control = c[@"control"];
    if (c[@"titles"])
        return [NSString stringWithFormat:@"%ld", (long)[control indexOfSelectedItem]];
    return [(NSButton *)control state] == NSControlStateValueOn ? @"true" : @"false";
}

/* A value the chooser gave back, put into its control as a click would. */
static void apply_value(NSDictionary *c, NSString *value)
{
    if (!value || [value isEqualToString:current_value(c)])
        return;
    id control = c[@"control"];
    if (c[@"titles"]) {
        NSInteger i = [value integerValue];
        if (![c[@"indexes"] containsObject:@(i)])
            return;
        [[control cell] _menuView:nil didChooseItem:[control itemAtIndex:i]];
    } else {
        NSButton *b = control;
        [b setState:[value isEqualToString:@"true"] ? NSControlStateValueOn : NSControlStateValueOff];
        ABindingsPush(b, NO);
        [b sendAction:[b action] to:[b target]];
    }
}

static const char **cstrings(NSArray *strings)
{
    const char **v = calloc([strings count] + 1, sizeof *v);
    for (NSUInteger i = 0; i < [strings count]; i++)
        v[i] = [[strings[i] description] UTF8String];
    return v;
}

- (void)_addChoices:(NSArray *)choices toChooser:(void *)chooser
{
    for (NSUInteger k = 0; k < [choices count]; k++) {
        NSDictionary *c = choices[k];
        char id[16];
        snprintf(id, sizeof id, "c%lu", (unsigned long)k);
        if (c[@"titles"]) {
            const char **ids = cstrings(c[@"indexes"]), **titles = cstrings(c[@"titles"]);
            gtk_file_chooser_add_choice(chooser, id, [c[@"label"] UTF8String], ids, titles);
            free(ids);
            free(titles);
        } else
            gtk_file_chooser_add_choice(chooser, id, [c[@"label"] UTF8String], NULL, NULL);
        gtk_file_chooser_set_choice(chooser, id, [current_value(c) UTF8String]);
    }
}

- (void)_takeChoices:(NSArray *)choices fromChooser:(void *)chooser
{
    for (NSUInteger k = 0; k < [choices count]; k++) {
        char id[16];
        snprintf(id, sizeof id, "c%lu", (unsigned long)k);
        const char *v = gtk_file_chooser_get_choice(chooser, id);
        apply_value(choices[k], v ? @(v) : nil);
    }
}

/* FERRY_PANEL_CHOICES: "Label=Option" lines, an option by its title, a
 * check box by true or false. */
- (void)_takeScriptedChoices:(NSArray *)choices
{
    const char *env = getenv("FERRY_PANEL_CHOICES");
    if (!env)
        return;
    for (NSString *line in [@(env) componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound)
            continue;
        NSString *label = [line substringToIndex:eq.location], *want = [line substringFromIndex:NSMaxRange(eq)];
        for (NSDictionary *c in choices) {
            if (![c[@"label"] isEqualToString:label])
                continue;
            if (c[@"titles"]) {
                NSUInteger i = [c[@"titles"] indexOfObject:want];
                if (i != NSNotFound)
                    apply_value(c, [c[@"indexes"][i] description]);
            } else
                apply_value(c, [want isEqualToString:@"true"] ? @"true" : @"false");
            break;
        }
    }
}

- (BOOL)_accept:(NSArray *)paths
{
    [_chosen removeAllObjects];
    for (NSString *p in paths) {
        if (![p length])
            continue;
        if (![p isAbsolutePath])
            p = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:p];
        [_chosen addObject:[self _fixedURL:[NSURL fileURLWithPath:p]]];
    }
    if (![_chosen count])
        return NO;
    if ([_panelDelegate respondsToSelector:@selector(panel:validateURL:error:)])
        for (NSURL *u in _chosen)
            if (![_panelDelegate panel:self validateURL:u error:NULL]) {
                [_chosen removeAllObjects];
                return NO;
            }
    [self setDirectoryURL:[[_chosen firstObject] URLByDeletingLastPathComponent]];
    if ([self _action] == GTK_FILE_CHOOSER_ACTION_SAVE)
        [self setNameFieldStringValue:[[_chosen firstObject] lastPathComponent]];
    return YES;
}

#define FOLDER_RESPONSE 1
- (BOOL)_choosesFilesAndFolders { return NO; }

- (NSModalResponse)_runChooser
{
    int action = [self _action];
    NSString *title = [self title];
    if (![title length] || [title isEqualToString:@"Window"])
        title = _message ?: [self _defaultTitle];
    /* an Open panel for files and folders: a dialog with a button that
     * chooses the folder that's selected, or the one being shown */
    BOOL both = [self _choosesFilesAndFolders];
    void *chooser;
    if (both) {
        chooser = gtk_file_chooser_dialog_new([title UTF8String], NULL, action, NULL, NULL);
        if (chooser) {
            gtk_dialog_add_button(chooser, "Cancel", GTK_RESPONSE_CANCEL);
            gtk_dialog_add_button(chooser, "Choose Folder", FOLDER_RESPONSE);
            gtk_dialog_add_button(chooser, [(_prompt ?: [self _defaultTitle]) UTF8String], GTK_RESPONSE_ACCEPT);
        }
    } else {
        chooser = gtk_file_chooser_native_new([title UTF8String], NULL, action,
                                              [(_prompt ?: [self _defaultTitle]) UTF8String], "Cancel");
    }
    if (!chooser)
        return NSModalResponseCancel;
    gtk_file_chooser_set_select_multiple(chooser, [self _multiple]);
    gtk_file_chooser_set_show_hidden(chooser, _showHidden);
    if (action == GTK_FILE_CHOOSER_ACTION_SAVE) {
        gtk_file_chooser_set_do_overwrite_confirmation(chooser, 1);
        gtk_file_chooser_set_create_folders(chooser, _createDirs);
        if ([_nameField length])
            gtk_file_chooser_set_current_name(chooser, [_nameField UTF8String]);
    }
    if ([_directory isFileURL])
        gtk_file_chooser_set_current_folder(chooser, [[_directory path] fileSystemRepresentation]);
    NSMutableArray *patterns = [NSMutableArray array];
    for (NSString *t in _types)
        for (NSString *e in AExtensionsForType(t) ?: @[])
            [patterns addObject:e];
    if ([patterns count] && action != GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER) {
        GtkFileFilter *filter = gtk_file_filter_new();
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *e in patterns) {
            /* both cases, since GTK's patterns are case-sensitive */
            gtk_file_filter_add_pattern(filter, [[@"*." stringByAppendingString:[e lowercaseString]] UTF8String]);
            gtk_file_filter_add_pattern(filter, [[@"*." stringByAppendingString:[e uppercaseString]] UTF8String]);
            [names addObject:[@"." stringByAppendingString:e]];
        }
        gtk_file_filter_set_name(filter, [[names componentsJoinedByString:@", "] UTF8String]);
        gtk_file_chooser_add_filter(chooser, filter);
        if (_otherTypes || action == GTK_FILE_CHOOSER_ACTION_SAVE) {
            GtkFileFilter *all = gtk_file_filter_new();
            gtk_file_filter_set_name(all, "All files");
            gtk_file_filter_add_pattern(all, "*");
            gtk_file_chooser_add_filter(chooser, all);
        }
    }
    NSArray *choices = [self _choices];
    [self _addChoices:choices toChooser:chooser];
    NSModalResponse answer = NSModalResponseCancel;
    for (;;) {
        int response = both ? gtk_dialog_run(chooser) : gtk_native_dialog_run(chooser);
        if (response != GTK_RESPONSE_ACCEPT && response != FOLDER_RESPONSE)
            break;
        [self _takeChoices:choices fromChooser:chooser];
        NSMutableArray *paths = [NSMutableArray array];
        GSList *names = gtk_file_chooser_get_filenames(chooser);
        for (GSList *n = names; n; n = n->next) {
            [paths addObject:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:n->data
                                                                                         length:strlen(n->data)]];
            g_free(n->data);
        }
        g_slist_free(names);
        if (response == FOLDER_RESPONSE) {
            NSMutableArray *dirs = [NSMutableArray array];
            for (NSString *p in paths) {
                BOOL dir = NO;
                if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir] && dir)
                    [dirs addObject:p];
            }
            if (![dirs count]) {
                char *here = gtk_file_chooser_get_current_folder(chooser);
                if (here) {
                    [dirs addObject:[[NSFileManager defaultManager] stringWithFileSystemRepresentation:here
                                                                                                length:strlen(here)]];
                    g_free(here);
                }
            }
            paths = dirs;
        }
        if ([self _accept:paths]) {
            answer = NSModalResponseOK;
            break;
        }
        NSBeep(); /* the delegate turned it down: ask again */
    }
    if (both)
        gtk_widget_destroy(chooser);
    else
        g_object_unref(chooser);
    return answer;
}

- (NSModalResponse)runModal
{
    [_chosen removeAllObjects];
    id wasStartTypes = _startTypes;
    _startTypes = [_types copy];
    [wasStartTypes release];
    if (ADisplayAvailable())
        return [self _runChooser];
    const char *answer = getenv("FERRY_PANEL_ANSWER");
    if (!answer) {
        AWarnOnce("Open and Save panels with no display (they answer Cancel)");
        return NSModalResponseCancel;
    }
    NSArray *paths = [[NSString stringWithUTF8String:answer] componentsSeparatedByString:@"\n"];
    if (![self _multiple] && [paths count] > 1)
        paths = [paths subarrayWithRange:NSMakeRange(0, 1)];
    [self _takeScriptedChoices:[self _choices]];
    return [self _accept:paths] ? NSModalResponseOK : NSModalResponseCancel;
}

- (void)_beginWith:(void (^)(NSModalResponse))handler
{
    [self retain];
    void (^h)(NSModalResponse) = [handler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSModalResponse r = [self runModal];
        if (h)
            h(r);
        [h release];
        [self release];
    });
}
- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler
{
    [self _beginWith:handler];
}
- (void)beginWithCompletionHandler:(void (^)(NSModalResponse))handler { [self _beginWith:handler]; }

/* The old calls */
- (NSInteger)runModalForDirectory:(NSString *)path file:(NSString *)name
{
    if (path)
        [self setDirectory:path];
    if (name)
        [self setNameFieldStringValue:name];
    return [self runModal];
}
- (void)beginSheetForDirectory:(NSString *)path file:(NSString *)name modalForWindow:(NSWindow *)window
                 modalDelegate:(id)delegate didEndSelector:(SEL)selector contextInfo:(void *)context
{
    if (path)
        [self setDirectory:path];
    if (name)
        [self setNameFieldStringValue:name];
    [self beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        if (delegate && selector)
            ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, selector, self, r, context);
    }];
}
@end

@implementation NSOpenPanel {
    BOOL _files, _dirs, _multipleSelection, _resolves, _disclosed;
}

+ (NSOpenPanel *)openPanel { return [[[self alloc] init] autorelease]; }

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style
                            backing:(NSBackingStoreType)backing defer:(BOOL)defer
{
    if ((self = [super initWithContentRect:rect styleMask:style backing:backing defer:defer])) {
        _files = YES;
        _resolves = YES;
        _createDirs = NO;
        _otherTypes = NO;
    }
    return self;
}

- (NSArray *)URLs { return [[_chosen copy] autorelease]; }
- (NSArray *)filenames { return [_chosen valueForKey:@"path"]; }
- (BOOL)canChooseFiles { return _files; }
- (void)setCanChooseFiles:(BOOL)f { _files = f; }
- (BOOL)canChooseDirectories { return _dirs; }
- (void)setCanChooseDirectories:(BOOL)f { _dirs = f; }
- (BOOL)allowsMultipleSelection { return _multipleSelection; }
- (void)setAllowsMultipleSelection:(BOOL)f { _multipleSelection = f; }
- (BOOL)resolvesAliases { return _resolves; }
- (void)setResolvesAliases:(BOOL)f { _resolves = f; }
- (BOOL)isAccessoryViewDisclosed { return _disclosed; }
- (void)setAccessoryViewDisclosed:(BOOL)f { _disclosed = f; }
- (BOOL)canDownloadUbiquitousContents { return NO; }
- (void)setCanDownloadUbiquitousContents:(BOOL)f {}
- (BOOL)canResolveUbiquitousConflicts { return NO; }
- (void)setCanResolveUbiquitousConflicts:(BOOL)f {}

- (int)_action
{
    if (_dirs && !_files)
        return GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;
    return GTK_FILE_CHOOSER_ACTION_OPEN;
}
- (BOOL)_choosesFilesAndFolders { return _files && _dirs; }
- (BOOL)_multiple { return _multipleSelection; }
- (NSString *)_defaultTitle { return @"Open"; }

/* Only what the panel may choose: files of the allowed types, or folders. */
- (BOOL)_accept:(NSArray *)paths
{
    NSMutableArray *ok = [NSMutableArray array];
    for (NSString *p in paths) {
        BOOL dir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir])
            continue;
        if (dir ? !_dirs : !_files)
            continue;
        if (!dir && [_types count] && !_otherTypes) {
            NSString *ext = [[p pathExtension] lowercaseString];
            BOOL allowed = NO;
            for (NSString *t in _types)
                allowed |= [AExtensionsForType(t) containsObject:ext] || ![AExtensionsForType(t) count];
            if (!allowed)
                continue;
        }
        if ([_panelDelegate respondsToSelector:@selector(panel:shouldEnableURL:)] &&
            ![_panelDelegate panel:self shouldEnableURL:[NSURL fileURLWithPath:p]])
            continue;
        [ok addObject:p];
    }
    return [super _accept:ok];
}

- (NSInteger)runModalForTypes:(NSArray *)types
{
    [self setAllowedFileTypes:types];
    return [self runModal];
}
- (NSInteger)runModalForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)types
{
    [self setAllowedFileTypes:types];
    return [self runModalForDirectory:path file:name];
}
@end
