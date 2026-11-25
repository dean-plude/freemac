/* SPDX-License-Identifier: GPL-3.0-or-later
 * The older WebView's DOM classes, with this system's WebKitGTK (freemac
 * 1.217, Ferry 0.42.0): the document, nodes, elements and lists, their
 * classes, reading and changing the page through them, one object for each
 * node, and DOMException. A page from a string only. */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

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

static const char *cls(id o) { return o ? object_getClassName(o) : "nil"; }

@interface Loads : NSObject <WebFrameLoadDelegate>
@property int finished;
@property (copy) NSString *title;
@end
@implementation Loads
/* the main frame's title as WebKit reports it, which comes after a
 * script's change, on a later turn of the run loop (1.229) */
- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
    if (frame == sender.mainFrame)
        self.title = title;
}
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (frame == sender.mainFrame)
        _finished++;
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        WebView *web = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
        Loads *loads = [[Loads alloc] init];
        web.frameLoadDelegate = loads;
        [window.contentView addSubview:web];
        [window makeKeyAndOrderFront:nil];
        [web.mainFrame loadHTMLString:@"<!DOCTYPE html><html lang=en><head><title>The page</title></head>"
                                      @"<body style='margin:0'><h1 id=top class='big title'>Hello</h1>"
                                      @"<p id=p1 data-x=1>One <b>bold</b> word</p><p id=p2>Two</p>"
                                      @"<ul><li>a</li><li>b</li><li>c</li></ul>"
                                      @"<a id=link href='next.html#part'>next</a>"
                                      @"<div id=box style='height:50px;overflow:auto'><div style='height:400px'>x</div></div>"
                                      @"<div id=far style='margin-top:2000px'>far</div></body></html>"
                              baseURL:[NSURL URLWithString:@"file:///tmp/dom/"]];
        if (!spin_until(^{ return (BOOL)(loads.finished > 0); }))
            printf("(timed out)\n");

        DOMDocument *doc = web.mainFrameDocument;
        printf("document %s, the main frame's %d, title \"%s\", URL %s\n", cls(doc), doc == web.mainFrame.DOMDocument,
               [doc.title UTF8String], [doc.URL UTF8String]);
        printf("documentElement %s <%s lang=%s>, head %s, body %s, doctype %s %s\n", cls(doc.documentElement),
               [doc.documentElement.tagName UTF8String], [[doc.documentElement getAttribute:@"lang"] UTF8String],
               cls(doc.head), cls(doc.body), cls(doc.doctype), [doc.doctype.name UTF8String]);
        printf("one object for each node: body %d, documentElement %d, equal %d\n", doc.body == doc.body,
               doc.documentElement == doc.body.parentNode, [doc.body isEqual:[doc querySelector:@"body"]]);

        DOMElement *h1 = [doc getElementById:@"top"];
        printf("h1: %s, text \"%s\", className \"%s\", id \"%s\", nodeType %d, nodeName %s\n", cls(h1),
               [h1.textContent UTF8String], [h1.className UTF8String], [((DOMHTMLElement *)h1).idName UTF8String],
               h1.nodeType, [h1.nodeName UTF8String]);
        DOMHTMLElement *p1 = (DOMHTMLElement *)[doc getElementById:@"p1"];
        printf("p1: %s, innerHTML \"%s\", data-x %s, has data-y %d\n", cls(p1), [p1.innerHTML UTF8String],
               [[p1 getAttribute:@"data-x"] UTF8String], [p1 hasAttribute:@"data-y"]);
        printf("its children: %u nodes (%s, %s, %s), first %s \"%s\", parent %s\n", p1.childNodes.length,
               cls([p1.childNodes item:0]), cls([p1.childNodes item:1]), cls([p1.childNodes item:2]),
               cls(p1.firstChild), [p1.firstChild.nodeValue UTF8String], cls(p1.parentNode));
        DOMNamedNodeMap *attributes = p1.attributes;
        printf("its attributes: %s, %u, the first %s %s=%s\n", cls(attributes), attributes.length,
               cls([attributes item:0]), [[[attributes item:0] name] UTF8String],
               [[(DOMAttr *)[attributes item:0] value] UTF8String]);

        DOMNodeList *items = [doc getElementsByTagName:@"li"];
        printf("li: %s of %u, the second %s \"%s\"\n", cls(items), items.length, cls([items item:1]),
               [[[items item:1] textContent] UTF8String]);
        DOMNodeList *ps = [doc querySelectorAll:@"p"];
        printf("querySelectorAll p: %s of %u; querySelector ul > li:last-child \"%s\"; none: %s\n", cls(ps), ps.length,
               [[doc querySelector:@"ul > li:last-child"].textContent UTF8String], cls([doc querySelector:@"table"]));
        printf("by class: %u; webkitMatchesSelector .big %d\n", [doc getElementsByClassName:@"title"].length,
               [h1 webkitMatchesSelector:@".big"]);

        /* changing the page */
        DOMElement *div = [doc createElement:@"div"];
        DOMText *t = [doc createTextNode:@"made here"];
        [div appendChild:t];
        [div setAttribute:@"id" value:@"made"];
        div.className = @"new";
        printf("made: %s and %s, in the page %d\n", cls(div), cls(t), [doc getElementById:@"made"] != nil);
        [doc.body insertBefore:div refChild:h1];
        printf("inserted: first child now #%s, found %d, same object %d\n",
               [[(DOMElement *)doc.body.firstChild getAttribute:@"id"] UTF8String], [doc getElementById:@"made"] != nil,
               [doc getElementById:@"made"] == div);
        [doc.body removeChild:div];
        printf("removed: found %d, parent %s\n", [doc getElementById:@"made"] != nil, cls(div.parentNode));
        p1.innerHTML = @"<i>new</i> text";
        printf("innerHTML set: \"%s\", outerHTML \"%s\"\n", [p1.textContent UTF8String], [p1.outerHTML UTF8String]);
        ((DOMHTMLElement *)[doc getElementById:@"p2"]).outerHTML = @"<p id=p3>Three</p>";
        printf("outerHTML set: p2 %s, p3 \"%s\"\n", cls([doc getElementById:@"p2"]),
               [[doc getElementById:@"p3"].textContent UTF8String]);
        doc.title = @"Changed";
        /* the web view's title follows once WebKit says it changed */
        BOOL told = spin_until(^{
            return (BOOL)([loads.title isEqualToString:@"Changed"] && [web.mainFrameTitle isEqualToString:@"Changed"]);
        });
        printf("title set: \"%s\", the frame load delegate told %d, the frame's data source says \"%s\"\n",
               [doc.title UTF8String], told, [web.mainFrameTitle UTF8String]);
        [h1.style setProperty:@"color" value:@"rgb(1, 2, 3)" priority:@""];
        printf("style: %s, color %s, cssText \"%s\"\n", cls(h1.style), [[h1.style getPropertyValue:@"color"] UTF8String],
               [h1.style.cssText UTF8String]);

        DOMHTMLAnchorElement *a = (DOMHTMLAnchorElement *)[doc getElementById:@"link"];
        printf("a: %s, href %s, hash %s, absoluteLinkURL %s\n", cls(a), [a.href UTF8String], [a.hashName UTF8String],
               [[a.absoluteLinkURL absoluteString] UTF8String]);
        printf("links %s of %u\n", cls(doc.links), doc.links.length);

        /* layout and scrolling */
        DOMElement *box = [doc getElementById:@"box"];
        box.scrollTop = 100;
        printf("box: offsetTop > 0 %d, clientHeight %d, scrollHeight %d, scrollTop %d\n", box.offsetTop > 0,
               box.clientHeight, box.scrollHeight, box.scrollTop);
        DOMElement *far = [doc getElementById:@"far"];
        [far scrollIntoView:YES];
        int scrolled = [[web stringByEvaluatingJavaScriptFromString:@"scrollY"] intValue];
        printf("scrolled into view: the page scrolled down %d\n", scrolled > 1000);
        NSView *documentView = web.mainFrame.frameView.documentView;
        printf("the frame view follows at once: %d\n",
               (int)documentView.enclosingScrollView.contentView.bounds.origin.y == scrolled);

        /* exceptions in the page raise DOMException */
        @try {
            [doc querySelector:@"##"];
            printf("no exception\n");
        } @catch (NSException *e) {
            printf("bad selector: %s\n", [e.name UTF8String]);
        }
        @try {
            [h1 appendChild:doc.documentElement];
            printf("no exception\n");
        } @catch (NSException *e) {
            printf("a node into its own child: %s\n", [e.name UTF8String]);
        }

        /* the script objects are the same */
        WebScriptObject *bodyFromScript = [web.windowScriptObject evaluateWebScript:@"document.body"];
        printf("document.body from a script: %s, the same %d\n", cls(bodyFromScript), bodyFromScript == doc.body);
        printf("a plain object from a script: %s\n", cls([web.windowScriptObject evaluateWebScript:@"({a:1})"]));

        /* a new page: its nodes are new */
        int before = loads.finished;
        [web.mainFrame loadHTMLString:@"<body><p id=p1>Again</p></body>" baseURL:nil];
        spin_until(^{ return (BOOL)(loads.finished > before); });
        printf("after a new page: old p1 text \"%s\", new p1 \"%s\", different %d\n", [p1.textContent UTF8String],
               [[web.mainFrameDocument getElementById:@"p1"].textContent UTF8String],
               [web.mainFrameDocument getElementById:@"p1"] != p1);
    }
    return 0;
}
