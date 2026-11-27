/* SPDX-License-Identifier: GPL-3.0-or-later
 * AppKit calls that Chromium and Electron make as an app starts and builds
 * its menus and windows (freemac 1.265, Ferry 0.88.0; first seen in
 * Obsidian), from Apple's public AppKit documentation of each:
 *
 * - NSMenuItem: whether its key equivalent works while it is hidden, the
 *   user's own key equivalents (none can be set on freemac), and the images
 *   for its on, off and mixed states.
 * - NSWindow: tabbing a window into another's tab group (Ferry shows each
 *   tab as its own window), whether it is on the space being shown (freemac
 *   shows every window on one space), the title bar's layout direction, the
 *   direction keyboard focus is moving in, and the resize animation's time.
 * - NSSpellChecker: checking a string all at once, or in the background;
 *   Ferry's spell checker has no dictionaries, so it finds nothing to
 *   correct, as a Mac with none installed would.
 * - NSResponder: gesture start and end, which nothing sends here.
 */
#import "AInternal.h"
#import <objc/runtime.h>

/* ---- menu items ---------------------------------------------------------------------- */

static char key_hidden, key_on_image, key_off_image, key_mixed_image;

@implementation NSMenuItem (FerryElectron)
- (BOOL)allowsKeyEquivalentWhenHidden { return [objc_getAssociatedObject(self, &key_hidden) boolValue]; }
- (void)setAllowsKeyEquivalentWhenHidden:(BOOL)allows
{
    objc_setAssociatedObject(self, &key_hidden, allows ? @YES : nil, OBJC_ASSOCIATION_RETAIN);
}
- (BOOL)allowsAutomaticKeyEquivalentLocalization { return YES; }
- (void)setAllowsAutomaticKeyEquivalentLocalization:(BOOL)allows {}
- (BOOL)allowsAutomaticKeyEquivalentMirroring { return YES; }
- (void)setAllowsAutomaticKeyEquivalentMirroring:(BOOL)allows {}
+ (BOOL)usesUserKeyEquivalents { return NO; }
+ (void)setUsesUserKeyEquivalents:(BOOL)flag {}
- (NSString *)userKeyEquivalent { return @""; }
- (NSImage *)onStateImage { return objc_getAssociatedObject(self, &key_on_image); }
- (void)setOnStateImage:(NSImage *)image { objc_setAssociatedObject(self, &key_on_image, image, OBJC_ASSOCIATION_RETAIN); }
- (NSImage *)offStateImage { return objc_getAssociatedObject(self, &key_off_image); }
- (void)setOffStateImage:(NSImage *)image { objc_setAssociatedObject(self, &key_off_image, image, OBJC_ASSOCIATION_RETAIN); }
- (NSImage *)mixedStateImage { return objc_getAssociatedObject(self, &key_mixed_image); }
- (void)setMixedStateImage:(NSImage *)image
{
    objc_setAssociatedObject(self, &key_mixed_image, image, OBJC_ASSOCIATION_RETAIN);
}
@end

/* ---- windows ------------------------------------------------------------------------------ */

@implementation NSWindow (FerryElectron)
- (void)addTabbedWindow:(NSWindow *)window ordered:(NSWindowOrderingMode)ordered
{
    if (window && window != self)
        [window makeKeyAndOrderFront:nil];
}
- (BOOL)isOnActiveSpace { return [self isVisible]; }
- (NSSelectionDirection)keyViewSelectionDirection { return NSDirectSelection; }
- (NSTimeInterval)animationResizeTime:(NSRect)newFrame { return 0.2; }
- (NSInteger)orderedIndex
{
    NSUInteger i = [[NSApp orderedWindows] indexOfObjectIdenticalTo:self];
    return i == NSNotFound ? -1 : (NSInteger)i;
}
- (void)setOrderedIndex:(NSInteger)index {}
@end

@implementation NSResponder (FerryElectronGestures)
- (void)beginGestureWithEvent:(NSEvent *)event {}
- (void)endGestureWithEvent:(NSEvent *)event {}
@end

/* ---- the spell checker -------------------------------------------------------------------- */

static NSInteger spell_sequence;

@implementation NSSpellChecker (FerryElectron)
- (NSArray *)checkString:(NSString *)stringToCheck range:(NSRange)range types:(NSTextCheckingTypes)checkingTypes
                 options:(NSDictionary *)options inSpellDocumentWithTag:(NSInteger)tag
             orthography:(NSOrthography **)orthography wordCount:(NSInteger *)wordCount
{
    if (orthography)
        *orthography = nil;
    if (wordCount)
        *wordCount = [self countWordsInString:[stringToCheck substringWithRange:range] language:nil];
    return @[];
}
- (NSInteger)requestCheckingOfString:(NSString *)stringToCheck range:(NSRange)range types:(NSTextCheckingTypes)checkingTypes
                             options:(NSDictionary *)options inSpellDocumentWithTag:(NSInteger)tag
                   completionHandler:(void (^)(NSInteger, NSArray *, NSOrthography *, NSInteger))completionHandler
{
    NSInteger seq = ++spell_sequence;
    NSInteger words = [self countWordsInString:[stringToCheck substringWithRange:range] language:nil];
    if (completionHandler) {
        void (^handler)(NSInteger, NSArray *, NSOrthography *, NSInteger) = [completionHandler copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(seq, @[], nil, words);
            [handler release];
        });
    }
    return seq;
}
- (NSInteger)requestCandidatesForSelectedRange:(NSRange)selectedRange inString:(NSString *)stringToCheck
                                         types:(NSTextCheckingTypes)checkingTypes options:(NSDictionary *)options
                        inSpellDocumentWithTag:(NSInteger)tag
                             completionHandler:(void (^)(NSInteger, NSArray *))completionHandler
{
    NSInteger seq = ++spell_sequence;
    if (completionHandler) {
        void (^handler)(NSInteger, NSArray *) = [completionHandler copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(seq, @[]);
            [handler release];
        });
    }
    return seq;
}
- (void)showCorrectionIndicatorOfType:(NSInteger)type primaryString:(NSString *)primaryString
                   alternativeStrings:(NSArray *)alternativeStrings forStringInRect:(NSRect)rect view:(NSView *)view
                    completionHandler:(void (^)(NSString *))completionBlock
{
}
- (void)dismissCorrectionIndicatorForView:(NSView *)view {}
- (BOOL)preventsAutocorrectionBeforeString:(NSString *)string language:(NSString *)language { return NO; }
- (void)recordResponse:(NSInteger)response toCorrection:(NSString *)correction forWord:(NSString *)word
              language:(NSString *)language inSpellDocumentWithTag:(NSInteger)tag
{
}
- (NSString *)correctionForWordRange:(NSRange)range inString:(NSString *)string language:(NSString *)language
              inSpellDocumentWithTag:(NSInteger)tag
{
    return nil;
}
@end
