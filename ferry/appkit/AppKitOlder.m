/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Older AppKit names that Sequel Pro and other apps written for Mac OS X
 * 10.6 to 10.10 still use (freemac 1.226, Ferry 0.50.0): see
 * AppKitOlder.h. Written from Apple's public documentation; no Apple code
 * was read. */
#import "AInternal.h"
#import <objc/runtime.h>

/* ---- a window's base coordinates ------------------------------------------------------ */

@implementation NSView (FerryBaseCoordinates)
- (NSRect)convertRectToBase:(NSRect)rect { return [self convertRect:rect toView:nil]; }
- (NSRect)convertRectFromBase:(NSRect)rect { return [self convertRect:rect fromView:nil]; }
- (NSPoint)convertPointToBase:(NSPoint)point { return [self convertPoint:point toView:nil]; }
- (NSPoint)convertPointFromBase:(NSPoint)point { return [self convertPoint:point fromView:nil]; }
- (NSSize)convertSizeToBase:(NSSize)size { return [self convertSize:size toView:nil]; }
- (NSSize)convertSizeFromBase:(NSSize)size { return [self convertSize:size fromView:nil]; }
@end

/* ---- the layout manager's other glyph queries ------------------------------------------ */

@implementation NSLayoutManager (FerryGlyphQueries)
- (NSRange)glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds inTextContainer:(NSTextContainer *)container
{
    return [self glyphRangeForBoundingRect:bounds inTextContainer:container];
}

/* glyphIndexForPoint:inTextContainer: answers the nearest insertion point;
 * the glyph under the point is the one before it when the point lies
 * within that glyph's rectangle. */
- (NSUInteger)glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
    fractionOfDistanceThroughGlyph:(CGFloat *)fraction
{
    NSUInteger n = [self numberOfGlyphs];
    NSUInteger i = [self glyphIndexForPoint:point inTextContainer:container];
    if (fraction)
        *fraction = 0;
    if (!n)
        return 0;
    if (i >= n)
        i = n - 1;
    if (i > 0) {
        NSRect before = [self boundingRectForGlyphRange:NSMakeRange(i - 1, 1) inTextContainer:container];
        if (point.x >= NSMinX(before) && point.x <= NSMaxX(before) && point.y >= NSMinY(before) &&
            point.y <= NSMaxY(before))
            i--;
    }
    if (fraction) {
        NSRect r = [self boundingRectForGlyphRange:NSMakeRange(i, 1) inTextContainer:container];
        CGFloat f = r.size.width > 0 ? (point.x - NSMinX(r)) / r.size.width : 0;
        *fraction = f < 0 ? 0 : f > 1 ? 1 : f;
    }
    return i;
}

- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
{
    CGFloat f = 0;
    [self glyphIndexForPoint:point inTextContainer:container fractionOfDistanceThroughGlyph:&f];
    return f;
}
@end

/* ---- colour lists ------------------------------------------------------------------------ */

NSNotificationName const NSColorListDidChangeNotification = @"NSColorListDidChangeNotification";

/* the system colours' names: each is an NSColor class method */
static NSArray *system_color_names(void)
{
    return @[
        @"alternateSelectedControlColor", @"alternateSelectedControlTextColor", @"controlBackgroundColor",
        @"controlColor", @"controlDarkShadowColor", @"controlHighlightColor", @"controlLightHighlightColor",
        @"controlShadowColor", @"controlTextColor", @"disabledControlTextColor", @"gridColor",
        @"headerColor", @"headerTextColor", @"highlightColor", @"keyboardFocusIndicatorColor",
        @"knobColor", @"labelColor", @"linkColor", @"placeholderTextColor", @"quaternaryLabelColor",
        @"scrollBarColor", @"secondaryLabelColor", @"secondarySelectedControlColor", @"selectedControlColor",
        @"selectedControlTextColor", @"selectedKnobColor", @"selectedMenuItemColor",
        @"selectedMenuItemTextColor", @"selectedTextBackgroundColor", @"selectedTextColor",
        @"separatorColor", @"shadowColor", @"tertiaryLabelColor", @"textBackgroundColor", @"textColor",
        @"underPageBackgroundColor", @"windowBackgroundColor", @"windowFrameColor", @"windowFrameTextColor",
    ];
}

@implementation NSColorList {
    NSString *_name;
    NSMutableArray *_keys;
    NSMutableDictionary *_colors;
    BOOL _system;
}

static NSMutableArray *made_lists(void)
{
    static NSMutableArray *lists;
    if (!lists)
        lists = [[NSMutableArray alloc] init];
    return lists;
}

static NSColorList *system_list(void)
{
    static NSColorList *list;
    if (!list) {
        list = [[NSColorList alloc] initWithName:@"System"];
        list->_system = YES;
        for (NSString *key in system_color_names())
            if ([NSColor respondsToSelector:NSSelectorFromString(key)])
                [list->_keys addObject:key];
    }
    return list;
}

+ (NSArray *)availableColorLists
{
    NSMutableArray *a = [NSMutableArray arrayWithObject:system_list()];
    @synchronized(made_lists()) {
        [a addObjectsFromArray:made_lists()];
    }
    return a;
}

+ (NSColorList *)colorListNamed:(NSString *)name
{
    for (NSColorList *list in [self availableColorLists])
        if ([[list name] isEqualToString:name])
            return list;
    return nil;
}

- (instancetype)initWithName:(NSString *)name
{
    if ((self = [super init])) {
        _name = [name copy];
        _keys = [[NSMutableArray alloc] init];
        _colors = [[NSMutableDictionary alloc] init];
        if (name && ![name isEqualToString:@"System"])
            @synchronized(made_lists()) {
                [made_lists() addObject:self];
            }
    }
    return self;
}

/* A colour list file is an archive of a list, as writeToURL:error: makes it. */
- (instancetype)initWithName:(NSString *)name fromFile:(NSString *)path
{
    if (!(self = [self initWithName:name]))
        return nil;
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSColorList *read = nil;
    @try {
        read = data ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
    } @catch (NSException *e) {
        read = nil;
    }
    if ([read isKindOfClass:[NSColorList class]])
        for (NSString *key in [read allKeys])
            [self setColor:[read colorWithKey:key] forKey:key];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self initWithName:[coder decodeObjectForKey:@"NSName"]])) {
        NSArray *keys = [coder decodeObjectForKey:@"NSKeys"];
        NSArray *colors = [coder decodeObjectForKey:@"NSColors"];
        for (NSUInteger i = 0; i < [keys count] && i < [colors count]; i++)
            [self setColor:colors[i] forKey:keys[i]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    NSMutableArray *colors = [NSMutableArray array];
    for (NSString *key in [self allKeys])
        [colors addObject:[self colorWithKey:key] ?: [NSColor clearColor]];
    [coder encodeObject:_name forKey:@"NSName"];
    [coder encodeObject:[self allKeys] forKey:@"NSKeys"];
    [coder encodeObject:colors forKey:@"NSColors"];
}

- (void)dealloc
{
    [_name release];
    [_keys release];
    [_colors release];
    [super dealloc];
}

- (NSString *)name { return _name; }
- (NSArray *)allKeys { return [[_keys copy] autorelease]; }
- (BOOL)isEditable { return !_system; }

- (NSColor *)colorWithKey:(NSString *)key
{
    if (_system) {
        if (![_keys containsObject:key])
            return nil;
        id color = [NSColor performSelector:NSSelectorFromString(key)];
        return [color isKindOfClass:[NSColor class]] ? color : nil;
    }
    return [_colors objectForKey:key];
}

- (void)insertColor:(NSColor *)color key:(NSString *)key atIndex:(NSUInteger)index
{
    if (_system || !key || !color)
        return;
    [_keys removeObject:key];
    [_keys insertObject:key atIndex:MIN(index, [_keys count])];
    [_colors setObject:color forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSColorListDidChangeNotification object:self];
}

- (void)setColor:(NSColor *)color forKey:(NSString *)key
{
    if (_system || !key || !color)
        return;
    if (![_keys containsObject:key])
        [_keys addObject:key];
    [_colors setObject:color forKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSColorListDidChangeNotification object:self];
}

- (void)removeColorWithKey:(NSString *)key
{
    if (_system || ![_keys containsObject:key])
        return;
    [_keys removeObject:key];
    [_colors removeObjectForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSColorListDidChangeNotification object:self];
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error
{
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self];
    return url && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (void)removeFile
{
    @synchronized(made_lists()) {
        [made_lists() removeObjectIdenticalTo:self];
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<NSColorList %p %@, %lu colours>", self, _name, (unsigned long)[_keys count]];
}
@end

/* ---- HFS type codes as file types ------------------------------------------------------- */

NSString *NSFileTypeForHFSTypeCode(OSType code)
{
    char s[7] = {'\'', (char)(code >> 24), (char)(code >> 16), (char)(code >> 8), (char)code, '\'', 0};
    for (int i = 1; i < 5; i++)
        if (!s[i])
            s[i] = ' ';
    return [NSString stringWithCString:s encoding:NSMacOSRomanStringEncoding];
}

/* "'abcd'" or "abcd"; anything else is 0. */
OSType NSHFSTypeCodeFromFileType(NSString *type)
{
    NSData *d = [type dataUsingEncoding:NSMacOSRomanStringEncoding];
    const unsigned char *b = [d bytes];
    NSUInteger n = [d length];
    if (n == 6 && b[0] == '\'' && b[5] == '\'')
        b++, n = 4;
    if (n != 4)
        return 0;
    return ((OSType)b[0] << 24) | ((OSType)b[1] << 16) | ((OSType)b[2] << 8) | b[3];
}

NSString *NSHFSTypeOfFile(NSString *path)
{
    BOOL dir = NO;
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir])
        return nil;
    return dir ? NSFileTypeForHFSTypeCode('fldr') : NSFileTypeForHFSTypeCode(0);
}

/* ---- the print panel's accessory views -------------------------------------------------- */

NSPrintPanelAccessorySummaryKey const NSPrintPanelAccessorySummaryItemNameKey = @"name";
NSPrintPanelAccessorySummaryKey const NSPrintPanelAccessorySummaryItemDescriptionKey = @"description";

/* ---- the token field cell's delegate ----------------------------------------------------- */

static char cell_delegate_key;

@interface AWeakCellDelegate : NSObject {
  @public
    id target;
}
@end
@implementation AWeakCellDelegate
@end

@implementation NSTokenFieldCell (FerryCellDelegate)
- (id)delegate
{
    AWeakCellDelegate *box = objc_getAssociatedObject(self, &cell_delegate_key);
    return box ? box->target : nil;
}
- (void)setDelegate:(id)delegate
{
    AWeakCellDelegate *box = [[AWeakCellDelegate alloc] init];
    box->target = delegate;
    objc_setAssociatedObject(self, &cell_delegate_key, box, OBJC_ASSOCIATION_RETAIN);
    [box release];
}
@end

/* ---- PICT images ---------------------------------------------------------------------- */

@implementation NSPICTImageRep
+ (instancetype)imageRepWithData:(NSData *)data { return [[[self alloc] initWithData:data] autorelease]; }
- (instancetype)initWithData:(NSData *)data
{
    [self release];
    return nil;
}
+ (BOOL)canInitWithData:(NSData *)data { return NO; }
+ (NSArray *)imageUnfilteredTypes { return @[]; }
- (NSData *)PICTRepresentation { return nil; }
- (NSRect)boundingBox { return NSZeroRect; }
- (BOOL)draw { return NO; }
@end

/* ---- the HTML writer's left-out elements ------------------------------------------------ */

NSAttributedStringDocumentAttributeKey const NSExcludedElementsDocumentAttribute = @"ExcludedElements";

/* ---- matrices of cells ------------------------------------------------------------------ */

@interface NSButtonCell (FerryMatrixType)
- (NSButtonType)_buttonType;
@end

@implementation NSMatrix {
    NSMatrixMode _mode;
    Class _cellClass;
    id _prototype;
    NSSize _cellSize, _spacing;
    NSInteger _rows, _columns, _selected;
    NSMutableArray *_cells, *_buttons;
    BOOL _allowsEmpty, _byRect, _drawsBackground, _drawsCellBackground, _autosizes;
    NSColor *_background, *_cellBackground;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    return [self initWithFrame:frame mode:NSRadioModeMatrix cellClass:[NSActionCell class] numberOfRows:0
               numberOfColumns:0];
}

- (instancetype)initWithFrame:(NSRect)frame mode:(NSMatrixMode)mode cellClass:(Class)cellClass
                 numberOfRows:(NSInteger)rows numberOfColumns:(NSInteger)columns
{
    if ((self = [super initWithFrame:frame])) {
        _mode = mode;
        _cellClass = cellClass ?: [NSActionCell class];
        _cellSize = NSMakeSize(100, 17);
        _spacing = NSMakeSize(1, 1);
        _selected = -1;
        _allowsEmpty = YES;
        _cells = [[NSMutableArray alloc] init];
        _buttons = [[NSMutableArray alloc] init];
        [self renewRows:rows columns:columns];
    }
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame mode:(NSMatrixMode)mode prototype:(NSCell *)cell
                 numberOfRows:(NSInteger)rows numberOfColumns:(NSInteger)columns
{
    if ((self = [self initWithFrame:frame mode:mode cellClass:[cell class] numberOfRows:0 numberOfColumns:0])) {
        _prototype = [cell retain];
        [self renewRows:rows columns:columns];
    }
    return self;
}

- (void)dealloc
{
    [_prototype release];
    [_cells release];
    [_buttons release];
    [_background release];
    [_cellBackground release];
    [super dealloc];
}

- (NSMatrixMode)mode { return _mode; }
- (void)setMode:(NSMatrixMode)mode { _mode = mode; }
- (Class)cellClass { return _cellClass; }
- (void)setCellClass:(Class)c { _cellClass = c; }
- (id)prototype { return _prototype; }
- (void)setPrototype:(id)p
{
    [p retain];
    [_prototype release];
    _prototype = p;
}
- (NSSize)cellSize { return _cellSize; }
- (void)setCellSize:(NSSize)s
{
    _cellSize = s;
    [self _layout];
}
- (NSSize)intercellSpacing { return _spacing; }
- (void)setIntercellSpacing:(NSSize)s
{
    _spacing = s;
    [self _layout];
}
- (BOOL)allowsEmptySelection { return _allowsEmpty; }
- (void)setAllowsEmptySelection:(BOOL)f { _allowsEmpty = f; }
- (BOOL)selectionByRect { return _byRect; }
- (void)setSelectionByRect:(BOOL)f { _byRect = f; }
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)f { _drawsBackground = f; }
- (BOOL)drawsCellBackground { return _drawsCellBackground; }
- (void)setDrawsCellBackground:(BOOL)f { _drawsCellBackground = f; }
- (BOOL)autosizesCells { return _autosizes; }
- (void)setAutosizesCells:(BOOL)f { _autosizes = f; }
- (NSColor *)backgroundColor { return _background; }
- (void)setBackgroundColor:(NSColor *)c
{
    c = [c copy];
    [_background release];
    _background = c;
}
- (NSColor *)cellBackgroundColor { return _cellBackground; }
- (void)setCellBackgroundColor:(NSColor *)c
{
    c = [c copy];
    [_cellBackground release];
    _cellBackground = c;
}
- (NSInteger)numberOfRows { return _rows; }
- (NSInteger)numberOfColumns { return _columns; }
- (NSArray *)cells { return [[_cells copy] autorelease]; }

- (NSCell *)makeCellAtRow:(NSInteger)row column:(NSInteger)column
{
    return _prototype ? [[_prototype copy] autorelease] : [[[_cellClass alloc] init] autorelease];
}

static NSUInteger cell_index(NSInteger row, NSInteger column, NSInteger columns)
{
    return (NSUInteger)(row * columns + column);
}

- (NSCell *)cellAtRow:(NSInteger)row column:(NSInteger)column
{
    if (row < 0 || column < 0 || row >= _rows || column >= _columns)
        return nil;
    return [_cells objectAtIndex:cell_index(row, column, _columns)];
}

- (NSCell *)cellWithTag:(NSInteger)tag
{
    for (NSCell *c in _cells)
        if ([c tag] == tag)
            return c;
    return nil;
}

- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)column ofCell:(NSCell *)cell
{
    NSUInteger i = [_cells indexOfObjectIdenticalTo:cell];
    if (i == NSNotFound || !_columns)
        return NO;
    if (row)
        *row = (NSInteger)i / _columns;
    if (column)
        *column = (NSInteger)i % _columns;
    return YES;
}

/* the button that shows a cell */
- (NSButton *)_buttonFor:(NSCell *)cell
{
    NSButton *b = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
    if ([cell isKindOfClass:[NSButtonCell class]] && [cell respondsToSelector:@selector(_buttonType)])
        [b setButtonType:[(NSButtonCell *)cell _buttonType]];
    else if (_mode == NSRadioModeMatrix)
        [b setButtonType:NSButtonTypeRadio];
    [b setTitle:[cell title] ?: @""];
    if ([cell font])
        [b setFont:[cell font]];
    [b setState:[cell state]];
    [b setTag:[cell tag]];
    [b setEnabled:[cell isEnabled]];
    [b setTarget:self];
    [b setAction:@selector(_cellButtonClicked:)];
    return b;
}

/* rows run down from the top, as in a nib */
- (BOOL)isFlipped { return YES; }

- (NSRect)cellFrameAtRow:(NSInteger)row column:(NSInteger)column
{
    CGFloat x = column * (_cellSize.width + _spacing.width);
    CGFloat y = row * (_cellSize.height + _spacing.height);
    if (![self isFlipped])
        y = NSHeight([self bounds]) - y - _cellSize.height;
    return NSMakeRect(x, y, _cellSize.width, _cellSize.height);
}

- (void)_layout
{
    for (NSUInteger i = 0; i < [_buttons count]; i++) {
        NSInteger row = _columns ? (NSInteger)i / _columns : 0, column = _columns ? (NSInteger)i % _columns : 0;
        [[_buttons objectAtIndex:i] setFrame:[self cellFrameAtRow:row column:column]];
    }
}

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self _layout];
}

- (void)_rebuild
{
    for (NSButton *b in _buttons)
        [b removeFromSuperview];
    [_buttons removeAllObjects];
    for (NSCell *c in _cells) {
        NSButton *b = [self _buttonFor:c];
        [_buttons addObject:b];
        [self addSubview:b];
    }
    [self _layout];
}

- (void)renewRows:(NSInteger)rows columns:(NSInteger)columns
{
    rows = rows < 0 ? 0 : rows;
    columns = columns < 0 ? 0 : columns;
    NSMutableArray *cells = [NSMutableArray array];
    for (NSInteger r = 0; r < rows; r++)
        for (NSInteger c = 0; c < columns; c++) {
            NSCell *old = r < _rows && c < _columns ? [self cellAtRow:r column:c] : nil;
            NSCell *cell = old ?: [self makeCellAtRow:r column:c];
            [cell setControlView:self];
            [cells addObject:cell];
        }
    [_cells setArray:cells];
    _rows = rows;
    _columns = columns;
    if (_selected >= (NSInteger)[_cells count])
        _selected = -1;
    [self _rebuild];
}

- (void)addRow { [self renewRows:_rows + 1 columns:_columns ?: 1]; }
- (void)addColumn { [self renewRows:_rows ?: 1 columns:_columns + 1]; }

- (void)putCell:(NSCell *)cell atRow:(NSInteger)row column:(NSInteger)column
{
    if (!cell || row < 0 || column < 0 || row >= _rows || column >= _columns)
        return;
    [cell setControlView:self];
    [_cells replaceObjectAtIndex:cell_index(row, column, _columns) withObject:cell];
    [self _rebuild];
}

- (void)_syncButtons
{
    for (NSUInteger i = 0; i < [_cells count] && i < [_buttons count]; i++)
        [(NSButton *)[_buttons objectAtIndex:i] setState:[(NSCell *)[_cells objectAtIndex:i] state]];
}

- (NSCell *)selectedCell
{
    return _selected >= 0 && _selected < (NSInteger)[_cells count] ? [_cells objectAtIndex:(NSUInteger)_selected] : nil;
}
- (NSArray *)selectedCells
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSCell *c in _cells)
        if ([c state] == NSControlStateValueOn)
            [a addObject:c];
    if (![a count] && [self selectedCell])
        [a addObject:[self selectedCell]];
    return a;
}
- (NSInteger)selectedRow { return _selected >= 0 && _columns ? _selected / _columns : -1; }
- (NSInteger)selectedColumn { return _selected >= 0 && _columns ? _selected % _columns : -1; }
- (NSInteger)selectedTag { return [[self selectedCell] tag]; }

- (void)_select:(NSInteger)i
{
    _selected = i;
    if (_mode == NSRadioModeMatrix)
        for (NSInteger k = 0; k < (NSInteger)[_cells count]; k++)
            [[_cells objectAtIndex:(NSUInteger)k] setState:k == i ? NSControlStateValueOn : NSControlStateValueOff];
    else if (i >= 0)
        [[_cells objectAtIndex:(NSUInteger)i] setState:NSControlStateValueOn];
    [self _syncButtons];
}

- (void)selectCellAtRow:(NSInteger)row column:(NSInteger)column
{
    if (row < 0 || column < 0) {
        [self deselectAllCells];
        return;
    }
    if ([self cellAtRow:row column:column])
        [self _select:(NSInteger)cell_index(row, column, _columns)];
}

- (BOOL)selectCellWithTag:(NSInteger)tag
{
    NSCell *c = [self cellWithTag:tag];
    if (!c)
        return NO;
    [self _select:(NSInteger)[_cells indexOfObjectIdenticalTo:c]];
    return YES;
}

- (void)selectAll:(id)sender
{
    if (_mode == NSRadioModeMatrix)
        return;
    for (NSCell *c in _cells)
        [c setState:NSControlStateValueOn];
    [self _syncButtons];
}

- (void)deselectAllCells
{
    if (_mode == NSRadioModeMatrix && !_allowsEmpty)
        return;
    for (NSCell *c in _cells)
        [c setState:NSControlStateValueOff];
    _selected = -1;
    [self _syncButtons];
}

- (void)deselectSelectedCell
{
    if (_mode == NSRadioModeMatrix && !_allowsEmpty)
        return;
    [[self selectedCell] setState:NSControlStateValueOff];
    _selected = -1;
    [self _syncButtons];
}

- (void)setState:(NSInteger)value atRow:(NSInteger)row column:(NSInteger)column
{
    NSCell *c = [self cellAtRow:row column:column];
    if (!c)
        return;
    if (value && _mode == NSRadioModeMatrix)
        [self _select:(NSInteger)cell_index(row, column, _columns)];
    else
        [c setState:value];
    [self _syncButtons];
}

- (void)sizeToCells
{
    [self setFrameSize:NSMakeSize(_columns * _cellSize.width + (_columns > 1 ? (_columns - 1) * _spacing.width : 0),
                                  _rows * _cellSize.height + (_rows > 1 ? (_rows - 1) * _spacing.height : 0))];
}

- (void)_cellButtonClicked:(NSButton *)button
{
    NSUInteger i = [_buttons indexOfObjectIdenticalTo:button];
    if (i == NSNotFound)
        return;
    NSCell *cell = [_cells objectAtIndex:i];
    if (_mode == NSRadioModeMatrix) {
        [self _select:(NSInteger)i];
    } else {
        [cell setState:[button state]];
        _selected = (NSInteger)i;
    }
    /* a cell with its own action sends it; otherwise the matrix's */
    SEL action = [cell action] ?: [self action];
    id target = [cell action] ? [cell target] : [self target];
    if (action)
        [self sendAction:action to:target];
}

- (NSInteger)integerValue { return [self selectedTag]; }
@end

/* ---- the spelling checker ---------------------------------------------------------------- */

@implementation NSSpellChecker {
    NSString *_language;
    NSArray *_preferred;
    NSMutableSet *_learned;
    NSMutableDictionary *_ignored;
    BOOL _identifies;
}

static NSSpellChecker *shared_checker;

+ (NSSpellChecker *)sharedSpellChecker
{
    @synchronized(self) {
        if (!shared_checker)
            shared_checker = [[NSSpellChecker alloc] init];
    }
    return shared_checker;
}
+ (BOOL)sharedSpellCheckerExists { return shared_checker != nil; }
+ (NSInteger)uniqueSpellDocumentTag
{
    static NSInteger next;
    @synchronized(self) {
        return ++next;
    }
}

- (instancetype)init
{
    if ((self = [super init])) {
        _language = [@"en" copy];
        _learned = [[NSMutableSet alloc] init];
        _ignored = [[NSMutableDictionary alloc] init];
        _identifies = YES;
    }
    return self;
}

- (NSString *)language { return _language; }

- (BOOL)setLanguage:(NSString *)language
{
    if (![language length])
        return NO;
    language = [language copy];
    [_language release];
    _language = language;
    return YES;
}
- (NSArray *)availableLanguages { return @[]; }
- (NSArray *)userPreferredLanguages { return _preferred ?: @[]; }
- (void)setUserPreferredLanguages:(NSArray *)langs
{
    langs = [langs copy];
    [_preferred release];
    _preferred = langs;
}
- (BOOL)automaticallyIdentifiesLanguages { return _identifies; }
- (void)setAutomaticallyIdentifiesLanguages:(BOOL)f { _identifies = f; }

- (NSRange)checkSpellingOfString:(NSString *)string startingAt:(NSInteger)start
{
    return NSMakeRange(NSNotFound, 0);
}
- (NSRange)checkSpellingOfString:(NSString *)string startingAt:(NSInteger)start language:(NSString *)language
                            wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count
{
    if (count)
        *count = [self countWordsInString:string language:language];
    return NSMakeRange(NSNotFound, 0);
}
- (NSInteger)countWordsInString:(NSString *)string language:(NSString *)language
{
    NSInteger n = 0;
    BOOL inWord = NO;
    NSCharacterSet *letters = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < [string length]; i++) {
        BOOL letter = [letters characterIsMember:[string characterAtIndex:i]] || [string characterAtIndex:i] == '\'';
        if (letter && !inWord)
            n++;
        inWord = letter;
    }
    return n;
}
- (NSArray *)guessesForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language
          inSpellDocumentWithTag:(NSInteger)tag
{
    return @[];
}
- (NSArray *)completionsForPartialWordRange:(NSRange)range inString:(NSString *)string
                                   language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag
{
    return @[];
}
- (void)learnWord:(NSString *)word
{
    if (word)
        [_learned addObject:word];
}
- (void)unlearnWord:(NSString *)word
{
    if (word)
        [_learned removeObject:word];
}
- (BOOL)hasLearnedWord:(NSString *)word { return word && [_learned containsObject:word]; }
- (void)ignoreWord:(NSString *)word inSpellDocumentWithTag:(NSInteger)tag
{
    if (!word)
        return;
    NSMutableArray *a = [_ignored objectForKey:@(tag)];
    if (!a)
        [_ignored setObject:(a = [NSMutableArray array]) forKey:@(tag)];
    if (![a containsObject:word])
        [a addObject:word];
}
- (NSArray *)ignoredWordsInSpellDocumentWithTag:(NSInteger)tag
{
    return [[[_ignored objectForKey:@(tag)] copy] autorelease] ?: @[];
}
- (void)setIgnoredWords:(NSArray *)words inSpellDocumentWithTag:(NSInteger)tag
{
    [_ignored setObject:[NSMutableArray arrayWithArray:words ?: @[]] forKey:@(tag)];
}
- (void)closeSpellDocumentWithTag:(NSInteger)tag { [_ignored removeObjectForKey:@(tag)]; }
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word {}
- (NSPanel *)spellingPanel { return nil; }
- (NSPanel *)substitutionsPanel { return nil; }
@end

/* ---- the graphics port ------------------------------------------------------------------ */

@implementation NSGraphicsContext (FerryGraphicsPort)
- (void *)graphicsPort { return [self CGContext]; }
@end
