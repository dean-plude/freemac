/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: rulers and their markers (NSRulerView.m), written from
 * Apple's public documentation. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_NSRULERVIEW_H_
#define _FERRY_APPKIT_NSRULERVIEW_H_

@class NSRulerView;

typedef NS_ENUM(NSUInteger, NSRulerOrientation) {
    NSHorizontalRuler = 0, NSVerticalRuler = 1,
};
typedef NSString *NSRulerViewUnitName;
APPKIT_EXTERN NSRulerViewUnitName const NSRulerViewUnitInches;
APPKIT_EXTERN NSRulerViewUnitName const NSRulerViewUnitCentimeters;
APPKIT_EXTERN NSRulerViewUnitName const NSRulerViewUnitPoints;
APPKIT_EXTERN NSRulerViewUnitName const NSRulerViewUnitPicas;

/* A mark on a ruler, drawn as an image, that the user may move or remove. */
@interface NSRulerMarker : NSObject <NSCopying, NSCoding>
- (instancetype)initWithRulerView:(NSRulerView *)ruler markerLocation:(CGFloat)location image:(NSImage *)image
                      imageOrigin:(NSPoint)imageOrigin;
@property (readonly, assign) NSRulerView *ruler;
@property CGFloat markerLocation;
@property (retain) NSImage *image;
@property NSPoint imageOrigin;
@property (getter=isMovable) BOOL movable;
@property (getter=isRemovable) BOOL removable;
@property (readonly, getter=isDragging) BOOL dragging;
@property (retain) id<NSCopying> representedObject;
@property (readonly) NSRect imageRectInRuler;
@property (readonly) CGFloat thicknessRequiredInRuler;
- (void)drawRect:(NSRect)rect;
- (BOOL)trackMouse:(NSEvent *)mouseDownEvent adding:(BOOL)isAdding;
@end

/* A ruler along one side of a scroll view's content, measuring its
 * client view (usually the document view) in a unit of measurement. */
@interface NSRulerView : NSView
+ (void)registerUnitWithName:(NSRulerViewUnitName)unitName abbreviation:(NSString *)abbreviation
    unitToPointsConversionFactor:(CGFloat)conversionFactor stepUpCycle:(NSArray<NSNumber *> *)stepUpCycle
                   stepDownCycle:(NSArray<NSNumber *> *)stepDownCycle;
- (instancetype)initWithScrollView:(NSScrollView *)scrollView orientation:(NSRulerOrientation)orientation;
@property (assign) NSScrollView *scrollView;
@property NSRulerOrientation orientation;
@property CGFloat ruleThickness, reservedThicknessForMarkers, reservedThicknessForAccessoryView;
@property (readonly) CGFloat requiredThickness, baselineLocation;
@property (copy) NSRulerViewUnitName measurementUnits;
@property CGFloat originOffset;
@property (assign) NSView *clientView;
@property (copy) NSArray<NSRulerMarker *> *markers;
- (void)addMarker:(NSRulerMarker *)marker;
- (void)removeMarker:(NSRulerMarker *)marker;
- (BOOL)trackMarker:(NSRulerMarker *)marker withMouseEvent:(NSEvent *)event;
@property (retain) NSView *accessoryView;
- (void)moveRulerlineFromLocation:(CGFloat)oldLocation toLocation:(CGFloat)newLocation;
- (void)invalidateHashMarks;
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect;
- (void)drawMarkersInRect:(NSRect)rect;
@end

/* What a ruler asks of its client view, which implements those it wants. */
@interface NSView (NSRulerMarkerClientViewDelegation)
- (BOOL)rulerView:(NSRulerView *)ruler shouldMoveMarker:(NSRulerMarker *)marker;
- (CGFloat)rulerView:(NSRulerView *)ruler willMoveMarker:(NSRulerMarker *)marker toLocation:(CGFloat)location;
- (void)rulerView:(NSRulerView *)ruler didMoveMarker:(NSRulerMarker *)marker;
- (BOOL)rulerView:(NSRulerView *)ruler shouldRemoveMarker:(NSRulerMarker *)marker;
- (void)rulerView:(NSRulerView *)ruler didRemoveMarker:(NSRulerMarker *)marker;
- (BOOL)rulerView:(NSRulerView *)ruler shouldAddMarker:(NSRulerMarker *)marker;
- (CGFloat)rulerView:(NSRulerView *)ruler willAddMarker:(NSRulerMarker *)marker atLocation:(CGFloat)location;
- (void)rulerView:(NSRulerView *)ruler didAddMarker:(NSRulerMarker *)marker;
- (void)rulerView:(NSRulerView *)ruler handleMouseDown:(NSEvent *)event;
- (void)rulerView:(NSRulerView *)ruler willSetClientView:(NSView *)newClient;
- (CGFloat)rulerView:(NSRulerView *)ruler locationForPoint:(NSPoint)point;
- (NSPoint)rulerView:(NSRulerView *)ruler pointForLocation:(CGFloat)location;
@end

/* A scroll view's rulers: made of the class rulerViewClass names, shown
 * beside the content while rulersVisible is YES. */
@interface NSScrollView (NSRulerSupport)
+ (void)setRulerViewClass:(Class)rulerViewClass;
+ (Class)rulerViewClass;
@property (retain) NSRulerView *horizontalRulerView, *verticalRulerView;
@end

#endif
