/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: table views. Our own code, written from Apple's public
 * API documentation.
 *
 * An NSTableView lays its rows out top to bottom (it is flipped) and its
 * columns left to right; each row is rowHeight plus the intercell spacing's
 * height tall (or what the delegate's tableView:heightOfRow: says), each
 * column its width plus the spacing's width. It works in one of two ways,
 * chosen the way a Mac chooses: when the delegate makes views
 * (tableView:viewForTableColumn:row:) the table is view-based, and shows an
 * NSTableRowView for each visible row with the delegate's cell views in
 * it; otherwise it is cell-based, and draws each column's data cell itself
 * with the values the data source gives. Views are only made for the rows
 * in sight, and views that scroll out of sight are kept for
 * makeViewWithIdentifier:owner: to hand out again.
 *
 * Selections are drawn as current macOS draws them: rounded, in the accent
 * colour while the table has the keyboard (grey otherwise), inset from the
 * table's sides, with a run of selected rows drawn as one block.
 *
 * Editing in place: a double click on an editable cell of a selected row,
 * Return on a single selected row, or editColumn:row:withEvent:select:
 * edits a text cell. In a view-based table the cell's own text field is
 * edited, and its action goes to its target as editing ends with a change
 * (or by Return); in a cell-based table a text field is laid over the
 * cell, the data source gets the new string through
 * tableView:setObjectValue:forTableColumn:row:, and the table posts
 * NSControlTextDidEndEditingNotification (with "NSTextMovement") as the
 * control. A cell-based cell is edited only when its column is editable,
 * its cell is a text cell and tableView:shouldEditTableColumn:row: agrees.
 * Tab and Shift-Tab move on to the next or previous editable cell, row by
 * row, and stop at the table's ends; Escape puts the old value back. A
 * column cell's formatter shows the value being edited and reads what was
 * typed, so the data source gets the value (Ferry 0.17.0).
 *
 * Dragging rows (freemac 1.220, Ferry 0.44.0), as Sequel Pro and MacPass
 * do it: when the data source gives pasteboard writers for rows
 * (tableView:pasteboardWriterForRow:) or writes them itself
 * (tableView:writeRowsWithIndexes:toPasteboard:), a press on a row and a
 * move of a few points drags the selected rows if it is one of them, or
 * that row (a press on a row of a larger selection changes the selection
 * only if no drag begins); with verticalMotionCanBeginDrag off, a move
 * straight up or down selects rows instead. The table is the drag's
 * source, offering draggingSourceOperationMaskForLocal: (everything,
 * unless setDraggingSourceOperationMask:forLocal: or the nib says
 * otherwise), and its data source hears the drag begin and end. A table
 * that registered the drag's types takes drops: the point proposes a row
 * and an operation (on a row from its middle, above it from its top
 * quarter, below it from its bottom quarter, below the last row past the
 * end), the data source's tableView:validateDrop:proposedRow:
 * proposedDropOperation: answers and may change it with setDropRow:
 * dropOperation: (-1 and NSTableViewDropOn for the whole table), the
 * table shows it as a line between rows or a ring round a row, and
 * tableView:acceptDrop:row:dropOperation: takes it. Drags stay within the
 * app (see NSDragging.m).
 *
 * Not done yet: editing after a pause on a click in a selected row,
 * dragging columns, type-to-select, dragging rows to other apps, promised
 * files, and saving column widths under autosaveName. Animations run
 * instantly.
 *
 * Nibs: the table's switches are "NSTvFlags", whose bits (column
 * reordering, column resizing, grid, empty and multiple selection, column
 * selection, alternating rows) follow descriptions of the format
 * published by developers and the GNUstep project; no Apple code was
 * read. A view-based table's cell view prototypes come as
 * "NSTableViewArchivedReusableViewsKey", identifiers mapped to nibs. */
#import "AInternal.h"

NSNotificationName const NSTableViewSelectionDidChangeNotification = @"NSTableViewSelectionDidChangeNotification";
NSNotificationName const NSTableViewSelectionIsChangingNotification = @"NSTableViewSelectionIsChangingNotification";
NSNotificationName const NSTableViewColumnDidMoveNotification = @"NSTableViewColumnDidMoveNotification";
NSNotificationName const NSTableViewColumnDidResizeNotification = @"NSTableViewColumnDidResizeNotification";
NSUserInterfaceItemIdentifier const NSTableViewRowViewKey = @"NSTableViewRowViewKey";

static const CGFloat header_height = 28;
static const CGFloat selection_inset = 5, selection_radius = 5;

@interface NSButtonCell (FerryTableCheck)
- (BOOL)_isCheck;
@end

/* ---- colours -------------------------------------------------------------------------- */

@implementation NSColor (NSTableViewColors)
+ (NSArray *)alternatingContentBackgroundColors
{
    static NSArray *colors;
    if (!colors)
        colors = [@[ [NSColor colorWithCalibratedWhite:1 alpha:1], [NSColor colorWithCalibratedWhite:0.957 alpha:1] ]
            retain];
    return colors;
}
+ (NSArray *)controlAlternatingRowBackgroundColors { return [self alternatingContentBackgroundColors]; }
+ (NSColor *)selectedContentBackgroundColor { return [NSColor controlAccentColor]; }
+ (NSColor *)unemphasizedSelectedContentBackgroundColor { return [NSColor colorWithCalibratedWhite:0.863 alpha:1]; }
+ (NSColor *)alternateSelectedControlTextColor { return [NSColor whiteColor]; }
+ (NSColor *)unemphasizedSelectedTextColor { return [NSColor labelColor]; }
+ (NSColor *)selectedControlTextColor { return [NSColor controlTextColor]; }
@end

/* ---- drawing helpers ------------------------------------------------------------------ */

/* A rectangle whose corners at its smaller y are rounded by r0 and those
 * at its larger y by r1. */
static NSBezierPath *corner_path(NSRect r, CGFloat r0, CGFloat r1)
{
    const CGFloat k = 0.4477; /* how far a control point sits from the corner, as a share of the radius */
    CGFloat x0 = NSMinX(r), x1 = NSMaxX(r), y0 = NSMinY(r), y1 = NSMaxY(r);
    r0 = fmin(r0, fmin(r.size.width, r.size.height) / 2);
    r1 = fmin(r1, fmin(r.size.width, r.size.height) / 2);
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(x0 + r0, y0)];
    [p lineToPoint:NSMakePoint(x1 - r0, y0)];
    if (r0 > 0)
        [p curveToPoint:NSMakePoint(x1, y0 + r0) controlPoint1:NSMakePoint(x1 - r0 * k, y0)
           controlPoint2:NSMakePoint(x1, y0 + r0 * k)];
    [p lineToPoint:NSMakePoint(x1, y1 - r1)];
    if (r1 > 0)
        [p curveToPoint:NSMakePoint(x1 - r1, y1) controlPoint1:NSMakePoint(x1, y1 - r1 * k)
           controlPoint2:NSMakePoint(x1 - r1 * k, y1)];
    [p lineToPoint:NSMakePoint(x0 + r1, y1)];
    if (r1 > 0)
        [p curveToPoint:NSMakePoint(x0, y1 - r1) controlPoint1:NSMakePoint(x0 + r1 * k, y1)
           controlPoint2:NSMakePoint(x0, y1 - r1 * k)];
    [p lineToPoint:NSMakePoint(x0, y0 + r0)];
    if (r0 > 0)
        [p curveToPoint:NSMakePoint(x0 + r0, y0) controlPoint1:NSMakePoint(x0, y0 + r0 * k)
           controlPoint2:NSMakePoint(x0 + r0 * k, y0)];
    [p closePath];
    return p;
}

/* A selection over rows r (in a flipped view): rounded and inset unless
 * the table is full width or plain. top and bottom say whether a
 * neighbouring selected row joins on. */
void ATableDrawSelection(NSRect r, NSTableViewStyle style, NSTableViewSelectionHighlightStyle highlight,
                           BOOL emphasized, BOOL joinsAbove, BOOL joinsBelow)
{
    if (highlight == NSTableViewSelectionHighlightStyleNone || NSIsEmptyRect(r))
        return;
    NSColor *fill = emphasized ? [NSColor selectedContentBackgroundColor]
                               : [NSColor unemphasizedSelectedContentBackgroundColor];
    if (style == NSTableViewStyleFullWidth || style == NSTableViewStylePlain) {
        [fill setFill];
        NSRectFill(r);
        return;
    }
    r = NSInsetRect(r, selection_inset, 0);
    [fill setFill];
    [corner_path(r, joinsAbove ? 0 : selection_radius, joinsBelow ? 0 : selection_radius) fill];
}

/* A line of text, cut short with an ellipsis if it doesn't fit width. */
void ATableDrawTextLine(NSAttributedString *s, NSRect frame, NSTextAlignment align, BOOL flipped)
{
    CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
    if (!cg || ![s length] || frame.size.width <= 0)
        return;
    CTLineRef line = CTLineCreateWithAttributedString((CFAttributedStringRef)s);
    CGFloat ascent = 0, descent = 0, leading = 0;
    double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    if (width > frame.size.width) {
        NSDictionary *attrs = [s attributesAtIndex:0 effectiveRange:NULL];
        NSAttributedString *dots = [[NSAttributedString alloc] initWithString:@"…" attributes:attrs];
        CTLineRef token = CTLineCreateWithAttributedString((CFAttributedStringRef)dots);
        CTLineRef cut = CTLineCreateTruncatedLine(line, frame.size.width, kCTLineTruncationEnd, token);
        CFRelease(token);
        [dots release];
        if (cut) {
            CFRelease(line);
            line = cut;
            width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
        }
    }
    CGFloat x = frame.origin.x;
    if (align == NSTextAlignmentRight)
        x = NSMaxX(frame) - width;
    else if (align == NSTextAlignmentCenter)
        x = NSMidX(frame) - width / 2;
    CGFloat y = flipped ? floor(NSMidY(frame) + (ascent - descent) / 2) : ceil(NSMidY(frame) - (ascent - descent) / 2);
    CGContextSaveGState(cg);
    CGContextClipToRect(cg, frame);
    CGAffineTransform saved = CGContextGetTextMatrix(cg);
    CGContextSetTextMatrix(cg, flipped ? CGAffineTransformMakeScale(1, -1) : CGAffineTransformIdentity);
    CGContextSetTextPosition(cg, round(x * 2) / 2, y);
    CTLineDraw(line, cg);
    CGContextSetTextMatrix(cg, saved);
    CGContextRestoreGState(cg);
    CFRelease(line);
}

/* A chevron pointing right, or down when open, centred in r. */
void ATableDrawChevron(NSRect r, BOOL down, NSColor *color, BOOL flipped)
{
    CGFloat cx = NSMidX(r), cy = NSMidY(r), s = 3.5;
    NSBezierPath *p = [NSBezierPath bezierPath];
    if (down) {
        CGFloat dy = flipped ? s / 2 : -s / 2;
        [p moveToPoint:NSMakePoint(cx - s, cy - dy)];
        [p lineToPoint:NSMakePoint(cx, cy + dy)];
        [p lineToPoint:NSMakePoint(cx + s, cy - dy)];
    } else {
        [p moveToPoint:NSMakePoint(cx - s / 2, cy - s)];
        [p lineToPoint:NSMakePoint(cx + s / 2, cy)];
        [p lineToPoint:NSMakePoint(cx - s / 2, cy + s)];
    }
    [p setLineWidth:1.6];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [color setStroke];
    [p stroke];
}

/* ---- cells drawing themselves --------------------------------------------------------- */

static NSColor *cell_text_color(NSCell *cell, NSColor *own)
{
    if (![cell isEnabled])
        return [NSColor disabledControlTextColor];
    if ([cell backgroundStyle] == NSBackgroundStyleEmphasized)
        return [NSColor alternateSelectedControlTextColor];
    return own ?: [NSColor controlTextColor];
}

@implementation NSCell (NSCellDrawing)
- (NSRect)drawingRectForBounds:(NSRect)r { return NSInsetRect(r, 2, 0); }
- (NSRect)titleRectForBounds:(NSRect)r { return [self drawingRectForBounds:r]; }
- (NSRect)imageRectForBounds:(NSRect)r { return [self drawingRectForBounds:r]; }
- (NSSize)cellSizeForBounds:(NSRect)r
{
    NSSize s = [self cellSize];
    return NSMakeSize(fmin(s.width, r.size.width), fmin(s.height, r.size.height));
}
- (NSSize)cellSize
{
    NSImage *image = [self image];
    if (image && ![[self stringValue] length])
        return [image size];
    NSSize s = ALineSize(AAttributed([self stringValue], [self font] ?: ADefaultFont(), [NSColor textColor]), NULL, NULL);
    return NSMakeSize(s.width + 4, s.height + 2);
}
- (NSColor *)_drawingTextColor { return cell_text_color(self, nil); }
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    id value = [self objectValue];
    if ([value isKindOfClass:[NSImage class]]) {
        NSImage *image = value;
        NSSize s = [image size];
        if (s.width <= 0 || s.height <= 0)
            return;
        CGFloat scale = fmin(1, fmin(frame.size.width / s.width, frame.size.height / s.height));
        NSRect r = NSMakeRect(NSMidX(frame) - s.width * scale / 2, NSMidY(frame) - s.height * scale / 2,
                              s.width * scale, s.height * scale);
        BOOL white = [self backgroundStyle] == NSBackgroundStyleEmphasized;
        [image _drawInControlRect:r color:white ? [NSColor whiteColor] : [NSColor labelColor] fraction:[self isEnabled] ? 1 : 0.5];
        return;
    }
    NSFont *font = [self font] ?: ADefaultFont();
    NSColor *color = [self _drawingTextColor];
    NSAttributedString *s;
    if ([value isKindOfClass:[NSAttributedString class]] && [self backgroundStyle] != NSBackgroundStyleEmphasized)
        s = value;
    else
        s = AAttributed([self stringValue], font, color);
    ATableDrawTextLine(s, [self titleRectForBounds:frame], [self alignment], [view isFlipped]);
}
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view { [self drawInteriorWithFrame:frame inView:view]; }
@end

@implementation NSTextFieldCell (NSCellDrawing)
- (NSColor *)_drawingTextColor { return cell_text_color(self, [self textColor]); }
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view
{
    if ([self drawsBackground] && [self backgroundColor] && [self backgroundStyle] != NSBackgroundStyleEmphasized) {
        [[self backgroundColor] setFill];
        NSRectFill(frame);
    }
    if ([self isBezeled] || [self isBordered]) {
        [[NSColor colorWithCalibratedWhite:0 alpha:0.25] setFill];
        NSFrameRect(frame);
    }
    [self drawInteriorWithFrame:frame inView:view];
}
@end

@implementation NSButtonCell (NSCellDrawing)
- (BOOL)_isCheck { return [self _hasButtonType] && ([self _buttonType] == NSButtonTypeSwitch || [self _buttonType] == NSButtonTypeRadio); }
- (NSSize)cellSize
{
    NSSize s = [super cellSize];
    return [self _isCheck] ? NSMakeSize(s.width + 20, fmax(s.height, 16)) : NSMakeSize(s.width + 16, fmax(s.height, 20));
}
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    BOOL flipped = [view isFlipped];
    CGFloat dim = [self isEnabled] ? 1 : 0.45;
    NSString *title = [self title];
    if ([self _isCheck]) {
        BOOL radio = [self _buttonType] == NSButtonTypeRadio;
        CGFloat size = 14;
        BOOL hasTitle = [title length] > 0 && ![[self objectValue] isKindOfClass:[NSNumber class]];
        CGFloat x = hasTitle || [self alignment] != NSTextAlignmentCenter ? frame.origin.x + 2 : floor(NSMidX(frame) - size / 2);
        NSRect box = NSMakeRect(x, floor(NSMidY(frame) - size / 2), size, size);
        BOOL on = [self state] != NSControlStateValueOff;
        NSColor *fill = on ? [NSColor controlAccentColor] : [NSColor whiteColor];
        if (on && [self backgroundStyle] == NSBackgroundStyleEmphasized)
            fill = [NSColor whiteColor];
        AFillRoundedRect(box, radio ? size / 2 : 3.5, [fill colorWithAlphaComponent:dim],
                         on && [self backgroundStyle] != NSBackgroundStyleEmphasized ? nil : [NSColor colorWithWhite:0 alpha:0.3 * dim]);
        if (on) {
            NSColor *mark = [self backgroundStyle] == NSBackgroundStyleEmphasized ? [NSColor controlAccentColor] : [NSColor whiteColor];
            [[mark colorWithAlphaComponent:dim] set];
            if (radio) {
                [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(box, 4.5, 4.5)] fill];
            } else if ([self state] == NSControlStateValueMixed) {
                NSRectFill(NSMakeRect(box.origin.x + 3.5, NSMidY(box) - 1, size - 7, 2));
            } else {
                NSBezierPath *tick = [NSBezierPath bezierPath];
                CGFloat y0 = box.origin.y;
                #define Y(v) (flipped ? y0 + size - (v) : y0 + (v))
                [tick moveToPoint:NSMakePoint(box.origin.x + 3.5, Y(7.2))];
                [tick lineToPoint:NSMakePoint(box.origin.x + 6, Y(4.5))];
                [tick lineToPoint:NSMakePoint(box.origin.x + 10.5, Y(10))];
                #undef Y
                [tick setLineWidth:2];
                [tick setLineCapStyle:NSLineCapStyleRound];
                [tick setLineJoinStyle:NSLineJoinStyleRound];
                [tick stroke];
            }
        }
        if (hasTitle)
            ATableDrawTextLine(AAttributed(title, [self font] ?: ADefaultFont(), [self _drawingTextColor]),
                           NSMakeRect(NSMaxX(box) + 5, frame.origin.y, NSMaxX(frame) - NSMaxX(box) - 5, frame.size.height),
                           NSTextAlignmentLeft, flipped);
        return;
    }
    NSColor *background = [self backgroundColor];
    if (background && ![self isTransparent]) {
        [background set];
        NSRectFillUsingOperation(frame, NSCompositingOperationSourceOver);
    }
    if ([self isBordered] && ![self isTransparent]) {
        CGFloat h = fmin(frame.size.height - 2, 20);
        NSRect bezel = NSMakeRect(frame.origin.x + 2, floor(NSMidY(frame) - h / 2), frame.size.width - 4, h);
        AFillRoundedRect(bezel, 5, [[NSColor whiteColor] colorWithAlphaComponent:dim], [NSColor colorWithWhite:0 alpha:0.22]);
    }
    NSImage *image = [self image];
    if (image && ![title length]) {
        NSSize s = [image size];
        NSRect r = NSMakeRect(NSMidX(frame) - s.width / 2, NSMidY(frame) - s.height / 2, s.width, s.height);
        [image _drawInControlRect:r color:[self _drawingTextColor] fraction:dim];
        return;
    }
    if (![self isTransparent])
        ATableDrawTextLine(AAttributed(title, [self font] ?: ADefaultFont(), [self _drawingTextColor]), NSInsetRect(frame, 6, 0),
                       [self alignment], flipped);
}
@end

@implementation NSImageCell (NSCellDrawing)
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    NSImage *image = [self image];
    NSSize s = [image size];
    if (!image || s.width <= 0 || s.height <= 0)
        return;
    CGFloat sx = frame.size.width / s.width, sy = frame.size.height / s.height, scale;
    switch ([self imageScaling]) {
    case NSImageScaleAxesIndependently:
        [image _drawInControlRect:frame color:[NSColor labelColor] fraction:1];
        return;
    case NSImageScaleNone: scale = 1; break;
    case NSImageScaleProportionallyUpOrDown: scale = fmin(sx, sy); break;
    default: scale = fmin(1, fmin(sx, sy)); break;
    }
    NSRect r = NSMakeRect(NSMidX(frame) - s.width * scale / 2, NSMidY(frame) - s.height * scale / 2, s.width * scale,
                          s.height * scale);
    [image _drawInControlRect:r color:[self backgroundStyle] == NSBackgroundStyleEmphasized ? [NSColor whiteColor]
                                                                                           : [NSColor labelColor]
                     fraction:1];
}
@end

/* ---- NSTableHeaderCell ---------------------------------------------------------------- */

@implementation NSTableHeaderCell
- (instancetype)initTextCell:(NSString *)string
{
    if ((self = [super initTextCell:string])) {
        [self setFont:[NSFont systemFontOfSize:11]];
        [self setLineBreakMode:NSLineBreakByTruncatingTail];
        [self setWraps:NO];
    }
    return self;
}
- (NSRect)sortIndicatorRectForBounds:(NSRect)r { return NSMakeRect(NSMaxX(r) - 18, r.origin.y, 12, r.size.height); }
- (void)drawSortIndicatorWithFrame:(NSRect)frame inView:(NSView *)view ascending:(BOOL)ascending
                          priority:(NSInteger)priority
{
    if (priority != 0)
        return;
    NSRect r = [self sortIndicatorRectForBounds:frame];
    BOOL flipped = [view isFlipped];
    /* a small chevron: up for ascending, down for descending */
    CGFloat cx = NSMidX(r), cy = NSMidY(r), s = 3.5, dy = (ascending == flipped) ? -s / 2 : s / 2;
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(cx - s, cy - dy)];
    [p lineToPoint:NSMakePoint(cx, cy + dy)];
    [p lineToPoint:NSMakePoint(cx + s, cy - dy)];
    [p setLineWidth:1.5];
    [p setLineCapStyle:NSLineCapStyleRound];
    [p setLineJoinStyle:NSLineJoinStyleRound];
    [[NSColor secondaryLabelColor] setStroke];
    [p stroke];
}
- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view
{
    NSColor *color = [self textColor] ?: [NSColor headerTextColor];
    ATableDrawTextLine(AAttributed([self stringValue], [self font] ?: [NSFont systemFontOfSize:11], color),
                   NSInsetRect(frame, 6, 0), [self alignment] == NSTextAlignmentNatural ? NSTextAlignmentLeft : [self alignment],
                   [view isFlipped]);
}
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view { [self drawInteriorWithFrame:frame inView:view]; }
@end

/* ---- NSTableColumn -------------------------------------------------------------------- */

@implementation NSTableColumn {
    NSString *_identifier, *_toolTip;
    NSTableView *_tableView;   /* not retained */
    CGFloat _width, _minWidth, _maxWidth;
    NSTableHeaderCell *_headerCell;
    NSCell *_dataCell;
    BOOL _editable, _hidden;
    NSTableColumnResizingOptions _resizing;
    NSSortDescriptor *_prototype;
}
- (void)_setUp
{
    _width = 100;
    _minWidth = 10;
    _maxWidth = 1e6;
    _editable = YES;
    _resizing = NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask;
    _headerCell = [[NSTableHeaderCell alloc] initTextCell:@""];
    NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
    [cell setWraps:NO];
    _dataCell = cell;
}
- (instancetype)init { return [self initWithIdentifier:@""]; }
- (instancetype)initWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    if ((self = [super init])) {
        [self _setUp];
        _identifier = [identifier copy];
    }
    return self;
}
static id decoded(NSCoder *c, NSString *key, Class cls)
{
    id v = [c containsValueForKey:key] ? [c decodeObjectForKey:key] : nil;
    return [v isKindOfClass:cls] ? v : nil;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super init]))
        return nil;
    [self _setUp];
    id ident = [coder containsValueForKey:@"NSIdentifier"] ? [coder decodeObjectForKey:@"NSIdentifier"] : nil;
    if ([ident isKindOfClass:[NSString class]])
        _identifier = [ident copy];
    else if (ident)
        _identifier = [[ident description] copy];
    if ([coder containsValueForKey:@"NSWidth"])
        _width = [coder decodeDoubleForKey:@"NSWidth"];
    if ([coder containsValueForKey:@"NSMinWidth"])
        _minWidth = [coder decodeDoubleForKey:@"NSMinWidth"];
    if ([coder containsValueForKey:@"NSMaxWidth"])
        _maxWidth = [coder decodeDoubleForKey:@"NSMaxWidth"];
    if (_maxWidth < _minWidth)
        _maxWidth = _minWidth;
    _width = fmax(_minWidth, fmin(_width, _maxWidth));
    NSCell *header = decoded(coder, @"NSHeaderCell", [NSCell class]);
    if (header) {
        if ([header isKindOfClass:[NSTableHeaderCell class]]) {
            [_headerCell release];
            _headerCell = (NSTableHeaderCell *)[header retain];
        } else {
            [_headerCell setStringValue:[header stringValue]];
            if ([header font])
                [_headerCell setFont:[header font]];
            [_headerCell setAlignment:[header alignment]];
        }
    }
    NSCell *data = decoded(coder, @"NSDataCell", [NSCell class]);
    if (data) {
        [_dataCell release];
        _dataCell = [data retain];
    }
    if ([coder containsValueForKey:@"NSResizingMask"])
        _resizing = (NSTableColumnResizingOptions)[coder decodeIntegerForKey:@"NSResizingMask"];
    else if ([coder containsValueForKey:@"NSIsResizeable"])
        _resizing = [coder decodeBoolForKey:@"NSIsResizeable"] ? NSTableColumnUserResizingMask | NSTableColumnAutoresizingMask : 0;
    if ([coder containsValueForKey:@"NSIsEditable"])
        _editable = [coder decodeBoolForKey:@"NSIsEditable"];
    if ([coder containsValueForKey:@"NSIsHidden"])
        _hidden = [coder decodeBoolForKey:@"NSIsHidden"];
    NSTableView *table = decoded(coder, @"NSTableView", [NSTableView class]);
    if (table)
        _tableView = table;
    _prototype = [decoded(coder, @"NSSortDescriptorPrototype", [NSSortDescriptor class]) copy];
    NSString *tip = decoded(coder, @"NSHeaderToolTip", [NSString class]);
    _toolTip = [tip copy];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_identifier)
        [coder encodeObject:_identifier forKey:@"NSIdentifier"];
    [coder encodeDouble:_width forKey:@"NSWidth"];
    [coder encodeDouble:_minWidth forKey:@"NSMinWidth"];
    [coder encodeDouble:_maxWidth forKey:@"NSMaxWidth"];
    [coder encodeObject:_headerCell forKey:@"NSHeaderCell"];
    [coder encodeObject:_dataCell forKey:@"NSDataCell"];
    [coder encodeInteger:(NSInteger)_resizing forKey:@"NSResizingMask"];
    [coder encodeBool:_editable forKey:@"NSIsEditable"];
    [coder encodeBool:_hidden forKey:@"NSIsHidden"];
    if (_prototype)
        [coder encodeObject:_prototype forKey:@"NSSortDescriptorPrototype"];
}
- (void)dealloc
{
    [_identifier release];
    [_toolTip release];
    [_headerCell release];
    [_dataCell release];
    [_prototype release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> %@ width %g", [self class], self, _identifier, _width];
}
- (NSUserInterfaceItemIdentifier)identifier { return _identifier; }
- (void)setIdentifier:(NSUserInterfaceItemIdentifier)i
{
    [_identifier release];
    _identifier = [i copy];
}
- (NSTableView *)tableView { return _tableView; }
- (void)setTableView:(NSTableView *)t { _tableView = t; }
- (CGFloat)width { return _width; }
- (void)setWidth:(CGFloat)w
{
    w = fmax(_minWidth, fmin(w, _maxWidth));
    if (w == _width)
        return;
    CGFloat old = _width;
    _width = w;
    [_tableView _columnWidthChanged:self from:old];
}
- (CGFloat)minWidth { return _minWidth; }
- (void)setMinWidth:(CGFloat)w
{
    _minWidth = fmax(w, 0);
    if (_maxWidth < _minWidth)
        _maxWidth = _minWidth;
    if (_width < _minWidth)
        [self setWidth:_minWidth];
}
- (CGFloat)maxWidth { return _maxWidth; }
- (void)setMaxWidth:(CGFloat)w
{
    _maxWidth = fmax(w, _minWidth);
    if (_width > _maxWidth)
        [self setWidth:_maxWidth];
}
- (NSString *)title { return [_headerCell stringValue]; }
- (void)setTitle:(NSString *)t
{
    [_headerCell setStringValue:t ?: @""];
    [[_tableView headerView] setNeedsDisplay:YES];
}
- (NSString *)headerToolTip { return _toolTip; }
- (void)setHeaderToolTip:(NSString *)t
{
    [_toolTip release];
    _toolTip = [t copy];
}
- (id)headerCell { return _headerCell; }
- (void)setHeaderCell:(NSTableHeaderCell *)c
{
    if (!c)
        return;
    [c retain];
    [_headerCell release];
    _headerCell = c;
    [[_tableView headerView] setNeedsDisplay:YES];
}
- (id)dataCell { return _dataCell; }
- (void)setDataCell:(NSCell *)c
{
    if (!c)
        return;
    [c retain];
    [_dataCell release];
    _dataCell = c;
    [_tableView setNeedsDisplay:YES];
}
- (id)dataCellForRow:(NSInteger)row { return _dataCell; }
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)f { _editable = f; }
- (BOOL)isHidden { return _hidden; }
- (void)setHidden:(BOOL)f
{
    if (f == _hidden)
        return;
    _hidden = f;
    [_tableView _columnWidthChanged:self from:_width];
}
- (NSTableColumnResizingOptions)resizingMask { return _resizing; }
- (void)setResizingMask:(NSTableColumnResizingOptions)m { _resizing = m; }
- (NSSortDescriptor *)sortDescriptorPrototype { return _prototype; }
- (void)setSortDescriptorPrototype:(NSSortDescriptor *)d
{
    [_prototype release];
    _prototype = [d copy];
}
- (void)sizeToFit
{
    NSSize s = ALineSize(AAttributed([self title], [_headerCell font] ?: ADefaultFont(), [NSColor textColor]), NULL, NULL);
    [self setWidth:fmax(_minWidth, s.width + 24)];
}
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSHeaderTitleBinding]) {
        [self setTitle:value ? [value description] : @""];
        [[_tableView headerView] setNeedsDisplay:YES];
    } else {
        [super _ferrySetValue:value forBinding:binding];
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSHeaderTitleBinding])
        return [self title];
    return [super _ferryValueForBinding:binding];
}
@end

/* ---- NSTableHeaderView ---------------------------------------------------------------- */

@implementation NSTableHeaderView {
    NSTableView *_tableView;   /* not retained */
    NSInteger _pressed, _resized, _dragged;
    CGFloat _grabX, _grabWidth, _draggedDistance;
    BOOL _moved;
}
- (void)_setUp
{
    _pressed = _resized = _dragged = -1;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if (frame.size.height <= 0)
        frame.size.height = header_height;
    if ((self = [super initWithFrame:frame]))
        [self _setUp];
    return self;
}
- (instancetype)init { return [self initWithFrame:NSMakeRect(0, 0, 0, header_height)]; }
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        [self _setUp];
        id table = [coder containsValueForKey:@"NSTableView"] ? [coder decodeObjectForKey:@"NSTableView"] : nil;
        if ([table isKindOfClass:[NSTableView class]])
            _tableView = table;
        if ([self frame].size.height <= 0)
            [self setFrameSize:NSMakeSize([self frame].size.width, header_height)];
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (NSTableView *)tableView { return _tableView; }
- (void)setTableView:(NSTableView *)t { _tableView = t; }
- (NSInteger)draggedColumn { return _dragged; }
- (NSInteger)resizedColumn { return _resized; }
- (CGFloat)draggedDistance { return _draggedDistance; }
- (NSRect)headerRectOfColumn:(NSInteger)column
{
    NSRect c = [_tableView rectOfColumn:column];
    return NSMakeRect(c.origin.x, 0, c.size.width, [self bounds].size.height);
}
- (NSInteger)columnAtPoint:(NSPoint)p
{
    NSInteger n = [_tableView numberOfColumns];
    for (NSInteger i = 0; i < n; i++)
        if (NSMouseInRect(p, [self headerRectOfColumn:i], YES))
            return i;
    return -1;
}
/* The column whose right-hand divider is within reach of x. */
- (NSInteger)_dividerAt:(CGFloat)x
{
    if (![_tableView allowsColumnResizing])
        return -1;
    NSArray *cols = [_tableView tableColumns];
    for (NSInteger i = (NSInteger)[cols count] - 1; i >= 0; i--) {
        NSTableColumn *c = [cols objectAtIndex:i];
        if ([c isHidden] || !([c resizingMask] & NSTableColumnUserResizingMask))
            continue;
        if (fabs(x - NSMaxX([_tableView rectOfColumn:i])) <= 3)
            return i;
    }
    return -1;
}
- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirty);
    NSArray *cols = [_tableView tableColumns];
    NSArray *sorts = [_tableView sortDescriptors];
    NSSortDescriptor *first = [sorts firstObject];
    for (NSUInteger i = 0; i < [cols count]; i++) {
        NSTableColumn *c = [cols objectAtIndex:i];
        if ([c isHidden])
            continue;
        NSRect r = [self headerRectOfColumn:(NSInteger)i];
        if (!NSIntersectsRect(r, dirty))
            continue;
        if ((NSInteger)i == _pressed && _resized < 0) {
            [[NSColor colorWithCalibratedWhite:0 alpha:0.05] setFill];
            NSRectFill(r);
        }
        NSTableHeaderCell *cell = [c headerCell];
        NSSortDescriptor *proto = [c sortDescriptorPrototype];
        BOOL sorted = proto && first && [[proto key] isEqualToString:[first key]];
        NSRect title = r;
        if (sorted)
            title.size.width -= 14;
        [cell drawWithFrame:title inView:self];
        if (sorted)
            [cell drawSortIndicatorWithFrame:r inView:self ascending:[first ascending] priority:0];
        /* a thin divider, short of the top and bottom */
        [[NSColor separatorColor] setFill];
        NSRectFill(NSMakeRect(NSMaxX(r) - 1, b.origin.y + 6, 1, b.size.height - 12));
    }
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(dirty.origin.x, NSMaxY(b) - 1, dirty.size.width, 1));
}
- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    _moved = NO;
    _draggedDistance = 0;
    _resized = [self _dividerAt:p.x];
    if (_resized >= 0) {
        _grabX = p.x;
        _grabWidth = [[[_tableView tableColumns] objectAtIndex:(NSUInteger)_resized] width];
        return;
    }
    _pressed = [self columnAtPoint:p];
    if (_pressed >= 0) {
        [_tableView _mouseDownInHeaderOfColumn:[[_tableView tableColumns] objectAtIndex:(NSUInteger)_pressed]];
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseDragged:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    _moved = YES;
    if (_resized >= 0) {
        NSTableColumn *c = [[_tableView tableColumns] objectAtIndex:(NSUInteger)_resized];
        CGFloat before = [c width];
        CGFloat want = fmax([c minWidth], fmin(_grabWidth + (p.x - _grabX), [c maxWidth]));
        if (want != before)
            [_tableView _userResizedColumn:c by:want - before];
        [self setNeedsDisplay:YES];
    }
}
- (void)mouseUp:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSInteger pressed = _pressed;
    _pressed = -1;
    if (_resized >= 0) {
        _resized = -1;
        [self setNeedsDisplay:YES];
        return;
    }
    if (pressed >= 0 && [self columnAtPoint:p] == pressed)
        [_tableView _headerClickedColumn:[[_tableView tableColumns] objectAtIndex:(NSUInteger)pressed]];
    [self setNeedsDisplay:YES];
}
@end

/* The square above a table's vertical scroller, beside the header. */
@interface _NSCornerView : NSView
@end
@implementation _NSCornerView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(dirty);
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(b.origin.x, NSMaxY(b) - 1, b.size.width, 1));
}
@end

/* ---- NSTableRowView ------------------------------------------------------------------- */

@implementation NSTableRowView {
    BOOL _selected, _emphasized, _group, _floating, _prevSelected, _nextSelected, _target;
    NSTableViewSelectionHighlightStyle _highlight;
    NSTableViewDraggingDestinationFeedbackStyle _feedback;
    NSColor *_background;
    CGFloat _dropIndent;
@public
    NSMutableDictionary *_views;   /* column (by address, or NSNull for a group row) -> cell view */
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _views = [[NSMutableDictionary alloc] init];
        _emphasized = YES;
    }
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _views = [[NSMutableDictionary alloc] init];
        _emphasized = YES;
    }
    return self;
}
- (void)dealloc
{
    [_views release];
    [_background release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (NSTableView *)_table { return [[self superview] isKindOfClass:[NSTableView class]] ? (NSTableView *)[self superview] : nil; }
- (BOOL)isSelected { return _selected; }
- (void)setSelected:(BOOL)f
{
    if (f == _selected)
        return;
    _selected = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)isEmphasized { return _emphasized; }
- (void)setEmphasized:(BOOL)f
{
    if (f == _emphasized)
        return;
    _emphasized = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)isGroupRowStyle { return _group; }
- (void)setGroupRowStyle:(BOOL)f { _group = f; }
- (BOOL)isFloating { return _floating; }
- (void)setFloating:(BOOL)f { _floating = f; }
- (BOOL)isPreviousRowSelected { return _prevSelected; }
- (void)setPreviousRowSelected:(BOOL)f
{
    _prevSelected = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)isNextRowSelected { return _nextSelected; }
- (void)setNextRowSelected:(BOOL)f
{
    _nextSelected = f;
    [self setNeedsDisplay:YES];
}
- (NSTableViewSelectionHighlightStyle)selectionHighlightStyle { return _highlight; }
- (void)setSelectionHighlightStyle:(NSTableViewSelectionHighlightStyle)s { _highlight = s; }
- (NSTableViewDraggingDestinationFeedbackStyle)draggingDestinationFeedbackStyle { return _feedback; }
- (void)setDraggingDestinationFeedbackStyle:(NSTableViewDraggingDestinationFeedbackStyle)s { _feedback = s; }
- (NSColor *)backgroundColor { return _background; }
- (void)setBackgroundColor:(NSColor *)c
{
    [_background release];
    _background = [c copy];
    [self setNeedsDisplay:YES];
}
- (CGFloat)indentationForDropOperation { return _dropIndent; }
- (void)setIndentationForDropOperation:(CGFloat)v { _dropIndent = v; }
- (BOOL)isTargetForDropOperation { return _target; }
- (void)setTargetForDropOperation:(BOOL)f { _target = f; }
- (NSBackgroundStyle)interiorBackgroundStyle
{
    return _selected && _emphasized && _highlight != NSTableViewSelectionHighlightStyleNone ? NSBackgroundStyleEmphasized
                                                                                            : NSBackgroundStyleNormal;
}
- (NSInteger)numberOfColumns { return [[self _table] numberOfColumns]; }
- (NSView *)_viewForColumnKey:(id)key { return [_views objectForKey:key]; }
- (id)viewAtColumn:(NSInteger)column
{
    NSArray *cols = [[self _table] tableColumns];
    /* a group row's one view, across the row, is its first column's */
    if (column < 0 || column >= (NSInteger)[cols count] || (_group && column == 0))
        return [_views objectForKey:[NSNull null]];
    return [_views objectForKey:[NSValue valueWithNonretainedObject:[cols objectAtIndex:(NSUInteger)column]]];
}
- (void)drawBackgroundInRect:(NSRect)dirty
{
    if (_background) {
        [_background setFill];
        NSRectFill(dirty);
    }
}
- (void)drawSelectionInRect:(NSRect)dirty
{
    NSTableView *t = [self _table];
    ATableDrawSelection([self bounds], t ? [t _drawingStyle] : NSTableViewStyleInset, _highlight, _emphasized, _prevSelected,
                   _nextSelected);
}
- (void)drawSeparatorInRect:(NSRect)dirty {}
- (void)drawDraggingDestinationFeedbackInRect:(NSRect)dirty {}
- (void)drawRect:(NSRect)dirty
{
    [self drawBackgroundInRect:dirty];
    if (_selected)
        [self drawSelectionInRect:dirty];
    [self drawSeparatorInRect:dirty];
    [[self _table] _drawDecorationsInRowView:self];
}
@end

/* ---- NSTableCellView ------------------------------------------------------------------ */

@implementation NSTableCellView {
    id _objectValue;
    NSTextField *_textField;   /* outlets, not retained: they are subviews */
    NSImageView *_imageView;
    NSBackgroundStyle _backgroundStyle;
    NSTableViewRowSizeStyle _rowSizeStyle;
    NSArray *_dragImages;
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
        _rowSizeStyle = NSTableViewRowSizeStyleDefault;
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [super initWithCoder:coder])) {
        _rowSizeStyle = NSTableViewRowSizeStyleDefault;
        id f = [coder containsValueForKey:@"NSTextField"] ? [coder decodeObjectForKey:@"NSTextField"] : nil;
        id i = [coder containsValueForKey:@"NSImageView"] ? [coder decodeObjectForKey:@"NSImageView"] : nil;
        if ([f isKindOfClass:[NSTextField class]])
            _textField = f;
        if ([i isKindOfClass:[NSImageView class]])
            _imageView = i;
    }
    return self;
}
- (void)dealloc
{
    [_objectValue release];
    [_dragImages release];
    [super dealloc];
}
- (BOOL)isFlipped { return YES; }
- (id)objectValue { return _objectValue; }
- (void)setObjectValue:(id)v
{
    [v retain];
    [_objectValue release];
    _objectValue = v;
}
- (NSTextField *)textField { return _textField; }
- (void)setTextField:(NSTextField *)f { _textField = f; }
- (NSImageView *)imageView { return _imageView; }
- (void)setImageView:(NSImageView *)v { _imageView = v; }
- (NSTableViewRowSizeStyle)rowSizeStyle { return _rowSizeStyle; }
- (void)setRowSizeStyle:(NSTableViewRowSizeStyle)s { _rowSizeStyle = s; }
- (NSArray *)draggingImageComponents { return _dragImages; }
- (void)setDraggingImageComponents:(NSArray *)a
{
    [_dragImages release];
    _dragImages = [a retain];
}
- (NSBackgroundStyle)backgroundStyle { return _backgroundStyle; }
/* Passed on to the controls inside, so their text turns white on a
 * selected row; a control made in code gets a cell to carry it. */
static void pass_background_style(NSView *v, NSBackgroundStyle style)
{
    for (NSView *sub in [v subviews]) {
        if ([sub isKindOfClass:[NSControl class]]) {
            NSControl *c = (NSControl *)sub;
            if (![c cell] && style != NSBackgroundStyleNormal) {
                NSCell *cell = [c isKindOfClass:[NSTextField class]] ? [[NSTextFieldCell alloc] initTextCell:@""]
                                                                    : [[NSCell alloc] initTextCell:@""];
                [c setCell:cell];
                [cell release];
            }
            if ([[c cell] backgroundStyle] != style) {
                [[c cell] setBackgroundStyle:style];
                [c setNeedsDisplay:YES];
            }
        } else if (![sub isKindOfClass:[NSTableCellView class]]) {
            pass_background_style(sub, style);
        }
    }
}
- (void)setBackgroundStyle:(NSBackgroundStyle)s
{
    _backgroundStyle = s;
    pass_background_style(self, s);
}
@end

/* ---- the field a cell-based table edits a cell in ------------------------------------- */

/* A cell-based table edits a text cell with one of these laid over the
 * cell. What the field would tell its delegate goes to the table instead,
 * which gives the new value to its data source and tells its own delegate,
 * as the control whose text was edited. */
@interface NSTableView ()
- (void)_cellEditorPosted:(NSNotificationName)name selector:(SEL)sel movement:(NSInteger)movement;
- (BOOL)_beginDragOfRows:(NSEvent *)e;
@end

/* Where a drop on a table would go (freemac 1.220): a line between rows,
 * with a small ring at its start, or a ring round a row or the table. */
@interface ATableDropIndicator : NSView {
@public
    BOOL ring;
}
@end
@implementation ATableDropIndicator
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds];
    [[NSColor controlAccentColor] set];
    if (ring) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(b, 1, 1) xRadius:4 yRadius:4];
        [p setLineWidth:2];
        [p stroke];
        return;
    }
    NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(b.origin.x + 1, b.origin.y + 1, 4, 4)];
    [dot setLineWidth:1.5];
    [dot stroke];
    NSRectFill(NSMakeRect(b.origin.x + 5, NSMidY(b) - 1, b.size.width - 5, 2));
}
@end

@interface ATableCellEditor : NSTextField {
@public
    NSTableView *_table; /* not retained */
}
@end
@implementation ATableCellEditor
- (void)_post:(NSNotificationName)name selector:(SEL)sel
{
    [_table _cellEditorPosted:name selector:sel movement:[self _textMovement]];
}
/* the field is its own delegate, and asks the table's */
- (BOOL)control:(NSControl *)control textShouldBeginEditing:(id)fieldEditor
{
    id d = [_table delegate];
    return ![d respondsToSelector:_cmd] || [d control:_table textShouldBeginEditing:fieldEditor];
}
- (BOOL)control:(NSControl *)control textShouldEndEditing:(id)fieldEditor
{
    id d = [_table delegate];
    return ![d respondsToSelector:_cmd] || [d control:_table textShouldEndEditing:fieldEditor];
}
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)sel
{
    id d = [_table delegate];
    return [d respondsToSelector:_cmd] && [d control:_table textView:textView doCommandBySelector:sel];
}
/* the column cell's formatter couldn't read what was typed */
- (BOOL)control:(NSControl *)control didFailToFormatString:(NSString *)string errorDescription:(NSString *)error
{
    id d = [_table delegate];
    return [d respondsToSelector:_cmd] && [d control:_table didFailToFormatString:string errorDescription:error];
}
- (void)control:(NSControl *)control didFailToValidatePartialString:(NSString *)string
    errorDescription:(NSString *)error
{
    id d = [_table delegate];
    if ([d respondsToSelector:_cmd])
        [d control:_table didFailToValidatePartialString:string errorDescription:error];
}
- (BOOL)control:(NSControl *)control isValidObject:(id)obj
{
    id d = [_table delegate];
    return ![d respondsToSelector:_cmd] || [d control:_table isValidObject:obj];
}
@end

/* ---- NSTableView ---------------------------------------------------------------------- */

enum {
    TV_COLUMN_ORDERING = 0x80000000u,
    TV_COLUMN_RESIZING = 0x40000000u,
    TV_DRAWS_GRID = 0x20000000u,
    TV_EMPTY_SELECTION = 0x10000000u,
    TV_MULTIPLE_SELECTION = 0x08000000u,
    TV_COLUMN_SELECTION = 0x04000000u,
    TV_COLUMN_AUTOSAVE = 0x01000000u,
    TV_ALTERNATING_ROWS = 0x00800000u,
};

@implementation NSTableView {
    NSMutableArray *_columns;
    id _dataSource, _delegate;        /* not retained */
    NSTableHeaderView *_header;
    NSView *_corner;
    CGFloat _rowHeight;
    NSSize _spacing;
    NSTableViewRowSizeStyle _rowSizeStyle;
    NSTableViewStyle _style;
    BOOL _alternating, _autoRowHeights;
    BOOL _allowsReordering, _allowsResizing, _allowsColumnSelection, _multiple, _empty, _typeSelect;
    BOOL _floatsGroupRows, _staticContents, _verticalDrag, _autosaveColumns;
    NSColor *_background, *_grid;
    NSTableViewGridLineStyle _gridMask;
    NSTableViewColumnAutoresizingStyle _autoresizing;
    NSTableViewSelectionHighlightStyle _highlight;
    NSTableViewDraggingDestinationFeedbackStyle _feedback;
    NSString *_autosaveName;
    SEL _doubleAction;
    NSInteger _clickedRow, _clickedColumn, _editedRow, _editedColumn;
    NSArray *_sortDescriptors;
    NSTableColumn *_highlightedColumn;
    NSMutableDictionary *_indicators;
    NSInteger _draggingMaskLocal, _draggingMaskNonLocal;
    /* dragging rows, and drops on them (freemac 1.220) */
    NSPoint _dragFrom;        /* where the button went down, in the table */
    NSInteger _dragRow;       /* the row it went down on */
    BOOL _dragMaybe;          /* a move from there may begin a drag */
    BOOL _clickDeferred;      /* the click on a selected row selects it alone on mouseUp */
    NSIndexSet *_dragRows;    /* the rows being dragged */
    NSInteger _dropRow;
    NSTableViewDropOperation _dropOp;
    BOOL _dropValid;
    NSView *_dropIndicator;
    /* rows */
    NSInteger _rows;
    BOOL _rowsKnown;
    CGFloat *_offsets;       /* with heights from the delegate: where each row starts, and the end */
    NSInteger _offsetCount;
    /* selection */
    NSMutableIndexSet *_selection, *_columnSelection;
    NSInteger _anchor, _lead, _lastSelected;
    BOOL _clickChangedSelection;
    /* views */
    NSMutableDictionary *_rowViews;   /* row number -> NSTableRowView */
    NSMutableDictionary *_nibs;       /* identifier -> NSNib */
    BOOL _nibPrototypes;              /* the nib gave cell view prototypes (Ferry 0.20.0) */
    NSMutableDictionary *_reusable;   /* identifier -> views out of sight */
    NSInteger _updateDepth;
    BOOL _tiling, _updatingViews, _sizing;
    CGFloat _fittedWidth;
    NSView *_observedClip;
    /* editing a cell in place */
    NSTextField *_editor;    /* the field being edited: a cell view's, or ATableCellEditor */
    id _editOriginal;        /* its value when editing began */
    BOOL _endingEdit, _editedOnClick;
    BOOL _bindingUpdate;     /* set from a binding: not written back to it */
}

- (void)_setUp
{
    _columns = [[NSMutableArray alloc] init];
    _rowHeight = 17;
    _spacing = NSMakeSize(3, 2);
    _rowSizeStyle = NSTableViewRowSizeStyleCustom;
    _allowsResizing = _allowsReordering = _empty = _typeSelect = YES;
    _autoresizing = NSTableViewLastColumnOnlyAutoresizingStyle;
    _clickedRow = _clickedColumn = _editedRow = _editedColumn = -1;
    _anchor = _lead = _lastSelected = -1;
    _selection = [[NSMutableIndexSet alloc] init];
    _columnSelection = [[NSMutableIndexSet alloc] init];
    _rowViews = [[NSMutableDictionary alloc] init];
    _nibs = [[NSMutableDictionary alloc] init];
    _reusable = [[NSMutableDictionary alloc] init];
    _sortDescriptors = [[NSArray alloc] init];
    _indicators = [[NSMutableDictionary alloc] init];
    _fittedWidth = -1;
    _draggingMaskLocal = (NSInteger)NSDragOperationEvery;
    _draggingMaskNonLocal = NSDragOperationNone;
    _verticalDrag = YES;
    _dropRow = -1;
    [self setAutoresizesSubviews:NO];
}
- (instancetype)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self _setUp];
        _header = [[NSTableHeaderView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, header_height)];
        [_header setTableView:self];
        _corner = [[_NSCornerView alloc] initWithFrame:NSMakeRect(0, 0, 15, header_height)];
    }
    return self;
}
- (instancetype)init { return [self initWithFrame:NSZeroRect]; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    [self _setUp];
    for (id c in decoded(coder, @"NSTableColumns", [NSArray class]))
        if ([c isKindOfClass:[NSTableColumn class]]) {
            [_columns addObject:c];
            [(NSTableColumn *)c setTableView:self];
        }
    _header = [decoded(coder, @"NSHeaderView", [NSTableHeaderView class]) retain];
    [_header setTableView:self];
    _corner = [decoded(coder, @"NSCornerView", [NSView class]) retain];
    if ([coder containsValueForKey:@"NSRowHeight"])
        _rowHeight = fmax([coder decodeDoubleForKey:@"NSRowHeight"], 1);
    if ([coder containsValueForKey:@"NSIntercellSpacingWidth"])
        _spacing.width = [coder decodeDoubleForKey:@"NSIntercellSpacingWidth"];
    if ([coder containsValueForKey:@"NSIntercellSpacingHeight"])
        _spacing.height = [coder decodeDoubleForKey:@"NSIntercellSpacingHeight"];
    if ([coder containsValueForKey:@"NSTvFlags"]) {
        unsigned f = (unsigned)[coder decodeInt64ForKey:@"NSTvFlags"];
        _allowsReordering = (f & TV_COLUMN_ORDERING) != 0;
        _allowsResizing = (f & TV_COLUMN_RESIZING) != 0;
        if (f & TV_DRAWS_GRID)
            _gridMask = NSTableViewSolidVerticalGridLineMask | NSTableViewSolidHorizontalGridLineMask;
        _empty = (f & TV_EMPTY_SELECTION) != 0;
        _multiple = (f & TV_MULTIPLE_SELECTION) != 0;
        _allowsColumnSelection = (f & TV_COLUMN_SELECTION) != 0;
        _autosaveColumns = (f & TV_COLUMN_AUTOSAVE) != 0;
        _alternating = (f & TV_ALTERNATING_ROWS) != 0;
    }
    if ([coder containsValueForKey:@"NSColumnAutoresizingStyle"])
        _autoresizing = (NSTableViewColumnAutoresizingStyle)[coder decodeIntegerForKey:@"NSColumnAutoresizingStyle"];
    _grid = [decoded(coder, @"NSGridColor", [NSColor class]) copy];
    _background = [decoded(coder, @"NSBackgroundColor", [NSColor class]) copy];
    if ([coder containsValueForKey:@"NSTableViewSelectionHighlightStyle"])
        [self setSelectionHighlightStyle:(NSTableViewSelectionHighlightStyle)[coder
                                             decodeIntegerForKey:@"NSTableViewSelectionHighlightStyle"]];
    if ([coder containsValueForKey:@"NSDraggingSourceMaskForLocal"])
        _draggingMaskLocal = [coder decodeIntegerForKey:@"NSDraggingSourceMaskForLocal"];
    if ([coder containsValueForKey:@"NSDraggingSourceMaskForNonLocal"])
        _draggingMaskNonLocal = [coder decodeIntegerForKey:@"NSDraggingSourceMaskForNonLocal"];
    if ([coder containsValueForKey:@"NSAllowsTypeSelect"])
        _typeSelect = [coder decodeBoolForKey:@"NSAllowsTypeSelect"];
    NSDictionary *prototypes = decoded(coder, @"NSTableViewArchivedReusableViewsKey", [NSDictionary class]);
    for (id key in prototypes) {
        id nib = [prototypes objectForKey:key];
        if ([key isKindOfClass:[NSString class]] && [nib isKindOfClass:[NSNib class]]) {
            [_nibs setObject:nib forKey:key];
            _nibPrototypes = YES;
        }
    }
    [self tile];
    return self;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (NSTableColumn *c in _columns)
        if ([c tableView] == self)
            [c setTableView:nil];
    [_header setTableView:nil];
    [_columns release];
    [_header release];
    [_corner release];
    [_background release];
    [_grid release];
    [_autosaveName release];
    [_sortDescriptors release];
    [_highlightedColumn release];
    [_indicators release];
    [_selection release];
    [_columnSelection release];
    [_rowViews release];
    [_nibs release];
    [_reusable release];
    [_editor release];
    [_editOriginal release];
    free(_offsets);
    [_dragRows release];
    [_dropIndicator release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return ![self refusesFirstResponder]; }
- (BOOL)becomeFirstResponder
{
    [self setNeedsDisplay:YES];
    [self _selectionChanged];
    return YES;
}
- (BOOL)resignFirstResponder
{
    [self setNeedsDisplay:YES];
    [self performSelector:@selector(_selectionChanged) withObject:nil afterDelay:0];
    return YES;
}

/* ---- the data source and delegate (NSOutlineView changes these) ---- */

- (id)dataSource { return _dataSource; }
- (void)setDataSource:(id)d
{
    _dataSource = d;
    if (d)
        [self reloadData];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_delegate) {
        [nc removeObserver:_delegate name:[self _selectionDidChangeName] object:self];
        [nc removeObserver:_delegate name:[self _columnDidResizeName] object:self];
    }
    _delegate = d;
    if (d) {
        if ([d respondsToSelector:[self _selectionDidChangeSelector]])
            [nc addObserver:d selector:[self _selectionDidChangeSelector] name:[self _selectionDidChangeName] object:self];
        if ([d respondsToSelector:[self _columnDidResizeSelector]])
            [nc addObserver:d selector:[self _columnDidResizeSelector] name:[self _columnDidResizeName] object:self];
    }
    if (_rowsKnown)
        [self reloadData];
}
/* With bindings (Ferry 0.18.0) the rows are the bound content (or a bound
 * column's rows), and a bound column's cells its key of each; otherwise
 * the data source answers. */
- (NSArray *)_boundRows
{
    BOOL bound;
    id rows = ABindingModelValue(self, NSContentBinding, &bound);
    if (!bound)
        for (NSTableColumn *c in _columns)
            if (ABindingIsBound(c, NSValueBinding)) {
                NSDictionary *info = [c infoForBinding:NSValueBinding];
                NSString *path = [info objectForKey:NSObservedKeyPathKey];
                NSRange dot = [path rangeOfString:@"."];
                if (dot.location != NSNotFound)
                    path = [path substringToIndex:dot.location];
                @try {
                    rows = [[info objectForKey:NSObservedObjectKey] valueForKeyPath:path];
                } @catch (NSException *e) {
                    rows = nil;
                }
                bound = YES;
                break;
            }
    if (!bound)
        return nil;
    if ([rows isKindOfClass:[NSSet class]])
        rows = [rows allObjects];
    return [rows isKindOfClass:[NSArray class]] ? rows : [NSArray array];
}
- (NSInteger)_countRows
{
    NSArray *rows = [self _boundRows];
    if (rows)
        return (NSInteger)[rows count];
    return [_dataSource respondsToSelector:@selector(numberOfRowsInTableView:)] ? [_dataSource numberOfRowsInTableView:self] : 0;
}
- (id)_objectValueForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    BOOL bound;
    id v = ABindingCellValue(c, row, &bound);
    if (bound)
        return v;
    if (ABindingIsBound(self, NSContentBinding)) {
        NSArray *rows = [self _boundRows];
        return row >= 0 && (NSUInteger)row < [rows count] ? [rows objectAtIndex:(NSUInteger)row] : nil;
    }
    if ([_dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)])
        return [_dataSource tableView:self objectValueForTableColumn:c row:row];
    return nil;
}
- (void)_setObjectValue:(id)v forColumn:(NSTableColumn *)c row:(NSInteger)row
{
    if (ABindingIsBound(c, NSValueBinding)) {
        ABindingSetCellValue(c, row, v);
        return;
    }
    if ([_dataSource respondsToSelector:@selector(tableView:setObjectValue:forTableColumn:row:)])
        [_dataSource tableView:self setObjectValue:v forTableColumn:c row:row];
}
/* The bound rows changed: loaded again, the selection taken from its
 * binding, nothing written back. */
- (void)_ferryBoundRowsChanged
{
    BOOL was = _bindingUpdate;
    _bindingUpdate = YES;
    @try {
        if (_editor && _endingEdit)
            [self _reloadRowsQuietly];
        else
            [self reloadData];
        ABindingRefresh(self, NSSelectionIndexesBinding);
        ABindingRefresh(self, NSSelectionIndexPathsBinding);
    } @finally {
        _bindingUpdate = was;
    }
}
- (BOOL)_ferryIsBindingUpdate { return _bindingUpdate; }
- (void)_ferryAsBindingUpdate:(void (^)(void))step
{
    BOOL was = _bindingUpdate;
    _bindingUpdate = YES;
    @try {
        step();
    } @finally {
        _bindingUpdate = was;
    }
}
- (void)_ferrySetValue:(id)value forBinding:(NSString *)binding
{
    BOOL was = _bindingUpdate;
    _bindingUpdate = YES;
    @try {
        if ([binding isEqualToString:NSContentBinding]) {
            [self _ferryBoundRowsChanged];
        } else if ([binding isEqualToString:NSSelectionIndexesBinding]) {
            NSIndexSet *rows = [value isKindOfClass:[NSIndexSet class]] ? value : [NSIndexSet indexSet];
            if (![rows isEqualToIndexSet:_selection])
                [self selectRowIndexes:rows byExtendingSelection:NO];
        } else if ([binding isEqualToString:NSSortDescriptorsBinding]) {
            [self setSortDescriptors:[value isKindOfClass:[NSArray class]] ? value : @[]];
        } else {
            [super _ferrySetValue:value forBinding:binding];
        }
    } @finally {
        _bindingUpdate = was;
    }
}
- (id)_ferryValueForBinding:(NSString *)binding
{
    if ([binding isEqualToString:NSSelectionIndexesBinding])
        return [self selectedRowIndexes];
    if ([binding isEqualToString:NSSortDescriptorsBinding])
        return [self sortDescriptors];
    if ([binding isEqualToString:NSContentBinding])
        return [self _boundRows];
    return [super _ferryValueForBinding:binding];
}
- (BOOL)_dataSourceTakesValues
{
    return [_dataSource respondsToSelector:@selector(tableView:setObjectValue:forTableColumn:row:)];
}
- (BOOL)_shouldEditColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return ![_delegate respondsToSelector:@selector(tableView:shouldEditTableColumn:row:)] ||
           [_delegate tableView:self shouldEditTableColumn:c row:row];
}
/* With bindings, a table whose nib holds cell view prototypes is
 * view-based without the delegate's tableView:viewForTableColumn:row:, as
 * Apple documents for tables with bindings. */
- (BOOL)_makesViewsFromNib { return _nibPrototypes && ABindingIsBound(self, NSContentBinding); }
- (NSView *)_viewFromNibForColumn:(NSTableColumn *)c
{
    return c && [c identifier] ? [self makeViewWithIdentifier:[c identifier] owner:_delegate] : nil;
}
- (BOOL)_delegateMakesViews
{
    return [_delegate respondsToSelector:@selector(tableView:viewForTableColumn:row:)] || [self _makesViewsFromNib];
}
- (NSView *)_delegateViewForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    if ([_delegate respondsToSelector:@selector(tableView:viewForTableColumn:row:)])
        return [_delegate tableView:self viewForTableColumn:c row:row];
    return [self _makesViewsFromNib] ? [self _viewFromNibForColumn:c] : nil;
}
- (NSTableRowView *)_delegateRowViewForRow:(NSInteger)row
{
    return [_delegate respondsToSelector:@selector(tableView:rowViewForRow:)] ? [_delegate tableView:self rowViewForRow:row]
                                                                              : nil;
}
- (void)_didAddRowView:(NSTableRowView *)v row:(NSInteger)row
{
    if ([_delegate respondsToSelector:@selector(tableView:didAddRowView:forRow:)])
        [_delegate tableView:self didAddRowView:v forRow:row];
}
- (void)_didRemoveRowView:(NSTableRowView *)v row:(NSInteger)row
{
    if ([_delegate respondsToSelector:@selector(tableView:didRemoveRowView:forRow:)])
        [_delegate tableView:self didRemoveRowView:v forRow:row];
}
- (NSCell *)_delegateCellForColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [_delegate respondsToSelector:@selector(tableView:dataCellForTableColumn:row:)]
               ? [_delegate tableView:self dataCellForTableColumn:c row:row]
               : nil;
}
- (void)_willDisplayCell:(NSCell *)cell column:(NSTableColumn *)c row:(NSInteger)row
{
    if ([_delegate respondsToSelector:@selector(tableView:willDisplayCell:forTableColumn:row:)])
        [_delegate tableView:self willDisplayCell:cell forTableColumn:c row:row];
}
- (BOOL)_delegateHasRowHeights { return [_delegate respondsToSelector:@selector(tableView:heightOfRow:)]; }
- (CGFloat)_delegateHeightOfRow:(NSInteger)row { return [_delegate tableView:self heightOfRow:row]; }
- (BOOL)_isGroupRow:(NSInteger)row
{
    return [_delegate respondsToSelector:@selector(tableView:isGroupRow:)] && [_delegate tableView:self isGroupRow:row];
}
- (BOOL)_selectionShouldChange
{
    return ![_delegate respondsToSelector:@selector(selectionShouldChangeInTableView:)] ||
           [_delegate selectionShouldChangeInTableView:self];
}
- (BOOL)_shouldSelectRow:(NSInteger)row
{
    return ![_delegate respondsToSelector:@selector(tableView:shouldSelectRow:)] || [_delegate tableView:self shouldSelectRow:row];
}
- (NSNotificationName)_selectionDidChangeName { return NSTableViewSelectionDidChangeNotification; }
- (SEL)_selectionDidChangeSelector { return @selector(tableViewSelectionDidChange:); }
- (NSNotificationName)_columnDidResizeName { return NSTableViewColumnDidResizeNotification; }
- (SEL)_columnDidResizeSelector { return @selector(tableViewColumnDidResize:); }
- (void)_sortDescriptorsDidChange:(NSArray *)old
{
    if (!_bindingUpdate)
        ABindingPush(self, NSSortDescriptorsBinding);
    if ([_dataSource respondsToSelector:@selector(tableView:sortDescriptorsDidChange:)])
        [_dataSource tableView:self sortDescriptorsDidChange:old];
}
- (void)_mouseDownInHeaderOfColumn:(NSTableColumn *)c
{
    if ([_delegate respondsToSelector:@selector(tableView:mouseDownInHeaderOfTableColumn:)])
        [_delegate tableView:self mouseDownInHeaderOfTableColumn:c];
}
- (void)_didClickColumn:(NSTableColumn *)c
{
    if ([_delegate respondsToSelector:@selector(tableView:didClickTableColumn:)])
        [_delegate tableView:self didClickTableColumn:c];
}
- (CGFloat)_indentationForRow:(NSInteger)row column:(NSInteger)column { return 0; }
- (BOOL)_handleMouseDown:(NSEvent *)e row:(NSInteger)row column:(NSInteger)column point:(NSPoint)p { return NO; }
- (void)_drawDecorationsForRow:(NSInteger)row {}
- (void)_drawDecorationsInRowView:(NSTableRowView *)view {}

/* The delegate hears of the notifications it observes; this posts them. */
- (void)_post:(NSNotificationName)name selector:(SEL)sel userInfo:(NSDictionary *)info
{
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:info];
}

/* ---- columns ---- */

- (NSArray *)tableColumns { return [[_columns copy] autorelease]; }
- (NSInteger)numberOfColumns { return (NSInteger)[_columns count]; }
- (void)addTableColumn:(NSTableColumn *)c
{
    if (!c || [_columns containsObject:c])
        return;
    [_columns addObject:c];
    [c setTableView:self];
    _fittedWidth = -1;
    [self _dropAllRowViews];
    [self tile];
    ABindingColumnJoinedTable(c);
}
- (void)removeTableColumn:(NSTableColumn *)c
{
    NSUInteger i = [_columns indexOfObjectIdenticalTo:c];
    if (i == NSNotFound)
        return;
    [self _dropAllRowViews];
    [c retain];
    if ([c tableView] == self)
        [c setTableView:nil];
    [_columns removeObjectAtIndex:i];
    [_columnSelection removeIndex:i];
    [_columnSelection shiftIndexesStartingAtIndex:i + 1 by:-1];
    if (_highlightedColumn == c) {
        [_highlightedColumn release];
        _highlightedColumn = nil;
    }
    [c release];
    _fittedWidth = -1;
    [self tile];
}
- (void)moveColumn:(NSInteger)from toColumn:(NSInteger)to
{
    NSInteger n = (NSInteger)[_columns count];
    if (from < 0 || from >= n || to < 0 || to >= n || from == to)
        return;
    id c = [[_columns objectAtIndex:(NSUInteger)from] retain];
    [_columns removeObjectAtIndex:(NSUInteger)from];
    [_columns insertObject:c atIndex:(NSUInteger)to];
    [c release];
    [self tile];
    [self _post:NSTableViewColumnDidMoveNotification selector:@selector(tableViewColumnDidMove:)
       userInfo:@{@"NSOldColumn" : @(from), @"NSNewColumn" : @(to)}];
}
- (NSInteger)columnWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    for (NSUInteger i = 0; i < [_columns count]; i++) {
        id mine = [[_columns objectAtIndex:i] identifier];
        if (mine == identifier || [mine isEqual:identifier])
            return (NSInteger)i;
    }
    return -1;
}
- (NSTableColumn *)tableColumnWithIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    NSInteger i = [self columnWithIdentifier:identifier];
    return i < 0 ? nil : [_columns objectAtIndex:(NSUInteger)i];
}

/* the width all the shown columns take, with their spacing */
- (CGFloat)_columnsWidth
{
    CGFloat w = 0;
    for (NSTableColumn *c in _columns)
        if (![c isHidden])
            w += [c width] + _spacing.width;
    return w;
}
/* The width to fill: the clip view's, if the table is in one. */
- (CGFloat)_availableWidth
{
    NSView *sv = [self superview];
    return [sv isKindOfClass:[NSClipView class]] ? [sv bounds].size.width : [self frame].size.width;
}

/* Spreads delta over columns, in order (or evenly), as far as their limits
 * allow. Returns what is left over. */
- (CGFloat)_spread:(CGFloat)delta over:(NSArray *)cols evenly:(BOOL)evenly
{
    _sizing = YES;
    for (int pass = 0; pass < 8 && fabs(delta) > 0.01; pass++) {
        NSMutableArray *open = [NSMutableArray array];
        for (NSTableColumn *c in cols)
            if (![c isHidden] && ([c resizingMask] & NSTableColumnAutoresizingMask) &&
                (delta > 0 ? [c width] < [c maxWidth] : [c width] > [c minWidth]))
                [open addObject:c];
        if (![open count])
            break;
        if (!evenly) {
            for (NSTableColumn *c in open) {
                CGFloat before = [c width];
                [c setWidth:before + delta];
                delta -= [c width] - before;
                if (fabs(delta) <= 0.01)
                    break;
            }
            break;
        }
        CGFloat share = delta / (CGFloat)[open count];
        for (NSTableColumn *c in open) {
            CGFloat before = [c width];
            [c setWidth:before + share];
            delta -= [c width] - before;
        }
    }
    _sizing = NO;
    return delta;
}
/* The columns that take up a change of size, in the order they take it. */
- (NSArray *)_columnsToResizeAfter:(NSInteger)index
{
    NSMutableArray *shown = [NSMutableArray array];
    for (NSUInteger i = (NSUInteger)(index + 1); i < [_columns count]; i++)
        if (![[_columns objectAtIndex:i] isHidden])
            [shown addObject:[_columns objectAtIndex:i]];
    NSMutableArray *all = [NSMutableArray array];
    for (NSTableColumn *c in _columns)
        if (![c isHidden])
            [all addObject:c];
    switch (_autoresizing) {
    case NSTableViewNoColumnAutoresizing:
        return @[];
    case NSTableViewLastColumnOnlyAutoresizingStyle:
        return [all lastObject] && (index < 0 || [all indexOfObject:[all lastObject]] > [all indexOfObject:[_columns objectAtIndex:(NSUInteger)index]])
                   ? @[ [all lastObject] ]
                   : @[];
    case NSTableViewFirstColumnOnlyAutoresizingStyle:
        if (index < 0)
            return [all count] ? @[ [all firstObject] ] : @[];
        return [shown count] ? @[ [shown firstObject] ] : @[];
    case NSTableViewSequentialColumnAutoresizingStyle:
        return [[(index < 0 ? all : shown) reverseObjectEnumerator] allObjects];
    default: /* uniform and reverse sequential */
        return index < 0 ? all : shown;
    }
}
- (void)_fitColumnsToWidth
{
    if (_sizing || _autoresizing == NSTableViewNoColumnAutoresizing || ![_columns count])
        return;
    CGFloat avail = [self _availableWidth];
    if (avail <= 0)
        return;
    CGFloat delta = avail - [self _columnsWidth];
    if (fabs(delta) > 0.01)
        [self _spread:delta over:[self _columnsToResizeAfter:-1]
                evenly:_autoresizing == NSTableViewUniformColumnAutoresizingStyle];
    _fittedWidth = avail;
}
- (void)_userResizedColumn:(NSTableColumn *)c by:(CGFloat)delta
{
    NSUInteger i = [_columns indexOfObjectIdenticalTo:c];
    if (i == NSNotFound)
        return;
    CGFloat before = [c width];
    _sizing = YES;
    [c setWidth:before + delta];
    _sizing = NO;
    delta = [c width] - before;
    if (delta != 0 && _autoresizing != NSTableViewNoColumnAutoresizing) {
        CGFloat left = [self _spread:-delta over:[self _columnsToResizeAfter:(NSInteger)i]
                              evenly:_autoresizing == NSTableViewUniformColumnAutoresizingStyle];
        if (fabs(left) > 0.01) { /* the others couldn't give way: take back what they couldn't */
            _sizing = YES;
            [c setWidth:[c width] + left];
            _sizing = NO;
        }
    }
    [self tile];
}
- (void)_columnWidthChanged:(NSTableColumn *)c from:(CGFloat)old
{
    if (!_sizing)
        [self tile];
    else
        [self setNeedsDisplay:YES];
    [_header setNeedsDisplay:YES];
    [self _post:[self _columnDidResizeName] selector:[self _columnDidResizeSelector]
       userInfo:@{@"NSTableColumn" : c, @"NSOldWidth" : @(old)}];
}
- (void)sizeLastColumnToFit
{
    NSTableColumn *last = nil;
    for (NSTableColumn *c in _columns)
        if (![c isHidden])
            last = c;
    if (!last)
        return;
    CGFloat others = [self _columnsWidth] - [last width] - _spacing.width;
    _sizing = YES;
    [last setWidth:[self _availableWidth] - others - _spacing.width];
    _sizing = NO;
    [self tile];
}
- (void)sizeToFit
{
    CGFloat delta = [self _availableWidth] - [self _columnsWidth];
    NSMutableArray *all = [NSMutableArray array];
    for (NSTableColumn *c in _columns)
        if (![c isHidden])
            [all addObject:c];
    [self _spread:delta over:all evenly:YES];
    [self tile];
}
- (void)_clipViewResized:(NSClipView *)clip
{
    if (_tiling)
        return;
    if ([clip bounds].size.width != _fittedWidth)
        [self _fitColumnsToWidth];
    [self tile];
}
- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    if (_observedClip)
        [nc removeObserver:self name:NSViewBoundsDidChangeNotification object:_observedClip];
    _observedClip = nil;
    NSView *sv = [self superview];
    if ([sv isKindOfClass:[NSClipView class]]) {
        _observedClip = sv;
        [sv setPostsBoundsChangedNotifications:YES];
        [nc addObserver:self selector:@selector(_clipScrolled:) name:NSViewBoundsDidChangeNotification object:sv];
    }
    [self tile];
}
- (void)_clipScrolled:(NSNotification *)n { [self _updateVisibleViews]; }

/* ---- row geometry ---- */

- (CGFloat)rowHeight { return _rowHeight; }
- (void)setRowHeight:(CGFloat)h
{
    _rowHeight = fmax(h, 1);
    [self noteNumberOfRowsChanged];
}
- (NSSize)intercellSpacing { return _spacing; }
- (void)setIntercellSpacing:(NSSize)s
{
    _spacing = s;
    [self noteNumberOfRowsChanged];
}
- (NSTableViewRowSizeStyle)rowSizeStyle { return _rowSizeStyle; }
- (void)setRowSizeStyle:(NSTableViewRowSizeStyle)s
{
    _rowSizeStyle = s;
    switch ([self effectiveRowSizeStyle]) {
    case NSTableViewRowSizeStyleSmall: [self setRowHeight:17]; break;
    case NSTableViewRowSizeStyleMedium: [self setRowHeight:22]; break;
    case NSTableViewRowSizeStyleLarge: [self setRowHeight:28]; break;
    default: break;
    }
}
- (NSTableViewRowSizeStyle)effectiveRowSizeStyle
{
    return _rowSizeStyle == NSTableViewRowSizeStyleDefault ? NSTableViewRowSizeStyleMedium : _rowSizeStyle;
}
- (NSTableViewStyle)style { return _style; }
- (void)setStyle:(NSTableViewStyle)s
{
    _style = s;
    [self setNeedsDisplay:YES];
}
- (NSTableViewStyle)effectiveStyle
{
    if (_style != NSTableViewStyleAutomatic)
        return _style;
    return _highlight == NSTableViewSelectionHighlightStyleSourceList ? NSTableViewStyleSourceList : NSTableViewStyleInset;
}
- (NSTableViewStyle)_drawingStyle { return [self effectiveStyle]; }

/* Rows end to end from the top; with heights from the delegate, where
 * each starts is worked out once and kept. */
- (void)_computeRows
{
    _rows = MAX([self _countRows], 0);
    _rowsKnown = YES;
    free(_offsets);
    _offsets = NULL;
    _offsetCount = 0;
    if ([self _delegateHasRowHeights]) {
        _offsets = malloc(sizeof(CGFloat) * (size_t)(_rows + 1));
        CGFloat y = 0;
        for (NSInteger r = 0; r < _rows; r++) {
            _offsets[r] = y;
            CGFloat h = [self _delegateHeightOfRow:r];
            y += (h > 0 ? h : _rowHeight) + _spacing.height;
        }
        _offsets[_rows] = y;
        _offsetCount = _rows + 1;
    }
}
- (NSInteger)numberOfRows
{
    if (!_rowsKnown)
        [self _computeRows];
    return _rows;
}
- (CGFloat)_rowTop:(NSInteger)row
{
    if (_offsets)
        return _offsets[MAX(0, MIN(row, _offsetCount - 1))];
    return row * (_rowHeight + _spacing.height);
}
- (CGFloat)_rowsHeight
{
    [self numberOfRows];
    return [self _rowTop:_rows];
}
- (NSRect)rectOfRow:(NSInteger)row
{
    if (row < 0 || row >= [self numberOfRows])
        return NSZeroRect;
    CGFloat y = [self _rowTop:row];
    return NSMakeRect(0, y, [self bounds].size.width, [self _rowTop:row + 1] - y);
}
- (NSRect)rectOfColumn:(NSInteger)column
{
    if (column < 0 || column >= (NSInteger)[_columns count])
        return NSZeroRect;
    CGFloat x = 0;
    for (NSInteger i = 0; i < column; i++) {
        NSTableColumn *c = [_columns objectAtIndex:(NSUInteger)i];
        if (![c isHidden])
            x += [c width] + _spacing.width;
    }
    NSTableColumn *c = [_columns objectAtIndex:(NSUInteger)column];
    if ([c isHidden])
        return NSMakeRect(x, 0, 0, [self bounds].size.height);
    return NSMakeRect(x, 0, [c width] + _spacing.width, [self bounds].size.height);
}
- (NSRange)rowsInRect:(NSRect)r
{
    NSInteger n = [self numberOfRows];
    if (n == 0 || NSIsEmptyRect(r))
        return NSMakeRange(0, 0);
    NSInteger first = [self rowAtPoint:NSMakePoint(0, fmax(NSMinY(r), 0))];
    if (first < 0)
        return NSMakeRange(0, 0);
    NSInteger last = [self rowAtPoint:NSMakePoint(0, fmin(NSMaxY(r), [self _rowsHeight]) - 0.001)];
    if (last < 0)
        last = n - 1;
    return NSMakeRange((NSUInteger)first, (NSUInteger)(last - first + 1));
}
- (NSIndexSet *)columnIndexesInRect:(NSRect)r
{
    NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < [_columns count]; i++) {
        NSRect c = [self rectOfColumn:(NSInteger)i];
        if (c.size.width > 0 && NSMaxX(c) > NSMinX(r) && NSMinX(c) < NSMaxX(r))
            [set addIndex:i];
    }
    return set;
}
- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSRect rr = [self rectOfRow:row], cr = [self rectOfColumn:column];
    if (NSIsEmptyRect(rr) || cr.size.width <= 0)
        return NSZeroRect;
    CGFloat indent = [self _indentationForRow:row column:column];
    NSRect f = NSMakeRect(cr.origin.x + floor(_spacing.width / 2) + indent, rr.origin.y + floor(_spacing.height / 2),
                          cr.size.width - _spacing.width - indent, rr.size.height - _spacing.height);
    f.size.width = fmax(f.size.width, 0);
    return f;
}
- (NSInteger)rowAtPoint:(NSPoint)p
{
    NSInteger n = [self numberOfRows];
    if (p.y < 0 || n == 0 || p.y >= [self _rowsHeight])
        return -1;
    if (!_offsets) {
        NSInteger r = (NSInteger)floor(p.y / (_rowHeight + _spacing.height));
        return r < n ? r : -1;
    }
    NSInteger lo = 0, hi = n - 1;
    while (lo < hi) {
        NSInteger mid = (lo + hi + 1) / 2;
        if (_offsets[mid] <= p.y)
            lo = mid;
        else
            hi = mid - 1;
    }
    return lo;
}
- (NSInteger)columnAtPoint:(NSPoint)p
{
    if (p.x < 0)
        return -1;
    for (NSUInteger i = 0; i < [_columns count]; i++) {
        NSRect c = [self rectOfColumn:(NSInteger)i];
        if (c.size.width > 0 && p.x >= NSMinX(c) && p.x < NSMaxX(c))
            return (NSInteger)i;
    }
    return -1;
}

/* Sizes the table to its rows and columns (at least the clip view's size)
 * and its header to match. */
- (void)tile
{
    if (_tiling)
        return;
    _tiling = YES;
    [self numberOfRows];
    NSView *sv = [self superview];
    NSSize clip = [sv isKindOfClass:[NSClipView class]] ? [sv bounds].size : NSZeroSize;
    NSSize size = NSMakeSize(fmax([self _columnsWidth], clip.width), fmax([self _rowsHeight], clip.height));
    if ([sv isKindOfClass:[NSClipView class]] || NSIsEmptyRect([self frame]) || !NSEqualSizes(size, [self frame].size)) {
        if (![sv isKindOfClass:[NSClipView class]])
            size = NSMakeSize(fmax(size.width, [self frame].size.width), fmax(size.height, [self frame].size.height));
        if (!NSEqualSizes(size, [self frame].size))
            [self setFrameSize:size];
    }
    if (_header) {
        NSSize hs = NSMakeSize(size.width, [_header frame].size.height > 0 ? [_header frame].size.height : header_height);
        if (!NSEqualSizes(hs, [_header frame].size))
            [_header setFrameSize:hs];
        [_header setNeedsDisplay:YES];
    }
    _tiling = NO;
    [self _layOutRowViews];
    [self _updateVisibleViews];
    [self setNeedsDisplay:YES];
}
- (NSTableHeaderView *)headerView { return _header; }
- (void)setHeaderView:(NSTableHeaderView *)h
{
    if (h == _header)
        return;
    [_header setTableView:nil];
    if ([[_header superview] isKindOfClass:[NSClipView class]])
        [[_header superview] setHidden:YES];
    [h retain];
    [_header release];
    _header = h;
    [_header setTableView:self];
    [self tile];
    [[self enclosingScrollView] tile];
}
- (NSView *)cornerView { return _corner; }
- (void)setCornerView:(NSView *)v
{
    if (v == _corner)
        return;
    if ([_corner superview])
        [_corner removeFromSuperview];
    [v retain];
    [_corner release];
    _corner = v;
    [[self enclosingScrollView] tile];
}

/* ---- settings ---- */

- (BOOL)usesAlternatingRowBackgroundColors { return _alternating; }
- (void)setUsesAlternatingRowBackgroundColors:(BOOL)f
{
    _alternating = f;
    [self setNeedsDisplay:YES];
}
- (BOOL)usesAutomaticRowHeights { return _autoRowHeights; }
- (void)setUsesAutomaticRowHeights:(BOOL)f { _autoRowHeights = f; }
- (NSColor *)backgroundColor { return _background ?: [NSColor controlBackgroundColor]; }
- (void)setBackgroundColor:(NSColor *)c
{
    [_background release];
    _background = [c copy];
    [self setNeedsDisplay:YES];
}
- (NSColor *)gridColor { return _grid ?: [NSColor gridColor]; }
- (void)setGridColor:(NSColor *)c
{
    [_grid release];
    _grid = [c copy];
    [self setNeedsDisplay:YES];
}
- (NSTableViewGridLineStyle)gridStyleMask { return _gridMask; }
- (void)setGridStyleMask:(NSTableViewGridLineStyle)m
{
    _gridMask = m;
    [self setNeedsDisplay:YES];
}
- (NSTableViewColumnAutoresizingStyle)columnAutoresizingStyle { return _autoresizing; }
- (void)setColumnAutoresizingStyle:(NSTableViewColumnAutoresizingStyle)s { _autoresizing = s; }
- (NSTableViewSelectionHighlightStyle)selectionHighlightStyle { return _highlight; }
- (void)setSelectionHighlightStyle:(NSTableViewSelectionHighlightStyle)s
{
    _highlight = s;
    for (NSTableRowView *v in [_rowViews allValues])
        [v setSelectionHighlightStyle:s];
    if (s == NSTableViewSelectionHighlightStyleSourceList && !_background)
        _background = [[NSColor clearColor] copy];
    [self setNeedsDisplay:YES];
}
- (NSTableViewDraggingDestinationFeedbackStyle)draggingDestinationFeedbackStyle { return _feedback; }
- (void)setDraggingDestinationFeedbackStyle:(NSTableViewDraggingDestinationFeedbackStyle)s { _feedback = s; }
- (BOOL)allowsColumnReordering { return _allowsReordering; }
- (void)setAllowsColumnReordering:(BOOL)f { _allowsReordering = f; }
- (BOOL)allowsColumnResizing { return _allowsResizing; }
- (void)setAllowsColumnResizing:(BOOL)f { _allowsResizing = f; }
- (BOOL)allowsColumnSelection { return _allowsColumnSelection; }
- (void)setAllowsColumnSelection:(BOOL)f { _allowsColumnSelection = f; }
- (BOOL)allowsMultipleSelection { return _multiple; }
- (void)setAllowsMultipleSelection:(BOOL)f { _multiple = f; }
- (BOOL)allowsEmptySelection { return _empty; }
- (void)setAllowsEmptySelection:(BOOL)f { _empty = f; }
- (BOOL)allowsTypeSelect { return _typeSelect; }
- (void)setAllowsTypeSelect:(BOOL)f { _typeSelect = f; }
- (BOOL)floatsGroupRows { return _floatsGroupRows; }
- (void)setFloatsGroupRows:(BOOL)f { _floatsGroupRows = f; }
- (BOOL)usesStaticContents { return _staticContents; }
- (void)setUsesStaticContents:(BOOL)f { _staticContents = f; }
- (BOOL)verticalMotionCanBeginDrag { return _verticalDrag; }
- (void)setVerticalMotionCanBeginDrag:(BOOL)f { _verticalDrag = f; }
- (NSString *)autosaveName { return _autosaveName; }
- (void)setAutosaveName:(NSString *)n
{
    [_autosaveName release];
    _autosaveName = [n copy];
}
- (BOOL)autosaveTableColumns { return _autosaveColumns; }
- (void)setAutosaveTableColumns:(BOOL)f { _autosaveColumns = f; }
- (SEL)doubleAction { return _doubleAction; }
- (void)setDoubleAction:(SEL)a { _doubleAction = a; }
- (NSInteger)clickedRow { return _clickedRow; }
- (NSInteger)clickedColumn { return _clickedColumn; }
- (NSInteger)editedRow { return _editedRow; }
- (NSInteger)editedColumn { return _editedColumn; }

/* ---- editing a cell in place ---- */

/* The text field a view-based table edits in a cell: the cell view, when
 * it is an editable text field, or the cell view's textField. */
- (NSTextField *)_editableFieldAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSView *v = [self viewAtColumn:column row:row makeIfNecessary:YES];
    NSTextField *f = nil;
    if ([v isKindOfClass:[NSTextField class]])
        f = (NSTextField *)v;
    else if ([v isKindOfClass:[NSTableCellView class]])
        f = [(NSTableCellView *)v textField];
    return [f isKindOfClass:[NSTextField class]] && [f isEditable] && [f isEnabled] && ![f isHiddenOrHasHiddenAncestor]
               ? f
               : nil;
}
/* The text cell a cell-based table would edit, or nil. */
- (NSCell *)_editableCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    NSTableColumn *c = [_columns objectAtIndex:(NSUInteger)column];
    NSCell *cell = [self _delegateCellForColumn:c row:row] ?: [c dataCellForRow:row];
    BOOL enabled = ABindingCellHas(c, NSEnabledBinding) ? ABindingCellAllows(c, NSEnabledBinding, row) : [cell isEnabled];
    return [cell isKindOfClass:[NSTextFieldCell class]] && enabled ? cell : nil;
}
/* Whether a double click (or Return, or Tab from the cell before) edits
 * this cell: in a view-based table, when it holds an editable text field;
 * in a cell-based one, when its column is editable, its cell is a text
 * cell, the data source can take the new value and the delegate agrees. */
- (BOOL)_canEditColumn:(NSInteger)column row:(NSInteger)row
{
    if (column < 0 || column >= (NSInteger)[_columns count] || row < 0 || row >= [self numberOfRows])
        return NO;
    NSTableColumn *c = [_columns objectAtIndex:(NSUInteger)column];
    if ([c isHidden])
        return NO;
    if (!ABindingCellEditable(c, row))
        return NO;   /* its controller, or its row's editable or enabled binding, says no */
    if ([self _delegateMakesViews])
        return [self _editableFieldAtColumn:column row:row] != nil;
    if ([self _isGroupRow:row] || ![c isEditable] ||
        !([self _dataSourceTakesValues] || ABindingIsBound(c, NSValueBinding)) ||
        ![self _editableCellAtColumn:column row:row])
        return NO;
    return [self _shouldEditColumn:c row:row];
}
- (BOOL)_isEditingField:(NSTextField *)f { return f && f == _editor; }

/* Edits a cell: the row must be selected, as Apple documents. It doesn't
 * ask the column or the delegate (a double click does), but the cell has
 * to be one that takes text. */
- (void)editColumn:(NSInteger)column row:(NSInteger)row withEvent:(NSEvent *)e select:(BOOL)select
{
    if (row < 0 || row >= [self numberOfRows] || column < 0 || column >= (NSInteger)[_columns count])
        return;
    if (![self isRowSelected:row])
        [NSException raise:NSInternalInconsistencyException
                    format:@"-[NSTableView editColumn:row:withEvent:select:]: row %ld isn't selected", (long)row];
    if (_editor) {
        [self _endEditingWithMovement:NSTextMovementOther];
        if (_editor)
            return;
    }
    NSWindow *w = [self window];
    if (!w)
        return;
    [self scrollRowToVisible:row];
    [self scrollColumnToVisible:column];
    NSTextField *field;
    if ([self _delegateMakesViews]) {
        field = [self _editableFieldAtColumn:column row:row];
        if (!field)
            return;
    } else {
        NSCell *cell = [self _editableCellAtColumn:column row:row];
        if (!cell)
            return;
        cell = [self preparedCellAtColumn:column row:row];
        ATableCellEditor *ed = [[[ATableCellEditor alloc] initWithFrame:[self frameOfCellAtColumn:column row:row]] autorelease];
        ed->_table = self;
        [ed setDelegate:ed];
        if ([cell font])
            [ed setFont:[cell font]];
        [ed setAlignment:[cell alignment]];
        [ed setBezeled:NO];
        [ed setBordered:YES];
        [ed setDrawsBackground:YES];
        [ed setEditable:YES];
        /* the column cell's formatter shows the value and reads what is
         * typed, so the data source gets the value, not the text */
        if ([cell formatter]) {
            [ed setFormatter:[cell formatter]];
            [ed setObjectValue:[cell objectValue]];
        } else {
            [ed setStringValue:[cell stringValue] ?: @""];
        }
        [self addSubview:ed];
        field = ed;
    }
    _editor = [field retain];
    _editOriginal = [[field objectValue] retain];
    _editedRow = row;
    _editedColumn = column;
    [self setNeedsDisplayInRect:[self rectOfRow:row]];
    if (![w makeFirstResponder:field]) {
        if (_editor == field)
            [self _editingFieldDidResign:field];
        return;
    }
    if (!select)
        [field _placeCaretAtEnd];
}

/* The field is no longer being edited: forget it, and take the cell-based
 * table's field away. */
- (void)_editingFieldDidResign:(NSTextField *)f
{
    if (!f || f != _editor)
        return;
    NSInteger row = _editedRow;
    [_editor autorelease];
    _editor = nil;
    [_editOriginal release];
    _editOriginal = nil;
    _editedRow = _editedColumn = -1;
    if ([f isKindOfClass:[ATableCellEditor class]])
        [f removeFromSuperview];
    if (row >= 0 && row < [self numberOfRows])
        [self setNeedsDisplayInRect:[self rectOfRow:row]];
}

/* What the cell-based table's field would have posted: the table posts it,
 * as the control, and the data source gets the new value as editing ends
 * (unless it was cancelled). */
- (void)_cellEditorPosted:(NSNotificationName)name selector:(SEL)sel movement:(NSInteger)movement
{
    NSDictionary *info = nil;
    if ([name isEqualToString:NSControlTextDidEndEditingNotification]) {
        info = @{NSTextMovementUserInfoKey : @(movement)};
        if (movement != NSTextMovementCancel && _editor && _editedRow >= 0 && _editedColumn >= 0 &&
            _editedColumn < (NSInteger)[_columns count])
            [self _setObjectValue:[_editor formatter] ? [_editor objectValue] : [_editor stringValue]
                        forColumn:[_columns objectAtIndex:(NSUInteger)_editedColumn]
                              row:_editedRow];
    }
    NSNotification *n = [NSNotification notificationWithName:name object:self userInfo:info];
    if ([_delegate respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(_delegate, sel, n);
    [[NSNotificationCenter defaultCenter] postNotification:n];
}

/* The next (or previous) cell that can be edited after column, row: along
 * the row, then on to the next rows. -1 in *column when there is none. */
- (NSInteger)_editableCellFrom:(NSInteger)column row:(NSInteger)row forward:(BOOL)forward column:(NSInteger *)outColumn
{
    NSInteger nc = (NSInteger)[_columns count], nr = [self numberOfRows], c = column, r = row;
    *outColumn = -1;
    if (nc == 0)
        return -1;
    for (;;) {
        if (forward) {
            if (++c >= nc) {
                c = 0;
                if (++r >= nr)
                    return -1;
            }
        } else {
            if (--c < 0) {
                c = nc - 1;
                if (--r < 0)
                    return -1;
            }
        }
        if ([self _canEditColumn:c row:r]) {
            *outColumn = c;
            return r;
        }
    }
}

/* Ends the editing as Return, Tab, Shift-Tab or Escape asks. Tab and
 * Shift-Tab go on to edit the next or previous editable cell, selecting
 * its row; past the last (or before the first) the table keeps the
 * keyboard. If the delegate won't let the editing end, it goes on. */
- (void)_endEditingWithMovement:(NSInteger)movement
{
    if (!_editor || _endingEdit)
        return;
    NSTextField *f = [[_editor retain] autorelease];
    NSInteger row = _editedRow, column = _editedColumn;
    if (movement == NSTextMovementCancel)
        [f _discardEditsTo:_editOriginal];
    [f _setTextMovement:movement];
    _endingEdit = YES;
    NSWindow *w = [self window];
    NSUInteger beeps = ABeepCount();
    BOOL ended = w && [w firstResponder] == f ? [w makeFirstResponder:self] : [f resignFirstResponder];
    _endingEdit = NO;
    if (!ended || _editor == f) {
        [f _setTextMovement:NSTextMovementOther];
        if (ABeepCount() == beeps)   /* once: a formatter that refused the text beeped already */
            NSBeep();
        return;
    }
    if (movement != NSTextMovementTab && movement != NSTextMovementBacktab)
        return;
    NSInteger nextColumn;
    NSInteger nextRow = [self _editableCellFrom:column row:row forward:movement == NSTextMovementTab column:&nextColumn];
    if (nextRow < 0)
        return;
    if (![self isRowSelected:nextRow] || [self numberOfSelectedRows] != 1) {
        if (![self _userSelect:[NSIndexSet indexSetWithIndex:(NSUInteger)nextRow]] || ![self isRowSelected:nextRow])
            return;
        [self _setAnchor:nextRow];
    }
    [self editColumn:nextColumn row:nextRow withEvent:nil select:YES];
}

/* Ends any editing and gives up what was typed. */
- (BOOL)abortEditing
{
    if (!_editor)
        return NO;
    if (!_endingEdit)
        [self _endEditingWithMovement:NSTextMovementCancel];
    return YES;
}
/* Where editing a cell starts when Return is pressed on the table. */
- (NSInteger)_firstEditableColumnInRow:(NSInteger)row
{
    for (NSInteger c = 0; c < (NSInteger)[_columns count]; c++)
        if ([self _canEditColumn:c row:row])
            return c;
    return -1;
}
- (NSTableColumn *)highlightedTableColumn { return _highlightedColumn; }
- (void)setHighlightedTableColumn:(NSTableColumn *)c
{
    [c retain];
    [_highlightedColumn release];
    _highlightedColumn = c;
    [_header setNeedsDisplay:YES];
}
- (void)setIndicatorImage:(NSImage *)image inTableColumn:(NSTableColumn *)c
{
    if (!c)
        return;
    NSValue *key = [NSValue valueWithNonretainedObject:c];
    if (image)
        [_indicators setObject:image forKey:key];
    else
        [_indicators removeObjectForKey:key];
    [_header setNeedsDisplay:YES];
}
- (NSImage *)indicatorImageInTableColumn:(NSTableColumn *)c
{
    return c ? [_indicators objectForKey:[NSValue valueWithNonretainedObject:c]] : nil;
}

/* ---- sorting ---- */

- (NSArray *)sortDescriptors { return _sortDescriptors; }
- (void)setSortDescriptors:(NSArray *)d
{
    d = d ?: @[];
    if ([d isEqual:_sortDescriptors])
        return;
    NSArray *old = _sortDescriptors;
    _sortDescriptors = [d copy];
    [self _sortDescriptorsDidChange:old];
    [old release];
    [_header setNeedsDisplay:YES];
}
/* A click on a column's title: sort by it, or turn its sort around. */
- (void)_headerClickedColumn:(NSTableColumn *)c
{
    NSSortDescriptor *proto = [c sortDescriptorPrototype];
    if (proto) {
        NSSortDescriptor *first = [_sortDescriptors firstObject];
        NSMutableArray *next = [NSMutableArray array];
        if (first && [[first key] isEqualToString:[proto key]]) {
            [next addObject:[first reversedSortDescriptor]];
            [next addObjectsFromArray:[_sortDescriptors subarrayWithRange:NSMakeRange(1, [_sortDescriptors count] - 1)]];
        } else {
            [next addObject:proto];
            for (NSSortDescriptor *d in _sortDescriptors)
                if (![[d key] isEqualToString:[proto key]])
                    [next addObject:d];
        }
        [self setSortDescriptors:next];
    }
    [self _didClickColumn:c];
}

/* ---- loading ---- */

- (void)reloadData
{
    /* reloading gives up a cell being edited, unless the reload comes from
     * the data source taking the cell's new value */
    if (_editor && !_endingEdit)
        [self abortEditing];
    [self _dropAllRowViews];
    [self _computeRows];
    NSRange beyond = NSMakeRange((NSUInteger)_rows, NSNotFound - (NSUInteger)_rows);
    BOOL changed = [_selection countOfIndexesInRange:beyond] > 0;
    [_selection removeIndexesInRange:beyond];
    /* a bound selection is the controller's to choose */
    if (!_empty && ![_selection count] && _rows > 0 && !ABindingIsBound(self, NSSelectionIndexesBinding) &&
        !ABindingIsBound(self, NSSelectionIndexPathsBinding)) {
        [_selection addIndex:0];
        changed = YES;
    }
    [self tile];
    if (changed) {
        [self _selectionChanged];
        [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
    }
}
- (void)_reloadRowsQuietly
{
    [self _dropAllRowViews];
    [self _computeRows];
    [self tile];
}
- (void)_setAnchor:(NSInteger)row
{
    _anchor = _lead = _lastSelected = row;
}
- (void)noteNumberOfRowsChanged
{
    NSInteger old = _rows;
    [self _computeRows];
    if (_rows < old) {
        for (NSInteger r = _rows; r < old; r++)
            [self _removeRowView:r];
        if ([_selection countOfIndexesInRange:NSMakeRange((NSUInteger)_rows, NSNotFound - (NSUInteger)_rows)]) {
            [_selection removeIndexesInRange:NSMakeRange((NSUInteger)_rows, NSNotFound - (NSUInteger)_rows)];
            [self _selectionChanged];
            [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
        }
    }
    [self tile];
}
- (void)noteHeightOfRowsWithIndexesChanged:(NSIndexSet *)rows
{
    [self _computeRows];
    [self tile];
}
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns
{
    [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        NSTableRowView *rv = [_rowViews objectForKey:@(r)];
        if (rv) {
            [columns enumerateIndexesUsingBlock:^(NSUInteger c, BOOL *stop2) {
                if (c < [_columns count])
                    [self _removeView:[rv viewAtColumn:(NSInteger)c] column:[_columns objectAtIndex:c] fromRowView:rv];
            }];
            [self _fillRowView:rv row:(NSInteger)r];
        }
        [self setNeedsDisplayInRect:[self rectOfRow:(NSInteger)r]];
    }];
}
- (void)beginUpdates { _updateDepth++; }
- (void)endUpdates
{
    if (_updateDepth > 0 && --_updateDepth == 0)
        [self tile];
}
/* Renumbers the row views from row on by delta. */
- (void)_shiftRowViewsFrom:(NSInteger)row by:(NSInteger)delta
{
    NSMutableDictionary *moved = [NSMutableDictionary dictionary];
    for (NSNumber *key in [_rowViews allKeys]) {
        NSInteger r = [key integerValue];
        if (r >= row) {
            [moved setObject:[_rowViews objectForKey:key] forKey:@(r + delta)];
            [_rowViews removeObjectForKey:key];
        }
    }
    [_rowViews addEntriesFromDictionary:moved];
}
- (void)insertRowsAtIndexes:(NSIndexSet *)indexes withAnimation:(NSTableViewAnimationOptions)options
{
    if (![indexes count])
        return;
    if (_editor && !_endingEdit)
        [self abortEditing];
    [self numberOfRows];
    __block BOOL selectionMoved = NO;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        NSInteger at = MIN((NSInteger)i, _rows);
        [self _shiftRowViewsFrom:at by:1];
        if ([_selection countOfIndexesInRange:NSMakeRange((NSUInteger)at, NSNotFound - (NSUInteger)at)])
            selectionMoved = YES;
        [_selection shiftIndexesStartingAtIndex:(NSUInteger)at by:1];
        _rows++;
    }];
    [self _computeRows];
    [self tile];
    if (selectionMoved) {
        [self _selectionChanged];
        [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
    }
}
- (void)removeRowsAtIndexes:(NSIndexSet *)indexes withAnimation:(NSTableViewAnimationOptions)options
{
    if (![indexes count])
        return;
    if (_editor && !_endingEdit)
        [self abortEditing];
    [self numberOfRows];
    __block BOOL selectionMoved = NO;
    [indexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger i, BOOL *stop) {
        if ((NSInteger)i >= _rows)
            return;
        [self _removeRowView:(NSInteger)i];
        [self _shiftRowViewsFrom:(NSInteger)i + 1 by:-1];
        if ([_selection countOfIndexesInRange:NSMakeRange(i, NSNotFound - i)])
            selectionMoved = YES;
        [_selection removeIndex:i];
        [_selection shiftIndexesStartingAtIndex:i + 1 by:-1];
        _rows--;
    }];
    [self _computeRows];
    [self tile];
    if (selectionMoved) {
        [self _selectionChanged];
        [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
    }
}
- (void)moveRowAtIndex:(NSInteger)from toIndex:(NSInteger)to
{
    NSInteger n = [self numberOfRows];
    if (from < 0 || from >= n || to < 0 || to >= n || from == to)
        return;
    NSTableRowView *moving = [[_rowViews objectForKey:@(from)] retain];
    [_rowViews removeObjectForKey:@(from)];
    BOOL wasSelected = [_selection containsIndex:(NSUInteger)from];
    [_selection removeIndex:(NSUInteger)from];
    [_selection shiftIndexesStartingAtIndex:(NSUInteger)from + 1 by:-1];
    [self _shiftRowViewsFrom:from + 1 by:-1];
    [self _shiftRowViewsFrom:to by:1];
    [_selection shiftIndexesStartingAtIndex:(NSUInteger)to by:1];
    if (wasSelected)
        [_selection addIndex:(NSUInteger)to];
    if (moving)
        [_rowViews setObject:moving forKey:@(to)];
    [moving release];
    [self tile];
}
- (void)scrollRowToVisible:(NSInteger)row
{
    NSRect r = [self rectOfRow:row];
    if (NSIsEmptyRect(r))
        return;
    NSRect v = [self visibleRect];
    r.origin.x = v.origin.x;
    r.size.width = fmin(v.size.width, r.size.width);
    [self scrollRectToVisible:r];
    [self _updateVisibleViews];
}
- (void)scrollColumnToVisible:(NSInteger)column
{
    NSRect c = [self rectOfColumn:column];
    if (c.size.width <= 0)
        return;
    NSRect v = [self visibleRect];
    c.origin.y = v.origin.y;
    c.size.height = fmin(v.size.height, 1);
    [self scrollRectToVisible:c];
}

/* ---- selection ---- */

- (NSIndexSet *)selectedRowIndexes { return [[_selection copy] autorelease]; }
- (NSIndexSet *)selectedColumnIndexes { return [[_columnSelection copy] autorelease]; }
- (NSInteger)numberOfSelectedRows { return (NSInteger)[_selection count]; }
- (NSInteger)numberOfSelectedColumns { return (NSInteger)[_columnSelection count]; }
- (NSInteger)selectedRow
{
    if (![_selection count])
        return -1;
    if (_lastSelected >= 0 && [_selection containsIndex:(NSUInteger)_lastSelected])
        return _lastSelected;
    return (NSInteger)[_selection lastIndex];
}
- (NSInteger)selectedColumn { return [_columnSelection count] ? (NSInteger)[_columnSelection lastIndex] : -1; }
- (BOOL)isRowSelected:(NSInteger)row { return row >= 0 && [_selection containsIndex:(NSUInteger)row]; }
- (BOOL)isColumnSelected:(NSInteger)column { return column >= 0 && [_columnSelection containsIndex:(NSUInteger)column]; }

/* Sets the selection, redraws, and (if it changed and notify) posts the
 * notification. */
- (void)_setSelection:(NSIndexSet *)rows notify:(BOOL)notify
{
    NSMutableIndexSet *next = [[rows mutableCopy] autorelease];
    NSInteger n = [self numberOfRows];
    if (n >= 0)
        [next removeIndexesInRange:NSMakeRange((NSUInteger)n, NSNotFound - (NSUInteger)n)];
    if (!_multiple && [next count] > 1) {
        NSUInteger keep = (_lastSelected >= 0 && [next containsIndex:(NSUInteger)_lastSelected]) ? (NSUInteger)_lastSelected
                                                                                                : [next lastIndex];
        [next removeAllIndexes];
        [next addIndex:keep];
    }
    if ([next isEqualToIndexSet:_selection])
        return;
    [_selection removeAllIndexes];
    [_selection addIndexes:next];
    if ([_selection count] && !(_lastSelected >= 0 && [_selection containsIndex:(NSUInteger)_lastSelected]))
        _lastSelected = (NSInteger)[_selection lastIndex];
    if (![_selection count])
        _lastSelected = -1;
    [self _selectionChanged];
    if (!_bindingUpdate) {
        ABindingPush(self, NSSelectionIndexesBinding);
        ABindingPush(self, NSSelectionIndexPathsBinding);
    }
    if (notify)
        [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
}
- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
    NSMutableIndexSet *next = [NSMutableIndexSet indexSet];
    if (extend)
        [next addIndexes:_selection];
    if (indexes)
        [next addIndexes:indexes];
    if ([indexes count]) {
        _lastSelected = (NSInteger)[indexes lastIndex];
        _anchor = _lead = _lastSelected;
    }
    if ([_columnSelection count]) {
        [_columnSelection removeAllIndexes];
        [_header setNeedsDisplay:YES];
    }
    [self _setSelection:next notify:YES];
}
- (void)selectRow:(NSInteger)row byExtendingSelection:(BOOL)extend
{
    if (row >= 0)
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:extend];
}
- (void)deselectRow:(NSInteger)row
{
    if (![self isRowSelected:row])
        return;
    NSMutableIndexSet *next = [[_selection mutableCopy] autorelease];
    [next removeIndex:(NSUInteger)row];
    [self _setSelection:next notify:YES];
}
- (void)selectColumnIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend
{
    if (!_allowsColumnSelection)
        return;
    if (!extend)
        [_columnSelection removeAllIndexes];
    [_columnSelection addIndexes:indexes];
    [_selection removeAllIndexes];
    [self _selectionChanged];
    [_header setNeedsDisplay:YES];
    [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
}
- (void)deselectColumn:(NSInteger)column
{
    if (![self isColumnSelected:column])
        return;
    [_columnSelection removeIndex:(NSUInteger)column];
    [self setNeedsDisplay:YES];
    [self _post:[self _selectionDidChangeName] selector:[self _selectionDidChangeSelector] userInfo:nil];
}
- (void)selectAll:(id)sender
{
    if (!_multiple)
        return;
    [self _setSelection:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)[self numberOfRows])] notify:YES];
}
- (void)deselectAll:(id)sender
{
    if (!_empty)
        return;
    _anchor = _lead = -1;
    [self _setSelection:[NSIndexSet indexSet] notify:YES];
}

- (BOOL)_isEmphasized
{
    NSWindow *w = [self window];
    if (!w || ![w isKeyWindow])
        return NO;
    id r = [w firstResponder];
    return r == self || ([r isKindOfClass:[NSView class]] && [(NSView *)r isDescendantOf:self]);
}
/* Brings the row views (and the cell views in them) in line with the
 * selection, and redraws. */
- (void)_selectionChanged
{
    BOOL emphasized = [self _isEmphasized];
    for (NSNumber *key in _rowViews) {
        NSInteger r = [key integerValue];
        NSTableRowView *rv = [_rowViews objectForKey:key];
        [rv setEmphasized:emphasized];
        [rv setSelected:[self isRowSelected:r]];
        [rv setPreviousRowSelected:[self isRowSelected:r - 1]];
        [rv setNextRowSelected:[self isRowSelected:r + 1]];
        NSBackgroundStyle style = [rv interiorBackgroundStyle];
        for (NSView *v in [rv->_views allValues])
            if ([v respondsToSelector:@selector(setBackgroundStyle:)])
                [(NSTableCellView *)v setBackgroundStyle:style];
    }
    [self setNeedsDisplay:YES];
}

/* What a click (or a key) asks for, through the delegate's say. */
- (BOOL)_userSelect:(NSIndexSet *)proposed
{
    if ([proposed isEqualToIndexSet:_selection])
        return YES;
    if (![self _selectionShouldChange])
        return NO;
    NSMutableIndexSet *allowed = [NSMutableIndexSet indexSet];
    [proposed enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if ([_selection containsIndex:i] || [self _shouldSelectRow:(NSInteger)i])
            [allowed addIndex:i];
    }];
    if ([proposed count] && ![allowed count])
        return NO;
    if ([_delegate respondsToSelector:@selector(tableView:selectionIndexesForProposedSelection:)])
        allowed = [[[_delegate tableView:self selectionIndexesForProposedSelection:allowed] mutableCopy] autorelease];
    if (![allowed count] && !_empty)
        return NO;
    [self _setSelection:allowed notify:YES];
    return YES;
}
- (void)_clickRow:(NSInteger)row flags:(NSEventModifierFlags)flags
{
    BOOL cmd = (flags & NSEventModifierFlagCommand) != 0, shift = (flags & NSEventModifierFlagShift) != 0;
    if (row < 0) {
        if (_empty && !cmd && !shift && [_selection count]) {
            _anchor = _lead = -1;
            [self _userSelect:[NSIndexSet indexSet]];
        }
        return;
    }
    NSMutableIndexSet *next = [NSMutableIndexSet indexSet];
    if (_multiple && cmd) {
        [next addIndexes:_selection];
        if ([next containsIndex:(NSUInteger)row]) {
            [next removeIndex:(NSUInteger)row];
            if (![next count] && !_empty)
                return;
        } else {
            [next addIndex:(NSUInteger)row];
            _lastSelected = row;
        }
        _anchor = _lead = row;
    } else if (_multiple && shift && _anchor >= 0) {
        NSInteger a = MIN(_anchor, row), b = MAX(_anchor, row);
        [next addIndexesInRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))];
        _lead = row;
        _lastSelected = row;
    } else {
        [next addIndex:(NSUInteger)row];
        _anchor = _lead = _lastSelected = row;
    }
    [self _userSelect:next];
}
/* The next row up or down from row that may be selected, or -1. */
- (NSInteger)_selectableRowFrom:(NSInteger)row step:(NSInteger)step
{
    NSInteger n = [self numberOfRows];
    for (NSInteger r = row + step; r >= 0 && r < n; r += step)
        if ([self _shouldSelectRow:r] && ![self _isGroupRow:r])
            return r;
    return -1;
}
- (void)_moveSelectionBy:(NSInteger)step extending:(BOOL)extend
{
    NSInteger n = [self numberOfRows];
    if (n == 0)
        return;
    NSInteger from = _lead >= 0 && _lead < n ? _lead : [self selectedRow];
    NSInteger to = from < 0 ? [self _selectableRowFrom:step > 0 ? -1 : n step:step] : [self _selectableRowFrom:from step:step];
    if (to < 0)
        return;
    NSMutableIndexSet *next = [NSMutableIndexSet indexSet];
    if (extend && _multiple && _anchor >= 0) {
        NSInteger a = MIN(_anchor, to), b = MAX(_anchor, to);
        [next addIndexesInRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))];
        _lead = to;
    } else {
        [next addIndex:(NSUInteger)to];
        _anchor = _lead = to;
    }
    _lastSelected = to;
    if ([self _userSelect:next])
        [self scrollRowToVisible:to];
}
- (void)keyDown:(NSEvent *)e { [self interpretKeyEvents:@[ e ]]; }
- (void)insertText:(id)string {} /* type-to-select isn't done yet */
- (void)moveUp:(id)sender { [self _moveSelectionBy:-1 extending:NO]; }
- (void)moveDown:(id)sender { [self _moveSelectionBy:1 extending:NO]; }
- (void)moveUpAndModifySelection:(id)sender { [self _moveSelectionBy:-1 extending:YES]; }
- (void)moveDownAndModifySelection:(id)sender { [self _moveSelectionBy:1 extending:YES]; }
- (void)moveToBeginningOfDocument:(id)sender
{
    NSInteger to = [self _selectableRowFrom:-1 step:1];
    if (to >= 0 && [self _userSelect:[NSIndexSet indexSetWithIndex:(NSUInteger)to]]) {
        _anchor = _lead = _lastSelected = to;
        [self scrollRowToVisible:to];
    }
}
- (void)moveToEndOfDocument:(id)sender
{
    NSInteger to = [self _selectableRowFrom:[self numberOfRows] step:-1];
    if (to >= 0 && [self _userSelect:[NSIndexSet indexSetWithIndex:(NSUInteger)to]]) {
        _anchor = _lead = _lastSelected = to;
        [self scrollRowToVisible:to];
    }
}
- (void)scrollToBeginningOfDocument:(id)sender { [self scrollRowToVisible:0]; }
- (void)scrollToEndOfDocument:(id)sender { [self scrollRowToVisible:[self numberOfRows] - 1]; }
/* Return edits the selected row's first editable cell, as in the Finder's
 * lists; with no cell to edit it sends the double action. */
- (void)insertNewline:(id)sender
{
    NSInteger row = [self selectedRow];
    if (row >= 0 && [self numberOfSelectedRows] == 1) {
        NSInteger column = [self _firstEditableColumnInRow:row];
        if (column >= 0) {
            [self editColumn:column row:row withEvent:nil select:YES];
            return;
        }
    }
    if (_doubleAction && [self selectedRow] >= 0) {
        _clickedRow = [self selectedRow];
        _clickedColumn = -1;
        [self sendAction:_doubleAction to:[self target]];
    }
}
- (void)cancelOperation:(id)sender {}

/* ---- the mouse ---- */

/* Clicks on a cell view's labels and images are the table's, and so are
 * clicks on its editable text fields until a double click (or Return)
 * starts editing one; buttons, selectable fields, the field being edited
 * and other controls inside keep theirs. */
- (NSView *)hitTest:(NSPoint)p
{
    NSView *hit = [super hitTest:p];
    if (!hit || hit == self)
        return hit;
    for (NSView *v = hit; v && v != self; v = [v superview]) {
        if ([v isKindOfClass:[NSTextField class]]) {
            NSTextField *f = (NSTextField *)v;
            if (f == _editor || (![f isEditable] && [f isSelectable]))
                return hit;
            if ([f isEditable])
                return self;
        } else if ([v isKindOfClass:[NSControl class]] && ![v isKindOfClass:[NSImageView class]]) {
            return hit;
        }
    }
    return self;
}
- (BOOL)_toggleCheckAt:(NSInteger)row column:(NSInteger)column point:(NSPoint)p
{
    if (row < 0 || column < 0)
        return NO;
    NSTableColumn *col = [_columns objectAtIndex:(NSUInteger)column];
    NSCell *cell = [self preparedCellAtColumn:column row:row];
    if (![cell isKindOfClass:[NSButtonCell class]] || ![(NSButtonCell *)cell _isCheck] || ![cell isEnabled] ||
        ![col isEditable] || !ABindingCellEditable(col, row))
        return NO;
    NSInteger next = [cell state] == NSControlStateValueOn ? NSControlStateValueOff : NSControlStateValueOn;
    [self _setObjectValue:@(next) forColumn:col row:row];
    [self setNeedsDisplayInRect:[self rectOfRow:row]];
    if ([cell action])
        [NSApp sendAction:[cell action] to:[cell target] from:self];
    return YES;
}
- (void)mouseDown:(NSEvent *)e
{
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    NSInteger row = [self rowAtPoint:p], column = [self columnAtPoint:p];
    _clickedRow = row;
    _clickedColumn = column;
    _clickChangedSelection = NO;
    if ([[self window] firstResponder] != self)
        [[self window] makeFirstResponder:self];
    _editedOnClick = NO;
    if ([self _handleMouseDown:e row:row column:column point:p])
        return;
    /* a double click on an editable cell of a selected row edits it, and
     * sends neither the double action nor the action */
    if ([e clickCount] == 2 && [self isRowSelected:row] && [self _canEditColumn:column row:row]) {
        _editedOnClick = YES;
        [self editColumn:column row:row withEvent:e select:YES];
        return;
    }
    if (![self _delegateMakesViews] && [e clickCount] == 1 && [self _toggleCheckAt:row column:column point:p])
        return;
    _dragMaybe = _clickDeferred = NO;
    if ([e clickCount] == 1 && row >= 0 && [self _canDragRows]) {
        _dragMaybe = YES;
        _dragFrom = p;
        _dragRow = row;
        /* a press on a row of a larger selection may drag them all */
        NSEventModifierFlags f = [e modifierFlags];
        if ([self isRowSelected:row] && [_selection count] > 1 &&
            !(f & (NSEventModifierFlagCommand | NSEventModifierFlagShift))) {
            _clickDeferred = YES;
            return;
        }
    }
    if ([e clickCount] == 1) {
        NSIndexSet *before = [[_selection copy] autorelease];
        [self _clickRow:row flags:[e modifierFlags]];
        _clickChangedSelection = ![before isEqualToIndexSet:_selection];
    }
}
- (void)mouseDragged:(NSEvent *)e
{
    if (_dragMaybe) {
        NSPoint at = [self convertPoint:[e locationInWindow] fromView:nil];
        CGFloat dx = at.x - _dragFrom.x, dy = at.y - _dragFrom.y;
        if (hypot(dx, dy) < 4)
            return;
        _dragMaybe = NO;
        if ((_verticalDrag || fabs(dx) > fabs(dy)) && [self _beginDragOfRows:e])
            return;
        if (_clickDeferred) {
            _clickDeferred = NO;
            [self _clickRow:_dragRow flags:0];
        }
    }
    if (!_multiple || _anchor < 0)
        return;
    NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
    [self autoscroll:e];
    NSInteger row = [self rowAtPoint:p];
    if (row < 0)
        row = p.y < 0 ? 0 : [self numberOfRows] - 1;
    if (row < 0 || row == _lead)
        return;
    NSInteger a = MIN(_anchor, row), b = MAX(_anchor, row);
    _lead = row;
    _lastSelected = row;
    [self _userSelect:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))]];
}
- (void)mouseUp:(NSEvent *)e
{
    _dragMaybe = NO;
    if (_clickDeferred) {
        _clickDeferred = NO;
        NSIndexSet *before = [[_selection copy] autorelease];
        [self _clickRow:_dragRow flags:0];
        _clickChangedSelection = ![before isEqualToIndexSet:_selection];
    }
    if (_editedOnClick) {
        _editedOnClick = NO;
        return;
    }
    if ([e clickCount] >= 2 && _doubleAction) {
        if (_clickedRow >= 0 || _clickedColumn >= 0)
            [self sendAction:_doubleAction to:[self target]];
        return;
    }
    if ([self action])
        [self sendAction:[self action] to:[self target]];
}

/* ---- dragging rows (freemac 1.220, Ferry 0.44.0) ---- */

- (BOOL)_canDragRows
{
    return [_dataSource respondsToSelector:@selector(tableView:pasteboardWriterForRow:)] ||
           [_dataSource respondsToSelector:@selector(tableView:writeRowsWithIndexes:toPasteboard:)];
}
- (BOOL)_putRows:(NSIndexSet *)rows onPasteboard:(NSPasteboard *)pb
{
    if ([_dataSource respondsToSelector:@selector(tableView:pasteboardWriterForRow:)]) {
        NSMutableArray *writers = [NSMutableArray array];
        id ds = _dataSource;
        [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
            id w = [ds tableView:self pasteboardWriterForRow:(NSInteger)r];
            if (w)
                [writers addObject:w];
        }];
        if ([writers count]) {
            [pb clearContents];
            return [pb writeObjects:writers];
        }
    }
    if ([_dataSource respondsToSelector:@selector(tableView:writeRowsWithIndexes:toPasteboard:)]) {
        [pb clearContents];
        return [_dataSource tableView:self writeRowsWithIndexes:rows toPasteboard:pb];
    }
    return NO;
}
- (void)_dragOfRows:(NSIndexSet *)rows session:(NSDraggingSession *)session willBeginAt:(NSPoint)screenPoint
{
    if ([_dataSource respondsToSelector:@selector(tableView:draggingSession:willBeginAtPoint:forRowIndexes:)])
        [_dataSource tableView:self draggingSession:session willBeginAtPoint:screenPoint forRowIndexes:rows];
}
- (void)_dragSession:(NSDraggingSession *)session endedAt:(NSPoint)screenPoint operation:(NSDragOperation)op
{
    if ([_dataSource respondsToSelector:@selector(tableView:draggingSession:endedAtPoint:operation:)])
        [_dataSource tableView:self draggingSession:session endedAtPoint:screenPoint operation:op];
}
- (BOOL)_beginDragOfRows:(NSEvent *)e
{
    NSIndexSet *rows = [self isRowSelected:_dragRow] ? [[_selection copy] autorelease]
                                                     : [NSIndexSet indexSetWithIndex:(NSUInteger)_dragRow];
    if (![rows count] || ![self canDragRowsWithIndexes:rows atPoint:_dragFrom])
        return NO;
    NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
    if (![self _putRows:rows onPasteboard:pb])
        return NO;
    _clickDeferred = NO;
    [_dragRows release];
    _dragRows = [rows retain];
    NSMutableArray *items = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) {
        NSDraggingItem *item = [[[NSDraggingItem alloc] initWithPasteboardWriter:nil] autorelease];
        [item setDraggingFrame:[self rectOfRow:(NSInteger)r]];
        [items addObject:item];
    }];
    ABeginDragSession(pb, items, self, e);
    return YES;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    return [self draggingSourceOperationMaskForLocal:context == NSDraggingContextWithinApplication];
}
- (void)draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint
{
    [self _dragOfRows:_dragRows ?: [NSIndexSet indexSet] session:session willBeginAt:screenPoint];
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint
              operation:(NSDragOperation)operation
{
    [self _dragSession:session endedAt:screenPoint operation:operation];
    [_dragRows release];
    _dragRows = nil;
}
- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    return (NSDragOperation)(isLocal ? _draggingMaskLocal : _draggingMaskNonLocal);
}
- (void)setDraggingSourceOperationMask:(NSDragOperation)mask forLocal:(BOOL)isLocal
{
    if (isLocal)
        _draggingMaskLocal = (NSInteger)mask;
    else
        _draggingMaskNonLocal = (NSInteger)mask;
}
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rows atPoint:(NSPoint)point { return YES; }
- (NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)rows tableColumns:(NSArray *)columns event:(NSEvent *)e
                                  offset:(NSPointPointer)offset
{
    return nil;     /* no picture follows the pointer yet */
}

/* ---- drops on rows ---- */

- (void)_updateDraggingItemsForDrag:(id<NSDraggingInfo>)info
{
    if ([_dataSource respondsToSelector:@selector(tableView:updateDraggingItemsForDrag:)])
        [_dataSource tableView:self updateDraggingItemsForDrag:info];
}
- (void)_proposeDropAt:(NSPoint)p
{
    NSInteger n = [self numberOfRows], r = [self rowAtPoint:p];
    if (r < 0) {
        _dropRow = p.y < 0 && n ? 0 : n;
        _dropOp = NSTableViewDropAbove;
        return;
    }
    NSRect rr = [self rectOfRow:r];
    CGFloat f = (p.y - NSMinY(rr)) / fmax(rr.size.height, 1);
    if (f < 0.25) {
        _dropRow = r;
        _dropOp = NSTableViewDropAbove;
    } else if (f > 0.75) {
        _dropRow = r + 1;
        _dropOp = NSTableViewDropAbove;
    } else {
        _dropRow = r;
        _dropOp = NSTableViewDropOn;
    }
}
- (void)setDropRow:(NSInteger)row dropOperation:(NSTableViewDropOperation)op
{
    _dropRow = row;
    _dropOp = op;
}
- (NSDragOperation)_validateDrop:(id<NSDraggingInfo>)info
{
    if (![_dataSource respondsToSelector:@selector(tableView:validateDrop:proposedRow:proposedDropOperation:)])
        return NSDragOperationNone;
    return [_dataSource tableView:self validateDrop:info proposedRow:_dropRow proposedDropOperation:_dropOp];
}
- (BOOL)_acceptDrop:(id<NSDraggingInfo>)info
{
    if (![_dataSource respondsToSelector:@selector(tableView:acceptDrop:row:dropOperation:)])
        return NO;
    return [_dataSource tableView:self acceptDrop:info row:_dropRow dropOperation:_dropOp];
}
- (BOOL)_dropFeedbackRow:(NSInteger *)row operation:(NSTableViewDropOperation *)op indent:(CGFloat *)indent
{
    *row = _dropRow;
    *op = _dropOp;
    *indent = 0;
    return _dropRow >= 0 || _dropOp == NSTableViewDropOn;
}

- (void)_hideDropFeedback
{
    [_dropIndicator removeFromSuperview];
    [_dropIndicator release];
    _dropIndicator = nil;
}
- (void)_showDropFeedback
{
    NSInteger row, n = [self numberOfRows];
    NSTableViewDropOperation op;
    CGFloat indent;
    if (_feedback == NSTableViewDraggingDestinationFeedbackStyleNone ||
        ![self _dropFeedbackRow:&row operation:&op indent:&indent]) {
        [self _hideDropFeedback];
        return;
    }
    NSRect b = [self bounds], r;
    BOOL ring = op == NSTableViewDropOn;
    if (ring && (row < 0 || row >= n)) {
        r = NSInsetRect([self visibleRect], 1, 1);
    } else if (ring) {
        r = NSInsetRect([self rectOfRow:row], 2, 0);
    } else {
        CGFloat y = row < n ? NSMinY([self rectOfRow:row]) : n ? NSMaxY([self rectOfRow:n - 1]) : 0;
        r = NSMakeRect(b.origin.x + indent + 2, y - 3, b.size.width - indent - 4, 6);
    }
    if (!_dropIndicator)
        _dropIndicator = [[ATableDropIndicator alloc] initWithFrame:r];
    ((ATableDropIndicator *)_dropIndicator)->ring = ring;
    [_dropIndicator setFrame:r];
    if ([_dropIndicator superview] != self || [[self subviews] lastObject] != _dropIndicator) {
        [_dropIndicator removeFromSuperview];
        [self addSubview:_dropIndicator];    /* over the rows */
    }
    [_dropIndicator setNeedsDisplay:YES];
}
- (NSDragOperation)_dropUpdate:(id<NSDraggingInfo>)info
{
    [self _proposeDropAt:[self convertPoint:[info draggingLocation] fromView:nil]];
    NSDragOperation op = [self _validateDrop:info];
    _dropValid = op != NSDragOperationNone;
    if (_dropValid)
        [self _showDropFeedback];
    else
        [self _hideDropFeedback];
    return op;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info
{
    [self _updateDraggingItemsForDrag:info];
    return [self _dropUpdate:info];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info { return [self _dropUpdate:info]; }
- (void)draggingExited:(id<NSDraggingInfo>)info
{
    _dropValid = NO;
    [self _hideDropFeedback];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)info { return _dropValid; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)info
{
    BOOL done = _dropValid && [self _acceptDrop:info];
    _dropValid = NO;
    [self _hideDropFeedback];
    return done;
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)info {}
- (void)draggingEnded:(id<NSDraggingInfo>)info { [self _hideDropFeedback]; }

/* ---- views ---- */

- (void)registerNib:(NSNib *)nib forIdentifier:(NSUserInterfaceItemIdentifier)identifier
{
    if (!identifier)
        return;
    if (nib)
        [_nibs setObject:nib forKey:identifier];
    else
        [_nibs removeObjectForKey:identifier];
}
- (NSDictionary *)registeredNibsByIdentifier { return [[_nibs copy] autorelease]; }
- (id)makeViewWithIdentifier:(NSUserInterfaceItemIdentifier)identifier owner:(id)owner
{
    if (!identifier)
        return nil;
    NSMutableArray *pool = [_reusable objectForKey:identifier];
    if ([pool count]) {
        NSView *v = [[[pool lastObject] retain] autorelease];
        [pool removeLastObject];
        if ([v respondsToSelector:@selector(prepareForReuse)])
            [v performSelector:@selector(prepareForReuse)];
        return v;
    }
    NSNib *nib = [_nibs objectForKey:identifier];
    if (!nib)
        return nil;
    NSArray *tops = nil;
    if (![nib instantiateWithOwner:owner topLevelObjects:&tops])
        return nil;
    NSView *found = nil;
    for (id o in tops)
        if ([o isKindOfClass:[NSView class]] && (!found || [[(NSView *)o identifier] isEqualToString:identifier]))
            found = o;
    if (found && ![found identifier])
        [found setIdentifier:identifier];
    return found;
}
- (NSInteger)_rowForRowView:(NSTableRowView *)view
{
    for (NSNumber *key in _rowViews)
        if ([_rowViews objectForKey:key] == view)
            return [key integerValue];
    return -1;
}
- (NSInteger)rowForView:(NSView *)view
{
    for (NSView *v = view; v && v != self; v = [v superview])
        if ([v isKindOfClass:[NSTableRowView class]] && [v superview] == self)
            return [self _rowForRowView:(NSTableRowView *)v];
    return -1;
}
- (NSInteger)columnForView:(NSView *)view
{
    for (NSView *v = view; v && v != self; v = [v superview]) {
        NSTableRowView *rv = [[v superview] isKindOfClass:[NSTableRowView class]] ? (NSTableRowView *)[v superview] : nil;
        if (!rv)
            continue;
        for (NSValue *key in rv->_views)
            if ([rv->_views objectForKey:key] == v && [key isKindOfClass:[NSValue class]])
                return (NSInteger)[_columns indexOfObjectIdenticalTo:[key nonretainedObjectValue]];
        return -1;
    }
    return -1;
}
- (id)rowViewAtRow:(NSInteger)row makeIfNecessary:(BOOL)make
{
    NSTableRowView *rv = [_rowViews objectForKey:@(row)];
    if (rv || !make || row < 0 || row >= [self numberOfRows] || ![self _delegateMakesViews])
        return rv;
    rv = [self _delegateRowViewForRow:row];
    if (![rv isKindOfClass:[NSTableRowView class]])
        rv = [self makeViewWithIdentifier:NSTableViewRowViewKey owner:_delegate];
    if (![rv isKindOfClass:[NSTableRowView class]])
        rv = [[[NSTableRowView alloc] initWithFrame:NSZeroRect] autorelease];
    [rv setSelectionHighlightStyle:_highlight];
    [rv setGroupRowStyle:[self _isGroupRow:row]];
    [rv setFrame:[self rectOfRow:row]];
    [_rowViews setObject:rv forKey:@(row)];
    [self addSubview:rv];
    [rv setEmphasized:[self _isEmphasized]];
    [rv setSelected:[self isRowSelected:row]];
    [rv setPreviousRowSelected:[self isRowSelected:row - 1]];
    [rv setNextRowSelected:[self isRowSelected:row + 1]];
    [self _fillRowView:rv row:row];
    [self _didAddRowView:rv row:row];
    return rv;
}
- (id)viewAtColumn:(NSInteger)column row:(NSInteger)row makeIfNecessary:(BOOL)make
{
    NSTableRowView *rv = [self rowViewAtRow:row makeIfNecessary:make];
    return [rv viewAtColumn:column];
}
- (void)enumerateAvailableRowViewsUsingBlock:(void (^)(__kindof NSTableRowView *, NSInteger))block
{
    NSArray *keys = [[_rowViews allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *key in keys) {
        NSTableRowView *rv = [_rowViews objectForKey:key];
        if (rv)
            block(rv, [key integerValue]);
    }
}
/* The frame of a cell in its row view. */
- (NSRect)_cellFrameForColumn:(NSInteger)column row:(NSInteger)row
{
    NSRect f = [self frameOfCellAtColumn:column row:row], rr = [self rectOfRow:row];
    f.origin.y -= rr.origin.y;
    return f;
}
/* Asks the delegate for the views a row view lacks. */
- (void)_fillRowView:(NSTableRowView *)rv row:(NSInteger)row
{
    if ([rv isGroupRowStyle]) {
        if (![rv->_views objectForKey:[NSNull null]]) {
            NSView *v = [self _delegateViewForColumn:nil row:row];
            if (v) {
                NSRect rr = [self rectOfRow:row];
                [v setFrame:NSMakeRect(0, floor(_spacing.height / 2), rr.size.width, rr.size.height - _spacing.height)];
                [rv->_views setObject:v forKey:[NSNull null]];
                [rv addSubview:v];
                /* a source list's heading, in Interface Builder's colour for
                 * it, is drawn as a Mac draws it, in grey */
                if (_highlight == NSTableViewSelectionHighlightStyleSourceList &&
                    [v respondsToSelector:@selector(textField)]) {
                    NSTextField *tf = [(NSTableCellView *)v textField];
                    if ([[tf textColor] isEqual:[NSColor headerColor]])
                        [tf setTextColor:[NSColor secondaryLabelColor]];
                }
            }
        }
    } else {
        for (NSUInteger i = 0; i < [_columns count]; i++) {
            NSTableColumn *c = [_columns objectAtIndex:i];
            NSValue *key = [NSValue valueWithNonretainedObject:c];
            if ([c isHidden] || [rv->_views objectForKey:key])
                continue;
            NSView *v = [self _delegateViewForColumn:c row:row];
            if (!v)
                continue;
            if ([v respondsToSelector:@selector(setObjectValue:)] &&
                ([_dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)] ||
                 [_dataSource respondsToSelector:@selector(outlineView:objectValueForTableColumn:byItem:)] ||
                 ABindingIsBound(c, NSValueBinding) || ABindingIsBound(self, NSContentBinding)))
                [(NSTableCellView *)v setObjectValue:[self _objectValueForColumn:c row:row]];
            [v setFrame:[self _cellFrameForColumn:(NSInteger)i row:row]];
            [rv->_views setObject:v forKey:key];
            if ([v superview] != rv)
                [rv addSubview:v];
        }
    }
    NSBackgroundStyle style = [rv interiorBackgroundStyle];
    for (NSView *v in [rv->_views allValues])
        if ([v respondsToSelector:@selector(setBackgroundStyle:)])
            [(NSTableCellView *)v setBackgroundStyle:style];
}
/* Takes a cell view out of its row and keeps it to be made again. */
- (void)_removeView:(NSView *)v column:(id)column fromRowView:(NSTableRowView *)rv
{
    if (!v)
        return;
    [v retain];
    [rv->_views removeObjectForKey:column ? [NSValue valueWithNonretainedObject:column] : (id)[NSNull null]];
    [v removeFromSuperview];
    NSString *ident = [v identifier];
    if (ident) {
        NSMutableArray *pool = [_reusable objectForKey:ident];
        if (!pool) {
            pool = [NSMutableArray array];
            [_reusable setObject:pool forKey:ident];
        }
        if ([pool count] < 64)
            [pool addObject:v];
    }
    [v release];
}
- (void)_removeRowView:(NSInteger)row
{
    NSTableRowView *rv = [[_rowViews objectForKey:@(row)] retain];
    if (!rv)
        return;
    [_rowViews removeObjectForKey:@(row)];
    for (NSValue *key in [rv->_views allKeys]) {
        id column = [key isKindOfClass:[NSNull class]] ? nil : [key nonretainedObjectValue];
        [self _removeView:[rv->_views objectForKey:key] column:column fromRowView:rv];
    }
    [rv removeFromSuperview];
    [self _didRemoveRowView:rv row:row];
    if ([rv identifier]) {
        NSMutableArray *pool = [_reusable objectForKey:[rv identifier]];
        if (!pool) {
            pool = [NSMutableArray array];
            [_reusable setObject:pool forKey:[rv identifier]];
        }
        [pool addObject:rv];
    }
    [rv release];
}
- (void)_dropAllRowViews
{
    for (NSNumber *key in [_rowViews allKeys])
        [self _removeRowView:[key integerValue]];
}
- (void)_layOutRowViews
{
    for (NSNumber *key in _rowViews) {
        NSInteger r = [key integerValue];
        NSTableRowView *rv = [_rowViews objectForKey:key];
        [rv setFrame:[self rectOfRow:r]];
        for (NSValue *ck in rv->_views) {
            NSView *v = [rv->_views objectForKey:ck];
            if ([ck isKindOfClass:[NSNull class]]) {
                NSRect rr = [self rectOfRow:r];
                [v setFrame:NSMakeRect(0, floor(_spacing.height / 2), rr.size.width, rr.size.height - _spacing.height)];
                continue;
            }
            NSInteger i = (NSInteger)[_columns indexOfObjectIdenticalTo:[ck nonretainedObjectValue]];
            if (i >= 0)
                [v setFrame:[self _cellFrameForColumn:i row:r]];
        }
    }
    if ([_editor isKindOfClass:[ATableCellEditor class]] && _editedRow >= 0 && _editedColumn >= 0)
        [_editor setFrame:[self frameOfCellAtColumn:_editedColumn row:_editedRow]];
}
/* The part of the table in sight: the clip view's, or all of it. */
- (NSRect)_shownRect
{
    NSView *sv = [self superview];
    if ([sv isKindOfClass:[NSClipView class]])
        return NSIntersectionRect([self convertRect:[sv bounds] fromView:sv], [self bounds]);
    NSRect v = [self visibleRect];
    return NSIsEmptyRect(v) ? [self bounds] : v;
}
/* Makes row views for the rows in sight and lets go of the others; a
 * table in no window shows nothing, so it makes none until it has one. */
- (void)_updateVisibleViews
{
    if (_updatingViews || _updateDepth > 0 || _tiling || ![self window] || ![self _delegateMakesViews])
        return;
    _updatingViews = YES;
    NSRange rows = [self rowsInRect:[self _shownRect]];
    for (NSNumber *key in [_rowViews allKeys]) {
        NSUInteger r = (NSUInteger)[key integerValue];
        /* the row being edited stays, in sight or not */
        if (!NSLocationInRange(r, rows) && !(_editor && (NSInteger)r == _editedRow))
            [self _removeRowView:(NSInteger)r];
    }
    for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++)
        [self rowViewAtRow:(NSInteger)r makeIfNecessary:YES];
    _updatingViews = NO;
}

/* ---- drawing ---- */

- (void)drawBackgroundInClipRect:(NSRect)clip
{
    NSColor *bg = [self backgroundColor];
    [bg setFill];
    NSRectFillUsingOperation(clip, NSCompositingOperationSourceOver);
    if (!_alternating)
        return;
    NSArray *colors = [NSColor alternatingContentBackgroundColors];
    NSInteger n = [self numberOfRows];
    CGFloat stride = _rowHeight + _spacing.height;
    NSRange rows = [self rowsInRect:clip];
    for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++) {
        [[colors objectAtIndex:r % [colors count]] setFill];
        NSRectFill(NSIntersectionRect([self rectOfRow:(NSInteger)r], clip));
    }
    /* stripes carry on below the last row */
    CGFloat y = [self _rowsHeight];
    for (NSInteger r = n; y < NSMaxY(clip); r++, y += stride) {
        if (y + stride < NSMinY(clip))
            continue;
        [[colors objectAtIndex:(NSUInteger)r % [colors count]] setFill];
        NSRectFill(NSIntersectionRect(NSMakeRect(NSMinX(clip), y, clip.size.width, stride), clip));
    }
}
- (void)drawGridInClipRect:(NSRect)clip
{
    if (!_gridMask)
        return;
    [[self gridColor] setFill];
    if (_gridMask & NSTableViewSolidVerticalGridLineMask) {
        for (NSUInteger i = 0; i < [_columns count]; i++) {
            NSRect c = [self rectOfColumn:(NSInteger)i];
            if (c.size.width > 0)
                NSRectFill(NSIntersectionRect(NSMakeRect(NSMaxX(c) - 1, NSMinY(clip), 1, clip.size.height), clip));
        }
    }
    if (_gridMask & (NSTableViewSolidHorizontalGridLineMask | NSTableViewDashedHorizontalGridLineMask)) {
        NSRange rows = [self rowsInRect:clip];
        for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++) {
            NSRect rr = [self rectOfRow:(NSInteger)r];
            NSRect line = NSMakeRect(NSMinX(clip), NSMaxY(rr) - 1, clip.size.width, 1);
            if (_gridMask & NSTableViewDashedHorizontalGridLineMask) {
                NSBezierPath *p = [NSBezierPath bezierPath];
                [p moveToPoint:NSMakePoint(NSMinX(line), NSMidY(line))];
                [p lineToPoint:NSMakePoint(NSMaxX(line), NSMidY(line))];
                CGFloat dash[2] = {2, 2};
                [p setLineDash:dash count:2 phase:0];
                [p setLineWidth:1];
                [[self gridColor] setStroke];
                [p stroke];
            } else {
                NSRectFill(line);
            }
        }
    }
}
- (void)highlightSelectionInClipRect:(NSRect)clip
{
    if (_highlight == NSTableViewSelectionHighlightStyleNone)
        return;
    BOOL emphasized = [self _isEmphasized];
    NSTableViewStyle style = [self _drawingStyle];
    NSRange rows = [self rowsInRect:clip];
    /* each run of selected rows as one block */
    NSUInteger r = rows.location;
    while (r < NSMaxRange(rows)) {
        if (![_selection containsIndex:r]) {
            r++;
            continue;
        }
        NSUInteger first = r;
        while (r + 1 < (NSUInteger)[self numberOfRows] && [_selection containsIndex:r + 1])
            r++;
        NSRect block = NSUnionRect([self rectOfRow:(NSInteger)first], [self rectOfRow:(NSInteger)r]);
        ATableDrawSelection(block, style, _highlight, emphasized, NO, NO);
        r++;
    }
    for (NSUInteger c = 0; c < [_columns count]; c++)
        if ([_columnSelection containsIndex:c]) {
            [[(emphasized ? [NSColor selectedContentBackgroundColor] : [NSColor unemphasizedSelectedContentBackgroundColor])
                colorWithAlphaComponent:0.25] setFill];
            NSRectFillUsingOperation(NSIntersectionRect([self rectOfColumn:(NSInteger)c], clip),
                                     NSCompositingOperationSourceOver);
        }
}
- (NSCell *)preparedCellAtColumn:(NSInteger)column row:(NSInteger)row
{
    if (column < 0 || column >= (NSInteger)[_columns count] || row < 0 || row >= [self numberOfRows])
        return nil;
    NSTableColumn *c = [_columns objectAtIndex:(NSUInteger)column];
    NSCell *cell = [self _delegateCellForColumn:c row:row] ?: [c dataCellForRow:row];
    id value = [self _objectValueForColumn:c row:row];
    if ([cell isKindOfClass:[NSButtonCell class]] && [(NSButtonCell *)cell _isCheck])
        [cell setState:[value respondsToSelector:@selector(integerValue)] ? [value integerValue] : NSControlStateValueOff];
    else
        [cell setObjectValue:value];
    [cell setControlView:self];
    if (ABindingCellHas(c, NSEnabledBinding))
        [cell setEnabled:ABindingCellAllows(c, NSEnabledBinding, row)];
    BOOL selected = [self isRowSelected:row] || [self isColumnSelected:column];
    [cell setBackgroundStyle:selected && [self _isEmphasized] && _highlight != NSTableViewSelectionHighlightStyleNone
                                 ? NSBackgroundStyleEmphasized
                                 : NSBackgroundStyleNormal];
    [self _willDisplayCell:cell column:c row:row];
    return cell;
}
- (void)drawRow:(NSInteger)row clipRect:(NSRect)clip
{
    for (NSUInteger i = 0; i < [_columns count]; i++) {
        if ([[_columns objectAtIndex:i] isHidden])
            continue;
        if (_editor && row == _editedRow && (NSInteger)i == _editedColumn)
            continue; /* the field editing it is drawn instead */
        NSRect f = [self frameOfCellAtColumn:(NSInteger)i row:row];
        if (NSIsEmptyRect(f) || !NSIntersectsRect(NSInsetRect(f, -_spacing.width, -_spacing.height), clip))
            continue;
        NSCell *cell = [self preparedCellAtColumn:(NSInteger)i row:row];
        [cell drawWithFrame:f inView:self];
    }
    [self _drawDecorationsForRow:row];
}
- (void)drawRect:(NSRect)dirty
{
    [self drawBackgroundInClipRect:dirty];
    [self drawGridInClipRect:dirty];
    if ([self _delegateMakesViews]) {
        [self _updateVisibleViews];
        return;
    }
    [self highlightSelectionInClipRect:dirty];
    NSRange rows = [self rowsInRect:dirty];
    for (NSUInteger r = rows.location; r < NSMaxRange(rows); r++)
        [self drawRow:(NSInteger)r clipRect:dirty];
}
- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:NSWindowDidBecomeKeyNotification object:nil];
    [nc removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
    if ([self window]) {
        [nc addObserver:self selector:@selector(_keyChanged:) name:NSWindowDidBecomeKeyNotification object:[self window]];
        [nc addObserver:self selector:@selector(_keyChanged:) name:NSWindowDidResignKeyNotification object:[self window]];
    }
    [self tile];
}
- (void)_keyChanged:(NSNotification *)n { [self _selectionChanged]; }
@end
