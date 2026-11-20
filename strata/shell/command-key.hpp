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
 *   Super+. cancels a dialog, as Escape does.
 *
 * An app that stays open with no window keeps its shortcuts: Topline tells
 * Strata which ones its menus offer (Super+N for New...), and Strata asks the
 * app to carry them out when one is pressed while no window has the keyboard.
 *
 * Original freemac code.
 */
#pragma once
#include "hidden-windows.hpp"

#include <algorithm>
#include <cctype>
#include <cstring>
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
#include <nlohmann/json.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/util.hpp>
#include <wayfire/util/log.hpp>
#include <wayfire/view-helpers.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>

class strata_command_key
{
    wf::option_wrapper_t<bool> enabled{"strata-shell/command_key"};
    wf::option_wrapper_t<std::string> terminals{"strata-shell/command_key_terminals"};
    wf::option_wrapper_t<wf::activatorbinding_t> quit_app{"strata-shell/quit_app"};
    wf::option_wrapper_t<std::string> whole_apps{"strata-shell/quit_whole_apps"};
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

    /* The modifier keys held down right now, as the keyboard has them (the
     * Command key is Logo). Tack asks while its panel is up, because it may
     * not have the keyboard itself and so can't see Command let go. */
  public:
    nlohmann::json held_modifiers()
    {
        nlohmann::json out = nlohmann::json::object();
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        uint32_t down = kbd ? kbd->modifiers.depressed : 0;
        out["command"] = kbd && (down & mask(kbd, XKB_MOD_NAME_LOGO));
        out["alt"]     = kbd && (down & mask(kbd, XKB_MOD_NAME_ALT));
        out["control"] = kbd && (down & mask(kbd, XKB_MOD_NAME_CTRL));
        out["shift"]   = kbd && (down & mask(kbd, XKB_MOD_NAME_SHIFT));
        return out;
    }

  private:
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

    static bool dialog_focused()
    {
        auto view = wf::toplevel_cast(wf::get_core().seat->get_active_view());
        return view && view->parent;
    }

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

              case KEY_DOT:
                /* Command-period cancels, in a dialog. Elsewhere it stays
                 * Ctrl+period for the app. */
                if (dialog_focused())
                {
                    out = {KEY_ESC, logo, 0};
                    return true;
                }

                break;
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

        /* No window has the keyboard (the desktop may hold it, as nothing). */
        if (enabled && !wf::get_core().seat->get_active_view() && windowless_shortcut(kbd, key))
        {
            ev->mode = wf::input_event_processing_mode_t::IGNORE;
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

    /* -- the shortcuts of an app with no window open */

    /* The key's name as on its key cap, unshifted ("n", "comma"). */
    static std::string key_name(wlr_keyboard *kbd, uint32_t key)
    {
        if (!kbd->keymap || !kbd->xkb_state)
        {
            return "";
        }

        xkb_keycode_t code = key + 8;
        auto layout = xkb_state_key_get_layout(kbd->xkb_state, code);
        const xkb_keysym_t *syms = nullptr;
        int count = xkb_keymap_key_get_syms_by_level(kbd->keymap, code,
            (layout == XKB_LAYOUT_INVALID) ? 0 : layout, 0, &syms);
        char name[64];
        if ((count < 1) || (xkb_keysym_get_name(xkb_keysym_to_lower(syms[0]), name, sizeof(name)) <= 0))
        {
            return "";
        }

        return name;
    }

    /* Command (with Shift, Option) and a key, as Topline names them:
     * "alt+command+shift+n". */
    std::string chord(wlr_keyboard *kbd, uint32_t key)
    {
        uint32_t mods = kbd->modifiers.depressed;
        if (!(mods & mask(kbd, XKB_MOD_NAME_LOGO)) || (mods & mask(kbd, XKB_MOD_NAME_CTRL)))
        {
            return "";
        }

        auto name = key_name(kbd, key);
        if (name.empty())
        {
            return "";
        }

        std::string out = (mods & mask(kbd, XKB_MOD_NAME_ALT)) ? "alt+command+" : "command+";
        if (mods & mask(kbd, XKB_MOD_NAME_SHIFT))
        {
            out += "shift+";
        }

        return out + name;
    }

    bool windowless_shortcut(wlr_keyboard *kbd, uint32_t key)
    {
        if (front_windowless.empty() || (front_windowless != windowless_keys_app))
        {
            return false;
        }

        auto it = windowless_keys.find(chord(kbd, key));
        return (it != windowless_keys.end()) &&
               activate_app_action(whole_app_bus_name(front_windowless), it->second);
    }

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

    /* For an app that stays open with no window, the D-Bus name it owns, so
     * Quit asks the app itself to quit rather than closing its windows; ""
     * for other apps. The option lists app-id=bus.name pairs. */
    std::string whole_app_bus_name(const std::string& app_id)
    {
        std::istringstream pairs{std::string(whole_apps)};
        std::string pair;
        while (pairs >> pair)
        {
            auto eq = pair.find('=');
            if ((eq != std::string::npos) && (pair.substr(0, eq) == app_id))
            {
                return pair.substr(eq + 1);
            }
        }

        return "";
    }

    /* Activate one of the app's own actions over D-Bus (its quit asks about
     * unsaved changes itself). The names become part of a command, so only
     * plain D-Bus and action names are accepted. */
    static bool plain(const std::string& text, const char *also)
    {
        return !text.empty() && (text.size() <= 200) &&
               std::all_of(text.begin(), text.end(), [=] (char c)
        {
            return std::isalnum((unsigned char)c) || ((c != 0) && strchr(also, c));
        });
    }

    static bool activate_app_action(const std::string& bus_name, const std::string& action)
    {
        if (!plain(bus_name, "._") || !plain(action, "-_."))
        {
            return false;
        }

        std::string path = "/" + bus_name;
        std::replace(path.begin(), path.end(), '.', '/');
        wf::get_core().run("gdbus call --session --dest " + bus_name + " --object-path " + path +
            " --method org.gtk.Actions.Activate " + action + " '[]' '{}' >/dev/null 2>&1");
        return true;
    }

    static bool ask_app_to_quit(const std::string& bus_name)
    {
        return activate_app_action(bus_name, "quit");
    }

    wf::activator_callback on_quit = [=] (const wf::activator_data_t&)
    {
        auto view = focused_app_window();
        std::string app_id = view ? view->get_app_id() : front_windowless;
        if (ask_app_to_quit(whole_app_bus_name(app_id)))
        {
            front_windowless.clear();
            return true;
        }

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
                strata_hidden::hide(window);
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
                strata_hidden::hide(window);
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

    /* An app that stays open with no window keeps the front when its last
     * window closes, as on a Mac: no other app's window takes the keyboard.
     * Wayfire hands focus to the next window as the last one goes; Strata
     * takes it back straight after, and the app stays in the menu bar. */
    wf::wl_idle_call keep_front_idle;
    wf::signal::connection_t<wf::view_unmapped_signal> on_unmapped = [=] (wf::view_unmapped_signal *ev)
    {
        auto view = wf::toplevel_cast(ev->view);
        if (!view || view->parent || (wf::get_core().seat->get_active_view() != ev->view))
        {
            return;
        }

        std::string app_id = view->get_app_id();
        if (whole_app_bus_name(app_id).empty())
        {
            return;
        }

        for (auto& other : wf::get_core().get_all_views())
        {
            auto toplevel = wf::toplevel_cast(other);
            if (toplevel && (toplevel != view) && toplevel->is_mapped() &&
                (toplevel->get_app_id() == app_id) && !toplevel->minimized)
            {
                return; // the app has another window to go to
            }
        }

        front_windowless = app_id;
        keep_front_idle.run_once([=] ()
        {
            if (front_windowless == app_id)
            {
                wf::get_core().seat->focus_view(nullptr);
            }
        });
    };

    wf::activator_callback on_next = [=] (const wf::activator_data_t&) { return step_window(1); };
    wf::activator_callback on_prev = [=] (const wf::activator_data_t&) { return step_window(-1); };

  public:
    /* The app in front with no window open (Topline says which), for ⌘Q. */
    std::string front_windowless;

    /* Its shortcuts, as Topline found them in its menus: chord -> action. */
    std::string windowless_keys_app;
    std::map<std::string, std::string> windowless_keys;

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
        wf::get_core().connect(&on_unmapped);
        auto& bindings = wf::get_core().bindings;
        bindings->add_activator(quit_app, &on_quit);
        bindings->add_activator(hide_app, &on_hide);
        bindings->add_activator(hide_others, &on_hide_others);
        bindings->add_activator(next_window, &on_next);
        bindings->add_activator(prev_window, &on_prev);
    }
};
