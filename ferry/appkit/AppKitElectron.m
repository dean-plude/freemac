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
/* The system's typing settings (Keyboard > Text Input on a Mac), which an
 * app asks before it fixes up what's typed. Ferry corrects nothing as you
 * type, so each is off (freemac 1.266). */
+ (BOOL)isAutomaticTextReplacementEnabled { return NO; }
+ (BOOL)isAutomaticSpellingCorrectionEnabled { return NO; }
+ (BOOL)isAutomaticQuoteSubstitutionEnabled { return NO; }
+ (BOOL)isAutomaticDashSubstitutionEnabled { return NO; }
+ (BOOL)isAutomaticCapitalizationEnabled { return NO; }
+ (BOOL)isAutomaticPeriodSubstitutionEnabled { return NO; }
+ (BOOL)isAutomaticTextCompletionEnabled { return NO; }
+ (BOOL)isAutomaticInlinePredictionEnabled { return NO; }
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

/* ---- window server calls Chromium declares in its own source (freemac 1.266) ---------- */

/* Chromium's helpers cut themselves off from the window server, and its
 * windows set their alpha, transform, warp and which part of them screen
 * capture leaves out through private calls that it declares itself. Ferry
 * has one connection and draws windows its own way, so each is accepted
 * and changes nothing (kCGErrorSuccess). A region is the rectangle it was
 * made from, kept in a CF object the caller releases. */
int32_t CGSSetDenyWindowServerConnections(bool deny) { return 0; }
int32_t CGSSetWindowAlpha(int connection, int window, float alpha) { return 0; }
int32_t CGSSetWindowTransform(int connection, int window, CGAffineTransform transform) { return 0; }
int32_t CGSSetWindowWarp(int connection, int window, int width, int height, const void *mesh) { return 0; }
int32_t CGSSetWindowCaptureExcludeShape(int connection, int window, CFTypeRef region) { return 0; }
int _CGSDefaultConnection(void) { return 1; }
CFTypeRef CGRegionCreateWithRect(CGRect rect) { return (CFTypeRef)[[NSValue valueWithRect:NSRectFromCGRect(rect)] retain]; }

/* ---- services and events --------------------------------------------------------------- */

/* Running a service from the Services menu: freemac has no services, so
 * none runs (Apple's documentation: NO when the service couldn't be run). */
BOOL NSPerformService(NSString *itemName, NSPasteboard *pboard) { return NO; }

/* An event from data that CGEventCreateData made: Ferry's events aren't
 * flattened to data, so there is none to make one from. */
CGEventRef CGEventCreateFromData(CFAllocatorRef allocator, CFDataRef data) { return NULL; }

/* ---- captions (MediaAccessibility) ----------------------------------------------------- */

/* How the user wants captions on video drawn: freemac has no caption
 * settings, so the Mac's defaults, white text on black, and the video's own
 * style wherever it has one (kMACaptionAppearanceBehaviorUseContentIfAvailable). */
static void caption_behavior(int *behavior)
{
    if (behavior)
        *behavior = 1;
}
CGColorRef MACaptionAppearanceCopyForegroundColor(int domain, int *behavior)
{
    caption_behavior(behavior);
    return CGColorCreateGenericRGB(1, 1, 1, 1);
}
CGColorRef MACaptionAppearanceCopyBackgroundColor(int domain, int *behavior)
{
    caption_behavior(behavior);
    return CGColorCreateGenericRGB(0, 0, 0, 1);
}
CGColorRef MACaptionAppearanceCopyWindowColor(int domain, int *behavior)
{
    caption_behavior(behavior);
    return CGColorCreateGenericRGB(0, 0, 0, 1);
}
CGFloat MACaptionAppearanceGetForegroundOpacity(int domain, int *behavior) { caption_behavior(behavior); return 1; }
CGFloat MACaptionAppearanceGetBackgroundOpacity(int domain, int *behavior) { caption_behavior(behavior); return 0.8; }
CGFloat MACaptionAppearanceGetWindowOpacity(int domain, int *behavior) { caption_behavior(behavior); return 0; }
CGFloat MACaptionAppearanceGetWindowRoundedCornerRadius(int domain, int *behavior) { caption_behavior(behavior); return 0; }
CGFloat MACaptionAppearanceGetRelativeCharacterSize(int domain, int *behavior) { caption_behavior(behavior); return 1; }
int MACaptionAppearanceGetTextEdgeStyle(int domain, int *behavior) { caption_behavior(behavior); return 1; /* none */ }
CTFontDescriptorRef MACaptionAppearanceCopyFontDescriptorForStyle(int domain, int *behavior, int style)
{
    caption_behavior(behavior);
    return CTFontDescriptorCreateWithNameAndSize(CFSTR("Helvetica"), 0);
}
