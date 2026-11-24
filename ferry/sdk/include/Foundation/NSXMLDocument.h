/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSXMLDocument, an XML document as a tree of NSXMLNodes
 * (foundation/NSXMLNode.m), parsed with this system's libxml2. Written for
 * freemac from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_FOUNDATION_NSXMLDOCUMENT_H_
#define _FERRY_FOUNDATION_NSXMLDOCUMENT_H_
#include <Foundation/NSXMLNode.h>
#include <Foundation/NSXMLElement.h>
#include <Foundation/NSXMLDTD.h>

typedef NS_ENUM(NSUInteger, NSXMLDocumentContentKind) {
    NSXMLDocumentXMLKind = 0,
    NSXMLDocumentXHTMLKind,
    NSXMLDocumentHTMLKind,
    NSXMLDocumentTextKind,
};

@interface NSXMLDocument : NSXMLNode
- (instancetype)init;
- (instancetype)initWithXMLString:(NSString *)string options:(NSXMLNodeOptions)mask error:(NSError **)error;
- (instancetype)initWithContentsOfURL:(NSURL *)url options:(NSXMLNodeOptions)mask error:(NSError **)error;
- (instancetype)initWithData:(NSData *)data options:(NSXMLNodeOptions)mask error:(NSError **)error;
- (instancetype)initWithRootElement:(NSXMLElement *)element;
+ (Class)replacementClassForClass:(Class)cls;

@property (copy) NSString *characterEncoding;
@property (copy) NSString *version;
@property (getter=isStandalone) BOOL standalone;
@property NSXMLDocumentContentKind documentContentKind;
@property (copy) NSString *MIMEType;
@property (copy) NSXMLDTD *DTD;

- (void)setRootElement:(NSXMLElement *)root;
- (NSXMLElement *)rootElement;
- (void)insertChild:(NSXMLNode *)child atIndex:(NSUInteger)index;
- (void)insertChildren:(NSArray<NSXMLNode *> *)children atIndex:(NSUInteger)index;
- (void)removeChildAtIndex:(NSUInteger)index;
- (void)setChildren:(NSArray<NSXMLNode *> *)children;
- (void)addChild:(NSXMLNode *)child;
- (void)replaceChildAtIndex:(NSUInteger)index withNode:(NSXMLNode *)node;

@property (readonly, copy) NSData *XMLData;
- (NSData *)XMLDataWithOptions:(NSXMLNodeOptions)options;
@end

#endif
