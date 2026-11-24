/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test: NSXMLParser and its delegate: elements, attributes, text
 * (split where an entity is), CDATA, comments, processing instructions,
 * entities declared in the document, namespaces off and on, errors with
 * their line numbers, and a delegate that stops the parse. */
#import <Foundation/Foundation.h>

@interface Logger : NSObject <NSXMLParserDelegate>
@property int depth;
@property BOOL abortAtSecondItem;
@property int items;
@end

@implementation Logger
- (void)indent
{
    for (int i = 0; i < self.depth; i++)
        printf("  ");
}
- (void)parserDidStartDocument:(NSXMLParser *)parser { printf("start document\n"); }
- (void)parserDidEndDocument:(NSXMLParser *)parser { printf("end document\n"); }
- (void)parser:(NSXMLParser *)parser
    didStartElement:(NSString *)name
       namespaceURI:(NSString *)uri
      qualifiedName:(NSString *)qname
         attributes:(NSDictionary *)attrs
{
    [self indent];
    printf("<%s>", [name UTF8String]);
    if (uri)
        printf(" uri=%s", [uri UTF8String]);
    if (qname)
        printf(" qname=%s", [qname UTF8String]);
    for (NSString *k in [[attrs allKeys] sortedArrayUsingSelector:@selector(compare:)])
        printf(" %s=\"%s\"", [k UTF8String], [[attrs objectForKey:k] UTF8String]);
    printf(" (line %ld)\n", (long)[parser lineNumber]);
    self.depth++;
    if ([name isEqualToString:@"item"] && ++self.items == 2 && self.abortAtSecondItem) {
        printf("aborting\n");
        [parser abortParsing];
    }
}
- (void)parser:(NSXMLParser *)parser
    didEndElement:(NSString *)name
     namespaceURI:(NSString *)uri
    qualifiedName:(NSString *)qname
{
    self.depth--;
    [self indent];
    printf("</%s>\n", [name UTF8String]);
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)s
{
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![t length])
        return;
    [self indent];
    printf("text \"%s\"\n", [s UTF8String]);
}
- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)data
{
    [self indent];
    printf("cdata %lu bytes \"%.*s\"\n", (unsigned long)[data length], (int)[data length], (const char *)[data bytes]);
}
- (void)parser:(NSXMLParser *)parser foundComment:(NSString *)comment
{
    [self indent];
    printf("comment \"%s\"\n", [comment UTF8String]);
}
- (void)parser:(NSXMLParser *)parser foundProcessingInstructionWithTarget:(NSString *)target data:(NSString *)data
{
    [self indent];
    printf("processing instruction %s \"%s\"\n", [target UTF8String], [data UTF8String]);
}
- (void)parser:(NSXMLParser *)parser foundInternalEntityDeclarationWithName:(NSString *)name value:(NSString *)value
{
    printf("entity %s = \"%s\"\n", [name UTF8String], [value UTF8String]);
}
- (void)parser:(NSXMLParser *)parser didStartMappingPrefix:(NSString *)prefix toURI:(NSString *)uri
{
    [self indent];
    printf("map \"%s\" -> %s\n", [prefix UTF8String], [uri UTF8String]);
}
- (void)parser:(NSXMLParser *)parser didEndMappingPrefix:(NSString *)prefix
{
    [self indent];
    printf("unmap \"%s\"\n", [prefix UTF8String]);
}
- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)error
{
    printf("error %ld at line %ld\n", (long)[error code], (long)[parser lineNumber]);
}
@end

static void run(const char *title, NSString *xml, BOOL namespaces, BOOL abort)
{
    printf("-- %s\n", title);
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    Logger *l = [[Logger alloc] init];
    l.abortAtSecondItem = abort;
    [p setDelegate:l];
    [p setShouldProcessNamespaces:namespaces];
    [p setShouldReportNamespacePrefixes:namespaces];
    BOOL ok = [p parse];
    NSError *e = [p parserError];
    printf("parse: %d", ok);
    if (e)
        printf(", error %s %ld", [[e domain] UTF8String], (long)[e code]);
    printf("\n");
    [p release];
    [l release];
}

int main(void)
{
    @autoreleasepool {
        run("a document",
            @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            @"<?xml-stylesheet href=\"a.css\"?>\n"
            @"<!DOCTYPE list [ <!ENTITY who \"Ferry\"> ]>\n"
            @"<list kind=\"fruit\" note=\"a &amp; b &lt; c\">\n"
            @"  <!-- the first -->\n"
            @"  <item id=\"1\">apple</item>\n"
            @"  <item id='2'>pear &amp; quince</item>\n"
            @"  <empty/>\n"
            @"  <code><![CDATA[if (a < b) {}]]></code>\n"
            @"  <by>&who; on Linux &#233;&#x263A;</by>\n"
            @"</list>\n",
            NO, NO);

        NSString *ns = @"<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:x=\"urn:x\">\n"
                       @"  <x:entry x:id=\"7\" plain=\"p\">hi</x:entry>\n"
                       @"</feed>";
        run("namespaces off", ns, NO, NO);
        run("namespaces on", ns, YES, NO);

        run("mismatched tags", @"<a>\n<b>\n</a>", NO, NO);
        run("nothing", @"", NO, NO);
        run("text after the end", @"<a/>junk", NO, NO);
        run("an undeclared entity", @"<a>&nope;</a>", NO, NO);
        run("aborting", @"<list><item>1</item><item>2</item><item>3</item></list>", NO, YES);

        /* from a file, with no delegate */
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ferry-xmlparser-test.xml"];
        [@"<plist><dict/></plist>" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        NSXMLParser *p = [[NSXMLParser alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path]];
        printf("-- from a file, no delegate: %d\n", [p parse]);
        [p release];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

        /* the error's details */
        p = [[NSXMLParser alloc] initWithData:[@"<a>\n  <b></c>" dataUsingEncoding:NSUTF8StringEncoding]];
        [p parse];
        NSError *e = [p parserError];
        printf("-- error details: code %ld, line %ld, has a message %d, parser line %ld\n", (long)[e code],
               (long)[[[e userInfo] objectForKey:@"NSXMLParserErrorLineNumber"] integerValue],
               [[[e userInfo] objectForKey:@"NSXMLParserErrorMessage"] length] > 0, (long)[p lineNumber]);
        [p release];
    }
    return 0;
}
