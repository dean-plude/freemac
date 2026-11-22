// SPDX-License-Identifier: GPL-3.0-or-later
// Mission Control's row of desktops: while the overview of windows is open
// (Ctrl+Up, a 4-finger swipe up, the Mission Control key), Topline shows the
// desktops along the top of the screen (shell/freemac_shell/spaces.py), and
// a click on one goes to that desktop, as on a Mac.
//
// The overview is Wayfire's scale plugin, which takes all pointer input while
// it is open, so the row itself never sees the pointer. Strata watches
// instead: it tells Topline when the overview opens and closes and where the
// pointer is near the top of the screen ("spaces open OUTPUT", "spaces close",
// "spaces pointer X Y"), Topline tells Strata where its desktops are drawn
// (strata/spaces-areas), and a click inside one of those areas is kept from
// the overview, which is closed before Strata moves to that desktop.
// strata/desktops lists the desktops and the windows on each, for drawing.
// A window dragged out of the overview and let go over a desktop in the row
// moves to that desktop, as on a Mac.
// Original freemac code.
#pragma once

#include <functional>
#include <string>
#include <vector>
#include <wayfire/core.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/util.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/workspace-set.hpp>
#include <wayfire/plugins/scale-signal.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/common/move-drag-interface.hpp>

namespace strata_spaces
{
/* How far down the screen the pointer is reported while the overview is
 * open: the row, opened out, is never taller than this. */
static const int REPORT_HEIGHT = 240;

struct area_t
{
    wf::geometry_t box;
    wf::point_t desktop;
};

class spaces_t
{
  public:
    void init(std::function<void(const std::string&)> tell)
    {
        this->tell = tell;
        for (auto output : wf::get_core().output_layout->get_outputs())
        {
            watch(output);
        }

        wf::get_core().output_layout->connect(&on_output_added);
        wf::get_core().output_layout->connect(&on_output_removed);
        wf::get_core().connect(&on_motion);
        wf::get_core().connect(&on_motion_absolute);
        wf::get_core().connect(&on_button);
        drag->connect(&on_drag_done);
    }

    /* strata/desktops {"output": NAME}: the desktop grid, the one showing,
     * and each window on the output with the desktop it's on and its place
     * on that desktop. */
    nlohmann::json desktops(nlohmann::json data)
    {
        wf::output_t *output = nullptr;
        if (data.contains("output") && data["output"].is_string())
        {
            output = wf::get_core().output_layout->find_output(data["output"].get<std::string>());
        }

        if (!output)
        {
            output = wf::get_core().seat->get_active_output();
        }

        if (!output)
        {
            return wf::ipc::json_error("no output");
        }

        auto wset    = output->wset();
        auto grid    = wset->get_workspace_grid_size();
        auto current = wset->get_current_workspace();
        auto size    = output->get_screen_size();
        auto out     = wf::ipc::json_ok();
        out["output"]  = output->to_string();
        out["grid"]    = {grid.width, grid.height};
        out["current"] = {current.x, current.y};
        out["size"]    = {size.width, size.height};
        out["windows"] = nlohmann::json::array();
        // Back to front, so the row draws them in the order they overlap.
        for (auto& view : wset->get_views(wf::WSET_MAPPED_ONLY | wf::WSET_EXCLUDE_MINIMIZED |
            wf::WSET_SORT_STACKING))
        {
            if ((view->role != wf::VIEW_ROLE_TOPLEVEL) || view->parent)
            {
                continue;
            }

            auto ws = wset->get_view_main_workspace(view);
            auto g  = view->get_geometry();
            g.x -= (ws.x - current.x) * size.width;
            g.y -= (ws.y - current.y) * size.height;
            nlohmann::json w;
            w["id"]       = view->get_id();
            w["app-id"]   = view->get_app_id();
            w["title"]    = view->get_title();
            w["desktop"]  = {ws.x, ws.y};
            w["geometry"] = {g.x, g.y, g.width, g.height};
            w["focused"]  = (view == wf::get_core().seat->get_active_view());
            out["windows"].push_back(w);
        }

        std::reverse(out["windows"].begin(), out["windows"].end());
        return out;
    }

    /* strata/spaces-areas {"areas": [[x, y, w, h, desktop x, desktop y], ...]}
     * in the layout's coordinates: where Topline drew each desktop. */
    nlohmann::json set_areas(nlohmann::json data)
    {
        areas.clear();
        if (data.contains("areas") && data["areas"].is_array())
        {
            for (auto& a : data["areas"])
            {
                if (a.is_array() && (a.size() == 6))
                {
                    areas.push_back({{a[0].get<int>(), a[1].get<int>(), a[2].get<int>(), a[3].get<int>()},
                        {a[4].get<int>(), a[5].get<int>()}});
                }
            }
        }

        return wf::ipc::json_ok();
    }

  private:
    std::function<void(const std::string&)> tell;
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> methods;
    wf::shared_data::ref_ptr_t<wf::move_drag::core_drag_t> drag;
    wf::wl_idle_call idle_move;
    /* While a window is dragged the overview takes the pointer in a way
     * that sends no motion signals, so the pointer is also looked at on a
     * timer for as long as the overview is open. */
    wf::wl_timer<true> watch_pointer;
    int drag_small = -1;
    wf::output_t *open_on = nullptr;
    std::vector<area_t> areas;
    int pressed = -1;
    bool reported = false;
    bool have_pending = false;
    wf::point_t pending;
    wf::wl_idle_call idle_go;

    void watch(wf::output_t *output)
    {
        output->connect(&on_filter);
        output->connect(&on_end);
        output->connect(&on_workspace_changed);
    }

    int area_at(wf::pointf_t at)
    {
        for (size_t i = 0; i < areas.size(); i++)
        {
            if (areas[i].box & wf::point_t{(int)at.x, (int)at.y})
            {
                return (int)i;
            }
        }

        return -1;
    }

    void closed()
    {
        if (!open_on)
        {
            return;
        }

        open_on = nullptr;
        watch_pointer.disconnect();
        areas.clear();
        pressed  = -1;
        reported = false;
        tell("spaces close");
    }

    void moved()
    {
        if (!open_on)
        {
            return;
        }

        auto at  = wf::get_core().get_cursor_position();
        auto box = open_on->get_layout_geometry();
        bool near = (at.x >= box.x) && (at.x < box.x + box.width) &&
            (at.y >= box.y) && (at.y < box.y + REPORT_HEIGHT);
        if (near || reported)
        {
            tell("spaces pointer " + std::to_string((int)at.x) + " " + std::to_string((int)at.y));
        }

        reported = near;
    }

    /* Leave the overview, then go to the desktop once it has closed. */
    void go_to(wf::point_t desktop)
    {
        have_pending = true;
        pending = desktop;
        idle_go.run_once([=] ()
        {
            if (open_on)
            {
                methods->call_method("scale/toggle", nlohmann::json::object());
            }

            if (!open_on && have_pending)
            {
                switch_now();
            }
        });
    }

    void switch_now()
    {
        auto output = wf::get_core().seat->get_active_output();
        have_pending = false;
        if (!output)
        {
            return;
        }

        auto grid = output->wset()->get_workspace_grid_size();
        if ((pending.x < 0) || (pending.y < 0) || (pending.x >= grid.width) || (pending.y >= grid.height))
        {
            return;
        }

        output->wset()->request_workspace(pending);
        // As on a Mac, the window in front on that desktop becomes the
        // active one, so the menu bar shows its app.
        auto wset = output->wset();
        for (auto& view : wset->get_views(wf::WSET_MAPPED_ONLY | wf::WSET_EXCLUDE_MINIMIZED |
            wf::WSET_SORT_STACKING))
        {
            if ((view->role == wf::VIEW_ROLE_TOPLEVEL) && !view->parent &&
                (wset->get_view_main_workspace(view) == pending))
            {
                wf::get_core().default_wm->focus_raise_view(view);
                break;
            }
        }
    }

    void move_window(uint32_t id, wf::point_t desktop)
    {
        auto view = wf::toplevel_cast(wf::ipc::find_view_by_id(id));
        if (!view || !view->is_mapped() || !view->get_output())
        {
            return;
        }

        auto wset = view->get_output()->wset();
        auto grid = wset->get_workspace_grid_size();
        if ((desktop.x < 0) || (desktop.y < 0) || (desktop.x >= grid.width) || (desktop.y >= grid.height) ||
            (wset->get_view_main_workspace(view) == desktop))
        {
            return;
        }

        wset->move_to_workspace(view, desktop);
        if (open_on)
        {
            tell("spaces changed");
        }
    }

    wf::signal::connection_t<scale_filter_signal> on_filter = [=] (scale_filter_signal*)
    {
        auto output = wf::get_core().seat->get_active_output();
        if (!open_on && output)
        {
            open_on = output;
            tell("spaces open " + output->to_string());
            moved();
            watch_pointer.set_timeout(40, [=] ()
            {
                if (drag->view)
                {
                    moved();
                    /* Near the row the window being dragged shrinks, so the
                     * desktops stay in sight, as on a Mac. */
                    if (!drag->is_view_held_in_place())
                    {
                        int small = reported ? 1 : 0;
                        if (small != drag_small)
                        {
                            drag_small = small;
                            // The drag divides the size by this.
                            drag->set_scale(small ? 4.0 : 1.0);
                        }
                    }
                } else
                {
                    drag_small = -1;
                }

                return open_on != nullptr;
            });
        }
    };

    /* A window dragged out of the overview and let go over one of the
     * desktops: the overview puts it back in its place, then it moves to
     * that desktop and the overview lays out the ones left. */
    wf::signal::connection_t<wf::move_drag::drag_done_signal> on_drag_done =
        [=] (wf::move_drag::drag_done_signal *ev)
    {
        if (!open_on || !ev->main_view)
        {
            return;
        }

        int at = area_at({(double)ev->grab_position.x, (double)ev->grab_position.y});
        if (at < 0)
        {
            return;
        }

        auto id = ev->main_view->get_id();
        auto desktop = areas[at].desktop;
        idle_move.run_once([=] () { move_window(id, desktop); });
    };

    wf::signal::connection_t<scale_end_signal> on_end = [=] (scale_end_signal*)
    {
        closed();
        if (have_pending)
        {
            switch_now();
        }
    };

    wf::signal::connection_t<wf::workspace_changed_signal> on_workspace_changed =
        [=] (wf::workspace_changed_signal*)
    {
        if (open_on)
        {
            tell("spaces changed");
        }
    };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_button_event>> on_button =
        [=] (wf::input_event_signal<wlr_pointer_button_event> *ev)
    {
        if (!open_on || areas.empty())
        {
            return;
        }

        int at = area_at(wf::get_core().get_cursor_position());
        if (ev->event->state == WLR_BUTTON_PRESSED)
        {
            if (at >= 0)
            {
                pressed  = at;
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
            }

            return;
        }

        if (pressed >= 0)
        {
            ev->mode = wf::input_event_processing_mode_t::IGNORE;
            if ((at == pressed) && (ev->event->button == BTN_LEFT))
            {
                go_to(areas[at].desktop);
            }

            pressed = -1;
        }
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

    wf::signal::connection_t<wf::output_added_signal> on_output_added =
        [=] (wf::output_added_signal *ev)
    {
        watch(ev->output);
    };

    wf::signal::connection_t<wf::output_removed_signal> on_output_removed =
        [=] (wf::output_removed_signal *ev)
    {
        if (ev->output == open_on)
        {
            closed();
        }
    };
};
}
