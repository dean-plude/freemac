/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: WKWebView, written from Apple's public WebKit
 * documentation. Each one is an NSView that owns one WebKitWebView of this
 * system's WebKitGTK, shown over it in AppKit's window by WKEmbed. Loads,
 * navigation and its state (each observable with key-value observing),
 * scripts, the navigation and UI delegates and snapshots go to and come
 * from WebKitGTK's calls and signals. */
#import "WKInternal.h"

@interface WKWebView () {
@public
    WKWebViewConfiguration *_configuration;
    GtkWidget *_web;
    BOOL _related;   /* made beside another view, for its createWebView */
}
@end

static NSError *wk_error(NSInteger code, NSString *message, NSDictionary *extra)
{
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (extra)
        [info addEntriesFromDictionary:extra];
    return [NSError errorWithDomain:WKErrorDomain code:code userInfo:info];
}

@implementation WKWebView {
    WKEmbed *_embed;
    WebKitSettings *_settings;
    id _navigationDelegate, _UIDelegate;   /* weak */
    WKBackForwardList *_backForwardList;
    WKNavigation *_navigation, *_pending;
    BOOL _failed;
    /* what key-value observers were last told */
    NSString *_title;
    NSURL *_URL;
    BOOL _loading, _canGoBack, _canGoForward;
    double _progress;
    NSString *_customUserAgent;
    BOOL _allowsBackForwardNavigationGestures, _allowsLinkPreview, _allowsMagnification;
    CGFloat _magnification, _pageZoom;
}

+ (BOOL)handlesURLScheme:(NSString *)scheme
{
    static NSSet *schemes;
    if (!schemes)
        schemes = [[NSSet setWithObjects:@"http", @"https", @"file", @"about", @"data", @"blob",
                                                 @"javascript", @"ws", @"wss", nil] retain];
    return [schemes containsObject:[scheme lowercaseString]];
}

/* ---- making the GTK view ---------------------------------------------------------------- */

static void on_load_changed(GtkWidget *web, int event, void *data);
static gboolean on_load_failed(GtkWidget *web, int event, const char *uri, GError *error, void *data);
static gboolean on_decide_policy(GtkWidget *web, WebKitPolicyDecision *decision, int type, void *data);
static gboolean on_script_dialog(GtkWidget *web, WebKitScriptDialog *dialog, void *data);
static GtkWidget *on_create(GtkWidget *web, WebKitNavigationAction *action, void *data);
static void on_close(GtkWidget *web, void *data);
static void on_notify(void *object, GParamSpec *pspec, void *data);
static void on_list_changed(WebKitBackForwardList *list, void *item, void *removed, void *data);
static gboolean on_focus_in(GtkWidget *web, void *event, void *data);
static void on_terminated(GtkWidget *web, int reason, void *data);

- (void)_setUp:(WKWebViewConfiguration *)configuration
{
    _configuration = [configuration ?: [[[WKWebViewConfiguration alloc] init] autorelease] copy];
    _magnification = _pageZoom = 1;
    _allowsLinkPreview = YES;
    GtkWidget *related = _configuration._relatedView;
    _configuration._relatedView = NULL;
    WKBackForwardList *list = nil;
    if (WKAvailable()) {
        GType type = WK(webkit_web_view_get_type)();
        if (related) {
            /* the new view shares the other's web process, context, settings and user content */
            _web = g_object_new(type, "related-view", related, NULL);
            _related = YES;
        } else {
            WebKitSettings *settings = WK(webkit_settings_new)();
            _web = g_object_new(type, "web-context", [_configuration.websiteDataStore _context], "user-content-manager",
                                [_configuration.userContentController _manager], "settings", settings, NULL);
            g_object_unref(settings);
        }
        _settings = g_object_ref(WK(webkit_web_view_get_settings)(_web));
        [_configuration.preferences _addSettings:_settings];
        WK(webkit_settings_set_enable_javascript_markup)(_settings,
                                                         _configuration.defaultWebpagePreferences.allowsContentJavaScript);
        [_configuration.userContentController _addWebView:self];
        _embed = [[WKEmbed alloc] initWithWebView:_web owner:self];
        [self _applyUserAgent];
        WKConnect(_web, "load-changed", on_load_changed, self);
        WKConnect(_web, "load-failed", on_load_failed, self);
        WKConnect(_web, "decide-policy", on_decide_policy, self);
        WKConnect(_web, "script-dialog", on_script_dialog, self);
        WKConnect(_web, "create", on_create, self);
        WKConnect(_web, "close", on_close, self);
        WKConnect(_web, "notify::title", on_notify, self);
        WKConnect(_web, "notify::uri", on_notify, self);
        WKConnect(_web, "notify::is-loading", on_notify, self);
        WKConnect(_web, "notify::estimated-load-progress", on_notify, self);
        WKConnect(_web, "focus-in-event", on_focus_in, self);
        WKConnect(_web, "web-process-terminated", on_terminated, self);
        WebKitBackForwardList *bfl = WK(webkit_web_view_get_back_forward_list)(_web);
        WKConnect(bfl, "changed", on_list_changed, self);
        list = [[WKBackForwardList alloc] _initWithList:bfl];
    }
    _backForwardList = list ?: [[WKBackForwardList alloc] _initWithList:NULL];
}

- (instancetype)initWithFrame:(NSRect)frame configuration:(WKWebViewConfiguration *)configuration
{
    self = [super initWithFrame:frame];
    [self _setUp:configuration];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame configuration:nil]; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    [self _setUp:nil];
    return self;
}

- (void)dealloc
{
    if (_web) {
        WKDisconnect(_web, self);
        WKDisconnect(WK(webkit_web_view_get_back_forward_list)(_web), self);
        WK(webkit_web_view_stop_loading)(_web);
        [_configuration.preferences _removeSettings:_settings];
        [_configuration.userContentController _removeWebView:self];
        [_embed invalidate];
        g_object_unref(_settings);
    }
    objc_storeWeak(&_navigationDelegate, nil);
    objc_storeWeak(&_UIDelegate, nil);
    [_embed release];
    [_configuration release];
    [_backForwardList release];
    [_navigation release];
    [_pending release];
    [_title release];
    [_URL release];
    [_customUserAgent release];
    [super dealloc];
}

- (WKWebViewConfiguration *)configuration { return [[_configuration copy] autorelease]; }
- (WKBackForwardList *)backForwardList { return _backForwardList; }
- (id<WKNavigationDelegate>)navigationDelegate { return objc_loadWeak(&_navigationDelegate); }
- (void)setNavigationDelegate:(id<WKNavigationDelegate>)delegate { objc_storeWeak(&_navigationDelegate, delegate); }
- (id<WKUIDelegate>)UIDelegate { return objc_loadWeak(&_UIDelegate); }
- (void)setUIDelegate:(id<WKUIDelegate>)delegate { objc_storeWeak(&_UIDelegate, delegate); }

/* ---- the state, for key-value observers ---------------------------------------------- */

- (NSString *)title { return _title; }
- (NSURL *)URL { return _URL; }
- (BOOL)isLoading { return _loading; }
- (double)estimatedProgress { return _progress; }
- (BOOL)canGoBack { return _canGoBack; }
- (BOOL)canGoForward { return _canGoForward; }
- (BOOL)hasOnlySecureContent { return [[[_URL scheme] lowercaseString] isEqualToString:@"https"]; }

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    static NSSet *ours;
    if (!ours)
        ours = [[NSSet setWithObjects:@"title", @"URL", @"loading", @"estimatedProgress", @"canGoBack",
                                              @"canGoForward", nil] retain];
    return ![ours containsObject:key] && [super automaticallyNotifiesObserversForKey:key];
}

/* reads WebKitGTK's state and tells observers what changed */
- (void)_refresh
{
    if (!_web)
        return;
    NSString *title = WKString(WK(webkit_web_view_get_title)(_web));
    NSString *uri = WKString(WK(webkit_web_view_get_uri)(_web));
    NSURL *url = [uri length] ? [NSURL URLWithString:uri] : nil;
    BOOL loading = WK(webkit_web_view_is_loading)(_web);
    double progress = WK(webkit_web_view_get_estimated_load_progress)(_web);
    BOOL back = WK(webkit_web_view_can_go_back)(_web), forward = WK(webkit_web_view_can_go_forward)(_web);
    if (title != _title && ![title isEqualToString:_title]) {
        [self willChangeValueForKey:@"title"];
        id wasTitle = _title;
        _title = [title copy];
        [wasTitle release];
        [self didChangeValueForKey:@"title"];
    }
    if (url != _URL && ![url isEqual:_URL]) {
        [self willChangeValueForKey:@"URL"];
        id wasURL = _URL;
        _URL = [url retain];
        [wasURL release];
        [self didChangeValueForKey:@"URL"];
    }
    if (loading != _loading) {
        [self willChangeValueForKey:@"loading"];
        _loading = loading;
        [self didChangeValueForKey:@"loading"];
    }
    if (progress != _progress) {
        [self willChangeValueForKey:@"estimatedProgress"];
        _progress = progress;
        [self didChangeValueForKey:@"estimatedProgress"];
    }
    if (back != _canGoBack) {
        [self willChangeValueForKey:@"canGoBack"];
        _canGoBack = back;
        [self didChangeValueForKey:@"canGoBack"];
    }
    if (forward != _canGoForward) {
        [self willChangeValueForKey:@"canGoForward"];
        _canGoForward = forward;
        [self didChangeValueForKey:@"canGoForward"];
    }
}

static void on_notify(void *object, GParamSpec *pspec, void *data)
{
    @autoreleasepool {
        [(WKWebView *)data _refresh];
    }
}

static void on_list_changed(WebKitBackForwardList *list, void *item, void *removed, void *data)
{
    @autoreleasepool {
        [(WKWebView *)data _refresh];
    }
}

/* ---- loading -------------------------------------------------------------------------- */

- (WKNavigation *)_begin
{
    if (!_web)
        return nil;
    WKNavigation *n = [[[WKNavigation alloc] init] autorelease];
    id wasPending = _pending;
    _pending = [n retain];
    [wasPending release];
    return n;
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request
{
    NSString *uri = [[request URL] absoluteString];
    if (!_web || !uri)
        return nil;
    if (![[request HTTPMethod] isEqualToString:@"GET"] || [request HTTPBody] || [[request allHTTPHeaderFields] count])
        WKWarnOnce("a web view's request with a method, headers or a body of its own (it is loaded as a GET)");
    WKNavigation *n = [self _begin];
    WebKitURIRequest *r = WK(webkit_uri_request_new)([uri UTF8String]);
    WK(webkit_web_view_load_request)(_web, r);
    g_object_unref(r);
    return n;
}

- (WKNavigation *)loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL
{
    if (!_web || ![URL isFileURL])
        return nil;
    /* WebKitGTK lets a file's page read other local files without a list */
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_load_uri)(_web, [[URL absoluteString] UTF8String]);
    return n;
}

- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
    if (!_web)
        return nil;
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_load_html)(_web, [string ?: @"" UTF8String], [[baseURL absoluteString] UTF8String]);
    return n;
}

- (WKNavigation *)loadData:(NSData *)data MIMEType:(NSString *)MIMEType
      characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL
{
    if (!_web)
        return nil;
    WKNavigation *n = [self _begin];
    GBytes *bytes = g_bytes_new([data bytes], [data length]);
    WK(webkit_web_view_load_bytes)(_web, bytes, [MIMEType ?: @"text/html" UTF8String],
                                   [characterEncodingName ?: @"UTF-8" UTF8String], [[baseURL absoluteString] UTF8String]);
    g_bytes_unref(bytes);
    return n;
}

- (WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item
{
    if (!_web || ![item _item])
        return nil;
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_go_to_back_forward_list_item)(_web, [item _item]);
    return n;
}

- (WKNavigation *)goBack
{
    if (!_web || !WK(webkit_web_view_can_go_back)(_web))
        return nil;
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_go_back)(_web);
    return n;
}

- (WKNavigation *)goForward
{
    if (!_web || !WK(webkit_web_view_can_go_forward)(_web))
        return nil;
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_go_forward)(_web);
    return n;
}

- (WKNavigation *)reload
{
    if (!_web)
        return nil;
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_reload)(_web);
    return n;
}

- (WKNavigation *)reloadFromOrigin
{
    if (!_web)
        return nil;
    WKNavigation *n = [self _begin];
    WK(webkit_web_view_reload_bypass_cache)(_web);
    return n;
}

- (void)stopLoading
{
    if (_web)
        WK(webkit_web_view_stop_loading)(_web);
}

- (IBAction)goBack:(id)sender { [self goBack]; }
- (IBAction)goForward:(id)sender { [self goForward]; }
- (IBAction)reload:(id)sender { [self reload]; }
- (IBAction)reloadFromOrigin:(id)sender { [self reloadFromOrigin]; }
- (IBAction)stopLoading:(id)sender { [self stopLoading]; }

/* ---- the navigation delegate ----------------------------------------------------------- */

static void on_load_changed(GtkWidget *web, int event, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        [[self retain] autorelease];
        id d = [[objc_loadWeak(&self->_navigationDelegate) retain] autorelease];
        [self _refresh];
        switch (event) {
        case WEBKIT_LOAD_STARTED:
            [self->_navigation release];
            self->_navigation = self->_pending ?: [[WKNavigation alloc] init];
            self->_pending = nil;
            self->_failed = NO;
            if ([d respondsToSelector:@selector(webView:didStartProvisionalNavigation:)])
                [d webView:self didStartProvisionalNavigation:self->_navigation];
            break;
        case WEBKIT_LOAD_REDIRECTED:
            if ([d respondsToSelector:@selector(webView:didReceiveServerRedirectForProvisionalNavigation:)])
                [d webView:self didReceiveServerRedirectForProvisionalNavigation:self->_navigation];
            break;
        case WEBKIT_LOAD_COMMITTED:
            if ([d respondsToSelector:@selector(webView:didCommitNavigation:)])
                [d webView:self didCommitNavigation:self->_navigation];
            break;
        case WEBKIT_LOAD_FINISHED: {
            WKNavigation *n = [self->_navigation autorelease];
            self->_navigation = nil;
            if (!self->_failed && [d respondsToSelector:@selector(webView:didFinishNavigation:)])
                [d webView:self didFinishNavigation:n];
            break;
        }
        }
    }
}

static gboolean on_load_failed(GtkWidget *web, int event, const char *uri, GError *error, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        [[self retain] autorelease];
        id d = [[objc_loadWeak(&self->_navigationDelegate) retain] autorelease];
        self->_failed = YES;
        [self _refresh];
        NSError *e = WKLoadError(error, uri);
        if (event == WEBKIT_LOAD_STARTED || event == WEBKIT_LOAD_REDIRECTED) {
            if ([d respondsToSelector:@selector(webView:didFailProvisionalNavigation:withError:)])
                [d webView:self didFailProvisionalNavigation:self->_navigation withError:e];
        } else if ([d respondsToSelector:@selector(webView:didFailNavigation:withError:)])
            [d webView:self didFailNavigation:self->_navigation withError:e];
    }
    return 1;   /* no error page of WebKitGTK's own, as on a Mac */
}

static void twice(id delegate, const char *method)
{
    fflush(stdout);
    fprintf(stderr, "WebKit (Ferry): the completion handler passed to -[%s %s] was called more than once\n",
            class_getName([delegate class]), method);
}

static void decide(WebKitPolicyDecision *decision, BOOL use)
{
    if (use)
        WK(webkit_policy_decision_use)(decision);
    else
        WK(webkit_policy_decision_ignore)(decision);
    g_object_unref(decision);
}

- (void)_decideAction:(WebKitPolicyDecision *)decision newWindow:(BOOL)newWindow
{
    id d = [[objc_loadWeak(&_navigationDelegate) retain] autorelease];
    WebKitNavigationAction *gtk = WK(webkit_navigation_policy_decision_get_navigation_action)(decision);
    WKNavigationAction *action = [WKNavigationAction _actionFrom:gtk view:self newWindow:newWindow];
    g_object_ref(decision);
    __block BOOL decided = NO;
    WKWebView *view = self;
    void (^finish)(WKNavigationActionPolicy, WKWebpagePreferences *) =
        ^(WKNavigationActionPolicy policy, WKWebpagePreferences *preferences) {
            /* a Mac raises here; an exception can't pass through GTK's calls, so it is said */
            if (decided) {
                twice(d, "webView:decidePolicyForNavigationAction:decisionHandler:");
                return;
            }
            decided = YES;
            if (policy == WKNavigationActionPolicyDownload)
                WKWarnOnce("downloads from a web view (the navigation was cancelled)");
            if (policy != WKNavigationActionPolicyAllow && !newWindow) {
                [view->_pending release];
                view->_pending = nil;
            }
            if (preferences && view->_settings)
                WK(webkit_settings_set_enable_javascript_markup)(view->_settings, preferences.allowsContentJavaScript);
            decide(decision, policy == WKNavigationActionPolicyAllow);
        };
    finish = [[finish copy] autorelease];
    if ([d respondsToSelector:@selector(webView:decidePolicyForNavigationAction:preferences:decisionHandler:)]) {
        WKWebpagePreferences *p = [[[WKWebpagePreferences alloc] init] autorelease];
        p.allowsContentJavaScript = _configuration.defaultWebpagePreferences.allowsContentJavaScript;
        p.preferredContentMode = _configuration.defaultWebpagePreferences.preferredContentMode;
        [d webView:self decidePolicyForNavigationAction:action preferences:p
            decisionHandler:^(WKNavigationActionPolicy policy, WKWebpagePreferences *preferences) {
                finish(policy, preferences);
            }];
    } else if ([d respondsToSelector:@selector(webView:decidePolicyForNavigationAction:decisionHandler:)])
        [d webView:self decidePolicyForNavigationAction:action
            decisionHandler:^(WKNavigationActionPolicy policy) { finish(policy, nil); }];
    else
        finish(WKNavigationActionPolicyAllow, nil);
}

- (void)_decideResponse:(WebKitPolicyDecision *)decision
{
    id d = [[objc_loadWeak(&_navigationDelegate) retain] autorelease];
    WKNavigationResponse *response = [WKNavigationResponse _responseFrom:decision];
    g_object_ref(decision);
    __block BOOL decided = NO;
    void (^finish)(WKNavigationResponsePolicy) = ^(WKNavigationResponsePolicy policy) {
        if (decided) {
            twice(d, "webView:decidePolicyForNavigationResponse:decisionHandler:");
            return;
        }
        decided = YES;
        if (policy == WKNavigationResponsePolicyDownload)
            WKWarnOnce("downloads from a web view (the navigation was cancelled)");
        /* a type WebKit can't show is never downloaded instead */
        decide(decision, policy == WKNavigationResponsePolicyAllow && response.canShowMIMEType);
    };
    if ([d respondsToSelector:@selector(webView:decidePolicyForNavigationResponse:decisionHandler:)])
        [d webView:self decidePolicyForNavigationResponse:response decisionHandler:[[finish copy] autorelease]];
    else
        finish(WKNavigationResponsePolicyAllow);
}

static gboolean on_decide_policy(GtkWidget *web, WebKitPolicyDecision *decision, int type, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        [[self retain] autorelease];
        if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE)
            [self _decideResponse:decision];
        else
            [self _decideAction:decision newWindow:type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION];
    }
    return 1;
}

static void on_terminated(GtkWidget *web, int reason, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        id d = [[objc_loadWeak(&self->_navigationDelegate) retain] autorelease];
        if ([d respondsToSelector:@selector(webViewWebContentProcessDidTerminate:)])
            [d webViewWebContentProcessDidTerminate:self];
    }
}

/* ---- the UI delegate ------------------------------------------------------------------ */

static gboolean on_script_dialog(GtkWidget *web, WebKitScriptDialog *dialog, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        [[self retain] autorelease];
        id d = [[objc_loadWeak(&self->_UIDelegate) retain] autorelease];
        int type = WK(webkit_script_dialog_get_dialog_type)(dialog);
        NSString *message = WKString(WK(webkit_script_dialog_get_message)(dialog)) ?: @"";
        WKFrameInfo *frame = [WKFrameInfo _mainFrameOf:self request:nil];
        /* answered while the signal runs, the dialog is WebKitGTK's to close;
         * answered later, it is kept and closed then */
        __block BOOL done = NO, kept = NO;
        void (^close)(void) = ^{
            if (done)
                return;
            done = YES;
            if (kept) {
                WK(webkit_script_dialog_close)(dialog);
                WK(webkit_script_dialog_unref)(dialog);
            }
        };
        close = [[close copy] autorelease];
        switch (type) {
        case WEBKIT_SCRIPT_DIALOG_ALERT:
            if ([d respondsToSelector:@selector(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:
                                                     completionHandler:)])
                [d webView:self runJavaScriptAlertPanelWithMessage:message initiatedByFrame:frame
                    completionHandler:close];
            else
                close();
            break;
        case WEBKIT_SCRIPT_DIALOG_CONFIRM:
            if ([d respondsToSelector:@selector(webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:
                                                     completionHandler:)])
                [d webView:self runJavaScriptConfirmPanelWithMessage:message initiatedByFrame:frame
                    completionHandler:^(BOOL result) {
                        if (!done)
                            WK(webkit_script_dialog_confirm_set_confirmed)(dialog, result);
                        close();
                    }];
            else {
                WK(webkit_script_dialog_confirm_set_confirmed)(dialog, 0);
                close();
            }
            break;
        case WEBKIT_SCRIPT_DIALOG_PROMPT: {
            NSString *text = WKString(WK(webkit_script_dialog_prompt_get_default_text)(dialog));
            if ([d respondsToSelector:@selector(webView:runJavaScriptTextInputPanelWithPrompt:defaultText:
                                                     initiatedByFrame:completionHandler:)])
                [d webView:self runJavaScriptTextInputPanelWithPrompt:message defaultText:text initiatedByFrame:frame
                    completionHandler:^(NSString *result) {
                        if (!done)
                            WK(webkit_script_dialog_prompt_set_text)(dialog, [result UTF8String]);
                        close();
                    }];
            else {
                WK(webkit_script_dialog_prompt_set_text)(dialog, NULL);
                close();
            }
            break;
        }
        default:   /* leaving the page: allowed, as a Mac does without a delegate of its own */
            WK(webkit_script_dialog_confirm_set_confirmed)(dialog, 1);
            close();
        }
        if (!done) {
            WK(webkit_script_dialog_ref)(dialog);
            kept = YES;
        }
    }
    return 1;
}

static GtkWidget *on_create(GtkWidget *web, WebKitNavigationAction *gtk, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        id d = [[objc_loadWeak(&self->_UIDelegate) retain] autorelease];
        if (![d respondsToSelector:@selector(webView:createWebViewWithConfiguration:forNavigationAction:
                                                 windowFeatures:)])
            return NULL;
        WKWebViewConfiguration *configuration = [[self->_configuration copy] autorelease];
        configuration._relatedView = web;
        WKNavigationAction *action = [WKNavigationAction _actionFrom:gtk view:self newWindow:YES];
        WKWebView *view = [d webView:self createWebViewWithConfiguration:configuration forNavigationAction:action
                      windowFeatures:[[[WKWindowFeatures alloc] init] autorelease]];
        if (!view || !view->_web)
            return NULL;
        if (!view->_related) {   /* a Mac raises; here the new window isn't opened */
            fflush(stdout);
            fprintf(stderr, "WebKit (Ferry): the WKWebView returned from -[%s webView:createWebViewWithConfiguration:"
                            "forNavigationAction:windowFeatures:] wasn't made with the configuration given\n",
                    class_getName([d class]));
            return NULL;
        }
        return g_object_ref(view->_web);   /* WebKitGTK takes a reference of its own */
    }
}

static void on_close(GtkWidget *web, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        id d = [[objc_loadWeak(&self->_UIDelegate) retain] autorelease];
        if ([d respondsToSelector:@selector(webViewDidClose:)])
            [d webViewDidClose:self];
    }
}

/* ---- scripts ------------------------------------------------------------------------- */

static void evaluated(void *source, GAsyncResult *result, void *data)
{
    @autoreleasepool {
        void (^handler)(id, NSError *) = data;
        GError *error = NULL;
        JSCValue *value = WK(webkit_web_view_evaluate_javascript_finish)(source, result, &error);
        id object = nil;
        NSError *e = nil;
        if (value) {
            BOOL unsupported = NO;
            object = WKObjectFromJSC(value, &unsupported);
            if (unsupported)
                e = wk_error(WKErrorJavaScriptResultTypeIsUnsupported,
                             @"JavaScript execution returned a result of an unsupported type", nil);
            g_object_unref(value);
        } else {
            NSString *message = error && error->message ? WKString(error->message) : @"";
            /* WebKitGTK reports a value it can't hand over (a function) as a
             * failed script with this message */
            BOOL invalid = error && error->domain == WK(webkit_javascript_error_quark)() &&
                           (error->code == WEBKIT_JAVASCRIPT_ERROR_INVALID_RESULT ||
                            [message isEqualToString:@"Unsupported result type"]);
            if (invalid)
                e = wk_error(WKErrorJavaScriptResultTypeIsUnsupported,
                             @"JavaScript execution returned a result of an unsupported type", nil);
            else {
                /* WebKitGTK's message is "source:line:column: message" */
                NSMutableDictionary *info = [NSMutableDictionary dictionary];
                NSRegularExpression *re =
                    [NSRegularExpression regularExpressionWithPattern:@"^(.*):([0-9]+):([0-9]+): (.*)$"
                                                              options:NSRegularExpressionDotMatchesLineSeparators
                                                                error:NULL];
                NSTextCheckingResult *m = [re firstMatchInString:message options:0
                                                           range:NSMakeRange(0, [message length])];
                if (m) {
                    NSString *source = [message substringWithRange:[m rangeAtIndex:1]];
                    NSURL *url = [NSURL URLWithString:source];
                    if (url)
                        info[WKJavaScriptExceptionSourceURL] = url;
                    info[WKJavaScriptExceptionLineNumber] = @([[message substringWithRange:[m rangeAtIndex:2]] integerValue]);
                    info[WKJavaScriptExceptionColumnNumber] =
                        @([[message substringWithRange:[m rangeAtIndex:3]] integerValue]);
                    message = [message substringWithRange:[m rangeAtIndex:4]];
                }
                info[WKJavaScriptExceptionMessage] = message;
                e = wk_error(WKErrorJavaScriptExceptionOccurred, @"A JavaScript exception occurred", info);
            }
            if (error)
                g_error_free(error);
        }
        if (handler)
            handler(e ? nil : object, e);
        [handler release];
    }
}

- (void)evaluateJavaScript:(NSString *)script completionHandler:(void (^)(id, NSError *))handler
{
    [self evaluateJavaScript:script inFrame:nil inContentWorld:[WKContentWorld pageWorld] completionHandler:handler];
}

- (void)evaluateJavaScript:(NSString *)script inFrame:(WKFrameInfo *)frame inContentWorld:(WKContentWorld *)world
         completionHandler:(void (^)(id, NSError *))handler
{
    if (!_web) {
        if (handler) {
            NSError *e = wk_error(WKErrorUnknown, @"Web views need WebKitGTK and a display", nil);
            void (^h)(id, NSError *) = [[handler copy] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{ h(nil, e); });
        }
        return;
    }
    WK(webkit_web_view_evaluate_javascript)(_web, [script ?: @"" UTF8String], -1,
                                            [world ?: [WKContentWorld pageWorld] _gtkName], NULL, NULL, evaluated,
                                            [handler copy]);
}

/* ---- snapshots ----------------------------------------------------------------------- */

static void snapped(void *source, GAsyncResult *result, void *data)
{
    @autoreleasepool {
        NSDictionary *job = [(NSDictionary *)data autorelease];
        void (^handler)(NSImage *, NSError *) = job[@"handler"];
        GError *error = NULL;
        cairo_surface_t *surface = WK(webkit_web_view_get_snapshot_finish)(source, result, &error);
        NSImage *image = nil;
        if (surface) {
            NSRect rect = [job[@"rect"] rectValue];
            cairo_surface_t *shown = surface;
            if (!NSIsEmptyRect(rect)) {
                /* the part asked for, in the view's coordinates (from its top left, as WebKit's are) */
                shown = cairo_image_surface_create(0 /* ARGB32 */, (int)NSWidth(rect), (int)NSHeight(rect));
                cairo_t *cr = cairo_create(shown);
                cairo_set_source_surface(cr, surface, -NSMinX(rect), -NSMinY(rect));
                cairo_paint(cr);
                cairo_destroy(cr);
            }
            image = WKImageFromSurface(shown);
            NSSize size = NSIsEmptyRect(rect) ? [job[@"size"] sizeValue] : rect.size;
            NSNumber *width = job[@"width"];
            if (width && size.width > 0)
                size = NSMakeSize([width doubleValue], size.height * [width doubleValue] / size.width);
            if (size.width > 0 && size.height > 0)
                [image setSize:size];
            if (shown != surface)
                cairo_surface_destroy(shown);
            cairo_surface_destroy(surface);
        }
        NSError *e = nil;
        if (!image)
            e = wk_error(WKErrorUnknown, error && error->message ? WKString(error->message) : @"No snapshot was taken",
                         nil);
        if (error)
            g_error_free(error);
        if (handler)
            handler(image, e);
    }
}

- (void)takeSnapshotWithConfiguration:(WKSnapshotConfiguration *)configuration
                    completionHandler:(void (^)(NSImage *, NSError *))handler
{
    if (!_web) {
        if (handler) {
            NSError *e = wk_error(WKErrorUnknown, @"Web views need WebKitGTK and a display", nil);
            void (^h)(NSImage *, NSError *) = [[handler copy] autorelease];
            dispatch_async(dispatch_get_main_queue(), ^{ h(nil, e); });
        }
        return;
    }
    NSMutableDictionary *job = [[NSMutableDictionary alloc] init];
    if (handler)
        job[@"handler"] = [[handler copy] autorelease];
    job[@"rect"] = [NSValue valueWithRect:configuration ? configuration.rect : NSZeroRect];
    job[@"size"] = [NSValue valueWithSize:[self bounds].size];
    if (configuration.snapshotWidth)
        job[@"width"] = configuration.snapshotWidth;
    WK(webkit_web_view_get_snapshot)(_web, WEBKIT_SNAPSHOT_REGION_VISIBLE, WEBKIT_SNAPSHOT_OPTIONS_NONE, NULL, snapped,
                                     job);
}

/* ---- the rest of the view's settings --------------------------------------------------- */

- (void)_applyUserAgent
{
    if (!_settings)
        return;
    if (_customUserAgent) {
        WK(webkit_settings_set_user_agent)(_settings, [_customUserAgent UTF8String]);
        return;
    }
    WK(webkit_settings_set_user_agent)(_settings, NULL);
    NSString *name = _configuration.applicationNameForUserAgent;
    if ([name length]) {
        NSString *agent = WKString(WK(webkit_settings_get_user_agent)(_settings));
        WK(webkit_settings_set_user_agent)(_settings, [[NSString stringWithFormat:@"%@ %@", agent, name] UTF8String]);
    }
}

- (NSString *)customUserAgent { return _customUserAgent; }
- (void)setCustomUserAgent:(NSString *)agent
{
    [_customUserAgent release];
    _customUserAgent = [agent length] ? [agent copy] : nil;
    [self _applyUserAgent];
}

- (void)_applyZoom
{
    if (_web)
        WK(webkit_web_view_set_zoom_level)(_web, _magnification * _pageZoom);
}
- (CGFloat)magnification { return _magnification; }
- (void)setMagnification:(CGFloat)magnification
{
    _magnification = magnification > 0 ? magnification : 1;
    [self _applyZoom];
}
- (void)setMagnification:(CGFloat)magnification centeredAtPoint:(CGPoint)point { [self setMagnification:magnification]; }
- (CGFloat)pageZoom { return _pageZoom; }
- (void)setPageZoom:(CGFloat)zoom
{
    _pageZoom = zoom > 0 ? zoom : 1;
    [self _applyZoom];
}
- (BOOL)allowsMagnification { return _allowsMagnification; }
- (void)setAllowsMagnification:(BOOL)flag { _allowsMagnification = flag; }
- (BOOL)allowsBackForwardNavigationGestures { return _allowsBackForwardNavigationGestures; }
- (void)setAllowsBackForwardNavigationGestures:(BOOL)flag { _allowsBackForwardNavigationGestures = flag; }
- (BOOL)allowsLinkPreview { return _allowsLinkPreview; }
- (void)setAllowsLinkPreview:(BOOL)flag { _allowsLinkPreview = flag; }

/* ---- the view in its window --------------------------------------------------------- */

- (GtkWidget *)_gtkWebView { return _web; }
- (WebKitSettings *)_gtkSettings { return _settings; }
- (NSArray *)_ferryPlacement { return _embed ? [_embed placement] : @[]; }
- (BOOL)_ferryHasFocus { return [_embed hasFocus]; }
- (void)_setApplicationName:(NSString *)name
{
    _configuration.applicationNameForUserAgent = name;
    [self _applyUserAgent];
}

- (void)viewDidMoveToWindow
{
    [super viewDidMoveToWindow];
    [_embed sync];
}

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [_embed setNeedsSync];
}

- (void)setFrameOrigin:(NSPoint)origin
{
    [super setFrameOrigin:origin];
    [_embed setNeedsSync];
}

- (void)setHidden:(BOOL)hidden
{
    [super setHidden:hidden];
    [_embed setNeedsSync];
}

/* under the web view, or in its place without WebKitGTK: a white page */
- (void)drawRect:(NSRect)dirty
{
    [[NSColor whiteColor] setFill];
    NSRectFill(dirty);
    [_embed setNeedsSync];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (BOOL)becomeFirstResponder
{
    [_embed focus];
    return YES;
}

- (BOOL)resignFirstResponder
{
    [_embed unfocus];
    return YES;
}

static gboolean on_focus_in(GtkWidget *web, void *event, void *data)
{
    @autoreleasepool {
        WKWebView *self = data;
        NSWindow *window = [self window];
        if (window && [window firstResponder] != self)
            [window makeFirstResponder:self];
    }
    return 0;
}

/* the Edit menu's commands, done in the page */
- (void)_edit:(const char *)command
{
    if (_web)
        WK(webkit_web_view_execute_editing_command)(_web, command);
}
- (IBAction)copy:(id)sender { [self _edit:"Copy"]; }
- (IBAction)cut:(id)sender { [self _edit:"Cut"]; }
- (IBAction)paste:(id)sender { [self _edit:"Paste"]; }
- (IBAction)selectAll:(id)sender { [self _edit:"SelectAll"]; }
- (IBAction)undo:(id)sender { [self _edit:"Undo"]; }
- (IBAction)redo:(id)sender { [self _edit:"Redo"]; }
- (IBAction)delete:(id)sender { [self _edit:"Delete"]; }
@end
