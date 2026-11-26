/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: drawing a layer tree with Ferry's Core Graphics.
 * Each layer is drawn in its own bounds space, in the order Apple's
 * documentation gives: the background colour (inside the rounded corners),
 * then the contents (placed by the contents gravity) or what the layer's
 * kind draws, then the sublayers (by zPosition, through the sublayer
 * transform and geometryFlipped), then the border on top; all inside the
 * rounded bounds when masksToBounds is set, and composited as one at the
 * layer's opacity. A layer's transform is drawn as its 2D part. Images
 * are always drawn the right way up on the page. Shadows, masks and
 * filters aren't drawn yet. */
#import "QInternal.h"

/* From a layer's bounds space to the space its superlayer puts sublayers
 * in: position + transform(p - (bounds.origin + anchorPoint * size)). */
static CGAffineTransform placement(NSDictionary *v)
{
    CGRect b = QRect(v, @"bounds");
    CGPoint ap = QPoint(v, @"anchorPoint"), pos = QPoint(v, @"position");
    CGAffineTransform t = CGAffineTransformMakeTranslation(-(b.origin.x + ap.x * b.size.width),
                                                           -(b.origin.y + ap.y * b.size.height));
    t = CGAffineTransformConcat(t, QAffine2D(QTransform(v, @"transform")));
    return CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(pos.x, pos.y));
}

/* From the space a layer puts its sublayers in to its bounds space: its
 * geometryFlipped flip, then its sublayer transform about its anchor point. */
static CGAffineTransform sublayer_space(NSDictionary *v)
{
    CGRect b = QRect(v, @"bounds");
    CGAffineTransform m = CGAffineTransformIdentity;
    if (QBool(v, @"geometryFlipped"))
        m = CGAffineTransformMake(1, 0, 0, -1, 0, 2 * b.origin.y + b.size.height);
    CATransform3D st = QTransform(v, @"sublayerTransform");
    if (!CATransform3DIsIdentity(st)) {
        CGPoint ap = QPoint(v, @"anchorPoint");
        double cx = b.origin.x + ap.x * b.size.width, cy = b.origin.y + ap.y * b.size.height;
        CGAffineTransform s = CGAffineTransformMakeTranslation(-cx, -cy);
        s = CGAffineTransformConcat(s, QAffine2D(st));
        s = CGAffineTransformConcat(s, CGAffineTransformMakeTranslation(cx, cy));
        m = CGAffineTransformConcat(m, s);
    }
    return m;
}

CGAffineTransform QLayerToSuperlayer(NSDictionary *v, CALayer *layer)
{
    CGAffineTransform m = placement(v);
    CALayer *super = [layer superlayer];
    if (super)
        m = CGAffineTransformConcat(m, sublayer_space([super _ferryValues]));
    return m;
}

static BOOL reverses(CGAffineTransform m) { return m.a * m.d - m.b * m.c < 0; }

/* The bounds with rounded corners, as Apple's documentation describes:
 * maskedCorners names the corners (by minimum and maximum x and y) that are
 * rounded. */
static CGPathRef rounded(CGRect r, double radius, NSUInteger corners)
{
    r = CGRectStandardize(r);
    radius = fmin(radius, fmin(r.size.width, r.size.height) / 2);
    if (radius <= 0 || !(corners & 15))
        return CGPathCreateWithRect(r, NULL);
    double x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    double rMinMin = corners & kCALayerMinXMinYCorner ? radius : 0;
    double rMaxMin = corners & kCALayerMaxXMinYCorner ? radius : 0;
    double rMaxMax = corners & kCALayerMaxXMaxYCorner ? radius : 0;
    double rMinMax = corners & kCALayerMinXMaxYCorner ? radius : 0;
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, x0 + rMinMin, y0);
    CGPathAddLineToPoint(p, NULL, x1 - rMaxMin, y0);
    if (rMaxMin)
        CGPathAddArcToPoint(p, NULL, x1, y0, x1, y0 + rMaxMin, rMaxMin);
    CGPathAddLineToPoint(p, NULL, x1, y1 - rMaxMax);
    if (rMaxMax)
        CGPathAddArcToPoint(p, NULL, x1, y1, x1 - rMaxMax, y1, rMaxMax);
    CGPathAddLineToPoint(p, NULL, x0 + rMinMax, y1);
    if (rMinMax)
        CGPathAddArcToPoint(p, NULL, x0, y1, x0, y1 - rMinMax, rMinMax);
    CGPathAddLineToPoint(p, NULL, x0, y0 + rMinMin);
    if (rMinMin)
        CGPathAddArcToPoint(p, NULL, x0, y0, x0 + rMinMin, y0, rMinMin);
    CGPathCloseSubpath(p);
    return p;
}

static void surface_done(void *info, const void *data, size_t size)
{
    (void)data;
    (void)size;
    [(id)info release];
}

/* An IOSurface as layer contents (Qt's backing store gives one): its BGRA
 * pixels, read in place, while the image keeps the surface. Asked through
 * the IOSurface class's own methods, so Core Animation needn't link it. */
static CGImageRef surface_image(id s)
{
    if (((OSType(*)(id, SEL))objc_msgSend)(s, @selector(pixelFormat)) != 'BGRA') {
        QWarnOnce("IOSurface contents other than BGRA");
        return NULL;
    }
    size_t w = (size_t)((NSInteger(*)(id, SEL))objc_msgSend)(s, @selector(width));
    size_t h = (size_t)((NSInteger(*)(id, SEL))objc_msgSend)(s, @selector(height));
    size_t row = (size_t)((NSInteger(*)(id, SEL))objc_msgSend)(s, @selector(bytesPerRow));
    void *base = ((void *(*)(id, SEL))objc_msgSend)(s, @selector(baseAddress));
    if (!w || !h || !base || row < w * 4)
        return NULL;
    CGDataProviderRef p = CGDataProviderCreateWithData([s retain], base, row * h, surface_done);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate(w, h, 8, 32, row, cs, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
                                   p, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs);
    CGDataProviderRelease(p);
    return img ? (CGImageRef)[(id)img autorelease] : NULL;
}

/* contents as an image: a CGImage, anything that gives one (NSImage), or an IOSurface */
static CGImageRef image_of(id contents)
{
    if (!contents)
        return NULL;
    if ([contents isKindOfClass:[GImage class]])
        return (CGImageRef)contents;
    Class surface = objc_getClass("IOSurface");
    if (surface && [contents isKindOfClass:surface])
        return surface_image(contents);
    SEL s = @selector(CGImageForProposedRect:context:hints:);
    if ([contents respondsToSelector:s])
        return ((CGImageRef(*)(id, SEL, CGRect *, id, id))objc_msgSend)(contents, s, NULL, nil, nil);
    QWarnOnce("layer contents other than images");
    return NULL;
}

/* Where the contents go in the bounds. "Top" is the maximum y and "bottom"
 * the minimum, in the layer's own space, whichever way up it is drawn. */
static CGRect gravity_rect(NSString *g, CGRect b, CGSize s)
{
    if (!g || [g isEqualToString:kCAGravityResize] || s.width <= 0 || s.height <= 0)
        return b;
    if ([g isEqualToString:kCAGravityResizeAspect] || [g isEqualToString:kCAGravityResizeAspectFill]) {
        double fx = b.size.width / s.width, fy = b.size.height / s.height;
        double f = [g isEqualToString:kCAGravityResizeAspect] ? fmin(fx, fy) : fmax(fx, fy);
        s = CGSizeMake(s.width * f, s.height * f);
    }
    double x = CGRectGetMidX(b) - s.width / 2, y = CGRectGetMidY(b) - s.height / 2;
    if ([g hasSuffix:@"Left"] || [g isEqualToString:kCAGravityLeft])
        x = CGRectGetMinX(b);
    if ([g hasSuffix:@"Right"] || [g isEqualToString:kCAGravityRight])
        x = CGRectGetMaxX(b) - s.width;
    if ([g hasPrefix:@"top"])
        y = CGRectGetMaxY(b) - s.height;
    if ([g hasPrefix:@"bottom"])
        y = CGRectGetMinY(b);
    return CGRectMake(x, y, s.width, s.height);
}

/* Draws an image upright on the page in r, however the space is turned. */
static void draw_upright(CGContextRef ctx, CGRect r, CGImageRef img, BOOL flipped)
{
    if (!flipped) {
        CGContextDrawImage(ctx, r, img);
        return;
    }
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, 0, 2 * r.origin.y + r.size.height);
    CGContextScaleCTM(ctx, 1, -1);
    CGContextDrawImage(ctx, r, img);
    CGContextRestoreGState(ctx);
}

/* whether a property the layer's class redraws for is animating */
static BOOL redraws_while_animating(CALayer *l)
{
    Class cls = [l class];
    for (QRunning *r in [l _ferryRunning]) {
        if (![r->animation isKindOfClass:[CAPropertyAnimation class]])
            continue;
        NSString *path = [(CAPropertyAnimation *)r->animation keyPath];
        NSString *first = [[path componentsSeparatedByString:@"."] firstObject];
        if (first && [cls needsDisplayForKey:first])
            return YES;
    }
    return NO;
}

static void draw_contents(CALayer *l, NSDictionary *v, CGContextRef ctx, BOOL flipped, BOOL pres)
{
    CGRect b = QRect(v, @"bounds");
    if (pres && redraws_while_animating(l)) {
        /* drawn afresh, with the values shown now */
        CALayer *p = [l presentationLayer];
        CGContextSaveGState(ctx);
        CGContextClipToRect(ctx, b);
        [p drawInContext:ctx];
        CGContextRestoreGState(ctx);
        return;
    }
    CGImageRef img = image_of(v[@"contents"]);
    if (!img)
        return;
    double scale = QNum(v, @"contentsScale");
    if (scale <= 0)
        scale = 1;
    CGSize size = CGSizeMake(CGImageGetWidth(img) / scale, CGImageGetHeight(img) / scale);
    if (!CGRectEqualToRect(QRect(v, @"contentsRect"), CGRectMake(0, 0, 1, 1)))
        QWarnOnce("contentsRect");
    if (!CGRectEqualToRect(QRect(v, @"contentsCenter"), CGRectMake(0, 0, 1, 1)))
        QWarnOnce("contentsCenter");
    CGRect r = gravity_rect(v[@"contentsGravity"], b, size);
    CGContextSaveGState(ctx);
    if ([v[@"magnificationFilter"] isEqual:kCAFilterNearest])
        CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    draw_upright(ctx, r, img, flipped);
    CGContextRestoreGState(ctx);
}

static NSDictionary *values_of(CALayer *l, BOOL pres)
{
    return pres ? [l _ferryPresentationValues] : [l _ferryValues];
}

static void render_layer(CALayer *l, NSDictionary *v, CGContextRef ctx, BOOL pres, BOOL flipped,
                         void (^content)(CGContextRef))
{
    if (pres)
        [l _ferryMarkRendered];   /* shown: its changes animate from now on */
    [l displayIfNeeded];
    if (QBool(v, @"hidden"))
        return;
    double opacity = QNum(v, @"opacity");
    if (opacity <= 0)
        return;
    CGRect b = QRect(v, @"bounds");
    CGContextSaveGState(ctx);
    BOOL group = opacity < 1;
    if (group) {
        CGContextSetAlpha(ctx, GSTATE((GContext *)ctx)->alpha * opacity);
        CGContextBeginTransparencyLayer(ctx, NULL);
    }
    if (QNum(v, @"shadowOpacity") > 0)
        QWarnOnce("layer shadows");
    if ([l mask])
        QWarnOnce("layer masks");
    if ([v[@"filters"] count] || [v[@"backgroundFilters"] count] || v[@"compositingFilter"])
        QWarnOnce("layer filters");
    double radius = QNum(v, @"cornerRadius");
    NSUInteger corners = [v[@"maskedCorners"] unsignedIntegerValue];
    CGPathRef shape = rounded(b, radius, corners);

    CGColorRef bg = QColor(v, @"backgroundColor");
    if (bg && CGColorGetAlpha(bg) > 0) {
        CGContextSaveGState(ctx);
        CGContextSetFillColorWithColor(ctx, bg);
        CGContextBeginPath(ctx);
        CGContextAddPath(ctx, shape);
        CGContextFillPath(ctx);
        CGContextRestoreGState(ctx);
    }

    BOOL clip = QBool(v, @"masksToBounds");
    if (clip) {
        CGContextSaveGState(ctx);
        CGContextBeginPath(ctx);
        CGContextAddPath(ctx, shape);
        CGContextClip(ctx);
    }
    draw_contents(l, v, ctx, flipped, pres);
    CGContextSaveGState(ctx);
    [l _ferryDrawContentWithValues:v inContext:ctx flipped:flipped];
    CGContextRestoreGState(ctx);
    if (content) {
        CGContextSaveGState(ctx);
        content(ctx);
        CGContextRestoreGState(ctx);
    }

    NSArray *subs = [[[l _ferrySublayers] copy] autorelease];
    if ([subs count]) {
        CGContextSaveGState(ctx);
        CGAffineTransform space = sublayer_space(v);
        CGContextConcatCTM(ctx, space);
        BOOL subFlipped = flipped ^ reverses(space);
        /* by zPosition, keeping the order of equal ones */
        NSUInteger n = [subs count];
        NSDictionary **sv = calloc(n, sizeof *sv);
        NSUInteger *order = calloc(n, sizeof *order);
        for (NSUInteger i = 0; i < n; i++) {
            sv[i] = values_of(subs[i], pres);
            order[i] = i;
        }
        for (NSUInteger i = 1; i < n; i++)
            for (NSUInteger j = i; j > 0 && QNum(sv[order[j - 1]], @"zPosition") > QNum(sv[order[j]], @"zPosition"); j--) {
                NSUInteger t = order[j];
                order[j] = order[j - 1];
                order[j - 1] = t;
            }
        for (NSUInteger k = 0; k < n; k++) {
            NSUInteger i = order[k];
            CGAffineTransform m = placement(sv[i]);
            CGContextSaveGState(ctx);
            CGContextConcatCTM(ctx, m);
            render_layer(subs[i], sv[i], ctx, pres, subFlipped ^ reverses(m), nil);
            CGContextRestoreGState(ctx);
        }
        free(sv);
        free(order);
        CGContextRestoreGState(ctx);
    }
    if (clip)
        CGContextRestoreGState(ctx);

    double bw = QNum(v, @"borderWidth");
    CGColorRef bc = QColor(v, @"borderColor");
    if (bw > 0 && bc && CGColorGetAlpha(bc) > 0) {
        CGPathRef edge = rounded(CGRectInset(b, bw / 2, bw / 2), fmax(radius - bw / 2, 0), corners);
        CGContextSaveGState(ctx);
        CGContextSetStrokeColorWithColor(ctx, bc);
        CGContextSetLineWidth(ctx, bw);
        CGContextBeginPath(ctx);
        CGContextAddPath(ctx, edge);
        CGContextStrokePath(ctx);
        CGContextRestoreGState(ctx);
        CGPathRelease(edge);
    }
    CGPathRelease(shape);
    if (group)
        CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

void FerryCALayerRender(CALayer *layer, CGContextRef ctx, BOOL presentation, BOOL flipped,
                        void (^content)(CGContextRef ctx))
{
    if (!layer || !ctx)
        return;
    @autoreleasepool {
        CALayer *model = [layer modelLayer];
        [model layoutIfNeeded];
        render_layer(model, values_of(model, presentation), ctx, presentation, flipped, content);
    }
}

CGAffineTransform FerryCALayerPresentationOffset(CALayer *layer)
{
    NSDictionary *model = [layer _ferryValues];
    if (![[layer _ferryRunning] count] && CATransform3DIsIdentity(QTransform(model, @"transform")))
        return CGAffineTransformIdentity;
    NSMutableDictionary *base = [[model mutableCopy] autorelease];
    base[@"transform"] = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    CGAffineTransform shown = placement([layer _ferryPresentationValues]);
    return CGAffineTransformConcat(shown, CGAffineTransformInvert(placement(base)));
}
