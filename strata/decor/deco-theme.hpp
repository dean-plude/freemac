#pragma once
#include <wayfire/render-manager.hpp>
#include "deco-button.hpp"

namespace wf
{
namespace strata_decor
{
/**
 * A  class which manages the outlook of decorations.
 * It is responsible for determining the background colors, sizes, etc.
 */
class decoration_theme_t
{
  public:
    /** Create a new theme with the default parameters */
    decoration_theme_t();

    /** @return The available height for displaying the title */
    int get_title_height() const;
    /** @return The available border for resizing */
    int get_border_size() const;

    /**
     * Strata: draw the sides and bottom of the frame: a soft edge that fades
     * out from the window, like a small shadow, in place of a solid border.
     *
     * @param fb The target framebuffer.
     * @param rectangle The whole frame, in logical coordinates.
     * @param top Height of the title bar part (drawn by render_titlebar).
     * @param scissor The GL scissor rectangle to use.
     * @param active Whether the window is the active one.
     */
    void render_edges(const wf::render_target_t& fb, wf::geometry_t rectangle, int top,
        const wf::geometry_t& scissor, bool active) const;

    /**
     * Strata: the title bar, with rounded top corners, the same soft edge and
     * a hairline under it, as a cairo surface of the given pixel size.
     * The caller frees it.
     */
    cairo_surface_t *render_titlebar(int width, int height, double scale, bool active) const;

    /**
     * Render the given text on a cairo_surface_t with the given size.
     * The caller is responsible for freeing the memory afterwards.
     */
    cairo_surface_t *render_text(std::string text, int width, int height) const;

    struct button_state_t
    {
        /** Button width */
        double width;
        /** Button height */
        double height;
        /** Button outline size */
        double border;
        /** Progress of button hover, in range [-1, 1].
         * Negative numbers are usually used for pressed state. */
        double hover_progress;
        /** Strata: draw the symbol (the pointer is over the buttons) */
        bool show_symbol;
        /** Strata: the window is the active one */
        bool active;
    };

    /**
     * Get the icon for the given button.
     * The caller is responsible for freeing the memory afterwards.
     *
     * @param button The button type.
     * @param state The button state.
     */
    cairo_surface_t *get_button_surface(button_type_t button,
        const button_state_t& state) const;

    /** Whether the title bar is dark (so its text and symbols are light) */
    bool is_dark() const;
    /** Title and symbol colour for the current title bar colour */
    wf::color_t text_color() const;

  private:
    wf::option_wrapper_t<std::string> font{"decoration/font"};
    wf::option_wrapper_t<int> title_height{"decoration/title_height"};
    wf::option_wrapper_t<int> border_size{"decoration/border_size"};
    wf::option_wrapper_t<wf::color_t> active_color{"decoration/active_color"};
    wf::option_wrapper_t<wf::color_t> inactive_color{"decoration/inactive_color"};
};
}
}
