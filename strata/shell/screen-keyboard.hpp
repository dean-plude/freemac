// SPDX-License-Identifier: GPL-3.0-or-later
// The Accessibility Keyboard, as on a Mac (Dials > Accessibility): a
// keyboard on the screen, drawn by Topline (screen_keyboard.py), for typing
// with the pointer alone.
//
// strata/press-key {"key": N, "action": "tap" | "press" | "release"} sends
// one key, by its evdev code, through the computer's own keyboard
// (wlr_keyboard_notify_key, updating its state as a real key would), so
// Wayfire's bindings, the Command key and the app with the keyboard all see
// an ordinary key. Topline holds a modifier down with "press" until the
// next key, and "tap" types a key. Slow Keys lets these through at once.
// Original freemac code.
#pragma once

#include <cstdint>
#include <set>
#include <string>
#include <nlohmann/json.hpp>
#include <wayfire/core.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/util.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <wlr/interfaces/wlr_keyboard.h>
#include "slow-keys.hpp"

namespace strata_screen_keys
{
class keys_t
{
  public:
    void init(strata_slow::slow_t *slow_keys)
    {
        slow = slow_keys;
    }

    nlohmann::json press(nlohmann::json data)
    {
        if (!data.contains("key") || !data["key"].is_number_integer())
        {
            return wf::ipc::json_error("key: an evdev key code");
        }

        int key = data["key"].get<int>();
        if ((key < 1) || (key > 255))
        {
            return wf::ipc::json_error("key out of range");
        }

        std::string action = (data.contains("action") && data["action"].is_string()) ?
            data["action"].get<std::string>() : "tap";
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        if (!kbd)
        {
            return wf::ipc::json_error("no keyboard");
        }

        if ((action == "press") || (action == "tap"))
        {
            send(kbd, key, true);
        }

        if ((action == "release") || (action == "tap"))
        {
            send(kbd, key, false);
        }

        return wf::ipc::json_ok();
    }

    /* Let go of every key this sent and still holds (the panel closed). */
    nlohmann::json release_all(nlohmann::json)
    {
        auto kbd = wlr_seat_get_keyboard(wf::get_core().get_current_seat());
        auto keys = held;
        for (auto key : keys)
        {
            if (kbd)
            {
                send(kbd, key, false);
            }
        }

        held.clear();
        return wf::ipc::json_ok();
    }

  private:
    strata_slow::slow_t *slow = nullptr;
    std::set<uint32_t> held;

    void send(wlr_keyboard *kbd, uint32_t key, bool down)
    {
        if (down ? held.count(key) : !held.count(key))
        {
            return;   // already down, or not ours to let go
        }

        if (down)
        {
            held.insert(key);
        } else
        {
            held.erase(key);
        }

        wlr_keyboard_key_event event{};
        event.time_msec    = wf::get_current_time();
        event.keycode      = key;
        event.update_state = true;
        event.state = down ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED;
        if (slow)
        {
            slow->pass([&] () { wlr_keyboard_notify_key(kbd, &event); });
        } else
        {
            wlr_keyboard_notify_key(kbd, &event);
        }
    }
};
}
