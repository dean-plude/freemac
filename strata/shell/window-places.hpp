// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Window places: when an app's window closes, Strata notes its size and
 * place; when the app opens a window again (and has no other window open),
 * that window comes back the same size, in the same place. A second window
 * of an already open app is placed as usual. Original freemac code.
 *
 * The notes live in $XDG_STATE_HOME/freemac/window-places (one line per app:
 * "x y width height app-id": the window's content, without its title bar,
 * measured from the top left of the screen's free area, below Topline).
 */
#pragma once

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <vector>

#include <wayfire/core.hpp>
#include <wayfire/toplevel.hpp>
#include <wayfire/util.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/output.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/view.hpp>
#include <wayfire/workarea.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>

class strata_window_places
{
    std::map<std::string, wf::geometry_t> places;
    bool loaded = false;

    /* Windows just put back, and the content each should have. Some apps
     * answer the first size they're given late, or change it again as the
     * title bar arrives, so it's checked every 100 ms for two seconds and
     * asked for again. An app that keeps refusing it (one that needs more
     * room) keeps its own size, with the whole window kept on the screen. */
    struct settling
    {
        uint32_t id;
        wf::geometry_t content;
        int checks;
        int asked;
    };
    std::vector<settling> settle;
    static constexpr int CHECKS = 20;
    static constexpr int ASK_AGAIN = 4;
    wf::wl_timer<true> settle_timer;

    bool check_settling()
    {
        for (auto it = settle.begin(); it != settle.end();)
        {
            auto view = wf::toplevel_cast(wf::ipc::find_view_by_id(it->id));
            if (!view || !view->is_mapped() || (--it->checks < 0))
            {
                it = settle.erase(it);
                continue;
            }

            auto& now = view->toplevel()->current();
            at_least_min_size(view, it->content);
            auto want = wf::expand_geometry_by_margins(it->content, now.margins);
            if ((view->get_pending_geometry() != now.geometry) || (now.geometry == want))
            {
                ++it; // the app hasn't answered yet, or has the noted size
                continue;
            }

            if (it->asked < ASK_AGAIN)
            {
                ++it->asked;
                view->set_geometry(want);
            } else
            {
                auto area = view->get_output()->workarea->get_workarea();
                auto g    = now.geometry;
                g.x = std::clamp(g.x, area.x, std::max(area.x, area.x + area.width - g.width));
                g.y = std::clamp(g.y, area.y, std::max(area.y, area.y + area.height - g.height));
                if (g != now.geometry)
                {
                    view->set_geometry(g);
                }
            }

            ++it;
        }

        return !settle.empty();
    }

    static std::string folder()
    {
        const char *state = std::getenv("XDG_STATE_HOME");
        std::string base;
        if (state && *state)
        {
            base = state;
        } else
        {
            const char *home = std::getenv("HOME");
            base = std::string(home ? home : "/tmp") + "/.local/state";
        }

        return base + "/freemac";
    }

    void load()
    {
        if (loaded)
        {
            return;
        }

        loaded = true;
        std::ifstream in(folder() + "/window-places");
        std::string line;
        while (std::getline(in, line))
        {
            std::istringstream fields(line);
            wf::geometry_t g;
            std::string app_id;
            if ((fields >> g.x >> g.y >> g.width >> g.height) && std::getline(fields >> std::ws, app_id) &&
                !app_id.empty() && (g.width > 0) && (g.height > 0))
            {
                places[app_id] = g;
            }
        }
    }

    void save()
    {
        std::string dir = folder();
        std::string parent = dir.substr(0, dir.rfind('/'));
        mkdir(parent.c_str(), 0755);
        mkdir(dir.c_str(), 0755);
        std::string path = dir + "/window-places";
        std::string tmp  = path + ".new";
        {
            std::ofstream out(tmp, std::ios::trunc);
            for (auto& [app_id, g] : places)
            {
                out << g.x << " " << g.y << " " << g.width << " " << g.height << " " << app_id << "\n";
            }

            if (!out)
            {
                return;
            }
        }

        std::rename(tmp.c_str(), path.c_str());
    }

    /* Only ordinary app windows: not dialogs, and not windows that are
     * filling the screen or tiled to one side. */
    static wayfire_toplevel_view ordinary(wayfire_view view)
    {
        auto toplevel = wf::toplevel_cast(view);
        if (!toplevel || toplevel->parent || !toplevel->get_output() ||
            (toplevel->role != wf::VIEW_ROLE_TOPLEVEL) || toplevel->get_app_id().empty())
        {
            return nullptr;
        }

        return toplevel;
    }

    /* No smaller than the app says its window can be. */
    static void at_least_min_size(wayfire_toplevel_view view, wf::geometry_t& g)
    {
        auto surface = view->get_wlr_surface();
        auto xdg     = surface ? wlr_xdg_surface_try_from_wlr_surface(surface) : nullptr;
        if (xdg && (xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) && xdg->toplevel)
        {
            g.width  = std::max(g.width, xdg->toplevel->current.min_width);
            g.height = std::max(g.height, xdg->toplevel->current.min_height);
        }
    }

    static bool others_open(wayfire_toplevel_view view)
    {
        for (auto& other : wf::get_core().get_all_views())
        {
            auto toplevel = wf::toplevel_cast(other);
            if (toplevel && (toplevel != view) && toplevel->is_mapped() && !toplevel->parent &&
                (toplevel->get_app_id() == view->get_app_id()))
            {
                return true;
            }
        }

        return false;
    }

  public:
    /* Before the place plugin picks a spot: put the window back where the
     * app's last one was. */
    wf::signal::connection_t<wf::view_mapped_signal> on_mapped = [=] (wf::view_mapped_signal *ev)
    {
        auto view = ordinary(ev->view);
        if (!view || ev->is_positioned || view->pending_fullscreen() || view->pending_tiled_edges())
        {
            return;
        }

        load();
        auto it = places.find(view->get_app_id());
        if ((it == places.end()) || others_open(view))
        {
            return;
        }

        auto area = view->get_output()->workarea->get_workarea();
        wf::geometry_t g = it->second;
        at_least_min_size(view, g);
        g.width  = std::min(g.width, area.width);
        g.height = std::min(g.height, area.height);
        g.x = area.x + std::clamp(g.x, 0, area.width - g.width);
        g.y = area.y + std::clamp(g.y, 0, area.height - g.height);
        /* Notes are of the window's content. A title bar Strata adds as the
         * window maps grows the frame around it, back to where it was. */
        view->set_geometry(wf::expand_geometry_by_margins(g, view->toplevel()->pending().margins));
        ev->is_positioned = true;
        settle.push_back({view->get_id(), g, CHECKS, 0});
        if (!settle_timer.is_connected())
        {
            settle_timer.set_timeout(100, [=] () { return check_settling(); });
        }
    };

    /* As a window closes: note where it was. */
    wf::signal::connection_t<wf::view_pre_unmap_signal> on_closing = [=] (wf::view_pre_unmap_signal *ev)
    {
        auto view = ordinary(ev->view);
        if (!view || view->toplevel()->current().fullscreen || view->toplevel()->current().tiled_edges || view->minimized)
        {
            return;
        }

        load();
        auto area = view->get_output()->workarea->get_workarea();
        auto& now = view->toplevel()->current();
        wf::geometry_t g = wf::shrink_geometry_by_margins(now.geometry, now.margins);
        g.x -= area.x;
        g.y -= area.y;
        if ((g.width <= 0) || (g.height <= 0))
        {
            return;
        }

        auto it = places.find(view->get_app_id());
        if ((it != places.end()) && (it->second == g))
        {
            return;
        }

        places[view->get_app_id()] = g;
        save();
    };

    wf::signal::connection_t<wf::output_added_signal> on_output_added = [=] (wf::output_added_signal *ev)
    {
        ev->output->connect(&on_mapped);
    };

    /* Connect before the place plugin does (strata-shell comes earlier in
     * the plugin list), so a remembered place wins over a new one. */
    void init()
    {
        for (auto output : wf::get_core().output_layout->get_outputs())
        {
            output->connect(&on_mapped);
        }

        wf::get_core().output_layout->connect(&on_output_added);
        wf::get_core().connect(&on_closing);
    }
};
