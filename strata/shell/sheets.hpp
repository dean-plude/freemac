// SPDX-License-Identifier: GPL-3.0-or-later
// Sheets: a dialog that belongs to one window (Save, an unsaved-changes
// alert) comes down from that window's title bar, centred on it, and stays
// with the window when it moves, as on a Mac. It is never taller than the
// room below the title bar, nor (where the app lets it be narrower) wider
// than the window it belongs to.
//
// Which dialogs: those with a parent window that the app marks as modal
// through gtk-shell (GTK does for its Save and Open dialogs and its alerts).
// Other dialogs (About, Preferences) are windows of their own and are placed
// as usual. Original freemac code.
#pragma once

#include <algorithm>
#include <cstdlib>
#include <map>
#include <memory>
#include <set>
#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/render-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/util.hpp>
#include <wayfire/util/log.hpp>
#include <wayfire/view-transform.hpp>
#include <wayfire/workarea.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>

namespace strata_sheets
{
/* The surfaces GTK has marked modal (its gtk_surface1.set_modal). */
inline std::set<wl_resource*>& modal_surfaces()
{
    static std::set<wl_resource*> surfaces;
    return surfaces;
}

static const std::string TRANSFORMER = "strata-sheet-drop";
static constexpr int DROP_MS = 220;
/* How far down a client-drawn window's title bar reaches, when Strata
 * hasn't drawn it and can't measure it: freemac's own title bars. */
static constexpr int CLIENT_TITLE_BAR = 28;
/* Space kept on each side when a sheet is made to fit its window. */
static constexpr int SIDE = 16;

/* The sheet coming down: it grows from the parent's title bar downward. */
class drop_t
{
  public:
    drop_t(wayfire_toplevel_view view, wf::output_t *output) : view(view), output(output)
    {
        auto node = view->get_transformed_node();
        transformer = std::make_shared<wf::scene::view_2d_transformer_t>(view);
        node->add_transformer(transformer, wf::TRANSFORMER_HIGHLEVEL + 2, TRANSFORMER);
        start = wf::get_current_time();
        apply(0);
        output->render->add_effect(&hook, wf::OUTPUT_EFFECT_PRE);
        output->render->schedule_redraw();
    }

    ~drop_t()
    {
        output->render->rem_effect(&hook);
        auto node = view->get_transformed_node();
        if (node->get_transformer<wf::scene::view_2d_transformer_t>(TRANSFORMER))
        {
            view->damage();
            node->rem_transformer(TRANSFORMER);
        }
    }

    bool finished = false;

  private:
    wayfire_toplevel_view view;
    wf::output_t *output;
    std::shared_ptr<wf::scene::view_2d_transformer_t> transformer;
    int64_t start = 0;

    void apply(double t)
    {
        double k = 1 - (1 - t) * (1 - t);            // fast, then settling
        double scale = 0.06 + 0.94 * k;
        double height = view->get_geometry().height;
        auto node = view->get_transformed_node();
        node->begin_transform_update();
        transformer->scale_x = 1;
        transformer->scale_y = scale;
        /* Scaling happens about the middle; keep the top edge in place. */
        transformer->translation_y = -(1 - scale) * height / 2;
        transformer->alpha = 0.4 + 0.6 * k;
        node->end_transform_update();
    }

    wf::effect_hook_t hook = [=] ()
    {
        if (finished)
        {
            return;
        }

        double t = std::clamp((wf::get_current_time() - start) / (double)DROP_MS, 0.0, 1.0);
        apply(t);
        output->render->schedule_redraw();
        if (t >= 1.0)
        {
            finished = true;
        }
    };
};

class sheets_t
{
  public:
    void init()
    {
        wf::get_core().connect(&on_mapped);
        wf::get_core().connect(&on_unmapped);
        wf::get_core().connect(&on_geometry);
    }

  private:
    std::map<wayfire_toplevel_view, bool> sheets;   // sheet -> fitted once
    std::map<wayfire_toplevel_view, std::unique_ptr<drop_t>> drops;
    wf::wl_timer<true> cleanup;
    bool placing = false;

    static bool is_sheet(wayfire_toplevel_view view)
    {
        auto surface = view ? view->get_wlr_surface() : nullptr;
        bool modal   = view && (view->has_data("gtk-shell-modal") ||
            (surface && modal_surfaces().count(surface->resource)));
        return modal && view->parent && view->parent->is_mapped() && !view->pending_fullscreen();
    }

    /* Where the parent's title bar ends. */
    static int title_bar_bottom(wayfire_toplevel_view parent)
    {
        auto g = parent->get_geometry();
        int top = parent->toplevel()->current().margins.top;
        return g.y + (top > 0 ? top : CLIENT_TITLE_BAR);
    }

    /* The sheet's place under its parent, and on first showing, its size. */
    void place(wayfire_toplevel_view sheet, bool fit)
    {
        auto parent = sheet->parent;
        auto output = sheet->get_output();
        if (!parent || !output)
        {
            return;
        }

        auto area   = output->workarea->get_workarea();
        auto pg     = parent->get_geometry();
        auto g      = sheet->get_pending_geometry();
        int top     = std::max(area.y, title_bar_bottom(parent));
        if (fit)
        {
            int widest  = std::max(pg.width - 2 * SIDE, 1);
            int tallest = std::max(area.y + area.height - top, 1);
            g.width  = std::min(g.width, widest);
            g.height = std::min(g.height, tallest);
            /* Never smaller than the app allows. */
            auto surface = sheet->get_wlr_surface();
            auto xdg     = surface ? wlr_xdg_surface_try_from_wlr_surface(surface) : nullptr;
            if (xdg && (xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) && xdg->toplevel)
            {
                g.width  = std::max(g.width, xdg->toplevel->current.min_width);
                g.height = std::max(g.height, xdg->toplevel->current.min_height);
            }
        }

        g.x = pg.x + (pg.width - g.width) / 2;
        g.x = std::clamp(g.x, area.x, std::max(area.x, area.x + area.width - g.width));
        g.y = top;
        if (getenv("STRATA_SHEETS_DEBUG"))
        {
            LOGI("strata sheet ", fit ? "fit " : "move ", "parent=", pg, " area=", area, " top=", top,
                " was=", sheet->get_pending_geometry(), " now=", g);
        }

        if (g != sheet->get_pending_geometry())
        {
            placing = true;
            sheet->set_geometry(g);
            placing = false;
        }
    }

    wf::signal::connection_t<wf::view_mapped_signal> on_mapped = [=] (wf::view_mapped_signal *ev)
    {
        auto sheet = wf::toplevel_cast(ev->view);
        if (sheet && getenv("STRATA_SHEETS_DEBUG"))
        {
            LOGI("strata sheet? ", sheet->get_title(), " parent=", sheet->parent != nullptr,
                " modal=", is_sheet(sheet));
        }

        if (!is_sheet(sheet))
        {
            return;
        }

        sheets[sheet] = true;
        place(sheet, true);
        ev->is_positioned = true;
        if (auto output = sheet->get_output())
        {
            drops[sheet] = std::make_unique<drop_t>(sheet, output);
            cleanup.set_timeout(DROP_MS + 60, [=] ()
            {
                for (auto it = drops.begin(); it != drops.end();)
                {
                    it = it->second->finished ? drops.erase(it) : std::next(it);
                }

                return !drops.empty();
            });
        }
    };

    wf::signal::connection_t<wf::view_unmapped_signal> on_unmapped = [=] (wf::view_unmapped_signal *ev)
    {
        if (auto view = wf::toplevel_cast(ev->view))
        {
            sheets.erase(view);
            drops.erase(view);
        }
    };

    /* A window moved or changed size: its sheets go with it. A sheet that
     * changed its own size (the app answered the size it was given) is
     * centred again. */
    wf::signal::connection_t<wf::view_geometry_changed_signal> on_geometry =
        [=] (wf::view_geometry_changed_signal *ev)
    {
        if (placing || !ev->view)
        {
            return;
        }

        if (sheets.count(ev->view))
        {
            place(ev->view, false);
            return;
        }

        for (auto& child : ev->view->children)
        {
            if (sheets.count(child) && child->is_mapped())
            {
                place(child, false);
            }
        }
    };
};
}
