/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit with no web views shown: the classes, their defaults and
 * constants, which need neither WebKitGTK nor a display; then web views
 * made where they can't be shown (run with no display, and again as if
 * WebKitGTK weren't installed), which stay empty while the program goes
 * on. With the argument "classes" only the first part runs, and WebKitGTK
 * is never opened. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static BOOL spin_until(BOOL (^done)(void))
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done() && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return done();
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        WKWebViewConfiguration *c = [[WKWebViewConfiguration alloc] init];
        printf("configuration: preferences %d, controller %d, store %d (the default %d, persistent %d), pool %d\n",
               c.preferences != nil, c.userContentController != nil, c.websiteDataStore != nil,
               c.websiteDataStore == [WKWebsiteDataStore defaultDataStore], c.websiteDataStore.isPersistent,
               c.processPool != nil);
        WKWebViewConfiguration *copy = [c copy];
        printf("a copy shares the controller %d and the preferences %d\n",
               copy.userContentController == c.userContentController, copy.preferences == c.preferences);
        printf("preferences: JavaScript %d, open windows %d, minimum font size %g, tabs to links %d, fullscreen %d\n",
               c.preferences.javaScriptEnabled, c.preferences.javaScriptCanOpenWindowsAutomatically,
               c.preferences.minimumFontSize, c.preferences.tabFocusesLinks, c.preferences.isElementFullscreenEnabled);
        WKWebsiteDataStore *a = [WKWebsiteDataStore nonPersistentDataStore], *b = [WKWebsiteDataStore nonPersistentDataStore];
        printf("non-persistent stores: persistent %d, each its own %d; %lu data types\n", a.isPersistent, a != b,
               (unsigned long)[WKWebsiteDataStore allWebsiteDataTypes].count);
        WKUserScript *script = [[WKUserScript alloc] initWithSource:@"1" injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                                   forMainFrameOnly:NO];
        printf("user script: %s, at the end %d, all frames %d\n", [script.source UTF8String],
               script.injectionTime == WKUserScriptInjectionTimeAtDocumentEnd, !script.isForMainFrameOnly);
        printf("worlds: the page's is one object %d, a named one %d, its name %s\n",
               [WKContentWorld pageWorld] == [WKContentWorld pageWorld],
               [WKContentWorld worldWithName:@"x"] == [WKContentWorld worldWithName:@"x"],
               [[WKContentWorld worldWithName:@"x"].name UTF8String]);
        WKSnapshotConfiguration *snap = [[WKSnapshotConfiguration alloc] init];
        printf("snapshot configuration: rect empty %d, width %s, after screen updates %d\n", NSIsEmptyRect(snap.rect),
               snap.snapshotWidth ? "set" : "nil", snap.afterScreenUpdates);
        printf("schemes: http %d, file %d, about %d, ferry %d\n", [WKWebView handlesURLScheme:@"http"],
               [WKWebView handlesURLScheme:@"file"], [WKWebView handlesURLScheme:@"about"],
               [WKWebView handlesURLScheme:@"ferry"]);
        printf("constants: %s, %s, %s\n", [WKErrorDomain UTF8String], [WebViewProgressFinishedNotification UTF8String],
               [WebActionNavigationTypeKey UTF8String]);
        WebPreferences *p = [WebPreferences standardPreferences];
        printf("WebPreferences: %s, %s, %d, JavaScript %d, page cache %d\n", [p.sansSerifFontFamily UTF8String],
               [p.fixedFontFamily UTF8String], p.defaultFontSize, p.isJavaScriptEnabled, p.usesPageCache);
        printf("WebUndefined: %s, one object %d\n", [[[WebUndefined undefined] description] UTF8String],
               [WebUndefined undefined] == [WebUndefined undefined]);
        if (argc > 1 && !strcmp(argv[1], "classes"))
            return 0;

        WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200) configuration:c];
        printf("a web view that can't be shown: load %s, title %s, URL %s, loading %d, back-forward list %d\n",
               [web loadHTMLString:@"<title>x</title>" baseURL:nil] ? "a navigation" : "nil",
               [web.title UTF8String] ?: "nil", [[web.URL absoluteString] UTF8String] ?: "nil", web.loading,
               web.backForwardList != nil);
        __block NSError *scriptError = nil, *snapError = nil;
        [web evaluateJavaScript:@"1" completionHandler:^(id result, NSError *error) { scriptError = error; }];
        [web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) { snapError = error; }];
        spin_until(^{ return (BOOL)(scriptError && snapError); });
        printf("its script: %s %ld; its snapshot: %s %ld\n", [scriptError.domain UTF8String], (long)scriptError.code,
               [snapError.domain UTF8String], (long)snapError.code);
        [c.userContentController addScriptMessageHandler:(id<WKScriptMessageHandler>)[[NSObject alloc] init] name:@"x"];
        [c.userContentController removeAllScriptMessageHandlers];
        __block int removed = 0;
        [[WKWebsiteDataStore nonPersistentDataStore] removeDataOfTypes:[WKWebsiteDataStore allWebsiteDataTypes]
                                                         modifiedSince:[NSDate distantPast]
                                                     completionHandler:^{ removed++; }];
        spin_until(^{ return (BOOL)(removed > 0); });
        printf("data removed: %d\n", removed);

        WebView *old = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
        [old.mainFrame loadHTMLString:@"<title>x</title>" baseURL:nil];
        printf("an older WebView: script \"%s\", window object's value %s, title \"%s\", URL \"%s\"\n",
               [[old stringByEvaluatingJavaScriptFromString:@"1 + 1"] UTF8String],
               [[[old.windowScriptObject evaluateWebScript:@"1"] description] UTF8String], [old.mainFrameTitle UTF8String],
               [old.mainFrameURL UTF8String]);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        window.releasedWhenClosed = NO;
        [window.contentView addSubview:web];
        [window.contentView addSubview:old];
        [window display];
        printf("in a window, drawn: %d\n", [window.contentView subviews].count == 2);
        [window close];
        printf("the program goes on\n");
    }
    return 0;
}
