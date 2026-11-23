// SPDX-License-Identifier: GPL-3.0-or-later
// Hover Text, as on a Mac (Dials > Accessibility > Hover Text): hold a
// modifier key (Command, unless Dials says Option or Control) and point at
// some words, and Topline shows them large in a panel above the pointer.
//
// Strata only watches: the key held on its own (no other key or button
// since it went down) and where the pointer rests. Once the pointer has
// rested REST_MS, it tells Topline "hover at X Y" (the pointer's place in
// the output layout); letting go of the key, pressing another key or a
// button, or scrolling tells it "hover stop". Topline reads the words under
// the pointer off the screen and draws the panel (hover_text.py). No key or
// button is swallowed, so the key still does what it did before.
//
// strata/hover-cursor {"hide": bool}: Topline hides the pointer for the
// moment it takes the picture, so the arrow doesn't cover the very word it
// points at (on a display drawn without a hardware cursor, the arrow is in
// the picture). It comes back by itself after HIDE_MAX_MS whatever happens.
// Original freemac code.
#pragma once

#include <cmath>
#include <set>
#include <string>
#include <xkbcommon/xkbcommon.h>
#include <nlohmann/json.hpp>
#include <wayfire/core.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>

namespace strata_hover
{
static const int REST_MS = 120;   // the pointer still this long, the panel follows it
static const int HIDE_MAX_MS = 600;

class hover_t
{
  public:
    using tell_fn = void (*)(const std::string&);

    void init(tell_fn tell_topline)
    {
        tell = tell_topline;
        wf::get_core().connect(&on_key);
        wf::get_core().connect(&on_button);
        wf::get_core().connect(&on_axis);
        wf::get_core().connect(&on_motion);
        wf::get_core().connect(&on_motion_absolute);
        enabled.set_callback([=] ()
        {
            if (!enabled)
            {
                stop();
            }
        });
    }

    nlohmann::json cursor(nlohmann::json data)
    {
        bool hide = data.contains("hide") && data["hide"].is_boolean() && data["hide"].get<bool>();
        if (hide && active() && !hidden)
        {
            hidden = true;
            wf::get_core().hide_cursor();
            unhide_timer.set_timeout(HIDE_MAX_MS, [=] () { show_cursor(); });
        } else if (!hide)
        {
            show_cursor();
        }

        return wf::ipc::json_ok();
    }

  private:
    wf::option_wrapper_t<bool> enabled{"strata-shell/hover_text"};
    wf::option_wrapper_t<std::string> key_name{"strata-shell/hover_text_key"};
    tell_fn tell = nullptr;

    std::set<uint32_t> held;     // the hover key(s) down right now
    bool spoiled  = false;       // another key or a button since the key went down
    bool showing  = false;       // Topline has been told where the pointer is
    double last_x = -1, last_y = -1;
    wf::wl_timer<false> rest;
    wf::wl_timer<false> unhide_timer;
    bool hidden = false;

    void show_cursor()
    {
        unhide_timer.disconnect();
        if (hidden)
        {
            hidden = false;
            wf::get_core().unhide_cursor();
        }
    }

    /* The keysyms that count as the chosen key, either side. */
    bool is_hover_key(uint32_t keycode) const
    {
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        if (!kbd || !kbd->xkb_state)
        {
            return false;
        }

        auto sym = xkb_state_key_get_one_sym(kbd->xkb_state, keycode + 8);
        std::string which = key_name;
        if (which == "option")
        {
            return sym == XKB_KEY_Alt_L || sym == XKB_KEY_Alt_R || sym == XKB_KEY_Meta_L ||
                   sym == XKB_KEY_Meta_R;
        }

        if (which == "control")
        {
            return sym == XKB_KEY_Control_L || sym == XKB_KEY_Control_R;
        }

        return sym == XKB_KEY_Super_L || sym == XKB_KEY_Super_R || sym == XKB_KEY_Hyper_L ||
               sym == XKB_KEY_Hyper_R;
    }

    bool active() const
    {
        return enabled && !held.empty() && !spoiled;
    }

    void stop()
    {
        rest.disconnect();
        show_cursor();
        if (showing && tell)
        {
            tell("hover stop");
        }

        showing = false;
        last_x  = last_y = -1;
    }

    void point()
    {
        if (!active() || !tell)
        {
            return;
        }

        auto at = wf::get_core().get_cursor_position();
        int x = (int)std::floor(at.x), y = (int)std::floor(at.y);
        if (showing && (x == (int)last_x) && (y == (int)last_y))
        {
            return;
        }

        last_x  = x;
        last_y  = y;
        showing = true;
        tell("hover at " + std::to_string(x) + " " + std::to_string(y));
    }

    void moved()
    {
        if (active())
        {
            rest.disconnect();
            rest.set_timeout(REST_MS, [=] () { point(); });
        }
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_keyboard_key_event>> on_key =
        [=] (wf::input_event_signal<wlr_keyboard_key_event> *ev)
    {
        uint32_t key = ev->event->keycode;
        bool pressed = (ev->event->state == WL_KEYBOARD_KEY_STATE_PRESSED);
        if (is_hover_key(key))
        {
            if (pressed)
            {
                if (held.empty())
                {
                    spoiled = false;
                }

                held.insert(key);
                // Held with the pointer already still: show at once, after a rest.
                moved();
            } else
            {
                held.erase(key);
                if (held.empty())
                {
                    stop();
                }
            }

            return;
        }

        if (pressed && !held.empty())
        {
            // A shortcut (Command+C...), not Hover Text.
            spoiled = true;
            stop();
        }
    };

    void spoil()
    {
        if (!held.empty())
        {
            spoiled = true;
            stop();
        }
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_button_event>> on_button =
        [=] (wf::input_event_signal<wlr_pointer_button_event>*) { spoil(); };

    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_axis_event>> on_axis =
        [=] (wf::input_event_signal<wlr_pointer_axis_event>*) { spoil(); };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_motion_event>> on_motion =
        [=] (wf::post_input_event_signal<wlr_pointer_motion_event>*) { moved(); };

    wf::signal::connection_t<wf::post_input_event_signal<wlr_pointer_motion_absolute_event>>
    on_motion_absolute =
        [=] (wf::post_input_event_signal<wlr_pointer_motion_absolute_event>*) { moved(); };
};
}
