/* SPDX-License-Identifier: GPL-3.0-or-later
 * Rulers on a scroll view, with no display: hasVerticalRuler and
 * hasHorizontalRuler, rulersVisible and the tiling around them,
 * ruleThickness and reservedThicknessForMarkers, the class rulerViewClass
 * names, a subclass drawing line numbers in drawHashMarksAndLabelsInRect:
 * from the clip view's bounds (as Sequel Pro's line-number ruler does)
 * and the default drawing, both drawn into bitmaps; the client view;
 * measurement units, registered and refused; markers, their places and
 * thicknesses, dragged and dragged off by the mouse with the client's
 * say, and added by trackMarker:withMouseEvent:. */
#import <Cocoa/Cocoa.h>

static void rect(const char *what, NSRect r)
{
    printf("%s: %.0f,%.0f %.0fx%.0f\n", what, r.origin.x, r.origin.y, r.size.width, r.size.height);
}
/* x and y from the bitmap's top left */
static void pixel(const char *what, NSBitmapImageRep *rep, int x, int y)
{
    CGFloat r, g, b, a;
    [[rep colorAtX:x y:y] getRed:&r green:&g blue:&b alpha:&a];
    printf("%s (%d,%d): %.2f %.2f %.2f\n", what, x, y, r, g, b);
}
static NSBitmapImageRep *drawn(NSView *v)
{
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
    [v cacheDisplayInRect:[v bounds] toBitmapImageRep:rep];
    return rep;
}
static NSEvent *mouse(NSEventType type, NSWindow *w, NSView *v, NSPoint p)
{
    return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:[w windowNumber] context:nil eventNumber:0 clickCount:1 pressure:1];
}

static NSMutableArray *calls;

/* The document: flipped, 400 by 600, and the rulers' client. */
@interface Page : NSView
@property BOOL keepMarkers;
@end
@implementation Page
- (BOOL)isFlipped { return YES; }
- (BOOL)rulerView:(NSRulerView *)r shouldMoveMarker:(NSRulerMarker *)m
{
    [calls addObject:@"should move"];
    return YES;
}
- (CGFloat)rulerView:(NSRulerView *)r willMoveMarker:(NSRulerMarker *)m toLocation:(CGFloat)location
{
    [calls addObject:[NSString stringWithFormat:@"will move to %.0f", location]];
    return round(location / 5) * 5;  /* to a multiple of 5 */
}
- (void)rulerView:(NSRulerView *)r didMoveMarker:(NSRulerMarker *)m
{
    [calls addObject:[NSString stringWithFormat:@"did move to %.0f", [m markerLocation]]];
}
- (BOOL)rulerView:(NSRulerView *)r shouldRemoveMarker:(NSRulerMarker *)m
{
    [calls addObject:@"should remove"];
    return !self.keepMarkers;
}
- (void)rulerView:(NSRulerView *)r didRemoveMarker:(NSRulerMarker *)m { [calls addObject:@"did remove"]; }
- (BOOL)rulerView:(NSRulerView *)r shouldAddMarker:(NSRulerMarker *)m
{
    [calls addObject:@"should add"];
    return YES;
}
- (CGFloat)rulerView:(NSRulerView *)r willAddMarker:(NSRulerMarker *)m atLocation:(CGFloat)location
{
    [calls addObject:[NSString stringWithFormat:@"will add at %.0f", location]];
    return location;
}
- (void)rulerView:(NSRulerView *)r didAddMarker:(NSRulerMarker *)m { [calls addObject:@"did add"]; }
- (void)rulerView:(NSRulerView *)r handleMouseDown:(NSEvent *)e { [calls addObject:@"mouse down"]; }
- (void)rulerView:(NSRulerView *)r willSetClientView:(NSView *)v { [calls addObject:@"losing the ruler"]; }
@end

/* Line numbers, as a line-number ruler draws them: a mark for each 20
 * points of the document that the clip view shows, worked out from the
 * clip view's bounds. */
static int drawnLines;
@interface Numbers : NSRulerView
@end
@implementation Numbers
- (instancetype)initWithScrollView:(NSScrollView *)sv orientation:(NSRulerOrientation)o
{
    if ((self = [super initWithScrollView:sv orientation:o]))
        [self setRuleThickness:24];
    return self;
}
- (CGFloat)requiredThickness { return [self ruleThickness]; }
- (void)drawHashMarksAndLabelsInRect:(NSRect)rect
{
    NSRect visible = [[[self scrollView] contentView] bounds];
    drawnLines = 0;
    [[NSColor colorWithDeviceRed:0 green:0 blue:1 alpha:1] setFill];
    for (CGFloat y = floor(NSMinY(visible) / 20) * 20; y < NSMaxY(visible); y += 20) {
        NSPoint at = [self convertPoint:NSMakePoint(0, y) fromView:[self clientView]];
        NSRectFill(NSMakeRect(4, at.y, 10, 2));
        drawnLines++;
    }
}
@end

static void flush(const char *what)
{
    printf("%s: %s\n", what, [[calls componentsJoinedByString:@"; "] UTF8String]);
    [calls removeAllObjects];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        calls = [NSMutableArray array];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 250) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        [w makeKeyAndOrderFront:nil];
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 200, 150)];
        Page *page = [[Page alloc] initWithFrame:NSMakeRect(0, 0, 400, 600)];
        [sv setDocumentView:page];
        [[w contentView] addSubview:sv];
        printf("ruler class %s; rulers %s, %s; visible %d\n", [NSStringFromClass([NSScrollView rulerViewClass]) UTF8String],
               [sv horizontalRulerView] ? "some" : "none", [sv verticalRulerView] ? "some" : "none", [sv rulersVisible]);

        [sv setHasVerticalRuler:YES];
        NSRulerView *v = [sv verticalRulerView];
        printf("vertical ruler a %s, orientation %lu, its scroll view %d, client %s, flipped %d\n", object_getClassName(v),
               (unsigned long)[v orientation], [v scrollView] == sv, [v clientView] ? "set" : "none", [v isFlipped]);
        printf("thickness: rule %.0f, markers %.0f, required %.0f, baseline %.0f, units %s\n", [v ruleThickness],
               [v reservedThicknessForMarkers], [v requiredThickness], [v baselineLocation],
               [[v measurementUnits] UTF8String]);
        rect("content, rulers hidden", [[sv contentView] frame]);
        printf("ruler in the scroll view %d, hidden %d\n", [v superview] == sv, [v isHidden]);
        [sv setRulersVisible:YES];
        rect("content, ruler shown", [[sv contentView] frame]);
        rect("vertical ruler", [v frame]);
        [v setRuleThickness:20];
        rect("thicker rule: content", [[sv contentView] frame]);
        [sv setHasHorizontalRuler:YES];
        NSRulerView *h = [sv horizontalRulerView];
        rect("both: content", [[sv contentView] frame]);
        rect("horizontal ruler", [h frame]);
        rect("vertical ruler", [v frame]);
        [sv setHasHorizontalRuler:NO];
        rect("vertical only again: content", [[sv contentView] frame]);
        printf("horizontal ruler kept %d, hidden %d\n", [sv horizontalRulerView] == h, [h isHidden]);

        /* ---- the default drawing ---- */
        [v setClientView:page];
        [v setReservedThicknessForMarkers:0];
        rect("no markers' room: vertical ruler", [v frame]);
        NSBitmapImageRep *rep = drawn(v);
        pixel("background", rep, 5, 7);
        pixel("edge next to the content", rep, (int)[v frame].size.width - 1, 50);
        /* inches: a labelled mark every 72 points, so the first below the top is at 72 */
        pixel("the 1-inch mark", rep, 18, 72);
        pixel("between marks", rep, 18, 60);

        /* ---- units ---- */
        [NSRulerView registerUnitWithName:@"Lines" abbreviation:@"ln" unitToPointsConversionFactor:20
                              stepUpCycle:@[ @5.0 ] stepDownCycle:@[ @0.5 ]];
        [v setMeasurementUnits:@"Lines"];
        printf("units now %s\n", [[v measurementUnits] UTF8String]);
        @try {
            [v setMeasurementUnits:@"Furlongs"];
            printf("Furlongs taken\n");
        } @catch (NSException *e) {
            printf("Furlongs refused: %s, still %s\n", [[e name] UTF8String], [[v measurementUnits] UTF8String]);
        }
        [v setMeasurementUnits:NSRulerViewUnitCentimeters];
        [v setOriginOffset:10];
        printf("origin offset %.0f\n", [v originOffset]);
        [v setOriginOffset:0];

        /* ---- markers ---- */
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(8, 6)];
        [image lockFocus];
        [[NSColor colorWithDeviceRed:1 green:0 blue:0 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, 0, 8, 6));
        [image unlockFocus];
        NSRulerMarker *m = [[NSRulerMarker alloc] initWithRulerView:v markerLocation:100 image:image
                                                        imageOrigin:NSMakePoint(8, 3)];
        printf("marker: movable %d, removable %d, location %.0f, thickness %.0f\n", [m isMovable], [m isRemovable],
               [m markerLocation], [m thicknessRequiredInRuler]);
        [v addMarker:m];
        printf("markers %lu, required %.0f\n", (unsigned long)[[v markers] count], [v requiredThickness]);
        rect("ruler with a marker", [v frame]);
        rect("marker's image", [m imageRectInRuler]);
        rep = drawn(v);
        NSRect ir = [m imageRectInRuler];
        pixel("marker drawn", rep, (int)NSMidX(ir), (int)NSMidY(ir));
        [m setMovable:YES];
        [m setRemovable:YES];
        NSPoint at = NSMakePoint(NSMidX(ir), NSMidY(ir));
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, at)];
        printf("dragging %d\n", [m isDragging]);
        [w sendEvent:mouse(NSEventTypeLeftMouseDragged, w, v, NSMakePoint(at.x, at.y + 12))];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, NSMakePoint(at.x, at.y + 23))];
        printf("dragged 23 down: location %.0f, dragging %d\n", [m markerLocation], [m isDragging]);
        flush("client");
        ir = [m imageRectInRuler];
        at = NSMakePoint(NSMidX(ir), NSMidY(ir));
        page.keepMarkers = YES;
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, at)];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, NSMakePoint(at.x + 60, at.y))];
        printf("dragged off, kept by the client: markers %lu\n", (unsigned long)[[v markers] count]);
        flush("client");
        page.keepMarkers = NO;
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, at)];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, NSMakePoint(at.x + 60, at.y))];
        printf("dragged off: markers %lu, its ruler %s\n", (unsigned long)[[v markers] count], [m ruler] ? "set" : "none");
        flush("client");
        [w sendEvent:mouse(NSEventTypeLeftMouseDown, w, v, NSMakePoint(5, 40))];
        [w sendEvent:mouse(NSEventTypeLeftMouseUp, w, v, NSMakePoint(5, 40))];
        flush("a click off the markers");
        NSRulerMarker *dropped = [[NSRulerMarker alloc] initWithRulerView:v markerLocation:0 image:image
                                                              imageOrigin:NSMakePoint(8, 3)];
        printf("track to add: %d, ", [v trackMarker:dropped withMouseEvent:mouse(NSEventTypeLeftMouseDown, w, v, NSMakePoint(5, 30))]);
        printf("location %.0f, markers %lu\n", [dropped markerLocation], (unsigned long)[[v markers] count]);
        flush("client");
        NSRulerMarker *copy = [dropped copy];
        printf("a copy: location %.0f, image the same %d\n", [copy markerLocation], [copy image] == [dropped image]);
        [v setClientView:nil];
        printf("client gone: markers %lu\n", (unsigned long)[[v markers] count]);
        flush("client");

        /* ---- a ruler class of the program's own, drawing line numbers ---- */
        [NSScrollView setRulerViewClass:[Numbers class]];
        NSScrollView *text = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 160, 100)];
        Page *lines = [[Page alloc] initWithFrame:NSMakeRect(0, 0, 136, 400)];
        [text setDocumentView:lines];
        [[w contentView] addSubview:text];
        [text setHasVerticalRuler:YES];
        [text setRulersVisible:YES];
        NSRulerView *n = [text verticalRulerView];
        [n setClientView:lines];
        printf("line ruler a %s, thickness %.0f\n", object_getClassName(n), [n requiredThickness]);
        rect("line ruler", [n frame]);
        rect("its content", [[text contentView] frame]);
        rep = drawn(n);
        printf("lines drawn %d\n", drawnLines);
        pixel("line 0's mark", rep, 8, 1);
        pixel("line 1's mark", rep, 8, 21);
        pixel("between", rep, 8, 11);
        [[text contentView] scrollToPoint:NSMakePoint(0, 30)];
        [text reflectScrolledClipView:[text contentView]];
        rep = drawn(n);
        printf("scrolled 30 down: lines drawn %d\n", drawnLines);
        pixel("line 2's mark", rep, 8, 11);
        pixel("between", rep, 8, 1);
        [NSScrollView setRulerViewClass:nil];
        printf("ruler class again %s\n", [NSStringFromClass([NSScrollView rulerViewClass]) UTF8String]);
    }
    return 0;
}
