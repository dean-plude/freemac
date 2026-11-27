/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSPrintOperation, NSPrintPanel, NSPageLayout and the
 * printing parts of NSView, NSWindow and NSApplication, written from
 * Apple's public documentation of those classes and its printing
 * programming guide; no Apple code or headers were used.
 *
 * A print operation lays a view out on pages, either as the view asks
 * (knowsPageRange: and rectForPage:) or by automatic pagination, which
 * tiles the view in page-sized pieces, lets the view move each page's
 * bottom and right edges (adjustPageHeightNew: and adjustPageWidthNew:),
 * fits the view to the page, or clips it, as the print info says. Each
 * page is drawn by the view's own drawRect: into a PDF page made with
 * Cairo, in the paper's size, the view placed inside the margins
 * (locationOfPrintRect:), scaled by the print info's scaling factor, with
 * its page border, header and footer. The drawing is never to the screen,
 * so views leave out selections and insertion points.
 *
 * The PDF goes where the print info's job disposition says: to a file
 * (NSPrintSaveJob, which is also GTK's Print to File), to the printer the
 * print panel chose (handed to GTK's print job, or to lp when no dialog
 * chose a GTK printer), or to the desktop's PDF viewer (NSPrintPreviewJob).
 * A PDF or EPS operation writes the pages to data or a file and never
 * shows a panel.
 *
 * The print panel and the page layout are GTK's print and page setup
 * dialogs, filled in from the print info, which then takes what the user
 * chose. As sheets they are shown on top of the window, modal to it, once
 * the call that begins them has returned. With no display, the panels
 * answer as the environment says: FERRY_PRINT_ANSWER and
 * FERRY_PAGE_LAYOUT_ANSWER hold "ok" or "cancel" followed by changes such
 * as "paper=iso-a4 landscape scale=50 pages=2-3 file=/tmp/out.pdf"; with
 * neither set they answer Cancel. With a display and the variable set,
 * the dialog is shown and answered by itself after a moment, so a script
 * can print through it. Built without ARC. */
#import "AInternal.h"
#include <dispatch/dispatch.h>

NSPrintPanelJobStyleHint const NSPrintPhotoJobStyleHint = @"Photo";
NSPrintPanelJobStyleHint const NSPrintAllPresetsJobStyleHint = @"All";
NSPrintPanelJobStyleHint const NSPrintNoPresetsJobStyleHint = @"None";

enum { GTK_RESPONSE_APPLY = -10 };

@interface NSPrintPanel (FerryRunning)
- (NSInteger)_runWithPrintInfo:(NSPrintInfo *)info window:(NSWindow *)window;
@end
@interface NSPrintOperation (FerryDrawing)
- (NSPoint)_placementOfRect:(NSRect)rect;
- (void)_beginPageInRect:(NSRect)rect atPlacement:(NSPoint)location;
- (void)_endPage;
@end

/* ---- GTK's dialogs, answered by themselves when the environment asks ------------------- */

struct auto_answer {
    GtkWidget *dialog;
    int response, ticks;
    BOOL wants_printer, finished, removed;
};

static int answer_tick(void *data)
{
    struct auto_answer *a = data;
    if (a->finished) {
        free(a);
        return 0;
    }
    a->ticks++;
    /* wait (up to five seconds) until GTK has found a printer to select */
    if (a->wants_printer && a->response == GTK_RESPONSE_OK && a->ticks < 50 &&
        !gtk_print_unix_dialog_get_selected_printer(a->dialog))
        return 1;
    if (a->ticks < 3)
        return 1;
    a->removed = YES;
    gtk_dialog_response(a->dialog, a->response);
    return 0;
}

/* Runs a GTK dialog, modal to the window if one is given; with an answer
 * in the environment, the dialog answers itself. */
static int run_dialog(GtkWidget *dialog, NSWindow *window, const char *answer, BOOL wants_printer)
{
    GtkWidget *parent = [window _gtkWindow];
    if (parent) {
        gtk_window_set_transient_for(dialog, parent);
        gtk_window_set_modal(dialog, 1);
    }
    struct auto_answer *a = NULL;
    if (answer) {
        a = calloc(1, sizeof *a);
        a->dialog = dialog;
        a->wants_printer = wants_printer;
        a->response = strncasecmp(answer, "cancel", 6) ? GTK_RESPONSE_OK : GTK_RESPONSE_CANCEL;
        g_timeout_add(100, answer_tick, a);
    }
    int response = gtk_dialog_run(dialog);
    if (a) {
        if (a->removed)
            free(a);
        else
            a->finished = YES; /* the timeout frees it */
    }
    return response;
}

/* The words of an answer from the environment: "ok" or "cancel", then
 * changes to the print info. */
static NSArray *answer_words(const char *answer, BOOL *ok)
{
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in [@(answer) componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])
        if ([w length])
            [words addObject:w];
    *ok = YES;
    if ([words count]) {
        NSString *first = [words[0] lowercaseString];
        if ([first isEqual:@"cancel"])
            *ok = NO;
        if ([first isEqual:@"cancel"] || [first isEqual:@"ok"] || [first isEqual:@"print"])
            [words removeObjectAtIndex:0];
    }
    return words;
}

static const char *nonempty_env(const char *name)
{
    const char *v = getenv(name);
    return v && *v ? v : NULL;
}

/* ---- NSPrintPanel ---------------------------------------------------------------------- */

@implementation NSPrintPanel {
    NSPrintPanelOptions _options;
    NSString *_hint, *_anchor, *_button;
    NSPrintInfo *_info;
    NSMutableArray *_accessories;
    GtkPrinter *_printer;
}

+ (NSPrintPanel *)printPanel { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init])) {
        _options = NSPrintPanelShowsCopies | NSPrintPanelShowsPageRange;
        _accessories = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_hint release];
    [_anchor release];
    [_button release];
    [_info release];
    [_accessories release];
    if (_printer)
        g_object_unref(_printer);
    [super dealloc];
}
- (NSPrintPanelOptions)options { return _options; }
- (void)setOptions:(NSPrintPanelOptions)o { _options = o; }
- (NSString *)jobStyleHint { return _hint; }
- (void)setJobStyleHint:(NSString *)h
{
    id wasHint = _hint;
    _hint = [h copy];
    [wasHint release];
}
- (NSString *)helpAnchor { return _anchor; }
- (void)setHelpAnchor:(NSString *)a
{
    id wasAnchor = _anchor;
    _anchor = [a copy];
    [wasAnchor release];
}
- (NSString *)defaultButtonTitle { return _button ?: @"Print"; }
- (void)setDefaultButtonTitle:(NSString *)t
{
    id wasButton = _button;
    _button = [t copy];
    [wasButton release];
}
- (NSPrintInfo *)printInfo { return _info; }
- (void)addAccessoryController:(NSViewController *)c
{
    if (c && ![_accessories containsObject:c])
        [_accessories addObject:c];
    AWarnOnce("accessory views in the print panel");
}
- (void)removeAccessoryController:(NSViewController *)c { [_accessories removeObject:c]; }
- (NSArray *)accessoryControllers { return [[_accessories copy] autorelease]; }
- (GtkPrinter *)_chosenPrinter { return _printer; }

- (NSInteger)_runWithPrintInfo:(NSPrintInfo *)info window:(NSWindow *)window
{
    if (!info)
        info = [NSPrintInfo sharedPrintInfo];
    [info retain];
    [_info release];
    _info = info;
    if (_printer) {
        g_object_unref(_printer);
        _printer = NULL;
    }
    const char *answer = nonempty_env("FERRY_PRINT_ANSWER");
    BOOL ok = NO;
    NSArray *words = answer ? answer_words(answer, &ok) : nil;
    if (!ADisplayAvailable()) {
        if (!answer) {
            AWarnOnce("the print panel with no display (it answers Cancel)");
            return NSModalResponseCancel;
        }
        if (ok)
            [info _takeAnswerWords:words];
        return ok ? NSModalResponseOK : NSModalResponseCancel;
    }
    /* the answer's changes first, so the dialog shows them (Print to File
     * for "file=") */
    if (ok)
        [info _takeAnswerWords:words];
    NSString *title = [[NSPrintOperation currentOperation] jobTitle];
    GtkWidget *dialog = gtk_print_unix_dialog_new([title length] ? [title UTF8String] : "Print", NULL);
    GtkPageSetup *setup = [info _gtkPageSetup];
    GtkPrintSettings *settings = [info _gtkPrintSettings];
    gtk_print_unix_dialog_set_page_setup(dialog, setup);
    gtk_print_unix_dialog_set_settings(dialog, settings);
    g_object_unref(setup);
    g_object_unref(settings);
    gtk_print_unix_dialog_set_manual_capabilities(
        dialog, GTK_PRINT_CAPABILITY_PAGE_SET | GTK_PRINT_CAPABILITY_COPIES | GTK_PRINT_CAPABILITY_COLLATE |
                    GTK_PRINT_CAPABILITY_REVERSE | GTK_PRINT_CAPABILITY_SCALE | GTK_PRINT_CAPABILITY_GENERATE_PDF);
    gtk_print_unix_dialog_set_embed_page_setup(dialog, 1);
    int response = run_dialog(dialog, window, answer, YES);
    NSInteger result = NSModalResponseCancel;
    if (response == GTK_RESPONSE_OK || response == GTK_RESPONSE_APPLY) {
        GtkPrintSettings *chosen = gtk_print_unix_dialog_get_settings(dialog);
        [info _takeGtkPrintSettings:chosen];
        if (chosen)
            g_object_unref(chosen);
        [info _takeGtkPageSetup:gtk_print_unix_dialog_get_page_setup(dialog)];
        GtkPrinter *printer = gtk_print_unix_dialog_get_selected_printer(dialog);
        if (response == GTK_RESPONSE_APPLY)
            [info setJobDisposition:NSPrintPreviewJob];
        else if (printer && gtk_printer_is_virtual(printer) && [[info dictionary] objectForKey:NSPrintJobSavingURL])
            [info setJobDisposition:NSPrintSaveJob];
        else
            [info setJobDisposition:NSPrintSpoolJob];
        if (printer && !gtk_printer_is_virtual(printer))
            _printer = g_object_ref(printer);
        if (ok)
            [info _takeAnswerWords:words];
        result = NSModalResponseOK;
    }
    gtk_widget_destroy(dialog);
    return result;
}

- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)info { return [self _runWithPrintInfo:info window:nil]; }
- (NSInteger)runModal
{
    return [self runModalWithPrintInfo:[[NSPrintOperation currentOperation] printInfo]];
}
- (void)beginSheetUsingPrintInfo:(NSPrintInfo *)info onWindow:(NSWindow *)window
               completionHandler:(void (^)(NSInteger))handler
{
    [self retain];
    [info retain];
    [window retain];
    void (^h)(NSInteger) = [handler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger r = [self _runWithPrintInfo:info window:window];
      if (h)
          h(r);
      [h release];
      [window release];
      [info release];
      [self release];
    });
}
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)info modalForWindow:(NSWindow *)window delegate:(id)delegate
                 didEndSelector:(SEL)selector contextInfo:(void *)context
{
    [self beginSheetUsingPrintInfo:info onWindow:window completionHandler:^(NSInteger r) {
      if (delegate && selector)
          ((void (*)(id, SEL, id, int, void *))objc_msgSend)(delegate, selector, self, (int)r, context);
    }];
}
@end

/* ---- NSPageLayout ---------------------------------------------------------------------- */

@implementation NSPageLayout {
    NSPrintInfo *_info;
    NSMutableArray *_accessories;
}

+ (NSPageLayout *)pageLayout { return [[[self alloc] init] autorelease]; }
- (instancetype)init
{
    if ((self = [super init]))
        _accessories = [[NSMutableArray alloc] init];
    return self;
}
- (void)dealloc
{
    [_info release];
    [_accessories release];
    [super dealloc];
}
- (NSPrintInfo *)printInfo { return _info; }
- (void)addAccessoryController:(NSViewController *)c
{
    if (c && ![_accessories containsObject:c])
        [_accessories addObject:c];
    AWarnOnce("accessory views in the page layout");
}
- (void)removeAccessoryController:(NSViewController *)c { [_accessories removeObject:c]; }
- (NSArray *)accessoryControllers { return [[_accessories copy] autorelease]; }

- (NSInteger)_runWithPrintInfo:(NSPrintInfo *)info window:(NSWindow *)window
{
    if (!info)
        info = [NSPrintInfo sharedPrintInfo];
    [info retain];
    [_info release];
    _info = info;
    const char *answer = nonempty_env("FERRY_PAGE_LAYOUT_ANSWER");
    BOOL ok = NO;
    NSArray *words = answer ? answer_words(answer, &ok) : nil;
    if (!ADisplayAvailable()) {
        if (!answer) {
            AWarnOnce("Page Setup with no display (it answers Cancel)");
            return NSModalResponseCancel;
        }
        if (ok)
            [info _takeAnswerWords:words];
        return ok ? NSModalResponseOK : NSModalResponseCancel;
    }
    GtkWidget *dialog = gtk_page_setup_unix_dialog_new("Page Setup", NULL);
    GtkPageSetup *setup = [info _gtkPageSetup];
    gtk_page_setup_unix_dialog_set_page_setup(dialog, setup);
    g_object_unref(setup);
    int response = run_dialog(dialog, window, answer, NO);
    NSInteger result = NSModalResponseCancel;
    if (response == GTK_RESPONSE_OK) {
        [info _takeGtkPageSetup:gtk_page_setup_unix_dialog_get_page_setup(dialog)];
        if (ok)
            [info _takeAnswerWords:words];
        result = NSModalResponseOK;
    }
    gtk_widget_destroy(dialog);
    return result;
}

- (NSInteger)runModalWithPrintInfo:(NSPrintInfo *)info { return [self _runWithPrintInfo:info window:nil]; }
- (NSInteger)runModal { return [self runModalWithPrintInfo:[NSPrintInfo sharedPrintInfo]]; }
- (void)beginSheetUsingPrintInfo:(NSPrintInfo *)info onWindow:(NSWindow *)window
               completionHandler:(void (^)(NSInteger))handler
{
    [self retain];
    [info retain];
    [window retain];
    void (^h)(NSInteger) = [handler copy];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger r = [self _runWithPrintInfo:info window:window];
      if (h)
          h(r);
      [h release];
      [window release];
      [info release];
      [self release];
    });
}
- (void)beginSheetWithPrintInfo:(NSPrintInfo *)info modalForWindow:(NSWindow *)window delegate:(id)delegate
                 didEndSelector:(SEL)selector contextInfo:(void *)context
{
    [self beginSheetUsingPrintInfo:info onWindow:window completionHandler:^(NSInteger r) {
      if (delegate && selector)
          ((void (*)(id, SEL, id, int, void *))objc_msgSend)(delegate, selector, self, (int)r, context);
    }];
}
@end

/* ---- NSPrintOperation ------------------------------------------------------------------ */

static NSPrintOperation *current_operation;

static cairo_status_t append_bytes(void *closure, const unsigned char *data, unsigned int length)
{
    [(NSMutableData *)closure appendBytes:data length:length];
    return 0;
}

@implementation NSPrintOperation {
    NSView *_view;
    NSPrintInfo *_info;
    NSRect _rect;          /* what a PDF or EPS operation draws, in the view */
    BOOL _copying, _eps;
    NSMutableData *_data;  /* where a PDF or EPS operation's pages go */
    NSString *_path;       /* or there */
    NSString *_title;
    BOOL _showsPanel, _showsProgress, _spawn;
    NSPrintPanel *_panel;
    NSPrintingPageOrder _order;
    NSInteger _page;
    NSRange _range;
    NSGraphicsContext *_context;
    /* laying out and drawing */
    NSMutableArray *_pages; /* the rect of each page, in the view */
    NSInteger _firstNumber; /* the number of _pages[0] */
    NSInteger _across, _down;
    CGFloat _scale;
    NSMutableData *_out;
    cairo_surface_t *_surface;
    CGContextRef _cg;
    BOOL _pageOpen;
}

+ (NSPrintOperation *)currentOperation { return current_operation; }
+ (void)setCurrentOperation:(NSPrintOperation *)op
{
    [op retain];
    [current_operation release];
    current_operation = op;
}

- (instancetype)_initWithView:(NSView *)view printInfo:(NSPrintInfo *)info
{
    if ((self = [super init])) {
        _view = [view retain];
        _info = [(info ?: [NSPrintInfo sharedPrintInfo]) copy];
        _rect = [view bounds];
        _showsPanel = YES;
        _showsProgress = YES;
        _order = NSAscendingPageOrder;
        _range = NSMakeRange(1, 0);
        _scale = 1;
    }
    return self;
}

+ (NSPrintOperation *)printOperationWithView:(NSView *)view printInfo:(NSPrintInfo *)info
{
    return [[[self alloc] _initWithView:view printInfo:info] autorelease];
}
+ (NSPrintOperation *)printOperationWithView:(NSView *)view { return [self printOperationWithView:view printInfo:nil]; }

/* A PDF or EPS operation with no print info draws the rect on one page of
 * its size, with no margins. */
static NSPrintInfo *copying_info(NSRect rect)
{
    NSPrintInfo *info = [[[NSPrintInfo sharedPrintInfo] copy] autorelease];
    [info setPaperSize:rect.size];
    [info setLeftMargin:0];
    [info setRightMargin:0];
    [info setTopMargin:0];
    [info setBottomMargin:0];
    [info setScalingFactor:1];
    [info setHorizontalPagination:NSClipPagination];
    [info setVerticalPagination:NSClipPagination];
    [info setHorizontallyCentered:NO];
    [info setVerticallyCentered:NO];
    [[info dictionary] setObject:@NO forKey:NSPrintHeaderAndFooter];
    [[info dictionary] setObject:@YES forKey:NSPrintAllPages];
    return info;
}

- (instancetype)_initCopying:(NSView *)view rect:(NSRect)rect data:(NSMutableData *)data path:(NSString *)path
                   printInfo:(NSPrintInfo *)info eps:(BOOL)eps
{
    if ((self = [self _initWithView:view printInfo:info ?: copying_info(rect)])) {
        _rect = rect;
        _copying = YES;
        _eps = eps;
        _data = [data retain];
        _path = [path copy];
        _showsPanel = NO;
        _showsProgress = NO;
    }
    return self;
}

+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
                                 printInfo:(NSPrintInfo *)info
{
    return [[[self alloc] _initCopying:view rect:rect data:data path:nil printInfo:info eps:NO] autorelease];
}
+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
{
    return [self PDFOperationWithView:view insideRect:rect toData:data printInfo:nil];
}
+ (NSPrintOperation *)PDFOperationWithView:(NSView *)view insideRect:(NSRect)rect toPath:(NSString *)path
                                 printInfo:(NSPrintInfo *)info
{
    return [[[self alloc] _initCopying:view rect:rect data:nil path:path printInfo:info eps:NO] autorelease];
}
+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
                                 printInfo:(NSPrintInfo *)info
{
    return [[[self alloc] _initCopying:view rect:rect data:data path:nil printInfo:info eps:YES] autorelease];
}
+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toData:(NSMutableData *)data
{
    return [self EPSOperationWithView:view insideRect:rect toData:data printInfo:nil];
}
+ (NSPrintOperation *)EPSOperationWithView:(NSView *)view insideRect:(NSRect)rect toPath:(NSString *)path
                                 printInfo:(NSPrintInfo *)info
{
    return [[[self alloc] _initCopying:view rect:rect data:nil path:path printInfo:info eps:YES] autorelease];
}

- (void)dealloc
{
    [self destroyContext];
    [_view release];
    [_info release];
    [_data release];
    [_path release];
    [_title release];
    [_panel release];
    [_pages release];
    [_out release];
    [super dealloc];
}

- (BOOL)isCopyingOperation { return _copying; }
- (NSPrintRenderingQuality)preferredRenderingQuality { return NSPrintRenderingQualityBest; }
- (NSString *)jobTitle { return _title ?: [_view printJobTitle]; }
- (void)setJobTitle:(NSString *)t
{
    id wasTitle = _title;
    _title = [t copy];
    [wasTitle release];
}
- (BOOL)showsPrintPanel { return _showsPanel; }
- (void)setShowsPrintPanel:(BOOL)f { _showsPanel = f; }
- (BOOL)showsProgressPanel { return _showsProgress; }
- (void)setShowsProgressPanel:(BOOL)f { _showsProgress = f; }
- (BOOL)canSpawnSeparateThread { return _spawn; }
- (void)setCanSpawnSeparateThread:(BOOL)f { _spawn = f; }
- (NSPrintPanel *)printPanel
{
    if (!_panel)
        _panel = [[NSPrintPanel alloc] init];
    return _panel;
}
- (void)setPrintPanel:(NSPrintPanel *)p
{
    [p retain];
    [_panel release];
    _panel = p;
}
- (NSPrintingPageOrder)pageOrder { return _order; }
- (void)setPageOrder:(NSPrintingPageOrder)o { _order = o; }
- (NSPrintInfo *)printInfo { return _info; }
- (void)setPrintInfo:(NSPrintInfo *)info
{
    if (!info || info == _info)
        return;
    id wasInfo = _info;
    _info = [info copy];
    [wasInfo release];
}
- (NSView *)view { return _view; }
- (NSInteger)currentPage { return _page; }
- (NSRange)pageRange { return _range; }
- (NSGraphicsContext *)context { return _context; }

/* ---- laying out ---- */

/* Splits [start, end) into pieces of at most size, letting the view move
 * each piece's far edge back (by at most limit of a piece). Down a flipped
 * view and across any view, coordinates grow; down an unflipped view, they
 * shrink, the top being the largest. */
- (NSArray *)_split:(CGFloat)start to:(CGFloat)end size:(CGFloat)size vertical:(BOOL)vertical
               mode:(NSPrintingPaginationMode)mode
{
    NSMutableArray *pieces = [NSMutableArray array];
    BOOL down = vertical && ![_view isFlipped]; /* shrinking coordinates */
    CGFloat length = fabs(end - start);
    if (size <= 0 || mode != NSAutoPagination || length <= size + 0.001) {
        CGFloat piece = mode == NSClipPagination ? fmin(length, size) : length;
        [pieces addObject:@[ @(start), @(down ? start - piece : start + piece) ]];
        return pieces;
    }
    CGFloat limit = vertical ? [_view heightAdjustLimit] : [_view widthAdjustLimit];
    limit = fmax(0, fmin(limit, 1)) * size;
    CGFloat at = start;
    while (down ? at > end + 0.001 : at < end - 0.001) {
        CGFloat far = down ? at - size : at + size;
        if (down ? far <= end : far >= end) {
            far = end;
        } else {
            CGFloat moved = far, least = down ? far + limit : far - limit;
            if (vertical)
                [_view adjustPageHeightNew:&moved top:at bottom:far limit:least];
            else
                [_view adjustPageWidthNew:&moved left:at right:far limit:least];
            /* the view may move the edge back, but no further than the limit */
            if (down ? (moved >= far && moved <= least) : (moved <= far && moved >= least))
                far = moved;
            if (fabs(far - at) < 0.5)
                far = down ? at - size : at + size;
        }
        [pieces addObject:@[ @(at), @(far) ]];
        at = far;
    }
    return pieces;
}

- (BOOL)_paginate
{
    [_pages release];
    _pages = [[NSMutableArray alloc] init];
    NSPrintInfo *info = _info;
    NSSize paper = [info paperSize];
    CGFloat scale = [info scalingFactor] > 0 ? [info scalingFactor] : 1;
    NSRange known = NSMakeRange(1, 0);
    if (!_copying && [_view knowsPageRange:&known]) {
        _scale = scale;
        _firstNumber = known.location;
        _across = _down = 1;
        for (NSUInteger i = 0; i < known.length; i++) {
            _page = known.location + i;
            [_pages addObject:[NSValue valueWithRect:[_view rectForPage:_page]]];
        }
        _range = known;
        return YES;
    }
    NSRect r = _copying ? _rect : [_view bounds];
    if (NSIsEmptyRect(r))
        return NO;
    CGFloat areaW = paper.width - [info leftMargin] - [info rightMargin];
    CGFloat areaH = paper.height - [info topMargin] - [info bottomMargin];
    if (areaW <= 0 || areaH <= 0)
        return NO;
    NSPrintingPaginationMode h = [info horizontalPagination], v = [info verticalPagination];
    /* fitting shrinks the whole view, keeping its shape, until it fits */
    if (h == NSFitPagination && r.size.width * scale > areaW)
        scale = areaW / r.size.width;
    if (v == NSFitPagination && r.size.height * scale > areaH)
        scale = areaH / r.size.height;
    _scale = scale;
    CGFloat w = areaW / scale, hh = areaH / scale;
    NSArray *columns = [self _split:NSMinX(r) to:NSMaxX(r) size:w vertical:NO mode:h];
    BOOL flipped = [_view isFlipped];
    NSArray *rows = flipped ? [self _split:NSMinY(r) to:NSMaxY(r) size:hh vertical:YES mode:v]
                            : [self _split:NSMaxY(r) to:NSMinY(r) size:hh vertical:YES mode:v];
    _across = [columns count];
    _down = [rows count];
    for (NSArray *row in rows)
        for (NSArray *column in columns) {
            CGFloat x0 = [column[0] doubleValue], x1 = [column[1] doubleValue];
            CGFloat y0 = [row[0] doubleValue], y1 = [row[1] doubleValue];
            [_pages addObject:[NSValue valueWithRect:NSMakeRect(x0, fmin(y0, y1), x1 - x0, fabs(y1 - y0))]];
        }
    _firstNumber = 1;
    _range = NSMakeRange(1, [_pages count]);
    return [_pages count] > 0;
}

/* Where a page's rect goes on the paper (its lower left corner, the paper
 * unflipped): inside the margins, at the top left, or centred where the
 * print info asks and the view is one page wide or tall. */
- (NSPoint)_placementOfRect:(NSRect)rect
{
    NSSize paper = [_info paperSize];
    CGFloat l = [_info leftMargin], r = [_info rightMargin], t = [_info topMargin], b = [_info bottomMargin];
    CGFloat w = rect.size.width * _scale, h = rect.size.height * _scale;
    CGFloat x = l, y = paper.height - t - h;
    if ([_info isHorizontallyCentered] && _across <= 1)
        x = l + (paper.width - l - r - w) / 2;
    if ([_info isVerticallyCentered] && _down <= 1)
        y = b + (paper.height - t - b - h) / 2;
    return NSMakePoint(x, y);
}

/* ---- drawing ---- */

- (NSGraphicsContext *)createContext
{
    if (_surface)
        return _context;
    [_out release];
    _out = [[NSMutableData alloc] init];
    NSSize paper = [_info paperSize];
    if (_eps) {
        _surface = cairo_ps_surface_create_for_stream(append_bytes, _out, paper.width, paper.height);
        cairo_ps_surface_set_eps(_surface, 1);
    } else {
        _surface = cairo_pdf_surface_create_for_stream(append_bytes, _out, paper.width, paper.height);
    }
    return nil;
}

- (void)destroyContext
{
    [self _endPage];
    if (_surface) {
        cairo_surface_finish(_surface);
        cairo_surface_destroy(_surface);
        _surface = NULL;
    }
}

/* Starts a page of the paper's size, drawing rect of the view placed at
 * location (both as beginPageInRect:atPlacement: has them). */
- (void)_beginPageInRect:(NSRect)rect atPlacement:(NSPoint)location
{
    if (!_surface)
        [self createContext];
    [self _endPage];
    NSSize paper = [_info paperSize];
    if (_eps)
        cairo_ps_surface_set_size(_surface, paper.width, paper.height);
    else
        cairo_pdf_surface_set_size(_surface, paper.width, paper.height);
    _cg = GContextCreateWithSurface(_surface, paper.height);
    _pageOpen = YES;
    _context = [[NSGraphicsContext graphicsContextWithCGContext:_cg flipped:NO] retain];
    [_context _setDrawingToScreen:NO];
    CGContextSaveGState(_cg);
    CGFloat s = _scale;
    CGContextClipToRect(_cg, CGRectMake(location.x, location.y, rect.size.width * s, rect.size.height * s));
    if ([_view isFlipped]) {
        CGContextTranslateCTM(_cg, location.x, location.y + rect.size.height * s);
        CGContextScaleCTM(_cg, s, -s);
    } else {
        CGContextTranslateCTM(_cg, location.x, location.y);
        CGContextScaleCTM(_cg, s, s);
    }
    CGContextTranslateCTM(_cg, -rect.origin.x, -rect.origin.y);
}

- (void)_endPage
{
    if (!_pageOpen)
        return;
    _pageOpen = NO;
    cairo_show_page(((GContext *)_cg)->cr);
    CGContextRelease(_cg);
    _cg = NULL;
    [_context release];
    _context = nil;
}

/* The header (left part, tab, right part) and the footer (centred), in
 * the margins of the page, the paper unflipped. */
- (void)_drawHeaderAndFooter
{
    NSSize paper = [_info paperSize];
    NSFont *font = [NSFont systemFontOfSize:10];
    NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
    [NSGraphicsContext setCurrentContext:_context];
    NSAttributedString *header = [_view pageHeader], *footer = [_view pageFooter];
    CGFloat l = [_info leftMargin], r = [_info rightMargin];
    if ([header length]) {
        NSArray *parts = [[header string] componentsSeparatedByString:@"\t"];
        CGFloat y = paper.height - [_info topMargin] / 2;
        NSAttributedString *left = AAttributed(parts[0], font, [NSColor blackColor]);
        ADrawLine(left, l, y);
        if ([parts count] > 1) {
            NSAttributedString *right = AAttributed([parts lastObject], font, [NSColor blackColor]);
            ADrawLine(right, paper.width - r - ALineSize(right, NULL, NULL).width, y);
        }
    }
    if ([footer length]) {
        NSAttributedString *f = AAttributed([footer string], font, [NSColor blackColor]);
        CGFloat width = ALineSize(f, NULL, NULL).width;
        ADrawLine(f, l + (paper.width - l - r - width) / 2, [_info bottomMargin] / 2);
    }
    [NSGraphicsContext setCurrentContext:saved];
    [saved release];
}

- (void)_drawPage:(NSInteger)index
{
    NSRect rect = [_pages[index] rectValue];
    _page = _firstNumber + index;
    NSPoint place = [_view locationOfPrintRect:rect];
    [_view beginPageInRect:rect atPlacement:place];
    if (_cg) {
        @autoreleasepool {
            [_view _drawContentInContext:_cg dirty:rect screen:NO];
        }
        CGContextRestoreGState(_cg);
        NSSize paper = [_info paperSize];
        NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
        [NSGraphicsContext setCurrentContext:_context];
        [_view drawPageBorderWithSize:paper];
        [NSGraphicsContext setCurrentContext:saved];
        [saved release];
        if ([[[_info dictionary] objectForKey:NSPrintHeaderAndFooter] boolValue])
            [self _drawHeaderAndFooter];
    }
    [_view endPage];
}

/* The pages the print info asks for, in the order printed. */
- (NSArray *)_pageIndexes
{
    NSMutableArray *indexes = [NSMutableArray array];
    NSInteger count = [_pages count];
    NSInteger first = 0, last = count - 1;
    NSDictionary *d = [_info dictionary];
    if (!_copying && ![[d objectForKey:NSPrintAllPages] boolValue] && [d objectForKey:NSPrintFirstPage]) {
        first = MAX(first, [[d objectForKey:NSPrintFirstPage] integerValue] - _firstNumber);
        if ([d objectForKey:NSPrintLastPage])
            last = MIN(last, [[d objectForKey:NSPrintLastPage] integerValue] - _firstNumber);
    }
    for (NSInteger i = first; i <= last; i++)
        [indexes addObject:@(i)];
    BOOL reverse = _order == NSDescendingPageOrder || (!_copying && [[d objectForKey:NSPrintReversePageOrder] boolValue]);
    return reverse ? [[indexes reverseObjectEnumerator] allObjects] : indexes;
}

/* ---- delivering ---- */

static NSString *temporary_pdf(void)
{
    NSString *name = [NSString stringWithFormat:@"ferry-print-%d-%u.pdf", getpid(), arc4random()];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

static void print_failed(NSString *why)
{
    fflush(stdout);
    fprintf(stderr, "AppKit (Ferry): printing failed: %s\n", [why UTF8String]);
}

struct job_wait {
    BOOL done, ok;
};
static void job_complete(GtkPrintJob *job, void *data, const GError *error)
{
    struct job_wait *w = data;
    w->ok = error == NULL;
    w->done = YES;
}

/* Sends the PDF file to the printer: GTK's, when the print panel chose
 * one, else the print info's (or the system's default) through lp. */
- (BOOL)_spool:(NSString *)path
{
    GtkPrinter *printer = [_panel _chosenPrinter];
    NSString *title = [self jobTitle] ?: @"Untitled";
    if (printer) {
        GtkPrintSettings *settings = [_info _gtkPrintSettings];
        GtkPageSetup *setup = [_info _gtkPageSetup];
        GtkPrintJob *job = gtk_print_job_new([title UTF8String], printer, settings, setup);
        g_object_unref(settings);
        g_object_unref(setup);
        GError *error = NULL;
        if (!gtk_print_job_set_source_file(job, [path fileSystemRepresentation], &error)) {
            if (error)
                g_error_free(error);
            g_object_unref(job);
            print_failed(@"the printer can't take a PDF file");
            return NO;
        }
        struct job_wait w = {NO, NO};
        gtk_print_job_send(job, job_complete, &w, NULL);
        while (!w.done)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        g_object_unref(job);
        if (!w.ok)
            print_failed(@"the printer turned the job down");
        return w.ok;
    }
    NSString *lp = nil;
    NSString *dirs = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"] ?: @"/usr/bin:/bin";
    for (NSString *dir in [dirs componentsSeparatedByString:@":"])
        if ([dir length] && [[NSFileManager defaultManager]
                                isExecutableFileAtPath:[dir stringByAppendingPathComponent:@"lp"]]) {
            lp = [dir stringByAppendingPathComponent:@"lp"];
            break;
        }
    if (!lp) {
        print_failed(@"there is no print service here (no lp program); print to a PDF file instead");
        return NO;
    }
    NSMutableArray *args = [NSMutableArray array];
    NSString *name = [[_info printer] name];
    if ([name length])
        [args addObjectsFromArray:@[ @"-d", name ]];
    NSInteger copies = [[[_info dictionary] objectForKey:NSPrintCopies] integerValue];
    if (copies > 1)
        [args addObjectsFromArray:@[ @"-n", [NSString stringWithFormat:@"%ld", (long)copies] ]];
    [args addObjectsFromArray:@[ @"-t", title, @"--", path ]];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:lp];
    [task setArguments:args];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *e) {
        print_failed(@"lp could not be run");
        return NO;
    }
    if ([task terminationStatus] != 0) {
        print_failed(@"lp turned the job down");
        return NO;
    }
    return YES;
}

- (BOOL)deliverResult
{
    if (!_out)
        return NO;
    if (_copying) {
        if (_data)
            [_data appendData:_out];
        if (_path)
            return [_out writeToFile:_path atomically:YES];
        return YES;
    }
    NSString *disposition = [_info jobDisposition];
    if ([disposition isEqual:NSPrintCancelJob])
        return NO;
    if ([disposition isEqual:NSPrintSaveJob]) {
        id where = [[_info dictionary] objectForKey:NSPrintJobSavingURL];
        NSString *path = [where isKindOfClass:[NSURL class]] && [where isFileURL] ? [where path] : nil;
        if (!path && [[[_info dictionary] objectForKey:NSPrintSavePath] isKindOfClass:[NSString class]])
            path = [[_info dictionary] objectForKey:NSPrintSavePath];
        if (!path) {
            print_failed(@"the job is to be saved, but the print info names no file");
            return NO;
        }
        if (![_out writeToFile:path atomically:YES]) {
            print_failed([NSString stringWithFormat:@"%@ could not be written", path]);
            return NO;
        }
        return YES;
    }
    NSString *path = temporary_pdf();
    if (![_out writeToFile:path atomically:YES]) {
        print_failed(@"the pages could not be written to a temporary file");
        return NO;
    }
    if ([disposition isEqual:NSPrintPreviewJob]) {
        /* the viewer reads the file in its own time, so it stays */
        return [[NSWorkspace sharedWorkspace] openFile:path];
    }
    BOOL ok = [self _spool:path];
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    return ok;
}

- (void)cleanUpOperation
{
    [self destroyContext];
    if (current_operation == self)
        [NSPrintOperation setCurrentOperation:nil];
}

- (BOOL)_runWithWindow:(NSWindow *)window
{
    if (!_view)
        return NO;
    NSPrintOperation *saved = [current_operation retain];
    [NSPrintOperation setCurrentOperation:self];
    BOOL ok = NO;
    if (_showsPanel && !_copying) {
        NSPrintPanel *panel = [self printPanel];
        if ([panel _runWithPrintInfo:_info window:window] != NSModalResponseOK)
            goto done;
    }
    if ([[_info jobDisposition] isEqual:NSPrintCancelJob])
        goto done;
    if (![self _paginate])
        goto done;
    [self createContext];
    [_view beginDocument];
    for (NSNumber *i in [self _pageIndexes])
        [self _drawPage:[i integerValue]];
    [_view endDocument];
    [self destroyContext];
    ok = [self deliverResult];
done:
    [self cleanUpOperation];
    [NSPrintOperation setCurrentOperation:saved];
    [saved release];
    if ([_view window])
        [_view setNeedsDisplay:YES];
    return ok;
}

- (BOOL)runOperation { return [self _runWithWindow:nil]; }

- (void)runOperationModalForWindow:(NSWindow *)window delegate:(id)delegate didRunSelector:(SEL)selector
                       contextInfo:(void *)context
{
    [self retain];
    [window retain];
    dispatch_async(dispatch_get_main_queue(), ^{
      BOOL ok = [self _runWithWindow:window];
      if (delegate && selector)
          ((void (*)(id, SEL, id, BOOL, void *))objc_msgSend)(delegate, selector, self, ok, context);
      [window release];
      [self release];
    });
}

- (NSInteger)_pageCount { return (NSInteger)[_pages count]; }
@end

/* ---- NSView ---------------------------------------------------------------------------- */

@implementation NSView (NSPrinting)

- (IBAction)print:(id)sender { [[NSPrintOperation printOperationWithView:self] runOperation]; }

- (NSData *)dataWithPDFInsideRect:(NSRect)rect
{
    NSMutableData *data = [NSMutableData data];
    if (![[NSPrintOperation PDFOperationWithView:self insideRect:rect toData:data] runOperation])
        return nil;
    return data;
}
- (NSData *)dataWithEPSInsideRect:(NSRect)rect
{
    NSMutableData *data = [NSMutableData data];
    if (![[NSPrintOperation EPSOperationWithView:self insideRect:rect toData:data] runOperation])
        return nil;
    return data;
}
- (void)writePDFInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard
{
    NSData *data = [self dataWithPDFInsideRect:rect];
    if (!data)
        return;
    [pasteboard declareTypes:@[ NSPasteboardTypePDF ] owner:nil];
    [pasteboard setData:data forType:NSPasteboardTypePDF];
}
- (void)writeEPSInsideRect:(NSRect)rect toPasteboard:(NSPasteboard *)pasteboard
{
    NSData *data = [self dataWithEPSInsideRect:rect];
    if (!data)
        return;
    [pasteboard declareTypes:@[ NSPostScriptPboardType ] owner:nil];
    [pasteboard setData:data forType:NSPostScriptPboardType];
}

/* The window's document's name, else the window's title. */
- (NSString *)printJobTitle
{
    NSWindow *w = [self window];
    id doc = [[w windowController] document];
    if ([doc respondsToSelector:@selector(displayName)] && [[doc displayName] length])
        return [doc displayName];
    return [[w title] length] ? [w title] : nil;
}

- (BOOL)knowsPageRange:(NSRangePointer)range { return NO; }
- (NSRect)rectForPage:(NSInteger)page { return NSZeroRect; }
- (NSPoint)locationOfPrintRect:(NSRect)rect
{
    NSPrintOperation *op = [NSPrintOperation currentOperation];
    return op ? [op _placementOfRect:rect] : NSZeroPoint;
}
- (void)adjustPageWidthNew:(CGFloat *)newRight left:(CGFloat)left right:(CGFloat)right limit:(CGFloat)limit {}
- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)top bottom:(CGFloat)bottom limit:(CGFloat)limit {}
- (CGFloat)heightAdjustLimit { return 0.2; }
- (CGFloat)widthAdjustLimit { return 0.2; }
- (void)beginDocument {}
- (void)endDocument {}
- (void)beginPageInRect:(NSRect)rect atPlacement:(NSPoint)location
{
    [[NSPrintOperation currentOperation] _beginPageInRect:rect atPlacement:location];
}
- (void)endPage { [[NSPrintOperation currentOperation] _endPage]; }
- (void)drawPageBorderWithSize:(NSSize)size {}
- (void)drawSheetBorderWithSize:(NSSize)size {}

- (NSAttributedString *)pageHeader
{
    NSString *title = [[NSPrintOperation currentOperation] jobTitle] ?: @"";
    NSString *date = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterMediumStyle
                                                    timeStyle:NSDateFormatterShortStyle];
    return [[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\t%@", title, date]]
        autorelease];
}
- (NSAttributedString *)pageFooter
{
    NSPrintOperation *op = [NSPrintOperation currentOperation];
    NSRange r = [op pageRange];
    NSString *s = [NSString stringWithFormat:@"Page %ld of %ld", (long)[op currentPage], (long)NSMaxRange(r) - 1];
    return [[[NSAttributedString alloc] initWithString:s] autorelease];
}
@end

/* ---- NSWindow and NSApplication -------------------------------------------------------- */

@implementation NSWindow (NSPrinting)
/* The window's content view, which is all of a Ferry window that the
 * program draws. */
- (IBAction)print:(id)sender { [[self contentView] print:sender]; }
- (NSData *)dataWithPDFInsideRect:(NSRect)rect
{
    NSView *v = [self contentView];
    return [v dataWithPDFInsideRect:[v convertRect:rect fromView:nil]];
}
- (NSData *)dataWithEPSInsideRect:(NSRect)rect
{
    NSView *v = [self contentView];
    return [v dataWithEPSInsideRect:[v convertRect:rect fromView:nil]];
}
@end

@implementation NSApplication (NSPrinting)
- (IBAction)runPageLayout:(id)sender { [[NSPageLayout pageLayout] runModalWithPrintInfo:[NSPrintInfo sharedPrintInfo]]; }
@end

/* For tests: the text Poppler reads on a page (from 0) of a PDF. */
A_EXPORT NSString *FerryPDFPageText(NSData *pdf, NSUInteger page);
A_EXPORT NSString *FerryPDFPageText(NSData *pdf, NSUInteger page)
{
    if ([pdf length] < 5)
        return nil;
    GError *error = NULL;
    NSData *copy = [[pdf copy] autorelease];
    PopplerDocument *doc = poppler_document_new_from_data((char *)[copy bytes], (int)[copy length], NULL, &error);
    if (error)
        g_error_free(error);
    if (!doc)
        return nil;
    NSString *text = nil;
    if ((int)page < poppler_document_get_n_pages(doc)) {
        PopplerPage *p = poppler_document_get_page(doc, (int)page);
        char *s = p ? poppler_page_get_text(p) : NULL;
        if (s) {
            text = [NSString stringWithUTF8String:s];
            g_free(s);
        }
        if (p)
            g_object_unref(p);
    }
    g_object_unref(doc);
    return text;
}
