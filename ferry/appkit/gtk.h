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

/* GIO's D-Bus calls, for menu bar items (NSStatusBar.m): the desktop's
 * StatusNotifierItem and dbusmenu protocols. GVariant values are built with
 * the constructors that take no format string. A GVariantType is its type
 * string, so a type is passed as a string such as "a{sv}". */
typedef struct _GVariant GVariant;
typedef struct _GDBusConnection GDBusConnection;
typedef struct _GDBusMethodInvocation GDBusMethodInvocation;
typedef struct _GDBusNodeInfo GDBusNodeInfo;
typedef struct _GDBusInterfaceInfo GDBusInterfaceInfo;
typedef void (*GDBusMethodCall)(GDBusConnection *connection, const char *sender, const char *path,
                                const char *iface, const char *method, GVariant *parameters,
                                GDBusMethodInvocation *invocation, void *data);
typedef GVariant *(*GDBusGetProperty)(GDBusConnection *connection, const char *sender, const char *path,
                                      const char *iface, const char *property, GError **error, void *data);
typedef struct {
    GDBusMethodCall method_call;
    GDBusGetProperty get_property;
    void *set_property;
    void *padding[8];
} GDBusInterfaceVTable;
typedef void (*GDBusSignalCallback)(GDBusConnection *connection, const char *sender, const char *path,
                                    const char *iface, const char *signal, GVariant *parameters, void *data);
enum { G_BUS_TYPE_SESSION = 2 };
GDBusConnection *g_bus_get_sync(int bus_type, void *cancellable, GError **error);
GDBusNodeInfo *g_dbus_node_info_new_for_xml(const char *xml, GError **error);
GDBusInterfaceInfo *g_dbus_node_info_lookup_interface(GDBusNodeInfo *info, const char *name);
unsigned g_dbus_connection_register_object(GDBusConnection *connection, const char *path, GDBusInterfaceInfo *iface,
                                           const GDBusInterfaceVTable *vtable, void *data, void *free_data,
                                           GError **error);
gboolean g_dbus_connection_unregister_object(GDBusConnection *connection, unsigned id);
gboolean g_dbus_connection_emit_signal(GDBusConnection *connection, const char *destination, const char *path,
                                       const char *iface, const char *signal, GVariant *parameters, GError **error);
void g_dbus_connection_call(GDBusConnection *connection, const char *name, const char *path, const char *iface,
                            const char *method, GVariant *parameters, const char *reply_type, int flags,
                            int timeout_ms, void *cancellable, void *callback, void *data);
GVariant *g_dbus_connection_call_sync(GDBusConnection *connection, const char *name, const char *path,
                                      const char *iface, const char *method, GVariant *parameters,
                                      const char *reply_type, int flags, int timeout_ms, void *cancellable,
                                      GError **error);
unsigned g_dbus_connection_signal_subscribe(GDBusConnection *connection, const char *sender, const char *iface,
                                            const char *member, const char *path, const char *arg0, int flags,
                                            GDBusSignalCallback callback, void *data, void *free_data);
void g_dbus_method_invocation_return_value(GDBusMethodInvocation *invocation, GVariant *value);
void g_dbus_method_invocation_return_dbus_error(GDBusMethodInvocation *invocation, const char *name,
                                                const char *message);
GVariant *g_variant_new_string(const char *string);
GVariant *g_variant_new_object_path(const char *path);
GVariant *g_variant_new_int32(int32_t value);
GVariant *g_variant_new_uint32(uint32_t value);
GVariant *g_variant_new_boolean(gboolean value);
GVariant *g_variant_new_variant(GVariant *value);
GVariant *g_variant_new_tuple(GVariant *const *children, size_t n);
GVariant *g_variant_new_array(const char *child_type, GVariant *const *children, size_t n);
GVariant *g_variant_new_dict_entry(GVariant *key, GVariant *value);
GVariant *g_variant_new_fixed_array(const char *element_type, const void *elements, size_t n, size_t element_size);
GVariant *g_variant_get_child_value(GVariant *value, size_t index);
size_t g_variant_n_children(GVariant *value);
int32_t g_variant_get_int32(GVariant *value);
const char *g_variant_get_string(GVariant *value, size_t *length);
gboolean g_variant_is_of_type(GVariant *value, const char *type);
void g_variant_unref(GVariant *value);

/* Sheets that don't fit in their window (NSWindow.m), the icon theme
 * (NSWorkspace.m), the desktop's recent files (NSDocumentController.m), and
 * starting the desktop's own launcher with no shell between (NSWorkspace.m).
 * GIO's content types say which icon a kind of file has; a GIcon from it
 * is a GThemedIcon, whose names are tried in turn. */
typedef struct _GtkIconTheme GtkIconTheme;
typedef struct _GtkRecentManager GtkRecentManager;
typedef struct _GIcon GIcon;
enum { GTK_ICON_LOOKUP_FORCE_SIZE = 1 << 4 };
enum { G_SPAWN_SEARCH_PATH = 1 << 2, G_SPAWN_STDOUT_TO_DEV_NULL = 1 << 3, G_SPAWN_STDERR_TO_DEV_NULL = 1 << 4 };
void gtk_window_set_transient_for(GtkWidget *window, GtkWidget *parent);
void gtk_window_set_modal(GtkWidget *window, gboolean modal);
GtkIconTheme *gtk_icon_theme_get_default(void);
GtkIconTheme *gtk_icon_theme_new(void);
void gtk_icon_theme_set_custom_theme(GtkIconTheme *theme, const char *name);
gboolean gtk_icon_theme_has_icon(GtkIconTheme *theme, const char *name);
GdkPixbuf *gtk_icon_theme_load_icon(GtkIconTheme *theme, const char *name, int size, int flags, GError **error);
GtkRecentManager *gtk_recent_manager_get_default(void);
gboolean gtk_recent_manager_add_item(GtkRecentManager *manager, const char *uri);
char *g_content_type_guess(const char *filename, const unsigned char *data, size_t size, gboolean *uncertain);
char *g_content_type_get_generic_icon_name(const char *type);
GIcon *g_content_type_get_icon(const char *type);
const char *const *g_themed_icon_get_names(GIcon *icon);
gboolean g_spawn_async(const char *working_directory, char **argv, char **envp, int flags, void *child_setup,
                       void *user_data, int *child_pid, GError **error);
char *g_find_program_in_path(const char *program);
char *g_filename_to_uri(const char *filename, const char *hostname, GError **error);

/* The colour panel (NSColorWell.m): GTK's colour chooser dialog, shown
 * without blocking; and a sound player that is waited for (NSSound.m). */
typedef struct { double red, green, blue, alpha; } GdkRGBA;
enum { GTK_RESPONSE_OK = -5, GTK_RESPONSE_DELETE_EVENT = -4 };
enum { G_SPAWN_DO_NOT_REAP_CHILD = 1 << 1 };
GtkWidget *gtk_color_chooser_dialog_new(const char *title, GtkWidget *parent);
void gtk_color_chooser_set_rgba(void *chooser, const GdkRGBA *color);
void gtk_color_chooser_get_rgba(void *chooser, GdkRGBA *color);
void gtk_color_chooser_set_use_alpha(void *chooser, gboolean use_alpha);

/* Printing and fonts (NSPrintOperation.m, NSPrintInfo.m, NSFontManager.m).
 * Pages are drawn by Cairo into PDF (or PostScript) files; GTK's print
 * and page setup dialogs stand for the Mac's print panel and page layout,
 * and a GtkPrintJob hands the PDF to the printer the user chose. The font
 * panel is GTK's font chooser, and the font manager lists the system's
 * families and faces through Pango (which asks fontconfig). Poppler reads
 * a printed file's text back, for tests. */
typedef struct _GtkPrintSettings GtkPrintSettings;
typedef struct _GtkPageSetup GtkPageSetup;
typedef struct _GtkPaperSize GtkPaperSize;
typedef struct _GtkPrinter GtkPrinter;
typedef struct _GtkPrintJob GtkPrintJob;
typedef struct { int start, end; } GtkPageRange;
typedef struct _PangoFontFamily PangoFontFamily;
typedef struct _PangoFontFace PangoFontFace;
typedef void (*GtkPrintJobCompleteFunc)(GtkPrintJob *job, void *data, const GError *error);
typedef int (*GSourceFunc)(void *data);
enum { GTK_UNIT_NONE = 0, GTK_UNIT_POINTS = 1, GTK_UNIT_INCH = 2, GTK_UNIT_MM = 3 };
enum { GTK_PAGE_ORIENTATION_PORTRAIT = 0, GTK_PAGE_ORIENTATION_LANDSCAPE = 1 };
enum { GTK_PRINT_PAGES_ALL = 0, GTK_PRINT_PAGES_CURRENT = 1, GTK_PRINT_PAGES_RANGES = 2 };
enum { GTK_PRINT_CAPABILITY_PAGE_SET = 1 << 0, GTK_PRINT_CAPABILITY_COPIES = 1 << 1,
       GTK_PRINT_CAPABILITY_COLLATE = 1 << 2, GTK_PRINT_CAPABILITY_REVERSE = 1 << 3,
       GTK_PRINT_CAPABILITY_SCALE = 1 << 4, GTK_PRINT_CAPABILITY_GENERATE_PDF = 1 << 5 };
enum { CAIRO_PDF_VERSION_1_4 = 0 };
cairo_surface_t *cairo_pdf_surface_create_for_stream(cairo_write_func_t write, void *closure, double width,
                                                     double height);
void cairo_pdf_surface_set_size(cairo_surface_t *surface, double width, double height);
cairo_surface_t *cairo_ps_surface_create_for_stream(cairo_write_func_t write, void *closure, double width,
                                                    double height);
void cairo_ps_surface_set_eps(cairo_surface_t *surface, cairo_bool_t eps);
void cairo_ps_surface_set_size(cairo_surface_t *surface, double width, double height);
void cairo_show_page(cairo_t *cr);
void cairo_surface_finish(cairo_surface_t *surface);
unsigned g_timeout_add(unsigned interval_ms, GSourceFunc function, void *data);
GtkPrintSettings *gtk_print_settings_new(void);
void gtk_print_settings_set_n_copies(GtkPrintSettings *settings, int copies);
int gtk_print_settings_get_n_copies(GtkPrintSettings *settings);
void gtk_print_settings_set_collate(GtkPrintSettings *settings, gboolean collate);
gboolean gtk_print_settings_get_collate(GtkPrintSettings *settings);
void gtk_print_settings_set_reverse(GtkPrintSettings *settings, gboolean reverse);
gboolean gtk_print_settings_get_reverse(GtkPrintSettings *settings);
void gtk_print_settings_set_scale(GtkPrintSettings *settings, double scale);
double gtk_print_settings_get_scale(GtkPrintSettings *settings);
void gtk_print_settings_set_print_pages(GtkPrintSettings *settings, int pages);
int gtk_print_settings_get_print_pages(GtkPrintSettings *settings);
void gtk_print_settings_set_page_ranges(GtkPrintSettings *settings, GtkPageRange *ranges, int count);
GtkPageRange *gtk_print_settings_get_page_ranges(GtkPrintSettings *settings, int *count);
void gtk_print_settings_set_printer(GtkPrintSettings *settings, const char *printer);
const char *gtk_print_settings_get_printer(GtkPrintSettings *settings);
void gtk_print_settings_set(GtkPrintSettings *settings, const char *key, const char *value);
const char *gtk_print_settings_get(GtkPrintSettings *settings, const char *key);
GtkPageSetup *gtk_page_setup_new(void);
void gtk_page_setup_set_orientation(GtkPageSetup *setup, int orientation);
int gtk_page_setup_get_orientation(GtkPageSetup *setup);
void gtk_page_setup_set_paper_size(GtkPageSetup *setup, GtkPaperSize *size);
GtkPaperSize *gtk_page_setup_get_paper_size(GtkPageSetup *setup);
void gtk_page_setup_set_top_margin(GtkPageSetup *setup, double margin, int unit);
void gtk_page_setup_set_bottom_margin(GtkPageSetup *setup, double margin, int unit);
void gtk_page_setup_set_left_margin(GtkPageSetup *setup, double margin, int unit);
void gtk_page_setup_set_right_margin(GtkPageSetup *setup, double margin, int unit);
double gtk_page_setup_get_top_margin(GtkPageSetup *setup, int unit);
double gtk_page_setup_get_bottom_margin(GtkPageSetup *setup, int unit);
double gtk_page_setup_get_left_margin(GtkPageSetup *setup, int unit);
double gtk_page_setup_get_right_margin(GtkPageSetup *setup, int unit);
GtkPaperSize *gtk_paper_size_new(const char *name);
GtkPaperSize *gtk_paper_size_new_custom(const char *name, const char *display_name, double width, double height,
                                        int unit);
void gtk_paper_size_free(GtkPaperSize *size);
const char *gtk_paper_size_get_name(GtkPaperSize *size);
double gtk_paper_size_get_width(GtkPaperSize *size, int unit);
double gtk_paper_size_get_height(GtkPaperSize *size, int unit);
gboolean gtk_paper_size_is_custom(GtkPaperSize *size);
GtkWidget *gtk_print_unix_dialog_new(const char *title, GtkWidget *parent);
void gtk_print_unix_dialog_set_page_setup(GtkWidget *dialog, GtkPageSetup *setup);
GtkPageSetup *gtk_print_unix_dialog_get_page_setup(GtkWidget *dialog);
void gtk_print_unix_dialog_set_settings(GtkWidget *dialog, GtkPrintSettings *settings);
GtkPrintSettings *gtk_print_unix_dialog_get_settings(GtkWidget *dialog);
GtkPrinter *gtk_print_unix_dialog_get_selected_printer(GtkWidget *dialog);
void gtk_print_unix_dialog_set_manual_capabilities(GtkWidget *dialog, int capabilities);
void gtk_print_unix_dialog_set_embed_page_setup(GtkWidget *dialog, gboolean embed);
GtkWidget *gtk_page_setup_unix_dialog_new(const char *title, GtkWidget *parent);
void gtk_page_setup_unix_dialog_set_page_setup(GtkWidget *dialog, GtkPageSetup *setup);
GtkPageSetup *gtk_page_setup_unix_dialog_get_page_setup(GtkWidget *dialog);
int gtk_dialog_run(GtkWidget *dialog);
void gtk_dialog_response(GtkWidget *dialog, int response);
const char *gtk_printer_get_name(GtkPrinter *printer);
gboolean gtk_printer_is_virtual(GtkPrinter *printer);
GtkPrintJob *gtk_print_job_new(const char *title, GtkPrinter *printer, GtkPrintSettings *settings,
                               GtkPageSetup *setup);
gboolean gtk_print_job_set_source_file(GtkPrintJob *job, const char *filename, GError **error);
void gtk_print_job_send(GtkPrintJob *job, GtkPrintJobCompleteFunc callback, void *data, void *destroy);
GtkWidget *gtk_font_chooser_dialog_new(const char *title, GtkWidget *parent);
PangoFontDescription *gtk_font_chooser_get_font_desc(void *chooser);
void gtk_font_chooser_set_font_desc(void *chooser, const PangoFontDescription *desc);
PangoFontDescription *pango_font_description_from_string(const char *string);
char *pango_font_description_to_string(const PangoFontDescription *desc);
int pango_font_description_get_size(const PangoFontDescription *desc);
gboolean pango_font_description_get_size_is_absolute(const PangoFontDescription *desc);
void pango_font_description_set_size(PangoFontDescription *desc, int size);
void pango_font_map_list_families(PangoFontMap *fontmap, PangoFontFamily ***families, int *count);
const char *pango_font_family_get_name(PangoFontFamily *family);
gboolean pango_font_family_is_monospace(PangoFontFamily *family);
void pango_font_family_list_faces(PangoFontFamily *family, PangoFontFace ***faces, int *count);
const char *pango_font_face_get_face_name(PangoFontFace *face);
PangoFontDescription *pango_font_face_describe(PangoFontFace *face);
gboolean pango_font_face_is_synthesized(PangoFontFace *face);
char *poppler_page_get_text(PopplerPage *page);
/* Notifications and the Dock (ANotifyServer.m, NSDockTile.m): the replies to
 * D-Bus calls made without waiting, sending what is queued before the
 * program ends, and the GVariant kinds that the notification and
 * LauncherEntry interfaces use. */
typedef struct _GAsyncResult GAsyncResult;
GVariant *g_dbus_connection_call_finish(GDBusConnection *connection, GAsyncResult *result, GError **error);
gboolean g_dbus_connection_flush_sync(GDBusConnection *connection, void *cancellable, GError **error);
GVariant *g_variant_new_int64(int64_t value);
GVariant *g_variant_new_byte(unsigned char value);
uint32_t g_variant_get_uint32(GVariant *value);
/* Cursors (NSCursor.m): a named or drawn cursor set on a window. */
typedef struct _GdkWindow GdkWindow;
typedef struct _GdkCursor GdkCursor;
GdkWindow *gtk_widget_get_window(GtkWidget *widget);
GdkCursor *gdk_cursor_new_from_name(GdkDisplay *display, const char *name);
GdkCursor *gdk_cursor_new_from_surface(GdkDisplay *display, cairo_surface_t *surface, double x, double y);
void gdk_window_set_cursor(GdkWindow *window, GdkCursor *cursor);
GtkWidget *gtk_window_get_focus(GtkWidget *window);
#endif
