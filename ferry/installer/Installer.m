/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Installer: opens a Mac installer package (.pkg) or disk image
 * (.dmg) in a window and installs what it holds, for the person using it:
 * apps go to ~/Applications, anything else into Ferry's own folder
 * (~/.local/share/ferry/root). It walks the steps a Mac's installer does
 * (introduction, read me, licence, destination, installation, summary) with
 * the package's own texts. It is a Mac program of our own, built with
 * ferry-cc against Ferry's AppKit, so it also exercises that AppKit.
 *
 * Scripts in a package and the checks its Distribution file makes (written
 * in JavaScript) are not run; the window says so when a package has them.
 *
 *   Installer [PACKAGE-OR-DISK-IMAGE]
 *   Installer --info PACKAGE-OR-DISK-IMAGE
 *   Installer --install PACKAGE-OR-DISK-IMAGE [--applications DIR] [--root DIR]
 */
#import <Cocoa/Cocoa.h>
#import "IPackage.h"
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>
int execlp(const char *file, const char *arg, ...);
int execl(const char *path, const char *arg, ...);

typedef NS_ENUM(NSInteger, IPage) { IPageIntro, IPageReadme, IPageLicense, IPageDestination, IPageInstall, IPageSummary };
static NSString *page_name(IPage p)
{
    switch (p) {
    case IPageIntro: return @"Introduction";
    case IPageReadme: return @"Read Me";
    case IPageLicense: return @"Licence";
    case IPageDestination: return @"Destination";
    case IPageInstall: return @"Installation";
    case IPageSummary: return @"Summary";
    }
    return @"";
}

static NSString *tilde(NSString *path) { return [path stringByAbbreviatingWithTildeInPath]; }

/* Tells the desktop about an installed app, when it has the command for it. */
static void register_app(NSString *app)
{
    if (getenv("FERRY_NO_DESKTOP_ENTRY"))
        return;
    pid_t pid = fork();
    if (pid == 0) {
        int null = open("/dev/null", O_WRONLY);
        if (null >= 0) {
            dup2(null, 1);
            dup2(null, 2);
        }
        execlp("freemac-mac-app", "freemac-mac-app", "install", [app fileSystemRepresentation], (char *)NULL);
        _exit(127);
    }
    if (pid > 0) {
        int status;
        waitpid(pid, &status, 0);
    }
}

/* ---- the step list down the left -------------------------------------------------------- */

@interface ISidebar : NSView
@property (retain) NSArray *pages;
@property NSInteger current;
@end
@implementation ISidebar
- (void)dealloc
{
    [_pages release];
    [super dealloc];
}
- (void)drawRect:(NSRect)dirty
{
    [[NSColor colorWithCalibratedWhite:0.94 alpha:1] setFill];
    NSRectFill([self bounds]);
    [[NSColor colorWithCalibratedWhite:0.82 alpha:1] setFill];
    NSRectFill(NSMakeRect(NSMaxX([self bounds]) - 1, 0, 1, [self bounds].size.height));
    CGFloat y = [self bounds].size.height - 48;
    for (NSUInteger i = 0; i < [_pages count]; i++) {
        IPage p = (IPage)[[_pages objectAtIndex:i] integerValue];
        BOOL now = (NSInteger)i == _current, done = (NSInteger)i < _current;
        NSColor *dot = now ? [NSColor controlAccentColor] : done ? [NSColor colorWithCalibratedWhite:0.55 alpha:1]
                                                              : [NSColor colorWithCalibratedWhite:0.8 alpha:1];
        [dot setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(20, y + 4, 8, 8)] fill];
        NSFont *f = now ? [NSFont boldSystemFontOfSize:13] : [NSFont systemFontOfSize:13];
        NSColor *c = now || done ? [NSColor labelColor] : [NSColor secondaryLabelColor];
        [page_name(p) drawAtPoint:NSMakePoint(38, y) withAttributes:@{NSFontAttributeName : f, NSForegroundColorAttributeName : c}];
        y -= 28;
    }
}
@end

/* ---- the app ------------------------------------------------------------------------------- */

@interface IController : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (copy) NSString *file;
@end

@implementation IController {
    NSWindow *_window;
    ISidebar *_sidebar;
    NSTextField *_heading, *_status;
    NSScrollView *_scroll;
    NSTextView *_text;
    NSView *_panel;              /* for pages that aren't one text */
    NSButton *_back, *_next, *_agree, *_open;
    NSProgressIndicator *_progress, *_spinner;
    IPackage *_pkg;
    IInstallJob *_job;
    NSMutableArray *_pages;
    NSInteger _at;
    NSString *_failure;
    BOOL _opening;
}

- (void)dealloc
{
    [_file release];
    [_pkg release];
    [_job release];
    [_pages release];
    [_failure release];
    [super dealloc];
}

- (NSTextField *)_label:(NSString *)s frame:(NSRect)f font:(NSFont *)font
{
    NSTextField *l = [NSTextField wrappingLabelWithString:s ?: @""];
    [l setFrame:f];
    [l setFont:font];
    return l;
}

- (void)_buildWindow
{
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 660, 460)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                    NSWindowStyleMaskMiniaturizable
                                            backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:@"Installer"];
    [_window setDelegate:self];
    [_window center];
    NSView *v = [_window contentView];
    _sidebar = [[[ISidebar alloc] initWithFrame:NSMakeRect(0, 0, 180, 460)] autorelease];
    [v addSubview:_sidebar];
    _heading = [self _label:@"" frame:NSMakeRect(200, 414, 440, 24) font:[NSFont boldSystemFontOfSize:15]];
    [v addSubview:_heading];

    _scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(200, 104, 440, 302)] autorelease];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setBorderType:NSBezelBorder];
    NSSize cs = [_scroll contentSize];
    _text = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, cs.width, cs.height)] autorelease];
    [_text setEditable:NO];
    [_text setTextContainerInset:NSMakeSize(10, 10)];
    [_text setAutoresizingMask:NSViewWidthSizable];
    [_scroll setDocumentView:_text];
    [v addSubview:_scroll];

    _panel = [[[NSView alloc] initWithFrame:NSMakeRect(200, 70, 440, 336)] autorelease];
    [_panel setHidden:YES];
    [v addSubview:_panel];

    _agree = [NSButton checkboxWithTitle:@"I have read and agree to the terms of the licence" target:self
                                  action:@selector(agreeChanged:)];
    [_agree setFrame:NSMakeRect(200, 72, 440, 22)];
    [_agree setHidden:YES];
    [v addSubview:_agree];

    NSBox *line = [[[NSBox alloc] initWithFrame:NSMakeRect(180, 56, 480, 1)] autorelease];
    [line setBoxType:NSBoxSeparator];
    [v addSubview:line];
    _back = [NSButton buttonWithTitle:@"Go Back" target:self action:@selector(goBack:)];
    [_back setFrame:NSMakeRect(410, 14, 110, 30)];
    [v addSubview:_back];
    _next = [NSButton buttonWithTitle:@"Continue" target:self action:@selector(goOn:)];
    [_next setFrame:NSMakeRect(530, 14, 110, 30)];
    [_next setKeyEquivalent:@"\r"];
    [v addSubview:_next];
    _open = [NSButton buttonWithTitle:@"Open" target:self action:@selector(openApp:)];
    [_open setFrame:NSMakeRect(290, 14, 110, 30)];
    [_open setHidden:YES];
    [v addSubview:_open];
}

/* ---- opening the package ---- */

- (void)_showOpening
{
    [_heading setStringValue:[NSString stringWithFormat:@"Opening “%@”…", [_file lastPathComponent]]];
    [_scroll setHidden:YES];
    [_panel setHidden:NO];
    _spinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(204, 150, 32, 32)] autorelease];
    [_spinner setStyle:NSProgressIndicatorStyleSpinning];
    [_panel addSubview:_spinner];
    [_spinner startAnimation:nil];
    [_back setEnabled:NO];
    [_next setEnabled:NO];
}

- (void)_open
{
    __block BOOL alive = YES;
    [IPackage setDiskImageWaiter:^BOOL {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        return alive;
    }];
    NSString *why = nil;
    _pkg = [[IPackage openPath:_file error:&why] retain];
    [IPackage setDiskImageWaiter:nil];
    [_spinner stopAnimation:nil];
    [_spinner removeFromSuperview];
    _spinner = nil;
    _opening = NO;
    if (!_pkg) {
        _failure = [[NSString stringWithFormat:@"“%@” can't be opened. %@", [_file lastPathComponent], why ?: @""] copy];
        _pages = [@[ @(IPageSummary) ] mutableCopy];
        [self _show:0];
        return;
    }
    [_window setTitle:[NSString stringWithFormat:@"Install %@", _pkg.title]];
    _pages = [[NSMutableArray alloc] initWithObjects:@(IPageIntro), nil];
    if ([_pkg.readme length])
        [_pages addObject:@(IPageReadme)];
    if ([_pkg.license length])
        [_pages addObject:@(IPageLicense)];
    [_pages addObjectsFromArray:@[ @(IPageDestination), @(IPageInstall), @(IPageSummary) ]];
    [self _show:0];
}

/* ---- pages ---- */

- (void)_showText:(NSAttributedString *)s
{
    [_scroll setHidden:NO];
    [_panel setHidden:YES];
    [[_text textStorage] setAttributedString:s ?: [[[NSAttributedString alloc] initWithString:@""] autorelease]];
    [_text setSelectedRange:NSMakeRange(0, 0)];
    [_text scrollRangeToVisible:NSMakeRange(0, 0)];
    [[_scroll contentView] scrollToPoint:NSZeroPoint];
}
- (void)_clearPanel
{
    for (NSView *sub in [_panel subviews])
        [sub removeFromSuperview];
    [_scroll setHidden:YES];
    [_panel setHidden:NO];
}
- (NSAttributedString *)_plain:(NSString *)s
{
    return [[[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName : [NSFont systemFontOfSize:13], NSForegroundColorAttributeName : [NSColor textColor]
    }] autorelease];
}
- (NSAttributedString *)_introduction
{
    if ([_pkg.welcome length]) {
        NSMutableAttributedString *m = [[_pkg.welcome mutableCopy] autorelease];
        NSString *notes = [self _notes];
        if ([notes length])
            [m appendAttributedString:[self _plain:[@"\n\n" stringByAppendingString:notes]]];
        return m;
    }
    NSString *what = [_pkg.apps count] ? [NSString stringWithFormat:@"This disk image holds %@.", [[_pkg.apps valueForKey:@"lastPathComponent"]
                                                                                                   componentsJoinedByString:@", "]]
                                       : @"You'll be guided through the steps to install this software.";
    return [self _plain:[NSString stringWithFormat:@"Welcome to the %@ installer.\n\n%@\n\n%@", _pkg.title, what,
                                                   [self _notes]]];
}
- (NSString *)_notes
{
    NSMutableArray *n = [NSMutableArray array];
    if (_pkg.hasChecks)
        [n addObject:@"This package checks the computer with scripts written in JavaScript, which Ferry doesn't run."];
    if (_pkg.hasScripts)
        [n addObject:@"It also has install scripts, which Ferry doesn't run, so anything only they set up will be "
                     @"missing."];
    return [n componentsJoinedByString:@" "];
}

- (void)_showDestination
{
    [self _clearPanel];
    IDestination *d = [IDestination standard];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"%@ will be installed for you alone; nothing outside your home folder changes.\n\n",
                    _pkg.title];
    [s appendFormat:@"Apps go to your Applications folder:\n    %@\n\n", tilde(d.applications)];
    if (![_pkg.apps count])
        [s appendFormat:@"Anything else the package holds (command-line tools, libraries, settings) goes into "
                        @"Ferry's own folder:\n    %@\n\n",
                        tilde(d.root)];
    [s appendFormat:@"This will take %@ of space.", IHumanSize(_pkg.installKBytes)];
    NSTextField *l = [self _label:s frame:NSMakeRect(4, 60, 432, 270) font:[NSFont systemFontOfSize:13]];
    [_panel addSubview:l];
    NSString *notes = [self _notes];
    if ([notes length]) {
        NSTextField *n = [self _label:notes frame:NSMakeRect(4, 4, 432, 50) font:[NSFont systemFontOfSize:11]];
        [n setTextColor:[NSColor secondaryLabelColor]];
        [_panel addSubview:n];
    }
}

- (void)_showInstall
{
    [self _clearPanel];
    _status = [self _label:@"Preparing…" frame:NSMakeRect(4, 190, 432, 20) font:[NSFont systemFontOfSize:13]];
    [_panel addSubview:_status];
    _progress = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(4, 160, 432, 20)] autorelease];
    [_progress setIndeterminate:NO];
    [_progress setMinValue:0];
    [_progress setMaxValue:1];
    [_panel addSubview:_progress];
    [_back setEnabled:NO];
    [_next setEnabled:NO];
    [_job release];
    _job = [[IInstallJob alloc] initWithPackage:_pkg destination:[IDestination standard]];
    [self performSelector:@selector(_installStep) withObject:nil afterDelay:0.05];
}
- (void)_installStep
{
    BOOL more = [_job step];
    [_progress setDoubleValue:_job.fraction];
    [_status setStringValue:_job.status ?: @""];
    if (more) {
        [self performSelector:@selector(_installStep) withObject:nil afterDelay:0];
        return;
    }
    if (_job.error)
        _failure = [_job.error copy];
    else
        for (NSString *app in _job.installedApps)
            register_app(app);
    [self _show:_at + 1];
}

- (void)_showSummary
{
    [self _clearPanel];
    NSMutableString *s = [NSMutableString string];
    NSString *head;
    if (_failure) {
        head = @"The installation failed.";
        [s appendString:_failure];
    } else {
        head = @"The installation was successful.";
        NSArray *apps = _job.installedApps;
        if ([apps count]) {
            [s appendString:[apps count] == 1 ? @"Installed in your Applications folder:\n" : @"Installed in your Applications folder:\n"];
            for (NSString *a in apps)
                [s appendFormat:@"    %@\n", [[a lastPathComponent] stringByDeletingPathExtension]];
        }
        if (_job.filesWritten && ![_pkg.apps count])
            [s appendFormat:@"\n%llu files in all.", _job.filesWritten];
        if ([_pkg.conclusion length])
            [s appendFormat:@"\n\n%@", [_pkg.conclusion string]];
    }
    NSTextField *h = [self _label:head frame:NSMakeRect(4, 290, 432, 24) font:[NSFont boldSystemFontOfSize:14]];
    [_panel addSubview:h];
    [_panel addSubview:[self _label:s frame:NSMakeRect(4, 40, 432, 240) font:[NSFont systemFontOfSize:13]]];
    if (!_failure && [_job.installedApps count] == 1) {
        [_open setTitle:[NSString stringWithFormat:@"Open %@", [[[_job.installedApps firstObject] lastPathComponent]
                                                                  stringByDeletingPathExtension]]];
        [_open sizeToFit];
        NSRect f = [_open frame];
        f.size.width = fmax(f.size.width + 20, 110);
        f.size.height = 30;
        f.origin = NSMakePoint(400 - f.size.width, 14);
        [_open setFrame:f];
        [_open setHidden:NO];
    }
}

- (void)_show:(NSInteger)index
{
    _at = MAX(0, MIN(index, (NSInteger)[_pages count] - 1));
    IPage p = (IPage)[[_pages objectAtIndex:(NSUInteger)_at] integerValue];
    _sidebar.pages = _pages;
    _sidebar.current = _at;
    [_sidebar setNeedsDisplay:YES];
    [_agree setHidden:p != IPageLicense];
    [_scroll setFrame:p == IPageLicense ? NSMakeRect(200, 104, 440, 302) : NSMakeRect(200, 70, 440, 336)];
    [_back setEnabled:_at > 0 && p != IPageSummary];
    [_back setHidden:p == IPageSummary];
    [_next setEnabled:YES];
    [_next setTitle:p == IPageDestination ? @"Install" : p == IPageSummary ? @"Close" : @"Continue"];
    switch (p) {
    case IPageIntro:
        [_heading setStringValue:[NSString stringWithFormat:@"Welcome to the %@ installer", _pkg.title]];
        [self _showText:[self _introduction]];
        break;
    case IPageReadme:
        [_heading setStringValue:@"Important information"];
        [self _showText:_pkg.readme];
        break;
    case IPageLicense:
        [_heading setStringValue:@"Software licence agreement"];
        [self _showText:_pkg.license];
        [_next setEnabled:[_agree state] == NSControlStateValueOn];
        break;
    case IPageDestination:
        [_heading setStringValue:[NSString stringWithFormat:@"Install %@ for you", _pkg.title]];
        [self _showDestination];
        break;
    case IPageInstall:
        [_heading setStringValue:[NSString stringWithFormat:@"Installing %@", _pkg.title]];
        [self _showInstall];
        break;
    case IPageSummary:
        [_heading setStringValue:_failure ? @"Something went wrong" : @"The installation is complete"];
        [self _showSummary];
        break;
    }
    [_window display];
}

/* ---- actions ---- */

- (void)agreeChanged:(id)sender { [_next setEnabled:[_agree state] == NSControlStateValueOn]; }
- (void)goBack:(id)sender
{
    if (_at > 0)
        [self _show:_at - 1];
}
- (void)goOn:(id)sender
{
    IPage p = (IPage)[[_pages objectAtIndex:(NSUInteger)_at] integerValue];
    if (p == IPageSummary) {
        [NSApp terminate:nil];
        return;
    }
    [self _show:_at + 1];
}
- (void)openApp:(id)sender
{
    NSString *app = [_job.installedApps firstObject];
    if (!app)
        return;
    if (fork() == 0) {
        /* this program runs under Ferry, so /proc/self/exe is Ferry */
        execl("/proc/self/exe", "ferry", [app fileSystemRepresentation], (char *)NULL);
        _exit(127);
    }
    [NSApp terminate:nil];
}

/* ---- the application ---- */

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    NSMenu *bar = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"Installer" action:NULL keyEquivalent:@""] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"Installer"] autorelease];
    [appMenu addItemWithTitle:@"Quit Installer" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [bar addItem:appItem];
    NSMenuItem *editItem = [[[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""] autorelease];
    NSMenu *edit = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editItem setSubmenu:edit];
    [bar addItem:editItem];
    [NSApp setMainMenu:bar];

    [self _buildWindow];
    if (!_file) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setAllowedFileTypes:@[ @"pkg", @"mpkg", @"dmg" ]];
        [panel setMessage:@"Choose an installer package or disk image"];
        if ([panel runModal] != NSModalResponseOK || ![[panel URLs] count]) {
            [NSApp terminate:nil];
            return;
        }
        self.file = [[[panel URLs] firstObject] path];
    }
    [self _showOpening];
    [_window makeKeyAndOrderFront:nil];
    _opening = YES;
    [self performSelector:@selector(_open) withObject:nil afterDelay:0.1];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }
- (void)applicationWillTerminate:(NSNotification *)note
{
    if (_pkg.imageDirectory)
        IRemoveTree(_pkg.imageDirectory);
}
@end

/* ---- without a window ---------------------------------------------------------------------- */

static int print_info(NSString *file)
{
    NSString *why = nil;
    IPackage *p = [IPackage openPath:file error:&why];
    if (!p) {
        fprintf(stderr, "Installer: %s can't be opened. %s\n", [[file lastPathComponent] UTF8String], [why UTF8String]);
        return 1;
    }
    printf("title: %s\n", [p.title UTF8String]);
    for (IComponent *c in p.components)
        printf("component: %s %s, installs at %s, %s%s\n", [c.identifier UTF8String], [c.version ?: @"" UTF8String],
               [c.installLocation UTF8String], [IHumanSize(c.installKBytes) UTF8String],
               c.hasScripts ? ", has scripts (not run)" : "");
    for (NSString *a in p.apps)
        printf("app: %s\n", [[a lastPathComponent] UTF8String]);
    printf("welcome: %lu characters, read me: %lu, licence: %lu\n", (unsigned long)[p.welcome length],
           (unsigned long)[p.readme length], (unsigned long)[p.license length]);
    if ([p.license length])
        printf("licence begins: %s\n",
               [[[[p.license string] substringToIndex:MIN([p.license length], 60)]
                   stringByReplacingOccurrencesOfString:@"\n" withString:@" "] UTF8String]);
    printf("checks in JavaScript: %s\n", p.hasChecks ? "yes (not run)" : "no");
    if (p.imageDirectory)
        IRemoveTree(p.imageDirectory);
    return 0;
}

static int install_quietly(NSString *file, NSString *apps, NSString *root)
{
    NSString *why = nil;
    IPackage *p = [IPackage openPath:file error:&why];
    if (!p) {
        fprintf(stderr, "Installer: %s can't be opened. %s\n", [[file lastPathComponent] UTF8String], [why UTF8String]);
        return 1;
    }
    IDestination *d = [IDestination standard];
    if (apps)
        d.applications = apps;
    if (root)
        d.root = root;
    IInstallJob *job = [[[IInstallJob alloc] initWithPackage:p destination:d] autorelease];
    int shown = -1;
    while ([job step]) {
        int pct = (int)(job.fraction * 100);
        if (pct / 25 != shown / 25) {
            printf("%d%%\n", pct);
            shown = pct;
        }
    }
    if (p.imageDirectory)
        IRemoveTree(p.imageDirectory);
    if (job.error) {
        fprintf(stderr, "Installer: the installation failed. %s\n", [job.error UTF8String]);
        return 1;
    }
    if ([p.apps count])
        printf("installed %s: copied from the disk image\n", [p.title UTF8String]);
    else
        printf("installed %s: %llu files\n", [p.title UTF8String], job.filesWritten);
    for (NSString *a in job.installedApps) {
        printf("app: %s\n", [[a lastPathComponent] UTF8String]);
        register_app(a);
    }
    return 0;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        /* ferry FILE.pkg [options] runs this as Installer FILE.pkg [options] */
        NSString *file = nil, *apps = nil, *root = nil;
        BOOL info = NO, quiet = NO;
        for (int i = 1; i < argc; i++) {
            if (!strcmp(argv[i], "--info"))
                info = YES;
            else if (!strcmp(argv[i], "--install"))
                quiet = YES;
            else if (!strcmp(argv[i], "--applications") && i + 1 < argc)
                apps = [NSString stringWithUTF8String:argv[++i]];
            else if (!strcmp(argv[i], "--root") && i + 1 < argc)
                root = [NSString stringWithUTF8String:argv[++i]];
            else if (argv[i][0] != '-' && !file)
                file = [NSString stringWithUTF8String:argv[i]];
        }
        if ((info || quiet) && !file) {
            fprintf(stderr, "Installer: name an installer package or disk image\n");
            return 2;
        }
        if (info)
            return print_info(file);
        if (quiet)
            return install_quietly(file, apps, root);
        [NSApplication sharedApplication];
        IController *c = [[IController alloc] init];
        c.file = file;
        [NSApp setDelegate:c];
        [NSApp run];
    }
    return 0;
}
