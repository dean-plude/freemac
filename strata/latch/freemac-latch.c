// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * Latch: dresses the lock screen (gtklock 2.1) like Gangway, the login
 * screen. gtklock still does the locking and checks the password; this
 * module only moves its widgets: the date and a large clock near the top,
 * the person's picture and name in the lower middle, and a round password
 * field with an arrow button in it. It also adds what a Mac's lock screen
 * shows: the battery in the top right, Now Playing with its buttons and the
 * notifications that came in while locked under the clock, and a message
 * under the password field. Those come from "freemac-lock --feed" (latch.py
 * explains the lines it sends), started when the screen locks. Original
 * freemac code.
 *
 * gtklock passes its own structures to modules. The two below repeat the
 * layout of gtklock 2.1's include/gtklock.h and include/window.h (GPL-3.0,
 * Copyright (c) 2022 Kenny Levinsen, Jovan Lanik), which is all a module may
 * rely on; the build only installs this module next to gtklock 2.1.
 */
#include <pwd.h>
#include <stdlib.h>
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
	/* freemac-lock gives the region's order (Language & Region). */
	const char *format = g_getenv("FREEMAC_DATE_FORMAT");
	if(format == NULL || *format == '\0' || strlen(format) > 32 || strchr(format, '%') == NULL) format = "%A, %B %-d";
	if(strftime(text, sizeof(text), format, &tm) > 0) gtk_label_set_text(GTK_LABEL(label), text);
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

/* ---- What the feed sends ------------------------------------------------ */

#define CARD_WIDTH 340
#define COLUMN_TOP 215        /* under the clock */
#define CARD_STEP 78          /* a card and the gap after it */
#define MORE_HEIGHT 24
#define PERSON_HEIGHT 358     /* the picture, name and field, and the margin under them */
#define MESSAGE_HEIGHT 24

typedef struct {
	char *app, *icon, *title, *body;
	gint64 when;
} Note;

typedef struct {
	gboolean have_battery;
	int percent;
	char *power;           /* "charging", "plugged" or "battery" */
	gboolean have_playing;
	char *play_app, *play_title, *play_artist;
	gboolean playing, can_previous, can_next;
	GPtrArray *notes;      /* Note* */
	int more;
	char *message;
} Shown;

/* One lock window's added widgets. */
typedef struct {
	GtkWidget *window;
	GtkWidget *battery;    /* the box in the top right */
	GtkWidget *battery_label;
	GtkWidget *battery_icon;
	GtkWidget *column;     /* Now Playing and the notifications */
	GtkWidget *message;
	int height;
} Extras;

static GSubprocess *feed;
static GOutputStream *feed_in;
static GDataInputStream *feed_out;
static GPtrArray *reading;     /* the lines of the block being read */
static Shown shown;
static GSList *all_extras;

static void note_free(gpointer data)
{
	Note *note = data;
	g_free(note->app);
	g_free(note->icon);
	g_free(note->title);
	g_free(note->body);
	g_free(note);
}

static void shown_clear(void)
{
	g_free(shown.power);
	g_free(shown.play_app);
	g_free(shown.play_title);
	g_free(shown.play_artist);
	g_free(shown.message);
	if(shown.notes) g_ptr_array_unref(shown.notes);
	memset(&shown, 0, sizeof(shown));
	shown.notes = g_ptr_array_new_with_free_func(note_free);
}

static const char *field(gchar **fields, int i)
{
	for(int k = 0; k <= i; k++) if(!fields[k]) return "";
	return fields[i];
}

static void take_line(const char *line)
{
	gchar **f = g_strsplit(line, "\t", -1);
	const char *kind = field(f, 0);
	if(!strcmp(kind, "clear")) {
		shown_clear();
	} else if(!strcmp(kind, "battery")) {
		shown.have_battery = TRUE;
		shown.percent = atoi(field(f, 1));
		g_free(shown.power);
		shown.power = g_strdup(field(f, 2));
	} else if(!strcmp(kind, "playing")) {
		shown.have_playing = TRUE;
		g_free(shown.play_app);
		g_free(shown.play_title);
		g_free(shown.play_artist);
		shown.play_app = g_strdup(field(f, 1));
		shown.play_title = g_strdup(field(f, 2));
		shown.play_artist = g_strdup(field(f, 3));
		shown.playing = !strcmp(field(f, 4), "Playing");
		shown.can_previous = !strcmp(field(f, 5), "1");
		shown.can_next = !strcmp(field(f, 6), "1");
	} else if(!strcmp(kind, "note")) {
		Note *note = g_new0(Note, 1);
		note->app = g_strdup(field(f, 1));
		note->icon = g_strdup(field(f, 2));
		note->title = g_strdup(field(f, 3));
		note->body = g_strdup(field(f, 4));
		note->when = g_ascii_strtoll(field(f, 5), NULL, 10);
		g_ptr_array_add(shown.notes, note);
	} else if(!strcmp(kind, "more")) {
		shown.more = atoi(field(f, 1));
	} else if(!strcmp(kind, "message")) {
		g_free(shown.message);
		shown.message = g_strdup(field(f, 1));
	}
	g_strfreev(f);
}

static void send_command(const char *word)
{
	if(!feed_in) return;
	char *line = g_strconcat(word, "\n", NULL);
	g_output_stream_write_all(feed_in, line, strlen(line), NULL, NULL, NULL);
	g_output_stream_flush(feed_in, NULL, NULL);
	g_free(line);
}

static void on_media(GtkButton *button, gpointer word)
{
	(void)button;
	send_command(word);
}

static char *when_text(gint64 when)
{
	gint64 age = (gint64)time(NULL) - when;
	if(age < 60) return g_strdup("now");
	if(age < 3600) return g_strdup_printf("%dm ago", (int)(age / 60));
	char text[32];
	time_t t = (time_t)when;
	struct tm tm;
	localtime_r(&t, &tm);
	strftime(text, sizeof(text), "%-I:%M %p", &tm);
	return g_strdup(text);
}

static GtkWidget *label(const char *text, const char *name, gboolean wrap)
{
	GtkWidget *l = gtk_label_new(text);
	gtk_widget_set_name(l, name);
	gtk_label_set_xalign(GTK_LABEL(l), 0);
	gtk_label_set_ellipsize(GTK_LABEL(l), PANGO_ELLIPSIZE_END);
	if(wrap) {
		gtk_label_set_line_wrap(GTK_LABEL(l), TRUE);
		gtk_label_set_lines(GTK_LABEL(l), 2);
		gtk_label_set_max_width_chars(GTK_LABEL(l), 40);
	}
	return l;
}

static GtkWidget *note_icon(const char *icon)
{
	GtkWidget *image = NULL;
	const char *path = g_str_has_prefix(icon, "file://") ? icon + 7 : icon;
	if(path[0] == '/') {
		GdkPixbuf *pixbuf = gdk_pixbuf_new_from_file_at_scale(path, 30, 30, TRUE, NULL);
		if(pixbuf) {
			image = gtk_image_new_from_pixbuf(pixbuf);
			g_object_unref(pixbuf);
		}
	}
	if(!image) {
		image = gtk_image_new_from_icon_name(icon[0] && !strchr(icon, '/') ? icon : "dialog-information-symbolic",
		                                     GTK_ICON_SIZE_DND);
		gtk_image_set_pixel_size(GTK_IMAGE(image), 30);
	}
	gtk_widget_set_valign(image, GTK_ALIGN_START);
	return image;
}

static GtkWidget *card(void)
{
	GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10);
	gtk_widget_set_name(box, "latch-card");
	gtk_widget_set_size_request(box, CARD_WIDTH, -1);
	gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
	return box;
}

static GtkWidget *note_card(Note *note)
{
	GtkWidget *box = card();
	gtk_box_pack_start(GTK_BOX(box), note_icon(note->icon), FALSE, FALSE, 0);
	GtkWidget *text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
	GtkWidget *head = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
	char *app = g_utf8_strup(note->app, -1);
	gtk_box_pack_start(GTK_BOX(head), label(app, "latch-card-app", FALSE), TRUE, TRUE, 0);
	g_free(app);
	char *when = when_text(note->when);
	gtk_box_pack_end(GTK_BOX(head), label(when, "latch-card-when", FALSE), FALSE, FALSE, 0);
	g_free(when);
	gtk_box_pack_start(GTK_BOX(text), head, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(text), label(note->title, "latch-card-title", FALSE), FALSE, FALSE, 0);
	if(note->body[0]) gtk_box_pack_start(GTK_BOX(text), label(note->body, "latch-card-body", TRUE), FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), text, TRUE, TRUE, 0);
	return box;
}

static GtkWidget *media_button(const char *icon, const char *word, const char *tip, gboolean sensitive)
{
	GtkWidget *button = gtk_button_new_from_icon_name(icon, GTK_ICON_SIZE_LARGE_TOOLBAR);
	gtk_widget_set_name(button, "latch-media-button");
	gtk_button_set_relief(GTK_BUTTON(button), GTK_RELIEF_NONE);
	gtk_widget_set_tooltip_text(button, tip);
	gtk_widget_set_valign(button, GTK_ALIGN_CENTER);
	gtk_widget_set_sensitive(button, sensitive);
	gtk_widget_set_can_focus(button, FALSE);
	g_signal_connect(button, "clicked", G_CALLBACK(on_media), (gpointer)word);
	return button;
}

static GtkWidget *playing_card(void)
{
	GtkWidget *box = card();
	gtk_widget_set_name(box, "latch-playing");
	GtkWidget *text = gtk_box_new(GTK_ORIENTATION_VERTICAL, 1);
	gtk_widget_set_valign(text, GTK_ALIGN_CENTER);
	char *app = g_utf8_strup(shown.play_app, -1);
	gtk_box_pack_start(GTK_BOX(text), label(app, "latch-card-app", FALSE), FALSE, FALSE, 0);
	g_free(app);
	gtk_box_pack_start(GTK_BOX(text), label(shown.play_title[0] ? shown.play_title : "Not Playing",
	                                        "latch-card-title", FALSE), FALSE, FALSE, 0);
	if(shown.play_artist[0])
		gtk_box_pack_start(GTK_BOX(text), label(shown.play_artist, "latch-card-artist", FALSE), FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), text, TRUE, TRUE, 0);
	GtkWidget *buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
	gtk_box_pack_start(GTK_BOX(buttons), media_button("media-skip-backward-symbolic", "previous", "Previous",
	                                                  shown.can_previous), FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(buttons), media_button(shown.playing ? "media-playback-pause-symbolic"
	                                                                : "media-playback-start-symbolic",
	                                                  "play-pause", shown.playing ? "Pause" : "Play", TRUE),
	                   FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(buttons), media_button("media-skip-forward-symbolic", "next", "Next",
	                                                  shown.can_next), FALSE, FALSE, 0);
	gtk_box_pack_end(GTK_BOX(box), buttons, FALSE, FALSE, 0);
	return box;
}

/* A battery drawn like the one in the menu bar: an outline, a nub, filled
 * as far as it's charged, with a bolt while charging. */
static gboolean draw_battery(GtkWidget *widget, cairo_t *cr, gpointer data)
{
	(void)widget;
	(void)data;
	double w = 25, h = 12, x = 0.5, y = 0.5, r = 3;
	cairo_set_line_width(cr, 1);
	cairo_set_source_rgba(cr, 1, 1, 1, 0.75);
	cairo_new_sub_path(cr);
	cairo_arc(cr, x + w - r, y + r, r, -G_PI / 2, 0);
	cairo_arc(cr, x + w - r, y + h - r, r, 0, G_PI / 2);
	cairo_arc(cr, x + r, y + h - r, r, G_PI / 2, G_PI);
	cairo_arc(cr, x + r, y + r, r, G_PI, 3 * G_PI / 2);
	cairo_close_path(cr);
	cairo_stroke(cr);
	cairo_rectangle(cr, x + w + 1.5, y + 3.5, 1.5, 5);
	cairo_fill(cr);
	double fill = (w - 4) * CLAMP(shown.percent, 0, 100) / 100.0;
	gboolean charging = shown.power && !strcmp(shown.power, "charging");
	if(shown.percent <= 10 && !charging) cairo_set_source_rgb(cr, 1, 0.27, 0.23);
	else if(charging) cairo_set_source_rgb(cr, 0.2, 0.84, 0.29);
	else cairo_set_source_rgb(cr, 1, 1, 1);
	cairo_rectangle(cr, x + 2, y + 2, MAX(fill, 1.5), h - 4);
	cairo_fill(cr);
	if(charging) {
		double cx = x + w / 2, cy = y + h / 2;
		cairo_move_to(cr, cx + 1.5, cy - 7);
		cairo_line_to(cr, cx - 3.5, cy + 1);
		cairo_line_to(cr, cx - 0.2, cy + 1);
		cairo_line_to(cr, cx - 1.5, cy + 7);
		cairo_line_to(cr, cx + 3.5, cy - 1);
		cairo_line_to(cr, cx + 0.2, cy - 1);
		cairo_close_path(cr);
		cairo_set_source_rgb(cr, 1, 1, 1);
		cairo_fill_preserve(cr);
		cairo_set_source_rgba(cr, 0, 0, 0, 0.5);
		cairo_set_line_width(cr, 0.8);
		cairo_stroke(cr);
	}
	return FALSE;
}

static void fill_extras(Extras *ex)
{
	if(shown.have_battery) {
		char *text = g_strdup_printf("%d%%", shown.percent);
		gtk_label_set_text(GTK_LABEL(ex->battery_label), text);
		g_free(text);
		gtk_widget_set_tooltip_text(ex->battery, !g_strcmp0(shown.power, "charging") ? "Charging"
		                            : !g_strcmp0(shown.power, "plugged") ? "Power Adapter" : "Battery");
		gtk_widget_queue_draw(ex->battery_icon);
		gtk_widget_show(ex->battery);
	} else {
		gtk_widget_hide(ex->battery);
	}

	GList *old = gtk_container_get_children(GTK_CONTAINER(ex->column));
	for(GList *l = old; l; l = l->next) gtk_widget_destroy(l->data);
	g_list_free(old);
	/* Room between the clock and the person below: as many cards as fit,
	 * keeping a line for "2 more notifications" when not all of them do. */
	gboolean with_message = shown.message && shown.message[0];
	int below = PERSON_HEIGHT + (with_message ? MESSAGE_HEIGHT : 0);
	int space = ex->height > 0 ? ex->height - COLUMN_TOP - below - 12 : 3 * CARD_STEP;
	guint total = shown.notes ? shown.notes->len : 0;
	int cards = space / CARD_STEP;
	if(shown.have_playing) cards--;
	if(cards < (int)total || shown.more > 0) cards = (space - MORE_HEIGHT) / CARD_STEP - (shown.have_playing ? 1 : 0);
	guint fits = cards > 0 ? MIN(total, (guint)cards) : 0;
	int hidden = shown.more + (int)(total - fits);
	if(shown.have_playing)
		gtk_box_pack_start(GTK_BOX(ex->column), playing_card(), FALSE, FALSE, 0);
	for(guint i = 0; i < fits; i++)
		gtk_box_pack_start(GTK_BOX(ex->column), note_card(g_ptr_array_index(shown.notes, i)), FALSE, FALSE, 0);
	if(hidden > 0) {
		char *text = g_strdup_printf(hidden == 1 ? "%d more notification" : "%d more notifications", hidden);
		GtkWidget *more = gtk_label_new(text);
		gtk_widget_set_name(more, "latch-more");
		g_free(text);
		gtk_box_pack_start(GTK_BOX(ex->column), more, FALSE, FALSE, 0);
	}
	gtk_widget_show_all(ex->column);

	if(shown.message && shown.message[0]) {
		gtk_label_set_text(GTK_LABEL(ex->message), shown.message);
		gtk_widget_show(ex->message);
	} else {
		gtk_widget_hide(ex->message);
	}
}

static void fill_all(void)
{
	for(GSList *l = all_extras; l; l = l->next) fill_extras(l->data);
}

static void read_next(void);

static void got_line(GObject *source, GAsyncResult *result, gpointer data)
{
	(void)data;
	gsize length;
	char *line = g_data_input_stream_read_line_finish_utf8(G_DATA_INPUT_STREAM(source), result, &length, NULL);
	if(!line) {
		g_clear_object(&feed_out);
		g_clear_object(&feed);
		feed_in = NULL;
		return;      /* the feed ended; what it last sent stays */
	}
	if(g_getenv("FREEMAC_LATCH_DEBUG")) g_printerr("latch: %s\n", line);
	if(!strcmp(line, "end")) {
		shown_clear();
		for(guint i = 0; i < reading->len; i++) take_line(g_ptr_array_index(reading, i));
		g_ptr_array_set_size(reading, 0);
		fill_all();
	} else {
		g_ptr_array_add(reading, line);
		line = NULL;
	}
	g_free(line);
	read_next();
}

static void read_next(void)
{
	if(feed_out) g_data_input_stream_read_line_async(feed_out, G_PRIORITY_DEFAULT, NULL, got_line, NULL);
}

static void start_feed(void)
{
	if(feed) return;
	reading = g_ptr_array_new_with_free_func(g_free);
	shown_clear();
	char *program = g_find_program_in_path("freemac-lock");
	if(!program) return;
	/* Python takes a moment to start; notifications from that moment on count. */
	char *since = g_strdup_printf("%" G_GINT64_FORMAT, (gint64)time(NULL));
	feed = g_subprocess_new(G_SUBPROCESS_FLAGS_STDIN_PIPE | G_SUBPROCESS_FLAGS_STDOUT_PIPE, NULL,
	                        program, "--feed", since, NULL);
	g_free(since);
	g_free(program);
	if(!feed) return;
	feed_in = g_subprocess_get_stdin_pipe(feed);
	feed_out = g_data_input_stream_new(g_subprocess_get_stdout_pipe(feed));
	read_next();
}

/* "5m ago" moves on while the screen stays locked. */
static gboolean refresh(gpointer data)
{
	(void)data;
	if(all_extras && shown.notes && shown.notes->len) fill_all();
	return G_SOURCE_CONTINUE;
}

static void window_gone(GtkWidget *window, gpointer data)
{
	(void)window;
	all_extras = g_slist_remove(all_extras, data);
	g_free(data);
}

static void add_extras(struct Window *win)
{
	Extras *ex = g_new0(Extras, 1);
	ex->window = win->window;
	GdkRectangle area = {0};
	if(win->monitor) gdk_monitor_get_geometry(win->monitor, &area);
	ex->height = area.height;

	ex->battery = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
	gtk_widget_set_name(ex->battery, "latch-battery");
	gtk_widget_set_halign(ex->battery, GTK_ALIGN_END);
	gtk_widget_set_valign(ex->battery, GTK_ALIGN_START);
	gtk_widget_set_margin_top(ex->battery, 14);
	gtk_widget_set_margin_end(ex->battery, 20);
	ex->battery_label = gtk_label_new("");
	gtk_widget_set_name(ex->battery_label, "battery-label");
	ex->battery_icon = gtk_drawing_area_new();
	gtk_widget_set_size_request(ex->battery_icon, 30, 13);
	gtk_widget_set_valign(ex->battery_icon, GTK_ALIGN_CENTER);
	g_signal_connect(ex->battery_icon, "draw", G_CALLBACK(draw_battery), NULL);
	gtk_box_pack_start(GTK_BOX(ex->battery), ex->battery_label, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(ex->battery), ex->battery_icon, FALSE, FALSE, 0);
	gtk_widget_show(ex->battery_label);
	gtk_widget_show(ex->battery_icon);
	gtk_widget_set_no_show_all(ex->battery, TRUE);
	gtk_overlay_add_overlay(GTK_OVERLAY(win->overlay), ex->battery);
	gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(win->overlay), ex->battery, TRUE);

	/* Under the clock; it takes clicks only where its cards are. */
	ex->column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
	gtk_widget_set_halign(ex->column, GTK_ALIGN_CENTER);
	gtk_widget_set_valign(ex->column, GTK_ALIGN_START);
	gtk_widget_set_margin_top(ex->column, COLUMN_TOP);
	gtk_overlay_add_overlay(GTK_OVERLAY(win->overlay), ex->column);

	ex->message = gtk_label_new("");
	gtk_widget_set_name(ex->message, "message-label");
	gtk_label_set_line_wrap(GTK_LABEL(ex->message), TRUE);
	gtk_label_set_max_width_chars(GTK_LABEL(ex->message), 60);
	gtk_label_set_justify(GTK_LABEL(ex->message), GTK_JUSTIFY_CENTER);
	gtk_widget_set_halign(ex->message, GTK_ALIGN_CENTER);
	gtk_widget_set_margin_top(ex->message, 4);
	gtk_widget_set_no_show_all(ex->message, TRUE);
	gtk_box_pack_end(GTK_BOX(win->window_box), ex->message, FALSE, FALSE, 0);

	all_extras = g_slist_prepend(all_extras, ex);
	g_signal_connect(win->window, "destroy", G_CALLBACK(window_gone), ex);
	static gboolean ticking = FALSE;
	if(!ticking) {
		g_timeout_add_seconds(30, refresh, NULL);
		ticking = TRUE;
	}
	start_feed();
	fill_extras(ex);
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

	add_extras(win);
}
