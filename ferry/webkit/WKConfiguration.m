/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: what a WKWebView is made with and what it hands to its
 * delegates. The configuration, preferences, data stores, user scripts and
 * script message handlers, content worlds, frames, navigations and the
 * back-forward list, written from Apple's public WebKit documentation and
 * kept on WebKitGTK's settings, web contexts and user content managers. */
#import "WKInternal.h"

NSString *const WKErrorDomain = @"WKErrorDomain";
NSString *const WKJavaScriptExceptionMessage = @"WKJavaScriptExceptionMessage";
NSString *const WKJavaScriptExceptionLineNumber = @"WKJavaScriptExceptionLineNumber";
NSString *const WKJavaScriptExceptionColumnNumber = @"WKJavaScriptExceptionColumnNumber";
NSString *const WKJavaScriptExceptionSourceURL = @"WKJavaScriptExceptionSourceURL";

NSString *const WKWebsiteDataTypeDiskCache = @"WKWebsiteDataTypeDiskCache";
NSString *const WKWebsiteDataTypeMemoryCache = @"WKWebsiteDataTypeMemoryCache";
NSString *const WKWebsiteDataTypeOfflineWebApplicationCache = @"WKWebsiteDataTypeOfflineWebApplicationCache";
NSString *const WKWebsiteDataTypeCookies = @"WKWebsiteDataTypeCookies";
NSString *const WKWebsiteDataTypeSessionStorage = @"WKWebsiteDataTypeSessionStorage";
NSString *const WKWebsiteDataTypeLocalStorage = @"WKWebsiteDataTypeLocalStorage";
NSString *const WKWebsiteDataTypeWebSQLDatabases = @"WKWebsiteDataTypeWebSQLDatabases";
NSString *const WKWebsiteDataTypeIndexedDBDatabases = @"WKWebsiteDataTypeIndexedDBDatabases";
NSString *const WKWebsiteDataTypeFetchCache = @"WKWebsiteDataTypeFetchCache";
NSString *const WKWebsiteDataTypeServiceWorkerRegistrations = @"WKWebsiteDataTypeServiceWorkerRegistrations";

/* Archiving keeps nothing of these: an archived one comes back as a new one. */
#define WK_CODING                                                                                           \
    +(BOOL)supportsSecureCoding { return YES; }                                                             \
    -(void)encodeWithCoder : (NSCoder *)coder {}                                                            \
    -(instancetype)initWithCoder : (NSCoder *)coder { return [self init]; }

@implementation WKProcessPool
WK_CODING
@end

/* ---- preferences -------------------------------------------------------------------- */

@implementation WKPreferences {
    NSMutableArray *_settings;   /* NSValues of WebKitSettings, each with a reference */
}
WK_CODING
@synthesize minimumFontSize = _minimumFontSize, javaScriptEnabled = _javaScriptEnabled,
            javaScriptCanOpenWindowsAutomatically = _canOpen, tabFocusesLinks = _tabFocusesLinks,
            fraudulentWebsiteWarningEnabled = _fraudWarning, textInteractionEnabled = _textInteraction,
            elementFullscreenEnabled = _fullscreen, javaEnabled = _javaEnabled, plugInsEnabled = _plugInsEnabled;

- (instancetype)init
{
    self = [super init];
    _javaScriptEnabled = YES;
    _canOpen = YES;
    _fraudWarning = YES;
    _textInteraction = YES;
    _settings = [NSMutableArray new];
    return self;
}

- (void)dealloc
{
    for (NSValue *v in _settings)
        g_object_unref([v pointerValue]);
    [_settings release];
    [super dealloc];
}

- (void)_applyTo:(WebKitSettings *)s
{
    WK(webkit_settings_set_enable_javascript)(s, _javaScriptEnabled);
    WK(webkit_settings_set_javascript_can_open_windows_automatically)(s, _canOpen);
    WK(webkit_settings_set_minimum_font_size)(s, (uint32_t)fmax(_minimumFontSize, 0));
    WK(webkit_settings_set_enable_tabs_to_links)(s, _tabFocusesLinks);
    WK(webkit_settings_set_enable_fullscreen)(s, _fullscreen);
}

- (void)_addSettings:(WebKitSettings *)s
{
    for (NSValue *v in _settings)
        if ([v pointerValue] == s)
            return;
    g_object_ref(s);
    [_settings addObject:[NSValue valueWithPointer:s]];
    [self _applyTo:s];
}

- (void)_removeSettings:(WebKitSettings *)s
{
    for (NSUInteger i = 0; i < [_settings count]; i++)
        if ([_settings[i] pointerValue] == s) {
            [_settings removeObjectAtIndex:i];
            g_object_unref(s);
            return;
        }
}

- (void)_changed
{
    for (NSValue *v in _settings)
        [self _applyTo:[v pointerValue]];
}

#define WK_PREF(getter, setter, type, ivar)                                                                 \
    -(type)getter { return ivar; }                                                                          \
    -(void)setter : (type)value                                                                             \
    {                                                                                                       \
        ivar = value;                                                                                       \
        [self _changed];                                                                                    \
    }
WK_PREF(minimumFontSize, setMinimumFontSize, CGFloat, _minimumFontSize)
WK_PREF(javaScriptEnabled, setJavaScriptEnabled, BOOL, _javaScriptEnabled)
WK_PREF(javaScriptCanOpenWindowsAutomatically, setJavaScriptCanOpenWindowsAutomatically, BOOL, _canOpen)
WK_PREF(tabFocusesLinks, setTabFocusesLinks, BOOL, _tabFocusesLinks)
WK_PREF(isElementFullscreenEnabled, setElementFullscreenEnabled, BOOL, _fullscreen)
@end

@implementation WKWebpagePreferences
@synthesize allowsContentJavaScript = _allowsContentJavaScript, preferredContentMode = _preferredContentMode;
- (instancetype)init
{
    self = [super init];
    _allowsContentJavaScript = YES;
    return self;
}
@end

/* ---- user scripts and content worlds ------------------------------------------------- */

@implementation WKContentWorld {
    NSString *_name;
    NSString *_gtk;
}
+ (WKContentWorld *)_world:(NSString *)name gtk:(NSString *)gtk
{
    WKContentWorld *w = [[[WKContentWorld alloc] init] autorelease];
    w->_name = [name copy];
    w->_gtk = [gtk copy];
    return w;
}
+ (WKContentWorld *)pageWorld
{
    static WKContentWorld *page;
    if (!page)
        page = [[self _world:nil gtk:nil] retain];
    return page;
}
+ (WKContentWorld *)defaultClientWorld
{
    static WKContentWorld *client;
    if (!client)
        client = [[self _world:nil gtk:@"ferry-default-client-world"] retain];
    return client;
}
+ (WKContentWorld *)worldWithName:(NSString *)name
{
    static NSMutableDictionary *worlds;
    if (!worlds)
        worlds = [NSMutableDictionary new];
    WKContentWorld *w = worlds[name];
    if (!w) {
        w = [self _world:name gtk:name];
        worlds[name] = w;
    }
    return w;
}
- (NSString *)name { return _name; }
- (const char *)_gtkName { return [_gtk UTF8String]; }
- (void)dealloc
{
    [_name release];
    [_gtk release];
    [super dealloc];
}
@end

@implementation WKUserScript {
    NSString *_source;
    WKUserScriptInjectionTime _time;
    BOOL _mainFrameOnly;
    WKContentWorld *_world;
}
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)time
              forMainFrameOnly:(BOOL)mainFrameOnly
{
    return [self initWithSource:source injectionTime:time forMainFrameOnly:mainFrameOnly
                 inContentWorld:[WKContentWorld pageWorld]];
}
- (instancetype)initWithSource:(NSString *)source injectionTime:(WKUserScriptInjectionTime)time
              forMainFrameOnly:(BOOL)mainFrameOnly inContentWorld:(WKContentWorld *)world
{
    self = [super init];
    _source = [source copy] ?: @"";
    _time = time;
    _mainFrameOnly = mainFrameOnly;
    _world = [world ?: [WKContentWorld pageWorld] retain];
    return self;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)source { return _source; }
- (WKUserScriptInjectionTime)injectionTime { return _time; }
- (BOOL)isForMainFrameOnly { return _mainFrameOnly; }
- (WKContentWorld *)_world { return _world; }
- (WebKitUserScript *)_newGtkScript
{
    int frames = _mainFrameOnly ? WEBKIT_USER_CONTENT_INJECT_TOP_FRAME : WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES;
    int when = _time == WKUserScriptInjectionTimeAtDocumentStart ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START
                                                                 : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END;
    const char *world = [_world _gtkName];
    if (world)
        return WK(webkit_user_script_new_for_world)([_source UTF8String], frames, when, world, NULL, NULL);
    return WK(webkit_user_script_new)([_source UTF8String], frames, when, NULL, NULL);
}
- (void)dealloc
{
    [_source release];
    [_world release];
    [super dealloc];
}
@end

@implementation WKScriptMessage {
    id _body;
    id _webView;   /* weak */
    WKFrameInfo *_frameInfo;
    NSString *_name;
    WKContentWorld *_world;
}
- (instancetype)_initWithBody:(id)body view:(WKWebView *)view name:(NSString *)name world:(WKContentWorld *)world
{
    self = [super init];
    _body = [body retain];
    objc_storeWeak(&_webView, view);
    _name = [name copy];
    _world = [world retain];
    _frameInfo = [[WKFrameInfo _mainFrameOf:view request:nil] retain];
    return self;
}
- (id)body { return _body; }
- (WKWebView *)webView { return objc_loadWeak(&_webView); }
- (WKFrameInfo *)frameInfo { return _frameInfo; }
- (NSString *)name { return _name; }
- (WKContentWorld *)world { return _world; }
- (void)dealloc
{
    objc_storeWeak(&_webView, nil);
    [_body release];
    [_frameInfo release];
    [_name release];
    [_world release];
    [super dealloc];
}
@end

/* One message channel of a user content controller: its handler (retained,
 * as on a Mac), its name and its world. */
@interface WKMessageChannel : NSObject {
@public
    id<WKScriptMessageHandler> handler;
    NSString *name;
    WKContentWorld *world;
    WKUserContentController *controller;   /* not retained */
    BOOL registered;
}
@end
@implementation WKMessageChannel
- (void)dealloc
{
    [(id)handler release];
    [name release];
    [world release];
    [super dealloc];
}
@end

@implementation WKUserContentController {
    WebKitUserContentManager *_manager;
    NSMutableArray *_scripts;
    NSMutableArray *_channels;
    NSMutableArray *_views;   /* NSValues of the web views using it, not retained */
}
WK_CODING

- (instancetype)init
{
    self = [super init];
    _scripts = [NSMutableArray new];
    _channels = [NSMutableArray new];
    _views = [NSMutableArray new];
    return self;
}

- (void)dealloc
{
    if (_manager) {
        for (WKMessageChannel *c in _channels)
            WKDisconnect(_manager, c);
        g_object_unref(_manager);
    }
    [_scripts release];
    [_channels release];
    [_views release];
    [super dealloc];
}

static void on_script_message(WebKitUserContentManager *manager, WebKitJavascriptResult *result, void *data)
{
    @autoreleasepool {
        WKMessageChannel *c = data;
        BOOL unsupported = NO;
        id body = WKObjectFromJSC(WK(webkit_javascript_result_get_js_value)(result), &unsupported);
        WKWebView *view = [c->controller->_views count] ? [c->controller->_views[0] nonretainedObjectValue] : nil;
        WKScriptMessage *message = [[[WKScriptMessage alloc] _initWithBody:body view:view name:c->name
                                                                     world:c->world] autorelease];
        id<WKScriptMessageHandler> handler = [[(id)c->handler retain] autorelease];
        [handler userContentController:c->controller didReceiveScriptMessage:message];
    }
}

- (void)_register:(WKMessageChannel *)c
{
    if (!_manager || c->registered)
        return;
    const char *world = [c->world _gtkName];
    NSString *signal = [@"script-message-received::" stringByAppendingString:c->name];
    WKConnect(_manager, [signal UTF8String], on_script_message, c);
    if (world)
        WK(webkit_user_content_manager_register_script_message_handler_in_world)(_manager, [c->name UTF8String], world);
    else
        WK(webkit_user_content_manager_register_script_message_handler)(_manager, [c->name UTF8String]);
    c->registered = YES;
}

- (void)_unregister:(WKMessageChannel *)c
{
    if (!_manager || !c->registered)
        return;
    const char *world = [c->world _gtkName];
    if (world)
        WK(webkit_user_content_manager_unregister_script_message_handler_in_world)(_manager, [c->name UTF8String],
                                                                                    world);
    else
        WK(webkit_user_content_manager_unregister_script_message_handler)(_manager, [c->name UTF8String]);
    WKDisconnect(_manager, c);
    c->registered = NO;
}

- (void)_addGtkScript:(WKUserScript *)script
{
    WebKitUserScript *s = [script _newGtkScript];
    WK(webkit_user_content_manager_add_script)(_manager, s);
    WK(webkit_user_script_unref)(s);
}

/* made the first time a web view uses this controller */
- (WebKitUserContentManager *)_manager
{
    if (!_manager && WKAvailable()) {
        _manager = WK(webkit_user_content_manager_new)();
        g_object_ref_sink(_manager);
        for (WKUserScript *s in _scripts)
            [self _addGtkScript:s];
        for (WKMessageChannel *c in _channels)
            [self _register:c];
    }
    return _manager;
}

- (void)_addWebView:(WKWebView *)view { [_views addObject:[NSValue valueWithNonretainedObject:view]]; }
- (void)_removeWebView:(WKWebView *)view
{
    for (NSUInteger i = 0; i < [_views count]; i++)
        if ([_views[i] nonretainedObjectValue] == view) {
            [_views removeObjectAtIndex:i];
            return;
        }
}

- (NSArray *)userScripts { return [[_scripts copy] autorelease]; }

- (void)addUserScript:(WKUserScript *)userScript
{
    if (!userScript)
        return;
    [_scripts addObject:userScript];
    if (_manager)
        [self _addGtkScript:userScript];
}

- (void)removeAllUserScripts
{
    [_scripts removeAllObjects];
    if (_manager)
        WK(webkit_user_content_manager_remove_all_scripts)(_manager);
}

- (WKMessageChannel *)_channel:(NSString *)name world:(WKContentWorld *)world
{
    for (WKMessageChannel *c in _channels)
        if ([c->name isEqualToString:name] && c->world == world)
            return c;
    return nil;
}

- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)handler name:(NSString *)name
{
    [self addScriptMessageHandler:handler contentWorld:[WKContentWorld pageWorld] name:name];
}

- (void)addScriptMessageHandler:(id<WKScriptMessageHandler>)handler contentWorld:(WKContentWorld *)world
                           name:(NSString *)name
{
    world = world ?: [WKContentWorld pageWorld];
    if ([self _channel:name world:world])
        [NSException raise:NSInvalidArgumentException
                    format:@"Attempt to add script message handler with name '%@' when one already exists.", name];
    WKMessageChannel *c = [[WKMessageChannel new] autorelease];
    c->handler = [(id)handler retain];
    c->name = [name copy];
    c->world = [world retain];
    c->controller = self;
    [_channels addObject:c];
    [self _register:c];
}

- (void)removeScriptMessageHandlerForName:(NSString *)name
{
    [self removeScriptMessageHandlerForName:name contentWorld:[WKContentWorld pageWorld]];
}

- (void)removeScriptMessageHandlerForName:(NSString *)name contentWorld:(WKContentWorld *)world
{
    WKMessageChannel *c = [self _channel:name world:world ?: [WKContentWorld pageWorld]];
    if (!c)
        return;
    [self _unregister:c];
    [_channels removeObject:c];
}

- (void)removeAllScriptMessageHandlers
{
    for (WKMessageChannel *c in _channels)
        [self _unregister:c];
    [_channels removeAllObjects];
}
@end

/* ---- data stores -------------------------------------------------------------------- */

@implementation WKWebsiteDataStore {
    BOOL _persistent;
    WebKitWebContext *_context;
}
WK_CODING

+ (WKWebsiteDataStore *)defaultDataStore
{
    static WKWebsiteDataStore *store;
    if (!store) {
        store = [[WKWebsiteDataStore alloc] init];
        store->_persistent = YES;
    }
    return store;
}

+ (WKWebsiteDataStore *)nonPersistentDataStore { return [[[WKWebsiteDataStore alloc] init] autorelease]; }

- (BOOL)isPersistent { return _persistent; }

/* the default store is WebKitGTK's default context (kept in the program's
 * folders under ~/.local/share and ~/.cache); each other store is an
 * ephemeral context of its own, which keeps everything in memory */
- (WebKitWebContext *)_context
{
    if (!_context && WKAvailable()) {
        _context = _persistent ? WK(webkit_web_context_get_default)() : WK(webkit_web_context_new_ephemeral)();
        if (_persistent)
            g_object_ref(_context);
    }
    return _context;
}

- (void)dealloc
{
    if (_context)
        g_object_unref(_context);
    [super dealloc];
}

+ (NSSet *)allWebsiteDataTypes
{
    return [NSSet setWithObjects:WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                                 WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeCookies,
                                 WKWebsiteDataTypeSessionStorage, WKWebsiteDataTypeLocalStorage,
                                 WKWebsiteDataTypeWebSQLDatabases, WKWebsiteDataTypeIndexedDBDatabases,
                                 WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeServiceWorkerRegistrations, nil];
}

static void data_cleared(void *source, GAsyncResult *result, void *data)
{
    @autoreleasepool {
        WK(webkit_website_data_manager_clear_finish)(source, result, NULL);
        void (^done)(void) = data;
        if (done)
            done();
        [done release];
    }
}

- (void)removeDataOfTypes:(NSSet *)types modifiedSince:(NSDate *)date completionHandler:(void (^)(void))done
{
    WebKitWebContext *context = [self _context];
    int bits = 0;
    if ([types containsObject:WKWebsiteDataTypeDiskCache])
        bits |= WEBKIT_WEBSITE_DATA_DISK_CACHE;
    if ([types containsObject:WKWebsiteDataTypeMemoryCache])
        bits |= WEBKIT_WEBSITE_DATA_MEMORY_CACHE;
    if ([types containsObject:WKWebsiteDataTypeOfflineWebApplicationCache])
        bits |= WEBKIT_WEBSITE_DATA_OFFLINE_APPLICATION_CACHE;
    if ([types containsObject:WKWebsiteDataTypeCookies])
        bits |= WEBKIT_WEBSITE_DATA_COOKIES;
    if ([types containsObject:WKWebsiteDataTypeSessionStorage])
        bits |= WEBKIT_WEBSITE_DATA_SESSION_STORAGE;
    if ([types containsObject:WKWebsiteDataTypeLocalStorage])
        bits |= WEBKIT_WEBSITE_DATA_LOCAL_STORAGE;
    if ([types containsObject:WKWebsiteDataTypeIndexedDBDatabases])
        bits |= WEBKIT_WEBSITE_DATA_INDEXEDDB_DATABASES;
    if ([types containsObject:WKWebsiteDataTypeFetchCache])
        bits |= WEBKIT_WEBSITE_DATA_DOM_CACHE;
    if ([types containsObject:WKWebsiteDataTypeServiceWorkerRegistrations])
        bits |= WEBKIT_WEBSITE_DATA_SERVICE_WORKER_REGISTRATIONS;
    if (!context || !bits) {
        if (done)
            dispatch_async(dispatch_get_main_queue(), done);
        return;
    }
    /* WebKitGTK takes how far back to go: 0 for everything */
    NSTimeInterval back = date ? -[date timeIntervalSinceNow] : 0;
    int64_t span = back > 0 && back < 1e9 ? (int64_t)(back * 1e6) : 0;
    WK(webkit_website_data_manager_clear)(WK(webkit_web_context_get_website_data_manager)(context), bits, span, NULL,
                                          data_cleared, [done copy]);
}
@end

/* ---- the configuration -------------------------------------------------------------- */

@implementation WKWebViewConfiguration {
    GtkWidget *_relatedView;
}
WK_CODING
@synthesize processPool = _processPool, preferences = _preferences, userContentController = _userContentController,
            websiteDataStore = _websiteDataStore, defaultWebpagePreferences = _defaultWebpagePreferences,
            applicationNameForUserAgent = _applicationNameForUserAgent,
            suppressesIncrementalRendering = _suppressesIncrementalRendering,
            allowsAirPlayForMediaPlayback = _allowsAirPlay,
            limitsNavigationsToAppBoundDomains = _limitsNavigations, upgradeKnownHostsToHTTPS = _upgradeHosts;

- (instancetype)init
{
    self = [super init];
    _processPool = [WKProcessPool new];
    _preferences = [WKPreferences new];
    _userContentController = [WKUserContentController new];
    _websiteDataStore = [[WKWebsiteDataStore defaultDataStore] retain];
    _defaultWebpagePreferences = [WKWebpagePreferences new];
    _allowsAirPlay = YES;
    return self;
}

/* A copy shares the configuration's objects, as on a Mac: a script handler
 * added to a web view's configuration's controller reaches the web view. */
- (id)copyWithZone:(NSZone *)zone
{
    WKWebViewConfiguration *c = [[WKWebViewConfiguration alloc] init];
    c.processPool = _processPool;
    c.preferences = _preferences;
    c.userContentController = _userContentController;
    c.websiteDataStore = _websiteDataStore;
    c.defaultWebpagePreferences = _defaultWebpagePreferences;
    c.applicationNameForUserAgent = _applicationNameForUserAgent;
    c.suppressesIncrementalRendering = _suppressesIncrementalRendering;
    c.allowsAirPlayForMediaPlayback = _allowsAirPlay;
    c.limitsNavigationsToAppBoundDomains = _limitsNavigations;
    c.upgradeKnownHostsToHTTPS = _upgradeHosts;
    c->_relatedView = _relatedView;
    return c;
}

- (GtkWidget *)_relatedView { return _relatedView; }
- (void)set_relatedView:(GtkWidget *)view { _relatedView = view; }

- (void)dealloc
{
    [_processPool release];
    [_preferences release];
    [_userContentController release];
    [_websiteDataStore release];
    [_defaultWebpagePreferences release];
    [_applicationNameForUserAgent release];
    [super dealloc];
}
@end

/* ---- frames, navigations and the back-forward list ---------------------------------- */

@implementation WKSecurityOrigin {
    NSString *_protocol, *_host;
    NSInteger _port;
}
+ (WKSecurityOrigin *)_originOf:(NSURL *)url
{
    WKSecurityOrigin *o = [[[WKSecurityOrigin alloc] init] autorelease];
    o->_protocol = [[url scheme] ?: @"" copy];
    o->_host = [[url host] ?: @"" copy];
    o->_port = [[url port] integerValue];
    return o;
}
- (NSString *)protocol { return _protocol; }
- (NSString *)host { return _host; }
- (NSInteger)port { return _port; }
- (void)dealloc
{
    [_protocol release];
    [_host release];
    [super dealloc];
}
@end

@implementation WKFrameInfo {
    NSURLRequest *_request;
    WKSecurityOrigin *_origin;
    id _webView;   /* weak */
}
+ (WKFrameInfo *)_mainFrameOf:(WKWebView *)view request:(NSURLRequest *)request
{
    WKFrameInfo *f = [[[WKFrameInfo alloc] init] autorelease];
    if (!request)
        request = [NSURLRequest requestWithURL:[view URL] ?: [NSURL URLWithString:@"about:blank"]];
    f->_request = [request retain];
    f->_origin = [[WKSecurityOrigin _originOf:[request URL]] retain];
    objc_storeWeak(&f->_webView, view);
    return f;
}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isMainFrame { return YES; }
- (NSURLRequest *)request { return _request; }
- (WKSecurityOrigin *)securityOrigin { return _origin; }
- (WKWebView *)webView { return objc_loadWeak(&_webView); }
- (void)dealloc
{
    objc_storeWeak(&_webView, nil);
    [_request release];
    [_origin release];
    [super dealloc];
}
@end

@implementation WKNavigation
- (WKContentMode)effectiveContentMode { return WKContentModeDesktop; }
@end

@implementation WKNavigationAction {
    WKFrameInfo *_source, *_target;
    WKNavigationType _type;
    NSURLRequest *_request;
    NSEventModifierFlags _modifiers;
    NSInteger _button;
}
+ (WKNavigationAction *)_actionFrom:(WebKitNavigationAction *)action view:(WKWebView *)view newWindow:(BOOL)newWindow
{
    WKNavigationAction *a = [[[WKNavigationAction alloc] init] autorelease];
    int type = WK(webkit_navigation_action_get_navigation_type)(action);
    a->_type = type >= WEBKIT_NAVIGATION_TYPE_LINK_CLICKED && type < WEBKIT_NAVIGATION_TYPE_OTHER
                   ? (WKNavigationType)type
                   : WKNavigationTypeOther;
    a->_request = [WKRequest(WK(webkit_navigation_action_get_request)(action)) retain];
    a->_modifiers = WKModifiers(WK(webkit_navigation_action_get_modifiers)(action));
    /* GTK counts buttons from 1 (and 0 for none); NSEvent counts from 0 */
    unsigned button = WK(webkit_navigation_action_get_mouse_button)(action);
    a->_button = button == 3 ? 1 : button == 2 ? 2 : 0;
    a->_source = [[WKFrameInfo _mainFrameOf:view request:nil] retain];
    a->_target = newWindow ? nil : [[WKFrameInfo _mainFrameOf:view request:a->_request] retain];
    return a;
}
- (WKFrameInfo *)sourceFrame { return _source; }
- (WKFrameInfo *)targetFrame { return _target; }
- (WKNavigationType)navigationType { return _type; }
- (NSURLRequest *)request { return _request; }
- (NSEventModifierFlags)modifierFlags { return _modifiers; }
- (NSInteger)buttonNumber { return _button; }
- (BOOL)shouldPerformDownload { return NO; }
- (void)dealloc
{
    [_source release];
    [_target release];
    [_request release];
    [super dealloc];
}
@end

@implementation WKNavigationResponse {
    BOOL _main, _canShow;
    NSURLResponse *_response;
}
+ (WKNavigationResponse *)_responseFrom:(WebKitPolicyDecision *)decision
{
    WKNavigationResponse *r = [[[WKNavigationResponse alloc] init] autorelease];
    r->_main = WK(webkit_response_policy_decision_is_main_frame_main_resource)(decision);
    r->_canShow = WK(webkit_response_policy_decision_is_mime_type_supported)(decision);
    r->_response = [WKResponse(WK(webkit_response_policy_decision_get_response)(decision)) retain];
    return r;
}
- (BOOL)isForMainFrame { return _main; }
- (NSURLResponse *)response { return _response; }
- (BOOL)canShowMIMEType { return _canShow; }
- (void)dealloc
{
    [_response release];
    [super dealloc];
}
@end

/* a new window's features aren't known: each is nil, as on a Mac when the
 * page didn't say */
@implementation WKWindowFeatures
- (NSNumber *)menuBarVisibility { return nil; }
- (NSNumber *)statusBarVisibility { return nil; }
- (NSNumber *)toolbarsVisibility { return nil; }
- (NSNumber *)allowsResizing { return nil; }
- (NSNumber *)x { return nil; }
- (NSNumber *)y { return nil; }
- (NSNumber *)width { return nil; }
- (NSNumber *)height { return nil; }
@end

@implementation WKBackForwardListItem {
    WebKitBackForwardListItem *_item;
}
+ (WKBackForwardListItem *)_itemFor:(WebKitBackForwardListItem *)item
{
    if (!item)
        return nil;
    WKBackForwardListItem *i = [[[WKBackForwardListItem alloc] init] autorelease];
    i->_item = g_object_ref(item);
    return i;
}
- (WebKitBackForwardListItem *)_item { return _item; }
- (NSURL *)URL
{
    NSString *s = WKString(WK(webkit_back_forward_list_item_get_uri)(_item));
    return s ? [NSURL URLWithString:s] : nil;
}
- (NSURL *)initialURL
{
    NSString *s = WKString(WK(webkit_back_forward_list_item_get_original_uri)(_item));
    return s ? [NSURL URLWithString:s] : nil;
}
- (NSString *)title { return WKString(WK(webkit_back_forward_list_item_get_title)(_item)); }
- (BOOL)isEqual:(id)other
{
    return [other isKindOfClass:[WKBackForwardListItem class]] && ((WKBackForwardListItem *)other)->_item == _item;
}
- (NSUInteger)hash { return (NSUInteger)_item; }
- (void)dealloc
{
    g_object_unref(_item);
    [super dealloc];
}
@end

@implementation WKBackForwardList {
    WebKitBackForwardList *_list;
}
- (instancetype)_initWithList:(WebKitBackForwardList *)list
{
    self = [super init];
    _list = list;
    if (_list)
        g_object_ref(_list);
    return self;
}
- (void)dealloc
{
    if (_list)
        g_object_unref(_list);
    [super dealloc];
}
- (WKBackForwardListItem *)currentItem
{
    return _list ? [WKBackForwardListItem _itemFor:WK(webkit_back_forward_list_get_current_item)(_list)] : nil;
}
- (WKBackForwardListItem *)backItem
{
    return _list ? [WKBackForwardListItem _itemFor:WK(webkit_back_forward_list_get_back_item)(_list)] : nil;
}
- (WKBackForwardListItem *)forwardItem
{
    return _list ? [WKBackForwardListItem _itemFor:WK(webkit_back_forward_list_get_forward_item)(_list)] : nil;
}
- (WKBackForwardListItem *)itemAtIndex:(NSInteger)index
{
    return _list ? [WKBackForwardListItem _itemFor:WK(webkit_back_forward_list_get_nth_item)(_list, (int)index)] : nil;
}
static NSArray *items_of(GList *list)
{
    NSMutableArray *a = [NSMutableArray array];
    for (GList *l = list; l; l = l->next)
        [a addObject:[WKBackForwardListItem _itemFor:l->data]];
    g_list_free(list);
    return a;
}
/* both lists run from the oldest item to the newest, as on a Mac */
- (NSArray *)backList
{
    if (!_list)
        return @[];
    return [[items_of(WK(webkit_back_forward_list_get_back_list)(_list)) reverseObjectEnumerator] allObjects];
}
- (NSArray *)forwardList { return _list ? items_of(WK(webkit_back_forward_list_get_forward_list)(_list)) : @[]; }
@end

@implementation WKSnapshotConfiguration
@synthesize rect = _rect, snapshotWidth = _snapshotWidth, afterScreenUpdates = _afterScreenUpdates;
- (instancetype)init
{
    self = [super init];
    _rect = NSZeroRect;
    _afterScreenUpdates = YES;
    return self;
}
- (id)copyWithZone:(NSZone *)zone
{
    WKSnapshotConfiguration *c = [[WKSnapshotConfiguration alloc] init];
    c.rect = _rect;
    c.snapshotWidth = _snapshotWidth;
    c.afterScreenUpdates = _afterScreenUpdates;
    return c;
}
- (void)dealloc
{
    [_snapshotWidth release];
    [super dealloc];
}
@end
