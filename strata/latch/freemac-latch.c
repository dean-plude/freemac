// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Latch: dresses the lock screen (gtklock 2.1) like Gangway, the login
 * screen. gtklock still does the locking and checks the password; this
 * module only moves its widgets: the date and a large clock near the top,
 * the person's picture and name in the lower middle, and a round password
 * field with an arrow button in it. Original freemac code.
 *
 * gtklock passes its own structures to modules. The two below repeat the
 * layout of gtklock 2.1's include/gtklock.h and include/window.h (GPL-3.0,
 * Copyright (c) 2022 Kenny Levinsen, Jovan Lanik), which is all a module may
 * rely on; the build only installs this module next to gtklock 2.1.
 */
#include <pwd.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <gtk/gtk.h>

struct Window;

struct GtkLock {
	GtkApplication *app;
	GArray *windows;
	GArray *messages;
	GArray *errors;
	struct Window *focused_window;
	gboolean hidden;
	guint idle_timeout;
	guint draw_clock_source;
	guint idle_hide_source;
	gboolean use_layer_shell;
	gboolean use_input_inhibit;
	gboolean use_idle_hide;
	char *time;
	char *time_format;
	char *config_path;
	GArray *modules;
};

struct Window {
	GdkMonitor *monitor;
	GtkWidget *window;
	GtkWidget *overlay;
	GtkWidget *window_box;
	GtkWidget *body_revealer;
	GtkWidget *body_grid;
	GtkWidget *input_label;
	GtkWidget *input_field;
	GtkWidget *message_box;
	GtkWidget *unlock_button;
	GtkWidget *error_label;
	GtkWidget *warning_label;
	GtkWidget *clock_label;
	gulong enter_notify_handler;
	void *module_data[];
};

const gchar module_name[] = "freemac-latch";
const guint module_major_version = 2;
const guint module_minor_version = 1;

#define AVATAR 96

static const char *display_name(void)
{
	static char name[256];
	struct passwd *pw = getpwuid(getuid());
	if(!pw) return g_get_user_name();
	const char *gecos = pw->pw_gecos ? pw->pw_gecos : "";
	size_t n = strcspn(gecos, ",");
	if(n == 0) return pw->pw_name;
	if(n >= sizeof(name)) n = sizeof(name) - 1;
	memcpy(name, gecos, n);
	name[n] = '\0';
	return name;
}

static char *initials(const char *name)
{
	GString *out = g_string_new(NULL);
	gchar **words = g_strsplit_set(name, " .", -1);
	for(int i = 0; words[i] && out->len < 2; i++) {
		gunichar c = g_utf8_get_char(words[i]);
		if(words[i][0] && g_unichar_isalpha(c)) g_string_append_unichar(out, g_unichar_toupper(c));
	}
	g_strfreev(words);
	if(out->len == 0) g_string_append(out, "?");
	return g_string_free(out, FALSE);
}

/* The person's picture as a circle: ~/.face if they set one, else their
 * initials on a soft grey gradient, the same as on the login screen. */
static GtkWidget *avatar(void)
{
	cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, AVATAR, AVATAR);
	cairo_t *cr = cairo_create(surface);
	cairo_arc(cr, AVATAR / 2.0, AVATAR / 2.0, AVATAR / 2.0, 0, 2 * G_PI);
	cairo_clip(cr);
	GdkPixbuf *picture = NULL;
	const char *faces[] = {".face", ".face.icon"};
	for(int i = 0; i < 2 && !picture; i++) {
		char *path = g_build_filename(g_get_home_dir(), faces[i], NULL);
		picture = gdk_pixbuf_new_from_file_at_scale(path, AVATAR, AVATAR, FALSE, NULL);
		g_free(path);
	}
	if(picture) {
		gdk_cairo_set_source_pixbuf(cr, picture, 0, 0);
		cairo_paint(cr);
		g_object_unref(picture);
	} else {
		cairo_pattern_t *g = cairo_pattern_create_linear(0, 0, 0, AVATAR);
		cairo_pattern_add_color_stop_rgb(g, 0, 0.66, 0.69, 0.75);
		cairo_pattern_add_color_stop_rgb(g, 1, 0.47, 0.50, 0.57);
		cairo_set_source(cr, g);
		cairo_paint(cr);
		cairo_pattern_destroy(g);
		char *text = initials(display_name());
		cairo_set_source_rgb(cr, 1, 1, 1);
		cairo_select_font_face(cr, "Inter", CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL);
		cairo_set_font_size(cr, AVATAR * 0.40);
		cairo_text_extents_t ext;
		cairo_text_extents(cr, text, &ext);
		cairo_move_to(cr, AVATAR / 2.0 - ext.width / 2 - ext.x_bearing, AVATAR / 2.0 - ext.height / 2 - ext.y_bearing);
		cairo_show_text(cr, text);
		g_free(text);
	}
	cairo_destroy(cr);
	GtkWidget *image = gtk_image_new_from_surface(surface);
	cairo_surface_destroy(surface);
	return image;
}

static void set_date(GtkWidget *label)
{
	char text[128];
	time_t now = time(NULL);
	struct tm tm;
	localtime_r(&now, &tm);
	if(strftime(text, sizeof(text), "%A, %B %-d", &tm) > 0) gtk_label_set_text(GTK_LABEL(label), text);
}

static gboolean tick(gpointer data)
{
	GtkWidget **slot = data;
	if(*slot == NULL) {
		g_free(slot);
		return G_SOURCE_REMOVE;
	}
	set_date(*slot);
	return G_SOURCE_CONTINUE;
}

static void add_class(GtkWidget *widget, const char *name)
{
	gtk_style_context_add_class(gtk_widget_get_style_context(widget), name);
}

/* The hint over the empty field stays until typing starts, as on the login
 * screen (GTK hides an entry's own placeholder while it has focus). */
static void field_changed(GtkEditable *entry, gpointer placeholder)
{
	gtk_widget_set_visible(GTK_WIDGET(placeholder), gtk_entry_get_text_length(GTK_ENTRY(entry)) == 0);
}

void on_window_create(struct GtkLock *gtklock, struct Window *win)
{
	(void)gtklock;

	/* The date and the clock at the top. */
	GtkWidget *top = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	gtk_widget_set_halign(top, GTK_ALIGN_CENTER);
	gtk_widget_set_valign(top, GTK_ALIGN_START);
	gtk_widget_set_margin_top(top, 64);
	GtkWidget *date = gtk_label_new(NULL);
	gtk_widget_set_name(date, "date-label");
	set_date(date);
	GtkWidget **slot = g_new(GtkWidget *, 1);
	*slot = date;
	g_object_add_weak_pointer(G_OBJECT(date), (gpointer *)slot);
	g_timeout_add_seconds(20, tick, slot);
	gtk_box_pack_start(GTK_BOX(top), date, FALSE, FALSE, 0);
	g_object_ref(win->clock_label);
	gtk_container_remove(GTK_CONTAINER(win->window_box), win->clock_label);
	gtk_widget_set_margin_bottom(win->clock_label, 0);
	gtk_box_pack_start(GTK_BOX(top), win->clock_label, FALSE, FALSE, 0);
	g_object_unref(win->clock_label);
	gtk_overlay_add_overlay(GTK_OVERLAY(win->overlay), top);
	gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(win->overlay), top, TRUE);

	/* The person in the lower middle. */
	GtkWidget *box = win->window_box;
	gtk_container_set_border_width(GTK_CONTAINER(box), 0);
	g_object_set(box, "margin", 0, NULL);
	gtk_widget_set_valign(box, GTK_ALIGN_END);
	gtk_widget_set_margin_bottom(box, 150);
	gtk_box_set_spacing(GTK_BOX(box), 10);
	GtkWidget *picture = avatar();
	gtk_widget_set_halign(picture, GTK_ALIGN_CENTER);
	gtk_box_pack_start(GTK_BOX(box), picture, FALSE, FALSE, 0);
	gtk_box_reorder_child(GTK_BOX(box), picture, 0);
	GtkWidget *name = gtk_label_new(display_name());
	gtk_widget_set_name(name, "name-label");
	gtk_box_pack_start(GTK_BOX(box), name, FALSE, FALSE, 0);
	gtk_box_reorder_child(GTK_BOX(box), name, 1);

	/* A round field with the arrow button inside it, and no "Password:". */
	gtk_widget_set_no_show_all(win->input_label, TRUE);
	gtk_widget_hide(win->input_label);
	GtkWidget *entry = win->input_field;
	GtkWidget *button = win->unlock_button;
	GtkWidget *button_row = gtk_widget_get_parent(button);
	g_object_ref(entry);
	g_object_ref(button);
	gtk_container_remove(GTK_CONTAINER(win->body_grid), entry);
	gtk_container_remove(GTK_CONTAINER(button_row), button);
	gtk_widget_set_halign(button_row, GTK_ALIGN_CENTER);

	gtk_entry_set_icon_from_icon_name(GTK_ENTRY(entry), GTK_ENTRY_ICON_SECONDARY, NULL);
	gtk_entry_set_has_frame(GTK_ENTRY(entry), FALSE);
	gtk_widget_set_size_request(entry, -1, -1);
	gtk_widget_set_hexpand(entry, TRUE);
	GtkWidget *placeholder = gtk_label_new("Enter Password");
	gtk_widget_set_name(placeholder, "placeholder-label");
	gtk_widget_set_halign(placeholder, GTK_ALIGN_START);
	gtk_widget_set_margin_start(placeholder, 2);
	g_signal_connect(entry, "changed", G_CALLBACK(field_changed), placeholder);
	GtkWidget *stack = gtk_overlay_new();
	gtk_container_add(GTK_CONTAINER(stack), entry);
	gtk_overlay_add_overlay(GTK_OVERLAY(stack), placeholder);
	gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(stack), placeholder, TRUE);

	gtk_button_set_label(GTK_BUTTON(button), NULL);
	gtk_button_set_image(GTK_BUTTON(button), gtk_image_new_from_icon_name("go-next-symbolic", GTK_ICON_SIZE_BUTTON));
	gtk_button_set_always_show_image(GTK_BUTTON(button), TRUE);
	gtk_style_context_remove_class(gtk_widget_get_style_context(button), "suggested-action");
	gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
	gtk_widget_set_tooltip_text(button, "Unlock");

	GtkWidget *field = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
	gtk_widget_set_name(field, "latch-field");
	gtk_widget_set_size_request(field, 240, -1);
	gtk_widget_set_halign(field, GTK_ALIGN_CENTER);
	gtk_widget_set_margin_top(field, 6);
	gtk_box_pack_start(GTK_BOX(field), stack, TRUE, TRUE, 0);
	gtk_box_pack_start(GTK_BOX(field), button, FALSE, FALSE, 0);
	add_class(field, "latch-field");
	gtk_grid_attach(GTK_GRID(win->body_grid), field, 1, 0, 2, 1);
	gtk_widget_set_halign(win->body_grid, GTK_ALIGN_CENTER);
	/* Keep the room when the field hides after a while, so the picture
	 * doesn't jump. */
	gtk_widget_set_size_request(win->body_revealer, -1, 70);
	gtk_widget_set_valign(win->body_grid, GTK_ALIGN_START);
	g_object_unref(entry);
	g_object_unref(button);
}
