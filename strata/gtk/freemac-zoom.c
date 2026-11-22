// SPDX-License-Identifier: GPL-3.0-or-later
// A GTK 3 module that lets an app's own green button open freemac's
// Move & Resize menu, as resting on a Mac's green button does. GTK apps
// draw their own title bar, so only the app knows the pointer is on the
// button: this module tells Topline "hover PID" when it arrives and
// "unhover PID" when it goes or the button is pressed. Topline asks Strata
// where the pointer is and which window is under it, and opens the menu.
//
// freemac-session loads it into every GTK 3 app through GTK_MODULES.
// Original freemac code.
#include <errno.h>
#include <fcntl.h>
#include <gtk/gtk.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static void tell_topline(const char *word)
{
    const char *runtime = g_getenv("XDG_RUNTIME_DIR");
    if (!runtime)
    {
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    if (snprintf(addr.sun_path, sizeof(addr.sun_path), "%s/freemac-topline.sock", runtime) >=
        (int)sizeof(addr.sun_path))
    {
        return;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0)
    {
        return;
    }

    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) == 0)
    {
        char line[64];
        int length = snprintf(line, sizeof(line), "%s %d\n", word, (int)getpid());
        (void)!send(fd, line, length, MSG_NOSIGNAL);
    }

    close(fd);
}

static gboolean on_enter(GtkWidget *button, GdkEventCrossing *event, gpointer data)
{
    (void)button;
    (void)data;
    if (event->detail != GDK_NOTIFY_INFERIOR)
    {
        tell_topline("hover");
    }

    return FALSE;
}

static gboolean on_leave(GtkWidget *button, GdkEventCrossing *event, gpointer data)
{
    (void)button;
    (void)data;
    if (event->detail != GDK_NOTIFY_INFERIOR)
    {
        tell_topline("unhover");
    }

    return FALSE;
}

static gboolean on_press(GtkWidget *button, GdkEvent *event, gpointer data)
{
    (void)button;
    (void)event;
    (void)data;
    tell_topline("unhover");
    return FALSE;
}

/* Every widget that is shown passes through here once; only a title bar's
 * maximize button (GtkHeaderBar's, styled "titlebutton maximize") is
 * watched. */
static gboolean on_map(GSignalInvocationHint *hint, guint count, const GValue *values, gpointer data)
{
    (void)hint;
    (void)data;
    if (count < 1)
    {
        return TRUE;
    }

    GObject *object = g_value_get_object(&values[0]);
    if (!GTK_IS_BUTTON(object) || g_object_get_data(object, "freemac-zoom"))
    {
        return TRUE;
    }

    GtkStyleContext *style = gtk_widget_get_style_context(GTK_WIDGET(object));
    if (!gtk_style_context_has_class(style, "titlebutton") ||
        !gtk_style_context_has_class(style, "maximize"))
    {
        return TRUE;
    }

    g_object_set_data(object, "freemac-zoom", GINT_TO_POINTER(1));
    gtk_widget_add_events(GTK_WIDGET(object), GDK_ENTER_NOTIFY_MASK | GDK_LEAVE_NOTIFY_MASK);
    g_signal_connect(object, "enter-notify-event", G_CALLBACK(on_enter), NULL);
    g_signal_connect(object, "leave-notify-event", G_CALLBACK(on_leave), NULL);
    g_signal_connect(object, "button-press-event", G_CALLBACK(on_press), NULL);
    return TRUE;
}

G_MODULE_EXPORT void gtk_module_init(gint *argc, gchar ***argv)
{
    (void)argc;
    (void)argv;
    /* Only on Wayland, where Strata is the compositor. */
    GdkDisplay *display = gdk_display_get_default();
    if (display && strcmp(G_OBJECT_TYPE_NAME(display), "GdkWaylandDisplay") != 0)
    {
        return;
    }

    /* The class has to exist before its signals can be looked up. */
    g_type_class_unref(g_type_class_ref(GTK_TYPE_WIDGET));
    guint map = g_signal_lookup("map", GTK_TYPE_WIDGET);
    if (map)
    {
        g_signal_add_emission_hook(map, 0, on_map, NULL, NULL);
    }
}
