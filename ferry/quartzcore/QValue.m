/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Core Animation: animated values. Each value an animation can
 * blend (a number, point, size, rectangle, 3D transform or colour) is taken
 * apart into numbers, blended, added or subtracted, and put together again;
 * arrays of those are blended element by element and paths point by point.
 * Also the structure fields that key paths may name ("position.x",
 * "transform.rotation.z"), as Apple's documentation of Core Animation's
 * key-value coding extensions lists them. */
#import "QInternal.h"

/* ---- colours ------------------------------------------------------------------------------ */

BOOL QIsColor(id v) { return [v isKindOfClass:[GColor class]]; }
BOOL QIsPath(id v) { return [v isKindOfClass:[GPath class]]; }

void QColorRGBA(CGColorRef color, double rgba[4])
{
    if (!color) {
        rgba[0] = rgba[1] = rgba[2] = rgba[3] = 0;
        return;
    }
    memcpy(rgba, ((GColor *)color)->rgba, 4 * sizeof(double));
}

/* ---- taking values apart -------------------------------------------------------------------- */

QKind QValueRead(id value, struct qval *v)
{
    memset(v, 0, sizeof *v);
    if (!value)
        return v->kind = QV_NONE;
    if ([value isKindOfClass:[QTransformValue class]]) {
        memcpy(v->d, &((QTransformValue *)value)->t, sizeof(CATransform3D));
        return v->kind = QV_TRANSFORM;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        v->d[0] = [value doubleValue];
        return v->kind = QV_NUMBER;
    }
    if ([value isKindOfClass:[NSValue class]]) {
        const char *t = [value objCType];
        if (!strncmp(t, "{CGPoint=", 9)) {
            NSPoint p = [value pointValue];
            v->d[0] = p.x, v->d[1] = p.y;
            return v->kind = QV_POINT;
        }
        if (!strncmp(t, "{CGSize=", 8)) {
            NSSize s = [value sizeValue];
            v->d[0] = s.width, v->d[1] = s.height;
            return v->kind = QV_SIZE;
        }
        if (!strncmp(t, "{CGRect=", 8)) {
            NSRect r = [value rectValue];
            v->d[0] = r.origin.x, v->d[1] = r.origin.y, v->d[2] = r.size.width, v->d[3] = r.size.height;
            return v->kind = QV_RECT;
        }
        return v->kind = QV_OTHER;
    }
    if (QIsColor(value)) {
        QColorRGBA((CGColorRef)value, v->d);
        return v->kind = QV_COLOR;
    }
    return v->kind = QV_OTHER;
}

id QValueMake(const struct qval *v)
{
    switch (v->kind) {
    case QV_NUMBER: return [NSNumber numberWithDouble:v->d[0]];
    case QV_POINT: return [NSValue valueWithPoint:NSMakePoint(v->d[0], v->d[1])];
    case QV_SIZE: return [NSValue valueWithSize:NSMakeSize(v->d[0], v->d[1])];
    case QV_RECT: return [NSValue valueWithRect:NSMakeRect(v->d[0], v->d[1], v->d[2], v->d[3])];
    case QV_TRANSFORM: {
        CATransform3D t;
        memcpy(&t, v->d, sizeof t);
        return [NSValue valueWithCATransform3D:t];
    }
    case QV_COLOR: {
        double c[4];
        for (int i = 0; i < 4; i++)
            c[i] = fmax(0, fmin(1, v->d[i]));
        return [(id)CGColorCreateSRGB(c[0], c[1], c[2], c[3]) autorelease];
    }
    default: return nil;
    }
}

static int count_of(QKind k)
{
    switch (k) {
    case QV_NUMBER: return 1;
    case QV_POINT:
    case QV_SIZE: return 2;
    case QV_RECT:
    case QV_COLOR: return 4;
    case QV_TRANSFORM: return 16;
    default: return 0;
    }
}

/* A 2D transform as scale, shear, rotation and translation: its top rows
 * are [sx 0; m sy] times a rotation by r. */
struct qdecomp {
    double sx, sy, m, r, tx, ty;
};
static BOOL decompose(const double *d, struct qdecomp *o)
{
    CATransform3D t;
    memcpy(&t, d, sizeof t);
    if (!CATransform3DIsAffine(t))
        return NO;
    o->sx = hypot(t.m11, t.m12);
    if (o->sx == 0)
        return NO;
    o->r = atan2(t.m12, t.m11);
    double c = cos(o->r), s = sin(o->r);
    o->m = t.m21 * c + t.m22 * s;
    o->sy = -t.m21 * s + t.m22 * c;
    o->tx = t.m41, o->ty = t.m42;
    return YES;
}
static void recompose(const struct qdecomp *o, double *d)
{
    CATransform3D t = CATransform3DIdentity;
    double c = cos(o->r), s = sin(o->r);
    t.m11 = o->sx * c, t.m12 = o->sx * s;
    t.m21 = o->m * c - o->sy * s, t.m22 = o->m * s + o->sy * c;
    t.m41 = o->tx, t.m42 = o->ty;
    memcpy(d, &t, sizeof t);
}

void QValueBlend(const struct qval *a, const struct qval *b, double t, struct qval *out)
{
    *out = *a;
    if (a->kind == QV_TRANSFORM) {
        struct qdecomp x, y;
        if (decompose(a->d, &x) && decompose(b->d, &y)) {
            /* the shorter way round */
            if (y.r - x.r > M_PI)
                y.r -= 2 * M_PI;
            else if (x.r - y.r > M_PI)
                y.r += 2 * M_PI;
            struct qdecomp z = {x.sx + (y.sx - x.sx) * t, x.sy + (y.sy - x.sy) * t, x.m + (y.m - x.m) * t,
                                x.r + (y.r - x.r) * t, x.tx + (y.tx - x.tx) * t, x.ty + (y.ty - x.ty) * t};
            recompose(&z, out->d);
            return;
        }
    }
    for (int i = 0; i < count_of(a->kind); i++)
        out->d[i] = a->d[i] + (b->d[i] - a->d[i]) * t;
}

void QValueAdd(const struct qval *a, const struct qval *b, struct qval *out)
{
    *out = *a;
    if (a->kind == QV_TRANSFORM) {
        CATransform3D x, y, z;
        memcpy(&x, a->d, sizeof x);
        memcpy(&y, b->d, sizeof y);
        z = CATransform3DConcat(x, y);
        memcpy(out->d, &z, sizeof z);
        return;
    }
    for (int i = 0; i < count_of(a->kind); i++)
        out->d[i] = a->d[i] + b->d[i];
}

void QValueSubtract(const struct qval *a, const struct qval *b, struct qval *out)
{
    *out = *a;
    if (a->kind == QV_TRANSFORM) {
        CATransform3D x, y, z;
        memcpy(&x, a->d, sizeof x);
        memcpy(&y, b->d, sizeof y);
        z = CATransform3DConcat(x, CATransform3DInvert(y));
        memcpy(out->d, &z, sizeof z);
        return;
    }
    for (int i = 0; i < count_of(a->kind); i++)
        out->d[i] = a->d[i] - b->d[i];
}

double QValueDistance(const struct qval *a, const struct qval *b)
{
    double s = 0;
    int n = a->kind == QV_TRANSFORM ? 16 : count_of(a->kind);
    for (int i = 0; i < n; i++)
        s += (b->d[i] - a->d[i]) * (b->d[i] - a->d[i]);
    return sqrt(s);
}

/* ---- paths ----------------------------------------------------------------------------- */

struct pathpts {
    CGPathElementType *types;
    CGPoint *pts;
    size_t ntypes, npts, cap, tcap;
};
static int points_for(CGPathElementType t)
{
    switch (t) {
    case kCGPathElementMoveToPoint:
    case kCGPathElementAddLineToPoint: return 1;
    case kCGPathElementAddQuadCurveToPoint: return 2;
    case kCGPathElementAddCurveToPoint: return 3;
    default: return 0;
    }
}
static void collect(void *info, const CGPathElement *e)
{
    struct pathpts *p = info;
    if (p->ntypes == p->tcap) {
        p->tcap = p->tcap ? p->tcap * 2 : 16;
        p->types = realloc(p->types, p->tcap * sizeof *p->types);
    }
    p->types[p->ntypes++] = e->type;
    for (int i = 0; i < points_for(e->type); i++) {
        if (p->npts == p->cap) {
            p->cap = p->cap ? p->cap * 2 : 32;
            p->pts = realloc(p->pts, p->cap * sizeof *p->pts);
        }
        p->pts[p->npts++] = e->points[i];
    }
}

static id blend_paths(CGPathRef a, CGPathRef b, double t)
{
    struct pathpts x = {0}, y = {0};
    CGPathApply(a, &x, collect);
    CGPathApply(b, &y, collect);
    id result = nil;
    if (x.ntypes == y.ntypes && x.npts == y.npts && (!x.ntypes || !memcmp(x.types, y.types, x.ntypes * sizeof *x.types))) {
        CGMutablePathRef p = CGPathCreateMutable();
        size_t k = 0;
        for (size_t i = 0; i < x.ntypes; i++) {
            CGPoint q[3];
            for (int j = 0; j < points_for(x.types[i]); j++, k++)
                q[j] = CGPointMake(x.pts[k].x + (y.pts[k].x - x.pts[k].x) * t,
                                   x.pts[k].y + (y.pts[k].y - x.pts[k].y) * t);
            switch (x.types[i]) {
            case kCGPathElementMoveToPoint: CGPathMoveToPoint(p, NULL, q[0].x, q[0].y); break;
            case kCGPathElementAddLineToPoint: CGPathAddLineToPoint(p, NULL, q[0].x, q[0].y); break;
            case kCGPathElementAddQuadCurveToPoint:
                CGPathAddQuadCurveToPoint(p, NULL, q[0].x, q[0].y, q[1].x, q[1].y);
                break;
            case kCGPathElementAddCurveToPoint:
                CGPathAddCurveToPoint(p, NULL, q[0].x, q[0].y, q[1].x, q[1].y, q[2].x, q[2].y);
                break;
            case kCGPathElementCloseSubpath: CGPathCloseSubpath(p); break;
            }
        }
        result = [(id)p autorelease];
    } else {
        QWarnOnce("blending paths with different shapes (the path is swapped instead)");
        result = t < 0.5 ? (id)a : (id)b;
    }
    free(x.types), free(x.pts), free(y.types), free(y.pts);
    return result;
}

/* ---- any value ---------------------------------------------------------------------------- */

id QBlend(id from, id to, double t)
{
    if ([from isKindOfClass:[NSArray class]] && [to isKindOfClass:[NSArray class]] && [from count] == [to count]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[from count]];
        for (NSUInteger i = 0; i < [from count]; i++) {
            id v = QBlend(from[i], to[i], t);
            [out addObject:v ?: [NSNull null]];
        }
        return out;
    }
    if (QIsPath(from) && QIsPath(to))
        return blend_paths((CGPathRef)from, (CGPathRef)to, t);
    struct qval a, b, r;
    QKind ka = QValueRead(from, &a), kb = QValueRead(to, &b);
    /* a colour from or to none: the colour, clear */
    if (ka == QV_NONE && kb == QV_COLOR) {
        a = b, a.d[3] = 0, ka = QV_COLOR;
    } else if (kb == QV_NONE && ka == QV_COLOR) {
        b = a, b.d[3] = 0, kb = QV_COLOR;
    }
    if (ka == kb && ka != QV_OTHER && ka != QV_NONE) {
        QValueBlend(&a, &b, t, &r);
        return QValueMake(&r);
    }
    return t < 0.5 ? from : to;
}

static id combine(id a, id b, BOOL add)
{
    if ([a isKindOfClass:[NSArray class]] && [b isKindOfClass:[NSArray class]] && [a count] == [b count]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[a count]];
        for (NSUInteger i = 0; i < [a count]; i++)
            [out addObject:combine(a[i], b[i], add) ?: [NSNull null]];
        return out;
    }
    struct qval x, y, r;
    QKind kx = QValueRead(a, &x), ky = QValueRead(b, &y);
    if (kx == QV_NONE)
        return add ? b : nil;
    if (ky == QV_NONE)
        return a;
    if (kx != ky || kx == QV_OTHER)
        return add ? b : a;
    (add ? QValueAdd : QValueSubtract)(&x, &y, &r);
    return QValueMake(&r);
}
id QAdd(id a, id b) { return combine(a, b, YES); }
id QSubtract(id a, id b) { return combine(a, b, NO); }

BOOL QValuesEqual(id a, id b)
{
    if (a == b)
        return YES;
    if (!a || !b)
        return NO;
    if (QIsColor(a) && QIsColor(b))
        return CGColorEqualToColor((CGColorRef)a, (CGColorRef)b);
    if (QIsPath(a) && QIsPath(b))
        return CGPathEqualToPath((CGPathRef)a, (CGPathRef)b);
    return [a isEqual:b];
}

/* ---- structure fields ------------------------------------------------------------------- */

/* A transform's parts, as its "rotation", "scale" and "translation" fields
 * read and write them: 2D ones are taken apart exactly, others only as
 * far as their translation and diagonal. */
struct tparts {
    double tx, ty, tz, sx, sy, sz, rx, ry, rz;
};
static struct tparts transform_parts(CATransform3D t)
{
    struct tparts p = {t.m41, t.m42, t.m43, 1, 1, t.m33, 0, 0, 0};
    struct qdecomp d;
    if (decompose(&t.m11, &d)) {
        p.sx = d.sx, p.sy = d.sy, p.rz = d.r;
    } else {
        p.sx = hypot(t.m11, t.m12), p.sy = hypot(t.m21, t.m22), p.rz = atan2(t.m12, t.m11);
        p.sz = hypot(t.m31, t.m33);
    }
    return p;
}
static CATransform3D transform_from(struct tparts p)
{
    CATransform3D t = CATransform3DMakeScale(p.sx, p.sy, p.sz);
    if (p.rx)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(p.rx, 1, 0, 0));
    if (p.ry)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(p.ry, 0, 1, 0));
    if (p.rz)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(p.rz, 0, 0, 1));
    return CATransform3DConcat(t, CATransform3DMakeTranslation(p.tx, p.ty, p.tz));
}

static double *tfield(struct tparts *p, NSString *f, int *count)
{
    *count = 1;
    if ([f isEqualToString:@"rotation"] || [f isEqualToString:@"rotation.z"])
        return &p->rz;
    if ([f isEqualToString:@"rotation.x"])
        return &p->rx;
    if ([f isEqualToString:@"rotation.y"])
        return &p->ry;
    if ([f isEqualToString:@"scale.x"])
        return &p->sx;
    if ([f isEqualToString:@"scale.y"])
        return &p->sy;
    if ([f isEqualToString:@"scale.z"])
        return &p->sz;
    if ([f isEqualToString:@"translation.x"])
        return &p->tx;
    if ([f isEqualToString:@"translation.y"])
        return &p->ty;
    if ([f isEqualToString:@"translation.z"])
        return &p->tz;
    if ([f isEqualToString:@"scale"]) {
        *count = 3;
        return &p->sx;
    }
    if ([f isEqualToString:@"translation"]) {
        *count = 2;
        return &p->tx;
    }
    return NULL;
}

id QFieldGet(id whole, NSString *field)
{
    struct qval v;
    QKind k = QValueRead(whole, &v);
    NSRange dot = [field rangeOfString:@"."];
    NSString *first = dot.location == NSNotFound ? field : [field substringToIndex:dot.location];
    NSString *rest = dot.location == NSNotFound ? nil : [field substringFromIndex:dot.location + 1];
    switch (k) {
    case QV_POINT:
        if ([field isEqualToString:@"x"])
            return @(v.d[0]);
        if ([field isEqualToString:@"y"])
            return @(v.d[1]);
        break;
    case QV_SIZE:
        if ([field isEqualToString:@"width"])
            return @(v.d[0]);
        if ([field isEqualToString:@"height"])
            return @(v.d[1]);
        break;
    case QV_RECT: {
        id part = nil;
        if ([first isEqualToString:@"origin"])
            part = [NSValue valueWithPoint:NSMakePoint(v.d[0], v.d[1])];
        else if ([first isEqualToString:@"size"])
            part = [NSValue valueWithSize:NSMakeSize(v.d[2], v.d[3])];
        return rest ? QFieldGet(part, rest) : part;
    }
    case QV_TRANSFORM: {
        CATransform3D t;
        memcpy(&t, v.d, sizeof t);
        struct tparts p = transform_parts(t);
        int n;
        double *f = tfield(&p, field, &n);
        if (!f)
            break;
        if (n == 3)   /* the average of the three */
            return @((p.sx + p.sy + p.sz) / 3);
        if (n == 2)
            return [NSValue valueWithSize:NSMakeSize(p.tx, p.ty)];
        return @(*f);
    }
    default: break;
    }
    return nil;
}

id QFieldSet(id whole, NSString *field, id part)
{
    struct qval v, pv;
    QKind k = QValueRead(whole, &v);
    QValueRead(part, &pv);
    NSRange dot = [field rangeOfString:@"."];
    NSString *first = dot.location == NSNotFound ? field : [field substringToIndex:dot.location];
    NSString *rest = dot.location == NSNotFound ? nil : [field substringFromIndex:dot.location + 1];
    double x = [part respondsToSelector:@selector(doubleValue)] ? [part doubleValue] : 0;
    switch (k) {
    case QV_POINT:
        if ([field isEqualToString:@"x"])
            v.d[0] = x;
        else if ([field isEqualToString:@"y"])
            v.d[1] = x;
        return QValueMake(&v);
    case QV_SIZE:
        if ([field isEqualToString:@"width"])
            v.d[0] = x;
        else if ([field isEqualToString:@"height"])
            v.d[1] = x;
        return QValueMake(&v);
    case QV_RECT: {
        BOOL origin = [first isEqualToString:@"origin"];
        if (!origin && ![first isEqualToString:@"size"])
            return whole;
        id sub = origin ? [NSValue valueWithPoint:NSMakePoint(v.d[0], v.d[1])]
                        : [NSValue valueWithSize:NSMakeSize(v.d[2], v.d[3])];
        sub = rest ? QFieldSet(sub, rest, part) : part;
        struct qval s;
        QValueRead(sub, &s);
        v.d[origin ? 0 : 2] = s.d[0];
        v.d[origin ? 1 : 3] = s.d[1];
        return QValueMake(&v);
    }
    case QV_TRANSFORM: {
        CATransform3D t;
        memcpy(&t, v.d, sizeof t);
        struct tparts p = transform_parts(t);
        int n;
        double *f = tfield(&p, field, &n);
        if (!f)
            return whole;
        if (n == 3)
            p.sx = p.sy = p.sz = x;
        else if (n == 2)
            p.tx = pv.d[0], p.ty = pv.d[1];
        else
            *f = x;
        return [NSValue valueWithCATransform3D:transform_from(p)];
    }
    default: return whole;
    }
}

id QValueAtKeyPath(NSDictionary *values, NSString *keyPath, CALayer *layer)
{
    NSRange dot = [keyPath rangeOfString:@"."];
    if (dot.location == NSNotFound)
        return values[keyPath];
    id whole = values[[keyPath substringToIndex:dot.location]];
    return QFieldGet(whole, [keyPath substringFromIndex:dot.location + 1]);
}

void QSetValueAtKeyPath(NSMutableDictionary *values, NSString *keyPath, id value, CALayer *layer)
{
    NSRange dot = [keyPath rangeOfString:@"."];
    NSString *key = dot.location == NSNotFound ? keyPath : [keyPath substringToIndex:dot.location];
    if (dot.location != NSNotFound)
        value = QFieldSet(values[key], [keyPath substringFromIndex:dot.location + 1], value);
    if (value)
        values[key] = value;
    else
        [values removeObjectForKey:key];
}
