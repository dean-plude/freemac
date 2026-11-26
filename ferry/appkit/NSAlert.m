/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSAlert, the NSRunAlertPanel family and error
 * presentation (NSResponder's presentError: and its sheet form). Ferry's
 * own code, written from Apple's public NSAlert and error-handling
 * documentation and from how an alert looks on a Mac; no Apple code,
 * artwork or headers were used. An alert is a panel of Ferry's own views:
 * the icon, the message in bold, the informative text, the accessory view
 * and the suppression check box, all centred, then the buttons (one
 * across, two side by side with the first on the right, three or more
 * stacked with the first on top). The first button answers Return, one
 * titled Cancel answers Escape, one titled Don't Save answers Command-D.
 * runModal runs a nested event loop; a sheet is shown inside its window
 * (see NSWindow.m). With no display, FERRY_ALERT_ANSWER (a button's title
 * or its number from 1) answers an alert at once, for scripted runs.
 * Built without ARC. */
#import "AInternal.h"

/* The panel's content: top to bottom, so flipped. */
@interface AAlertView : NSView
@end
@implementation AAlertView
- (BOOL)isFlipped { return YES; }
@end

@interface NSAlert ()
- (void)_buttonPressed:(NSButton *)button;
@end

static const CGFloat kPad = 20, kIcon = 64, kButtonH = 28;

/* The answer FERRY_ALERT_ANSWER gives, when there's no display. */
static BOOL scripted_answer(NSArray *buttons, NSModalResponse *code)
{
    if (ADisplayAvailable())
        return NO;
    const char *env = getenv("FERRY_ALERT_ANSWER");
    if (!env || !*env || ![buttons count])
        return NO;
    NSString *want = [[NSString stringWithUTF8String:env] stringByReplacingOccurrencesOfString:@"’"
                                                                                     withString:@"'"];
    NSInteger n = [want integerValue];
    if (n >= 1 && (NSUInteger)n <= [buttons count] && [[NSString stringWithFormat:@"%ld", (long)n] isEqualToString:want]) {
        *code = [buttons[n - 1] tag];
        return YES;
    }
    for (NSButton *b in buttons) {
        NSString *t = [[b title] stringByReplacingOccurrencesOfString:@"’" withString:@"'"];
        if ([t caseInsensitiveCompare:want] == NSOrderedSame) {
            *code = [b tag];
            return YES;
        }
    }
    return NO;
}

static NSString *plain_apostrophe(NSString *s) { return [s stringByReplacingOccurrencesOfString:@"’" withString:@"'"]; }

@implementation NSAlert {
    NSString *_message, *_informative, *_helpAnchor;
    NSImage *_icon;
    NSAlertStyle _style;
    BOOL _showsHelp, _showsSuppression, _oldReturns, _runningModal;
    id _delegate;
    NSMutableArray *_buttons;
    NSButton *_suppression, *_helpButton;
    NSView *_accessory;
    NSPanel *_window;
    void (^_sheetHandler)(NSModalResponse);
}

- (instancetype)init
{
    if ((self = [super init])) {
        _message = @"Alert";
        _informative = @"";
        _buttons = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_message release];
    [_informative release];
    [_helpAnchor release];
    [_icon release];
    [_buttons release];
    [_suppression release];
    [_helpButton release];
    [_accessory release];
    [_window release];
    [_sheetHandler release];
    [super dealloc];
}

+ (NSAlert *)alertWithError:(NSError *)error
{
    NSAlert *a = [[[self alloc] init] autorelease];
    [a setAlertStyle:NSAlertStyleWarning];
    [a setMessageText:[error localizedDescription] ?: @"An error occurred."];
    NSString *suggestion = [error localizedRecoverySuggestion];
    if (!suggestion)
        suggestion = [error localizedFailureReason];
    [a setInformativeText:suggestion ?: @""];
    NSArray *options = [error localizedRecoveryOptions];
    if ([options count]) {
        for (NSString *o in options)
            [a addButtonWithTitle:o];
    } else {
        [a addButtonWithTitle:@"OK"];
    }
    return a;
}

+ (NSAlert *)alertWithMessageText:(NSString *)message defaultButton:(NSString *)def
                  alternateButton:(NSString *)alt otherButton:(NSString *)other
        informativeTextWithFormat:(NSString *)format, ...
{
    NSAlert *a = [[[self alloc] init] autorelease];
    [a setMessageText:message ?: @""];
    if (format) {
        va_list ap;
        va_start(ap, format);
        [a setInformativeText:[[[NSString alloc] initWithFormat:format arguments:ap] autorelease]];
        va_end(ap);
    }
    /* the return codes of the old panels */
    [[a addButtonWithTitle:def ?: @"OK"] setTag:NSAlertDefaultReturn];
    if (alt)
        [[a addButtonWithTitle:alt] setTag:NSAlertAlternateReturn];
    if (other)
        [[a addButtonWithTitle:other] setTag:NSAlertOtherReturn];
    a->_oldReturns = YES;
    return a;
}

- (NSString *)messageText { return _message; }
- (void)setMessageText:(NSString *)s
{
    s = [s copy] ?: @"";
    [_message release];
    _message = s;
}
- (NSString *)informativeText { return _informative; }
- (void)setInformativeText:(NSString *)s
{
    s = [s copy] ?: @"";
    [_informative release];
    _informative = s;
}
- (NSImage *)icon { return _icon; }
- (void)setIcon:(NSImage *)icon
{
    [icon retain];
    [_icon release];
    _icon = icon;
}
- (NSAlertStyle)alertStyle { return _style; }
- (void)setAlertStyle:(NSAlertStyle)style { _style = style; }
- (BOOL)showsHelp { return _showsHelp; }
- (void)setShowsHelp:(BOOL)flag { _showsHelp = flag; }
- (NSString *)helpAnchor { return _helpAnchor; }
- (void)setHelpAnchor:(NSString *)s
{
    s = [s copy];
    [_helpAnchor release];
    _helpAnchor = s;
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (NSArray *)buttons { return [[_buttons copy] autorelease]; }
- (BOOL)showsSuppressionButton { return _showsSuppression; }
- (void)setShowsSuppressionButton:(BOOL)flag { _showsSuppression = flag; }
- (NSView *)accessoryView { return _accessory; }
- (void)setAccessoryView:(NSView *)v
{
    [v retain];
    [_accessory release];
    _accessory = v;
}

- (NSButton *)suppressionButton
{
    if (!_suppression)
        _suppression = [[NSButton checkboxWithTitle:@"Do not show this message again" target:nil action:NULL] retain];
    return _suppression;
}

/* Return for the first button, Escape for Cancel, Command-D for Don't Save. */
- (NSButton *)addButtonWithTitle:(NSString *)title
{
    NSButton *b = [NSButton buttonWithTitle:title ?: @"" target:self action:@selector(_buttonPressed:)];
    [b setBezelStyle:NSBezelStyleRounded];
    [b setTag:NSAlertFirstButtonReturn + (NSInteger)[_buttons count]];
    NSString *plain = plain_apostrophe(title ?: @"");
    if (![_buttons count]) {
        [b setKeyEquivalent:@"\r"];
    } else if ([plain caseInsensitiveCompare:@"Cancel"] == NSOrderedSame) {
        [b setKeyEquivalent:@"\e"];
    } else if ([plain caseInsensitiveCompare:@"Don't Save"] == NSOrderedSame) {
        [b setKeyEquivalent:@"d"];
        [b setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    }
    [_buttons addObject:b];
    return b;
}

/* The app's icon; a critical alert shows the caution sign with the app's
 * icon on it. */
- (NSImage *)_shownIcon
{
    NSImage *app = _icon ?: [NSApp applicationIconImage] ?: [NSImage imageNamed:NSImageNameApplicationIcon];
    if (_style != NSAlertStyleCritical || _icon)
        return app;
    NSImage *caution = [NSImage imageNamed:NSImageNameCaution];
    if (!caution)
        return app;
    return [NSImage imageWithSize:NSMakeSize(kIcon, kIcon) flipped:NO drawingHandler:^BOOL(NSRect r) {
        [caution drawInRect:r fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        [app drawInRect:NSMakeRect(NSMaxX(r) - r.size.width / 2, 0, r.size.width / 2, r.size.height / 2)
               fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        return YES;
    }];
}

static CGFloat text_height(NSString *s, NSFont *font, CGFloat width)
{
    if (![s length])
        return 0;
    NSRect r = [s boundingRectWithSize:NSMakeSize(width - 4, 1e6) options:NSStringDrawingUsesLineFragmentOrigin
                            attributes:@{NSFontAttributeName : font}];
    return ceil(r.size.height) + 2;
}

static NSTextField *label(NSString *s, NSFont *font, CGFloat x, CGFloat y, CGFloat w, CGFloat h)
{
    NSTextField *f = [NSTextField wrappingLabelWithString:s];
    [f setFont:font];
    [f setAlignment:NSTextAlignmentCenter];
    [f setFrame:NSMakeRect(x, y, w, h)];
    return f;
}

- (NSWindow *)window
{
    if (!_window) {
        _window = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 260, 160) styleMask:NSWindowStyleMaskBorderless
                                               backing:NSBackingStoreBuffered defer:YES];
        [_window setReleasedWhenClosed:NO];
        [_window setTitle:@""];
    }
    return _window;
}

/* Places everything in the panel and sizes it. */
- (void)layout
{
    if (![_buttons count])
        [self addButtonWithTitle:@"OK"];
    NSWindow *w = [self window];
    CGFloat width = 260;
    if (_accessory)
        width = fmax(width, [_accessory frame].size.width + 2 * kPad);
    CGFloat inner = width - 2 * kPad;
    /* two buttons sit side by side when both titles fit */
    BOOL sideBySide = [_buttons count] == 2;
    if (sideBySide)
        for (NSButton *b in _buttons)
            if ([b intrinsicContentSize].width > (inner - 8) / 2 + 12)
                sideBySide = NO;

    AAlertView *v = [[[AAlertView alloc] initWithFrame:NSMakeRect(0, 0, width, 100)] autorelease];
    CGFloat y = kPad;
    NSImageView *iv = [NSImageView imageViewWithImage:[self _shownIcon]];
    [iv setImageScaling:NSImageScaleProportionallyUpOrDown];
    [iv setFrame:NSMakeRect(floor((width - kIcon) / 2), y, kIcon, kIcon)];
    [v addSubview:iv];
    y += kIcon + 12;

    NSFont *bold = [NSFont boldSystemFontOfSize:13], *small = [NSFont systemFontOfSize:11];
    CGFloat h = text_height(_message, bold, inner);
    if (h > 0) {
        [v addSubview:label(_message, bold, kPad, y, inner, h)];
        y += h;
    }
    h = text_height(_informative, small, inner);
    if (h > 0) {
        y += 6;
        [v addSubview:label(_informative, small, kPad, y, inner, h)];
        y += h;
    }
    if (_accessory) {
        y += 12;
        NSSize s = [_accessory frame].size;
        [_accessory setFrameOrigin:NSMakePoint(floor((width - s.width) / 2), y)];
        [v addSubview:_accessory];
        y += s.height;
    }
    if (_showsSuppression) {
        y += 12;
        NSButton *c = [self suppressionButton];
        [c sizeToFit];
        NSSize s = [c frame].size;
        [c setFrame:NSMakeRect(kPad, y, fmin(s.width, inner), s.height)];
        [v addSubview:c];
        y += s.height;
    }
    y += 16;
    /* a button's frame is 6 points wider than its bezel on each side and
     * 3 taller above and below */
    if ([_buttons count] == 1 || !sideBySide) {
        for (NSButton *b in _buttons) {
            [b setFrame:NSMakeRect(kPad - 6, y - 3, inner + 12, kButtonH)];
            [v addSubview:b];
            y += 22 + 8;
        }
        y -= 8;
    } else {
        CGFloat half = (inner - 8) / 2;
        [_buttons[0] setFrame:NSMakeRect(kPad + half + 8 - 6, y - 3, half + 12, kButtonH)];
        [_buttons[1] setFrame:NSMakeRect(kPad - 6, y - 3, half + 12, kButtonH)];
        [v addSubview:_buttons[0]];
        [v addSubview:_buttons[1]];
        y += 22;
    }
    if (_showsHelp) {
        y += 10;
        if (!_helpButton) {
            _helpButton = [[NSButton alloc] initWithFrame:NSZeroRect];
            [_helpButton setBezelStyle:NSBezelStyleHelpButton];
            [_helpButton setTitle:@""];
            [_helpButton setTarget:self];
            [_helpButton setAction:@selector(_help:)];
        }
        [_helpButton setFrame:NSMakeRect(kPad - 2, y, 25, 25)];
        [v addSubview:_helpButton];
        y += 25;
    }
    y += kPad;
    [v setFrameSize:NSMakeSize(width, y)];
    [w setContentView:v];
    [w setContentSize:NSMakeSize(width, y)];
    [w setInitialFirstResponder:nil];
    [w makeFirstResponder:w];
}

- (void)_help:(id)sender
{
    if ([_delegate respondsToSelector:@selector(alertShowHelp:)] && [_delegate alertShowHelp:self])
        return;
    AWarnOnce("Help Book anchors (an alert's help button)");
}

- (void)_buttonPressed:(NSButton *)button
{
    NSModalResponse code = [button tag];
    if (_runningModal) {
        [NSApp stopModalWithCode:code];
    } else if ([_window sheetParent]) {
        [[_window sheetParent] endSheet:_window returnCode:code];
    }
}

- (NSModalResponse)runModal
{
    [self layout];
    NSWindow *w = [self window];
    /* centred a third of the way down the main window, or the screen, and
     * kept on the screen: a tall alert (ShiftIt's, with its picture) moves
     * down rather than losing its top (1.229); a main window that is
     * hidden, off the screen or smaller than the alert counts for nothing,
     * and the alert goes on the screen (VLC asks its first-run question over
     * its 84-point-high window, freemac 1.NEXT) */
    NSWindow *over = [NSApp mainWindow];
    NSRect f = [w frame], screen = [[NSScreen mainScreen] visibleFrame];
    if (![over isVisible] || !NSContainsRect(NSInsetRect(screen, -1, -1), [over frame]) ||
        NSWidth([over frame]) < f.size.width || NSHeight([over frame]) < f.size.height)
        over = nil;
    NSRect base = over ? [over frame] : screen;
    NSPoint at = NSMakePoint(floor(NSMidX(base) - f.size.width / 2),
                             floor(NSMaxY(base) - (NSMaxY(base) - NSMinY(base)) / 3 - f.size.height / 2));
    at.x = fmax(NSMinX(screen), fmin(at.x, NSMaxX(screen) - f.size.width));
    at.y = fmin(fmax(at.y, NSMinY(screen)), NSMaxY(screen) - f.size.height); /* the top wins */
    [w setFrameOrigin:at];
    NSModalResponse code;
    if (scripted_answer(_buttons, &code))
        return code;
    [self retain];
    _runningModal = YES;
    code = [NSApp runModalForWindow:w];
    _runningModal = NO;
    [w orderOut:nil];
    [self autorelease];
    return code;
}

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler
{
    if (!window) {
        NSModalResponse r = [self runModal];
        if (handler)
            handler(r);
        return;
    }
    [self layout];
    [self retain];   /* until the sheet ends */
    void (^h)(NSModalResponse) = [handler copy];
    NSWindow *sheet = [self window];
    [window beginSheet:sheet completionHandler:^(NSModalResponse r) {
        if (h)
            h(r);
        [h release];
        [self autorelease];
    }];
    NSModalResponse code;
    if (scripted_answer(_buttons, &code)) {
        /* answered when the loop next turns, as a person would answer */
        [self performSelector:@selector(_answerSheet:) withObject:@(code) afterDelay:0];
    }
}

- (void)_answerSheet:(NSNumber *)code
{
    if ([_window sheetParent])
        [[_window sheetParent] endSheet:_window returnCode:[code integerValue]];
}

- (void)beginSheetModalForWindow:(NSWindow *)window modalDelegate:(id)delegate didEndSelector:(SEL)selector
                     contextInfo:(void *)context
{
    [self beginSheetModalForWindow:window completionHandler:^(NSModalResponse r) {
        if (delegate && selector)
            ((void (*)(id, SEL, id, NSInteger, void *))objc_msgSend)(delegate, selector, self, r, context);
    }];
}
@end

/* ---- the old panels -------------------------------------------------------------------- */

static NSInteger run_panel(NSAlertStyle style, NSString *title, NSString *format, NSString *def, NSString *alt,
                           NSString *other, va_list ap)
{
    NSString *text = format ? [[[NSString alloc] initWithFormat:format arguments:ap] autorelease] : @"";
    NSAlert *a = [NSAlert alertWithMessageText:title defaultButton:def alternateButton:alt otherButton:other
                     informativeTextWithFormat:@"%@", text];
    [a setAlertStyle:style];
    return [a runModal];
}

NSInteger NSRunAlertPanel(NSString *title, NSString *format, NSString *def, NSString *alt, NSString *other, ...)
{
    va_list ap;
    va_start(ap, other);
    NSInteger r = run_panel(NSAlertStyleWarning, title, format, def, alt, other, ap);
    va_end(ap);
    return r;
}
NSInteger NSRunInformationalAlertPanel(NSString *title, NSString *format, NSString *def, NSString *alt,
                                       NSString *other, ...)
{
    va_list ap;
    va_start(ap, other);
    NSInteger r = run_panel(NSAlertStyleInformational, title, format, def, alt, other, ap);
    va_end(ap);
    return r;
}
NSInteger NSRunCriticalAlertPanel(NSString *title, NSString *format, NSString *def, NSString *alt, NSString *other,
                                  ...)
{
    va_list ap;
    va_start(ap, other);
    NSInteger r = run_panel(NSAlertStyleCritical, title, format, def, alt, other, ap);
    va_end(ap);
    return r;
}

/* ---- presenting errors -------------------------------------------------------------------
 * Up the responder chain, each responder may change the error
 * (willPresentError:), and the application shows it. */

@implementation NSResponder (NSErrorPresentation)
- (NSError *)willPresentError:(NSError *)error { return error; }
- (BOOL)presentError:(NSError *)error
{
    error = [self willPresentError:error];
    NSResponder *next = [self nextResponder];
    return next ? [next presentError:error] : [NSApp presentError:error];
}
- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate
    didPresentSelector:(SEL)selector contextInfo:(void *)context
{
    error = [self willPresentError:error];
    NSResponder *next = [self nextResponder];
    if (next)
        [next presentError:error modalForWindow:window delegate:delegate didPresentSelector:selector
                 contextInfo:context];
    else
        [NSApp presentError:error modalForWindow:window delegate:delegate didPresentSelector:selector
                contextInfo:context];
}
@end
