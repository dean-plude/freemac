/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What Chromium and Electron call in AppKit besides (freemac 1.265, Ferry
 * 0.88.0), written from Apple's public documentation; not Apple's header.
 * Implemented in appkit/AppKitElectron.m and appkit/NSCursor.m. Imported by
 * AppKit.h. */
#ifndef _FERRY_APPKIT_ELECTRON_H_
#define _FERRY_APPKIT_ELECTRON_H_

typedef NS_ENUM(NSUInteger, NSSelectionDirection) {
    NSDirectSelection = 0, NSSelectingNext = 1, NSSelectingPrevious = 2
};
@class NSOrthography;

@interface NSMenuItem (FerryElectron)
@property BOOL allowsKeyEquivalentWhenHidden;
@property BOOL allowsAutomaticKeyEquivalentLocalization;
@property BOOL allowsAutomaticKeyEquivalentMirroring;
@property (class) BOOL usesUserKeyEquivalents;          /* none can be set: NO */
@property (readonly) NSString *userKeyEquivalent;       /* "" */
@property (strong) NSImage *onStateImage;
@property (strong) NSImage *offStateImage;
@property (strong) NSImage *mixedStateImage;
@end

typedef NS_OPTIONS(NSUInteger, NSCursorFrameResizePosition) {
    NSCursorFrameResizePositionTop = 1 << 0, NSCursorFrameResizePositionLeft = 1 << 1,
    NSCursorFrameResizePositionBottom = 1 << 2, NSCursorFrameResizePositionRight = 1 << 3,
    NSCursorFrameResizePositionTopLeft = (1 << 0) | (1 << 1), NSCursorFrameResizePositionTopRight = (1 << 0) | (1 << 3),
    NSCursorFrameResizePositionBottomLeft = (1 << 2) | (1 << 1),
    NSCursorFrameResizePositionBottomRight = (1 << 2) | (1 << 3),
};
typedef NS_OPTIONS(NSUInteger, NSCursorFrameResizeDirections) {
    NSCursorFrameResizeDirectionsInward = 1 << 0, NSCursorFrameResizeDirectionsOutward = 1 << 1,
    NSCursorFrameResizeDirectionsAll = 3,
};
@interface NSCursor (FerryElectron)
@property (class, readonly, retain) NSCursor *zoomInCursor;
@property (class, readonly, retain) NSCursor *zoomOutCursor;
@property (class, readonly, retain) NSCursor *columnResizeCursor;
@property (class, readonly, retain) NSCursor *rowResizeCursor;
+ (NSCursor *)columnResizeCursorInDirections:(NSUInteger)directions;
+ (NSCursor *)rowResizeCursorInDirections:(NSUInteger)directions;
+ (NSCursor *)frameResizeCursorFromPosition:(NSCursorFrameResizePosition)position
                               inDirections:(NSCursorFrameResizeDirections)directions;
@end

@interface NSWindow (FerryElectron)
/* Ferry shows each tab as a window of its own */
- (void)addTabbedWindow:(NSWindow *)window ordered:(NSWindowOrderingMode)ordered;
@property (readonly) BOOL isOnActiveSpace;   /* freemac has one space: when visible */
@property (readonly) NSSelectionDirection keyViewSelectionDirection;
- (NSTimeInterval)animationResizeTime:(NSRect)newFrame;
@property NSInteger orderedIndex;
@end

@interface NSResponder (FerryElectronGestures)
- (void)beginGestureWithEvent:(NSEvent *)event;
- (void)endGestureWithEvent:(NSEvent *)event;
@end

/* Ferry's spell checker has no dictionaries: it finds nothing to correct */
@interface NSSpellChecker (FerryElectron)
@property (class, readonly) BOOL automaticTextReplacementEnabled, automaticSpellingCorrectionEnabled,
    automaticQuoteSubstitutionEnabled, automaticDashSubstitutionEnabled, automaticCapitalizationEnabled,
    automaticPeriodSubstitutionEnabled, automaticTextCompletionEnabled, automaticInlinePredictionEnabled;
+ (BOOL)isAutomaticTextReplacementEnabled;
+ (BOOL)isAutomaticSpellingCorrectionEnabled;
+ (BOOL)isAutomaticQuoteSubstitutionEnabled;
+ (BOOL)isAutomaticDashSubstitutionEnabled;
+ (BOOL)isAutomaticCapitalizationEnabled;
+ (BOOL)isAutomaticPeriodSubstitutionEnabled;
+ (BOOL)isAutomaticTextCompletionEnabled;
+ (BOOL)isAutomaticInlinePredictionEnabled;
- (NSArray *)checkString:(NSString *)stringToCheck range:(NSRange)range types:(NSTextCheckingTypes)checkingTypes
                 options:(NSDictionary *)options inSpellDocumentWithTag:(NSInteger)tag
             orthography:(NSOrthography **)orthography wordCount:(NSInteger *)wordCount;
- (NSInteger)requestCheckingOfString:(NSString *)stringToCheck range:(NSRange)range types:(NSTextCheckingTypes)checkingTypes
                             options:(NSDictionary *)options inSpellDocumentWithTag:(NSInteger)tag
                   completionHandler:(void (^)(NSInteger sequenceNumber, NSArray *results, NSOrthography *orthography,
                                               NSInteger wordCount))completionHandler;
- (NSInteger)requestCandidatesForSelectedRange:(NSRange)selectedRange inString:(NSString *)stringToCheck
                                         types:(NSTextCheckingTypes)checkingTypes options:(NSDictionary *)options
                        inSpellDocumentWithTag:(NSInteger)tag
                             completionHandler:(void (^)(NSInteger sequenceNumber, NSArray *candidates))completionHandler;
- (void)showCorrectionIndicatorOfType:(NSInteger)type primaryString:(NSString *)primaryString
                   alternativeStrings:(NSArray *)alternativeStrings forStringInRect:(NSRect)rect view:(NSView *)view
                    completionHandler:(void (^)(NSString *acceptedString))completionBlock;
- (void)dismissCorrectionIndicatorForView:(NSView *)view;
- (BOOL)preventsAutocorrectionBeforeString:(NSString *)string language:(NSString *)language;
- (void)recordResponse:(NSInteger)response toCorrection:(NSString *)correction forWord:(NSString *)word
              language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag;
- (NSString *)correctionForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language
              inSpellDocumentWithTag:(NSInteger)tag;
@end
#endif
