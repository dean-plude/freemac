/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Text on Pango and HarfBuzz. Fonts are this system's: a Mac font name
 * is matched to the nearest family that is installed (Helvetica, SF and
 * Lucida Grande become the system's sans-serif font, which on freemac is
 * Inter; Menlo, Monaco and Courier its monospace font; Times its serif one),
 * and the font reports its real name. Lines and frames are laid out by
 * Pango, which shapes text with HarfBuzz and falls back to other fonts for
 * characters the chosen font lacks. Sizes are in points, one point being
 * one unit of user space, as on a Mac. */
#import "GInternal.h"
#include <objc/message.h>

const CFStringRef kCTFontAttributeName = (CFStringRef)@"NSFont";
const CFStringRef kCTForegroundColorAttributeName = (CFStringRef)@"CTForegroundColor";
const CFStringRef kCTForegroundColorFromContextAttributeName = (CFStringRef)@"CTForegroundColorFromContext";
const CFStringRef kCTKernAttributeName = (CFStringRef)@"NSKern";
const CFStringRef kCTUnderlineStyleAttributeName = (CFStringRef)@"NSUnderline";
const CFStringRef kCTUnderlineColorAttributeName = (CFStringRef)@"CTUnderlineColor";
const CFStringRef kCTStrokeWidthAttributeName = (CFStringRef)@"NSStrokeWidth";
const CFStringRef kCTStrokeColorAttributeName = (CFStringRef)@"CTStrokeColor";
const CFStringRef kCTParagraphStyleAttributeName = (CFStringRef)@"NSParagraphStyle";
const CFStringRef kCTLigatureAttributeName = (CFStringRef)@"NSLigature";

/* AppKit's text attributes that Core Text draws too: a shadow (NSShadow,
 * under the run's glyphs) and an attachment (NSTextAttachment, an image in
 * the place of its U+FFFC character). AppKit's classes answer these. */
static NSString *const shadow_key = @"NSShadow", *const attachment_key = @"NSAttachment";
@interface NSObject (FerryTextDrawing)
- (CGSize)shadowOffset;
- (CGFloat)shadowBlurRadius;
- (id)shadowColor;
/* an attachment's box: x 0, y from the baseline (up), width and height */
- (CGRect)_ferryAttachmentBounds;
- (void)_ferryDrawAttachmentInRect:(CGRect)rect context:(CGContextRef)context;
@end

/* The Pango context everything is laid out in: 72 dots per inch, so a size
 * in points is a size in user-space units, and no hinting of metrics, so
 * widths scale exactly with the size. */
static PangoContext *pango_context(void)
{
    static PangoContext *context;
    if (!context) {
        context = pango_font_map_create_context(pango_cairo_font_map_get_default());
        pango_cairo_context_set_resolution(context, 72);
        cairo_font_options_t *options = cairo_font_options_create();
        cairo_font_options_set_hint_metrics(options, CAIRO_HINT_METRICS_OFF);
        cairo_font_options_set_hint_style(options, CAIRO_HINT_STYLE_NONE);
        pango_cairo_context_set_font_options(context, options);
        cairo_font_options_destroy(options);
        pango_context_set_round_glyph_positions(context, 0);
    }
    return context;
}

/* ---- fonts ------------------------------------------------------------------------ */

@implementation GFont

- (id)copyWithZone:(NSZone *)zone { return [self retain]; }

- (void)dealloc
{
    if (hb)
        hb_font_destroy(hb);
    if (font)
        g_object_unref(font);
    if (desc)
        pango_font_description_free(desc);
    [family release];
    [super dealloc];
}

- (BOOL)isEqual:(id)other
{
    if (![other isKindOfClass:[GFont class]])
        return NO;
    GFont *o = other;
    return o->size == size && o->weight == weight && o->style == style && [o->family isEqual:family];
}

- (NSUInteger)hash { return [family hash] ^ (NSUInteger)(size * 64) ^ (NSUInteger)weight; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CTFont %p> %@ %g pt", self, (NSString *)CTFontCopyPostScriptName((CTFontRef)self), size];
}

@end

static const struct { const char *mac, *family; } families[] = {
    {"helvetica", "sans-serif"},      {"helveticaneue", "sans-serif"}, {"arial", "sans-serif"},
    {"sfns", "sans-serif"},           {"sfnsdisplay", "sans-serif"},   {"sfnstext", "sans-serif"},
    {"sfpro", "sans-serif"},          {"sfprodisplay", "sans-serif"},  {"sfprotext", "sans-serif"},
    {"applesystemuifont", "sans-serif"}, {"systemfont", "sans-serif"}, {"lucidagrande", "sans-serif"},
    {"geneva", "sans-serif"},         {"verdana", "sans-serif"},       {"tahoma", "sans-serif"},
    {"menlo", "monospace"},           {"monaco", "monospace"},         {"courier", "monospace"},
    {"couriernew", "monospace"},      {"sfmono", "monospace"},         {"andalemono", "monospace"},
    {"times", "serif"},               {"timesnewroman", "serif"},      {"georgia", "serif"},
    {"palatino", "serif"},            {"newyork", "serif"},
};

static const struct { const char *word; int weight; } weights[] = {
    {"ultralight", PANGO_WEIGHT_THIN + 100}, {"thin", PANGO_WEIGHT_THIN}, {"semibold", PANGO_WEIGHT_SEMIBOLD},
    {"demibold", PANGO_WEIGHT_SEMIBOLD}, {"bold", PANGO_WEIGHT_BOLD},     {"light", PANGO_WEIGHT_LIGHT},
    {"medium", PANGO_WEIGHT_MEDIUM},       {"heavy", 800},                {"black", PANGO_WEIGHT_HEAVY},
};

/* "Helvetica-BoldOblique" -> sans-serif, bold, oblique. */
static void parse_name(NSString *name, NSString **family, int *weight, int *style)
{
    *weight = PANGO_WEIGHT_NORMAL;
    *style = PANGO_STYLE_NORMAL;
    const char *s = name.UTF8String;
    while (*s == '.')
        s++;
    char base[128], key[128];
    snprintf(base, sizeof base, "%s", s);
    char *dash = strchr(base, '-');
    const char *suffix = dash ? dash + 1 : "";
    if (dash)
        *dash = 0;
    /* the lower-case base name, without spaces, for matching */
    size_t k = 0;
    for (const char *p = base; *p && k + 1 < sizeof key; p++)
        if (*p != ' ')
            key[k++] = (char)tolower((unsigned char)*p);
    key[k] = 0;
    char style_words[128];
    snprintf(style_words, sizeof style_words, "%s", suffix);
    for (char *p = style_words; *p; p++)
        *p = (char)tolower((unsigned char)*p);
    *family = nil;
    for (size_t i = 0; i < sizeof families / sizeof families[0]; i++) {
        size_t n = strlen(families[i].mac);
        if (!strncmp(key, families[i].mac, n)) {
            /* "HelveticaNeue" also matches "helvetica"; take the rest as style words */
            if (key[n] && !*style_words)
                snprintf(style_words, sizeof style_words, "%s", key + n);
            *family = @(families[i].family);
        }
    }
    if (!*family)
        *family = [NSString stringWithUTF8String:base];
    for (size_t i = 0; i < sizeof weights / sizeof weights[0]; i++)
        if (strstr(style_words, weights[i].word)) {
            *weight = weights[i].weight;
            break;
        }
    if (strstr(style_words, "italic"))
        *style = PANGO_STYLE_ITALIC;
    else if (strstr(style_words, "oblique"))
        *style = PANGO_STYLE_OBLIQUE;
}

static GFont *load_font(NSString *family, int weight, int style, CGFloat size, const CGAffineTransform *matrix)
{
    if (size <= 0)
        size = 12;
    /* AppKit's NSFont is a Core Text font, as on a Mac (where the two are
     * toll-free bridged): when AppKit is loaded, fonts are made as NSFonts. */
    static Class cls;
    if (!cls)
        cls = objc_getClass("NSFont") ?: [GFont class];
    GFont *f = [[cls alloc] init];
    f->size = size;
    f->matrix = matrix ? *matrix : CGAffineTransformIdentity;
    f->desc = pango_font_description_new();
    pango_font_description_set_family(f->desc, family.UTF8String);
    pango_font_description_set_weight(f->desc, weight);
    pango_font_description_set_style(f->desc, style);
    pango_font_description_set_absolute_size(f->desc, size * PANGO_SCALE);
    f->font = pango_context_load_font(pango_context(), f->desc);
    if (!f->font) {
        [f release];
        return nil;
    }
    PangoFontDescription *real = pango_font_describe(f->font);
    const char *name = pango_font_description_get_family(real);
    f->family = [[NSString alloc] initWithUTF8String:name ? name : "Unknown"];
    f->weight = pango_font_description_get_weight(real);
    f->style = pango_font_description_get_style(real);
    pango_font_description_free(real);
    hb_face_t *face = hb_font_get_face(pango_font_get_hb_font(f->font));
    f->hb = hb_font_create(face);  /* scaled in font units */
    f->upem = hb_face_get_upem(face);
    hb_codepoint_t gi, gm;
    if (hb_font_get_nominal_glyph(f->hb, 'i', &gi) && hb_font_get_nominal_glyph(f->hb, 'M', &gm))
        f->monospace = hb_font_get_glyph_h_advance(f->hb, gi) == hb_font_get_glyph_h_advance(f->hb, gm);
    return f;
}

/* For Core Text's font descriptors (CTFontDescriptor.m). */
GFont *GFontLoad(NSString *family, int weight, int style, CGFloat size, const CGAffineTransform *matrix)
{
    return load_font(family, weight, style, size, matrix);
}

static CGFloat units(GFont *f, double v) { return v * f->size / f->upem; }

static GFont *default_font(void)
{
    static GFont *font;
    if (!font)
        font = load_font(@"sans-serif", PANGO_WEIGHT_NORMAL, PANGO_STYLE_NORMAL, 12, NULL);
    return font;
}

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix)
{
    NSString *family;
    int weight, style;
    parse_name(name ? (NSString *)name : @"Helvetica", &family, &weight, &style);
    return (CTFontRef)load_font(family, weight, style, size, matrix);
}

/* For AppKit's font manager: a font of an installed family, as named
 * (not mapped from a Mac name), with a Pango weight and style. */
GFont *GFontCreate(NSString *family, int weight, int style, CGFloat size) __attribute__((visibility("default")));
GFont *GFontCreate(NSString *family, int weight, int style, CGFloat size)
{
    return load_font(family, weight, style, size, NULL);
}

/* For AppKit's font manager: the family that stands for a Mac family
 * (Helvetica, Times, Menlo...), or nil for a name that isn't one. */
NSString *GFontMacFamily(NSString *name) __attribute__((visibility("default")));
NSString *GFontMacFamily(NSString *name)
{
    char key[128];
    size_t k = 0;
    for (const char *p = name.UTF8String ?: ""; *p && k + 1 < sizeof key; p++)
        if (*p != ' ' && *p != '.')
            key[k++] = (char)tolower((unsigned char)*p);
    key[k] = 0;
    for (size_t i = 0; i < sizeof families / sizeof families[0]; i++)
        if (!strcmp(key, families[i].mac))
            return @(families[i].family);
    return nil;
}

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType type, CGFloat size, CFStringRef language)
{
    static const struct { CGFloat size; BOOL bold, mono; } ui[] = {
        [kCTFontUIFontUser] = {12, NO, NO},
        [kCTFontUIFontUserFixedPitch] = {10, NO, YES},
        [kCTFontUIFontSystem] = {13, NO, NO},
        [kCTFontUIFontEmphasizedSystem] = {13, YES, NO},
        [kCTFontUIFontSmallSystem] = {11, NO, NO},
        [kCTFontUIFontSmallEmphasizedSystem] = {11, YES, NO},
        [kCTFontUIFontMiniSystem] = {9, NO, NO},
        [kCTFontUIFontMiniEmphasizedSystem] = {9, YES, NO},
        [kCTFontUIFontViews] = {12, NO, NO},
        [kCTFontUIFontApplication] = {13, NO, NO},
        [kCTFontUIFontLabel] = {10, NO, NO},
        [kCTFontUIFontMenuTitle] = {14, NO, NO},
        [kCTFontUIFontMenuItem] = {14, NO, NO},
        [kCTFontUIFontMenuItemMark] = {14, NO, NO},
        [kCTFontUIFontMenuItemCmdKey] = {14, NO, NO},
        [kCTFontUIFontWindowTitle] = {13, NO, NO},
        [kCTFontUIFontPushButton] = {13, NO, NO},
        [kCTFontUIFontUtilityWindowTitle] = {11, NO, NO},
        [kCTFontUIFontAlertHeader] = {13, YES, NO},
        [kCTFontUIFontSystemDetail] = {12, NO, NO},
        [kCTFontUIFontEmphasizedSystemDetail] = {12, YES, NO},
        [kCTFontUIFontToolbar] = {11, NO, NO},
        [kCTFontUIFontSmallToolbar] = {10, NO, NO},
        [kCTFontUIFontMessage] = {13, NO, NO},
        [kCTFontUIFontPalette] = {11, NO, NO},
        [kCTFontUIFontToolTip] = {11, NO, NO},
        [kCTFontUIFontControlContent] = {13, NO, NO},
    };
    if ((unsigned)type >= sizeof ui / sizeof ui[0])
        return NULL;
    return (CTFontRef)load_font(ui[type].mono ? @"monospace" : @"sans-serif",
                                ui[type].bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL, PANGO_STYLE_NORMAL,
                                size > 0 ? size : ui[type].size, NULL);
}

#define FONT ((GFont *)font)

CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                         CTFontDescriptorRef attributes)
{
    if (attributes)
        GWarnOnce("font descriptors");
    return (CTFontRef)load_font(FONT->family, FONT->weight, FONT->style, size > 0 ? size : FONT->size,
                                matrix ? matrix : &FONT->matrix);
}

CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                             CTFontSymbolicTraits value, CTFontSymbolicTraits mask)
{
    int weight = FONT->weight, style = FONT->style;
    if (mask & kCTFontTraitBold)
        weight = (value & kCTFontTraitBold) ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL;
    if (mask & kCTFontTraitItalic)
        style = (value & kCTFontTraitItalic) ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL;
    return (CTFontRef)load_font(FONT->family, weight, style, size > 0 ? size : FONT->size,
                                matrix ? matrix : &FONT->matrix);
}

CTFontRef CTFontCreateCopyWithFamily(CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
                                     CFStringRef family)
{
    NSString *mapped;
    int w, s;
    parse_name((NSString *)family, &mapped, &w, &s);
    return (CTFontRef)load_font(mapped, FONT->weight, FONT->style, size > 0 ? size : FONT->size,
                                matrix ? matrix : &FONT->matrix);
}

NSString *GFontStyleName(GFont *f)
{
    const char *w = f->weight >= 800   ? "Black"
                    : f->weight >= 700 ? "Bold"
                    : f->weight >= 600 ? "SemiBold"
                    : f->weight >= 500 ? "Medium"
                    : f->weight <= 200 ? "Thin"
                    : f->weight <= 300 ? "Light"
                                       : "";
    BOOL italic = f->style != PANGO_STYLE_NORMAL;
    if (!*w && !italic)
        return @"Regular";
    return [NSString stringWithFormat:@"%s%s", w, italic ? "Italic" : ""];
}

CFStringRef CTFontCopyFamilyName(CTFontRef font) { return (CFStringRef)[FONT->family copy]; }

CFStringRef CTFontCopyPostScriptName(CTFontRef font)
{
    NSString *family = [FONT->family stringByReplacingOccurrencesOfString:@" " withString:@""];
    return (CFStringRef)[[NSString alloc] initWithFormat:@"%@-%@", family, GFontStyleName(FONT)];
}

CFStringRef CTFontCopyFullName(CTFontRef font)
{
    NSString *style = GFontStyleName(FONT);
    if ([style isEqual:@"Regular"])
        return (CFStringRef)[FONT->family copy];
    return (CFStringRef)[[NSString alloc] initWithFormat:@"%@ %@", FONT->family, style];
}

CFStringRef CTFontCopyDisplayName(CTFontRef font) { return CTFontCopyFullName(font); }
CGFloat CTFontGetSize(CTFontRef font) { return FONT->size; }
CGAffineTransform CTFontGetMatrix(CTFontRef font) { return FONT->matrix; }

CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef font)
{
    CTFontSymbolicTraits t = 0;
    if (FONT->weight >= PANGO_WEIGHT_SEMIBOLD)
        t |= kCTFontTraitBold;
    if (FONT->style != PANGO_STYLE_NORMAL)
        t |= kCTFontTraitItalic;
    if (FONT->monospace)
        t |= kCTFontTraitMonoSpace;
    return t;
}

static hb_font_extents_t extents(GFont *f)
{
    hb_font_extents_t e;
    memset(&e, 0, sizeof e);
    hb_font_get_h_extents(f->hb, &e);
    return e;
}

CGFloat CTFontGetAscent(CTFontRef font) { return units(FONT, extents(FONT).ascender); }
CGFloat CTFontGetDescent(CTFontRef font) { return units(FONT, -extents(FONT).descender); }
CGFloat CTFontGetLeading(CTFontRef font) { return units(FONT, extents(FONT).line_gap); }
unsigned CTFontGetUnitsPerEm(CTFontRef font) { return FONT->upem; }
CFIndex CTFontGetGlyphCount(CTFontRef font) { return hb_face_get_glyph_count(hb_font_get_face(FONT->hb)); }

static CGFloat metric(GFont *f, uint32_t tag, CGFloat fallback)
{
    hb_position_t v;
    return hb_ot_metrics_get_position(f->hb, tag, &v) ? units(f, v) : fallback;
}

CGFloat CTFontGetCapHeight(CTFontRef font) { return metric(FONT, HB_TAG('c', 'p', 'h', 't'), CTFontGetAscent(font) * 0.7); }
CGFloat CTFontGetXHeight(CTFontRef font) { return metric(FONT, HB_TAG('x', 'h', 'g', 't'), CTFontGetAscent(font) * 0.5); }
CGFloat CTFontGetUnderlinePosition(CTFontRef font) { return metric(FONT, HB_TAG('u', 'n', 'd', 'o'), -FONT->size / 10); }
CGFloat CTFontGetUnderlineThickness(CTFontRef font) { return metric(FONT, HB_TAG('u', 'n', 'd', 's'), FONT->size / 15); }
CGFloat CTFontGetSlantAngle(CTFontRef font) { return FONT->style == PANGO_STYLE_NORMAL ? 0 : -12; }

CGRect CTFontGetBoundingBox(CTFontRef font)
{
    /* HarfBuzz doesn't give the font's own box; this is its usual extent. */
    CGFloat a = CTFontGetAscent(font), d = CTFontGetDescent(font);
    return CGRectMake(-FONT->size * 0.2, -d, FONT->size * 1.4, a + d);
}

bool CTFontGetGlyphsForCharacters(CTFontRef font, const UniChar *chars, CGGlyph *glyphs, CFIndex count)
{
    bool all = true;
    for (CFIndex i = 0; i < count; i++) {
        uint32_t cp = chars[i];
        BOOL pair = cp >= 0xD800 && cp < 0xDC00 && i + 1 < count && chars[i + 1] >= 0xDC00 && chars[i + 1] < 0xE000;
        if (pair)
            cp = 0x10000 + ((cp - 0xD800) << 10) + (chars[i + 1] - 0xDC00);
        hb_codepoint_t g = 0;
        if (!hb_font_get_nominal_glyph(FONT->hb, cp, &g)) {
            g = 0;
            all = false;
        }
        glyphs[i] = (CGGlyph)g;
        if (pair)
            glyphs[++i] = 0;
    }
    return all;
}

/* The characters the font has glyphs for, from its character map
 * (freemac 1.266; Chromium asks to decide which font draws a character). */
CFCharacterSetRef CTFontCopyCharacterSet(CTFontRef font)
{
    NSMutableCharacterSet *set = [[NSMutableCharacterSet alloc] init];
    hb_set_t *codes = hb_set_create();
    hb_face_collect_unicodes(hb_font_get_face(FONT->hb), codes);
    hb_codepoint_t first = (hb_codepoint_t)-1, last = 0;
    while (hb_set_next_range(codes, &first, &last))
        [set addCharactersInRange:NSMakeRange(first, (NSUInteger)last - first + 1)];
    hb_set_destroy(codes);
    return (CFCharacterSetRef)set;
}

double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph *glyphs,
                                  CGSize *advances, CFIndex count)
{
    double total = 0;
    for (CFIndex i = 0; i < count; i++) {
        CGFloat a = units(FONT, hb_font_get_glyph_h_advance(FONT->hb, glyphs[i]));
        if (advances)
            advances[i] = CGSizeMake(a, 0);
        total += a;
    }
    return total;
}

CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph *glyphs,
                                       CGRect *rects, CFIndex count)
{
    CGRect all = CGRectNull;
    for (CFIndex i = 0; i < count; i++) {
        hb_glyph_extents_t e;
        CGRect r = CGRectZero;
        if (hb_font_get_glyph_extents(FONT->hb, glyphs[i], &e))
            r = CGRectStandardize(CGRectMake(units(FONT, e.x_bearing), units(FONT, e.y_bearing + e.height),
                                             units(FONT, e.width), units(FONT, -e.height)));
        if (rects)
            rects[i] = r;
        if (!CGRectIsEmpty(r))
            all = CGRectUnion(all, r);
    }
    return CGRectIsNull(all) ? CGRectZero : all;
}

CGPathRef CTFontCreatePathForGlyph(CTFontRef font, CGGlyph glyph, const CGAffineTransform *matrix)
{
    cairo_surface_t *s = cairo_image_surface_create(CAIRO_FORMAT_A8, 1, 1);
    cairo_t *cr = cairo_create(s);
    /* Flip, so the outline comes out with y going up. */
    cairo_matrix_t flip = {1, 0, 0, -1, 0, 0};
    cairo_set_matrix(cr, &flip);
    cairo_set_scaled_font(cr, pango_cairo_font_get_scaled_font(FONT->font));
    cairo_glyph_t g = {glyph, 0, 0};
    cairo_glyph_path(cr, &g, 1);
    /* Read back without the flip: the outline now has y going up. */
    cairo_identity_matrix(cr);
    GPath *p = GPathFromCairo(cr);
    cairo_destroy(cr);
    cairo_surface_destroy(s);
    CGPathRef out = CGPathCreateCopyByTransformingPath((CGPathRef)p, matrix);
    [p release];
    return out;
}

void CTFontDrawGlyphs(CTFontRef font, const CGGlyph glyphs[], const CGPoint positions[], size_t count,
                      CGContextRef context)
{
    if (!count)
        return;
    cairo_glyph_t *g = malloc(count * sizeof *g);
    for (size_t i = 0; i < count; i++)
        g[i] = (cairo_glyph_t){glyphs[i], positions[i].x, -positions[i].y};
    GContext *c = (GContext *)context;
    cairo_scaled_font_t *sf = pango_cairo_font_get_scaled_font(FONT->font);
    GContextDrawText(c, 0, 0, ^(BOOL path) {
        cairo_set_scaled_font(c->cr, sf);
        (path ? cairo_glyph_path : cairo_show_glyphs)(c->cr, g, (int)count);
    });
    free(g);
}

CFTypeID CTFontGetTypeID(void) { return (CFTypeID)[GFont class]; }

/* ---- paragraph styles ---------------------------------------------------------------- */

@implementation GParagraphStyle
- (id)copyWithZone:(NSZone *)zone { return [self retain]; }
@end

CTParagraphStyleRef CTParagraphStyleCreate(const CTParagraphStyleSetting *settings, size_t count)
{
    GParagraphStyle *p = [[GParagraphStyle alloc] init];
    p->alignment = kCTTextAlignmentNatural;
    for (size_t i = 0; i < count; i++) {
        const CTParagraphStyleSetting *s = &settings[i];
        if (!s->value)
            continue;
        if (s->spec == kCTParagraphStyleSpecifierAlignment && s->valueSize >= 1)
            p->alignment = *(const uint8_t *)s->value;
        else if (s->spec == kCTParagraphStyleSpecifierLineBreakMode && s->valueSize >= 1)
            p->lineBreakMode = *(const uint8_t *)s->value;
        else if (s->spec == kCTParagraphStyleSpecifierBaseWritingDirection && s->valueSize >= 1)
            p->writingDirection = *(const uint8_t *)s->value;
        else if ((unsigned)s->spec < 17 && s->valueSize == sizeof(CGFloat))
            p->values[s->spec] = *(const CGFloat *)s->value;
    }
    return (CTParagraphStyleRef)p;
}

bool CTParagraphStyleGetValueForSpecifier(CTParagraphStyleRef style, CTParagraphStyleSpecifier spec, size_t size,
                                          void *buffer)
{
    GParagraphStyle *p = (GParagraphStyle *)style;
    if (!buffer)
        return false;
    uint8_t byte;
    if (spec == kCTParagraphStyleSpecifierAlignment || spec == kCTParagraphStyleSpecifierLineBreakMode ||
        spec == kCTParagraphStyleSpecifierBaseWritingDirection) {
        byte = spec == kCTParagraphStyleSpecifierAlignment       ? (p ? p->alignment : kCTTextAlignmentNatural)
               : spec == kCTParagraphStyleSpecifierLineBreakMode ? (p ? p->lineBreakMode : 0)
                                                                 : (p ? p->writingDirection : 0);
        if (size < 1)
            return false;
        *(uint8_t *)buffer = byte;
        return true;
    }
    if ((unsigned)spec >= 17 || size < sizeof(CGFloat))
        return false;
    *(CGFloat *)buffer = p ? p->values[spec] : 0;
    return true;
}

/* ---- laying out attributed text ------------------------------------------------------- */

/* Text laid out by Pango, with the map from the string's UTF-16 indexes to
 * the UTF-8 byte offsets Pango works in. */
@interface GLayout : NSObject {
@public
    PangoLayout *layout;
    NSAttributedString *source;
    NSRange range;          /* of source */
    NSUInteger *offsets;    /* offsets[i] is the byte where UTF-16 unit i starts; offsets[len] the end */
    CGFloat leading;        /* largest font leading in the text */
}
@end

@implementation GLayout

- (void)dealloc
{
    if (layout)
        g_object_unref(layout);
    [source release];
    free(offsets);
    [super dealloc];
}

@end

static BOOL rgba_of(id value, double rgba[4])
{
    if (!value)
        return NO;
    if (![value isKindOfClass:[GColor class]] && [value respondsToSelector:@selector(CGColor)])
        value = ((id(*)(id, SEL))objc_msgSend)(value, @selector(CGColor));
    if (![value isKindOfClass:[GColor class]])
        return NO;
    memcpy(rgba, ((GColor *)value)->rgba, 4 * sizeof(double));
    return YES;
}

static void add_attr(PangoAttrList *list, PangoAttribute *a, unsigned start, unsigned end)
{
    a->start_index = start;
    a->end_index = end;
    pango_attr_list_insert(list, a);
}

static uint16_t c16(double v) { return (uint16_t)lround(v * 65535); }

static GLayout *make_layout(NSAttributedString *as, NSRange range)
{
    GLayout *l = [[GLayout alloc] init];
    l->source = [as copy];
    l->range = range;
    NSString *text = [as.string substringWithRange:range];
    NSUInteger n = text.length;
    unichar *chars = malloc((n + 1) * sizeof *chars);
    [text getCharacters:chars range:NSMakeRange(0, n)];
    l->offsets = malloc((n + 1) * sizeof *l->offsets);
    char *utf8 = malloc(n * 3 + 1);
    size_t pos = 0;
    for (NSUInteger i = 0; i < n; i++) {
        l->offsets[i] = pos;
        uint32_t c = chars[i];
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && chars[i + 1] >= 0xDC00 && chars[i + 1] < 0xE000) {
            c = 0x10000 + ((c - 0xD800) << 10) + (chars[i + 1] - 0xDC00);
            utf8[pos++] = (char)(0xF0 | c >> 18);
            utf8[pos++] = (char)(0x80 | ((c >> 12) & 0x3F));
            utf8[pos++] = (char)(0x80 | ((c >> 6) & 0x3F));
            utf8[pos++] = (char)(0x80 | (c & 0x3F));
            l->offsets[++i] = pos;  /* the low half has no byte of its own */
            continue;
        }
        if (c >= 0xD800 && c < 0xE000)
            c = 0xFFFD;
        if (c < 0x80) {
            utf8[pos++] = (char)c;
        } else if (c < 0x800) {
            utf8[pos++] = (char)(0xC0 | c >> 6);
            utf8[pos++] = (char)(0x80 | (c & 0x3F));
        } else {
            utf8[pos++] = (char)(0xE0 | c >> 12);
            utf8[pos++] = (char)(0x80 | ((c >> 6) & 0x3F));
            utf8[pos++] = (char)(0x80 | (c & 0x3F));
        }
    }
    l->offsets[n] = pos;
    utf8[pos] = 0;
    free(chars);

    l->layout = pango_layout_new(pango_context());
    pango_layout_set_text(l->layout, utf8, (int)pos);
    free(utf8);
    pango_layout_set_font_description(l->layout, default_font()->desc);

    PangoAttrList *list = pango_attr_list_new();
    __block CGFloat leading = 0;
    [as enumerateAttributesInRange:range
                           options:0
                        usingBlock:^(NSDictionary *attrs, NSRange r, BOOL *stop) {
                            unsigned s = (unsigned)l->offsets[r.location - range.location];
                            unsigned e = (unsigned)l->offsets[r.location + r.length - range.location];
                            GFont *font = attrs[(id)kCTFontAttributeName];
                            if (![font isKindOfClass:[GFont class]])
                                font = default_font();
                            add_attr(list, pango_attr_font_desc_new(font->desc), s, e);
                            leading = fmax(leading, CTFontGetLeading((CTFontRef)font));
                            double rgba[4] = {0, 0, 0, 1};
                            BOOL fromContext = [attrs[(id)kCTForegroundColorFromContextAttributeName] boolValue];
                            BOOL explicit = rgba_of(attrs[(id)kCTForegroundColorAttributeName], rgba) ||
                                            rgba_of(attrs[@"NSColor"], rgba);
                            if (explicit || !fromContext) {
                                add_attr(list, pango_attr_foreground_new(c16(rgba[0]), c16(rgba[1]), c16(rgba[2])), s, e);
                                if (rgba[3] < 1)
                                    add_attr(list, pango_attr_foreground_alpha_new(c16(rgba[3])), s, e);
                            }
                            id kern = attrs[(id)kCTKernAttributeName];
                            if ([kern isKindOfClass:[NSNumber class]] && [kern doubleValue] != 0)
                                add_attr(list, pango_attr_letter_spacing_new((int)lround([kern doubleValue] * PANGO_SCALE)),
                                         s, e);
                            NSInteger underline = [attrs[(id)kCTUnderlineStyleAttributeName] integerValue];
                            if (underline & 0xff) {
                                add_attr(list, pango_attr_underline_new((underline & 0xff) == kCTUnderlineStyleDouble
                                                                            ? PANGO_UNDERLINE_DOUBLE
                                                                            : PANGO_UNDERLINE_SINGLE),
                                         s, e);
                                double u[4];
                                if (rgba_of(attrs[(id)kCTUnderlineColorAttributeName], u))
                                    add_attr(list, pango_attr_underline_color_new(c16(u[0]), c16(u[1]), c16(u[2])), s, e);
                            }
                            if ([attrs[(id)kCTStrokeWidthAttributeName] doubleValue] != 0)
                                GWarnOnce("outlined text (kCTStrokeWidthAttributeName)");
                            id att = attrs[attachment_key];
                            if ([att respondsToSelector:@selector(_ferryAttachmentBounds)]) {
                                CGRect b = [att _ferryAttachmentBounds];
                                PangoRectangle box = {0, (int)lround(-(b.origin.y + b.size.height) * PANGO_SCALE),
                                                      (int)lround(b.size.width * PANGO_SCALE),
                                                      (int)lround(b.size.height * PANGO_SCALE)};
                                /* the line keeps at least its font's ascent and descent */
                                double top = fmax(b.origin.y + b.size.height, CTFontGetAscent((CTFontRef)font));
                                double below = fmax(-b.origin.y, CTFontGetDescent((CTFontRef)font));
                                PangoRectangle room = {0, (int)lround(-top * PANGO_SCALE), box.width,
                                                       (int)lround((top + below) * PANGO_SCALE)};
                                for (NSUInteger i = r.location; i < NSMaxRange(r); i++)
                                    if ([as.string characterAtIndex:i] == 0xFFFC)
                                        add_attr(list, pango_attr_shape_new(&box, &room),
                                                 (unsigned)l->offsets[i - range.location],
                                                 (unsigned)l->offsets[i + 1 - range.location]);
                            }
                        }];
    pango_layout_set_attributes(l->layout, list);
    pango_attr_list_unref(list);
    l->leading = leading;
    return l;
}

/* The UTF-16 index (within the layout's text) at a byte offset. */
static NSUInteger index_for_byte(GLayout *l, int byte)
{
    NSUInteger lo = 0, hi = l->range.length;
    while (lo < hi) {
        NSUInteger mid = (lo + hi + 1) / 2;
        if (l->offsets[mid] <= (NSUInteger)byte)
            lo = mid;
        else
            hi = mid - 1;
    }
    return lo;
}

/* ---- lines ------------------------------------------------------------------------- */

@interface GLine : NSObject {
@public
    GLayout *layout;
    int index;          /* which of the layout's lines */
}
@end

@implementation GLine

- (void)dealloc
{
    [layout release];
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<CTLine %p>", self];
}

@end

static GLine *make_line(GLayout *layout, int index)
{
    GLine *line = [[GLine alloc] init];
    line->layout = [layout retain];
    line->index = index;
    return line;
}

#define LINE ((GLine *)line)

static PangoLayoutLine *pline(GLine *line) { return pango_layout_get_line_readonly(line->layout->layout, line->index); }

CTLineRef CTLineCreateWithAttributedString(CFAttributedStringRef string)
{
    NSAttributedString *as = (NSAttributedString *)string;
    GLayout *l = make_layout(as, NSMakeRange(0, as.length));
    pango_layout_set_single_paragraph_mode(l->layout, 1);
    GLine *line = make_line(l, 0);
    [l release];
    return (CTLineRef)line;
}

CFRange CTLineGetStringRange(CTLineRef line)
{
    PangoLayoutLine *pl = pline(LINE);
    GLayout *l = LINE->layout;
    NSUInteger start = index_for_byte(l, pl->start_index), end = index_for_byte(l, pl->start_index + pl->length);
    if (LINE->index == pango_layout_get_line_count(l->layout) - 1)
        end = l->range.length;
    return CFRangeMake((CFIndex)(l->range.location + start), (CFIndex)(end - start));
}

CFIndex CTLineGetGlyphCount(CTLineRef line)
{
    CFIndex n = 0;
    for (GSList *r = pline(LINE)->runs; r; r = r->next)
        n += ((PangoGlyphItem *)r->data)->glyphs->num_glyphs;
    return n;
}

double CTLineGetTypographicBounds(CTLineRef line, CGFloat *ascent, CGFloat *descent, CGFloat *leading)
{
    PangoRectangle ink, logical;
    pango_layout_line_get_extents(pline(LINE), &ink, &logical);
    if (ascent)
        *ascent = -logical.y / (double)PANGO_SCALE;
    if (descent)
        *descent = (logical.height + logical.y) / (double)PANGO_SCALE;
    if (leading)
        *leading = LINE->layout->leading;
    return logical.width / (double)PANGO_SCALE;
}

CGRect CTLineGetImageBounds(CTLineRef line, CGContextRef context)
{
    PangoRectangle ink, logical;
    pango_layout_line_get_extents(pline(LINE), &ink, &logical);
    if (!ink.width || !ink.height)
        return CGRectNull;
    CGRect r = CGRectMake(ink.x / (double)PANGO_SCALE, -(ink.y + ink.height) / (double)PANGO_SCALE,
                          ink.width / (double)PANGO_SCALE, ink.height / (double)PANGO_SCALE);
    if (context)
        r = CGRectOffset(r, ((GContext *)context)->textMatrix.tx, ((GContext *)context)->textMatrix.ty);
    return r;
}

static double x_at(GLine *line, NSUInteger i)
{
    GLayout *l = line->layout;
    int x;
    pango_layout_line_index_to_x(pline(line), (int)l->offsets[i], 0, &x);
    return x / (double)PANGO_SCALE;
}

double CTLineGetTrailingWhitespaceWidth(CTLineRef line)
{
    CFRange r = CTLineGetStringRange(line);
    NSString *s = LINE->layout->source.string;
    CFIndex end = r.location + r.length, i = end;
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (i > r.location && [ws characterIsMember:[s characterAtIndex:i - 1]])
        i--;
    if (i == end)
        return 0;
    double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    return width - x_at(LINE, i - LINE->layout->range.location);
}

double CTLineGetPenOffsetForFlush(CTLineRef line, CGFloat flushFactor, double flushWidth)
{
    double used = CTLineGetTypographicBounds(line, NULL, NULL, NULL) - CTLineGetTrailingWhitespaceWidth(line);
    double offset = (flushWidth - used) * fmax(0, fmin(1, flushFactor));
    return offset > 0 ? offset : 0;
}

CGFloat CTLineGetOffsetForStringIndex(CTLineRef line, CFIndex charIndex, CGFloat *secondaryOffset)
{
    CFRange r = CTLineGetStringRange(line);
    GLayout *l = LINE->layout;
    CGFloat x;
    if (charIndex >= r.location + r.length)
        x = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    else if (charIndex <= r.location)
        x = x_at(LINE, r.location - l->range.location);
    else
        x = x_at(LINE, charIndex - l->range.location);
    if (secondaryOffset)
        *secondaryOffset = x;
    return x;
}

CFIndex CTLineGetStringIndexForPosition(CTLineRef line, CGPoint position)
{
    GLayout *l = LINE->layout;
    CFRange r = CTLineGetStringRange(line);
    if (position.x <= 0)
        return r.location;
    if (position.x >= CTLineGetTypographicBounds(line, NULL, NULL, NULL))
        return r.location + r.length;
    int index, trailing;
    pango_layout_line_x_to_index(pline(LINE), (int)lround(position.x * PANGO_SCALE), &index, &trailing);
    NSUInteger i = index_for_byte(l, index);
    if (trailing) {
        /* after the character: step over it (both halves of a surrogate pair) */
        NSUInteger next = i + 1;
        while (next < l->range.length && l->offsets[next] == l->offsets[i])
            next++;
        i = next;
    }
    return (CFIndex)(l->range.location + i);
}

/* Each run of the line with an NSShadow attribute: its glyphs alone (the
 * rest of the line made transparent in a copy of the layout) drawn for
 * their shadow only, so that every shadow lies under the whole line. */
static void draw_run_shadows(GLine *line, GContext *c, CGFloat x, CGFloat y)
{
    GLayout *l = line->layout;
    CFRange lr = CTLineGetStringRange((CTLineRef)line);
    if (lr.length <= 0)
        return;
    NSRange range = NSMakeRange((NSUInteger)lr.location, (NSUInteger)lr.length);
    [l->source enumerateAttribute:shadow_key
                          inRange:range
                          options:0
                       usingBlock:^(id shadow, NSRange r, BOOL *stop) {
                           double rgba[4];
                           if (![shadow respondsToSelector:@selector(shadowOffset)] ||
                               ![shadow respondsToSelector:@selector(shadowColor)] ||
                               !rgba_of([shadow shadowColor], rgba) || rgba[3] <= 0)
                               return;
                           unsigned s = (unsigned)l->offsets[r.location - l->range.location];
                           unsigned e = (unsigned)l->offsets[NSMaxRange(r) - l->range.location];
                           unsigned end = (unsigned)l->offsets[l->range.length];
                           PangoLayout *copy = pango_layout_copy(l->layout);
                           PangoAttrList *had = pango_layout_get_attributes(copy);
                           PangoAttrList *list = had ? pango_attr_list_copy(had) : pango_attr_list_new();
                           /* an alpha of 0 means "not set" to Pango; 1 is as good as clear */
                           if (s > 0)
                               add_attr(list, pango_attr_foreground_alpha_new(1), 0, s);
                           if (e < end)
                               add_attr(list, pango_attr_foreground_alpha_new(1), e, end);
                           pango_layout_set_attributes(copy, list);
                           pango_attr_list_unref(list);
                           PangoLayoutLine *pl = pango_layout_get_line_readonly(copy, line->index);
                           CGContextSaveGState((CGContextRef)c);
                           struct gstate *st = GSTATE(c);
                           st->shadowOffset = [shadow shadowOffset];
                           st->shadowBlur = [shadow respondsToSelector:@selector(shadowBlurRadius)]
                                                ? fmax(0, [shadow shadowBlurRadius])
                                                : 0;
                           memcpy(st->shadowColor, rgba, sizeof rgba);
                           c->shadowOnly = YES;
                           GContextDrawText(c, x, y, ^(BOOL path) {
                               (path ? pango_cairo_layout_line_path : pango_cairo_show_layout_line)(c->cr, pl);
                           });
                           c->shadowOnly = NO;
                           CGContextRestoreGState((CGContextRef)c);
                           g_object_unref(copy);
                       }];
}

/* The line's attachments, each drawn in the room its shape took. */
static void draw_attachments(GLine *line, GContext *c, CGFloat x, CGFloat y)
{
    GLayout *l = line->layout;
    CFRange lr = CTLineGetStringRange((CTLineRef)line);
    if (lr.length <= 0 || GSTATE(c)->textMode == kCGTextInvisible)
        return;
    PangoLayoutLine *pl = pline(line);
    NSString *string = l->source.string;
    [l->source enumerateAttribute:attachment_key
                          inRange:NSMakeRange((NSUInteger)lr.location, (NSUInteger)lr.length)
                          options:0
                       usingBlock:^(id att, NSRange r, BOOL *stop) {
                           if (![att respondsToSelector:@selector(_ferryDrawAttachmentInRect:context:)])
                               return;
                           CGRect b = [att _ferryAttachmentBounds];
                           for (NSUInteger i = r.location; i < NSMaxRange(r); i++) {
                               if ([string characterAtIndex:i] != 0xFFFC)
                                   continue;
                               int xpos = 0;
                               pango_layout_line_index_to_x(pl, (int)l->offsets[i - l->range.location], 0, &xpos);
                               CGContextSaveGState((CGContextRef)c);
                               CGContextConcatCTM((CGContextRef)c, c->textMatrix);
                               CGContextTranslateCTM((CGContextRef)c, x, y);
                               CGAffineTransform tm = c->textMatrix;
                               c->textMatrix = CGAffineTransformIdentity;
                               [att _ferryDrawAttachmentInRect:CGRectMake(xpos / (double)PANGO_SCALE, b.origin.y,
                                                                          b.size.width, b.size.height)
                                                       context:(CGContextRef)c];
                               c->textMatrix = tm;
                               CGContextRestoreGState((CGContextRef)c);
                           }
                       }];
}

static void draw_line(GLine *line, GContext *c, CGFloat x, CGFloat y)
{
    PangoLayoutLine *pl = pline(line);
    draw_run_shadows(line, c, x, y);
    GContextDrawText(c, x, y, ^(BOOL path) {
        (path ? pango_cairo_layout_line_path : pango_cairo_show_layout_line)(c->cr, pl);
    });
    draw_attachments(line, c, x, y);
}

void CTLineDraw(CTLineRef line, CGContextRef context)
{
    if (line && context)
        draw_line(LINE, (GContext *)context, 0, 0);
}

CTLineRef CTLineCreateTruncatedLine(CTLineRef line, double width, CTLineTruncationType type, CTLineRef token)
{
    if (CTLineGetTypographicBounds(line, NULL, NULL, NULL) <= width)
        return (CTLineRef)make_line(LINE->layout, LINE->index);
    if (token)
        GWarnOnce("a custom truncation token (Ferry always uses …)");
    CFRange r = CTLineGetStringRange(line);
    GLayout *l = make_layout(LINE->layout->source, NSMakeRange(r.location, r.length));
    pango_layout_set_single_paragraph_mode(l->layout, 1);
    pango_layout_set_width(l->layout, (int)(width * PANGO_SCALE));
    pango_layout_set_ellipsize(l->layout, type == kCTLineTruncationStart    ? PANGO_ELLIPSIZE_START
                                          : type == kCTLineTruncationMiddle ? PANGO_ELLIPSIZE_MIDDLE
                                                                            : PANGO_ELLIPSIZE_END);
    GLine *out = make_line(l, 0);
    [l release];
    return (CTLineRef)out;
}

CFTypeID CTLineGetTypeID(void) { return (CFTypeID)[GLine class]; }

/* ---- framesetters and frames ---------------------------------------------------------- */

@interface GFramesetter : NSObject {
@public
    NSAttributedString *string;
}
@end

@implementation GFramesetter
- (void)dealloc
{
    [string release];
    [super dealloc];
}
@end

@interface GFrame : NSObject {
@public
    GLayout *layout;
    CGPathRef path;
    CGRect rect;
    NSArray *lines;
    CGPoint *origins;   /* relative to rect's origin, y going up */
    NSRange visible;
}
@end

@implementation GFrame
- (void)dealloc
{
    [layout release];
    CGPathRelease(path);
    [lines release];
    free(origins);
    [super dealloc];
}
@end

CTFramesetterRef CTFramesetterCreateWithAttributedString(CFAttributedStringRef string)
{
    GFramesetter *f = [[GFramesetter alloc] init];
    f->string = [(NSAttributedString *)string copy];
    return (CTFramesetterRef)f;
}

static NSRange full_range(GFramesetter *fs, CFRange r)
{
    NSUInteger len = fs->string.length;
    NSUInteger loc = r.location < 0 ? 0 : MIN((NSUInteger)r.location, len);
    NSUInteger n = r.length <= 0 ? len - loc : MIN((NSUInteger)r.length, len - loc);
    return NSMakeRange(loc, n);
}

/* Lays out range at the given width (or unbounded when width <= 0),
 * following the paragraph style at its start. */
static GLayout *frame_layout(GFramesetter *fs, NSRange range, CGFloat width)
{
    GLayout *l = make_layout(fs->string, range);
    GParagraphStyle *style = range.length
                                 ? [fs->string attribute:(id)kCTParagraphStyleAttributeName atIndex:range.location
                                          effectiveRange:NULL]
                                 : nil;
    if (![style isKindOfClass:[GParagraphStyle class]])
        style = nil;
    int wrap = PANGO_WRAP_WORD_CHAR;
    if (style && style->lineBreakMode == kCTLineBreakByCharWrapping)
        wrap = PANGO_WRAP_CHAR;
    pango_layout_set_wrap(l->layout, wrap);
    if (width > 0 && width < 1e7 && !(style && style->lineBreakMode == kCTLineBreakByClipping))
        pango_layout_set_width(l->layout, (int)(width * PANGO_SCALE));
    if (style) {
        int align = style->alignment == kCTTextAlignmentRight    ? PANGO_ALIGN_RIGHT
                    : style->alignment == kCTTextAlignmentCenter ? PANGO_ALIGN_CENTER
                                                                 : PANGO_ALIGN_LEFT;
        if (style->alignment == kCTTextAlignmentJustified)
            GWarnOnce("justified text");
        pango_layout_set_alignment(l->layout, align);
    }
    return l;
}

CTFrameRef CTFramesetterCreateFrame(CTFramesetterRef framesetter, CFRange stringRange, CGPathRef path,
                                    CFDictionaryRef frameAttributes)
{
    GFramesetter *fs = (GFramesetter *)framesetter;
    if (!fs || !path)
        return NULL;
    GFrame *f = [[GFrame alloc] init];
    f->path = CGPathRetain(path);
    CGRect rect;
    if (!CGPathIsRect(path, &rect)) {
        GWarnOnce("text frames that aren't rectangles (Ferry uses the bounding box)");
        rect = CGPathGetBoundingBox(path);
    }
    f->rect = rect;
    NSRange range = full_range(fs, stringRange);
    f->layout = frame_layout(fs, range, rect.size.width);
    int count = pango_layout_get_line_count(f->layout->layout);
    f->origins = calloc(count ? count : 1, sizeof *f->origins);
    NSMutableArray *lines = [NSMutableArray array];
    PangoLayoutIter *it = pango_layout_get_iter(f->layout->layout);
    NSUInteger end = range.location;
    for (int i = 0; i < count; i++) {
        PangoRectangle ink, logical;
        pango_layout_iter_get_line_extents(it, &ink, &logical);
        double bottom = (logical.y + logical.height) / (double)PANGO_SCALE;
        if (bottom > rect.size.height + 0.01 && i > 0)
            break;
        if (bottom > rect.size.height + 0.01) /* not even one line fits */
            break;
        double baseline = pango_layout_iter_get_baseline(it) / (double)PANGO_SCALE;
        f->origins[i] = CGPointMake(logical.x / (double)PANGO_SCALE, rect.size.height - baseline);
        GLine *line = make_line(f->layout, i);
        [lines addObject:line];
        CFRange lr = CTLineGetStringRange((CTLineRef)line);
        end = (NSUInteger)(lr.location + lr.length);
        [line release];
        if (!pango_layout_iter_next_line(it))
            break;
    }
    pango_layout_iter_free(it);
    f->lines = [lines copy];
    f->visible = NSMakeRange(range.location, end - range.location);
    return (CTFrameRef)f;
}

CGSize CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterRef framesetter, CFRange stringRange,
                                                    CFDictionaryRef frameAttributes, CGSize constraints,
                                                    CFRange *fitRange)
{
    GFramesetter *fs = (GFramesetter *)framesetter;
    NSRange range = full_range(fs, stringRange);
    GLayout *l = frame_layout(fs, range, constraints.width);
    PangoLayoutIter *it = pango_layout_get_iter(l->layout);
    double width = 0, height = 0;
    NSUInteger end = range.location;
    int count = pango_layout_get_line_count(l->layout);
    for (int i = 0; i < count; i++) {
        PangoRectangle ink, logical;
        pango_layout_iter_get_line_extents(it, &ink, &logical);
        double bottom = (logical.y + logical.height) / (double)PANGO_SCALE;
        if (bottom > constraints.height + 0.01 && i > 0)
            break;
        height = bottom;
        width = fmax(width, (logical.x + logical.width) / (double)PANGO_SCALE);
        GLine *line = make_line(l, i);
        CFRange lr = CTLineGetStringRange((CTLineRef)line);
        end = (NSUInteger)(lr.location + lr.length);
        [line release];
        if (!pango_layout_iter_next_line(it))
            break;
    }
    pango_layout_iter_free(it);
    [l release];
    if (fitRange)
        *fitRange = CFRangeMake((CFIndex)range.location, (CFIndex)(end - range.location));
    return CGSizeMake(width, height);
}

#define FRAME ((GFrame *)frame)

CFArrayRef CTFrameGetLines(CTFrameRef frame) { return (CFArrayRef)FRAME->lines; }

void CTFrameGetLineOrigins(CTFrameRef frame, CFRange range, CGPoint origins[])
{
    NSUInteger n = FRAME->lines.count;
    NSUInteger loc = (NSUInteger)range.location, len = range.length ? (NSUInteger)range.length : n - loc;
    for (NSUInteger i = 0; i < len && loc + i < n; i++)
        origins[i] = FRAME->origins[loc + i];
}

CFRange CTFrameGetStringRange(CTFrameRef frame)
{
    return CFRangeMake((CFIndex)FRAME->layout->range.location, (CFIndex)FRAME->layout->range.length);
}

CFRange CTFrameGetVisibleStringRange(CTFrameRef frame)
{
    return CFRangeMake((CFIndex)FRAME->visible.location, (CFIndex)FRAME->visible.length);
}

CGPathRef CTFrameGetPath(CTFrameRef frame) { return FRAME->path; }

void CTFrameDraw(CTFrameRef frame, CGContextRef context)
{
    /* Each line goes at its origin in the frame, whatever the text position was. */
    GContext *c = (GContext *)context;
    CGAffineTransform saved = c->textMatrix;
    c->textMatrix.tx = c->textMatrix.ty = 0;
    for (NSUInteger i = 0; i < FRAME->lines.count; i++)
        draw_line(FRAME->lines[i], c, FRAME->rect.origin.x + FRAME->origins[i].x,
                  FRAME->rect.origin.y + FRAME->origins[i].y);
    c->textMatrix = saved;
}
