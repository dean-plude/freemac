/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Text's font descriptors, collections and font manager (freemac
 * 1.238, for VLC's subtitle text, which finds font files this way and draws
 * them with FreeType). Written from Apple's public API documentation.
 *
 * The installed faces are read once, from the font folders this system's
 * fontconfig uses: each file's faces, with their family, style, full and
 * PostScript names and weight and slant read by HarfBuzz. A descriptor is
 * its attributes; one that names a font answers what it doesn't hold (its
 * file's URL, its traits) from the installed face it names. A collection
 * matches descriptors by family, display name or PostScript name, ignoring
 * case, as a Mac's does. A Mac family that isn't installed (Helvetica
 * Neue, Monaco...) matches the faces of the family that stands for it, as
 * CTFontCreateWithName gives, and those faces then show the Mac family as
 * their display name; any other family that isn't installed matches
 * nothing. CTFontCreateForString
 * finds the font that has a string's first character as Pango would. */
#import "GInternal.h"

GFont *GFontCreate(NSString *family, int weight, int style, CGFloat size);
NSString *GFontMacFamily(NSString *name);

/* The attribute keys, the descriptor class and the calls that make and read
 * descriptors are in CTFontDescriptor.m; these two come from there. */
CTFontDescriptorRef GFontDescriptorMake(NSDictionary *attributes);
NSDictionary *GFontDescriptorAttributes(CTFontDescriptorRef descriptor);

/* ---- the installed faces ------------------------------------------------------------ */

@interface GFace : NSObject {
@public
    NSString *path, *family, *style, *full, *postscript, *ferryName;
    NSString *standsFor;   /* the Mac family it was given for, if any */
    unsigned index;
    float weight;   /* 100 to 900 */
    BOOL italic;
    BOOL mono;      /* every glyph as wide as the next: a terminal's font */
}
@end
@implementation GFace
- (void)dealloc
{
    [path release]; [family release]; [style release]; [full release]; [postscript release];
    [ferryName release]; [standsFor release];
    [super dealloc];
}
@end

static NSString *face_name(hb_face_t *face, unsigned id)
{
    char text[256];
    unsigned size = sizeof text;
    if (!hb_ot_name_get_utf8(face, id, NULL, &size, text) || !*text)
        return nil;
    return [NSString stringWithUTF8String:text];
}

/* the weight trait (-1 to 1) a Mac gives a face of this OS/2 weight */
static double weight_trait(float w)
{
    static const float classes[] = {100, 200, 300, 400, 500, 600, 700, 800, 900};
    static const double traits[] = {-0.8, -0.6, -0.4, 0, 0.23, 0.3, 0.4, 0.56, 0.62};
    if (w <= 100)
        return traits[0];
    for (int i = 1; i < 9; i++)
        if (w <= classes[i])
            return traits[i - 1] + (traits[i] - traits[i - 1]) * (w - classes[i - 1]) / 100;
    return traits[8];
}

/* the name CTFontCopyPostScriptName gives a font of this family and style */
static NSString *ferry_name(NSString *family, float weight, BOOL italic)
{
    const char *w = weight >= 800 ? "Black" : weight >= 700 ? "Bold" : weight >= 600 ? "SemiBold"
                    : weight >= 500 ? "Medium" : weight <= 200 ? "Thin" : weight <= 300 ? "Light" : "";
    NSString *style = !*w && !italic ? @"Regular" : [NSString stringWithFormat:@"%s%s", w, italic ? "Italic" : ""];
    return [NSString stringWithFormat:@"%@-%@", [family stringByReplacingOccurrencesOfString:@" " withString:@""], style];
}

static void read_file(NSString *path, NSMutableArray *out)
{
    hb_blob_t *blob = hb_blob_create_from_file(path.fileSystemRepresentation);
    unsigned count = blob ? hb_face_count(blob) : 0;
    for (unsigned i = 0; i < count; i++) {
        hb_face_t *hf = hb_face_create(blob, i);
        NSString *family = face_name(hf, 16) ?: face_name(hf, 1);
        if (family) {
            GFace *f = [[GFace alloc] init];
            f->path = [path copy];
            f->index = i;
            f->family = [family copy];
            f->style = [face_name(hf, 17) ?: face_name(hf, 2) ?: @"Regular" copy];
            f->full = [face_name(hf, 4) ?: family copy];
            f->postscript = [face_name(hf, 6) ?: [f->full stringByReplacingOccurrencesOfString:@" " withString:@""]
                copy];
            hb_font_t *font = hb_font_create(hf);
            hb_codepoint_t gi, gm;
            if (hb_font_get_nominal_glyph(font, 'i', &gi) && hb_font_get_nominal_glyph(font, 'M', &gm))
                f->mono = hb_font_get_glyph_h_advance(font, gi) == hb_font_get_glyph_h_advance(font, gm);
            f->weight = hb_style_get_value(font, HB_TAG('w', 'g', 'h', 't'));
            f->italic = hb_style_get_value(font, HB_TAG('i', 't', 'a', 'l')) > 0 ||
                        hb_style_get_value(font, HB_TAG('s', 'l', 'n', 't')) != 0;
            hb_font_destroy(font);
            f->ferryName = [ferry_name(family, f->weight, f->italic) copy];
            [out addObject:f];
            [f release];
        }
        hb_face_destroy(hf);
    }
    if (blob)
        hb_blob_destroy(blob);
}

static NSArray *installed_faces(void)
{
    static NSArray *faces;
    if (faces)
        return faces;
    NSMutableArray *all = [[NSMutableArray alloc] init];
    NSArray *dirs = @[@"/usr/share/fonts", @"/usr/local/share/fonts",
                      [NSHomeDirectory() stringByAppendingPathComponent:@".local/share/fonts"],
                      [NSHomeDirectory() stringByAppendingPathComponent:@".fonts"]];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        NSArray *names = [[fm subpathsOfDirectoryAtPath:dir error:NULL]
            sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *name in names) {
            NSString *ext = name.pathExtension.lowercaseString;
            if ([@[@"ttf", @"otf", @"ttc", @"otc"] containsObject:ext])
                read_file([dir stringByAppendingPathComponent:name], all);
        }
    }
    faces = all;
    return faces;
}

static BOOL same(NSString *a, id b)
{
    return a && [b isKindOfClass:[NSString class]] && [a caseInsensitiveCompare:b] == NSOrderedSame;
}

/* the installed face a font name names: its PostScript name, its full name,
 * or the name Ferry's CTFontCopyPostScriptName gives it */
static NSArray *stand_in_faces(void);

static GFace *face_named(NSString *name)
{
    if (![name isKindOfClass:[NSString class]])
        return nil;
    NSArray *faces = installed_faces();
    for (GFace *f in faces)
        if (same(f->postscript, name))
            return f;
    for (GFace *f in faces)
        if (same(f->full, name) || same(f->ferryName, name))
            return f;
    for (GFace *f in stand_in_faces())
        if (same(f->postscript, name) || same(f->full, name))
            return f;
    return nil;
}

/* ---- descriptors --------------------------------------------------------------------- */

static CTFontDescriptorRef descriptor(NSDictionary *attributes) { return GFontDescriptorMake(attributes); }

/* A face given for a Mac family that isn't installed shows that family as
 * its display name, as the Mac's own faces do ("Helvetica Neue", "Helvetica
 * Neue Bold"), so that an app that looks for the family in the file's faces
 * finds it; its family and PostScript names stay its own. */
static NSString *display_name(GFace *f)
{
    if (!f->standsFor)
        return f->full;
    BOOL regular = [f->style caseInsensitiveCompare:@"Regular"] == NSOrderedSame || ![f->style length];
    return regular ? f->standsFor : [NSString stringWithFormat:@"%@ %@", f->standsFor, f->style];
}

static NSDictionary *face_attributes(GFace *f)
{
    return @{
        (id)kCTFontNameAttribute : f->postscript,
        (id)kCTFontDisplayNameAttribute : display_name(f),
        (id)kCTFontFamilyNameAttribute : f->family,
        (id)kCTFontStyleNameAttribute : f->style,
        (id)kCTFontURLAttribute : [NSURL fileURLWithPath:f->path],
        (id)kCTFontTraitsAttribute : @{
            (id)kCTFontWeightTrait : @(weight_trait(f->weight)),
            (id)kCTFontSlantTrait : @(f->italic ? 0.07 : 0.0),
            (id)kCTFontSymbolicTrait : @((f->italic ? kCTFontTraitItalic : 0) |
                                        (f->weight >= 600 ? kCTFontTraitBold : 0) |
                                        (f->mono ? kCTFontTraitMonoSpace : 0)),
        },
    };
}

/* What a descriptor that names an installed font answers for an attribute it
 * doesn't hold (its file's URL, its traits...): CTFontDescriptorCopyAttribute
 * asks this. */
id GFontInstalledFaceAttribute(NSDictionary *attributes, NSString *attribute)
{
    GFace *f = face_named(attributes[(id)kCTFontNameAttribute]);
    return f ? face_attributes(f)[attribute] : nil;
}

/* ---- collections --------------------------------------------------------------------- */

@interface GFontCollection : NSObject {
@public
    NSArray *descriptors;
    BOOL available;   /* the list of every font: matching it gives the list itself */
}
@end
@implementation GFontCollection
- (void)dealloc
{
    [descriptors release];
    [super dealloc];
}
@end

CTFontCollectionRef CTFontCollectionCreateWithFontDescriptors(CFArrayRef descriptors, CFDictionaryRef options)
{
    (void)options;
    GFontCollection *c = [[GFontCollection alloc] init];
    c->descriptors = [(NSArray *)descriptors copy] ?: [[NSArray alloc] init];
    return (CTFontCollectionRef)c;
}

/* The classic Mac families an app may look for by name in the list of
 * available fonts (kitty takes Menlo when nothing else fits). Where one isn't
 * installed, its stand-in's faces are listed under the Mac name too, with
 * Mac-style PostScript names ("Menlo-Bold") that Ferry maps back to them. */
static const char *const listed_mac_families[] = {"Menlo", "Monaco", "Courier", "Helvetica", "Helvetica Neue", "Times"};

static NSArray *stand_in_faces(void)
{
    static NSArray *listed;
    if (listed)
        return listed;
    NSMutableArray *out = [[NSMutableArray alloc] init];
    NSArray *faces = installed_faces();
    for (size_t i = 0; i < sizeof listed_mac_families / sizeof listed_mac_families[0]; i++) {
        NSString *mac = @(listed_mac_families[i]);
        BOOL installed = NO;
        for (GFace *f in faces)
            if (same(f->family, mac))
                installed = YES;
        NSString *standin = installed ? nil : GFontMacFamily(mac);
        GFont *font = standin ? GFontCreate(standin, 400, 0, 12) : nil;
        NSString *family = font ? [[font->family copy] autorelease] : nil;
        [font release];
        for (GFace *f in faces) {
            if (!family || !same(f->family, family))
                continue;
            GFace *g = [[GFace alloc] init];
            g->path = [f->path copy];
            g->index = f->index;
            g->family = [mac copy];
            g->style = [f->style copy];
            BOOL regular = [f->style caseInsensitiveCompare:@"Regular"] == NSOrderedSame || ![f->style length];
            g->full = regular ? [mac copy] : [[NSString alloc] initWithFormat:@"%@ %@", mac, f->style];
            g->postscript = [[NSString alloc] initWithFormat:@"%@-%@",
                [mac stringByReplacingOccurrencesOfString:@" " withString:@""],
                regular ? @"Regular" : [f->style stringByReplacingOccurrencesOfString:@" " withString:@""]];
            g->ferryName = [f->ferryName copy];
            g->weight = f->weight;
            g->italic = f->italic;
            g->mono = f->mono;
            [out addObject:g];
            [g release];
        }
    }
    listed = out;
    return listed;
}

CTFontCollectionRef CTFontCollectionCreateFromAvailableFonts(CFDictionaryRef options)
{
    (void)options;
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *list in @[installed_faces(), stand_in_faces()])
        for (GFace *f in list) {
            CTFontDescriptorRef d = descriptor(face_attributes(f));
            [all addObject:(id)d];
            CFRelease(d);
        }
    GFontCollection *c = (GFontCollection *)CTFontCollectionCreateWithFontDescriptors((CFArrayRef)all, NULL);
    c->available = YES;
    return (CTFontCollectionRef)c;
}

static BOOL face_matches(GFace *f, NSDictionary *query)
{
    id family = query[(id)kCTFontFamilyNameAttribute], name = query[(id)kCTFontNameAttribute],
       display = query[(id)kCTFontDisplayNameAttribute];
    if (!family && !name && !display)
        return NO;
    return (!family || same(f->family, family)) && (!name || same(f->postscript, name)) &&
           (!display || same(f->full, display) || same(display_name(f), display));
}

CFArrayRef CTFontCollectionCreateMatchingFontDescriptors(CTFontCollectionRef collection)
{
    NSArray *queries = ((GFontCollection *)collection)->descriptors;
    if (((GFontCollection *)collection)->available)
        return [queries count] ? (CFArrayRef)[queries copy] : NULL;
    NSMutableArray *out = [[NSMutableArray alloc] init];
    for (GFace *f in installed_faces())
        for (id q in queries)
            if (GFontDescriptorAttributes((CTFontDescriptorRef)q) &&
                face_matches(f, GFontDescriptorAttributes((CTFontDescriptorRef)q))) {
                CTFontDescriptorRef d = descriptor(face_attributes(f));
                [out addObject:(id)d];
                CFRelease(d);
                break;
            }
    if (![out count]) {
        /* A Mac family that isn't here: the installed family standing for it */
        for (id q in queries) {
            NSDictionary *a = GFontDescriptorAttributes((CTFontDescriptorRef)q);
            if (!a)
                continue;
            id mac = a[(id)kCTFontFamilyNameAttribute] ?: a[(id)kCTFontDisplayNameAttribute];
            NSString *standin = [mac isKindOfClass:[NSString class]] ? GFontMacFamily(mac) : nil;
            GFont *font = standin ? GFontCreate(standin, 400, 0, 12) : nil;
            NSString *family = font ? [[font->family copy] autorelease] : nil;
            [font release];
            if (!family)
                continue;
            for (GFace *f in installed_faces())
                if (same(f->family, family)) {
                    if (!f->standsFor)
                        f->standsFor = [mac copy];
                    CTFontDescriptorRef d = descriptor(face_attributes(f));
                    [out addObject:(id)d];
                    CFRelease(d);
                }
        }
    }
    if (![out count]) {
        [out release];
        return NULL;
    }
    return (CFArrayRef)out;
}

/* The collection's fonts of one family (Apple's CTFontCollection
 * documentation; freemac 1.266). */
CFArrayRef CTFontCollectionCreateMatchingFontDescriptorsForFamily(CTFontCollectionRef collection,
                                                                  CFStringRef familyName, CFDictionaryRef options)
{
    NSArray *all = collection ? [(NSArray *)CTFontCollectionCreateMatchingFontDescriptors(collection) autorelease] : nil;
    NSMutableArray *out = [[NSMutableArray alloc] init];
    for (id d in all) {
        NSString *family = [(id)CTFontDescriptorCopyAttribute((CTFontDescriptorRef)d, kCTFontFamilyNameAttribute) autorelease];
        if ([family isKindOfClass:[NSString class]] && familyName &&
            [family caseInsensitiveCompare:(NSString *)familyName] == NSOrderedSame)
            [out addObject:d];
    }
    if (![out count]) {
        [out release];
        return NULL;
    }
    return (CFArrayRef)out;
}

/* ---- the font manager ---------------------------------------------------------------- */

/* the faces in a font file, in the order of their index in it */
CFArrayRef CTFontManagerCreateFontDescriptorsFromURL(CFURLRef url)
{
    NSString *path = [[(NSURL *)url path] stringByStandardizingPath];
    if (!path)
        return NULL;
    NSMutableArray *faces = [NSMutableArray array];
    for (GFace *f in installed_faces())
        if ([[f->path stringByStandardizingPath] isEqual:path])
            [faces addObject:f];
    if (![faces count])
        read_file(path, faces);   /* a file of the app's own */
    if (![faces count])
        return NULL;
    NSMutableArray *out = [[NSMutableArray alloc] init];
    for (GFace *f in faces) {
        CTFontDescriptorRef d = descriptor(face_attributes(f));
        [out addObject:(id)d];
        CFRelease(d);
    }
    return (CFArrayRef)out;
}

/* ---- the font for a string ------------------------------------------------------------ */

/* The font that draws the first character of the range: the font itself when
 * it has it, otherwise the one fontconfig falls back to for that character,
 * in the font's weight and style. */
CTFontRef CTFontCreateForString(CTFontRef current, CFStringRef string, CFRange range)
{
    GFont *font = (GFont *)current;
    NSString *s = (NSString *)string;
    if (!font || !s || range.location < 0 || range.location >= (CFIndex)[s length])
        return (CTFontRef)[font retain];
    UTF32Char c = [s characterAtIndex:range.location];
    if (CFStringIsSurrogateHighCharacter(c) && range.location + 1 < (CFIndex)[s length])
        c = CFStringGetLongCharacterForSurrogatePair(c, [s characterAtIndex:range.location + 1]);
    hb_codepoint_t glyph;
    if (hb_font_get_nominal_glyph(font->hb, c, &glyph))
        return (CTFontRef)[font retain];
    static PangoContext *context;
    if (!context)
        context = pango_font_map_create_context(pango_font_get_font_map(font->font));
    PangoFontset *set = pango_context_load_fontset(context, font->desc, NULL);
    PangoFont *other = set ? pango_fontset_get_font(set, c) : NULL;
    if (set)
        g_object_unref(set);
    if (!other)
        return (CTFontRef)[font retain];
    PangoFontDescription *d = pango_font_describe(other);
    const char *family = pango_font_description_get_family(d);
    GFont *result = family ? GFontCreate(@(family), pango_font_description_get_weight(d),
                                         pango_font_description_get_style(d), font->size)
                           : nil;
    pango_font_description_free(d);
    g_object_unref(other);
    return (CTFontRef)(result ?: [font retain]);
}
