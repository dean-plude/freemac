/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSXMLElement (foundation/NSXMLNode.m). Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSXMLELEMENT_H_
#define _FERRY_FOUNDATION_NSXMLELEMENT_H_
#include <Foundation/NSXMLNode.h>

@interface NSXMLElement : NSXMLNode
- (instancetype)initWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name URI:(NSString *)URI;
- (instancetype)initWithName:(NSString *)name stringValue:(NSString *)string;
- (instancetype)initWithXMLString:(NSString *)string error:(NSError **)error;
- (instancetype FERRY_SWIFT_NONNULL)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options;

- (NSArray<NSXMLElement *> *)elementsForName:(NSString *)name;
- (NSArray<NSXMLElement *> *)elementsForLocalName:(NSString *)localName URI:(NSString *)URI;

- (void)addAttribute:(NSXMLNode *)attribute;
- (void)removeAttributeForName:(NSString *)name;
@property (copy) NSArray<NSXMLNode *> *attributes;
- (void)setAttributesWithDictionary:(NSDictionary<NSString *, NSString *> *)attributes;
- (void)setAttributesAsDictionary:(NSDictionary *)attributes;
- (NSXMLNode *)attributeForName:(NSString *)name;
- (NSXMLNode *)attributeForLocalName:(NSString *)localName URI:(NSString *)URI;

- (void)addNamespace:(NSXMLNode *)aNamespace;
- (void)removeNamespaceForPrefix:(NSString *)name;
@property (copy) NSArray<NSXMLNode *> *namespaces;
- (NSXMLNode *)namespaceForPrefix:(NSString *)name;
- (NSXMLNode *)resolveNamespaceForName:(NSString *)name;
- (NSString *)resolvePrefixForNamespaceURI:(NSString *)namespaceURI;

- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index;
- (void)insertChildren:(NSArray<NSXMLNode *> *)children atIndex:(NSUInteger)index;
- (void)removeChildAtIndex:(NSUInteger)index;
- (void)setChildren:(NSArray<NSXMLNode *> *)children;
- (void)addChild:(NSXMLNode *)child;
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node;
- (void)normalizeAdjacentTextNodesPreservingCDATA:(BOOL)preserve;
@end

#endif
