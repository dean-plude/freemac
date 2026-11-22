// SPDX-License-Identifier: GPL-3.0-or-later
// Coming to the front, and asking for attention (1.116), as on a Mac.
//
// Apps ask to bring a window forward through xdg-activation: a browser
// asked to open a link, an app opened again from the Dock, Seek or Drawer,
// a notification clicked. Strata grants the ask when it was made from
// something you did (the token carries the seat and an input serial, as
// Wayfire's own xdg-activation plugin requires), and the window comes
// forward, on its own desktop. An app that asks with nothing you did behind
// it doesn't take the keyboard from you: its icon bounces in the Dock until
// you go to it, as a Mac's does. X11 apps that set the urgency hint bounce
// the same way.
//
// Strata tells the Dock over its socket: "attention APP-ID on|off".
// Original freemac code.
#pragma once

#include <set>
#include <string>
#include <cstring>
#include <cstdlib>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <wayfire/core.hpp>
#include <wayfire/debug.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/util.hpp>
#include <wayfire/view.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <nlohmann/json.hpp>

namespace strata_attention
{
inline void tell_dock(const std::string& line)
{
    const char *dir = std::getenv("XDG_RUNTIME_DIR");
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::string path = std::string(dir ? dir : "") + "/freemac-pier.sock";
    if (!dir || (path.size() >= sizeof(address.sun_path)))
    {
        return;
    }

    std::strcpy(address.sun_path, path.c_str());
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0)
    {
        return;
    }

    if (connect(fd, (sockaddr*)&address, sizeof(address)) == 0)
    {
        std::string text = line + "\n";
        send(fd, text.data(), text.size(), MSG_NOSIGNAL);
    }

    close(fd);
}

class attention_t
{
    wlr_xdg_activation_v1 *activation = nullptr;
    wf::wl_listener_wrapper on_request;
    std::set<std::string> asking;   // app ids whose icons bounce

    static wayfire_toplevel_view root_of(wayfire_view view)
    {
        auto toplevel = wf::toplevel_cast(view);
        return toplevel ? wf::find_topmost_parent(toplevel) : nullptr;
    }

    static wayfire_toplevel_view active()
    {
        return root_of(wf::get_core().seat->get_active_view());
    }

    /* Whether an activation token was made from an input event of yours. */
    static bool from_you(wlr_xdg_activation_token_v1 *token)
    {
        return token && token->seat;
    }

    void set(const std::string& app_id, bool on)
    {
        if (app_id.empty())
        {
            return;
        }

        bool changed = on ? asking.insert(app_id).second : (asking.erase(app_id) > 0);
        if (changed)
        {
            tell_dock("attention " + app_id + (on ? " on" : " off"));
        }
    }

    void ask(wayfire_toplevel_view view)
    {
        auto now = active();
        if (now && (now->get_app_id() == view->get_app_id()))
        {
            return;   // already the app in front
        }

        set(view->get_app_id(), true);
    }

    void request(wlr_xdg_activation_v1_request_activate_event *ev)
    {
        if (!ev->surface)
        {
            return;
        }

        auto view = wf::toplevel_cast(wf::wl_surface_to_wayfire_view(ev->surface->resource));
        if (!view || !view->is_mapped())
        {
            return;
        }

        view = wf::find_topmost_parent(view);
        LOGI("strata: ", view->get_app_id(), " asks to come forward",
            from_you(ev->token) ? "" : " with nothing you did behind it");
        if (from_you(ev->token))
        {
            set(view->get_app_id(), false);
            wf::get_core().default_wm->focus_request(view);
        } else
        {
            ask(view);
        }
    }

    wf::signal::connection_t<wf::keyboard_focus_changed_signal> on_focus =
        [=] (wf::keyboard_focus_changed_signal *ev)
    {
        if (auto view = root_of(wf::node_to_view(ev->new_focus)))
        {
            set(view->get_app_id(), false);
        }
    };

    wf::signal::connection_t<wf::view_hints_changed_signal> on_hints =
        [=] (wf::view_hints_changed_signal *ev)
    {
        auto view = root_of(ev->view);
        if (!view)
        {
            return;
        }

        if (ev->demands_attention)
        {
            ask(view);
        } else
        {
            set(view->get_app_id(), false);
        }
    };

    wf::signal::connection_t<wf::view_unmapped_signal> on_unmapped =
        [=] (wf::view_unmapped_signal *ev)
    {
        auto view = wf::toplevel_cast(ev->view);
        if (!view || view->parent)
        {
            return;
        }

        // The app's last window went: nothing left to go to.
        std::string app_id = view->get_app_id();
        for (auto& other : wf::get_core().get_all_views())
        {
            auto toplevel = wf::toplevel_cast(other);
            if (toplevel && (toplevel != view) && toplevel->is_mapped() &&
                (toplevel->get_app_id() == app_id))
            {
                return;
            }
        }

        set(app_id, false);
    };

  public:
    void init()
    {
        activation = wlr_xdg_activation_v1_create(wf::get_core().display);
        if (!activation)
        {
            return;
        }

        on_request.set_callback([=] (void *data)
        {
            request(static_cast<wlr_xdg_activation_v1_request_activate_event*>(data));
        });
        on_request.connect(&activation->events.request_activate);
        wf::get_core().connect(&on_focus);
        wf::get_core().connect(&on_hints);
        wf::get_core().connect(&on_unmapped);
    }

    /* strata/attention: the apps asking now, for a Dock that starts later. */
    nlohmann::json list(nlohmann::json)
    {
        nlohmann::json out = nlohmann::json::object();
        out["result"] = "ok";
        out["apps"]   = nlohmann::json::array();
        for (auto& app_id : asking)
        {
            out["apps"].push_back(app_id);
        }

        return out;
    }
};
}
