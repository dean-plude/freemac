/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Foundation: NSXMLParser, an event-driven (SAX) XML parser that
 * tells its delegate what it finds.
 *
 * A Mac's NSXMLParser is libxml2's SAX parser, so Ferry's is too: this
 * system's libxml2 (the library a Mac program linking libxml2 gets, see
 * src/host.c), reached through ferry_twin_symbol only when the first
 * document is parsed. That gives the same splitting of text (an entity
 * reference ends a run of characters), the same encodings, and error codes
 * that are libxml2's own, which is what NSXMLParserError's values are.
 *
 * libxml2's SAX2 interface is used in both modes. With namespace
 * processing off (the default) elements are reported by their qualified
 * names, the xmlns attributes stay ordinary attributes, and libxml2's
 * namespace complaints are ignored; with it on, local names, URIs and
 * prefix mappings are reported. Parsing stops at the first error.
 * Entities declared in the document's own DTD are expanded; external
 * entities and DTDs are only loaded (from files, never the network) when
 * shouldResolveExternalEntities is set.
 *
 * Written from Apple's public documentation of NSXMLParser and libxml2's
 * of its SAX2 interface; no Apple code was used. */
#import "FInternal.h"

void *ferry_twin_symbol(const char *install_name, const char *name);

typedef unsigned char xmlChar;
typedef struct xmlCtxt xmlCtxt; /* xmlParserCtxt: only its first three pointers are read */
typedef struct {
    int domain, code;
    char *message;
    int level;
    char *file;
    int line;
    char *str1, *str2, *str3;
    int int1, int2;
    void *ctxt, *node;
} xmlError;

/* libxml2's struct _xmlSAXHandler, field for field */
typedef struct {
    void (*internalSubset)(void *, const xmlChar *, const xmlChar *, const xmlChar *);
    int (*isStandalone)(void *);
    int (*hasInternalSubset)(void *);
    int (*hasExternalSubset)(void *);
    void *(*resolveEntity)(void *, const xmlChar *, const xmlChar *);
    void *(*getEntity)(void *, const xmlChar *);
    void (*entityDecl)(void *, const xmlChar *, int, const xmlChar *, const xmlChar *, xmlChar *);
    void (*notationDecl)(void *, const xmlChar *, const xmlChar *, const xmlChar *);
    void (*attributeDecl)(void *, const xmlChar *, const xmlChar *, int, int, const xmlChar *, void *);
    void (*elementDecl)(void *, const xmlChar *, int, void *);
    void (*unparsedEntityDecl)(void *, const xmlChar *, const xmlChar *, const xmlChar *, const xmlChar *);
    void (*setDocumentLocator)(void *, void *);
    void (*startDocument)(void *);
    void (*endDocument)(void *);
    void (*startElement)(void *, const xmlChar *, const xmlChar **);
    void (*endElement)(void *, const xmlChar *);
    void (*reference)(void *, const xmlChar *);
    void (*characters)(void *, const xmlChar *, int);
    void (*ignorableWhitespace)(void *, const xmlChar *, int);
    void (*processingInstruction)(void *, const xmlChar *, const xmlChar *);
    void (*comment)(void *, const xmlChar *);
    void (*warning)(void *, const char *, ...);
    void (*error)(void *, const char *, ...);
    void (*fatalError)(void *, const char *, ...);
    void *(*getParameterEntity)(void *, const xmlChar *);
    void (*cdataBlock)(void *, const xmlChar *, int);
    void (*externalSubset)(void *, const xmlChar *, const xmlChar *, const xmlChar *);
    unsigned int initialized;
    void *_private;
    void (*startElementNs)(void *, const xmlChar *, const xmlChar *, const xmlChar *, int, const xmlChar **, int, int,
                           const xmlChar **);
    void (*endElementNs)(void *, const xmlChar *, const xmlChar *, const xmlChar *);
    void (*serror)(void *, xmlError *);
} xmlSAXHandler;

#define XML_SAX2_MAGIC 0xDEEDBEAF
#define XML_PARSE_NOENT (1 << 1)
#define XML_PARSE_DTDLOAD (1 << 2)
#define XML_PARSE_NONET (1 << 11)
#define XML_PARSE_BIG_LINES (1 << 22)
#define XML_FROM_NAMESPACE 3
#define XML_ERR_ERROR 2

typedef void (*generic_error_fn)(void *, const char *, ...);

static struct {
    BOOL tried, ok;
    xmlCtxt *(*createPush)(xmlSAXHandler *, void *, const char *, int, const char *);
    int (*useOptions)(xmlCtxt *, int);
    int (*parseChunk)(xmlCtxt *, const char *, int, int);
    void (*freeCtxt)(xmlCtxt *);
    void (*stop)(xmlCtxt *);
    void (*freeDoc)(void *);
    int (*line)(void *);
    int (*column)(void *);
    void (*sax2InternalSubset)(void *, const xmlChar *, const xmlChar *, const xmlChar *);
    void *(*sax2GetEntity)(void *, const xmlChar *);
    void *(*sax2GetParameterEntity)(void *, const xmlChar *);
    void (*sax2EntityDecl)(void *, const xmlChar *, int, const xmlChar *, const xmlChar *, xmlChar *);
    void (*sax2StartDocument)(void *);
    generic_error_fn *(*genericError)(void);
    void **(*genericErrorContext)(void);
} lx;

static BOOL load_libxml2(void)
{
    if (lx.tried)
        return lx.ok;
    lx.tried = YES;
    const char *lib = "/usr/lib/libxml2.2.dylib";
#define LOAD(field, name) *(void **)&lx.field = ferry_twin_symbol(lib, name)
    LOAD(createPush, "xmlCreatePushParserCtxt");
    LOAD(useOptions, "xmlCtxtUseOptions");
    LOAD(parseChunk, "xmlParseChunk");
    LOAD(freeCtxt, "xmlFreeParserCtxt");
    LOAD(stop, "xmlStopParser");
    LOAD(freeDoc, "xmlFreeDoc");
    LOAD(line, "xmlSAX2GetLineNumber");
    LOAD(column, "xmlSAX2GetColumnNumber");
    LOAD(sax2InternalSubset, "xmlSAX2InternalSubset");
    LOAD(sax2GetEntity, "xmlSAX2GetEntity");
    LOAD(sax2GetParameterEntity, "xmlSAX2GetParameterEntity");
    LOAD(sax2EntityDecl, "xmlSAX2EntityDecl");
    LOAD(sax2StartDocument, "xmlSAX2StartDocument");
    LOAD(genericError, "__xmlGenericError");
    LOAD(genericErrorContext, "__xmlGenericErrorContext");
#undef LOAD
    lx.ok = lx.createPush && lx.useOptions && lx.parseChunk && lx.freeCtxt && lx.stop && lx.freeDoc && lx.line &&
            lx.column && lx.sax2InternalSubset && lx.sax2GetEntity && lx.sax2EntityDecl && lx.sax2StartDocument;
    return lx.ok;
}

NSString *const NSXMLParserErrorDomain = @"NSXMLParserErrorDomain";

@interface NSXMLParser () {
@public
    NSData *_data;
    id _delegate;
    BOOL _namespaces, _prefixes, _external;
    NSXMLParserExternalEntityResolvingPolicy _policy;
    NSSet *_allowed;
    NSError *_error;
    xmlCtxt *_ctxt;
    void *_current; /* the context of the callback being served */
    BOOL _parsing, _aborted, _stopped;
    NSInteger _line, _column;
    NSMutableArray *_mappings; /* per open element: the prefixes it mapped */
    NSString *_publicID, *_systemID;
}
@end

/* The parsers parsing now, innermost last (a delegate may parse another
 * document from inside a callback). libxml2 hands each callback its parser
 * context, or the context of an entity's text being parsed inside it. */
static pthread_key_t active_key; /* each thread's own list */
static void free_active(void *list) { [(NSMutableArray *)list release]; }
static NSMutableArray *active_list(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      pthread_key_create(&active_key, free_active);
    });
    NSMutableArray *list = pthread_getspecific(active_key);
    if (!list) {
        list = [[NSMutableArray alloc] init];
        pthread_setspecific(active_key, list);
    }
    return list;
}

static NSXMLParser *parser_for(void *ctx)
{
    NSMutableArray *active = active_list();
    NSXMLParser *p = [active lastObject];
    for (NSXMLParser *q in active)
        if (q->_ctxt == ctx)
            p = q;
    if (p)
        p->_current = ctx;
    return (p && !p->_stopped) ? p : nil;
}

static NSString *str(const xmlChar *s) { return s ? [NSString stringWithUTF8String:(const char *)s] : nil; }
static NSString *str_len(const xmlChar *s, int n)
{
    return [[[NSString alloc] initWithBytes:s length:n encoding:NSUTF8StringEncoding] autorelease];
}

/* libxml2 keeps "&" in an attribute's value as "&#38;" when it doesn't
 * expand entities itself (it leaves that to the tree builder). */
static NSString *attribute_value(const xmlChar *v, int n)
{
    NSString *s = str_len(v, n);
    if ([s rangeOfString:@"&#38;"].location != NSNotFound)
        s = [s stringByReplacingOccurrencesOfString:@"&#38;" withString:@"&"];
    return s;
}

#define TELL(p, sel) ((p)->_delegate && [(p)->_delegate respondsToSelector:@selector(sel)])

static void sax_start_document(void *ctx)
{
    NSXMLParser *p = parser_for(ctx);
    lx.sax2StartDocument(ctx); /* the document the DTD's entities are kept in */
    if (p && TELL(p, parserDidStartDocument:))
        [p->_delegate parserDidStartDocument:p];
}
static void sax_end_document(void *ctx)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parserDidEndDocument:))
        [p->_delegate parserDidEndDocument:p];
}
static void sax_internal_subset(void *ctx, const xmlChar *name, const xmlChar *ext, const xmlChar *sys)
{
    NSXMLParser *p = parser_for(ctx);
    if (p) {
        [p->_publicID release];
        p->_publicID = [str(ext) copy];
        [p->_systemID release];
        p->_systemID = [str(sys) copy];
    }
    lx.sax2InternalSubset(ctx, name, ext, sys);
}
static void *sax_get_entity(void *ctx, const xmlChar *name) { return lx.sax2GetEntity(ctx, name); }
static void *sax_get_parameter_entity(void *ctx, const xmlChar *name)
{
    return lx.sax2GetParameterEntity ? lx.sax2GetParameterEntity(ctx, name) : NULL;
}
static void sax_entity_decl(void *ctx, const xmlChar *name, int type, const xmlChar *pub, const xmlChar *sys,
                            xmlChar *content)
{
    NSXMLParser *p = parser_for(ctx);
    lx.sax2EntityDecl(ctx, name, type, pub, sys, content);
    if (!p)
        return;
    if (type == 1 && TELL(p, parser:foundInternalEntityDeclarationWithName:value:))
        [p->_delegate parser:p foundInternalEntityDeclarationWithName:str(name) value:str(content)];
    else if (type == 2 && TELL(p, parser:foundExternalEntityDeclarationWithName:publicID:systemID:))
        [p->_delegate parser:p foundExternalEntityDeclarationWithName:str(name) publicID:str(pub) systemID:str(sys)];
}
static void sax_notation_decl(void *ctx, const xmlChar *name, const xmlChar *pub, const xmlChar *sys)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundNotationDeclarationWithName:publicID:systemID:))
        [p->_delegate parser:p foundNotationDeclarationWithName:str(name) publicID:str(pub) systemID:str(sys)];
}
static void sax_unparsed_entity_decl(void *ctx, const xmlChar *name, const xmlChar *pub, const xmlChar *sys,
                                     const xmlChar *notation)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundUnparsedEntityDeclarationWithName:publicID:systemID:notationName:))
        [p->_delegate parser:p
            foundUnparsedEntityDeclarationWithName:str(name)
                                          publicID:str(pub)
                                          systemID:str(sys)
                                      notationName:str(notation)];
}

static NSString *qualified(const xmlChar *prefix, const xmlChar *local)
{
    return prefix ? [NSString stringWithFormat:@"%s:%s", prefix, local] : str(local);
}

static void sax_start_element(void *ctx, const xmlChar *local, const xmlChar *prefix, const xmlChar *uri, int nns,
                              const xmlChar **ns, int nattrs, int ndefaulted, const xmlChar **attrs)
{
    NSXMLParser *p = parser_for(ctx);
    if (!p)
        return;
    @autoreleasepool {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        NSMutableArray *mapped = [NSMutableArray array];
        for (int i = 0; i < nns; i++) {
            const xmlChar *pre = ns[2 * i], *u = ns[2 * i + 1];
            if (!p->_namespaces)
                [dict setObject:str(u) ?: @"" forKey:pre ? [NSString stringWithFormat:@"xmlns:%s", pre] : @"xmlns"];
            else if (p->_prefixes) {
                NSString *ps = str(pre) ?: @"";
                [mapped addObject:ps];
                if (TELL(p, parser:didStartMappingPrefix:toURI:))
                    [p->_delegate parser:p didStartMappingPrefix:ps toURI:str(u) ?: @""];
                if (p->_stopped)
                    return;
            }
        }
        for (int i = 0; i < nattrs; i++) {
            const xmlChar **a = attrs + 5 * i; /* local name, prefix, URI, value, end of value */
            [dict setObject:attribute_value(a[3], (int)(a[4] - a[3])) forKey:qualified(a[1], a[0])];
        }
        [p->_mappings addObject:mapped];
        if (!TELL(p, parser:didStartElement:namespaceURI:qualifiedName:attributes:))
            return;
        if (p->_namespaces)
            [p->_delegate parser:p
                 didStartElement:str(local)
                    namespaceURI:str(uri)
                   qualifiedName:qualified(prefix, local)
                      attributes:dict];
        else
            [p->_delegate parser:p
                 didStartElement:qualified(prefix, local)
                    namespaceURI:nil
                   qualifiedName:nil
                      attributes:dict];
    }
}
static void sax_end_element(void *ctx, const xmlChar *local, const xmlChar *prefix, const xmlChar *uri)
{
    NSXMLParser *p = parser_for(ctx);
    if (!p)
        return;
    @autoreleasepool {
        NSArray *mapped = [[[p->_mappings lastObject] retain] autorelease];
        if ([p->_mappings count])
            [p->_mappings removeLastObject];
        if (TELL(p, parser:didEndElement:namespaceURI:qualifiedName:)) {
            if (p->_namespaces)
                [p->_delegate parser:p
                       didEndElement:str(local)
                        namespaceURI:str(uri)
                       qualifiedName:qualified(prefix, local)];
            else
                [p->_delegate parser:p didEndElement:qualified(prefix, local) namespaceURI:nil qualifiedName:nil];
        }
        if (TELL(p, parser:didEndMappingPrefix:))
            for (NSString *pre in mapped)
                if (!p->_stopped)
                    [p->_delegate parser:p didEndMappingPrefix:pre];
    }
}
static void sax_characters(void *ctx, const xmlChar *ch, int len)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundCharacters:)) {
        @autoreleasepool {
            [p->_delegate parser:p foundCharacters:str_len(ch, len)];
        }
    }
}
static void sax_ignorable(void *ctx, const xmlChar *ch, int len)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundIgnorableWhitespace:)) {
        @autoreleasepool {
            [p->_delegate parser:p foundIgnorableWhitespace:str_len(ch, len)];
        }
    }
}
static void sax_pi(void *ctx, const xmlChar *target, const xmlChar *data)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundProcessingInstructionWithTarget:data:)) {
        @autoreleasepool {
            [p->_delegate parser:p foundProcessingInstructionWithTarget:str(target) data:str(data)];
        }
    }
}
static void sax_comment(void *ctx, const xmlChar *value)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundComment:)) {
        @autoreleasepool {
            [p->_delegate parser:p foundComment:str(value)];
        }
    }
}
static void sax_cdata(void *ctx, const xmlChar *value, int len)
{
    NSXMLParser *p = parser_for(ctx);
    if (p && TELL(p, parser:foundCDATA:)) {
        @autoreleasepool {
            [p->_delegate parser:p foundCDATA:[NSData dataWithBytes:value length:len]];
        }
    }
}
static void sax_error(void *ctx, xmlError *e)
{
    NSXMLParser *p = parser_for(ctx);
    if (!p || !e || e->level < XML_ERR_ERROR)
        return;
    if (e->domain == XML_FROM_NAMESPACE && !p->_namespaces)
        return; /* namespaces aren't being processed */
    NSString *message = e->message ? [NSString stringWithUTF8String:e->message] : @"";
    NSDictionary *info = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:e->line], @"NSXMLParserErrorLineNumber",
                                     [NSNumber numberWithInt:e->int2], @"NSXMLParserErrorColumn", message,
                                     @"NSXMLParserErrorMessage", nil];
    p->_error = [[NSError alloc] initWithDomain:NSXMLParserErrorDomain code:e->code userInfo:info];
    p->_line = e->line;
    p->_column = e->int2;
    p->_stopped = YES;
    lx.stop(p->_ctxt);
    if (TELL(p, parser:parseErrorOccurred:))
        [p->_delegate parser:p parseErrorOccurred:p->_error];
}
static void quiet(void *ctx, const char *msg, ...) {}

static xmlSAXHandler handler = {
    .internalSubset = sax_internal_subset,
    .getEntity = sax_get_entity,
    .entityDecl = sax_entity_decl,
    .notationDecl = sax_notation_decl,
    .unparsedEntityDecl = sax_unparsed_entity_decl,
    .startDocument = sax_start_document,
    .endDocument = sax_end_document,
    .characters = sax_characters,
    .ignorableWhitespace = sax_ignorable,
    .processingInstruction = sax_pi,
    .comment = sax_comment,
    .warning = quiet,
    .error = quiet,
    .fatalError = quiet,
    .getParameterEntity = sax_get_parameter_entity,
    .cdataBlock = sax_cdata,
    .initialized = XML_SAX2_MAGIC,
    .startElementNs = sax_start_element,
    .endElementNs = sax_end_element,
    .serror = sax_error,
};

@implementation NSXMLParser
- (instancetype)initWithData:(NSData *)data
{
    if (!(self = [super init]))
        return nil;
    _data = [data copy];
    _policy = NSXMLParserResolveExternalEntitiesNever;
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url
{
    NSData *data = [NSData dataWithContentsOfURL:url];
    return [self initWithData:data];
}
- (instancetype)init { return [self initWithData:nil]; }
- (void)dealloc
{
    [_data release];
    [_allowed release];
    [_error release];
    [_mappings release];
    [_publicID release];
    [_systemID release];
    [super dealloc];
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (BOOL)shouldProcessNamespaces { return _namespaces; }
- (void)setShouldProcessNamespaces:(BOOL)flag { _namespaces = flag; }
- (BOOL)shouldReportNamespacePrefixes { return _prefixes; }
- (void)setShouldReportNamespacePrefixes:(BOOL)flag { _prefixes = flag; }
- (BOOL)shouldResolveExternalEntities { return _external; }
- (void)setShouldResolveExternalEntities:(BOOL)flag { _external = flag; }
- (NSXMLParserExternalEntityResolvingPolicy)externalEntityResolvingPolicy { return _policy; }
- (void)setExternalEntityResolvingPolicy:(NSXMLParserExternalEntityResolvingPolicy)p { _policy = p; }
- (NSSet *)allowedExternalEntityURLs { return _allowed; }
- (void)setAllowedExternalEntityURLs:(NSSet *)urls
{
    urls = [urls copy];
    [_allowed release];
    _allowed = urls;
}
- (NSError *)parserError { return _error; }
- (NSString *)publicID { return _publicID; }
- (NSString *)systemID { return _systemID; }
- (NSInteger)lineNumber
{
    if (_parsing && _current && !_error)
        return lx.line(_current);
    return _line;
}
- (NSInteger)columnNumber
{
    if (_parsing && _current && !_error)
        return lx.column(_current);
    return _column;
}

- (void)abortParsing
{
    if (!_parsing || _stopped)
        return;
    _aborted = _stopped = YES;
    [_error release];
    _error = [[NSError alloc] initWithDomain:NSXMLParserErrorDomain
                                        code:NSXMLParserDelegateAbortedParseError
                                    userInfo:nil];
    _line = lx.line(_current ? _current : _ctxt);
    _column = lx.column(_current ? _current : _ctxt);
    lx.stop(_ctxt);
    if (TELL(self, parser:parseErrorOccurred:))
        [_delegate parser:self parseErrorOccurred:_error];
}

- (BOOL)parse
{
    if (_parsing)
        return NO;
    [_error release];
    _error = nil;
    _aborted = _stopped = NO;
    if (!load_libxml2()) {
        _error = [[NSError alloc] initWithDomain:NSXMLParserErrorDomain code:NSXMLParserInternalError userInfo:nil];
        return NO;
    }
    if (![_data length]) { /* libxml2's "Document is empty", without a parse */
        _error = [[NSError alloc]
            initWithDomain:NSXMLParserErrorDomain
                      code:NSXMLParserEmptyDocumentError
                  userInfo:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1],
                                                                      @"NSXMLParserErrorLineNumber",
                                                                      [NSNumber numberWithInt:1],
                                                                      @"NSXMLParserErrorColumn",
                                                                      @"Document is empty\n",
                                                                      @"NSXMLParserErrorMessage", nil]];
        _line = _column = 1;
        if (TELL(self, parser:parseErrorOccurred:))
            [_delegate parser:self parseErrorOccurred:_error];
        return NO;
    }
    [self retain];
    [_mappings release];
    _mappings = [[NSMutableArray alloc] init];
    [active_list() addObject:self];
    _parsing = YES;

    /* libxml2's messages go to the error callback, not the terminal */
    generic_error_fn saved_fn = NULL;
    void *saved_ctx = NULL;
    if (lx.genericError && lx.genericErrorContext) {
        saved_fn = *lx.genericError();
        saved_ctx = *lx.genericErrorContext();
        *lx.genericError() = quiet;
    }
    const char *bytes = [_data bytes];
    NSUInteger len = [_data length], first = len < 4 ? len : 4;
    _ctxt = lx.createPush(&handler, NULL, bytes, (int)first, NULL);
    if (!_ctxt) {
        _error = [[NSError alloc] initWithDomain:NSXMLParserErrorDomain code:NSXMLParserOutOfMemoryError userInfo:nil];
    } else {
        int options = XML_PARSE_NONET | XML_PARSE_BIG_LINES;
        if (_external) /* from files only: XML_PARSE_NONET stays */
            options |= XML_PARSE_NOENT | XML_PARSE_DTDLOAD;
        lx.useOptions(_ctxt, options);
        NSUInteger at = first;
        do {
            NSUInteger n = len - at > 65536 ? 65536 : len - at;
            lx.parseChunk(_ctxt, bytes ? bytes + at : "", (int)n, at + n >= len);
            at += n;
        } while (at < len && !_stopped);
        if (!_error) {
            _line = lx.line(_ctxt);
            _column = lx.column(_ctxt);
        }
        void **doc = (void **)_ctxt + 2; /* xmlParserCtxt's myDoc: the DTD's entities */
        if (*doc) {
            lx.freeDoc(*doc);
            *doc = NULL;
        }
        lx.freeCtxt(_ctxt);
        _ctxt = NULL;
    }
    if (lx.genericError && lx.genericErrorContext) {
        *lx.genericError() = saved_fn;
        *lx.genericErrorContext() = saved_ctx;
    }
    _current = NULL;
    _parsing = NO;
    [active_list() removeObjectIdenticalTo:self];
    BOOL ok = _error == nil;
    [self release];
    return ok;
}
@end
