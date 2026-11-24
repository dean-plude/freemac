/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older WebView's DOM classes (freemac 1.217, Ferry
 * 0.42.0). Our own code, written from Apple's public documentation of the
 * DOM's Objective-C classes and the W3C's and WHATWG's DOM standards.
 *
 * The page runs in a process of WebKitGTK's own, so a DOM object here is a
 * WebScriptObject that stands for a value of the page (WebView.m keeps the
 * table of them): each property and call is a script run in the page and
 * waited for, as stringByEvaluatingJavaScriptFromString: is, which a Mac's
 * would answer at once. Most of the Objective-C names are the page's own;
 * a call that changes the page also brings back the page's size and scroll
 * position for the frame view; an exception in the page raises
 * DOMException. A string the page gives as null or undefined is "". */
#import "WKInternal.h"

NSString *const DOMException = @"DOMException";

/* the classes of the lists that have no node type */
static NSString *list_class(NSString *js)
{
    static NSDictionary *names;
    if (!names)
        names = [@{
            @"NodeList" : @"DOMNodeList",
            @"RadioNodeList" : @"DOMNodeList",
            @"HTMLCollection" : @"DOMHTMLCollection",
            @"HTMLOptionsCollection" : @"DOMHTMLCollection",
            @"HTMLFormControlsCollection" : @"DOMHTMLCollection",
            @"HTMLAllCollection" : @"DOMHTMLCollection",
            @"NamedNodeMap" : @"DOMNamedNodeMap",
            @"CSSStyleDeclaration" : @"DOMCSSStyleDeclaration",
            @"CSSStyleProperties" : @"DOMCSSStyleDeclaration",
            @"CSS2Properties" : @"DOMCSSStyleDeclaration",
        } retain];
    return names[js];
}

Class WSClassFor(NSString *js, int kind)
{
    if (kind < 0) {
        NSString *name = list_class(js);
        return name ? NSClassFromString(name) : [WebScriptObject class];
    }
    /* a node: the class of its JavaScript class's name, if there is one */
    Class c = [js length] ? NSClassFromString([@"DOM" stringByAppendingString:js]) : Nil;
    if (c && [c isSubclassOfClass:[DOMNode class]])
        return c;
    switch (kind / 2) {
    case DOM_ELEMENT_NODE:
        return kind & 1 ? [DOMHTMLElement class] : [DOMElement class];
    case DOM_ATTRIBUTE_NODE:
        return [DOMAttr class];
    case DOM_TEXT_NODE:
        return [DOMText class];
    case DOM_CDATA_SECTION_NODE:
        return [DOMCDATASection class];
    case DOM_PROCESSING_INSTRUCTION_NODE:
        return [DOMProcessingInstruction class];
    case DOM_COMMENT_NODE:
        return [DOMComment class];
    case DOM_DOCUMENT_NODE:
        return [DOMDocument class];
    case DOM_DOCUMENT_TYPE_NODE:
        return [DOMDocumentType class];
    case DOM_DOCUMENT_FRAGMENT_NODE:
        return [DOMDocumentFragment class];
    default:
        return [DOMNode class];
    }
}

static NSString *string_of(id v)
{
    if ([v isKindOfClass:[NSString class]])
        return v;
    if ([v isKindOfClass:[NSNumber class]])
        return [v stringValue];
    return @"";
}

static NSNumber *number_of(id v) { return [v isKindOfClass:[NSNumber class]] ? v : @0; }

static id object_of(id v, Class c) { return [v isKindOfClass:c] ? v : nil; }

static NSURL *url_of(id v)
{
    NSString *s = string_of(v);
    return [s length] ? [NSURL URLWithString:s] : nil;
}

/* the WebFrame of a frame element's window */
static WebFrame *content_frame(WebScriptObject *element)
{
    GtkWidget *web = [element _web];
    WebView *view = WSWebViewOf(web);
    if (!view)
        return nil;
    NSString *script = [NSString
        stringWithFormat:@"(function(){var o=%@,W=window.__ferryWS;return o&&W?W.path(o.contentWindow):null;})()",
                         [element _expression]];
    id path = WKObjectFromJSON([WKEvaluateJSONSync(web, script) UTF8String]);
    return [path isKindOfClass:[NSArray class]] && [path count] ? [view _frameAtPath:path create:YES] : nil;
}

/* ---- DOMObject ---------------------------------------------------------------------- */

/* One object stands for a value of the page while it is kept; one kept by
 * a program after its page is gone is equal only to itself. */
@implementation DOMObject
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
- (BOOL)isEqual:(id)other
{
    if (other == self)
        return YES;
    return [other isKindOfClass:[DOMObject class]] && [(DOMObject *)other _web] == [self _web] &&
           [[other _expression] isEqualToString:[self _expression]];
}
- (NSUInteger)hash { return [[self _expression] hash]; }
@end

@implementation DOMNodeList
- (id)item:(unsigned)index
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.item?o.item(%u):o[%u];", index, index]
                          flags:WSRaise],
                     [WebScriptObject class]);
}
- (unsigned)length { return (unsigned)[number_of([self _run:@"return o.length;" flags:0]) unsignedIntValue]; }
@end

@implementation DOMHTMLCollection
/* the collection's elements with the tag name */
- (DOMNodeList *)tags:(NSString *)name
{
    return (DOMNodeList *)object_of(
        [self _run:[NSString stringWithFormat:@"var n=String(%@).toLowerCase(),a=[];"
                                              @"for(var i=0;i<o.length;i++)if(o[i].localName===n||n==='*')a.push(o[i]);"
                                              @"W.force='NodeList';return a;",
                                              WSLiteral(name)]
             flags:WSRaise],
        [DOMNodeList class]);
}
- (unsigned)length { return (unsigned)[number_of([self _run:@"return o.length;" flags:0]) unsignedIntValue]; }
- (id)item:(unsigned)index
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.item(%u);", index] flags:WSRaise],
        [WebScriptObject class]);
}
- (id)namedItem:(NSString *)name
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.namedItem(%@);", WSLiteral(name)] flags:WSRaise],
        [WebScriptObject class]);
}
@end

@implementation DOMNamedNodeMap
- (unsigned)length { return (unsigned)[number_of([self _run:@"return o.length;" flags:0]) unsignedIntValue]; }
- (id)item:(unsigned)index
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.item(%u);", index] flags:WSRaise],
        [WebScriptObject class]);
}
- (id)getNamedItem:(NSString *)name
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.getNamedItem(%@);", WSLiteral(name)]
        flags:WSRaise], [WebScriptObject class]);
}
- (id)setNamedItem:(id)node
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.setNamedItem(%@);", WSLiteral(node)]
        flags:WSRaise | WSGeometry], [WebScriptObject class]);
}
- (id)removeNamedItem:(NSString *)name
{
    return object_of([self _run:[NSString stringWithFormat:@"return o.removeNamedItem(%@);", WSLiteral(name)]
        flags:WSRaise | WSGeometry], [WebScriptObject class]);
}
@end

@implementation DOMCSSStyleDeclaration
- (NSString *)cssText { return string_of([self _run:@"return o.cssText;" flags:0]); }
- (void)setCssText:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.cssText=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (unsigned)length { return (unsigned)[number_of([self _run:@"return o.length;" flags:0]) unsignedIntValue]; }
- (NSString *)item:(unsigned)index
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.item(%u);", index] flags:WSRaise]);
}
- (NSString *)getPropertyValue:(NSString *)propertyName
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.getPropertyValue(%@);", WSLiteral(propertyName)]
        flags:WSRaise]);
}
- (NSString *)getPropertyPriority:(NSString *)propertyName
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.getPropertyPriority(%@);",
        WSLiteral(propertyName)] flags:WSRaise]);
}
- (NSString *)removeProperty:(NSString *)propertyName
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.removeProperty(%@);", WSLiteral(propertyName)]
        flags:WSRaise | WSGeometry]);
}
- (void)setProperty:(NSString *)propertyName value:(NSString *)value priority:(NSString *)priority
{
    [self _run:[NSString stringWithFormat:@"return o.setProperty(%@,%@,%@);", WSLiteral(propertyName), WSLiteral(value),
        WSLiteral(priority)] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMNode
- (NSString *)nodeName { return string_of([self _run:@"return o.nodeName;" flags:0]); }
- (NSString *)nodeValue { return string_of([self _run:@"return o.nodeValue;" flags:0]); }
- (void)setNodeValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.nodeValue=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (unsigned short)nodeType
{
    return (unsigned short)[number_of([self _run:@"return o.nodeType;" flags:0]) unsignedIntValue];
}
- (DOMNode *)parentNode { return (DOMNode *)object_of([self _run:@"return o.parentNode;" flags:0], [DOMNode class]); }
- (DOMElement *)parentElement
{
    return (DOMElement *)object_of([self _run:@"return o.parentElement;" flags:0], [DOMElement class]);
}
- (DOMNodeList *)childNodes
{
    return (DOMNodeList *)object_of([self _run:@"W.force='NodeList';" @"return o.childNodes;" flags:0],
        [DOMNodeList class]);
}
- (DOMNode *)firstChild { return (DOMNode *)object_of([self _run:@"return o.firstChild;" flags:0], [DOMNode class]); }
- (DOMNode *)lastChild { return (DOMNode *)object_of([self _run:@"return o.lastChild;" flags:0], [DOMNode class]); }
- (DOMNode *)previousSibling
{
    return (DOMNode *)object_of([self _run:@"return o.previousSibling;" flags:0], [DOMNode class]);
}
- (DOMNode *)nextSibling { return (DOMNode *)object_of([self _run:@"return o.nextSibling;" flags:0], [DOMNode class]); }
- (DOMDocument *)ownerDocument
{
    return (DOMDocument *)object_of([self _run:@"return o.ownerDocument;" flags:0], [DOMDocument class]);
}
- (NSString *)namespaceURI { return string_of([self _run:@"return o.namespaceURI;" flags:0]); }
- (NSString *)prefix { return string_of([self _run:@"return o.prefix;" flags:0]); }
- (void)setPrefix:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.prefix=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)localName { return string_of([self _run:@"return o.localName;" flags:0]); }
- (DOMNamedNodeMap *)attributes
{
    return (DOMNamedNodeMap *)object_of([self _run:@"return o.attributes;" flags:0], [DOMNamedNodeMap class]);
}
- (NSString *)baseURI { return string_of([self _run:@"return o.baseURI;" flags:0]); }
- (NSString *)textContent { return string_of([self _run:@"return o.textContent;" flags:0]); }
- (void)setTextContent:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.textContent=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)isContentEditable { return [number_of([self _run:@"return !!(o.isContentEditable);" flags:0]) boolValue]; }
- (DOMNode *)insertBefore:(DOMNode *)newChild refChild:(DOMNode *)refChild
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.insertBefore(%@,%@);",
        WSLiteral(newChild), WSLiteral(refChild)] flags:WSRaise | WSGeometry], [DOMNode class]);
}
- (DOMNode *)replaceChild:(DOMNode *)newChild oldChild:(DOMNode *)oldChild
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.replaceChild(%@,%@);",
        WSLiteral(newChild), WSLiteral(oldChild)] flags:WSRaise | WSGeometry], [DOMNode class]);
}
- (DOMNode *)removeChild:(DOMNode *)oldChild
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.removeChild(%@);", WSLiteral(oldChild)]
        flags:WSRaise | WSGeometry], [DOMNode class]);
}
- (DOMNode *)appendChild:(DOMNode *)newChild
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.appendChild(%@);", WSLiteral(newChild)]
        flags:WSRaise | WSGeometry], [DOMNode class]);
}
- (BOOL)hasChildNodes { return [number_of([self _run:@"return !!o.hasChildNodes();" flags:WSRaise]) boolValue]; }
- (DOMNode *)cloneNode:(BOOL)deep
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.cloneNode(%@);", deep ? @"true" :
        @"false"] flags:WSRaise], [DOMNode class]);
}
- (void)normalize { [self _run:@"return o.normalize();" flags:WSRaise | WSGeometry]; }
- (BOOL)isSupported:(NSString *)feature version:(NSString *)version
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.isSupported(%@,%@);", WSLiteral(feature),
        WSLiteral(version)] flags:WSRaise]) boolValue];
}
- (BOOL)hasAttributes { return [number_of([self _run:@"return !!o.hasAttributes();" flags:WSRaise]) boolValue]; }
- (BOOL)isSameNode:(DOMNode *)other
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.isSameNode(%@);", WSLiteral(other)]
        flags:WSRaise]) boolValue];
}
- (BOOL)isEqualNode:(DOMNode *)other
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.isEqualNode(%@);", WSLiteral(other)]
        flags:WSRaise]) boolValue];
}
- (NSString *)lookupPrefix:(NSString *)namespaceURI
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.lookupPrefix(%@);", WSLiteral(namespaceURI)]
        flags:WSRaise]);
}
- (NSString *)lookupNamespaceURI:(NSString *)prefix
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.lookupNamespaceURI(%@);", WSLiteral(prefix)]
        flags:WSRaise]);
}
- (BOOL)isDefaultNamespace:(NSString *)namespaceURI
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.isDefaultNamespace(%@);",
        WSLiteral(namespaceURI)] flags:WSRaise]) boolValue];
}
- (unsigned short)compareDocumentPosition:(DOMNode *)other
{
    return (unsigned short)[number_of([self _run:[NSString stringWithFormat:@"return o.compareDocumentPosition(%@);",
        WSLiteral(other)] flags:WSRaise]) unsignedIntValue];
}
- (BOOL)contains:(DOMNode *)other
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.contains(%@);", WSLiteral(other)]
        flags:WSRaise]) boolValue];
}
@end

@implementation DOMAttr
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (BOOL)specified { return [number_of([self _run:@"return !!(o.specified);" flags:0]) boolValue]; }
- (NSString *)value { return string_of([self _run:@"return o.value;" flags:0]); }
- (void)setValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.value=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMElement *)ownerElement
{
    return (DOMElement *)object_of([self _run:@"return o.ownerElement;" flags:0], [DOMElement class]);
}
@end

@implementation DOMCharacterData
- (NSString *)data { return string_of([self _run:@"return o.data;" flags:0]); }
- (void)setData:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.data=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (unsigned)length { return (unsigned)[number_of([self _run:@"return o.length;" flags:0]) unsignedIntValue]; }
- (NSString *)substringData:(unsigned)offset length:(unsigned)length
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.substringData(%u,%u);", offset, length]
        flags:WSRaise]);
}
- (void)appendData:(NSString *)data
{
    [self _run:[NSString stringWithFormat:@"return o.appendData(%@);", WSLiteral(data)] flags:WSRaise | WSGeometry];
}
- (void)insertData:(unsigned)offset data:(NSString *)data
{
    [self _run:[NSString stringWithFormat:@"return o.insertData(%u,%@);", offset, WSLiteral(data)]
        flags:WSRaise | WSGeometry];
}
- (void)deleteData:(unsigned)offset length:(unsigned)length
{
    [self _run:[NSString stringWithFormat:@"return o.deleteData(%u,%u);", offset, length] flags:WSRaise | WSGeometry];
}
- (void)replaceData:(unsigned)offset length:(unsigned)length data:(NSString *)data
{
    [self _run:[NSString stringWithFormat:@"return o.replaceData(%u,%u,%@);", offset, length, WSLiteral(data)]
        flags:WSRaise | WSGeometry];
}
@end

@implementation DOMText
- (NSString *)wholeText { return string_of([self _run:@"return o.wholeText;" flags:0]); }
- (DOMText *)splitText:(unsigned)offset
{
    return (DOMText *)object_of([self _run:[NSString stringWithFormat:@"return o.splitText(%u);", offset]
        flags:WSRaise | WSGeometry], [DOMText class]);
}
@end

@implementation DOMComment
@end

@implementation DOMCDATASection
@end

@implementation DOMProcessingInstruction
- (NSString *)target { return string_of([self _run:@"return o.target;" flags:0]); }
@end

@implementation DOMDocumentType
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (NSString *)publicId { return string_of([self _run:@"return o.publicId;" flags:0]); }
- (NSString *)systemId { return string_of([self _run:@"return o.systemId;" flags:0]); }
@end

@implementation DOMDocumentFragment
- (DOMElement *)getElementById:(NSString *)elementId
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.getElementById(%@);",
        WSLiteral(elementId)] flags:WSRaise], [DOMElement class]);
}
- (DOMElement *)querySelector:(NSString *)selectors
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.querySelector(%@);",
        WSLiteral(selectors)] flags:WSRaise], [DOMElement class]);
}
- (DOMNodeList *)querySelectorAll:(NSString *)selectors
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.querySelectorAll(%@);", WSLiteral(selectors)] flags:WSRaise], [DOMNodeList class]);
}
@end

@implementation DOMElement
- (NSString *)tagName { return string_of([self _run:@"return o.tagName;" flags:0]); }
- (NSString *)className { return string_of([self _run:@"return o.className;" flags:0]); }
- (void)setClassName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.className=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMCSSStyleDeclaration *)style
{
    return (DOMCSSStyleDeclaration *)object_of([self _run:@"return o.style;" flags:0], [DOMCSSStyleDeclaration class]);
}
- (int)offsetLeft { return (int)[number_of([self _run:@"return o.offsetLeft;" flags:0]) intValue]; }
- (int)offsetTop { return (int)[number_of([self _run:@"return o.offsetTop;" flags:0]) intValue]; }
- (int)offsetWidth { return (int)[number_of([self _run:@"return o.offsetWidth;" flags:0]) intValue]; }
- (int)offsetHeight { return (int)[number_of([self _run:@"return o.offsetHeight;" flags:0]) intValue]; }
- (DOMElement *)offsetParent
{
    return (DOMElement *)object_of([self _run:@"return o.offsetParent;" flags:0], [DOMElement class]);
}
- (int)clientLeft { return (int)[number_of([self _run:@"return o.clientLeft;" flags:0]) intValue]; }
- (int)clientTop { return (int)[number_of([self _run:@"return o.clientTop;" flags:0]) intValue]; }
- (int)clientWidth { return (int)[number_of([self _run:@"return o.clientWidth;" flags:0]) intValue]; }
- (int)clientHeight { return (int)[number_of([self _run:@"return o.clientHeight;" flags:0]) intValue]; }
- (int)scrollLeft { return (int)[number_of([self _run:@"return o.scrollLeft;" flags:0]) intValue]; }
- (void)setScrollLeft:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.scrollLeft=%d;", v] flags:WSRaise | WSGeometry];
}
- (int)scrollTop { return (int)[number_of([self _run:@"return o.scrollTop;" flags:0]) intValue]; }
- (void)setScrollTop:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.scrollTop=%d;", v] flags:WSRaise | WSGeometry];
}
- (int)scrollWidth { return (int)[number_of([self _run:@"return o.scrollWidth;" flags:0]) intValue]; }
- (int)scrollHeight { return (int)[number_of([self _run:@"return o.scrollHeight;" flags:0]) intValue]; }
- (DOMElement *)firstElementChild
{
    return (DOMElement *)object_of([self _run:@"return o.firstElementChild;" flags:0], [DOMElement class]);
}
- (DOMElement *)lastElementChild
{
    return (DOMElement *)object_of([self _run:@"return o.lastElementChild;" flags:0], [DOMElement class]);
}
- (DOMElement *)previousElementSibling
{
    return (DOMElement *)object_of([self _run:@"return o.previousElementSibling;" flags:0], [DOMElement class]);
}
- (DOMElement *)nextElementSibling
{
    return (DOMElement *)object_of([self _run:@"return o.nextElementSibling;" flags:0], [DOMElement class]);
}
- (unsigned)childElementCount
{
    return (unsigned)[number_of([self _run:@"return o.childElementCount;" flags:0]) unsignedIntValue];
}
- (NSString *)getAttribute:(NSString *)name
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.getAttribute(%@);", WSLiteral(name)]
        flags:WSRaise]);
}
- (void)setAttribute:(NSString *)name value:(NSString *)value
{
    [self _run:[NSString stringWithFormat:@"return o.setAttribute(%@,%@);", WSLiteral(name), WSLiteral(value)]
        flags:WSRaise | WSGeometry];
}
- (void)removeAttribute:(NSString *)name
{
    [self _run:[NSString stringWithFormat:@"return o.removeAttribute(%@);", WSLiteral(name)]
        flags:WSRaise | WSGeometry];
}
- (BOOL)hasAttribute:(NSString *)name
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.hasAttribute(%@);", WSLiteral(name)]
        flags:WSRaise]) boolValue];
}
- (DOMAttr *)getAttributeNode:(NSString *)name
{
    return (DOMAttr *)object_of([self _run:[NSString stringWithFormat:@"return o.getAttributeNode(%@);",
        WSLiteral(name)] flags:WSRaise], [DOMAttr class]);
}
- (NSString *)getAttributeNS:(NSString *)namespaceURI localName:(NSString *)localName
{
    return string_of([self _run:[NSString stringWithFormat:@"return o.getAttributeNS(%@,%@);", WSLiteral(namespaceURI),
        WSLiteral(localName)] flags:WSRaise]);
}
- (void)setAttributeNS:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName value:(NSString *)value
{
    [self _run:[NSString stringWithFormat:@"return o.setAttributeNS(%@,%@,%@);", WSLiteral(namespaceURI),
        WSLiteral(qualifiedName), WSLiteral(value)] flags:WSRaise | WSGeometry];
}
- (void)removeAttributeNS:(NSString *)namespaceURI localName:(NSString *)localName
{
    [self _run:[NSString stringWithFormat:@"return o.removeAttributeNS(%@,%@);", WSLiteral(namespaceURI),
        WSLiteral(localName)] flags:WSRaise | WSGeometry];
}
- (BOOL)hasAttributeNS:(NSString *)namespaceURI localName:(NSString *)localName
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.hasAttributeNS(%@,%@);",
        WSLiteral(namespaceURI), WSLiteral(localName)] flags:WSRaise]) boolValue];
}
- (DOMNodeList *)getElementsByTagName:(NSString *)name
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.getElementsByTagName(%@);", WSLiteral(name)] flags:WSRaise], [DOMNodeList class]);
}
- (DOMNodeList *)getElementsByClassName:(NSString *)name
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.getElementsByClassName(%@);", WSLiteral(name)] flags:WSRaise], [DOMNodeList class]);
}
- (DOMElement *)querySelector:(NSString *)selectors
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.querySelector(%@);",
        WSLiteral(selectors)] flags:WSRaise], [DOMElement class]);
}
- (DOMNodeList *)querySelectorAll:(NSString *)selectors
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.querySelectorAll(%@);", WSLiteral(selectors)] flags:WSRaise], [DOMNodeList class]);
}
- (BOOL)webkitMatchesSelector:(NSString *)selectors
{
    return [number_of([self _run:[NSString stringWithFormat:@"return !!o.webkitMatchesSelector(%@);",
        WSLiteral(selectors)] flags:WSRaise]) boolValue];
}
- (void)scrollIntoView:(BOOL)alignWithTop
{
    [self _run:[NSString stringWithFormat:@"return o.scrollIntoView(%@);", alignWithTop ? @"true" : @"false"]
        flags:WSRaise | WSGeometry];
}
- (void)scrollIntoViewIfNeeded:(BOOL)centerIfNeeded
{
    [self _run:[NSString stringWithFormat:@"return o.scrollIntoViewIfNeeded(%@);", centerIfNeeded ? @"true" : @"false"]
        flags:WSRaise | WSGeometry];
}
- (void)focus { [self _run:@"return o.focus();" flags:WSRaise | WSGeometry]; }
- (void)blur { [self _run:@"return o.blur();" flags:WSRaise | WSGeometry]; }
@end

@implementation DOMDocument
- (DOMDocumentType *)doctype
{
    return (DOMDocumentType *)object_of([self _run:@"return o.doctype;" flags:0], [DOMDocumentType class]);
}
- (DOMElement *)documentElement
{
    return (DOMElement *)object_of([self _run:@"return o.documentElement;" flags:0], [DOMElement class]);
}
- (NSString *)title { return string_of([self _run:@"return o.title;" flags:0]); }
- (void)setTitle:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.title=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)referrer { return string_of([self _run:@"return o.referrer;" flags:0]); }
- (NSString *)domain { return string_of([self _run:@"return o.domain;" flags:0]); }
- (NSString *)URL { return string_of([self _run:@"return o.URL;" flags:0]); }
- (NSString *)documentURI { return string_of([self _run:@"return o.documentURI;" flags:0]); }
- (NSString *)cookie { return string_of([self _run:@"return o.cookie;" flags:0]); }
- (void)setCookie:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.cookie=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMHTMLElement *)body
{
    return (DOMHTMLElement *)object_of([self _run:@"return o.body;" flags:0], [DOMHTMLElement class]);
}
- (void)setBody:(DOMHTMLElement *)v
{
    [self _run:[NSString stringWithFormat:@"o.body=%@;", WSLiteral(v)] flags:WSRaise | WSGeometry];
}
- (DOMHTMLHeadElement *)head
{
    return (DOMHTMLHeadElement *)object_of([self _run:@"return o.head;" flags:0], [DOMHTMLHeadElement class]);
}
- (DOMHTMLCollection *)images
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.images;" flags:0], [DOMHTMLCollection class]);
}
- (DOMHTMLCollection *)links
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.links;" flags:0], [DOMHTMLCollection class]);
}
- (DOMHTMLCollection *)forms
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.forms;" flags:0], [DOMHTMLCollection class]);
}
- (DOMHTMLCollection *)anchors
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.anchors;" flags:0], [DOMHTMLCollection class]);
}
- (NSString *)lastModified { return string_of([self _run:@"return o.lastModified;" flags:0]); }
- (NSString *)charset { return string_of([self _run:@"return o.charset;" flags:0]); }
- (void)setCharset:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.charset=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)characterSet { return string_of([self _run:@"return o.characterSet;" flags:0]); }
- (NSString *)inputEncoding { return string_of([self _run:@"return o.inputEncoding;" flags:0]); }
- (NSString *)readyState { return string_of([self _run:@"return o.readyState;" flags:0]); }
- (DOMElement *)activeElement
{
    return (DOMElement *)object_of([self _run:@"return o.activeElement;" flags:0], [DOMElement class]);
}
- (DOMElement *)createElement:(NSString *)tagName
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.createElement(%@);",
        WSLiteral(tagName)] flags:WSRaise], [DOMElement class]);
}
- (DOMElement *)createElementNS:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.createElementNS(%@,%@);",
        WSLiteral(namespaceURI), WSLiteral(qualifiedName)] flags:WSRaise], [DOMElement class]);
}
- (DOMDocumentFragment *)createDocumentFragment
{
    return (DOMDocumentFragment *)object_of([self _run:@"return o.createDocumentFragment();" flags:WSRaise],
        [DOMDocumentFragment class]);
}
- (DOMText *)createTextNode:(NSString *)data
{
    return (DOMText *)object_of([self _run:[NSString stringWithFormat:@"return o.createTextNode(%@);", WSLiteral(data)]
        flags:WSRaise], [DOMText class]);
}
- (DOMComment *)createComment:(NSString *)data
{
    return (DOMComment *)object_of([self _run:[NSString stringWithFormat:@"return o.createComment(%@);",
        WSLiteral(data)] flags:WSRaise], [DOMComment class]);
}
- (DOMCDATASection *)createCDATASection:(NSString *)data
{
    return (DOMCDATASection *)object_of([self _run:[NSString stringWithFormat:@"return o.createCDATASection(%@);",
        WSLiteral(data)] flags:WSRaise], [DOMCDATASection class]);
}
- (DOMAttr *)createAttribute:(NSString *)name
{
    return (DOMAttr *)object_of([self _run:[NSString stringWithFormat:@"return o.createAttribute(%@);", WSLiteral(name)]
        flags:WSRaise], [DOMAttr class]);
}
- (DOMNodeList *)getElementsByTagName:(NSString *)tagname
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.getElementsByTagName(%@);", WSLiteral(tagname)] flags:WSRaise], [DOMNodeList class]);
}
- (DOMNodeList *)getElementsByClassName:(NSString *)tagname
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.getElementsByClassName(%@);", WSLiteral(tagname)] flags:WSRaise], [DOMNodeList class]);
}
- (DOMNodeList *)getElementsByName:(NSString *)elementName
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.getElementsByName(%@);", WSLiteral(elementName)] flags:WSRaise], [DOMNodeList class]);
}
- (DOMElement *)getElementById:(NSString *)elementId
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.getElementById(%@);",
        WSLiteral(elementId)] flags:WSRaise], [DOMElement class]);
}
- (DOMElement *)querySelector:(NSString *)selectors
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.querySelector(%@);",
        WSLiteral(selectors)] flags:WSRaise], [DOMElement class]);
}
- (DOMNodeList *)querySelectorAll:(NSString *)selectors
{
    return (DOMNodeList *)object_of([self _run:[NSString stringWithFormat:@"W.force='NodeList';"
        @"return o.querySelectorAll(%@);", WSLiteral(selectors)] flags:WSRaise], [DOMNodeList class]);
}
- (DOMNode *)importNode:(DOMNode *)importedNode deep:(BOOL)deep
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.importNode(%@,%@);",
        WSLiteral(importedNode), deep ? @"true" : @"false"] flags:WSRaise], [DOMNode class]);
}
- (DOMNode *)adoptNode:(DOMNode *)source
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.adoptNode(%@);", WSLiteral(source)]
        flags:WSRaise | WSGeometry], [DOMNode class]);
}
- (DOMElement *)elementFromPoint:(int)x y:(int)y
{
    return (DOMElement *)object_of([self _run:[NSString stringWithFormat:@"return o.elementFromPoint(%d,%d);", x, y]
        flags:WSRaise], [DOMElement class]);
}
@end

@implementation DOMHTMLDocument
/* the size of its root element's content: documents have no width of their own now */
- (int)width
{
    return [number_of([self _run:@"var e=o.documentElement;return e?e.scrollWidth:0;" flags:0]) intValue];
}
- (int)height
{
    return [number_of([self _run:@"var e=o.documentElement;return e?e.scrollHeight:0;" flags:0]) intValue];
}
- (NSString *)dir { return string_of([self _run:@"return o.dir;" flags:0]); }
- (void)setDir:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.dir=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)designMode { return string_of([self _run:@"return o.designMode;" flags:0]); }
- (void)setDesignMode:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.designMode=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMHTMLCollection *)embeds
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.embeds;" flags:0], [DOMHTMLCollection class]);
}
- (DOMHTMLCollection *)scripts
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.scripts;" flags:0], [DOMHTMLCollection class]);
}
- (void)open { [self _run:@"return o.open();" flags:WSRaise | WSGeometry]; }
- (void)close { [self _run:@"return o.close();" flags:WSRaise | WSGeometry]; }
- (void)write:(NSString *)text
{
    [self _run:[NSString stringWithFormat:@"return o.write(%@);", WSLiteral(text)] flags:WSRaise | WSGeometry];
}
- (void)writeln:(NSString *)text
{
    [self _run:[NSString stringWithFormat:@"return o.writeln(%@);", WSLiteral(text)] flags:WSRaise | WSGeometry];
}
- (void)clear { [self _run:@"return o.clear();" flags:WSRaise | WSGeometry]; }
- (BOOL)hasFocus { return [number_of([self _run:@"return !!o.hasFocus();" flags:WSRaise]) boolValue]; }
@end

@implementation DOMHTMLElement
- (NSString *)idName { return string_of([self _run:@"return o.id;" flags:0]); }
- (void)setIdName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.id=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)title { return string_of([self _run:@"return o.title;" flags:0]); }
- (void)setTitle:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.title=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)lang { return string_of([self _run:@"return o.lang;" flags:0]); }
- (void)setLang:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.lang=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)dir { return string_of([self _run:@"return o.dir;" flags:0]); }
- (void)setDir:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.dir=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (int)tabIndex { return (int)[number_of([self _run:@"return o.tabIndex;" flags:0]) intValue]; }
- (void)setTabIndex:(int)v { [self _run:[NSString stringWithFormat:@"o.tabIndex=%d;", v] flags:WSRaise | WSGeometry]; }
- (NSString *)accessKey { return string_of([self _run:@"return o.accessKey;" flags:0]); }
- (void)setAccessKey:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.accessKey=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)innerHTML { return string_of([self _run:@"return o.innerHTML;" flags:0]); }
- (void)setInnerHTML:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.innerHTML=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)outerHTML { return string_of([self _run:@"return o.outerHTML;" flags:0]); }
- (void)setOuterHTML:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.outerHTML=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)innerText { return string_of([self _run:@"return o.innerText;" flags:0]); }
- (void)setInnerText:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.innerText=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)outerText { return string_of([self _run:@"return o.outerText;" flags:0]); }
- (void)setOuterText:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.outerText=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)contentEditable { return string_of([self _run:@"return o.contentEditable;" flags:0]); }
- (void)setContentEditable:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.contentEditable=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)hidden { return [number_of([self _run:@"return !!(o.hidden);" flags:0]) boolValue]; }
- (void)setHidden:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.hidden=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMHTMLCollection *)children
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.children;" flags:0], [DOMHTMLCollection class]);
}
- (void)click { [self _run:@"return o.click();" flags:WSRaise | WSGeometry]; }
@end

@implementation DOMHTMLHtmlElement
- (NSString *)version { return string_of([self _run:@"return o.version;" flags:0]); }
- (void)setVersion:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.version=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLHeadElement
- (NSString *)profile { return string_of([self _run:@"return o.profile;" flags:0]); }
- (void)setProfile:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.profile=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLTitleElement
- (NSString *)text { return string_of([self _run:@"return o.text;" flags:0]); }
- (void)setText:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.text=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLBodyElement
- (NSString *)aLink { return string_of([self _run:@"return o.aLink;" flags:0]); }
- (void)setALink:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.aLink=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)background { return string_of([self _run:@"return o.background;" flags:0]); }
- (void)setBackground:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.background=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)bgColor { return string_of([self _run:@"return o.bgColor;" flags:0]); }
- (void)setBgColor:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.bgColor=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)link { return string_of([self _run:@"return o.link;" flags:0]); }
- (void)setLink:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.link=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)text { return string_of([self _run:@"return o.text;" flags:0]); }
- (void)setText:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.text=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)vLink { return string_of([self _run:@"return o.vLink;" flags:0]); }
- (void)setVLink:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.vLink=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLDivElement
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLParagraphElement
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLHeadingElement
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLPreElement
- (int)width { return (int)[number_of([self _run:@"return o.width;" flags:0]) intValue]; }
- (void)setWidth:(int)v { [self _run:[NSString stringWithFormat:@"o.width=%d;", v] flags:WSRaise | WSGeometry]; }
- (BOOL)wrap { return [number_of([self _run:@"return !!(o.wrap);" flags:0]) boolValue]; }
- (void)setWrap:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.wrap=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLQuoteElement
- (NSString *)cite { return string_of([self _run:@"return o.cite;" flags:0]); }
- (void)setCite:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.cite=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLBRElement
- (NSString *)clear { return string_of([self _run:@"return o.clear;" flags:0]); }
- (void)setClear:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.clear=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLHRElement
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)noShade { return [number_of([self _run:@"return !!(o.noShade);" flags:0]) boolValue]; }
- (void)setNoShade:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.noShade=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)size { return string_of([self _run:@"return o.size;" flags:0]); }
- (void)setSize:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.size=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)width { return string_of([self _run:@"return o.width;" flags:0]); }
- (void)setWidth:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.width=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLUListElement
- (BOOL)compact { return [number_of([self _run:@"return !!(o.compact);" flags:0]) boolValue]; }
- (void)setCompact:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.compact=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLOListElement
- (BOOL)compact { return [number_of([self _run:@"return !!(o.compact);" flags:0]) boolValue]; }
- (void)setCompact:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.compact=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (int)start { return (int)[number_of([self _run:@"return o.start;" flags:0]) intValue]; }
- (void)setStart:(int)v { [self _run:[NSString stringWithFormat:@"o.start=%d;", v] flags:WSRaise | WSGeometry]; }
- (BOOL)reversed { return [number_of([self _run:@"return !!(o.reversed);" flags:0]) boolValue]; }
- (void)setReversed:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.reversed=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLDListElement
- (BOOL)compact { return [number_of([self _run:@"return !!(o.compact);" flags:0]) boolValue]; }
- (void)setCompact:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.compact=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLLIElement
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (int)value { return (int)[number_of([self _run:@"return o.value;" flags:0]) intValue]; }
- (void)setValue:(int)v { [self _run:[NSString stringWithFormat:@"o.value=%d;", v] flags:WSRaise | WSGeometry]; }
@end

@implementation DOMHTMLAnchorElement
- (NSURL *)absoluteLinkURL { return url_of([self _run:@"return o.href;" flags:0]); }
- (NSString *)href { return string_of([self _run:@"return o.href;" flags:0]); }
- (void)setHref:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.href=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)target { return string_of([self _run:@"return o.target;" flags:0]); }
- (void)setTarget:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.target=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)rel { return string_of([self _run:@"return o.rel;" flags:0]); }
- (void)setRel:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.rel=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)hreflang { return string_of([self _run:@"return o.hreflang;" flags:0]); }
- (void)setHreflang:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.hreflang=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)text { return string_of([self _run:@"return o.text;" flags:0]); }
- (NSString *)hashName { return string_of([self _run:@"return o.hash;" flags:0]); }
- (NSString *)host { return string_of([self _run:@"return o.host;" flags:0]); }
- (NSString *)hostname { return string_of([self _run:@"return o.hostname;" flags:0]); }
- (NSString *)pathname { return string_of([self _run:@"return o.pathname;" flags:0]); }
- (NSString *)port { return string_of([self _run:@"return o.port;" flags:0]); }
- (NSString *)protocol { return string_of([self _run:@"return o.protocol;" flags:0]); }
- (NSString *)search { return string_of([self _run:@"return o.search;" flags:0]); }
@end

@implementation DOMHTMLImageElement
- (NSURL *)absoluteImageURL { return url_of([self _run:@"return o.src;" flags:0]); }
- (NSString *)altDisplayString { return string_of([self _run:@"return o.alt;" flags:0]); }
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)alt { return string_of([self _run:@"return o.alt;" flags:0]); }
- (void)setAlt:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.alt=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)border { return string_of([self _run:@"return o.border;" flags:0]); }
- (void)setBorder:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.border=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (int)height { return (int)[number_of([self _run:@"return o.height;" flags:0]) intValue]; }
- (void)setHeight:(int)v { [self _run:[NSString stringWithFormat:@"o.height=%d;", v] flags:WSRaise | WSGeometry]; }
- (int)width { return (int)[number_of([self _run:@"return o.width;" flags:0]) intValue]; }
- (void)setWidth:(int)v { [self _run:[NSString stringWithFormat:@"o.width=%d;", v] flags:WSRaise | WSGeometry]; }
- (int)hspace { return (int)[number_of([self _run:@"return o.hspace;" flags:0]) intValue]; }
- (void)setHspace:(int)v { [self _run:[NSString stringWithFormat:@"o.hspace=%d;", v] flags:WSRaise | WSGeometry]; }
- (int)vspace { return (int)[number_of([self _run:@"return o.vspace;" flags:0]) intValue]; }
- (void)setVspace:(int)v { [self _run:[NSString stringWithFormat:@"o.vspace=%d;", v] flags:WSRaise | WSGeometry]; }
- (BOOL)isMap { return [number_of([self _run:@"return !!(o.isMap);" flags:0]) boolValue]; }
- (void)setIsMap:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.isMap=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)longDesc { return string_of([self _run:@"return o.longDesc;" flags:0]); }
- (void)setLongDesc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.longDesc=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)src { return string_of([self _run:@"return o.src;" flags:0]); }
- (void)setSrc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.src=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)useMap { return string_of([self _run:@"return o.useMap;" flags:0]); }
- (void)setUseMap:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.useMap=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)complete { return [number_of([self _run:@"return !!(o.complete);" flags:0]) boolValue]; }
- (int)naturalHeight { return (int)[number_of([self _run:@"return o.naturalHeight;" flags:0]) intValue]; }
- (int)naturalWidth { return (int)[number_of([self _run:@"return o.naturalWidth;" flags:0]) intValue]; }
- (int)x { return (int)[number_of([self _run:@"return o.x;" flags:0]) intValue]; }
- (int)y { return (int)[number_of([self _run:@"return o.y;" flags:0]) intValue]; }
@end

@implementation DOMHTMLScriptElement
- (NSString *)text { return string_of([self _run:@"return o.text;" flags:0]); }
- (void)setText:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.text=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)htmlFor { return string_of([self _run:@"return o.htmlFor;" flags:0]); }
- (void)setHtmlFor:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.htmlFor=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)event { return string_of([self _run:@"return o.event;" flags:0]); }
- (void)setEvent:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.event=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)charset { return string_of([self _run:@"return o.charset;" flags:0]); }
- (void)setCharset:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.charset=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)defer { return [number_of([self _run:@"return !!(o.defer);" flags:0]) boolValue]; }
- (void)setDefer:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.defer=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)src { return string_of([self _run:@"return o.src;" flags:0]); }
- (void)setSrc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.src=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLStyleElement
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)media { return string_of([self _run:@"return o.media;" flags:0]); }
- (void)setMedia:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.media=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLLinkElement
- (NSURL *)absoluteLinkURL { return url_of([self _run:@"return o.href;" flags:0]); }
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)charset { return string_of([self _run:@"return o.charset;" flags:0]); }
- (void)setCharset:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.charset=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)href { return string_of([self _run:@"return o.href;" flags:0]); }
- (void)setHref:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.href=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)hreflang { return string_of([self _run:@"return o.hreflang;" flags:0]); }
- (void)setHreflang:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.hreflang=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)media { return string_of([self _run:@"return o.media;" flags:0]); }
- (void)setMedia:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.media=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)rel { return string_of([self _run:@"return o.rel;" flags:0]); }
- (void)setRel:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.rel=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)rev { return string_of([self _run:@"return o.rev;" flags:0]); }
- (void)setRev:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.rev=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)target { return string_of([self _run:@"return o.target;" flags:0]); }
- (void)setTarget:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.target=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLMetaElement
- (NSString *)content { return string_of([self _run:@"return o.content;" flags:0]); }
- (void)setContent:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.content=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)httpEquiv { return string_of([self _run:@"return o.httpEquiv;" flags:0]); }
- (void)setHttpEquiv:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.httpEquiv=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)scheme { return string_of([self _run:@"return o.scheme;" flags:0]); }
- (void)setScheme:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.scheme=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLIFrameElement
- (WebFrame *)contentFrame { return content_frame(self); }
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)frameBorder { return string_of([self _run:@"return o.frameBorder;" flags:0]); }
- (void)setFrameBorder:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.frameBorder=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)height { return string_of([self _run:@"return o.height;" flags:0]); }
- (void)setHeight:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.height=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)longDesc { return string_of([self _run:@"return o.longDesc;" flags:0]); }
- (void)setLongDesc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.longDesc=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)marginHeight { return string_of([self _run:@"return o.marginHeight;" flags:0]); }
- (void)setMarginHeight:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.marginHeight=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)marginWidth { return string_of([self _run:@"return o.marginWidth;" flags:0]); }
- (void)setMarginWidth:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.marginWidth=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)scrolling { return string_of([self _run:@"return o.scrolling;" flags:0]); }
- (void)setScrolling:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.scrolling=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)src { return string_of([self _run:@"return o.src;" flags:0]); }
- (void)setSrc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.src=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)srcdoc { return string_of([self _run:@"return o.srcdoc;" flags:0]); }
- (void)setSrcdoc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.srcdoc=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)width { return string_of([self _run:@"return o.width;" flags:0]); }
- (void)setWidth:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.width=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMDocument *)contentDocument
{
    return (DOMDocument *)object_of([self _run:@"return o.contentDocument;" flags:0], [DOMDocument class]);
}
@end

@implementation DOMHTMLFrameElement
- (WebFrame *)contentFrame { return content_frame(self); }
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)src { return string_of([self _run:@"return o.src;" flags:0]); }
- (void)setSrc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.src=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)scrolling { return string_of([self _run:@"return o.scrolling;" flags:0]); }
- (void)setScrolling:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.scrolling=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)noResize { return [number_of([self _run:@"return !!(o.noResize);" flags:0]) boolValue]; }
- (void)setNoResize:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.noResize=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMDocument *)contentDocument
{
    return (DOMDocument *)object_of([self _run:@"return o.contentDocument;" flags:0], [DOMDocument class]);
}
@end

@implementation DOMHTMLFormElement
- (DOMHTMLCollection *)elements
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.elements;" flags:0], [DOMHTMLCollection class]);
}
- (int)length { return (int)[number_of([self _run:@"return o.length;" flags:0]) intValue]; }
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)acceptCharset { return string_of([self _run:@"return o.acceptCharset;" flags:0]); }
- (void)setAcceptCharset:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.acceptCharset=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)action { return string_of([self _run:@"return o.action;" flags:0]); }
- (void)setAction:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.action=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)enctype { return string_of([self _run:@"return o.enctype;" flags:0]); }
- (void)setEnctype:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.enctype=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)encoding { return string_of([self _run:@"return o.encoding;" flags:0]); }
- (void)setEncoding:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.encoding=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)method { return string_of([self _run:@"return o.method;" flags:0]); }
- (void)setMethod:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.method=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)target { return string_of([self _run:@"return o.target;" flags:0]); }
- (void)setTarget:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.target=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)noValidate { return [number_of([self _run:@"return !!(o.noValidate);" flags:0]) boolValue]; }
- (void)setNoValidate:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.noValidate=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (void)submit { [self _run:@"return o.submit();" flags:WSRaise | WSGeometry]; }
- (void)reset { [self _run:@"return o.reset();" flags:WSRaise | WSGeometry]; }
@end

@implementation DOMHTMLInputElement
- (NSString *)accept { return string_of([self _run:@"return o.accept;" flags:0]); }
- (void)setAccept:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.accept=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)alt { return string_of([self _run:@"return o.alt;" flags:0]); }
- (void)setAlt:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.alt=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)autofocus { return [number_of([self _run:@"return !!(o.autofocus);" flags:0]) boolValue]; }
- (void)setAutofocus:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.autofocus=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)defaultChecked { return [number_of([self _run:@"return !!(o.defaultChecked);" flags:0]) boolValue]; }
- (void)setDefaultChecked:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.defaultChecked=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)checked { return [number_of([self _run:@"return !!(o.checked);" flags:0]) boolValue]; }
- (void)setChecked:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.checked=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)indeterminate { return [number_of([self _run:@"return !!(o.indeterminate);" flags:0]) boolValue]; }
- (void)setIndeterminate:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.indeterminate=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMHTMLFormElement *)form
{
    return (DOMHTMLFormElement *)object_of([self _run:@"return o.form;" flags:0], [DOMHTMLFormElement class]);
}
- (int)maxLength { return (int)[number_of([self _run:@"return o.maxLength;" flags:0]) intValue]; }
- (void)setMaxLength:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.maxLength=%d;", v] flags:WSRaise | WSGeometry];
}
- (BOOL)multiple { return [number_of([self _run:@"return !!(o.multiple);" flags:0]) boolValue]; }
- (void)setMultiple:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.multiple=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)placeholder { return string_of([self _run:@"return o.placeholder;" flags:0]); }
- (void)setPlaceholder:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.placeholder=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)readOnly { return [number_of([self _run:@"return !!(o.readOnly);" flags:0]) boolValue]; }
- (void)setReadOnly:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.readOnly=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)required { return [number_of([self _run:@"return !!(o.required);" flags:0]) boolValue]; }
- (void)setRequired:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.required=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)size { return string_of([self _run:@"return o.size;" flags:0]); }
- (void)setSize:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.size=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)src { return string_of([self _run:@"return o.src;" flags:0]); }
- (void)setSrc:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.src=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)defaultValue { return string_of([self _run:@"return o.defaultValue;" flags:0]); }
- (void)setDefaultValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.defaultValue=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)value { return string_of([self _run:@"return o.value;" flags:0]); }
- (void)setValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.value=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (int)selectionStart { return (int)[number_of([self _run:@"return o.selectionStart;" flags:0]) intValue]; }
- (void)setSelectionStart:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.selectionStart=%d;", v] flags:WSRaise | WSGeometry];
}
- (int)selectionEnd { return (int)[number_of([self _run:@"return o.selectionEnd;" flags:0]) intValue]; }
- (void)setSelectionEnd:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.selectionEnd=%d;", v] flags:WSRaise | WSGeometry];
}
- (void)select { [self _run:@"return o.select();" flags:WSRaise | WSGeometry]; }
- (void)setSelectionRange:(int)start end:(int)end
{
    [self _run:[NSString stringWithFormat:@"return o.setSelectionRange(%d,%d);", start, end]
        flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLTextAreaElement
- (BOOL)autofocus { return [number_of([self _run:@"return !!(o.autofocus);" flags:0]) boolValue]; }
- (void)setAutofocus:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.autofocus=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (int)cols { return (int)[number_of([self _run:@"return o.cols;" flags:0]) intValue]; }
- (void)setCols:(int)v { [self _run:[NSString stringWithFormat:@"o.cols=%d;", v] flags:WSRaise | WSGeometry]; }
- (int)rows { return (int)[number_of([self _run:@"return o.rows;" flags:0]) intValue]; }
- (void)setRows:(int)v { [self _run:[NSString stringWithFormat:@"o.rows=%d;", v] flags:WSRaise | WSGeometry]; }
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMHTMLFormElement *)form
{
    return (DOMHTMLFormElement *)object_of([self _run:@"return o.form;" flags:0], [DOMHTMLFormElement class]);
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)placeholder { return string_of([self _run:@"return o.placeholder;" flags:0]); }
- (void)setPlaceholder:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.placeholder=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)readOnly { return [number_of([self _run:@"return !!(o.readOnly);" flags:0]) boolValue]; }
- (void)setReadOnly:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.readOnly=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)required { return [number_of([self _run:@"return !!(o.required);" flags:0]) boolValue]; }
- (void)setRequired:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.required=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (NSString *)defaultValue { return string_of([self _run:@"return o.defaultValue;" flags:0]); }
- (void)setDefaultValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.defaultValue=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)value { return string_of([self _run:@"return o.value;" flags:0]); }
- (void)setValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.value=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (int)selectionStart { return (int)[number_of([self _run:@"return o.selectionStart;" flags:0]) intValue]; }
- (void)setSelectionStart:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.selectionStart=%d;", v] flags:WSRaise | WSGeometry];
}
- (int)selectionEnd { return (int)[number_of([self _run:@"return o.selectionEnd;" flags:0]) intValue]; }
- (void)setSelectionEnd:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.selectionEnd=%d;", v] flags:WSRaise | WSGeometry];
}
- (void)select { [self _run:@"return o.select();" flags:WSRaise | WSGeometry]; }
- (void)setSelectionRange:(int)start end:(int)end
{
    [self _run:[NSString stringWithFormat:@"return o.setSelectionRange(%d,%d);", start, end]
        flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLButtonElement
- (BOOL)autofocus { return [number_of([self _run:@"return !!(o.autofocus);" flags:0]) boolValue]; }
- (void)setAutofocus:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.autofocus=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMHTMLFormElement *)form
{
    return (DOMHTMLFormElement *)object_of([self _run:@"return o.form;" flags:0], [DOMHTMLFormElement class]);
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (void)setType:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.type=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)value { return string_of([self _run:@"return o.value;" flags:0]); }
- (void)setValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.value=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLSelectElement
- (BOOL)autofocus { return [number_of([self _run:@"return !!(o.autofocus);" flags:0]) boolValue]; }
- (void)setAutofocus:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.autofocus=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMHTMLFormElement *)form
{
    return (DOMHTMLFormElement *)object_of([self _run:@"return o.form;" flags:0], [DOMHTMLFormElement class]);
}
- (BOOL)multiple { return [number_of([self _run:@"return !!(o.multiple);" flags:0]) boolValue]; }
- (void)setMultiple:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.multiple=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)name { return string_of([self _run:@"return o.name;" flags:0]); }
- (void)setName:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.name=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (int)size { return (int)[number_of([self _run:@"return o.size;" flags:0]) intValue]; }
- (void)setSize:(int)v { [self _run:[NSString stringWithFormat:@"o.size=%d;", v] flags:WSRaise | WSGeometry]; }
- (NSString *)type { return string_of([self _run:@"return o.type;" flags:0]); }
- (DOMHTMLCollection *)options
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.options;" flags:0], [DOMHTMLCollection class]);
}
- (int)length { return (int)[number_of([self _run:@"return o.length;" flags:0]) intValue]; }
- (int)selectedIndex { return (int)[number_of([self _run:@"return o.selectedIndex;" flags:0]) intValue]; }
- (void)setSelectedIndex:(int)v
{
    [self _run:[NSString stringWithFormat:@"o.selectedIndex=%d;", v] flags:WSRaise | WSGeometry];
}
- (NSString *)value { return string_of([self _run:@"return o.value;" flags:0]); }
- (void)setValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.value=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMNode *)item:(unsigned)index
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.item(%u);", index] flags:WSRaise],
        [DOMNode class]);
}
- (DOMNode *)namedItem:(NSString *)name
{
    return (DOMNode *)object_of([self _run:[NSString stringWithFormat:@"return o.namedItem(%@);", WSLiteral(name)]
        flags:WSRaise], [DOMNode class]);
}
- (void)remove:(int)index
{
    [self _run:[NSString stringWithFormat:@"return o.remove(%d);", index] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLOptionElement
- (BOOL)disabled { return [number_of([self _run:@"return !!(o.disabled);" flags:0]) boolValue]; }
- (void)setDisabled:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.disabled=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (DOMHTMLFormElement *)form
{
    return (DOMHTMLFormElement *)object_of([self _run:@"return o.form;" flags:0], [DOMHTMLFormElement class]);
}
- (NSString *)label { return string_of([self _run:@"return o.label;" flags:0]); }
- (void)setLabel:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.label=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (BOOL)defaultSelected { return [number_of([self _run:@"return !!(o.defaultSelected);" flags:0]) boolValue]; }
- (void)setDefaultSelected:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.defaultSelected=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (BOOL)selected { return [number_of([self _run:@"return !!(o.selected);" flags:0]) boolValue]; }
- (void)setSelected:(BOOL)v
{
    [self _run:[NSString stringWithFormat:@"o.selected=%@;", v ? @"true" : @"false"] flags:WSRaise | WSGeometry];
}
- (NSString *)value { return string_of([self _run:@"return o.value;" flags:0]); }
- (void)setValue:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.value=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)text { return string_of([self _run:@"return o.text;" flags:0]); }
- (int)index { return (int)[number_of([self _run:@"return o.index;" flags:0]) intValue]; }
@end

@implementation DOMHTMLTableElement
- (DOMHTMLCollection *)rows
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.rows;" flags:0], [DOMHTMLCollection class]);
}
- (DOMHTMLCollection *)tBodies
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.tBodies;" flags:0], [DOMHTMLCollection class]);
}
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)border { return string_of([self _run:@"return o.border;" flags:0]); }
- (void)setBorder:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.border=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)cellPadding { return string_of([self _run:@"return o.cellPadding;" flags:0]); }
- (void)setCellPadding:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.cellPadding=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)cellSpacing { return string_of([self _run:@"return o.cellSpacing;" flags:0]); }
- (void)setCellSpacing:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.cellSpacing=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)summary { return string_of([self _run:@"return o.summary;" flags:0]); }
- (void)setSummary:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.summary=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)width { return string_of([self _run:@"return o.width;" flags:0]); }
- (void)setWidth:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.width=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMHTMLElement *)insertRow:(int)index
{
    return (DOMHTMLElement *)object_of([self _run:[NSString stringWithFormat:@"return o.insertRow(%d);", index]
        flags:WSRaise | WSGeometry], [DOMHTMLElement class]);
}
- (void)deleteRow:(int)index
{
    [self _run:[NSString stringWithFormat:@"return o.deleteRow(%d);", index] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLTableSectionElement
- (DOMHTMLCollection *)rows
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.rows;" flags:0], [DOMHTMLCollection class]);
}
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMHTMLElement *)insertRow:(int)index
{
    return (DOMHTMLElement *)object_of([self _run:[NSString stringWithFormat:@"return o.insertRow(%d);", index]
        flags:WSRaise | WSGeometry], [DOMHTMLElement class]);
}
- (void)deleteRow:(int)index
{
    [self _run:[NSString stringWithFormat:@"return o.deleteRow(%d);", index] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLTableRowElement
- (int)rowIndex { return (int)[number_of([self _run:@"return o.rowIndex;" flags:0]) intValue]; }
- (int)sectionRowIndex { return (int)[number_of([self _run:@"return o.sectionRowIndex;" flags:0]) intValue]; }
- (DOMHTMLCollection *)cells
{
    return (DOMHTMLCollection *)object_of([self _run:@"return o.cells;" flags:0], [DOMHTMLCollection class]);
}
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (DOMHTMLElement *)insertCell:(int)index
{
    return (DOMHTMLElement *)object_of([self _run:[NSString stringWithFormat:@"return o.insertCell(%d);", index]
        flags:WSRaise | WSGeometry], [DOMHTMLElement class]);
}
- (void)deleteCell:(int)index
{
    [self _run:[NSString stringWithFormat:@"return o.deleteCell(%d);", index] flags:WSRaise | WSGeometry];
}
@end

@implementation DOMHTMLTableCellElement
- (int)cellIndex { return (int)[number_of([self _run:@"return o.cellIndex;" flags:0]) intValue]; }
- (int)colSpan { return (int)[number_of([self _run:@"return o.colSpan;" flags:0]) intValue]; }
- (void)setColSpan:(int)v { [self _run:[NSString stringWithFormat:@"o.colSpan=%d;", v] flags:WSRaise | WSGeometry]; }
- (int)rowSpan { return (int)[number_of([self _run:@"return o.rowSpan;" flags:0]) intValue]; }
- (void)setRowSpan:(int)v { [self _run:[NSString stringWithFormat:@"o.rowSpan=%d;", v] flags:WSRaise | WSGeometry]; }
- (NSString *)align { return string_of([self _run:@"return o.align;" flags:0]); }
- (void)setAlign:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.align=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)headers { return string_of([self _run:@"return o.headers;" flags:0]); }
- (void)setHeaders:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.headers=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
- (NSString *)scope { return string_of([self _run:@"return o.scope;" flags:0]); }
- (void)setScope:(NSString *)v
{
    [self _run:[NSString stringWithFormat:@"o.scope=%@;", WKQuote(v ?: @"")] flags:WSRaise | WSGeometry];
}
@end

