/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older WebView's frame views (freemac 1.217, Ferry
 * 0.42.0). Our own code, written from Apple's public documentation of
 * WebFrameView and WebDocumentView.
 *
 * WebKitGTK draws the page and scrolls it itself. A frame view stands for
 * that: it holds a scroll view, under the WKWebView that shows the page,
 * whose document view (a WebHTMLView) is as large as the page and whose
 * clip view is scrolled where the page is. The page's agent (WebView.m)
 * says when the page scrolls or changes size, and the clip view follows;
 * when a program scrolls the clip view (or calls the document view's
 * scrollPoint:), the page is scrolled there. Sizes are the page's CSS
 * pixels times the web view's text size multiplier, which zooms the page. */
#import "WKInternal.h"

@class WebClipView;

@interface WebFrameView () {
@public
    WebFrame *_frame;   /* not retained: it owns this */
    NSScrollView *_scroll;
    WebClipView *_clip;
    NSView<WebDocumentView> *_document;
    BOOL _allowsScrolling;
}
@end

/* the clip view, which scrolls the page when a program scrolls it */
@interface WebClipView : NSClipView {
@public
    WebFrameView *_owner;   /* not retained */
    int _quiet;             /* following the page, not moving it */
}
@end

@implementation WebClipView
- (void)setBounds:(NSRect)bounds
{
    NSPoint was = [self bounds].origin;
    [super setBounds:bounds];
    if (_quiet || NSEqualPoints(was, bounds.origin))
        return;
    WebFrame *frame = _owner ? _owner->_frame : nil;
    [[frame webView] _scrollFrame:frame to:bounds.origin];
}
- (void)setFrameSize:(NSSize)size
{
    _quiet++;
    [super setFrameSize:size];
    _quiet--;
}
@end

/* The view of a frame's HTML document: as large as the page; the page is
 * drawn over it by WebKitGTK. Its text is the page's. */
@interface WebHTMLView : NSView <WebDocumentView, WebDocumentText> {
@public
    WebFrameView *_owner;   /* not retained */
    WebDataSource *_dataSource;   /* not retained */
}
@end

@implementation WebHTMLView
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirty {}

- (void)setDataSource:(WebDataSource *)dataSource { _dataSource = dataSource; }
- (void)dataSourceUpdated:(WebDataSource *)dataSource {}
- (void)setNeedsLayout:(BOOL)flag {}
- (void)layout {}
- (void)viewWillMoveToHostWindow:(NSWindow *)hostWindow {}
- (void)viewDidMoveToHostWindow {}

/* a script run in this frame's window, its value as text */
- (NSString *)_text:(NSString *)body
{
    WebFrame *frame = _owner ? _owner->_frame : nil;
    WebScriptObject *window = [frame windowObject];
    if (!window)
        return @"";
    id s = [window _run:[NSString stringWithFormat:@"try{%@}catch(e){return '';}", body] flags:0];
    return [s isKindOfClass:[NSString class]] ? s : @"";
}

- (BOOL)supportsTextEncoding { return YES; }
- (NSString *)string { return [self _text:@"var b=o.document.body;return b?b.innerText:'';"]; }
- (NSAttributedString *)attributedString
{
    return [[[NSAttributedString alloc] initWithString:[self string]] autorelease];
}
- (NSString *)selectedString { return [self _text:@"return String(o.getSelection());"]; }
- (NSAttributedString *)selectedAttributedString
{
    return [[[NSAttributedString alloc] initWithString:[self selectedString]] autorelease];
}
- (void)selectAll { [self _text:@"o.document.execCommand('selectAll');return '';"]; }
- (void)deselectAll { [self _text:@"o.getSelection().removeAllRanges();return '';"]; }
- (IBAction)selectAll:(id)sender { [self selectAll]; }
@end

@implementation WebFrameView

- (instancetype)_initWithFrame:(NSRect)rect webFrame:(WebFrame *)frame
{
    self = [super initWithFrame:rect];
    _frame = frame;
    _allowsScrolling = YES;
    _scroll = [[NSScrollView alloc] initWithFrame:[self bounds]];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_scroll setDrawsBackground:NO];
    [_scroll setBorderType:NSNoBorder];
    _clip = [[WebClipView alloc] initWithFrame:[_scroll bounds]];
    _clip->_owner = self;
    _clip->_quiet++;
    [_clip setDrawsBackground:NO];
    [_scroll setContentView:_clip];
    WebHTMLView *html = [[WebHTMLView alloc] initWithFrame:[_clip bounds]];
    html->_owner = self;
    _document = html;
    [_scroll setDocumentView:html];
    _clip->_quiet--;
    [self addSubview:_scroll];
    return self;
}

- (instancetype)initWithFrame:(NSRect)rect { return [self _initWithFrame:rect webFrame:nil]; }

- (void)dealloc
{
    _clip->_owner = nil;
    ((WebHTMLView *)_document)->_owner = nil;
    [_document release];
    [_clip release];
    [_scroll release];
    [super dealloc];
}

/* its frame is going */
- (void)_forget { _frame = nil; }

- (void)setFrameSize:(NSSize)size
{
    _clip->_quiet++;
    [super setFrameSize:size];
    _clip->_quiet--;
}

/* where the page is scrolled and how large it is: {x, y, width, height}
 * in CSS pixels */
- (void)_setPageGeometry:(NSArray *)g
{
    if (![g isKindOfClass:[NSArray class]] || [g count] < 4)
        return;
    for (id v in g)
        if (![v isKindOfClass:[NSNumber class]])
            return;
    CGFloat zoom = _frame ? [[_frame webView] _zoom] : 1;
    if (zoom <= 0)
        zoom = 1;
    NSSize page = NSMakeSize(round([g[2] doubleValue] * zoom), round([g[3] doubleValue] * zoom));
    NSPoint at = NSMakePoint(round([g[0] doubleValue] * zoom), round([g[1] doubleValue] * zoom));
    _clip->_quiet++;
    if (!NSEqualSizes([_document frame].size, page))
        [_document setFrameSize:page];
    [_clip scrollToPoint:at];
    [_scroll reflectScrolledClipView:_clip];
    _clip->_quiet--;
    if (!_allowsScrolling)
        [self _applyScrolling];
}

- (void)_applyScrolling
{
    WebScriptObject *window = [_frame windowObject];
    [window _run:[NSString stringWithFormat:@"try{var s=o.document.documentElement.style;"
                                            @"if(%d)s.removeProperty('overflow');else s.overflow='hidden';}catch(e){}"
                                            @"return undefined;",
                                            _allowsScrolling ? 1 : 0]
           flags:0];
}

- (WebFrame *)webFrame { return _frame; }
- (NSView<WebDocumentView> *)documentView { return _document; }
- (BOOL)allowsScrolling { return _allowsScrolling; }
- (void)setAllowsScrolling:(BOOL)flag
{
    if (flag == _allowsScrolling)
        return;
    _allowsScrolling = flag;
    [self _applyScrolling];
}
- (BOOL)canPrintHeadersAndFooters { return NO; }
- (BOOL)documentViewShouldHandlePrint { return NO; }
- (NSPrintOperation *)printOperationWithPrintInfo:(NSPrintInfo *)printInfo
{
    WKWarnOnce("printing a web view's frame (the frame view is printed, without the page)");
    return [NSPrintOperation printOperationWithView:_document printInfo:printInfo];
}
- (void)printDocumentView { [[self printOperationWithPrintInfo:[NSPrintInfo sharedPrintInfo]] runOperation]; }
- (BOOL)acceptsFirstResponder { return NO; }
@end
