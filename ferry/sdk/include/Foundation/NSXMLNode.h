/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSXMLNode, a node of an XML tree (foundation/NSXMLNode.m), on
 * this system's libxml2 for parsing and XPath. Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSXMLNODE_H_
#define _FERRY_FOUNDATION_NSXMLNODE_H_
#include <Foundation/Foundation.h>
#include <Foundation/NSXMLNodeOptions.h>

@class NSXMLElement, NSXMLDocument, NSXMLDTD;

typedef NS_ENUM(NSUInteger, NSXMLNodeKind) {
    NSXMLInvalidKind = 0,
    NSXMLDocumentKind,
    NSXMLElementKind,
    NSXMLAttributeKind,
    NSXMLNamespaceKind,
    NSXMLProcessingInstructionKind,
    NSXMLCommentKind,
    NSXMLTextKind,
    NSXMLDTDKind,
    NSXMLEntityDeclarationKind,
    NSXMLAttributeDeclarationKind,
    NSXMLElementDeclarationKind,
    NSXMLNotationDeclarationKind,
};

@interface NSXMLNode : NSObject <NSCopying>
- (instancetype)init;
- (instancetype)initWithKind:(NSXMLNodeKind)kind;
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options;

+ (id)document;
+ (id)documentWithRootElement:(NSXMLElement *)element;
+ (id)elementWithName:(NSString *)name;
+ (id)elementWithName:(NSString *)name URI:(NSString *)URI;
+ (id)elementWithName:(NSString *)name stringValue:(NSString *)string;
+ (id)elementWithName:(NSString *)name children:(NSArray<NSXMLNode *> *)children
           attributes:(NSArray<NSXMLNode *> *)attributes;
+ (id)attributeWithName:(NSString *)name stringValue:(NSString *)stringValue;
+ (id)attributeWithName:(NSString *)name URI:(NSString *)URI stringValue:(NSString *)stringValue;
+ (id)namespaceWithName:(NSString *)name stringValue:(NSString *)stringValue;
+ (id)processingInstructionWithName:(NSString *)name stringValue:(NSString *)stringValue;
+ (id)commentWithStringValue:(NSString *)stringValue;
+ (id)textWithStringValue:(NSString *)stringValue;
+ (id)DTDNodeWithXMLString:(NSString *)string;

@property (readonly) NSXMLNodeKind kind;
@property (copy) NSString *name;
@property (retain) id objectValue;
@property (copy) NSString *stringValue;
- (void)setStringValue:(NSString *)string resolvingEntities:(BOOL)resolve;

@property (readonly) NSUInteger index;
@property (readonly) NSUInteger level;
@property (readonly, retain) NSXMLDocument *rootDocument;
@property (readonly, copy) NSXMLNode *parent;
@property (readonly) NSUInteger childCount;
@property (readonly, copy) NSArray<NSXMLNode *> *children;
- (NSXMLNode *)childAtIndex:(NSUInteger)index;
@property (readonly, copy) NSXMLNode *previousSibling;
@property (readonly, copy) NSXMLNode *nextSibling;
@property (readonly, copy) NSXMLNode *previousNode;
@property (readonly, copy) NSXMLNode *nextNode;
- (void)detach;
@property (readonly, copy) NSString *XPath;

@property (readonly, copy) NSString *localName;
@property (readonly, copy) NSString *prefix;
@property (copy) NSString *URI;
+ (NSString *)localNameForName:(NSString *)name;
+ (NSString *)prefixForName:(NSString *)name;
+ (NSXMLNode *)predefinedNamespaceForPrefix:(NSString *)name;

@property (readonly, copy) NSString *description;
@property (readonly, copy) NSString *XMLString;
- (NSString *)XMLStringWithOptions:(NSXMLNodeOptions)options;
- (NSString *)canonicalXMLStringPreservingComments:(BOOL)comments;

- (NSArray<__kindof NSXMLNode *> *)nodesForXPath:(NSString *)xpath error:(NSError **)error;

@property (readonly) NSXMLNodeOptions options;
@end

#endif
