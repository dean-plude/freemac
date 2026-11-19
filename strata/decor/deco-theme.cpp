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

/**
 * Fill the given rectangle with the background color(s).
 *
 * @param fb The target framebuffer, must have been bound already
 * @param rectangle The rectangle to redraw.
 * @param scissor The GL scissor rectangle to use.
 * @param active Whether to use active or inactive colors
 */
void decoration_theme_t::render_background(const wf::render_target_t& fb,
    wf::geometry_t rectangle, const wf::geometry_t& scissor, bool active) const
{
    wf::color_t color = active ? active_color : inactive_color;
    OpenGL::render_begin(fb);
    fb.logic_scissor(scissor);
    OpenGL::render_rectangle(rectangle, color, fb.get_orthographic_projection());
    OpenGL::render_end();
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

    /* Strata: a modest, centred title in the text colour of the mode. */
    const double font_size = std::min(height * 0.44, 15.0);

    PangoFontDescription *font_desc;
    PangoLayout *layout;

    font_desc = pango_font_description_from_string(((std::string)font).c_str());
    pango_font_description_set_absolute_size(font_desc, font_size * PANGO_SCALE);
    pango_font_description_set_weight(font_desc, PANGO_WEIGHT_SEMIBOLD);

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
    return is_dark() ? wf::color_t{0.92, 0.92, 0.96, 1.0} : wf::color_t{0.18, 0.18, 0.24, 1.0};
}

static void rounded_rectangle(cairo_t *cr, double x, double y, double w, double h, double r)
{
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

/*
 * Strata's window buttons: soft rounded squares with a thin symbol, the same
 * look as the buttons freemac's own apps draw. Hovering darkens them; the
 * close button turns freemac's indigo accent.
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
    wf::color_t ink = text_color();

    wf::color_t base = dark ? wf::color_t{1.0, 1.0, 1.0, 0.10} : wf::color_t{0.30, 0.30, 0.40, 0.12};
    base.a += (pressed ? 0.22 : 0.12) * hover;
    if ((button == BUTTON_CLOSE) && (hover > 1e-3))
    {
        /* freemac indigo (#4b5fc4), fading in with the hover */
        base = {0x4b / 255.0, 0x5f / 255.0, 0xc4 / 255.0, 0.35 + 0.6 * hover};
        ink  = {1.0, 1.0, 1.0, 1.0};
    }

    const double w = state.width, h = state.height;
    rounded_rectangle(cr, 0.5, 0.5, w - 1, h - 1, std::min(w, h) * 0.24);
    cairo_set_source_rgba(cr, base.r, base.g, base.b, base.a);
    cairo_fill(cr);

    cairo_set_source_rgba(cr, ink.r, ink.g, ink.b, 0.85);
    cairo_set_line_width(cr, std::max(1.2, w / 14.0));
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    const double a = w * 0.34, b = w * 0.66, ya = h * 0.34, yb = h * 0.66;
    switch (button)
    {
      case BUTTON_CLOSE:
        cairo_move_to(cr, a, ya);
        cairo_line_to(cr, b, yb);
        cairo_move_to(cr, b, ya);
        cairo_line_to(cr, a, yb);
        cairo_stroke(cr);
        break;

      case BUTTON_TOGGLE_MAXIMIZE:
        rounded_rectangle(cr, a, ya, b - a, yb - ya, w * 0.05);
        cairo_stroke(cr);
        break;

      case BUTTON_MINIMIZE:
        cairo_move_to(cr, a, h / 2.0);
        cairo_line_to(cr, b, h / 2.0);
        cairo_stroke(cr);
        break;

      default:
        assert(false);
    }

    cairo_destroy(cr);
    return button_surface;
}
}
}
