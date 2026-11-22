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
// With the row opened out, a "+" at its right end adds a desktop and the
// round button on a desktop's corner closes it, its windows going to the
// first desktop (a window dragged onto the "+" goes to a new desktop of its
// own). The count is the core/vwidth option, set here at once; Topline
// saves it in wayfire.ini ("spaces desktops N").
// An app can be assigned to a desktop from its Dock menu (Options > Assign
// To), as on a Mac: to all desktops (its windows are sticky), or to one
// (its windows open there, and you're taken there). strata/assign sets it,
// strata/assignments lists them; they are kept in
// ~/.config/freemac/desktop-assignments, one "all APP-ID" or "N APP-ID" a line.
// Original freemac code.
#pragma once

#include <cstdlib>
#include <fstream>
#include <functional>
#include <map>
#include <sstream>
#include <string>
#include <sys/stat.h>
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
/* As many desktops as a Mac allows. */
static const int MOST_DESKTOPS = 16;
/* An app assigned to all desktops. */
static const int ALL_DESKTOPS = -1;

/* What a click in one of Topline's areas does. Topline sends an area's
 * desktop as (-1, 0) for the "+" and (-2, N) for the button that closes
 * desktop N. */
enum area_kind_t
{
    AREA_DESKTOP,
    AREA_ADD,
    AREA_CLOSE,
};

struct area_t
{
    wf::geometry_t box;
    wf::point_t desktop;
    area_kind_t kind = AREA_DESKTOP;
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
        wf::get_core().connect(&on_mapped);
        drag->connect(&on_drag_done);
        load_assignments();
    }

    /* strata/assignments: {"apps": {APP-ID: "all" or a desktop index}}. */
    nlohmann::json assignments(nlohmann::json)
    {
        auto out = wf::ipc::json_ok();
        out["apps"] = nlohmann::json::object();
        for (auto& [app, to] : assigned)
        {
            if (to == ALL_DESKTOPS)
            {
                out["apps"][app] = "all";
            } else
            {
                out["apps"][app] = to;
            }
        }

        return out;
    }

    /* strata/assign {"app-id": ID, "to": "all", "none" or a desktop index}:
     * kept, and the app's open windows follow at once. */
    nlohmann::json assign(nlohmann::json data)
    {
        if (!data.contains("app-id") || !data["app-id"].is_string() || !data.contains("to"))
        {
            return wf::ipc::json_error("app-id and to are needed");
        }

        std::string app = data["app-id"];
        auto& to = data["to"];
        if (app.empty() || (app.find('\n') != std::string::npos))
        {
            return wf::ipc::json_error("bad app-id");
        }

        if (to.is_string() && (to.get<std::string>() == "none"))
        {
            assigned.erase(app);
        } else if (to.is_string() && (to.get<std::string>() == "all"))
        {
            assigned[app] = ALL_DESKTOPS;
        } else if (to.is_number_integer() && (to.get<int>() >= 0) && (to.get<int>() < MOST_DESKTOPS))
        {
            assigned[app] = to.get<int>();
        } else
        {
            return wf::ipc::json_error("to must be all, none or a desktop");
        }

        save_assignments();
        for (auto output : wf::get_core().output_layout->get_outputs())
        {
            auto wset = output->wset();
            for (auto& view : wset->get_views(wf::WSET_MAPPED_ONLY))
            {
                if (!view->parent && (view->get_app_id() == app))
                {
                    follow(view, false);
                }
            }
        }

        return wf::ipc::json_ok();
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
                    area_t area;
                    area.box = {a[0].get<int>(), a[1].get<int>(), a[2].get<int>(), a[3].get<int>()};
                    area.desktop = {a[4].get<int>(), a[5].get<int>()};
                    if (area.desktop.x == -1)
                    {
                        area.kind = AREA_ADD;
                    } else if (area.desktop.x == -2)
                    {
                        area.kind = AREA_CLOSE;
                    }

                    areas.push_back(area);
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
    wf::wl_idle_call idle_change;
    std::map<std::string, int> assigned;
    /* Windows just opened by an app assigned to one desktop, moved there
     * once the other plugins have placed them. */
    std::vector<uint32_t> to_follow;
    wf::wl_idle_call idle_follow;

    static std::string assignments_path()
    {
        const char *config = std::getenv("XDG_CONFIG_HOME");
        std::string base;
        if (config && *config)
        {
            base = config;
        } else
        {
            const char *home = std::getenv("HOME");
            base = std::string(home ? home : "/tmp") + "/.config";
        }

        return base + "/freemac/desktop-assignments";
    }

    void load_assignments()
    {
        assigned.clear();
        std::ifstream in(assignments_path());
        std::string line;
        while (std::getline(in, line))
        {
            std::istringstream fields(line);
            std::string to, app;
            if (!(fields >> to) || !std::getline(fields >> std::ws, app) || app.empty())
            {
                continue;
            }

            if (to == "all")
            {
                assigned[app] = ALL_DESKTOPS;
            } else
            {
                char *end = nullptr;
                long n = std::strtol(to.c_str(), &end, 10);
                if (end && !*end && (n >= 0) && (n < MOST_DESKTOPS))
                {
                    assigned[app] = (int)n;
                }
            }
        }
    }

    void save_assignments()
    {
        auto path = assignments_path();
        mkdir(path.substr(0, path.rfind('/')).c_str(), 0755);
        std::ofstream out(path, std::ios::trunc);
        for (auto& [app, to] : assigned)
        {
            out << ((to == ALL_DESKTOPS) ? std::string("all") : std::to_string(to)) << " " << app << "\n";
        }
    }

    /* Put a window where its app is assigned; a window just opened takes
     * you to its desktop too, as on a Mac. */
    void follow(wayfire_toplevel_view view, bool opened)
    {
        auto it = assigned.find(view->get_app_id());
        if (it == assigned.end())
        {
            if (view->sticky && !opened)
            {
                view->set_sticky(false);
            }

            return;
        }

        if (it->second == ALL_DESKTOPS)
        {
            view->set_sticky(true);
            return;
        }

        if (!view->get_output())
        {
            return;
        }

        auto wset = view->get_output()->wset();
        auto grid = wset->get_workspace_grid_size();
        wf::point_t desktop = {it->second, 0};
        if ((grid.height != 1) || (desktop.x >= grid.width))
        {
            return;
        }

        if (view->sticky)
        {
            view->set_sticky(false);
        }

        if (wset->get_view_main_workspace(view) != desktop)
        {
            wset->move_to_workspace(view, desktop);
        }

        if (opened && (wset->get_current_workspace() != desktop))
        {
            wset->request_workspace(desktop);
        }
    }

    /* Desktop `gone` closed: assignments after it move along by one, and
     * those to it are dropped. */
    void desktop_closed(int gone)
    {
        bool changed = false;
        for (auto it = assigned.begin(); it != assigned.end();)
        {
            if (it->second == gone)
            {
                it = assigned.erase(it);
                changed = true;
                continue;
            }

            if (it->second > gone)
            {
                it->second--;
                changed = true;
            }

            ++it;
        }

        if (changed)
        {
            save_assignments();
        }
    }

    wf::signal::connection_t<wf::view_mapped_signal> on_mapped = [=] (wf::view_mapped_signal *ev)
    {
        auto view = wf::toplevel_cast(ev->view);
        if (!view || view->parent || (view->role != wf::VIEW_ROLE_TOPLEVEL) ||
            !assigned.count(view->get_app_id()))
        {
            return;
        }

        to_follow.push_back(view->get_id());
        idle_follow.run_once([=] ()
        {
            auto ids = std::move(to_follow);
            to_follow.clear();
            for (auto id : ids)
            {
                auto v = wf::toplevel_cast(wf::ipc::find_view_by_id(id));
                if (v && v->is_mapped())
                {
                    follow(v, true);
                }
            }
        });
    };
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

    wf::workspace_set_t *row_wset()
    {
        auto output = open_on ? open_on : wf::get_core().seat->get_active_output();
        return output ? output->wset().get() : nullptr;
    }

    /* Desktops are added and closed along a single row, as on a Mac. */
    void set_count(int count)
    {
        auto option = wf::get_core().config.get_option("core/vwidth");
        if (option)
        {
            option->set_value_str(std::to_string(count));
        }

        tell("spaces desktops " + std::to_string(count));
        if (open_on)
        {
            tell("spaces changed");
        }
    }

    /* A new desktop at the end of the row; true if there's room for one. */
    bool add_desktop()
    {
        auto wset = row_wset();
        if (!wset)
        {
            return false;
        }

        auto grid = wset->get_workspace_grid_size();
        if ((grid.height != 1) || (grid.width >= MOST_DESKTOPS))
        {
            return false;
        }

        set_count(grid.width + 1);
        return wset->get_workspace_grid_size().width == grid.width + 1;
    }

    /* Close desktop `gone`: its windows go to the first desktop and the
     * ones after it move along by one. */
    void close_desktop(int gone)
    {
        auto wset = row_wset();
        if (!wset)
        {
            return;
        }

        auto grid = wset->get_workspace_grid_size();
        if ((grid.height != 1) || (grid.width <= 1) || (gone < 0) || (gone >= grid.width))
        {
            return;
        }

        auto to = [=] (int x) { return (x < gone) ? x : ((x == gone) ? 0 : x - 1); };
        auto current = wset->get_current_workspace();
        std::vector<wayfire_toplevel_view> here;
        std::vector<std::pair<wayfire_toplevel_view, int>> moves;
        for (auto& view : wset->get_views(wf::WSET_MAPPED_ONLY))
        {
            if (view->sticky)
            {
                continue;
            }

            int x = wset->get_view_main_workspace(view).x;
            if ((x == current.x) && (to(x) != x))
            {
                // A dialog goes along with its window.
                if (!view->parent)
                {
                    here.push_back(view);
                }
            } else if (to(x) != x)
            {
                moves.push_back({view, to(x)});
            }
        }

        /* The desktop showing moves first and takes its windows with it, so
         * the overview never finds itself on an empty desktop and closes. */
        if (to(current.x) != current.x)
        {
            wset->set_workspace({to(current.x), 0}, here);
        }

        for (auto& [view, x] : moves)
        {
            wset->move_to_workspace(view, {x, 0});
        }

        set_count(grid.width - 1);
        desktop_closed(gone);
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
        auto area = areas[at];
        if (area.kind == AREA_CLOSE)
        {
            return;
        }

        idle_move.run_once([=] ()
        {
            if (area.kind == AREA_ADD)
            {
                // Onto the "+": a new desktop with this window on it.
                if (add_desktop())
                {
                    auto wset = row_wset();
                    move_window(id, {wset->get_workspace_grid_size().width - 1, 0});
                }
            } else
            {
                move_window(id, area.desktop);
            }
        });
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
                auto area = areas[at];
                if (area.kind == AREA_ADD)
                {
                    idle_change.run_once([=] () { add_desktop(); });
                } else if (area.kind == AREA_CLOSE)
                {
                    idle_change.run_once([=] () { close_desktop(area.desktop.y); });
                } else
                {
                    go_to(area.desktop);
                }
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
