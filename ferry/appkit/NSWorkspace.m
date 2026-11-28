/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSWorkspace and NSWorkspaceOpenConfiguration. Ferry's own
 * code, written from Apple's public NSWorkspace documentation; no Apple
 * code, artwork or headers were used. Files, folders and web addresses are
 * opened by the desktop's own launcher, "gio open", or "xdg-open" where
 * there's no gio, started directly with the address as its one argument,
 * with no shell between; that is the only way Ferry starts anything outside
 * itself, so another Mac app is never launched (launchApplication: answers
 * NO). Showing a file "in the Finder" opens the folder that holds it. Icons
 * are the desktop's icon theme's icon for the file's content type (GIO
 * says which), drawn by GTK at 32 points; an app bundle shows its own icon,
 * and a plain page or folder drawn by Ferry stands in when the theme has
 * none. The workspace's notification centre and its notifications are all
 * there, but nothing on this system posts the sleep, wake, launch or mount
 * ones. Built without ARC. */
#import "AInternal.h"
#include <dispatch/dispatch.h>

NSNotificationName const NSWorkspaceWillLaunchApplicationNotification = @"NSWorkspaceWillLaunchApplicationNotification";
NSNotificationName const NSWorkspaceDidLaunchApplicationNotification = @"NSWorkspaceDidLaunchApplicationNotification";
NSNotificationName const NSWorkspaceDidTerminateApplicationNotification =
    @"NSWorkspaceDidTerminateApplicationNotification";
NSNotificationName const NSWorkspaceDidActivateApplicationNotification =
    @"NSWorkspaceDidActivateApplicationNotification";
NSNotificationName const NSWorkspaceDidDeactivateApplicationNotification =
    @"NSWorkspaceDidDeactivateApplicationNotification";
NSNotificationName const NSWorkspaceDidHideApplicationNotification = @"NSWorkspaceDidHideApplicationNotification";
NSNotificationName const NSWorkspaceDidUnhideApplicationNotification = @"NSWorkspaceDidUnhideApplicationNotification";
NSNotificationName const NSWorkspaceWillSleepNotification = @"NSWorkspaceWillSleepNotification";
NSNotificationName const NSWorkspaceDidWakeNotification = @"NSWorkspaceDidWakeNotification";
NSNotificationName const NSWorkspaceScreensDidSleepNotification = @"NSWorkspaceScreensDidSleepNotification";
NSNotificationName const NSWorkspaceScreensDidWakeNotification = @"NSWorkspaceScreensDidWakeNotification";
NSNotificationName const NSWorkspaceWillPowerOffNotification = @"NSWorkspaceWillPowerOffNotification";
NSNotificationName const NSWorkspaceSessionDidBecomeActiveNotification =
    @"NSWorkspaceSessionDidBecomeActiveNotification";
NSNotificationName const NSWorkspaceSessionDidResignActiveNotification =
    @"NSWorkspaceSessionDidResignActiveNotification";
NSNotificationName const NSWorkspaceDidMountNotification = @"NSWorkspaceDidMountNotification";
NSNotificationName const NSWorkspaceWillUnmountNotification = @"NSWorkspaceWillUnmountNotification";
NSNotificationName const NSWorkspaceDidUnmountNotification = @"NSWorkspaceDidUnmountNotification";
NSNotificationName const NSWorkspaceActiveSpaceDidChangeNotification = @"NSWorkspaceActiveSpaceDidChangeNotification";
NSString *const NSWorkspaceApplicationKey = @"NSWorkspaceApplicationKey";

@implementation NSWorkspaceOpenConfiguration {
    BOOL _activates, _prompts, _addsToRecent, _hides, _newInstance;
    NSArray *_arguments;
}
+ (instancetype)configuration { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        _activates = YES;
        _addsToRecent = YES;
        _arguments = [[NSArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_arguments release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSWorkspaceOpenConfiguration *c = [[[self class] alloc] init];
    c->_activates = _activates;
    c->_prompts = _prompts;
    c->_addsToRecent = _addsToRecent;
    c->_hides = _hides;
    c->_newInstance = _newInstance;
    [c setArguments:_arguments];
    return c;
}
- (BOOL)activates { return _activates; }
- (void)setActivates:(BOOL)f { _activates = f; }
- (BOOL)promptsUserIfNeeded { return _prompts; }
- (void)setPromptsUserIfNeeded:(BOOL)f { _prompts = f; }
- (BOOL)addsToRecentItems { return _addsToRecent; }
- (void)setAddsToRecentItems:(BOOL)f { _addsToRecent = f; }
- (BOOL)hides { return _hides; }
- (void)setHides:(BOOL)f { _hides = f; }
- (BOOL)createsNewApplicationInstance { return _newInstance; }
- (void)setCreatesNewApplicationInstance:(BOOL)f { _newInstance = f; }
- (NSArray *)arguments { return _arguments; }
- (void)setArguments:(NSArray *)a
{
    a = [a copy] ?: [[NSArray alloc] init];
    [_arguments release];
    _arguments = a;
}
@end

/* ---- the desktop's launcher ---------------------------------------------------------- */

/* Starts "gio open <address>", or "xdg-open <address>": one argument, no
 * shell, so nothing in the address is read as a command. */
static BOOL launch(NSString *address)
{
    if (![address length] || [address hasPrefix:@"-"])
        return NO;
    char *gio = g_find_program_in_path("gio");
    char *xdg = gio ? NULL : g_find_program_in_path("xdg-open");
    if (!gio && !xdg) {
        AWarnOnce("opening files and addresses (neither gio nor xdg-open is installed)");
        return NO;
    }
    char *argv[4];
    int n = 0;
    argv[n++] = gio ?: xdg;
    if (gio)
        argv[n++] = (char *)"open";
    argv[n++] = (char *)[address UTF8String];
    argv[n] = NULL;
    GError *error = NULL;
    BOOL ok = g_spawn_async(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL, NULL, NULL,
                            NULL, &error) != 0;
    if (error)
        g_error_free(error);
    g_free(gio);
    g_free(xdg);
    return ok;
}

/* Runs "gio mount -e <path>" (eject, which unmounts first) and waits for
 * it; one argument, no shell. */
static BOOL eject(NSString *path, NSError **error)
{
    char *gio = g_find_program_in_path("gio");
    BOOL ok = NO;
    if (gio && [path length] && ![path hasPrefix:@"-"]) {
        char *argv[] = {gio, (char *)"mount", (char *)"-e", (char *)[path fileSystemRepresentation], NULL};
        int status = -1;
        ok = g_spawn_sync(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL, NULL, NULL,
                          NULL, NULL, &status, NULL) && g_spawn_check_wait_status(status, NULL);
    } else if (!gio)
        AWarnOnce("ejecting disks (gio is not installed)");
    g_free(gio);
    if (!ok && error)
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                                 userInfo:path ? [NSDictionary dictionaryWithObject:path forKey:NSFilePathErrorKey] : nil];
    return ok;
}

static NSString *file_address(NSString *path)
{
    if (![path length])
        return nil;
    path = [path stringByStandardizingPath];
    if (![path isAbsolutePath])
        path = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:path];
    return [[NSURL fileURLWithPath:path] absoluteString];
}

/* ---- icons ---------------------------------------------------------------------------- */

static NSImage *themed_icon(NSString *contentType)
{
    if (![contentType length])
        return nil;
    static GtkIconTheme *theme;
    if (!theme) {
        if (ADisplayAvailable()) {
            theme = gtk_icon_theme_get_default();
        } else {
            theme = gtk_icon_theme_new();
            if (theme)
                gtk_icon_theme_set_custom_theme(theme, "Adwaita");
        }
        if (!theme)
            return nil;
    }
    NSMutableArray *names = [NSMutableArray array];
    GIcon *gicon = g_content_type_get_icon([contentType UTF8String]);
    if (gicon) {
        const char *const *list = g_themed_icon_get_names(gicon);
        for (int i = 0; list && list[i]; i++)
            [names addObject:[NSString stringWithUTF8String:list[i]]];
        g_object_unref(gicon);
    }
    char *generic = g_content_type_get_generic_icon_name([contentType UTF8String]);
    if (generic) {
        [names addObject:[NSString stringWithUTF8String:generic]];
        g_free(generic);
    }
    [names addObject:@"text-x-generic"];
    for (NSString *name in names) {
        if (!gtk_icon_theme_has_icon(theme, [name UTF8String]))
            continue;
        GError *error = NULL;
        GdkPixbuf *pixbuf = gtk_icon_theme_load_icon(theme, [name UTF8String], 64, GTK_ICON_LOOKUP_FORCE_SIZE, &error);
        if (error)
            g_error_free(error);
        if (!pixbuf)
            continue;
        char *buffer = NULL;
        unsigned long size = 0;
        int saved = gdk_pixbuf_save_to_bufferv(pixbuf, &buffer, &size, "png", NULL, NULL, NULL);
        g_object_unref(pixbuf);
        if (!saved || !buffer)
            continue;
        NSData *png = [NSData dataWithBytes:buffer length:size];
        g_free(buffer);
        NSImage *image = [[[NSImage alloc] initWithData:png] autorelease];
        if ([image isValid]) {
            [image setSize:NSMakeSize(32, 32)];
            return image;
        }
    }
    return nil;
}

/* Ferry's own stand-ins: a page with a folded corner, or a folder. */
static NSImage *drawn_icon(BOOL folder)
{
    return [NSImage imageWithSize:NSMakeSize(32, 32) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSBezierPath *p = [NSBezierPath bezierPath];
        if (folder) {
            [[NSColor colorWithCalibratedRed:0.36 green:0.62 blue:0.9 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 4, 28, 20) xRadius:2 yRadius:2] fill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 20, 12, 6) xRadius:2 yRadius:2] fill];
            [[NSColor colorWithCalibratedRed:0.5 green:0.74 blue:0.97 alpha:1] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 4, 28, 16) xRadius:2 yRadius:2] fill];
            return YES;
        }
        [p moveToPoint:NSMakePoint(6.5, 1.5)];
        [p lineToPoint:NSMakePoint(25.5, 1.5)];
        [p lineToPoint:NSMakePoint(25.5, 23.5)];
        [p lineToPoint:NSMakePoint(18.5, 30.5)];
        [p lineToPoint:NSMakePoint(6.5, 30.5)];
        [p closePath];
        [[NSColor whiteColor] setFill];
        [p fill];
        [[NSColor colorWithWhite:0.6 alpha:1] setStroke];
        [p stroke];
        NSBezierPath *fold = [NSBezierPath bezierPath];
        [fold moveToPoint:NSMakePoint(18.5, 30.5)];
        [fold lineToPoint:NSMakePoint(18.5, 23.5)];
        [fold lineToPoint:NSMakePoint(25.5, 23.5)];
        [fold stroke];
        return YES;
    }];
}

static NSString *content_type_for_name(NSString *name, BOOL directory)
{
    if (directory)
        return @"inode/directory";
    gboolean uncertain = 0;
    char *t = g_content_type_guess([name UTF8String], NULL, 0, &uncertain);
    if (!t)
        return nil;
    NSString *s = [NSString stringWithUTF8String:t];
    g_free(t);
    return s;
}

static NSImage *icon_for(NSString *name, BOOL directory)
{
    static NSMutableDictionary *cache;
    if (!cache)
        cache = [[NSMutableDictionary alloc] init];
    NSString *ext = directory ? @"/" : [[name pathExtension] lowercaseString];
    NSImage *icon = cache[ext];
    if (icon)
        return [[icon copy] autorelease];
    icon = themed_icon(content_type_for_name(name, directory)) ?: drawn_icon(directory);
    cache[ext] = icon;
    return [[icon copy] autorelease];
}

/* ---- types -------------------------------------------------------------------------- */

static NSString *uti_for_extension(NSString *ext)
{
    ext = [ext lowercaseString];
    /* the app's own declared types first */
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ]) {
        for (NSDictionary *d in info[key]) {
            if (![d isKindOfClass:[NSDictionary class]])
                continue;
            id exts = d[@"UTTypeTagSpecification"][@"public.filename-extension"];
            if ([exts isKindOfClass:[NSString class]])
                exts = @[ exts ];
            for (NSString *e in exts)
                if ([e isKindOfClass:[NSString class]] && [[e lowercaseString] isEqualToString:ext])
                    return d[@"UTTypeIdentifier"];
        }
    }
    NSDictionary *known = @{
        @"txt" : @"public.plain-text", @"text" : @"public.plain-text", @"png" : @"public.png",
        @"jpg" : @"public.jpeg", @"jpeg" : @"public.jpeg", @"tif" : @"public.tiff", @"tiff" : @"public.tiff",
        @"gif" : @"com.compuserve.gif", @"bmp" : @"com.microsoft.bmp", @"pdf" : @"com.adobe.pdf",
        @"html" : @"public.html", @"htm" : @"public.html", @"rtf" : @"public.rtf", @"xml" : @"public.xml",
        @"json" : @"public.json", @"csv" : @"public.comma-separated-values-text",
        @"plist" : @"com.apple.property-list", @"app" : @"com.apple.application-bundle",
    };
    return known[ext];
}

@implementation NSWorkspace {
    NSNotificationCenter *_center;
}

+ (NSWorkspace *)sharedWorkspace
{
    static NSWorkspace *shared;
    if (!shared)
        shared = [[NSWorkspace alloc] init];
    return shared;
}

- (NSNotificationCenter *)notificationCenter
{
    if (!_center)
        _center = [[NSNotificationCenter alloc] init];
    return _center;
}

- (BOOL)openURL:(NSURL *)url
{
    if (![[url scheme] length])
        return NO;
    return launch([url absoluteString]);
}

- (void)openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^)(NSRunningApplication *, NSError *))handler
{
    BOOL ok = [self openURL:url];
    if (!handler)
        return;
    void (^h)(NSRunningApplication *, NSError *) = [handler copy];
    NSError *error = ok ? nil : [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
                                                userInfo:url ? @{NSURLErrorKey : url} : nil];
    [error retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        h(nil, error);
        [h release];
        [error release];
    });
}

- (BOOL)unmountAndEjectDeviceAtURL:(NSURL *)url error:(NSError **)error
{
    return eject([url isFileURL] ? [url path] : nil, error);
}
- (BOOL)unmountAndEjectDeviceAtPath:(NSString *)path { return eject(path, NULL); }

- (BOOL)openFile:(NSString *)path
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:[path stringByStandardizingPath]])
        return NO;
    return launch(file_address(path));
}
- (BOOL)openFile:(NSString *)path withApplication:(NSString *)app
{
    if (app)
        AWarnOnce("opening a file with a chosen app (the desktop's own choice opens it)");
    return [self openFile:path];
}
- (BOOL)openFile:(NSString *)path withApplication:(NSString *)app andDeactivate:(BOOL)deactivate
{
    return [self openFile:path withApplication:app];
}

/* The Finder would show the file selected in its folder; the desktop's
 * file manager is opened on that folder. */
- (BOOL)selectFile:(NSString *)path inFileViewerRootedAtPath:(NSString *)root
{
    NSString *folder = [path length] ? [[path stringByStandardizingPath] stringByDeletingLastPathComponent] : root;
    if (![folder length])
        return NO;
    BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&dir] || !dir)
        return NO;
    return launch(file_address(folder));
}
- (void)activateFileViewerSelectingURLs:(NSArray *)urls
{
    NSMutableSet *done = [NSMutableSet set];
    for (NSURL *u in urls) {
        if (![u isFileURL])
            continue;
        NSString *folder = [[u path] stringByDeletingLastPathComponent];
        if ([done containsObject:folder])
            continue;
        [done addObject:folder];
        [self selectFile:[u path] inFileViewerRootedAtPath:@""];
    }
}

- (BOOL)launchApplication:(NSString *)name
{
    AWarnOnce("launching another app (Ferry starts only the desktop's launcher)");
    return NO;
}

- (NSImage *)iconForFile:(NSString *)path
{
    path = [path stringByStandardizingPath];
    BOOL dir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir];
    if (exists && dir && [[[path pathExtension] lowercaseString] isEqualToString:@"app"]) {
        NSBundle *b = [NSBundle bundleWithPath:path];
        NSString *file = [b objectForInfoDictionaryKey:@"CFBundleIconFile"];
        if ([file isKindOfClass:[NSString class]] && [file length]) {
            NSString *res = [b pathForResource:[file stringByDeletingPathExtension]
                                        ofType:[file pathExtension].length ? [file pathExtension] : @"icns"];
            NSImage *image = res ? [[[NSImage alloc] initWithContentsOfFile:res] autorelease] : nil;
            if ([image isValid]) {
                [image setSize:NSMakeSize(32, 32)];
                return image;
            }
        }
        return [self iconForFileType:@"com.apple.application-bundle"];
    }
    return icon_for([path lastPathComponent], exists && dir);
}

- (NSImage *)iconForFiles:(NSArray *)paths
{
    if ([paths count] == 1)
        return [self iconForFile:paths[0]];
    return icon_for(@"files", NO);
}

/* The alert icons that the HFS codes 'stop', 'caut' and 'note' name: a red
 * stop sign with a white bar, the caution triangle and the info circle. */
static NSImage *alert_icon(NSString *type)
{
    if ([type isEqualToString:@"'caut'"])
        return [NSImage imageNamed:NSImageNameCaution];
    if ([type isEqualToString:@"'note'"])
        return [NSImage imageNamed:NSImageNameInfo];
    if (![type isEqualToString:@"'stop'"])
        return nil;
    static NSImage *stop;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stop = [[NSImage imageWithSize:NSMakeSize(32, 32) flipped:NO drawingHandler:^BOOL(NSRect r) {
            NSBezierPath *p = [NSBezierPath bezierPath];
            for (int i = 0; i < 8; i++) {
                CGFloat a = M_PI / 8 + i * M_PI / 4;
                NSPoint pt = NSMakePoint(16 + 14.5 * cos(a), 16 + 14.5 * sin(a));
                if (i)
                    [p lineToPoint:pt];
                else
                    [p moveToPoint:pt];
            }
            [p closePath];
            [[NSColor colorWithRed:0.86 green:0.16 blue:0.14 alpha:1] setFill];
            [p fill];
            [[NSColor whiteColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(7, 13.5, 18, 5) xRadius:1.5 yRadius:1.5] fill];
            return YES;
        }] retain];
    });
    return stop;
}

/* A filename extension, a uniform type identifier, or an HFS type code. */
- (NSImage *)iconForFileType:(NSString *)type
{
    NSImage *alert = alert_icon(type);
    if (alert)
        return alert;
    if ([type isEqualToString:@"public.folder"] || [type isEqualToString:@"public.directory"] ||
        [type isEqualToString:@"'fldr'"] || [type isEqualToString:NSFileTypeDirectory])
        return icon_for(@"folder", YES);
    NSString *ext = type;
    if ([type rangeOfString:@"."].location != NSNotFound) {
        ext = [AExtensionsForType(type) firstObject];
        if (!ext) {
            for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ])
                for (NSDictionary *d in [[NSBundle mainBundle] infoDictionary][key])
                    if ([d isKindOfClass:[NSDictionary class]] && [d[@"UTTypeIdentifier"] isEqual:type]) {
                        id e = d[@"UTTypeTagSpecification"][@"public.filename-extension"];
                        ext = [e isKindOfClass:[NSArray class]] ? [e firstObject] : e;
                    }
        }
    }
    if ([ext isKindOfClass:[NSString class]] && [ext hasPrefix:@"'"])
        ext = nil;   /* an HFS code */
    return icon_for([ext isKindOfClass:[NSString class]] && [ext length] ? [@"file." stringByAppendingString:ext]
                                                                         : @"file",
                    NO);
}

- (BOOL)setIcon:(NSImage *)image forFile:(NSString *)path options:(NSUInteger)options { return NO; }

static NSString *app_with(BOOL (^match)(NSBundle *))
{
    NSBundle *main = [NSBundle mainBundle];
    if (match(main))
        return [main bundlePath];
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    if (home)
        [dirs addObject:[home stringByAppendingPathComponent:@"Applications"]];
    [dirs addObject:@"/Applications"];
    for (NSString *dir in dirs) {
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
            if (![[[name pathExtension] lowercaseString] isEqualToString:@"app"])
                continue;
            NSString *path = [dir stringByAppendingPathComponent:name];
            NSBundle *b = [NSBundle bundleWithPath:path];
            if (b && match(b))
                return path;
        }
    }
    return nil;
}

/* Only Mac apps Ferry can see: this one, and those in ~/Applications and
 * /Applications; nil for any other. */
- (NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)identifier
{
    if (![identifier length])
        return nil;
    NSString *path = app_with(^BOOL(NSBundle *b) {
        /* a bundle with no identifier (a bare program's) matches none */
        NSString *ident = [b bundleIdentifier];
        return [ident length] && [ident caseInsensitiveCompare:identifier] == NSOrderedSame;
    });
    return path ? [NSURL fileURLWithPath:path] : nil;
}
- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)identifier
{
    return [[self URLForApplicationWithBundleIdentifier:identifier] path];
}
- (NSString *)fullPathForApplication:(NSString *)name
{
    if (![name length])
        return nil;
    NSString *want = [[name lastPathComponent] stringByDeletingPathExtension];
    return app_with(^BOOL(NSBundle *b) {
        return [[[[b bundlePath] lastPathComponent] stringByDeletingPathExtension] isEqualToString:want];
    });
}
- (NSURL *)URLForApplicationToOpenURL:(NSURL *)url { return nil; }

- (BOOL)isFilePackageAtPath:(NSString *)path
{
    BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir] || !dir)
        return NO;
    NSString *ext = [[path pathExtension] lowercaseString];
    if ([@[ @"app", @"bundle", @"framework", @"plugin", @"kext", @"rtfd", @"pkg", @"xcodeproj" ] containsObject:ext])
        return YES;
    for (NSDictionary *t in [[NSBundle mainBundle] infoDictionary][@"CFBundleDocumentTypes"]) {
        if (![t isKindOfClass:[NSDictionary class]] || ![t[@"LSTypeIsPackage"] boolValue])
            continue;
        for (NSString *e in t[@"CFBundleTypeExtensions"])
            if ([e isKindOfClass:[NSString class]] && [[e lowercaseString] isEqualToString:ext])
                return YES;
    }
    return NO;
}

- (NSString *)typeOfFile:(NSString *)path error:(NSError **)error
{
    BOOL dir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir]) {
        if (error)
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                     userInfo:@{NSFilePathErrorKey : path ?: @""}];
        return nil;
    }
    NSString *uti = uti_for_extension([path pathExtension]);
    if (uti)
        return uti;
    if (dir)
        return [self isFilePackageAtPath:path] ? @"com.apple.package" : @"public.folder";
    return @"public.data";
}

- (NSString *)localizedDescriptionForType:(NSString *)type
{
    for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ])
        for (NSDictionary *d in [[NSBundle mainBundle] infoDictionary][key])
            if ([d isKindOfClass:[NSDictionary class]] && [d[@"UTTypeIdentifier"] isEqual:type] &&
                d[@"UTTypeDescription"])
                return d[@"UTTypeDescription"];
    NSDictionary *names = @{
        @"public.plain-text" : @"Plain Text Document", @"public.folder" : @"Folder",
        @"com.adobe.pdf" : @"PDF Document", @"public.png" : @"PNG image", @"public.jpeg" : @"JPEG image",
        @"public.html" : @"HTML document", @"public.rtf" : @"Rich Text Document",
        @"com.apple.application-bundle" : @"Application", @"public.data" : @"Document",
    };
    return names[type] ?: type;
}

- (NSString *)preferredFilenameExtensionForType:(NSString *)type
{
    return [AExtensionsForType(type) firstObject];
}
- (BOOL)filenameExtension:(NSString *)extension isValidForType:(NSString *)type
{
    for (NSString *e in AExtensionsForType(type))
        if ([e caseInsensitiveCompare:extension] == NSOrderedSame)
            return YES;
    return [uti_for_extension(extension) isEqualToString:type];
}
- (BOOL)type:(NSString *)type conformsToType:(NSString *)other
{
    if ([type isEqualToString:other] || [other isEqualToString:@"public.item"] ||
        ([other isEqualToString:@"public.data"] && ![type isEqualToString:@"public.folder"]))
        return YES;
    if ([other isEqualToString:@"public.text"] &&
        [@[ @"public.plain-text", @"public.utf8-plain-text", @"public.html", @"public.rtf", @"public.xml",
            @"public.json", @"public.comma-separated-values-text" ] containsObject:type])
        return YES;
    if ([other isEqualToString:@"public.image"] &&
        [@[ @"public.png", @"public.jpeg", @"public.tiff", @"com.compuserve.gif", @"com.microsoft.bmp" ]
            containsObject:type])
        return YES;
    for (NSString *key in @[ @"UTExportedTypeDeclarations", @"UTImportedTypeDeclarations" ])
        for (NSDictionary *d in [[NSBundle mainBundle] infoDictionary][key])
            if ([d isKindOfClass:[NSDictionary class]] && [d[@"UTTypeIdentifier"] isEqual:type]) {
                id c = d[@"UTTypeConformsTo"];
                if ([c isKindOfClass:[NSString class]])
                    c = @[ c ];
                for (NSString *parent in c)
                    if ([parent isKindOfClass:[NSString class]] && [self type:parent conformsToType:other])
                        return YES;
            }
    return NO;
}
- (void)noteFileSystemChanged:(NSString *)path {}
@end

/* ---- file operations (freemac 1.223, Ferry 0.47.0) ----
 * Done at once by NSFileManager. Compressing, encrypting and their reverses
 * have no meaning here and answer NO. A duplicate is named "name copy" (then
 * "name copy 2" and on) beside the original, as the Finder names one. */
NSWorkspaceFileOperationName const NSWorkspaceMoveOperation = @"move";
NSWorkspaceFileOperationName const NSWorkspaceCopyOperation = @"copy";
NSWorkspaceFileOperationName const NSWorkspaceLinkOperation = @"link";
NSWorkspaceFileOperationName const NSWorkspaceCompressOperation = @"compress";
NSWorkspaceFileOperationName const NSWorkspaceDecompressOperation = @"decompress";
NSWorkspaceFileOperationName const NSWorkspaceEncryptOperation = @"encrypt";
NSWorkspaceFileOperationName const NSWorkspaceDecryptOperation = @"decrypt";
NSWorkspaceFileOperationName const NSWorkspaceDestroyOperation = @"destroy";
NSWorkspaceFileOperationName const NSWorkspaceRecycleOperation = @"recycle";
NSWorkspaceFileOperationName const NSWorkspaceDuplicateOperation = @"duplicate";
NSNotificationName const NSWorkspaceDidPerformFileOperationNotification =
    @"NSWorkspaceDidPerformFileOperationNotification";

static NSString *duplicate_path(NSString *path)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent], *ext = [path pathExtension];
    NSString *base = [[path lastPathComponent] stringByDeletingPathExtension];
    for (int n = 1; n < 10000; n++) {
        NSString *name = n == 1 ? [NSString stringWithFormat:@"%@ copy", base]
                                : [NSString stringWithFormat:@"%@ copy %d", base, n];
        if ([ext length])
            name = [name stringByAppendingPathExtension:ext];
        NSString *candidate = [dir stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:candidate])
            return candidate;
    }
    return nil;
}

@implementation NSWorkspace (NSWorkspaceFileOperations)
- (BOOL)performFileOperation:(NSWorkspaceFileOperationName)operation source:(NSString *)source
                 destination:(NSString *)destination files:(NSArray<NSString *> *)files tag:(NSInteger *)tag
{
    static NSInteger next_tag;
    NSInteger this_tag = ++next_tag;
    if (tag)
        *tag = this_tag;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL ok = YES;
    for (NSString *name in files) {
        NSString *from = [source stringByAppendingPathComponent:name];
        NSString *to = [destination length] ? [destination stringByAppendingPathComponent:name] : nil;
        BOOL done = NO;
        if ([operation isEqualToString:NSWorkspaceMoveOperation])
            done = to && [fm moveItemAtPath:from toPath:to error:NULL];
        else if ([operation isEqualToString:NSWorkspaceCopyOperation])
            done = to && [fm copyItemAtPath:from toPath:to error:NULL];
        else if ([operation isEqualToString:NSWorkspaceLinkOperation])
            done = to && [fm createSymbolicLinkAtPath:to withDestinationPath:from error:NULL];
        else if ([operation isEqualToString:NSWorkspaceDestroyOperation])
            done = [fm removeItemAtPath:from error:NULL];
        else if ([operation isEqualToString:NSWorkspaceRecycleOperation])
            done = [fm trashItemAtURL:[NSURL fileURLWithPath:from] resultingItemURL:NULL error:NULL];
        else if ([operation isEqualToString:NSWorkspaceDuplicateOperation]) {
            NSString *copy = duplicate_path(from);
            done = copy && [fm copyItemAtPath:from toPath:copy error:NULL];
        }
        ok = ok && done;
    }
    [[self notificationCenter] postNotificationName:NSWorkspaceDidPerformFileOperationNotification object:self
                                           userInfo:@{@"NSOperationNumber" : @(this_tag)}];
    return ok;
}

/* The block-based forms: the work is done at once, and the handler is
 * called on the main queue, as a Mac calls it. */
static void file_operation(BOOL recycle, NSArray<NSURL *> *urls,
                           void (^handler)(NSDictionary<NSURL *, NSURL *> *, NSError *))
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary *done = [NSMutableDictionary dictionary];
    NSError *firstError = nil;
    for (NSURL *url in urls) {
        NSError *error = nil;
        NSURL *result = nil;
        BOOL ok;
        if (recycle)
            ok = [fm trashItemAtURL:url resultingItemURL:&result error:&error];
        else {
            NSString *copy = duplicate_path([url path]);
            ok = copy && [fm copyItemAtPath:[url path] toPath:copy error:&error];
            result = ok ? [NSURL fileURLWithPath:copy] : nil;
        }
        if (ok && result)
            done[url] = result;
        else if (!firstError)
            firstError = error ? error
                               : [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                                                 userInfo:@{NSURLErrorKey : url}];
    }
    if (handler)
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(done, firstError);
        });
}
- (void)recycleURLs:(NSArray<NSURL *> *)urls
    completionHandler:(void (^)(NSDictionary<NSURL *, NSURL *> *, NSError *))handler
{
    file_operation(YES, urls, handler);
}
- (void)duplicateURLs:(NSArray<NSURL *> *)urls
    completionHandler:(void (^)(NSDictionary<NSURL *, NSURL *> *, NSError *))handler
{
    file_operation(NO, urls, handler);
}
@end
