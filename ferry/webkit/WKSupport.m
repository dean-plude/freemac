/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: finding WebKitGTK, turning what it hands back into
 * Foundation's objects, waiting for it, and placing its web view inside
 * AppKit's windows (WKEmbed). */
#import "WKInternal.h"

/* ---- WebKitGTK itself ------------------------------------------------------------------ */

void *WKLookup(const char *name)
{
    void *p = ferry_webkit_symbol(name);
    if (!p) {
        fflush(stdout);
        fprintf(stderr, "ferry: this program uses WebKit, and this system's WebKitGTK has no %s\n", name);
        exit(127);
    }
    return p;
}

void WKWarnOnce(const char *what)
{
    static NSMutableSet *said;
    if (!said)
        said = [[NSMutableSet alloc] init];
    NSString *key = @(what);
    if ([said containsObject:key])
        return;
    [said addObject:key];
    fflush(stdout);
    fprintf(stderr, "WebKit (Ferry): %s isn't supported yet\n", what);
}

BOOL WKAvailable(void)
{
    static int state; /* 0 not tried, 1 yes, -1 no */
    if (state)
        return state > 0;
    state = -1;
    AMainThreadOnly("WebKit's web views");
    if (!ferry_webkit_symbol("webkit_web_view_get_type") || !ferry_webkit_symbol("jsc_value_to_json")) {
        fflush(stdout);
        fprintf(stderr, "WebKit (Ferry): web views need WebKitGTK (libwebkit2gtk-4.1), which isn't installed; "
                        "they will stay empty\n");
        return NO;
    }
    if (!ADisplayAvailable()) {
        fflush(stdout);
        fprintf(stderr, "WebKit (Ferry): web views need a display (Wayland or X11); they will stay empty\n");
        return NO;
    }
    state = 1;
    return YES;
}

unsigned long WKConnect(void *instance, const char *signal, void *handler, id data)
{
    return g_signal_connect_data(instance, signal, (GCallback)handler, data, NULL, 0);
}

void WKDisconnect(void *instance, id data)
{
    if (instance)
        g_signal_handlers_disconnect_matched(instance, G_SIGNAL_MATCH_DATA, 0, 0, NULL, NULL, data);
}

/* ---- values ------------------------------------------------------------------------------- */

NSString *WKString(const char *s) { return s ? [NSString stringWithUTF8String:s] : nil; }

NSString *WKQuote(NSString *text)
{
    NSMutableString *out = [NSMutableString stringWithString:@"\""];
    NSUInteger n = [text length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [text characterAtIndex:i];
        switch (c) {
        case '"': [out appendString:@"\\\""]; break;
        case '\\': [out appendString:@"\\\\"]; break;
        case '\n': [out appendString:@"\\n"]; break;
        case '\r': [out appendString:@"\\r"]; break;
        case '\t': [out appendString:@"\\t"]; break;
        default:
            if (c < 0x20 || c == 0x2028 || c == 0x2029)
                [out appendFormat:@"\\u%04x", c];
            else
                [out appendFormat:@"%C", c];
        }
    }
    [out appendString:@"\""];
    return out;
}

id WKObjectFromJSON(const char *json)
{
    if (!json)
        return nil;
    NSData *data = [NSData dataWithBytes:json length:strlen(json)];
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:NULL];
}

id WKObjectFromJSC(JSCValue *value, BOOL *unsupported)
{
    *unsupported = NO;
    if (!value || WK(jsc_value_is_undefined)(value))
        return nil;
    if (WK(jsc_value_is_null)(value))
        return [NSNull null];
    if (WK(jsc_value_is_function)(value)) {
        *unsupported = YES;
        return nil;
    }
    if (WK(jsc_value_is_object)(value) && WK(jsc_value_object_is_instance_of)(value, "Date"))
        return [NSDate dateWithTimeIntervalSince1970:WK(jsc_value_to_double)(value) / 1000];
    char *json = WK(jsc_value_to_json)(value, 0);
    id result = WKObjectFromJSON(json);
    g_free(json);
    if (!result)
        *unsupported = YES;
    return result;
}

static NSString *const WebKitErrorDomainName = @"WebKitErrorDomain";

NSError *WKLoadError(GError *error, const char *failingURI)
{
    NSString *domain = NSURLErrorDomain;
    NSInteger code = NSURLErrorUnknown;
    NSString *message = error && error->message ? WKString(error->message) : @"The page couldn't be loaded";
    if (error) {
        const char *name = g_quark_to_string(error->domain);
        if (error->domain == WK(webkit_network_error_quark)()) {
            code = error->code == WEBKIT_NETWORK_ERROR_CANCELLED             ? NSURLErrorCancelled
                   : error->code == WEBKIT_NETWORK_ERROR_FILE_DOES_NOT_EXIST ? NSURLErrorFileDoesNotExist
                   : error->code == WEBKIT_NETWORK_ERROR_UNKNOWN_PROTOCOL    ? NSURLErrorUnsupportedURL
                   : error->code == WEBKIT_NETWORK_ERROR_TRANSPORT           ? NSURLErrorCannotConnectToHost
                                                                             : NSURLErrorUnknown;
        } else if (error->domain == WK(webkit_policy_error_quark)()) {
            domain = WebKitErrorDomainName;
            code = error->code;
        } else if (name && !strcmp(name, "g-io-error-quark"))   /* GIO's NOT_FOUND and PERMISSION_DENIED */
            code = error->code == 1 ? NSURLErrorFileDoesNotExist
                   : error->code == 14 ? NSURLErrorNoPermissionsToReadFile
                                       : NSURLErrorUnknown;
        else if (name && !strcmp(name, "g-resolver-error-quark"))
            code = NSURLErrorCannotFindHost;
        else if (name && !strcmp(name, "g-tls-error-quark"))
            code = NSURLErrorSecureConnectionFailed;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    NSString *uri = WKString(failingURI);
    if (uri) {
        info[NSURLErrorFailingURLStringErrorKey] = uri;
        NSURL *url = [NSURL URLWithString:uri];
        if (url)
            info[NSURLErrorFailingURLErrorKey] = url;
    }
    return [NSError errorWithDomain:domain code:code userInfo:info];
}

NSURLRequest *WKRequest(WebKitURIRequest *request)
{
    NSString *uri = request ? WKString(WK(webkit_uri_request_get_uri)(request)) : nil;
    NSURL *url = uri ? [NSURL URLWithString:uri] : nil;
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url ?: [NSURL URLWithString:@"about:blank"]];
    NSString *method = request ? WKString(WK(webkit_uri_request_get_http_method)(request)) : nil;
    if ([method length])
        [r setHTTPMethod:method];
    return r;
}

NSURLResponse *WKResponse(WebKitURIResponse *response)
{
    if (!response)
        return nil;
    NSString *uri = WKString(WK(webkit_uri_response_get_uri)(response));
    NSURL *url = [NSURL URLWithString:uri ?: @"about:blank"];
    NSString *mime = WKString(WK(webkit_uri_response_get_mime_type)(response));
    long long length = (long long)WK(webkit_uri_response_get_content_length)(response);
    NSString *scheme = [[url scheme] lowercaseString];
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        return [[[NSHTTPURLResponse alloc] initWithURL:url
                                            statusCode:WK(webkit_uri_response_get_status_code)(response)
                                           HTTPVersion:@"HTTP/1.1"
                                          headerFields:mime ? @{@"Content-Type" : mime} : nil] autorelease];
    return [[[NSURLResponse alloc] initWithURL:url
                                      MIMEType:mime
                         expectedContentLength:length ? length : -1
                              textEncodingName:nil] autorelease];
}

NSEventModifierFlags WKModifiers(unsigned gdk) { return AModifiersFromGdk(gdk); }

/* ---- waiting ----------------------------------------------------------------------------- */

static int keep_waking(void *data) { return 1; }

BOOL WKWaitFor(volatile BOOL *done, NSTimeInterval seconds)
{
    NSTimeInterval end = [NSDate timeIntervalSinceReferenceDate] + seconds;
    /* a timeout of its own, so a wait with nothing to dispatch still ends */
    unsigned tag = g_timeout_add(20, keep_waking, NULL);
    while (!*done && [NSDate timeIntervalSinceReferenceDate] < end)
        g_main_context_iteration(NULL, 1);
    g_source_remove(tag);
    return *done;
}

struct sync_eval {
    volatile BOOL done;
    char *json;
};

static void sync_evaluated(void *source, GAsyncResult *result, void *data)
{
    struct sync_eval *e = data;
    GError *error = NULL;
    JSCValue *value = WK(webkit_web_view_evaluate_javascript_finish)(source, result, &error);
    if (value) {
        e->json = WK(jsc_value_to_json)(value, 0);
        g_object_unref(value);
    } else if (error)
        g_error_free(error);
    e->done = YES;
}

NSString *WKEvaluateJSONSync(GtkWidget *web, NSString *script)
{
    struct sync_eval *e = calloc(1, sizeof *e);
    WK(webkit_web_view_evaluate_javascript)(web, [script UTF8String], -1, NULL, NULL, NULL, sync_evaluated, e);
    if (!WKWaitFor(&e->done, 10)) {
        fflush(stdout);
        fprintf(stderr, "WebKit (Ferry): a script in a web view didn't finish in 10 seconds; it was given up\n");
        return nil;   /* e stays, for the answer that may still come */
    }
    NSString *json = WKString(e->json);
    g_free(e->json);
    free(e);
    return json;
}

static cairo_status_t append_png(void *closure, const unsigned char *data, unsigned int length)
{
    [(NSMutableData *)closure appendBytes:data length:length];
    return 0;
}

NSImage *WKImageFromSurface(cairo_surface_t *surface)
{
    if (!surface)
        return nil;
    NSMutableData *png = [NSMutableData data];
    cairo_surface_write_to_png_stream(surface, append_png, png);
    return [[[NSImage alloc] initWithData:png] autorelease];
}

/* ---- the GTK web view inside AppKit's window ---------------------------------------------- */

static WKEmbed **embeds;
static size_t nembeds, embeds_cap;

static void on_window_destroy(GtkWidget *window, void *data);

/* The window's GtkOverlay, with AppKit's drawing area as its main child;
 * made from the drawing area the first time a web view is shown there. */
static GtkWidget *overlay_of(GtkWidget *window)
{
    GtkWidget *child = gtk_bin_get_child(window);
    if (!child)
        return NULL;
    if (g_object_get_data(child, "ferry-webkit-overlay"))
        return child;
    BOOL focused = gtk_widget_is_focus(child);
    g_object_ref(child);
    gtk_container_remove(window, child);
    GtkWidget *overlay = gtk_overlay_new();
    g_object_set_data(overlay, "ferry-webkit-overlay", (void *)1);
    gtk_container_add(overlay, child);
    g_object_unref(child);
    gtk_container_add(window, overlay);
    gtk_widget_show(overlay);
    g_signal_connect_data(window, "destroy", (GCallback)on_window_destroy, NULL, NULL, 0);
    if (focused)
        gtk_widget_grab_focus(child);
    return overlay;
}

@implementation WKEmbed {
    GtkWidget *_web, *_layout;
    NSView *_owner;          /* not retained: it owns this */
    int _placed[8];          /* the last placement given to GTK */
    BOOL _shown, _syncQueued;
}

+ (void)_windowsUpdated:(NSNotification *)n
{
    NSWindow *window = [n object];
    for (size_t i = 0; i < nembeds; i++)
        if ([embeds[i]->_owner window] == window || gtk_widget_get_parent(embeds[i]->_layout))
            [embeds[i] sync];
}

- (instancetype)initWithWebView:(GtkWidget *)web owner:(NSView *)owner
{
    self = [super init];
    _web = g_object_ref_sink(web);
    _owner = owner;
    _layout = g_object_ref_sink(gtk_layout_new(NULL, NULL));
    gtk_widget_set_halign(_layout, GTK_ALIGN_START);
    gtk_widget_set_valign(_layout, GTK_ALIGN_START);
    gtk_layout_put(_layout, _web, 0, 0);
    gtk_widget_show(_web);
    static BOOL observing;
    if (!observing) {
        observing = YES;
        [[NSNotificationCenter defaultCenter] addObserver:[WKEmbed class] selector:@selector(_windowsUpdated:)
                                                     name:NSWindowDidUpdateNotification object:nil];
    }
    if (nembeds == embeds_cap) {
        embeds_cap = embeds_cap ? embeds_cap * 2 : 8;
        embeds = realloc(embeds, embeds_cap * sizeof *embeds);
    }
    embeds[nembeds++] = self;
    return self;
}

- (GtkWidget *)web { return _web; }

- (void)_detach
{
    GtkWidget *parent = _layout ? gtk_widget_get_parent(_layout) : NULL;
    if (parent)
        gtk_container_remove(parent, _layout);
    _shown = NO;
    memset(_placed, 0, sizeof _placed);
}

static void on_window_destroy(GtkWidget *window, void *data)
{
    /* before GTK destroys the window's children: the web views leave it,
     * alive, to be shown again in the window AppKit makes next */
    GtkWidget *overlay = gtk_bin_get_child(window);
    for (size_t i = 0; i < nembeds; i++)
        if (overlay && gtk_widget_get_parent(embeds[i]->_layout) == overlay)
            [embeds[i] _detach];
}

- (void)_queuedSync
{
    _syncQueued = NO;
    [self sync];
}

- (void)setNeedsSync
{
    if (_syncQueued || !_layout)
        return;
    _syncQueued = YES;
    [self performSelector:@selector(_queuedSync) withObject:nil afterDelay:0];
}

- (void)sync
{
    if (!_layout)
        return;
    NSWindow *window = [_owner window];
    GtkWidget *top = [window isVisible] ? [window _gtkWindow] : NULL;
    if (!top || [_owner isHiddenOrHasHiddenAncestor]) {
        if (_shown) {
            gtk_widget_hide(_layout);
            _shown = NO;
        }
        if (!top && gtk_widget_get_parent(_layout))
            [self _detach];
        return;
    }
    GtkWidget *overlay = overlay_of(top);
    if (!overlay)
        return;
    if (gtk_widget_get_parent(_layout) != overlay) {
        [self _detach];
        gtk_overlay_add_overlay(overlay, _layout);
    }
    CGFloat height = NSHeight([window frame]);
    NSRect full = [_owner convertRect:[_owner bounds] toView:nil];
    NSRect shown = [_owner convertRect:[_owner visibleRect] toView:nil];
    int place[8] = {
        (int)lround(NSMinX(shown)), (int)lround(height - NSMaxY(shown)), (int)lround(NSWidth(shown)),
        (int)lround(NSHeight(shown)), (int)lround(NSMinX(full) - NSMinX(shown)),
        (int)lround(NSMaxY(shown) - NSMaxY(full)), (int)lround(NSWidth(full)), (int)lround(NSHeight(full)),
    };
    BOOL visible = place[2] > 0 && place[3] > 0;
    if (visible && memcmp(place, _placed, sizeof place)) {
        gtk_widget_set_margin_start(_layout, place[0] > 0 ? place[0] : 0);
        gtk_widget_set_margin_top(_layout, place[1] > 0 ? place[1] : 0);
        gtk_widget_set_size_request(_layout, place[2], place[3]);
        gtk_layout_move(_layout, _web, place[4], place[5]);
        gtk_widget_set_size_request(_web, place[6], place[7]);
        memcpy(_placed, place, sizeof place);
    }
    if (visible != _shown) {
        if (visible)
            gtk_widget_show(_layout);
        else
            gtk_widget_hide(_layout);
        _shown = visible;
    }
}

- (NSArray *)placement
{
    if (!_shown)
        return @[];
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < 6; i++)
        [a addObject:@(_placed[i])];
    return a;
}

- (void)focus
{
    [self sync];
    if (_shown && !gtk_widget_is_focus(_web))
        gtk_widget_grab_focus(_web);
}

- (void)unfocus
{
    GtkWidget *overlay = gtk_widget_get_parent(_layout);
    if (overlay && gtk_widget_is_focus(_web)) {
        GtkWidget *area = gtk_bin_get_child(overlay);
        if (area)
            gtk_widget_grab_focus(area);
    }
}

- (BOOL)hasFocus { return _web && gtk_widget_is_focus(_web); }

- (void)invalidate
{
    if (!_layout)
        return;
    for (size_t i = 0; i < nembeds; i++)
        if (embeds[i] == self) {
            embeds[i] = embeds[--nembeds];
            break;
        }
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self _detach];
    gtk_widget_destroy(_layout);
    g_object_unref(_layout);
    g_object_unref(_web);
    _layout = _web = NULL;
}

- (void)dealloc
{
    [self invalidate];
    [super dealloc];
}
@end
