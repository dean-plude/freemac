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
 * in the page by number, in a table of Ferry's own (window.__ferryWS).
 *
 * From freemac 1.217 (Ferry 0.42.0): the DOM objects (WebDOM.m) are script
 * objects too, each value of the page has one object while it is kept, and
 * an agent of Ferry's own, a script in a world of its own in every frame,
 * tells the web view about subframes' loads and the page's scrolling and
 * size (for WebFrameView.m), since WebKitGTK reports neither. The resource
 * load delegate hears WebKitGTK's resources, user style sheets are WebKitGTK's,
 * and a window opened by window.open is a web view related to its opener,
 * so the page gets the window. */
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

/* From a nib (freemac 1.229, Ferry 0.53.0): the identifier, and the
 * settings ferry-ibtool writes under the names they are kept by here. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSString *identifier = [coder allowsKeyedCoding] ? [coder decodeObjectForKey:@"Identifier"] : nil;
    if (![identifier isKindOfClass:[NSString class]])
        identifier = nil;
    if (!(self = [self initWithIdentifier:identifier]) || ![coder allowsKeyedCoding])
        return self;
    static NSString *const ints[] = {@"defaultFontSize", @"defaultFixedFontSize", @"minimumFontSize",
                                     @"minimumLogicalFontSize", nil};
    static NSString *const bools[] = {@"javaEnabled", @"javaScriptEnabled", @"javaScriptCanOpenWindowsAutomatically",
                                      @"plugInsEnabled", @"allowsAnimatedImages", @"allowsAnimatedImageLooping",
                                      @"loadsImagesAutomatically", @"autosaves", @"shouldPrintBackgrounds",
                                      @"privateBrowsingEnabled", @"userStyleSheetEnabled", @"tabsToLinks",
                                      @"usesPageCache", nil};
    static NSString *const strings[] = {@"standardFontFamily", @"fixedFontFamily", @"serifFontFamily",
                                        @"sansSerifFontFamily", @"cursiveFontFamily", @"fantasyFontFamily",
                                        @"defaultTextEncodingName", nil};
    for (int i = 0; ints[i]; i++)
        if ([coder containsValueForKey:ints[i]])
            [self _set:@([coder decodeIntegerForKey:ints[i]]) forKey:ints[i]];
    for (int i = 0; bools[i]; i++)
        if ([coder containsValueForKey:bools[i]])
            [self _set:@([coder decodeBoolForKey:bools[i]]) forKey:bools[i]];
    for (int i = 0; strings[i]; i++) {
        id v = [coder containsValueForKey:strings[i]] ? [coder decodeObjectForKey:strings[i]] : nil;
        if ([v isKindOfClass:[NSString class]])
            [self _set:v forKey:strings[i]];
    }
    return self;
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
/* each web view with these preferences reads the sheet again (WebView's _applyUserStyleSheet) */
- (void)setUserStyleSheetLocation:(NSURL *)url
{
    [self _set:[[url copy] autorelease] forKey:@"userStyleSheetLocation"];
}
WEB_PREF_BOOL(isJavaEnabled, setJavaEnabled, @"javaEnabled")
WEB_PREF_BOOL(isJavaScriptEnabled, setJavaScriptEnabled, @"javaScriptEnabled")
WEB_PREF_BOOL(javaScriptCanOpenWindowsAutomatically, setJavaScriptCanOpenWindowsAutomatically,
              @"javaScriptCanOpenWindowsAutomatically")
WEB_PREF_BOOL(arePlugInsEnabled, setPlugInsEnabled, @"plugInsEnabled")
- (BOOL)plugInsEnabled { return [self arePlugInsEnabled]; }
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
 * in the table). Put in front of every script, so a new page has it too.
 * A value keeps its number while the page lasts (ids), so it has one
 * object here; g tells this page's numbers from an earlier page's. For a
 * value, c is its JavaScript class and k what kind of node it is (twice
 * the node type, plus one for an HTML element), for the DOM class here.
 * force makes the next value a list of the kind the Mac's call gives.
 * (freemac 1.217, Ferry 0.42.0: ids, g, c, k, force, geo and path) */
static NSString *const script_table =
    @"var W=window.__ferryWS;if(!W)W=window.__ferryWS={n:1,o:{0:window},ids:new WeakMap(),force:null,"
    @"g:Date.now().toString(36)+Math.random().toString(36).slice(2),"
    @"tag:function(v){var f=this.force;this.force=null;if(v===undefined)return{t:'u'};if(v===null)return{t:'n'};"
    @"var y=typeof v;if(y==='string'||y==='number'||y==='boolean')return{t:'p',v:v};"
    @"if(v===window)return{t:'o',i:0,g:this.g,c:'Window',k:-1};"
    @"var i=this.ids.get(v);if(i===undefined){i=this.n++;this.ids.set(v,i);}this.o[i]=v;"
    @"return{t:'o',i:i,g:this.g,c:f||this.cls(v),k:this.kind(v)};},"
    @"cls:function(v){try{return Object.prototype.toString.call(v).slice(8,-1);}catch(e){return '';}},"
    @"kind:function(v){try{var t=v.nodeType;if(typeof t==='number'&&typeof v.nodeName==='string')"
    @"return t*2+(v.namespaceURI==='http://www.w3.org/1999/xhtml'?1:0);}catch(e){}return -1;},"
    @"geo:function(){var s=document.scrollingElement||document.documentElement;"
    @"return s?[scrollX,scrollY,s.scrollWidth,s.scrollHeight]:[scrollX,scrollY,0,0];},"
    @"path:function(w){var p=[];try{while(w&&w!==window){var u=w.parent;if(!u||u===w)return null;"
    @"var n=u.frames.length,i=0;for(;i<n;i++)if(u.frames[i]===w)break;if(i===n)return null;p.unshift(i);w=u;}}"
    @"catch(e){return null;}return w===window?p:null;}};";

/* the objects handed out, by web view, page and number (not retained) */
static NSMutableDictionary *wrappers;

static NSString *wrapper_key(GtkWidget *web, NSString *generation, long handle)
{
    return [NSString stringWithFormat:@"%p %@ %ld", web, generation, handle];
}

/* the page's size and scroll position, for the main frame's view */
static void page_geometry(GtkWidget *web, id geometry)
{
    if ([geometry isKindOfClass:[NSArray class]])
        [[[WSWebViewOf(web) mainFrame] frameView] _setPageGeometry:geometry];
}

static id wrapper_for(GtkWidget *web, NSDictionary *tag)
{
    long handle = [tag[@"i"] longValue];
    if (!handle) {
        WebView *view = WSWebViewOf(web);
        if (view)
            return [view windowScriptObject];
        return [[[WebScriptObject alloc] _initWithWeb:web handle:0 generation:nil] autorelease];
    }
    NSString *generation = [tag[@"g"] description] ?: @"";
    WebScriptObject *o = [wrappers[wrapper_key(web, generation, handle)] nonretainedObjectValue];
    if (o)
        return [[o retain] autorelease];
    Class c = WSClassFor([tag[@"c"] description], tag[@"k"] ? [tag[@"k"] intValue] : -1);
    return [[[c alloc] _initWithWeb:web handle:handle generation:generation] autorelease];
}

/* What a script gave back, as the older WebKit's objects: NSString,
 * NSNumber, NSNull for null, WebUndefined, or a WebScriptObject. */
static id script_result(GtkWidget *web, NSString *json, int flags)
{
    NSDictionary *tag = json ? WKObjectFromJSON([json UTF8String]) : nil;
    if (![tag isKindOfClass:[NSDictionary class]])
        return [WebUndefined undefined];
    if (tag[@"geo"])
        page_geometry(web, tag[@"geo"]);
    NSString *t = tag[@"t"];
    if ([t isEqualToString:@"p"])
        return tag[@"v"];
    if ([t isEqualToString:@"n"])
        return [NSNull null];
    if ([t isEqualToString:@"o"])
        return wrapper_for(web, tag);
    if ([t isEqualToString:@"x"] && (flags & WSRaise))
        [NSException raise:DOMException format:@"%@", tag[@"m"] ?: @"An exception occurred in the page"];
    return [WebUndefined undefined];
}

/* runs a script's body (which uses W, the table) and waits for its tagged result */
id WSRun(GtkWidget *web, NSString *body, int flags)
{
    if (!web)
        return [WebUndefined undefined];
    NSString *script = [NSString
        stringWithFormat:@"(function(){%@var r;try{r=W.tag((function(){%@})());}"
                         @"catch(e){W.force=null;r={t:'x',m:String(e&&e.message!==undefined?e.message:e)};}"
                         @"%@return r;})()",
                         script_table, body, (flags & WSGeometry) ? @"try{r.geo=W.geo();}catch(e){}" : @""];
    return script_result(web, WKEvaluateJSONSync(web, script), flags);
}

static id run_tagged(GtkWidget *web, NSString *body) { return WSRun(web, body, 0); }

/* an Objective-C value as a JavaScript expression, for a script's arguments */
NSString *WSLiteral(id value)
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
            [parts addObject:WSLiteral(v)];
        return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id k in value)
            [parts addObject:[NSString stringWithFormat:@"%@:%@", WKQuote([k description]), WSLiteral(value[k])]];
        return [NSString stringWithFormat:@"({%@})", [parts componentsJoinedByString:@","]];
    }
    return WKQuote([value description]);
}

WebView *WSWebViewOf(GtkWidget *web) { return web ? (WebView *)g_object_get_data(web, "ferry-webview") : nil; }

@implementation WebScriptObject {
    GtkWidget *_web;
    long _handle;
    NSString *_generation;   /* the page's, for its values; nil for the window */
}

- (instancetype)_initWithWeb:(GtkWidget *)web handle:(long)handle generation:(NSString *)generation
{
    self = [super init];
    _web = web ? g_object_ref(web) : NULL;
    _handle = handle;
    _generation = [generation copy];
    if (_web && _handle && _generation) {
        if (!wrappers)
            wrappers = [NSMutableDictionary new];
        wrappers[wrapper_key(_web, _generation, _handle)] = [NSValue valueWithNonretainedObject:self];
    }
    return self;
}

- (void)dealloc
{
    if (_web) {
        if (_handle && _generation) {
            [wrappers removeObjectForKey:wrapper_key(_web, _generation, _handle)];
            /* the page may let go of the value now */
            WK(webkit_web_view_evaluate_javascript)(
                _web,
                [[NSString stringWithFormat:@"if(window.__ferryWS&&window.__ferryWS.g===%@)"
                                            @"delete window.__ferryWS.o[%ld]",
                                            WKQuote(_generation), _handle] UTF8String],
                -1, NULL, NULL, NULL, NULL, NULL);
        }
        g_object_unref(_web);
    }
    [_generation release];
    [super dealloc];
}

- (GtkWidget *)_web { return _web; }

/* the value, in the page; window itself for the window object */
- (NSString *)_expression
{
    if (!_handle)
        return @"window";
    return [NSString stringWithFormat:@"(window.__ferryWS&&window.__ferryWS.g===%@?window.__ferryWS.o[%ld]:undefined)",
                                      WKQuote(_generation ?: @""), _handle];
}

- (NSString *)_object
{
    if (!_handle)
        return @"var o=window;";
    return [NSString stringWithFormat:@"var o=W.g===%@?W.o[%ld]:undefined;", WKQuote(_generation ?: @""), _handle];
}

- (id)_run:(NSString *)body flags:(int)flags
{
    return WSRun(_web, [[self _object] stringByAppendingString:body], flags);
}

+ (BOOL)throwException:(NSString *)message
{
    WKWarnOnce("+[WebScriptObject throwException:]");
    return NO;
}

- (void)setException:(NSString *)description { WKWarnOnce("-[WebScriptObject setException:]"); }

/* run in the page's global scope, as a Mac does */
- (id)evaluateWebScript:(NSString *)script
{
    /* a subframe's window evaluates in that frame */
    if (_handle)
        return [self _run:[NSString stringWithFormat:@"var s=%@;if(o&&o.window===o&&o!==window)return o.eval(s);"
                                                     @"return (0,eval)(s);",
                                                     WKQuote(script ?: @"")]
                    flags:0];
    return run_tagged(_web, [NSString stringWithFormat:@"return (0,eval)(%@);", WKQuote(script ?: @"")]);
}

- (id)callWebScriptMethod:(NSString *)name withArguments:(NSArray *)arguments
{
    NSMutableArray *args = [NSMutableArray array];
    for (id a in arguments)
        [args addObject:WSLiteral(a)];
    return [self _run:[NSString stringWithFormat:@"var f=o[%@];if(typeof f!=='function')return undefined;"
                                                 @"return f.apply(o,[%@]);",
                                                 WKQuote(name ?: @""), [args componentsJoinedByString:@","]]
                flags:0];
}

- (id)valueForKey:(NSString *)key
{
    return [self _run:[NSString stringWithFormat:@"return o[%@];", WKQuote(key ?: @"")] flags:0];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
    if ([value isKindOfClass:[NSObject class]] && ![value isKindOfClass:[NSString class]] &&
        ![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSNull class]] &&
        ![value isKindOfClass:[WebUndefined class]] && ![value isKindOfClass:[WebScriptObject class]] &&
        ![value isKindOfClass:[NSArray class]] && ![value isKindOfClass:[NSDictionary class]])
        WKWarnOnce("giving a page an Objective-C object of a program's own (its description is given instead)");
    [self _run:[NSString stringWithFormat:@"o[%@]=%@;return undefined;", WKQuote(key ?: @""), WSLiteral(value)]
         flags:0];
}

- (void)removeWebScriptKey:(NSString *)name
{
    [self _run:[NSString stringWithFormat:@"delete o[%@];return undefined;", WKQuote(name ?: @"")] flags:0];
}

- (NSString *)stringRepresentation
{
    id s = [self _run:@"return String(o);" flags:0];
    return [s isKindOfClass:[NSString class]] ? s : @"";
}

- (id)webScriptValueAtIndex:(unsigned)index
{
    return [self _run:[NSString stringWithFormat:@"return o[%u];", index] flags:0];
}

- (void)setWebScriptValueAtIndex:(unsigned)index value:(id)value
{
    [self _run:[NSString stringWithFormat:@"o[%u]=%@;return undefined;", index, WSLiteral(value)] flags:0];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%s %@>", class_getName([self class]), [self stringRepresentation]];
}
@end

/* ---- frames and their data ---------------------------------------------------------- */

@interface WebDataSource ()
- (void)_setFrame:(WebFrame *)frame;
- (void)_setResponse:(NSURLResponse *)response;
- (void)_setLoading:(BOOL)loading;
@end

@interface WebFrame () {
@public
    NSString *_announced;   /* a link the agent saw clicked in this frame, to be loaded here */
    NSString *_title;
    BOOL _started;          /* its load has been reported as started */
}
- (instancetype)_initWithWebView:(WebView *)view parent:(WebFrame *)parent index:(NSUInteger)index;
- (void)_setFrameView:(WebFrameView *)view;
- (void)_start:(NSURLRequest *)request;
- (void)_commit;
- (void)_finish;
- (void)_setResponse:(NSURLResponse *)response;
- (void)_setName:(NSString *)name;
- (NSMutableArray *)_children;
- (void)_setChildren:(NSArray *)tree;
- (void)_removeChildren;
- (void)_forget;
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
    id wasResponse = _response;
    _response = [response retain];
    [wasResponse release];
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
    NSString *t = [_frame parentFrame] ? _frame->_title : [[[_frame webView] _wk] title];
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

/* the page's source as loaded, waited for (WebKitGTK gives the main frame's alone) */
- (NSData *)data
{
    GtkWidget *web = [[[_frame webView] _wk] _gtkWebView];
    WebKitWebResource *resource = web && ![_frame parentFrame] ? WK(webkit_web_view_get_main_resource)(web) : NULL;
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

/* the page's frames, from the main frame's window: their names and URLs,
 * and theirs (a frame of another origin shows its count, not its insides) */
static NSString *const frame_tree_script =
    @"(function(){var f=function(w){var a=[],n=0;try{n=w.frames.length;}catch(e){}"
    @"for(var i=0;i<n;i++){var c=w.frames[i],nm='',u='';try{nm=c.name;u=c.location.href;}catch(e){"
    @"try{var l=w.document.querySelectorAll('iframe,frame');if(l[i])nm=l[i].name||'';}catch(e2){}}"
    @"a.push({n:nm,u:u,c:f(c)});}return a;};return f(window);})()";

@implementation WebFrame {
    WebView *_webView;   /* not retained: it owns this */
    WebFrame *_parent;   /* not retained: it owns this */
    NSUInteger _index;   /* in its parent's window.frames */
    NSString *_name;
    WebDataSource *_dataSource, *_provisional;
    WebFrameView *_frameView;
    NSMutableArray *_children;
}

- (instancetype)_initWithWebView:(WebView *)view parent:(WebFrame *)parent index:(NSUInteger)index
{
    self = [super init];
    _webView = view;
    _parent = parent;
    _index = index;
    _children = [NSMutableArray new];
    return self;
}

- (instancetype)_initWithWebView:(WebView *)view { return [self _initWithWebView:view parent:nil index:0]; }

- (void)dealloc
{
    [self _removeChildren];
    [_frameView _forget];
    [_frameView release];
    [_children release];
    [_dataSource release];
    [_provisional release];
    [_name release];
    [_title release];
    [_announced release];
    [super dealloc];
}

/* the web view is going: this frame and its children stay, if a program
 * keeps them, but lead nowhere */
- (void)_forget
{
    for (WebFrame *child in _children)
        [child _forget];
    _webView = nil;
}

- (void)_setFrameView:(WebFrameView *)view
{
    [view retain];
    [_frameView release];
    _frameView = view;
}

- (void)_setName:(NSString *)name
{
    if ([name isEqualToString:_name])
        return;
    id wasName = _name;
    _name = [name copy];
    [wasName release];
}

- (GtkWidget *)_web { return [[_webView _wk] _gtkWebView]; }

- (NSString *)_windowExpression
{
    return _parent ? [NSString stringWithFormat:@"%@.frames[%lu]", [_parent _windowExpression], (unsigned long)_index]
                   : @"window";
}

- (NSArray *)_path
{
    NSMutableArray *path = [NSMutableArray array];
    for (WebFrame *f = self; f->_parent; f = f->_parent)
        [path insertObject:@(f->_index) atIndex:0];
    return path;
}

- (NSMutableArray *)_children { return _children; }

- (void)_removeChildren
{
    for (WebFrame *child in _children)
        [child _forget];
    [_children removeAllObjects];
}

/* the frames the page has now: those at the same place are kept */
- (void)_setChildren:(NSArray *)tree
{
    if (![tree isKindOfClass:[NSArray class]])
        tree = @[];
    while ([_children count] > [tree count]) {
        [[_children lastObject] _forget];
        [_children removeLastObject];
    }
    for (NSUInteger i = 0; i < [tree count]; i++) {
        NSDictionary *t = [tree[i] isKindOfClass:[NSDictionary class]] ? tree[i] : @{};
        if (i == [_children count]) {
            WebFrame *child = [[[WebFrame alloc] _initWithWebView:_webView parent:self index:i] autorelease];
            [_children addObject:child];
        }
        WebFrame *child = _children[i];
        if ([t[@"n"] isKindOfClass:[NSString class]])
            [child _setName:t[@"n"]];
        NSString *u = [t[@"u"] isKindOfClass:[NSString class]] ? t[@"u"] : nil;
        if ([u length] && !child->_dataSource && !child->_provisional) {
            NSURL *url = [NSURL URLWithString:u];
            if (url) {
                [child _start:[NSURLRequest requestWithURL:url]];
                [child _commit];
                [child _finish];
            }
        }
        [child _setChildren:t[@"c"]];
    }
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
    [_title release];
    _title = nil;
}

- (void)_finish
{
    [_dataSource _setLoading:NO];
    [_provisional release];
    _provisional = nil;
    _started = NO;
}

- (NSString *)name { return _name ?: @""; }
- (WebView *)webView { return _webView; }
- (WebDataSource *)dataSource { return _dataSource; }
- (WebDataSource *)provisionalDataSource { return _provisional; }
- (WebFrame *)parentFrame { return _parent; }

- (NSArray *)childFrames
{
    GtkWidget *web = [self _web];
    if (web) {
        id tree = WKObjectFromJSON([WKEvaluateJSONSync(web, frame_tree_script) UTF8String]);
        [[_webView mainFrame] _setChildren:tree];
    }
    return [[_children copy] autorelease];
}

/* A subframe's view isn't in a window (WebKitGTK draws the subframe in
 * its page); its size and scroll position are read when it is asked for. */
- (WebFrameView *)frameView
{
    if (!_parent)
        return _frameView;
    if (!_frameView)
        _frameView = [[WebFrameView alloc] _initWithFrame:NSMakeRect(0, 0, 0, 0) webFrame:self];
    GtkWidget *web = [self _web];
    if (web) {
        NSString *script = [NSString
            stringWithFormat:@"(function(){try{var w=%@,d=w.document,s=d.scrollingElement||d.documentElement;"
                             @"return [w.scrollX,w.scrollY,s.scrollWidth,s.scrollHeight,w.innerWidth,w.innerHeight];}"
                             @"catch(e){return null;}})()",
                             [self _windowExpression]];
        NSArray *g = WKObjectFromJSON([WKEvaluateJSONSync(web, script) UTF8String]);
        if ([g isKindOfClass:[NSArray class]] && [g count] == 6) {
            CGFloat zoom = [_webView _zoom];
            [_frameView setFrameSize:NSMakeSize([g[4] doubleValue] * zoom, [g[5] doubleValue] * zoom)];
            [_frameView _setPageGeometry:[g subarrayWithRange:NSMakeRange(0, 4)]];
        }
    }
    return _frameView;
}

- (WebScriptObject *)windowObject
{
    if (!_parent)
        return [_webView windowScriptObject];
    id w = WSRun([self _web], [NSString stringWithFormat:@"return %@;", [self _windowExpression]], 0);
    return [w isKindOfClass:[WebScriptObject class]] ? w : nil;
}

- (DOMDocument *)DOMDocument
{
    id d = WSRun([self _web], [NSString stringWithFormat:@"return %@.document;", [self _windowExpression]], 0);
    return [d isKindOfClass:[DOMDocument class]] ? d : nil;
}

- (DOMHTMLElement *)frameElement
{
    if (!_parent)
        return nil;
    id e = WSRun([self _web], [NSString stringWithFormat:@"return %@.frameElement;", [self _windowExpression]], 0);
    if (![e isKindOfClass:[DOMHTMLElement class]])   /* another origin: the parent's list of frames */
        e = WSRun([self _web],
                  [NSString stringWithFormat:@"var w=%@,l=w.document.querySelectorAll('iframe,frame');"
                                             @"for(var i=0;i<l.length;i++)"
                                             @"if(l[i].contentWindow===w.frames[%lu])return l[i];"
                                             @"return null;",
                                             [_parent _windowExpression], (unsigned long)_index],
                  0);
    return [e isKindOfClass:[DOMHTMLElement class]] ? e : nil;
}

/* a subframe's loads are asked of its window */
/* the navigation this frame is about to ask about is its own */
- (void)_announce:(NSString *)url
{
    id wasAnnounced = _announced;
    _announced = [url copy];
    [wasAnnounced release];
}

- (void)_inFrame:(NSString *)body
{
    WSRun([self _web], [NSString stringWithFormat:@"var w=%@;%@return undefined;", [self _windowExpression], body], 0);
}

- (void)loadRequest:(NSURLRequest *)request
{
    if (!_parent) {
        [[_webView _wk] loadRequest:request];
        return;
    }
    NSString *url = [[request URL] absoluteString];
    if (url) {
        [self _announce:url];
        [self _inFrame:[NSString stringWithFormat:@"w.location.href=%@;", WKQuote(url)]];
    }
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)encodingName
         baseURL:(NSURL *)URL
{
    if (!_parent) {
        [[_webView _wk] loadData:data ?: [NSData data] MIMEType:MIMEType characterEncodingName:encodingName
                         baseURL:URL];
        return;
    }
    NSString *type = MIMEType ?: @"text/html";
    NSString *url = [NSString stringWithFormat:@"data:%@;base64,%@", type,
                                               [data ?: [NSData data] base64EncodedStringWithOptions:0]];
    [self _announce:url];
    [self _inFrame:[NSString stringWithFormat:@"w.location.href=%@;", WKQuote(url)]];
}

- (void)loadHTMLString:(NSString *)string baseURL:(NSURL *)URL
{
    if (!_parent) {
        [[_webView _wk] loadHTMLString:string baseURL:URL];
        return;
    }
    /* written into the frame's document, which keeps its URL */
    [self _inFrame:[NSString stringWithFormat:@"var d=w.document;d.open();d.write(%@);d.close();",
                                              WKQuote(string ?: @"")]];
}

- (void)loadAlternateHTMLString:(NSString *)string baseURL:(NSURL *)baseURL forUnreachableURL:(NSURL *)unreachableURL
{
    [self loadHTMLString:string baseURL:baseURL];
}

- (void)stopLoading
{
    if (_parent)
        [self _inFrame:@"w.stop();"];
    else
        [[_webView _wk] stopLoading];
}

- (void)reload
{
    if (_parent) {
        [self _announce:[[[_dataSource request] URL] absoluteString]];
        [self _inFrame:@"w.location.reload();"];
    } else
        [[_webView _wk] reload];
}

- (void)reloadFromOrigin
{
    if (_parent) {
        [self _announce:[[[_dataSource request] URL] absoluteString]];
        [self _inFrame:@"w.location.reload();"];
    } else
        [[_webView _wk] reloadFromOrigin];
}

- (WebFrame *)_findNamed:(NSString *)name
{
    if ([[self name] isEqualToString:name])
        return self;
    for (WebFrame *child in _children) {
        WebFrame *f = [child _findNamed:name];
        if (f)
            return f;
    }
    return nil;
}

- (WebFrame *)findFrameNamed:(NSString *)name
{
    if (![name length] || [name isEqualToString:@"_self"] || [name isEqualToString:@"_current"])
        return self;
    WebFrame *main = [_webView mainFrame] ?: self;
    if ([name isEqualToString:@"_top"])
        return main;
    if ([name isEqualToString:@"_parent"])
        return _parent ?: self;
    if ([name isEqualToString:@"_blank"])
        return nil;
    [main childFrames];   /* brought up to date */
    return [self _findNamed:name] ?: [main _findNamed:name];
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

/* Ferry's agent in each frame of the older web view's pages, in a world
 * of its own (freemac 1.217, Ferry 0.42.0). WebKitGTK reports the main
 * frame's loads alone, so a subframe's agent says when its document is
 * committed, has its title and has finished loading, and which link
 * clicked in it is to load there; the main frame's says when the page
 * scrolls or changes size. Each message names its frame by its path in
 * window.frames, and its web view by the number the web view gives the
 * main frame's agent when the page is committed (the views a page opens
 * share their opener's scripts): until then the messages wait. The number
 * is also left on the window, since the commit can reach the page before
 * the agent has started there, and the agent then picks it up itself. */
static const char agent_world[] = "ferry-webview";
static NSString *const agent_script =
    @"(function(){if(window.__ferryAgent)return;var A=window.__ferryAgent={v:window.__ferryView||0,q:[]};"
    @"var H=function(){try{return window.webkit.messageHandlers.ferryWebView;}catch(e){return null;}};"
    @"var root=function(){if(window===window.top)return A;"
    @"try{return window.top.__ferryAgent||null;}catch(e){return null;}};"
    @"var path=function(){var p=[],w=window;try{while(w!==w.parent){var u=w.parent,n=u.frames.length,i=0;"
    @"for(;i<n;i++)if(u.frames[i]===w)break;p.unshift(i);w=u;}}catch(e){}return p;};"
    @"A.post=function(m){var h=H();if(h)h.postMessage(m);};"
    @"A.send=function(m){m.p=path();var r=root();if(r&&!r.v){r.q.push(m);return;}m.v=r?r.v:0;A.post(m);};"
    @"A.setView=function(v){A.v=v;var q=A.q;A.q=[];for(var i=0;i<q.length;i++){q[i].v=v;A.post(q[i]);}};"
    @"if(window!==window.top){A.send({e:'commit',u:location.href,n:window.name});"
    @"document.addEventListener('DOMContentLoaded',function(){"
    @"if(document.title)A.send({e:'title',t:document.title});});"
    @"window.addEventListener('load',function(){A.send({e:'finish',t:document.title});});"
    @"document.addEventListener('click',function(ev){var t=ev.target,a=t&&t.closest?t.closest('a[href]'):null;"
    @"if(a&&(!a.target||a.target==='_self'))A.send({e:'will',u:a.href});},true);"
    @"}else{var due=0,last='';var geo=function(){due=0;var s=document.scrollingElement||document.documentElement;"
    @"if(!s)return;var g=[scrollX,scrollY,s.scrollWidth,s.scrollHeight],k=g.join();if(k===last)return;last=k;"
    @"A.send({e:'geom',g:g});};var soon=function(){if(!due)due=setTimeout(geo,10);};"
    @"window.addEventListener('scroll',soon,true);window.addEventListener('resize',soon);"
    @"window.addEventListener('load',soon);document.addEventListener('DOMContentLoaded',function(){soon();"
    @"try{new ResizeObserver(soon).observe(document.documentElement);}catch(e){}});}})();";

/* the older web views, by number, and the numbers of those on each user
 * content manager (not retained) */
static NSMutableDictionary *views_by_id, *views_by_manager;

@interface WebView ()
- (void)_agent:(NSDictionary *)message;
- (long)_number;
- (BOOL)_madeForOpener;
- (id)_adapter;
@end

static void on_agent_message(WebKitUserContentManager *manager, WebKitJavascriptResult *result, void *data)
{
    @autoreleasepool {
        BOOL unsupported = NO;
        NSDictionary *m = WKObjectFromJSC(WK(webkit_javascript_result_get_js_value)(result), &unsupported);
        if (![m isKindOfClass:[NSDictionary class]])
            return;
        WebView *view = [views_by_id[m[@"v"]] nonretainedObjectValue];
        if (!view) {   /* not yet told its view: the first on its manager */
            NSArray *ids = views_by_manager[[NSValue valueWithPointer:manager]];
            view = [ids count] ? [views_by_id[ids[0]] nonretainedObjectValue] : nil;
        }
        [[view retain] autorelease];
        [view _agent:m];
    }
}

/* One resource a page loads, for the resource load delegate. */
@interface WebResourceRecord : NSObject {
@public
    id _identifier;
    WebDataSource *_dataSource;
    WebKitWebResource *_resource;
    WebView *_view;   /* not retained */
    BOOL _failed;
}
@end
@implementation WebResourceRecord
- (void)dealloc
{
    [_identifier release];
    [_dataSource release];
    [super dealloc];
}
@end

/* The WKWebView's delegate, on the WebView's behalf. */
@interface WebViewAdapter : NSObject <WKNavigationDelegate, WKUIDelegate> {
@public
    WebView *_view;            /* not retained: it owns this */
    NSURLRequest *_pendingMain;   /* allowed for the main frame, until its load starts */
    NSURL *_newWindowAllowed;     /* a new window's navigation the policy delegate allowed */
    NSMutableArray *_resources;   /* WebResourceRecords loading */
    long _lastResource;
    BOOL _committed;              /* the main frame has a page, which may have frames */
}
- (void)_endResources;
@end

/* the WebView made while a UI delegate is asked for a new window's view
 * takes this configuration, which relates it to the opener */
static WKWebViewConfiguration *opener_configuration;

@implementation WebViewAdapter

- (void)dealloc
{
    [self _endResources];
    [_resources release];
    [_pendingMain release];
    [_newWindowAllowed release];
    [super dealloc];
}

/* every frame of the page, the main frame first */
static void all_frames(WebFrame *frame, NSMutableArray *out)
{
    [out addObject:frame];
    for (WebFrame *child in [frame _children])
        all_frames(child, out);
}

/* WebKitGTK asks about subframes' navigations too, without saying whose.
 * A link the agent saw clicked in a subframe is that frame's; otherwise a
 * URL a frame element of the page is loading is that frame's; the rest
 * are the main frame's. */
- (WebFrame *)_frameFor:(NSURLRequest *)request
{
    WebFrame *main = [_view mainFrame];
    NSString *url = [[request URL] absoluteString];
    if (!_committed || !url)
        return main;
    NSMutableArray *frames = [NSMutableArray array];
    all_frames(main, frames);
    for (WebFrame *f in frames)
        if (f != main && [f->_announced isEqualToString:url]) {
            [f->_announced release];
            f->_announced = nil;
            return f;
        }
    GtkWidget *web = [[_view _wk] _gtkWebView];
    NSString *script =
        @"(function(){var out=[];var walk=function(w,p){var l,n=0;try{l=w.document.querySelectorAll('iframe,frame');"
        @"n=w.frames.length;}catch(e){return;}for(var i=0;i<l.length;i++){var el=l[i],c=el.contentWindow,x=-1;"
        @"for(var j=0;j<n;j++)if(w.frames[j]===c){x=j;break;}if(x<0)continue;var q=p.concat([x]);"
        @"out.push({p:q,n:el.name||'',s:el.hasAttribute('srcdoc')?'about:srcdoc':(el.src||'about:blank')});"
        @"walk(c,q);}};"
        @"walk(window,[]);return out;})()";
    NSArray *list = web ? WKObjectFromJSON([WKEvaluateJSONSync(web, script) UTF8String]) : nil;
    if (![list isKindOfClass:[NSArray class]])
        return main;
    WebFrame *found = nil;
    for (NSDictionary *e in list) {
        if (![e isKindOfClass:[NSDictionary class]] || ![e[@"s"] isEqual:url])
            continue;
        WebFrame *f = [_view _frameAtPath:e[@"p"] create:YES];
        if (f && !f->_started && [e[@"n"] isKindOfClass:[NSString class]])
            [f _setName:e[@"n"]];
        if (f && !f->_started)
            return f;
        if (!found)
            found = f;
    }
    return found ?: main;
}

- (void)webView:(WKWebView *)wk decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))handler
{
    WebView *view = _view;
    id d = [view policyDelegate];
    BOOL newWindow = action.targetFrame == nil;
    NSURLRequest *request = action.request;
    WebFrame *frame = newWindow ? nil : [self _frameFor:request];
    WebPolicyListener *listener = [[[WebPolicyListener alloc] init] autorelease];
    void (^h)(WKNavigationActionPolicy) = [[handler copy] autorelease];
    WebViewAdapter *adapter = self;
    listener->_decide = [^(int how) {
        if (how == 2)
            WKWarnOnce("downloads from a web view (the navigation was cancelled)");
        if (how == 1 && newWindow) {
            [adapter->_newWindowAllowed release];
            adapter->_newWindowAllowed = [[request URL] retain];
        } else if (how == 1 && frame == [view mainFrame]) {
            [adapter->_pendingMain release];
            adapter->_pendingMain = [request retain];
        } else if (how == 1 && frame) {
            [frame _start:request];
            frame->_started = YES;
            id fd = [view frameLoadDelegate];
            if ([fd respondsToSelector:@selector(webView:didStartProvisionalLoadForFrame:)])
                [fd webView:view didStartProvisionalLoadForFrame:frame];
        }
        h(how == 1 ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
    } copy];
    if (newWindow && [d respondsToSelector:@selector(webView:decidePolicyForNewWindowAction:request:newFrameName:
                                                        decisionListener:)])
        [d webView:view decidePolicyForNewWindowAction:action_information(action) request:request
                newFrameName:[action _targetFrameName] ?: @""
            decisionListener:listener];
    else if (!newWindow && [d respondsToSelector:@selector(webView:decidePolicyForNavigationAction:request:frame:
                                                              decisionListener:)])
        [d webView:view decidePolicyForNavigationAction:action_information(action) request:request
                     frame:frame
          decisionListener:listener];
    else
        [listener use];
}

- (void)webView:(WKWebView *)wk decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))handler
{
    WebView *view = _view;
    id d = [view policyDelegate];
    WebFrame *frame = [view mainFrame];
    if (!response.forMainFrame) {   /* a subframe's page: the frame loading its URL */
        NSMutableArray *frames = [NSMutableArray array];
        all_frames([view mainFrame], frames);
        for (WebFrame *f in frames)
            if (f != [view mainFrame] &&
                [[[[f provisionalDataSource] request] URL] isEqual:response.response.URL]) {
                frame = f;
                break;
            }
    }
    if (response.forMainFrame || frame != [view mainFrame])
        [frame _setResponse:response.response];
    WebPolicyListener *listener = [[[WebPolicyListener alloc] init] autorelease];
    void (^h)(WKNavigationResponsePolicy) = [[handler copy] autorelease];
    BOOL canShow = response.canShowMIMEType;
    listener->_decide = [^(int how) {
        if (how == 2)
            WKWarnOnce("downloads from a web view (the navigation was cancelled)");
        h(how == 1 ? WKNavigationResponsePolicyAllow : WKNavigationResponsePolicyCancel);
    } copy];
    NSString *type = response.response.MIMEType ?: @"";
    NSURL *url = response.response.URL ?: [NSURL URLWithString:@"about:blank"];
    if ([d respondsToSelector:@selector(webView:decidePolicyForMIMEType:request:frame:decisionListener:)])
        [d webView:view decidePolicyForMIMEType:type
                       request:[NSURLRequest requestWithURL:url]
                         frame:frame
              decisionListener:listener];
    else if (canShow)
        [listener use];
    else
        [listener ignore];
}

/* the main frame's provisional data source: the request allowed for it,
 * or one for the URL WebKitGTK is loading */
- (void)_startMain
{
    WebFrame *frame = [_view mainFrame];
    NSURLRequest *request = _pendingMain;
    if (!request) {
        GtkWidget *web = [[_view _wk] _gtkWebView];
        const char *uri = web ? WK(webkit_web_view_get_uri)(web) : NULL;
        NSURL *url = uri ? [NSURL URLWithString:WKString(uri)] : nil;
        request = [NSURLRequest requestWithURL:url ?: [NSURL URLWithString:@"about:blank"]];
    }
    [frame _start:request];
    [_pendingMain release];
    _pendingMain = nil;
}

- (void)webView:(WKWebView *)wk didStartProvisionalNavigation:(WKNavigation *)navigation
{
    WebView *view = _view;
    WebFrame *frame = [view mainFrame];
    if (![frame provisionalDataSource] || _pendingMain)
        [self _startMain];
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
    [frame _removeChildren];   /* a new page: its frames are new */
    _committed = YES;
    [[frame frameView] _setPageGeometry:@[ @0, @0, @0, @0 ]];
    /* the page's agent may send its messages now */
    GtkWidget *web = [wk _gtkWebView];
    long number = [view _number];
    if (web)
        WK(webkit_web_view_evaluate_javascript)(
            web,
            [[NSString stringWithFormat:@"window.__ferryView=%ld;if(window.__ferryAgent)window.__ferryAgent.setView(%ld)", number, number] UTF8String],
            -1, agent_world, NULL, NULL, NULL, NULL);
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
    /* the page's size, read now; the agent's messages sent before this
     * (its subframes' loads) come in while it is read */
    WSRun([wk _gtkWebView], @"return null;", WSGeometry);
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

/* A new window (freemac 1.217, Ferry 0.42.0): the policy delegate is
 * asked first (unless it was for this navigation already), then the UI
 * delegate makes a WebView. The WebView made then is related to this one,
 * so WebKitGTK loads the page in it and the page that opened it gets its
 * window; a WebView made some other way is only loaded, and the page gets
 * null. */
- (WKWebView *)webView:(WKWebView *)wk createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)action
         windowFeatures:(WKWindowFeatures *)features
{
    WebView *view = _view;
    id d = [view UIDelegate], pd = [view policyDelegate];
    NSURLRequest *request = action.request;
    BOOL asked = _newWindowAllowed && [_newWindowAllowed isEqual:[request URL]];
    [_newWindowAllowed release];
    _newWindowAllowed = nil;
    if (!asked && [pd respondsToSelector:@selector(webView:decidePolicyForNewWindowAction:request:newFrameName:
                                                       decisionListener:)]) {
        __block int answer = -1;
        WebPolicyListener *listener = [[[WebPolicyListener alloc] init] autorelease];
        listener->_decide = [^(int how) { answer = how; } copy];
        [pd webView:view decidePolicyForNewWindowAction:action_information(action) request:request
                newFrameName:[action _targetFrameName] ?: @""
            decisionListener:listener];
        if (answer < 0) {
            WKWarnOnce("a policy delegate's answer for a new window given later (the window isn't opened)");
            listener->_decide = [^(int how) {} copy];
            return nil;
        }
        if (answer == 2)
            WKWarnOnce("downloads from a web view (the navigation was cancelled)");
        if (answer != 1)
            return nil;
    }
    if (![d respondsToSelector:@selector(webView:createWebViewWithRequest:)])
        return nil;
    WKWebViewConfiguration *previous = opener_configuration;
    opener_configuration = [configuration retain];
    WebView *opened = [d webView:view createWebViewWithRequest:request];
    [opener_configuration release];   /* if no WebView took it */
    opener_configuration = previous;
    if (!opened)
        return nil;
    WKWebView *made = [opened _wk];
    BOOL related = [opened _madeForOpener] && [made _gtkWebView];
    if (!related && request.URL && ![request.URL.absoluteString isEqualToString:@""])
        [[opened mainFrame] loadRequest:request];
    id od = [opened UIDelegate];
    if ([od respondsToSelector:@selector(webViewShow:)])
        [od webViewShow:opened];
    return related ? made : nil;
}

- (void)webViewDidClose:(WKWebView *)wk
{
    id d = [_view UIDelegate];
    if ([d respondsToSelector:@selector(webViewClose:)])
        [d webViewClose:_view];
}

/* ---- the resource load delegate (freemac 1.217, Ferry 0.42.0) ---- */

- (void)_endResource:(WebResourceRecord *)r
{
    WKDisconnect(r->_resource, r);
    g_object_unref(r->_resource);
    [_resources removeObjectIdenticalTo:r];
}

- (void)_endResources
{
    while ([_resources count])
        [self _endResource:[_resources lastObject]];
}

static void on_resource_sent(WebKitWebResource *resource, WebKitURIRequest *request, WebKitURIResponse *redirect,
                             void *data)
{
    @autoreleasepool {
        WebResourceRecord *r = [[(WebResourceRecord *)data retain] autorelease];
        id d = [r->_view resourceLoadDelegate];
        if (![d respondsToSelector:@selector(webView:resource:willSendRequest:redirectResponse:fromDataSource:)])
            return;
        NSURLRequest *sent = WKRequest(request);
        NSURLRequest *answer = [d webView:r->_view resource:r->_identifier willSendRequest:sent
                         redirectResponse:WKResponse(redirect)
                           fromDataSource:r->_dataSource];
        if (answer != sent && ![[answer URL] isEqual:[sent URL]])
            WKWarnOnce("a resource load delegate's changed or refused requests (the request is sent as it was)");
    }
}

static void on_resource_response(void *object, GParamSpec *pspec, void *data)
{
    @autoreleasepool {
        WebResourceRecord *r = [[(WebResourceRecord *)data retain] autorelease];
        id d = [r->_view resourceLoadDelegate];
        WebKitURIResponse *response = WK(webkit_web_resource_get_response)(r->_resource);
        if (response && [d respondsToSelector:@selector(webView:resource:didReceiveResponse:fromDataSource:)])
            [d webView:r->_view resource:r->_identifier didReceiveResponse:WKResponse(response)
                fromDataSource:r->_dataSource];
    }
}

static void on_resource_data(WebKitWebResource *resource, uint64_t length, void *data)
{
    @autoreleasepool {
        WebResourceRecord *r = [[(WebResourceRecord *)data retain] autorelease];
        id d = [r->_view resourceLoadDelegate];
        if ([d respondsToSelector:@selector(webView:resource:didReceiveContentLength:fromDataSource:)])
            [d webView:r->_view resource:r->_identifier didReceiveContentLength:(NSInteger)length
                fromDataSource:r->_dataSource];
    }
}

static void on_resource_failed(WebKitWebResource *resource, GError *error, void *data)
{
    @autoreleasepool {
        WebResourceRecord *r = [[(WebResourceRecord *)data retain] autorelease];
        r->_failed = YES;
        id d = [r->_view resourceLoadDelegate];
        if ([d respondsToSelector:@selector(webView:resource:didFailLoadingWithError:fromDataSource:)])
            [d webView:r->_view resource:r->_identifier
                didFailLoadingWithError:WKLoadError(error, WK(webkit_web_resource_get_uri)(resource))
                         fromDataSource:r->_dataSource];
    }
}

static void on_resource_finished(WebKitWebResource *resource, void *data)
{
    @autoreleasepool {
        WebResourceRecord *r = [[(WebResourceRecord *)data retain] autorelease];
        WebView *view = r->_view;
        id d = [view resourceLoadDelegate];
        if (!r->_failed && [d respondsToSelector:@selector(webView:resource:didFinishLoadingFromDataSource:)])
            [d webView:view resource:r->_identifier didFinishLoadingFromDataSource:r->_dataSource];
        WebViewAdapter *adapter = [view _adapter];
        [adapter _endResource:r];
    }
}

static void on_resource_started(GtkWidget *web, WebKitWebResource *resource, WebKitURIRequest *request, void *data)
{
    @autoreleasepool {
        WebViewAdapter *self = data;
        WebView *view = [[self->_view retain] autorelease];
        id d = [view resourceLoadDelegate];
        if (!d)
            return;
        WebFrame *main = [view mainFrame];
        /* the page itself: its provisional data source may not be made yet */
        if (resource == WK(webkit_web_view_get_main_resource)(web) && ![main provisionalDataSource] &&
            [view isLoading])
            [self _startMain];
        WebResourceRecord *r = [[[WebResourceRecord alloc] init] autorelease];
        r->_view = view;
        r->_resource = g_object_ref(resource);
        r->_dataSource = [[main provisionalDataSource] ?: [main dataSource] retain];
        NSURLRequest *initial = WKRequest(request);
        if ([d respondsToSelector:@selector(webView:identifierForInitialRequest:fromDataSource:)])
            r->_identifier =
                [[d webView:view identifierForInitialRequest:initial fromDataSource:r->_dataSource] retain];
        if (!r->_identifier)
            r->_identifier = [@(++self->_lastResource) retain];
        if (!self->_resources)
            self->_resources = [NSMutableArray new];
        [self->_resources addObject:r];
        WKConnect(resource, "sent-request", on_resource_sent, r);
        WKConnect(resource, "notify::response", on_resource_response, r);
        static int has_data = -1;   /* "received-data" is gone from newer WebKitGTKs */
        if (has_data < 0)
            has_data = g_signal_lookup("received-data", WK(webkit_web_resource_get_type)()) != 0;
        if (has_data)
            WKConnect(resource, "received-data", on_resource_data, r);
        WKConnect(resource, "failed", on_resource_failed, r);
        WKConnect(resource, "finished", on_resource_finished, r);
    }
}
@end

/* ---- the web view ------------------------------------------------------------------- */

/* ---- the back-forward list (freemac 1.226, Ferry 0.50.0) ------------------------------
 * The items added with addItem:; while there are none, the list answers
 * from the page's own history (WKBackForwardList). */

NSString *const WebHistoryItemChangedNotification = @"WebHistoryItemChangedNotification";

@implementation WebHistoryItem {
    NSString *_URLString, *_originalURLString, *_title, *_alternateTitle;
    NSTimeInterval _lastVisited;
}
- (instancetype)initWithURLString:(NSString *)URLString title:(NSString *)title
          lastVisitedTimeInterval:(NSTimeInterval)time
{
    if ((self = [super init])) {
        _URLString = [URLString copy];
        _originalURLString = [URLString copy];
        _title = [title copy];
        _lastVisited = time;
    }
    return self;
}
- (instancetype)init { return [self initWithURLString:nil title:nil lastVisitedTimeInterval:0]; }
- (id)copyWithZone:(NSZone *)zone
{
    WebHistoryItem *c = [[WebHistoryItem allocWithZone:zone] initWithURLString:_URLString title:_title
                                                       lastVisitedTimeInterval:_lastVisited];
    c->_alternateTitle = [_alternateTitle copy];
    return c;
}
- (void)dealloc
{
    [_URLString release];
    [_originalURLString release];
    [_title release];
    [_alternateTitle release];
    [super dealloc];
}
- (NSString *)URLString { return _URLString; }
- (NSString *)originalURLString { return _originalURLString; }
- (NSString *)title { return _title; }
- (NSString *)alternateTitle { return _alternateTitle; }
- (void)setAlternateTitle:(NSString *)t
{
    t = [t copy];
    [_alternateTitle release];
    _alternateTitle = t;
}
- (NSTimeInterval)lastVisitedTimeInterval { return _lastVisited; }
- (NSImage *)icon { return nil; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<WebHistoryItem %p %@ \"%@\">", self, _URLString, _title];
}
@end

static WebHistoryItem *item_of(WKBackForwardListItem *wk)
{
    if (!wk)
        return nil;
    return [[[WebHistoryItem alloc] initWithURLString:[[wk URL] absoluteString] title:[wk title]
                                 lastVisitedTimeInterval:0] autorelease];
}

@implementation WebBackForwardList {
  @public
    WebView *_view;   /* not retained: the view owns the list */
    NSMutableArray *_items;
    NSInteger _current;   /* the current item's index, -1 for none */
    int _capacity, _pageCacheSize;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _items = [[NSMutableArray alloc] init];
        _current = -1;
        _capacity = 100;
    }
    return self;
}
- (void)dealloc
{
    [_items release];
    [super dealloc];
}
- (WKBackForwardList *)_page { return [_items count] ? nil : [[_view _wk] backForwardList]; }

- (void)addItem:(WebHistoryItem *)item
{
    if (!item || _capacity <= 0)
        return;
    NSInteger keep = _current + 1;
    if ((NSUInteger)keep < [_items count])
        [_items removeObjectsInRange:NSMakeRange((NSUInteger)keep, [_items count] - (NSUInteger)keep)];
    [_items addObject:item];
    while ([_items count] > (NSUInteger)_capacity)
        [_items removeObjectAtIndex:0];
    _current = (NSInteger)[_items count] - 1;
}
- (void)goBack
{
    if ([_items count]) {
        if (_current > 0)
            _current--;
    } else {
        [[_view _wk] goBack];
    }
}
- (void)goForward
{
    if ([_items count]) {
        if (_current + 1 < (NSInteger)[_items count])
            _current++;
    } else {
        [[_view _wk] goForward];
    }
}
- (void)goToItem:(WebHistoryItem *)item
{
    NSUInteger i = [_items indexOfObjectIdenticalTo:item];
    if (i != NSNotFound)
        _current = (NSInteger)i;
}
- (WebHistoryItem *)itemAtIndex:(int)index
{
    if (![_items count])
        return item_of([[self _page] itemAtIndex:index]);
    NSInteger i = _current + index;
    return i >= 0 && i < (NSInteger)[_items count] ? [_items objectAtIndex:(NSUInteger)i] : nil;
}
- (WebHistoryItem *)backItem { return [self itemAtIndex:-1]; }
- (WebHistoryItem *)currentItem { return [self itemAtIndex:0]; }
- (WebHistoryItem *)forwardItem { return [self itemAtIndex:1]; }
- (int)backListCount
{
    if (![_items count])
        return (int)[[[self _page] backList] count];
    return (int)_current;
}
- (int)forwardListCount
{
    if (![_items count])
        return (int)[[[self _page] forwardList] count];
    return (int)([_items count] - (NSUInteger)_current - 1);
}
- (NSArray *)backListWithLimit:(int)limit
{
    NSMutableArray *a = [NSMutableArray array];
    for (int i = MIN(limit, [self backListCount]); i >= 1; i--)
        if ([self itemAtIndex:-i])
            [a addObject:[self itemAtIndex:-i]];
    return a;
}
- (NSArray *)forwardListWithLimit:(int)limit
{
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 1; i <= MIN(limit, [self forwardListCount]); i++)
        if ([self itemAtIndex:i])
            [a addObject:[self itemAtIndex:i]];
    return a;
}
- (BOOL)containsItem:(WebHistoryItem *)item { return [_items indexOfObjectIdenticalTo:item] != NSNotFound; }
- (int)capacity { return _capacity; }
- (void)setCapacity:(int)capacity
{
    _capacity = capacity < 0 ? 0 : capacity;
    while ([_items count] > (NSUInteger)_capacity) {
        [_items removeObjectAtIndex:0];
        _current--;
    }
    if (_current < 0 && [_items count])
        _current = 0;
}
- (int)pageCacheSize { return _pageCacheSize; }
- (void)setPageCacheSize:(int)size { _pageCacheSize = size; }
- (BOOL)_hasItems { return [_items count] != 0; }
@end

@implementation WebView {
    WKWebView *_wk;
    WebViewAdapter *_adapter;
    WebFrame *_mainFrame;
    WebFrameView *_mainFrameView;
    WebPreferences *_preferences;
    WebScriptObject *_windowScriptObject;
    id _frameLoadDelegate, _policyDelegate, _UIDelegate, _resourceLoadDelegate, _downloadDelegate, _editingDelegate;
    NSString *_applicationName, *_groupName, *_frameName;
    NSWindow *_hostWindow;
    float _textSizeMultiplier;
    BOOL _editable, _drawsBackground, _shouldUpdateWhileOffscreen, _maintainsBackForwardList,
        _continuousSpellChecking, _closed;
    /* freemac 1.217, Ferry 0.42.0 */
    long _number;                      /* for the agent's messages */
    WebKitUserContentManager *_manager;   /* its page's scripts (its opener's, for a new window) */
    WebKitUserStyleSheet *_styleSheet; /* the preferences' user style sheet */
    BOOL _madeForOpener;
    WebBackForwardList *_backForward;   /* freemac 1.226, Ferry 0.50.0 */
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

/* the agent's script and messages, once for each user content manager */
- (void)_startAgent
{
    WebKitUserContentManager *m = _manager;
    if (!m)
        return;
    if (!views_by_manager)
        views_by_manager = [NSMutableDictionary new];
    NSValue *key = [NSValue valueWithPointer:m];
    NSMutableArray *ids = views_by_manager[key];
    if (!ids)
        views_by_manager[key] = ids = [NSMutableArray array];
    [ids addObject:@(_number)];
    if (g_object_get_data(m, "ferry-webview-agent"))
        return;
    g_object_set_data(m, "ferry-webview-agent", (void *)1);
    WebKitUserScript *s = WK(webkit_user_script_new_for_world)([agent_script UTF8String],
                                                               WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
                                                               WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, agent_world,
                                                               NULL, NULL);
    WK(webkit_user_content_manager_add_script)(m, s);
    WK(webkit_user_script_unref)(s);
    WKConnect(m, "script-message-received::ferryWebView", on_agent_message, [WebView class]);
    WK(webkit_user_content_manager_register_script_message_handler_in_world)(m, "ferryWebView", agent_world);
}

- (void)_setUp
{
    static long last_number;
    _number = ++last_number;
    _textSizeMultiplier = 1;
    _drawsBackground = YES;
    _maintainsBackForwardList = YES;
    _mainFrame = [[WebFrame alloc] _initWithWebView:self];
    [_mainFrame _setName:_frameName];
    /* the main frame's view fills this; the WKWebView fills it, over its scroll view */
    _mainFrameView = [[WebFrameView alloc] _initWithFrame:[self bounds] webFrame:_mainFrame];
    [_mainFrameView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_mainFrame _setFrameView:_mainFrameView];
    [self addSubview:_mainFrameView];
    _adapter = [[WebViewAdapter alloc] init];
    _adapter->_view = self;
    WKWebViewConfiguration *configuration = nil;
    if (opener_configuration) {   /* made for a new window: related to its opener */
        configuration = [opener_configuration autorelease];
        opener_configuration = nil;
        _madeForOpener = YES;
    }
    _wk = [[WKWebView alloc] initWithFrame:[_mainFrameView bounds] configuration:configuration];
    [_wk setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _wk.navigationDelegate = _adapter;
    _wk.UIDelegate = _adapter;
    [_wk addObserver:_adapter forKeyPath:@"title" options:0 context:NULL];
    [_wk addObserver:_adapter forKeyPath:@"estimatedProgress" options:0 context:NULL];
    [_mainFrameView addSubview:_wk];
    GtkWidget *web = [_wk _gtkWebView];
    if (web) {
        g_object_set_data(web, "ferry-webview", self);
        if (!views_by_id)
            views_by_id = [NSMutableDictionary new];
        views_by_id[@(_number)] = [NSValue valueWithNonretainedObject:self];
        _manager = [[[_wk configuration] userContentController] _manager];
        if (_manager)
            g_object_ref(_manager);
        [self _startAgent];
        WKConnect(web, "resource-load-started", on_resource_started, _adapter);
    }
    [self setPreferences:[WebPreferences standardPreferences]];
    /* as a Mac's WebView, a page from a file may reach the other files' (its frames') */
    if ([_wk _gtkSettings])
        WK(webkit_settings_set_allow_file_access_from_file_urls)([_wk _gtkSettings], 1);
    _windowScriptObject = [[WebScriptObject alloc] _initWithWeb:web handle:0 generation:nil];
}

- (instancetype)initWithFrame:(NSRect)frame frameName:(NSString *)frameName groupName:(NSString *)groupName
{
    self = [super initWithFrame:frame];
    _groupName = [groupName copy];
    _frameName = [frameName copy];
    [self _setUp];
    return self;
}

- (instancetype)initWithFrame:(NSRect)frame { return [self initWithFrame:frame frameName:nil groupName:nil]; }

/* From a nib: its preferences, frame and group names and whether it keeps
 * a back-forward list, as ferry-ibtool writes them (freemac 1.229). */
- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if ([coder allowsKeyedCoding]) {
        id frame = [coder decodeObjectForKey:@"FrameName"], group = [coder decodeObjectForKey:@"GroupName"];
        if ([frame isKindOfClass:[NSString class]])
            _frameName = [frame copy];
        if ([group isKindOfClass:[NSString class]])
            _groupName = [group copy];
    }
    [self _setUp];
    if ([coder allowsKeyedCoding]) {
        id prefs = [coder decodeObjectForKey:@"WebPreferences"];
        if ([prefs isKindOfClass:[WebPreferences class]])
            [self setPreferences:prefs];
        if ([coder containsValueForKey:@"UseBackForwardList"])
            [self setMaintainsBackForwardList:[coder decodeBoolForKey:@"UseBackForwardList"]];
        id name = [coder decodeObjectForKey:@"ApplicationName"];
        if ([name isKindOfClass:[NSString class]])
            [self setApplicationNameForUserAgent:name];
    }
    return self;
}

- (void)_removeUserStyleSheet
{
    if (_styleSheet) {
        WK(webkit_user_content_manager_remove_style_sheet)(_manager, _styleSheet);
        WK(webkit_user_style_sheet_unref)(_styleSheet);
        _styleSheet = NULL;
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_adapter _endResources];
    GtkWidget *web = [_wk _gtkWebView];
    if (web) {
        WKDisconnect(web, _adapter);
        g_object_set_data(web, "ferry-webview", NULL);
    }
    [views_by_id removeObjectForKey:@(_number)];
    if (_manager) {
        [self _removeUserStyleSheet];
        [views_by_manager[[NSValue valueWithPointer:_manager]] removeObject:@(_number)];
        g_object_unref(_manager);
    }
    [_wk removeObserver:_adapter forKeyPath:@"title"];
    [_wk removeObserver:_adapter forKeyPath:@"estimatedProgress"];
    _wk.navigationDelegate = nil;
    _wk.UIDelegate = nil;
    if ([_wk _gtkSettings])
        [_preferences _removeSettings:[_wk _gtkSettings]];
    [_mainFrame _forget];
    [_wk release];
    [_adapter release];
    [_mainFrame release];
    [_mainFrameView release];
    [_preferences release];
    [_windowScriptObject release];
    [_applicationName release];
    [_groupName release];
    [_frameName release];
    [_hostWindow release];
    if (_backForward)
        _backForward->_view = nil;
    [_backForward release];
    [super dealloc];
}

- (WKWebView *)_wk { return _wk; }
- (CGFloat)_zoom { return _textSizeMultiplier; }
/* for the adapter */
- (long)_number { return _number; }
- (BOOL)_madeForOpener { return _madeForOpener; }
- (id)_adapter { return _adapter; }

- (void)close
{
    if (_closed)
        return;
    _closed = YES;
    [_wk stopLoading];
}

- (WebFrame *)mainFrame { return _mainFrame; }
- (DOMDocument *)mainFrameDocument { return [_mainFrame DOMDocument]; }

- (WebFrame *)_frameAtPath:(NSArray *)path create:(BOOL)create
{
    WebFrame *f = _mainFrame;
    for (id step in path) {
        if (![step isKindOfClass:[NSNumber class]])
            return nil;
        NSUInteger i = [step unsignedIntegerValue];
        NSMutableArray *children = [f _children];
        if (i >= [children count]) {
            if (!create || i > 64)
                return nil;
            while ([children count] <= i)
                [children addObject:[[[WebFrame alloc] _initWithWebView:self parent:f index:[children count]]
                                        autorelease]];
        }
        f = children[i];
    }
    return f;
}

/* what the agent says of a subframe's loads, or of the page's geometry */
- (void)_agent:(NSDictionary *)m
{
    NSString *e = m[@"e"];
    NSArray *path = [m[@"p"] isKindOfClass:[NSArray class]] ? m[@"p"] : @[];
    if ([e isEqual:@"geom"]) {
        if (![path count])
            [_mainFrameView _setPageGeometry:m[@"g"]];
        return;
    }
    if (![path count])
        return;   /* the main frame's loads come from WebKitGTK */
    WebFrame *frame = [self _frameAtPath:path create:YES];
    if (!frame)
        return;
    id d = _frameLoadDelegate;
    if ([e isEqual:@"will"]) {
        [frame->_announced release];
        frame->_announced = [[m[@"u"] description] copy];
    } else if ([e isEqual:@"commit"]) {
        if ([m[@"n"] isKindOfClass:[NSString class]])
            [frame _setName:m[@"n"]];
        NSURL *url = [NSURL URLWithString:[m[@"u"] description] ?: @""] ?: [NSURL URLWithString:@"about:blank"];
        if (!frame->_started || ![frame provisionalDataSource]) {
            [frame _start:[NSURLRequest requestWithURL:url]];
            frame->_started = YES;
            if ([d respondsToSelector:@selector(webView:didStartProvisionalLoadForFrame:)])
                [d webView:self didStartProvisionalLoadForFrame:frame];
        }
        [frame _commit];
        [frame _removeChildren];
        if ([d respondsToSelector:@selector(webView:didCommitLoadForFrame:)])
            [d webView:self didCommitLoadForFrame:frame];
        if ([d respondsToSelector:@selector(webView:didClearWindowObject:forFrame:)]) {
            WebScriptObject *window = [frame windowObject];
            if (window)
                [d webView:self didClearWindowObject:window forFrame:frame];
        }
    } else if ([e isEqual:@"title"] || [e isEqual:@"finish"]) {
        NSString *title = [m[@"t"] isKindOfClass:[NSString class]] ? m[@"t"] : nil;
        if ([title length] && ![title isEqualToString:frame->_title]) {
            [frame->_title release];
            frame->_title = [title copy];
            if ([d respondsToSelector:@selector(webView:didReceiveTitle:forFrame:)])
                [d webView:self didReceiveTitle:title forFrame:frame];
        }
        if ([e isEqual:@"finish"]) {
            [frame _finish];
            if ([d respondsToSelector:@selector(webView:didFinishLoadForFrame:)])
                [d webView:self didFinishLoadForFrame:frame];
        }
    }
}

/* the page scrolled where a program scrolled the frame's view, in CSS pixels */
- (void)_scrollFrame:(WebFrame *)frame to:(NSPoint)point
{
    GtkWidget *web = [_wk _gtkWebView];
    if (!web || !frame)
        return;
    CGFloat zoom = [self _zoom];
    NSString *script = [NSString stringWithFormat:@"try{%@.scrollTo(%g,%g)}catch(e){}", [frame _windowExpression],
                                                  point.x / zoom, point.y / zoom];
    WK(webkit_web_view_evaluate_javascript)(web, [script UTF8String], -1, NULL, NULL, NULL, NULL, NULL);
}

/* the delegates aren't retained, as on a Mac */
- (id<WebFrameLoadDelegate>)frameLoadDelegate { return _frameLoadDelegate; }
- (void)setFrameLoadDelegate:(id<WebFrameLoadDelegate>)d { _frameLoadDelegate = d; }
- (id<WebPolicyDelegate>)policyDelegate { return _policyDelegate; }
- (void)setPolicyDelegate:(id<WebPolicyDelegate>)d { _policyDelegate = d; }
- (id<WebUIDelegate>)UIDelegate { return _UIDelegate; }
- (void)setUIDelegate:(id<WebUIDelegate>)d { _UIDelegate = d; }
- (id)resourceLoadDelegate { return _resourceLoadDelegate; }
- (void)setResourceLoadDelegate:(id)d { _resourceLoadDelegate = d; }
- (id)downloadDelegate { return _downloadDelegate; }
- (void)setDownloadDelegate:(id)d { _downloadDelegate = d; }
- (id)editingDelegate { return _editingDelegate; }
- (void)setEditingDelegate:(id)d { _editingDelegate = d; }

/* The preferences' user style sheet, read again whenever they change, as
 * a user style sheet of WebKitGTK's in every frame (freemac 1.217, Ferry 0.42.0) */
- (void)_applyUserStyleSheet
{
    if (!_manager)
        return;
    [self _removeUserStyleSheet];
    NSURL *location = [_preferences userStyleSheetLocation];
    if (![_preferences userStyleSheetEnabled] || !location)
        return;
    NSData *data = [NSData dataWithContentsOfURL:location];
    NSString *css = data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
    if (!css && data)
        css = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (!css)
        return;
    _styleSheet = WK(webkit_user_style_sheet_new)([css UTF8String], WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
                                                  WEBKIT_USER_STYLE_LEVEL_USER, NULL, NULL);
    WK(webkit_user_content_manager_add_style_sheet)(_manager, _styleSheet);
}

- (void)_preferencesChanged:(NSNotification *)n { [self _applyUserStyleSheet]; }

- (WebPreferences *)preferences { return _preferences; }
- (void)setPreferences:(WebPreferences *)preferences
{
    preferences = preferences ?: [WebPreferences standardPreferences];
    WebKitSettings *settings = [_wk _gtkSettings];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_preferences)
        [center removeObserver:self name:WebPreferencesChangedNotification object:_preferences];
    if (settings && _preferences)
        [_preferences _removeSettings:settings];
    [preferences retain];
    [_preferences release];
    _preferences = preferences;
    if (settings)
        [_preferences _addSettings:settings];
    [center addObserver:self selector:@selector(_preferencesChanged:) name:WebPreferencesChangedNotification
                 object:_preferences];
    [self _applyUserStyleSheet];
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
    id wasApplicationName = _applicationName;
    _applicationName = [name copy];
    [wasApplicationName release];
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
- (WebBackForwardList *)backForwardList
{
    if (!_backForward) {
        _backForward = [[WebBackForwardList alloc] init];
        _backForward->_view = self;
    }
    return _backForward;
}
/* the list's current item, loaded in the main frame */
- (BOOL)_loadListItem
{
    NSURL *url = [NSURL URLWithString:[[_backForward currentItem] URLString] ?: @""];
    if (url)
        [_mainFrame loadRequest:[NSURLRequest requestWithURL:url]];
    return url != nil;
}
- (BOOL)goToBackForwardItem:(WebHistoryItem *)item
{
    if (![_backForward containsItem:item])
        return NO;
    [_backForward goToItem:item];
    return [self _loadListItem];
}
- (BOOL)canGoBack { return [_backForward _hasItems] ? [_backForward backListCount] > 0 : [_wk canGoBack]; }
- (BOOL)canGoForward { return [_backForward _hasItems] ? [_backForward forwardListCount] > 0 : [_wk canGoForward]; }
- (BOOL)goBack
{
    if (![_backForward _hasItems])
        return [_wk goBack] != nil;
    if ([_backForward backListCount] <= 0)
        return NO;
    [_backForward goBack];
    return [self _loadListItem];
}
- (BOOL)goForward
{
    if (![_backForward _hasItems])
        return [_wk goForward] != nil;
    if ([_backForward forwardListCount] <= 0)
        return NO;
    [_backForward goForward];
    return [self _loadListItem];
}

- (float)textSizeMultiplier { return _textSizeMultiplier; }
- (void)setTextSizeMultiplier:(float)m
{
    _textSizeMultiplier = m > 0 ? m : 1;
    [_wk setPageZoom:_textSizeMultiplier];
    /* the page's size in the frame view's points changes with it */
    WSRun([_wk _gtkWebView], @"return null;", WSGeometry);
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
    id wasGroupName = _groupName;
    _groupName = [name copy];
    [wasGroupName release];
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
