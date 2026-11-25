/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The parts of this system's libpulse that Ferry's Core Audio uses
 * (CABackend.m): a one-shot connection to list the server's sinks and
 * sources, a subscription that hears them change, and the simple API's
 * blocking streams that play and record. PulseAudio has libpulse, and
 * PipeWire offers the same library through pipewire-pulse. libpulse is a
 * Linux library and Core Audio is Mac code, but both use the System V
 * calling convention, so Core Audio calls it directly. Its calls are looked
 * up by name through ferry_sound_symbol() (src/host.c) the first time a
 * program touches the audio hardware.
 *
 * Written here from libpulse's published API documentation (the Mac build
 * can't include Linux headers): only calls, constants and the leading
 * members of the structures that are part of libpulse's stable public
 * API, in its documented order.
 */
#ifndef FERRY_COREAUDIO_PULSE_H
#define FERRY_COREAUDIO_PULSE_H
#include <stddef.h>
#include <stdint.h>

typedef struct pa_mainloop pa_mainloop;
typedef struct pa_mainloop_api pa_mainloop_api;
typedef struct pa_context pa_context;
typedef struct pa_operation pa_operation;
typedef struct pa_proplist pa_proplist;
typedef struct pa_simple pa_simple;
typedef uint64_t pa_usec_t;

enum { PA_CHANNELS_MAX = 32 };
enum {
    PA_SAMPLE_U8 = 0,
    PA_SAMPLE_S16LE = 3,
    PA_SAMPLE_FLOAT32LE = 5,
    PA_SAMPLE_S32LE = 7,
};
enum { PA_STREAM_PLAYBACK = 1, PA_STREAM_RECORD = 2 };
enum { PA_CONTEXT_NOAUTOSPAWN = 1 };
enum {
    PA_CONTEXT_UNCONNECTED = 0,
    PA_CONTEXT_CONNECTING = 1,
    PA_CONTEXT_AUTHORIZING = 2,
    PA_CONTEXT_SETTING_NAME = 3,
    PA_CONTEXT_READY = 4,
    PA_CONTEXT_FAILED = 5,
    PA_CONTEXT_TERMINATED = 6,
};
enum { PA_OPERATION_RUNNING = 0, PA_OPERATION_DONE = 1, PA_OPERATION_CANCELLED = 2 };
enum {
    PA_SUBSCRIPTION_MASK_SINK = 0x0001,
    PA_SUBSCRIPTION_MASK_SOURCE = 0x0002,
    PA_SUBSCRIPTION_MASK_SERVER = 0x0080,
};
enum { PA_VOLUME_NORM = 0x10000 };
enum { PA_INVALID_INDEX = 0xFFFFFFFF };

/* channel positions */
enum {
    PA_CHANNEL_POSITION_MONO = 0,
    PA_CHANNEL_POSITION_FRONT_LEFT = 1,
    PA_CHANNEL_POSITION_FRONT_RIGHT = 2,
    PA_CHANNEL_POSITION_FRONT_CENTER = 3,
    PA_CHANNEL_POSITION_REAR_CENTER = 4,
    PA_CHANNEL_POSITION_REAR_LEFT = 5,
    PA_CHANNEL_POSITION_REAR_RIGHT = 6,
    PA_CHANNEL_POSITION_LFE = 7,
    PA_CHANNEL_POSITION_FRONT_LEFT_OF_CENTER = 8,
    PA_CHANNEL_POSITION_FRONT_RIGHT_OF_CENTER = 9,
    PA_CHANNEL_POSITION_SIDE_LEFT = 10,
    PA_CHANNEL_POSITION_SIDE_RIGHT = 11,
    PA_CHANNEL_POSITION_AUX0 = 12,
    PA_CHANNEL_POSITION_AUX31 = 43,
    PA_CHANNEL_POSITION_TOP_CENTER = 44,
    PA_CHANNEL_POSITION_TOP_FRONT_LEFT = 45,
    PA_CHANNEL_POSITION_TOP_FRONT_RIGHT = 46,
    PA_CHANNEL_POSITION_TOP_FRONT_CENTER = 47,
    PA_CHANNEL_POSITION_TOP_REAR_LEFT = 48,
    PA_CHANNEL_POSITION_TOP_REAR_RIGHT = 49,
    PA_CHANNEL_POSITION_TOP_REAR_CENTER = 50,
};

typedef struct pa_sample_spec {
    int format;
    uint32_t rate;
    uint8_t channels;
} pa_sample_spec;

typedef struct pa_channel_map {
    uint8_t channels;
    int map[PA_CHANNELS_MAX];
} pa_channel_map;

typedef struct pa_cvolume {
    uint8_t channels;
    uint32_t values[PA_CHANNELS_MAX];
} pa_cvolume;

typedef struct pa_buffer_attr {
    uint32_t maxlength;
    uint32_t tlength;
    uint32_t prebuf;
    uint32_t minreq;
    uint32_t fragsize;
} pa_buffer_attr;

typedef struct pa_server_info {
    const char *user_name;
    const char *host_name;
    const char *server_version;
    const char *server_name;
    pa_sample_spec sample_spec;
    const char *default_sink_name;
    const char *default_source_name;
    uint32_t cookie;
    pa_channel_map channel_map;
} pa_server_info;

/* the leading members of pa_sink_info and pa_source_info, which are the
 * same in both (a sink names its monitor source where a source names the
 * sink it monitors); Core Audio reads no further than the property list */
typedef struct pa_device_info {
    const char *name;
    uint32_t index;
    const char *description;
    pa_sample_spec sample_spec;
    pa_channel_map channel_map;
    uint32_t owner_module;
    pa_cvolume volume;
    int mute;
    uint32_t monitor_index;        /* a sink's monitor source, or the sink a source monitors */
    const char *monitor_name;
    pa_usec_t latency;
    const char *driver;
    int flags;
    pa_proplist *proplist;
    pa_usec_t configured_latency;
} pa_device_info;

typedef void (*pa_context_notify_cb_t)(pa_context *c, void *userdata);
typedef void (*pa_server_info_cb_t)(pa_context *c, const pa_server_info *i, void *userdata);
typedef void (*pa_device_info_cb_t)(pa_context *c, const pa_device_info *i, int eol, void *userdata);
typedef void (*pa_context_subscribe_cb_t)(pa_context *c, int type, uint32_t idx, void *userdata);
typedef void (*pa_context_success_cb_t)(pa_context *c, int success, void *userdata);

/* The calls, each a member of the table below (CABackend.m fills it). */
#define FERRY_PULSE_CALLS(X)                                                                                       \
    X(pa_mainloop *, pa_mainloop_new, (void))                                                                      \
    X(pa_mainloop_api *, pa_mainloop_get_api, (pa_mainloop * m))                                                   \
    X(int, pa_mainloop_iterate, (pa_mainloop * m, int block, int *retval))                                         \
    X(void, pa_mainloop_free, (pa_mainloop * m))                                                                   \
    X(pa_context *, pa_context_new, (pa_mainloop_api * api, const char *name))                                     \
    X(int, pa_context_connect, (pa_context * c, const char *server, int flags, const void *api))                   \
    X(void, pa_context_disconnect, (pa_context * c))                                                               \
    X(void, pa_context_unref, (pa_context * c))                                                                    \
    X(int, pa_context_get_state, (const pa_context *c))                                                            \
    X(pa_operation *, pa_context_get_server_info, (pa_context * c, pa_server_info_cb_t cb, void *userdata))        \
    X(pa_operation *, pa_context_get_sink_info_list, (pa_context * c, pa_device_info_cb_t cb, void *userdata))     \
    X(pa_operation *, pa_context_get_source_info_list, (pa_context * c, pa_device_info_cb_t cb, void *userdata))   \
    X(void, pa_context_set_subscribe_callback, (pa_context * c, pa_context_subscribe_cb_t cb, void *userdata))     \
    X(pa_operation *, pa_context_subscribe, (pa_context * c, int mask, pa_context_success_cb_t cb, void *userdata)) \
    X(pa_operation *, pa_context_set_default_sink,                                                                 \
      (pa_context * c, const char *name, pa_context_success_cb_t cb, void *userdata))                              \
    X(pa_operation *, pa_context_set_default_source,                                                               \
      (pa_context * c, const char *name, pa_context_success_cb_t cb, void *userdata))                              \
    X(pa_operation *, pa_context_set_sink_volume_by_name,                                                          \
      (pa_context * c, const char *name, const pa_cvolume *volume, pa_context_success_cb_t cb, void *userdata))    \
    X(pa_operation *, pa_context_set_source_volume_by_name,                                                        \
      (pa_context * c, const char *name, const pa_cvolume *volume, pa_context_success_cb_t cb, void *userdata))    \
    X(pa_operation *, pa_context_set_sink_mute_by_name,                                                            \
      (pa_context * c, const char *name, int mute, pa_context_success_cb_t cb, void *userdata))                    \
    X(pa_operation *, pa_context_set_source_mute_by_name,                                                          \
      (pa_context * c, const char *name, int mute, pa_context_success_cb_t cb, void *userdata))                    \
    X(int, pa_operation_get_state, (const pa_operation *o))                                                        \
    X(void, pa_operation_unref, (pa_operation * o))                                                                \
    X(const char *, pa_proplist_gets, (const pa_proplist *p, const char *key))                                     \
    X(const char *, pa_strerror, (int error))                                                                      \
    X(pa_simple *, pa_simple_new,                                                                                  \
      (const char *server, const char *name, int dir, const char *dev, const char *stream_name,                    \
       const pa_sample_spec *ss, const pa_channel_map *map, const pa_buffer_attr *attr, int *error))               \
    X(void, pa_simple_free, (pa_simple * s))                                                                       \
    X(int, pa_simple_write, (pa_simple * s, const void *data, size_t bytes, int *error))                           \
    X(int, pa_simple_read, (pa_simple * s, void *data, size_t bytes, int *error))                                  \
    X(int, pa_simple_drain, (pa_simple * s, int *error))                                                           \
    X(int, pa_simple_flush, (pa_simple * s, int *error))                                                           \
    X(pa_usec_t, pa_simple_get_latency, (pa_simple * s, int *error))

#define FERRY_PULSE_MEMBER(ret, name, args) ret(*name) args;
struct ferry_pulse {
    FERRY_PULSE_CALLS(FERRY_PULSE_MEMBER)
};
#undef FERRY_PULSE_MEMBER

#endif
