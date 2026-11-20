// Strata's copy of Wayfire's gtk-shell plugin. Besides what gtk-shell does, it
// keeps the menu addresses GTK apps publish (Wayfire's plugin drops them),
// hands them to Topline over IPC (strata/app-menus), and tells GTK apps that
// the desktop shows their menu bar, so they leave it out of the window. It
// also lets Pier say where each window's dock icon is (strata/minimize-hint),
// so minimizing a window shrinks it into that icon and restoring grows it back,
// and closes windows on request (strata/close) for Quit in the menu bar and dock.
#include "gtk-shell-protocol.h"
#include "wayfire/core.hpp"
#include "wayfire/object.hpp"
#include <map>
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

#include "gtk-shell.hpp"
#include "window-places.hpp"
#include "command-key.hpp"

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
        window_places.init();
        command_key.init();
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
