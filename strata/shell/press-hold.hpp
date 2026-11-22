// SPDX-License-Identifier: GPL-3.0-or-later
// Press and hold a letter for its accents, as on a Mac: holding e in a text
// field shows è é ê ë ē ė ę in a small panel by the text cursor; a number
// key or a click picks one, and it takes the letter's place.
//
// Strata watches the keyboard before the app does. A letter that has
// accents (a c e i l n o s u y z, with or without Shift) is typed once at
// once and doesn't repeat while held; held for HOLD_MS, Strata asks Topline
// to show the panel ("accent show LETTER X Y H", the text cursor's place in
// the layout and its height). While it shows, the number keys, the arrows,
// Return and Escape go to the panel ("accent pick N", "accent move ±1",
// "accent enter", "accent close"); any other key closes it and goes on to
// the app as usual. Topline asks Strata to type the accent it picked
// (strata/accent-type), and says when the panel has closed
// (strata/accent-closed).
//
// Apps say which text field has the keyboard, and where its text cursor
// is, only while an input method runs (freemac-im, strata/im). Without that
// for an app, the panel goes by the window instead, and Topline types the
// accent through wtype.
// Original freemac code.
#pragma once

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <linux/input-event-codes.h>
#include <set>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <wayfire/core.hpp>
#include <wayfire/input-device.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/scene.hpp>
#include <wayfire/seat.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/util.hpp>
#include <wayfire/view.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>

namespace strata_accents
{
/* Tell Topline something over its socket, without waiting. */
static void strata_tell_topline(const std::string& line)
{
    const char *dir = std::getenv("XDG_RUNTIME_DIR");
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::string path = std::string(dir ? dir : "") + "/freemac-topline.sock";
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

static const int HOLD_MS = 450;          // held this long, the panel opens
static const int TYPE_AFTER_MS = 1000;   // the accent goes anyway if the app says nothing back
static const int SETTLE_MS = 70;         // after the app's last word about its cursor
static const char *LETTERS = "aceilnosuyz";

/* Where a point in a view's main surface is in the layout. */
static wf::pointf_t surface_to_layout(wayfire_view view, wf::pointf_t point)
{
    wf::scene::node_t *node = view->get_surface_root_node().get();
    while (node)
    {
        point = node->to_global(point);
        node  = node->parent();
    }

    return point;
}

class hold_t
{
  public:
    void init()
    {
        on_ti_commit.set_callback([=] (void*)
        {
            /* The app may say more than once where its cursor is: send the
             * accent once it has been quiet a moment, or the app takes the
             * accent as out of date and drops it. */
            type_timer.set_timeout(SETTLE_MS, [=] () { send_pending(); });
        });
        on_ti_destroy.set_callback([=] (void*)
        {
            pending_ti = nullptr;
            on_ti_commit.disconnect();
            on_ti_destroy.disconnect();
        });
        wf::get_core().connect(&on_key);
        wf::get_core().connect(&on_button);
        wf::get_core().connect(&on_focus);
    }

    void fini()
    {
        hold_timer.disconnect();
        type_timer.disconnect();
        on_ti_commit.disconnect();
        on_ti_destroy.disconnect();
        close(false);
    }

    /* strata/accent-type: type `text` in place of the held letter. False
     * when the app has no text field Strata can type into; Topline then
     * types it itself. */
    bool type(const std::string& text)
    {
        bool was_open = open;
        close(false);
        auto ti = text_input_now();
        if (!was_open || !ti || text.empty() || (text.size() > 16))
        {
            return false;
        }

        auto seat = wf::get_core().get_current_seat();
        bool surrounding = ti->current.features & WLR_TEXT_INPUT_V3_FEATURE_SURROUNDING_TEXT;
        if (surrounding && ti->current.surrounding.text)
        {
            /* The field says what's before its cursor: replace the letter in
             * one step, if it's there. */
            std::string before(ti->current.surrounding.text,
                std::min<size_t>(ti->current.surrounding.cursor,
                    std::strlen(ti->current.surrounding.text)));
            bool there = !before.empty() && (before.back() == letter);
            wlr_text_input_v3_send_preedit_string(ti, nullptr, 0, 0);
            if (there)
            {
                wlr_text_input_v3_send_delete_surrounding_text(ti, 1, 0);
            }

            wlr_text_input_v3_send_commit_string(ti, text.c_str());
            wlr_text_input_v3_send_done(ti);
            return true;
        }

        /* Otherwise (a terminal, say) a Backspace takes the letter back, and
         * the accent follows once the app has read it: the app answers the
         * Backspace by telling where its cursor has gone, and the accent is
         * sent once it has done that, so the app takes it as up to date. */
        uint32_t now = wf::get_current_time();
        wlr_seat_keyboard_notify_key(seat, now, KEY_BACKSPACE, WL_KEYBOARD_KEY_STATE_PRESSED);
        wlr_seat_keyboard_notify_key(seat, now + 1, KEY_BACKSPACE, WL_KEYBOARD_KEY_STATE_RELEASED);
        pending_text = text;
        pending_ti   = ti;
        on_ti_commit.disconnect();
        on_ti_destroy.disconnect();
        on_ti_commit.connect(&ti->events.commit);
        on_ti_destroy.connect(&ti->events.destroy);
        type_timer.set_timeout(TYPE_AFTER_MS, [=] () { send_pending(); });
        return true;
    }

    /* strata/accent-closed: Topline's panel has gone. */
    void closed()
    {
        open = false;
    }

  private:
    wf::option_wrapper_t<bool> enabled{"strata-shell/press_and_hold"};
    wf::wl_timer<false> hold_timer, type_timer;
    std::string pending_text;
    wlr_text_input_v3 *pending_ti = nullptr;   // the text field an accent waits for
    wf::wl_listener_wrapper on_ti_commit, on_ti_destroy;

    /* Type the accent that waits, in the text field it was meant for. */
    void send_pending()
    {
        type_timer.disconnect();
        on_ti_commit.disconnect();
        on_ti_destroy.disconnect();
        auto ti = pending_ti;
        pending_ti = nullptr;
        if (ti && (ti == text_input_now()))
        {
            wlr_text_input_v3_send_commit_string(ti, pending_text.c_str());
            wlr_text_input_v3_send_done(ti);
        }
    }

    uint32_t held_key = 0;     // the letter being held, 0 for none
    char letter = 0;           // what it typed
    bool open   = false;       // Topline's panel shows
    std::set<uint32_t> swallowed;   // keys pressed for the panel, or the held letter

    /* The keyboard a key came from: the one that has it down now. */
    static wlr_keyboard *keyboard_with(uint32_t key)
    {
        for (auto& device : wf::get_core().get_input_devices())
        {
            auto handle = device->get_wlr_handle();
            if (!handle || (handle->type != WLR_INPUT_DEVICE_KEYBOARD))
            {
                continue;
            }

            auto kbd = wlr_keyboard_from_input_device(handle);
            for (size_t i = 0; i < kbd->num_keycodes; i++)
            {
                if (kbd->keycodes[i] == key)
                {
                    return kbd;
                }
            }
        }

        return nullptr;
    }

    /* The text field with the keyboard now, as its app says, or null. */
    static wlr_text_input_v3 *text_input_now()
    {
        auto seat    = wf::get_core().get_current_seat();
        auto focused = seat ? seat->keyboard_state.focused_surface : nullptr;
        auto manager = wf::get_core().protocols.text_input;
        if (!focused || !manager)
        {
            return nullptr;
        }

        wlr_text_input_v3 *ti;
        wl_list_for_each(ti, &manager->text_inputs, link)
        {
            if ((ti->focused_surface == focused) && ti->current_enabled)
            {
                return ti;
            }
        }

        return nullptr;
    }

    /* Whether the app with the keyboard tells Strata about its text fields
     * at all (it has been told which surface has the keyboard). */
    static bool app_tells()
    {
        auto seat    = wf::get_core().get_current_seat();
        auto focused = seat ? seat->keyboard_state.focused_surface : nullptr;
        auto manager = wf::get_core().protocols.text_input;
        if (!focused || !manager)
        {
            return false;
        }

        wlr_text_input_v3 *ti;
        wl_list_for_each(ti, &manager->text_inputs, link)
        {
            if (ti->focused_surface == focused)
            {
                return true;
            }
        }

        return false;
    }

    void close(bool tell)
    {
        hold_timer.disconnect();
        held_key = 0;
        if (open && tell)
        {
            strata_tell_topline("accent close");
        }

        open = false;
    }

    /* Show the panel by the text cursor, or by the window if the app
     * doesn't say where that is. */
    void show()
    {
        auto seat = wf::get_core().get_current_seat();
        auto view = wf::get_core().seat->get_active_view();
        if (!view || !seat->keyboard_state.focused_surface)
        {
            return;
        }

        wf::pointf_t at;
        double height = 0;
        auto ti = text_input_now();
        if (ti && (ti->current.features & WLR_TEXT_INPUT_V3_FEATURE_CURSOR_RECTANGLE))
        {
            auto view_of = wf::wl_surface_to_wayfire_view(ti->focused_surface->resource);
            if (view_of)
            {
                view = view_of;
            }

            auto rect = ti->current.cursor_rectangle;
            at     = surface_to_layout(view, {(double)rect.x, (double)rect.y});
            height = std::max(rect.height, 1);
        } else
        {
            /* No text cursor known: a third of the way down the window. */
            auto toplevel = wf::toplevel_cast(view);
            if (!toplevel || !view->get_output())
            {
                return;
            }

            auto g = toplevel->get_geometry();
            auto o = wf::origin(view->get_output()->get_layout_geometry());
            at = {(double)(o.x + g.x + g.width / 2), (double)(o.y + g.y + g.height / 3)};
            height = 0;
        }

        open = true;
        strata_tell_topline(std::string("accent show ") + letter + " " +
            std::to_string((int)at.x) + " " + std::to_string((int)at.y) + " " +
            std::to_string((int)height));
    }

    /* A key the panel takes while it shows, as Topline's word for it. */
    static std::string panel_word(uint32_t key)
    {
        if ((key >= KEY_1) && (key <= KEY_9))
        {
            return "pick " + std::to_string(key - KEY_1 + 1);
        }

        if ((key >= KEY_KP1) && (key <= KEY_KP9))
        {
            static const int pad[] = {7, 8, 9, 0, 4, 5, 6, 0, 1, 2, 3};
            int n = (key >= KEY_KP7) ? pad[key - KEY_KP7] : 0;
            return n ? ("pick " + std::to_string(n)) : "";
        }

        switch (key)
        {
          case KEY_LEFT:
            return "move -1";

          case KEY_RIGHT:
          case KEY_TAB:
            return "move 1";

          case KEY_ENTER:
          case KEY_KPENTER:
          case KEY_SPACE:
            return "enter";

          case KEY_ESC:
            return "close";

          default:
            return "";
        }
    }

    wf::signal::connection_t<wf::input_event_signal<wlr_keyboard_key_event>> on_key =
        [=] (wf::input_event_signal<wlr_keyboard_key_event> *ev)
    {
        if (ev->mode != wf::input_event_processing_mode_t::FULL)
        {
            return;
        }

        uint32_t key = ev->event->keycode;
        if (ev->event->state == WL_KEYBOARD_KEY_STATE_RELEASED)
        {
            if (swallowed.erase(key))
            {
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
            }

            if (key == held_key)
            {
                /* Let go before the panel opened: just the letter. */
                hold_timer.disconnect();
                held_key = 0;
            }

            return;
        }

        if (open)
        {
            auto word = panel_word(key);
            if (!word.empty())
            {
                ev->mode = wf::input_event_processing_mode_t::IGNORE;
                swallowed.insert(key);
                strata_tell_topline("accent " + word);
                if (word == "close")
                {
                    open = false;
                }

                return;
            }

            /* Any other key closes the panel and goes on to the app. */
            close(true);
        }

        /* Another key while the letter is held: no panel. */
        hold_timer.disconnect();
        held_key = 0;
        if (!enabled)
        {
            return;
        }

        auto seat = wf::get_core().get_current_seat();
        auto kbd  = keyboard_with(key);
        if (!kbd || !kbd->xkb_state || (wlr_seat_get_keyboard(seat) != kbd) ||
            !seat->keyboard_state.focused_surface || !wf::get_core().seat->get_active_view())
        {
            return;
        }

        /* Only a plain letter (Shift allowed) with accents. */
        auto mods = wlr_keyboard_get_modifiers(kbd);
        auto blocked = WLR_MODIFIER_CTRL | WLR_MODIFIER_ALT | WLR_MODIFIER_LOGO | WLR_MODIFIER_MOD5;
        if (mods & blocked)
        {
            return;
        }

        xkb_keysym_t sym = xkb_state_key_get_one_sym(kbd->xkb_state, key + 8);
        char typed = 0;
        if ((sym >= XKB_KEY_a) && (sym <= XKB_KEY_z))
        {
            typed = 'a' + (sym - XKB_KEY_a);
        } else if ((sym >= XKB_KEY_A) && (sym <= XKB_KEY_Z))
        {
            typed = 'A' + (sym - XKB_KEY_A);
        }

        if (!typed || !std::strchr(LETTERS, std::tolower(typed)))
        {
            return;
        }

        /* An app that tells about its text fields, with none in use: the
         * key works as usual (and repeats). */
        if (app_tells() && !text_input_now())
        {
            return;
        }

        /* Type it once now, and don't let it repeat. */
        ev->mode = wf::input_event_processing_mode_t::IGNORE;
        swallowed.insert(key);
        wlr_seat_keyboard_notify_key(seat, ev->event->time_msec, key, WL_KEYBOARD_KEY_STATE_PRESSED);
        wlr_seat_keyboard_notify_key(seat, ev->event->time_msec, key, WL_KEYBOARD_KEY_STATE_RELEASED);
        held_key = key;
        letter   = typed;
        hold_timer.set_timeout(HOLD_MS, [=] ()
        {
            if (held_key)
            {
                show();
            }
        });
    };

    /* A click anywhere: Topline closes the panel unless it was on it. */
    wf::signal::connection_t<wf::input_event_signal<wlr_pointer_button_event>> on_button =
        [=] (wf::input_event_signal<wlr_pointer_button_event> *ev)
    {
        if (open && (ev->event->state == WLR_BUTTON_PRESSED))
        {
            strata_tell_topline("accent click");
        }
    };

    wf::signal::connection_t<wf::keyboard_focus_changed_signal> on_focus =
        [=] (wf::keyboard_focus_changed_signal*)
    {
        /* Topline's panel never takes the keyboard, so this is another
         * window: the panel goes. */
        close(true);
    };
};
}
