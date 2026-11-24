/* SPDX-License-Identifier: GPL-3.0-or-later
 * WKWebView on a display, with this system's WebKitGTK: pages loaded from
 * strings, data and local files (never the network), the navigation
 * delegate's calls and policies, the view's state as key-value observers
 * see it, going back and forward, scripts and their results, user scripts,
 * content worlds, script message handlers, data stores and a snapshot. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/* a turn of the event loop, as [NSApp run] takes it */
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

static NSString *name_of(NSURL *url)
{
    if (!url)
        return @"(none)";
    return [url isFileURL] ? [url lastPathComponent] : [url absoluteString];
}

@interface Recorder : NSObject <WKNavigationDelegate, WKScriptMessageHandler>
@property (strong) NSMutableArray *log;
@property (strong) NSMutableSet *observed;
@property int finished;
@property (strong) WKNavigation *returned;
@property BOOL sameNavigation;
@property (strong) NSMutableArray *messages;
@end

@implementation Recorder
- (instancetype)init
{
    self = [super init];
    _log = [NSMutableArray array];
    _observed = [NSMutableSet set];
    _messages = [NSMutableArray array];
    return self;
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSString *name = name_of(action.request.URL);
    [_log addObject:[NSString stringWithFormat:@"action %@ type %ld main %d", name, (long)action.navigationType,
                                               action.targetFrame.isMainFrame]];
    if ([name isEqualToString:@"blocked.html"]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        _finished++;   /* nothing else comes for a cancelled navigation */
    } else
        /* answered later, as a delegate may */
        dispatch_async(dispatch_get_main_queue(), ^{ decisionHandler(WKNavigationActionPolicyAllow); });
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
    [_log addObject:[NSString stringWithFormat:@"response %@ %@ main %d can show %d", name_of(response.response.URL),
                                               response.response.MIMEType, response.forMainFrame,
                                               response.canShowMIMEType]];
    decisionHandler(WKNavigationResponsePolicyAllow);
}
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
    _sameNavigation = navigation == _returned;
    [_log addObject:@"start"];
}
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation { [_log addObject:@"commit"]; }
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    [_log addObject:[NSString stringWithFormat:@"finish (the navigation the load gave: %d)",
                                               _sameNavigation && navigation == _returned]];
    _finished++;
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [_log addObject:[NSString stringWithFormat:@"failed provisionally: %@ %ld, for %@", error.domain, (long)error.code,
                                               name_of(error.userInfo[NSURLErrorFailingURLErrorKey])]];
    _finished++;
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [_log addObject:[NSString stringWithFormat:@"failed: %@ %ld", error.domain, (long)error.code]];
    _finished++;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    [_observed addObject:keyPath];
}
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message
{
    [_messages addObject:[NSString stringWithFormat:@"%@: %@ (from the view: %d, main frame: %d)", message.name,
                                                    message.body, message.webView != nil,
                                                    message.frameInfo.isMainFrame]];
}
- (void)flush:(NSString *)title
{
    printf("%s:\n", [title UTF8String]);
    for (NSString *line in _log)
        printf("  %s\n", [line UTF8String]);
    [_log removeAllObjects];
}
@end

static Recorder *rec;
static WKWebView *web;

static void load(NSString *title, WKNavigation * (^start)(void))
{
    int before = rec.finished;
    rec.returned = start();
    if (!spin_until(^{ return (BOOL)(rec.finished > before); }))
        [rec.log addObject:@"(timed out)"];
    [rec flush:title];
}

static NSString *kind_of(id value)
{
    for (Class c in @[ [NSString class], [NSNumber class], [NSArray class], [NSDictionary class], [NSDate class],
                       [NSNull class] ])
        if ([value isKindOfClass:c])
            return NSStringFromClass(c);
    return NSStringFromClass([value class]);
}

/* a script's result, as text */
static NSString *evaluate(NSString *script)
{
    __block NSString *out = nil;
    [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        if (error)
            out = [NSString stringWithFormat:@"error %@ %ld%@", error.domain, (long)error.code,
                                             error.userInfo[WKJavaScriptExceptionMessage]
                                                 ? [@": " stringByAppendingString:error.userInfo[WKJavaScriptExceptionMessage]]
                                                 : @""];
        else if (!result)
            out = @"nil";
        else
            out = [NSString stringWithFormat:@"%@ %@", kind_of(result),
                                             [[result description] stringByReplacingOccurrencesOfString:@"\n"
                                                                                             withString:@" "]];
    }];
    if (!spin_until(^{ return (BOOL)(out != nil); }))
        return @"(timed out)";
    return out;
}

static void show(NSString *script) { printf("  %s -> %s\n", [script UTF8String], [evaluate(script) UTF8String]); }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"pages"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"<title>Page A</title><p>a</p><a id=l href=b.html>b</a>" writeToFile:[dir stringByAppendingPathComponent:@"a.html"]
                                                                   atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"<title>Page B</title><p>b</p>" writeToFile:[dir stringByAppendingPathComponent:@"b.html"] atomically:YES
                                             encoding:NSUTF8StringEncoding error:NULL];
        NSURL *a = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"a.html"]];
        NSURL *b = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"b.html"]];

        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        printf("defaults: JavaScript %d, open windows %d, content JavaScript %d, store persistent %d\n",
               configuration.preferences.javaScriptEnabled, configuration.preferences.javaScriptCanOpenWindowsAutomatically,
               configuration.defaultWebpagePreferences.allowsContentJavaScript,
               configuration.websiteDataStore.isPersistent);
        configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
        rec = [[Recorder alloc] init];
        WKUserContentController *content = configuration.userContentController;
        [content addUserScript:[[WKUserScript alloc] initWithSource:@"window.startedEarly = typeof document.body"
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:YES]];
        [content addUserScript:[[WKUserScript alloc] initWithSource:@"window.endBody = document.body ? 'there' : 'no'"
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                   forMainFrameOnly:NO]];
        [content addUserScript:[[WKUserScript alloc] initWithSource:@"window.secret = 'kept apart'"
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                   forMainFrameOnly:YES
                                                     inContentWorld:[WKContentWorld worldWithName:@"tools"]]];
        [content addScriptMessageHandler:rec name:@"ferry"];
        printf("user scripts: %lu, the first at document start: %d, main frame only: %d\n",
               (unsigned long)content.userScripts.count,
               content.userScripts[0].injectionTime == WKUserScriptInjectionTimeAtDocumentStart,
               content.userScripts[0].isForMainFrameOnly);
        @try {
            [content addScriptMessageHandler:rec name:@"ferry"];
            printf("a second handler of the same name: allowed\n");
        } @catch (NSException *e) {
            printf("a second handler of the same name: %s\n", [e.name UTF8String]);
        }

        web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) configuration:configuration];
        printf("the view's store is the one given: %d (persistent %d)\n",
               web.configuration.websiteDataStore == configuration.websiteDataStore,
               web.configuration.websiteDataStore.isPersistent);
        web.navigationDelegate = rec;
        for (NSString *key in @[ @"title", @"URL", @"loading", @"estimatedProgress", @"canGoBack", @"canGoForward" ])
            [web addObserver:rec forKeyPath:key options:0 context:NULL];
        printf("before loading: title %s, URL %s, loading %d, back %d, forward %d\n", [web.title UTF8String] ?: "nil",
               [name_of(web.URL) UTF8String], web.loading, web.canGoBack, web.canGoForward);

        load(@"an HTML string", ^{
            return [web loadHTMLString:@"<title>From a string</title><p id=p>hello</p>"
                                       @"<script>window.webkit.messageHandlers.ferry.postMessage({n: 1, s: 'hi', a: [1, 2]})</script>"
                               baseURL:nil];
        });
        spin_until(^{ return (BOOL)(rec.messages.count > 0 && [web.title length] > 0); });
        printf("title %s, URL %s, loading %d, progress %g\n", [web.title UTF8String], [name_of(web.URL) UTF8String],
               web.loading, web.estimatedProgress);
        printf("messages:\n");
        for (NSString *m in rec.messages)
            printf("  %s\n", [m UTF8String]);
        [rec.messages removeAllObjects];
        printf("observed:");
        for (NSString *k in [[rec.observed allObjects] sortedArrayUsingSelector:@selector(compare:)])
            printf(" %s", [k UTF8String]);
        printf("\n");
        [rec.observed removeAllObjects];

        printf("scripts:\n");
        show(@"1 + 2");
        show(@"'a' + 'b'");
        show(@"true");
        show(@"[1, 'two', null]");
        show(@"({x: 1})");
        show(@"null");
        show(@"undefined");
        show(@"new Date(86400000)");
        show(@"(function () {})");
        show(@"document.getElementById('p').textContent");
        show(@"throw new Error('broken')");
        show(@"window.startedEarly + ', ' + window.endBody");
        show(@"typeof window.secret");
        __block NSString *inWorld = nil;
        [web evaluateJavaScript:@"window.secret" inFrame:nil inContentWorld:[WKContentWorld worldWithName:@"tools"]
              completionHandler:^(id result, NSError *error) { inWorld = result ?: @"nil"; }];
        spin_until(^{ return (BOOL)(inWorld != nil); });
        printf("  window.secret in the world 'tools' -> %s\n", [inWorld UTF8String]);

        load(@"data", ^{
            return [web loadData:[@"<title>From data</title>caf\xc3\xa9" dataUsingEncoding:NSUTF8StringEncoding]
                        MIMEType:@"text/html"
           characterEncodingName:@"UTF-8"
                         baseURL:[NSURL URLWithString:@"file:///data-page/"]];
        });
        show(@"document.body.textContent");

        load(@"a file", ^{ return [web loadFileURL:a allowingReadAccessToURL:[a URLByDeletingLastPathComponent]]; });
        spin_until(^{ return [web.title isEqualToString:@"Page A"]; });
        printf("title %s, URL %s\n", [web.title UTF8String], [name_of(web.URL) UTF8String]);

        load(@"a link clicked in the page", ^{
            [web evaluateJavaScript:@"document.getElementById('l').click()" completionHandler:nil];
            return (WKNavigation *)nil;
        });
        spin_until(^{ return [web.title isEqualToString:@"Page B"]; });
        printf("title %s, back %d, forward %d\n", [web.title UTF8String], web.canGoBack, web.canGoForward);
        WKBackForwardList *list = web.backForwardList;
        printf("back-forward list: current %s, back %s, back list %lu (the last: %s), forward list %lu\n",
               [name_of(list.currentItem.URL) UTF8String], [name_of(list.backItem.URL) UTF8String],
               (unsigned long)list.backList.count, [name_of(list.backList.lastObject.URL) UTF8String],
               (unsigned long)list.forwardList.count);

        load(@"back", ^{ return [web goBack]; });
        spin_until(^{ return [web.title isEqualToString:@"Page A"]; });
        printf("title %s, back %d, forward %d, forward item %s\n", [web.title UTF8String], web.canGoBack,
               web.canGoForward, [name_of(web.backForwardList.forwardItem.URL) UTF8String]);
        load(@"forward", ^{ return [web goForward]; });
        spin_until(^{ return [web.title isEqualToString:@"Page B"]; });
        printf("title %s\n", [web.title UTF8String]);
        load(@"reload", ^{ return [web reload]; });
        load(@"a request for a file", ^{ return [web loadRequest:[NSURLRequest requestWithURL:a]]; });
        printf("observed:");
        for (NSString *k in [[rec.observed allObjects] sortedArrayUsingSelector:@selector(compare:)])
            printf(" %s", [k UTF8String]);
        printf("\n");

        load(@"a file that isn't there", ^{
            return [web loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"none.html"]]]];
        });
        load(@"a navigation the delegate cancels", ^{
            return [web loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"blocked.html"]]]];
        });
        printf("still showing %s\n", [name_of(web.URL) UTF8String]);
        printf("goForward with nothing ahead: %s\n", [web goForward] ? "a navigation" : "nil");

        [content removeScriptMessageHandlerForName:@"ferry"];
        load(@"after the handler is removed", ^{ return [web loadHTMLString:@"<title>Gone</title>" baseURL:nil]; });
        show(@"typeof (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ferry)");

        __block int cleared = 0;
        [configuration.websiteDataStore removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
                                            modifiedSince:[NSDate distantPast]
                                        completionHandler:^{ cleared++; }];
        spin_until(^{ return (BOOL)(cleared > 0); });
        printf("data removed: %d (types %lu)\n", cleared, (unsigned long)[WKWebsiteDataStore allWebsiteDataTypes].count);

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.releasedWhenClosed = NO;
        [window.contentView addSubview:web];
        [window makeKeyAndOrderFront:nil];
        load(@"a page to snapshot", ^{
            return [web loadHTMLString:@"<body style='margin:0;background:rgb(0,0,255)'></body>" baseURL:nil];
        });
        __block NSImage *image = nil;
        __block BOOL snapped = NO;
        WKSnapshotConfiguration *snap = [[WKSnapshotConfiguration alloc] init];
        snap.rect = NSMakeRect(0, 0, 100, 50);
        [web takeSnapshotWithConfiguration:snap completionHandler:^(NSImage *i, NSError *e) {
            image = i;
            snapped = YES;
        }];
        spin_until(^{ return snapped; });
        NSBitmapImageRep *rep = image ? [[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]] : nil;
        NSColor *pixel = [rep colorAtX:10 y:10];
        printf("snapshot: %s, %gx%g, blue at (10, 10): %d\n", image ? "an image" : "none", image.size.width,
               image.size.height, pixel.blueComponent > 0.9 && pixel.redComponent < 0.1);
        for (NSString *key in @[ @"title", @"URL", @"loading", @"estimatedProgress", @"canGoBack", @"canGoForward" ])
            [web removeObserver:rec forKeyPath:key];
        [window close];
        printf("done\n");
    }
    return 0;
}
