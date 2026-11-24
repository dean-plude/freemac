/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSXMLDTD, a document type definition (foundation/NSXMLNode.m).
 * Written for freemac from Apple's public API documentation; not Apple's
 * header. */
#ifndef _FERRY_FOUNDATION_NSXMLDTD_H_
#define _FERRY_FOUNDATION_NSXMLDTD_H_
#include <Foundation/NSXMLNode.h>
#include <Foundation/NSXMLDTDNode.h>

@interface NSXMLDTD : NSXMLNode
- (instancetype)init;
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSXMLNodeOptions)mask error:(NSError **)error;
- (instancetype)initWithData:(NSData *)data options:(NSXMLNodeOptions)mask error:(NSError **)error;
@property (copy) NSString *publicID;
@property (copy) NSString *systemID;
- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index;
- (void)insertChildren:(NSArray<NSXMLNode *> *)children atIndex:(NSUInteger)index;
- (void)removeChildAtIndex:(NSUInteger)index;
- (void)setChildren:(NSArray<NSXMLNode *> *)children;
- (void)addChild:(NSXMLNode *)child;
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node;
- (NSXMLDTDNode *)entityDeclarationForName:(NSString *)name;
- (NSXMLDTDNode *)notationDeclarationForName:(NSString *)name;
- (NSXMLDTDNode *)elementDeclarationForName:(NSString *)name;
- (NSXMLDTDNode *)attributeDeclarationForName:(NSString *)name elementName:(NSString *)elementName;
+ (NSXMLDTDNode *)predefinedEntityDeclarationForName:(NSString *)name;
@end

#endif
