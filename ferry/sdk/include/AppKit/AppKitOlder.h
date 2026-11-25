/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Older AppKit names that apps written for Mac OS X 10.6 to 10.10 still
 * use, Sequel Pro's among them (freemac 1.226, Ferry 0.50.0): the window
 * and bezel style names from before NSWindowStyleMask and NSBezelStyle,
 * colour lists, HFS type codes as file types, the print panel's accessory
 * protocol, the token field cell's delegate, PICT image reps, and the
 * conversions to and from a window's "base" coordinates. Written from
 * Apple's public documentation; not Apple's header. Implemented in
 * appkit/AppKitOlder.m. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_OLDER_H_
#define _FERRY_APPKIT_OLDER_H_

#define NSTexturedBackgroundWindowMask NSWindowStyleMaskTexturedBackground
#define NSThickSquareBezelStyle NSBezelStyleThickSquare
#define NSThickerSquareBezelStyle NSBezelStyleThickerSquare

/* ---- a window's base coordinates ------------------------------------------------------
 * The base coordinate system is the window's; these are convertRect:toView:
 * and convertRect:fromView: with nil, as on a Mac since 10.7. */
@interface NSView (FerryBaseCoordinates)
- (NSRect)convertRectToBase:(NSRect)rect;
- (NSRect)convertRectFromBase:(NSRect)rect;
- (NSPoint)convertPointToBase:(NSPoint)point;
- (NSPoint)convertPointFromBase:(NSPoint)point;
- (NSSize)convertSizeToBase:(NSSize)size;
- (NSSize)convertSizeFromBase:(NSSize)size;
@end

/* ---- the layout manager's other glyph queries ------------------------------------------ */

@interface NSLayoutManager (FerryGlyphQueries)
/* Ferry lays the whole text out when it is asked, so this is
 * glyphRangeForBoundingRect:inTextContainer:. */
- (NSRange)glyphRangeForBoundingRectWithoutAdditionalLayout:(NSRect)bounds inTextContainer:(NSTextContainer *)container;
/* The glyph under the point, and how far across it the point is (0 at its
 * leading edge, 1 at its trailing edge). */
- (NSUInteger)glyphIndexForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container
    fractionOfDistanceThroughGlyph:(CGFloat *)fraction;
- (CGFloat)fractionOfDistanceThroughGlyphForPoint:(NSPoint)point inTextContainer:(NSTextContainer *)container;
@end

/* ---- colour lists ------------------------------------------------------------------------
 * Named lists of named colours. The list named "System" holds the system
 * colours by their NSColor names (controlColor, windowBackgroundColor, …)
 * and answers each with the NSColor class method of that name; "Apple"
 * and "Crayons" are not there. Lists an app makes are kept for the run. */
typedef NSString *NSColorListName;
typedef NSString *NSColorName;
@interface NSColorList : NSObject <NSCoding>
@property (class, readonly, copy) NSArray<NSColorList *> *availableColorLists;
+ (NSColorList *)colorListNamed:(NSColorListName)name;
- (instancetype)initWithName:(NSColorListName)name;
- (instancetype)initWithName:(NSColorListName)name fromFile:(NSString *)path;
@property (readonly, copy) NSColorListName name;
@property (readonly, copy) NSArray<NSColorName> *allKeys;
@property (readonly) BOOL isEditable;
- (NSColor *)colorWithKey:(NSColorName)key;
- (void)setColor:(NSColor *)color forKey:(NSColorName)key;
- (void)insertColor:(NSColor *)color key:(NSColorName)key atIndex:(NSUInteger)index;
- (void)removeColorWithKey:(NSColorName)key;
- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;
- (void)removeFile;
@end
APPKIT_EXTERN NSNotificationName const NSColorListDidChangeNotification;

/* ---- HFS type codes as file types -------------------------------------------------------
 * A type code as a file type is its four characters in single quotes
 * ('fldr'), which NSWorkspace's iconForFileType: takes. Ferry's files have
 * no type codes, so NSHFSTypeOfFile answers a folder's 'fldr' or nothing. */
NSString *NSFileTypeForHFSTypeCode(OSType hfsFileTypeCode);
OSType NSHFSTypeCodeFromFileType(NSString *fileTypeString);
NSString *NSHFSTypeOfFile(NSString *fullFilePath);

/* ---- the print panel's accessory views -------------------------------------------------- */

typedef NSString *NSPrintPanelAccessorySummaryKey;
APPKIT_EXTERN NSPrintPanelAccessorySummaryKey const NSPrintPanelAccessorySummaryItemNameKey;
APPKIT_EXTERN NSPrintPanelAccessorySummaryKey const NSPrintPanelAccessorySummaryItemDescriptionKey;
@protocol NSPrintPanelAccessorizing
- (NSArray<NSDictionary<NSPrintPanelAccessorySummaryKey, NSString *> *> *)localizedSummaryItems;
@optional
- (NSSet<NSString *> *)keyPathsForValuesAffectingPreview;
@end

/* ---- the token field cell's delegate --------------------------------------------------- */

@protocol NSTokenFieldCellDelegate <NSObject>
@optional
- (NSArray *)tokenFieldCell:(NSTokenFieldCell *)cell completionsForSubstring:(NSString *)substring
               indexOfToken:(NSInteger)index indexOfSelectedItem:(NSInteger *)selected;
- (NSArray *)tokenFieldCell:(NSTokenFieldCell *)cell shouldAddObjects:(NSArray *)tokens atIndex:(NSUInteger)index;
- (NSString *)tokenFieldCell:(NSTokenFieldCell *)cell displayStringForRepresentedObject:(id)object;
- (NSString *)tokenFieldCell:(NSTokenFieldCell *)cell editingStringForRepresentedObject:(id)object;
- (id)tokenFieldCell:(NSTokenFieldCell *)cell representedObjectForEditingString:(NSString *)string;
- (BOOL)tokenFieldCell:(NSTokenFieldCell *)cell writeRepresentedObjects:(NSArray *)objects
          toPasteboard:(NSPasteboard *)pboard;
- (NSArray *)tokenFieldCell:(NSTokenFieldCell *)cell readFromPasteboard:(NSPasteboard *)pboard;
- (NSMenu *)tokenFieldCell:(NSTokenFieldCell *)cell menuForRepresentedObject:(id)object;
- (BOOL)tokenFieldCell:(NSTokenFieldCell *)cell hasMenuForRepresentedObject:(id)object;
- (NSTokenStyle)tokenFieldCell:(NSTokenFieldCell *)cell styleForRepresentedObject:(id)object;
@end
@interface NSTokenFieldCell (FerryCellDelegate)
@property (assign) id<NSTokenFieldCellDelegate> delegate;
@end

/* ---- PICT images ------------------------------------------------------------------------
 * QuickDraw pictures, which only Mac OS X 10.0 to 10.14 drew. Ferry draws
 * none: an image rep made from PICT data is nil, and no data is read as
 * one (canInitWithData: answers NO). */
@interface NSPICTImageRep : NSImageRep
+ (BOOL)canInitWithData:(NSData *)data;
+ (instancetype)imageRepWithData:(NSData *)data;
- (instancetype)initWithData:(NSData *)data;
@property (readonly, strong) NSData *PICTRepresentation;
@property (readonly) NSRect boundingBox;
@end

/* ---- matrices of cells ------------------------------------------------------------------
 * A grid of cells of one size, the radio groups of nibs from before 10.8.
 * Ferry's controls draw themselves, so a matrix shows each button cell as
 * a button of its own, laid out row by row; in radio mode choosing one
 * turns the others off, and the matrix sends its action with itself as
 * the sender (selectedCell, selectedTag). */
typedef NS_ENUM(NSUInteger, NSMatrixMode) {
    NSRadioModeMatrix = 0,
    NSHighlightModeMatrix = 1,
    NSListModeMatrix = 2,
    NSTrackModeMatrix = 3,
};
@interface NSMatrix : NSControl
- (instancetype)initWithFrame:(NSRect)frame mode:(NSMatrixMode)mode prototype:(NSCell *)cell
                 numberOfRows:(NSInteger)rows numberOfColumns:(NSInteger)columns;
- (instancetype)initWithFrame:(NSRect)frame mode:(NSMatrixMode)mode cellClass:(Class)cellClass
                 numberOfRows:(NSInteger)rows numberOfColumns:(NSInteger)columns;
@property NSMatrixMode mode;
@property (retain) Class cellClass;
@property (retain) id prototype;
@property NSSize cellSize;
@property NSSize intercellSpacing;
@property BOOL allowsEmptySelection, selectionByRect, drawsBackground, drawsCellBackground, autosizesCells;
@property (copy) NSColor *backgroundColor, *cellBackgroundColor;
@property (readonly) NSInteger numberOfRows;
@property (readonly) NSInteger numberOfColumns;
@property (readonly, copy) NSArray<NSCell *> *cells;
- (NSCell *)makeCellAtRow:(NSInteger)row column:(NSInteger)column;
- (NSCell *)cellAtRow:(NSInteger)row column:(NSInteger)column;
- (NSCell *)cellWithTag:(NSInteger)tag;
- (BOOL)getRow:(NSInteger *)row column:(NSInteger *)column ofCell:(NSCell *)cell;
- (void)renewRows:(NSInteger)rows columns:(NSInteger)columns;
- (void)addRow;
- (void)addColumn;
- (void)putCell:(NSCell *)cell atRow:(NSInteger)row column:(NSInteger)column;
@property (readonly, strong) NSCell *selectedCell;
@property (readonly, copy) NSArray<NSCell *> *selectedCells;
@property (readonly) NSInteger selectedRow;
@property (readonly) NSInteger selectedColumn;
@property (readonly) NSInteger selectedTag;
- (void)selectCellAtRow:(NSInteger)row column:(NSInteger)column;
- (BOOL)selectCellWithTag:(NSInteger)tag;
- (void)selectAll:(id)sender;
- (void)deselectAllCells;
- (void)deselectSelectedCell;
- (void)setState:(NSInteger)value atRow:(NSInteger)row column:(NSInteger)column;
- (void)sizeToCells;
- (NSRect)cellFrameAtRow:(NSInteger)row column:(NSInteger)column;
@end

/* ---- the spelling checker ---------------------------------------------------------------
 * Ferry has no dictionaries: every word is spelled right, there are no
 * guesses or completions, and the words a program has the checker learn
 * are kept for the run. */
@interface NSSpellChecker : NSObject
@property (class, readonly, strong) NSSpellChecker *sharedSpellChecker;
@property (class, readonly) BOOL sharedSpellCheckerExists;
+ (NSInteger)uniqueSpellDocumentTag;
- (NSString *)language;
@property (readonly, copy) NSArray<NSString *> *availableLanguages;
@property (copy) NSArray<NSString *> *userPreferredLanguages;
@property BOOL automaticallyIdentifiesLanguages;
- (BOOL)setLanguage:(NSString *)language;
- (NSRange)checkSpellingOfString:(NSString *)string startingAt:(NSInteger)start;
- (NSRange)checkSpellingOfString:(NSString *)string startingAt:(NSInteger)start language:(NSString *)language
                            wrap:(BOOL)wrap inSpellDocumentWithTag:(NSInteger)tag wordCount:(NSInteger *)count;
- (NSInteger)countWordsInString:(NSString *)string language:(NSString *)language;
- (NSArray<NSString *> *)guessesForWordRange:(NSRange)range inString:(NSString *)string
                                    language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag;
- (NSArray<NSString *> *)completionsForPartialWordRange:(NSRange)range inString:(NSString *)string
                                               language:(NSString *)language
                                 inSpellDocumentWithTag:(NSInteger)tag;
- (void)learnWord:(NSString *)word;
- (void)unlearnWord:(NSString *)word;
- (BOOL)hasLearnedWord:(NSString *)word;
- (void)ignoreWord:(NSString *)word inSpellDocumentWithTag:(NSInteger)tag;
- (NSArray<NSString *> *)ignoredWordsInSpellDocumentWithTag:(NSInteger)tag;
- (void)setIgnoredWords:(NSArray<NSString *> *)words inSpellDocumentWithTag:(NSInteger)tag;
- (void)closeSpellDocumentWithTag:(NSInteger)tag;
- (void)updateSpellingPanelWithMisspelledWord:(NSString *)word;
@property (readonly, strong) NSPanel *spellingPanel;
@property (readonly, strong) NSPanel *substitutionsPanel;
@end

/* ---- the graphics port ------------------------------------------------------------------
 * The name the Core Graphics context had before 10.10, as an untyped
 * pointer. */
@interface NSGraphicsContext (FerryGraphicsPort)
@property (readonly) void *graphicsPort;
@end

/* ---- the HTML writer's left-out elements ------------------------------------------------ */

APPKIT_EXTERN NSAttributedStringDocumentAttributeKey const NSExcludedElementsDocumentAttribute;

#endif
