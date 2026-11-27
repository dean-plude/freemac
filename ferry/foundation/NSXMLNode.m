/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSXMLNode, NSXMLElement, NSXMLDocument, NSXMLDTD and
 * NSXMLDTDNode, an XML document as a tree of objects that can be read,
 * changed, searched with XPath and written out again.
 *
 * The tree is made of Objective-C objects, and they are the document: every
 * change made through the API is what XMLString, stringValue and XPath see.
 * libxml2 (this system's copy, the library a Mac program linking libxml2
 * gets, see src/host.c) does the parts a Mac's NSXMLDocument also leaves to
 * it, reached through ferry_twin_symbol only when first needed:
 *
 *  - parsing: libxml2 reads the document into its own tree, which is copied
 *    into objects and freed;
 *  - XPath and canonical XML: a copy of the object tree is made in libxml2's
 *    tree form (kept until the next change anywhere), each libxml2 node
 *    pointing back to its object through its _private field, and the nodes
 *    libxml2 finds are answered as those objects.
 *
 * Writing XML out (XMLString, XMLData, pretty printing) is Ferry's own.
 *
 * Written from Apple's public documentation of NSXMLNode, NSXMLElement,
 * NSXMLDocument, NSXMLDTD and NSXMLDTDNode, and libxml2's of its tree,
 * parser, XPath and C14N interfaces; no Apple code was used. */
#import "FInternal.h"
#include <errno.h>
#include <math.h>

void *ferry_twin_symbol(const char *install_name, const char *name);

/* ---- libxml2's structures, as its documentation gives them (the fields used here) ---- */

typedef unsigned char xmlChar;
struct xDoc;
typedef struct xNs {
    struct xNs *next;
    int type;
    const xmlChar *href, *prefix;
    void *_private;
    struct xDoc *context;
} xNs;
#define X_COMMON                                                                                                       \
    void *_private;                                                                                                    \
    int type;                                                                                                          \
    const xmlChar *name;                                                                                               \
    struct xNode *children, *last;                                                                                     \
    void *parent;                                                                                                      \
    struct xNode *next, *prev;                                                                                         \
    struct xDoc *doc;
typedef struct xNode {
    X_COMMON
    xNs *ns;
    xmlChar *content;
    struct xAttr *properties;
    xNs *nsDef;
} xNode;
typedef struct xAttr {
    X_COMMON
    xNs *ns;
} xAttr;
typedef struct xDtd {
    X_COMMON
    void *notations, *elements, *attributes, *entities;
    const xmlChar *ExternalID, *SystemID;
} xDtd;
typedef struct xDoc {
    X_COMMON
    int compression, standalone;
    xDtd *intSubset, *extSubset;
    xNs *oldNs;
    const xmlChar *version, *encoding;
} xDoc;
typedef struct {
    X_COMMON
    xmlChar *orig, *content;
    int length, etype;
    const xmlChar *ExternalID, *SystemID;
} xEntity;
typedef struct {
    X_COMMON
    void *nexth;
    int atype, def;
    const xmlChar *defaultValue;
    void *tree;
    const xmlChar *prefix, *elem;
} xAttrDecl;
typedef struct {
    X_COMMON
    int etype;
} xElemDecl;
typedef struct {
    int nodeNr, nodeMax;
    xNode **nodeTab;
} xNodeSet;
typedef struct {
    int type;
    xNodeSet *nodesetval;
} xXPathObject;
typedef struct {
    int domain, code;
    char *message;
    int level;
    char *file;
    int line;
    char *str1, *str2, *str3;
    int int1, int2;
    void *ctxt, *node;
} xError;

enum {
    X_ELEMENT = 1, X_ATTRIBUTE = 2, X_TEXT = 3, X_CDATA = 4, X_ENTITY_REF = 5, X_PI = 7, X_COMMENT = 8,
    X_DOCUMENT = 9, X_DTD = 14, X_ELEMENT_DECL = 15, X_ATTRIBUTE_DECL = 16, X_ENTITY_DECL = 17, X_NAMESPACE = 18,
};
#define XML_PARSE_RECOVER (1 << 0)
#define XML_PARSE_NOENT (1 << 1)
#define XML_PARSE_DTDLOAD (1 << 2)
#define XML_PARSE_DTDATTR (1 << 3)
#define XML_PARSE_DTDVALID (1 << 4)
#define XML_PARSE_XINCLUDE (1 << 10)
#define XML_PARSE_NONET (1 << 11)
#define XML_PARSE_NOXINCNODE (1 << 15)
#define XML_PARSE_IGNORE_ENC (1 << 21)
#define XML_PARSE_BIG_LINES (1 << 22)
#define XML_FROM_DTD 4
#define XML_FROM_VALID 23
#define XML_ERR_ERROR 2

typedef void (*generic_error_fn)(void *, const char *, ...);
typedef void (*structured_error_fn)(void *, xError *);
typedef int (*visible_fn)(void *, xNode *, xNode *);

static struct {
    BOOL tried, ok;
    void (*initParser)(void);
    xDoc *(*readMemory)(const char *, int, const char *, const char *, int);
    void (*freeDoc)(xDoc *);
    xDoc *(*newDoc)(const xmlChar *);
    xNode *(*newDocNode)(xDoc *, xNs *, const xmlChar *, const xmlChar *);
    xNs *(*newNs)(xNode *, const xmlChar *, const xmlChar *);
    xAttr *(*newNsProp)(xNode *, xNs *, const xmlChar *, const xmlChar *);
    xNode *(*newDocText)(xDoc *, const xmlChar *);
    xNode *(*newCDataBlock)(xDoc *, const xmlChar *, int);
    xNode *(*newDocComment)(xDoc *, const xmlChar *);
    xNode *(*newDocPI)(xDoc *, const xmlChar *, const xmlChar *);
    xNs *(*searchNs)(xDoc *, xNode *, const xmlChar *);
    xmlChar *(*nodeGetContent)(const xNode *);
    void **xmlFree;
    void *(*bufferCreate)(void);
    void (*bufferFree)(void *);
    const xmlChar *(*bufferContent)(const void *);
    int (*nodeDump)(void *, xDoc *, xNode *, int, int);
    void *(*xpathNewContext)(xDoc *);
    void (*xpathFreeContext)(void *);
    int (*xpathRegisterNs)(void *, const xmlChar *, const xmlChar *);
    xXPathObject *(*xpathNodeEval)(xNode *, const xmlChar *, void *);
    void (*xpathFreeObject)(xXPathObject *);
    int (*c14nDocDumpMemory)(xDoc *, void *, int, xmlChar **, int, xmlChar **);
    int (*c14nExecute)(xDoc *, visible_fn, void *, int, xmlChar **, int, void *);
    void *(*allocOutputBuffer)(void *);
    const xmlChar *(*outputBufferGetContent)(void *);
    size_t (*outputBufferGetSize)(void *);
    int (*outputBufferClose)(void *);
    generic_error_fn *(*genericError)(void);
    void **(*genericErrorContext)(void);
    structured_error_fn *(*structuredError)(void);
    void **(*structuredErrorContext)(void);
    void (*setStructuredErrorFunc)(void *, structured_error_fn);
} lx;

static BOOL load_libxml2(void)
{
    if (lx.tried)
        return lx.ok;
    lx.tried = YES;
    const char *lib = "/usr/lib/libxml2.2.dylib";
#define LOAD(field, name) *(void **)&lx.field = ferry_twin_symbol(lib, name)
    LOAD(initParser, "xmlInitParser");
    LOAD(readMemory, "xmlReadMemory");
    LOAD(freeDoc, "xmlFreeDoc");
    LOAD(newDoc, "xmlNewDoc");
    LOAD(newDocNode, "xmlNewDocNode");
    LOAD(newNs, "xmlNewNs");
    LOAD(newNsProp, "xmlNewNsProp");
    LOAD(newDocText, "xmlNewDocText");
    LOAD(newCDataBlock, "xmlNewCDataBlock");
    LOAD(newDocComment, "xmlNewDocComment");
    LOAD(newDocPI, "xmlNewDocPI");
    LOAD(searchNs, "xmlSearchNs");
    LOAD(nodeGetContent, "xmlNodeGetContent");
    LOAD(xmlFree, "xmlFree");
    LOAD(bufferCreate, "xmlBufferCreate");
    LOAD(bufferFree, "xmlBufferFree");
    LOAD(bufferContent, "xmlBufferContent");
    LOAD(nodeDump, "xmlNodeDump");
    LOAD(xpathNewContext, "xmlXPathNewContext");
    LOAD(xpathFreeContext, "xmlXPathFreeContext");
    LOAD(xpathRegisterNs, "xmlXPathRegisterNs");
    LOAD(xpathNodeEval, "xmlXPathNodeEval");
    LOAD(xpathFreeObject, "xmlXPathFreeObject");
    LOAD(c14nDocDumpMemory, "xmlC14NDocDumpMemory");
    LOAD(c14nExecute, "xmlC14NExecute");
    LOAD(allocOutputBuffer, "xmlAllocOutputBuffer");
    LOAD(outputBufferGetContent, "xmlOutputBufferGetContent");
    LOAD(outputBufferGetSize, "xmlOutputBufferGetSize");
    LOAD(outputBufferClose, "xmlOutputBufferClose");
    LOAD(genericError, "__xmlGenericError");
    LOAD(genericErrorContext, "__xmlGenericErrorContext");
    LOAD(structuredError, "__xmlStructuredError");
    LOAD(structuredErrorContext, "__xmlStructuredErrorContext");
    LOAD(setStructuredErrorFunc, "xmlSetStructuredErrorFunc");
#undef LOAD
    lx.ok = lx.initParser && lx.readMemory && lx.freeDoc && lx.newDoc && lx.newDocNode && lx.newNs && lx.newNsProp &&
            lx.newDocText && lx.newCDataBlock && lx.newDocComment && lx.newDocPI && lx.searchNs &&
            lx.nodeGetContent && lx.xmlFree && *lx.xmlFree && lx.bufferCreate && lx.bufferFree && lx.bufferContent &&
            lx.nodeDump && lx.xpathNewContext && lx.xpathFreeContext && lx.xpathRegisterNs && lx.xpathNodeEval &&
            lx.xpathFreeObject && lx.genericError && lx.genericErrorContext && lx.structuredError &&
            lx.structuredErrorContext && lx.setStructuredErrorFunc;
    if (lx.ok)
        lx.initParser();
    return lx.ok;
}

static void x_free(void *p)
{
    if (p)
        ((void (*)(void *)) * lx.xmlFree)(p);
}

/* libxml2's messages: the first error is kept, nothing reaches the terminal. */
static struct {
    BOOL have, validity;
    int code, line, column;
    char message[512];
} first_error;
static generic_error_fn saved_generic;
static void *saved_generic_ctx;
static structured_error_fn saved_structured;
static void *saved_structured_ctx;

static void quiet(void *ctx, const char *msg, ...) {}
static void keep_error(void *ctx, xError *e)
{
    if (!e || e->level < XML_ERR_ERROR)
        return;
    if (e->domain == XML_FROM_VALID || e->domain == XML_FROM_DTD)
        first_error.validity = YES;
    if (first_error.have)
        return;
    first_error.have = YES;
    first_error.code = e->code;
    first_error.line = e->line;
    first_error.column = e->int2;
    snprintf(first_error.message, sizeof first_error.message, "%s", e->message ? e->message : "");
}
static void quiet_begin(void)
{
    memset(&first_error, 0, sizeof first_error);
    saved_generic = *lx.genericError();
    saved_generic_ctx = *lx.genericErrorContext();
    saved_structured = *lx.structuredError();
    saved_structured_ctx = *lx.structuredErrorContext();
    *lx.genericError() = quiet;
    lx.setStructuredErrorFunc(NULL, keep_error);
}
static void quiet_end(void)
{
    *lx.genericError() = saved_generic;
    *lx.genericErrorContext() = saved_generic_ctx;
    lx.setStructuredErrorFunc(saved_structured_ctx, saved_structured);
}

static NSError *kept_error(int fallback_code, NSString *fallback)
{
    NSString *message = first_error.have ? [NSString stringWithUTF8String:first_error.message] : fallback;
    message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *desc = first_error.have && first_error.line > 0
                         ? [NSString stringWithFormat:@"Line %d: %@", first_error.line, message]
                         : message;
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:desc, NSLocalizedDescriptionKey,
                                                                    [NSNumber numberWithInt:first_error.line],
                                                                    @"NSXMLParserErrorLineNumber",
                                                                    [NSNumber numberWithInt:first_error.column],
                                                                    @"NSXMLParserErrorColumn", message,
                                                                    @"NSXMLParserErrorMessage", nil];
    return [NSError errorWithDomain:NSXMLParserErrorDomain
                               code:first_error.have ? first_error.code : fallback_code
                           userInfo:info];
}

static NSError *unavailable(void)
{
    return [NSError
        errorWithDomain:NSXMLParserErrorDomain
                   code:NSXMLParserInternalError
               userInfo:[NSDictionary dictionaryWithObject:@"libxml2 (libxml2.so.2) isn't installed on this system"
                                                    forKey:NSLocalizedDescriptionKey]];
}

static NSString *str(const xmlChar *s) { return s ? [NSString stringWithUTF8String:(const char *)s] : nil; }
static const xmlChar *u8(NSString *s) { return (const xmlChar *)(s ? [s UTF8String] : ""); }

/* ---- the object tree ---- */

/* Bumped by every change to any tree: a libxml2 copy made before is stale. */
static unsigned long xml_generation = 1;
#define CHANGED() (xml_generation++)

struct shadow {
    xDoc *doc;
    unsigned long generation;
    NSMutableDictionary *nodes;    /* object (pointer) -> its libxml2 node (pointer) */
    NSMutableDictionary *prefixes; /* every prefix declared in the tree -> its URI */
};
static void shadow_free(struct shadow *s)
{
    if (!s)
        return;
    if (s->doc)
        lx.freeDoc(s->doc);
    [s->nodes release];
    [s->prefixes release];
    free(s);
}

@interface NSXMLNode () {
@public
    NSXMLNodeKind _kind;
    NSXMLNodeOptions _options;
    NSString *_name;
    id _value;
    NSString *_URI;
    NSXMLNode *_parent; /* not retained */
    NSMutableArray *_children;
    struct shadow *_shadow;
}
- (void)_copyInto:(NSXMLNode *)copy;
@end

@interface NSXMLElement () {
@public
    NSMutableArray *_attributes, *_namespaces;
}
@end

@interface NSXMLDocument () {
@public
    NSString *_version, *_encoding, *_MIMEType;
    BOOL _standalone;
    NSXMLDocumentContentKind _contentKind;
    NSXMLDTD *_DTD;
}
@end

@interface NSXMLDTD () {
@public
    NSString *_publicID, *_systemID;
}
@end

@interface NSXMLDTDNode () {
@public
    NSXMLDTDNodeKind _DTDKind;
    NSString *_publicID, *_systemID, *_notationName, *_elementName;
    NSString *_xml; /* the declaration as read, until it is changed */
}
@end

static void adopt_at(NSXMLNode *parent, NSXMLNode *child, NSUInteger index);

static NSString *object_string(id v)
{
    if (!v)
        return nil;
    if ([v isKindOfClass:[NSString class]])
        return v;
    if ([v isKindOfClass:[NSNumber class]]) {
        const char *t = [v objCType];
        if (t && (!strcmp(t, "c") || !strcmp(t, "B")) && ([v intValue] == 0 || [v intValue] == 1))
            return [v boolValue] ? @"true" : @"false";
        return [v stringValue];
    }
    if ([v isKindOfClass:[NSDate class]]) { /* xs:dateTime, in UTC */
        time_t t = (time_t)floor([v timeIntervalSince1970]);
        struct tm tm;
        gmtime_r(&t, &tm);
        return [NSString stringWithFormat:@"%04d-%02d-%02dT%02d:%02d:%02dZ", tm.tm_year + 1900, tm.tm_mon + 1,
                                          tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec];
    }
    if ([v isKindOfClass:[NSData class]]) { /* xs:hexBinary */
        const unsigned char *b = [v bytes];
        NSMutableString *s = [NSMutableString stringWithCapacity:[v length] * 2];
        for (NSUInteger i = 0; i < [v length]; i++)
            [s appendFormat:@"%02X", b[i]];
        return s;
    }
    if ([v isKindOfClass:[NSURL class]])
        return [v absoluteString];
    return [v description];
}

static BOOL is_blank(NSString *s)
{
    NSUInteger n = [s length];
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [s characterAtIndex:i];
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r')
            return NO;
    }
    return YES;
}

/* &amp; &lt; &gt; &quot; &apos; and character references */
static NSString *resolve_entities(NSString *s)
{
    if ([s rangeOfString:@"&"].location == NSNotFound)
        return s;
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = [s length], i = 0;
    while (i < n) {
        unichar c = [s characterAtIndex:i];
        if (c == '&') {
            NSRange semi = [s rangeOfString:@";" options:0 range:NSMakeRange(i, n - i)];
            if (semi.location != NSNotFound && semi.location - i <= 10) {
                NSString *ent = [s substringWithRange:NSMakeRange(i + 1, semi.location - i - 1)];
                NSString *rep = nil;
                if ([ent isEqualToString:@"amp"])
                    rep = @"&";
                else if ([ent isEqualToString:@"lt"])
                    rep = @"<";
                else if ([ent isEqualToString:@"gt"])
                    rep = @">";
                else if ([ent isEqualToString:@"quot"])
                    rep = @"\"";
                else if ([ent isEqualToString:@"apos"])
                    rep = @"'";
                else if ([ent hasPrefix:@"#"] && [ent length] > 1) {
                    const char *d = [ent UTF8String] + 1;
                    unsigned long cp = (*d == 'x' || *d == 'X') ? strtoul(d + 1, NULL, 16) : strtoul(d, NULL, 10);
                    if (cp > 0 && cp <= 0x10FFFF) {
                        if (cp > 0xFFFF) {
                            unichar pair[2] = {(unichar)(0xD800 + ((cp - 0x10000) >> 10)),
                                               (unichar)(0xDC00 + ((cp - 0x10000) & 0x3FF))};
                            rep = [NSString stringWithCharacters:pair length:2];
                        } else {
                            unichar one = (unichar)cp;
                            rep = [NSString stringWithCharacters:&one length:1];
                        }
                    }
                }
                if (rep) {
                    [out appendString:rep];
                    i = semi.location + 1;
                    continue;
                }
            }
        }
        [out appendString:[s substringWithRange:NSMakeRange(i, 1)]];
        i++;
    }
    return out;
}

static void text_of(NSXMLNode *n, NSMutableString *out)
{
    for (NSXMLNode *c in n->_children) {
        if (c->_kind == NSXMLTextKind) {
            NSString *s = object_string(c->_value);
            if (s)
                [out appendString:s];
        } else if (c->_kind == NSXMLElementKind)
            text_of(c, out);
    }
}

static NSXMLNode *top_of(NSXMLNode *n)
{
    while (n->_parent)
        n = n->_parent;
    return n;
}

static NSString *xpath_step(NSXMLNode *n)
{
    NSXMLNode *p = n->_parent;
    switch (n->_kind) {
    case NSXMLAttributeKind:
        return [@"@" stringByAppendingString:n->_name ?: @""];
    case NSXMLNamespaceKind:
        return [@"namespace::" stringByAppendingString:n->_name ?: @""];
    default:
        break;
    }
    NSString *test = n->_kind == NSXMLElementKind                 ? (n->_name ?: @"")
                     : n->_kind == NSXMLTextKind                  ? @"text()"
                     : n->_kind == NSXMLCommentKind               ? @"comment()"
                     : n->_kind == NSXMLProcessingInstructionKind ? @"processing-instruction()"
                                                                  : @"node()";
    NSUInteger pos = 1;
    for (NSXMLNode *s in p ? p->_children : nil) {
        if (s == n)
            break;
        if (s->_kind == n->_kind && (n->_kind != NSXMLElementKind || [s->_name isEqualToString:n->_name]))
            pos++;
    }
    return [NSString stringWithFormat:@"%@[%lu]", test, (unsigned long)pos];
}

/* ---- writing XML ---- */

typedef struct {
    char *p;
    size_t n, cap;
    unsigned maxch; /* characters above this are written as references (an encoding that lacks them) */
} Out;

static void put(Out *o, const char *s, size_t n)
{
    if (o->n + n + 1 > o->cap) {
        o->cap = (o->n + n + 1) * 2 + 64;
        o->p = realloc(o->p, o->cap);
    }
    memcpy(o->p + o->n, s, n);
    o->n += n;
    o->p[o->n] = 0;
}
static void putc_(Out *o, char c) { put(o, &c, 1); }
static void puts_(Out *o, const char *s) { put(o, s, strlen(s)); }
static void put_ns(Out *o, NSString *s)
{
    if (s)
        puts_(o, [s UTF8String]);
}
static void put_indent(Out *o, int level)
{
    for (int i = 0; i < level; i++)
        put(o, "    ", 4);
}

/* Text (attr 0) or an attribute's value (quote is its quote character) */
static void put_escaped(Out *o, NSString *s, int attr, char quote)
{
    if (!s)
        return;
    const unsigned char *p = (const unsigned char *)[s UTF8String];
    while (*p) {
        unsigned c = *p;
        if (c == '&')
            puts_(o, "&amp;");
        else if (c == '<')
            puts_(o, "&lt;");
        else if (c == '>')
            puts_(o, "&gt;");
        else if (c == '\r')
            puts_(o, "&#13;");
        else if (attr && c == '"' && quote == '"')
            puts_(o, "&quot;");
        else if (attr && c == '\'' && quote == '\'')
            puts_(o, "&apos;");
        else if (attr && c == '\n')
            puts_(o, "&#10;");
        else if (attr && c == '\t')
            puts_(o, "&#9;");
        else if (c >= 0x80 && o->maxch < 0x10FFFF) {
            int len = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : c >= 0xC0 ? 2 : 1;
            unsigned cp = len == 4 ? c & 7 : len == 3 ? c & 15 : len == 2 ? c & 31 : c;
            for (int i = 1; i < len && p[i]; i++)
                cp = (cp << 6) | (p[i] & 63);
            if (cp > o->maxch) {
                char ref[16];
                snprintf(ref, sizeof ref, "&#x%X;", cp);
                puts_(o, ref);
            } else
                put(o, (const char *)p, len);
            p += len;
            continue;
        } else
            putc_(o, (char)c);
        p++;
    }
}

static void write_node(Out *o, NSXMLNode *n, NSXMLNodeOptions opts, int level);

static NSString *dtd_node_xml(NSXMLDTDNode *d);

static void write_dtd(Out *o, NSXMLDTD *d, NSXMLNodeOptions opts)
{
    puts_(o, "<!DOCTYPE ");
    put_ns(o, d->_name);
    if (d->_publicID) {
        puts_(o, " PUBLIC \"");
        put_ns(o, d->_publicID);
        puts_(o, "\" \"");
        put_ns(o, d->_systemID);
        putc_(o, '"');
    } else if (d->_systemID) {
        puts_(o, " SYSTEM \"");
        put_ns(o, d->_systemID);
        putc_(o, '"');
    }
    if ([d->_children count]) {
        puts_(o, " [");
        for (NSXMLNode *c in d->_children) {
            putc_(o, '\n');
            write_node(o, c, opts, 0);
        }
        puts_(o, "\n]");
    }
    putc_(o, '>');
}

static BOOL compact_empty(NSXMLNode *n, NSXMLNodeOptions opts)
{
    NSXMLNodeOptions e = opts & NSXMLNodePreserveEmptyElements;
    if (e == NSXMLNodeCompactEmptyElement)
        return YES;
    if (e == NSXMLNodeExpandEmptyElement)
        return NO;
    return (n->_options & NSXMLNodePreserveEmptyElements) == NSXMLNodeCompactEmptyElement;
}

static void write_element(Out *o, NSXMLElement *e, NSXMLNodeOptions opts, int level)
{
    putc_(o, '<');
    put_ns(o, e->_name);
    for (NSXMLNode *ns in e->_namespaces) {
        putc_(o, ' ');
        write_node(o, ns, opts, level);
    }
    for (NSXMLNode *a in e->_attributes) {
        putc_(o, ' ');
        write_node(o, a, opts, level);
    }
    if (![e->_children count]) {
        if (compact_empty(e, opts))
            puts_(o, "/>");
        else {
            puts_(o, "></");
            put_ns(o, e->_name);
            putc_(o, '>');
        }
        return;
    }
    putc_(o, '>');
    BOOL block = (opts & NSXMLNodePrettyPrint) != 0;
    for (NSXMLNode *c in e->_children)
        if (c->_kind == NSXMLTextKind)
            block = NO;
    if (block) {
        for (NSXMLNode *c in e->_children) {
            putc_(o, '\n');
            put_indent(o, level + 1);
            write_node(o, c, opts, level + 1);
        }
        putc_(o, '\n');
        put_indent(o, level);
    } else {
        for (NSXMLNode *c in e->_children)
            write_node(o, c, opts & ~NSXMLNodePrettyPrint, level + 1);
    }
    puts_(o, "</");
    put_ns(o, e->_name);
    putc_(o, '>');
}

static void write_document(Out *o, NSXMLDocument *d, NSXMLNodeOptions opts)
{
    BOOL pretty = (opts & NSXMLNodePrettyPrint) != 0, any = NO;
    if (d->_version || d->_encoding || d->_standalone) {
        puts_(o, "<?xml version=\"");
        put_ns(o, d->_version ?: @"1.0");
        putc_(o, '"');
        if (d->_encoding) {
            puts_(o, " encoding=\"");
            put_ns(o, d->_encoding);
            putc_(o, '"');
        }
        if (d->_standalone)
            puts_(o, " standalone=\"yes\"");
        puts_(o, "?>");
        any = YES;
    }
    if (d->_DTD) {
        if (pretty && any)
            putc_(o, '\n');
        write_dtd(o, d->_DTD, opts);
        any = YES;
    }
    for (NSXMLNode *c in d->_children) {
        if (pretty && any)
            putc_(o, '\n');
        write_node(o, c, opts, 0);
        any = YES;
    }
}

static void write_node(Out *o, NSXMLNode *n, NSXMLNodeOptions opts, int level)
{
    NSXMLNodeOptions all = opts | n->_options;
    char quote = (all & NSXMLNodePreserveQuotes) == NSXMLNodeUseSingleQuotes ? '\'' : '"';
    switch (n->_kind) {
    case NSXMLDocumentKind:
        write_document(o, (NSXMLDocument *)n, opts);
        break;
    case NSXMLElementKind:
        write_element(o, (NSXMLElement *)n, opts, level);
        break;
    case NSXMLAttributeKind:
        put_ns(o, n->_name);
        putc_(o, '=');
        putc_(o, quote);
        if (all & NSXMLNodeNeverEscapeContents)
            put_ns(o, object_string(n->_value));
        else
            put_escaped(o, object_string(n->_value), 1, quote);
        putc_(o, quote);
        break;
    case NSXMLNamespaceKind:
        puts_(o, "xmlns");
        if ([n->_name length]) {
            putc_(o, ':');
            put_ns(o, n->_name);
        }
        putc_(o, '=');
        putc_(o, quote);
        put_escaped(o, object_string(n->_value), 1, quote);
        putc_(o, quote);
        break;
    case NSXMLProcessingInstructionKind: {
        NSString *v = object_string(n->_value);
        puts_(o, "<?");
        put_ns(o, n->_name);
        if ([v length]) {
            putc_(o, ' ');
            put_ns(o, v);
        }
        puts_(o, "?>");
        break;
    }
    case NSXMLCommentKind:
        puts_(o, "<!--");
        put_ns(o, object_string(n->_value));
        puts_(o, "-->");
        break;
    case NSXMLTextKind: {
        NSString *v = object_string(n->_value);
        if (n->_options & NSXMLNodeIsCDATA) {
            puts_(o, "<![CDATA[");
            put_ns(o, [v stringByReplacingOccurrencesOfString:@"]]>" withString:@"]]]]><![CDATA[>"]);
            puts_(o, "]]>");
        } else if (all & NSXMLNodeNeverEscapeContents)
            put_ns(o, v);
        else
            put_escaped(o, v, 0, 0);
        break;
    }
    case NSXMLDTDKind:
        write_dtd(o, (NSXMLDTD *)n, opts);
        break;
    case NSXMLEntityDeclarationKind:
    case NSXMLAttributeDeclarationKind:
    case NSXMLElementDeclarationKind:
    case NSXMLNotationDeclarationKind:
        put_ns(o, dtd_node_xml((NSXMLDTDNode *)n));
        break;
    default:
        break;
    }
}

static NSString *xml_string(NSXMLNode *n, NSXMLNodeOptions opts, unsigned maxch)
{
    Out o = {NULL, 0, 0, maxch};
    put(&o, "", 0);
    write_node(&o, n, opts, 0);
    NSString *s = [NSString stringWithUTF8String:o.p];
    free(o.p);
    return s;
}

/* ---- libxml2's copy of a tree, for XPath and canonical XML ---- */

static NSValue *ptr(const void *p) { return [NSValue valueWithPointer:p]; }

static void link_child(xNode *parent, xNode *c)
{
    c->parent = parent;
    c->next = NULL;
    c->prev = parent->last;
    if (parent->last)
        parent->last->next = c;
    else
        parent->children = c;
    parent->last = c;
}

static const xmlChar *or_null(NSString *s) { return [s length] ? u8(s) : NULL; }

static void build(NSXMLNode *n, xDoc *doc, xNode *parent, struct shadow *sh)
{
    xNode *x = NULL;
    NSString *value = object_string(n->_value);
    switch (n->_kind) {
    case NSXMLElementKind: {
        NSXMLElement *e = (NSXMLElement *)n;
        x = lx.newDocNode(doc, NULL, u8([NSXMLNode localNameForName:e->_name]), NULL);
        if (!x)
            return;
        link_child(parent, x);
        for (NSXMLNode *ns in e->_namespaces) {
            NSString *uri = object_string(ns->_value) ?: @"";
            xNs *d = lx.newNs(x, u8(uri), or_null(ns->_name));
            if (d)
                d->_private = ns;
            if ([ns->_name length] && ![sh->prefixes objectForKey:ns->_name])
                [sh->prefixes setObject:uri forKey:ns->_name];
        }
        NSString *pre = [NSXMLNode prefixForName:e->_name];
        xNs *ns = lx.searchNs(doc, x, or_null(pre));
        if (e->_URI && (!ns || strcmp((const char *)ns->href, [e->_URI UTF8String]))) {
            xNs *d = lx.newNs(x, u8(e->_URI), or_null(pre));
            if (d)
                ns = d;
            if ([pre length] && ![sh->prefixes objectForKey:pre])
                [sh->prefixes setObject:e->_URI forKey:pre];
        }
        x->ns = ns;
        for (NSXMLNode *a in e->_attributes) {
            NSString *apre = [NSXMLNode prefixForName:a->_name];
            xNs *ans = NULL;
            if ([apre length] && ![apre isEqualToString:@"xmlns"]) {
                ans = lx.searchNs(doc, x, u8(apre));
                if (a->_URI && (!ans || strcmp((const char *)ans->href, [a->_URI UTF8String]))) {
                    xNs *d = lx.newNs(x, u8(a->_URI), u8(apre));
                    if (d)
                        ans = d;
                    if (![sh->prefixes objectForKey:apre])
                        [sh->prefixes setObject:a->_URI forKey:apre];
                }
            }
            xAttr *xa = lx.newNsProp(x, ans, ans ? u8([NSXMLNode localNameForName:a->_name]) : u8(a->_name),
                                     u8(object_string(a->_value)));
            if (xa) {
                xa->_private = a;
                [sh->nodes setObject:ptr(xa) forKey:ptr(a)];
            }
        }
        break;
    }
    case NSXMLTextKind:
        x = (n->_options & NSXMLNodeIsCDATA) ? lx.newCDataBlock(doc, u8(value), (int)strlen((const char *)u8(value)))
                                             : lx.newDocText(doc, u8(value));
        break;
    case NSXMLCommentKind:
        x = lx.newDocComment(doc, u8(value));
        break;
    case NSXMLProcessingInstructionKind:
        x = lx.newDocPI(doc, u8(n->_name), or_null(value));
        break;
    default:
        return;
    }
    if (!x)
        return;
    if (!x->parent)
        link_child(parent, x);
    x->_private = n;
    [sh->nodes setObject:ptr(x) forKey:ptr(n)];
    for (NSXMLNode *c in n->_children)
        build(c, doc, x, sh);
}

static struct shadow *shadow_of(NSXMLNode *node)
{
    if (!load_libxml2())
        return NULL;
    NSXMLNode *top = top_of(node);
    if (top->_shadow && top->_shadow->generation == xml_generation)
        return top->_shadow;
    shadow_free(top->_shadow);
    struct shadow *sh = calloc(1, sizeof *sh);
    sh->generation = xml_generation;
    sh->nodes = [[NSMutableDictionary alloc] init];
    sh->prefixes = [[NSMutableDictionary alloc] init];
    sh->doc = lx.newDoc((const xmlChar *)"1.0");
    top->_shadow = sh;
    if (!sh->doc)
        return sh;
    if (top->_kind == NSXMLDocumentKind) {
        sh->doc->_private = top;
        [sh->nodes setObject:ptr(sh->doc) forKey:ptr(top)];
        for (NSXMLNode *c in top->_children)
            build(c, sh->doc, (xNode *)sh->doc, sh);
    } else
        build(top, sh->doc, (xNode *)sh->doc, sh);
    return sh;
}

static xNode *shadow_node(struct shadow *sh, NSXMLNode *n) { return [[sh->nodes objectForKey:ptr(n)] pointerValue]; }

/* ---- reading libxml2's tree into objects ---- */

typedef struct {
    NSXMLNodeOptions options;
    Class element, node, dtd, dtdNode;
} Conv;

static void append_child(NSXMLNode *parent, NSXMLNode *child)
{
    if (!parent->_children)
        parent->_children = [[NSMutableArray alloc] init];
    [parent->_children addObject:child];
    child->_parent = parent;
}

static void append_text(NSXMLNode *parent, NSString *s, BOOL cdata, Conv *cv)
{
    NSXMLNode *last = [parent->_children lastObject];
    if (!cdata && last && last->_kind == NSXMLTextKind && !(last->_options & NSXMLNodeIsCDATA)) {
        NSString *joined = [object_string(last->_value) stringByAppendingString:s];
        [last->_value release];
        last->_value = [joined copy];
        return;
    }
    NSXMLNode *t = [[cv->node alloc] initWithKind:NSXMLTextKind options:cdata ? NSXMLNodeIsCDATA : 0];
    t->_value = [s copy];
    append_child(parent, t);
    [t release];
}

static NSString *qualified(xNs *ns, const xmlChar *local)
{
    if (ns && ns->prefix)
        return [NSString stringWithFormat:@"%s:%s", ns->prefix, local];
    return str(local) ?: @"";
}

static void convert_list(xNode *x, NSXMLNode *parent, Conv *cv);

static NSXMLElement *convert_element(xNode *x, Conv *cv)
{
    NSXMLElement *e = [[cv->element alloc] initWithName:qualified(x->ns, x->name)
                                                    URI:x->ns && x->ns->href ? str(x->ns->href) : nil];
    for (xNs *d = x->nsDef; d; d = d->next) {
        NSXMLNode *ns = [[cv->node alloc] initWithKind:NSXMLNamespaceKind options:0];
        ns->_name = [(str(d->prefix) ?: @"") copy];
        ns->_value = [(str(d->href) ?: @"") copy];
        if (!e->_namespaces)
            e->_namespaces = [[NSMutableArray alloc] init];
        [e->_namespaces addObject:ns];
        ns->_parent = e;
        [ns release];
    }
    for (xAttr *a = x->properties; a; a = (xAttr *)a->next) {
        NSXMLNode *attr = [[cv->node alloc] initWithKind:NSXMLAttributeKind options:0];
        attr->_name = [qualified(a->ns, a->name) copy];
        if (a->ns && a->ns->href)
            attr->_URI = [str(a->ns->href) copy];
        xmlChar *v = lx.nodeGetContent((xNode *)a);
        attr->_value = [(str(v) ?: @"") copy];
        x_free(v);
        if (!e->_attributes)
            e->_attributes = [[NSMutableArray alloc] init];
        [e->_attributes addObject:attr];
        attr->_parent = e;
        [attr release];
    }
    convert_list(x->children, e, cv);
    if (!(cv->options & NSXMLNodePreserveWhitespace)) {
        BOOL mixed = NO;
        for (NSXMLNode *c in e->_children)
            if (c->_kind != NSXMLTextKind)
                mixed = YES;
        if (mixed)
            for (NSInteger i = (NSInteger)[e->_children count] - 1; i >= 0; i--) {
                NSXMLNode *c = [e->_children objectAtIndex:i];
                if (c->_kind == NSXMLTextKind && !(c->_options & NSXMLNodeIsCDATA) && is_blank(c->_value)) {
                    c->_parent = nil;
                    [e->_children removeObjectAtIndex:i];
                }
            }
    }
    return e;
}

static void convert_node(xNode *x, NSXMLNode *parent, Conv *cv)
{
    {
        switch (x->type) {
        case X_ELEMENT: {
            NSXMLElement *e = convert_element(x, cv);
            append_child(parent, e);
            [e release];
            break;
        }
        case X_TEXT:
            if (parent->_kind == NSXMLElementKind)
                append_text(parent, str(x->content) ?: @"", NO, cv);
            break;
        case X_CDATA:
            if (parent->_kind == NSXMLElementKind)
                append_text(parent, str(x->content) ?: @"", (cv->options & NSXMLNodePreserveCDATA) != 0, cv);
            break;
        case X_ENTITY_REF: /* the entity's content, as if it were written out */
            if (x->children && x->children->type == X_ENTITY_DECL)
                convert_list(x->children->children, parent, cv);
            break;
        case X_PI:
        case X_COMMENT: {
            NSXMLNode *n = [[cv->node alloc]
                initWithKind:x->type == X_PI ? NSXMLProcessingInstructionKind : NSXMLCommentKind
                     options:0];
            if (x->type == X_PI)
                n->_name = [(str(x->name) ?: @"") copy];
            n->_value = [(str(x->content) ?: @"") copy];
            append_child(parent, n);
            [n release];
            break;
        }
        default:
            break;
        }
    }
}

static void convert_list(xNode *x, NSXMLNode *parent, Conv *cv)
{
    for (; x; x = x->next)
        convert_node(x, parent, cv);
}

static NSXMLDTDNode *convert_decl(xNode *x, Conv *cv)
{
    NSXMLNodeKind kind = x->type == X_ENTITY_DECL      ? NSXMLEntityDeclarationKind
                         : x->type == X_ELEMENT_DECL   ? NSXMLElementDeclarationKind
                         : x->type == X_ATTRIBUTE_DECL ? NSXMLAttributeDeclarationKind
                                                       : NSXMLInvalidKind;
    if (kind == NSXMLInvalidKind)
        return nil;
    NSXMLDTDNode *d = [[cv->dtdNode alloc] initWithKind:kind options:0];
    d->_name = [(str(x->name) ?: @"") copy];
    void *buf = lx.bufferCreate();
    if (buf) {
        lx.nodeDump(buf, x->doc, x, 0, 0);
        NSString *xml = str(lx.bufferContent(buf));
        d->_xml = [[xml stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
        lx.bufferFree(buf);
    }
    if (x->type == X_ENTITY_DECL) {
        xEntity *ent = (xEntity *)x;
        static const NSXMLDTDNodeKind kinds[] = {0, NSXMLEntityGeneralKind, NSXMLEntityParsedKind,
                                                 NSXMLEntityUnparsedKind, NSXMLEntityParameterKind,
                                                 NSXMLEntityParameterKind, NSXMLEntityPredefined};
        d->_DTDKind = ent->etype >= 1 && ent->etype <= 6 ? kinds[ent->etype] : NSXMLEntityGeneralKind;
        d->_publicID = [str(ent->ExternalID) copy];
        d->_systemID = [str(ent->SystemID) copy];
        if (ent->etype == 3) /* unparsed: the content is the notation's name */
            d->_notationName = [str(ent->content) copy];
        else
            d->_value = [(str(ent->content) ?: @"") copy];
    } else {
        /* the rest of the declaration after its name: the content model or the attribute's type and default */
        NSString *xml = d->_xml ?: @"";
        NSString *lead = x->type == X_ELEMENT_DECL
                             ? [NSString stringWithFormat:@"<!ELEMENT %@ ", d->_name]
                             : [NSString stringWithFormat:@"<!ATTLIST %s %@ ", ((xAttrDecl *)x)->elem, d->_name];
        if ([xml hasPrefix:lead] && [xml hasSuffix:@">"])
            d->_value = [[xml substringWithRange:NSMakeRange([lead length], [xml length] - [lead length] - 1)] copy];
        if (x->type == X_ELEMENT_DECL) {
            int t = ((xElemDecl *)x)->etype;
            d->_DTDKind = NSXMLElementDeclarationUndefinedKind + (t >= 0 && t <= 4 ? t : 0);
        } else {
            xAttrDecl *ad = (xAttrDecl *)x;
            d->_DTDKind = NSXMLAttributeCDATAKind + (ad->atype >= 1 && ad->atype <= 10 ? ad->atype - 1 : 0);
            d->_elementName = [str(ad->elem) copy];
        }
    }
    return d;
}

static NSXMLDTD *convert_dtd(xDtd *x, Conv *cv)
{
    NSXMLDTD *dtd = [[cv->dtd alloc] init];
    dtd->_name = [str(x->name) copy];
    dtd->_publicID = [str(x->ExternalID) copy];
    dtd->_systemID = [str(x->SystemID) copy];
    for (xNode *c = x->children; c; c = c->next) {
        if (c->type == X_COMMENT || c->type == X_PI) {
            convert_node(c, dtd, cv);
            continue;
        }
        NSXMLDTDNode *d = convert_decl(c, cv);
        if (d) {
            append_child(dtd, d);
            [d release];
        }
    }
    return dtd;
}

/* Parses bytes with libxml2; NULL (and *error) when they aren't a document. */
static xDoc *parse_bytes(const char *bytes, NSUInteger len, NSString *url, const char *encoding,
                         NSXMLNodeOptions mask, NSError **error)
{
    if (!load_libxml2()) {
        FSetError(error, unavailable());
        return NULL;
    }
    if (!len) {
        memset(&first_error, 0, sizeof first_error);
        FSetError(error, kept_error(NSXMLParserEmptyDocumentError, @"Document is empty"));
        return NULL;
    }
    int options = XML_PARSE_NONET | XML_PARSE_BIG_LINES;
    if (mask & NSXMLDocumentTidyXML)
        options |= XML_PARSE_RECOVER;
    if (mask & NSXMLNodeLoadExternalEntitiesAlways) /* from files only: XML_PARSE_NONET stays */
        options |= XML_PARSE_NOENT | XML_PARSE_DTDLOAD | XML_PARSE_DTDATTR;
    if (mask & NSXMLDocumentValidate)
        options |= XML_PARSE_DTDVALID | XML_PARSE_DTDLOAD | XML_PARSE_DTDATTR;
    if (mask & NSXMLDocumentXInclude)
        options |= XML_PARSE_XINCLUDE | XML_PARSE_NOXINCNODE;
    if (encoding)
        options |= XML_PARSE_IGNORE_ENC;
    quiet_begin();
    xDoc *doc = lx.readMemory(bytes, (int)len, url ? [url UTF8String] : NULL, encoding, options);
    quiet_end();
    if (doc && (mask & NSXMLDocumentValidate) && first_error.validity) {
        lx.freeDoc(doc);
        doc = NULL;
    }
    if (!doc)
        FSetError(error, kept_error(NSXMLParserInternalError, @"The document couldn't be read"));
    return doc;
}

/* The encoding named in a string's XML declaration, if it has one. */
static NSString *declared_encoding(NSString *s)
{
    if (![s hasPrefix:@"<?xml"])
        return nil;
    NSRange end = [s rangeOfString:@"?>"];
    if (end.location == NSNotFound)
        return nil;
    NSString *decl = [s substringToIndex:end.location];
    NSRange at = [decl rangeOfString:@"encoding"];
    if (at.location == NSNotFound)
        return nil;
    NSString *rest = [decl substringFromIndex:at.location + at.length];
    NSUInteger i = 0, n = [rest length];
    while (i < n && ([rest characterAtIndex:i] == ' ' || [rest characterAtIndex:i] == '='))
        i++;
    if (i >= n)
        return nil;
    unichar q = [rest characterAtIndex:i];
    if (q != '"' && q != '\'')
        return nil;
    NSRange close = [rest rangeOfString:(q == '"' ? @"\"" : @"'") options:0 range:NSMakeRange(i + 1, n - i - 1)];
    if (close.location == NSNotFound)
        return nil;
    return [rest substringWithRange:NSMakeRange(i + 1, close.location - i - 1)];
}

/* ---- NSXMLNode ---- */

static void check_orphan(NSXMLNode *child)
{
    if (!child)
        FRaise(NSInvalidArgumentException, @"*** NSXMLNode: nil child");
    if (child->_parent)
        FRaise(NSInternalInconsistencyException, @"Cannot add a child that has a parent; detach or copy first");
}

static void check_child_kind(NSXMLNode *parent, NSXMLNode *child)
{
    NSXMLNodeKind k = child->_kind;
    BOOL ok;
    switch (parent->_kind) {
    case NSXMLElementKind:
        ok = k == NSXMLElementKind || k == NSXMLTextKind || k == NSXMLCommentKind ||
             k == NSXMLProcessingInstructionKind;
        break;
    case NSXMLDocumentKind:
        ok = k == NSXMLElementKind || k == NSXMLCommentKind || k == NSXMLProcessingInstructionKind;
        break;
    case NSXMLDTDKind:
        ok = k == NSXMLEntityDeclarationKind || k == NSXMLAttributeDeclarationKind ||
             k == NSXMLElementDeclarationKind || k == NSXMLNotationDeclarationKind || k == NSXMLCommentKind ||
             k == NSXMLProcessingInstructionKind;
        break;
    default:
        ok = NO;
    }
    if (!ok)
        FRaise(NSInvalidArgumentException, @"*** -[%@ insertChild:atIndex:]: a node of kind %lu can't be a child here",
               NSStringFromClass([parent class]), (unsigned long)k);
}

static void adopt_at(NSXMLNode *parent, NSXMLNode *child, NSUInteger index)
{
    check_orphan(child);
    check_child_kind(parent, child);
    if (!parent->_children)
        parent->_children = [[NSMutableArray alloc] init];
    if (index > [parent->_children count])
        FRaise(NSRangeException, @"*** -[%@ insertChild:atIndex:]: index %lu beyond bounds [0 .. %lu]",
               NSStringFromClass([parent class]), (unsigned long)index, (unsigned long)[parent->_children count]);
    [parent->_children insertObject:child atIndex:index];
    child->_parent = parent;
    shadow_free(child->_shadow); /* made while it was a tree of its own */
    child->_shadow = NULL;
    CHANGED();
}

static void remove_at(NSXMLNode *parent, NSUInteger index)
{
    if (index >= [parent->_children count])
        FRaise(NSRangeException, @"*** -[%@ removeChildAtIndex:]: index %lu beyond bounds [0 .. %lu]",
               NSStringFromClass([parent class]), (unsigned long)index, (unsigned long)[parent->_children count]);
    NSXMLNode *c = [parent->_children objectAtIndex:index];
    c->_parent = nil;
    [parent->_children removeObjectAtIndex:index];
    CHANGED();
}

static void remove_all(NSXMLNode *parent)
{
    for (NSXMLNode *c in parent->_children)
        c->_parent = nil;
    [parent->_children removeAllObjects];
    CHANGED();
}

static void set_children(NSXMLNode *parent, NSArray *children)
{
    [[children retain] autorelease];
    remove_all(parent);
    for (NSXMLNode *c in children)
        adopt_at(parent, c, [parent->_children count]);
}

static void replace_at(NSXMLNode *parent, NSUInteger index, NSXMLNode *node)
{
    if (index >= [parent->_children count])
        FRaise(NSRangeException, @"*** -[%@ replaceChildAtIndex:withNode:]: index %lu beyond bounds",
               NSStringFromClass([parent class]), (unsigned long)index);
    check_orphan(node);
    check_child_kind(parent, node);
    remove_at(parent, index);
    adopt_at(parent, node, index);
}

@implementation NSXMLNode
- (instancetype)init { return [self initWithKind:NSXMLInvalidKind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind { return [self initWithKind:kind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options
{
    if ([self class] == [NSXMLNode class]) {
        Class cls = nil;
        switch (kind) {
        case NSXMLElementKind:
            cls = [NSXMLElement class];
            break;
        case NSXMLDocumentKind:
            cls = [NSXMLDocument class];
            break;
        case NSXMLDTDKind:
            cls = [NSXMLDTD class];
            break;
        case NSXMLEntityDeclarationKind:
        case NSXMLAttributeDeclarationKind:
        case NSXMLElementDeclarationKind:
        case NSXMLNotationDeclarationKind:
            cls = [NSXMLDTDNode class];
            break;
        default:
            break;
        }
        if (cls) {
            [self release];
            return [[cls alloc] initWithKind:kind options:options];
        }
    }
    if (!(self = [super init]))
        return nil;
    _kind = kind;
    _options = options;
    return self;
}

- (void)dealloc
{
    for (NSXMLNode *c in _children)
        c->_parent = nil;
    [_children release];
    [_name release];
    [_value release];
    [_URI release];
    shadow_free(_shadow);
    [super dealloc];
}

+ (id)document { return [[[NSXMLDocument alloc] init] autorelease]; }
+ (id)documentWithRootElement:(NSXMLElement *)element
{
    return [[[NSXMLDocument alloc] initWithRootElement:element] autorelease];
}
+ (id)elementWithName:(NSString *)name { return [[[NSXMLElement alloc] initWithName:name] autorelease]; }
+ (id)elementWithName:(NSString *)name URI:(NSString *)URI
{
    return [[[NSXMLElement alloc] initWithName:name URI:URI] autorelease];
}
+ (id)elementWithName:(NSString *)name stringValue:(NSString *)string
{
    return [[[NSXMLElement alloc] initWithName:name stringValue:string] autorelease];
}
+ (id)elementWithName:(NSString *)name children:(NSArray *)children attributes:(NSArray *)attributes
{
    NSXMLElement *e = [[[NSXMLElement alloc] initWithName:name] autorelease];
    [e setChildren:children];
    [e setAttributes:attributes];
    return e;
}
static NSXMLNode *leaf(NSXMLNodeKind kind, NSString *name, NSString *URI, NSString *value)
{
    NSXMLNode *n = [[[NSXMLNode alloc] initWithKind:kind options:0] autorelease];
    n->_name = [name copy];
    n->_URI = [URI copy];
    n->_value = [value copy];
    return n;
}
+ (id)attributeWithName:(NSString *)name stringValue:(NSString *)stringValue
{
    return leaf(NSXMLAttributeKind, name, nil, stringValue);
}
+ (id)attributeWithName:(NSString *)name URI:(NSString *)URI stringValue:(NSString *)stringValue
{
    return leaf(NSXMLAttributeKind, name, URI, stringValue);
}
+ (id)namespaceWithName:(NSString *)name stringValue:(NSString *)stringValue
{
    return leaf(NSXMLNamespaceKind, name ?: @"", nil, stringValue);
}
+ (id)processingInstructionWithName:(NSString *)name stringValue:(NSString *)stringValue
{
    return leaf(NSXMLProcessingInstructionKind, name, nil, stringValue);
}
+ (id)commentWithStringValue:(NSString *)stringValue { return leaf(NSXMLCommentKind, nil, nil, stringValue); }
+ (id)textWithStringValue:(NSString *)stringValue { return leaf(NSXMLTextKind, nil, nil, stringValue); }
+ (id)DTDNodeWithXMLString:(NSString *)string { return [[[NSXMLDTDNode alloc] initWithXMLString:string] autorelease]; }

- (NSXMLNodeKind)kind { return _kind; }
- (NSXMLNodeOptions)options { return _options; }

- (NSString *)name
{
    switch (_kind) {
    case NSXMLDocumentKind:
    case NSXMLTextKind:
    case NSXMLCommentKind:
    case NSXMLInvalidKind:
        return nil;
    default:
        return _name;
    }
}
- (void)setName:(NSString *)name
{
    name = [name copy];
    [_name release];
    _name = name;
    CHANGED();
}

- (id)objectValue
{
    if (_kind == NSXMLElementKind || _kind == NSXMLDocumentKind)
        return [self stringValue];
    return _value;
}
- (void)setObjectValue:(id)value
{
    if (_kind == NSXMLElementKind || _kind == NSXMLDocumentKind) {
        [self setStringValue:object_string(value)];
        return;
    }
    value = [value isKindOfClass:[NSString class]] ? [value copy] : [value retain];
    [_value release];
    _value = value;
    CHANGED();
}

- (NSString *)stringValue
{
    switch (_kind) {
    case NSXMLElementKind:
    case NSXMLDocumentKind: {
        NSMutableString *s = [NSMutableString string];
        text_of(self, s);
        return s;
    }
    case NSXMLDTDKind:
        return @"";
    default:
        return object_string(_value) ?: @"";
    }
}
- (void)setStringValue:(NSString *)string
{
    if (_kind == NSXMLElementKind) {
        remove_all(self);
        if ([string length]) {
            NSXMLNode *t = leaf(NSXMLTextKind, nil, nil, string);
            adopt_at(self, t, 0);
        }
        return;
    }
    if (_kind == NSXMLDocumentKind || _kind == NSXMLDTDKind)
        return;
    string = [string copy];
    [_value release];
    _value = string;
    if ([self isKindOfClass:[NSXMLDTDNode class]]) {
        [((NSXMLDTDNode *)self)->_xml release];
        ((NSXMLDTDNode *)self)->_xml = nil;
    }
    CHANGED();
}
- (void)setStringValue:(NSString *)string resolvingEntities:(BOOL)resolve
{
    [self setStringValue:resolve ? resolve_entities(string) : string];
}

- (NSUInteger)index
{
    if (!_parent)
        return 0;
    NSArray *list = _kind == NSXMLAttributeKind   ? ((NSXMLElement *)_parent)->_attributes
                    : _kind == NSXMLNamespaceKind ? ((NSXMLElement *)_parent)->_namespaces
                                                  : _parent->_children;
    NSUInteger i = [list indexOfObjectIdenticalTo:self];
    return i == NSNotFound ? 0 : i;
}
- (NSUInteger)level
{
    NSUInteger n = 0;
    for (NSXMLNode *p = _parent; p; p = p->_parent)
        n++;
    return n;
}
- (NSXMLDocument *)rootDocument
{
    NSXMLNode *top = top_of(self);
    return top->_kind == NSXMLDocumentKind ? (NSXMLDocument *)top : nil;
}
- (NSXMLNode *)parent { return _parent; }
- (NSUInteger)childCount { return [_children count]; }
- (NSArray *)children { return [_children count] ? [[_children copy] autorelease] : nil; }
- (NSXMLNode *)childAtIndex:(NSUInteger)index { return [_children objectAtIndex:index]; }

static BOOL is_child_kind(NSXMLNode *n) { return n->_kind != NSXMLAttributeKind && n->_kind != NSXMLNamespaceKind; }

- (NSXMLNode *)previousSibling
{
    if (!_parent || !is_child_kind(self))
        return nil;
    NSUInteger i = [_parent->_children indexOfObjectIdenticalTo:self];
    return i != NSNotFound && i > 0 ? [_parent->_children objectAtIndex:i - 1] : nil;
}
- (NSXMLNode *)nextSibling
{
    if (!_parent || !is_child_kind(self))
        return nil;
    NSUInteger i = [_parent->_children indexOfObjectIdenticalTo:self];
    return i != NSNotFound && i + 1 < [_parent->_children count] ? [_parent->_children objectAtIndex:i + 1] : nil;
}
- (NSXMLNode *)nextNode
{
    if (!is_child_kind(self))
        return nil;
    if ([_children count])
        return [_children objectAtIndex:0];
    for (NSXMLNode *n = self; n; n = n->_parent) {
        NSXMLNode *s = [n nextSibling];
        if (s)
            return s;
    }
    return nil;
}
- (NSXMLNode *)previousNode
{
    if (!is_child_kind(self))
        return nil;
    NSXMLNode *s = [self previousSibling];
    if (!s)
        return _parent;
    while ([s->_children count])
        s = [s->_children lastObject];
    return s;
}

- (void)detach
{
    NSXMLNode *p = _parent;
    if (!p)
        return;
    [[self retain] autorelease];
    if (_kind == NSXMLAttributeKind)
        [((NSXMLElement *)p)->_attributes removeObjectIdenticalTo:self];
    else if (_kind == NSXMLNamespaceKind)
        [((NSXMLElement *)p)->_namespaces removeObjectIdenticalTo:self];
    else if (p->_kind == NSXMLDocumentKind && ((NSXMLDocument *)p)->_DTD == (id)self) {
        ((NSXMLDocument *)p)->_DTD = nil;
        [self autorelease];
    } else
        [p->_children removeObjectIdenticalTo:self];
    _parent = nil;
    CHANGED();
}

- (NSString *)XPath
{
    if (_kind == NSXMLDocumentKind)
        return @"/";
    NSMutableArray *steps = [NSMutableArray array];
    NSXMLNode *n = self;
    for (; n && n->_kind != NSXMLDocumentKind; n = n->_parent)
        [steps insertObject:xpath_step(n) atIndex:0];
    NSString *path = [steps componentsJoinedByString:@"/"];
    return n ? [@"/" stringByAppendingString:path] : path;
}

+ (NSString *)localNameForName:(NSString *)name
{
    if (!name)
        return nil;
    NSRange r = [name rangeOfString:@":"];
    return r.location == NSNotFound ? name : [name substringFromIndex:r.location + 1];
}
+ (NSString *)prefixForName:(NSString *)name
{
    if (!name)
        return nil;
    NSRange r = [name rangeOfString:@":"];
    return r.location == NSNotFound ? @"" : [name substringToIndex:r.location];
}
+ (NSXMLNode *)predefinedNamespaceForPrefix:(NSString *)name
{
    NSString *uri = [name isEqualToString:@"xml"]   ? @"http://www.w3.org/XML/1998/namespace"
                    : [name isEqualToString:@"xs"]  ? @"http://www.w3.org/2001/XMLSchema"
                    : [name isEqualToString:@"xsi"] ? @"http://www.w3.org/2001/XMLSchema-instance"
                    : [name isEqualToString:@"fn"]  ? @"http://www.w3.org/2005/xpath-functions"
                                                    : nil;
    return uri ? [NSXMLNode namespaceWithName:name stringValue:uri] : nil;
}

- (NSString *)localName
{
    if (_kind == NSXMLElementKind || _kind == NSXMLAttributeKind)
        return [NSXMLNode localNameForName:_name];
    return [self name];
}
- (NSString *)prefix
{
    if (_kind == NSXMLElementKind || _kind == NSXMLAttributeKind)
        return [NSXMLNode prefixForName:_name];
    return @"";
}
- (NSString *)URI
{
    if (_URI || _kind != NSXMLElementKind || !_name)
        return _URI;
    /* an element made without one is in the namespace its prefix has where it is */
    return [[(NSXMLElement *)self resolveNamespaceForName:_name] stringValue];
}
- (void)setURI:(NSString *)URI
{
    URI = [URI copy];
    [_URI release];
    _URI = URI;
    CHANGED();
}

- (NSString *)description { return [self XMLString]; }
- (NSString *)XMLString { return [self XMLStringWithOptions:NSXMLNodeOptionsNone]; }
- (NSString *)XMLStringWithOptions:(NSXMLNodeOptions)options { return xml_string(self, options, 0x10FFFF); }

static int c14n_visible(void *target, xNode *node, xNode *parent)
{
    xNode *n = node;
    if (!n || n->type == X_NAMESPACE || n->type == X_ATTRIBUTE)
        n = parent;
    for (; n; n = n->parent)
        if (n == target)
            return 1;
    return 0;
}

- (NSString *)canonicalXMLStringPreservingComments:(BOOL)comments
{
    struct shadow *sh = shadow_of(self);
    if (!sh || !sh->doc)
        return nil;
    NSString *result = nil;
    quiet_begin();
    if (_kind == NSXMLDocumentKind && lx.c14nDocDumpMemory) {
        xmlChar *out = NULL;
        if (lx.c14nDocDumpMemory(sh->doc, NULL, 0, NULL, comments, &out) >= 0)
            result = str(out) ?: @"";
        x_free(out);
    } else if (lx.c14nExecute && lx.allocOutputBuffer && lx.outputBufferGetContent && lx.outputBufferGetSize &&
               lx.outputBufferClose) {
        xNode *target = shadow_node(sh, self);
        void *buf = lx.allocOutputBuffer(NULL);
        if (target && buf && lx.c14nExecute(sh->doc, c14n_visible, target, 0, NULL, comments, buf) >= 0)
            result = [[[NSString alloc] initWithBytes:lx.outputBufferGetContent(buf)
                                               length:lx.outputBufferGetSize(buf)
                                             encoding:NSUTF8StringEncoding] autorelease];
        if (buf)
            lx.outputBufferClose(buf);
    }
    quiet_end();
    return result;
}

static NSXMLNode *object_for(xNode *x)
{
    if (x->type != X_NAMESPACE)
        return x->_private;
    /* XPath hands out copies of namespace nodes, whose next is their element */
    xNs *ns = (xNs *)x;
    xNode *el = (xNode *)ns->next;
    NSString *prefix = str(ns->prefix) ?: @"";
    for (NSXMLNode *e = el ? el->_private : nil; e; e = e->_parent)
        if (e->_kind == NSXMLElementKind)
            for (NSXMLNode *n in ((NSXMLElement *)e)->_namespaces)
                if ([n->_name isEqualToString:prefix])
                    return n;
    return [NSXMLNode namespaceWithName:prefix stringValue:str(ns->href)];
}

- (NSArray *)nodesForXPath:(NSString *)xpath error:(NSError **)error
{
    if (!load_libxml2()) {
        FSetError(error, unavailable());
        return nil;
    }
    struct shadow *sh = shadow_of(self);
    xNode *context = sh && sh->doc ? shadow_node(sh, self) : NULL;
    if (!context) {
        FSetError(error, [NSError errorWithDomain:NSXMLParserErrorDomain
                                             code:NSXMLParserInternalError
                                         userInfo:[NSDictionary dictionaryWithObject:@"This node can't be searched"
                                                                              forKey:NSLocalizedDescriptionKey]]);
        return nil;
    }
    void *ctx = lx.xpathNewContext(sh->doc);
    if (!ctx) {
        FSetError(error, unavailable());
        return nil;
    }
    for (NSString *p in sh->prefixes)
        lx.xpathRegisterNs(ctx, u8(p), u8([sh->prefixes objectForKey:p]));
    /* the namespaces in scope where the search starts come first */
    NSMutableArray *chain = [NSMutableArray array];
    for (NSXMLNode *n = self; n; n = n->_parent)
        if (n->_kind == NSXMLElementKind)
            [chain insertObject:n atIndex:0];
    for (NSXMLElement *e in chain)
        for (NSXMLNode *ns in e->_namespaces)
            if ([ns->_name length])
                lx.xpathRegisterNs(ctx, u8(ns->_name), u8(object_string(ns->_value)));
    quiet_begin();
    xXPathObject *obj = lx.xpathNodeEval(context, u8(xpath), ctx);
    quiet_end();
    NSMutableArray *result = nil;
    if (!obj)
        FSetError(error, kept_error(NSXMLParserInternalError, @"Invalid XPath expression"));
    else if (obj->type != 1)
        FSetError(error,
                  [NSError errorWithDomain:NSXMLParserErrorDomain
                                      code:NSXMLParserInternalError
                                  userInfo:[NSDictionary dictionaryWithObject:@"The XPath result isn't a set of nodes"
                                                                       forKey:NSLocalizedDescriptionKey]]);
    else {
        result = [NSMutableArray array];
        xNodeSet *set = obj->nodesetval;
        for (int i = 0; set && i < set->nodeNr; i++) {
            NSXMLNode *n = object_for(set->nodeTab[i]);
            if (n)
                [result addObject:n];
        }
    }
    if (obj)
        lx.xpathFreeObject(obj);
    lx.xpathFreeContext(ctx);
    return result;
}

- (id)copyWithZone:(NSZone *)zone
{
    NSXMLNode *c = [[[self class] alloc] initWithKind:_kind options:_options];
    [self _copyInto:c];
    return c;
}
- (void)_copyInto:(NSXMLNode *)c
{
    [c->_name release];
    c->_name = [_name copy];
    [c->_value release];
    c->_value = [_value copy];
    [c->_URI release];
    c->_URI = [_URI copy];
    for (NSXMLNode *child in _children) {
        NSXMLNode *cc = [child copy];
        append_child(c, cc);
        [cc release];
    }
}
@end

/* ---- NSXMLElement ---- */

static NSXMLDocument *parse_document(Class cls, NSData *data, NSString *url, const char *encoding,
                                     NSXMLNodeOptions mask, NSError **error);

@implementation NSXMLElement
- (instancetype)init { return [self initWithKind:NSXMLElementKind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options
{
    return [super initWithKind:NSXMLElementKind options:options];
}
- (instancetype)initWithName:(NSString *)name { return [self initWithName:name URI:nil]; }
- (instancetype)initWithName:(NSString *)name URI:(NSString *)URI
{
    if (!(self = [self initWithKind:NSXMLElementKind options:0]))
        return nil;
    _name = [name copy];
    _URI = [URI copy];
    return self;
}
- (instancetype)initWithName:(NSString *)name stringValue:(NSString *)string
{
    if (!(self = [self initWithName:name URI:nil]))
        return nil;
    if ([string length]) {
        NSXMLNode *t = leaf(NSXMLTextKind, nil, nil, string);
        append_child(self, t);
    }
    return self;
}
- (instancetype)initWithXMLString:(NSString *)string error:(NSError **)error
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLDocument *doc = parse_document([NSXMLDocument class], data, nil, "UTF-8", 0, error);
    NSXMLElement *root = [doc rootElement];
    [self release];
    if (!root) {
        if (doc)
            FSetError(error, kept_error(NSXMLParserEmptyDocumentError, @"No element"));
        return nil;
    }
    [root retain];
    [root detach];
    return root;
}
- (void)dealloc
{
    for (NSXMLNode *a in _attributes)
        a->_parent = nil;
    for (NSXMLNode *n in _namespaces)
        n->_parent = nil;
    [_attributes release];
    [_namespaces release];
    [super dealloc];
}

- (NSArray *)elementsForName:(NSString *)name
{
    NSMutableArray *out = [NSMutableArray array];
    NSString *prefix = [NSXMLNode prefixForName:name], *local = [NSXMLNode localNameForName:name], *uri = nil;
    if ([prefix length])
        uri = [[self resolveNamespaceForName:name] stringValue];
    for (NSXMLNode *c in _children) {
        if (c->_kind != NSXMLElementKind)
            continue;
        if ([c->_name isEqualToString:name] ||
            (uri && [[c localName] isEqualToString:local] && [[c URI] isEqualToString:uri]))
            [out addObject:c];
    }
    return out;
}
- (NSArray *)elementsForLocalName:(NSString *)localName URI:(NSString *)URI
{
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *c in _children) {
        if (c->_kind != NSXMLElementKind || ![[c localName] isEqualToString:localName])
            continue;
        NSString *u = [c URI];
        if ((!u && ![URI length]) || [u isEqualToString:URI])
            [out addObject:c];
    }
    return out;
}

- (void)addAttribute:(NSXMLNode *)attribute
{
    check_orphan(attribute);
    if (attribute->_kind != NSXMLAttributeKind)
        FRaise(NSInvalidArgumentException, @"*** -[NSXMLElement addAttribute:]: not an attribute");
    if ([self attributeForName:attribute->_name])
        return;
    if (!_attributes)
        _attributes = [[NSMutableArray alloc] init];
    [_attributes addObject:attribute];
    attribute->_parent = self;
    CHANGED();
}
- (void)removeAttributeForName:(NSString *)name { [[self attributeForName:name] detach]; }
- (NSArray *)attributes { return [_attributes count] ? [[_attributes copy] autorelease] : nil; }
- (void)setAttributes:(NSArray *)attributes
{
    [[attributes retain] autorelease];
    for (NSXMLNode *a in _attributes)
        a->_parent = nil;
    [_attributes removeAllObjects];
    CHANGED();
    for (NSXMLNode *a in attributes)
        [self addAttribute:a];
}
- (void)setAttributesWithDictionary:(NSDictionary *)attributes
{
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *k in attributes)
        [list addObject:[NSXMLNode attributeWithName:k stringValue:object_string([attributes objectForKey:k])]];
    [self setAttributes:list];
}
- (void)setAttributesAsDictionary:(NSDictionary *)attributes { [self setAttributesWithDictionary:attributes]; }
- (NSXMLNode *)attributeForName:(NSString *)name
{
    for (NSXMLNode *a in _attributes)
        if ([a->_name isEqualToString:name])
            return a;
    return nil;
}
- (NSXMLNode *)attributeForLocalName:(NSString *)localName URI:(NSString *)URI
{
    for (NSXMLNode *a in _attributes) {
        if (![[a localName] isEqualToString:localName])
            continue;
        NSString *u = a->_URI;
        if (!u && [[a prefix] length])
            u = [[self resolveNamespaceForName:a->_name] stringValue];
        if ((!u && ![URI length]) || [u isEqualToString:URI])
            return a;
    }
    return nil;
}

- (void)addNamespace:(NSXMLNode *)aNamespace
{
    check_orphan(aNamespace);
    if (aNamespace->_kind != NSXMLNamespaceKind)
        FRaise(NSInvalidArgumentException, @"*** -[NSXMLElement addNamespace:]: not a namespace");
    if ([self namespaceForPrefix:aNamespace->_name])
        return;
    if (!_namespaces)
        _namespaces = [[NSMutableArray alloc] init];
    [_namespaces addObject:aNamespace];
    aNamespace->_parent = self;
    CHANGED();
}
- (void)removeNamespaceForPrefix:(NSString *)name { [[self namespaceForPrefix:name] detach]; }
- (NSArray *)namespaces { return [_namespaces count] ? [[_namespaces copy] autorelease] : nil; }
- (void)setNamespaces:(NSArray *)namespaces
{
    [[namespaces retain] autorelease];
    for (NSXMLNode *n in _namespaces)
        n->_parent = nil;
    [_namespaces removeAllObjects];
    CHANGED();
    for (NSXMLNode *n in namespaces)
        [self addNamespace:n];
}
- (NSXMLNode *)namespaceForPrefix:(NSString *)name
{
    name = name ?: @"";
    for (NSXMLNode *n in _namespaces)
        if ([(n->_name ?: @"") isEqualToString:name])
            return n;
    return nil;
}
- (NSXMLNode *)resolveNamespaceForName:(NSString *)name
{
    NSString *prefix = [NSXMLNode prefixForName:name] ?: @"";
    for (NSXMLNode *e = self; e; e = e->_parent)
        if (e->_kind == NSXMLElementKind) {
            NSXMLNode *ns = [(NSXMLElement *)e namespaceForPrefix:prefix];
            if (ns)
                return ns;
        }
    return [prefix length] ? [NSXMLNode predefinedNamespaceForPrefix:prefix] : nil;
}
- (NSString *)resolvePrefixForNamespaceURI:(NSString *)namespaceURI
{
    for (NSXMLNode *e = self; e; e = e->_parent)
        if (e->_kind == NSXMLElementKind)
            for (NSXMLNode *n in ((NSXMLElement *)e)->_namespaces)
                if ([object_string(n->_value) isEqualToString:namespaceURI])
                    return n->_name;
    if ([namespaceURI isEqualToString:@"http://www.w3.org/XML/1998/namespace"])
        return @"xml";
    return nil;
}

- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index { adopt_at(self, child, index); }
- (void)insertChildren:(NSArray *)children atIndex:(NSUInteger)index
{
    for (NSXMLNode *c in children)
        adopt_at(self, c, index++);
}
- (void)removeChildAtIndex:(NSUInteger)index { remove_at(self, index); }
- (void)setChildren:(NSArray *)children { set_children(self, children); }
- (void)addChild:(NSXMLNode *)child { adopt_at(self, child, [_children count]); }
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node { replace_at(self, index, node); }
- (void)normalizeAdjacentTextNodesPreservingCDATA:(BOOL)preserve
{
    for (NSInteger i = (NSInteger)[_children count] - 1; i > 0; i--) {
        NSXMLNode *a = [_children objectAtIndex:i - 1], *b = [_children objectAtIndex:i];
        if (a->_kind != NSXMLTextKind || b->_kind != NSXMLTextKind)
            continue;
        if (preserve && ((a->_options | b->_options) & NSXMLNodeIsCDATA))
            continue;
        NSString *joined = [[a stringValue] stringByAppendingString:[b stringValue]];
        [a->_value release];
        a->_value = [joined copy];
        a->_options &= ~NSXMLNodeIsCDATA;
        remove_at(self, i);
    }
    for (NSXMLNode *c in _children)
        if (c->_kind == NSXMLElementKind)
            [(NSXMLElement *)c normalizeAdjacentTextNodesPreservingCDATA:preserve];
    CHANGED();
}

- (void)_copyInto:(NSXMLNode *)c
{
    [super _copyInto:c];
    NSXMLElement *e = (NSXMLElement *)c;
    for (NSXMLNode *n in _namespaces) {
        NSXMLNode *nc = [n copy];
        [e addNamespace:nc];
        [nc release];
    }
    for (NSXMLNode *a in _attributes) {
        NSXMLNode *ac = [a copy];
        [e addAttribute:ac];
        [ac release];
    }
}
@end

/* ---- NSXMLDocument ---- */

static NSXMLDocument *parse_document(Class cls, NSData *data, NSString *url, const char *encoding,
                                     NSXMLNodeOptions mask, NSError **error)
{
    if (mask & NSXMLDocumentTidyHTML) {
        FSetError(error, [NSError errorWithDomain:NSXMLParserErrorDomain
                                             code:NSXMLParserInternalError
                                         userInfo:[NSDictionary dictionaryWithObject:@"Ferry doesn't read HTML documents"
                                                                              forKey:NSLocalizedDescriptionKey]]);
        return nil;
    }
    xDoc *x = parse_bytes([data bytes], [data length], url, encoding, mask, error);
    if (!x)
        return nil;
    Conv cv = {mask, [cls replacementClassForClass:[NSXMLElement class]],
               [cls replacementClassForClass:[NSXMLNode class]], [cls replacementClassForClass:[NSXMLDTD class]],
               [cls replacementClassForClass:[NSXMLDTDNode class]]};
    NSXMLDocument *doc = [[[cls alloc] initWithKind:NSXMLDocumentKind options:mask] autorelease];
    if (x->standalone != -1) /* there was an XML declaration */
        doc->_version = [(str(x->version) ?: @"1.0") copy];
    doc->_encoding = [str(x->encoding) copy];
    doc->_standalone = x->standalone == 1;
    if (x->intSubset) {
        doc->_DTD = convert_dtd(x->intSubset, &cv);
        doc->_DTD->_parent = doc;
    }
    convert_list(x->children, doc, &cv);
    lx.freeDoc(x);
    CHANGED();
    return doc;
}

@implementation NSXMLDocument
+ (Class)replacementClassForClass:(Class)cls { return cls; }
- (instancetype)init { return [self initWithKind:NSXMLDocumentKind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options
{
    return [super initWithKind:NSXMLDocumentKind options:options];
}
- (instancetype)initWithRootElement:(NSXMLElement *)element
{
    if (!(self = [self init]))
        return nil;
    if (element)
        [self setRootElement:element];
    return self;
}
/* Takes the parsed document's contents (and class) in place of the receiver. */
- (instancetype)_become:(NSXMLDocument *)doc
{
    [self release];
    return [doc retain];
}
- (instancetype)initWithXMLString:(NSString *)string options:(NSXMLNodeOptions)mask error:(NSError **)error
{
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLDocument *doc = parse_document([self class], data, nil, "UTF-8", mask, error);
    if (doc) {
        [doc->_encoding release];
        doc->_encoding = [declared_encoding(string) copy];
    }
    return [self _become:doc];
}
- (instancetype)initWithData:(NSData *)data options:(NSXMLNodeOptions)mask error:(NSError **)error
{
    return [self _become:parse_document([self class], data, nil, NULL, mask, error)];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSXMLNodeOptions)mask error:(NSError **)error
{
    if (![url isFileURL]) {
        FSetError(error, [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileReadUnsupportedSchemeError
                                         userInfo:[NSDictionary dictionaryWithObject:@"Ferry reads XML documents from files only"
                                                                              forKey:NSLocalizedDescriptionKey]]);
        [self release];
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:[url path]];
    if (!data) {
        FSetError(error, FPosixError(ENOENT, [url path]));
        [self release];
        return nil;
    }
    NSXMLDocument *doc = parse_document([self class], data, [url path], NULL, mask, error);
    if (doc)
        doc->_URI = [[url absoluteString] copy];
    return [self _become:doc];
}
- (void)dealloc
{
    [_version release];
    [_encoding release];
    [_MIMEType release];
    if (_DTD)
        _DTD->_parent = nil;
    [_DTD release];
    [super dealloc];
}

- (NSString *)characterEncoding { return _encoding; }
- (void)setCharacterEncoding:(NSString *)encoding
{
    encoding = [encoding copy];
    [_encoding release];
    _encoding = encoding;
}
- (NSString *)version { return _version; }
- (void)setVersion:(NSString *)version
{
    if (version && ![version isEqualToString:@"1.0"] && ![version isEqualToString:@"1.1"])
        FRaise(NSInvalidArgumentException, @"*** -[NSXMLDocument setVersion:]: the version must be 1.0 or 1.1");
    version = [version copy];
    [_version release];
    _version = version;
}
- (BOOL)isStandalone { return _standalone; }
- (void)setStandalone:(BOOL)standalone { _standalone = standalone; }
- (NSXMLDocumentContentKind)documentContentKind { return _contentKind; }
- (void)setDocumentContentKind:(NSXMLDocumentContentKind)kind { _contentKind = kind; }
- (NSString *)MIMEType { return _MIMEType; }
- (void)setMIMEType:(NSString *)type
{
    type = [type copy];
    [_MIMEType release];
    _MIMEType = type;
}
- (NSXMLDTD *)DTD { return _DTD; }
- (void)setDTD:(NSXMLDTD *)dtd
{
    if (dtd == _DTD)
        return;
    if (dtd && dtd->_parent)
        check_orphan(dtd);
    if (_DTD)
        _DTD->_parent = nil;
    id wasDTD = _DTD;
    _DTD = [dtd retain];
    [wasDTD release];
    if (dtd)
        dtd->_parent = self;
    CHANGED();
}

- (NSXMLElement *)rootElement
{
    for (NSXMLNode *c in _children)
        if (c->_kind == NSXMLElementKind)
            return (NSXMLElement *)c;
    return nil;
}
- (void)setRootElement:(NSXMLElement *)root
{
    NSXMLElement *old = [self rootElement];
    if (old == root)
        return;
    if (old) {
        NSUInteger i = [_children indexOfObjectIdenticalTo:old];
        if (root)
            replace_at(self, i, root);
        else
            remove_at(self, i);
    } else if (root)
        adopt_at(self, root, [_children count]);
}
- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index { adopt_at(self, child, index); }
- (void)insertChildren:(NSArray *)children atIndex:(NSUInteger)index
{
    for (NSXMLNode *c in children)
        adopt_at(self, c, index++);
}
- (void)removeChildAtIndex:(NSUInteger)index { remove_at(self, index); }
- (void)setChildren:(NSArray *)children { set_children(self, children); }
- (void)addChild:(NSXMLNode *)child { adopt_at(self, child, [_children count]); }
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node { replace_at(self, index, node); }

- (NSData *)XMLData { return [self XMLDataWithOptions:NSXMLNodeOptionsNone]; }
- (NSData *)XMLDataWithOptions:(NSXMLNodeOptions)options
{
    /* In an encoding that lacks a character, text and attribute values get a
     * character reference for it. Other encodings than these are written as UTF-8. */
    NSString *enc = [_encoding uppercaseString];
    unsigned maxch = 0x10FFFF;
    if ([enc isEqualToString:@"ISO-8859-1"] || [enc isEqualToString:@"LATIN1"] || [enc isEqualToString:@"ISO_8859-1"])
        maxch = 0xFF;
    else if ([enc isEqualToString:@"US-ASCII"] || [enc isEqualToString:@"ASCII"])
        maxch = 0x7F;
    else if ([enc isEqualToString:@"UTF-16"]) { /* with a byte order mark, little-endian */
        NSString *s = xml_string(self, options, maxch);
        NSMutableData *d = [NSMutableData dataWithLength:2 + 2 * [s length]];
        unsigned char *b = [d mutableBytes];
        b[0] = 0xFF, b[1] = 0xFE;
        for (NSUInteger i = 0; i < [s length]; i++) {
            unichar c = [s characterAtIndex:i];
            b[2 + 2 * i] = c & 0xFF, b[3 + 2 * i] = c >> 8;
        }
        return d;
    }
    Out o = {NULL, 0, 0, maxch};
    put(&o, "", 0);
    write_node(&o, self, options, 0);
    if (maxch == 0xFF) { /* UTF-8 to Latin-1, in place: every character left is below 256 */
        size_t j = 0;
        for (size_t i = 0; i < o.n; i++) {
            unsigned char c = (unsigned char)o.p[i];
            if (c >= 0xC0 && i + 1 < o.n) {
                o.p[j++] = (char)(((c & 0x1F) << 6) | ((unsigned char)o.p[i + 1] & 0x3F));
                i++;
            } else
                o.p[j++] = (char)c;
        }
        o.n = j;
    }
    NSData *data = [NSData dataWithBytes:o.p length:o.n];
    free(o.p);
    return data;
}

- (void)_copyInto:(NSXMLNode *)c
{
    [super _copyInto:c];
    NSXMLDocument *d = (NSXMLDocument *)c;
    d->_version = [_version copy];
    d->_encoding = [_encoding copy];
    d->_MIMEType = [_MIMEType copy];
    d->_standalone = _standalone;
    d->_contentKind = _contentKind;
    if (_DTD) {
        NSXMLDTD *dc = [_DTD copy];
        [d setDTD:dc];
        [dc release];
    }
}
@end

/* ---- NSXMLDTD and NSXMLDTDNode ---- */

/* The declarations in a DTD's text, read as a document's internal subset. */
static NSXMLDTD *parse_dtd(NSData *data, NSXMLNodeOptions mask, NSError **error)
{
    NSMutableData *doc = [NSMutableData dataWithBytes:"<!DOCTYPE x [\n" length:14];
    [doc appendData:data];
    [doc appendBytes:"\n]><x/>" length:7];
    xDoc *x = parse_bytes([doc bytes], [doc length], nil, NULL, mask & ~NSXMLDocumentValidate, error);
    if (!x)
        return nil;
    Conv cv = {mask, [NSXMLElement class], [NSXMLNode class], [NSXMLDTD class], [NSXMLDTDNode class]};
    NSXMLDTD *dtd = x->intSubset ? convert_dtd(x->intSubset, &cv) : [[NSXMLDTD alloc] init];
    [dtd->_name release];
    dtd->_name = nil;
    lx.freeDoc(x);
    return [dtd autorelease];
}

@implementation NSXMLDTD
+ (NSXMLDTDNode *)predefinedEntityDeclarationForName:(NSString *)name
{
    NSString *value = [name isEqualToString:@"lt"]     ? @"<"
                      : [name isEqualToString:@"gt"]   ? @">"
                      : [name isEqualToString:@"amp"]  ? @"&"
                      : [name isEqualToString:@"quot"] ? @"\""
                      : [name isEqualToString:@"apos"] ? @"'"
                                                       : nil;
    if (!value)
        return nil;
    NSXMLDTDNode *d = [[[NSXMLDTDNode alloc] initWithKind:NSXMLEntityDeclarationKind options:0] autorelease];
    d->_name = [name copy];
    d->_value = [value copy];
    d->_DTDKind = NSXMLEntityPredefined;
    return d;
}
- (instancetype)init { return [self initWithKind:NSXMLDTDKind options:0]; }
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options
{
    return [super initWithKind:NSXMLDTDKind options:options];
}
- (instancetype)initWithData:(NSData *)data options:(NSXMLNodeOptions)mask error:(NSError **)error
{
    NSXMLDTD *dtd = parse_dtd(data, mask, error);
    [self release];
    return [dtd retain];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSXMLNodeOptions)mask error:(NSError **)error
{
    NSData *data = [url isFileURL] ? [NSData dataWithContentsOfFile:[url path]] : nil;
    if (!data) {
        FSetError(error, [url isFileURL] ? FPosixError(ENOENT, [url path])
                                         : [NSError errorWithDomain:NSCocoaErrorDomain
                                                               code:NSFileReadUnsupportedSchemeError
                                                           userInfo:nil]);
        [self release];
        return nil;
    }
    self = [self initWithData:data options:mask error:error];
    if (self)
        _systemID = [[url absoluteString] copy];
    return self;
}
- (void)dealloc
{
    [_publicID release];
    [_systemID release];
    [super dealloc];
}
- (NSString *)publicID { return _publicID; }
- (void)setPublicID:(NSString *)s
{
    s = [s copy];
    [_publicID release];
    _publicID = s;
}
- (NSString *)systemID { return _systemID; }
- (void)setSystemID:(NSString *)s
{
    s = [s copy];
    [_systemID release];
    _systemID = s;
}
- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index { adopt_at(self, child, index); }
- (void)insertChildren:(NSArray *)children atIndex:(NSUInteger)index
{
    for (NSXMLNode *c in children)
        adopt_at(self, c, index++);
}
- (void)removeChildAtIndex:(NSUInteger)index { remove_at(self, index); }
- (void)setChildren:(NSArray *)children { set_children(self, children); }
- (void)addChild:(NSXMLNode *)child { adopt_at(self, child, [_children count]); }
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node { replace_at(self, index, node); }
static NSXMLDTDNode *find_decl(NSXMLDTD *d, NSXMLNodeKind kind, NSString *name, NSString *element)
{
    for (NSXMLNode *c in d->_children)
        if (c->_kind == kind && [c->_name isEqualToString:name] &&
            (!element || [((NSXMLDTDNode *)c)->_elementName isEqualToString:element]))
            return (NSXMLDTDNode *)c;
    return nil;
}
- (NSXMLDTDNode *)entityDeclarationForName:(NSString *)name
{
    return find_decl(self, NSXMLEntityDeclarationKind, name, nil);
}
- (NSXMLDTDNode *)notationDeclarationForName:(NSString *)name
{
    return find_decl(self, NSXMLNotationDeclarationKind, name, nil);
}
- (NSXMLDTDNode *)elementDeclarationForName:(NSString *)name
{
    return find_decl(self, NSXMLElementDeclarationKind, name, nil);
}
- (NSXMLDTDNode *)attributeDeclarationForName:(NSString *)name elementName:(NSString *)elementName
{
    return find_decl(self, NSXMLAttributeDeclarationKind, name, elementName);
}
- (void)_copyInto:(NSXMLNode *)c
{
    [super _copyInto:c];
    ((NSXMLDTD *)c)->_publicID = [_publicID copy];
    ((NSXMLDTD *)c)->_systemID = [_systemID copy];
}
@end

static NSString *dtd_node_xml(NSXMLDTDNode *d)
{
    if (d->_xml)
        return d->_xml;
    NSString *v = object_string(d->_value) ?: @"";
    switch (d->_kind) {
    case NSXMLEntityDeclarationKind: {
        NSMutableString *s = [NSMutableString stringWithString:@"<!ENTITY "];
        if (d->_DTDKind == NSXMLEntityParameterKind)
            [s appendString:@"% "];
        [s appendString:d->_name ?: @""];
        if (d->_publicID)
            [s appendFormat:@" PUBLIC \"%@\" \"%@\"", d->_publicID, d->_systemID ?: @""];
        else if (d->_systemID)
            [s appendFormat:@" SYSTEM \"%@\"", d->_systemID];
        else
            [s appendFormat:@" \"%@\"", [v stringByReplacingOccurrencesOfString:@"\"" withString:@"&#34;"]];
        if (d->_notationName)
            [s appendFormat:@" NDATA %@", d->_notationName];
        [s appendString:@">"];
        return s;
    }
    case NSXMLElementDeclarationKind:
        return [NSString stringWithFormat:@"<!ELEMENT %@ %@>", d->_name ?: @"", v];
    case NSXMLAttributeDeclarationKind:
        return [NSString stringWithFormat:@"<!ATTLIST %@ %@ %@>", d->_elementName ?: @"", d->_name ?: @"", v];
    case NSXMLNotationDeclarationKind:
        if (d->_publicID)
            return [NSString stringWithFormat:@"<!NOTATION %@ PUBLIC \"%@\"%@>", d->_name ?: @"", d->_publicID,
                                              d->_systemID ? [NSString stringWithFormat:@" \"%@\"", d->_systemID]
                                                           : @""];
        return [NSString stringWithFormat:@"<!NOTATION %@ SYSTEM \"%@\">", d->_name ?: @"", d->_systemID ?: @""];
    default:
        return @"";
    }
}

@implementation NSXMLDTDNode
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options
{
    return [super initWithKind:kind options:options];
}
- (instancetype)initWithXMLString:(NSString *)string
{
    NSXMLDTD *dtd = parse_dtd([string dataUsingEncoding:NSUTF8StringEncoding], 0, NULL);
    NSXMLNode *first = [dtd childCount] ? [dtd childAtIndex:0] : nil;
    [self release];
    if (![first isKindOfClass:[NSXMLDTDNode class]])
        return nil;
    [first retain];
    [first detach];
    return (NSXMLDTDNode *)first;
}
- (void)dealloc
{
    [_publicID release];
    [_systemID release];
    [_notationName release];
    [_elementName release];
    [_xml release];
    [super dealloc];
}
static void changed_decl(NSXMLDTDNode *d)
{
    [d->_xml release];
    d->_xml = nil;
    CHANGED();
}
- (void)setName:(NSString *)name
{
    [super setName:name];
    changed_decl(self);
}
- (NSXMLDTDNodeKind)DTDKind { return _DTDKind; }
- (void)setDTDKind:(NSXMLDTDNodeKind)kind
{
    _DTDKind = kind;
    changed_decl(self);
}
- (BOOL)isExternal { return _systemID != nil; }
- (NSString *)publicID { return _publicID; }
- (void)setPublicID:(NSString *)s
{
    s = [s copy];
    [_publicID release];
    _publicID = s;
    changed_decl(self);
}
- (NSString *)systemID { return _systemID; }
- (void)setSystemID:(NSString *)s
{
    s = [s copy];
    [_systemID release];
    _systemID = s;
    changed_decl(self);
}
- (NSString *)notationName { return _notationName; }
- (void)setNotationName:(NSString *)s
{
    s = [s copy];
    [_notationName release];
    _notationName = s;
    changed_decl(self);
}
- (void)_copyInto:(NSXMLNode *)c
{
    [super _copyInto:c];
    NSXMLDTDNode *d = (NSXMLDTDNode *)c;
    d->_DTDKind = _DTDKind;
    d->_publicID = [_publicID copy];
    d->_systemID = [_systemID copy];
    d->_notationName = [_notationName copy];
    d->_elementName = [_elementName copy];
    d->_xml = [_xml copy];
}
@end
