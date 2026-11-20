// SPDX-License-Identifier: GPL-3.0-or-later
// Minimizing shrinks the window down into its place in the Dock (the minimize
// hint Pier gives it), and restoring grows it back out from there, as on a
// Mac. Strata carries out the minimize itself: it animates first, then hides
// the window. Windows with no hint (or an empty one, as for hidden apps) are
// left to Wayfire and simply go.
// Original freemac code.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <functional>
#include <map>
#include <set>
#include <memory>
#include <string>
#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/util.hpp>
#include <wayfire/view-transform.hpp>

namespace strata_glide
{
static const std::string TRANSFORMER = "strata-minimize-glide";

/* How long the shrink takes, in milliseconds; about a Mac's.
 * STRATA_GLIDE_MS slows it down, for checking it frame by frame. */
inline int glide_length()
{
    static int length = [] ()
    {
        const char *slow = getenv("STRATA_GLIDE_MS");
        int ms = slow ? atoi(slow) : 0;
        return (ms >= 50 && ms <= 10000) ? ms : 320;
    }();
    return length;
}

class glide_t
{
  public:
    glide_t(wayfire_toplevel_view view, wf::output_t *output, bool minimizing, wf::pointf_t offset,
        double scale, std::function<void()> on_done) :
        view(view), minimizing(minimizing), output(output), offset(offset), scale(scale), on_done(on_done)
    {
        auto transformed = view->get_transformed_node();
        transformer = transformed->get_transformer<wf::scene::view_2d_transformer_t>(TRANSFORMER);
        if (!transformer)
        {
            transformer = std::make_shared<wf::scene::view_2d_transformer_t>(view);
            transformed->add_transformer(transformer, wf::TRANSFORMER_HIGHLEVEL + 1, TRANSFORMER);
        }

        start = wf::get_current_time();
        apply(0);
        output->render->add_effect(&hook, wf::OUTPUT_EFFECT_PRE);
        output->render->schedule_redraw();
    }

    ~glide_t()
    {
        output->render->rem_effect(&hook);
        if (transformer && view->get_transformed_node()->get_transformer<
            wf::scene::view_2d_transformer_t>(TRANSFORMER))
        {
            view->damage();
            view->get_transformed_node()->rem_transformer(TRANSFORMER);
        }
    }

    wayfire_toplevel_view view;
    bool minimizing;

  private:
    wf::output_t *output;
    wf::pointf_t offset;
    double scale;
    std::function<void()> on_done;
    std::shared_ptr<wf::scene::view_2d_transformer_t> transformer;
    int64_t start = 0;
    bool finished = false;

    /* t runs 0 to 1. k is how far toward the Dock the window is: 0 at its
     * own place, 1 in the Dock. It speeds up into the Dock and slows down
     * coming out of it. */
    void apply(double t)
    {
        double k  = minimizing ? t * t : (1 - t) * (1 - t);
        auto node = view->get_transformed_node();
        node->begin_transform_update();
        transformer->translation_x = offset.x * k;
        transformer->translation_y = offset.y * k;
        transformer->scale_x = transformer->scale_y = 1 + (scale - 1) * k;
        transformer->alpha   = 1 - 0.25 * k;
        node->end_transform_update();
    }

    wf::effect_hook_t hook = [=] ()
    {
        if (finished)
        {
            return;
        }

        double t = std::clamp((wf::get_current_time() - start) / (double)glide_length(), 0.0, 1.0);
        apply(t);
        output->render->schedule_redraw();
        if (t >= 1.0)
        {
            finished = true;
            on_done();
        }
    };
};

class glides_t
{
  public:
    void init()
    {
        for (auto output : wf::get_core().output_layout->get_outputs())
        {
            output->connect(&on_minimize_request);
        }

        wf::get_core().output_layout->connect(&on_output_added);
        wf::get_core().connect(&on_unmapped);
    }

  private:
    std::map<wayfire_toplevel_view, std::unique_ptr<glide_t>> running;
    wf::wl_idle_call idle_cleanup;

    void forget_later(wayfire_toplevel_view view)
    {
        idle_cleanup.run_once([=] ()
        {
            for (auto it = running.begin(); it != running.end();)
            {
                if (done.count(it->first))
                {
                    if (it->second->minimizing && !it->first->minimized)
                    {
                        it->first->set_minimized(true);
                    }

                    it = running.erase(it);
                } else
                {
                    ++it;
                }
            }

            done.clear();
        });
        done.insert(view);
    }

    std::set<wayfire_toplevel_view> done;

    /* Returns whether the glide runs. */
    bool start(wayfire_toplevel_view view, bool minimizing)
    {
        auto output = view->get_output();
        if (!output || !view->get_transformed_node() || !view->is_mapped())
        {
            return false;
        }

        wlr_box hint = view->get_minimize_hint();
        wf::geometry_t box = view->get_geometry();
        if ((hint.width <= 0) || (hint.height <= 0) || (box.width <= 0) || (box.height <= 0))
        {
            running.erase(view);
            return false;
        }

        double scale = std::min(1.0 * hint.width / box.width, 1.0 * hint.height / box.height);
        wf::pointf_t offset{
            (hint.x + hint.width / 2.0) - (box.x + box.width / 2.0),
            (hint.y + hint.height / 2.0) - (box.y + box.height / 2.0),
        };
        done.erase(view);
        running.erase(view);
        running[view] = std::make_unique<glide_t>(view, output, minimizing, offset, scale,
            [=] () { forget_later(view); });
        return true;
    }

    wf::signal::connection_t<wf::view_minimize_request_signal> on_minimize_request =
        [=] (wf::view_minimize_request_signal *ev)
    {
        if (ev->carried_out || !ev->view || (ev->view->minimized == ev->state))
        {
            return;
        }

        /* Minimizing: Strata hides the window itself once it has shrunk into
         * the Dock. Restoring: Wayfire shows it and it grows back out. */
        if (start(ev->view, ev->state) && ev->state)
        {
            ev->carried_out = true;
        }
    };

    wf::signal::connection_t<wf::output_added_signal> on_output_added =
        [=] (wf::output_added_signal *ev)
    {
        ev->output->connect(&on_minimize_request);
    };

    wf::signal::connection_t<wf::view_unmapped_signal> on_unmapped = [=] (wf::view_unmapped_signal *ev)
    {
        if (auto toplevel = wf::toplevel_cast(ev->view))
        {
            running.erase(toplevel);
            done.erase(toplevel);
        }
    };
};
}
