// SPDX-License-Identifier: GPL-3.0-or-later
// Shake the pointer to find it, as on a Mac (Dials > Accessibility >
// Shake mouse pointer to locate): moving the mouse quickly back and forth
// makes the pointer grow large for a moment, then shrink back.
//
// Strata watches pointer motion after Wayfire has handled it. Five quick
// turns (each after at least 40 px of travel) within 900 ms count as a
// shake. While it lasts, the real pointer is hidden and a large arrow is
// drawn in its place as an overlay on the display under it.
// Original freemac code; the arrow is drawn here with Cairo.
#pragma once

#include <algorithm>
#include <cairo.h>
#include <cmath>
#include <deque>
#include <map>
#include <wayfire/core.hpp>
#include <wayfire/opengl.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>
#include <wayfire/plugins/common/cairo-util.hpp>
#include <wayfire/plugins/common/simple-texture.hpp>

namespace strata_locate
{
static const int TURNS_NEEDED = 5;
static const int TURN_WINDOW  = 900;   // ms
static const double TURN_TRAVEL = 40;  // px between turns
static const int GROW_MS   = 160;
static const int HOLD_MS   = 450;      // stays big this long after the shaking stops
static const int SHRINK_MS = 260;
static const double BIG    = 4.0;      // times the normal pointer
static const int ARROW_PX  = 24;       // the normal pointer's height
static const int TEXTURE_PX = 112;     // drawn once at this height

/* A plain arrow, its tip at (0, 0), in a 12 x 19 box: black with a white
 * edge, like the pointer it stands in for. */
static void arrow_path(cairo_t *cr)
{
    cairo_move_to(cr, 0, 0);
    cairo_line_to(cr, 0, 16.5);
    cairo_line_to(cr, 3.9, 12.8);
    cairo_line_to(cr, 6.6, 18.9);
    cairo_line_to(cr, 9.2, 17.8);
    cairo_line_to(cr, 6.6, 11.9);
    cairo_line_to(cr, 12, 11.9);
    cairo_close_path(cr);
}

class locate_t
{
  public:
    void init()
    {
        wf::get_core().connect(&on_motion);
        wf::get_core().connect(&on_motion_absolute);
        wf::get_core().output_layout->connect(&on_output_removed);
    }

    void fini()
    {
        finish();
        if (texture.tex != (GLuint)-1)
        {
            OpenGL::render_begin();
            texture.release();
            OpenGL::render_end();
        }
    }

  private:
    wf::option_wrapper_t<bool> enabled{"strata-shell/shake_to_locate"};
    wf::simple_texture_t texture;
    double tex_scale = 1.0;   // TEXTURE_PX / the arrow's height in its own units

    /* Shake detection */
    double last_x   = NAN;
    int direction   = 0;
    double travel   = 0;
    std::deque<int64_t> turns;

    /* The effect */
    bool active = false;
    bool hidden = false;
    int64_t started = 0;      // when it began to grow
    int64_t last_shake = 0;   // the last turn that kept it going
    wf::output_t *shown_on = nullptr;
    wf::geometry_t last_box = {0, 0, 0, 0};

    void moved()
    {
        if (!enabled)
        {
            return;
        }

        auto at = wf::get_core().get_cursor_position();
        if (std::isnan(last_x))
        {
            last_x = at.x;
            return;
        }

        double dx = at.x - last_x;
        last_x = at.x;
        if (std::abs(dx) < 0.5)
        {
            if (active)
            {
                damage();
            }

            return;
        }

        int now = (dx > 0) ? 1 : -1;
        int64_t time = wf::get_current_time();
        if (now == direction)
        {
            travel += std::abs(dx);
        } else
        {
            if ((direction != 0) && (travel >= TURN_TRAVEL))
            {
                turns.push_back(time);
            }

            direction = now;
            travel    = std::abs(dx);
        }

        while (!turns.empty() && (time - turns.front() > TURN_WINDOW))
        {
            turns.pop_front();
        }

        if ((int)turns.size() >= TURNS_NEEDED)
        {
            shake(time);
        }

        if (active)
        {
            damage();
        }
    }

    void shake(int64_t time)
    {
        bool shrinking = active && (time - last_shake > HOLD_MS);
        last_shake = time;
        if (active)
        {
            /* Shaking again while it shrinks grows it straight back. */
            if (shrinking)
            {
                started = time - GROW_MS;
            }

            return;
        }

        make_texture();
        active  = true;
        started = time;
        if (!hidden)
        {
            wf::get_core().hide_cursor();
            hidden = true;
        }

        follow_output();
        damage();
    }

    /* How big the arrow is now, in times the normal pointer; 0 when done. */
    double size_now() const
    {
        int64_t now = wf::get_current_time();
        double t    = now - started;
        double grow = std::clamp(t / GROW_MS, 0.0, 1.0);
        grow = 1 - (1 - grow) * (1 - grow);   // ease out
        double since = now - last_shake - HOLD_MS;
        if (since <= 0)
        {
            return 1 + (BIG - 1) * grow;
        }

        double shrink = std::clamp(since / SHRINK_MS, 0.0, 1.0);
        if (shrink >= 1)
        {
            return 0;
        }

        return 1 + (BIG - 1) * grow * (1 - shrink * shrink);
    }

    wf::output_t *output_at_cursor()
    {
        auto at = wf::get_core().get_cursor_position();
        return wf::get_core().output_layout->get_output_coords_at(at, at);
    }

    void follow_output()
    {
        auto output = output_at_cursor();
        if (output == shown_on)
        {
            return;
        }

        stop_hooks();
        shown_on = output;
        if (shown_on)
        {
            shown_on->render->add_effect(&pre, wf::OUTPUT_EFFECT_PRE);
            shown_on->render->add_effect(&overlay, wf::OUTPUT_EFFECT_OVERLAY);
            shown_on->render->damage_whole();
        }
    }

    void stop_hooks()
    {
        if (shown_on)
        {
            shown_on->render->rem_effect(&pre);
            shown_on->render->rem_effect(&overlay);
            shown_on->render->damage(last_box);
            shown_on = nullptr;
        }
    }

    void finish()
    {
        active = false;
        turns.clear();
        stop_hooks();
        if (hidden)
        {
            wf::get_core().unhide_cursor();
            hidden = false;
        }
    }

    /* Where the arrow goes now on `shown_on`, in that output's coordinates. */
    wf::geometry_t box_now(double size)
    {
        auto at     = wf::get_core().get_cursor_position();
        auto origin = wf::origin(shown_on->get_layout_geometry());
        double height = ARROW_PX * size;
        double width  = height * texture.width / std::max(1, texture.height);
        // The texture has a margin around the arrow for its edge and
        // shadow; keep the tip on the pointer's hot spot.
        double inset = MARGIN * height / TEXTURE_PX;
        return {
            (int)std::floor(at.x - origin.x - inset),
            (int)std::floor(at.y - origin.y - inset),
            (int)std::ceil(width),
            (int)std::ceil(height),
        };
    }

    /* Work out where the arrow goes this frame and damage both its old and
     * new place; the overlay then draws exactly there, so nothing is drawn
     * outside what this frame repaints. */
    void damage()
    {
        if (shown_on)
        {
            shown_on->render->damage(last_box);
            last_box = box_now(std::max(1.0, size_now()));
            shown_on->render->damage(last_box);
        }
    }

    static constexpr double MARGIN = 6;   // px of the texture around the arrow

    void make_texture()
    {
        if (texture.tex != (GLuint)-1)
        {
            return;
        }

        /* The arrow is 19 units tall; fit it, with a margin, in TEXTURE_PX. */
        tex_scale = (TEXTURE_PX - 2 * MARGIN) / 19.0;
        int width = (int)std::ceil(12 * tex_scale + 2 * MARGIN);
        auto surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, TEXTURE_PX);
        auto cr = cairo_create(surface);
        cairo_translate(cr, MARGIN, MARGIN);
        cairo_scale(cr, tex_scale, tex_scale);
        cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
        // A soft shadow under it.
        cairo_save(cr);
        cairo_translate(cr, 0.35, 0.6);
        arrow_path(cr);
        cairo_set_source_rgba(cr, 0, 0, 0, 0.28);
        cairo_set_line_width(cr, 1.6);
        cairo_stroke_preserve(cr);
        cairo_fill(cr);
        cairo_restore(cr);
        arrow_path(cr);
        cairo_set_source_rgb(cr, 1, 1, 1);
        cairo_set_line_width(cr, 1.7);
        cairo_stroke_preserve(cr);
        cairo_set_source_rgb(cr, 0, 0, 0);
        cairo_fill(cr);
        cairo_destroy(cr);
        cairo_surface_flush(surface);
        OpenGL::render_begin();
        cairo_surface_upload_to_texture(surface, texture);
        OpenGL::render_end();
        cairo_surface_destroy(surface);
    }

    wf::effect_hook_t pre = [=] ()
    {
        if (!active)
        {
            return;
        }

        if (size_now() <= 0)
        {
            // Done: the normal pointer comes back.
            finish();
            return;
        }

        follow_output();
        damage();
    };

    wf::effect_hook_t overlay = [=] ()
    {
        if (!active || !shown_on)
        {
            return;
        }

        make_texture();
        auto box = last_box;
        auto fb  = shown_on->render->get_target_framebuffer();
        OpenGL::render_begin(fb);
        fb.logic_scissor(box);
        OpenGL::render_texture(texture.tex, fb, box, glm::vec4(1.0f),
            OpenGL::TEXTURE_TRANSFORM_INVERT_Y);
        OpenGL::render_end();
    };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_motion_event>> on_motion =
        [=] (wf::post_input_event_signal<wlr_pointer_motion_event>*)
    {
        moved();
    };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_motion_absolute_event>>
    on_motion_absolute =
        [=] (wf::post_input_event_signal<wlr_pointer_motion_absolute_event>*)
    {
        moved();
    };

    wf::signal::connection_t<wf::output_removed_signal> on_output_removed =
        [=] (wf::output_removed_signal *ev)
    {
        if (ev->output == shown_on)
        {
            shown_on = nullptr;
            finish();
        }
    };
};
}
