/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's WebKit: the older WebKit's Objective-C DOM (DOMDocument, DOMNode,
 * DOMElement, DOMHTMLElement and the others), written from Apple's public
 * documentation (freemac 1.217, Ferry 0.42.0). Imported by WebKit.h.
 *
 * A DOM object is a WebScriptObject, as on a Mac: it stands for a node or a
 * list of the page and reads and changes it at once. Ferry reaches the page
 * through scripts, since this system's WebKitGTK gives a program no DOM of
 * its own, so each property read or set and each call is one script, run
 * in the page and waited for. */
#ifndef _FERRY_WEBKIT_DOM_H_
#define _FERRY_WEBKIT_DOM_H_
#import <WebKit/WebView.h>

@class DOMDocument, DOMElement, DOMHTMLElement, DOMHTMLCollection, DOMNodeList, DOMNamedNodeMap, DOMAttr,
    DOMCSSStyleDeclaration, DOMDocumentFragment, DOMText, DOMComment, DOMCDATASection, DOMDocumentType,
    DOMHTMLFormElement, DOMHTMLHeadElement;

/* the name of the exceptions DOM calls raise, with the page's message as the reason */
WEBKIT_EXTERN NSString *const DOMException;

enum {
    DOM_ELEMENT_NODE = 1,
    DOM_ATTRIBUTE_NODE = 2,
    DOM_TEXT_NODE = 3,
    DOM_CDATA_SECTION_NODE = 4,
    DOM_ENTITY_REFERENCE_NODE = 5,
    DOM_ENTITY_NODE = 6,
    DOM_PROCESSING_INSTRUCTION_NODE = 7,
    DOM_COMMENT_NODE = 8,
    DOM_DOCUMENT_NODE = 9,
    DOM_DOCUMENT_TYPE_NODE = 10,
    DOM_DOCUMENT_FRAGMENT_NODE = 11,
    DOM_NOTATION_NODE = 12,
};
enum {
    DOM_DOCUMENT_POSITION_DISCONNECTED = 0x01,
    DOM_DOCUMENT_POSITION_PRECEDING = 0x02,
    DOM_DOCUMENT_POSITION_FOLLOWING = 0x04,
    DOM_DOCUMENT_POSITION_CONTAINS = 0x08,
    DOM_DOCUMENT_POSITION_CONTAINED_BY = 0x10,
    DOM_DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC = 0x20,
};

@interface DOMObject : WebScriptObject <NSCopying>
@end

/* ---- lists ------------------------------------------------------------------------- */

@interface DOMNodeList : DOMObject
@property (readonly) unsigned length;
- (id)item:(unsigned)index;
@end

@interface DOMHTMLCollection : DOMObject
@property (readonly) unsigned length;
- (id)item:(unsigned)index;
- (id)namedItem:(NSString *)name;
- (DOMNodeList *)tags:(NSString *)name;
@end

@interface DOMNamedNodeMap : DOMObject
@property (readonly) unsigned length;
- (id)item:(unsigned)index;
- (id)getNamedItem:(NSString *)name;
- (id)setNamedItem:(id)node;
- (id)removeNamedItem:(NSString *)name;
@end

@interface DOMCSSStyleDeclaration : DOMObject
@property (copy) NSString *cssText;
@property (readonly) unsigned length;
- (NSString *)item:(unsigned)index;
- (NSString *)getPropertyValue:(NSString *)propertyName;
- (NSString *)getPropertyPriority:(NSString *)propertyName;
- (NSString *)removeProperty:(NSString *)propertyName;
- (void)setProperty:(NSString *)propertyName value:(NSString *)value priority:(NSString *)priority;
@end

/* ---- nodes ------------------------------------------------------------------------- */

@interface DOMNode : DOMObject
@property (readonly, copy) NSString *nodeName;
@property (copy) NSString *nodeValue;
@property (readonly) unsigned short nodeType;
@property (readonly, retain) DOMNode *parentNode;
@property (readonly, retain) DOMElement *parentElement;
@property (readonly, retain) DOMNodeList *childNodes;
@property (readonly, retain) DOMNode *firstChild;
@property (readonly, retain) DOMNode *lastChild;
@property (readonly, retain) DOMNode *previousSibling;
@property (readonly, retain) DOMNode *nextSibling;
@property (readonly, retain) DOMDocument *ownerDocument;
@property (readonly, copy) NSString *namespaceURI;
@property (copy) NSString *prefix;
@property (readonly, copy) NSString *localName;
@property (readonly, retain) DOMNamedNodeMap *attributes;
@property (readonly, copy) NSString *baseURI;
@property (copy) NSString *textContent;
@property (readonly) BOOL isContentEditable;
- (DOMNode *)insertBefore:(DOMNode *)newChild refChild:(DOMNode *)refChild;
- (DOMNode *)replaceChild:(DOMNode *)newChild oldChild:(DOMNode *)oldChild;
- (DOMNode *)removeChild:(DOMNode *)oldChild;
- (DOMNode *)appendChild:(DOMNode *)newChild;
- (BOOL)hasChildNodes;
- (DOMNode *)cloneNode:(BOOL)deep;
- (void)normalize;
- (BOOL)isSupported:(NSString *)feature version:(NSString *)version;
- (BOOL)hasAttributes;
- (BOOL)isSameNode:(DOMNode *)other;
- (BOOL)isEqualNode:(DOMNode *)other;
- (NSString *)lookupPrefix:(NSString *)namespaceURI;
- (NSString *)lookupNamespaceURI:(NSString *)prefix;
- (BOOL)isDefaultNamespace:(NSString *)namespaceURI;
- (unsigned short)compareDocumentPosition:(DOMNode *)other;
- (BOOL)contains:(DOMNode *)other;
@end

@interface DOMAttr : DOMNode
@property (readonly, copy) NSString *name;
@property (readonly) BOOL specified;
@property (copy) NSString *value;
@property (readonly, retain) DOMElement *ownerElement;
@end

@interface DOMCharacterData : DOMNode
@property (copy) NSString *data;
@property (readonly) unsigned length;
- (NSString *)substringData:(unsigned)offset length:(unsigned)length;
- (void)appendData:(NSString *)data;
- (void)insertData:(unsigned)offset data:(NSString *)data;
- (void)deleteData:(unsigned)offset length:(unsigned)length;
- (void)replaceData:(unsigned)offset length:(unsigned)length data:(NSString *)data;
@end

@interface DOMText : DOMCharacterData
@property (readonly, copy) NSString *wholeText;
- (DOMText *)splitText:(unsigned)offset;
@end
@interface DOMComment : DOMCharacterData
@end
@interface DOMCDATASection : DOMText
@end
@interface DOMProcessingInstruction : DOMCharacterData
@property (readonly, copy) NSString *target;
@end

@interface DOMDocumentType : DOMNode
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *publicId;
@property (readonly, copy) NSString *systemId;
@end

@interface DOMDocumentFragment : DOMNode
- (DOMElement *)getElementById:(NSString *)elementId;
- (DOMElement *)querySelector:(NSString *)selectors;
- (DOMNodeList *)querySelectorAll:(NSString *)selectors;
@end

@interface DOMElement : DOMNode
@property (readonly, copy) NSString *tagName;
@property (copy) NSString *className;
@property (readonly, retain) DOMCSSStyleDeclaration *style;
@property (readonly) int offsetLeft;
@property (readonly) int offsetTop;
@property (readonly) int offsetWidth;
@property (readonly) int offsetHeight;
@property (readonly, retain) DOMElement *offsetParent;
@property (readonly) int clientLeft;
@property (readonly) int clientTop;
@property (readonly) int clientWidth;
@property (readonly) int clientHeight;
@property int scrollLeft;
@property int scrollTop;
@property (readonly) int scrollWidth;
@property (readonly) int scrollHeight;
@property (readonly, retain) DOMElement *firstElementChild;
@property (readonly, retain) DOMElement *lastElementChild;
@property (readonly, retain) DOMElement *previousElementSibling;
@property (readonly, retain) DOMElement *nextElementSibling;
@property (readonly) unsigned childElementCount;
- (NSString *)getAttribute:(NSString *)name;
- (void)setAttribute:(NSString *)name value:(NSString *)value;
- (void)removeAttribute:(NSString *)name;
- (BOOL)hasAttribute:(NSString *)name;
- (DOMAttr *)getAttributeNode:(NSString *)name;
- (NSString *)getAttributeNS:(NSString *)namespaceURI localName:(NSString *)localName;
- (void)setAttributeNS:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName value:(NSString *)value;
- (void)removeAttributeNS:(NSString *)namespaceURI localName:(NSString *)localName;
- (BOOL)hasAttributeNS:(NSString *)namespaceURI localName:(NSString *)localName;
- (DOMNodeList *)getElementsByTagName:(NSString *)name;
- (DOMNodeList *)getElementsByClassName:(NSString *)name;
- (DOMElement *)querySelector:(NSString *)selectors;
- (DOMNodeList *)querySelectorAll:(NSString *)selectors;
- (BOOL)webkitMatchesSelector:(NSString *)selectors;
- (void)scrollIntoView:(BOOL)alignWithTop;
- (void)scrollIntoViewIfNeeded:(BOOL)centerIfNeeded;
- (void)focus;
- (void)blur;
@end

@interface DOMDocument : DOMNode
@property (readonly, retain) DOMDocumentType *doctype;
@property (readonly, retain) DOMElement *documentElement;
@property (copy) NSString *title;
@property (readonly, copy) NSString *referrer;
@property (readonly, copy) NSString *domain;
@property (readonly, copy) NSString *URL;
@property (readonly, copy) NSString *documentURI;
@property (copy) NSString *cookie;
@property (retain) DOMHTMLElement *body;
@property (readonly, retain) DOMHTMLHeadElement *head;
@property (readonly, retain) DOMHTMLCollection *images;
@property (readonly, retain) DOMHTMLCollection *links;
@property (readonly, retain) DOMHTMLCollection *forms;
@property (readonly, retain) DOMHTMLCollection *anchors;
@property (readonly, copy) NSString *lastModified;
@property (copy) NSString *charset;
@property (readonly, copy) NSString *characterSet;
@property (readonly, copy) NSString *inputEncoding;
@property (readonly, copy) NSString *readyState;
@property (readonly, retain) DOMElement *activeElement;
- (DOMElement *)createElement:(NSString *)tagName;
- (DOMElement *)createElementNS:(NSString *)namespaceURI qualifiedName:(NSString *)qualifiedName;
- (DOMDocumentFragment *)createDocumentFragment;
- (DOMText *)createTextNode:(NSString *)data;
- (DOMComment *)createComment:(NSString *)data;
- (DOMCDATASection *)createCDATASection:(NSString *)data;
- (DOMAttr *)createAttribute:(NSString *)name;
- (DOMNodeList *)getElementsByTagName:(NSString *)tagname;
- (DOMNodeList *)getElementsByClassName:(NSString *)tagname;
- (DOMNodeList *)getElementsByName:(NSString *)elementName;
- (DOMElement *)getElementById:(NSString *)elementId;
- (DOMElement *)querySelector:(NSString *)selectors;
- (DOMNodeList *)querySelectorAll:(NSString *)selectors;
- (DOMNode *)importNode:(DOMNode *)importedNode deep:(BOOL)deep;
- (DOMNode *)adoptNode:(DOMNode *)source;
- (DOMElement *)elementFromPoint:(int)x y:(int)y;
@end

/* ---- HTML -------------------------------------------------------------------------- */

@interface DOMHTMLDocument : DOMDocument
@property (readonly) int width;
@property (readonly) int height;
@property (copy) NSString *dir;
@property (copy) NSString *designMode;
@property (readonly, retain) DOMHTMLCollection *embeds;
@property (readonly, retain) DOMHTMLCollection *scripts;
- (void)open;
- (void)close;
- (void)write:(NSString *)text;
- (void)writeln:(NSString *)text;
- (void)clear;
- (BOOL)hasFocus;
@end

@interface DOMHTMLElement : DOMElement
@property (copy) NSString *idName;   /* the id attribute */
@property (copy) NSString *title;
@property (copy) NSString *lang;
@property (copy) NSString *dir;
@property int tabIndex;
@property (copy) NSString *accessKey;
@property (copy) NSString *innerHTML;
@property (copy) NSString *outerHTML;
@property (copy) NSString *innerText;
@property (copy) NSString *outerText;
@property (copy) NSString *contentEditable;
@property BOOL hidden;
@property (readonly, retain) DOMHTMLCollection *children;
- (void)click;
@end

@interface DOMHTMLHtmlElement : DOMHTMLElement
@property (copy) NSString *version;
@end
@interface DOMHTMLHeadElement : DOMHTMLElement
@property (copy) NSString *profile;
@end
@interface DOMHTMLTitleElement : DOMHTMLElement
@property (copy) NSString *text;
@end
@interface DOMHTMLBodyElement : DOMHTMLElement
@property (copy) NSString *aLink;
@property (copy) NSString *background;
@property (copy) NSString *bgColor;
@property (copy) NSString *link;
@property (copy) NSString *text;
@property (copy) NSString *vLink;
@end
@interface DOMHTMLDivElement : DOMHTMLElement
@property (copy) NSString *align;
@end
@interface DOMHTMLParagraphElement : DOMHTMLElement
@property (copy) NSString *align;
@end
@interface DOMHTMLHeadingElement : DOMHTMLElement
@property (copy) NSString *align;
@end
@interface DOMHTMLPreElement : DOMHTMLElement
@property int width;
@property BOOL wrap;
@end
@interface DOMHTMLQuoteElement : DOMHTMLElement
@property (copy) NSString *cite;
@end
@interface DOMHTMLBRElement : DOMHTMLElement
@property (copy) NSString *clear;
@end
@interface DOMHTMLHRElement : DOMHTMLElement
@property (copy) NSString *align;
@property BOOL noShade;
@property (copy) NSString *size;
@property (copy) NSString *width;
@end
@interface DOMHTMLUListElement : DOMHTMLElement
@property BOOL compact;
@property (copy) NSString *type;
@end
@interface DOMHTMLOListElement : DOMHTMLElement
@property BOOL compact;
@property int start;
@property BOOL reversed;
@property (copy) NSString *type;
@end
@interface DOMHTMLDListElement : DOMHTMLElement
@property BOOL compact;
@end
@interface DOMHTMLLIElement : DOMHTMLElement
@property (copy) NSString *type;
@property int value;
@end
@interface DOMHTMLAnchorElement : DOMHTMLElement
@property (copy) NSString *href;
@property (copy) NSString *target;
@property (copy) NSString *name;
@property (copy) NSString *rel;
@property (copy) NSString *type;
@property (copy) NSString *hreflang;
@property (readonly, copy) NSString *text;
@property (readonly, copy) NSString *hashName;
@property (readonly, copy) NSString *host;
@property (readonly, copy) NSString *hostname;
@property (readonly, copy) NSString *pathname;
@property (readonly, copy) NSString *port;
@property (readonly, copy) NSString *protocol;
@property (readonly, copy) NSString *search;
@property (readonly, copy) NSURL *absoluteLinkURL;
@end
@interface DOMHTMLImageElement : DOMHTMLElement
@property (copy) NSString *name;
@property (copy) NSString *align;
@property (copy) NSString *alt;
@property (copy) NSString *border;
@property int height;
@property int width;
@property int hspace;
@property int vspace;
@property BOOL isMap;
@property (copy) NSString *longDesc;
@property (copy) NSString *src;
@property (copy) NSString *useMap;
@property (readonly) BOOL complete;
@property (readonly) int naturalHeight;
@property (readonly) int naturalWidth;
@property (readonly) int x;
@property (readonly) int y;
@property (readonly, copy) NSString *altDisplayString;
@property (readonly, copy) NSURL *absoluteImageURL;
@end
@interface DOMHTMLScriptElement : DOMHTMLElement
@property (copy) NSString *text;
@property (copy) NSString *htmlFor;
@property (copy) NSString *event;
@property (copy) NSString *charset;
@property BOOL defer;
@property (copy) NSString *src;
@property (copy) NSString *type;
@end
@interface DOMHTMLStyleElement : DOMHTMLElement
@property BOOL disabled;
@property (copy) NSString *media;
@property (copy) NSString *type;
@end
@interface DOMHTMLLinkElement : DOMHTMLElement
@property BOOL disabled;
@property (copy) NSString *charset;
@property (copy) NSString *href;
@property (copy) NSString *hreflang;
@property (copy) NSString *media;
@property (copy) NSString *rel;
@property (copy) NSString *rev;
@property (copy) NSString *target;
@property (copy) NSString *type;
@property (readonly, copy) NSURL *absoluteLinkURL;
@end
@interface DOMHTMLMetaElement : DOMHTMLElement
@property (copy) NSString *content;
@property (copy) NSString *httpEquiv;
@property (copy) NSString *name;
@property (copy) NSString *scheme;
@end
@interface DOMHTMLIFrameElement : DOMHTMLElement
@property (copy) NSString *align;
@property (copy) NSString *frameBorder;
@property (copy) NSString *height;
@property (copy) NSString *longDesc;
@property (copy) NSString *marginHeight;
@property (copy) NSString *marginWidth;
@property (copy) NSString *name;
@property (copy) NSString *scrolling;
@property (copy) NSString *src;
@property (copy) NSString *srcdoc;
@property (copy) NSString *width;
@property (readonly, retain) DOMDocument *contentDocument;
@property (readonly) WebFrame *contentFrame;
@end
@interface DOMHTMLFrameElement : DOMHTMLElement
@property (copy) NSString *name;
@property (copy) NSString *src;
@property (copy) NSString *scrolling;
@property BOOL noResize;
@property (readonly, retain) DOMDocument *contentDocument;
@property (readonly) WebFrame *contentFrame;
@end
@interface DOMHTMLFormElement : DOMHTMLElement
@property (readonly, retain) DOMHTMLCollection *elements;
@property (readonly) int length;
@property (copy) NSString *name;
@property (copy) NSString *acceptCharset;
@property (copy) NSString *action;
@property (copy) NSString *enctype;
@property (copy) NSString *encoding;
@property (copy) NSString *method;
@property (copy) NSString *target;
@property BOOL noValidate;
- (void)submit;
- (void)reset;
@end
@interface DOMHTMLInputElement : DOMHTMLElement
@property (copy) NSString *accept;
@property (copy) NSString *alt;
@property BOOL autofocus;
@property BOOL defaultChecked;
@property BOOL checked;
@property BOOL disabled;
@property BOOL indeterminate;
@property (readonly, retain) DOMHTMLFormElement *form;
@property int maxLength;
@property BOOL multiple;
@property (copy) NSString *name;
@property (copy) NSString *placeholder;
@property BOOL readOnly;
@property BOOL required;
@property (copy) NSString *size;
@property (copy) NSString *src;
@property (copy) NSString *type;
@property (copy) NSString *defaultValue;
@property (copy) NSString *value;
@property int selectionStart;
@property int selectionEnd;
- (void)select;
- (void)setSelectionRange:(int)start end:(int)end;
@end
@interface DOMHTMLTextAreaElement : DOMHTMLElement
@property BOOL autofocus;
@property int cols;
@property int rows;
@property BOOL disabled;
@property (readonly, retain) DOMHTMLFormElement *form;
@property (copy) NSString *name;
@property (copy) NSString *placeholder;
@property BOOL readOnly;
@property BOOL required;
@property (readonly, copy) NSString *type;
@property (copy) NSString *defaultValue;
@property (copy) NSString *value;
@property int selectionStart;
@property int selectionEnd;
- (void)select;
- (void)setSelectionRange:(int)start end:(int)end;
@end
@interface DOMHTMLButtonElement : DOMHTMLElement
@property BOOL autofocus;
@property BOOL disabled;
@property (readonly, retain) DOMHTMLFormElement *form;
@property (copy) NSString *name;
@property (copy) NSString *type;
@property (copy) NSString *value;
@end
@interface DOMHTMLSelectElement : DOMHTMLElement
@property BOOL autofocus;
@property BOOL disabled;
@property (readonly, retain) DOMHTMLFormElement *form;
@property BOOL multiple;
@property (copy) NSString *name;
@property int size;
@property (readonly, copy) NSString *type;
@property (readonly, retain) DOMHTMLCollection *options;
@property (readonly) int length;
@property int selectedIndex;
@property (copy) NSString *value;
- (DOMNode *)item:(unsigned)index;
- (DOMNode *)namedItem:(NSString *)name;
- (void)remove:(int)index;
@end
@interface DOMHTMLOptionElement : DOMHTMLElement
@property BOOL disabled;
@property (readonly, retain) DOMHTMLFormElement *form;
@property (copy) NSString *label;
@property BOOL defaultSelected;
@property BOOL selected;
@property (copy) NSString *value;
@property (readonly, copy) NSString *text;
@property (readonly) int index;
@end
@interface DOMHTMLTableElement : DOMHTMLElement
@property (readonly, retain) DOMHTMLCollection *rows;
@property (readonly, retain) DOMHTMLCollection *tBodies;
@property (copy) NSString *align;
@property (copy) NSString *border;
@property (copy) NSString *cellPadding;
@property (copy) NSString *cellSpacing;
@property (copy) NSString *summary;
@property (copy) NSString *width;
- (DOMHTMLElement *)insertRow:(int)index;
- (void)deleteRow:(int)index;
@end
@interface DOMHTMLTableSectionElement : DOMHTMLElement
@property (readonly, retain) DOMHTMLCollection *rows;
@property (copy) NSString *align;
- (DOMHTMLElement *)insertRow:(int)index;
- (void)deleteRow:(int)index;
@end
@interface DOMHTMLTableRowElement : DOMHTMLElement
@property (readonly) int rowIndex;
@property (readonly) int sectionRowIndex;
@property (readonly, retain) DOMHTMLCollection *cells;
@property (copy) NSString *align;
- (DOMHTMLElement *)insertCell:(int)index;
- (void)deleteCell:(int)index;
@end
@interface DOMHTMLTableCellElement : DOMHTMLElement
@property (readonly) int cellIndex;
@property int colSpan;
@property int rowSpan;
@property (copy) NSString *align;
@property (copy) NSString *headers;
@property (copy) NSString *scope;
@end

#endif
