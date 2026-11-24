/* SPDX-License-Identifier: GPL-3.0-or-later
 * WKWebView's UI delegate, with this system's WebKitGTK: a page's alert,
 * confirm and prompt (answered at once and answered later), what a page
 * gets with no UI delegate, and a new window that a page opens and closes. */
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

static NSString *evaluate(WKWebView *web, NSString *script)
{
    __block NSString *out = nil;
    [web evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
        out = error ? [NSString stringWithFormat:@"error %ld", (long)error.code] : result ? [result description] : @"nil";
    }];
    if (!spin_until(^{ return (BOOL)(out != nil); }))
        return @"(timed out)";
    return out;
}

@interface UI : NSObject <WKUIDelegate, WKNavigationDelegate>
@property (strong) NSMutableArray *opened;
@property int finished, closed;
@property BOOL makeNone;
@end

@implementation UI
- (instancetype)init
{
    self = [super init];
    _opened = [NSMutableArray array];
    return self;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(void))completionHandler
{
    printf("  alert \"%s\" (main frame %d)\n", [message UTF8String], frame.isMainFrame);
    completionHandler();
}
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(BOOL))completionHandler
{
    printf("  confirm \"%s\", answered later\n", [message UTF8String]);
    BOOL yes = [message hasPrefix:@"yes"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(),
                   ^{ completionHandler(yes); });
}
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
          defaultText:(NSString *)defaultText
     initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *))completionHandler
{
    printf("  prompt \"%s\" with \"%s\"\n", [prompt UTF8String], [defaultText UTF8String] ?: "nil");
    completionHandler([prompt isEqualToString:@"cancel"] ? nil : [defaultText stringByAppendingString:@"!"]);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action
         windowFeatures:(WKWindowFeatures *)features
{
    printf("  create a web view for %s (target frame %s, features %s)\n", [action.request.URL.lastPathComponent UTF8String],
           action.targetFrame ? "given" : "none", features.width ? "given" : "none");
    if (_makeNone)
        return nil;
    WKWebView *view = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100) configuration:configuration];
    view.UIDelegate = self;
    view.navigationDelegate = self;
    [_opened addObject:view];
    return view;
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if ([_opened containsObject:webView])
        _finished++;
}
- (void)webViewDidClose:(WKWebView *)webView
{
    printf("  closed: the opened view %d\n", [_opened containsObject:webView]);
    _closed++;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ui"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"<title>Opener</title>" writeToFile:[dir stringByAppendingPathComponent:@"opener.html"] atomically:YES
                                     encoding:NSUTF8StringEncoding error:NULL];
        [@"<title>Opened</title><p>new</p>" writeToFile:[dir stringByAppendingPathComponent:@"opened.html"] atomically:YES
                                               encoding:NSUTF8StringEncoding error:NULL];
        UI *ui = [[UI alloc] init];
        WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        web.UIDelegate = ui;
        __block BOOL loaded = NO;
        [web loadFileURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"opener.html"]]
            allowingReadAccessToURL:[NSURL fileURLWithPath:dir]];
        spin_until(^{ return [web.title isEqualToString:@"Opener"]; });
        loaded = [web.title isEqualToString:@"Opener"];
        printf("loaded: %d\n", loaded);

        printf("with a UI delegate:\n");
        printf("  -> %s\n", [evaluate(web, @"alert('hello'); 'after the alert'") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"confirm('yes, please')") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"confirm('no, thanks')") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"prompt('name', 'Ferry')") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"String(prompt('cancel', 'x'))") UTF8String]);

        printf("a window the page opens:\n");
        printf("  -> %s\n", [evaluate(web, @"window.opened = window.open('opened.html'); typeof window.opened") UTF8String]);
        spin_until(^{ return (BOOL)(ui.finished > 0); });
        WKWebView *opened = ui.opened.firstObject;
        spin_until(^{ return [opened.title isEqualToString:@"Opened"]; });
        printf("  the opened view shows %s, title %s, made with the configuration's store: %d\n",
               [opened.URL.lastPathComponent UTF8String], [opened.title UTF8String],
               opened.configuration.websiteDataStore == web.configuration.websiteDataStore);
        printf("  -> %s\n", [evaluate(web, @"window.opened.close(); 'asked to close'") UTF8String]);
        spin_until(^{ return (BOOL)(ui.closed > 0); });
        ui.makeNone = YES;
        printf("  -> %s\n", [evaluate(web, @"String(window.open('opened.html'))") UTF8String]);

        printf("with no UI delegate:\n");
        web.UIDelegate = nil;
        printf("  -> %s\n", [evaluate(web, @"alert('unseen'); 'went on'") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"confirm('unseen')") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"String(prompt('unseen', 'x'))") UTF8String]);
        printf("  -> %s\n", [evaluate(web, @"String(window.open('opened.html'))") UTF8String]);
        printf("done\n");
    }
    return 0;
}
