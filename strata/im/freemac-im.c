// SPDX-License-Identifier: GPL-3.0-or-later
// freemac's input method: a quiet one that does nothing itself. Wayfire only
// tells apps which text field has the keyboard (the text-input protocol)
// while an input method is running, so this one runs to switch that on.
// Strata then knows when a text field has the keyboard and where its text
// cursor is, which pressing and holding a letter for its accents needs
// (strata/shell/press-hold.hpp), and types the accent through it.
//
// Topline starts it. If another input method is already running, it leaves.
// Original freemac code.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "input-method-unstable-v2-client-protocol.h"

static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *manager;
static int done;

static void on_global(void *data, struct wl_registry *registry, uint32_t name, const char *interface,
    uint32_t version)
{
    (void)data;
    (void)version;
    if (!seat && (strcmp(interface, wl_seat_interface.name) == 0))
    {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    } else if (strcmp(interface, zwp_input_method_manager_v2_interface.name) == 0)
    {
        manager = wl_registry_bind(registry, name, &zwp_input_method_manager_v2_interface, 1);
    }
}

static void on_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = on_global,
    .global_remove = on_global_remove,
};

/* What the text field says about itself; Strata reads it from Wayfire. */
static void on_activate(void *data, struct zwp_input_method_v2 *im)
{
    (void)data;
    (void)im;
}

static void on_deactivate(void *data, struct zwp_input_method_v2 *im)
{
    (void)data;
    (void)im;
}

static void on_surrounding_text(void *data, struct zwp_input_method_v2 *im, const char *text,
    uint32_t cursor, uint32_t anchor)
{
    (void)data;
    (void)im;
    (void)text;
    (void)cursor;
    (void)anchor;
}

static void on_text_change_cause(void *data, struct zwp_input_method_v2 *im, uint32_t cause)
{
    (void)data;
    (void)im;
    (void)cause;
}

static void on_content_type(void *data, struct zwp_input_method_v2 *im, uint32_t hint, uint32_t purpose)
{
    (void)data;
    (void)im;
    (void)hint;
    (void)purpose;
}

static void on_done(void *data, struct zwp_input_method_v2 *im)
{
    (void)data;
    (void)im;
}

/* Another input method has the seat: that one tells the apps instead. */
static void on_unavailable(void *data, struct zwp_input_method_v2 *im)
{
    (void)data;
    (void)im;
    done = 1;
}

static const struct zwp_input_method_v2_listener im_listener = {
    .activate = on_activate,
    .deactivate = on_deactivate,
    .surrounding_text = on_surrounding_text,
    .text_change_cause = on_text_change_cause,
    .content_type = on_content_type,
    .done = on_done,
    .unavailable = on_unavailable,
};

int main(void)
{
    struct wl_display *display = wl_display_connect(NULL);
    if (!display)
    {
        fprintf(stderr, "freemac-im: no Wayland display\n");
        return 1;
    }

    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !manager)
    {
        fprintf(stderr, "freemac-im: this desktop has no input method support\n");
        return 1;
    }

    struct zwp_input_method_v2 *im = zwp_input_method_manager_v2_get_input_method(manager, seat);
    zwp_input_method_v2_add_listener(im, &im_listener, NULL);
    while (!done && (wl_display_dispatch(display) != -1))
    {
    }

    zwp_input_method_v2_destroy(im);
    wl_display_disconnect(display);
    return 0;
}
