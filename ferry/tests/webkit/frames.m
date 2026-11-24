/* SPDX-License-Identifier: GPL-3.0-or-later
 * The older WebView, with this system's WebKitGTK (freemac 1.217, Ferry
 * 0.42.0): the frame view and its document view, following the page's size
 * and scroll position and scrolling it; subframes, their names, documents
 * and loads told to the frame load delegate; the resource load delegate;
 * the user style sheet; and window.open's window. Local files only. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static void turn(void)
{
    NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                       inMode:NSDefaultRunLoopMode
                                      dequeue:YES];
    if (e)
        [NSApp sendEvent:e];
}

static BOOL spin_until(BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done() && [end timeIntervalSinceNow] > 0)
        turn();
    return done();
}

static const char *cls(id o) { return o ? object_getClassName(o) : "nil"; }

static NSString *name_of(NSURL *url)
{
    if (!url)
        return @"(none)";
    if ([url isFileURL])
        return [url lastPathComponent];
    NSString *s = [url absoluteString];
    return [s hasPrefix:@"data:"] ? @"data:" : s;
}

static NSString *frame_name(WebFrame *f)
{
    return f.parentFrame ? [NSString stringWithFormat:@"\"%@\"", f.name] : @"main";
}

@interface Delegate : NSObject <WebFrameLoadDelegate, WebResourceLoadDelegate, WebPolicyDelegate, WebUIDelegate>
@property int finished;
@property (strong) NSMutableDictionary *frameLog;   /* by frame */
@property (strong) NSMutableDictionary *resources;  /* by identifier */
@property (strong) NSMutableArray *opened;
@property BOOL logResources;
@end

@implementation Delegate
- (instancetype)init
{
    self = [super init];
    _frameLog = [NSMutableDictionary dictionary];
    _resources = [NSMutableDictionary dictionary];
    _opened = [NSMutableArray array];
    return self;
}
- (void)note:(NSString *)what frame:(WebFrame *)frame
{
    NSString *key = frame_name(frame);
    if (!_frameLog[key])
        _frameLog[key] = [NSMutableArray array];
    [_frameLog[key] addObject:what];
}
- (void)flushFrames:(NSString *)title
{
    printf("%s\n", [title UTF8String]);
    for (NSString *key in [[_frameLog allKeys] sortedArrayUsingSelector:@selector(compare:)])
        printf("  %s: %s\n", [key UTF8String], [[_frameLog[key] componentsJoinedByString:@", "] UTF8String]);
    [_frameLog removeAllObjects];
}
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    [self note:[NSString stringWithFormat:@"start %@", name_of(frame.provisionalDataSource.request.URL)] frame:frame];
}
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    [self note:[NSString stringWithFormat:@"commit %@", name_of(frame.dataSource.request.URL)] frame:frame];
}
- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    [self note:[NSString stringWithFormat:@"title %@", title] frame:frame];
}
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    [self note:@"finish" frame:frame];
    if (frame == sender.mainFrame)
        _finished++;
}
- (void)webView:(WebView *)sender
    decidePolicyForNavigationAction:(NSDictionary *)information
                            request:(NSURLRequest *)request
                              frame:(WebFrame *)frame
                   decisionListener:(id<WebPolicyDecisionListener>)listener
{
    [self note:[NSString stringWithFormat:@"policy %@", name_of(request.URL)] frame:frame];
    [listener use];
}
- (void)webView:(WebView *)sender
    decidePolicyForNewWindowAction:(NSDictionary *)information
                           request:(NSURLRequest *)request
                      newFrameName:(NSString *)name
                  decisionListener:(id<WebPolicyDecisionListener>)listener
{
    printf("  policy for a new window: %s\n", [name_of(request.URL) UTF8String]);
    [listener use];
}
- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    WebView *view = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    view.frameLoadDelegate = self;
    [_opened addObject:view];
    printf("  create a web view\n");
    return view;
}
- (void)webViewShow:(WebView *)sender { printf("  show it\n"); }

- (id)webView:(WebView *)sender identifierForInitialRequest:(NSURLRequest *)request
    fromDataSource:(WebDataSource *)dataSource
{
    if (!_logResources)
        return nil;
    NSString *identifier = name_of(request.URL);
    _resources[identifier] = [NSMutableArray arrayWithObject:[NSString
                                                                 stringWithFormat:@"data source %@",
                                                                                  name_of(dataSource.request.URL)]];
    return identifier;
}
- (void)log:(NSString *)what for:(id)identifier
{
    if ([identifier isKindOfClass:[NSString class]])
        [_resources[identifier] addObject:what];
}
- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource
{
    [self log:@"will send" for:identifier];
    return request;
}
- (void)webView:(WebView *)sender resource:(id)identifier didReceiveResponse:(NSURLResponse *)response
    fromDataSource:(WebDataSource *)dataSource
{
    [self log:[NSString stringWithFormat:@"response %@", response.MIMEType] for:identifier];
}
- (void)webView:(WebView *)sender resource:(id)identifier didFinishLoadingFromDataSource:(WebDataSource *)dataSource
{
    [self log:@"finished" for:identifier];
}
- (void)webView:(WebView *)sender resource:(id)identifier didFailLoadingWithError:(NSError *)error
    fromDataSource:(WebDataSource *)dataSource
{
    [self log:[NSString stringWithFormat:@"failed %@ %ld", error.domain, (long)error.code] for:identifier];
}
@end

static Delegate *delegate;

static void load(WebView *web, void (^start)(void))
{
    int before = delegate.finished;
    start();
    if (!spin_until(^{ return (BOOL)(delegate.finished > before); }))
        printf("(timed out)\n");
    /* the subframes' last messages */
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:0.3];
    while ([end timeIntervalSinceNow] > 0)
        turn();
}

static void write_file(NSString *dir, NSString *name, NSString *text)
{
    [text writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding
                error:NULL];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frames"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        write_file(dir, @"tall.html", @"<title>Tall</title><body style='margin:0'><div style='height:3000px;width:10px'>top</div>"
                                      @"<a id=l href='#end'>to the end</a><div id=end>end</div>");
        write_file(dir, @"child.html", @"<title>Child</title><p>child <a id=l href=other.html>other</a></p>");
        write_file(dir, @"other.html", @"<title>Other</title><p>other</p>");
        write_file(dir, @"frames.html",
                   @"<title>Frames</title><link rel=stylesheet href=style.css><script src=script.js></script>"
                   @"<iframe name=one src=child.html></iframe>"
                   @"<iframe name=two srcdoc='<title>Inline</title><b>inline</b>'></iframe>"
                   @"<img src=missing.png>");
        write_file(dir, @"style.css", @"p { color: green }");
        write_file(dir, @"script.js", @"var loaded = 1;");
        write_file(dir, @"user.css", @"body { background-color: rgb(4, 5, 6) }");

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        delegate = [[Delegate alloc] init];
        web.frameLoadDelegate = delegate;
        web.policyDelegate = delegate;
        web.UIDelegate = delegate;
        [window.contentView addSubview:web];
        [window makeKeyAndOrderFront:nil];

        /* the frame view */
        WebFrameView *frameView = web.mainFrame.frameView;
        NSView *documentView = frameView.documentView;
        NSScrollView *scrollView = documentView.enclosingScrollView;
        NSClipView *clip = scrollView.contentView;
        printf("frame view %s of the main frame %d, in the web view %d, allows scrolling %d\n", cls(frameView),
               frameView.webFrame == web.mainFrame, [frameView isDescendantOf:web], frameView.allowsScrolling);
        printf("document view %s, a WebDocumentView %d, text %d, flipped %d, in a scroll view %d\n", cls(documentView),
               [documentView conformsToProtocol:@protocol(WebDocumentView)],
               [documentView conformsToProtocol:@protocol(WebDocumentText)], documentView.isFlipped,
               scrollView != nil && [scrollView isDescendantOf:frameView]);

        load(web, ^{ [web.mainFrame loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:
                                                                     [dir stringByAppendingPathComponent:@"tall.html"]]]]; });
        [delegate.frameLog removeAllObjects];
        printf("a tall page: the document view %.0f high, at %.0f; its text starts \"%s\"\n", documentView.frame.size.height,
               clip.bounds.origin.y, [[[(id<WebDocumentText>)documentView string] substringToIndex:3] UTF8String]);
        __block int boundsChanges = 0;
        clip.postsBoundsChangedNotifications = YES;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSViewBoundsDidChangeNotification
                                                                        object:clip
                                                                         queue:nil
                                                                    usingBlock:^(NSNotification *n) { boundsChanges++; }];
        [web stringByEvaluatingJavaScriptFromString:@"window.scrollTo(0, 1200)"];
        BOOL followed = spin_until(^{ return (BOOL)(clip.bounds.origin.y == 1200); });
        printf("the page scrolled by a script: the clip view at %.0f (followed %d, told %d)\n", clip.bounds.origin.y,
               followed, boundsChanges > 0);
        [documentView scrollPoint:NSMakePoint(0, 500)];
        spin_until(^{ return (BOOL)([[web stringByEvaluatingJavaScriptFromString:@"scrollY"] intValue] == 500); });
        printf("scrollPoint: on the document view: the page at %s\n",
               [[web stringByEvaluatingJavaScriptFromString:@"scrollY"] UTF8String]);
        [clip scrollToPoint:NSMakePoint(0, 2000)];
        [scrollView reflectScrolledClipView:clip];
        spin_until(^{ return (BOOL)([[web stringByEvaluatingJavaScriptFromString:@"scrollY"] intValue] == 2000); });
        printf("the clip view scrolled: the page at %s\n", [[web stringByEvaluatingJavaScriptFromString:@"scrollY"] UTF8String]);
        [clip scrollToPoint:NSMakePoint(0, 99999)];
        spin_until(^{ return (BOOL)([[web stringByEvaluatingJavaScriptFromString:@"scrollY"] intValue] > 2000); });
        printf("scrolled past the end: the clip view at the bottom %d, the page too %d\n",
               (int)NSMaxY(clip.bounds) == (int)documentView.frame.size.height,
               [[web stringByEvaluatingJavaScriptFromString:@"scrollY+innerHeight===document.documentElement.scrollHeight"]
                   isEqualToString:@"true"]);
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        web.textSizeMultiplier = 2;
        spin_until(^{ return (BOOL)(documentView.frame.size.height > 6000); });
        printf("zoomed twice: the document view %.0f high\n", documentView.frame.size.height);
        web.textSizeMultiplier = 1;
        spin_until(^{ return (BOOL)(documentView.frame.size.height < 6000); });

        /* subframes */
        delegate.logResources = YES;
        web.resourceLoadDelegate = delegate;
        load(web, ^{ [web.mainFrame loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:
                                                                     [dir stringByAppendingPathComponent:@"frames.html"]]]]; });
        [delegate flushFrames:@"a page with frames:"];
        NSArray *children = web.mainFrame.childFrames;
        printf("child frames: %lu", (unsigned long)children.count);
        for (WebFrame *f in children)
            printf(", \"%s\" (%s, parent the main frame %d, in the view %d)", [f.name UTF8String],
                   [name_of(f.dataSource.request.URL) UTF8String], f.parentFrame == web.mainFrame, f.webView == web);
        printf("\n");
        WebFrame *one = [web.mainFrame findFrameNamed:@"one"], *two = [web.mainFrame findFrameNamed:@"two"];
        printf("found by name: one %d, two %d, none %s; _top %d, _parent %d\n", one == children.firstObject,
               two == children.lastObject, cls([web.mainFrame findFrameNamed:@"three"]),
               [one findFrameNamed:@"_top"] == web.mainFrame, [two findFrameNamed:@"_parent"] == web.mainFrame);
        printf("one: document %s, body \"%s\", title %s, frame element %s name=%s, its contentFrame the frame %d\n",
               cls(one.DOMDocument), [one.DOMDocument.body.textContent UTF8String],
               [one.dataSource.pageTitle UTF8String], cls(one.frameElement),
               [[one.frameElement getAttribute:@"name"] UTF8String],
               [(DOMHTMLIFrameElement *)one.frameElement contentFrame] == one);
        printf("two: body \"%s\", window %s, the same frame after another look %d\n",
               [two.DOMDocument.body.textContent UTF8String], cls(two.windowObject), web.mainFrame.childFrames.lastObject == two);
        printf("one's frame view: %s of the frame %d, its document view %.0f wide\n", cls(one.frameView),
               one.frameView.webFrame == one, one.frameView.documentView.frame.size.width);
        printf("the page's documents: main %s, one's owner is not the main frame's %d\n", cls(web.mainFrame.DOMDocument),
               one.DOMDocument != web.mainFrame.DOMDocument);

        /* the resource load delegate: each resource, in the order of its URL */
        for (NSString *key in [[delegate.resources allKeys] sortedArrayUsingSelector:@selector(compare:)])
            printf("resource %s: %s\n", [key UTF8String], [[delegate.resources[key] componentsJoinedByString:@", "] UTF8String]);
        delegate.logResources = NO;
        web.resourceLoadDelegate = nil;

        /* a link clicked in a subframe */
        [one.windowObject evaluateWebScript:@"document.getElementById('l').click()"];
        spin_until(^{ return (BOOL)([[delegate.frameLog[@"\"one\""] lastObject] isEqual:@"finish"]); });
        [delegate flushFrames:@"a link clicked in frame one:"];
        printf("one now: %s, \"%s\"\n", [name_of(one.dataSource.request.URL) UTF8String],
               [one.DOMDocument.body.textContent UTF8String]);
        /* a subframe loaded by the program */
        [two loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"child.html"]]]];
        spin_until(^{ return (BOOL)([[delegate.frameLog[@"\"two\""] lastObject] isEqual:@"finish"]); });
        [delegate flushFrames:@"frame two loaded by the program:"];
        printf("two now: %s\n", [two.DOMDocument.title UTF8String]);

        /* the user style sheet */
        WebPreferences *preferences = [[WebPreferences alloc] initWithIdentifier:@"frames"];
        preferences.userStyleSheetLocation = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"user.css"]];
        preferences.userStyleSheetEnabled = YES;
        web.preferences = preferences;
        load(web, ^{ [web.mainFrame loadHTMLString:@"<body>styled</body>" baseURL:nil]; });
        printf("the user style sheet: background %s\n",
               [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.body).backgroundColor"] UTF8String]);
        preferences.userStyleSheetEnabled = NO;
        load(web, ^{ [web.mainFrame loadHTMLString:@"<body>plain</body>" baseURL:nil]; });
        printf("turned off: background %s\n",
               [[web stringByEvaluatingJavaScriptFromString:@"getComputedStyle(document.body).backgroundColor"] UTF8String]);

        /* window.open: the policy delegate first, then the new view, which the page gets */
        [delegate.frameLog removeAllObjects];
        load(web, ^{ [web.mainFrame loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:
                                                                     [dir stringByAppendingPathComponent:@"other.html"]]]]; });
        [delegate.frameLog removeAllObjects];
        printf("window.open:\n");
        NSString *opened = [web stringByEvaluatingJavaScriptFromString:
                                    @"window.__w = window.open('child.html'); String(window.__w !== null)"];
        WebView *made = delegate.opened.lastObject;
        spin_until(^{ return (BOOL)[made.mainFrameTitle isEqualToString:@"Child"]; });
        printf("  the page got a window %s; the new view shows %s\n", [opened UTF8String], [made.mainFrameTitle UTF8String]);
        printf("  the new window from the opener: closed %s, its title %s\n",
               [[web stringByEvaluatingJavaScriptFromString:@"String(window.__w.closed)"] UTF8String],
               [[web stringByEvaluatingJavaScriptFromString:@"window.__w.document.title"] UTF8String]);
    }
    return 0;
}
