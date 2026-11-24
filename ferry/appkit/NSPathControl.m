/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: path controls (NSPathControl, NSPathCell,
 * NSPathComponentCell, NSPathControlItem), written from Apple's public API
 * documentation.
 *
 * A path control shows the folders leading to a URL. A file URL starts at
 * the root, which freemac calls "Computer" (as the Drawer's path does),
 * and each folder after it gets its icon; any other URL starts at its
 * host. The standard style lays the components out in a row with small
 * chevrons between them, cutting the middle ones short first when they
 * don't fit; the navigation bar style is the same row on a band; the
 * pop-up style is a button showing the last component, which opens a menu
 * of the whole path, the last component first.
 *
 * Clicking a component (or choosing it from the menu) makes it the
 * clicked one (clickedPathItem, clickedPathComponentCell) and sends the
 * action; a double click sends the double action as well. The delegate
 * hears pathControl:willPopUpMenu: before the menu opens. Dragging files
 * onto an editable control and its "Choose…" item aren't done.
 *
 * A path control in a nib keeps its cell under "NSCell", and the cell
 * keeps its style under "NSPathStyle", its URL under "NSContents" and its
 * placeholder under "NSPlaceholderString" (names from developers'
 * descriptions of the format; no Apple code was read). */
#import "AInternal.h"

static const CGFloat icon_size = 16, gap = 3, chevron_width = 12, min_component = 28;

@interface NSPathControlItem (FerryPath)
- (void)_setURL:(NSURL *)url;
- (NSPathComponentCell *)_cell;
- (instancetype)_initWithCell:(NSPathComponentCell *)cell;
@end
@interface NSPathComponentCell (FerryPath)
- (CGFloat)_naturalWidth;
- (void)_drawInRect:(NSRect)r flipped:(BOOL)flipped color:(NSColor *)color;
@end
@interface NSPathCell (FerryPath)
- (void)_setClicked:(NSPathComponentCell *)c;
- (void)_setPressed:(NSPathComponentCell *)c;
- (NSArray *)_cellsForURL:(NSURL *)url;
@end

/* ---- the parts ------------------------------------------------------------------------- */

@implementation NSPathComponentCell {
    NSImage *_pathImage;
    NSURL *_URL;
}
- (void)dealloc
{
    [_pathImage release];
    [_URL release];
    [super dealloc];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSPathComponentCell *c = [super copyWithZone:zone];
    c->_pathImage = [_pathImage retain];
    c->_URL = [_URL retain];
    return c;
}
- (NSImage *)image { return _pathImage; }
- (void)setImage:(NSImage *)image
{
    [image retain];
    [_pathImage release];
    _pathImage = image;
}
- (NSURL *)URL { return _URL; }
- (void)setURL:(NSURL *)url
{
    url = [url copy];
    [_URL release];
    _URL = url;
}
/* Its natural width: the icon and the title. */
- (CGFloat)_naturalWidth
{
    CGFloat w = ceil(ALineSize(AAttributed([self stringValue], [self font] ?: ADefaultFont(), nil), NULL, NULL).width);
    if (_pathImage)
        w += icon_size + gap;
    return w;
}
- (void)_drawInRect:(NSRect)r flipped:(BOOL)flipped color:(NSColor *)color
{
    CGFloat x = NSMinX(r);
    NSFont *font = [self font] ?: ADefaultFont();
    if (_pathImage) {
        NSRect ir = NSMakeRect(x, floor(NSMidY(r) - icon_size / 2), icon_size, icon_size);
        [_pathImage drawInRect:ir fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1
                respectFlipped:YES hints:nil];
        x += icon_size + gap;
    }
    CGFloat w = NSMaxX(r) - x;
    if (w <= 4)
        return;
    NSMutableParagraphStyle *ps = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [ps setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : color, NSParagraphStyleAttributeName : ps};
    CGFloat h = ceil([font ascender] - [font descender]);
    [[self stringValue] drawInRect:NSMakeRect(x, floor(NSMidY(r) - h / 2), w, h) withAttributes:attrs];
}
@end

@implementation NSPathControlItem {
    NSPathComponentCell *_cell;
}
- (instancetype)init
{
    if ((self = [super init]))
        _cell = [[NSPathComponentCell alloc] initTextCell:@""];
    return self;
}
- (instancetype)_initWithCell:(NSPathComponentCell *)cell
{
    if ((self = [super init]))
        _cell = [cell retain];
    return self;
}
- (void)dealloc
{
    [_cell release];
    [super dealloc];
}
- (NSPathComponentCell *)_cell { return _cell; }
- (NSString *)title { return [_cell stringValue]; }
- (void)setTitle:(NSString *)title { [_cell setStringValue:title ?: @""]; }
- (NSAttributedString *)attributedTitle { return [_cell attributedStringValue]; }
- (void)setAttributedTitle:(NSAttributedString *)title { [_cell setAttributedStringValue:title]; }
- (NSImage *)image { return [_cell image]; }
- (void)setImage:(NSImage *)image { [_cell setImage:image]; }
- (NSURL *)URL { return [_cell URL]; }
- (void)_setURL:(NSURL *)url { [_cell setURL:url]; }
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[NSPathControlItem class]] && [(NSPathControlItem *)other _cell] == _cell;
}
- (NSUInteger)hash { return (NSUInteger)_cell; }
- (NSString *)description { return [NSString stringWithFormat:@"<NSPathControlItem %@>", [self title]]; }
@end

/* ---- the cell: the components, their layout and drawing --------------------------------- */

@implementation NSPathCell {
    NSPathStyle _style;
    NSURL *_URL;
    NSArray *_cells;
    NSPathComponentCell *_clicked, *_pressed;
    NSString *_placeholder;
    NSAttributedString *_placeholderAttributed;
    NSColor *_background;
    NSArray *_allowedTypes;
    SEL _doubleAction;
}

+ (Class)pathComponentCellClass { return [NSPathComponentCell class]; }

- (instancetype)initTextCell:(NSString *)s
{
    if ((self = [super initTextCell:@""])) {
        _cells = [@[] retain];
        [self setFont:ADefaultFont()];
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _cells = [@[] retain];
    _style = [coder decodeIntegerForKey:@"NSPathStyle"];
    id placeholder = [coder decodeObjectForKey:@"NSPlaceholderString"];
    if ([placeholder isKindOfClass:[NSString class]])
        _placeholder = [placeholder copy];
    else if ([placeholder isKindOfClass:[NSAttributedString class]])
        _placeholderAttributed = [placeholder copy];
    id bg = [coder decodeObjectForKey:@"NSBackgroundColor"];
    if ([bg isKindOfClass:[NSColor class]])
        _background = [bg copy];
    id types = [coder decodeObjectForKey:@"NSAllowedTypes"];
    if ([types isKindOfClass:[NSArray class]])
        _allowedTypes = [types copy];
    id contents = [coder decodeObjectForKey:@"NSContents"];
    if ([contents isKindOfClass:[NSURL class]] || [contents isKindOfClass:[NSString class]])
        [self setObjectValue:contents];
    else
        [super setObjectValue:nil];
    if (![self font])
        [self setFont:ADefaultFont()];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:_style forKey:@"NSPathStyle"];
    if (_URL)
        [coder encodeObject:_URL forKey:@"NSContents"];
    if (_placeholder)
        [coder encodeObject:_placeholder forKey:@"NSPlaceholderString"];
    if (_background)
        [coder encodeObject:_background forKey:@"NSBackgroundColor"];
    if (_allowedTypes)
        [coder encodeObject:_allowedTypes forKey:@"NSAllowedTypes"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSPathCell *c = [super copyWithZone:zone];
    [c->_URL release];
    c->_URL = [_URL copy];
    [c->_cells release];
    NSMutableArray *copies = [[NSMutableArray alloc] init];
    for (NSPathComponentCell *pc in _cells)
        [copies addObject:[[pc copy] autorelease]];
    c->_cells = copies;
    c->_clicked = c->_pressed = nil;
    c->_style = _style;
    c->_doubleAction = _doubleAction;
    c->_placeholder = [_placeholder copy];
    c->_placeholderAttributed = [_placeholderAttributed copy];
    c->_background = [_background copy];
    c->_allowedTypes = [_allowedTypes copy];
    return c;
}
- (void)dealloc
{
    [_URL release];
    [_cells release];
    [_placeholder release];
    [_placeholderAttributed release];
    [_background release];
    [_allowedTypes release];
    [super dealloc];
}

- (NSPathStyle)pathStyle { return _style; }
- (void)setPathStyle:(NSPathStyle)s { _style = s; }
- (NSString *)placeholderString { return _placeholder ?: [_placeholderAttributed string]; }
- (void)setPlaceholderString:(NSString *)s
{
    s = [s copy];
    [_placeholder release];
    _placeholder = s;
}
- (NSAttributedString *)placeholderAttributedString { return _placeholderAttributed; }
- (void)setPlaceholderAttributedString:(NSAttributedString *)s
{
    s = [s copy];
    [_placeholderAttributed release];
    _placeholderAttributed = s;
}
- (NSColor *)backgroundColor { return _background; }
- (void)setBackgroundColor:(NSColor *)c
{
    c = [c copy];
    [_background release];
    _background = c;
}
- (NSArray *)allowedTypes { return _allowedTypes; }
- (void)setAllowedTypes:(NSArray *)types
{
    types = [types copy];
    [_allowedTypes release];
    _allowedTypes = types;
}
- (SEL)doubleAction { return _doubleAction; }
- (void)setDoubleAction:(SEL)sel { _doubleAction = sel; }
- (NSPathComponentCell *)clickedPathComponentCell { return _clicked; }
- (void)_setClicked:(NSPathComponentCell *)c { _clicked = c; }
- (void)_setPressed:(NSPathComponentCell *)c { _pressed = c; }

- (NSArray *)pathComponentCells { return _cells; }
- (void)setPathComponentCells:(NSArray *)cells
{
    cells = [cells copy];
    [_cells release];
    _cells = cells ?: [@[] retain];
    _clicked = _pressed = nil;
    NSURL *last = [(NSPathComponentCell *)[_cells lastObject] URL];
    [last retain];
    [_URL release];
    _URL = last;
    [super setObjectValue:_URL];
}

- (NSURL *)URL { return _URL; }
- (void)setURL:(NSURL *)url { [self setObjectValue:url]; }
- (id)objectValue { return _URL; }
/* A URL, or a path as a string. */
- (void)setObjectValue:(id)value
{
    NSURL *url = nil;
    if ([value isKindOfClass:[NSURL class]])
        url = value;
    else if ([value isKindOfClass:[NSString class]] && [value length])
        url = [value hasPrefix:@"/"] || [value hasPrefix:@"~"]
                  ? [NSURL fileURLWithPath:[value stringByExpandingTildeInPath]]
                  : [NSURL URLWithString:value];
    url = [[url copy] autorelease];
    [url retain];
    [_URL release];
    _URL = url;
    [super setObjectValue:url];
    [_cells release];
    _cells = [[self _cellsForURL:url] retain];
    _clicked = _pressed = nil;
}
- (NSString *)stringValue { return _URL ? ([_URL isFileURL] ? [_URL path] : [_URL absoluteString]) : @""; }
- (void)setStringValue:(NSString *)s { [self setObjectValue:s]; }

- (NSPathComponentCell *)_componentTitled:(NSString *)title URL:(NSURL *)url image:(NSImage *)image
{
    NSPathComponentCell *c = [[[[[self class] pathComponentCellClass] alloc] initTextCell:title] autorelease];
    [c setFont:[self font]];
    [c setURL:url];
    [c setImage:image];
    return c;
}
- (NSArray *)_cellsForURL:(NSURL *)url
{
    NSMutableArray *cells = [NSMutableArray array];
    if (!url)
        return cells;
    if ([url isFileURL]) {
        NSString *path = [[url path] stringByStandardizingPath];
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        NSString *sofar = @"/";
        [cells addObject:[self _componentTitled:@"Computer" URL:[NSURL fileURLWithPath:@"/" isDirectory:YES]
                                          image:[ws iconForFileType:NSFileTypeDirectory]]];
        for (NSString *part in [path pathComponents]) {
            if ([part isEqualToString:@"/"] || ![part length])
                continue;
            sofar = [sofar stringByAppendingPathComponent:part];
            BOOL dir = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:sofar isDirectory:&dir];
            [cells addObject:[self _componentTitled:part URL:[NSURL fileURLWithPath:sofar isDirectory:dir]
                                              image:[ws iconForFile:sofar]]];
        }
        return cells;
    }
    NSString *host = [url host];
    NSString *base = host ? [NSString stringWithFormat:@"%@://%@/", [url scheme], host] : nil;
    if (base)
        [cells addObject:[self _componentTitled:host URL:[NSURL URLWithString:base] image:nil]];
    NSURL *sofar = base ? [NSURL URLWithString:base] : nil;
    for (NSString *part in [[url path] pathComponents]) {
        if ([part isEqualToString:@"/"] || ![part length] || !sofar)
            continue;
        sofar = [sofar URLByAppendingPathComponent:part];
        [cells addObject:[self _componentTitled:part URL:sofar image:nil]];
    }
    if (![cells count])
        [cells addObject:[self _componentTitled:[url absoluteString] URL:url image:nil]];
    return cells;
}

/* The components' rectangles in frame, for the row styles: their natural
 * widths, the middle ones cut down first (then the first, then the last)
 * until the row fits. */
- (NSArray *)_layoutInFrame:(NSRect)frame
{
    NSUInteger n = [_cells count];
    if (!n)
        return @[];
    NSRect inner = NSInsetRect(frame, 5, 0);
    CGFloat widths[n], total = 0;
    for (NSUInteger i = 0; i < n; i++) {
        widths[i] = [(NSPathComponentCell *)_cells[i] _naturalWidth];
        total += widths[i];
    }
    total += chevron_width * (n - 1);
    CGFloat excess = total - inner.size.width;
    if (excess > 0) {
        /* the order to cut in: from the middle outwards, then the first, then the last */
        NSMutableArray *order = [NSMutableArray array];
        if (n > 2) {
            NSInteger mid = (NSInteger)(n - 1) / 2;
            for (NSInteger d = 0; (NSUInteger)d < n; d++) {
                if (mid - d >= 1)
                    [order addObject:@(mid - d)];
                if (d && mid + d <= (NSInteger)n - 2)
                    [order addObject:@(mid + d)];
            }
        }
        if (n > 1)
            [order addObject:@0];
        [order addObject:@(n - 1)];
        for (NSNumber *k in order) {
            NSUInteger i = [k unsignedIntegerValue];
            CGFloat cut = fmin(excess, fmax(0, widths[i] - min_component));
            widths[i] -= cut;
            excess -= cut;
            if (excess <= 0)
                break;
        }
    }
    NSMutableArray *rects = [NSMutableArray array];
    CGFloat x = NSMinX(inner);
    for (NSUInteger i = 0; i < n; i++) {
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x, NSMinY(frame), widths[i], frame.size.height)]];
        x += widths[i] + chevron_width;
    }
    return rects;
}

- (NSRect)rectOfPathComponentCell:(NSPathComponentCell *)cell withFrame:(NSRect)frame inView:(NSView *)view
{
    NSUInteger i = [_cells indexOfObjectIdenticalTo:cell];
    if (i == NSNotFound)
        return NSZeroRect;
    if (_style == NSPathStylePopUp)
        return i == [_cells count] - 1 ? NSInsetRect(frame, 1, 1) : NSZeroRect;
    return [[self _layoutInFrame:frame][i] rectValue];
}
- (NSPathComponentCell *)pathComponentCellAtPoint:(NSPoint)p withFrame:(NSRect)frame inView:(NSView *)view
{
    if (_style == NSPathStylePopUp)
        return NSPointInRect(p, frame) ? [_cells lastObject] : nil;
    NSArray *rects = [self _layoutInFrame:frame];
    for (NSUInteger i = 0; i < [rects count]; i++) {
        NSRect r = [rects[i] rectValue];
        r.size.width += i + 1 < [rects count] ? chevron_width : 0;
        if (NSPointInRect(p, r))
            return _cells[i];
    }
    return nil;
}

- (NSSize)cellSize
{
    CGFloat w = 10;
    if (_style == NSPathStylePopUp)
        w += [(NSPathComponentCell *)[_cells lastObject] _naturalWidth] + 30;
    else
        for (NSPathComponentCell *c in _cells)
            w += [c _naturalWidth] + chevron_width;
    return NSMakeSize(w, _style == NSPathStylePopUp ? 25 : 22);
}

static void draw_chevron(NSRect r, BOOL flipped)
{
    CGFloat cx = floor(NSMidX(r)) + 0.5, cy = floor(NSMidY(r)) + 0.5, s = 3;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(cx - s / 2, cy - s)];
    [p lineToPoint:NSMakePoint(cx + s / 2, cy)];
    [p lineToPoint:NSMakePoint(cx - s / 2, cy + s)];
    [p setLineWidth:1.5];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [[NSColor tertiaryLabelColor] setStroke];
    [p stroke];
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    if (_style == NSPathStyleNavigationBar) {
        [[NSColor colorWithWhite:0.96 alpha:1] setFill];
        NSRectFill(frame);
        [[NSColor colorWithWhite:0 alpha:0.12] setFill];
        NSRectFill(NSMakeRect(NSMinX(frame), [view isFlipped] ? NSMaxY(frame) - 1 : NSMinY(frame), frame.size.width, 1));
    } else if (_background) {
        [_background setFill];
        NSRectFill(frame);
    }
    [self drawInteriorWithFrame:frame inView:view];
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    BOOL enabled = [self isEnabled];
    NSColor *text = enabled ? [NSColor labelColor] : [NSColor disabledControlTextColor];
    if (![_cells count]) {
        NSAttributedString *ph = _placeholderAttributed;
        if (!ph && _placeholder)
            ph = AAttributed(_placeholder, [self font] ?: ADefaultFont(), [NSColor placeholderTextColor]);
        if (ph) {
            CGFloat ascent, descent;
            ALineSize(ph, &ascent, &descent);
            CGFloat base = flipped ? floor(NSMidY(frame) + (ascent - descent) / 2) : ceil(NSMidY(frame) - (ascent - descent) / 2);
            ADrawLine(ph, NSMinX(frame) + (_style == NSPathStylePopUp ? 8 : 5), base);
        }
        if (_style != NSPathStylePopUp)
            return;
    }
    if (_style == NSPathStylePopUp) {
        NSRect b = NSInsetRect(frame, 1.5, 1.5);
        b.size.height = fmin(b.size.height, 22);
        b.origin.y = floor(NSMidY(frame) - b.size.height / 2) + 0.5;
        AFillRoundedRect(b, 5, _pressed ? [NSColor colorWithWhite:0.9 alpha:1] : [NSColor whiteColor],
                         [NSColor colorWithWhite:0 alpha:0.22]);
        NSPathComponentCell *last = [_cells lastObject];
        NSRect tr = NSMakeRect(NSMinX(b) + 7, NSMinY(b), b.size.width - 7 - 22, b.size.height);
        [last _drawInRect:tr flipped:flipped color:text];
        /* the up-and-down chevrons of a pop-up button */
        CGFloat cx = NSMaxX(b) - 11, cy = NSMidY(b);
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p moveToPoint:NSMakePoint(cx - 3, cy - 2)];
        [p lineToPoint:NSMakePoint(cx, cy - 5)];
        [p lineToPoint:NSMakePoint(cx + 3, cy - 2)];
        [p moveToPoint:NSMakePoint(cx - 3, cy + 2)];
        [p lineToPoint:NSMakePoint(cx, cy + 5)];
        [p lineToPoint:NSMakePoint(cx + 3, cy + 2)];
        [p setLineWidth:1.5];
        [p setLineCapStyle:NSLineCapStyleRound];
        [p setLineJoinStyle:NSLineJoinStyleRound];
        [(enabled ? [NSColor secondaryLabelColor] : [NSColor disabledControlTextColor]) setStroke];
        [p stroke];
        return;
    }
    NSArray *rects = [self _layoutInFrame:frame];
    for (NSUInteger i = 0; i < [_cells count]; i++) {
        NSRect r = [rects[i] rectValue];
        NSPathComponentCell *c = _cells[i];
        if (c == _pressed)
            AFillRoundedRect(NSInsetRect(r, -3, 2), 4, [NSColor colorWithWhite:0 alpha:0.08], nil);
        BOOL last = i + 1 == [_cells count];
        [c _drawInRect:r flipped:flipped color:last || !enabled ? text : [NSColor secondaryLabelColor]];
        if (!last)
            draw_chevron(NSMakeRect(NSMaxX(r), NSMinY(r), chevron_width, r.size.height), flipped);
    }
}
@end

/* ---- the control ----------------------------------------------------------------------- */

@implementation NSPathControl {
    BOOL _loading, _editable;
    id _delegate;
    NSPathComponentCell *_tracking;   /* the component the mouse went down on */
}

+ (Class)cellClass { return [NSPathCell class]; }
- (NSPathCell *)_pathCell { return (NSPathCell *)[self cell]; }

- (void)_setDefaults
{
    [super _setDefaults];
    if (!_loading && ![[self cell] isKindOfClass:[NSPathCell class]]) {
        NSPathCell *cell = [[NSPathCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    _loading = YES;
    if (!(self = [super initWithCoder:coder]))
        return nil;
    _loading = NO;
    if (![[self cell] isKindOfClass:[NSPathCell class]]) {
        NSPathCell *cell = [[NSPathCell alloc] initTextCell:@""];
        [self setCell:cell];
        [cell release];
    }
    if ([coder containsValueForKey:@"NSEditable"])
        _editable = [coder decodeBoolForKey:@"NSEditable"];
    return self;
}
- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
}
- (BOOL)isFlipped { return YES; }

- (NSPathStyle)pathStyle { return [[self _pathCell] pathStyle]; }
- (void)setPathStyle:(NSPathStyle)s
{
    [[self _pathCell] setPathStyle:s];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}
- (NSURL *)URL { return [[self _pathCell] URL]; }
- (void)setURL:(NSURL *)url { [self setObjectValue:url]; }
- (id)objectValue { return [[self _pathCell] URL]; }
- (void)setObjectValue:(id)value
{
    [[self _pathCell] setObjectValue:value];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}
- (NSString *)stringValue { return [[self _pathCell] stringValue]; }
- (void)setStringValue:(NSString *)s { [self setObjectValue:s]; }

- (NSArray *)pathComponentCells { return [[self _pathCell] pathComponentCells]; }
- (void)setPathComponentCells:(NSArray *)cells
{
    [[self _pathCell] setPathComponentCells:cells];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}
- (NSPathComponentCell *)clickedPathComponentCell { return [[self _pathCell] clickedPathComponentCell]; }

- (NSArray *)pathItems
{
    NSMutableArray *items = [NSMutableArray array];
    for (NSPathComponentCell *c in [self pathComponentCells])
        [items addObject:[[[NSPathControlItem alloc] _initWithCell:c] autorelease]];
    return items;
}
- (void)setPathItems:(NSArray *)items
{
    NSMutableArray *cells = [NSMutableArray array];
    for (NSPathControlItem *item in items) {
        NSPathComponentCell *c = [item _cell];
        if (![c font])
            [c setFont:[self font] ?: ADefaultFont()];
        [cells addObject:c];
    }
    [self setPathComponentCells:cells];
}
- (NSPathControlItem *)clickedPathItem
{
    NSPathComponentCell *c = [self clickedPathComponentCell];
    return c ? [[[NSPathControlItem alloc] _initWithCell:c] autorelease] : nil;
}

- (NSString *)placeholderString { return [[self _pathCell] placeholderString]; }
- (void)setPlaceholderString:(NSString *)s
{
    [[self _pathCell] setPlaceholderString:s];
    [self setNeedsDisplay:YES];
}
- (NSAttributedString *)placeholderAttributedString { return [[self _pathCell] placeholderAttributedString]; }
- (void)setPlaceholderAttributedString:(NSAttributedString *)s
{
    [[self _pathCell] setPlaceholderAttributedString:s];
    [self setNeedsDisplay:YES];
}
- (NSColor *)backgroundColor { return [[self _pathCell] backgroundColor]; }
- (void)setBackgroundColor:(NSColor *)c
{
    [[self _pathCell] setBackgroundColor:c];
    [self setNeedsDisplay:YES];
}
- (NSArray *)allowedTypes { return [[self _pathCell] allowedTypes]; }
- (void)setAllowedTypes:(NSArray *)t { [[self _pathCell] setAllowedTypes:t]; }
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)f { _editable = f; }
- (SEL)doubleAction { return [[self _pathCell] doubleAction]; }
- (void)setDoubleAction:(SEL)sel { [[self _pathCell] setDoubleAction:sel]; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }

- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, [[self _pathCell] cellSize].height); }

/* ---- clicks ---- */

- (BOOL)acceptsFirstResponder { return [NSApp isFullKeyboardAccessEnabled] && [self isEnabled]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }

- (void)_chose:(NSPathComponentCell *)c clicks:(NSInteger)clicks
{
    NSPathCell *cell = [self _pathCell];
    [cell _setClicked:c];
    [self sendAction:[self action] to:[self target]];
    if (clicks >= 2 && [cell doubleAction])
        [self sendAction:[cell doubleAction] to:[self target]];
}

- (void)_popUp
{
    NSArray *cells = [self pathComponentCells];
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    for (NSPathComponentCell *c in [cells reverseObjectEnumerator]) {
        NSMenuItem *item = [menu addItemWithTitle:[c stringValue] action:NULL keyEquivalent:@""];
        [item setRepresentedObject:c];
        NSImage *image = [[[c image] copy] autorelease];
        [image setSize:NSMakeSize(icon_size, icon_size)];
        [item setImage:image];
    }
    if ([_delegate respondsToSelector:@selector(pathControl:willPopUpMenu:)])
        [_delegate pathControl:self willPopUpMenu:menu];
    if (![menu numberOfItems])
        return;
    [AMenuView openMenu:menu forView:self rect:[self bounds] alignItem:0 skipFirst:NO font:[self font] owner:(id)self];
}
- (void)_menuView:(AMenuView *)menuView didChooseItem:(NSMenuItem *)item
{
    [[self _pathCell] _setPressed:nil];
    [self setNeedsDisplay:YES];
    if (!item)
        return;
    id c = [item representedObject];
    if ([c isKindOfClass:[NSPathComponentCell class]]) {
        [self _chose:c clicks:1];
    } else if ([item action]) {
        /* an item the delegate added */
        [NSApp sendAction:[item action] to:[item target] from:item];
    }
}

- (void)mouseDown:(NSEvent *)e
{
    if (![self isEnabled])
        return;
    NSPathCell *cell = [self _pathCell];
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    if ([self pathStyle] == NSPathStylePopUp) {
        [cell _setPressed:[[self pathComponentCells] lastObject]];
        [self setNeedsDisplay:YES];
        [self _popUp];
        return;
    }
    _tracking = [cell pathComponentCellAtPoint:p withFrame:[self bounds] inView:self];
    [cell _setPressed:_tracking];
    [self setNeedsDisplay:YES];
}
- (void)mouseDragged:(NSEvent *)e
{
    if (!_tracking)
        return;
    NSPathCell *cell = [self _pathCell];
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSPathComponentCell *over = [cell pathComponentCellAtPoint:p withFrame:[self bounds] inView:self];
    [cell _setPressed:over == _tracking ? _tracking : nil];
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)e
{
    if (!_tracking)
        return;
    NSPathCell *cell = [self _pathCell];
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSPathComponentCell *over = [cell pathComponentCellAtPoint:p withFrame:[self bounds] inView:self];
    NSPathComponentCell *t = _tracking;
    _tracking = nil;
    [cell _setPressed:nil];
    [self setNeedsDisplay:YES];
    if (over == t)
        [self _chose:t clicks:[e clickCount]];
}
- (void)keyDown:(NSEvent *)e
{
    NSString *c = [e charactersIgnoringModifiers];
    if ([self pathStyle] == NSPathStylePopUp && ([c isEqualToString:@" "] || [c isEqualToString:@"\r"])) {
        [self _popUp];
        return;
    }
    [super keyDown:e];
}

- (void)drawRect:(NSRect)dirty
{
    [[self _pathCell] drawWithFrame:[self bounds] inView:self];
    if ([[self window] firstResponder] == self && [[self window] isKeyWindow]) {
        NSBezierPath *ring = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self bounds], 1, 1) xRadius:5 yRadius:5];
        [ring setLineWidth:2.5];
        [[NSColor keyboardFocusIndicatorColor] setStroke];
        [ring stroke];
    }
}
@end
