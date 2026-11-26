/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: drawing a layer tree with Ferry's Core Graphics.
 * Each layer is drawn in its own bounds space, in the order Apple's
 * documentation gives: the background colour (inside the rounded corners),
 * then the contents (placed by the contents gravity) or what the layer's
 * kind draws, then the sublayers (by zPosition, through the sublayer
 * transform and geometryFlipped), then the border on top; all inside the
 * rounded bounds when masksToBounds is set, and composited as one at the
 * layer's opacity. A layer's transform is drawn as its 2D part. Images
 * are always drawn the right way up on the page. A layer casts its shadow
 * (freemac 1.253): from its shadowPath when it has one, else from all it
 * draws (background, contents, sublayers and border) taken as one, as Apple
 * documents. A mask keeps the layer only where the mask layer is opaque
 * (freemac 1.254). contentsRect picks a part of the image and contentsCenter
 * stretches it in nine parts (freemac 1.255). Filters aren't drawn yet. */
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

/* A rectangle in the unit space of the layer's contents (contentsRect,
 * contentsCenter) as whole pixels of the image, counted from its top row.
 * The unit space is the layer's own: y = 0 is the edge at its minimum y,
 * which is the image's bottom unless the space is drawn flipped. Only the
 * part inside the image is kept. */
static CGRect unit_to_pixels(CGRect u, CGImageRef img, BOOL flipped)
{
    double w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    double y = flipped ? u.origin.y : 1 - u.origin.y - u.size.height;
    CGRect px = CGRectMake(round(u.origin.x * w), round(y * h), 0, 0);
    px.size.width = round((u.origin.x + u.size.width) * w) - px.origin.x;
    px.size.height = round((y + u.size.height) * h) - px.origin.y;
    return CGRectIntersection(CGRectStandardize(px), CGRectMake(0, 0, w, h));
}

/* The image drawn into r in nine parts, as contentsCenter asks: the corners
 * outside the centre keep their size (shrunk alike when r is too small for
 * them), the edges stretch one way and the centre both. */
static void draw_stretched(CGContextRef ctx, CGRect r, CGImageRef img, CGRect c, double scale, BOOL flipped)
{
    double w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    if (CGRectIsNull(c)) /* a centre outside the image: the middle of it */
        c = CGRectMake(floor(w / 2), floor(h / 2), 0, 0);
    double sx[4] = {0, c.origin.x, CGRectGetMaxX(c), w}, sy[4] = {0, c.origin.y, CGRectGetMaxY(c), h};
    double left = sx[1] / scale, right = (w - sx[2]) / scale, top = sy[1] / scale, bottom = (h - sy[2]) / scale;
    double fx = left + right > r.size.width ? r.size.width / (left + right) : 1;
    double fy = top + bottom > r.size.height ? r.size.height / (top + bottom) : 1;
    double dx[4] = {0, left * fx, r.size.width - right * fx, r.size.width};
    double dy[4] = {0, top * fy, r.size.height - bottom * fy, r.size.height}; /* from the top down */
    for (int i = 0; i < 3; i++)
        for (int j = 0; j < 3; j++) {
            CGRect src = CGRectMake(sx[j], sy[i], sx[j + 1] - sx[j], sy[i + 1] - sy[i]);
            double dw = dx[j + 1] - dx[j], dh = dy[i + 1] - dy[i];
            if (src.size.width < 1 || src.size.height < 1 || dw <= 0 || dh <= 0)
                continue;
            CGImageRef piece = CGImageCreateWithImageInRect(img, src);
            if (!piece)
                continue;
            double y = flipped ? r.origin.y + dy[i] : CGRectGetMaxY(r) - dy[i + 1];
            draw_upright(ctx, CGRectMake(r.origin.x + dx[j], y, dw, dh), piece, flipped);
            CGImageRelease(piece);
        }
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
    CGImageRef part = NULL;
    CGRect cr = QRect(v, @"contentsRect");
    if (!CGRectEqualToRect(cr, CGRectMake(0, 0, 1, 1))) {
        CGRect px = unit_to_pixels(cr, img, flipped);
        if (px.size.width < 1 || px.size.height < 1)
            return;
        part = CGImageCreateWithImageInRect(img, px);
        if (!part)
            return;
        img = part;
    }
    CGSize size = CGSizeMake(CGImageGetWidth(img) / scale, CGImageGetHeight(img) / scale);
    CGRect r = gravity_rect(v[@"contentsGravity"], b, size);
    CGContextSaveGState(ctx);
    if ([v[@"magnificationFilter"] isEqual:kCAFilterNearest])
        CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    CGRect center = QRect(v, @"contentsCenter");
    if (CGRectEqualToRect(center, CGRectMake(0, 0, 1, 1)))
        draw_upright(ctx, r, img, flipped);
    else
        draw_stretched(ctx, r, img, unit_to_pixels(center, img, flipped), scale, flipped);
    CGContextRestoreGState(ctx);
    if (part)
        CGImageRelease(part);
}

/* Sets the layer's shadow in the context, if it casts one: its colour at
 * shadowOpacity, its offset (in the layer's superlayer's space, as the
 * layer is placed) and its radius taken to the base space Core Graphics
 * keeps shadows in. A layer's shadowRadius is a Gaussian's, Core Graphics's
 * blur twice that. */
static BOOL set_shadow(NSDictionary *v, CGContextRef ctx)
{
    double opacity = QNum(v, @"shadowOpacity");
    CGColorRef color = QColor(v, @"shadowColor");
    if (opacity <= 0 || !color || CGColorGetAlpha(color) <= 0)
        return NO;
    CGAffineTransform m = CGContextGetCTM(ctx);
    m.tx = m.ty = 0;
    CGSize off = CGSizeApplyAffineTransform(QSize(v, @"shadowOffset"), m);
    double scale = sqrt(fabs(m.a * m.d - m.b * m.c));
    CGColorRef c = CGColorCreateCopyWithAlpha(color, CGColorGetAlpha(color) * fmin(opacity, 1));
    CGContextSetShadowWithColor(ctx, off, 2 * fmax(QNum(v, @"shadowRadius"), 0) * scale, c);
    CGColorRelease(c);
    return YES;
}

static NSDictionary *values_of(CALayer *l, BOOL pres)
{
    return pres ? [l _ferryPresentationValues] : [l _ferryValues];
}

static void apply_mask(CALayer *mask, CGContextRef ctx, BOOL pres, BOOL flipped);

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
    BOOL shadowed = set_shadow(v, ctx), fromPath = shadowed && v[@"shadowPath"];
    if (fromPath) {
        /* the path's shadow under the layer, the layer itself unshadowed */
        CGContextSaveGState(ctx);
        CGContextSetAlpha(ctx, GSTATE((GContext *)ctx)->alpha * opacity);
        GContextSetDrawsShadowsOnly(ctx, YES);
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        CGContextBeginPath(ctx);
        CGContextAddPath(ctx, (CGPathRef)v[@"shadowPath"]);
        CGContextFillPath(ctx);
        GContextSetDrawsShadowsOnly(ctx, NO);
        CGContextRestoreGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    }
    CALayer *mask = [l mask];
    BOOL group = opacity < 1 || (shadowed && !fromPath) || mask;
    if (group) {
        CGContextSetAlpha(ctx, GSTATE((GContext *)ctx)->alpha * opacity);
        CGContextBeginTransparencyLayer(ctx, NULL);
    }
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
    if (mask)
        apply_mask(mask, ctx, pres, flipped);
    if (group)
        CGContextEndTransparencyLayer(ctx);
    CGContextRestoreGState(ctx);
}

/* A mask: what the layer drew so far (in its transparency layer) is kept
 * only as far as the mask layer, drawn in the layer's own space as placed
 * by its frame, is opaque; its colours don't count (freemac 1.254). */
static void apply_mask(CALayer *mask, CGContextRef ctx, BOOL pres, BOOL flipped)
{
    NSDictionary *mv = values_of(mask, pres);
    CGAffineTransform m = placement(mv);
    CGContextSaveGState(ctx);
    CGContextSetAlpha(ctx, 1);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 0, NULL);
    /* the transparency layer goes onto what is there in the blend mode in
     * force when it began, the mask drawn in it as usual */
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    CGContextBeginTransparencyLayer(ctx, NULL);
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    CGContextConcatCTM(ctx, m);
    render_layer(mask, mv, ctx, pres, flipped ^ reverses(m), nil);
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
