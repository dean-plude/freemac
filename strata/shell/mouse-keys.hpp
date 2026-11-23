// SPDX-License-Identifier: GPL-3.0-or-later
// Mouse Keys, as on a Mac (Dials > Accessibility > Mouse Keys): the numeric
// keypad moves the pointer and clicks, for anyone who finds a mouse or a
// trackpad hard to use.
//
//   keypad 8 / 2 / 4 / 6     up, down, left, right
//   keypad 7 / 9 / 1 / 3     the four diagonals
//   keypad 5                 click (with Control held: a secondary click)
//   keypad 0                 press and hold the button, to drag
//   keypad .                 let go of it
//
// With "use the letter keys too" on, a keyboard without a keypad does the
// same with 8, K, U, O, 7, 9, J, L, I, M and the full stop, as a Mac does.
// Hold a direction and the pointer starts slowly, then speeds up after the
// initial delay to the maximum speed (both set in Dials).
//
// Strata adds a pointer of its own to the seat (a wlr_pointer that no
// hardware stands behind) and sends its motion and buttons through it, so
// Wayfire treats them exactly as a mouse's: focus follows, apps get ordinary
// pointer events, and the pointer settings apply. The keys it uses go no
// further while Mouse Keys is on; with Command or Option held they pass, so
// shortcuts still work.
//
// Pressing Option five times in a row turns Mouse Keys on or off (unless
// Dials turns that off); Strata tells Topline "mouse turned on" or "off",
// and Topline saves it and says so on screen (mouse_keys.py).
// Original freemac code.
#pragma once

#include <cmath>
#include <map>
#include <set>
#include <string>
#include <linux/input-event-codes.h>
#include <xkbcommon/xkbcommon.h>
#include <wayfire/core.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/util.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <wlr/interfaces/wlr_pointer.h>

namespace strata_mouse_keys
{
static const int TICK_MS    = 16;
static const int FIRST_STEP = 3;      // pixels, the moment a direction goes down
static const int ACCEL_MS   = 1200;   // from slow to the maximum speed
static const int OPTION_TAPS   = 5;
static const int TAP_GAP_MS    = 700;

enum action_t
{
    MOVE,
    CLICK,
    HOLD,
    RELEASE,
};

struct key_use_t
{
    action_t action;
    int dx, dy;
};

class mouse_keys_t
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
                stop();
            }
        });
    }

  private:
    wf::option_wrapper_t<bool> enabled{"strata-shell/mouse_keys"};
    wf::option_wrapper_t<bool> letters{"strata-shell/mouse_keys_letters"};
    wf::option_wrapper_t<int> delay_ms{"strata-shell/mouse_keys_delay"};
    wf::option_wrapper_t<int> max_speed{"strata-shell/mouse_keys_speed"};
    wf::option_wrapper_t<bool> option_toggles{"strata-shell/mouse_keys_option"};
    tell_fn tell = nullptr;

    wlr_pointer pointer{};
    bool added = false;
    std::map<uint32_t, key_use_t> moving;   // direction keys held now
    std::set<uint32_t> swallowed;           // their releases go nowhere either
    bool button_held   = false;
    uint32_t held_button = BTN_LEFT;
    uint32_t moving_since = 0;
    double carry_x = 0, carry_y = 0;        // fractions of a pixel left over
    wf::wl_timer<true> tick;

    int option_taps = 0;
    uint32_t last_option_tap = 0;
    bool option_alone = false;

    static const wlr_pointer_impl *impl()
    {
        static const wlr_pointer_impl it = {"strata-mouse-keys"};
        return &it;
    }

    /* Strata's own pointer, added to the seat the first time it's needed. */
    wlr_pointer *device()
    {
        if (!added)
        {
            wlr_pointer_init(&pointer, impl(), "strata-mouse-keys");
            wl_signal_emit_mutable(&wf::get_core().backend->events.new_input, &pointer.base);
            added = true;
        }

        return &pointer;
    }

    static bool find(uint32_t key, bool with_letters, key_use_t& use)
    {
        switch (key)
        {
          case KEY_KP8:
            use = {MOVE, 0, -1};
            return true;

          case KEY_KP2:
            use = {MOVE, 0, 1};
            return true;

          case KEY_KP4:
            use = {MOVE, -1, 0};
            return true;

          case KEY_KP6:
            use = {MOVE, 1, 0};
            return true;

          case KEY_KP7:
            use = {MOVE, -1, -1};
            return true;

          case KEY_KP9:
            use = {MOVE, 1, -1};
            return true;

          case KEY_KP1:
            use = {MOVE, -1, 1};
            return true;

          case KEY_KP3:
            use = {MOVE, 1, 1};
            return true;

          case KEY_KP5:
            use = {CLICK, 0, 0};
            return true;

          case KEY_KP0:
            use = {HOLD, 0, 0};
            return true;

          case KEY_KPDOT:
            use = {RELEASE, 0, 0};
            return true;

          default:
            break;
        }

        if (!with_letters)
        {
            return false;
        }

        switch (key)
        {
          case KEY_8:
            use = {MOVE, 0, -1};
            return true;

          case KEY_K:
            use = {MOVE, 0, 1};
            return true;

          case KEY_U:
            use = {MOVE, -1, 0};
            return true;

          case KEY_O:
            use = {MOVE, 1, 0};
            return true;

          case KEY_7:
            use = {MOVE, -1, -1};
            return true;

          case KEY_9:
            use = {MOVE, 1, -1};
            return true;

          case KEY_J:
            use = {MOVE, -1, 1};
            return true;

          case KEY_L:
            use = {MOVE, 1, 1};
            return true;

          case KEY_I:
            use = {CLICK, 0, 0};
            return true;

          case KEY_M:
            use = {HOLD, 0, 0};
            return true;

          case KEY_DOT:
            use = {RELEASE, 0, 0};
            return true;

          default:
            return false;
        }
    }

    static xkb_keysym_t sym_of(uint32_t key)
    {
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        if (!kbd || !kbd->xkb_state)
        {
            return XKB_KEY_NoSymbol;
        }

        return xkb_state_key_get_one_sym(kbd->xkb_state, key + 8);
    }

    static bool is_option(xkb_keysym_t sym)
    {
        return sym == XKB_KEY_Alt_L || sym == XKB_KEY_Alt_R || sym == XKB_KEY_Meta_L ||
               sym == XKB_KEY_Meta_R;
    }

    /* Command or Option held: a shortcut, not Mouse Keys. */
    static bool shortcut_held()
    {
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        if (!kbd)
        {
            return false;
        }

        uint32_t mods = wlr_keyboard_get_modifiers(kbd);
        return mods & (WLR_MODIFIER_ALT | WLR_MODIFIER_LOGO);
    }

    static bool control_held()
    {
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        return kbd && (wlr_keyboard_get_modifiers(kbd) & WLR_MODIFIER_CTRL);
    }

    void frame()
    {
        wl_signal_emit_mutable(&device()->events.frame, device());
    }

    void move_by(double dx, double dy)
    {
        wlr_pointer_motion_event ev{};
        ev.pointer    = device();
        ev.time_msec  = wf::get_current_time();
        ev.delta_x    = ev.unaccel_dx = dx;
        ev.delta_y    = ev.unaccel_dy = dy;
        wl_signal_emit_mutable(&device()->events.motion, &ev);
        frame();
    }

    void button(uint32_t which, bool down)
    {
        wlr_pointer_button_event ev{};
        ev.pointer   = device();
        ev.time_msec = wf::get_current_time();
        ev.button    = which;
        ev.state     = down ? WLR_BUTTON_PRESSED : WLR_BUTTON_RELEASED;
        wl_signal_emit_mutable(&device()->events.button, &ev);
        frame();
    }

    void direction(int& dx, int& dy) const
    {
        dx = dy = 0;
        for (auto& [_key, use] : moving)
        {
            dx += use.dx;
            dy += use.dy;
        }

        dx = (dx > 0) - (dx < 0);
        dy = (dy > 0) - (dy < 0);
    }

    /* Pixels a tick, once the initial delay is over: from 1 up to the
     * maximum (Dials' 1 to 10 makes 4 to 22). */
    double speed_now() const
    {
        int top = max_speed;
        top = (top < 1) ? 1 : ((top > 10) ? 10 : top);
        double fastest = 2.0 + 2.0 * top;
        int wait = delay_ms;
        wait = (wait < 0) ? 0 : ((wait > 2000) ? 2000 : wait);
        double since = (double)(wf::get_current_time() - moving_since) - wait;
        if (since < 0)
        {
            return 0;
        }

        return std::min(fastest, 1.0 + (fastest - 1.0) * since / ACCEL_MS);
    }

    bool step()
    {
        int dx, dy;
        direction(dx, dy);
        if (moving.empty())
        {
            return false;
        }

        double speed = speed_now();
        if ((speed <= 0) || ((dx == 0) && (dy == 0)))
        {
            return true;   // still waiting out the delay
        }

        // Diagonals at the same speed as straight lines.
        double scale = (dx && dy) ? speed / std::sqrt(2.0) : speed;
        carry_x += dx * scale;
        carry_y += dy * scale;
        double x = std::trunc(carry_x), y = std::trunc(carry_y);
        carry_x -= x;
        carry_y -= y;
        if (x || y)
        {
            move_by(x, y);
        }

        return true;
    }

    void stop()
    {
        tick.disconnect();
        moving.clear();
        carry_x = carry_y = 0;
        if (button_held)
        {
            button_held = false;
            button(held_button, false);
        }
    }

    void use_key(uint32_t key, const key_use_t& use)
    {
        switch (use.action)
        {
          case MOVE:
          {
            bool first = moving.empty();
            moving[key] = use;
            if (first)
            {
                moving_since = wf::get_current_time();
                carry_x = carry_y = 0;
                tick.set_timeout(TICK_MS, [=] () { return step(); });
            }

            // A short tap moves a little at once, to place the pointer finely.
            move_by(use.dx * FIRST_STEP, use.dy * FIRST_STEP);
            break;
          }

          case CLICK:
          {
            uint32_t which = control_held() ? BTN_RIGHT : BTN_LEFT;
            if (button_held)
            {
                // A click while held lets go first, as a Mac does.
                button_held = false;
                button(held_button, false);
            }

            button(which, true);
            button(which, false);
            break;
          }

          case HOLD:
            if (!button_held)
            {
                button_held = true;
                held_button = BTN_LEFT;
                button(held_button, true);
            }

            break;

          case RELEASE:
            if (button_held)
            {
                button_held = false;
                button(held_button, false);
            }

            break;
        }
    }

    /* Option pressed and let go on its own five times in a row. */
    void count_option(uint32_t key, bool pressed, uint32_t time)
    {
        bool option = is_option(sym_of(key));
        if (!option)
        {
            if (pressed)
            {
                option_taps  = 0;
                option_alone = false;
            }

            return;
        }

        if (pressed)
        {
            option_alone = true;
            return;
        }

        if (!option_alone || !option_toggles)
        {
            return;
        }

        option_alone = false;
        option_taps  = (option_taps && (time - last_option_tap <= (uint32_t)TAP_GAP_MS)) ? option_taps + 1 : 1;
        last_option_tap = time;
        if (option_taps >= OPTION_TAPS)
        {
            option_taps = 0;
            bool on = !enabled;
            if (!on)
            {
                stop();
            }

            if (tell)
            {
                tell(on ? "mouse turned on" : "mouse turned off");
            }
        }
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_keyboard_key_event>> on_key =
        [=] (wf::input_event_signal<wlr_keyboard_key_event> *ev)
    {
        uint32_t key = ev->event->keycode;
        bool pressed = (ev->event->state == WL_KEYBOARD_KEY_STATE_PRESSED);
        if (ev->mode == wf::input_event_processing_mode_t::FULL)
        {
            count_option(key, pressed, ev->event->time_msec);
        }

        if (!pressed)
        {
            if (swallowed.erase(key))
            {
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
                moving.erase(key);
            }

            return;
        }

        if (!enabled || (ev->mode != wf::input_event_processing_mode_t::FULL) || shortcut_held())
        {
            return;
        }

        key_use_t use;
        if (!find(key, letters, use))
        {
            return;
        }

        ev->mode = wf::input_event_processing_mode_t::IGNORE;
        swallowed.insert(key);
        if (!moving.count(key))   // the keyboard's own repeat: already moving
        {
            use_key(key, use);
        }
    };
};
}
