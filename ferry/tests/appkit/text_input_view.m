/* SPDX-License-Identifier: GPL-3.0-or-later
 * A view that takes typing the way GPUI (Zed's toolkit) does, with no
 * display: it answers NO to acceptsFirstResponder yet is made the first
 * responder, sends its keys to -interpretKeyEvents:, and takes text through
 * NSTextInputClient's -insertText:replacementRange:. With Command held, a
 * key types nothing. Written from Apple's NSResponder, NSWindow and
 * NSTextInputClient documentation (freemac 1.268). */
#import <Cocoa/Cocoa.h>

@interface GPUILikeView : NSView <NSTextInputClient>
@property (nonatomic, strong) NSMutableString *typed;
@property (nonatomic) NSRange lastRange;
@property (nonatomic) int commands;
@end
@implementation GPUILikeView
- (BOOL)acceptsFirstResponder { return NO; }
- (void)keyDown:(NSEvent *)event { [self interpretKeyEvents:@[ event ]]; }
- (void)insertText:(id)string replacementRange:(NSRange)range
{
    NSString *s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    [self.typed appendString:s];
    self.lastRange = range;
}
- (void)doCommandBySelector:(SEL)selector { self.commands++; }
- (void)setMarkedText:(id)s selectedRange:(NSRange)a replacementRange:(NSRange)b {}
- (void)unmarkText {}
- (NSRange)selectedRange { return NSMakeRange(self.typed.length, 0); }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return NO; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)a { return nil; }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a { return NSZeroRect; }
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return 0; }
@end

static void key(NSWindow *w, NSString *s, NSEventModifierFlags flags)
{
    [w sendEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                              windowNumber:[w windowNumber] context:nil characters:s charactersIgnoringModifiers:s
                                 isARepeat:NO keyCode:0]];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                  styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        GPUILikeView *v = [[GPUILikeView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        v.typed = [NSMutableString string];
        [w setContentView:v];
        BOOL made = [w makeFirstResponder:v];
        printf("made first responder though it doesn't accept: %s, is it: %s\n", made ? "yes" : "no",
               [w firstResponder] == v ? "yes" : "no");
        key(w, @"h", 0);
        key(w, @"i", 0);
        key(w, @";", 0);
        key(w, @"(", NSEventModifierFlagShift);
        printf("typed: \"%s\", through insertText:replacementRange: with no range: %s\n", v.typed.UTF8String,
               v.lastRange.location == NSNotFound ? "yes" : "no");
        key(w, @"s", NSEventModifierFlagCommand);
        printf("Command-S types nothing: %s, a command instead: %s\n", [v.typed isEqualToString:@"hi;("] ? "yes" : "no",
               v.commands > 0 ? "yes" : "no");
    }
    return 0;
}
