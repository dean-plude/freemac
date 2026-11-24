/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older web view of macOS (WebView, with WebFrame,
 * WebDataSource, WebPreferences and WebScriptObject), written from Apple's
 * public WebKit documentation. A WebView holds a WKWebView of Ferry's own
 * that fills it, so both web views show pages with the same WebKitGTK view;
 * an adapter turns the WKWebView's delegate calls into the older frame load,
 * policy and UI delegates' calls.
 *
 * The older calls that answer at once on a Mac (a script's result, a script
 * object's properties) wait for WebKitGTK's answer, running GLib's main
 * context meanwhile (WKWaitFor). Script objects are JavaScript values kept
 * in the page by number, in a table of Ferry's own (window.__ferryWS). */
#import "WKInternal.h"

NSString *const WebPreferencesChangedNotification = @"WebPreferencesChangedNotification";
NSString *const WebActionNavigationTypeKey = @"WebActionNavigationTypeKey";
NSString *const WebActionElementKey = @"WebActionElementKey";
NSString *const WebActionButtonKey = @"WebActionButtonKey";
NSString *const WebActionModifierFlagsKey = @"WebActionModifierFlagsKey";
NSString *const WebActionOriginalURLKey = @"WebActionOriginalURLKey";
NSString *const WebViewProgressStartedNotification = @"WebViewProgressStartedNotification";
NSString *const WebViewProgressEstimateChangedNotification = @"WebViewProgressEstimateChangedNotification";
NSString *const WebViewProgressFinishedNotification = @"WebViewProgressFinishedNotification";

@interface WebView (FerryPrivate)
- (WKWebView *)_wk;
@end

/* ---- preferences -------------------------------------------------------------------- */

@implementation WebPreferences {
    NSString *_identifier;
    NSMutableDictionary *_values;
    NSMutableArray *_settings;   /* NSValues of WebKitSettings, each with a reference */
}

static NSMutableDictionary *preferences_by_name;

+ (WebPreferences *)standardPreferences
{
    static WebPreferences *standard;
    if (!standard)
        standard = [[WebPreferences alloc] initWithIdentifier:nil];
    return standard;
}

/* the values a Mac starts with, as its documentation gives them */
static NSDictionary *preference_defaults(void)
{
    static NSDictionary *d;
    if (!d)
        d = [@{
            @"defaultFontSize" : @16,
            @"defaultFixedFontSize" : @13,
            @"minimumFontSize" : @0,
            @"minimumLogicalFontSize" : @9,
            @"defaultTextEncodingName" : @"ISO-8859-1",
            @"userStyleSheetEnabled" : @NO,
            @"javaEnabled" : @NO,
            @"javaScriptEnabled" : @YES,
            @"javaScriptCanOpenWindowsAutomatically" : @YES,
            @"plugInsEnabled" : @NO,
            @"allowsAnimatedImages" : @YES,
            @"allowsAnimatedImageLooping" : @YES,
            @"loadsImagesAutomatically" : @YES,
            @"autosaves" : @YES,
            @"shouldPrintBackgrounds" : @NO,
            @"privateBrowsingEnabled" : @NO,
            @"tabsToLinks" : @NO,
            @"usesPageCache" : @YES,
            @"cacheModel" : @(WebCacheModelDocumentViewer),
        } retain];
    return d;
}

- (instancetype)init { return [self initWithIdentifier:nil]; }

- (instancetype)initWithIdentifier:(NSString *)identifier
{
    if (identifier) {
        WebPreferences *existing = preferences_by_name[identifier];
        if (existing) {
            [self release];
            return [existing retain];
        }
    }
    self = [super init];
    _identifier = [identifier copy];
    _values = [NSMutableDictionary new];
    _settings = [NSMutableArray new];
    if (identifier) {
        if (!preferences_by_name)
            preferences_by_name = [NSMutableDictionary new];
        preferences_by_name[identifier] = self;   /* kept, as a Mac keeps them */
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *identifier = [coder allowsKeyedCoding] ? [coder decodeObjectForKey:@"Identifier"] : nil;
    return [self initWithIdentifier:identifier];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if ([coder allowsKeyedCoding] && _identifier)
        [coder encodeObject:_identifier forKey:@"Identifier"];
}

- (void)dealloc
{
    for (NSValue *v in _settings)
        g_object_unref([v pointerValue]);
    [_settings release];
    [_values release];
    [_identifier release];
    [super dealloc];
}

- (NSString *)identifier { return _identifier; }

- (id)_value:(NSString *)key { return _values[key] ?: preference_defaults()[key]; }

- (void)_set:(id)value forKey:(NSString *)key
{
    if (value)
        _values[key] = value;
    else
        [_values removeObjectForKey:key];
    for (NSValue *v in _settings)
        [self _applyTo:[v pointerValue]];
    [[NSNotificationCenter defaultCenter] postNotificationName:WebPreferencesChangedNotification object:self];
}

/* font families only once a program sets them: a Mac's own (Times,
 * Helvetica...) would be found under other names here */
- (void)_applyTo:(WebKitSettings *)s
{
    WK(webkit_settings_set_enable_javascript)(s, [[self _value:@"javaScriptEnabled"] boolValue]);
    WK(webkit_settings_set_javascript_can_open_windows_automatically)(
        s, [[self _value:@"javaScriptCanOpenWindowsAutomatically"] boolValue]);
    WK(webkit_settings_set_auto_load_images)(s, [[self _value:@"loadsImagesAutomatically"] boolValue]);
    WK(webkit_settings_set_enable_tabs_to_links)(s, [[self _value:@"tabsToLinks"] boolValue]);
    WK(webkit_settings_set_enable_page_cache)(s, [[self _value:@"usesPageCache"] boolValue]);
    WK(webkit_settings_set_default_font_size)(s, (uint32_t)[[self _value:@"defaultFontSize"] intValue]);
    WK(webkit_settings_set_default_monospace_font_size)(s, (uint32_t)[[self _value:@"defaultFixedFontSize"] intValue]);
    WK(webkit_settings_set_minimum_font_size)(s, (uint32_t)[[self _value:@"minimumFontSize"] intValue]);
    WK(webkit_settings_set_default_charset)(s, [[self _value:@"defaultTextEncodingName"] UTF8String]);
    struct {
        NSString *key;
        void (*set)(WebKitSettings *, const char *);
    } fonts[] = {
        {@"standardFontFamily", WK(webkit_settings_set_default_font_family)},
        {@"fixedFontFamily", WK(webkit_settings_set_monospace_font_family)},
        {@"serifFontFamily", WK(webkit_settings_set_serif_font_family)},
        {@"sansSerifFontFamily", WK(webkit_settings_set_sans_serif_font_family)},
        {@"cursiveFontFamily", WK(webkit_settings_set_cursive_font_family)},
        {@"fantasyFontFamily", WK(webkit_settings_set_fantasy_font_family)},
    };
    for (size_t i = 0; i < sizeof fonts / sizeof *fonts; i++) {
        NSString *family = _values[fonts[i].key];
        if ([family length])
            fonts[i].set(s, [family UTF8String]);
    }
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

#define WEB_PREF_OBJECT(getter, setter, key)                                                                \
    -(id)getter { return [self _value:key]; }                                                               \
    -(void)setter : (id)value { [self _set:[[value copy] autorelease] forKey:key]; }
#define WEB_PREF_INT(getter, setter, key)                                                                   \
    -(int)getter { return [[self _value:key] intValue]; }                                                   \
    -(void)setter : (int)value { [self _set:@(value) forKey:key]; }
#define WEB_PREF_BOOL(getter, setter, key)                                                                  \
    -(BOOL)getter { return [[self _value:key] boolValue]; }                                                 \
    -(void)setter : (BOOL)value { [self _set:@(value) forKey:key]; }

/* the families a program hasn't set are the ones a Mac starts with */
- (NSString *)_family:(NSString *)key or:(NSString *)mac { return _values[key] ?: mac; }
- (NSString *)standardFontFamily { return [self _family:@"standardFontFamily" or:@"Times"]; }
- (void)setStandardFontFamily:(NSString *)f { [self _set:[[f copy] autorelease] forKey:@"standardFontFamily"]; }
- (NSString *)fixedFontFamily { return [self _family:@"fixedFontFamily" or:@"Courier"]; }
- (void)setFixedFontFamily:(NSString *)f { [self _set:[[f copy] autorelease] forKey:@"fixedFontFamily"]; }
- (NSString *)serifFontFamily { return [self _family:@"serifFontFamily" or:@"Times"]; }
- (void)setSerifFontFamily:(NSString *)f { [self _set:[[f copy] autorelease] forKey:@"serifFontFamily"]; }
- (NSString *)sansSerifFontFamily { return [self _family:@"sansSerifFontFamily" or:@"Helvetica"]; }
- (void)setSansSerifFontFamily:(NSString *)f { [self _set:[[f copy] autorelease] forKey:@"sansSerifFontFamily"]; }
- (NSString *)cursiveFontFamily { return [self _family:@"cursiveFontFamily" or:@"Apple Chancery"]; }
- (void)setCursiveFontFamily:(NSString *)f { [self _set:[[f copy] autorelease] forKey:@"cursiveFontFamily"]; }
- (NSString *)fantasyFontFamily { return [self _family:@"fantasyFontFamily" or:@"Papyrus"]; }
- (void)setFantasyFontFamily:(NSString *)f { [self _set:[[f copy] autorelease] forKey:@"fantasyFontFamily"]; }
WEB_PREF_INT(defaultFontSize, setDefaultFontSize, @"defaultFontSize")
WEB_PREF_INT(defaultFixedFontSize, setDefaultFixedFontSize, @"defaultFixedFontSize")
WEB_PREF_INT(minimumFontSize, setMinimumFontSize, @"minimumFontSize")
WEB_PREF_INT(minimumLogicalFontSize, setMinimumLogicalFontSize, @"minimumLogicalFontSize")
WEB_PREF_OBJECT(defaultTextEncodingName, setDefaultTextEncodingName, @"defaultTextEncodingName")
WEB_PREF_BOOL(userStyleSheetEnabled, setUserStyleSheetEnabled, @"userStyleSheetEnabled")
- (NSURL *)userStyleSheetLocation { return _values[@"userStyleSheetLocation"]; }
- (void)setUserStyleSheetLocation:(NSURL *)url
{
    if (url)
        WKWarnOnce("WebPreferences' user style sheets");
    [self _set:url forKey:@"userStyleSheetLocation"];
}
WEB_PREF_BOOL(isJavaEnabled, setJavaEnabled, @"javaEnabled")
WEB_PREF_BOOL(isJavaScriptEnabled, setJavaScriptEnabled, @"javaScriptEnabled")
WEB_PREF_BOOL(javaScriptCanOpenWindowsAutomatically, setJavaScriptCanOpenWindowsAutomatically,
              @"javaScriptCanOpenWindowsAutomatically")
WEB_PREF_BOOL(plugInsEnabled, setPlugInsEnabled, @"plugInsEnabled")
WEB_PREF_BOOL(allowsAnimatedImages, setAllowsAnimatedImages, @"allowsAnimatedImages")
WEB_PREF_BOOL(allowsAnimatedImageLooping, setAllowsAnimatedImageLooping, @"allowsAnimatedImageLooping")
WEB_PREF_BOOL(loadsImagesAutomatically, setLoadsImagesAutomatically, @"loadsImagesAutomatically")
WEB_PREF_BOOL(autosaves, setAutosaves, @"autosaves")
WEB_PREF_BOOL(shouldPrintBackgrounds, setShouldPrintBackgrounds, @"shouldPrintBackgrounds")
WEB_PREF_BOOL(privateBrowsingEnabled, setPrivateBrowsingEnabled, @"privateBrowsingEnabled")
WEB_PREF_BOOL(tabsToLinks, setTabsToLinks, @"tabsToLinks")
WEB_PREF_BOOL(usesPageCache, setUsesPageCache, @"usesPageCache")
- (WebCacheModel)cacheModel { return [[self _value:@"cacheModel"] unsignedIntegerValue]; }
- (void)setCacheModel:(WebCacheModel)model { [self _set:@(model) forKey:@"cacheModel"]; }
@end

/* ---- script objects ----------------------------------------------------------------- */

@implementation WebUndefined
+ (WebUndefined *)undefined
{
    static WebUndefined *one;
    if (!one)
        one = [[WebUndefined alloc] init];
    return one;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    [self release];
    return [[WebUndefined undefined] retain];
}
- (void)encodeWithCoder:(NSCoder *)coder {}
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (NSString *)description { return @"undefined"; }
@end

/* The page's half: a table of the values handed out, and the turning of a
 * value into what comes back (undefined, null, a plain value or a number
 * in the table). Put in front of every script, so a new page has it too. */
static NSString *const script_table =
    @"var W=window.__ferryWS||(window.__ferryWS={n:1,o:{0:window},"
    @"tag:function(v){if(v===undefined)return{t:'u'};if(v===null)return{t:'n'};var y=typeof v;"
    @"if(y==='string'||y==='number'||y==='boolean')return{t:'p',v:v};"
    @"var i=this.n++;this.o[i]=v;return{t:'o',i:i};}});";

@interface WebScriptObject ()
- (instancetype)_initWithWeb:(GtkWidget *)web handle:(long)handle;
- (NSString *)_expression;
@end

/* What a script gave back, as the older WebKit's objects: NSString,
 * NSNumber, NSNull for null, WebUndefined, or a WebScriptObject. */
static id script_result(GtkWidget *web, NSString *json)
{
    NSDictionary *tag = json ? WKObjectFromJSON([json UTF8String]) : nil;
    NSString *t = [tag isKindOfClass:[NSDictionary class]] ? tag[@"t"] : nil;
    if ([t isEqualToString:@"p"])
        return tag[@"v"];
    if ([t isEqualToString:@"n"])
        return [NSNull null];
    if ([t isEqualToString:@"o"])
        return [[[WebScriptObject alloc] _initWithWeb:web handle:[tag[@"i"] longValue]] autorelease];
    return [WebUndefined undefined];
}

/* runs a script's body (which uses W, the table) and waits for its tagged result */
static id run_tagged(GtkWidget *web, NSString *body)
{
    if (!web)
        return [WebUndefined undefined];
    NSString *script = [NSString stringWithFormat:@"(function(){%@try{return W.tag((function(){%@})());}"
                                                  @"catch(e){return{t:'x',m:String(e)};}})()",
                                                  script_table, body];
    return script_result(web, WKEvaluateJSONSync(web, script));
}

/* an Objective-C value as a JavaScript expression, for a script's arguments */
static NSString *script_literal(id value)
{
    if (!value || value == [NSNull null])
        return @"null";
    if ([value isKindOfClass:[WebUndefined class]])
        return @"undefined";
    if ([value isKindOfClass:[WebScriptObject class]])
        return [value _expression];
    if ([value isKindOfClass:[NSString class]])
        return WKQuote(value);
    if ([value isKindOfClass:[NSNumber class]]) {
        const char *type = [value objCType];
        if (!strcmp(type, @encode(BOOL)) || !strcmp(type, "B"))
            return [value boolValue] ? @"true" : @"false";
        return [value stringValue];
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id v in value)
            [parts addObject:script_literal(v)];
        return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id k in value)
            [parts addObject:[NSString stringWithFormat:@"%@:%@", WKQuote([k description]), script_literal(value[k])]];
        return [NSString stringWithFormat:@"({%@})", [parts componentsJoinedByString:@","]];
    }
    return WKQuote([value description]);
}

@implementation WebScriptObject {
    GtkWidget *_web;
    long _handle;
}

- (instancetype)_initWithWeb:(GtkWidget *)web handle:(long)handle
{
    self = [super init];
    _web = web ? g_object_ref(web) : NULL;
    _handle = handle;
    return self;
}

- (void)dealloc
{
    if (_web) {
        if (_handle)   /* the page may let go of the value now */
            WK(webkit_web_view_evaluate_javascript)(
                _web,
                [[NSString stringWithFormat:@"if(window.__ferryWS)delete window.__ferryWS.o[%ld]", _handle] UTF8String],
                -1, NULL, NULL, NULL, NULL, NULL);
        g_object_unref(_web);
    }
    [super dealloc];
}

/* the value, in the page; window itself when the table is gone (a new page) */
- (NSString *)_expression
{
    return _handle ? [NSString stringWithFormat:@"window.__ferryWS.o[%ld]", _handle] : @"window";
}

- (NSString *)_object { return [NSString stringWithFormat:@"var o=W.o[%ld];", _handle]; }

+ (BOOL)throwException:(NSString *)message
{
    WKWarnOnce("+[WebScriptObject throwException:]");
    return NO;
}

- (void)setException:(NSString *)description { WKWarnOnce("-[WebScriptObject setException:]"); }

/* run in the page's global scope, as a Mac does */
- (id)evaluateWebScript:(NSString *)script
{
    return run_tagged(_web, [NSString stringWithFormat:@"return (0,eval)(%@);", WKQuote(script ?: @"")]);
}

- (id)callWebScriptMethod:(NSString *)name withArguments:(NSArray *)arguments
{
    NSMutableArray *args = [NSMutableArray array];
    for (id a in arguments)
        [args addObject:script_literal(a)];
    return run_tagged(_web, [NSString stringWithFormat:@"%@var f=o[%@];if(typeof f!=='function')return undefined;"
                                                       @"return f.apply(o,[%@]);",
                                                       [self _object], WKQuote(name ?: @""),
                                                       [args componentsJoinedByString:@","]]);
}

- (id)valueForKey:(NSString *)key
{
    return run_tagged(_web, [NSString stringWithFormat:@"%@return o[%@];", [self _object], WKQuote(key ?: @"")]);
}

- (void)setValue:(id)value forKey:(NSString *)key
{
    if ([value isKindOfClass:[NSObject class]] && ![value isKindOfClass:[NSString class]] &&
        ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSNull class]] &&
        ![value isKindOfClass:[WebUndefined class]] && ![value isKindOfClass:[WebScriptObject class]] &&
        ![value isKindOfClass:[NSArray class]] && ![value isKindOfClass:[NSDictionary class]])
        WKWarnOnce("giving a page an Objective-C object of a program's own (its description is given instead)");
    run_tagged(_web, [NSString stringWithFormat:@"%@o[%@]=%@;return undefined;", [self _object], WKQuote(key ?: @""),
                                                script_literal(value)]);
}

- (void)removeWebScriptKey:(NSString *)name
{
    run_tagged(_web, [NSString stringWithFormat:@"%@delete o[%@];return undefined;", [self _object],
                                                WKQuote(name ?: @"")]);
}

- (NSString *)stringRepresentation
{
    id s = run_tagged(_web, [NSString stringWithFormat:@"%@return String(o);", [self _object]]);
    return [s isKindOfClass:[NSString class]] ? s : @"";
}

- (id)webScriptValueAtIndex:(unsigned)index
{
    return run_tagged(_web, [NSString stringWithFormat:@"%@return o[%u];", [self _object], index]);
}

- (void)setWebScriptValueAtIndex:(unsigned)index value:(id)value
{
    run_tagged(_web, [NSString stringWithFormat:@"%@o[%u]=%@;return undefined;", [self _object], index,
                                                script_literal(value)]);
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<WebScriptObject %@>", [self stringRepresentation]];
}
@end

/* ---- frames and their data ---------------------------------------------------------- */

@interface WebDataSource ()
- (void)_setFrame:(WebFrame *)frame;
- (void)_setResponse:(NSURLResponse *)response;
- (void)_setLoading:(BOOL)loading;
@end

@implementation WebDataSource {
    NSURLRequest *_initialRequest;
    NSMutableURLRequest *_request;
    NSURLResponse *_response;
    WebFrame *_frame;   /* not retained */
    BOOL _loading;
}

- (instancetype)initWithRequest:(NSURLRequest *)request
{
    self = [super init];
    _initialRequest = [request copy];
    _request = [request mutableCopy];
    _loading = YES;
    return self;
}

- (void)dealloc
{
    [_initialRequest release];
    [_request release];
    [_response release];
    [super dealloc];
}

- (void)_setFrame:(WebFrame *)frame { _frame = frame; }
- (void)_setResponse:(NSURLResponse *)response
{
    [_response release];
    _response = [response retain];
}
- (void)_setLoading:(BOOL)loading { _loading = loading; }

- (NSURLRequest *)initialRequest { return _initialRequest; }
- (NSMutableURLRequest *)request { return _request; }
- (NSURLResponse *)response { return _response; }
- (WebFrame *)webFrame { return _frame; }
- (BOOL)isLoading { return _loading; }
- (id)representation { return nil; }
- (NSURL *)unreachableURL { return nil; }
- (NSString *)textEncodingName { return [_response textEncodingName]; }
- (NSString *)pageTitle
{
    NSString *t = [[[_frame webView] _wk] title];
    return [t length] ? t : nil;
}

struct resource_data {
    volatile BOOL done;
    NSData *data;
};

static void resource_read(void *source, GAsyncResult *result, void *data)
{
    struct resource_data *r = data;
    size_t length = 0;
    unsigned char *bytes = WK(webkit_web_resource_get_data_finish)(source, result, &length, NULL);
    if (bytes) {
        r->data = [[NSData alloc] initWithBytes:bytes length:length];
        g_free(bytes);
    }
    r->done = YES;
}

/* the page's source as loaded, waited for */
- (NSData *)data
{
    GtkWidget *web = [[[_frame webView] _wk] _gtkWebView];
    WebKitWebResource *resource = web ? WK(webkit_web_view_get_main_resource)(web) : NULL;
    if (!resource)
        return nil;
    struct resource_data *r = calloc(1, sizeof *r);
    WK(webkit_web_resource_get_data)(resource, NULL, resource_read, r);
    if (!WKWaitFor(&r->done, 10))
        return nil;   /* r stays, for the answer that may still come */
    NSData *d = [r->data autorelease];
    free(r);
    return d;
}
@end

@interface WebFrame ()
- (instancetype)_initWithWebView:(WebView *)view;
- (void)_start:(NSURLRequest *)request;
- (void)_commit;
- (void)_finish;
- (void)_setResponse:(NSURLResponse *)response;
@end

@implementation WebFrame {
    WebView *_webView;   /* not retained: it owns this */
    WebDataSource *_dataSource, *_provisional;
}

- (instancetype)_initWithWebView:(WebView *)view
{
    self = [super init];
    _webView = view;
    return self;
}

- (void)dealloc
{
    [_dataSource release];
    [_provisional release];
    [super dealloc];
}

- (void)_start:(NSURLRequest *)request
{
    [_provisional release];
    _provisional = [[WebDataSource alloc] initWithRequest:request];
    [_provisional _setFrame:self];
}

- (void)_setResponse:(NSURLResponse *)response { [_provisional ?: _dataSource _setResponse:response]; }

- (void)_commit
{
    if (!_provisional)
        return;
    [_dataSource release];
    _dataSource = _provisional;
    _provisional = nil;
}

- (void)_finish
{
    [_dataSource _setLoading:NO];
    [_provisional release];
    _provisional = nil;
}

- (NSString *)name { return @""; }
- (WebView *)webView { return _webView; }
- (WebDataSource *)dataSource { return _dataSource; }
- (WebDataSource *)provisionalDataSource { return _provisional; }
- (WebFrame *)parentFrame { return nil; }
- (NSArray *)childFrames
{
    WKWarnOnce("a WebFrame's child frames (each web view has its main frame alone)");
    return @[];
}
- (WebScriptObject *)windowObject { return [_webView windowScriptObject]; }
- (id)DOMDocument
{
    WKWarnOnce("WebKit's DOM classes (DOMDocument and the others; use scripts instead)");
    return nil;
}
- (id)frameElement { return nil; }
- (void)loadRequest:(NSURLRequest *)request { [[_webView _wk] loadRequest:request]; }
- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)encodingName
         baseURL:(NSURL *)URL
{
    [[_webView _wk] loadData:data ?: [NSData data] MIMEType:MIMEType characterEncodingName:encodingName baseURL:URL];
}
- (void)loadHTMLString:(NSString *)string baseURL:(NSURL *)URL { [[_webView _wk] loadHTMLString:string baseURL:URL]; }
- (void)loadAlternateHTMLString:(NSString *)string baseURL:(NSURL *)baseURL forUnreachableURL:(NSURL *)unreachableURL
{
    [[_webView _wk] loadHTMLString:string baseURL:baseURL];
}
- (void)stopLoading { [[_webView _wk] stopLoading]; }
- (void)reload { [[_webView _wk] reload]; }
- (void)reloadFromOrigin { [[_webView _wk] reloadFromOrigin]; }
- (WebFrame *)findFrameNamed:(NSString *)name
{
    if (![name length] || [name isEqualToString:@"_self"] || [name isEqualToString:@"_top"] ||
        [name isEqualToString:@"_current"] || [name isEqualToString:@"_parent"])
        return self;
    return nil;
}
@end

/* ---- the delegates ------------------------------------------------------------------ */

@interface WebPolicyListener : NSObject <WebPolicyDecisionListener> {
@public
    void (^_decide)(int);   /* 0 ignore, 1 use, 2 download */
}
@end
@implementation WebPolicyListener
- (void)_answer:(int)how
{
    void (^decide)(int) = _decide;
    _decide = nil;
    if (decide) {
        decide(how);
        [decide release];
    }
}
- (void)use { [self _answer:1]; }
- (void)download { [self _answer:2]; }
- (void)ignore { [self _answer:0]; }
- (void)dealloc
{
    [_decide release];
    [super dealloc];
}
@end

static NSDictionary *action_information(WKNavigationAction *action)
{
    WKNavigationType type = action.navigationType;
    WebNavigationType legacy = type >= WKNavigationTypeLinkActivated && type <= WKNavigationTypeFormResubmitted
                                   ? (WebNavigationType)type
                                   : WebNavigationTypeOther;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[WebActionNavigationTypeKey] = @(legacy);
    info[WebActionModifierFlagsKey] = @(action.modifierFlags);
    if (type == WKNavigationTypeLinkActivated)
        info[WebActionButtonKey] = @(action.buttonNumber);
    if (action.request.URL)
        info[WebActionOriginalURLKey] = action.request.URL;
    return info;
}

/* The WKWebView's delegate, on the WebView's behalf. */
@interface WebViewAdapter : NSObject <WKNavigationDelegate, WKUIDelegate> {
@public
    WebView *_view;   /* not retained: it owns this */
}
@end

@implementation WebViewAdapter

- (void)webView:(WKWebView *)wk decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))handler
{
    WebView *view = _view;
    id d = [view policyDelegate];
    BOOL newWindow = action.targetFrame == nil;
    WebPolicyListener *listener = [[[WebPolicyListener alloc] init] autorelease];
    void (^h)(WKNavigationActionPolicy) = [[handler copy] autorelease];
    NSURLRequest *request = action.request;
    listener->_decide = [^(int how) {
        if (how == 2)
            WKWarnOnce("downloads from a web view (the navigation was cancelled)");
        if (how == 1 && !newWindow)
            [[view mainFrame] _start:request];
        h(how == 1 ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
    } copy];
    if (newWindow && [d respondsToSelector:@selector(webView:decidePolicyForNewWindowAction:request:newFrameName:
                                                        decisionListener:)])
        [d webView:view decidePolicyForNewWindowAction:action_information(action) request:request newFrameName:@""
            decisionListener:listener];
    else if (!newWindow && [d respondsToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:
                                                              decisionListener:)])
        [d webView:view decidePolicyForNavigationAction:action_information(action) request:request
                     frame:[view mainFrame]
          decisionListener:listener];
    else
        [listener use];
}

- (void)webView:(WKWebView *)wk decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))handler
{
    WebView *view = _view;
    id d = [view policyDelegate];
    if (response.forMainFrame)
        [[view mainFrame] _setResponse:response.response];
    WebPolicyListener *listener = [[[WebPolicyListener alloc] init] autorelease];
    void (^h)(WKNavigationResponsePolicy) = [[handler copy] autorelease];
    BOOL canShow = response.canShowMIMEType;
    listener->_decide = [^(int how) {
        if (how == 2)
            WKWarnOnce("downloads from a web view (the navigation was cancelled)");
        h(how == 1 ? WKNavigationResponsePolicyAllow : WKNavigationResponsePolicyCancel);
    } copy];
    NSString *type = response.response.MIMEType ?: @"";
    if ([d respondsToSelector:@selector(webView:decidePolicyForMIMEType:request:frame:decisionListener:)])
        [d webView:view decidePolicyForMIMEType:type
                       request:[NSURLRequest requestWithURL:response.response.URL ?: [NSURL URLWithString:@"about:blank"]]
                         frame:[view mainFrame]
              decisionListener:listener];
    else if (canShow)
        [listener use];
    else
        [listener ignore];
}

- (void)webView:(WKWebView *)wk didStartProvisionalNavigation:(WKNavigation *)navigation
{
    WebView *view = _view;
    WebFrame *frame = [view mainFrame];
    if (![frame provisionalDataSource])   /* a load that didn't ask for a policy, as for loadHTMLString: */
        [frame _start:[NSURLRequest requestWithURL:wk.URL ?: [NSURL URLWithString:@"about:blank"]]];
    [[NSNotificationCenter defaultCenter] postNotificationName:WebViewProgressStartedNotification object:view];
    id d = [view frameLoadDelegate];
    if ([d respondsToSelector:@selector(webView:didStartProvisionalLoadForFrame:)])
        [d webView:view didStartProvisionalLoadForFrame:frame];
}

- (void)webView:(WKWebView *)wk didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation
{
    id d = [_view frameLoadDelegate];
    if ([d respondsToSelector:@selector(webView:didReceiveServerRedirectForProvisionalLoadForFrame:)])
        [d webView:_view didReceiveServerRedirectForProvisionalLoadForFrame:[_view mainFrame]];
}

- (void)webView:(WKWebView *)wk didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    WebView *view = _view;
    WebFrame *frame = [view mainFrame];
    id d = [view frameLoadDelegate];
    if ([d respondsToSelector:@selector(webView:didFailProvisionalLoadWithError:forFrame:)])
        [d webView:view didFailProvisionalLoadWithError:error forFrame:frame];
    [frame _finish];
    [[NSNotificationCenter defaultCenter] postNotificationName:WebViewProgressFinishedNotification object:view];
}

- (void)webView:(WKWebView *)wk didCommitNavigation:(WKNavigation *)navigation
{
    WebView *view = _view;
    WebFrame *frame = [view mainFrame];
    [frame _commit];
    id d = [view frameLoadDelegate];
    if ([d respondsToSelector:@selector(webView:didCommitLoadForFrame:)])
        [d webView:view didCommitLoadForFrame:frame];
    /* the page's window is new: a Mac says so before the page's scripts
     * run, which here (the page runs in a process of its own) can't be */
    if ([d respondsToSelector:@selector(webView:didClearWindowObject:forFrame:)])
        [d webView:view didClearWindowObject:[view windowScriptObject] forFrame:frame];
    else if ([d respondsToSelector:@selector(webView:windowScriptObjectAvailable:)])
        [d webView:view windowScriptObjectAvailable:[view windowScriptObject]];
}

- (void)webView:(WKWebView *)wk didFinishNavigation:(WKNavigation *)navigation
{
    WebView *view = _view;
    WebFrame *frame = [view mainFrame];
    [frame _finish];
    id d = [view frameLoadDelegate];
    if ([d respondsToSelector:@selector(webView:didFinishLoadForFrame:)])
        [d webView:view didFinishLoadForFrame:frame];
    [[NSNotificationCenter defaultCenter] postNotificationName:WebViewProgressFinishedNotification object:view];
}

- (void)webView:(WKWebView *)wk didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    WebView *view = _view;
    WebFrame *frame = [view mainFrame];
    [frame _finish];
    id d = [view frameLoadDelegate];
    if ([d respondsToSelector:@selector(webView:didFailLoadWithError:forFrame:)])
        [d webView:view didFailLoadWithError:error forFrame:frame];
    [[NSNotificationCenter defaultCenter] postNotificationName:WebViewProgressFinishedNotification object:view];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context
{
    WebView *view = _view;
    if ([keyPath isEqualToString:@"title"]) {
        NSString *title = [object title];
        id d = [view frameLoadDelegate];
        if ([title length] && [d respondsToSelector:@selector(webView:didReceiveTitle:forFrame:)])
            [d webView:view didReceiveTitle:title forFrame:[view mainFrame]];
    } else if ([keyPath isEqualToString:@"estimatedProgress"])
        [[NSNotificationCenter defaultCenter] postNotificationName:WebViewProgressEstimateChangedNotification
                                                            object:view];
}

- (void)webView:(WKWebView *)wk runJavaScriptAlertPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(void))handler
{
    id d = [_view UIDelegate];
    if ([d respondsToSelector:@selector(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:)])
        [d webView:_view runJavaScriptAlertPanelWithMessage:message initiatedByFrame:[_view mainFrame]];
    else if ([d respondsToSelector:@selector(webView:runJavaScriptAlertPanelWithMessage:)])
        [d webView:_view runJavaScriptAlertPanelWithMessage:message];
    handler();
}

- (void)webView:(WKWebView *)wk runJavaScriptConfirmPanelWithMessage:(NSString *)message
    initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(BOOL))handler
{
    id d = [_view UIDelegate];
    BOOL result = NO;
    if ([d respondsToSelector:@selector(webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:)])
        result = [d webView:_view runJavaScriptConfirmPanelWithMessage:message initiatedByFrame:[_view mainFrame]];
    else if ([d respondsToSelector:@selector(webView:runJavaScriptConfirmPanelWithMessage:)])
        result = [d webView:_view runJavaScriptConfirmPanelWithMessage:message];
    handler(result);
}

- (void)webView:(WKWebView *)wk runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
          defaultText:(NSString *)defaultText
     initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString *))handler
{
    id d = [_view UIDelegate];
    NSString *result = nil;
    if ([d respondsToSelector:@selector(webView:runJavaScriptTextInputPanelWithPrompt:defaultText:initiatedByFrame:)])
        result = [d webView:_view runJavaScriptTextInputPanelWithPrompt:prompt defaultText:defaultText
            initiatedByFrame:[_view mainFrame]];
    else if ([d respondsToSelector:@selector(webView:runJavaScriptTextInputPanelWithPrompt:defaultText:)])
        result = [d webView:_view runJavaScriptTextInputPanelWithPrompt:prompt defaultText:defaultText];
    handler(result);
}

/* A new window: the UI delegate makes a WebView, and the request is loaded
 * in it (the page that opened it gets null from window.open) */
- (WKWebView *)webView:(WKWebView *)wk createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action
         windowFeatures:(WKWindowFeatures *)features
{
    id d = [_view UIDelegate];
    if (![d respondsToSelector:@selector(webView:createWebViewWithRequest:)])
        return nil;
    NSURLRequest *request = action.request;
    WebView *opened = [d webView:_view createWebViewWithRequest:request];
    if (opened) {
        if (request.URL && ![request.URL.absoluteString isEqualToString:@""])
            [[opened mainFrame] loadRequest:request];
        id od = [opened UIDelegate];
        if ([od respondsToSelector:@selector(webViewShow:)])
            [od webViewShow:opened];
    }
    return nil;
}

- (void)webViewDidClose:(WKWebView *)wk
{
    id d = [_view UIDelegate];
    if ([d respondsToSelector:@selector(webViewClose:)])
        [d webViewClose:_view];
}
@end

/* ---- the web view ------------------------------------------------------------------- */

@implementation WebView {
    WKWebView *_wk;
    WebViewAdapter *_adapter;
    WebFrame *_mainFrame;
    WebPreferences *_preferences;
    WebScriptObject *_windowScriptObject;
    id _frameLoadDelegate, _policyDelegate, _UIDelegate, _resourceLoadDelegate, _downloadDelegate, _editingDelegate;
    NSString *_applicationName, *_groupName;
    NSWindow *_hostWindow;
    float _textSizeMultiplier;
    BOOL _editable, _drawsBackground, _shouldUpdateWhileOffscreen, _maintainsBackForwardList,
        _continuousSpellChecking, _closed;
}

+ (NSArray *)MIMETypesShownAsHTML
{
    return @[ @"text/html", @"application/xhtml+xml", @"image/svg+xml", @"text/xml", @"application/xml" ];
}

+ (BOOL)canShowMIMETypeAsHTML:(NSString *)type
{
    return [[self MIMETypesShownAsHTML] containsObject:[type lowercaseString]];
}

+ (BOOL)canShowMIMEType:(NSString *)type
{
    type = [type lowercaseString];
    return [self canShowMIMETypeAsHTML:type] || [type hasPrefix:@"text/"] || [type hasPrefix:@"image/"] ||
           [type isEqualToString:@"application/json"] || [type isEqualToString:@"application/javascript"];
}

- (void)_setUp
{
    _textSizeMultiplier = 1;
    _drawsBackground = YES;
    _maintainsBackForwardList = YES;
    _mainFrame = [[WebFrame alloc] _initWithWebView:self];
    _adapter = [[WebViewAdapter alloc] init];
    _adapter->_view = self;
    _wk = [[WKWebView alloc] initWithFrame:[self bounds] configuration:nil];
    [_wk setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _wk.navigationDelegate = _adapter;
    _wk.UIDelegate = _adapter;
    [_wk addObserver:_adapter forKeyPath:@"title" options:0 context:NULL];
    [_wk addObserver:_adapter forKeyPath:@"estimatedProgress" options:0 context:NULL];
    [self addSubview:_wk];
    [self setPreferences:[WebPreferences standardPreferences]];
    _windowScriptObject = [[WebScriptObject alloc] _initWithWeb:[_wk _gtkWebView] handle:0];
}

- (instancetype)initWithFrame:(NSRect)frame frameName:(NSString *)frameName groupName:(NSString *)groupName
{
    self = [super initWithFrame:frame];
    _groupName = [groupName copy];
    [self _setUp];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame frameName:nil groupName:nil]; }

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    [self _setUp];
    return self;
}

- (void)dealloc
{
    [_wk removeObserver:_adapter forKeyPath:@"title"];
    [_wk removeObserver:_adapter forKeyPath:@"estimatedProgress"];
    _wk.navigationDelegate = nil;
    _wk.UIDelegate = nil;
    if ([_wk _gtkSettings])
        [_preferences _removeSettings:[_wk _gtkSettings]];
    [_wk release];
    [_adapter release];
    [_mainFrame release];
    [_preferences release];
    [_windowScriptObject release];
    [_applicationName release];
    [_groupName release];
    [_hostWindow release];
    [super dealloc];
}

- (WKWebView *)_wk { return _wk; }

- (void)close
{
    if (_closed)
        return;
    _closed = YES;
    [_wk stopLoading];
}

- (WebFrame *)mainFrame { return _mainFrame; }

/* the delegates aren't retained, as on a Mac */
- (id<WebFrameLoadDelegate>)frameLoadDelegate { return _frameLoadDelegate; }
- (void)setFrameLoadDelegate:(id<WebFrameLoadDelegate>)d { _frameLoadDelegate = d; }
- (id<WebPolicyDelegate>)policyDelegate { return _policyDelegate; }
- (void)setPolicyDelegate:(id<WebPolicyDelegate>)d { _policyDelegate = d; }
- (id<WebUIDelegate>)UIDelegate { return _UIDelegate; }
- (void)setUIDelegate:(id<WebUIDelegate>)d { _UIDelegate = d; }
- (id)resourceLoadDelegate { return _resourceLoadDelegate; }
- (void)setResourceLoadDelegate:(id)d
{
    if (d)
        WKWarnOnce("WebView's resource load delegate (it is kept and not called)");
    _resourceLoadDelegate = d;
}
- (id)downloadDelegate { return _downloadDelegate; }
- (void)setDownloadDelegate:(id)d { _downloadDelegate = d; }
- (id)editingDelegate { return _editingDelegate; }
- (void)setEditingDelegate:(id)d { _editingDelegate = d; }

- (WebPreferences *)preferences { return _preferences; }
- (void)setPreferences:(WebPreferences *)preferences
{
    preferences = preferences ?: [WebPreferences standardPreferences];
    WebKitSettings *settings = [_wk _gtkSettings];
    if (settings && _preferences)
        [_preferences _removeSettings:settings];
    [preferences retain];
    [_preferences release];
    _preferences = preferences;
    if (settings)
        [_preferences _addSettings:settings];
}
- (NSString *)preferencesIdentifier { return [_preferences identifier]; }
- (void)setPreferencesIdentifier:(NSString *)identifier
{
    [self setPreferences:[[[WebPreferences alloc] initWithIdentifier:identifier] autorelease]];
}

- (NSString *)customUserAgent { return [_wk customUserAgent]; }
- (void)setCustomUserAgent:(NSString *)agent { [_wk setCustomUserAgent:agent]; }
- (NSString *)applicationNameForUserAgent { return _applicationName; }
- (void)setApplicationNameForUserAgent:(NSString *)name
{
    [_applicationName release];
    _applicationName = [name copy];
    [_wk _setApplicationName:name];
}
- (NSString *)userAgentForURL:(NSURL *)URL
{
    WebKitSettings *s = [_wk _gtkSettings];
    return s ? WKString(WK(webkit_settings_get_user_agent)(s)) : @"";
}

- (NSString *)mainFrameURL
{
    NSURL *url = [[[_mainFrame provisionalDataSource] request] URL] ?: [_wk URL];
    return [url absoluteString] ?: @"";
}
- (void)setMainFrameURL:(NSString *)URLString
{
    NSURL *url = [URLString length] ? [NSURL URLWithString:URLString] : nil;
    if (url)
        [_mainFrame loadRequest:[NSURLRequest requestWithURL:url]];
}
- (NSString *)mainFrameTitle { return [_wk title] ?: @""; }
- (BOOL)isLoading { return [_wk isLoading]; }
- (double)estimatedProgress { return [_wk estimatedProgress]; }
- (BOOL)canGoBack { return [_wk canGoBack]; }
- (BOOL)canGoForward { return [_wk canGoForward]; }
- (BOOL)goBack { return [_wk goBack] != nil; }
- (BOOL)goForward { return [_wk goForward] != nil; }

- (float)textSizeMultiplier { return _textSizeMultiplier; }
- (void)setTextSizeMultiplier:(float)m
{
    _textSizeMultiplier = m > 0 ? m : 1;
    [_wk setPageZoom:_textSizeMultiplier];
}
- (BOOL)canMakeTextLarger { return _textSizeMultiplier < 3; }
- (BOOL)canMakeTextSmaller { return _textSizeMultiplier > 0.5; }
- (BOOL)canMakeTextStandardSize { return _textSizeMultiplier != 1; }
- (IBAction)makeTextLarger:(id)sender
{
    if ([self canMakeTextLarger])
        [self setTextSizeMultiplier:_textSizeMultiplier * 1.2f];
}
- (IBAction)makeTextSmaller:(id)sender
{
    if ([self canMakeTextSmaller])
        [self setTextSizeMultiplier:_textSizeMultiplier / 1.2f];
}
- (IBAction)makeTextStandardSize:(id)sender { [self setTextSizeMultiplier:1]; }

- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)editable
{
    _editable = editable;
    GtkWidget *web = [_wk _gtkWebView];
    if (web)
        WK(webkit_web_view_set_editable)(web, editable);
}
- (BOOL)drawsBackground { return _drawsBackground; }
- (void)setDrawsBackground:(BOOL)draws
{
    _drawsBackground = draws;
    GtkWidget *web = [_wk _gtkWebView];
    GdkRGBA color = {1, 1, 1, draws ? 1 : 0};
    if (web)
        WK(webkit_web_view_set_background_color)(web, &color);
}
- (BOOL)shouldUpdateWhileOffscreen { return _shouldUpdateWhileOffscreen; }
- (void)setShouldUpdateWhileOffscreen:(BOOL)flag { _shouldUpdateWhileOffscreen = flag; }
- (BOOL)maintainsBackForwardList { return _maintainsBackForwardList; }
- (void)setMaintainsBackForwardList:(BOOL)flag { _maintainsBackForwardList = flag; }
- (BOOL)continuousSpellCheckingEnabled { return _continuousSpellChecking; }
- (void)setContinuousSpellCheckingEnabled:(BOOL)flag { _continuousSpellChecking = flag; }
- (NSWindow *)hostWindow { return _hostWindow; }
- (void)setHostWindow:(NSWindow *)window
{
    [window retain];
    [_hostWindow release];
    _hostWindow = window;
}
- (NSString *)groupName { return _groupName; }
- (void)setGroupName:(NSString *)name
{
    [_groupName release];
    _groupName = [name copy];
}

- (WebScriptObject *)windowScriptObject { return _windowScriptObject; }

/* the script's value as text: strings, numbers and booleans; "" for the rest */
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script
{
    GtkWidget *web = [_wk _gtkWebView];
    if (!web)
        return @"";
    NSString *wrapped = [NSString
        stringWithFormat:@"(function(){try{var r=(0,eval)(%@);var y=typeof r;"
                         @"return y==='string'?r:(y==='number'||y==='boolean')?String(r):'';}catch(e){return '';}})()",
                         WKQuote(script ?: @"")];
    id result = WKObjectFromJSON([WKEvaluateJSONSync(web, wrapped) UTF8String]);
    return [result isKindOfClass:[NSString class]] ? result : @"";
}

- (IBAction)takeStringURLFrom:(id)sender
{
    if ([sender respondsToSelector:@selector(stringValue)])
        [self setMainFrameURL:[sender stringValue]];
}
- (IBAction)stopLoading:(id)sender { [_wk stopLoading]; }
- (IBAction)reload:(id)sender { [_wk reload]; }
- (IBAction)reloadFromOrigin:(id)sender { [_wk reloadFromOrigin]; }
- (IBAction)goBack:(id)sender { [self goBack]; }
- (IBAction)goForward:(id)sender { [self goForward]; }

/* the keyboard goes to the page */
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder
{
    /* once AppKit is done making this the first responder */
    NSWindow *window = [self window];
    if (window && _wk)
        [window performSelector:@selector(makeFirstResponder:) withObject:_wk afterDelay:0];
    return YES;
}

- (NSArray *)_ferryPlacement { return [_wk _ferryPlacement]; }
@end
