// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * The Command key. On freemac the Super key (the one next to the space bar,
 * or the Windows key, as Dials > Keyboard sets) is Command:
 *
 *  - Super with a letter does in an app what Ctrl with that letter does on
 *    other PCs (copy, paste, undo, save, find, new tab...). Apps are told
 *    Ctrl is held while Super is; in a terminal, Ctrl+Shift, so Super+C
 *    copies there too instead of stopping the running program.
 *  - Strata's own Super shortcuts (Super+Q, Super+H, Super+Tab, Super+Space...)
 *    still come first: those keys never reach the app.
 *  - Text keys: Super+Left/Right go to the start or end of the line,
 *    Super+Up/Down to the start or end of the text, and Alt (the key marked
 *    Option on other keyboards) with Left/Right/Backspace/Delete moves or
 *    deletes a word at a time; Shift still selects.
 *
 * And the app shortcuts that belong to the system:
 *   Super+Q quit the app (every window), Super+H hide it, Super+Alt+H hide
 *   the others, Super+` (Shift: back) step through the app's own windows.
 *
 * Original freemac code.
 */
#pragma once

#include <algorithm>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include <linux/input-event-codes.h>
#include <wayfire/bindings-repository.hpp>
#include <wayfire/core.hpp>
#include <wayfire/input-device.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/util.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>

class strata_command_key
{
    wf::option_wrapper_t<bool> enabled{"strata-shell/command_key"};
    wf::option_wrapper_t<std::string> terminals{"strata-shell/command_key_terminals"};
    wf::option_wrapper_t<wf::activatorbinding_t> quit_app{"strata-shell/quit_app"};
    wf::option_wrapper_t<wf::activatorbinding_t> hide_app{"strata-shell/hide_app"};
    wf::option_wrapper_t<wf::activatorbinding_t> hide_others{"strata-shell/hide_others"};
    wf::option_wrapper_t<wf::activatorbinding_t> next_window{"strata-shell/next_app_window"};
    wf::option_wrapper_t<wf::activatorbinding_t> prev_window{"strata-shell/prev_app_window"};

    /* A key Strata stands in for while it's held (Super+Left is Home): what
     * the app is sent instead, and the modifiers it sees meanwhile. */
    struct stand_in
    {
        uint32_t key;
        uint32_t drop;
        uint32_t add;
    };
    std::map<uint32_t, stand_in> held;
    std::map<wlr_keyboard*, std::unique_ptr<wf::wl_listener_wrapper>> listening;

    static uint32_t mask(wlr_keyboard *kbd, const char *name)
    {
        if (!kbd->keymap)
        {
            return 0;
        }

        auto index = xkb_keymap_mod_get_index(kbd->keymap, name);
        return (index == XKB_MOD_INVALID) ? 0 : (1u << index);
    }

    /* Dials, while it waits for a new shortcut, sees the keys as they are. */
    std::string raw_app;

    bool focused_is(const std::string& app_id)
    {
        auto view = wf::get_core().seat->get_active_view();
        return view && !app_id.empty() && (view->get_app_id() == app_id);
    }

    bool terminal_focused()
    {
        auto view = wf::get_core().seat->get_active_view();
        if (!view)
        {
            return false;
        }

        std::istringstream names{std::string(terminals)};
        std::string name;
        while (names >> name)
        {
            if (name == view->get_app_id())
            {
                return true;
            }
        }

        return false;
    }

    /* What the focused app is told is held, from what really is. */
    wlr_keyboard_modifiers for_apps(wlr_keyboard *kbd)
    {
        wlr_keyboard_modifiers mods = kbd->modifiers;
        if (focused_is(raw_app))
        {
            return mods;
        }

        uint32_t logo = mask(kbd, XKB_MOD_NAME_LOGO);
        uint32_t ctrl = mask(kbd, XKB_MOD_NAME_CTRL);
        if (!held.empty())
        {
            auto& in = held.rbegin()->second;
            mods.depressed = (mods.depressed & ~in.drop) | in.add;
        } else if (logo && ctrl && (mods.depressed & logo))
        {
            mods.depressed = (mods.depressed & ~logo) | ctrl;
            if (terminal_focused())
            {
                mods.depressed |= mask(kbd, XKB_MOD_NAME_SHIFT);
            }
        }

        return mods;
    }

    void tell_app(wlr_keyboard *kbd)
    {
        auto seat = wf::get_core().get_current_seat();
        if (enabled && kbd && (wlr_seat_get_keyboard(seat) == kbd))
        {
            auto mods = for_apps(kbd);
            wlr_seat_keyboard_send_modifiers(seat, &mods);
        }
    }

    /* Core has just told the app the real modifiers; correct them. */
    void listen(wlr_keyboard *kbd)
    {
        if (listening.count(kbd))
        {
            return;
        }

        auto listener = std::make_unique<wf::wl_listener_wrapper>();
        listener->set_callback([=] (void*) { tell_app(kbd); });
        listener->connect(&kbd->events.modifiers);
        listening[kbd] = std::move(listener);
    }

    void listen_all()
    {
        for (auto& device : wf::get_core().get_input_devices())
        {
            auto handle = device->get_wlr_handle();
            if (handle->type == WLR_INPUT_DEVICE_KEYBOARD)
            {
                listen(wlr_keyboard_from_input_device(handle));
            }
        }
    }

    wf::signal::connection_t<wf::input_device_added_signal> on_device_added =
        [=] (wf::input_device_added_signal *ev)
    {
        auto handle = ev->device->get_wlr_handle();
        if (handle->type == WLR_INPUT_DEVICE_KEYBOARD)
        {
            listen(wlr_keyboard_from_input_device(handle));
        }
    };

    wf::signal::connection_t<wf::input_device_removed_signal> on_device_removed =
        [=] (wf::input_device_removed_signal *ev)
    {
        auto handle = ev->device->get_wlr_handle();
        if (handle->type == WLR_INPUT_DEVICE_KEYBOARD)
        {
            listening.erase(wlr_keyboard_from_input_device(handle));
        }
    };

    /* A newly focused app is told the real modifiers too. */
    wf::signal::connection_t<wf::keyboard_focus_changed_signal> on_focus =
        [=] (wf::keyboard_focus_changed_signal*)
    {
        tell_app(wlr_seat_get_keyboard(wf::get_core().get_current_seat()));
    };

    bool stand_in_for(wlr_keyboard *kbd, uint32_t key, stand_in& out)
    {
        uint32_t mods  = kbd->modifiers.depressed;
        uint32_t logo  = mask(kbd, XKB_MOD_NAME_LOGO);
        uint32_t ctrl  = mask(kbd, XKB_MOD_NAME_CTRL);
        uint32_t alt   = mask(kbd, XKB_MOD_NAME_ALT);
        if (!logo || !ctrl || !alt || (mods & ctrl))
        {
            return false;
        }

        if ((mods & logo) && !(mods & alt))
        {
            switch (key)
            {
              case KEY_LEFT:
                out = {KEY_HOME, logo, 0};
                return true;

              case KEY_RIGHT:
                out = {KEY_END, logo, 0};
                return true;

              case KEY_UP:
                out = {KEY_HOME, logo, ctrl};
                return true;

              case KEY_DOWN:
                out = {KEY_END, logo, ctrl};
                return true;
            }
        } else if ((mods & alt) && !(mods & logo))
        {
            switch (key)
            {
              case KEY_LEFT:
              case KEY_RIGHT:
              case KEY_BACKSPACE:
              case KEY_DELETE:
                out = {key, alt, ctrl};
                return true;
            }
        }

        return false;
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_keyboard_key_event>> on_key =
        [=] (wf::input_event_signal<wlr_keyboard_key_event> *ev)
    {
        auto seat = wf::get_core().get_current_seat();
        auto kbd  = wlr_seat_get_keyboard(seat);
        if (!kbd || (ev->mode != wf::input_event_processing_mode_t::FULL))
        {
            return;
        }

        uint32_t key = ev->event->keycode;
        if (ev->event->state == WL_KEYBOARD_KEY_STATE_RELEASED)
        {
            auto it = held.find(key);
            if (it != held.end())
            {
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
                uint32_t sent = it->second.key;
                held.erase(it);
                wlr_seat_keyboard_notify_key(seat, ev->event->time_msec, sent, WL_KEYBOARD_KEY_STATE_RELEASED);
                tell_app(kbd);
            }

            return;
        }

        stand_in in;
        if (!enabled || held.count(key) || !seat->keyboard_state.focused_surface || focused_is(raw_app) ||
            !stand_in_for(kbd, key, in))
        {
            return;
        }

        ev->mode  = wf::input_event_processing_mode_t::IGNORE;
        held[key] = in;
        tell_app(kbd);
        wlr_seat_keyboard_notify_key(seat, ev->event->time_msec, in.key, WL_KEYBOARD_KEY_STATE_PRESSED);
    };

    /* -- the system's app shortcuts */
    static wayfire_toplevel_view focused_app_window()
    {
        auto view = wf::toplevel_cast(wf::get_core().seat->get_active_view());
        if (!view || (view->role != wf::VIEW_ROLE_TOPLEVEL) || view->get_app_id().empty())
        {
            return nullptr;
        }

        return view;
    }

    static std::vector<wayfire_toplevel_view> app_windows(const std::string& app_id, bool same)
    {
        std::vector<wayfire_toplevel_view> found;
        for (auto& view : wf::get_core().get_all_views())
        {
            auto toplevel = wf::toplevel_cast(view);
            if (toplevel && toplevel->is_mapped() && (toplevel->role == wf::VIEW_ROLE_TOPLEVEL) &&
                ((toplevel->get_app_id() == app_id) == same))
            {
                found.push_back(toplevel);
            }
        }

        return found;
    }

    wf::activator_callback on_quit = [=] (const wf::activator_data_t&)
    {
        auto view = focused_app_window();
        if (!view)
        {
            return false;
        }

        for (auto& window : app_windows(view->get_app_id(), true))
        {
            if (!window->parent)
            {
                window->close();
            }
        }

        return true;
    };

    wf::activator_callback on_hide = [=] (const wf::activator_data_t&)
    {
        auto view = focused_app_window();
        if (!view)
        {
            return false;
        }

        for (auto& window : app_windows(view->get_app_id(), true))
        {
            if (!window->parent && !window->minimized)
            {
                wf::get_core().default_wm->minimize_request(window, true);
            }
        }

        return true;
    };

    wf::activator_callback on_hide_others = [=] (const wf::activator_data_t&)
    {
        auto view = focused_app_window();
        if (!view)
        {
            return false;
        }

        for (auto& window : app_windows(view->get_app_id(), false))
        {
            if (!window->parent && !window->minimized && !window->get_app_id().empty())
            {
                wf::get_core().default_wm->minimize_request(window, true);
            }
        }

        return true;
    };

    bool step_window(int direction)
    {
        auto view = focused_app_window();
        if (!view)
        {
            return false;
        }

        if (view->parent)
        {
            view = wf::find_topmost_parent(view);
        }

        std::vector<wayfire_toplevel_view> windows;
        for (auto& window : app_windows(view->get_app_id(), true))
        {
            if (!window->parent && (!window->minimized || (window == view)))
            {
                windows.push_back(window);
            }
        }

        if (windows.size() < 2)
        {
            return true;
        }

        /* Oldest first, so stepping goes round every window in turn. */
        std::sort(windows.begin(), windows.end(), [] (auto& a, auto& b) { return a->get_id() < b->get_id(); });
        auto it = std::find(windows.begin(), windows.end(), view);
        int index = (it == windows.end()) ? 0 : (it - windows.begin());
        int count = windows.size();
        auto next = windows[((index + direction) % count + count) % count];
        wf::get_core().default_wm->focus_raise_view(next, true);
        return true;
    }

    wf::activator_callback on_next = [=] (const wf::activator_data_t&) { return step_window(1); };
    wf::activator_callback on_prev = [=] (const wf::activator_data_t&) { return step_window(-1); };

  public:
    void set_raw(const std::string& app_id, bool raw)
    {
        raw_app = raw ? app_id : "";
        tell_app(wlr_seat_get_keyboard(wf::get_core().get_current_seat()));
    }

    void init()
    {
        listen_all();
        wf::get_core().connect(&on_device_added);
        wf::get_core().connect(&on_device_removed);
        wf::get_core().connect(&on_focus);
        wf::get_core().connect(&on_key);
        auto& bindings = wf::get_core().bindings;
        bindings->add_activator(quit_app, &on_quit);
        bindings->add_activator(hide_app, &on_hide);
        bindings->add_activator(hide_others, &on_hide_others);
        bindings->add_activator(next_window, &on_next);
        bindings->add_activator(prev_window, &on_prev);
    }
};
