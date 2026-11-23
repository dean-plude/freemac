// SPDX-License-Identifier: GPL-3.0-or-later
// Slow Keys, as on a Mac (Dials > Accessibility > Slow Keys): a key counts
// only once it has been held down for the acceptance delay, so a finger that
// brushes a key on its way to another doesn't type it.
//
// Strata holds back each key press it sees, before Wayfire's own bindings
// and before the app. Let go before the delay and the key is dropped as if
// it had never been pressed; held for the delay and the press goes on, as
// the keyboard itself would have sent it (wlr_keyboard_notify_key), so
// shortcuts, press and hold for accents and the app all see it as usual,
// and the app repeats it while it's held. Shift, Control, Option and Command
// act at once, so a shortcut only waits for its last key.
//
// When the click is on, Strata tells Topline "slow pressed" as a key goes
// down and "slow accepted" once it counts, and Topline plays a soft click
// for each (slow_keys.py), as a Mac does.
// Original freemac code.
#pragma once

#include <cstdint>
#include <set>
#include <string>
#include <xkbcommon/xkbcommon.h>
#include <wayfire/core.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <wlr/interfaces/wlr_keyboard.h>

namespace strata_slow
{
class slow_t
{
  public:
    using tell_fn = void (*)(const std::string&);

    void init(tell_fn tell_topline)
    {
        tell = tell_topline;
        wf::get_core().connect(&on_key);
        enabled.set_callback([=] ()
        {
            if (!enabled)
            {
                drop();
            }
        });
    }

    /* Keys Strata sends itself (the Accessibility Keyboard) go straight
     * through: they were chosen on purpose, not brushed by accident. */
    template<class F>
    void pass(F send)
    {
        bool before = replaying;
        replaying = true;
        send();
        replaying = before;
    }

  private:
    wf::option_wrapper_t<bool> enabled{"strata-shell/slow_keys"};
    wf::option_wrapper_t<int> delay_ms{"strata-shell/slow_keys_delay"};
    wf::option_wrapper_t<bool> click{"strata-shell/slow_keys_click"};
    tell_fn tell = nullptr;

    uint32_t waiting = 0;            // the key held, not yet counted (keycode + 1)
    std::set<uint32_t> dropped;      // let go too soon: their release goes nowhere
    std::set<uint32_t> accepted;     // counted, and still down
    bool replaying = false;
    wf::wl_timer<false> timer;

    static bool is_modifier(uint32_t key)
    {
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        if (!kbd || !kbd->xkb_state)
        {
            return false;
        }

        switch (xkb_state_key_get_one_sym(kbd->xkb_state, key + 8))
        {
          case XKB_KEY_Shift_L:
          case XKB_KEY_Shift_R:
          case XKB_KEY_Control_L:
          case XKB_KEY_Control_R:
          case XKB_KEY_Alt_L:
          case XKB_KEY_Alt_R:
          case XKB_KEY_Meta_L:
          case XKB_KEY_Meta_R:
          case XKB_KEY_Super_L:
          case XKB_KEY_Super_R:
          case XKB_KEY_Hyper_L:
          case XKB_KEY_Hyper_R:
          case XKB_KEY_ISO_Level3_Shift:
          case XKB_KEY_Caps_Lock:
            return true;

          default:
            return false;
        }
    }

    int delay() const
    {
        int ms = delay_ms;
        return (ms < 100) ? 100 : ((ms > 2000) ? 2000 : ms);
    }

    void say(const char *what)
    {
        if (click && tell)
        {
            tell(what);
        }
    }

    /* Turned off: a key still waiting would never come. */
    void drop()
    {
        timer.disconnect();
        if (waiting)
        {
            dropped.insert(waiting - 1);
            waiting = 0;
        }
    }

    void accept()
    {
        uint32_t key = waiting - 1;
        waiting = 0;
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        if (!kbd)
        {
            dropped.insert(key);
            return;
        }

        accepted.insert(key);
        say("slow accepted");
        wlr_keyboard_key_event event{};
        event.time_msec    = wf::get_current_time();
        event.keycode      = key;
        event.update_state = false;   // the keyboard's state already has it
        event.state = WL_KEYBOARD_KEY_STATE_PRESSED;
        replaying   = true;
        wlr_keyboard_notify_key(kbd, &event);
        replaying = false;
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_keyboard_key_event>> on_key =
        [=] (wf::input_event_signal<wlr_keyboard_key_event> *ev)
    {
        if (replaying)
        {
            return;
        }

        uint32_t key = ev->event->keycode;
        if (ev->event->state == WL_KEYBOARD_KEY_STATE_RELEASED)
        {
            if (dropped.erase(key))
            {
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
            } else if (waiting == key + 1)
            {
                /* Let go too soon: as if it had never been pressed. */
                timer.disconnect();
                waiting = 0;
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
            } else
            {
                accepted.erase(key);
            }

            return;
        }

        if (!enabled || (ev->mode != wf::input_event_processing_mode_t::FULL) || is_modifier(key))
        {
            return;
        }

        if (accepted.count(key))
        {
            return;   // already counted and still down
        }

        /* A new key while another still waits: the first one is dropped. */
        if (waiting)
        {
            timer.disconnect();
            dropped.insert(waiting - 1);
        }

        waiting  = key + 1;
        ev->mode = wf::input_event_processing_mode_t::IGNORE;
        say("slow pressed");
        timer.set_timeout(delay(), [=] () { accept(); });
    };
};
}
