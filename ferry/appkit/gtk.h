/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The parts of this system's GTK 3 that Ferry's AppKit calls to put windows
 * on screen. GTK speaks Wayland to the compositor (or X11, where that is
 * what the session runs), and gives AppKit toplevel windows with the
 * compositor's decorations, input, scaling and clipboard. AppKit draws each
 * window's content itself, with Ferry's Core Graphics, into one GTK drawing
 * area per window.
 *
 * As in graphics/host.h, these declarations are written from GTK's, GDK's
 * and GLib's published API documentation, because the Mac build can't
 * include Linux headers, and Ferry's loader serves them (see src/host.c)
 * under the name /usr/lib/ferry/libFerryHost.dylib. Events are read with
 * GDK's accessor calls, so no event structure layout is relied on.
 */
#ifndef FERRY_APPKIT_GTK_H
#define FERRY_APPKIT_GTK_H
#include <stdint.h>
#include "../graphics/host.h"

typedef int gboolean;
typedef struct _GtkWidget GtkWidget;
typedef struct _GdkEvent GdkEvent;
typedef struct _GdkDisplay GdkDisplay;
typedef struct _GdkMonitor GdkMonitor;
typedef struct _GMainContext GMainContext;
typedef struct { int x, y, width, height; } GdkRectangle;
/* The same layout as struct pollfd, and GLib's G_IO_IN and friends have
 * poll's values, so the two are used interchangeably. */
typedef struct { int fd; unsigned short events, revents; } GPollFD;
typedef void (*GCallback)(void);

enum { GTK_WINDOW_TOPLEVEL = 0 };
enum {
    GDK_POINTER_MOTION_MASK = 1 << 2, GDK_BUTTON_PRESS_MASK = 1 << 8, GDK_BUTTON_RELEASE_MASK = 1 << 9,
    GDK_KEY_PRESS_MASK = 1 << 10, GDK_KEY_RELEASE_MASK = 1 << 11, GDK_ENTER_NOTIFY_MASK = 1 << 12,
    GDK_LEAVE_NOTIFY_MASK = 1 << 13, GDK_FOCUS_CHANGE_MASK = 1 << 14, GDK_STRUCTURE_MASK = 1 << 15,
    GDK_SCROLL_MASK = 1 << 21, GDK_SMOOTH_SCROLL_MASK = 1 << 23,
};
enum {
    GDK_SHIFT_MASK = 1 << 0, GDK_LOCK_MASK = 1 << 1, GDK_CONTROL_MASK = 1 << 2, GDK_MOD1_MASK = 1 << 3,
    GDK_MOD2_MASK = 1 << 4, GDK_BUTTON1_MASK = 1 << 8, GDK_BUTTON2_MASK = 1 << 9, GDK_BUTTON3_MASK = 1 << 10,
    GDK_SUPER_MASK = 1 << 26, GDK_HYPER_MASK = 1 << 27, GDK_META_MASK = 1 << 28,
};
enum { GDK_BUTTON_PRESS = 4, GDK_2BUTTON_PRESS = 5, GDK_3BUTTON_PRESS = 6, GDK_BUTTON_RELEASE = 7 };
enum { GDK_SCROLL_UP, GDK_SCROLL_DOWN, GDK_SCROLL_LEFT, GDK_SCROLL_RIGHT, GDK_SCROLL_SMOOTH };

/* Cairo, beyond what Core Graphics uses */
typedef cairo_status_t (*cairo_write_func_t)(void *closure, const unsigned char *data, unsigned int length);
cairo_status_t cairo_surface_write_to_png_stream(cairo_surface_t *surface, cairo_write_func_t write, void *closure);
void cairo_surface_set_device_scale(cairo_surface_t *surface, double x, double y);

/* GLib and GObject */
GMainContext *g_main_context_default(void);
gboolean g_main_context_acquire(GMainContext *context);
gboolean g_main_context_prepare(GMainContext *context, int *priority);
int g_main_context_query(GMainContext *context, int max_priority, int *timeout, GPollFD *fds, int n_fds);
gboolean g_main_context_check(GMainContext *context, int max_priority, GPollFD *fds, int n_fds);
void g_main_context_dispatch(GMainContext *context);
gboolean g_main_context_iteration(GMainContext *context, gboolean may_block);
unsigned long g_signal_connect_data(void *instance, const char *signal, GCallback handler, void *data,
                                    void *destroy_data, int flags);
void g_set_prgname(const char *name);
void g_set_application_name(const char *name);

/* GTK */
gboolean gtk_init_check(int *argc, char ***argv);
GtkWidget *gtk_window_new(int type);
void gtk_window_set_title(GtkWidget *window, const char *title);
void gtk_window_set_default_size(GtkWidget *window, int width, int height);
void gtk_window_resize(GtkWidget *window, int width, int height);
void gtk_window_present(GtkWidget *window);
void gtk_window_set_resizable(GtkWidget *window, gboolean resizable);
void gtk_window_set_decorated(GtkWidget *window, gboolean decorated);
void gtk_window_set_deletable(GtkWidget *window, gboolean deletable);
void gtk_window_iconify(GtkWidget *window);
void gtk_window_deiconify(GtkWidget *window);
void gtk_window_maximize(GtkWidget *window);
void gtk_window_unmaximize(GtkWidget *window);
GtkWidget *gtk_drawing_area_new(void);
void gtk_container_add(GtkWidget *container, GtkWidget *widget);
void gtk_widget_show_all(GtkWidget *widget);
void gtk_widget_hide(GtkWidget *widget);
void gtk_widget_destroy(GtkWidget *widget);
void gtk_widget_add_events(GtkWidget *widget, int events);
void gtk_widget_set_can_focus(GtkWidget *widget, gboolean can_focus);
void gtk_widget_grab_focus(GtkWidget *widget);
void gtk_widget_queue_draw(GtkWidget *widget);
int gtk_widget_get_allocated_width(GtkWidget *widget);
int gtk_widget_get_allocated_height(GtkWidget *widget);
int gtk_widget_get_scale_factor(GtkWidget *widget);
void gtk_widget_set_size_request(GtkWidget *widget, int width, int height);

/* GDK */
GdkDisplay *gdk_display_get_default(void);
int gdk_display_get_n_monitors(GdkDisplay *display);
GdkMonitor *gdk_display_get_monitor(GdkDisplay *display, int n);
GdkMonitor *gdk_display_get_primary_monitor(GdkDisplay *display);
void gdk_display_beep(GdkDisplay *display);
void gdk_monitor_get_geometry(GdkMonitor *monitor, GdkRectangle *geometry);
void gdk_monitor_get_workarea(GdkMonitor *monitor, GdkRectangle *workarea);
int gdk_monitor_get_scale_factor(GdkMonitor *monitor);
int gdk_event_get_event_type(const GdkEvent *event);
uint32_t gdk_event_get_time(const GdkEvent *event);
gboolean gdk_event_get_state(const GdkEvent *event, unsigned *state);
gboolean gdk_event_get_coords(const GdkEvent *event, double *x, double *y);
gboolean gdk_event_get_button(const GdkEvent *event, unsigned *button);
gboolean gdk_event_get_keyval(const GdkEvent *event, unsigned *keyval);
gboolean gdk_event_get_keycode(const GdkEvent *event, uint16_t *keycode);
gboolean gdk_event_get_scroll_direction(const GdkEvent *event, int *direction);
gboolean gdk_event_get_scroll_deltas(const GdkEvent *event, double *dx, double *dy);
uint32_t gdk_keyval_to_unicode(unsigned keyval);
unsigned gdk_keyval_to_lower(unsigned keyval);

/* Clipboard, file choosers and drops (M7) */
typedef void *GdkAtom;
typedef struct _GtkClipboard GtkClipboard;
typedef struct _GtkFileChooser GtkFileChooser;
typedef struct _GtkFileFilter GtkFileFilter;
typedef struct _GtkFileChooserNative GtkFileChooserNative;
typedef struct _GdkDragContext GdkDragContext;
typedef struct _GtkSelectionData GtkSelectionData;
typedef struct _GList { void *data; struct _GList *next, *prev; } GList;
typedef struct { char *target; unsigned flags, info; } GtkTargetEntry;
enum { GTK_FILE_CHOOSER_ACTION_OPEN = 0, GTK_FILE_CHOOSER_ACTION_SAVE = 1,
       GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER = 2 };
enum { GTK_RESPONSE_ACCEPT = -3, GTK_RESPONSE_CANCEL = -6 };
enum { GDK_ACTION_DEFAULT = 1 << 0, GDK_ACTION_COPY = 1 << 1, GDK_ACTION_MOVE = 1 << 2, GDK_ACTION_LINK = 1 << 3,
       GDK_ACTION_PRIVATE = 1 << 4, GDK_ACTION_ASK = 1 << 5 };
void gtk_window_set_default_icon(GdkPixbuf *icon);
void *gdk_display_get_default_seat(GdkDisplay *display);
GdkAtom gdk_atom_intern(const char *name, gboolean only_if_exists);
char *gdk_atom_name(GdkAtom atom);
GtkClipboard *gtk_clipboard_get(GdkAtom selection);
void gtk_clipboard_set_text(GtkClipboard *clipboard, const char *text, int len);
char *gtk_clipboard_wait_for_text(GtkClipboard *clipboard);
char **gtk_clipboard_wait_for_uris(GtkClipboard *clipboard);
GdkPixbuf *gtk_clipboard_wait_for_image(GtkClipboard *clipboard);
void gtk_clipboard_set_image(GtkClipboard *clipboard, GdkPixbuf *pixbuf);
void g_strfreev(char **strv);
char *g_filename_from_uri(const char *uri, char **hostname, void *error);
GtkFileChooserNative *gtk_file_chooser_native_new(const char *title, GtkWidget *parent, int action,
                                                  const char *accept_label, const char *cancel_label);
int gtk_native_dialog_run(void *dialog);
void gtk_file_chooser_set_select_multiple(void *chooser, gboolean select_multiple);
void gtk_file_chooser_set_do_overwrite_confirmation(void *chooser, gboolean confirm);
void gtk_file_chooser_set_create_folders(void *chooser, gboolean create_folders);
void gtk_file_chooser_set_show_hidden(void *chooser, gboolean show_hidden);
gboolean gtk_file_chooser_set_current_folder(void *chooser, const char *filename);
void gtk_file_chooser_set_current_name(void *chooser, const char *name);
GSList *gtk_file_chooser_get_filenames(void *chooser);
void gtk_file_chooser_add_filter(void *chooser, GtkFileFilter *filter);
GtkFileFilter *gtk_file_filter_new(void);
void gtk_file_filter_set_name(GtkFileFilter *filter, const char *name);
void gtk_file_filter_add_pattern(GtkFileFilter *filter, const char *pattern);
void g_slist_free(GSList *list);
void gtk_drag_dest_set(GtkWidget *widget, int flags, const GtkTargetEntry *targets, int n_targets, int actions);
void gtk_drag_dest_unset(GtkWidget *widget);
GdkAtom gtk_drag_dest_find_target(GtkWidget *widget, GdkDragContext *context, void *target_list);
void gtk_drag_get_data(GtkWidget *widget, GdkDragContext *context, GdkAtom target, uint32_t time);
void gtk_drag_finish(GdkDragContext *context, gboolean success, gboolean del, uint32_t time);
void gdk_drag_status(GdkDragContext *context, int action, uint32_t time);
int gdk_drag_context_get_actions(GdkDragContext *context);
char **gtk_selection_data_get_uris(const GtkSelectionData *data);
unsigned char *gtk_selection_data_get_text(const GtkSelectionData *data);

#endif
