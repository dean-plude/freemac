#include "deco-theme.hpp"
#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>
#include <config.h>
#include <map>
#include <algorithm>
#include <cmath>

namespace wf
{
namespace strata_decor
{
/** Create a new theme with the default parameters */
decoration_theme_t::decoration_theme_t()
{}

/** @return The available height for displaying the title */
int decoration_theme_t::get_title_height() const
{
    return title_height;
}

/** @return The available border for resizing */
int decoration_theme_t::get_border_size() const
{
    return border_size;
}

/* Strata: alpha of the soft edge, from the window outwards, one value per
 * pixel of border. A light window gets a faint dark edge; a dark one a
 * stronger one, since it shows less against a dark desktop. */
static double edge_alpha(int k, int border, bool dark, bool active)
{
    static const double light[] = {0.24, 0.10, 0.05, 0.022, 0.01, 0.004};
    static const double darkw[] = {0.70, 0.30, 0.14, 0.06, 0.025, 0.01};
    if ((k < 0) || (k >= border) || (k >= 6))
    {
        return 0.0;
    }

    double a = dark ? darkw[k] : light[k];
    return active ? a : a * 0.7;
}

void decoration_theme_t::render_edges(const wf::render_target_t& fb,
    wf::geometry_t r, int top, const wf::geometry_t& scissor, bool active) const
{
    const int b = border_size;
    const bool dark = is_dark();
    OpenGL::render_begin(fb);
    fb.logic_scissor(scissor);
    auto proj = fb.get_orthographic_projection();
    for (int k = 0; k < b; k++)
    {
        double a = edge_alpha(k, b, dark, active);
        if (a <= 0.0)
        {
            continue;
        }

        wf::color_t c{0, 0, 0, a};
        int side_h = r.height - top - b;
        /* left and right: column b-1-k counted from the outer edge */
        OpenGL::render_rectangle({r.x + b - 1 - k, r.y + top, 1, side_h}, c, proj);
        OpenGL::render_rectangle({r.x + r.width - b + k, r.y + top, 1, side_h}, c, proj);
        /* bottom, between the two side columns of the same distance */
        OpenGL::render_rectangle({r.x + b - 1 - k, r.y + r.height - b + k,
            r.width - 2 * (b - 1 - k), 1}, c, proj);
    }

    OpenGL::render_end();
}

static void top_rounded(cairo_t *cr, double x, double y, double w, double h, double r)
{
    cairo_new_sub_path(cr);
    cairo_move_to(cr, x, y + h);
    cairo_line_to(cr, x, y + r);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_line_to(cr, x + w - r, y);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_line_to(cr, x + w, y + h);
    cairo_close_path(cr);
}

cairo_surface_t*decoration_theme_t::render_titlebar(int width, int height, double scale,
    bool active) const
{
    auto surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    if ((width == 0) || (height == 0))
    {
        return surface;
    }

    auto cr = cairo_create(surface);
    cairo_scale(cr, scale, scale);
    const double w = width / scale, h = height / scale;
    const int b = border_size;
    const double radius = 10.0;
    const bool dark = is_dark();

    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_rgba(cr, 0, 0, 0, 0);
    cairo_paint(cr);

    /* The soft edge, ring by ring from the outside in. */
    for (int k = b - 1; k >= 0; k--)
    {
        double inset = b - 1 - k;
        top_rounded(cr, inset, inset, w - 2 * inset, h - inset + 1, radius + b - inset);
        cairo_set_source_rgba(cr, 0, 0, 0, edge_alpha(k, b, dark, active));
        cairo_fill(cr);
    }

    /* The bar itself: a gentle top-to-bottom shade on the active window,
     * flat on the others. */
    wf::color_t c = active ? active_color : inactive_color;
    top_rounded(cr, b, b, w - 2 * b, h - b + 1, radius);
    if (active)
    {
        auto grad = cairo_pattern_create_linear(0, b, 0, h);
        double lift = dark ? 0.03 : 0.025;
        cairo_pattern_add_color_stop_rgba(grad, 0, std::min(1.0, c.r + lift), std::min(1.0, c.g + lift),
            std::min(1.0, c.b + lift), c.a);
        cairo_pattern_add_color_stop_rgba(grad, 1, c.r - lift, c.g - lift, c.b - lift, c.a);
        cairo_set_source(cr, grad);
        cairo_fill(cr);
        cairo_pattern_destroy(grad);
    } else
    {
        cairo_set_source_rgba(cr, c.r, c.g, c.b, c.a);
        cairo_fill(cr);
    }

    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    /* A thin highlight along the top, as light catching the edge. */
    cairo_new_path(cr);
    cairo_move_to(cr, b + radius, b + 0.5);
    cairo_line_to(cr, w - b - radius, b + 0.5);
    cairo_set_line_width(cr, 1.0);
    cairo_set_source_rgba(cr, 1, 1, 1, dark ? 0.10 : 0.55);
    cairo_stroke(cr);
    /* The hairline between the title bar and the window's content. */
    cairo_rectangle(cr, b, h - 1, w - 2 * b, 1);
    cairo_set_source_rgba(cr, 0, 0, 0, dark ? 0.45 : 0.11);
    cairo_fill(cr);

    cairo_destroy(cr);
    return surface;
}

/**
 * Render the given text on a cairo_surface_t with the given size.
 * The caller is responsible for freeing the memory afterwards.
 */
cairo_surface_t*decoration_theme_t::render_text(std::string text,
    int width, int height) const
{
    const auto format = CAIRO_FORMAT_ARGB32;
    auto surface = cairo_image_surface_create(format, width, height);

    if ((height == 0) || (width == 0))
    {
        return surface;
    }

    auto cr = cairo_create(surface);

    /* Strata: a modest, centred title in the text colour of the mode
     * (13 px on the standard 28 px title bar). */
    const double font_size = std::min(height * 0.465, 15.0);

    PangoFontDescription *font_desc;
    PangoLayout *layout;

    font_desc = pango_font_description_from_string(((std::string)font).c_str());
    pango_font_description_set_absolute_size(font_desc, font_size * PANGO_SCALE);
    pango_font_description_set_weight(font_desc, PANGO_WEIGHT_MEDIUM);

    layout = pango_cairo_create_layout(cr);
    pango_layout_set_font_description(layout, font_desc);
    pango_layout_set_text(layout, text.c_str(), text.size());
    pango_layout_set_width(layout, width * PANGO_SCALE);
    pango_layout_set_alignment(layout, PANGO_ALIGN_CENTER);
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    pango_layout_set_single_paragraph_mode(layout, true);

    int text_w, text_h;
    pango_layout_get_pixel_size(layout, &text_w, &text_h);
    cairo_move_to(cr, 0, (height - text_h) / 2.0);

    color_t ink = text_color();
    cairo_set_source_rgba(cr, ink.r, ink.g, ink.b, ink.a);
    pango_cairo_show_layout(cr, layout);
    pango_font_description_free(font_desc);
    g_object_unref(layout);
    cairo_destroy(cr);

    return surface;
}

/** Whether the title bar colour is dark, so text and symbols must be light. */
bool decoration_theme_t::is_dark() const
{
    wf::color_t c = active_color;
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
}

wf::color_t decoration_theme_t::text_color() const
{
    return is_dark() ? wf::color_t{0.88, 0.88, 0.90, 1.0} : wf::color_t{0.25, 0.25, 0.27, 1.0};
}

/*
 * Strata's window buttons: three small round buttons at the left, all the
 * same soft grey, with a thin symbol that appears while the pointer is over
 * any of them. Hovering one darkens it; an inactive window's are paler.
 */
cairo_surface_t*decoration_theme_t::get_button_surface(button_type_t button,
    const button_state_t& state) const
{
    cairo_surface_t *button_surface = cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32, state.width, state.height);

    auto cr = cairo_create(button_surface);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST);

    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

    const bool dark = is_dark();
    const double hover = std::fabs(state.hover_progress);
    const bool pressed = state.hover_progress < -1e-3;

    /* fill: the grey of the mode, a little deeper under the pointer */
    double g, a;
    if (dark)
    {
        g = state.active ? 0.40 : 0.32;
        g += (pressed ? 0.16 : 0.08) * hover;
        a = 1.0;
    } else
    {
        g = state.active ? 0.74 : 0.84;
        g -= (pressed ? 0.20 : 0.10) * hover;
        a = 1.0;
    }

    const double w = state.width, h = state.height;
    const double cx = w / 2.0, cy = h / 2.0, r = std::min(w, h) / 2.0 - 1.0;
    cairo_arc(cr, cx, cy, r, 0, 2 * M_PI);
    cairo_set_source_rgba(cr, g, g, g + 0.015, a);
    cairo_fill_preserve(cr);
    /* a hairline ring, so the button reads on any title bar colour */
    cairo_set_line_width(cr, std::max(1.0, w / 24.0));
    cairo_set_source_rgba(cr, 0, 0, 0, dark ? 0.35 : 0.14);
    cairo_stroke(cr);

    if (state.show_symbol)
    {
        wf::color_t ink = dark ? wf::color_t{0.95, 0.95, 0.97, 0.9} : wf::color_t{0.18, 0.18, 0.20, 0.85};
        cairo_set_source_rgba(cr, ink.r, ink.g, ink.b, ink.a);
        cairo_set_line_width(cr, std::max(1.2, w / 11.0));
        cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
        const double d = r * 0.42;
        switch (button)
        {
          case BUTTON_CLOSE:
            cairo_move_to(cr, cx - d, cy - d);
            cairo_line_to(cr, cx + d, cy + d);
            cairo_move_to(cr, cx + d, cy - d);
            cairo_line_to(cr, cx - d, cy + d);
            cairo_stroke(cr);
            break;

          case BUTTON_TOGGLE_MAXIMIZE:
            /* two small corners pointing out: make the window bigger */
            cairo_move_to(cr, cx - d, cy + d * 0.15);
            cairo_line_to(cr, cx - d, cy + d);
            cairo_line_to(cr, cx - d * 0.15, cy + d);
            cairo_move_to(cr, cx + d, cy - d * 0.15);
            cairo_line_to(cr, cx + d, cy - d);
            cairo_line_to(cr, cx + d * 0.15, cy - d);
            cairo_stroke(cr);
            break;

          case BUTTON_MINIMIZE:
            cairo_move_to(cr, cx - d * 1.05, cy);
            cairo_line_to(cr, cx + d * 1.05, cy);
            cairo_stroke(cr);
            break;

          default:
            assert(false);
        }
    }

    cairo_destroy(cr);
    return button_surface;
}
}
}
