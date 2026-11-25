/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The parts of this system's Cairo, Pango and HarfBuzz that Ferry's Core
 * Graphics and Core Text call. These are Linux libraries; the frameworks
 * here are Mac code, but both sides use the same System V calling
 * convention, so a Mac library can call them directly. Ferry's loader finds
 * them (see src/host.c) under the made-up library name
 * /usr/lib/ferry/libFerryHost.dylib, which only Ferry's own frameworks use.
 *
 * The declarations are written here, from the libraries' published API
 * documentation, because the Mac build can't include Linux headers. Only
 * calls and structure layouts that are part of each library's stable public
 * API are used.
 */
#ifndef FERRY_GRAPHICS_HOST_H
#define FERRY_GRAPHICS_HOST_H
#include <stdint.h>

/* ---- Cairo -------------------------------------------------------------------- */

typedef struct _cairo cairo_t;
typedef struct _cairo_surface cairo_surface_t;
typedef struct _cairo_pattern cairo_pattern_t;
typedef struct _cairo_scaled_font cairo_scaled_font_t;
typedef struct _cairo_font_options cairo_font_options_t;
typedef int cairo_status_t;
typedef int cairo_bool_t;
typedef struct { double xx, yx, xy, yy, x0, y0; } cairo_matrix_t;
typedef struct { unsigned long index; double x, y; } cairo_glyph_t;
typedef union {
    struct { int type; int length; } header;
    struct { double x, y; } point;
} cairo_path_data_t;
typedef struct { cairo_status_t status; cairo_path_data_t *data; int num_data; } cairo_path_t;
typedef cairo_status_t (*cairo_read_func_t)(void *closure, unsigned char *data, unsigned int length);
typedef cairo_status_t (*cairo_write_func_t)(void *closure, const unsigned char *data, unsigned int length);

enum { CAIRO_FORMAT_ARGB32 = 0, CAIRO_FORMAT_RGB24 = 1, CAIRO_FORMAT_A8 = 2 };
enum {
    CAIRO_OPERATOR_CLEAR, CAIRO_OPERATOR_SOURCE, CAIRO_OPERATOR_OVER, CAIRO_OPERATOR_IN, CAIRO_OPERATOR_OUT,
    CAIRO_OPERATOR_ATOP, CAIRO_OPERATOR_DEST, CAIRO_OPERATOR_DEST_OVER, CAIRO_OPERATOR_DEST_IN,
    CAIRO_OPERATOR_DEST_OUT, CAIRO_OPERATOR_DEST_ATOP, CAIRO_OPERATOR_XOR, CAIRO_OPERATOR_ADD,
    CAIRO_OPERATOR_SATURATE, CAIRO_OPERATOR_MULTIPLY, CAIRO_OPERATOR_SCREEN, CAIRO_OPERATOR_OVERLAY,
    CAIRO_OPERATOR_DARKEN, CAIRO_OPERATOR_LIGHTEN, CAIRO_OPERATOR_COLOR_DODGE, CAIRO_OPERATOR_COLOR_BURN,
    CAIRO_OPERATOR_HARD_LIGHT, CAIRO_OPERATOR_SOFT_LIGHT, CAIRO_OPERATOR_DIFFERENCE, CAIRO_OPERATOR_EXCLUSION,
    CAIRO_OPERATOR_HSL_HUE, CAIRO_OPERATOR_HSL_SATURATION, CAIRO_OPERATOR_HSL_COLOR, CAIRO_OPERATOR_HSL_LUMINOSITY,
};
enum { CAIRO_FILL_RULE_WINDING = 0, CAIRO_FILL_RULE_EVEN_ODD = 1 };
enum { CAIRO_ANTIALIAS_DEFAULT = 0, CAIRO_ANTIALIAS_NONE = 1, CAIRO_ANTIALIAS_GRAY = 2 };
enum { CAIRO_EXTEND_NONE = 0, CAIRO_EXTEND_REPEAT = 1, CAIRO_EXTEND_REFLECT = 2, CAIRO_EXTEND_PAD = 3 };
enum { CAIRO_FILTER_FAST = 0, CAIRO_FILTER_GOOD = 1, CAIRO_FILTER_BEST = 2, CAIRO_FILTER_NEAREST = 3 };
enum { CAIRO_PATH_MOVE_TO = 0, CAIRO_PATH_LINE_TO = 1, CAIRO_PATH_CURVE_TO = 2, CAIRO_PATH_CLOSE_PATH = 3 };
enum { CAIRO_HINT_STYLE_NONE = 1 };
enum { CAIRO_HINT_METRICS_OFF = 1 };

cairo_surface_t *cairo_image_surface_create(int format, int width, int height);
cairo_surface_t *cairo_image_surface_create_for_data(unsigned char *data, int format, int width, int height,
                                                     int stride);
cairo_surface_t *cairo_image_surface_create_from_png_stream(cairo_read_func_t read, void *closure);
unsigned char *cairo_image_surface_get_data(cairo_surface_t *surface);
int cairo_image_surface_get_width(cairo_surface_t *surface);
int cairo_image_surface_get_height(cairo_surface_t *surface);
int cairo_image_surface_get_stride(cairo_surface_t *surface);
int cairo_image_surface_get_format(cairo_surface_t *surface);
int cairo_format_stride_for_width(int format, int width);
void cairo_surface_flush(cairo_surface_t *surface);
cairo_status_t cairo_surface_write_to_png_stream(cairo_surface_t *surface, cairo_write_func_t write, void *closure);
void cairo_surface_mark_dirty(cairo_surface_t *surface);
void cairo_surface_destroy(cairo_surface_t *surface);
cairo_surface_t *cairo_surface_reference(cairo_surface_t *surface);
cairo_status_t cairo_surface_status(cairo_surface_t *surface);

cairo_t *cairo_create(cairo_surface_t *target);
void cairo_destroy(cairo_t *cr);
void cairo_save(cairo_t *cr);
void cairo_restore(cairo_t *cr);
void cairo_set_matrix(cairo_t *cr, const cairo_matrix_t *matrix);
void cairo_get_matrix(cairo_t *cr, cairo_matrix_t *matrix);
void cairo_transform(cairo_t *cr, const cairo_matrix_t *matrix);
void cairo_identity_matrix(cairo_t *cr);
void cairo_user_to_device(cairo_t *cr, double *x, double *y);
void cairo_device_to_user(cairo_t *cr, double *x, double *y);
void cairo_set_source_rgba(cairo_t *cr, double r, double g, double b, double a);
void cairo_set_source(cairo_t *cr, cairo_pattern_t *source);
void cairo_set_source_surface(cairo_t *cr, cairo_surface_t *surface, double x, double y);
cairo_pattern_t *cairo_get_source(cairo_t *cr);
void cairo_set_line_width(cairo_t *cr, double width);
void cairo_set_line_cap(cairo_t *cr, int cap);
void cairo_set_line_join(cairo_t *cr, int join);
void cairo_set_miter_limit(cairo_t *cr, double limit);
void cairo_set_dash(cairo_t *cr, const double *dashes, int count, double offset);
void cairo_set_operator(cairo_t *cr, int op);
void cairo_set_fill_rule(cairo_t *cr, int rule);
void cairo_set_antialias(cairo_t *cr, int antialias);
void cairo_new_path(cairo_t *cr);
void cairo_new_sub_path(cairo_t *cr);
void cairo_move_to(cairo_t *cr, double x, double y);
void cairo_line_to(cairo_t *cr, double x, double y);
void cairo_curve_to(cairo_t *cr, double x1, double y1, double x2, double y2, double x3, double y3);
void cairo_close_path(cairo_t *cr);
void cairo_rectangle(cairo_t *cr, double x, double y, double w, double h);
void cairo_fill(cairo_t *cr);
void cairo_fill_preserve(cairo_t *cr);
void cairo_stroke(cairo_t *cr);
void cairo_stroke_preserve(cairo_t *cr);
void cairo_clip(cairo_t *cr);
void cairo_clip_extents(cairo_t *cr, double *x1, double *y1, double *x2, double *y2);
void cairo_paint(cairo_t *cr);
void cairo_paint_with_alpha(cairo_t *cr, double alpha);
void cairo_push_group(cairo_t *cr);
void cairo_pop_group_to_source(cairo_t *cr);
cairo_path_t *cairo_copy_path(cairo_t *cr);
void cairo_append_path(cairo_t *cr, const cairo_path_t *path);
void cairo_path_destroy(cairo_path_t *path);
cairo_bool_t cairo_has_current_point(cairo_t *cr);
void cairo_get_current_point(cairo_t *cr, double *x, double *y);
void cairo_path_extents(cairo_t *cr, double *x1, double *y1, double *x2, double *y2);
cairo_bool_t cairo_in_fill(cairo_t *cr, double x, double y);
cairo_bool_t cairo_in_stroke(cairo_t *cr, double x, double y);
void cairo_matrix_multiply(cairo_matrix_t *result, const cairo_matrix_t *a, const cairo_matrix_t *b);
cairo_status_t cairo_matrix_invert(cairo_matrix_t *matrix);
void cairo_set_scaled_font(cairo_t *cr, const cairo_scaled_font_t *scaled_font);
void cairo_show_glyphs(cairo_t *cr, const cairo_glyph_t *glyphs, int num_glyphs);
void cairo_glyph_path(cairo_t *cr, const cairo_glyph_t *glyphs, int num_glyphs);

cairo_pattern_t *cairo_pattern_create_for_surface(cairo_surface_t *surface);
cairo_pattern_t *cairo_pattern_create_linear(double x0, double y0, double x1, double y1);
cairo_pattern_t *cairo_pattern_create_radial(double cx0, double cy0, double r0, double cx1, double cy1, double r1);
void cairo_pattern_add_color_stop_rgba(cairo_pattern_t *p, double offset, double r, double g, double b, double a);
void cairo_pattern_set_extend(cairo_pattern_t *p, int extend);
void cairo_pattern_set_filter(cairo_pattern_t *p, int filter);
void cairo_pattern_set_matrix(cairo_pattern_t *p, const cairo_matrix_t *matrix);
void cairo_pattern_destroy(cairo_pattern_t *p);

cairo_font_options_t *cairo_font_options_create(void);
void cairo_font_options_set_hint_style(cairo_font_options_t *options, int style);
void cairo_font_options_set_hint_metrics(cairo_font_options_t *options, int metrics);
void cairo_font_options_destroy(cairo_font_options_t *options);

/* ---- GLib and GObject ----------------------------------------------------------- */

typedef struct _GSList { void *data; struct _GSList *next; } GSList;
void *g_object_ref(void *object);
void g_object_unref(void *object);

/* ---- Pango ------------------------------------------------------------------- */

#define PANGO_SCALE 1024
typedef struct _PangoFontMap PangoFontMap;
typedef struct _PangoContext PangoContext;
typedef struct _PangoFont PangoFont;
typedef struct _PangoFontDescription PangoFontDescription;
typedef struct _PangoFontMetrics PangoFontMetrics;
typedef struct _PangoLayout PangoLayout;
typedef struct _PangoLayoutIter PangoLayoutIter;
typedef struct _PangoAttrList PangoAttrList;
typedef struct { int x, y, width, height; } PangoRectangle;
typedef struct { const void *klass; unsigned start_index, end_index; } PangoAttribute;
typedef struct { void *layout; int start_index; int length; GSList *runs; unsigned flags; } PangoLayoutLine;
typedef struct { unsigned glyph; struct { int width, x_offset, y_offset; } geometry; unsigned attr; } PangoGlyphInfo;
typedef struct { int num_glyphs; PangoGlyphInfo *glyphs; int *log_clusters; } PangoGlyphString;
typedef struct { void *item; PangoGlyphString *glyphs; } PangoGlyphItem;

enum { PANGO_STYLE_NORMAL = 0, PANGO_STYLE_OBLIQUE = 1, PANGO_STYLE_ITALIC = 2 };
enum { PANGO_WEIGHT_THIN = 100, PANGO_WEIGHT_LIGHT = 300, PANGO_WEIGHT_NORMAL = 400, PANGO_WEIGHT_MEDIUM = 500,
       PANGO_WEIGHT_SEMIBOLD = 600, PANGO_WEIGHT_BOLD = 700, PANGO_WEIGHT_HEAVY = 900 };
enum { PANGO_ALIGN_LEFT = 0, PANGO_ALIGN_CENTER = 1, PANGO_ALIGN_RIGHT = 2 };
enum { PANGO_WRAP_WORD = 0, PANGO_WRAP_CHAR = 1, PANGO_WRAP_WORD_CHAR = 2 };
enum { PANGO_ELLIPSIZE_NONE = 0, PANGO_ELLIPSIZE_START = 1, PANGO_ELLIPSIZE_MIDDLE = 2, PANGO_ELLIPSIZE_END = 3 };
enum { PANGO_UNDERLINE_NONE = 0, PANGO_UNDERLINE_SINGLE = 1, PANGO_UNDERLINE_DOUBLE = 2 };

PangoFontDescription *pango_font_description_new(void);
PangoFontDescription *pango_font_description_copy(const PangoFontDescription *desc);
void pango_font_description_free(PangoFontDescription *desc);
void pango_font_description_set_family(PangoFontDescription *desc, const char *family);
void pango_font_description_set_weight(PangoFontDescription *desc, int weight);
void pango_font_description_set_style(PangoFontDescription *desc, int style);
void pango_font_description_set_absolute_size(PangoFontDescription *desc, double size);
const char *pango_font_description_get_family(const PangoFontDescription *desc);
int pango_font_description_get_weight(const PangoFontDescription *desc);
int pango_font_description_get_style(const PangoFontDescription *desc);
PangoFontDescription *pango_font_describe(PangoFont *font);
void *pango_font_get_hb_font(PangoFont *font);

PangoContext *pango_font_map_create_context(PangoFontMap *fontmap);
PangoFont *pango_context_load_font(PangoContext *context, const PangoFontDescription *desc);
void pango_context_set_round_glyph_positions(PangoContext *context, int round_positions);

PangoLayout *pango_layout_new(PangoContext *context);
void pango_layout_set_text(PangoLayout *layout, const char *text, int length);
void pango_layout_set_attributes(PangoLayout *layout, PangoAttrList *attrs);
void pango_layout_set_font_description(PangoLayout *layout, const PangoFontDescription *desc);
void pango_layout_set_width(PangoLayout *layout, int width);
void pango_layout_set_wrap(PangoLayout *layout, int wrap);
void pango_layout_set_ellipsize(PangoLayout *layout, int ellipsize);
void pango_layout_set_alignment(PangoLayout *layout, int alignment);
void pango_layout_set_single_paragraph_mode(PangoLayout *layout, int setting);
int pango_layout_get_line_count(PangoLayout *layout);
PangoLayoutLine *pango_layout_get_line_readonly(PangoLayout *layout, int line);
void pango_layout_get_extents(PangoLayout *layout, PangoRectangle *ink, PangoRectangle *logical);
PangoLayoutIter *pango_layout_get_iter(PangoLayout *layout);
int pango_layout_iter_get_baseline(PangoLayoutIter *iter);
void pango_layout_iter_get_line_extents(PangoLayoutIter *iter, PangoRectangle *ink, PangoRectangle *logical);
int pango_layout_iter_next_line(PangoLayoutIter *iter);
void pango_layout_iter_free(PangoLayoutIter *iter);
void pango_layout_line_get_extents(PangoLayoutLine *line, PangoRectangle *ink, PangoRectangle *logical);
void pango_layout_line_index_to_x(PangoLayoutLine *line, int index, int trailing, int *x_pos);
int pango_layout_line_x_to_index(PangoLayoutLine *line, int x_pos, int *index, int *trailing);

PangoAttrList *pango_attr_list_new(void);
void pango_attr_list_insert(PangoAttrList *list, PangoAttribute *attr);
void pango_attr_list_unref(PangoAttrList *list);
PangoAttribute *pango_attr_font_desc_new(const PangoFontDescription *desc);
PangoAttribute *pango_attr_foreground_new(uint16_t red, uint16_t green, uint16_t blue);
PangoAttribute *pango_attr_foreground_alpha_new(uint16_t alpha);
PangoAttribute *pango_attr_letter_spacing_new(int letter_spacing);
PangoAttribute *pango_attr_underline_new(int underline);
PangoAttribute *pango_attr_underline_color_new(uint16_t red, uint16_t green, uint16_t blue);

PangoFontMap *pango_cairo_font_map_get_default(void);
void pango_cairo_context_set_resolution(PangoContext *context, double dpi);
void pango_cairo_context_set_font_options(PangoContext *context, const cairo_font_options_t *options);
void pango_cairo_show_layout_line(cairo_t *cr, PangoLayoutLine *line);
void pango_cairo_layout_line_path(cairo_t *cr, PangoLayoutLine *line);
cairo_scaled_font_t *pango_cairo_font_get_scaled_font(PangoFont *font);

/* ---- HarfBuzz ---------------------------------------------------------------- */

typedef struct hb_font_t hb_font_t;
typedef struct hb_face_t hb_face_t;
typedef uint32_t hb_codepoint_t;
typedef int32_t hb_position_t;
typedef int hb_bool_t;
typedef struct { hb_position_t x_bearing, y_bearing, width, height; } hb_glyph_extents_t;
typedef struct { hb_position_t ascender, descender, line_gap, reserved[9]; } hb_font_extents_t;
#define HB_TAG(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

hb_face_t *hb_font_get_face(hb_font_t *font);
unsigned hb_face_get_upem(const hb_face_t *face);
unsigned hb_face_get_glyph_count(const hb_face_t *face);
hb_font_t *hb_font_create(hb_face_t *face);
void hb_font_destroy(hb_font_t *font);
hb_bool_t hb_font_get_nominal_glyph(hb_font_t *font, hb_codepoint_t unicode, hb_codepoint_t *glyph);
hb_position_t hb_font_get_glyph_h_advance(hb_font_t *font, hb_codepoint_t glyph);
hb_bool_t hb_font_get_glyph_extents(hb_font_t *font, hb_codepoint_t glyph, hb_glyph_extents_t *extents);
hb_bool_t hb_font_get_h_extents(hb_font_t *font, hb_font_extents_t *extents);
hb_bool_t hb_ot_metrics_get_position(hb_font_t *font, uint32_t tag, hb_position_t *position);

/* ---- GdkPixbuf (decoding image files) and Poppler (PDF) ------------------------- */

typedef struct { uint32_t domain; int code; char *message; } GError;
void g_error_free(GError *error);
typedef struct _GdkPixbuf GdkPixbuf;
typedef struct _GdkPixbufLoader GdkPixbufLoader;
typedef struct _GdkPixbufFormat GdkPixbufFormat;
GdkPixbufLoader *gdk_pixbuf_loader_new(void);
int gdk_pixbuf_loader_write(GdkPixbufLoader *loader, const unsigned char *buf, unsigned long count, GError **error);
int gdk_pixbuf_loader_close(GdkPixbufLoader *loader, GError **error);
GdkPixbuf *gdk_pixbuf_loader_get_pixbuf(GdkPixbufLoader *loader);
GdkPixbufFormat *gdk_pixbuf_loader_get_format(GdkPixbufLoader *loader);
char *gdk_pixbuf_format_get_name(GdkPixbufFormat *format);
int gdk_pixbuf_get_width(const GdkPixbuf *pixbuf);
int gdk_pixbuf_get_height(const GdkPixbuf *pixbuf);
int gdk_pixbuf_get_rowstride(const GdkPixbuf *pixbuf);
int gdk_pixbuf_get_n_channels(const GdkPixbuf *pixbuf);
int gdk_pixbuf_get_has_alpha(const GdkPixbuf *pixbuf);
unsigned char *gdk_pixbuf_get_pixels(const GdkPixbuf *pixbuf);
GdkPixbuf *gdk_pixbuf_new_from_data(const unsigned char *data, int colorspace, int has_alpha, int bits_per_sample,
                                    int width, int height, int rowstride, void (*destroy)(unsigned char *, void *),
                                    void *destroy_data);
int gdk_pixbuf_save_to_bufferv(GdkPixbuf *pixbuf, char **buffer, unsigned long *size, const char *type,
                               char **option_keys, char **option_values, GError **error);
void g_free(void *mem);

typedef struct _PopplerDocument PopplerDocument;
typedef struct _PopplerPage PopplerPage;
PopplerDocument *poppler_document_new_from_data(char *data, int length, const char *password, GError **error);
int poppler_document_get_n_pages(PopplerDocument *document);
PopplerPage *poppler_document_get_page(PopplerDocument *document, int index);
void poppler_page_get_size(PopplerPage *page, double *width, double *height);
void poppler_page_render(PopplerPage *page, cairo_t *cairo);

/* JPEG 2000 pictures, as an .icns file may hold its artwork (CGImage.m),
 * read by OpenJPEG's published API: a decoder for the JP2 file format, a
 * stream that reads from memory through three calls back, and the decoded
 * image's components, one plane of whole numbers each. */
typedef struct opj_codec opj_codec_t;
typedef struct opj_stream opj_stream_t;
typedef struct {
    uint32_t dx, dy, w, h, x0, y0, prec, bpp, sgnd, resno_decoded, factor;
    int32_t *data;
    uint16_t alpha;
} opj_image_comp_t;
typedef struct {
    uint32_t x0, y0, x1, y1, numcomps;
    int color_space;
    opj_image_comp_t *comps;
    unsigned char *icc_profile_buf;
    uint32_t icc_profile_len;
} opj_image_t;
/* opj_dparameters_t, which only OpenJPEG itself fills in and reads: room
 * for it, larger than it is */
typedef struct {
    _Alignas(8) unsigned char room[65536];
} opj_dparameters_t;
enum { OPJ_CODEC_J2K = 0, OPJ_CODEC_JP2 = 2 };
void opj_set_default_decoder_parameters(opj_dparameters_t *parameters);
/* weakly: NULL when OpenJPEG isn't installed */
opj_codec_t *opj_create_decompress(int format) __attribute__((weak_import));
int opj_setup_decoder(opj_codec_t *codec, opj_dparameters_t *parameters);
int opj_read_header(opj_stream_t *stream, opj_codec_t *codec, opj_image_t **image);
int opj_set_decoded_resolution_factor(opj_codec_t *codec, uint32_t factor);
int opj_decode(opj_codec_t *codec, opj_stream_t *stream, opj_image_t *image);
int opj_end_decompress(opj_codec_t *codec, opj_stream_t *stream);
void opj_destroy_codec(opj_codec_t *codec);
void opj_image_destroy(opj_image_t *image);
opj_stream_t *opj_stream_create(size_t buffer_size, int is_input);
void opj_stream_set_read_function(opj_stream_t *stream, size_t (*read)(void *buffer, size_t n, void *data));
void opj_stream_set_skip_function(opj_stream_t *stream, int64_t (*skip)(int64_t n, void *data));
void opj_stream_set_seek_function(opj_stream_t *stream, int (*seek)(int64_t at, void *data));
void opj_stream_set_user_data(opj_stream_t *stream, void *data, void (*free_data)(void *data));
void opj_stream_set_user_data_length(opj_stream_t *stream, uint64_t length);
void opj_stream_destroy(opj_stream_t *stream);

/* Shadows (CGContext.m): what a call draws is gathered in a group, whose
 * pixels are blurred into the shadow, and inline images in text, which
 * take the room of a shape in Pango's layout (CoreText.m). */
enum { CAIRO_SURFACE_TYPE_IMAGE = 0 };
cairo_pattern_t *cairo_pop_group(cairo_t *cr);
cairo_status_t cairo_pattern_get_surface(cairo_pattern_t *p, cairo_surface_t **surface);
void cairo_pattern_get_matrix(cairo_pattern_t *p, cairo_matrix_t *matrix);
void cairo_surface_get_device_offset(cairo_surface_t *surface, double *x, double *y);
void cairo_surface_set_device_offset(cairo_surface_t *surface, double x, double y);
void cairo_surface_get_device_scale(cairo_surface_t *surface, double *x, double *y);
void cairo_surface_set_device_scale(cairo_surface_t *surface, double x, double y);
int cairo_surface_get_type(cairo_surface_t *surface);
int cairo_get_operator(cairo_t *cr);
void cairo_mask(cairo_t *cr, cairo_pattern_t *pattern);
PangoLayout *pango_layout_copy(PangoLayout *layout);
PangoAttrList *pango_layout_get_attributes(PangoLayout *layout);
PangoAttrList *pango_attr_list_copy(PangoAttrList *list);
PangoAttribute *pango_attr_shape_new(const PangoRectangle *ink, const PangoRectangle *logical);

#endif
