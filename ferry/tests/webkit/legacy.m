/* SPDX-License-Identifier: GPL-3.0-or-later
 * The older WebView, with this system's WebKitGTK: its main frame's loads,
 * the frame load, policy and UI delegates, the progress notifications,
 * data sources, preferences, stringByEvaluatingJavaScriptFromString: (also
 * from inside a delegate's call) and script objects. Local pages only. */
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

static NSString *text(id value)
{
    if (!value)
        return @"nil";
    if ([value isKindOfClass:[WebScriptObject class]])
        return [NSString stringWithFormat:@"a WebScriptObject (%@)", [value stringRepresentation]];
    if ([value isKindOfClass:[WebUndefined class]])
        return @"WebUndefined";
    if ([value isKindOfClass:[NSNull class]])
        return @"NSNull";
    if ([value isKindOfClass:[NSString class]])
        return [NSString stringWithFormat:@"\"%@\"", value];
    if ([value isKindOfClass:[NSNumber class]])
        return [NSString stringWithFormat:@"NSNumber %@", value];
    return [value description];
}

@interface Delegate : NSObject <WebFrameLoadDelegate, WebPolicyDelegate, WebUIDelegate>
@property int finished, shown;
@property (strong) NSMutableArray *log;
@property (strong) NSMutableArray *opened;
@property (strong) NSMutableArray *titles;
@end

@implementation Delegate
- (instancetype)init
{
    self = [super init];
    _log = [NSMutableArray array];
    _opened = [NSMutableArray array];
    _titles = [NSMutableArray array];
    return self;
}
- (void)flush:(NSString *)title
{
    printf("%s:\n", [title UTF8String]);
    for (NSString *line in _log)
        printf("  %s\n", [line UTF8String]);
    [_log removeAllObjects];
}
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"start %@ (main frame %d)", name_of(frame.provisionalDataSource.request.URL),
                                               frame == sender.mainFrame]];
}
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"commit (data source %@, provisional %@)",
                                               name_of(frame.dataSource.request.URL),
                                               frame.provisionalDataSource ? @"still there" : @"none"]];
}
- (void)webView:(WebView *)webView didClearWindowObject:(WebScriptObject *)windowObject forFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"window object cleared (the view's: %d)",
                                               windowObject == webView.windowScriptObject]];
}
- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    /* kept apart: it may come before the load finishes or after */
    [_titles addObject:title];
}
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if ([_opened containsObject:sender]) {
        _finished++;
        return;
    }
    [_log addObject:[NSString stringWithFormat:@"finish; a script run here: %@",
                                               [sender stringByEvaluatingJavaScriptFromString:@"'title: ' + document.title"]]];
    _finished++;
}
- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"failed provisionally: %@ %ld", error.domain, (long)error.code]];
    _finished++;
}
- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"failed: %@ %ld", error.domain, (long)error.code]];
    _finished++;
}
- (void)webView:(WebView *)webView decidePolicyForNavigationAction:(NSDictionary *)info
                                                           request:(NSURLRequest *)request
                                                             frame:(WebFrame *)frame
                                                  decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSString *name = name_of(request.URL);
    [_log addObject:[NSString stringWithFormat:@"policy for %@: type %@, original URL %@", name,
                                               info[WebActionNavigationTypeKey],
                                               name_of(info[WebActionOriginalURLKey])]];
    if ([name isEqualToString:@"blocked.html"]) {
        [listener ignore];
        _finished++;
    } else
        [listener use];
}
- (void)webView:(WebView *)webView decidePolicyForNewWindowAction:(NSDictionary *)info
                                                          request:(NSURLRequest *)request
                                                     newFrameName:(NSString *)frameName
                                                 decisionListener:(id<WebPolicyDecisionListener>)listener
{
    [_log addObject:[NSString stringWithFormat:@"policy for a new window: %@", name_of(request.URL)]];
    [listener use];
}
- (void)webView:(WebView *)webView decidePolicyForMIMEType:(NSString *)type
                                                   request:(NSURLRequest *)request
                                                     frame:(WebFrame *)frame
                                          decisionListener:(id<WebPolicyDecisionListener>)listener
{
    [_log addObject:[NSString stringWithFormat:@"policy for the type %@ (can show %d)", type,
                                               [WebView canShowMIMEType:type]]];
    [listener use];
}
- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"alert \"%@\"", message]];
}
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"confirm \"%@\"", message]];
    return YES;
}
- (NSString *)webView:(WebView *)sender runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
          defaultText:(NSString *)defaultText
     initiatedByFrame:(WebFrame *)frame
{
    [_log addObject:[NSString stringWithFormat:@"prompt \"%@\" with \"%@\"", prompt, defaultText]];
    return @"typed";
}
- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    [_log addObject:[NSString stringWithFormat:@"create a web view for %@", name_of(request.URL)]];
    WebView *view = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
    view.UIDelegate = self;
    view.frameLoadDelegate = self;
    [_opened addObject:view];
    return view;
}
- (void)webViewShow:(WebView *)sender
{
    [_log addObject:[NSString stringWithFormat:@"show the new view (made here: %d)", [_opened containsObject:sender]]];
    _shown++;
}
@end

static Delegate *delegate;

static void load(NSString *title, void (^start)(void))
{
    int before = delegate.finished;
    start();
    if (!spin_until(^{ return (BOOL)(delegate.finished > before); }))
        [delegate.log addObject:@"(timed out)"];
    [delegate flush:title];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"legacy"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"<title>First</title><a id=l href=second.html>next</a>"
            writeToFile:[dir stringByAppendingPathComponent:@"first.html"] atomically:YES encoding:NSUTF8StringEncoding
                  error:NULL];
        [@"<title>Second</title>" writeToFile:[dir stringByAppendingPathComponent:@"second.html"] atomically:YES
                                     encoding:NSUTF8StringEncoding error:NULL];
        NSURL *first = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"first.html"]];

        WebPreferences *standard = [WebPreferences standardPreferences];
        printf("standard preferences: %s %d, fixed %s %d, JavaScript %d, images %d, encoding %s\n",
               [standard.standardFontFamily UTF8String], standard.defaultFontSize, [standard.fixedFontFamily UTF8String],
               standard.defaultFixedFontSize, standard.javaScriptEnabled, standard.loadsImagesAutomatically,
               [standard.defaultTextEncodingName UTF8String]);
        WebPreferences *named = [[WebPreferences alloc] initWithIdentifier:@"test"];
        printf("the same identifier, the same preferences: %d\n", named == [[WebPreferences alloc] initWithIdentifier:@"test"]);
        __block int changes = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:WebPreferencesChangedNotification
                                                                        object:named
                                                                         queue:nil
                                                                    usingBlock:^(NSNotification *n) { changes++; }];
        named.defaultFontSize = 20;
        named.standardFontFamily = @"DejaVu Serif";
        printf("changed: %d notifications, size %d, family %s\n", changes, named.defaultFontSize,
               [named.standardFontFamily UTF8String]);
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        printf("WebUndefined is one object: %d; text/html shown as HTML %d, image/png shown %d, application/zip %d\n",
               [WebUndefined undefined] == [[WebUndefined undefined] copy],
               [WebView canShowMIMETypeAsHTML:@"text/html"], [WebView canShowMIMEType:@"image/png"],
               [WebView canShowMIMEType:@"application/zip"]);

        delegate = [[Delegate alloc] init];
        WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300) frameName:nil groupName:@"tests"];
        web.frameLoadDelegate = delegate;
        web.policyDelegate = delegate;
        web.UIDelegate = delegate;
        web.preferences = named;
        printf("group %s, preferences %s, main frame named \"%s\", in the view %d\n", [web.groupName UTF8String],
               [web.preferencesIdentifier UTF8String], [web.mainFrame.name UTF8String], web.mainFrame.webView == web);
        __block int started = 0, estimated = 0, ended = 0;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserverForName:WebViewProgressStartedNotification object:web queue:nil
                        usingBlock:^(NSNotification *n) { started++; }];
        [center addObserverForName:WebViewProgressEstimateChangedNotification object:web queue:nil
                        usingBlock:^(NSNotification *n) { estimated++; }];
        [center addObserverForName:WebViewProgressFinishedNotification object:web queue:nil
                        usingBlock:^(NSNotification *n) { ended++; }];

        load(@"an HTML string", ^{
            [web.mainFrame loadHTMLString:@"<title>Legacy</title><script>"
                                          @"var thing = {n: 4, list: [1, 2, 3], add: function (a, b) { return a + b; },"
                                          @" name: function (o) { return o.n; }};"
                                          @"alert('hello'); var answer = confirm('sure?'); var typed = prompt('name', 'x');"
                                          @"</script>"
                                  baseURL:[NSURL fileURLWithPath:dir isDirectory:YES]];
        });
        spin_until(^{ return (BOOL)(delegate.titles.count > 0); });
        printf("titles received: %s\n", [[delegate.titles componentsJoinedByString:@", "] UTF8String]);
        [delegate.titles removeAllObjects];
        printf("progress notifications: started %d, finished %d, estimates %s\n", started, ended,
               estimated > 0 ? "some" : "none");
        printf("title %s, URL %s, loading %d\n", [web.mainFrameTitle UTF8String],
               [name_of([NSURL URLWithString:web.mainFrameURL]) UTF8String], web.isLoading);
        printf("data source: %s, title %s, loading %d\n", [name_of(web.mainFrame.dataSource.request.URL) UTF8String],
               [web.mainFrame.dataSource.pageTitle UTF8String], web.mainFrame.dataSource.isLoading);

        printf("stringByEvaluatingJavaScriptFromString:\n");
        for (NSString *script in @[ @"6 * 7", @"'text'", @"answer", @"typed", @"thing", @"undefined", @"null",
                                    @"this is not JavaScript", @"var later = 1", @"later + 1" ])
            printf("  %s -> \"%s\"\n", [script UTF8String], [[web stringByEvaluatingJavaScriptFromString:script] UTF8String]);

        printf("script objects:\n");
        WebScriptObject *window = web.windowScriptObject;
        printf("  the frame's window object is the view's: %d\n", web.mainFrame.windowObject == window);
        id thing = [window evaluateWebScript:@"thing"];
        printf("  thing -> %s\n", [text(thing) UTF8String]);
        printf("  thing.n -> %s\n", [text([thing valueForKey:@"n"]) UTF8String]);
        printf("  thing.add(2, 3) -> %s\n", [text([thing callWebScriptMethod:@"add" withArguments:@[ @2, @3 ]]) UTF8String]);
        printf("  thing.add('a', 'b') -> %s\n",
               [text([thing callWebScriptMethod:@"add" withArguments:@[ @"a", @"b" ]]) UTF8String]);
        printf("  thing.name(thing) -> %s\n", [text([thing callWebScriptMethod:@"name" withArguments:@[ thing ]]) UTF8String]);
        printf("  thing.missing() -> %s\n", [text([thing callWebScriptMethod:@"missing" withArguments:nil]) UTF8String]);
        id list = [thing valueForKey:@"list"];
        printf("  thing.list[1] -> %s\n", [text([list webScriptValueAtIndex:1]) UTF8String]);
        [list setWebScriptValueAtIndex:1 value:@"two"];
        [thing setValue:@YES forKey:@"flag"];
        [thing setValue:@[ @1, @"b" ] forKey:@"array"];
        printf("  after setting: %s\n",
               [text([window evaluateWebScript:@"thing.list.join(',') + ' ' + thing.flag + ' ' + JSON.stringify(thing.array)"])
                   UTF8String]);
        [thing removeWebScriptKey:@"flag"];
        printf("  after removing: %s\n", [text([window evaluateWebScript:@"typeof thing.flag"]) UTF8String]);
        printf("  undefined -> %s, null -> %s, true -> %s, 1.5 -> %s\n",
               [text([window evaluateWebScript:@"undefined"]) UTF8String],
               [text([window evaluateWebScript:@"null"]) UTF8String],
               [text([window evaluateWebScript:@"true"]) UTF8String],
               [text([window evaluateWebScript:@"1.5"]) UTF8String]);
        printf("  an exception -> %s\n", [text([window evaluateWebScript:@"throw new Error('no')"]) UTF8String]);
        printf("  a global made by a script -> %s\n",
               [text([window evaluateWebScript:@"var madeHere = 'kept'; window.madeHere"]) UTF8String]);
        printf("  window.document.title -> %s\n",
               [text([[window valueForKey:@"document"] valueForKey:@"title"]) UTF8String]);

        load(@"a file", ^{ [web.mainFrame loadRequest:[NSURLRequest requestWithURL:first]]; });
        printf("data source: request %s, response %s %s, %lu bytes, title %s\n",
               [name_of(web.mainFrame.dataSource.request.URL) UTF8String],
               [name_of(web.mainFrame.dataSource.response.URL) UTF8String],
               [web.mainFrame.dataSource.response.MIMEType UTF8String],
               (unsigned long)web.mainFrame.dataSource.data.length, [web.mainFrame.dataSource.pageTitle UTF8String]);
        load(@"a link clicked", ^{ [web stringByEvaluatingJavaScriptFromString:@"document.getElementById('l').click()"]; });
        printf("back %d, forward %d\n", web.canGoBack, web.canGoForward);
        load(@"back", ^{ printf("goBack: %d\n", [web goBack]); });
        printf("title %s\n", [web.mainFrameTitle UTF8String]);
        load(@"the main frame's URL set", ^{
            web.mainFrameURL = [[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"second.html"]] absoluteString];
        });
        load(@"a load the policy delegate ignores", ^{
            [web.mainFrame loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"blocked.html"]]]];
        });
        printf("still %s\n", [web.mainFrameTitle UTF8String]);
        load(@"a file that isn't there", ^{
            [web.mainFrame loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"none.html"]]]];
        });

        load(@"a new window", ^{ [web stringByEvaluatingJavaScriptFromString:@"window.open('first.html')"]; });
        spin_until(^{ return (BOOL)(delegate.opened.count > 0 && [[delegate.opened[0] mainFrameTitle] isEqualToString:@"First"]); });
        printf("the new view shows %s, title %s\n", [name_of([NSURL URLWithString:[delegate.opened[0] mainFrameURL]]) UTF8String],
               [[delegate.opened[0] mainFrameTitle] UTF8String]);
        [delegate.log removeAllObjects];

        web.UIDelegate = nil;
        printf("with no UI delegate: confirm %s, prompt %s\n",
               [[web stringByEvaluatingJavaScriptFromString:@"String(confirm('x'))"] UTF8String],
               [[web stringByEvaluatingJavaScriptFromString:@"String(prompt('x'))"] UTF8String]);
        float size = web.textSizeMultiplier;
        [web makeTextLarger:nil];
        printf("text size: %g, larger %g, can make it standard %d\n", size, web.textSizeMultiplier,
               web.canMakeTextStandardSize);
        web.customUserAgent = @"FerryTest/1.0";
        printf("user agent: %s\n", [[web userAgentForURL:first] UTF8String]);
        printf("done\n");
    }
    return 0;
}
