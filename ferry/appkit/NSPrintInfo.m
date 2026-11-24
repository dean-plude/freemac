/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSPrintInfo and NSPrinter, written from Apple's public
 * NSPrintInfo and NSPrinter documentation and its printing programming
 * guide; no Apple code or headers were used.
 *
 * A print info is a dictionary of attributes (the paper, its orientation,
 * the margins, scaling, pagination, centring, the job's disposition and
 * the pages to print), and its properties read and write that dictionary,
 * as on a Mac. The shared print info starts on the paper this system's
 * locale uses: US Letter where LC_ALL, LC_PAPER or LANG names the United
 * States, Canada, Mexico, the Philippines or one of the other countries
 * that use it (and in the C locale, as on an English Mac), A4 everywhere
 * else. A print info is archived with NSCoding as its dictionary of plain
 * values, so a document can keep one.
 *
 * GTK's page setup and print settings stand for the Mac's page format and
 * print settings: NSPrintOperation.m shows GTK's dialogs with a print
 * info's values and writes back what the user chose. The printers are
 * the ones this system's print service (CUPS) knows, asked with lpstat
 * when a program first wants them. Built without ARC. */
#import "AInternal.h"

NSPrintInfoAttributeKey const NSPrintPaperName = @"NSPaperName";
NSPrintInfoAttributeKey const NSPrintPaperSize = @"NSPaperSize";
NSPrintInfoAttributeKey const NSPrintOrientation = @"NSOrientation";
NSPrintInfoAttributeKey const NSPrintScalingFactor = @"NSScalingFactor";
NSPrintInfoAttributeKey const NSPrintLeftMargin = @"NSLeftMargin";
NSPrintInfoAttributeKey const NSPrintRightMargin = @"NSRightMargin";
NSPrintInfoAttributeKey const NSPrintTopMargin = @"NSTopMargin";
NSPrintInfoAttributeKey const NSPrintBottomMargin = @"NSBottomMargin";
NSPrintInfoAttributeKey const NSPrintHorizontallyCentered = @"NSHorizontallyCentered";
NSPrintInfoAttributeKey const NSPrintVerticallyCentered = @"NSVerticallyCentered";
NSPrintInfoAttributeKey const NSPrintHorizontalPagination = @"NSHorizontalPagination";
NSPrintInfoAttributeKey const NSPrintVerticalPagination = @"NSVerticalPagination";
NSPrintInfoAttributeKey const NSPrintPrinter = @"NSPrinter";
NSPrintInfoAttributeKey const NSPrintCopies = @"NSCopies";
NSPrintInfoAttributeKey const NSPrintAllPages = @"NSAllPages";
NSPrintInfoAttributeKey const NSPrintFirstPage = @"NSFirstPage";
NSPrintInfoAttributeKey const NSPrintLastPage = @"NSLastPage";
NSPrintInfoAttributeKey const NSPrintMustCollate = @"NSMustCollate";
NSPrintInfoAttributeKey const NSPrintReversePageOrder = @"NSReversePageOrder";
NSPrintInfoAttributeKey const NSPrintJobDisposition = @"NSJobDisposition";
NSPrintInfoAttributeKey const NSPrintJobSavingURL = @"NSJobSavingURL";
NSPrintInfoAttributeKey const NSPrintJobSavingFileNameExtensionHidden = @"NSJobSavingFileNameExtensionHidden";
NSPrintInfoAttributeKey const NSPrintHeaderAndFooter = @"NSPrintHeaderAndFooter";
NSPrintInfoAttributeKey const NSPrintSelectionOnly = @"NSPrintSelectionOnly";
NSPrintInfoAttributeKey const NSPrintPagesAcross = @"NSPagesAcross";
NSPrintInfoAttributeKey const NSPrintPagesDown = @"NSPagesDown";
NSPrintInfoAttributeKey const NSPrintTime = @"NSPrintTime";
NSPrintInfoAttributeKey const NSPrintDetailedErrorReporting = @"NSDetailedErrorReporting";
NSPrintInfoAttributeKey const NSPrintPrinterName = @"NSPrinterName";
NSPrintInfoAttributeKey const NSPrintSavePath = @"NSSavePath";
NSPrintJobDispositionValue const NSPrintSpoolJob = @"NSPrintSpoolJob";
NSPrintJobDispositionValue const NSPrintPreviewJob = @"NSPrintPreviewJob";
NSPrintJobDispositionValue const NSPrintSaveJob = @"NSPrintSaveJob";
NSPrintJobDispositionValue const NSPrintCancelJob = @"NSPrintCancelJob";

/* ---- papers --------------------------------------------------------------------------- */

/* The papers Ferry knows by name: the Mac's name (PWG's media names, as a
 * Mac's print info reports them), the name shown, the size in points
 * (portrait), and GTK's name for it. */
static const struct paper {
    const char *name, *shown;
    double width, height;
    const char *gtk;
} papers[] = {
    {"na-letter", "US Letter", 612, 792, "na_letter"},
    {"na-legal", "US Legal", 612, 1008, "na_legal"},
    {"iso-a4", "A4", 595, 842, "iso_a4"},
    {"iso-a3", "A3", 842, 1191, "iso_a3"},
    {"iso-a5", "A5", 420, 595, "iso_a5"},
    {"iso-b5", "B5", 499, 709, "iso_b5"},
    {"tabloid", "Tabloid", 792, 1224, "na_ledger"},
    {"na-number-10-envelope", "Envelope #10", 297, 684, "na_number-10"},
};
#define PAPER_COUNT (sizeof papers / sizeof papers[0])

static const struct paper *paper_named(NSString *name)
{
    if (!name)
        return NULL;
    const char *n = [name UTF8String];
    for (size_t i = 0; i < PAPER_COUNT; i++)
        if (!strcasecmp(n, papers[i].name) || !strcasecmp(n, papers[i].gtk) || !strcasecmp(n, papers[i].shown))
            return &papers[i];
    /* the short names some programs use */
    if (!strcasecmp(n, "Letter"))
        return &papers[0];
    if (!strcasecmp(n, "Legal"))
        return &papers[1];
    return NULL;
}

static const struct paper *paper_sized(NSSize s)
{
    for (size_t i = 0; i < PAPER_COUNT; i++)
        if ((fabs(s.width - papers[i].width) < 1 && fabs(s.height - papers[i].height) < 1) ||
            (fabs(s.height - papers[i].width) < 1 && fabs(s.width - papers[i].height) < 1))
            return &papers[i];
    return NULL;
}

/* US Letter in the countries that use it (and in the C locale), else A4. */
static const struct paper *locale_paper(void)
{
    const char *names[] = {"LC_ALL", "LC_PAPER", "LANG"};
    const char *locale = NULL;
    for (int i = 0; i < 3 && !locale; i++) {
        const char *v = getenv(names[i]);
        if (v && *v)
            locale = v;
    }
    if (!locale || !strcmp(locale, "C") || !strncmp(locale, "C.", 2) || !strcmp(locale, "POSIX"))
        return &papers[0];
    const char *us = strchr(locale, '_');
    static const char *const letter[] = {"US", "CA", "MX", "PH", "CL", "CO", "VE", "CR", "GT", "SV",
                                         "DO", "PR", "PA", "NI", "BZ", NULL};
    if (us)
        for (int i = 0; letter[i]; i++)
            if (!strncmp(us + 1, letter[i], 2))
                return &papers[0];
    return &papers[2];
}

/* ---- printers ------------------------------------------------------------------------- */

/* A program on the PATH, or nil. */
static NSString *find_program(NSString *name)
{
    NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"] ?: @"/usr/bin:/bin";
    for (NSString *dir in [path componentsSeparatedByString:@":"]) {
        NSString *full = [dir stringByAppendingPathComponent:name];
        if ([dir length] && [[NSFileManager defaultManager] isExecutableFileAtPath:full])
            return full;
    }
    return nil;
}

/* What lpstat says, in the C locale, or nil without lpstat. */
static NSString *lpstat(NSArray *arguments)
{
    NSString *program = find_program(@"lpstat");
    if (!program)
        return nil;
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:program];
    [task setArguments:arguments];
    NSMutableDictionary *env = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
    [env setObject:@"C" forKey:@"LC_ALL"];
    [task setEnvironment:env];
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    @try {
        [task launch];
    } @catch (NSException *e) {
        return nil;
    }
    NSData *out = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    return [[[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] autorelease];
}

@implementation NSPrinter {
    NSString *_name;
}

+ (NSArray *)printerNames
{
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *line in [lpstat(@[ @"-e" ]) componentsSeparatedByString:@"\n"]) {
        NSString *n = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([n length])
            [names addObject:n];
    }
    return names;
}
+ (NSArray *)printerTypes { return @[]; }
+ (NSPrinter *)printerWithName:(NSString *)name
{
    if (![name length])
        return nil;
    NSPrinter *p = [[[self alloc] init] autorelease];
    p->_name = [name copy];
    return p;
}
+ (NSPrinter *)printerWithType:(NSString *)type { return nil; }
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)other { return [other isKindOfClass:[NSPrinter class]] && [((NSPrinter *)other)->_name isEqual:_name]; }
- (NSUInteger)hash { return [_name hash]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super init]))
        _name = [[coder decodeObjectForKey:@"NSPrinterName"] copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeObject:_name forKey:@"NSPrinterName"]; }
- (NSString *)name { return _name; }
- (NSString *)type { return _name; }
- (NSInteger)languageLevel { return 3; }
- (NSDictionary *)deviceDescription { return @{@"NSDeviceIsPrinter" : @"YES"}; }
- (NSSize)pageSizeForPaper:(NSString *)paperName
{
    const struct paper *p = paper_named(paperName);
    return p ? NSMakeSize(p->width, p->height) : NSZeroSize;
}
- (NSString *)description { return [NSString stringWithFormat:@"<NSPrinter %p \"%@\">", self, _name]; }
@end

/* ---- NSPrintInfo ---------------------------------------------------------------------- */

static NSPrintInfo *shared_info;

@implementation NSPrintInfo {
    NSMutableDictionary *_dict;
    NSMutableDictionary *_settings;
}

+ (NSPrintInfo *)sharedPrintInfo
{
    if (!shared_info)
        shared_info = [[NSPrintInfo alloc] init];
    return shared_info;
}
+ (void)setSharedPrintInfo:(NSPrintInfo *)info
{
    if (!info)
        return;
    [info retain];
    [shared_info release];
    shared_info = info;
}
+ (NSPrinter *)defaultPrinter
{
    static NSPrinter *printer;
    static BOOL asked;
    if (!asked) {
        asked = YES;
        /* "system default destination: NAME" */
        NSString *out = lpstat(@[ @"-d" ]);
        NSRange r = [out rangeOfString:@": "];
        if (r.location != NSNotFound) {
            NSString *name = [[out substringFromIndex:NSMaxRange(r)]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            printer = [[NSPrinter printerWithName:name] retain];
        }
    }
    return printer;
}
+ (NSSize)sizeForPaperName:(NSString *)name
{
    const struct paper *p = paper_named(name);
    return p ? NSMakeSize(p->width, p->height) : NSZeroSize;
}

- (instancetype)initWithDictionary:(NSDictionary *)attributes
{
    if ((self = [super init])) {
        const struct paper *p = locale_paper();
        _dict = [@{
            NSPrintPaperName : @(p->name),
            NSPrintPaperSize : [NSValue valueWithSize:NSMakeSize(p->width, p->height)],
            NSPrintOrientation : @(NSPaperOrientationPortrait),
            NSPrintScalingFactor : @1.0,
            NSPrintLeftMargin : @72.0,
            NSPrintRightMargin : @72.0,
            NSPrintTopMargin : @90.0,
            NSPrintBottomMargin : @90.0,
            NSPrintHorizontallyCentered : @YES,
            NSPrintVerticallyCentered : @YES,
            NSPrintHorizontalPagination : @(NSClipPagination),
            NSPrintVerticalPagination : @(NSAutoPagination),
            NSPrintJobDisposition : NSPrintSpoolJob,
            NSPrintCopies : @1,
            NSPrintAllPages : @YES,
            NSPrintFirstPage : @1,
            NSPrintLastPage : @(NSIntegerMax),
            NSPrintMustCollate : @YES,
            NSPrintReversePageOrder : @NO,
            NSPrintHeaderAndFooter : @NO,
            NSPrintSelectionOnly : @NO,
        } mutableCopy];
        _settings = [[NSMutableDictionary alloc] init];
        if (attributes)
            [_dict addEntriesFromDictionary:attributes];
    }
    return self;
}
- (instancetype)init { return [self initWithDictionary:nil]; }
- (void)dealloc
{
    [_dict release];
    [_settings release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    NSPrintInfo *c = [[[self class] allocWithZone:zone] initWithDictionary:_dict];
    [c->_settings setDictionary:_settings];
    return c;
}

/* Archived as a dictionary of plain values: the printer by its name. */
- (void)encodeWithCoder:(NSCoder *)coder
{
    NSMutableDictionary *plain = [NSMutableDictionary dictionary];
    for (NSString *key in _dict) {
        id v = [_dict objectForKey:key];
        if ([v isKindOfClass:[NSPrinter class]]) {
            if ([v name])
                [plain setObject:[v name] forKey:NSPrintPrinterName];
        } else if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]] ||
                   [v isKindOfClass:[NSValue class]] || [v isKindOfClass:[NSURL class]] ||
                   [v isKindOfClass:[NSDate class]]) {
            [plain setObject:v forKey:key];
        }
    }
    [coder encodeObject:plain forKey:@"NSAttributes"];
    if ([_settings count])
        [coder encodeObject:_settings forKey:@"NSPrintSettings"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSDictionary *plain = [coder decodeObjectForKey:@"NSAttributes"];
    if (![plain isKindOfClass:[NSDictionary class]])
        plain = nil;
    if ((self = [self initWithDictionary:plain])) {
        NSString *printer = [_dict objectForKey:NSPrintPrinterName];
        if ([printer isKindOfClass:[NSString class]]) {
            [_dict setObject:[NSPrinter printerWithName:printer] forKey:NSPrintPrinter];
            [_dict removeObjectForKey:NSPrintPrinterName];
        }
        NSDictionary *settings = [coder decodeObjectForKey:@"NSPrintSettings"];
        if ([settings isKindOfClass:[NSDictionary class]])
            [_settings setDictionary:settings];
    }
    return self;
}

- (NSMutableDictionary *)dictionary { return _dict; }
- (NSMutableDictionary *)printSettings { return _settings; }

static double number(NSDictionary *d, NSString *key, double fallback)
{
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : fallback;
}

- (NSString *)paperName { return [_dict objectForKey:NSPrintPaperName]; }
- (void)setPaperName:(NSString *)name
{
    const struct paper *p = paper_named(name);
    if (!p) {
        if (name)
            [_dict setObject:[[name copy] autorelease] forKey:NSPrintPaperName];
        return;
    }
    [_dict setObject:@(p->name) forKey:NSPrintPaperName];
    NSSize s = NSMakeSize(p->width, p->height);
    if ([self orientation] == NSPaperOrientationLandscape)
        s = NSMakeSize(s.height, s.width);
    [_dict setObject:[NSValue valueWithSize:s] forKey:NSPrintPaperSize];
}
- (NSString *)localizedPaperName
{
    const struct paper *p = paper_named([self paperName]);
    if (p)
        return @(p->shown);
    NSSize s = [self paperSize];
    return [NSString stringWithFormat:@"%g by %g points", s.width, s.height];
}
- (NSSize)paperSize
{
    NSValue *v = [_dict objectForKey:NSPrintPaperSize];
    return [v isKindOfClass:[NSValue class]] ? [v sizeValue] : NSMakeSize(612, 792);
}
- (void)setPaperSize:(NSSize)size
{
    [_dict setObject:[NSValue valueWithSize:size] forKey:NSPrintPaperSize];
    const struct paper *p = paper_sized(size);
    if (p)
        [_dict setObject:@(p->name) forKey:NSPrintPaperName];
    else
        [_dict removeObjectForKey:NSPrintPaperName];
    if (size.width > size.height)
        [_dict setObject:@(NSPaperOrientationLandscape) forKey:NSPrintOrientation];
    else if (size.width < size.height)
        [_dict setObject:@(NSPaperOrientationPortrait) forKey:NSPrintOrientation];
}
- (NSPaperOrientation)orientation { return (NSPaperOrientation)number(_dict, NSPrintOrientation, 0); }
- (void)setOrientation:(NSPaperOrientation)orientation
{
    [_dict setObject:@(orientation) forKey:NSPrintOrientation];
    /* the paper size follows the orientation, as on a Mac */
    NSSize s = [self paperSize];
    if ((orientation == NSPaperOrientationLandscape) != (s.width > s.height) && s.width != s.height)
        [_dict setObject:[NSValue valueWithSize:NSMakeSize(s.height, s.width)] forKey:NSPrintPaperSize];
}

#define FLOAT_ATTRIBUTE(getter, setter, key, fallback)                                                           \
    -(CGFloat)getter { return number(_dict, key, fallback); }                                                    \
    -(void)setter:(CGFloat)v { [_dict setObject:@(v) forKey:key]; }
FLOAT_ATTRIBUTE(scalingFactor, setScalingFactor, NSPrintScalingFactor, 1)
FLOAT_ATTRIBUTE(leftMargin, setLeftMargin, NSPrintLeftMargin, 72)
FLOAT_ATTRIBUTE(rightMargin, setRightMargin, NSPrintRightMargin, 72)
FLOAT_ATTRIBUTE(topMargin, setTopMargin, NSPrintTopMargin, 90)
FLOAT_ATTRIBUTE(bottomMargin, setBottomMargin, NSPrintBottomMargin, 90)
#define BOOL_ATTRIBUTE(getter, setter, key, fallback)                                                            \
    -(BOOL)getter { return number(_dict, key, fallback) != 0; }                                                  \
    -(void)setter:(BOOL)v { [_dict setObject:@(v) forKey:key]; }
BOOL_ATTRIBUTE(isHorizontallyCentered, setHorizontallyCentered, NSPrintHorizontallyCentered, 1)
BOOL_ATTRIBUTE(isVerticallyCentered, setVerticallyCentered, NSPrintVerticallyCentered, 1)
BOOL_ATTRIBUTE(isSelectionOnly, setSelectionOnly, NSPrintSelectionOnly, 0)
- (NSPrintingPaginationMode)horizontalPagination
{
    return (NSPrintingPaginationMode)number(_dict, NSPrintHorizontalPagination, NSClipPagination);
}
- (void)setHorizontalPagination:(NSPrintingPaginationMode)m
{
    [_dict setObject:@(m) forKey:NSPrintHorizontalPagination];
}
- (NSPrintingPaginationMode)verticalPagination
{
    return (NSPrintingPaginationMode)number(_dict, NSPrintVerticalPagination, NSAutoPagination);
}
- (void)setVerticalPagination:(NSPrintingPaginationMode)m { [_dict setObject:@(m) forKey:NSPrintVerticalPagination]; }
- (NSString *)jobDisposition { return [_dict objectForKey:NSPrintJobDisposition] ?: NSPrintSpoolJob; }
- (void)setJobDisposition:(NSString *)d
{
    if (d)
        [_dict setObject:[[d copy] autorelease] forKey:NSPrintJobDisposition];
}
- (NSPrinter *)printer
{
    id p = [_dict objectForKey:NSPrintPrinter];
    if ([p isKindOfClass:[NSPrinter class]])
        return p;
    NSString *name = [_dict objectForKey:NSPrintPrinterName];
    if ([name isKindOfClass:[NSString class]])
        return [NSPrinter printerWithName:name];
    return [NSPrintInfo defaultPrinter];
}
- (void)setPrinter:(NSPrinter *)printer
{
    if (printer)
        [_dict setObject:printer forKey:NSPrintPrinter];
    else
        [_dict removeObjectForKey:NSPrintPrinter];
    [_dict removeObjectForKey:NSPrintPrinterName];
}
/* No printer reports its margins here, so the whole sheet. */
- (NSRect)imageablePageBounds { return (NSRect){NSZeroPoint, [self paperSize]}; }
- (void)setUpPrintOperationDefaultValues {}
- (void)updateFromPMPrintSettings {}
- (void)updateFromPMPageFormat {}

- (NSString *)description
{
    NSSize s = [self paperSize];
    return [NSString stringWithFormat:@"<NSPrintInfo %p: %@ %gx%g>", self, [self paperName], s.width, s.height];
}

/* ---- GTK's page setup and print settings ---- */

- (GtkPageSetup *)_gtkPageSetup
{
    GtkPageSetup *setup = gtk_page_setup_new();
    const struct paper *p = paper_named([self paperName]);
    NSSize s = [self paperSize];
    BOOL landscape = [self orientation] == NSPaperOrientationLandscape;
    GtkPaperSize *paper = p ? gtk_paper_size_new(p->gtk)
                            : gtk_paper_size_new_custom("custom", [[self localizedPaperName] UTF8String],
                                                        landscape ? s.height : s.width,
                                                        landscape ? s.width : s.height, GTK_UNIT_POINTS);
    gtk_page_setup_set_paper_size(setup, paper);
    gtk_paper_size_free(paper);
    gtk_page_setup_set_orientation(setup, landscape ? GTK_PAGE_ORIENTATION_LANDSCAPE : GTK_PAGE_ORIENTATION_PORTRAIT);
    gtk_page_setup_set_left_margin(setup, [self leftMargin], GTK_UNIT_POINTS);
    gtk_page_setup_set_right_margin(setup, [self rightMargin], GTK_UNIT_POINTS);
    gtk_page_setup_set_top_margin(setup, [self topMargin], GTK_UNIT_POINTS);
    gtk_page_setup_set_bottom_margin(setup, [self bottomMargin], GTK_UNIT_POINTS);
    return setup;
}

- (GtkPrintSettings *)_gtkPrintSettings
{
    GtkPrintSettings *settings = gtk_print_settings_new();
    gtk_print_settings_set_n_copies(settings, (int)number(_dict, NSPrintCopies, 1));
    gtk_print_settings_set_collate(settings, number(_dict, NSPrintMustCollate, 1) != 0);
    gtk_print_settings_set_reverse(settings, number(_dict, NSPrintReversePageOrder, 0) != 0);
    gtk_print_settings_set_scale(settings, [self scalingFactor] * 100);
    if (!number(_dict, NSPrintAllPages, 1)) {
        GtkPageRange r = {(int)number(_dict, NSPrintFirstPage, 1) - 1,
                          (int)fmin(number(_dict, NSPrintLastPage, 1), 1e6) - 1};
        gtk_print_settings_set_print_pages(settings, GTK_PRINT_PAGES_RANGES);
        gtk_print_settings_set_page_ranges(settings, &r, 1);
    }
    NSPrinter *printer = [_dict objectForKey:NSPrintPrinter];
    if ([printer isKindOfClass:[NSPrinter class]] && [printer name])
        gtk_print_settings_set_printer(settings, [[printer name] UTF8String]);
    /* a job saved to a file is GTK's Print to File, into that file */
    NSURL *url = [_dict objectForKey:NSPrintJobSavingURL];
    if ([[self jobDisposition] isEqual:NSPrintSaveJob] && [url isKindOfClass:[NSURL class]]) {
        gtk_print_settings_set_printer(settings, "Print to File");
        gtk_print_settings_set(settings, "output-uri", [[url absoluteString] UTF8String]);
        gtk_print_settings_set(settings, "output-file-format", "pdf");
    }
    return settings;
}

- (void)_takeGtkPageSetup:(GtkPageSetup *)setup
{
    if (!setup)
        return;
    GtkPaperSize *paper = gtk_page_setup_get_paper_size(setup);
    BOOL landscape = gtk_page_setup_get_orientation(setup) == GTK_PAGE_ORIENTATION_LANDSCAPE;
    NSSize s = NSMakeSize(gtk_paper_size_get_width(paper, GTK_UNIT_POINTS),
                          gtk_paper_size_get_height(paper, GTK_UNIT_POINTS));
    const struct paper *p = paper_named(@(gtk_paper_size_get_name(paper) ?: ""));
    [_dict setObject:@(landscape ? NSPaperOrientationLandscape : NSPaperOrientationPortrait) forKey:NSPrintOrientation];
    if (landscape)
        s = NSMakeSize(s.height, s.width);
    if (p)
        s = landscape ? NSMakeSize(p->height, p->width) : NSMakeSize(p->width, p->height);
    [_dict setObject:[NSValue valueWithSize:s] forKey:NSPrintPaperSize];
    if (p)
        [_dict setObject:@(p->name) forKey:NSPrintPaperName];
    else
        [_dict setObject:@(gtk_paper_size_get_name(paper) ?: "custom") forKey:NSPrintPaperName];
    [self setLeftMargin:gtk_page_setup_get_left_margin(setup, GTK_UNIT_POINTS)];
    [self setRightMargin:gtk_page_setup_get_right_margin(setup, GTK_UNIT_POINTS)];
    [self setTopMargin:gtk_page_setup_get_top_margin(setup, GTK_UNIT_POINTS)];
    [self setBottomMargin:gtk_page_setup_get_bottom_margin(setup, GTK_UNIT_POINTS)];
}

- (void)_takeGtkPrintSettings:(GtkPrintSettings *)settings
{
    if (!settings)
        return;
    [_dict setObject:@(gtk_print_settings_get_n_copies(settings)) forKey:NSPrintCopies];
    [_dict setObject:@(gtk_print_settings_get_collate(settings) != 0) forKey:NSPrintMustCollate];
    [_dict setObject:@(gtk_print_settings_get_reverse(settings) != 0) forKey:NSPrintReversePageOrder];
    double scale = gtk_print_settings_get_scale(settings);
    if (scale > 0)
        [self setScalingFactor:scale / 100];
    int count = 0;
    GtkPageRange *ranges = gtk_print_settings_get_print_pages(settings) == GTK_PRINT_PAGES_RANGES
                               ? gtk_print_settings_get_page_ranges(settings, &count)
                               : NULL;
    if (ranges && count > 0) {
        /* the Mac takes one range: from the first page asked for to the last */
        int first = ranges[0].start, last = ranges[0].end;
        for (int i = 1; i < count; i++) {
            first = MIN(first, ranges[i].start);
            last = MAX(last, ranges[i].end);
        }
        [_dict setObject:@NO forKey:NSPrintAllPages];
        [_dict setObject:@(first + 1) forKey:NSPrintFirstPage];
        [_dict setObject:@(last + 1) forKey:NSPrintLastPage];
    } else {
        [_dict setObject:@YES forKey:NSPrintAllPages];
    }
    g_free(ranges);
    const char *uri = gtk_print_settings_get(settings, "output-uri");
    const char *printer = gtk_print_settings_get_printer(settings);
    if (printer && *printer)
        [_dict setObject:[NSPrinter printerWithName:@(printer)] forKey:NSPrintPrinter];
    if (uri && *uri) {
        NSURL *url = [NSURL URLWithString:@(uri)];
        if (url)
            [_dict setObject:url forKey:NSPrintJobSavingURL];
    }
}

/* ---- the answer the environment gives, with no display ---- */

/* "paper=iso-a4", "landscape", "portrait", "scale=50" (per cent),
 * "margins=L,R,T,B", "copies=2", "pages=2-3" or "pages=all", "collate",
 * "reverse", "printer=NAME", "file=PATH" (saved there, as GTK's Print to
 * File does), "preview". */
- (void)_takeAnswerWords:(NSArray *)words
{
    for (NSString *w in words) {
        NSRange eq = [w rangeOfString:@"="];
        NSString *key = eq.location == NSNotFound ? [w lowercaseString] : [[w substringToIndex:eq.location] lowercaseString];
        NSString *value = eq.location == NSNotFound ? @"" : [w substringFromIndex:NSMaxRange(eq)];
        if ([key isEqual:@"paper"])
            [self setPaperName:value];
        else if ([key isEqual:@"landscape"])
            [self setOrientation:NSPaperOrientationLandscape];
        else if ([key isEqual:@"portrait"])
            [self setOrientation:NSPaperOrientationPortrait];
        else if ([key isEqual:@"scale"] && [value doubleValue] > 0)
            [self setScalingFactor:[value doubleValue] / 100];
        else if ([key isEqual:@"margins"]) {
            NSArray *m = [value componentsSeparatedByString:@","];
            if ([m count] == 4) {
                [self setLeftMargin:[m[0] doubleValue]];
                [self setRightMargin:[m[1] doubleValue]];
                [self setTopMargin:[m[2] doubleValue]];
                [self setBottomMargin:[m[3] doubleValue]];
            }
        } else if ([key isEqual:@"copies"] && [value integerValue] > 0)
            [_dict setObject:@([value integerValue]) forKey:NSPrintCopies];
        else if ([key isEqual:@"pages"]) {
            NSArray *r = [value componentsSeparatedByString:@"-"];
            if ([value isEqual:@"all"] || ![value length]) {
                [_dict setObject:@YES forKey:NSPrintAllPages];
            } else {
                [_dict setObject:@NO forKey:NSPrintAllPages];
                [_dict setObject:@([r[0] integerValue]) forKey:NSPrintFirstPage];
                [_dict setObject:@([[r lastObject] integerValue]) forKey:NSPrintLastPage];
            }
        } else if ([key isEqual:@"collate"])
            [_dict setObject:@YES forKey:NSPrintMustCollate];
        else if ([key isEqual:@"reverse"])
            [_dict setObject:@YES forKey:NSPrintReversePageOrder];
        else if ([key isEqual:@"printer"])
            [self setPrinter:[NSPrinter printerWithName:value]];
        else if ([key isEqual:@"file"] && [value length]) {
            [self setJobDisposition:NSPrintSaveJob];
            [_dict setObject:[NSURL fileURLWithPath:value] forKey:NSPrintJobSavingURL];
        } else if ([key isEqual:@"preview"])
            [self setJobDisposition:NSPrintPreviewJob];
    }
}
@end
