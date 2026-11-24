/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSXMLDTDNode, a declaration in a DTD (foundation/NSXMLNode.m).
 * Written for freemac from Apple's public API documentation; not Apple's
 * header. */
#ifndef _FERRY_FOUNDATION_NSXMLDTDNODE_H_
#define _FERRY_FOUNDATION_NSXMLDTDNODE_H_
#include <Foundation/NSXMLNode.h>

typedef NS_ENUM(NSUInteger, NSXMLDTDNodeKind) {
    NSXMLEntityGeneralKind = 1,
    NSXMLEntityParsedKind,
    NSXMLEntityUnparsedKind,
    NSXMLEntityParameterKind,
    NSXMLEntityPredefined,
    NSXMLAttributeCDATAKind,
    NSXMLAttributeIDKind,
    NSXMLAttributeIDRefKind,
    NSXMLAttributeIDRefsKind,
    NSXMLAttributeEntityKind,
    NSXMLAttributeEntitiesKind,
    NSXMLAttributeNMTokenKind,
    NSXMLAttributeNMTokensKind,
    NSXMLAttributeEnumerationKind,
    NSXMLAttributeNotationKind,
    NSXMLElementDeclarationUndefinedKind,
    NSXMLElementDeclarationEmptyKind,
    NSXMLElementDeclarationAnyKind,
    NSXMLElementDeclarationMixedKind,
    NSXMLElementDeclarationElementKind,
};

@interface NSXMLDTDNode : NSXMLNode
- (instancetype)initWithXMLString:(NSString *)string;
- (instancetype)initWithKind:(NSXMLNodeKind)kind options:(NSXMLNodeOptions)options;
@property NSXMLDTDNodeKind DTDKind;
@property (readonly, getter=isExternal) BOOL external;
@property (copy) NSString *publicID;
@property (copy) NSString *systemID;
@property (copy) NSString *notationName;
@end

#endif
