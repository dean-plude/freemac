// Strata's copy of Wayfire's gtk-shell plugin. Besides what gtk-shell does, it
// keeps the menu addresses GTK apps publish (Wayfire's plugin drops them),
// hands them to Topline over IPC (strata/app-menus), and tells GTK apps that
// the desktop shows their menu bar, so they leave it out of the window. It
// also lets Pier say where each window's dock icon is (strata/minimize-hint),
// so minimizing a window shrinks it into that icon and restoring grows it back,
// closes windows on request (strata/close) for Quit in the menu bar and dock,
// and draws small pictures of minimized windows for the dock (strata/snapshot).
// strata/input-source reads and switches the keyboard's input source (the XKB
// layout group), for Topline's input menu.
// It also plays freemac's alert sound (freemac-sound alert) for gtk_shell1's
// system bell, which GTK apps ring when something can't be done.
// strata/outputs lists the displays and the modes each can show, for Dials.
#include "gtk-shell-protocol.h"
#include "wayfire/core.hpp"
#include "wayfire/object.hpp"
#include <chrono>
#include <map>
#include <csignal>
#include <sys/types.h>
#include <unistd.h>
#include <string>
#include <wayfire/util.hpp>
#include <wayfire/view.hpp>
#include <wayfire/signal-definitions.hpp>
#include <wayfire/nonstd/wlroots-full.hpp>
#include <wayfire/plugin.hpp>
#include <wayfire/toplevel-view.hpp>
#include <wayfire/window-manager.hpp>
#include <wayfire/option-wrapper.hpp>
#include <wayfire/plugins/common/shared-core-data.hpp>
#include <wayfire/plugins/ipc/ipc-helpers.hpp>
#include <wayfire/plugins/ipc/ipc-method-repository.hpp>
#include <wayfire/idle.hpp>
#include <wayfire/input-device.hpp>
#include <wayfire/output-layout.hpp>
#include <wayfire/output.hpp>

#include "gtk-shell.hpp"
#include "window-places.hpp"
#include "command-key.hpp"
#include "window-snapshot.hpp"
#include "minimize-glide.hpp"
#include "sheets.hpp"
#include "screen-flash.hpp"
#include "pointer-locate.hpp"
#include "press-hold.hpp"
#include "sticky-keys.hpp"
#include "hover-text.hpp"
#include "colour-filters.hpp"
#include "mission-control.hpp"
#include "attention.hpp"

#define GTK_SHELL_VERSION 3

/* What a GTK app told us about one of its windows (gtk_surface1.set_dbus_properties). */
struct strata_surface_props
{
    std::string app_id;
    std::string app_menu_path;
    std::string menubar_path;
    std::string window_object_path;
    std::string application_object_path;
    std::string unique_bus_name;
};

class strata_shell_data : public wf::custom_data_t
{
  public:
    /* Keyed by the wl_surface resource of the window. */
    std::map<wl_resource*, strata_surface_props> surfaces;
};

static std::string or_empty(const char *s)
{
    return s ? s : "";
}

struct wf_gtk_surface
{
    wl_resource *resource;
    wl_resource *wl_surface;
    wf::wl_listener_wrapper on_configure;
    wf::wl_listener_wrapper on_destroy;
};

/**
 *  In gnome-shell/mutter/meta windows/views keep track of the properties
 *  specified as arguments here.
 *  Currently only the app_id is implemented / required.
 */
static void handle_gtk_surface_set_dbus_properties(wl_client *client,
    wl_resource *resource,
    const char *application_id, const char *app_menu_path, const char *menubar_path,
    const char *window_object_path, const char *application_object_path,
    const char *unique_bus_name)
{
    auto surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(resource));
    auto& props  = wf::get_core().get_data_safe<strata_shell_data>()->surfaces[surface->wl_surface];
    if (application_id)
    {
        props.app_id = application_id;
    }

    props.app_menu_path = or_empty(app_menu_path);
    props.menubar_path  = or_empty(menubar_path);
    props.window_object_path = or_empty(window_object_path);
    props.application_object_path = or_empty(application_object_path);
    props.unique_bus_name = or_empty(unique_bus_name);
}

/**
 * Modal dialogs may be handled differently than non-modal dialogs.
 * It is a hint that this should be attached to the parent surface.
 * In gnome this does not affect input-focus.
 * This function sets the modal hint.
 */
static void handle_gtk_surface_set_modal(wl_client *client, wl_resource *resource)
{
    auto surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(resource));
    /* GTK says a dialog is modal before it shows, often before Wayfire has
     * a view for it; Strata's sheets look it up by surface. */
    strata_sheets::modal_surfaces().insert(surface->wl_surface);
    wayfire_view view = wf::wl_surface_to_wayfire_view(surface->wl_surface);
    if (view)
    {
        view->store_data(std::make_unique<wf::custom_data_t>(), "gtk-shell-modal");
    }
}

/**
 * Modal dialogs may be handled differently than non-modal dialogs.
 * It is a hint that this should be attached to the parent surface.
 * In gnome this does not affect input-focus.
 * This function removes the modal hint.
 */
static void handle_gtk_surface_unset_modal(wl_client *client, wl_resource *resource)
{
    auto surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(resource));
    strata_sheets::modal_surfaces().erase(surface->wl_surface);
    wayfire_view view = wf::wl_surface_to_wayfire_view(surface->wl_surface);
    if (view)
    {
        view->erase_data("gtk-shell-modal");
    }
}

/**
 * The surface requests focus, for example single instance applications like
 * gnome-control-center, gnome-clocks, dconf-editor are single instance and if
 * they are already running and launched again, this will request that they get
 * focused.
 * This function is superseded by handle_gtk_surface_request_focus a newer
 * equivalelent
 * used by gtk-applications now. This function is for compatibility reasons.
 */
static void handle_gtk_surface_present(wl_client *client, wl_resource *resource,
    uint32_t time)
{
    auto surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(resource));
    wayfire_toplevel_view view = toplevel_cast(wf::wl_surface_to_wayfire_view(surface->wl_surface));
    if (view)
    {
        wf::get_core().default_wm->focus_request(view, true);
    }
}

/**
 * The surface requests focus, for example single instance applications like
 * gnome-control-center, gnome-clocks, dconf-editor are single instance and if
 * they are already running and launched again, this will request that they get
 * focused.
 */
static void handle_gtk_surface_request_focus(struct wl_client *client,
    struct wl_resource *resource,
    const char *startup_id)
{
    auto surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(resource));
    wayfire_toplevel_view view = toplevel_cast(wf::wl_surface_to_wayfire_view(surface->wl_surface));
    if (view)
    {
        wf::get_core().default_wm->focus_request(view, true);
    }
}

/**
 * Helper function used by send_gtk_surface_configure
 * and send_gtk_surface_configure_edges
 */
static void append_to_array(wl_array *array, uint32_t value)
{
    uint32_t *tmp;
    tmp  = (uint32_t*)wl_array_add(array, sizeof(*tmp));
    *tmp = value;
}

/**
 * Tells the client about the window state in more detail than xdg_surface.
 * This currently only includes which edges are tiled.
 */
static void send_gtk_surface_configure(wf_gtk_surface *surface, wayfire_toplevel_view view)
{
    int version = wl_resource_get_version(surface->resource);
    wl_array states;
    wl_array_init(&states);

    if (view->pending_tiled_edges())
    {
        append_to_array(&states, GTK_SURFACE1_STATE_TILED);
    }

    if ((version >= GTK_SURFACE1_STATE_TILED_TOP_SINCE_VERSION) &&
        (view->pending_tiled_edges() & WLR_EDGE_TOP))
    {
        append_to_array(&states, GTK_SURFACE1_STATE_TILED_TOP);
    }

    if ((version >= GTK_SURFACE1_STATE_TILED_RIGHT_SINCE_VERSION) &&
        (view->pending_tiled_edges() & WLR_EDGE_RIGHT))
    {
        append_to_array(&states, GTK_SURFACE1_STATE_TILED_RIGHT);
    }

    if ((version >= GTK_SURFACE1_STATE_TILED_BOTTOM_SINCE_VERSION) &&
        (view->pending_tiled_edges() & WLR_EDGE_BOTTOM))
    {
        append_to_array(&states, GTK_SURFACE1_STATE_TILED_BOTTOM);
    }

    if ((version >= GTK_SURFACE1_STATE_TILED_LEFT_SINCE_VERSION) &&
        (view->pending_tiled_edges() & WLR_EDGE_LEFT))
    {
        append_to_array(&states, GTK_SURFACE1_STATE_TILED_LEFT);
    }

    gtk_surface1_send_configure(surface->resource, &states);
    wl_array_release(&states);
}

/**
 * Tells gtk which edges should be resizable.
 */
static void send_gtk_surface_configure_edges(wf_gtk_surface *surface, wayfire_toplevel_view view)
{
    wl_array edges;
    wl_array_init(&edges);

    if (!view->pending_tiled_edges())
    {
        append_to_array(&edges, GTK_SURFACE1_EDGE_CONSTRAINT_RESIZABLE_TOP);
        append_to_array(&edges, GTK_SURFACE1_EDGE_CONSTRAINT_RESIZABLE_RIGHT);
        append_to_array(&edges, GTK_SURFACE1_EDGE_CONSTRAINT_RESIZABLE_BOTTOM);
        append_to_array(&edges, GTK_SURFACE1_EDGE_CONSTRAINT_RESIZABLE_LEFT);
    }

    gtk_surface1_send_configure_edges(surface->resource, &edges);
    wl_array_release(&edges);
}

/**
 * Augments xdg_surface's configure with additional gtk-specific information.
 */
static void handle_xdg_surface_on_configure(wf_gtk_surface *surface)
{
    wayfire_toplevel_view view = wf::toplevel_cast(wf::wl_surface_to_wayfire_view(surface->wl_surface));
    if (view)
    {
        send_gtk_surface_configure(surface, view);
        if (wl_resource_get_version(surface->resource) >=
            GTK_SURFACE1_CONFIGURE_EDGES_SINCE_VERSION)
        {
            send_gtk_surface_configure_edges(surface, view);
        }
    }
}

/**
 * Prevents a race condition where the xdg_surface is destroyed before
 * the gtk_surface's resource and the gtk_surface's destructor tries to
 * disconnect these signals which causes a use-after-free
 */
static void handle_xdg_surface_on_destroy(wf_gtk_surface *surface)
{
    strata_sheets::modal_surfaces().erase(surface->wl_surface);
    surface->on_configure.disconnect();
    surface->on_destroy.disconnect();
}

/**
 * Destroys the gtk_surface object.
 */
static void handle_gtk_surface_destroy(wl_resource *resource)
{
    auto surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(resource));
    wf::get_core().get_data_safe<strata_shell_data>()->surfaces.erase(surface->wl_surface);
    delete surface;
}

/**
 * Supported functions of the gtk_surface_interface implementation
 */
const struct gtk_surface1_interface gtk_surface1_impl = {
    .set_dbus_properties = handle_gtk_surface_set_dbus_properties,
    .set_modal   = handle_gtk_surface_set_modal,
    .unset_modal = handle_gtk_surface_unset_modal,
    .present     = handle_gtk_surface_present,
    .request_focus = handle_gtk_surface_request_focus,
};

/**
 * Initializes a gtk_surface object and passes it to the client.
 */
static void handle_gtk_shell_get_gtk_surface(wl_client *client, wl_resource *resource,
    uint32_t id, wl_resource *surface)
{
    wf_gtk_surface *gtk_surface = new wf_gtk_surface;
    gtk_surface->resource = wl_resource_create(client, &gtk_surface1_interface,
        wl_resource_get_version(resource), id);
    gtk_surface->wl_surface = surface;
    wl_resource_set_implementation(gtk_surface->resource, &gtk_surface1_impl,
        gtk_surface, handle_gtk_surface_destroy);

    wlr_surface *wlr_surface = wlr_surface_from_resource(surface);
    if (wlr_xdg_surface *xdg_surface = wlr_xdg_surface_try_from_wlr_surface(wlr_surface))
    {
        gtk_surface->on_configure.set_callback([=] (void*)
        {
            handle_xdg_surface_on_configure(gtk_surface);
        });
        gtk_surface->on_configure.connect(&xdg_surface->events.configure);
        gtk_surface->on_destroy.set_callback([=] (void*)
        {
            handle_xdg_surface_on_destroy(gtk_surface);
        });
        gtk_surface->on_destroy.connect(&xdg_surface->events.destroy);
    }
}

/**
 *  Supplements the request_focus() and present()
 *  to prevent focus stealing if user interaction happened
 *  between the time application was called and request_focus was received.
 *  Not implemented.
 */
static void handle_gtk_shell_notify_launch(wl_client *client, wl_resource *resource,
    const char *startup_id)
{}

/**
 *  A view could use this to receive notification when the surface is ready.
 *  Gets the DESKTOP_STARTUP_ID from environment and unsets this env var afterwards
 *  so any child processes don't inherit it.
 *  Not implemented.
 */
static void handle_gtk_shell_set_startup_id(wl_client *client, wl_resource *resource,
    const char *startup_id)
{}

/**
 *  A view could use this to invoke the system bell, be it aural, visual or none at
 * all.
 */
static void handle_gtk_shell_system_bell(wl_client *client, wl_resource *resource,
    wl_resource *surface)
{
    wf::view_system_bell_signal data;
    if (surface)
    {
        auto gtk_surface = static_cast<wf_gtk_surface*>(wl_resource_get_user_data(surface));
        data.view = wf::wl_surface_to_wayfire_view(gtk_surface->wl_surface);
    }

    wf::get_core().emit(&data);

    // freemac: play the alert sound chosen in Dials > Sound. Wayfire itself
    // makes no sound for the bell. A burst of bells (a key held down) plays
    // once, at most every 150 ms.
    static std::chrono::steady_clock::time_point last;
    auto now = std::chrono::steady_clock::now();
    if (now - last >= std::chrono::milliseconds(150))
    {
        last = now;
        wf::get_core().run("freemac-sound alert");
    }
}

/**
 * Supported functions of the gtk_shell_interface implementation
 */
static const struct gtk_shell1_interface gtk_shell1_impl = {
    .get_gtk_surface = handle_gtk_shell_get_gtk_surface,
    .set_startup_id  = handle_gtk_shell_set_startup_id,
    .system_bell     = handle_gtk_shell_system_bell,
    .notify_launch   = handle_gtk_shell_notify_launch,
};


/**
 * Destroy the gtk_shell object.
 * gtk_shell exists as long as the compositor runs.
 */
static void handle_gtk_shell1_destroy(wl_resource *resource)
{}


/**
 * Binds the gtk_shell to wayland.
 */
void bind_gtk_shell1(wl_client *client, void *data, uint32_t version, uint32_t id)
{
    auto resource = wl_resource_create(client, &gtk_shell1_interface, GTK_SHELL_VERSION, id);
    wl_resource_set_implementation(resource, &gtk_shell1_impl, data, handle_gtk_shell1_destroy);

    /* Topline shows the focused app's menus, so GTK apps can leave their
     * menu bar (and old-style app menu) out of the window. */
    wf::option_wrapper_t<bool> global_menus{"strata-shell/global_menus"};
    if (global_menus)
    {
        /* GTK tests these as plain values (caps & value) == value. */
        gtk_shell1_send_capabilities(resource,
            GTK_SHELL1_CAPABILITY_GLOBAL_APP_MENU | GTK_SHELL1_CAPABILITY_GLOBAL_MENU_BAR);
    }
}

class strata_shell_impl : public wf::plugin_interface_t
{
    wf::shared_data::ref_ptr_t<wf::ipc::method_repository_t> method_repository;
    strata_window_places window_places;
    strata_command_key command_key;
    strata_glide::glides_t glides;
    strata_sheets::sheets_t sheets;

    /* strata/app-menus {id}: where the app behind a window publishes its
     * menus on the session bus (org.gtk.Menus / org.gtk.Actions). */
    wf::ipc::method_callback get_app_menus = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        auto view = wf::ipc::find_view_by_id(data["id"]);
        if (!view)
        {
            return wf::ipc::json_error("no such view");
        }

        auto response = wf::ipc::json_ok();
        auto surface  = view->get_wlr_surface();
        auto shell    = wf::get_core().get_data_safe<strata_shell_data>();
        if (surface && shell->surfaces.count(surface->resource))
        {
            auto& p = shell->surfaces[surface->resource];
            response["app-id"]   = p.app_id;
            response["bus-name"] = p.unique_bus_name;
            response["app-menu-path"]    = p.app_menu_path;
            response["menubar-path"]     = p.menubar_path;
            response["window-path"]      = p.window_object_path;
            response["application-path"] = p.application_object_path;
        }

        return response;
    };

    /* strata/minimize-hint {id, x, y, width, height, relative-to}: the
     * rectangle a window shrinks into when minimized, in the coordinates of
     * the view relative-to (Pier's dock) or of the output if none is given. */
    wf::ipc::method_callback set_minimize_hint = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        WFJSON_EXPECT_FIELD(data, "x", number_integer);
        WFJSON_EXPECT_FIELD(data, "y", number_integer);
        WFJSON_EXPECT_FIELD(data, "width", number_integer);
        WFJSON_EXPECT_FIELD(data, "height", number_integer);
        auto toplevel = wf::toplevel_cast(wf::ipc::find_view_by_id(data["id"]));
        if (!toplevel)
        {
            return wf::ipc::json_error("no such window");
        }

        wlr_box hint{data["x"], data["y"], data["width"], data["height"]};
        if (data.contains("relative-to") && data["relative-to"].is_number_integer())
        {
            auto base = wf::ipc::find_view_by_id(data["relative-to"]);
            if (!base)
            {
                return wf::ipc::json_error("no such view to measure from");
            }

            wf::pointf_t origin = base->get_surface_root_node()->to_global({0, 0});
            hint.x += origin.x;
            hint.y += origin.y;
        }

        toplevel->set_minimize_hint(hint);
        return wf::ipc::json_ok();
    };

    /* strata/close {id}: ask a window to close, as its close button does (the
     * app may still ask to save first). Topline's and Pier's Quit use it. */
    wf::ipc::method_callback close_view = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        auto view = wf::ipc::find_view_by_id(data["id"]);
        if (!view || (view->role != wf::VIEW_ROLE_TOPLEVEL))
        {
            return wf::ipc::json_error("no such window");
        }

        view->close();
        return wf::ipc::json_ok();
    };

    /* strata/force-quit {id}: end the program behind a window at once, for an
     * app that has stopped answering (the Force Quit window). Only the
     * user's own programs, and never the compositor itself. */
    wf::ipc::method_callback force_quit_view = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        auto view = wf::ipc::find_view_by_id(data["id"]);
        wl_client *client = view ? view->get_client() : nullptr;
        if (!view || (view->role != wf::VIEW_ROLE_TOPLEVEL) || !client)
        {
            return wf::ipc::json_error("no such window");
        }

        pid_t pid = 0;
        uid_t uid = 0;
        gid_t gid = 0;
        wl_client_get_credentials(client, &pid, &uid, &gid);
        if ((pid <= 1) || (pid == getpid()) || (uid != getuid()))
        {
            return wf::ipc::json_error("not a program of yours");
        }

        if (kill(pid, SIGKILL) != 0)
        {
            return wf::ipc::json_error("couldn't end it");
        }

        auto out = wf::ipc::json_ok();
        out["pid"] = pid;
        return out;
    };

    /* strata/view-pids: which program each app window belongs to, so Gauge
     * can show what an app uses. Only the user's own programs. */
    wf::ipc::method_callback view_pids = [=] (nlohmann::json)
    {
        auto list = nlohmann::json::array();
        for (auto& view : wf::get_core().get_all_views())
        {
            wl_client *client = view->get_client();
            if ((view->role != wf::VIEW_ROLE_TOPLEVEL) || !client)
            {
                continue;
            }

            pid_t pid = 0;
            uid_t uid = 0;
            gid_t gid = 0;
            wl_client_get_credentials(client, &pid, &uid, &gid);
            if ((pid <= 1) || (uid != getuid()))
            {
                continue;
            }

            nlohmann::json one;
            one["id"]  = view->get_id();
            one["pid"] = pid;
            list.push_back(one);
        }

        auto out = wf::ipc::json_ok();
        out["views"] = list;
        return out;
    };

    /* strata/zoom {id}: fill the free part of the screen, or go back; what
     * the zoom button and the Window menu's Zoom do. */
    wf::ipc::method_callback zoom_view = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        auto toplevel = wf::toplevel_cast(wf::ipc::find_view_by_id(data["id"]));
        if (!toplevel)
        {
            return wf::ipc::json_error("no such window");
        }

        wf::get_core().default_wm->tile_request(toplevel,
            toplevel->pending_tiled_edges() ? 0 : wf::TILED_EDGES_ALL);
        return wf::ipc::json_ok();
    };

    /* strata/snapshot {id, path, size}: a small picture of a window, for its
     * place in the Dock while it is minimized. Only under the user's runtime
     * directory, so no other file can be overwritten. */
    wf::ipc::method_callback snapshot_view = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        WFJSON_EXPECT_FIELD(data, "path", string);
        auto view = wf::ipc::find_view_by_id(data["id"]);
        if (!view || (view->role != wf::VIEW_ROLE_TOPLEVEL) || !view->get_output())
        {
            return wf::ipc::json_error("no such window");
        }

        std::string path = data["path"];
        const char *runtime = getenv("XDG_RUNTIME_DIR");
        std::string dir     = std::string(runtime ? runtime : "/nonexistent") + "/freemac-pier/";
        if ((path.rfind(dir, 0) != 0) || (path.find("..") != std::string::npos) ||
            (path.find('/', dir.size()) != std::string::npos))
        {
            return wf::ipc::json_error("pictures go in the dock's own folder");
        }

        int size = 256;
        if (data.contains("size") && data["size"].is_number_integer())
        {
            size = std::clamp((int)data["size"], 16, 1024);
        }

        int width = 0, height = 0;
        std::string failed = strata_snapshot::save(view, path, size, width, height);
        if (!failed.empty())
        {
            return wf::ipc::json_error(failed);
        }

        auto out = wf::ipc::json_ok();
        out["width"]  = width;
        out["height"] = height;
        return out;
    };

    /* strata/hide {id}: hide a window (Hide in the menu bar and the Dock). */
    wf::ipc::method_callback hide_view = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "id", number_integer);
        auto toplevel = wf::toplevel_cast(wf::ipc::find_view_by_id(data["id"]));
        if (!toplevel)
        {
            return wf::ipc::json_error("no such window");
        }

        strata_hidden::hide(toplevel);
        return wf::ipc::json_ok();
    };

    /* strata/hidden: the ids of the windows hidden now. */
    wf::ipc::method_callback list_hidden = [=] (nlohmann::json)
    {
        auto out = wf::ipc::json_ok();
        out["ids"] = nlohmann::json::array();
        for (auto id : strata_hidden::current())
        {
            out["ids"].push_back(id);
        }

        return out;
    };

    /* strata/command-key {app-id, raw}: while raw, the app's windows get the
     * keys as they are, with no Command key (Dials, as it records a new
     * shortcut). */
    wf::ipc::method_callback set_command_key_raw = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "app-id", string);
        WFJSON_EXPECT_FIELD(data, "raw", boolean);
        command_key.set_raw(data["app-id"], data["raw"]);
        return wf::ipc::json_ok();
    };

    /* strata/front-app {app-id, keys}: the app Topline shows in front with
     * no window open, or "" for none; ⌘Q quits it, and its keys work. */
    wf::ipc::method_callback set_front_app = [=] (nlohmann::json data)
    {
        if (data.contains("app-id"))
        {
            WFJSON_EXPECT_FIELD(data, "app-id", string);
            command_key.front_windowless = data["app-id"];
        }

        /* keys {chord: action}: the app's own shortcuts, for while it has
         * no window open. */
        if (data.contains("keys") && data["keys"].is_object() && data.contains("app-id"))
        {
            command_key.windowless_keys.clear();
            command_key.windowless_keys_app = data["app-id"];
            for (auto& [chord, action] : data["keys"].items())
            {
                if (action.is_string() && (command_key.windowless_keys.size() < 200))
                {
                    command_key.windowless_keys[chord] = action;
                }
            }
        }

        /* Without an app-id it only answers: Strata itself keeps an app in
         * front when its last window closes, and Topline asks which. */
        auto out = wf::ipc::json_ok();
        out["app-id"] = command_key.front_windowless;
        return out;
    };

    /* strata/press {key, ctrl, shift, alt}: press a key (an evdev code) in
     * the window that has the keyboard. */
    wf::ipc::method_callback press_key = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "key", number_unsigned);
        auto flag = [&] (const char *name)
        {
            return data.contains(name) && data[name].is_boolean() && data[name].get<bool>();
        };
        if (!command_key.press(data["key"].get<uint32_t>(), flag("ctrl"), flag("shift"), flag("alt")))
        {
            return wf::ipc::json_error("no window has the keyboard");
        }

        return wf::ipc::json_ok();
    };

    /* strata/held-modifiers: which of Command, Alt, Control and Shift are
     * held down right now. */
    wf::ipc::method_callback get_held_modifiers = [=] (nlohmann::json)
    {
        auto out = wf::ipc::json_ok();
        out["held"] = command_key.held_modifiers();
        return out;
    };

    /* The keyboards plugged in now (a laptop's own and any USB ones). */
    static std::vector<wlr_keyboard*> keyboards()
    {
        std::vector<wlr_keyboard*> found;
        for (auto& device : wf::get_core().get_input_devices())
        {
            auto handle = device->get_wlr_handle();
            if (handle && (handle->type == WLR_INPUT_DEVICE_KEYBOARD))
            {
                found.push_back(wlr_keyboard_from_input_device(handle));
            }
        }

        return found;
    }

    /* strata/input-source {index?}: the input sources (XKB layouts) with
     * their names and which one is in use; with index, switch every keyboard
     * to that one first. */
    wf::ipc::method_callback input_source = [=] (nlohmann::json data)
    {
        auto all = keyboards();
        wlr_keyboard *kbd = nullptr;
        if (auto seat = wf::get_core().get_current_seat())
        {
            kbd = wlr_seat_get_keyboard(seat);
        }

        if (!kbd && !all.empty())
        {
            kbd = all.front();
        }

        if (!kbd || !kbd->keymap)
        {
            return wf::ipc::json_error("no keyboard");
        }

        xkb_layout_index_t count = xkb_keymap_num_layouts(kbd->keymap);
        if (data.contains("index"))
        {
            WFJSON_EXPECT_FIELD(data, "index", number_unsigned);
            auto index = data["index"].get<uint32_t>();
            if (index >= count)
            {
                return wf::ipc::json_error("no such input source");
            }

            for (auto keyboard : all)
            {
                if (keyboard->keymap && (index < xkb_keymap_num_layouts(keyboard->keymap)))
                {
                    wlr_keyboard_notify_modifiers(keyboard, keyboard->modifiers.depressed,
                        keyboard->modifiers.latched, keyboard->modifiers.locked, index);
                }
            }
        }

        auto out = wf::ipc::json_ok();
        out["names"] = nlohmann::json::array();
        for (xkb_layout_index_t i = 0; i < count; i++)
        {
            const char *name = xkb_keymap_layout_get_name(kbd->keymap, i);
            out["names"].push_back(name ? name : "");
        }

        out["index"] = kbd->xkb_state ?
            xkb_state_serialize_layout(kbd->xkb_state, XKB_STATE_LAYOUT_EFFECTIVE) : 0;
        return out;
    };

    /* strata/outputs: every display the computer has, with the modes it
     * can show, for Dials > Displays. Dials changes a display by writing
     * [output:NAME] in wayfire.ini, which Wayfire applies at once. */
    wf::ipc::method_callback list_outputs = [=] (nlohmann::json)
    {
        auto out = wf::ipc::json_ok();
        out["outputs"] = nlohmann::json::array();
        for (auto& [handle, state] : wf::get_core().output_layout->get_current_configuration())
        {
            nlohmann::json o;
            o["name"]  = handle->name ? handle->name : "";
            o["make"]  = handle->make ? handle->make : "";
            o["model"] = handle->model ? handle->model : "";
            o["serial"] = handle->serial ? handle->serial : "";
            o["description"] = handle->description ? handle->description : "";
            o["physical"] = {handle->phys_width, handle->phys_height};
            o["built_in"] = wlr_output_is_drm(handle) && handle->name &&
                (std::string(handle->name).rfind("eDP", 0) == 0 ||
                 std::string(handle->name).rfind("LVDS", 0) == 0 ||
                 std::string(handle->name).rfind("DSI", 0) == 0);
            switch (state.source)
            {
              case wf::OUTPUT_IMAGE_SOURCE_SELF:
                o["source"] = "self";
                break;

              case wf::OUTPUT_IMAGE_SOURCE_MIRROR:
                o["source"] = "mirror";
                break;

              case wf::OUTPUT_IMAGE_SOURCE_DPMS:
                o["source"] = "dpms";
                break;

              default:
                o["source"] = "off";
            }

            o["mirror_from"] = state.mirror_from;
            o["width"]   = handle->width;
            o["height"]  = handle->height;
            o["refresh"] = handle->refresh;
            o["scale"]   = state.scale;
            o["transform"] = (int)state.transform;
            o["x"] = 0;
            o["y"] = 0;
            if (auto wo = wf::get_core().output_layout->find_output(handle))
            {
                auto geometry = wo->get_layout_geometry();
                o["x"] = geometry.x;
                o["y"] = geometry.y;
                o["layout_width"]  = geometry.width;
                o["layout_height"] = geometry.height;
            }

            o["modes"] = nlohmann::json::array();
            wlr_output_mode *mode;
            wl_list_for_each(mode, &handle->modes, link)
            {
                o["modes"].push_back({{"width", mode->width}, {"height", mode->height},
                    {"refresh", mode->refresh}, {"preferred", mode->preferred}});
            }

            out["outputs"].push_back(o);
        }

        return out;
    };

    strata_flash::flashes_t flashes;
    strata_spaces::spaces_t spaces;
    strata_attention::attention_t attention;
    strata_locate::locate_t locate;
    strata_accents::hold_t accents;
    strata_sticky::sticky_t sticky;
    strata_hover::hover_t hover_text;
    strata_filters::filters_t colour_filters;

    /* strata/accent-type {text}: Topline's press-and-hold panel picked an
     * accent; type it in place of the held letter. typed is false when the
     * app has no text field Strata can type into (Topline then types it). */
    wf::ipc::method_callback accent_type = [=] (nlohmann::json data)
    {
        WFJSON_EXPECT_FIELD(data, "text", string);
        auto out = wf::ipc::json_ok();
        out["typed"] = accents.type(data["text"]);
        return out;
    };

    /* strata/accent-closed: the panel has gone, so the number keys and the
     * arrows go to the app again. */
    wf::ipc::method_callback accent_closed = [=] (nlohmann::json)
    {
        accents.closed();
        return wf::ipc::json_ok();
    };

    /* Flash every display once, for "Flash the screen when an alert sound
     * occurs". The alert sound's player calls it. */
    wf::ipc::method_callback flash_screen = [=] (nlohmann::json)
    {
        flashes.flash();
        return wf::ipc::json_ok();
    };

    /* strata/keep-awake {"on": true|false}: while something needs the
     * computer awake (a video playing, caffeinate), it isn't counted as idle,
     * so the screen stays on and neither the screen saver nor the lock comes.
     * freemac-lock --watch asks, on behalf of every app that asks it
     * (shell/freemac_shell/awake.py). */
    std::unique_ptr<wf::idle_inhibitor_t> awake;
    wf::ipc::method_callback keep_awake = [=] (nlohmann::json data)
    {
        if (!data.contains("on") || !data["on"].is_boolean())
        {
            return wf::ipc::json_error("\"on\" must be true or false");
        }

        if (data["on"].get<bool>())
        {
            if (!awake)
            {
                awake = std::make_unique<wf::idle_inhibitor_t>();
            }
        } else
        {
            awake.reset();
        }

        auto out = wf::ipc::json_ok();
        out["on"] = (bool)awake;
        return out;
    };

    /* strata/pointer: where the pointer is, in the layout's coordinates, and
     * the app window under it (view 0 when none). Topline asks when the
     * pointer rests on an app's own green button, which only the app sees. */
    wf::ipc::method_callback pointer = [=] (nlohmann::json)
    {
        auto at  = wf::get_core().get_cursor_position();
        auto out = wf::ipc::json_ok();
        out["x"]    = (int)at.x;
        out["y"]    = (int)at.y;
        out["view"] = 0;
        if (auto view = wf::get_core().get_cursor_focus_view())
        {
            view = wf::find_topmost_parent(view);
            if (view && (view->role == wf::VIEW_ROLE_TOPLEVEL))
            {
                out["view"] = view->get_id();
            }
        }

        return out;
    };

    /* Command-F5 turns the screen reader on or off, as VoiceOver's key does
     * on a Mac (1.120). An option here, not a [command] binding, so a
     * wayfire.ini from before 1.120 gets it too. */
    wf::option_wrapper_t<wf::activatorbinding_t> screen_reader_key{"strata-shell/screen_reader"};
    wf::activator_callback on_screen_reader = [=] (const wf::activator_data_t&)
    {
        wf::get_core().run("freemac-screen-reader --toggle");
        return true;
    };

  public:
    void init() override
    {
        auto display = wf::get_core().display;
        wl_global_create(display, &gtk_shell1_interface, GTK_SHELL_VERSION, NULL, bind_gtk_shell1);
        wf::get_core().connect(&on_app_id_query);
        method_repository->register_method("strata/app-menus", get_app_menus);
        method_repository->register_method("strata/minimize-hint", set_minimize_hint);
        method_repository->register_method("strata/close", close_view);
        method_repository->register_method("strata/command-key", set_command_key_raw);
        method_repository->register_method("strata/held-modifiers", get_held_modifiers);
        method_repository->register_method("strata/front-app", set_front_app);
        method_repository->register_method("strata/press", press_key);
        method_repository->register_method("strata/zoom", zoom_view);
        method_repository->register_method("strata/force-quit", force_quit_view);
        method_repository->register_method("strata/view-pids", view_pids);
        method_repository->register_method("strata/snapshot", snapshot_view);
        method_repository->register_method("strata/hide", hide_view);
        method_repository->register_method("strata/hidden", list_hidden);
        method_repository->register_method("strata/input-source", input_source);
        method_repository->register_method("strata/outputs", list_outputs);
        method_repository->register_method("strata/flash", flash_screen);
        method_repository->register_method("strata/pointer", pointer);
        method_repository->register_method("strata/keep-awake", keep_awake);
        method_repository->register_method("strata/accent-type", accent_type);
        method_repository->register_method("strata/accent-closed", accent_closed);
        method_repository->register_method("strata/hover-cursor",
            [=] (nlohmann::json data) { return hover_text.cursor(data); });
        method_repository->register_method("strata/desktops",
            [=] (nlohmann::json data) { return spaces.desktops(data); });
        method_repository->register_method("strata/spaces-areas",
            [=] (nlohmann::json data) { return spaces.set_areas(data); });
        method_repository->register_method("strata/assign",
            [=] (nlohmann::json data) { return spaces.assign(data); });
        method_repository->register_method("strata/assignments",
            [=] (nlohmann::json data) { return spaces.assignments(data); });
        method_repository->register_method("strata/app-expose",
            [=] (nlohmann::json data) { return spaces.app_expose(data); });
        method_repository->register_method("strata/attention",
            [=] (nlohmann::json data) { return attention.list(data); });
        attention.init();
        flashes.init();
        locate.init();
        window_places.init();
        command_key.init();
        accents.init();
        sticky.init(&strata_accents::strata_tell_topline);
        hover_text.init(&strata_accents::strata_tell_topline);
        colour_filters.init();
        spaces.init(&strata_accents::strata_tell_topline);
        glides.init();
        sheets.init();
        wf::get_core().bindings->add_activator(screen_reader_key, &on_screen_reader);
    }

    bool is_unloadable() override
    {
        return false;
    }

    wf::signal::connection_t<gtk_shell_app_id_query_signal> on_app_id_query =
        [=] (gtk_shell_app_id_query_signal *ev)
    {
        if (auto surface = ev->view->get_wlr_surface())
        {
            auto shell = wf::get_core().get_data_safe<strata_shell_data>();
            auto it    = shell->surfaces.find(surface->resource);
            if (it != shell->surfaces.end())
            {
                ev->app_id = it->second.app_id;
            }
        }
    };
};

DECLARE_WAYFIRE_PLUGIN(strata_shell_impl);
