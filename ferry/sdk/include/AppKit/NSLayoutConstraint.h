/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Auto Layout (freemac 1.222, Ferry 0.46.0). Constraints,
 * anchors, layout guides and the visual format language, as Apple's public
 * documentation describes them; not Apple's header. Ferry's solver
 * (appkit/NSLayoutConstraint.m) handles equalities, inequalities, fixed
 * sizes, pinning to the superview, centring, multipliers, intrinsic sizes and
 * priorities; it is a simple one, not a Mac's. */
#ifndef _FERRY_APPKIT_NSLAYOUTCONSTRAINT_H_
#define _FERRY_APPKIT_NSLAYOUTCONSTRAINT_H_
#import <Foundation/Foundation.h>

@class NSView, NSWindow, NSLayoutConstraint, NSLayoutGuide, NSLayoutXAxisAnchor, NSLayoutYAxisAnchor, NSLayoutDimension;

typedef NS_ENUM(NSInteger, NSLayoutRelation) {
    NSLayoutRelationLessThanOrEqual = -1, NSLayoutRelationEqual = 0, NSLayoutRelationGreaterThanOrEqual = 1,
};

typedef NS_OPTIONS(NSUInteger, NSLayoutFormatOptions) {
    NSLayoutFormatAlignAllLeft = (1 << NSLayoutAttributeLeft),
    NSLayoutFormatAlignAllRight = (1 << NSLayoutAttributeRight),
    NSLayoutFormatAlignAllTop = (1 << NSLayoutAttributeTop),
    NSLayoutFormatAlignAllBottom = (1 << NSLayoutAttributeBottom),
    NSLayoutFormatAlignAllLeading = (1 << NSLayoutAttributeLeading),
    NSLayoutFormatAlignAllTrailing = (1 << NSLayoutAttributeTrailing),
    NSLayoutFormatAlignAllCenterX = (1 << NSLayoutAttributeCenterX),
    NSLayoutFormatAlignAllCenterY = (1 << NSLayoutAttributeCenterY),
    NSLayoutFormatAlignAllLastBaseline = (1 << NSLayoutAttributeLastBaseline),
    NSLayoutFormatAlignAllFirstBaseline = (1 << NSLayoutAttributeFirstBaseline),
    NSLayoutFormatAlignAllBaseline = NSLayoutFormatAlignAllLastBaseline,
    NSLayoutFormatAlignmentMask = 0xFFFF,
    NSLayoutFormatDirectionLeadingToTrailing = 0 << 16,
    NSLayoutFormatDirectionLeftToRight = 1 << 16,
    NSLayoutFormatDirectionRightToLeft = 2 << 16,
    NSLayoutFormatDirectionMask = 0x3 << 16,
};

/* The standard spaces the visual format's "-" stands for. */
#define NSLayoutConstraintStandardSiblingSpacing 8.0
#define NSLayoutConstraintStandardSuperviewSpacing 20.0

@interface NSLayoutAnchor<AnchorType> : NSObject <NSCopying, NSCoding>
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutAnchor<AnchorType> *)anchor constant:(CGFloat)c;
@property (readonly, copy) NSString *name;
@property (readonly, weak) id item;
@property (readonly) BOOL hasAmbiguousLayout;
@property (readonly) NSArray<NSLayoutConstraint *> *constraintsAffectingLayout;
@end

@interface NSLayoutXAxisAnchor : NSLayoutAnchor<NSLayoutXAxisAnchor *>
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutXAxisAnchor *)otherAnchor;
@end
@interface NSLayoutYAxisAnchor : NSLayoutAnchor<NSLayoutYAxisAnchor *>
- (NSLayoutDimension *)anchorWithOffsetToAnchor:(NSLayoutYAxisAnchor *)otherAnchor;
@end
@interface NSLayoutDimension : NSLayoutAnchor<NSLayoutDimension *>
- (NSLayoutConstraint *)constraintEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToConstant:(CGFloat)c;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m;
- (NSLayoutConstraint *)constraintEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintGreaterThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
                                                    constant:(CGFloat)c;
- (NSLayoutConstraint *)constraintLessThanOrEqualToAnchor:(NSLayoutDimension *)anchor multiplier:(CGFloat)m
                                                 constant:(CGFloat)c;
@end

/* firstItem.firstAttribute (relation) secondItem.secondAttribute * multiplier + constant */
@interface NSLayoutConstraint : NSObject <NSCoding>
+ (instancetype FERRY_SWIFT_NONNULL)constraintWithItem:(id)view1 attribute:(NSLayoutAttribute)attr1 relatedBy:(NSLayoutRelation)relation
                            toItem:(id)view2 attribute:(NSLayoutAttribute)attr2 multiplier:(CGFloat)multiplier
                          constant:(CGFloat)c;
+ (NSArray<NSLayoutConstraint *> *)constraintsWithVisualFormat:(NSString *)format options:(NSLayoutFormatOptions)opts
                                                       metrics:(NSDictionary<NSString *, NSNumber *> *)metrics
                                                         views:(NSDictionary<NSString *, id> *)views;
+ (void)activateConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
+ (void)deactivateConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
@property (readonly, assign) id firstItem;
@property (readonly, assign) id secondItem;
@property (readonly) NSLayoutAttribute firstAttribute, secondAttribute;
@property (readonly, copy) NSLayoutAnchor *firstAnchor;
@property (readonly, copy) NSLayoutAnchor *secondAnchor;
@property (readonly) NSLayoutRelation relation;
@property (readonly) CGFloat multiplier;
@property CGFloat constant;
@property NSLayoutPriority priority;
@property (getter=isActive) BOOL active;
@property (copy) NSString *identifier;
@property BOOL shouldBeArchived;
@end

/* NSDictionaryOfVariableBindings(a, b) is @{@"a": a, @"b": b}, for the visual format's views. */
FOUNDATION_EXPORT NSDictionary *_NSDictionaryOfVariableBindings(NSString *commaSeparatedKeys, id firstValue, ...);
#define NSDictionaryOfVariableBindings(...) _NSDictionaryOfVariableBindings(@"" #__VA_ARGS__, __VA_ARGS__, nil)

/* A rectangle that takes part in layout without being a view. */
@interface NSLayoutGuide : NSObject <NSCoding>
@property (readonly) NSRect frame;
@property (weak) NSView *owningView;
@property (copy) NSUserInterfaceItemIdentifier identifier;
@property (readonly, strong) NSLayoutXAxisAnchor *leadingAnchor, *trailingAnchor, *leftAnchor, *rightAnchor, *centerXAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *topAnchor, *bottomAnchor, *centerYAnchor;
@property (readonly, strong) NSLayoutDimension *widthAnchor, *heightAnchor;
@property (readonly) BOOL hasAmbiguousLayout;
- (NSArray<NSLayoutConstraint *> *)constraintsAffectingLayoutForOrientation:(NSLayoutConstraintOrientation)o;
@end

@interface NSView (NSConstraintBasedLayoutInstallingConstraints)
@property (readonly, copy) NSArray<__kindof NSLayoutConstraint *> *constraints;
- (void)addConstraint:(NSLayoutConstraint *)constraint;
- (void)addConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
- (void)removeConstraint:(NSLayoutConstraint *)constraint;
- (void)removeConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
@property (readonly, strong) NSLayoutXAxisAnchor *leadingAnchor, *trailingAnchor, *leftAnchor, *rightAnchor, *centerXAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *topAnchor, *bottomAnchor, *centerYAnchor;
@property (readonly, strong) NSLayoutYAxisAnchor *firstBaselineAnchor, *lastBaselineAnchor;
@property (readonly, strong) NSLayoutDimension *widthAnchor, *heightAnchor;
@property (readonly, copy) NSArray<NSLayoutGuide *> *layoutGuides;
- (void)addLayoutGuide:(NSLayoutGuide *)guide;
- (void)removeLayoutGuide:(NSLayoutGuide *)guide;
@end

@interface NSView (NSConstraintBasedLayoutCoreMethods)
- (void)updateConstraintsForSubtreeIfNeeded;
- (void)updateConstraints;
@property BOOL needsUpdateConstraints;
+ (BOOL)requiresConstraintBasedLayout;
@property (readonly) NSEdgeInsets alignmentRectInsets;
- (NSRect)alignmentRectForFrame:(NSRect)frame;
- (NSRect)frameForAlignmentRect:(NSRect)alignmentRect;
@property (readonly) CGFloat baselineOffsetFromBottom, firstBaselineOffsetFromTop, lastBaselineOffsetFromBottom;
@end

@interface NSView (NSConstraintBasedLayoutDebugging)
- (NSArray<NSLayoutConstraint *> *)constraintsAffectingLayoutForOrientation:(NSLayoutConstraintOrientation)o;
@property (readonly) BOOL hasAmbiguousLayout;
- (void)exerciseAmbiguityInLayout;
@end

@interface NSWindow (NSConstraintBasedLayout)
- (void)updateConstraintsIfNeeded;
- (void)layoutIfNeeded;
- (void)setNeedsLayout:(BOOL)flag;
- (void)setNeedsUpdateConstraints:(BOOL)flag;
- (void)visualizeConstraints:(NSArray<NSLayoutConstraint *> *)constraints;
/* The part of the window's content view laid out against: here all of it. */
@property (readonly, strong) id contentLayoutGuide;
@property (readonly) NSRect contentLayoutRect;
- (NSLayoutAttribute)anchorAttributeForOrientation:(NSLayoutConstraintOrientation)o;
@end

#endif
