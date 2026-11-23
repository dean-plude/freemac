/* SPDX-License-Identifier: GPL-3.0-or-later
 * Scroll views, text views, progress indicators and boxes, with no display:
 * how a scroll view lays out its clip view and scrollers, scrolling by
 * point, by scroller and by rectangle, a text view that wraps, grows and
 * is edited from the keyboard's commands, RTF and HTML read into
 * attributed strings and RTF written back, and the text drawn. */
#import <Cocoa/Cocoa.h>

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}

@interface Watcher : NSObject <NSTextViewDelegate>
@property int changes;
@end
@implementation Watcher
- (void)textDidChange:(NSNotification *)n { self.changes++; }
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];

        /* a tall document in a scroll view with both scrollers */
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        [sv setHasVerticalScroller:YES];
        [sv setHasHorizontalScroller:YES];
        [sv setBorderType:NSBezelBorder];
        NSView *doc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 1000)];
        [sv setDocumentView:doc];
        [[w contentView] addSubview:sv];
        rect("clip view", [[sv contentView] frame]);
        rect("vertical scroller", [[sv verticalScroller] frame]);
        rect("horizontal scroller", [[sv horizontalScroller] frame]);
        printf("content size %.0fx%.0f, frame for it %.0fx%.0f\n", [sv contentSize].width, [sv contentSize].height,
               [NSScrollView frameSizeForContentSize:[sv contentSize] horizontalScrollerClass:[NSScroller class]
                               verticalScrollerClass:[NSScroller class] borderType:NSBezelBorder
                                         controlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy].width,
               [NSScrollView frameSizeForContentSize:[sv contentSize] horizontalScrollerClass:[NSScroller class]
                               verticalScrollerClass:[NSScroller class] borderType:NSBezelBorder
                                         controlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy].height);
        /* an unflipped document starts at its top */
        rect("visible at first", [sv documentVisibleRect]);
        printf("knob %.2f at %.2f\n", [[sv verticalScroller] knobProportion], [[sv verticalScroller] doubleValue]);
        [[sv contentView] scrollToPoint:NSMakePoint(50, 0)];
        rect("scrolled to the bottom", [sv documentVisibleRect]);
        printf("knob at %.2f, horizontal at %.2f\n", [[sv verticalScroller] doubleValue],
               [[sv horizontalScroller] doubleValue]);
        [[sv contentView] scrollToPoint:NSMakePoint(-20, 5000)];
        rect("kept inside the document", [sv documentVisibleRect]);
        [doc scrollRectToVisible:NSMakeRect(300, 400, 20, 20)];
        rect("after scrollRectToVisible", [sv documentVisibleRect]);
        rect("visibleRect of the document", [doc visibleRect]);
        printf("enclosing scroll view found: %d\n", [doc enclosingScrollView] == sv);
        /* the scroller drives the clip view */
        [[sv verticalScroller] setDoubleValue:0.5];
        [sv performSelector:@selector(_scrollerMoved:) withObject:[sv verticalScroller]];
        rect("scroller half way", [sv documentVisibleRect]);
        /* autohiding: a short document needs no scrollers */
        [sv setAutohidesScrollers:YES];
        [doc setFrameSize:NSMakeSize(100, 50)];
        printf("short document: vertical hidden %d, horizontal hidden %d\n", [[sv verticalScroller] isHidden],
               [[sv horizontalScroller] isHidden]);
        rect("clip view now", [[sv contentView] frame]);

        /* a text view that wraps and grows */
        NSScrollView *tsv = [NSTextView scrollableTextView];
        [tsv setFrame:NSMakeRect(0, 0, 160, 80)];
        NSTextView *tv = [tsv documentView];
        [[w contentView] addSubview:tsv];
        Watcher *watch = [[Watcher alloc] init];
        [tv setDelegate:watch];
        [tv setFont:[NSFont systemFontOfSize:12]];
        printf("text view flipped %d, editable %d, width follows %d\n", [tv isFlipped], [tv isEditable],
               [[tv textContainer] widthTracksTextView]);
        CGFloat before = [tv frame].size.height;
        [tv setString:@"One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen "
                     "sixteen seventeen eighteen nineteen twenty"];
        printf("wrapped: grew %d, width %.0f\n", [tv frame].size.height > before, [tv frame].size.width);
        NSRect used = [[tv layoutManager] usedRectForTextContainer:[tv textContainer]];
        printf("used rect is several lines: %d\n", used.size.height > 30);
        /* typing through the key commands */
        [w makeFirstResponder:tv];
        [tv setSelectedRange:NSMakeRange(0, 0)];
        [tv insertText:@"Zero "];
        [tv moveToEndOfDocument:nil];
        [tv insertNewline:nil];
        [tv insertText:@"last"];
        [tv deleteBackward:nil];
        [tv moveWordLeft:nil];
        [tv moveWordRightAndModifySelection:nil];
        NSRange sel = [tv selectedRange];
        printf("text ends \"%s\", selected \"%s\", %d changes\n",
               [[[tv string] substringFromIndex:[[tv string] length] - 9] UTF8String],
               [[[tv string] substringWithRange:sel] UTF8String], watch.changes);
        [tv moveToBeginningOfDocument:nil];
        [tv moveDown:nil];
        printf("down one line: past the first line %d\n", [tv selectedRange].location > 5);
        NSUInteger at = [tv characterIndexForInsertionAtPoint:NSMakePoint(2, 3)];
        printf("index at the top left %lu\n", (unsigned long)at);
        [tv selectAll:nil];
        printf("select all %lu\n", (unsigned long)[tv selectedRange].length);
        [tv setEditable:NO];
        [tv insertText:@"no"];
        printf("not editable: length still %lu\n", (unsigned long)[[tv string] length]);
        /* the storage can be changed directly */
        [[tv textStorage] replaceCharactersInRange:NSMakeRange(0, [[tv textStorage] length]) withString:@"short"];
        printf("after the storage changed: \"%s\", height back to the clip view's %d\n", [[tv string] UTF8String],
               [tv frame].size.height == [[tsv contentView] bounds].size.height);

        /* RTF in */
        NSData *rtf = [@"{\\rtf1\\ansi\\ansicpg1252{\\fonttbl\\f0\\fswiss Helvetica;}{\\colortbl;\\red255\\green0\\blue0;}"
                        "\\f0\\fs28 Plain {\\b bold} {\\i italic}\\par \\cf1 red \\'e9\\u8364? caf\\'e9\\\n"
                        "{\\*\\unknown skipped} \\qc centred}" dataUsingEncoding:NSUTF8StringEncoding];
        NSAttributedString *a = [[NSAttributedString alloc] initWithRTF:rtf documentAttributes:NULL];
        printf("rtf text: %s\n", [[[a string] stringByReplacingOccurrencesOfString:@"\n" withString:@"|"] UTF8String]);
        NSRange r;
        NSFont *f = [a attribute:NSFontAttributeName atIndex:7 effectiveRange:&r];
        printf("\"bold\" is bold %d, size %.0f\n",
               (CTFontGetSymbolicTraits((__bridge CTFontRef)f) & kCTFontTraitBold) != 0, [f pointSize]);
        f = [a attribute:NSFontAttributeName atIndex:12 effectiveRange:NULL];
        printf("\"italic\" is italic %d\n", (CTFontGetSymbolicTraits((__bridge CTFontRef)f) & kCTFontTraitItalic) != 0);
        NSColor *c = [a attribute:NSForegroundColorAttributeName atIndex:20 effectiveRange:NULL];
        printf("\"red\" has a colour %d\n", c != nil);
        NSParagraphStyle *p = [a attribute:NSParagraphStyleAttributeName atIndex:[a length] - 2 effectiveRange:NULL];
        printf("last line centred %d\n", [p alignment] == NSTextAlignmentCenter);
        /* and back out, and in again */
        NSData *out = [a RTFFromRange:NSMakeRange(0, [a length]) documentAttributes:@{}];
        NSAttributedString *again = [[NSAttributedString alloc] initWithRTF:out documentAttributes:NULL];
        printf("round trip same text %d, still bold %d\n", [[again string] isEqualToString:[a string]],
               (CTFontGetSymbolicTraits((__bridge CTFontRef)[again attribute:NSFontAttributeName atIndex:7
                                                         effectiveRange:NULL]) & kCTFontTraitBold) != 0);
        printf("not RTF: %s\n", [[NSAttributedString alloc] initWithRTF:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]
                                                      documentAttributes:NULL] ? "read" : "nil");

        /* HTML in */
        NSData *html = [@"<html><head><title>T</title><style>p{}</style></head><body><h1>Welcome</h1>"
                         "<p>To the <b>installer</b> &amp; more&nbsp;text.</p><ul><li>one</li><li>two</li></ul>"
                         "<a href=\"https://example.org/\">a link</a><br>end</body></html>"
                         dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *attrs;
        NSAttributedString *h = [[NSAttributedString alloc] initWithData:html options:@{} documentAttributes:&attrs error:NULL];
        printf("html (%s): %s\n", [[attrs objectForKey:NSDocumentTypeDocumentAttribute] UTF8String],
               [[[h string] stringByReplacingOccurrencesOfString:@"\n" withString:@"|"] UTF8String]);
        NSUInteger link = [[h string] rangeOfString:@"a link"].location;
        printf("link: %s\n", [[[h attribute:NSLinkAttributeName atIndex:link effectiveRange:NULL] description] UTF8String]);
        NSAttributedString *plain = [[NSAttributedString alloc] initWithData:[@"just text\nlines" dataUsingEncoding:NSUTF8StringEncoding]
                                                                     options:@{} documentAttributes:&attrs error:NULL];
        printf("plain (%s): %lu characters\n", [[attrs objectForKey:NSDocumentTypeDocumentAttribute] UTF8String],
               (unsigned long)[plain length]);

        /* the text view draws its text */
        NSTextView *shown = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 60)];
        [[shown textStorage] setAttributedString:a];
        NSBitmapImageRep *rep = [shown bitmapImageRepForCachingDisplayInRect:[shown bounds]];
        [shown cacheDisplayInRect:[shown bounds] toBitmapImageRep:rep];
        int dark = 0, redish = 0;
        for (int y = 0; y < (int)[rep pixelsHigh]; y++)
            for (int x = 0; x < (int)[rep pixelsWide]; x++) {
                NSColor *px = [rep colorAtX:x y:y];
                CGFloat rgba[4];
                [px getRed:&rgba[0] green:&rgba[1] blue:&rgba[2] alpha:&rgba[3]];
                if (rgba[0] < 0.5 && rgba[1] < 0.5)
                    dark++;
                if (rgba[0] > 0.7 && rgba[1] < 0.3)
                    redish++;
            }
        printf("drawn: dark text %d, red text %d\n", dark > 50, redish > 10);

        /* progress and boxes */
        NSProgressIndicator *pi = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 100, 20)];
        printf("progress: indeterminate %d, range %.0f-%.0f\n", [pi isIndeterminate], [pi minValue], [pi maxValue]);
        [pi setIndeterminate:NO];
        [pi setDoubleValue:40];
        [pi incrementBy:100];
        printf("progress value %.0f (clamped)\n", [pi doubleValue]);
        [pi setStyle:NSProgressIndicatorStyleSpinning];
        [pi setControlSize:NSControlSizeSmall];
        [pi sizeToFit];
        rect("small spinner", [pi frame]);
        NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        [box setTitle:@"Options"];
        rect("box content", [[box contentView] frame]);
        printf("title rect is at the top %d\n", NSMaxY([box titleRect]) == 100);
        [box setTitlePosition:NSNoTitle];
        [box setContentViewMargins:NSMakeSize(10, 10)];
        rect("untitled box content", [[box contentView] frame]);
    }
    return 0;
}
