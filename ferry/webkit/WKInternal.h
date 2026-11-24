/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: shared internals. Our own code, written from Apple's
 * public WebKit documentation and WebKitGTK's public API documentation;
 * built as a Mach-O library with ferry-cc, without ARC, like AppKit.
 *
 * Both of the Mac's web views, WKWebView (WKWebView.m) and the older
 * WebView (WebView.m), are NSViews that each own one WebKitGTK web view.
 * WKEmbed (WKSupport.m) places that GTK view over the NSView in AppKit's
 * GTK window, and the rest of WKSupport.m turns what WebKitGTK hands back
 * (values, errors, requests and responses) into Foundation's objects. */
#ifndef FERRY_WEBKIT_INTERNAL_H
#define FERRY_WEBKIT_INTERNAL_H
#include "../appkit/AInternal.h"
#include "WKHost.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

/* src/host.c: one WebKitGTK or JavaScriptCore call, by name */
void *ferry_webkit_symbol(const char *name);

/* A WebKitGTK call, looked up the first time this place makes it. A call
 * this system's WebKitGTK lacks stops the program with its name. */
void *WKLookup(const char *name);
#define WK(fn)                                                                                              \
    (*({                                                                                                    \
        static __typeof__(&fn) wk_p_;                                                                       \
        if (!wk_p_)                                                                                         \
            wk_p_ = (__typeof__(&fn))WKLookup(#fn);                                                         \
        wk_p_;                                                                                              \
    }))

/* YES when web views can be shown: WebKitGTK is installed and there is a
 * display. Otherwise says why, once, and web views stay empty. */
BOOL WKAvailable(void);
/* Says once, on stderr, that a part of WebKit isn't supported yet. */
void WKWarnOnce(const char *what);

/* Connects a GTK signal; the handler's data is the object given (not retained). */
unsigned long WKConnect(void *instance, const char *signal, void *handler, id data);
/* Drops every handler of an instance whose data is the object given. */
void WKDisconnect(void *instance, id data);

/* ---- what pages hand back ------------------------------------------------------------- */

NSString *WKString(const char *s);
/* A JavaScript string literal (in JSON's quoting) holding the text. */
NSString *WKQuote(NSString *text);
/* A value of the page, as WKWebView's evaluateJavaScript: gives it:
 * NSNumber, NSString, NSDate, NSArray, NSDictionary or NSNull, nil for
 * undefined; *unsupported is set for what can't be one of those. */
id WKObjectFromJSC(JSCValue *value, BOOL *unsupported);
/* The objects of a JSON text, or nil */
id WKObjectFromJSON(const char *json);
/* A WebKitGTK error as a Mac one: NSURLErrorDomain for loading, the
 * WebKitErrorDomain for policy errors. */
NSError *WKLoadError(GError *error, const char *failingURI);
NSURLRequest *WKRequest(WebKitURIRequest *request);
NSURLResponse *WKResponse(WebKitURIResponse *response);
NSEventModifierFlags WKModifiers(unsigned gdkModifiers);

/* Runs GLib's main context (WebKitGTK's replies come there) until *done,
 * or for the time given; NO if the time ran out. For the older WebView's
 * calls that answer at once on a Mac. */
BOOL WKWaitFor(volatile BOOL *done, NSTimeInterval seconds);
/* A script run in the page and its result as JSON text, waited for (nil
 * if it failed or took too long). */
NSString *WKEvaluateJSONSync(GtkWidget *web, NSString *script);

/* A snapshot of the page, as an image */
NSImage *WKImageFromSurface(cairo_surface_t *surface);

/* ---- the GTK web view inside an NSView ---------------------------------------------- */

/* The WebKitWebView sits in a GtkLayout of its own, which clips it to the
 * part of the NSView that is shown. Once the NSView is in a window shown on
 * screen, the layout is an overlay child of the window's GtkOverlay, laid
 * over AppKit's drawing area (which WKEmbed moves into the overlay the first
 * time), at the NSView's place. It follows the view on every pass of the
 * event loop (NSWindowDidUpdateNotification) and whenever the view draws. */
@interface WKEmbed : NSObject
- (instancetype)initWithWebView:(GtkWidget *)web owner:(NSView *)owner;
@property (readonly) GtkWidget *web;
/* Places the GTK view where the NSView is now (or takes it off screen). */
- (void)sync;
/* The same, once this pass of the event loop is over (from drawing, and
 * from changes to the view's frame). */
- (void)setNeedsSync;
/* Keyboard focus: to the GTK view, or back to AppKit's drawing area. */
- (void)focus;
- (void)unfocus;
- (BOOL)hasFocus;
/* Takes the GTK view away for good (the NSView is going). */
- (void)invalidate;
/* For tests: where the view is placed, in GTK's coordinates of the window,
 * {x, y, width, height} of the shown part, then the view's offset in it. */
- (NSArray *)placement;
@end

/* ---- shared between the two web views ------------------------------------------------ */

@interface WKWebView (FerryPrivate)
- (GtkWidget *)_gtkWebView;   /* NULL without WebKitGTK or a display */
- (WebKitSettings *)_gtkSettings;
- (void)_setApplicationName:(NSString *)name;
/* for tests: WKEmbed's placement, and whether the GTK view has the keyboard */
- (NSArray *)_ferryPlacement;
- (BOOL)_ferryHasFocus;
@end
@interface WKWebsiteDataStore (FerryPrivate)
- (WebKitWebContext *)_context;
@end
@interface WKUserContentController (FerryPrivate)
- (WebKitUserContentManager *)_manager;
- (void)_addWebView:(WKWebView *)view;
- (void)_removeWebView:(WKWebView *)view;
@end
@interface WKPreferences (FerryPrivate)
- (void)_applyTo:(WebKitSettings *)settings;
- (void)_addSettings:(WebKitSettings *)settings;
- (void)_removeSettings:(WebKitSettings *)settings;
@end
@interface WKWebViewConfiguration (FerryPrivate)
/* the web view a new window's view is made beside (createWebView) */
@property (assign) GtkWidget *_relatedView;
@end
@interface WKFrameInfo (FerryPrivate)
+ (WKFrameInfo *)_mainFrameOf:(WKWebView *)view request:(NSURLRequest *)request;
@end
@interface WKContentWorld (FerryPrivate)
/* the name of WebKitGTK's script world: NULL for the page's own */
- (const char *)_gtkName;
@end
@interface WKNavigationResponse (FerryPrivate)
+ (WKNavigationResponse *)_responseFrom:(WebKitPolicyDecision *)decision;
@end
@interface WKBackForwardList (FerryPrivate)
- (instancetype)_initWithList:(WebKitBackForwardList *)list;
@end
@interface WKBackForwardListItem (FerryPrivate)
- (WebKitBackForwardListItem *)_item;
@end
@interface WKNavigationAction (FerryPrivate)
+ (WKNavigationAction *)_actionFrom:(WebKitNavigationAction *)action view:(WKWebView *)view newWindow:(BOOL)newWindow;
- (NSString *)_targetFrameName;
@end

/* ---- the older WebView's pages, frames and DOM (freemac 1.217, Ferry 0.42.0) -------- */

/* WebView.m: a script's body run in the older web view's page, waited for,
 * with W, the page's table of the values handed out. Its result comes back
 * as the older WebKit's objects: NSString, NSNumber, NSNull, WebUndefined,
 * a WebScriptObject or a DOM object (one object for each value of the page
 * while it is kept). With WSRaise an exception in the page raises
 * DOMException; with WSGeometry the page's size and scroll position come
 * back too, for the frame view (the script may have changed them). */
enum { WSRaise = 1, WSGeometry = 2 };
id WSRun(GtkWidget *web, NSString *body, int flags);
/* an Objective-C value as a JavaScript expression */
NSString *WSLiteral(id value);
/* the WebView whose page this GTK view shows */
WebView *WSWebViewOf(GtkWidget *web);
/* WebDOM.m: the class of the DOM object for a value of the page, from its
 * JavaScript class name and what kind of node it is (-1 for no node) */
Class WSClassFor(NSString *jsClass, int kind);

@interface WebScriptObject (FerryPrivate)
- (instancetype)_initWithWeb:(GtkWidget *)web handle:(long)handle generation:(NSString *)generation;
- (GtkWidget *)_web;
- (NSString *)_expression;            /* the value, as an expression of the page */
- (id)_run:(NSString *)body flags:(int)flags;   /* a body with o, the value */
@end

@interface WebFrame (FerryPrivate)
- (NSString *)_windowExpression;      /* this frame's window, from the main frame's */
- (NSArray *)_path;                   /* the indexes of window.frames from the main frame */
@end

@interface WebView (FerryPrivate)
- (WKWebView *)_wk;
- (WebFrame *)_frameAtPath:(NSArray *)path create:(BOOL)create;
- (void)_scrollFrame:(WebFrame *)frame to:(NSPoint)point;
- (CGFloat)_zoom;
@end

@interface WebFrameView (FerryPrivate)
- (instancetype)_initWithFrame:(NSRect)rect webFrame:(WebFrame *)frame;
/* the page's scroll position and size {x, y, width, height}, in CSS pixels */
- (void)_setPageGeometry:(NSArray *)geometry;
- (void)_forget;   /* its frame is going */
@end

#endif
