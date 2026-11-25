/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older web view's selection and ranges, computed style,
 * the CSS properties by name and a frame's JavaScriptCore context (freemac
 * 1.225, Ferry 0.49.0), which MacDown uses. Our own code, written from
 * Apple's public documentation of DOMRange, DOMCSSStyleDeclaration,
 * WebView and WebFrame and the W3C's and WHATWG's DOM standards.
 *
 * As in WebDOM.m, each property read or call is a script run in the page.
 * A frame's javaScriptContext is a JSContext (JavaScriptCore's, loaded by
 * the program) whose scripts run in the frame's window instead of a context
 * of their own; what a script gives back is copied, as JSON carries it, into
 * a value of that context, so numbers, strings, arrays and plain objects
 * come back, and functions and nodes don't. */
#import "WKInternal.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <ctype.h>

NSString *const WebViewDidBeginEditingNotification = @"WebViewDidBeginEditingNotification";
NSString *const WebViewDidChangeNotification = @"WebViewDidChangeNotification";
NSString *const WebViewDidEndEditingNotification = @"WebViewDidEndEditingNotification";
NSString *const WebViewDidChangeSelectionNotification = @"WebViewDidChangeSelectionNotification";

static NSString *string_of(id v)
{
    if ([v isKindOfClass:[NSString class]])
        return v;
    if ([v isKindOfClass:[NSNumber class]])
        return [v stringValue];
    return @"";
}
static id object_of(id v, Class c) { return [v isKindOfClass:c] ? v : nil; }
static int int_of(id v) { return [v isKindOfClass:[NSNumber class]] ? [v intValue] : 0; }

/* ---- DOMRange ------------------------------------------------------------------------ */

@implementation DOMRange
- (DOMNode *)startContainer
{
    return (DOMNode *)object_of([self _run:@"return o.startContainer;" flags:0], [DOMNode class]);
}
- (DOMNode *)endContainer
{
    return (DOMNode *)object_of([self _run:@"return o.endContainer;" flags:0], [DOMNode class]);
}
- (DOMNode *)commonAncestorContainer
{
    return (DOMNode *)object_of([self _run:@"return o.commonAncestorContainer;" flags:0], [DOMNode class]);
}
- (int)startOffset { return int_of([self _run:@"return o.startOffset;" flags:0]); }
- (int)endOffset { return int_of([self _run:@"return o.endOffset;" flags:0]); }
- (BOOL)collapsed { return [[self _run:@"return o.collapsed;" flags:0] boolValue]; }
- (NSString *)text { return string_of([self _run:@"return o.toString();" flags:0]); }
- (NSString *)toString { return [self text]; }
- (NSString *)markupString
{
    return string_of([self _run:@"var d=o.startContainer.ownerDocument||document,e=d.createElement('div');"
                                @"e.appendChild(o.cloneContents());return e.innerHTML;"
                          flags:0]);
}
- (void)setStart:(DOMNode *)node offset:(int)offset
{
    [self _run:[NSString stringWithFormat:@"o.setStart(%@,%d);", WSLiteral(node), offset] flags:WSRaise];
}
- (void)setEnd:(DOMNode *)node offset:(int)offset
{
    [self _run:[NSString stringWithFormat:@"o.setEnd(%@,%d);", WSLiteral(node), offset] flags:WSRaise];
}
static void node_call(DOMRange *r, NSString *method, DOMNode *node)
{
    [r _run:[NSString stringWithFormat:@"o.%@(%@);", method, WSLiteral(node)] flags:WSRaise];
}
- (void)setStartBefore:(DOMNode *)node { node_call(self, @"setStartBefore", node); }
- (void)setStartAfter:(DOMNode *)node { node_call(self, @"setStartAfter", node); }
- (void)setEndBefore:(DOMNode *)node { node_call(self, @"setEndBefore", node); }
- (void)setEndAfter:(DOMNode *)node { node_call(self, @"setEndAfter", node); }
- (void)selectNode:(DOMNode *)node { node_call(self, @"selectNode", node); }
- (void)selectNodeContents:(DOMNode *)node { node_call(self, @"selectNodeContents", node); }
- (void)collapse:(BOOL)toStart
{
    [self _run:[NSString stringWithFormat:@"o.collapse(%@);", toStart ? @"true" : @"false"] flags:WSRaise];
}
- (short)compareBoundaryPoints:(unsigned short)how sourceRange:(DOMRange *)source
{
    return (short)int_of([self _run:[NSString stringWithFormat:@"return o.compareBoundaryPoints(%u,%@);", how,
                                                               WSLiteral(source)]
                              flags:WSRaise]);
}
- (void)deleteContents { [self _run:@"o.deleteContents();" flags:WSRaise | WSGeometry]; }
- (DOMDocumentFragment *)extractContents
{
    return (DOMDocumentFragment *)object_of([self _run:@"return o.extractContents();" flags:WSRaise | WSGeometry],
                                            [DOMDocumentFragment class]);
}
- (DOMDocumentFragment *)cloneContents
{
    return (DOMDocumentFragment *)object_of([self _run:@"return o.cloneContents();" flags:WSRaise],
                                            [DOMDocumentFragment class]);
}
- (void)insertNode:(DOMNode *)node
{
    [self _run:[NSString stringWithFormat:@"o.insertNode(%@);", WSLiteral(node)] flags:WSRaise | WSGeometry];
}
- (void)surroundContents:(DOMNode *)parent
{
    [self _run:[NSString stringWithFormat:@"o.surroundContents(%@);", WSLiteral(parent)] flags:WSRaise | WSGeometry];
}
- (DOMRange *)cloneRange
{
    return (DOMRange *)object_of([self _run:@"return o.cloneRange();" flags:0], [DOMRange class]);
}
- (void)detach { }
@end

/* ---- computed style, and the CSS properties by name ------------------------------------ */

@implementation DOMDocument (DOMDocumentRangeAndStyle)
- (DOMRange *)createRange
{
    return (DOMRange *)object_of([self _run:@"return o.createRange();" flags:WSRaise], [DOMRange class]);
}
- (DOMCSSStyleDeclaration *)getComputedStyle:(DOMElement *)element pseudoElement:(NSString *)pseudo
{
    NSString *p = [pseudo length] ? WSLiteral(pseudo) : @"null";
    return (DOMCSSStyleDeclaration *)object_of(
        [self _run:[NSString stringWithFormat:@"return (o.defaultView||window).getComputedStyle(%@,%@);",
                                              WSLiteral(element), p]
             flags:WSRaise],
        [DOMCSSStyleDeclaration class]);
}
@end

/* backgroundColor is background-color; cssFloat is float */
static NSString *css_name(const char *sel, BOOL setter)
{
    NSString *s = [NSString stringWithUTF8String:sel];
    if (setter) {
        if (![s hasPrefix:@"set"] || ![s hasSuffix:@":"] || [s length] < 5)
            return nil;
        s = [[[s substringWithRange:NSMakeRange(3, 1)] lowercaseString]
            stringByAppendingString:[s substringWithRange:NSMakeRange(4, [s length] - 5)]];
    } else if ([s rangeOfString:@":"].location != NSNotFound)
        return nil;
    if ([s isEqualToString:@"cssFloat"])
        return @"float";
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c >= 'A' && c <= 'Z')
            [m appendFormat:@"-%C", (unichar)(c + 32)];
        else
            [m appendFormat:@"%C", c];
    }
    return m;
}
static NSString *css_get(DOMCSSStyleDeclaration *self, SEL _cmd)
{
    return [self getPropertyValue:css_name(sel_getName(_cmd), NO)];
}
static void css_set(DOMCSSStyleDeclaration *self, SEL _cmd, NSString *value)
{
    [self setProperty:css_name(sel_getName(_cmd), YES) value:value ?: @"" priority:@""];
}

@implementation DOMCSSStyleDeclaration (DOMCSS2Properties)
@dynamic background, backgroundAttachment, backgroundColor, backgroundImage, backgroundPosition, backgroundRepeat,
    border, borderBottom, borderCollapse, borderColor, borderLeft, borderRight, borderSpacing, borderStyle,
    borderTop, borderWidth, bottom, clear, clip, color, content, cursor, direction, display, cssFloat, font,
    fontFamily, fontSize, fontStyle, fontVariant, fontWeight, height, left, letterSpacing, lineHeight, listStyle,
    listStyleType, margin, marginBottom, marginLeft, marginRight, marginTop, maxHeight, maxWidth, minHeight,
    minWidth, opacity, outline, overflow, padding, paddingBottom, paddingLeft, paddingRight, paddingTop, position,
    right, tableLayout, textAlign, textDecoration, textIndent, textTransform, top, verticalAlign, visibility,
    whiteSpace, width, wordSpacing, zIndex;
+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    objc_property_t prop = NULL;
    const char *name = sel_getName(sel);
    size_t n = strlen(name);
    if (n > 4 && !strncmp(name, "set", 3) && name[n - 1] == ':') {
        char buf[128];
        if (n - 4 < sizeof buf) {
            memcpy(buf, name + 3, n - 4);
            buf[n - 4] = 0;
            buf[0] = (char)tolower((unsigned char)buf[0]);
            prop = class_getProperty(self, buf);
            if (prop)
                return class_addMethod(self, sel, (IMP)css_set, "v@:@");
        }
    } else if ((prop = class_getProperty(self, name)))
        return class_addMethod(self, sel, (IMP)css_get, "@@:");
    return [super resolveInstanceMethod:sel];
}
@end

/* ---- the web view's selection ---------------------------------------------------------- */

@implementation WebView (FerryEditing)
- (DOMRange *)selectedDOMRange
{
    WebScriptObject *w = [self windowScriptObject];
    return (DOMRange *)object_of(
        [w _run:@"var s=o.getSelection();return s&&s.rangeCount?s.getRangeAt(0):null;" flags:0], [DOMRange class]);
}
- (BOOL)hasSelectedRange
{
    return [[[self windowScriptObject] _run:@"var s=o.getSelection();return !!(s&&s.rangeCount);" flags:0] boolValue];
}
- (NSSelectionAffinity)selectionAffinity { return NSSelectionAffinityDownstream; }
/* nil takes the selection away */
- (void)setSelectedDOMRange:(DOMRange *)range affinity:(NSSelectionAffinity)affinity
{
    [[self windowScriptObject] _run:[NSString stringWithFormat:@"var s=o.getSelection();if(s){s.removeAllRanges();"
                                                               @"var r=%@;if(r)s.addRange(r);}",
                                                               WSLiteral(range)]
                              flags:0];
}
- (DOMRange *)editableDOMRangeForPoint:(NSPoint)point
{
    return (DOMRange *)object_of(
        [[self windowScriptObject]
            _run:[NSString stringWithFormat:@"var d=o.document,r=d.caretRangeFromPoint?d.caretRangeFromPoint(%g,%g):null;"
                                            @"return r&&r.startContainer&&(r.startContainer.isContentEditable||"
                                            @"(r.startContainer.parentElement||{}).isContentEditable)?r:null;",
                                            point.x, point.y]
           flags:0],
        [DOMRange class]);
}
@end

/* ---- a frame's JavaScriptCore context -------------------------------------------------- */

@protocol FerryJSValueMaking
+ (id)valueWithObject:(id)value inContext:(id)context;
+ (id)valueWithUndefinedInContext:(id)context;
@end

static const char frame_key = 0;

/* the script's value, run in the frame's window and brought back as JSON */
static id page_context_evaluate(id self, SEL _cmd, NSString *script)
{
    WebFrame *frame = objc_getAssociatedObject(self, &frame_key);
    Class value = NSClassFromString(@"JSValue");
    GtkWidget *web = [frame _web];
    id result = nil;
    if (frame && web && script) {
        NSString *wrapped =
            [NSString stringWithFormat:@"(function(){try{var w=%@,r=w.eval(%@);"
                                       @"return r===undefined?{u:1}:{v:JSON.parse(JSON.stringify(r))};}"
                                       @"catch(e){return {u:1};}})()",
                                       [frame _windowExpression], WKQuote(script)];
        id answer = WKObjectFromJSON([WKEvaluateJSONSync(web, wrapped) UTF8String]);
        if ([answer isKindOfClass:[NSDictionary class]])
            result = answer[@"v"];
    }
    if (!result)
        return [(Class<FerryJSValueMaking>)value valueWithUndefinedInContext:self];
    return [(Class<FerryJSValueMaking>)value valueWithObject:result inContext:self];
}
static id page_context_evaluate_url(id self, SEL _cmd, NSString *script, NSURL *url)
{
    return page_context_evaluate(self, _cmd, script);
}

/* a subclass of the program's JSContext, made the first time one is asked for */
static Class page_context_class(void)
{
    static Class c;
    if (c)
        return c;
    Class base = NSClassFromString(@"JSContext");
    if (!base)
        return Nil;
    c = objc_allocateClassPair(base, "FerryWebFrameJSContext", 0);
    class_addMethod(c, @selector(evaluateScript:), (IMP)page_context_evaluate, "@@:@");
    class_addMethod(c, @selector(evaluateScript:withSourceURL:), (IMP)page_context_evaluate_url, "@@:@@");
    objc_registerClassPair(c);
    return c;
}

@implementation WebFrame (FerryJavaScriptContext)
- (JSContext *)javaScriptContext
{
    static const char context_key = 0;
    id ctx = objc_getAssociatedObject(self, &context_key);
    if (ctx)
        return ctx;
    Class c = page_context_class();
    if (!c)
        return nil;
    ctx = [[c alloc] init];
    objc_setAssociatedObject(ctx, &frame_key, self, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(self, &context_key, ctx, OBJC_ASSOCIATION_RETAIN);
    [ctx release];
    return ctx;
}
@end
