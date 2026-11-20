/* SPDX-License-Identifier: GPL-3.0-or-later
 * Paths: lists of moves, lines, curves and closes. Arcs, ellipses and
 * rounded rectangles are turned into cubic Bézier curves when they are
 * added, as on a Mac, so CGPathApply reports curves for them. Containment
 * and tight bounds are worked out by Cairo. */
#import "GInternal.h"

/* ---- shapes made of curves, sent to any sink -------------------------------------- */

static CGPoint pt(CGFloat x, CGFloat y) { return CGPointMake(x, y); }

void GSinkQuad(const struct gsink *s, CGPoint c, CGPoint p)
{
    CGPoint p0;
    if (!s->current(s->info, &p0)) {
        s->move(s->info, c);
        p0 = c;
    }
    CGPoint c1 = pt(p0.x + 2.0 / 3 * (c.x - p0.x), p0.y + 2.0 / 3 * (c.y - p0.y));
    CGPoint c2 = pt(p.x + 2.0 / 3 * (c.x - p.x), p.y + 2.0 / 3 * (c.y - p.y));
    s->curve(s->info, c1, c2, p);
}

/* An arc from angle a0 sweeping by delta (positive is counter-clockwise when
 * y points up), in pieces of at most a quarter turn. */
static void arc_sweep(const struct gsink *s, CGFloat x, CGFloat y, CGFloat r, CGFloat a0, CGFloat delta, BOOL lineIn)
{
    CGPoint first = pt(x + r * cos(a0), y + r * sin(a0));
    CGPoint cur;
    if (lineIn && s->current(s->info, &cur))
        s->line(s->info, first);
    else
        s->move(s->info, first);
    if (delta == 0 || r == 0)
        return;
    int pieces = (int)ceil(fabs(delta) / (M_PI / 2) - 1e-9);
    if (pieces < 1)
        pieces = 1;
    CGFloat step = delta / pieces;
    CGFloat k = 4.0 / 3 * tan(step / 4);
    for (int i = 0; i < pieces; i++) {
        CGFloat t0 = a0 + i * step, t1 = t0 + step;
        CGFloat c0 = cos(t0), s0 = sin(t0), c1 = cos(t1), s1 = sin(t1);
        s->curve(s->info, pt(x + r * (c0 - k * s0), y + r * (s0 + k * c0)),
                 pt(x + r * (c1 + k * s1), y + r * (s1 - k * c1)), pt(x + r * c1, y + r * s1));
    }
}

void GSinkArc(const struct gsink *s, CGFloat x, CGFloat y, CGFloat r, CGFloat start, CGFloat end, BOOL clockwise)
{
    CGFloat delta = end - start;
    if (clockwise) {
        /* Sweeping towards smaller angles, at most one full turn. */
        if (delta > 0)
            delta = fmod(delta, 2 * M_PI) - 2 * M_PI;
        else if (delta < -2 * M_PI)
            delta = -fmod(-delta, 2 * M_PI);
    } else {
        if (delta < 0)
            delta = 2 * M_PI - fmod(-delta, 2 * M_PI);
        else if (delta > 2 * M_PI)
            delta = fmod(delta, 2 * M_PI);
    }
    if (fabs(end - start) >= 2 * M_PI)
        delta = clockwise ? -2 * M_PI : 2 * M_PI;
    arc_sweep(s, x, y, fabs(r), start, delta, YES);
}

void GSinkArcToPoint(const struct gsink *s, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2, CGFloat r)
{
    CGPoint p0;
    if (!s->current(s->info, &p0)) {
        s->move(s->info, pt(x1, y1));
        p0 = pt(x1, y1);
    }
    CGFloat ax = p0.x - x1, ay = p0.y - y1, bx = x2 - x1, by = y2 - y1;
    CGFloat la = hypot(ax, ay), lb = hypot(bx, by);
    CGFloat cross = ax * by - ay * bx;
    if (r <= 0 || la == 0 || lb == 0 || fabs(cross) < 1e-12 * la * lb) {
        s->line(s->info, pt(x1, y1));
        return;
    }
    ax /= la, ay /= la, bx /= lb, by /= lb;
    CGFloat angle = acos(fmax(-1, fmin(1, ax * bx + ay * by)));   /* between the two legs */
    CGFloat d = r / tan(angle / 2);
    CGPoint t1 = pt(x1 + ax * d, y1 + ay * d), t2 = pt(x1 + bx * d, y1 + by * d);
    /* The centre lies along the bisector, r / sin(angle/2) from the corner. */
    CGFloat mx = ax + bx, my = ay + by, ml = hypot(mx, my);
    CGFloat cd = r / sin(angle / 2);
    CGFloat cx = x1 + mx / ml * cd, cy = y1 + my / ml * cd;
    CGFloat a0 = atan2(t1.y - cy, t1.x - cx), a1 = atan2(t2.y - cy, t2.x - cx);
    CGFloat delta = a1 - a0;
    while (delta > M_PI)
        delta -= 2 * M_PI;
    while (delta < -M_PI)
        delta += 2 * M_PI;
    arc_sweep(s, cx, cy, r, a0, delta, YES);
}

void GSinkRect(const struct gsink *s, CGRect r)
{
    s->move(s->info, pt(r.origin.x, r.origin.y));
    s->line(s->info, pt(r.origin.x + r.size.width, r.origin.y));
    s->line(s->info, pt(r.origin.x + r.size.width, r.origin.y + r.size.height));
    s->line(s->info, pt(r.origin.x, r.origin.y + r.size.height));
    s->close(s->info);
}

void GSinkEllipse(const struct gsink *s, CGRect r)
{
    r = CGRectStandardize(r);
    CGFloat cx = CGRectGetMidX(r), cy = CGRectGetMidY(r), rx = r.size.width / 2, ry = r.size.height / 2;
    const CGFloat k = 0.5522847498307936;   /* 4/3 (sqrt 2 - 1): a quarter circle as one curve */
    s->move(s->info, pt(cx + rx, cy));
    s->curve(s->info, pt(cx + rx, cy + k * ry), pt(cx + k * rx, cy + ry), pt(cx, cy + ry));
    s->curve(s->info, pt(cx - k * rx, cy + ry), pt(cx - rx, cy + k * ry), pt(cx - rx, cy));
    s->curve(s->info, pt(cx - rx, cy - k * ry), pt(cx - k * rx, cy - ry), pt(cx, cy - ry));
    s->curve(s->info, pt(cx + k * rx, cy - ry), pt(cx + rx, cy - k * ry), pt(cx + rx, cy));
    s->close(s->info);
}

void GSinkRoundedRect(const struct gsink *s, CGRect r, CGFloat cw, CGFloat ch)
{
    r = CGRectStandardize(r);
    cw = fmax(0, fmin(cw, r.size.width / 2));
    ch = fmax(0, fmin(ch, r.size.height / 2));
    if (cw == 0 || ch == 0) {
        GSinkRect(s, r);
        return;
    }
    CGFloat x0 = r.origin.x, y0 = r.origin.y, x1 = CGRectGetMaxX(r), y1 = CGRectGetMaxY(r);
    const CGFloat k = 0.5522847498307936;
    s->move(s->info, pt(x1 - cw, y0));
    s->curve(s->info, pt(x1 - cw + k * cw, y0), pt(x1, y0 + ch - k * ch), pt(x1, y0 + ch));
    s->line(s->info, pt(x1, y1 - ch));
    s->curve(s->info, pt(x1, y1 - ch + k * ch), pt(x1 - cw + k * cw, y1), pt(x1 - cw, y1));
    s->line(s->info, pt(x0 + cw, y1));
    s->curve(s->info, pt(x0 + cw - k * cw, y1), pt(x0, y1 - ch + k * ch), pt(x0, y1 - ch));
    s->line(s->info, pt(x0, y0 + ch));
    s->curve(s->info, pt(x0, y0 + ch - k * ch), pt(x0 + cw - k * cw, y0), pt(x0 + cw, y0));
    s->close(s->info);
}

/* ---- the path object ---------------------------------------------------------------- */

@implementation GPath

- (void)dealloc
{
    free(elems);
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone { return [self mutableCopyWithZone:zone]; }

- (id)mutableCopyWithZone:(NSZone *)zone
{
    GPath *p = [[GPath alloc] init];
    p->count = p->cap = count;
    p->elems = malloc((count ? count : 1) * sizeof *elems);
    memcpy(p->elems, elems, count * sizeof *elems);
    p->start = start;
    p->current = current;
    p->hasCurrent = hasCurrent;
    return p;
}

static int npoints(CGPathElementType t)
{
    switch (t) {
    case kCGPathElementMoveToPoint:
    case kCGPathElementAddLineToPoint: return 1;
    case kCGPathElementAddQuadCurveToPoint: return 2;
    case kCGPathElementAddCurveToPoint: return 3;
    default: return 0;
    }
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[GPath class]])
        return NO;
    GPath *o = other;
    if (o->count != count)
        return NO;
    for (size_t i = 0; i < count; i++) {
        if (o->elems[i].type != elems[i].type)
            return NO;
        for (int k = 0; k < npoints(elems[i].type); k++)
            if (!CGPointEqualToPoint(o->elems[i].pts[k], elems[i].pts[k]))
                return NO;
    }
    return YES;
}

- (NSUInteger)hash { return count; }

- (NSString *)description { return [NSString stringWithFormat:@"<CGPath %p>", self]; }

@end

static void add_elem(GPath *p, CGPathElementType type, CGPoint a, CGPoint b, CGPoint c)
{
    if (p->count == p->cap) {
        p->cap = p->cap ? p->cap * 2 : 16;
        p->elems = realloc(p->elems, p->cap * sizeof *p->elems);
    }
    struct gelem *e = &p->elems[p->count++];
    e->type = type;
    e->pts[0] = a;
    e->pts[1] = b;
    e->pts[2] = c;
    switch (type) {
    case kCGPathElementMoveToPoint:
        p->start = p->current = a;
        p->hasCurrent = YES;
        break;
    case kCGPathElementAddLineToPoint: p->current = a; break;
    case kCGPathElementAddQuadCurveToPoint: p->current = b; break;
    case kCGPathElementAddCurveToPoint: p->current = c; break;
    case kCGPathElementCloseSubpath: p->current = p->start; break;
    }
}

/* A sink that adds to a path, through an optional transform. */
struct path_sink {
    GPath *path;
    const CGAffineTransform *m;
};

static CGPoint tx(struct path_sink *ps, CGPoint p) { return ps->m ? CGPointApplyAffineTransform(p, *ps->m) : p; }
static void ps_move(void *i, CGPoint p) { add_elem(((struct path_sink *)i)->path, kCGPathElementMoveToPoint, tx(i, p), p, p); }
static void ps_line(void *i, CGPoint p)
{
    struct path_sink *ps = i;
    add_elem(ps->path, kCGPathElementAddLineToPoint, tx(i, p), p, p);
}
static void ps_curve(void *i, CGPoint a, CGPoint b, CGPoint c)
{
    add_elem(((struct path_sink *)i)->path, kCGPathElementAddCurveToPoint, tx(i, a), tx(i, b), tx(i, c));
}
static void ps_close(void *i)
{
    GPath *p = ((struct path_sink *)i)->path;
    if (p->hasCurrent)
        add_elem(p, kCGPathElementCloseSubpath, CGPointZero, CGPointZero, CGPointZero);
}
static BOOL ps_current(void *i, CGPoint *out)
{
    struct path_sink *ps = i;
    if (!ps->path->hasCurrent)
        return NO;
    CGPoint p = ps->path->current;
    if (ps->m) /* the shape is built in the caller's space, before the transform */
        p = CGPointApplyAffineTransform(p, CGAffineTransformInvert(*ps->m));
    *out = p;
    return YES;
}

#define PATH_SINK(name, path, m)                                                                                  \
    struct path_sink name##_info = {(GPath *)(path), (m)};                                                        \
    struct gsink name = {ps_move, ps_line, ps_curve, ps_close, ps_current, &name##_info}

CGMutablePathRef CGPathCreateMutable(void) { return (CGMutablePathRef)[[GPath alloc] init]; }
CGPathRef CGPathCreateCopy(CGPathRef path) { return path ? (CGPathRef)[OBJ(path) copy] : NULL; }
CGMutablePathRef CGPathCreateMutableCopy(CGPathRef path) { return path ? (CGMutablePathRef)[OBJ(path) mutableCopy] : NULL; }

CGMutablePathRef CGPathCreateMutableCopyByTransformingPath(CGPathRef path, const CGAffineTransform *m)
{
    if (!path)
        return NULL;
    GPath *p = [OBJ(path) mutableCopy];
    if (m) {
        for (size_t i = 0; i < p->count; i++)
            for (int k = 0; k < npoints(p->elems[i].type); k++)
                p->elems[i].pts[k] = CGPointApplyAffineTransform(p->elems[i].pts[k], *m);
        p->start = CGPointApplyAffineTransform(p->start, *m);
        p->current = CGPointApplyAffineTransform(p->current, *m);
    }
    return (CGMutablePathRef)p;
}

CGPathRef CGPathCreateCopyByTransformingPath(CGPathRef path, const CGAffineTransform *m)
{
    return CGPathCreateMutableCopyByTransformingPath(path, m);
}

CGPathRef CGPathCreateWithRect(CGRect rect, const CGAffineTransform *m)
{
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddRect(p, m, rect);
    return p;
}

CGPathRef CGPathCreateWithEllipseInRect(CGRect rect, const CGAffineTransform *m)
{
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddEllipseInRect(p, m, rect);
    return p;
}

CGPathRef CGPathCreateWithRoundedRect(CGRect rect, CGFloat cw, CGFloat ch, const CGAffineTransform *m)
{
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddRoundedRect(p, m, rect, cw, ch);
    return p;
}

CGPathRef CGPathRetain(CGPathRef path) { return (CGPathRef)[OBJ(path) retain]; }
void CGPathRelease(CGPathRef path) { [OBJ(path) release]; }
bool CGPathEqualToPath(CGPathRef a, CGPathRef b) { return a == b || (a && b && [OBJ(a) isEqual:OBJ(b)]); }

void CGPathMoveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y)
{
    PATH_SINK(s, path, m);
    s.move(s.info, pt(x, y));
}

void CGPathAddLineToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y)
{
    PATH_SINK(s, path, m);
    s.line(s.info, pt(x, y));
}

void CGPathAddQuadCurveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat cpx, CGFloat cpy,
                               CGFloat x, CGFloat y)
{
    PATH_SINK(s, path, m);
    (void)s;
    GPath *p = (GPath *)path;
    add_elem(p, kCGPathElementAddQuadCurveToPoint, tx(&s_info, pt(cpx, cpy)), tx(&s_info, pt(x, y)), CGPointZero);
}

void CGPathAddCurveToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat cp1x, CGFloat cp1y,
                           CGFloat cp2x, CGFloat cp2y, CGFloat x, CGFloat y)
{
    PATH_SINK(s, path, m);
    s.curve(s.info, pt(cp1x, cp1y), pt(cp2x, cp2y), pt(x, y));
}

void CGPathCloseSubpath(CGMutablePathRef path)
{
    PATH_SINK(s, path, NULL);
    s.close(s.info);
}

void CGPathAddRect(CGMutablePathRef path, const CGAffineTransform *m, CGRect rect)
{
    PATH_SINK(s, path, m);
    GSinkRect(&s, rect);
}

void CGPathAddRects(CGMutablePathRef path, const CGAffineTransform *m, const CGRect *rects, size_t count)
{
    for (size_t i = 0; i < count; i++)
        CGPathAddRect(path, m, rects[i]);
}

void CGPathAddLines(CGMutablePathRef path, const CGAffineTransform *m, const CGPoint *points, size_t count)
{
    PATH_SINK(s, path, m);
    for (size_t i = 0; i < count; i++)
        (i ? s.line : s.move)(s.info, points[i]);
}

void CGPathAddEllipseInRect(CGMutablePathRef path, const CGAffineTransform *m, CGRect rect)
{
    PATH_SINK(s, path, m);
    GSinkEllipse(&s, rect);
}

void CGPathAddRoundedRect(CGMutablePathRef path, const CGAffineTransform *m, CGRect rect, CGFloat cw, CGFloat ch)
{
    PATH_SINK(s, path, m);
    GSinkRoundedRect(&s, rect, cw, ch);
}

void CGPathAddArc(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y, CGFloat radius,
                  CGFloat startAngle, CGFloat endAngle, bool clockwise)
{
    PATH_SINK(s, path, m);
    GSinkArc(&s, x, y, radius, startAngle, endAngle, clockwise);
}

void CGPathAddRelativeArc(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x, CGFloat y, CGFloat radius,
                          CGFloat startAngle, CGFloat delta)
{
    PATH_SINK(s, path, m);
    arc_sweep(&s, x, y, radius, startAngle, delta, YES);
}

void CGPathAddArcToPoint(CGMutablePathRef path, const CGAffineTransform *m, CGFloat x1, CGFloat y1, CGFloat x2,
                         CGFloat y2, CGFloat radius)
{
    PATH_SINK(s, path, m);
    GSinkArcToPoint(&s, x1, y1, x2, y2, radius);
}

void CGPathAddPath(CGMutablePathRef path1, const CGAffineTransform *m, CGPathRef path2)
{
    GPath *src = [OBJ(path2) copy];
    GPath *dst = (GPath *)path1;
    for (size_t i = 0; i < src->count; i++) {
        struct gelem e = src->elems[i];
        if (m)
            for (int k = 0; k < npoints(e.type); k++)
                e.pts[k] = CGPointApplyAffineTransform(e.pts[k], *m);
        add_elem(dst, e.type, e.pts[0], e.pts[1], e.pts[2]);
    }
    [src release];
}

bool CGPathIsEmpty(CGPathRef path) { return !path || ((GPath *)path)->count == 0; }

bool CGPathIsRect(CGPathRef path, CGRect *rect)
{
    GPath *p = (GPath *)path;
    if (!p || p->count < 4 || p->count > 6 || p->elems[0].type != kCGPathElementMoveToPoint)
        return false;
    size_t n = p->count;
    if (p->elems[n - 1].type == kCGPathElementCloseSubpath)
        n--;
    CGPoint q[5];
    size_t nq = 0;
    for (size_t i = 0; i < n; i++) {
        if (i && p->elems[i].type != kCGPathElementAddLineToPoint)
            return false;
        q[nq++] = p->elems[i].pts[0];
    }
    if (nq == 5) {
        if (!CGPointEqualToPoint(q[4], q[0]))
            return false;
        nq = 4;
    }
    if (nq != 4)
        return false;
    for (int i = 0; i < 4; i++) {
        CGPoint a = q[i], b = q[(i + 1) % 4];
        if (a.x != b.x && a.y != b.y)
            return false;
    }
    if (!((q[0].x == q[1].x) != (q[1].x == q[2].x)))
        return false;
    if (rect) {
        CGFloat x0 = fmin(q[0].x, q[2].x), y0 = fmin(q[0].y, q[2].y);
        *rect = CGRectMake(x0, y0, fabs(q[2].x - q[0].x), fabs(q[2].y - q[0].y));
    }
    return true;
}

CGPoint CGPathGetCurrentPoint(CGPathRef path)
{
    GPath *p = (GPath *)path;
    return p && p->hasCurrent ? p->current : CGPointZero;
}

CGRect CGPathGetBoundingBox(CGPathRef path)
{
    GPath *p = (GPath *)path;
    if (!p || !p->count)
        return CGRectNull;
    CGFloat x0 = INFINITY, y0 = INFINITY, x1 = -INFINITY, y1 = -INFINITY;
    for (size_t i = 0; i < p->count; i++)
        for (int k = 0; k < npoints(p->elems[i].type); k++) {
            CGPoint q = p->elems[i].pts[k];
            x0 = fmin(x0, q.x), y0 = fmin(y0, q.y), x1 = fmax(x1, q.x), y1 = fmax(y1, q.y);
        }
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

/* A throwaway Cairo context for questions about a path's shape. */
static cairo_t *scratch(cairo_surface_t **surface)
{
    *surface = cairo_image_surface_create(CAIRO_FORMAT_A8, 1, 1);
    return cairo_create(*surface);
}

static void done(cairo_t *cr, cairo_surface_t *surface)
{
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
}

CGRect CGPathGetPathBoundingBox(CGPathRef path)
{
    GPath *p = (GPath *)path;
    if (!p || !p->count)
        return CGRectNull;
    cairo_surface_t *surface;
    cairo_t *cr = scratch(&surface);
    GPathToCairo(p, cr);
    double x0, y0, x1, y1;
    cairo_path_extents(cr, &x0, &y0, &x1, &y1);
    done(cr, surface);
    if (x0 == 0 && y0 == 0 && x1 == 0 && y1 == 0) /* only moves, which Cairo leaves out */
        return CGPathGetBoundingBox(path);
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

bool CGPathContainsPoint(CGPathRef path, const CGAffineTransform *m, CGPoint point, bool eoFill)
{
    GPath *p = (GPath *)path;
    if (!p || !p->count)
        return false;
    if (m)
        point = CGPointApplyAffineTransform(point, CGAffineTransformInvert(*m));
    cairo_surface_t *surface;
    cairo_t *cr = scratch(&surface);
    GPathToCairo(p, cr);
    cairo_set_fill_rule(cr, eoFill ? CAIRO_FILL_RULE_EVEN_ODD : CAIRO_FILL_RULE_WINDING);
    bool inside = cairo_in_fill(cr, point.x, point.y);
    done(cr, surface);
    return inside;
}

void CGPathApply(CGPathRef path, void *info, CGPathApplierFunction function)
{
    GPath *p = [OBJ(path) copy];
    for (size_t i = 0; i < p->count; i++) {
        CGPathElement e = {p->elems[i].type, p->elems[i].pts};
        function(info, &e);
    }
    [p release];
}

CFTypeID CGPathGetTypeID(void) { return (CFTypeID)[GPath class]; }

/* ---- to and from Cairo ------------------------------------------------------------- */

void GPathToCairo(GPath *p, cairo_t *cr)
{
    CGPoint cur = CGPointZero;
    for (size_t i = 0; i < p->count; i++) {
        struct gelem *e = &p->elems[i];
        switch (e->type) {
        case kCGPathElementMoveToPoint:
            cairo_move_to(cr, e->pts[0].x, e->pts[0].y);
            cur = e->pts[0];
            break;
        case kCGPathElementAddLineToPoint:
            cairo_line_to(cr, e->pts[0].x, e->pts[0].y);
            cur = e->pts[0];
            break;
        case kCGPathElementAddQuadCurveToPoint: {
            CGPoint c = e->pts[0], q = e->pts[1];
            if (cairo_has_current_point(cr))
                cairo_get_current_point(cr, &cur.x, &cur.y);
            cairo_curve_to(cr, cur.x + 2.0 / 3 * (c.x - cur.x), cur.y + 2.0 / 3 * (c.y - cur.y),
                           q.x + 2.0 / 3 * (c.x - q.x), q.y + 2.0 / 3 * (c.y - q.y), q.x, q.y);
            cur = q;
            break;
        }
        case kCGPathElementAddCurveToPoint:
            cairo_curve_to(cr, e->pts[0].x, e->pts[0].y, e->pts[1].x, e->pts[1].y, e->pts[2].x, e->pts[2].y);
            cur = e->pts[2];
            break;
        case kCGPathElementCloseSubpath:
            cairo_close_path(cr);
            break;
        }
    }
}

GPath *GPathFromCairo(cairo_t *cr)
{
    GPath *p = [[GPath alloc] init];
    cairo_path_t *cp = cairo_copy_path(cr);
    for (int i = 0; cp && i < cp->num_data; i += cp->data[i].header.length) {
        cairo_path_data_t *d = &cp->data[i];
        switch (d->header.type) {
        case CAIRO_PATH_MOVE_TO:
            /* Cairo adds a move back to the start after each close; a Mac path doesn't. */
            if (p->count && p->elems[p->count - 1].type == kCGPathElementCloseSubpath &&
                d[1].point.x == p->start.x && d[1].point.y == p->start.y)
                break;
            add_elem(p, kCGPathElementMoveToPoint, pt(d[1].point.x, d[1].point.y), CGPointZero, CGPointZero);
            break;
        case CAIRO_PATH_LINE_TO:
            add_elem(p, kCGPathElementAddLineToPoint, pt(d[1].point.x, d[1].point.y), CGPointZero, CGPointZero);
            break;
        case CAIRO_PATH_CURVE_TO:
            add_elem(p, kCGPathElementAddCurveToPoint, pt(d[1].point.x, d[1].point.y), pt(d[2].point.x, d[2].point.y),
                     pt(d[3].point.x, d[3].point.y));
            break;
        case CAIRO_PATH_CLOSE_PATH:
            add_elem(p, kCGPathElementCloseSubpath, CGPointZero, CGPointZero, CGPointZero);
            break;
        }
    }
    if (cp)
        cairo_path_destroy(cp);
    return p;
}
