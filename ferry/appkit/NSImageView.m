/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSImageView and NSImageCell. Our own code, written from
 * Apple's public documentation. In a nib an image view keeps its image and
 * settings in its NSImageCell ("NSContents", "NSScale", "NSAlign",
 * "NSStyle"), which the view copies when it is loaded. Built without ARC. */
#import "AInternal.h"

@implementation NSImageCell {
    NSImageScaling _scaling;
    NSImageAlignment _align;
    NSImageFrameStyle _style;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    if ([coder containsValueForKey:@"NSScale"])
        _scaling = [coder decodeIntegerForKey:@"NSScale"];
    if ([coder containsValueForKey:@"NSAlign"])
        _align = [coder decodeIntegerForKey:@"NSAlign"];
    if ([coder containsValueForKey:@"NSStyle"])
        _style = [coder decodeIntegerForKey:@"NSStyle"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    [super encodeWithCoder:coder];
    [coder encodeInteger:_scaling forKey:@"NSScale"];
    [coder encodeInteger:_align forKey:@"NSAlign"];
    [coder encodeInteger:_style forKey:@"NSStyle"];
}
- (NSImageScaling)imageScaling { return _scaling; }
- (void)setImageScaling:(NSImageScaling)s { _scaling = s; }
- (NSImageAlignment)imageAlignment { return _align; }
- (void)setImageAlignment:(NSImageAlignment)a { _align = a; }
- (NSImageFrameStyle)imageFrameStyle { return _style; }
- (void)setImageFrameStyle:(NSImageFrameStyle)s { _style = s; }
@end

@implementation NSImageView {
    NSImage *_image;
    NSImageScaling _scaling;
    NSImageAlignment _align;
    NSImageFrameStyle _style;
    BOOL _editable, _animates, _cutCopyPaste;
    NSColor *_tint;
}

+ (Class)cellClass { return [NSImageCell class]; }
+ (instancetype)imageViewWithImage:(NSImage *)image
{
    NSSize s = image ? [image size] : NSMakeSize(48, 48);
    NSImageView *v = [[[self alloc] initWithFrame:(NSRect){NSZeroPoint, s}] autorelease];
    [v setImage:image];
    return v;
}

- (void)_setDefaults
{
    [super _setDefaults];
    _scaling = NSImageScaleProportionallyDown;
    _cutCopyPaste = YES;
}

- (void)_takeFromCell:(NSCell *)cell
{
    [super _takeFromCell:cell];
    if ([[cell objectValue] isKindOfClass:[NSImage class]])
        [self setImage:[cell objectValue]];
    if ([cell isKindOfClass:[NSImageCell class]]) {
        NSImageCell *c = (NSImageCell *)cell;
        _scaling = [c imageScaling];
        _align = [c imageAlignment];
        _style = [c imageFrameStyle];
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    if ([coder containsValueForKey:@"NSEditable"])
        _editable = [coder decodeBoolForKey:@"NSEditable"];
    return self;
}

- (void)dealloc
{
    [_image release];
    [_tint release];
    [super dealloc];
}

- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image
{
    if (image && ![image isKindOfClass:[NSImage class]])
        image = nil;
    [image retain];
    [_image release];
    _image = image;
    [self setNeedsDisplay:YES];
}
- (id)objectValue { return _image; }
- (void)setObjectValue:(id)value { [self setImage:value]; }

- (NSImageScaling)imageScaling { return _scaling; }
- (void)setImageScaling:(NSImageScaling)s
{
    _scaling = s;
    [self setNeedsDisplay:YES];
}
- (NSImageAlignment)imageAlignment { return _align; }
- (void)setImageAlignment:(NSImageAlignment)a
{
    _align = a;
    [self setNeedsDisplay:YES];
}
- (NSImageFrameStyle)imageFrameStyle { return _style; }
- (void)setImageFrameStyle:(NSImageFrameStyle)s
{
    _style = s;
    [self setNeedsDisplay:YES];
}
- (BOOL)isEditable { return _editable; }
- (void)setEditable:(BOOL)f { _editable = f; }
- (BOOL)animates { return _animates; }
- (void)setAnimates:(BOOL)f { _animates = f; }
- (BOOL)allowsCutCopyPaste { return _cutCopyPaste; }
- (void)setAllowsCutCopyPaste:(BOOL)f { _cutCopyPaste = f; }
- (NSColor *)contentTintColor { return _tint; }
- (void)setContentTintColor:(NSColor *)c
{
    id wasTint = _tint;
    _tint = [c retain];
    [wasTint release];
    [self setNeedsDisplay:YES];
}

- (NSSize)intrinsicContentSize { return _image ? [_image size] : NSMakeSize(-1, -1); }

/* The rectangle the image is drawn in, inside the frame's border. */
- (NSRect)_imageRectIn:(NSRect)box
{
    NSSize s = [_image size];
    if (s.width <= 0 || s.height <= 0)
        return NSZeroRect;
    switch (_scaling) {
    case NSImageScaleAxesIndependently:
        return box;
    case NSImageScaleProportionallyUpOrDown:
    case NSImageScaleProportionallyDown: {
        CGFloat k = fmin(box.size.width / s.width, box.size.height / s.height);
        if (_scaling == NSImageScaleProportionallyDown)
            k = fmin(k, 1);
        s = NSMakeSize(s.width * k, s.height * k);
        break;
    }
    default:
        break;
    }
    BOOL left = _align == NSImageAlignLeft || _align == NSImageAlignTopLeft || _align == NSImageAlignBottomLeft;
    BOOL right = _align == NSImageAlignRight || _align == NSImageAlignTopRight || _align == NSImageAlignBottomRight;
    BOOL top = _align == NSImageAlignTop || _align == NSImageAlignTopLeft || _align == NSImageAlignTopRight;
    BOOL bottom = _align == NSImageAlignBottom || _align == NSImageAlignBottomLeft || _align == NSImageAlignBottomRight;
    if ([self isFlipped]) {
        BOOL t = top;
        top = bottom;
        bottom = t;
    }
    CGFloat x = left ? NSMinX(box) : right ? NSMaxX(box) - s.width : NSMidX(box) - s.width / 2;
    CGFloat y = bottom ? NSMinY(box) : top ? NSMaxY(box) - s.height : NSMidY(box) - s.height / 2;
    if (_scaling != NSImageScaleNone) {
        x = round(x);
        y = round(y);
    }
    return NSMakeRect(x, y, s.width, s.height);
}

- (void)drawRect:(NSRect)dirty
{
    NSRect b = [self bounds], box = b;
    switch (_style) {
    case NSImageFramePhoto:
        [[NSColor colorWithWhite:0 alpha:0.25] set];
        NSFrameRect(NSInsetRect(b, 0.5, 0.5));
        [[NSColor whiteColor] set];
        NSRectFill(NSInsetRect(b, 1, 1));
        box = NSInsetRect(b, 4, 4);
        break;
    case NSImageFrameGrayBezel:
    case NSImageFrameButton:
        AFillRoundedRect(NSInsetRect(b, 0.5, 0.5), _style == NSImageFrameButton ? 5 : 3,
                         _style == NSImageFrameButton ? [NSColor whiteColor] : nil,
                         [NSColor colorWithWhite:0 alpha:0.22]);
        box = NSInsetRect(b, 3, 3);
        break;
    case NSImageFrameGroove:
        [[NSColor colorWithWhite:0 alpha:0.2] set];
        NSFrameRect(b);
        [[NSColor colorWithWhite:1 alpha:0.7] set];
        NSFrameRect(NSInsetRect(b, 1, 1));
        box = NSInsetRect(b, 3, 3);
        break;
    default:
        break;
    }
    if (!_image)
        return;
    NSRect r = [self _imageRectIn:box];
    if (NSIsEmptyRect(r))
        return;
    NSGraphicsContext *gc = [NSGraphicsContext currentContext];
    CGContextSaveGState([gc CGContext]);
    NSRectClip(box);
    [_image _drawInControlRect:r color:_tint ?: [NSColor labelColor] fraction:[self isEnabled] ? 1 : 0.5];
    CGContextRestoreGState([gc CGContext]);
}
@end
