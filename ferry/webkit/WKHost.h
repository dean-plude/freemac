/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The parts of this system's WebKitGTK (webkit2gtk-4.1) and of
 * JavaScriptCore's GLib API (javascriptcoregtk-4.1) that Ferry's WebKit
 * framework calls, and the few GTK and GLib calls it adds to AppKit's
 * (appkit/gtk.h). WebKitGTK is a Linux library and the framework is Mac
 * code, but both use the System V calling convention, so the framework can
 * call it directly.
 *
 * As in graphics/host.h and appkit/gtk.h, these declarations are written
 * from the libraries' published API documentation, because the Mac build
 * can't include Linux headers. Only calls, enumerations and structures that
 * are part of each library's stable public API are used.
 *
 * The GTK and GLib calls are served, as AppKit's are, by Ferry's loader
 * under /usr/lib/ferry/libFerryHost.dylib. The WebKitGTK and JavaScriptCore
 * calls are different: the framework never links them. It looks each one
 * up by name, through ferry_webkit_symbol() (src/host.c), the first time it
 * is made, with WK() below, so a program that links WebKit but never makes
 * a web view doesn't open WebKitGTK, and a system without WebKitGTK still
 * runs it. The declarations here give those lookups their types.
 */
#ifndef FERRY_WEBKIT_HOST_H
#define FERRY_WEBKIT_HOST_H
#include <stddef.h>
#include <stdint.h>
#include "../appkit/gtk.h"

/* ---- GLib, GObject and GTK, beyond AppKit's -------------------------------------- */

typedef unsigned long GType;
typedef struct _GBytes GBytes;
typedef struct _GCancellable GCancellable;
typedef struct _GParamSpec GParamSpec;
typedef struct _GtkAdjustment GtkAdjustment;
typedef void (*GAsyncReadyCallback)(void *source, GAsyncResult *result, void *data);
enum { GTK_ALIGN_FILL = 0, GTK_ALIGN_START = 1, GTK_ALIGN_END = 2, GTK_ALIGN_CENTER = 3 };
enum { G_SIGNAL_MATCH_DATA = 1 << 4 };
enum { G_CONNECT_AFTER = 1 << 0 };

void *g_object_new(GType type, const char *first_property_name, ...);
void *g_object_ref_sink(void *object);
void g_object_set_data(void *object, const char *key, void *data);
void *g_object_get_data(void *object, const char *key);
void g_signal_handler_disconnect(void *instance, unsigned long handler_id);
unsigned g_signal_handlers_disconnect_matched(void *instance, int mask, unsigned signal_id, uint32_t detail,
                                              void *closure, void *func, void *data);
GBytes *g_bytes_new(const void *data, size_t size);
void g_bytes_unref(GBytes *bytes);
void g_list_free(GList *list);
const char *g_param_spec_get_name(GParamSpec *pspec);
const char *g_quark_to_string(uint32_t quark);
gboolean g_source_remove(unsigned tag);

GtkWidget *gtk_overlay_new(void);
void gtk_overlay_add_overlay(GtkWidget *overlay, GtkWidget *widget);
GtkWidget *gtk_layout_new(GtkAdjustment *hadjustment, GtkAdjustment *vadjustment);
void gtk_layout_put(GtkWidget *layout, GtkWidget *child, int x, int y);
void gtk_layout_move(GtkWidget *layout, GtkWidget *child, int x, int y);
GtkWidget *gtk_bin_get_child(GtkWidget *bin);
void gtk_container_remove(GtkWidget *container, GtkWidget *widget);
GtkWidget *gtk_widget_get_parent(GtkWidget *widget);
void gtk_widget_show(GtkWidget *widget);
gboolean gtk_widget_get_visible(GtkWidget *widget);
void gtk_widget_set_halign(GtkWidget *widget, int align);
void gtk_widget_set_valign(GtkWidget *widget, int align);
void gtk_widget_set_margin_start(GtkWidget *widget, int margin);
void gtk_widget_set_margin_top(GtkWidget *widget, int margin);
gboolean gtk_widget_has_focus(GtkWidget *widget);
gboolean gtk_widget_is_focus(GtkWidget *widget);

/* ---- JavaScriptCore's GLib API: values handed back from a page -------------------- */

typedef struct _JSCValue JSCValue;
gboolean jsc_value_is_undefined(JSCValue *value);
gboolean jsc_value_is_null(JSCValue *value);
gboolean jsc_value_is_boolean(JSCValue *value);
gboolean jsc_value_is_number(JSCValue *value);
gboolean jsc_value_is_string(JSCValue *value);
gboolean jsc_value_is_array(JSCValue *value);
gboolean jsc_value_is_object(JSCValue *value);
gboolean jsc_value_is_function(JSCValue *value);
gboolean jsc_value_object_is_instance_of(JSCValue *value, const char *name);
gboolean jsc_value_to_boolean(JSCValue *value);
double jsc_value_to_double(JSCValue *value);
char *jsc_value_to_string(JSCValue *value);
char *jsc_value_to_json(JSCValue *value, unsigned indent);

/* ---- WebKitGTK ------------------------------------------------------------------- */

typedef GtkWidget WebKitWebView;
typedef struct _WebKitSettings WebKitSettings;
typedef struct _WebKitWebContext WebKitWebContext;
typedef struct _WebKitWebsiteDataManager WebKitWebsiteDataManager;
typedef struct _WebKitUserContentManager WebKitUserContentManager;
typedef struct _WebKitUserScript WebKitUserScript;
typedef struct _WebKitURIRequest WebKitURIRequest;
typedef struct _WebKitURIResponse WebKitURIResponse;
typedef struct _WebKitPolicyDecision WebKitPolicyDecision;
typedef struct _WebKitNavigationAction WebKitNavigationAction;
typedef struct _WebKitScriptDialog WebKitScriptDialog;
typedef struct _WebKitBackForwardList WebKitBackForwardList;
typedef struct _WebKitBackForwardListItem WebKitBackForwardListItem;
typedef struct _WebKitJavascriptResult WebKitJavascriptResult;
typedef struct _WebKitWebResource WebKitWebResource;

enum { WEBKIT_LOAD_STARTED = 0, WEBKIT_LOAD_REDIRECTED = 1, WEBKIT_LOAD_COMMITTED = 2, WEBKIT_LOAD_FINISHED = 3 };
enum {
    WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION = 0,
    WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION = 1,
    WEBKIT_POLICY_DECISION_TYPE_RESPONSE = 2,
};
enum {
    WEBKIT_NAVIGATION_TYPE_LINK_CLICKED = 0,
    WEBKIT_NAVIGATION_TYPE_FORM_SUBMITTED = 1,
    WEBKIT_NAVIGATION_TYPE_BACK_FORWARD = 2,
    WEBKIT_NAVIGATION_TYPE_RELOAD = 3,
    WEBKIT_NAVIGATION_TYPE_FORM_RESUBMITTED = 4,
    WEBKIT_NAVIGATION_TYPE_OTHER = 5,
};
enum {
    WEBKIT_SCRIPT_DIALOG_ALERT = 0,
    WEBKIT_SCRIPT_DIALOG_CONFIRM = 1,
    WEBKIT_SCRIPT_DIALOG_PROMPT = 2,
    WEBKIT_SCRIPT_DIALOG_BEFORE_UNLOAD_CONFIRM = 3,
};
enum { WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES = 0, WEBKIT_USER_CONTENT_INJECT_TOP_FRAME = 1 };
enum { WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START = 0, WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END = 1 };
enum { WEBKIT_SNAPSHOT_REGION_VISIBLE = 0, WEBKIT_SNAPSHOT_REGION_FULL_DOCUMENT = 1 };
enum { WEBKIT_SNAPSHOT_OPTIONS_NONE = 0, WEBKIT_SNAPSHOT_OPTIONS_TRANSPARENT_BACKGROUND = 1 << 1 };
enum {
    WEBKIT_NETWORK_ERROR_FAILED = 399,
    WEBKIT_NETWORK_ERROR_TRANSPORT = 300,
    WEBKIT_NETWORK_ERROR_UNKNOWN_PROTOCOL = 301,
    WEBKIT_NETWORK_ERROR_CANCELLED = 302,
    WEBKIT_NETWORK_ERROR_FILE_DOES_NOT_EXIST = 303,
};
enum {
    WEBKIT_JAVASCRIPT_ERROR_SCRIPT_FAILED = 699,
    WEBKIT_JAVASCRIPT_ERROR_INVALID_PARAMETER = 600,
    WEBKIT_JAVASCRIPT_ERROR_INVALID_RESULT = 700,
};
/* The kinds of website data (WebKitWebsiteDataTypes). */
enum {
    WEBKIT_WEBSITE_DATA_MEMORY_CACHE = 1 << 0,
    WEBKIT_WEBSITE_DATA_DISK_CACHE = 1 << 1,
    WEBKIT_WEBSITE_DATA_OFFLINE_APPLICATION_CACHE = 1 << 2,
    WEBKIT_WEBSITE_DATA_SESSION_STORAGE = 1 << 3,
    WEBKIT_WEBSITE_DATA_LOCAL_STORAGE = 1 << 4,
    WEBKIT_WEBSITE_DATA_INDEXEDDB_DATABASES = 1 << 6,
    WEBKIT_WEBSITE_DATA_COOKIES = 1 << 8,
    WEBKIT_WEBSITE_DATA_HSTS_CACHE = 1 << 10,
    WEBKIT_WEBSITE_DATA_SERVICE_WORKER_REGISTRATIONS = 1 << 12,
    WEBKIT_WEBSITE_DATA_DOM_CACHE = 1 << 13,
};

uint32_t webkit_get_major_version(void);
uint32_t webkit_get_minor_version(void);
GType webkit_web_view_get_type(void);
void webkit_web_view_load_uri(WebKitWebView *view, const char *uri);
void webkit_web_view_load_html(WebKitWebView *view, const char *content, const char *base_uri);
void webkit_web_view_load_bytes(WebKitWebView *view, GBytes *bytes, const char *mime_type, const char *encoding,
                                const char *base_uri);
void webkit_web_view_load_request(WebKitWebView *view, WebKitURIRequest *request);
void webkit_web_view_go_back(WebKitWebView *view);
void webkit_web_view_go_forward(WebKitWebView *view);
void webkit_web_view_reload(WebKitWebView *view);
void webkit_web_view_reload_bypass_cache(WebKitWebView *view);
void webkit_web_view_stop_loading(WebKitWebView *view);
gboolean webkit_web_view_can_go_back(WebKitWebView *view);
gboolean webkit_web_view_can_go_forward(WebKitWebView *view);
gboolean webkit_web_view_is_loading(WebKitWebView *view);
const char *webkit_web_view_get_title(WebKitWebView *view);
const char *webkit_web_view_get_uri(WebKitWebView *view);
double webkit_web_view_get_estimated_load_progress(WebKitWebView *view);
WebKitSettings *webkit_web_view_get_settings(WebKitWebView *view);
WebKitBackForwardList *webkit_web_view_get_back_forward_list(WebKitWebView *view);
void webkit_web_view_go_to_back_forward_list_item(WebKitWebView *view, WebKitBackForwardListItem *item);
void webkit_web_view_evaluate_javascript(WebKitWebView *view, const char *script, long length, const char *world_name,
                                         const char *source_uri, GCancellable *cancellable,
                                         GAsyncReadyCallback callback, void *data);
JSCValue *webkit_web_view_evaluate_javascript_finish(WebKitWebView *view, GAsyncResult *result, GError **error);
void webkit_web_view_get_snapshot(WebKitWebView *view, int region, int options, GCancellable *cancellable,
                                  GAsyncReadyCallback callback, void *data);
cairo_surface_t *webkit_web_view_get_snapshot_finish(WebKitWebView *view, GAsyncResult *result, GError **error);
void webkit_web_view_execute_editing_command(WebKitWebView *view, const char *command);
void webkit_web_view_set_zoom_level(WebKitWebView *view, double zoom);
double webkit_web_view_get_zoom_level(WebKitWebView *view);
void webkit_web_view_set_background_color(WebKitWebView *view, const GdkRGBA *rgba);
void webkit_web_view_set_editable(WebKitWebView *view, gboolean editable);
WebKitWebResource *webkit_web_view_get_main_resource(WebKitWebView *view);
void webkit_web_resource_get_data(WebKitWebResource *resource, GCancellable *cancellable,
                                  GAsyncReadyCallback callback, void *data);
unsigned char *webkit_web_resource_get_data_finish(WebKitWebResource *resource, GAsyncResult *result, size_t *length,
                                                   GError **error);
WebKitURIResponse *webkit_web_resource_get_response(WebKitWebResource *resource);

WebKitSettings *webkit_settings_new(void);
void webkit_settings_set_enable_javascript(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_enable_javascript_markup(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_javascript_can_open_windows_automatically(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_auto_load_images(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_default_font_family(WebKitSettings *settings, const char *family);
void webkit_settings_set_monospace_font_family(WebKitSettings *settings, const char *family);
void webkit_settings_set_serif_font_family(WebKitSettings *settings, const char *family);
void webkit_settings_set_sans_serif_font_family(WebKitSettings *settings, const char *family);
void webkit_settings_set_cursive_font_family(WebKitSettings *settings, const char *family);
void webkit_settings_set_fantasy_font_family(WebKitSettings *settings, const char *family);
void webkit_settings_set_default_font_size(WebKitSettings *settings, uint32_t size);
void webkit_settings_set_default_monospace_font_size(WebKitSettings *settings, uint32_t size);
void webkit_settings_set_minimum_font_size(WebKitSettings *settings, uint32_t size);
void webkit_settings_set_default_charset(WebKitSettings *settings, const char *charset);
void webkit_settings_set_enable_tabs_to_links(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_enable_page_cache(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_enable_fullscreen(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_enable_developer_extras(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_enable_write_console_messages_to_stdout(WebKitSettings *settings, gboolean enabled);
void webkit_settings_set_allow_file_access_from_file_urls(WebKitSettings *settings, gboolean allowed);
void webkit_settings_set_allow_universal_access_from_file_urls(WebKitSettings *settings, gboolean allowed);
void webkit_settings_set_user_agent(WebKitSettings *settings, const char *user_agent);
void webkit_settings_set_user_agent_with_application_details(WebKitSettings *settings, const char *name,
                                                             const char *version);
const char *webkit_settings_get_user_agent(WebKitSettings *settings);

WebKitWebContext *webkit_web_context_get_default(void);
WebKitWebContext *webkit_web_context_new_ephemeral(void);
gboolean webkit_web_context_is_ephemeral(WebKitWebContext *context);
WebKitWebsiteDataManager *webkit_web_context_get_website_data_manager(WebKitWebContext *context);
void webkit_website_data_manager_clear(WebKitWebsiteDataManager *manager, int types, int64_t timespan,
                                       GCancellable *cancellable, GAsyncReadyCallback callback, void *data);
gboolean webkit_website_data_manager_clear_finish(WebKitWebsiteDataManager *manager, GAsyncResult *result,
                                                  GError **error);

WebKitUserContentManager *webkit_user_content_manager_new(void);
void webkit_user_content_manager_add_script(WebKitUserContentManager *manager, WebKitUserScript *script);
void webkit_user_content_manager_remove_all_scripts(WebKitUserContentManager *manager);
gboolean webkit_user_content_manager_register_script_message_handler(WebKitUserContentManager *manager,
                                                                     const char *name);
void webkit_user_content_manager_unregister_script_message_handler(WebKitUserContentManager *manager,
                                                                   const char *name);
WebKitUserScript *webkit_user_script_new(const char *source, int injected_frames, int injection_time,
                                         const char *const *allow_list, const char *const *block_list);
void webkit_user_script_unref(WebKitUserScript *script);
WebKitUserScript *webkit_user_script_new_for_world(const char *source, int injected_frames, int injection_time,
                                                   const char *world_name, const char *const *allow_list,
                                                   const char *const *block_list);
gboolean webkit_user_content_manager_register_script_message_handler_in_world(WebKitUserContentManager *manager,
                                                                              const char *name,
                                                                              const char *world_name);
void webkit_user_content_manager_unregister_script_message_handler_in_world(WebKitUserContentManager *manager,
                                                                            const char *name,
                                                                            const char *world_name);
JSCValue *webkit_javascript_result_get_js_value(WebKitJavascriptResult *result);

WebKitURIRequest *webkit_uri_request_new(const char *uri);
const char *webkit_uri_request_get_uri(WebKitURIRequest *request);
const char *webkit_uri_request_get_http_method(WebKitURIRequest *request);
const char *webkit_uri_response_get_uri(WebKitURIResponse *response);
unsigned webkit_uri_response_get_status_code(WebKitURIResponse *response);
uint64_t webkit_uri_response_get_content_length(WebKitURIResponse *response);
const char *webkit_uri_response_get_mime_type(WebKitURIResponse *response);
const char *webkit_uri_response_get_suggested_filename(WebKitURIResponse *response);

void webkit_policy_decision_use(WebKitPolicyDecision *decision);
void webkit_policy_decision_ignore(WebKitPolicyDecision *decision);
WebKitNavigationAction *webkit_navigation_policy_decision_get_navigation_action(WebKitPolicyDecision *decision);
int webkit_navigation_action_get_navigation_type(WebKitNavigationAction *action);
unsigned webkit_navigation_action_get_mouse_button(WebKitNavigationAction *action);
unsigned webkit_navigation_action_get_modifiers(WebKitNavigationAction *action);
WebKitURIRequest *webkit_navigation_action_get_request(WebKitNavigationAction *action);
gboolean webkit_navigation_action_is_user_gesture(WebKitNavigationAction *action);
const char *webkit_navigation_action_get_frame_name(WebKitNavigationAction *action);
WebKitURIRequest *webkit_response_policy_decision_get_request(WebKitPolicyDecision *decision);
WebKitURIResponse *webkit_response_policy_decision_get_response(WebKitPolicyDecision *decision);
gboolean webkit_response_policy_decision_is_mime_type_supported(WebKitPolicyDecision *decision);
gboolean webkit_response_policy_decision_is_main_frame_main_resource(WebKitPolicyDecision *decision);

int webkit_script_dialog_get_dialog_type(WebKitScriptDialog *dialog);
const char *webkit_script_dialog_get_message(WebKitScriptDialog *dialog);
void webkit_script_dialog_confirm_set_confirmed(WebKitScriptDialog *dialog, gboolean confirmed);
const char *webkit_script_dialog_prompt_get_default_text(WebKitScriptDialog *dialog);
void webkit_script_dialog_prompt_set_text(WebKitScriptDialog *dialog, const char *text);
WebKitScriptDialog *webkit_script_dialog_ref(WebKitScriptDialog *dialog);
void webkit_script_dialog_unref(WebKitScriptDialog *dialog);
void webkit_script_dialog_close(WebKitScriptDialog *dialog);

WebKitBackForwardListItem *webkit_back_forward_list_get_current_item(WebKitBackForwardList *list);
WebKitBackForwardListItem *webkit_back_forward_list_get_back_item(WebKitBackForwardList *list);
WebKitBackForwardListItem *webkit_back_forward_list_get_forward_item(WebKitBackForwardList *list);
WebKitBackForwardListItem *webkit_back_forward_list_get_nth_item(WebKitBackForwardList *list, int index);
GList *webkit_back_forward_list_get_back_list(WebKitBackForwardList *list);
GList *webkit_back_forward_list_get_forward_list(WebKitBackForwardList *list);
const char *webkit_back_forward_list_item_get_uri(WebKitBackForwardListItem *item);
const char *webkit_back_forward_list_item_get_title(WebKitBackForwardListItem *item);
const char *webkit_back_forward_list_item_get_original_uri(WebKitBackForwardListItem *item);

uint32_t webkit_javascript_error_quark(void);
uint32_t webkit_network_error_quark(void);
uint32_t webkit_policy_error_quark(void);

#endif
