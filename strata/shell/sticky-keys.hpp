// SPDX-License-Identifier: GPL-3.0-or-later
// Sticky Keys, as on a Mac (Dials > Accessibility > Sticky Keys): a
// modifier key tapped on its own (Shift, Control, Option or Command) stays
// down for the next key pressed. Tapped twice it locks, until it's tapped a
// third time. Pressing Shift five times in a row turns Sticky Keys on or
// off, when that's allowed.
//
// Strata watches the keys before Wayfire handles them, but changes nothing
// about them. Once a tap has been counted it sets the sticky modifiers on
// the keyboard itself (wlr_keyboard_notify_modifiers), so apps, Strata's
// own shortcuts and the Command key all see them held. It does that after
// the key event is over, because wlroots updates the keyboard's state only
// after the event. A latched modifier is let go just after the next key.
//
// Topline shows the modifiers that are set, in the top-right corner, and
// beeps when one is: "sticky state SHIFT CONTROL OPTION COMMAND", each 0
// (off), 1 (for the next key) or 2 (locked). "sticky turned on" or "off"
// after five Shifts: Topline saves the choice and says so.
// Original freemac code.
#pragma once

#include <array>
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

namespace strata_sticky
{
enum modifier { SHIFT = 0, CONTROL = 1, OPTION = 2, COMMAND = 3, NONE = -1 };
static const int SHIFT_TAPS = 5;        // in a row, to turn Sticky Keys on or off
static const int TAP_GAP_MS = 700;      // at most this long between those taps

class sticky_t
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
                clear();
            }
        });
    }

    void fini()
    {
        clear();
        on_key.disconnect();
    }

  private:
    wf::option_wrapper_t<bool> enabled{"strata-shell/sticky_keys"};
    wf::option_wrapper_t<bool> shift_toggles{"strata-shell/sticky_keys_shift"};
    tell_fn tell = nullptr;

    std::array<int, 4> state{0, 0, 0, 0};   // 0 off, 1 for the next key, 2 locked
    std::set<uint32_t> held;                 // modifier keys down right now
    modifier pending = NONE;                 // pressed alone so far
    int shift_taps = 0;
    uint32_t last_shift_tap = 0;
    wf::wl_idle_call idle;

    static uint32_t mask_of(wlr_keyboard *kbd, modifier m)
    {
        static const char *names[] = {
            XKB_MOD_NAME_SHIFT, XKB_MOD_NAME_CTRL, XKB_MOD_NAME_ALT, XKB_MOD_NAME_LOGO,
        };
        if (!kbd || !kbd->keymap || (m == NONE))
        {
            return 0;
        }

        auto index = xkb_keymap_mod_get_index(kbd->keymap, names[m]);
        return (index == XKB_MOD_INVALID) ? 0 : (1u << index);
    }

    /* Which modifier a key is, by what the layout makes it (so a swapped
     * Option and Command still count as what they do). */
    static modifier modifier_of(wlr_keyboard *kbd, uint32_t key)
    {
        if (!kbd || !kbd->xkb_state)
        {
            return NONE;
        }

        switch (xkb_state_key_get_one_sym(kbd->xkb_state, key + 8))
        {
          case XKB_KEY_Shift_L:
          case XKB_KEY_Shift_R:
            return SHIFT;

          case XKB_KEY_Control_L:
          case XKB_KEY_Control_R:
            return CONTROL;

          case XKB_KEY_Alt_L:
          case XKB_KEY_Alt_R:
          case XKB_KEY_Meta_L:
          case XKB_KEY_Meta_R:
            return OPTION;

          case XKB_KEY_Super_L:
          case XKB_KEY_Super_R:
          case XKB_KEY_Hyper_L:
          case XKB_KEY_Hyper_R:
            return COMMAND;

          default:
            return NONE;
        }
    }

    static wlr_keyboard *seat_keyboard()
    {
        return wlr_seat_get_keyboard(wf::get_core().get_current_seat());
    }

    bool any_set() const
    {
        for (int s : state)
        {
            if (s)
            {
                return true;
            }
        }

        return false;
    }

    void say_state()
    {
        if (tell)
        {
            tell("sticky state " + std::to_string(state[SHIFT]) + " " + std::to_string(state[CONTROL]) +
                " " + std::to_string(state[OPTION]) + " " + std::to_string(state[COMMAND]));
        }
    }

    /* Put the sticky modifiers on the keyboard, beside the ones really
     * held, once the key event in hand is over. */
    void apply_soon()
    {
        idle.run_once([=] () { apply(); });
    }

    void apply()
    {
        auto kbd = seat_keyboard();
        if (!kbd)
        {
            return;
        }

        // Other modifiers (AltGr's, say) stay as they are.
        uint32_t ours = 0;
        for (int m = SHIFT; m <= COMMAND; m++)
        {
            ours |= mask_of(kbd, (modifier)m);
        }

        auto& now = kbd->modifiers;
        uint32_t down = now.depressed & ~ours;
        for (uint32_t key : held)
        {
            down |= mask_of(kbd, modifier_of(kbd, key));
        }

        for (int m = SHIFT; m <= COMMAND; m++)
        {
            if (state[m])
            {
                down |= mask_of(kbd, (modifier)m);
            }
        }

        if (now.depressed != down)
        {
            wlr_keyboard_notify_modifiers(kbd, down, now.latched, now.locked, now.group);
        }
    }

    void clear()
    {
        bool was = any_set();
        state   = {0, 0, 0, 0};
        pending = NONE;
        if (was)
        {
            apply_soon();
            say_state();
        }
    }

    /* Five Shifts in a row, each soon after the last. */
    bool counted_shift_tap(uint32_t time)
    {
        if (!shift_toggles)
        {
            return false;
        }

        shift_taps = (shift_taps && (time - last_shift_tap <= (uint32_t)TAP_GAP_MS)) ? shift_taps + 1 : 1;
        last_shift_tap = time;
        if (shift_taps < SHIFT_TAPS)
        {
            return false;
        }

        shift_taps = 0;
        bool on = !enabled;
        clear();
        if (tell)
        {
            tell(on ? "sticky turned on" : "sticky turned off");
        }

        return true;
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_keyboard_key_event>> on_key =
        [=] (wf::input_event_signal<wlr_keyboard_key_event> *ev)
    {
        auto kbd = seat_keyboard();
        uint32_t key = ev->event->keycode;
        modifier m   = modifier_of(kbd, key);
        bool pressed = (ev->event->state == WL_KEYBOARD_KEY_STATE_PRESSED);

        if (m == NONE)
        {
            if (pressed)
            {
                pending    = NONE;
                shift_taps = 0;
                // The key goes out with the modifiers set for it; then the
                // ones that were only for this key are let go.
                bool latched = false;
                for (auto& s : state)
                {
                    if (s == 1)
                    {
                        s = 0;
                        latched = true;
                    }
                }

                if (latched)
                {
                    apply_soon();
                    say_state();
                }
            }

            return;
        }

        if (pressed)
        {
            held.insert(key);
            pending = held.size() == 1 ? m : NONE;
            return;
        }

        held.erase(key);
        bool tapped = (pending == m);
        pending = NONE;
        if (!tapped)
        {
            shift_taps = 0;
            if (any_set())
            {
                apply_soon();
            }

            return;
        }

        if ((m == SHIFT) ? counted_shift_tap(ev->event->time_msec) : ((shift_taps = 0), false))
        {
            return;
        }

        if (!enabled)
        {
            return;
        }

        state[m] = (state[m] + 1) % 3;
        apply_soon();
        say_state();
    };
};
}
