/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSXMLDocument and the tree around it: parsing (strings, data,
 * files), the nodes' kinds, names, values and places, namespaces,
 * attributes, changing the tree, writing it out (compact, pretty, as data in
 * another encoding), XPath on a tree that was changed, canonical XML, DTDs,
 * copies, errors, and a document class that makes its own elements. */
#import <Foundation/Foundation.h>

static void show(NSString *label, id value) { printf("%s: %s\n", [label UTF8String], [[value description] UTF8String]); }

static const char *kind_name(NSXMLNodeKind k)
{
    static const char *names[] = {"invalid", "document", "element", "attribute", "namespace", "pi", "comment",
                                  "text", "dtd", "entity-decl", "attribute-decl", "element-decl", "notation-decl"};
    return k <= NSXMLNotationDeclarationKind ? names[k] : "?";
}

static void walk(NSXMLNode *n)
{
    for (int i = 0; i < (int)[n level]; i++)
        printf("  ");
    printf("%s", kind_name([n kind]));
    if ([n name])
        printf(" name=%s", [[n name] UTF8String]);
    if ([n kind] == NSXMLElementKind) {
        NSXMLElement *e = (NSXMLElement *)n;
        printf(" local=%s prefix=\"%s\" uri=%s", [[e localName] UTF8String], [[e prefix] UTF8String],
               [e URI] ? [[e URI] UTF8String] : "-");
        for (NSXMLNode *ns in [e namespaces])
            printf(" ns[%s]=%s", [[ns name] UTF8String], [[ns stringValue] UTF8String]);
        for (NSXMLNode *a in [e attributes])
            printf(" @%s=%s%s%s", [[a name] UTF8String], [[a stringValue] UTF8String], [a URI] ? " in " : "",
                   [a URI] ? [[a URI] UTF8String] : "");
    } else if ([n kind] != NSXMLDocumentKind)
        printf(" value=\"%s\"%s", [[n stringValue] UTF8String], ([n options] & NSXMLNodeIsCDATA) ? " (cdata)" : "");
    printf(" index=%lu\n", (unsigned long)[n index]);
    for (NSXMLNode *c in [n children])
        walk(c);
}

static void xpath(NSXMLNode *context, NSString *expr)
{
    NSError *error = nil;
    NSArray *nodes = [context nodesForXPath:expr error:&error];
    if (!nodes) {
        printf("xpath %s: error %ld\n", [expr UTF8String], (long)[error code]);
        return;
    }
    printf("xpath %s: %lu\n", [expr UTF8String], (unsigned long)[nodes count]);
    for (NSXMLNode *n in nodes)
        printf("  %s %s = %s\n", kind_name([n kind]), [[n XPath] UTF8String], [[n XMLString] UTF8String]);
}

@interface Book : NSXMLElement
@end
@implementation Book
@end
@interface Library : NSXMLDocument
@end
@implementation Library
+ (Class)replacementClassForClass:(Class)cls
{
    return cls == [NSXMLElement class] ? [Book class] : [super replacementClassForClass:cls];
}
@end

int main(void)
{
    @autoreleasepool {
        NSError *error = nil;
        NSString *source = @"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
                            "<!-- a catalogue -->\n"
                            "<catalog xmlns=\"urn:books\" xmlns:p=\"urn:prices\" version=\"2\">\n"
                            "  <book id=\"b1\" p:currency=\"EUR\">\n"
                            "    <title>Dune &amp; more</title>\n"
                            "    <p:price>9.50</p:price>\n"
                            "  </book>\n"
                            "  <?render fast?>\n"
                            "  <book id=\"b2\"><title>Emma</title><note>A <b>fine</b> novel</note></book>\n"
                            "</catalog>\n";
        NSXMLDocument *doc = [[[NSXMLDocument alloc] initWithXMLString:source options:0 error:&error] autorelease];
        printf("== parse\n");
        show(@"error", error);
        show(@"version", [doc version]);
        show(@"encoding", [doc characterEncoding]);
        printf("standalone: %d, kind %s, children %lu\n", [doc isStandalone], kind_name([doc kind]),
               (unsigned long)[doc childCount]);
        walk(doc);
        NSXMLElement *root = [doc rootElement];
        show(@"root string value", [root stringValue]);
        show(@"root document is doc", [NSNumber numberWithBool:[root rootDocument] == doc]);
        NSXMLElement *book = [[root elementsForName:@"book"] objectAtIndex:0];
        show(@"next sibling", [[book nextSibling] XMLString]);
        show(@"previous sibling", [[book previousSibling] XMLString]);
        show(@"next node", [[book nextNode] XMLString]);
        show(@"previous node of the price", [[[[book children] lastObject] previousNode] XMLString]);
        show(@"attribute id", [[book attributeForName:@"id"] stringValue]);
        show(@"attribute by local name and URI", [[book attributeForLocalName:@"currency" URI:@"urn:prices"] XMLString]);
        show(@"elementsForName p:price", [[[book elementsForName:@"p:price"] lastObject] XMLString]);
        show(@"elementsForLocalName", [NSNumber numberWithUnsignedInteger:[[book elementsForLocalName:@"price"
                                                                                                   URI:@"urn:prices"] count]]);
        show(@"resolve p", [[book resolveNamespaceForName:@"p:x"] stringValue]);
        show(@"resolve default", [[book resolveNamespaceForName:@"x"] stringValue]);
        show(@"prefix for urn:prices", [book resolvePrefixForNamespaceURI:@"urn:prices"]);
        show(@"prefix for the xml namespace", [book resolvePrefixForNamespaceURI:@"http://www.w3.org/XML/1998/namespace"]);
        show(@"localName of p:price", [NSXMLNode localNameForName:@"p:price"]);
        show(@"prefix of p:price", [NSXMLNode prefixForName:@"p:price"]);

        printf("== writing\n");
        printf("%s\n", [[doc XMLString] UTF8String]);
        printf("%s\n", [[doc XMLStringWithOptions:NSXMLNodePrettyPrint] UTF8String]);
        printf("%s\n", [[book XMLStringWithOptions:NSXMLNodeCompactEmptyElement | NSXMLNodeUseSingleQuotes] UTF8String]);

        printf("== xpath\n");
        xpath(doc, @"//*[local-name()='title']");
        xpath(doc, @"//p:price");
        xpath(doc, @"//@id");
        xpath(book, @"@p:currency");
        xpath(root, @"processing-instruction()");
        xpath(doc, @"/comment()");
        xpath(doc, @"/");
        xpath(book, @"namespace::*");
        xpath(doc, @"count(//*)");
        xpath(doc, @"//[");

        printf("== changing the tree\n");
        NSXMLElement *added = [NSXMLElement elementWithName:@"book"];
        [added addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:@"b3"]];
        [added addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:@"ignored"]];
        [added addAttribute:[NSXMLNode attributeWithName:@"lang" stringValue:@"fr & \"en\"\n"]];
        [added addChild:[NSXMLElement elementWithName:@"title" stringValue:@"Les <Mis\xc3\xa9rables>"]];
        [added addChild:[NSXMLNode commentWithStringValue:@" new "]];
        [root insertChild:added atIndex:0];
        printf("added: %s\n", [[added XMLString] UTF8String]);
        xpath(doc, @"//*[local-name()='book']/@id");
        [root removeChildAtIndex:[[root children] indexOfObject:book]];
        show(@"removed book has no parent", [NSNumber numberWithBool:[book parent] == nil]);
        xpath(doc, @"//*[local-name()='book']/@id");
        [added removeAttributeForName:@"lang"];
        [[added attributeForName:@"id"] setStringValue:@"b3!"];
        [(NSXMLElement *)[added childAtIndex:0] setStringValue:@"Germinal"];
        xpath(doc, @"//*[local-name()='title'][.='Germinal']/../@id");
        [added setChildren:[NSArray arrayWithObjects:[NSXMLNode textWithStringValue:@"a"],
                                                     [NSXMLNode textWithStringValue:@"b"], nil]];
        show(@"two text nodes", [NSNumber numberWithUnsignedInteger:[added childCount]]);
        [added normalizeAdjacentTextNodesPreservingCDATA:NO];
        show(@"after normalizing", [added XMLString]);
        [added replaceChildAtIndex:0 withNode:[NSXMLNode processingInstructionWithName:@"go" stringValue:@""]];
        [added insertChildren:[NSArray arrayWithObjects:[NSXMLElement elementWithName:@"x"],
                                                        [NSXMLElement elementWithName:@"y"], nil]
                      atIndex:1];
        show(@"replaced and inserted", [added XMLString]);
        NSXMLElement *x = (NSXMLElement *)[added childAtIndex:1];
        [x addNamespace:[NSXMLNode namespaceWithName:@"q" stringValue:@"urn:q"]];
        [x addChild:[NSXMLElement elementWithName:@"q:z" URI:@"urn:q"]];
        [x addChild:[NSXMLElement elementWithName:@"q:w"]];
        show(@"q:w resolves its URI", [[[x children] lastObject] URI]);
        xpath(doc, @"//q:*");
        [[x childAtIndex:0] detach];
        xpath(doc, @"//q:*");
        @try {
            [root addChild:[added childAtIndex:0]];
            printf("added a node that has a parent\n");
        } @catch (NSException *e) {
            printf("exception %s\n", [[e name] UTF8String]);
        }
        @try {
            [root addChild:[NSXMLNode attributeWithName:@"a" stringValue:@"b"]];
            printf("added an attribute as a child\n");
        } @catch (NSException *e) {
            printf("exception %s\n", [[e name] UTF8String]);
        }
        printf("%s\n", [[doc XMLStringWithOptions:NSXMLNodePrettyPrint] UTF8String]);

        printf("== building\n");
        NSXMLElement *list = [NSXMLNode elementWithName:@"list"
                                               children:[NSArray arrayWithObjects:
                                                                     [NSXMLNode elementWithName:@"item" stringValue:@"1"],
                                                                     [NSXMLNode elementWithName:@"empty"], nil]
                                             attributes:[NSArray arrayWithObject:[NSXMLNode attributeWithName:@"n"
                                                                                                  stringValue:@"2"]]];
        NSXMLDocument *built = [NSXMLDocument documentWithRootElement:list];
        printf("%s\n", [[built XMLString] UTF8String]);
        [built setVersion:@"1.0"];
        [built setCharacterEncoding:@"ISO-8859-1"];
        [[list childAtIndex:0] setStringValue:@"caf\xc3\xa9 \xe2\x82\xac"];
        NSData *latin = [built XMLData];
        printf("latin-1 data: %lu bytes, %s\n", (unsigned long)[latin length],
               [[[[NSString alloc] initWithData:latin encoding:NSISOLatin1StringEncoding] autorelease] UTF8String]);
        [built setCharacterEncoding:@"US-ASCII"];
        printf("ascii: %s\n", [[[[NSString alloc] initWithData:[built XMLData]
                                                       encoding:NSASCIIStringEncoding] autorelease] UTF8String]);
        [built setCharacterEncoding:@"UTF-16"];
        NSData *utf16 = [built XMLData];
        NSXMLDocument *back = [[[NSXMLDocument alloc] initWithData:utf16 options:0 error:NULL] autorelease];
        printf("utf-16: %lu bytes, read back as %s: %s\n", (unsigned long)[utf16 length],
               [[back characterEncoding] UTF8String], [[[back rootElement] XMLString] UTF8String]);
        [built setRootElement:[NSXMLElement elementWithName:@"other"]];
        printf("new root: %s, list parent %s\n", [[built XMLString] UTF8String], [list parent] ? "set" : "nil");
        NSXMLNode *number = [NSXMLNode attributeWithName:@"count" stringValue:@""];
        [number setObjectValue:[NSNumber numberWithInt:42]];
        NSXMLNode *date = [NSXMLNode textWithStringValue:@""];
        [date setObjectValue:[NSDate dateWithTimeIntervalSince1970:86400 * 365]];
        NSXMLNode *yes = [NSXMLNode attributeWithName:@"ok" stringValue:@""];
        [yes setObjectValue:[NSNumber numberWithBool:YES]];
        printf("object values: %s %s %s\n", [[number XMLString] UTF8String], [[date stringValue] UTF8String],
               [[yes XMLString] UTF8String]);
        NSXMLNode *ent = [NSXMLNode textWithStringValue:@""];
        [ent setStringValue:@"a &lt; b &#x263A; &amp;c" resolvingEntities:YES];
        printf("resolved: %s\n", [[ent stringValue] UTF8String]);
        NSXMLNode *cdata = [[[NSXMLNode alloc] initWithKind:NSXMLTextKind options:NSXMLNodeIsCDATA] autorelease];
        [cdata setStringValue:@"x]]>y"];
        printf("cdata: %s\n", [[cdata XMLString] UTF8String]);
        NSXMLNode *generic = [[[NSXMLNode alloc] initWithKind:NSXMLElementKind] autorelease];
        printf("element from NSXMLNode: %s\n", [generic isKindOfClass:[NSXMLElement class]] ? "NSXMLElement" : "no");

        printf("== element from a string\n");
        NSXMLElement *parsed = [[[NSXMLElement alloc] initWithXMLString:@"<a k='v'><b/>t</a>" error:&error] autorelease];
        printf("%s parent=%s\n", [[parsed XMLString] UTF8String], [parsed parent] ? "set" : "nil");
        NSXMLElement *copy = [[parsed copy] autorelease];
        [[copy attributeForName:@"k"] setStringValue:@"w"];
        printf("copy %s, original %s\n", [[copy XMLString] UTF8String], [[parsed XMLString] UTF8String]);
        xpath(parsed, @"b");
        xpath(parsed, @"/a/text()");

        printf("== options\n");
        NSString *spaced = @"<r>\n  <a>  x  </a>\n  <b> </b>\n  <![CDATA[<c>]]>\n</r>";
        NSXMLDocument *d1 = [[[NSXMLDocument alloc] initWithXMLString:spaced options:0 error:NULL] autorelease];
        NSXMLDocument *d2 = [[[NSXMLDocument alloc] initWithXMLString:spaced
                                                              options:NSXMLNodePreserveWhitespace | NSXMLNodePreserveCDATA
                                                                error:NULL] autorelease];
        printf("default:  %s\n", [[d1 XMLString] UTF8String]);
        printf("preserve: %s\n", [[d2 XMLString] UTF8String]);
        show(@"version without a declaration", [d1 version]);
        error = nil;
        NSXMLDocument *broken = [[[NSXMLDocument alloc] initWithXMLString:@"<a><b>text</a>" options:0
                                                                    error:&error] autorelease];
        printf("broken: %s, error %ld: %s\n", broken ? "parsed" : "nil", (long)[error code],
               [[error localizedDescription] UTF8String]);
        NSXMLDocument *tidied = [[[NSXMLDocument alloc] initWithXMLString:@"<a><b>text</a>"
                                                                  options:NSXMLDocumentTidyXML
                                                                    error:NULL] autorelease];
        printf("tidied: %s\n", [[tidied XMLString] UTF8String]);
        error = nil;
        NSXMLDocument *empty = [[[NSXMLDocument alloc] initWithXMLString:@"" options:0 error:&error] autorelease];
        printf("empty: %s, error %ld\n", empty ? "parsed" : "nil", (long)[error code]);
        NSString *invalid = @"<!DOCTYPE r [<!ELEMENT r (a)><!ELEMENT a EMPTY>]><r><b/></r>";
        error = nil;
        NSXMLDocument *v1 = [[[NSXMLDocument alloc] initWithXMLString:invalid options:0 error:&error] autorelease];
        NSXMLDocument *v2 = [[[NSXMLDocument alloc] initWithXMLString:invalid options:NSXMLDocumentValidate
                                                                error:&error] autorelease];
        printf("not validated: %s, validated: %s (error %ld)\n", v1 ? "parsed" : "nil", v2 ? "parsed" : "nil",
               (long)[error code]);

        printf("== DTD\n");
        NSString *withDTD = @"<!DOCTYPE note PUBLIC \"-//Ferry//Note//EN\" \"note.dtd\" [\n"
                             "<!ENTITY who \"the world\">\n<!ELEMENT note (#PCDATA)>\n"
                             "<!ATTLIST note kind CDATA \"plain\">\n]>\n<note>Hello &who;</note>";
        NSXMLDocument *nd = [[[NSXMLDocument alloc] initWithXMLString:withDTD options:0 error:&error] autorelease];
        NSXMLDTD *dtd = [nd DTD];
        printf("dtd %s public %s system %s, %lu declarations\n", [[dtd name] UTF8String], [[dtd publicID] UTF8String],
               [[dtd systemID] UTF8String], (unsigned long)[dtd childCount]);
        for (NSXMLDTDNode *decl in [dtd children])
            printf("  %s %s kind %lu value \"%s\": %s\n", kind_name([decl kind]), [[decl name] UTF8String],
                   (unsigned long)[decl DTDKind], [[decl stringValue] UTF8String], [[decl XMLString] UTF8String]);
        show(@"entity", [[dtd entityDeclarationForName:@"who"] stringValue]);
        show(@"attribute declaration", [[dtd attributeDeclarationForName:@"kind" elementName:@"note"] XMLString]);
        show(@"text", [[nd rootElement] stringValue]);
        printf("%s\n", [[nd XMLString] UTF8String]);
        NSXMLDTDNode *made = [NSXMLNode DTDNodeWithXMLString:@"<!ENTITY logo SYSTEM \"logo.png\" NDATA png>"];
        printf("made: %s kind %lu notation %s external %d\n", [[made XMLString] UTF8String],
               (unsigned long)[made DTDKind], [[made notationName] UTF8String], [made isExternal]);
        [[dtd entityDeclarationForName:@"who"] setStringValue:@"everyone"];
        show(@"changed entity", [[dtd entityDeclarationForName:@"who"] XMLString]);
        show(@"predefined", [[NSXMLDTD predefinedEntityDeclarationForName:@"amp"] stringValue]);

        printf("== canonical\n");
        NSXMLDocument *cd = [[[NSXMLDocument alloc]
            initWithXMLString:@"<?xml version=\"1.0\"?><r xmlns:z='urn:z' b='2' a='1'><!--c--><z:e/></r>"
                      options:0
                        error:NULL] autorelease];
        printf("%s\n", [[cd canonicalXMLStringPreservingComments:YES] UTF8String]);
        printf("%s\n", [[cd canonicalXMLStringPreservingComments:NO] UTF8String]);
        printf("%s\n", [[[[cd rootElement] childAtIndex:1] canonicalXMLStringPreservingComments:NO] UTF8String]);

        printf("== data and files\n");
        unsigned char latinBytes[] = "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><w>na\xefve</w>";
        NSXMLDocument *ld = [[[NSXMLDocument alloc] initWithData:[NSData dataWithBytes:latinBytes
                                                                                length:sizeof latinBytes - 1]
                                                         options:0
                                                           error:&error] autorelease];
        printf("latin-1 in: %s (%s)\n", [[[ld rootElement] stringValue] UTF8String], [[ld characterEncoding] UTF8String]);
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-xmldocument-test.xml"];
        [[doc XMLData] writeToFile:path atomically:NO];
        NSXMLDocument *fd = [[[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                                  options:0
                                                                    error:&error] autorelease];
        printf("from the file: %s, same text %d\n", fd ? "parsed" : "nil",
               [[fd XMLString] isEqualToString:[doc XMLString]]);
        printf("file URI is a file URL: %d\n", [[fd URI] hasPrefix:@"file://"]);
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        error = nil;
        NSXMLDocument *web = [[[NSXMLDocument alloc] initWithContentsOfURL:[NSURL URLWithString:@"http://example.com/a.xml"]
                                                                   options:0
                                                                     error:&error] autorelease];
        printf("from the web: %s, %s %ld\n", web ? "parsed" : "nil", [[error domain] UTF8String], (long)[error code]);

        printf("== replacement classes\n");
        Library *lib = [[[Library alloc] initWithXMLString:@"<shelf><book/></shelf>" options:0 error:NULL] autorelease];
        printf("%s %s %s\n", [NSStringFromClass([lib class]) UTF8String],
               [NSStringFromClass([[lib rootElement] class]) UTF8String],
               [NSStringFromClass([[[lib rootElement] childAtIndex:0] class]) UTF8String]);
    }
    return 0;
}
