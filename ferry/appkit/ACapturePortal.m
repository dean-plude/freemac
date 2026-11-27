/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Screen capture's Wayland back end (freemac 1.240, Ferry 0.64.0): see
 * ACapture.h. On Wayland (freemac's own desktop is Wayfire) an app can't
 * read the screen itself. The way is the xdg-desktop-portal's ScreenCast
 * portal on the session bus, which asks the user and hands back a PipeWire
 * stream of the monitor or window they chose:
 *
 *   CreateSession, SelectSources (a monitor or a window, one of them; the
 *   pointer as metadata where the portal offers it, drawn in otherwise;
 *   persisted until the user revokes it, with the restore token the last
 *   Start gave), Start (the portal's own dialog), OpenPipeWireRemote
 *
 * each a Request whose Response signal carries the answer. The stream is
 * then read with libpipewire: BGRx, BGRA, RGBx or RGBA, in shared memory
 * (MemFd or MemPtr buffers, mapped by PipeWire), with the cursor, header
 * and crop metadata. Each frame is turned into B, G, R, X bytes for the
 * capture core, which scales it into the ring of IOSurfaces as it does
 * X11's. DMA-BUF isn't offered, so PipeWire's producer falls back to
 * shared memory.
 *
 * Every grabber is one portal session, on a thread of its own: the D-Bus
 * requests on a GLib main context of the thread's, then PipeWire's main
 * loop. A grabber asked for a source other than its session's (a display
 * stream turned into a window stream) starts another session, and so asks
 * again. The restore tokens are kept per app and per source in
 * ~/.config/freemac/screencast-restore.json, so that once the user has
 * chosen, later recordings of the same source start without the dialog.
 * The user's own say in freemac (screen-recording.json) is asked first,
 * as under X11; the portal's dialog is a second step.
 *
 * The displays and windows: Wayland lets no app list other apps' windows.
 * freemac's compositor answers on its IPC socket (AWayfire.m: Wayfire's
 * ipc-rules plugin, which Wayfire publishes with its own Python client),
 * so the displays are Wayfire's outputs, numbered as NSScreen numbers
 * them, and the windows its views, front to back, with Strata's process
 * ids. The portal's picker still decides which window is recorded: the
 * one the app asked for is what the dialog is opened for, and what the
 * user picks is what comes. Without Wayfire the displays come from
 * wl_output, and in place of other apps' windows there is one entry that
 * stands for the window the user will pick. Where the portal can't record
 * windows, a window is cut from its display's stream. A display's scale is
 * learned from its stream's first frame (the stream is in pixels, the
 * layout in points).
 *
 * GIO, libpipewire-0.3 and libwayland-client are this system's, opened
 * the first time they're needed (ferry_bus_symbol and ferry_capture_symbol,
 * src/host.c), so Ferry runs where they're missing. Their calls and the
 * PipeWire structures and SPA pod layouts used here are written from their
 * published documentation and headers' documented layouts, since the Mac
 * build can't include Linux headers. They are Linux libraries and AppKit
 * is Mac code, but both use the System V calling convention, and nothing
 * here is called on a thread PipeWire or GLib made: their callbacks come on
 * the session's own thread. */
#import "ACapture.h"
#import "AWayfire.h"
#include <errno.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

void *ferry_capture_symbol(const char *name); /* src/host.c */
void *ferry_bus_symbol(const char *name);     /* src/host.c */

/* ---- GIO ----------------------------------------------------------------------------------- */

typedef struct _GMainContext GMainContext;
typedef struct _GDBusConnection GDBusConnection;
typedef struct _GVariant GVariant;
typedef struct _GUnixFDList GUnixFDList;
typedef char GVariantType;
typedef struct {
    uint32_t domain;
    int code;
    char *message;
} GError;
typedef void (*GSignalCallback)(GDBusConnection *connection, const char *sender, const char *path,
                                const char *iface, const char *member, GVariant *parameters, void *data);

static struct {
    GDBusConnection *(*bus_get_sync)(int type, void *cancellable, GError **error);
    const char *(*unique_name)(GDBusConnection *c);
    GVariant *(*call_sync)(GDBusConnection *c, const char *bus, const char *path, const char *iface,
                           const char *method, GVariant *parameters, const GVariantType *reply, int flags,
                           int timeout, void *cancellable, GError **error);
    GVariant *(*call_fd_sync)(GDBusConnection *c, const char *bus, const char *path, const char *iface,
                              const char *method, GVariant *parameters, const GVariantType *reply, int flags,
                              int timeout, GUnixFDList *in, GUnixFDList **out, void *cancellable, GError **error);
    unsigned (*subscribe)(GDBusConnection *c, const char *sender, const char *iface, const char *member,
                          const char *path, const char *arg0, int flags, GSignalCallback callback, void *data,
                          void (*free_data)(void *));
    void (*unsubscribe)(GDBusConnection *c, unsigned id);
    GVariant *(*new_string)(const char *s);
    GVariant *(*new_object_path)(const char *s);
    GVariant *(*new_uint32)(uint32_t v);
    GVariant *(*new_boolean)(int b);
    GVariant *(*new_variant)(GVariant *v);
    GVariant *(*new_dict_entry)(GVariant *key, GVariant *value);
    GVariant *(*new_array)(const GVariantType *child, GVariant *const *children, size_t n);
    GVariant *(*new_tuple)(GVariant *const *children, size_t n);
    GVariant *(*child)(GVariant *v, size_t i);
    size_t (*n_children)(GVariant *v);
    const char *(*get_string)(GVariant *v, size_t *length);
    uint32_t (*get_uint32)(GVariant *v);
    int32_t (*get_int32)(GVariant *v);
    int32_t (*get_handle)(GVariant *v);
    GVariant *(*get_variant)(GVariant *v);
    GVariant *(*lookup_value)(GVariant *dict, const char *key, const GVariantType *type);
    int (*is_of_type)(GVariant *v, const GVariantType *type);
    void (*unref)(GVariant *v);
    GMainContext *(*context_new)(void);
    void (*push)(GMainContext *c);
    void (*pop)(GMainContext *c);
    int (*iteration)(GMainContext *c, int mayBlock);
    void (*context_unref)(GMainContext *c);
    void (*error_free)(GError *e);
    int (*fd_list_get)(GUnixFDList *list, int index, GError **error);
    void (*object_unref)(void *object);
} G;

static BOOL load_gio(void)
{
#define LOOK(field, name, from)                                                                                    \
    if (!(*(void **)&G.field = from(name)))                                                                        \
        return NO;
#define BUS(field, name) LOOK(field, name, ferry_bus_symbol)
    BUS(bus_get_sync, "g_bus_get_sync")
    BUS(unique_name, "g_dbus_connection_get_unique_name")
    BUS(call_sync, "g_dbus_connection_call_sync")
    BUS(call_fd_sync, "g_dbus_connection_call_with_unix_fd_list_sync")
    BUS(subscribe, "g_dbus_connection_signal_subscribe")
    BUS(unsubscribe, "g_dbus_connection_signal_unsubscribe")
    BUS(new_string, "g_variant_new_string")
    BUS(new_object_path, "g_variant_new_object_path")
    BUS(new_uint32, "g_variant_new_uint32")
    BUS(new_boolean, "g_variant_new_boolean")
    BUS(new_variant, "g_variant_new_variant")
    BUS(new_dict_entry, "g_variant_new_dict_entry")
    BUS(new_array, "g_variant_new_array")
    BUS(new_tuple, "g_variant_new_tuple")
    BUS(child, "g_variant_get_child_value")
    BUS(n_children, "g_variant_n_children")
    BUS(get_string, "g_variant_get_string")
    BUS(get_uint32, "g_variant_get_uint32")
    BUS(get_int32, "g_variant_get_int32")
    BUS(get_handle, "g_variant_get_handle")
    BUS(get_variant, "g_variant_get_variant")
    BUS(lookup_value, "g_variant_lookup_value")
    BUS(is_of_type, "g_variant_is_of_type")
    BUS(unref, "g_variant_unref")
    BUS(context_new, "g_main_context_new")
    BUS(push, "g_main_context_push_thread_default")
    BUS(pop, "g_main_context_pop_thread_default")
    BUS(iteration, "g_main_context_iteration")
    BUS(context_unref, "g_main_context_unref")
    BUS(error_free, "g_error_free")
    LOOK(fd_list_get, "g_unix_fd_list_get", ferry_capture_symbol)
    LOOK(object_unref, "g_object_unref", ferry_capture_symbol)
#undef BUS
#undef LOOK
    return YES;
}

/* ---- PipeWire and SPA --------------------------------------------------------------------- */

struct pw_main_loop;
struct pw_loop;
struct pw_context;
struct pw_core;
struct pw_stream;
struct pw_properties;
struct spa_pod {
    uint32_t size, type;
};
struct spa_chunk {
    uint32_t offset, size;
    int32_t stride, flags;
};
struct spa_data {
    uint32_t type, flags;
    int64_t fd;
    uint32_t mapoffset, maxsize;
    void *data;
    struct spa_chunk *chunk;
};
struct spa_meta {
    uint32_t type, size;
    void *data;
};
struct spa_buffer {
    uint32_t n_metas, n_datas;
    struct spa_meta *metas;
    struct spa_data *datas;
};
struct pw_buffer {
    struct spa_buffer *buffer;
    void *user_data;
    uint64_t size;
};
struct spa_meta_header {
    uint32_t flags, offset;
    int64_t pts, dts_offset;
    uint64_t seq;
};
struct spa_meta_region {
    int32_t x, y;
    uint32_t width, height;
};
struct spa_meta_bitmap {
    uint32_t format, width, height;
    int32_t stride;
    uint32_t offset;
};
struct spa_meta_cursor {
    uint32_t id, flags;
    int32_t x, y, hotX, hotY;
    uint32_t bitmapOffset;
};
struct pw_stream_events {
    uint32_t version;
    void (*destroy)(void *data);
    void (*state_changed)(void *data, int old, int state, const char *error);
    void (*control_info)(void *data, uint32_t id, const void *control);
    void (*io_changed)(void *data, uint32_t id, void *area, uint32_t size);
    void (*param_changed)(void *data, uint32_t id, const struct spa_pod *param);
    void (*add_buffer)(void *data, struct pw_buffer *buffer);
    void (*remove_buffer)(void *data, struct pw_buffer *buffer);
    void (*process)(void *data);
    void (*drained)(void *data);
    void (*command)(void *data, const void *command);
    void (*trigger_done)(void *data);
};
/* a struct spa_hook: a list link, the callbacks, removed and priv; more room than it needs */
typedef struct {
    void *words[12];
} SpaHook;

enum {
    SPA_TYPE_Id = 3, SPA_TYPE_Int = 4, SPA_TYPE_Rectangle = 10, SPA_TYPE_Fraction = 11, SPA_TYPE_Object = 15,
    SPA_TYPE_Choice = 19,
};
enum { SPA_TYPE_OBJECT_Format = 0x40003, SPA_TYPE_OBJECT_ParamBuffers = 0x40004, SPA_TYPE_OBJECT_ParamMeta = 0x40005 };
enum { SPA_PARAM_EnumFormat = 3, SPA_PARAM_Format = 4, SPA_PARAM_Buffers = 5, SPA_PARAM_Meta = 6 };
enum {
    SPA_FORMAT_mediaType = 1, SPA_FORMAT_mediaSubtype = 2, SPA_FORMAT_VIDEO_format = 0x20001,
    SPA_FORMAT_VIDEO_modifier = 0x20002, SPA_FORMAT_VIDEO_size = 0x20003, SPA_FORMAT_VIDEO_framerate = 0x20004,
};
enum { SPA_MEDIA_TYPE_video = 2, SPA_MEDIA_SUBTYPE_raw = 1 };
enum {
    SPA_VIDEO_FORMAT_RGBx = 7, SPA_VIDEO_FORMAT_BGRx = 8, SPA_VIDEO_FORMAT_xRGB = 9, SPA_VIDEO_FORMAT_xBGR = 10,
    SPA_VIDEO_FORMAT_RGBA = 11, SPA_VIDEO_FORMAT_BGRA = 12, SPA_VIDEO_FORMAT_ARGB = 13, SPA_VIDEO_FORMAT_ABGR = 14,
};
enum { SPA_CHOICE_None = 0, SPA_CHOICE_Range = 1, SPA_CHOICE_Enum = 3, SPA_CHOICE_Flags = 4 };
enum { SPA_PARAM_BUFFERS_dataType = 6, SPA_PARAM_META_type = 1, SPA_PARAM_META_size = 2 };
enum { SPA_META_Header = 1, SPA_META_VideoCrop = 2, SPA_META_Cursor = 5 };
enum { SPA_DATA_MemPtr = 1, SPA_DATA_MemFd = 2, SPA_DATA_DmaBuf = 3 };
enum { SPA_CHUNK_FLAG_CORRUPTED = 1, SPA_META_HEADER_FLAG_CORRUPTED = 2 };
enum { PW_DIRECTION_INPUT = 0, PW_STREAM_FLAG_AUTOCONNECT = 1, PW_STREAM_FLAG_MAP_BUFFERS = 4 };
enum { PW_STREAM_STATE_ERROR = -1, PW_STREAM_STATE_UNCONNECTED = 0, PW_STREAM_STATE_STREAMING = 3 };
#define CURSOR_META_SIZE(w, h) ((uint32_t)(sizeof(struct spa_meta_cursor) + sizeof(struct spa_meta_bitmap) + (w) * (h) * 4))

static struct {
    void (*init)(int *argc, char ***argv);
    struct pw_main_loop *(*main_loop_new)(const void *props);
    struct pw_loop *(*main_loop_get_loop)(struct pw_main_loop *l);
    int (*main_loop_run)(struct pw_main_loop *l);
    int (*main_loop_quit)(struct pw_main_loop *l);
    void (*main_loop_destroy)(struct pw_main_loop *l);
    struct pw_context *(*context_new)(struct pw_loop *l, struct pw_properties *props, size_t size);
    void (*context_destroy)(struct pw_context *c);
    struct pw_core *(*context_connect_fd)(struct pw_context *c, int fd, struct pw_properties *props, size_t size);
    int (*core_disconnect)(struct pw_core *c);
    struct pw_properties *(*properties_new_string)(const char *args);
    struct pw_stream *(*stream_new)(struct pw_core *c, const char *name, struct pw_properties *props);
    void (*stream_add_listener)(struct pw_stream *s, SpaHook *hook, const struct pw_stream_events *events, void *data);
    int (*stream_connect)(struct pw_stream *s, int direction, uint32_t target, int flags, const struct spa_pod **params,
                          uint32_t n);
    int (*stream_update_params)(struct pw_stream *s, const struct spa_pod **params, uint32_t n);
    struct pw_buffer *(*stream_dequeue_buffer)(struct pw_stream *s);
    int (*stream_queue_buffer)(struct pw_stream *s, struct pw_buffer *b);
    void (*stream_destroy)(struct pw_stream *s);
} PW;

static BOOL load_pipewire(void)
{
#define LOOK(field, name)                                                                                          \
    if (!(*(void **)&PW.field = ferry_capture_symbol(name)))                                                        \
        return NO;
    LOOK(init, "pw_init")
    LOOK(main_loop_new, "pw_main_loop_new")
    LOOK(main_loop_get_loop, "pw_main_loop_get_loop")
    LOOK(main_loop_run, "pw_main_loop_run")
    LOOK(main_loop_quit, "pw_main_loop_quit")
    LOOK(main_loop_destroy, "pw_main_loop_destroy")
    LOOK(context_new, "pw_context_new")
    LOOK(context_destroy, "pw_context_destroy")
    LOOK(context_connect_fd, "pw_context_connect_fd")
    LOOK(core_disconnect, "pw_core_disconnect")
    LOOK(properties_new_string, "pw_properties_new_string")
    LOOK(stream_new, "pw_stream_new")
    LOOK(stream_add_listener, "pw_stream_add_listener")
    LOOK(stream_connect, "pw_stream_connect")
    LOOK(stream_update_params, "pw_stream_update_params")
    LOOK(stream_dequeue_buffer, "pw_stream_dequeue_buffer")
    LOOK(stream_queue_buffer, "pw_stream_queue_buffer")
    LOOK(stream_destroy, "pw_stream_destroy")
#undef LOOK
    PW.init(NULL, NULL);
    return YES;
}

/* ---- SPA pods: built and read as SPA documents them (a size and a type, then the body,
 * padded to 8 bytes; an object's properties each a key, flags and a pod) ----------------- */

typedef struct {
    uint8_t bytes[1024];
    uint32_t length;
} Pod;

static void pod_put(Pod *p, const void *data, uint32_t n)
{
    if (p->length + n > sizeof p->bytes)
        return;
    memcpy(p->bytes + p->length, data, n);
    p->length += n;
}
static void pod_u32(Pod *p, uint32_t v) { pod_put(p, &v, 4); }
static void pod_pad(Pod *p)
{
    while (p->length % 8 && p->length < sizeof p->bytes)
        p->bytes[p->length++] = 0;
}
static uint32_t pod_begin(Pod *p, uint32_t type)
{
    uint32_t at = p->length;
    pod_u32(p, 0);
    pod_u32(p, type);
    return at;
}
static void pod_end(Pod *p, uint32_t at)
{
    uint32_t size = p->length - at - 8;
    memcpy(p->bytes + at, &size, 4);
    pod_pad(p);
}
static void pod_key(Pod *p, uint32_t key)
{
    pod_u32(p, key);
    pod_u32(p, 0);
}
static void pod_value(Pod *p, uint32_t type, const uint32_t *words, uint32_t n)
{
    uint32_t at = pod_begin(p, type);
    pod_put(p, words, n * 4);
    pod_end(p, at);
}
static void pod_id(Pod *p, uint32_t key, uint32_t v)
{
    pod_key(p, key);
    pod_value(p, SPA_TYPE_Id, &v, 1);
}
static void pod_int(Pod *p, uint32_t key, uint32_t v)
{
    pod_key(p, key);
    pod_value(p, SPA_TYPE_Int, &v, 1);
}
/* a choice of n values of `each` words: the first is the default */
static void pod_choice(Pod *p, uint32_t key, uint32_t kind, uint32_t type, uint32_t each, const uint32_t *words,
                       uint32_t n)
{
    pod_key(p, key);
    uint32_t at = pod_begin(p, SPA_TYPE_Choice);
    pod_u32(p, kind);
    pod_u32(p, 0);
    pod_u32(p, each * 4);
    pod_u32(p, type);
    pod_put(p, words, n * each * 4);
    pod_end(p, at);
}
static uint32_t pod_object(Pod *p, uint32_t type, uint32_t id)
{
    uint32_t at = pod_begin(p, SPA_TYPE_Object);
    pod_u32(p, type);
    pod_u32(p, id);
    return at;
}

/* the formats offered, best first: what the capture core uses as it is, then what's turned round */
static void enum_format(Pod *p)
{
    uint32_t at = pod_object(p, SPA_TYPE_OBJECT_Format, SPA_PARAM_EnumFormat);
    pod_id(p, SPA_FORMAT_mediaType, SPA_MEDIA_TYPE_video);
    pod_id(p, SPA_FORMAT_mediaSubtype, SPA_MEDIA_SUBTYPE_raw);
    const uint32_t formats[] = {SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRx, SPA_VIDEO_FORMAT_BGRA,
                                SPA_VIDEO_FORMAT_RGBx, SPA_VIDEO_FORMAT_RGBA};
    pod_choice(p, SPA_FORMAT_VIDEO_format, SPA_CHOICE_Enum, SPA_TYPE_Id, 1, formats, 5);
    const uint32_t sizes[] = {1920, 1080, 1, 1, 16384, 16384};
    pod_choice(p, SPA_FORMAT_VIDEO_size, SPA_CHOICE_Range, SPA_TYPE_Rectangle, 2, sizes, 3);
    const uint32_t rates[] = {60, 1, 0, 1, 360, 1};
    pod_choice(p, SPA_FORMAT_VIDEO_framerate, SPA_CHOICE_Range, SPA_TYPE_Fraction, 2, rates, 3);
    pod_end(p, at);
}

static void buffers_param(Pod *p)
{
    uint32_t at = pod_object(p, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers);
    const uint32_t types = (1u << SPA_DATA_MemPtr) | (1u << SPA_DATA_MemFd);
    pod_choice(p, SPA_PARAM_BUFFERS_dataType, SPA_CHOICE_Flags, SPA_TYPE_Int, 1, &types, 1);
    pod_end(p, at);
}

static void meta_param(Pod *p, uint32_t type, uint32_t size, BOOL ranged)
{
    uint32_t at = pod_object(p, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta);
    pod_id(p, SPA_PARAM_META_type, type);
    if (ranged) {
        const uint32_t sizes[] = {size, CURSOR_META_SIZE(1, 1), CURSOR_META_SIZE(1024, 1024)};
        pod_choice(p, SPA_PARAM_META_size, SPA_CHOICE_Range, SPA_TYPE_Int, 1, sizes, 3);
    } else
        pod_int(p, SPA_PARAM_META_size, size);
    pod_end(p, at);
}

/* A property's value in a pod object, a choice's default for a choice: its type, and its
 * body in words, or NULL. */
static const uint32_t *pod_find(const struct spa_pod *object, uint32_t key, uint32_t *type, uint32_t *size)
{
    if (!object || object->type != SPA_TYPE_Object || object->size < 8)
        return NULL;
    const uint8_t *body = (const uint8_t *)(object + 1), *end = body + object->size;
    const uint8_t *at = body + 8;
    while (at + 16 <= end) {
        uint32_t k, vsize, vtype;
        memcpy(&k, at, 4);
        memcpy(&vsize, at + 8, 4);
        memcpy(&vtype, at + 12, 4);
        const uint8_t *value = at + 16;
        if (value + vsize > end)
            return NULL;
        if (k == key) {
            if (vtype == SPA_TYPE_Choice) {
                if (vsize < 16)
                    return NULL;
                uint32_t each, etype;
                memcpy(&each, value + 8, 4);
                memcpy(&etype, value + 12, 4);
                if (16 + each > vsize)
                    return NULL;
                *type = etype;
                *size = each;
                return (const uint32_t *)(value + 16);
            }
            *type = vtype;
            *size = vsize;
            return (const uint32_t *)value;
        }
        at = value + ((vsize + 7) & ~7u);
    }
    return NULL;
}

/* ---- the restore tokens, per app and per source ------------------------------------------- */

static pthread_mutex_t tokens_lock = PTHREAD_MUTEX_INITIALIZER;

static NSString *tokens_path(void)
{
    const char *config = getenv("XDG_CONFIG_HOME");
    NSString *base = config && *config ? @(config) : [NSHomeDirectory() stringByAppendingPathComponent:@".config"];
    return [base stringByAppendingPathComponent:@"freemac/screencast-restore.json"];
}

static NSMutableDictionary *read_tokens(void)
{
    NSData *d = [NSData dataWithContentsOfFile:tokens_path()];
    id j = d ? [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingMutableContainers error:NULL] : nil;
    if (![j isKindOfClass:[NSMutableDictionary class]] || ![j[@"apps"] isKindOfClass:[NSMutableDictionary class]])
        j = [NSMutableDictionary dictionaryWithObject:[NSMutableDictionary dictionary] forKey:@"apps"];
    return j;
}

static NSString *stored_token(NSString *source)
{
    if (!source)
        return nil;
    pthread_mutex_lock(&tokens_lock);
    NSString *t = nil;
    @autoreleasepool {
        id app = read_tokens()[@"apps"][ACaptureAppKey()];
        id v = [app isKindOfClass:[NSDictionary class]] ? app[source] : nil;
        t = [v isKindOfClass:[NSString class]] && [v length] ? [v copy] : nil;
    }
    pthread_mutex_unlock(&tokens_lock);
    return [t autorelease];
}

static void store_token(NSString *source, NSString *token)
{
    if (!source)
        return;
    pthread_mutex_lock(&tokens_lock);
    @autoreleasepool {
        NSMutableDictionary *all = read_tokens();
        NSMutableDictionary *apps = all[@"apps"];
        NSString *key = ACaptureAppKey();
        NSMutableDictionary *app = [apps[key] isKindOfClass:[NSMutableDictionary class]] ? apps[key]
                                                                                         : [NSMutableDictionary dictionary];
        if (token)
            app[source] = token;
        else
            [app removeObjectForKey:source];
        apps[key] = app;
        NSString *path = tokens_path();
        [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        NSData *d = [NSJSONSerialization dataWithJSONObject:all options:NSJSONWritingPrettyPrinted error:NULL];
        if ([d writeToFile:path atomically:YES])
            chmod([path fileSystemRepresentation], 0600);
    }
    pthread_mutex_unlock(&tokens_lock);
}

/* ---- the session bus and the portal -------------------------------------------------------- */

#define PORTAL_BUS "org.freedesktop.portal.Desktop"
#define PORTAL_PATH "/org/freedesktop/portal/desktop"
#define SCREENCAST "org.freedesktop.portal.ScreenCast"

enum { SOURCE_MONITOR = 1, SOURCE_WINDOW = 2 };
enum { CURSOR_HIDDEN = 1, CURSOR_EMBEDDED = 2, CURSOR_METADATA = 4 };

/* Whether a session bus is there to connect to, without having D-Bus start one. */
static BOOL bus_present(void)
{
    const char *address = getenv("DBUS_SESSION_BUS_ADDRESS");
    if (address && *address)
        return YES;
    const char *dir = getenv("XDG_RUNTIME_DIR");
    if (!dir || !*dir)
        return NO;
    char path[4096];
    snprintf(path, sizeof path, "%s/bus", dir);
    struct stat st;
    return stat(path, &st) == 0 && (st.st_mode & 0170000) == 0140000;
}

/* a ScreenCast property: version, AvailableSourceTypes, AvailableCursorModes */
static BOOL portal_property(GDBusConnection *bus, const char *name, uint32_t *out, int timeout)
{
    GVariant *args[2] = {G.new_string(SCREENCAST), G.new_string(name)};
    GError *error = NULL;
    GVariant *reply = G.call_sync(bus, PORTAL_BUS, PORTAL_PATH, "org.freedesktop.DBus.Properties", "Get",
                                  G.new_tuple(args, 2), "(v)", 0, timeout, NULL, &error);
    if (!reply) {
        if (error)
            G.error_free(error);
        return NO;
    }
    GVariant *boxed = G.child(reply, 0);
    GVariant *v = G.get_variant(boxed);
    BOOL ok = G.is_of_type(v, "u");
    if (ok)
        *out = G.get_uint32(v);
    G.unref(v);
    G.unref(boxed);
    G.unref(reply);
    return ok;
}

static struct {
    BOOL reachable;
    uint32_t version, sourceTypes, cursorModes;
} portal;

BOOL ACapturePortalReachable(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!bus_present()) {
            ACaptureSayOnce("screen capture under Wayland needs the ScreenCast portal, and there's no session bus");
            return;
        }
        if (!load_gio()) {
            ACaptureSayOnce("screen capture under Wayland needs this system's GIO (libgio-2.0.so.0) to reach the "
                            "ScreenCast portal");
            return;
        }
        if (!load_pipewire()) {
            ACaptureSayOnce("screen capture under Wayland needs PipeWire's library (libpipewire-0.3.so.0), which "
                            "isn't installed");
            return;
        }
        GError *error = NULL;
        GDBusConnection *bus = G.bus_get_sync(2 /* G_BUS_TYPE_SESSION */, NULL, &error);
        if (!bus) {
            if (error)
                G.error_free(error);
            ACaptureSayOnce("screen capture under Wayland can't reach the session bus");
            return;
        }
        /* the first call may start the portal, which takes a moment */
        if (!portal_property(bus, "version", &portal.version, 5000)) {
            ACaptureSayOnce("screen capture under Wayland needs the ScreenCast portal (xdg-desktop-portal with a "
                            "back end such as xdg-desktop-portal-wlr), which doesn't answer on the session bus");
            G.object_unref(bus);
            return;
        }
        if (!portal_property(bus, "AvailableSourceTypes", &portal.sourceTypes, 3000))
            portal.sourceTypes = SOURCE_MONITOR;
        if (portal.version < 2 || !portal_property(bus, "AvailableCursorModes", &portal.cursorModes, 3000))
            portal.cursorModes = 0;
        G.object_unref(bus);
        portal.reachable = YES;
    });
    return portal.reachable;
}

/* ---- the displays and windows -------------------------------------------------------------- */

static pthread_mutex_t learned_lock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableDictionary *learned_scales;    /* display number: the scale its stream showed */
static NSMutableDictionary *display_names;     /* display number: its connector's name */

static CGFloat learned_scale(CGDirectDisplayID number)
{
    pthread_mutex_lock(&learned_lock);
    NSNumber *s = [[learned_scales[@(number)] retain] autorelease];
    pthread_mutex_unlock(&learned_lock);
    return s ? [s doubleValue] : 1;
}

static void learn_scale(CGDirectDisplayID number, CGFloat scale)
{
    if (!(scale > 0.2 && scale < 8))
        return;
    scale = round(scale * 4) / 4;    /* the scales compositors use: whole numbers and quarters */
    pthread_mutex_lock(&learned_lock);
    if (!learned_scales)
        learned_scales = [[NSMutableDictionary alloc] init];
    learned_scales[@(number)] = @(scale);
    pthread_mutex_unlock(&learned_lock);
}

static void name_display(CGDirectDisplayID number, NSString *name)
{
    pthread_mutex_lock(&learned_lock);
    if (!display_names)
        display_names = [[NSMutableDictionary alloc] init];
    if ([name length])
        display_names[@(number)] = name;
    pthread_mutex_unlock(&learned_lock);
}

static NSString *display_name(CGDirectDisplayID number)
{
    pthread_mutex_lock(&learned_lock);
    NSString *n = [[display_names[@(number)] retain] autorelease];
    pthread_mutex_unlock(&learned_lock);
    return n ?: [NSString stringWithFormat:@"%u", number];
}

static ACaptureDisplay *make_display(CGDirectDisplayID number, CGRect points, CGFloat scale, double refresh)
{
    ACaptureDisplay *d = [[[ACaptureDisplay alloc] init] autorelease];
    d->number = number;
    d->frame = points;
    d->scale = scale;
    d->pixelFrame = CGRectMake(points.origin.x * scale, points.origin.y * scale, points.size.width * scale,
                               points.size.height * scale);
    d->refreshRate = refresh > 0 ? refresh : 60;
    return d;
}

/* -- wl_output, for a compositor that isn't Wayfire: the core protocol's events, version 4 -- */

struct wl_interface {
    const char *name;
    int version, methodCount;
    const void *methods;
    int eventCount;
    const void *events;
};
union wl_argument {
    int32_t i;
    uint32_t u;
    const char *s;
    void *o;
    uint32_t n;
};
static struct {
    void *(*display_connect)(const char *name);
    void (*display_disconnect)(void *display);
    int (*display_roundtrip)(void *display);
    void *(*marshal)(void *proxy, uint32_t opcode, const struct wl_interface *iface, uint32_t version, uint32_t flags,
                     union wl_argument *args);
    int (*add_listener)(void *proxy, void (**listener)(void), void *data);
    void (*proxy_destroy)(void *proxy);
    const struct wl_interface *registry_interface, *output_interface;
} WL;

typedef struct {
    void *proxy;
    int32_t x, y, width, height, scale, transform, refresh;
    char name[64];
} WlOutput;
typedef struct {
    void *registry;
    WlOutput outputs[8];
    int count;
} WlListing;

static void wl_global(void *data, void *registry, uint32_t name, const char *iface, uint32_t version)
{
    WlListing *l = data;
    if (strcmp(iface, "wl_output") || l->count >= 8)
        return;
    WlOutput *o = &l->outputs[l->count++];
    memset(o, 0, sizeof *o);
    o->scale = 1;
    uint32_t v = version < 4 ? version : 4;
    union wl_argument args[4];
    args[0].u = name;
    args[1].s = WL.output_interface->name;
    args[2].u = v;
    args[3].o = NULL;
    o->proxy = WL.marshal(registry, 0 /* bind */, WL.output_interface, v, 0, args);
}
static void wl_global_remove(void *data, void *registry, uint32_t name) {}
static void wl_geometry(void *data, void *out, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t subpixel,
                        const char *make, const char *model, int32_t transform)
{
    WlOutput *o = data;
    o->x = x;
    o->y = y;
    o->transform = transform;
}
static void wl_mode(void *data, void *out, uint32_t flags, int32_t w, int32_t h, int32_t refresh)
{
    WlOutput *o = data;
    if (flags & 1) {    /* the current mode */
        o->width = w;
        o->height = h;
        o->refresh = refresh;
    }
}
static void wl_done(void *data, void *out) {}
static void wl_scale(void *data, void *out, int32_t factor)
{
    WlOutput *o = data;
    o->scale = factor > 0 ? factor : 1;
}
static void wl_name(void *data, void *out, const char *name)
{
    WlOutput *o = data;
    snprintf(o->name, sizeof o->name, "%s", name ?: "");
}
static void wl_description(void *data, void *out, const char *description) {}

static BOOL wl_loaded;
static void open_wayland(void)
{
#define LOOK(field, name)                                                                                          \
    if (!(*(void **)&WL.field = ferry_capture_symbol(name)))                                                        \
        return;
    LOOK(display_connect, "wl_display_connect")
    LOOK(display_disconnect, "wl_display_disconnect")
    LOOK(display_roundtrip, "wl_display_roundtrip")
    LOOK(marshal, "wl_proxy_marshal_array_flags")
    LOOK(add_listener, "wl_proxy_add_listener")
    LOOK(proxy_destroy, "wl_proxy_destroy")
    LOOK(registry_interface, "wl_registry_interface")
    LOOK(output_interface, "wl_output_interface")
#undef LOOK
    wl_loaded = YES;
}

static uint64_t now_ns(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000000000ull + (uint64_t)tv.tv_usec * 1000ull;
}

/* The compositor's outputs, kept for two seconds: each one's position from its geometry,
 * and its size in points its current mode over its scale. */
static NSArray *wl_output_displays(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static NSArray *kept;
    static uint64_t keptAt;
    pthread_once(&once, open_wayland);
    if (!wl_loaded)
        return @[];
    pthread_mutex_lock(&lock);
    if (kept && now_ns() - keptAt < 2000000000ull) {
        NSArray *k = [[kept retain] autorelease];
        pthread_mutex_unlock(&lock);
        return k;
    }
    NSMutableArray *out = [NSMutableArray array];
    void *display = WL.display_connect(NULL);
    if (display) {
        WlListing l;
        memset(&l, 0, sizeof l);
        static void (*registry_listener[])(void) = {(void (*)(void))wl_global, (void (*)(void))wl_global_remove};
        static void (*output_listener[])(void) = {(void (*)(void))wl_geometry, (void (*)(void))wl_mode,
                                                  (void (*)(void))wl_done,     (void (*)(void))wl_scale,
                                                  (void (*)(void))wl_name,     (void (*)(void))wl_description};
        union wl_argument args[1];
        args[0].o = NULL;
        l.registry = WL.marshal(display, 1 /* get_registry */, WL.registry_interface, 1, 0, args);
        if (l.registry) {
            WL.add_listener(l.registry, registry_listener, &l);
            WL.display_roundtrip(display);
            for (int i = 0; i < l.count; i++)
                if (l.outputs[i].proxy)
                    WL.add_listener(l.outputs[i].proxy, output_listener, &l.outputs[i]);
            WL.display_roundtrip(display);
            CGPoint main = CGPointZero;
            for (int i = 0; i < l.count; i++) {
                WlOutput *o = &l.outputs[i];
                if (o->proxy)
                    WL.proxy_destroy(o->proxy);
                if (o->width <= 0 || o->height <= 0)
                    continue;
                BOOL turned = o->transform & 1;    /* 90 or 270 degrees, flipped or not */
                CGFloat w = (turned ? o->height : o->width) / (CGFloat)o->scale,
                        h = (turned ? o->width : o->height) / (CGFloat)o->scale;
                if (![out count])
                    main = CGPointMake(o->x, o->y);
                CGDirectDisplayID number = (CGDirectDisplayID)[out count] + 1;
                [out addObject:make_display(number, CGRectMake(o->x - main.x, o->y - main.y, w, h), o->scale,
                                            o->refresh / 1000.0)];
                if (o->name[0])
                    name_display(number, @(o->name));
            }
            WL.proxy_destroy(l.registry);
        }
        WL.display_disconnect(display);
    }
    id wasKept = kept;
    kept = [out copy];
    [wasKept release];
    keptAt = now_ns();
    pthread_mutex_unlock(&lock);
    return out;
}

/* -- Wayfire's outputs and views -- */

static NSArray *wayfire_displays(NSArray *outputs)
{
    NSMutableArray *out = [NSMutableArray array];
    NSRect main = [[outputs firstObject][@"frame"] rectValue];
    for (NSDictionary *o in outputs) {
        NSRect f = [o[@"frame"] rectValue];
        CGDirectDisplayID number = (CGDirectDisplayID)[o[@"id"] unsignedIntValue];
        name_display(number, o[@"name"]);
        CGRect points = CGRectMake(f.origin.x - main.origin.x, f.origin.y - main.origin.y, f.size.width, f.size.height);
        [out addObject:make_display(number, points, learned_scale(number), 60)];
    }
    return out;
}

static NSArray *portal_displays(void)
{
    NSArray *outputs = AWayfireAvailable() ? AWayfireOutputs() : nil;
    return outputs ? wayfire_displays(outputs) : wl_output_displays();
}

static NSString *owner_from_app_id(id appID)
{
    if (![appID isKindOfClass:[NSString class]] || ![appID length])
        return @"";
    NSString *s = appID;
    NSRange dot = [s rangeOfString:@"." options:NSBackwardsSearch];
    if (dot.location != NSNotFound && dot.location + 1 < [s length] && [[s componentsSeparatedByString:@"."] count] > 2)
        return [s substringFromIndex:dot.location + 1];
    return s;
}

static CGRect json_rect(id j)
{
    if (![j isKindOfClass:[NSDictionary class]])
        return CGRectZero;
    return CGRectMake([j[@"x"] doubleValue], [j[@"y"] doubleValue], [j[@"width"] doubleValue], [j[@"height"] doubleValue]);
}

/* a rect in points into the back end's pixels, by the scale of the display it's on */
static CGRect to_pixels(CGRect points, NSArray *displays)
{
    ACaptureDisplay *on = [displays firstObject];
    for (ACaptureDisplay *d in displays)
        if (CGRectContainsPoint(d->frame, CGPointMake(CGRectGetMidX(points), CGRectGetMidY(points))))
            on = d;
    if (!on)
        return points;
    CGFloat s = on->scale;
    return CGRectMake(on->pixelFrame.origin.x + (points.origin.x - on->frame.origin.x) * s,
                      on->pixelFrame.origin.y + (points.origin.y - on->frame.origin.y) * s, points.size.width * s,
                      points.size.height * s);
}

/* the handle of the entry that stands for the window the user will pick */
static const uint64_t picked_window = 0xffffffffull;

static NSArray *portal_windows(void)
{
    NSMutableArray *out = [NSMutableArray array];
    id list = AWayfireAvailable() ? AWayfireCall(@"window-rules/list-views", nil) : nil;
    NSArray *outputs = [list isKindOfClass:[NSArray class]] ? AWayfireOutputs() : nil;
    if (!outputs) {
        if (ACapturePortalReachable() && (portal.sourceTypes & SOURCE_WINDOW)) {
            ACaptureDisplay *main = [portal_displays() firstObject];
            ACaptureWindow *w = [[[ACaptureWindow alloc] init] autorelease];
            w->handle = picked_window;
            w->title = [@"The window chosen when recording starts" copy];
            w->owner = [@"" copy];
            w->bundleID = [@"" copy];
            w->frame = main ? main->frame : CGRectMake(0, 0, 1280, 800);
            w->pixelFrame = main ? main->pixelFrame : w->frame;
            w->onscreen = YES;
            [out addObject:w];
        }
        return out;
    }
    NSMutableDictionary *pids = [NSMutableDictionary dictionary];
    id reply = AWayfireCall(@"strata/view-pids", nil);
    id views = [reply isKindOfClass:[NSDictionary class]] ? reply[@"views"] : nil;
    if ([views isKindOfClass:[NSArray class]])
        for (id v in views)
            if ([v isKindOfClass:[NSDictionary class]] && v[@"id"] && v[@"pid"])
                pids[@([v[@"id"] longLongValue])] = @([v[@"pid"] intValue]);
    NSMutableArray *toplevels = [NSMutableArray array];
    for (id v in list) {
        if (![v isKindOfClass:[NSDictionary class]])
            continue;
        id kind = v[@"role"] ?: v[@"type"];
        if ([kind isEqual:@"toplevel"])
            [toplevels addObject:v];
    }
    [toplevels sortUsingComparator:^NSComparisonResult(id a, id b) {
        double ta = [a[@"last-focus-timestamp"] doubleValue], tb = [b[@"last-focus-timestamp"] doubleValue];
        return ta > tb ? NSOrderedAscending : ta < tb ? NSOrderedDescending : NSOrderedSame;
    }];
    NSArray *displays = wayfire_displays(outputs);
    NSRect main = [[outputs firstObject][@"frame"] rectValue];
    for (NSDictionary *v in toplevels) {
        int64_t view = [v[@"id"] longLongValue];
        CGRect r = json_rect(v[@"geometry"]);
        NSRect of = main;
        for (NSDictionary *o in outputs)
            if ([o[@"id"] longLongValue] == [v[@"output-id"] longLongValue])
                of = [o[@"frame"] rectValue];
        r.origin.x += of.origin.x - main.origin.x;
        r.origin.y += of.origin.y - main.origin.y;
        id title = v[@"title"], appID = v[@"app-id"], mapped = v[@"mapped"];
        ACaptureWindow *w = [[[ACaptureWindow alloc] init] autorelease];
        w->handle = (uint64_t)view;
        w->pid = [pids[@(view)] intValue];
        w->title = [([title isKindOfClass:[NSString class]] ? title : @"") copy];
        w->owner = [owner_from_app_id(appID) copy];
        w->bundleID = [([appID isKindOfClass:[NSString class]] ? appID : @"") copy];
        w->frame = r;
        w->pixelFrame = to_pixels(r, displays);
        w->onscreen = (!mapped || [mapped boolValue]) && ![v[@"minimized"] boolValue];
        [out addObject:w];
    }
    return out;
}

static ACaptureWindow *window_with_handle(uint64_t handle)
{
    for (ACaptureWindow *w in portal_windows())
        if (w->handle == handle)
            return w;
    return nil;
}

static ACaptureDisplay *display_numbered(NSArray *displays, CGDirectDisplayID number)
{
    for (ACaptureDisplay *d in displays)
        if (d->number == number)
            return d;
    return nil;
}

/* ---- a portal session and its PipeWire stream, on a thread of its own --------------------- */

enum { ASKING = 0, STREAMING = 1, FAILED = 2, ENDED = 3 };

typedef struct Session {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    int refs;
    /* asked for */
    uint32_t kind;                  /* SOURCE_MONITOR or SOURCE_WINDOW */
    CGDirectDisplayID display;
    uint64_t window;
    BOOL showsCursor;
    char source[256];               /* the restore token's key */
    volatile int quit;
    /* the portal's answer */
    int state;
    NSInteger failCode;
    char why[256];
    uint32_t cursorMode, node;
    BOOL hasPosition;
    int32_t posX, posY, sizeW, sizeH;
    /* PipeWire's */
    struct pw_main_loop *loop;    /* while it runs, for session_stop */
    struct pw_stream *stream;
    BOOL closing;                 /* the stream is being taken down: its last states aren't news */
    SpaHook hook;
    uint32_t format, width, height;
    /* the latest frame, B, G, R, X */
    uint8_t *frame;
    size_t fw, fh, fcap;
    uint64_t serial;
    /* the pointer, premultiplied 0xAARRGGBB, at its place in the stream's pixels */
    uint32_t *cursor;
    size_t cw, ch, ccap;
    int32_t cx, cy, hx, hy;
    BOOL cursorShown;
} Session;

static void session_release(Session *s)
{
    pthread_mutex_lock(&s->lock);
    int left = --s->refs;
    pthread_mutex_unlock(&s->lock);
    if (left)
        return;
    pthread_mutex_destroy(&s->lock);
    pthread_cond_destroy(&s->cond);
    free(s->frame);
    free(s->cursor);
    free(s);
}

static void session_fail(Session *s, NSInteger code, const char *why)
{
    pthread_mutex_lock(&s->lock);
    if (s->state != FAILED) {
        s->state = FAILED;
        s->failCode = code;
        snprintf(s->why, sizeof s->why, "%s", why);
    }
    pthread_cond_broadcast(&s->cond);
    pthread_mutex_unlock(&s->lock);
}

/* -- the Request and Response dance -- */

typedef struct {
    GDBusConnection *bus;
    GMainContext *context;
    Session *session;
    char sender[128];
    unsigned counter;
    char path[256], handle[256];
    BOOL answered;
    uint32_t code;
    GVariant *results;
} Portal;

static void on_response(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                        const char *member, GVariant *params, void *data)
{
    Portal *p = data;
    if (p->answered || !path || (strcmp(path, p->path) && strcmp(path, p->handle)))
        return;
    if (!G.is_of_type(params, "(ua{sv})"))
        return;
    GVariant *code = G.child(params, 0);
    p->code = G.get_uint32(code);
    G.unref(code);
    p->results = G.child(params, 1);
    p->answered = YES;
}

/* an a{sv}: n keys and their values (each taken, as GVariants are) */
static GVariant *options(const char *const *keys, GVariant *const *values, size_t n)
{
    GVariant *entries[16];
    for (size_t i = 0; i < n && i < 16; i++)
        entries[i] = G.new_dict_entry(G.new_string(keys[i]), G.new_variant(values[i]));
    return G.new_array("{sv}", entries, n < 16 ? n : 16);
}

/* Calls one of ScreenCast's methods and waits for its Response, as long as `seconds` or until the
 * session is closed. The arguments come first, then the options with the request's token added.
 * The answer's code (0 done, 1 the user cancelled, 2 otherwise), or -1 with no answer. */
static int request(Portal *p, const char *method, GVariant **args, size_t nargs, const char **keys,
                   GVariant **values, size_t nvalues, double seconds, GVariant **results)
{
    *results = NULL;
    char token[64];
    snprintf(token, sizeof token, "ferry%d_%u", (int)getpid(), ++p->counter);
    snprintf(p->path, sizeof p->path, PORTAL_PATH "/request/%s/%s", p->sender, token);
    p->handle[0] = 0;
    p->answered = NO;
    p->results = NULL;
    unsigned sub = G.subscribe(p->bus, NULL, "org.freedesktop.portal.Request", "Response", NULL, NULL, 0,
                               on_response, p, NULL);
    const char *k[16];
    GVariant *v[16];
    size_t n = 0;
    k[n] = "handle_token";
    v[n++] = G.new_string(token);
    for (size_t i = 0; i < nvalues && n < 16; i++) {
        k[n] = keys[i];
        v[n++] = values[i];
    }
    GVariant *all[8];
    size_t count = 0;
    for (size_t i = 0; i < nargs && count < 7; i++)
        all[count++] = args[i];
    all[count++] = options(k, v, n);
    GError *error = NULL;
    GVariant *reply = G.call_sync(p->bus, PORTAL_BUS, PORTAL_PATH, SCREENCAST, method, G.new_tuple(all, count), "(o)",
                                  0, 30000, NULL, &error);
    if (!reply) {
        if (error)
            G.error_free(error);
        G.unsubscribe(p->bus, sub);
        return -1;
    }
    GVariant *h = G.child(reply, 0);
    snprintf(p->handle, sizeof p->handle, "%s", G.get_string(h, NULL));
    G.unref(h);
    G.unref(reply);
    uint64_t until = now_ns() + (uint64_t)(seconds * 1e9);
    while (!p->answered && !p->session->quit && now_ns() < until)
        if (!G.iteration(p->context, 0))
            usleep(5000);
    G.unsubscribe(p->bus, sub);
    if (!p->answered) {
        /* nobody waits for it any more */
        GVariant *none = NULL;
        GVariant *r = G.call_sync(p->bus, PORTAL_BUS, p->handle, "org.freedesktop.portal.Request", "Close",
                                  G.new_tuple(&none, 0), NULL, 0, 2000, NULL, &error);
        if (r)
            G.unref(r);
        else if (error)
            G.error_free(error);
        return -1;
    }
    *results = p->results;
    return (int)p->code;
}

static NSString *lookup_string(GVariant *dict, const char *key)
{
    GVariant *v = dict ? G.lookup_value(dict, key, "s") : NULL;
    if (!v)
        v = dict ? G.lookup_value(dict, key, "o") : NULL;
    if (!v)
        return nil;
    NSString *s = [NSString stringWithUTF8String:G.get_string(v, NULL)];
    G.unref(v);
    return s;
}

static BOOL lookup_pair(GVariant *dict, const char *key, int32_t *a, int32_t *b)
{
    GVariant *v = dict ? G.lookup_value(dict, key, "(ii)") : NULL;
    if (!v)
        return NO;
    GVariant *x = G.child(v, 0), *y = G.child(v, 1);
    *a = G.get_int32(x);
    *b = G.get_int32(y);
    G.unref(x);
    G.unref(y);
    G.unref(v);
    return YES;
}

/* -- PipeWire's side -- */

static void copy_frame(Session *s, const uint8_t *src, size_t stride, size_t w, size_t h)
{
    size_t need = w * h * 4;
    if (s->fcap < need) {
        free(s->frame);
        s->frame = malloc(need);
        s->fcap = s->frame ? need : 0;
        if (!s->frame)
            return;
    }
    BOOL swap = s->format == SPA_VIDEO_FORMAT_RGBx || s->format == SPA_VIDEO_FORMAT_RGBA;
    for (size_t y = 0; y < h; y++) {
        const uint8_t *from = src + y * stride;
        uint8_t *to = s->frame + y * w * 4;
        if (!swap)
            memcpy(to, from, w * 4);
        else
            for (size_t i = 0; i < w; i++) {
                to[4 * i] = from[4 * i + 2];
                to[4 * i + 1] = from[4 * i + 1];
                to[4 * i + 2] = from[4 * i];
                to[4 * i + 3] = from[4 * i + 3];
            }
    }
    s->fw = w;
    s->fh = h;
    s->serial++;
}

/* a cursor bitmap's pixel into premultiplied 0xAARRGGBB */
static uint32_t cursor_pixel(uint32_t format, const uint8_t *p)
{
    uint32_t r, g, b, a;
    switch (format) {
    case SPA_VIDEO_FORMAT_RGBA: r = p[0], g = p[1], b = p[2], a = p[3]; break;
    case SPA_VIDEO_FORMAT_BGRA: b = p[0], g = p[1], r = p[2], a = p[3]; break;
    case SPA_VIDEO_FORMAT_ARGB: a = p[0], r = p[1], g = p[2], b = p[3]; break;
    case SPA_VIDEO_FORMAT_ABGR: a = p[0], b = p[1], g = p[2], r = p[3]; break;
    default: return 0;
    }
    return (a << 24) | ((r * a / 255) << 16) | ((g * a / 255) << 8) | (b * a / 255);
}

static void read_cursor(Session *s, const struct spa_meta *m)
{
    if (m->size < sizeof(struct spa_meta_cursor) || !m->data)
        return;
    const struct spa_meta_cursor *c = m->data;
    if (!c->id)
        return;     /* nothing new */
    s->cx = c->x;
    s->cy = c->y;
    s->hx = c->hotX;
    s->hy = c->hotY;
    if (!c->bitmapOffset || c->bitmapOffset + sizeof(struct spa_meta_bitmap) > m->size)
        return;     /* moved, the same picture */
    const struct spa_meta_bitmap *bm = (const struct spa_meta_bitmap *)((const uint8_t *)c + c->bitmapOffset);
    size_t w = bm->width, h = bm->height;
    size_t stride = bm->stride > 0 ? (size_t)bm->stride : w * 4;
    if (!bm->format || !w || !h || c->bitmapOffset + bm->offset + stride * h > m->size) {
        s->cursorShown = NO;    /* no picture: the pointer is hidden */
        return;
    }
    if (s->ccap < w * h) {
        free(s->cursor);
        s->cursor = malloc(w * h * 4);
        s->ccap = s->cursor ? w * h : 0;
        if (!s->cursor)
            return;
    }
    const uint8_t *px = (const uint8_t *)bm + bm->offset;
    for (size_t y = 0; y < h; y++)
        for (size_t x = 0; x < w; x++)
            s->cursor[y * w + x] = cursor_pixel(bm->format, px + y * stride + x * 4);
    s->cw = w;
    s->ch = h;
    s->cursorShown = YES;
}

static void on_state(void *data, int old, int state, const char *error)
{
    Session *s = data;
    if (s->closing)
        return;
    if (state == PW_STREAM_STATE_ERROR || (state == PW_STREAM_STATE_UNCONNECTED && old > 0)) {
        char why[256];
        if (state == PW_STREAM_STATE_ERROR)
            snprintf(why, sizeof why, "The screen's stream failed (%s).", error ?: "PipeWire");
        else
            snprintf(why, sizeof why, "The screen cast ended.");
        session_fail(s, -3821, why);
        pthread_mutex_lock(&s->lock);
        if (s->loop)
            PW.main_loop_quit(s->loop);
        pthread_mutex_unlock(&s->lock);
    } else if (state == PW_STREAM_STATE_STREAMING) {
        pthread_mutex_lock(&s->lock);
        if (s->state == ASKING)
            s->state = STREAMING;
        pthread_mutex_unlock(&s->lock);
    }
}

static void on_param(void *data, uint32_t id, const struct spa_pod *param)
{
    Session *s = data;
    if (id != SPA_PARAM_Format || !param)
        return;
    uint32_t type = 0, size = 0;
    const uint32_t *v = pod_find(param, SPA_FORMAT_VIDEO_format, &type, &size);
    uint32_t format = v && type == SPA_TYPE_Id && size >= 4 ? v[0] : 0;
    v = pod_find(param, SPA_FORMAT_VIDEO_size, &type, &size);
    pthread_mutex_lock(&s->lock);
    s->format = format;
    if (v && type == SPA_TYPE_Rectangle && size >= 8) {
        s->width = v[0];
        s->height = v[1];
    }
    pthread_mutex_unlock(&s->lock);
    if (format != SPA_VIDEO_FORMAT_BGRx && format != SPA_VIDEO_FORMAT_BGRA && format != SPA_VIDEO_FORMAT_RGBx &&
        format != SPA_VIDEO_FORMAT_RGBA) {
        ACaptureSayOnce("the screen cast's stream came in a pixel format Ferry doesn't read");
        return;
    }
    if (pod_find(param, SPA_FORMAT_VIDEO_modifier, &type, &size))
        ACaptureSayOnce("the screen cast's stream asked for DMA-BUF, which Ferry doesn't read yet");
    Pod buffers = {{0}, 0}, header = {{0}, 0}, crop = {{0}, 0}, cursor = {{0}, 0};
    buffers_param(&buffers);
    meta_param(&header, SPA_META_Header, sizeof(struct spa_meta_header), NO);
    meta_param(&crop, SPA_META_VideoCrop, sizeof(struct spa_meta_region), NO);
    meta_param(&cursor, SPA_META_Cursor, CURSOR_META_SIZE(64, 64), YES);
    const struct spa_pod *params[4] = {(const struct spa_pod *)buffers.bytes, (const struct spa_pod *)header.bytes,
                                       (const struct spa_pod *)crop.bytes, (const struct spa_pod *)cursor.bytes};
    PW.stream_update_params(s->stream, params, s->cursorMode == CURSOR_METADATA ? 4 : 3);
}

static void on_process(void *data)
{
    Session *s = data;
    struct pw_buffer *b = NULL, *next;
    while ((next = PW.stream_dequeue_buffer(s->stream))) {
        if (b)
            PW.stream_queue_buffer(s->stream, b);
        b = next;    /* only the newest matters */
    }
    if (!b)
        return;
    struct spa_buffer *sb = b->buffer;
    pthread_mutex_lock(&s->lock);
    BOOL corrupted = NO;
    const struct spa_meta_region *region = NULL;
    for (uint32_t i = 0; sb && i < sb->n_metas; i++) {
        const struct spa_meta *m = &sb->metas[i];
        if (m->type == SPA_META_Header && m->data && m->size >= sizeof(struct spa_meta_header))
            corrupted = (((const struct spa_meta_header *)m->data)->flags & SPA_META_HEADER_FLAG_CORRUPTED) != 0;
        else if (m->type == SPA_META_VideoCrop && m->data && m->size >= sizeof(struct spa_meta_region))
            region = m->data;
        else if (m->type == SPA_META_Cursor)
            read_cursor(s, m);
    }
    if (sb && sb->n_datas && !corrupted) {
        const struct spa_data *d = &sb->datas[0];
        const struct spa_chunk *c = d->chunk;
        if (d->type == SPA_DATA_DmaBuf || !d->data)
            ACaptureSayOnce("the screen cast's buffers can't be read (DMA-BUF, which Ferry doesn't read yet)");
        else if (c && c->size && !(c->flags & SPA_CHUNK_FLAG_CORRUPTED) && s->width && s->height) {
            size_t stride = c->stride > 0 ? (size_t)c->stride : s->width * 4;
            const uint8_t *base = (const uint8_t *)d->data + c->offset;
            size_t x0 = 0, y0 = 0, w = s->width, h = s->height;
            if (region && region->width && region->height && region->x >= 0 && region->y >= 0 &&
                region->x + region->width <= s->width && region->y + region->height <= s->height) {
                x0 = (size_t)region->x, y0 = (size_t)region->y, w = region->width, h = region->height;
            }
            if ((size_t)c->offset + stride * (y0 + h) <= d->maxsize && stride >= (x0 + w) * 4)
                copy_frame(s, base + y0 * stride + x0 * 4, stride, w, h);
        }
    }
    pthread_cond_broadcast(&s->cond);
    pthread_mutex_unlock(&s->lock);
    PW.stream_queue_buffer(s->stream, b);
}

static const struct pw_stream_events stream_events = {
    .version = 2,
    .state_changed = on_state,
    .param_changed = on_param,
    .process = on_process,
};

static void read_stream(Session *s, int fd)
{
    s->loop = NULL;
    struct pw_main_loop *loop = PW.main_loop_new(NULL);
    struct pw_context *context = loop ? PW.context_new(PW.main_loop_get_loop(loop), NULL, 0) : NULL;
    struct pw_core *core = context ? PW.context_connect_fd(context, fd, NULL, 0) : NULL;
    if (!core) {
        if (context)
            PW.context_destroy(context);
        else if (fd >= 0)
            close(fd);
        if (loop)
            PW.main_loop_destroy(loop);
        session_fail(s, -3802, "PipeWire's screen cast connection couldn't be opened.");
        return;
    }
    s->stream = PW.stream_new(core, "Ferry screen capture",
                              PW.properties_new_string("media.type=Video media.category=Capture media.role=Screen"));
    if (s->stream) {
        s->loop = loop;
        PW.stream_add_listener(s->stream, &s->hook, &stream_events, s);
        Pod formats = {{0}, 0};
        enum_format(&formats);
        const struct spa_pod *params[1] = {(const struct spa_pod *)formats.bytes};
        if (PW.stream_connect(s->stream, PW_DIRECTION_INPUT, s->node,
                              PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, params, 1) < 0)
            session_fail(s, -3802, "The screen cast's stream couldn't be connected.");
        else {
            pthread_mutex_lock(&s->lock);
            BOOL go = !s->quit;
            pthread_mutex_unlock(&s->lock);
            if (go)
                PW.main_loop_run(loop);
        }
        pthread_mutex_lock(&s->lock);
        s->loop = NULL;
        pthread_mutex_unlock(&s->lock);
        s->closing = YES;
        PW.stream_destroy(s->stream);
        s->stream = NULL;
    } else
        session_fail(s, -3802, "The screen cast's stream couldn't be made.");
    PW.core_disconnect(core);
    PW.context_destroy(context);
    PW.main_loop_destroy(loop);
}

/* the session's thread: the portal's dialog, then the stream until it ends or is closed */
static void *session_main(void *arg)
{
    Session *s = arg;
    @autoreleasepool {
        Portal p;
        memset(&p, 0, sizeof p);
        p.session = s;
        p.context = G.context_new();
        G.push(p.context);
        GError *error = NULL;
        p.bus = G.bus_get_sync(2, NULL, &error);
        if (!p.bus) {
            if (error)
                G.error_free(error);
            session_fail(s, -3802, "The session bus can't be reached.");
            goto done;
        }
        /* the request paths name the caller: its unique name, ':' left out and '.' as '_' */
        const char *unique = G.unique_name(p.bus) ?: "";
        snprintf(p.sender, sizeof p.sender, "%s", unique[0] == ':' ? unique + 1 : unique);
        for (char *c = p.sender; *c; c++)
            if (*c == '.')
                *c = '_';

        GVariant *results = NULL;
        char sessionToken[64];
        snprintf(sessionToken, sizeof sessionToken, "ferry%d_session_%p", (int)getpid(), (void *)s);
        for (char *c = sessionToken; *c; c++)
            if (!((*c >= 'a' && *c <= 'z') || (*c >= 'A' && *c <= 'Z') || (*c >= '0' && *c <= '9') || *c == '_'))
                *c = '_';
        const char *createKeys[] = {"session_handle_token"};
        GVariant *createValues[] = {G.new_string(sessionToken)};
        int code = request(&p, "CreateSession", NULL, 0, createKeys, createValues, 1, 30, &results);
        NSString *handle = code == 0 ? lookup_string(results, "session_handle") : nil;
        if (results)
            G.unref(results);
        if (!handle) {
            session_fail(s, -3802, "The ScreenCast portal didn't make a session.");
            goto done;
        }

        /* the source, the pointer and the restore token */
        const char *keys[6];
        GVariant *values[6];
        size_t n = 0;
        keys[n] = "types", values[n++] = G.new_uint32(s->kind);
        keys[n] = "multiple", values[n++] = G.new_boolean(0);
        if (portal.version >= 2 && portal.cursorModes) {
            keys[n] = "cursor_mode";
            values[n++] = G.new_uint32(s->cursorMode);
        }
        NSString *source = @(s->source);
        if (portal.version >= 4) {
            keys[n] = "persist_mode", values[n++] = G.new_uint32(2);    /* until the user revokes it */
            NSString *token = stored_token(source);
            if (token)
                keys[n] = "restore_token", values[n++] = G.new_string([token UTF8String]);
        }
        GVariant *sessionArg[1] = {G.new_object_path([handle UTF8String])};
        code = request(&p, "SelectSources", sessionArg, 1, keys, values, n, 30, &results);
        if (results)
            G.unref(results);
        if (code != 0) {
            session_fail(s, code == 1 ? -3801 : -3802, "The ScreenCast portal didn't take the sources asked for.");
            goto close_session;
        }

        /* the portal's dialog: the user picks, or says no */
        GVariant *startArgs[2] = {G.new_object_path([handle UTF8String]), G.new_string("")};
        code = request(&p, "Start", startArgs, 2, NULL, NULL, 0, 600, &results);
        if (code != 0) {
            if (results)
                G.unref(results);
            if (!s->quit)
                session_fail(s, code == 1 ? -3801 : -3802,
                             code == 1 ? "The user didn't choose anything to record."
                                       : "The ScreenCast portal couldn't start the recording.");
            goto close_session;
        }
        NSString *token = lookup_string(results, "restore_token");
        if (token)
            store_token(source, token);
        GVariant *streams = results ? G.lookup_value(results, "streams", "a(ua{sv})") : NULL;
        BOOL found = NO;
        if (streams && G.n_children(streams) > 0) {
            GVariant *first = G.child(streams, 0);
            GVariant *node = G.child(first, 0), *props = G.child(first, 1);
            pthread_mutex_lock(&s->lock);
            s->node = G.get_uint32(node);
            s->hasPosition = lookup_pair(props, "position", &s->posX, &s->posY);
            if (!lookup_pair(props, "size", &s->sizeW, &s->sizeH))
                s->sizeW = s->sizeH = 0;
            pthread_mutex_unlock(&s->lock);
            G.unref(node);
            G.unref(props);
            G.unref(first);
            found = YES;
        }
        if (streams)
            G.unref(streams);
        G.unref(results);
        if (!found) {
            session_fail(s, -3815, "The ScreenCast portal gave no stream.");
            goto close_session;
        }

        /* PipeWire, through the portal's own connection to it */
        GVariant *remoteArgs[2] = {G.new_object_path([handle UTF8String]), options(NULL, NULL, 0)};
        GUnixFDList *fds = NULL;
        GVariant *reply = G.call_fd_sync(p.bus, PORTAL_BUS, PORTAL_PATH, SCREENCAST, "OpenPipeWireRemote",
                                         G.new_tuple(remoteArgs, 2), "(h)", 0, 30000, NULL, &fds, NULL, &error);
        int fd = -1;
        if (reply && fds) {
            GVariant *h = G.child(reply, 0);
            fd = G.fd_list_get(fds, G.get_handle(h), &error);
            G.unref(h);
        }
        if (reply)
            G.unref(reply);
        if (fds)
            G.object_unref(fds);
        if (error) {
            G.error_free(error);
            error = NULL;
        }
        if (fd < 0)
            session_fail(s, -3802, "The ScreenCast portal didn't open PipeWire.");
        else if (!s->quit)
            read_stream(s, fd);
        else
            close(fd);

    close_session : {
        GVariant *none = NULL;
        GVariant *r = G.call_sync(p.bus, PORTAL_BUS, [handle UTF8String], "org.freedesktop.portal.Session", "Close",
                                  G.new_tuple(&none, 0), NULL, 0, 2000, NULL, &error);
        if (r)
            G.unref(r);
        else if (error)
            G.error_free(error);
    }
    done:
        if (p.bus)
            G.object_unref(p.bus);
        G.pop(p.context);
        G.context_unref(p.context);
    }
    pthread_mutex_lock(&s->lock);
    if (s->state != FAILED)
        s->state = ENDED;
    pthread_cond_broadcast(&s->cond);
    pthread_mutex_unlock(&s->lock);
    session_release(s);
    return NULL;
}

static Session *session_start(uint32_t kind, CGDirectDisplayID display, uint64_t window, BOOL showsCursor)
{
    Session *s = calloc(1, sizeof *s);
    if (!s)
        return NULL;
    pthread_mutex_init(&s->lock, NULL);
    pthread_cond_init(&s->cond, NULL);
    s->refs = 2;    /* the grabber's and the thread's */
    s->kind = kind;
    s->display = display;
    s->window = window;
    s->showsCursor = showsCursor;
    /* the pointer as metadata, drawn by the capture core as configured; else drawn in or not */
    uint32_t modes = portal.cursorModes;
    s->cursorMode = (modes & CURSOR_METADATA)                  ? CURSOR_METADATA
                    : (showsCursor && (modes & CURSOR_EMBEDDED)) ? CURSOR_EMBEDDED
                    : (modes & CURSOR_HIDDEN)                    ? CURSOR_HIDDEN
                                                                 : CURSOR_EMBEDDED;
    @autoreleasepool {
        NSString *source;
        if (kind == SOURCE_MONITOR)
            source = [@"monitor " stringByAppendingString:display_name(display)];
        else {
            ACaptureWindow *w = window == picked_window ? nil : window_with_handle(window);
            NSString *app = !w                  ? @"any"
                            : [w->bundleID length] ? w->bundleID
                            : [w->owner length]    ? w->owner
                                                   : @"any";
            source = [@"window " stringByAppendingString:app];
        }
        snprintf(s->source, sizeof s->source, "%s", [source UTF8String]);
    }
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t t;
    int rc = pthread_create(&t, &attr, session_main, s);
    pthread_attr_destroy(&attr);
    if (rc) {
        session_fail(s, -3802, "The screen cast's thread couldn't start.");
        s->refs = 1;
    }
    return s;
}

static void session_stop(Session *s)
{
    if (!s)
        return;
    pthread_mutex_lock(&s->lock);
    s->quit = 1;
    if (s->loop)
        PW.main_loop_quit(s->loop);
    pthread_mutex_unlock(&s->lock);
    session_release(s);
}

/* ---- the grabbers ------------------------------------------------------------------------- */

typedef struct {
    ACaptureTarget target;
    Session *session;
    uint8_t *image;
    size_t imageSize;
    uint32_t *cursor;
    size_t cursorSize;
    CGRect shown;           /* where the last grab's pixels are, in the back end's pixels */
    CGFloat ratio;          /* the back end's pixels per stream pixel */
} Grabber;

static BOOL portal_available(void) { return ACapturePortalReachable(); }

static void *portal_open_target(const ACaptureTarget *t)
{
    if (!ACapturePortalReachable())
        return NULL;
    Grabber *g = calloc(1, sizeof *g);
    if (!g)
        return NULL;
    g->target = *t;
    g->ratio = 1;
    /* the dialog comes up as the stream starts, not at its first frame */
    if (t->kind == ACaptureSourceWindow && (portal.sourceTypes & SOURCE_WINDOW))
        g->session = session_start(SOURCE_WINDOW, 0, t->window, t->showsCursor);
    else if (t->kind != ACaptureSourceWindow)
        g->session = session_start(SOURCE_MONITOR, t->display, 0, t->showsCursor);
    return g;
}

static void *portal_open(void)
{
    ACaptureTarget t = {ACaptureSourceDisplay, 0, 0, NO, NO};
    ACaptureDisplay *main = [portal_displays() firstObject];
    t.display = main ? main->number : 1;
    return portal_open_target(&t);
}

static void portal_close(void *p)
{
    Grabber *g = p;
    if (!g)
        return;
    session_stop(g->session);
    free(g->image);
    free(g->cursor);
    free(g);
}

/* the session for this source, a new one when it's another */
static Session *session_for(Grabber *g, uint32_t kind, CGDirectDisplayID display, uint64_t window)
{
    Session *s = g->session;
    if (s && s->kind == kind && (kind == SOURCE_MONITOR ? s->display == display : s->window == window))
        return s;
    session_stop(s);
    g->session = session_start(kind, display, window, g->target.showsCursor);
    return g->session;
}

/* called with the session's lock held: whether it has a frame, waiting for one for a single picture */
static BOOL has_frame(Grabber *g, Session *s)
{
    if (g->target.once) {
        struct timespec until;
        struct timeval tv;
        gettimeofday(&tv, NULL);
        until.tv_sec = tv.tv_sec + 60;    /* the time to choose in the dialog */
        until.tv_nsec = tv.tv_usec * 1000;
        while (!s->serial && s->state != FAILED && s->state != ENDED)
            if (pthread_cond_timedwait(&s->cond, &s->lock, &until) == ETIMEDOUT)
                break;
    }
    return s->serial > 0 && s->frame && s->fw && s->fh;
}

/* part of a monitor's latest frame: `rect`, in the back end's pixels, of display d */
static BOOL grab_part(Grabber *g, Session *s, ACaptureDisplay *d, CGRect rect, ACaptureImage *out)
{
    pthread_mutex_lock(&s->lock);
    if (!has_frame(g, s)) {
        pthread_mutex_unlock(&s->lock);
        return NO;
    }
    /* the stream is the display in its own pixels; the first frame says the display's scale */
    CGRect logical = d->frame;
    if (s->sizeW > 0 && s->sizeH > 0)
        logical.size = CGSizeMake(s->sizeW, s->sizeH);
    learn_scale(d->number, s->fw / logical.size.width);
    CGRect pf = d->pixelFrame;
    double sx = s->fw / pf.size.width, sy = s->fh / pf.size.height;
    long x0 = lround((rect.origin.x - pf.origin.x) * sx), y0 = lround((rect.origin.y - pf.origin.y) * sy);
    long x1 = lround((CGRectGetMaxX(rect) - pf.origin.x) * sx), y1 = lround((CGRectGetMaxY(rect) - pf.origin.y) * sy);
    x0 = MAX(0, MIN(x0, (long)s->fw)), x1 = MAX(x0, MIN(x1, (long)s->fw));
    y0 = MAX(0, MIN(y0, (long)s->fh)), y1 = MAX(y0, MIN(y1, (long)s->fh));
    size_t w = (size_t)(x1 - x0), h = (size_t)(y1 - y0);
    if (!w || !h) {
        pthread_mutex_unlock(&s->lock);
        return NO;
    }
    if (g->imageSize < w * h * 4) {
        free(g->image);
        g->image = malloc(w * h * 4);
        g->imageSize = g->image ? w * h * 4 : 0;
    }
    if (g->image)
        for (size_t y = 0; y < h; y++)
            memcpy(g->image + y * w * 4, s->frame + ((size_t)y0 + y) * s->fw * 4 + (size_t)x0 * 4, w * 4);
    g->ratio = 1 / sx;
    g->shown = pf;    /* the whole stream, in the back end's pixels: the pointer is placed on it */
    pthread_mutex_unlock(&s->lock);
    if (!g->image)
        return NO;
    out->data = g->image;
    out->width = w;
    out->height = h;
    out->bytesPerRow = w * 4;
    return YES;
}

static ACaptureDisplay *display_of_rect(NSArray *displays, CGRect pixels, CGDirectDisplayID preferred)
{
    ACaptureDisplay *p = display_numbered(displays, preferred);
    CGPoint mid = CGPointMake(CGRectGetMidX(pixels), CGRectGetMidY(pixels));
    if (p && CGRectContainsPoint(p->pixelFrame, mid))
        return p;
    for (ACaptureDisplay *d in displays)
        if (CGRectContainsPoint(d->pixelFrame, mid))
            return d;
    return p ?: [displays firstObject];
}

static BOOL portal_grab_screen(void *p, CGRect rect, ACaptureImage *out)
{
    Grabber *g = p;
    @autoreleasepool {
        NSArray *displays = portal_displays();
        ACaptureDisplay *d = display_of_rect(displays, rect, g->target.display);
        if (!d)
            return NO;
        Session *s = session_for(g, SOURCE_MONITOR, d->number, 0);
        return s && grab_part(g, s, d, rect, out);
    }
}

static BOOL portal_grab_window(void *p, uint64_t handle, ACaptureImage *out, CGRect *pixelFrame)
{
    Grabber *g = p;
    @autoreleasepool {
        ACaptureWindow *w = handle == picked_window ? nil : window_with_handle(handle);
        if (!(portal.sourceTypes & SOURCE_WINDOW)) {
            /* a portal that records only monitors: the window cut from its display's stream */
            if (!w || !w->onscreen)
                return NO;
            NSArray *displays = portal_displays();
            ACaptureDisplay *d = display_of_rect(displays, w->pixelFrame, 0);
            Session *s = d ? session_for(g, SOURCE_MONITOR, d->number, 0) : NULL;
            CGRect part = CGRectIntersection(w->pixelFrame, d ? d->pixelFrame : CGRectNull);
            if (!s || CGRectIsEmpty(part) || !grab_part(g, s, d, part, out))
                return NO;
            if (pixelFrame)
                *pixelFrame = part;
            return YES;
        }
        Session *s = session_for(g, SOURCE_WINDOW, 0, handle);
        if (!s)
            return NO;
        pthread_mutex_lock(&s->lock);
        if (!has_frame(g, s)) {
            pthread_mutex_unlock(&s->lock);
            return NO;
        }
        size_t n = s->fw * s->fh * 4;
        if (g->imageSize < n) {
            free(g->image);
            g->image = malloc(n);
            g->imageSize = g->image ? n : 0;
        }
        if (g->image)
            memcpy(g->image, s->frame, n);
        out->data = g->image;
        out->width = s->fw;
        out->height = s->fh;
        out->bytesPerRow = s->fw * 4;
        /* the window as the stream shows it, at the window's place */
        CGRect at = w ? w->pixelFrame : CGRectMake(0, 0, s->fw, s->fh);
        g->shown = CGRectMake(at.origin.x, at.origin.y, s->fw, s->fh);
        g->ratio = w && s->fw ? w->pixelFrame.size.width / s->fw : 1;
        if (pixelFrame)
            *pixelFrame = CGRectMake(at.origin.x, at.origin.y, s->fw, s->fh);
        pthread_mutex_unlock(&s->lock);
        return g->image != NULL;
    }
}

static BOOL portal_cursor(void *p, ACaptureCursor *out)
{
    Grabber *g = p;
    Session *s = g->session;
    if (!s || s->cursorMode != CURSOR_METADATA)
        return NO;    /* drawn in by the compositor, or not at all */
    pthread_mutex_lock(&s->lock);
    BOOL ok = s->cursorShown && s->cursor && s->cw && s->ch;
    if (ok) {
        size_t n = s->cw * s->ch;
        if (g->cursorSize < n) {
            free(g->cursor);
            g->cursor = malloc(n * 4);
            g->cursorSize = g->cursor ? n : 0;
        }
        ok = g->cursor != NULL;
        if (ok) {
            memcpy(g->cursor, s->cursor, n * 4);
            out->argb = g->cursor;
            out->width = s->cw;
            out->height = s->ch;
            out->x = lround(g->shown.origin.x + (s->cx - s->hx) * g->ratio);
            out->y = lround(g->shown.origin.y + (s->cy - s->hy) * g->ratio);
        }
    }
    pthread_mutex_unlock(&s->lock);
    return ok;
}

static NSError *portal_failure(void *p)
{
    Grabber *g = p;
    Session *s = g ? g->session : NULL;
    if (!s)
        return nil;
    pthread_mutex_lock(&s->lock);
    NSError *e = s->state == FAILED ? ACaptureError(s->failCode, @(s->why)) : nil;
    pthread_mutex_unlock(&s->lock);
    return e;
}

const ACaptureBackend ACapturePortalBackend = {
    "portal",         portal_available,   portal_displays,    portal_windows, portal_open,
    portal_close,     portal_grab_screen, portal_grab_window, portal_cursor,  portal_open_target,
    portal_failure,
};

