/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The devices behind Ferry's Core Audio, and their streams (freemac 1.234,
 * Ferry 0.58.0).
 *
 * With a sound server (PulseAudio, or PipeWire through pipewire-pulse),
 * each sink is an output device and each source an input device; a sink's
 * monitor is listed as an input device that hears it, but is never the
 * default. Device UIDs are the server's names for them. Without a server,
 * or with FERRY_AUDIO=null, there is one device, "Null Audio Device", that
 * plays and records at real-time pace: what it plays is appended, as 32-bit
 * float samples, to FERRY_AUDIO_OUTPUT_FILE when that is set, and what it
 * records comes from FERRY_AUDIO_INPUT_FILE when that is set, or else is
 * what it last played (a loopback), or silence.
 */
#import "CAInternal.h"
#import "CAPulse.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

void *ferry_sound_symbol(const char *name); /* src/host.c */

enum { MAX_DEVICES = 128, FIRST_ID = 0x20 };

static pthread_mutex_t table_lock;
static ca_device devices[MAX_DEVICES];
static UInt32 device_count;
static AudioObjectID next_id = FIRST_ID;
static AudioObjectID default_device[2];
static int null_backend;
static struct ferry_pulse pa;
static char server_name[256];

pthread_mutex_t *ca_lock(void)
{
    return &table_lock;
}

int ca_backend_is_null(void)
{
    ca_init();
    return null_backend;
}

const char *ca_program_name(void)
{
    const char *name = getprogname();
    return name && *name ? name : "Ferry";
}

static void lock(void)
{
    pthread_mutex_lock(&table_lock);
}

static void unlock(void)
{
    pthread_mutex_unlock(&table_lock);
}

/* ---- channel positions ---------------------------------------------------------- */

static int has_position(const pa_channel_map *m, int pos)
{
    for (int i = 0; i < m->channels; i++)
        if (m->map[i] == pos)
            return 1;
    return 0;
}

static UInt32 label_for_position(const pa_channel_map *m, int pos)
{
    int sides = has_position(m, PA_CHANNEL_POSITION_SIDE_LEFT) || has_position(m, PA_CHANNEL_POSITION_SIDE_RIGHT);
    switch (pos) {
    case PA_CHANNEL_POSITION_MONO: return kAudioChannelLabel_Center;
    case PA_CHANNEL_POSITION_FRONT_LEFT: return kAudioChannelLabel_Left;
    case PA_CHANNEL_POSITION_FRONT_RIGHT: return kAudioChannelLabel_Right;
    case PA_CHANNEL_POSITION_FRONT_CENTER: return kAudioChannelLabel_Center;
    case PA_CHANNEL_POSITION_LFE: return kAudioChannelLabel_LFEScreen;
    case PA_CHANNEL_POSITION_REAR_LEFT: return sides ? kAudioChannelLabel_RearSurroundLeft : kAudioChannelLabel_LeftSurround;
    case PA_CHANNEL_POSITION_REAR_RIGHT:
        return sides ? kAudioChannelLabel_RearSurroundRight : kAudioChannelLabel_RightSurround;
    case PA_CHANNEL_POSITION_REAR_CENTER: return kAudioChannelLabel_CenterSurround;
    case PA_CHANNEL_POSITION_SIDE_LEFT: return kAudioChannelLabel_LeftSurround;
    case PA_CHANNEL_POSITION_SIDE_RIGHT: return kAudioChannelLabel_RightSurround;
    case PA_CHANNEL_POSITION_FRONT_LEFT_OF_CENTER: return kAudioChannelLabel_LeftCenter;
    case PA_CHANNEL_POSITION_FRONT_RIGHT_OF_CENTER: return kAudioChannelLabel_RightCenter;
    case PA_CHANNEL_POSITION_TOP_CENTER: return kAudioChannelLabel_TopCenterSurround;
    case PA_CHANNEL_POSITION_TOP_FRONT_LEFT: return kAudioChannelLabel_VerticalHeightLeft;
    case PA_CHANNEL_POSITION_TOP_FRONT_CENTER: return kAudioChannelLabel_VerticalHeightCenter;
    case PA_CHANNEL_POSITION_TOP_FRONT_RIGHT: return kAudioChannelLabel_VerticalHeightRight;
    case PA_CHANNEL_POSITION_TOP_REAR_LEFT: return kAudioChannelLabel_TopBackLeft;
    case PA_CHANNEL_POSITION_TOP_REAR_CENTER: return kAudioChannelLabel_TopBackCenter;
    case PA_CHANNEL_POSITION_TOP_REAR_RIGHT: return kAudioChannelLabel_TopBackRight;
    default:
        if (pos >= PA_CHANNEL_POSITION_AUX0 && pos <= PA_CHANNEL_POSITION_AUX31)
            return kAudioChannelLabel_Discrete_0 + (UInt32)(pos - PA_CHANNEL_POSITION_AUX0);
        return kAudioChannelLabel_Unknown;
    }
}

static int labels_have(const UInt32 *labels, UInt32 n, UInt32 a, UInt32 b)
{
    for (UInt32 i = 0; i < n; i++)
        if (labels[i] == a || labels[i] == b)
            return 1;
    return 0;
}

static void map_for_labels(const UInt32 *labels, UInt32 n, pa_channel_map *m)
{
    memset(m, 0, sizeof *m);
    m->channels = (uint8_t)n;
    int rears = labels_have(labels, n, kAudioChannelLabel_RearSurroundLeft, kAudioChannelLabel_RearSurroundRight);
    int aux = 0;
    for (UInt32 i = 0; i < n; i++) {
        int p;
        switch (labels[i]) {
        case kAudioChannelLabel_Mono: p = n == 1 ? PA_CHANNEL_POSITION_MONO : PA_CHANNEL_POSITION_FRONT_CENTER; break;
        case kAudioChannelLabel_Center: p = n == 1 ? PA_CHANNEL_POSITION_MONO : PA_CHANNEL_POSITION_FRONT_CENTER; break;
        case kAudioChannelLabel_Left:
        case kAudioChannelLabel_HeadphonesLeft:
        case kAudioChannelLabel_LeftTotal:
        case kAudioChannelLabel_LeftWide: p = PA_CHANNEL_POSITION_FRONT_LEFT; break;
        case kAudioChannelLabel_Right:
        case kAudioChannelLabel_HeadphonesRight:
        case kAudioChannelLabel_RightTotal:
        case kAudioChannelLabel_RightWide: p = PA_CHANNEL_POSITION_FRONT_RIGHT; break;
        case kAudioChannelLabel_LFEScreen:
        case kAudioChannelLabel_LFE2: p = PA_CHANNEL_POSITION_LFE; break;
        case kAudioChannelLabel_LeftSurround: p = rears ? PA_CHANNEL_POSITION_SIDE_LEFT : PA_CHANNEL_POSITION_REAR_LEFT; break;
        case kAudioChannelLabel_RightSurround:
            p = rears ? PA_CHANNEL_POSITION_SIDE_RIGHT : PA_CHANNEL_POSITION_REAR_RIGHT;
            break;
        case kAudioChannelLabel_RearSurroundLeft: p = PA_CHANNEL_POSITION_REAR_LEFT; break;
        case kAudioChannelLabel_RearSurroundRight: p = PA_CHANNEL_POSITION_REAR_RIGHT; break;
        case kAudioChannelLabel_LeftSurroundDirect: p = PA_CHANNEL_POSITION_SIDE_LEFT; break;
        case kAudioChannelLabel_RightSurroundDirect: p = PA_CHANNEL_POSITION_SIDE_RIGHT; break;
        case kAudioChannelLabel_CenterSurround: p = PA_CHANNEL_POSITION_REAR_CENTER; break;
        case kAudioChannelLabel_LeftCenter: p = PA_CHANNEL_POSITION_FRONT_LEFT_OF_CENTER; break;
        case kAudioChannelLabel_RightCenter: p = PA_CHANNEL_POSITION_FRONT_RIGHT_OF_CENTER; break;
        case kAudioChannelLabel_TopCenterSurround: p = PA_CHANNEL_POSITION_TOP_CENTER; break;
        case kAudioChannelLabel_VerticalHeightLeft: p = PA_CHANNEL_POSITION_TOP_FRONT_LEFT; break;
        case kAudioChannelLabel_VerticalHeightCenter: p = PA_CHANNEL_POSITION_TOP_FRONT_CENTER; break;
        case kAudioChannelLabel_VerticalHeightRight: p = PA_CHANNEL_POSITION_TOP_FRONT_RIGHT; break;
        case kAudioChannelLabel_TopBackLeft: p = PA_CHANNEL_POSITION_TOP_REAR_LEFT; break;
        case kAudioChannelLabel_TopBackCenter: p = PA_CHANNEL_POSITION_TOP_REAR_CENTER; break;
        case kAudioChannelLabel_TopBackRight: p = PA_CHANNEL_POSITION_TOP_REAR_RIGHT; break;
        default:
            if (labels[i] >= kAudioChannelLabel_Discrete_0 && labels[i] < kAudioChannelLabel_Discrete_0 + 32)
                p = PA_CHANNEL_POSITION_AUX0 + (int)(labels[i] - kAudioChannelLabel_Discrete_0);
            else
                p = PA_CHANNEL_POSITION_AUX0 + (aux < 32 ? aux : 31);
            aux++;
        }
        m->map[i] = p;
    }
}

/* ---- the device table --------------------------------------------------------------- */

ca_device *ca_device_for(AudioObjectID id)
{
    if (id < FIRST_ID)
        return NULL;
    ca_init();
    ca_device *found = NULL;
    lock();
    for (UInt32 i = 0; i < device_count; i++)
        if (devices[i].id == id) {
            found = &devices[i];
            break;
        }
    unlock();
    return found;
}

ca_device *ca_device_for_stream(AudioObjectID id, int *direction)
{
    if (id < FIRST_ID)
        return NULL;
    ca_init();
    ca_device *found = NULL;
    lock();
    for (UInt32 i = 0; i < device_count && !found; i++)
        for (int dir = 0; dir < 2; dir++)
            if (devices[i].stream[dir] == id) {
                found = &devices[i];
                if (direction)
                    *direction = dir;
                break;
            }
    unlock();
    return found;
}

UInt32 ca_device_list(AudioObjectID *ids, UInt32 max)
{
    ca_init();
    UInt32 n = 0;
    lock();
    for (UInt32 i = 0; i < device_count; i++)
        if (devices[i].listed) {
            if (ids && n < max)
                ids[n] = devices[i].id;
            n++;
        }
    unlock();
    return ids && n > max ? max : n;
}

AudioObjectID ca_default_device(int direction)
{
    ca_init();
    lock();
    AudioObjectID id = default_device[direction];
    unlock();
    return id;
}

static ca_device *new_device(void)
{
    /* a dead device keeps its slot, so pointers to it stay good */
    if (device_count >= MAX_DEVICES)
        return NULL;
    ca_device *d = &devices[device_count++];
    memset(d, 0, sizeof *d);
    d->id = next_id++;
    d->buffer_frames = 512;
    d->volume[0] = d->volume[1] = 1.0f;
    d->hog = -1;
    d->alive = d->listed = 1;
    return d;
}

static void add_null_device(void)
{
    ca_device *d = new_device();
    if (!d)
        return;
    strcpy(d->uid, "FerryNullAudioDevice");
    strcpy(d->name, "Null Audio Device");
    strcpy(d->manufacturer, "Ferry");
    d->rate = 48000;
    d->transport = kAudioDeviceTransportTypeVirtual;
    for (int dir = 0; dir < 2; dir++) {
        d->stream[dir] = next_id++;
        d->channels[dir] = 2;
        ca_default_labels(2, d->labels[dir]);
        d->latency[dir] = 0;
    }
    d->terminal[CA_OUT] = kAudioStreamTerminalTypeSpeaker;
    d->terminal[CA_IN] = kAudioStreamTerminalTypeMicrophone;
    default_device[CA_OUT] = default_device[CA_IN] = d->id;
}

/* ---- the sound server ----------------------------------------------------------------- */

typedef struct server_device {
    int dir, monitor;
    char name[256], description[256], vendor[128], bus[32], form_factor[32], klass[32];
    pa_sample_spec spec;
    pa_channel_map map;
    pa_usec_t latency;
    float volume;
    int mute;
} server_device;

typedef struct listing {
    server_device *list;
    int count, cap;
    int pending, failed;
    char default_name[2][256];
    char server[256];
} listing;

static void copy_str(char *to, size_t size, const char *from)
{
    snprintf(to, size, "%s", from ? from : "");
}

static int load_pulse(void)
{
#define LOAD(ret, name, args)                                                                                         \
    *(void **)&pa.name = ferry_sound_symbol(#name);                                                                   \
    if (!pa.name)                                                                                                     \
        return 0;
    FERRY_PULSE_CALLS(LOAD)
#undef LOAD
    return 1;
}

static void server_info_cb(pa_context *c, const pa_server_info *i, void *userdata)
{
    listing *l = userdata;
    if (i) {
        copy_str(l->default_name[CA_OUT], sizeof l->default_name[0], i->default_sink_name);
        copy_str(l->default_name[CA_IN], sizeof l->default_name[1], i->default_source_name);
        copy_str(l->server, sizeof l->server, i->server_name);
    }
    l->pending--;
}

static void device_cb(pa_context *c, const pa_device_info *i, int eol, void *userdata, int dir)
{
    listing *l = userdata;
    if (eol) {
        if (eol < 0)
            l->failed = 1;
        l->pending--;
        return;
    }
    if (!i || !i->name)
        return;
    if (l->count == l->cap) {
        int cap = l->cap ? l->cap * 2 : 16;
        server_device *n = realloc(l->list, (size_t)cap * sizeof *n);
        if (!n)
            return;
        l->list = n;
        l->cap = cap;
    }
    server_device *s = &l->list[l->count++];
    memset(s, 0, sizeof *s);
    s->dir = dir;
    s->monitor = dir == CA_IN && i->monitor_index != PA_INVALID_INDEX;
    copy_str(s->name, sizeof s->name, i->name);
    copy_str(s->description, sizeof s->description, i->description ? i->description : i->name);
    if (i->proplist) {
        copy_str(s->vendor, sizeof s->vendor, pa.pa_proplist_gets(i->proplist, "device.vendor.name"));
        copy_str(s->bus, sizeof s->bus, pa.pa_proplist_gets(i->proplist, "device.bus"));
        copy_str(s->form_factor, sizeof s->form_factor, pa.pa_proplist_gets(i->proplist, "device.form_factor"));
        copy_str(s->klass, sizeof s->klass, pa.pa_proplist_gets(i->proplist, "device.class"));
    }
    s->spec = i->sample_spec;
    s->map = i->channel_map;
    if (s->map.channels > PA_CHANNELS_MAX)
        s->map.channels = PA_CHANNELS_MAX;
    s->latency = i->configured_latency ? i->configured_latency : i->latency;
    double sum = 0;
    for (int k = 0; k < i->volume.channels && k < PA_CHANNELS_MAX; k++)
        sum += i->volume.values[k];
    s->volume = i->volume.channels ? (float)(sum / i->volume.channels / PA_VOLUME_NORM) : 1.0f;
    s->mute = i->mute;
}

static void sink_cb(pa_context *c, const pa_device_info *i, int eol, void *userdata)
{
    device_cb(c, i, eol, userdata, CA_OUT);
}

static void source_cb(pa_context *c, const pa_device_info *i, int eol, void *userdata)
{
    device_cb(c, i, eol, userdata, CA_IN);
}

typedef struct connection {
    pa_mainloop *loop;
    pa_context *context;
} connection;

static void disconnect(connection *k)
{
    if (k->context) {
        pa.pa_context_disconnect(k->context);
        pa.pa_context_unref(k->context);
    }
    if (k->loop)
        pa.pa_mainloop_free(k->loop);
    memset(k, 0, sizeof *k);
}

/* connects within about two seconds, never starting a server */
static int connect_server(connection *k)
{
    memset(k, 0, sizeof *k);
    k->loop = pa.pa_mainloop_new();
    if (!k->loop)
        return 0;
    k->context = pa.pa_context_new(pa.pa_mainloop_get_api(k->loop), ca_program_name());
    if (!k->context || pa.pa_context_connect(k->context, NULL, PA_CONTEXT_NOAUTOSPAWN, NULL) < 0) {
        disconnect(k);
        return 0;
    }
    UInt64 deadline = ca_now() + 2000000000ull;
    for (;;) {
        int state = pa.pa_context_get_state(k->context);
        if (state == PA_CONTEXT_READY)
            return 1;
        if (state == PA_CONTEXT_FAILED || state == PA_CONTEXT_TERMINATED || ca_now() > deadline) {
            disconnect(k);
            return 0;
        }
        if (pa.pa_mainloop_iterate(k->loop, 0, NULL) < 0) {
            disconnect(k);
            return 0;
        }
        ca_sleep_ns(1000000);
    }
}

/* runs the loop until the listing's operations finish; 0 on failure */
static int finish(connection *k, listing *l)
{
    UInt64 deadline = ca_now() + 2000000000ull;
    while (l->pending > 0) {
        if (pa.pa_context_get_state(k->context) != PA_CONTEXT_READY || ca_now() > deadline)
            return 0;
        if (pa.pa_mainloop_iterate(k->loop, 0, NULL) < 0)
            return 0;
        if (l->pending > 0)
            ca_sleep_ns(500000);
    }
    return !l->failed;
}

static int list_server(connection *k, listing *l)
{
    memset(l, 0, sizeof *l);
    pa_operation *ops[3] = {
        pa.pa_context_get_server_info(k->context, server_info_cb, l),
        pa.pa_context_get_sink_info_list(k->context, sink_cb, l),
        pa.pa_context_get_source_info_list(k->context, source_cb, l),
    };
    for (int i = 0; i < 3; i++)
        if (ops[i])
            l->pending++;
    int ok = l->pending == 3 && finish(k, l);
    for (int i = 0; i < 3; i++)
        if (ops[i])
            pa.pa_operation_unref(ops[i]);
    return ok;
}

static UInt32 transport_for(const server_device *s)
{
    if (!strcmp(s->bus, "usb"))
        return kAudioDeviceTransportTypeUSB;
    if (!strcmp(s->bus, "bluetooth"))
        return kAudioDeviceTransportTypeBluetooth;
    if (!strcmp(s->bus, "firewire"))
        return kAudioDeviceTransportTypeFireWire;
    if (!strcmp(s->form_factor, "hdmi") || strstr(s->name, "hdmi"))
        return kAudioDeviceTransportTypeHDMI;
    if (!strcmp(s->bus, "pci") || !strcmp(s->form_factor, "internal"))
        return kAudioDeviceTransportTypeBuiltIn;
    if (!strcmp(s->klass, "abstract") || !strcmp(s->klass, "monitor") || !s->bus[0])
        return kAudioDeviceTransportTypeVirtual;
    return kAudioDeviceTransportTypeUnknown;
}

static UInt32 terminal_for(const server_device *s)
{
    const char *f = s->form_factor;
    if (s->dir == CA_OUT) {
        if (!strcmp(f, "headphone") || !strcmp(f, "headset") || !strcmp(f, "hands-free"))
            return kAudioStreamTerminalTypeHeadphones;
        if (!strcmp(f, "hdmi"))
            return kAudioStreamTerminalTypeHDMI;
        return kAudioStreamTerminalTypeSpeaker;
    }
    if (s->monitor)
        return kAudioStreamTerminalTypeLine;
    if (!strcmp(f, "headset") || !strcmp(f, "hands-free"))
        return kAudioStreamTerminalTypeHeadsetMicrophone;
    return kAudioStreamTerminalTypeMicrophone;
}

static void fill_device(ca_device *d, const server_device *s)
{
    int dir = s->dir;
    snprintf(d->uid, sizeof d->uid, "%s", s->name);
    snprintf(d->name, sizeof d->name, "%s", s->description);
    snprintf(d->manufacturer, sizeof d->manufacturer, "%s", s->vendor[0] ? s->vendor : server_name);
    snprintf(d->server_name[dir], sizeof d->server_name[0], "%s", s->name);
    d->rate = s->spec.rate ? s->spec.rate : 48000;
    d->channels[dir] = s->map.channels ? s->map.channels : (s->spec.channels ? s->spec.channels : 2);
    if (d->channels[dir] > CA_MAX_CHANNELS)
        d->channels[dir] = CA_MAX_CHANNELS;
    if (s->map.channels == d->channels[dir])
        for (UInt32 k = 0; k < d->channels[dir]; k++)
            d->labels[dir][k] = label_for_position(&s->map, s->map.map[k]);
    else
        ca_default_labels(d->channels[dir], d->labels[dir]);
    d->latency[dir] = (UInt32)((double)s->latency * d->rate / 1e6);
    d->transport = transport_for(s);
    d->terminal[dir] = terminal_for(s);
    d->volume[dir] = s->volume;
    d->mute[dir] = (UInt32)s->mute;
    d->monitor = s->monitor;
}

/* merges a listing into the table and says what changed */
static void merge(listing *l)
{
    AudioObjectPropertyAddress changed[4];
    UInt32 nchanged = 0;
    AudioObjectID died[MAX_DEVICES];
    UInt32 ndied = 0;
    int list_changed = 0;
    struct { AudioObjectID id; int dir, volume, mute; } level[MAX_DEVICES];
    UInt32 nlevel = 0;

    lock();
    if (l->server[0])
        copy_str(server_name, sizeof server_name, l->server);
    for (UInt32 i = 0; i < device_count; i++)
        devices[i].listed = 0;
    for (int k = 0; k < l->count; k++) {
        server_device *s = &l->list[k];
        ca_device *d = NULL;
        int fresh = 0;
        for (UInt32 i = 0; i < device_count && !d; i++)
            if (devices[i].alive && devices[i].stream[s->dir] && !strcmp(devices[i].server_name[s->dir], s->name))
                d = &devices[i];
        if (!d) {
            d = new_device();
            if (!d)
                continue;
            d->stream[s->dir] = next_id++;
            list_changed = fresh = 1;
        }
        d->listed = 1;
        Float32 volume = d->volume[s->dir];
        UInt32 mute = d->mute[s->dir];
        fill_device(d, s);
        if (!fresh && nlevel < MAX_DEVICES && (volume != d->volume[s->dir] || mute != d->mute[s->dir])) {
            level[nlevel].id = d->id;
            level[nlevel].dir = s->dir;
            level[nlevel].volume = volume != d->volume[s->dir];
            level[nlevel].mute = mute != d->mute[s->dir];
            nlevel++;
        }
    }
    for (UInt32 i = 0; i < device_count; i++)
        if (devices[i].alive && !devices[i].listed) {
            devices[i].alive = 0;
            died[ndied++] = devices[i].id;
            list_changed = 1;
        }
    for (int dir = 0; dir < 2; dir++) {
        AudioObjectID id = 0, first = 0;
        for (UInt32 i = 0; i < device_count; i++) {
            ca_device *d = &devices[i];
            if (!d->listed || !d->stream[dir] || d->monitor)
                continue;
            if (!first)
                first = d->id;
            if (!strcmp(d->server_name[dir], l->default_name[dir]))
                id = d->id;
        }
        if (!id)
            id = first;
        if (id != default_device[dir]) {
            default_device[dir] = id;
            AudioObjectPropertyAddress a = {dir == CA_OUT ? kAudioHardwarePropertyDefaultOutputDevice
                                                         : kAudioHardwarePropertyDefaultInputDevice,
                                            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            changed[nchanged++] = a;
            if (dir == CA_OUT) {
                a.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice;
                changed[nchanged++] = a;
            }
        }
    }
    unlock();

    for (UInt32 i = 0; i < ndied; i++)
        ca_notify1(died[i], kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal);
    /* a volume or mute changed: the main element and the first channels */
    for (UInt32 i = 0; i < nlevel; i++) {
        AudioObjectPropertyAddress a[9];
        UInt32 n = 0;
        AudioObjectPropertyScope scope = level[i].dir == CA_OUT ? kAudioObjectPropertyScopeOutput
                                                                : kAudioObjectPropertyScopeInput;
        for (UInt32 e = 0; e <= 2; e++) {
            if (level[i].volume) {
                a[n++] = (AudioObjectPropertyAddress){kAudioDevicePropertyVolumeScalar, scope, e};
                a[n++] = (AudioObjectPropertyAddress){kAudioDevicePropertyVolumeDecibels, scope, e};
            }
            if (level[i].mute)
                a[n++] = (AudioObjectPropertyAddress){kAudioDevicePropertyMute, scope, e};
        }
        ca_notify(level[i].id, n, a);
    }
    if (list_changed) {
        AudioObjectPropertyAddress a = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        changed[nchanged++] = a;
    }
    if (nchanged)
        ca_notify(kAudioObjectSystemObject, nchanged, changed);
}

static int enumerate(void)
{
    connection k;
    if (!connect_server(&k))
        return 0;
    listing l;
    int ok = list_server(&k, &l);
    disconnect(&k);
    if (ok)
        merge(&l);
    free(l.list);
    return ok;
}

static void init_once(void)
{
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&table_lock, &attr);
    pthread_mutexattr_destroy(&attr);

    const char *want = getenv("FERRY_AUDIO");
    if (want && !strcmp(want, "null"))
        null_backend = 1;
    else if (!load_pulse())
        null_backend = 1;
    else if (!enumerate())
        null_backend = 1;
    if (null_backend)
        add_null_device();
}

void ca_init(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, init_once);
}

/* ---- hearing the server change -------------------------------------------------------- */

static volatile int server_changed;

static void subscribe_cb(pa_context *c, int type, uint32_t idx, void *userdata)
{
    server_changed = 1;
}

static void *watch(void *unused)
{
    for (;;) {
        connection k;
        if (!connect_server(&k)) {
            /* the server went away: its devices are gone until it's back */
            listing none;
            memset(&none, 0, sizeof none);
            merge(&none);
            ca_sleep_ns(2000000000ull);
            continue;
        }
        pa.pa_context_set_subscribe_callback(k.context, subscribe_cb, NULL);
        pa_operation *o = pa.pa_context_subscribe(
            k.context, PA_SUBSCRIPTION_MASK_SINK | PA_SUBSCRIPTION_MASK_SOURCE | PA_SUBSCRIPTION_MASK_SERVER, NULL,
            NULL);
        if (o)
            pa.pa_operation_unref(o);
        enumerate(); /* what changed while nobody listened */
        while (pa.pa_context_get_state(k.context) == PA_CONTEXT_READY) {
            if (pa.pa_mainloop_iterate(k.loop, 0, NULL) < 0)
                break;
            if (server_changed) {
                /* let a burst of changes settle, then list once */
                ca_sleep_ns(50000000);
                pa.pa_mainloop_iterate(k.loop, 0, NULL);
                server_changed = 0;
                enumerate();
            }
            ca_sleep_ns(20000000);
        }
        disconnect(&k);
    }
    return NULL;
}

static void start_watching(void)
{
    pthread_t t;
    if (!pthread_create(&t, NULL, watch, NULL))
        pthread_detach(t);
}

void ca_watch_server(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    ca_init();
    if (!null_backend)
        pthread_once(&once, start_watching);
}

static void set_default_cb(pa_context *c, int success, void *userdata)
{
    int *result = userdata;
    *result = success ? 1 : -1;
}

OSStatus ca_set_default_device(int direction, AudioObjectID id)
{
    ca_init();
    ca_device *d = ca_device_for(id);
    if (!d || !d->alive || !d->stream[direction] || d->monitor)
        return kAudioHardwareIllegalOperationError;
    if (null_backend)
        return noErr;
    char name[256];
    lock();
    snprintf(name, sizeof name, "%s", d->server_name[direction]);
    unlock();
    connection k;
    if (!connect_server(&k))
        return kAudioHardwareNotRunningError;
    int result = 0;
    pa_operation *o = direction == CA_OUT ? pa.pa_context_set_default_sink(k.context, name, set_default_cb, &result)
                                          : pa.pa_context_set_default_source(k.context, name, set_default_cb, &result);
    UInt64 deadline = ca_now() + 2000000000ull;
    while (o && !result && ca_now() < deadline && pa.pa_mainloop_iterate(k.loop, 0, NULL) >= 0)
        ca_sleep_ns(500000);
    if (o)
        pa.pa_operation_unref(o);
    disconnect(&k);
    if (result != 1)
        return kAudioHardwareUnspecifiedError;
    enumerate();
    return noErr;
}

/* a device's volume (0 to 1, as the server's percentage) or mute, on the
 * server; the null device has neither */
OSStatus ca_set_device_level(AudioObjectID id, int direction, int mute, Float32 value)
{
    ca_init();
    ca_device *d = ca_device_for(id);
    if (!d || !d->alive || !d->stream[direction])
        return kAudioHardwareBadDeviceError;
    if (null_backend)
        return kAudioHardwareUnknownPropertyError;
    if (!mute) {
        if (!(value >= 0)) /* also NaN */
            value = 0;
        if (value > 1)
            value = 1;
    }
    char name[256];
    lock();
    snprintf(name, sizeof name, "%s", d->server_name[direction]);
    UInt32 channels = d->channels[direction];
    unlock();
    connection k;
    if (!connect_server(&k))
        return kAudioHardwareNotRunningError;
    int result = 0;
    pa_cvolume v;
    memset(&v, 0, sizeof v);
    v.channels = (uint8_t)(channels && channels <= PA_CHANNELS_MAX ? channels : 2);
    for (int i = 0; i < v.channels; i++)
        v.values[i] = (uint32_t)(value * PA_VOLUME_NORM + 0.5f);
    pa_operation *o;
    if (mute)
        o = direction == CA_OUT ? pa.pa_context_set_sink_mute_by_name(k.context, name, value != 0, set_default_cb, &result)
                                : pa.pa_context_set_source_mute_by_name(k.context, name, value != 0, set_default_cb,
                                                                        &result);
    else
        o = direction == CA_OUT ? pa.pa_context_set_sink_volume_by_name(k.context, name, &v, set_default_cb, &result)
                                : pa.pa_context_set_source_volume_by_name(k.context, name, &v, set_default_cb, &result);
    UInt64 deadline = ca_now() + 2000000000ull;
    while (o && !result && ca_now() < deadline && pa.pa_mainloop_iterate(k.loop, 0, NULL) >= 0)
        ca_sleep_ns(500000);
    if (o)
        pa.pa_operation_unref(o);
    disconnect(&k);
    if (result != 1)
        return kAudioHardwareUnspecifiedError;
    /* what the server now says, and listeners told */
    enumerate();
    return noErr;
}

void ca_device_running(ca_device *d, int delta)
{
    lock();
    int was = d->running > 0;
    d->running += delta;
    if (d->running < 0)
        d->running = 0;
    int is = d->running > 0;
    AudioObjectID id = d->id;
    unlock();
    if (was != is) {
        AudioObjectPropertyAddress a[2] = {
            {kAudioDevicePropertyDeviceIsRunning, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
            {kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal,
             kAudioObjectPropertyElementMain},
        };
        ca_notify(id, 2, a);
    }
}

/* ---- the null device's sound: a file, or a loopback ring -------------------------------- */

enum { RING_FRAMES = 48000 * 2, RING_CHANNELS = 2 };
static pthread_mutex_t ring_lock = PTHREAD_MUTEX_INITIALIZER;
static float ring[RING_FRAMES * RING_CHANNELS];
static UInt32 ring_head, ring_count; /* in frames */
static int ring_readers;             /* open recordings that hear the ring */
/* the loopback's own latency: a recording hears nothing until this much is
 * waiting, and again after the ring runs dry, so that a player a little
 * late doesn't leave gaps in what is heard */
enum { RING_LATENCY = 2400 };
static int ring_primed;
static pthread_mutex_t file_lock = PTHREAD_MUTEX_INITIALIZER;

/* a recording opening hears only what is played from then on */
static void ring_reader(int delta)
{
    pthread_mutex_lock(&ring_lock);
    if (delta > 0 && !ring_readers) {
        ring_head = ring_count = 0;
        ring_primed = 0;
    }
    ring_readers += delta;
    pthread_mutex_unlock(&ring_lock);
}

static void ring_put(const float *s, UInt32 frames, UInt32 channels)
{
    pthread_mutex_lock(&ring_lock);
    if (!ring_readers) {
        pthread_mutex_unlock(&ring_lock);
        return;
    }
    for (UInt32 i = 0; i < frames; i++) {
        UInt32 at = (ring_head + ring_count) % RING_FRAMES;
        const float *f = s + (size_t)i * channels;
        ring[at * 2] = f[0];
        ring[at * 2 + 1] = channels > 1 ? f[1] : f[0];
        if (ring_count < RING_FRAMES)
            ring_count++;
        else
            ring_head = (ring_head + 1) % RING_FRAMES;
    }
    pthread_mutex_unlock(&ring_lock);
}

static void ring_get(float *s, UInt32 frames, UInt32 channels)
{
    pthread_mutex_lock(&ring_lock);
    if (!ring_primed && ring_count >= RING_LATENCY)
        ring_primed = 1;
    for (UInt32 i = 0; i < frames; i++) {
        float l = 0, r = 0;
        if (!ring_count)
            ring_primed = 0;
        if (ring_primed && ring_count) {
            l = ring[ring_head * 2];
            r = ring[ring_head * 2 + 1];
            ring_head = (ring_head + 1) % RING_FRAMES;
            ring_count--;
        }
        float *f = s + (size_t)i * channels;
        if (channels == 1)
            f[0] = (l + r) * 0.5f;
        else {
            f[0] = l;
            f[1] = r;
            for (UInt32 c = 2; c < channels; c++)
                f[c] = 0;
        }
    }
    pthread_mutex_unlock(&ring_lock);
}

/* ---- streams -------------------------------------------------------------------------- */

struct ca_stream {
    ca_device *device;
    int dir;
    UInt32 channels;
    Float64 rate;
    pa_simple *simple;
    /* the null device's clock */
    UInt64 start;
    UInt64 frames;
    FILE *file;
    int loopback;
};

ca_stream *ca_stream_open(ca_device *d, int dir, Float64 rate, UInt32 channels, const UInt32 *labels,
                          UInt32 frames_per_buffer)
{
    ca_init();
    if (!d || !channels || channels > CA_MAX_CHANNELS || rate < 1 || rate > 384000)
        return NULL;
    ca_stream *s = calloc(1, sizeof *s);
    if (!s)
        return NULL;
    s->device = d;
    s->dir = dir;
    s->channels = channels;
    s->rate = rate;
    if (!frames_per_buffer)
        frames_per_buffer = 512;
    if (null_backend) {
        const char *path = getenv(dir == CA_OUT ? "FERRY_AUDIO_OUTPUT_FILE" : "FERRY_AUDIO_INPUT_FILE");
        if (path && *path)
            s->file = fopen(path, dir == CA_OUT ? "ab" : "rb");
        s->loopback = dir == CA_IN && !s->file;
        if (s->loopback)
            ring_reader(1);
        s->start = ca_now();
        ca_device_running(d, 1);
        return s;
    }
    UInt32 own[CA_MAX_CHANNELS];
    if (!labels) {
        ca_default_labels(channels, own);
        labels = own;
    }
    pa_sample_spec spec = {PA_SAMPLE_FLOAT32LE, (uint32_t)(rate + 0.5), (uint8_t)channels};
    pa_channel_map map;
    map_for_labels(labels, channels, &map);
    uint32_t frame_bytes = 4 * channels;
    pa_buffer_attr attr;
    memset(&attr, 0xFF, sizeof attr); /* (uint32_t)-1: the server's choice */
    UInt32 period = frames_per_buffer < 64 ? 64 : frames_per_buffer;
    if (dir == CA_OUT) {
        UInt32 min = (UInt32)(rate * 0.04); /* at least 40 ms in flight */
        attr.tlength = (period * 2 > min ? period * 2 : min) * frame_bytes;
        attr.minreq = period * frame_bytes;
    } else
        attr.fragsize = period * frame_bytes;
    char dev[256];
    lock();
    snprintf(dev, sizeof dev, "%s", d->server_name[dir]);
    unlock();
    int error = 0;
    s->simple = pa.pa_simple_new(NULL, ca_program_name(), dir == CA_OUT ? PA_STREAM_PLAYBACK : PA_STREAM_RECORD,
                                 dev[0] ? dev : NULL, dir == CA_OUT ? "Playback" : "Recording", &spec, &map, &attr,
                                 &error);
    if (!s->simple) {
        fprintf(stderr, "Ferry: Core Audio couldn't open a %s stream on %s: %s\n",
                dir == CA_OUT ? "playback" : "recording", dev, pa.pa_strerror(error));
        free(s);
        return NULL;
    }
    ca_device_running(d, 1);
    return s;
}

/* the null device runs on the clock: it may get up to 20 ms ahead when
 * playing, and records no faster than time passes */
static void null_pace(ca_stream *s, UInt32 frames)
{
    UInt64 now = ca_now();
    UInt64 due = s->start + (UInt64)((double)(s->frames + (s->dir == CA_IN ? frames : 0)) * 1e9 / s->rate);
    UInt64 ahead = s->dir == CA_OUT ? 20000000ull : 0;
    if (now + 100000000ull < due - ahead || now > due + 200000000ull) {
        /* the clock jumped, or the program fell far behind: start over */
        s->start = now;
        s->frames = 0;
        if (s->dir == CA_IN)
            ca_sleep_ns((UInt64)(frames * 1e9 / s->rate));
    } else if (due > now + ahead)
        ca_sleep_ns(due - now - ahead);
    s->frames += frames;
}

int ca_stream_write(ca_stream *s, const float *samples, UInt32 frames)
{
    if (!frames)
        return 0;
    if (s->simple) {
        int error = 0;
        return pa.pa_simple_write(s->simple, samples, (size_t)frames * s->channels * 4, &error) < 0 ? -1 : 0;
    }
    null_pace(s, frames);
    if (s->file) {
        pthread_mutex_lock(&file_lock);
        fwrite(samples, 4 * s->channels, frames, s->file);
        fflush(s->file);
        pthread_mutex_unlock(&file_lock);
    }
    ring_put(samples, frames, s->channels);
    return 0;
}

int ca_stream_read(ca_stream *s, float *samples, UInt32 frames)
{
    if (!frames)
        return 0;
    if (s->simple) {
        int error = 0;
        return pa.pa_simple_read(s->simple, samples, (size_t)frames * s->channels * 4, &error) < 0 ? -1 : 0;
    }
    null_pace(s, frames);
    if (s->file) {
        size_t got = fread(samples, 4 * s->channels, frames, s->file);
        memset(samples + got * s->channels, 0, (frames - got) * s->channels * 4);
    } else
        ring_get(samples, frames, s->channels);
    return 0;
}

UInt64 ca_stream_latency_ns(ca_stream *s)
{
    if (s->simple) {
        int error = 0;
        pa_usec_t us = pa.pa_simple_get_latency(s->simple, &error);
        return us == (pa_usec_t)-1 ? 0 : us * 1000;
    }
    if (s->dir == CA_IN)
        return 0;
    UInt64 due = s->start + (UInt64)((double)s->frames * 1e9 / s->rate);
    UInt64 now = ca_now();
    return due > now ? due - now : 0;
}

void ca_stream_close(ca_stream *s, int drain)
{
    if (!s)
        return;
    if (s->simple) {
        int error = 0;
        if (drain && s->dir == CA_OUT)
            pa.pa_simple_drain(s->simple, &error);
        pa.pa_simple_free(s->simple);
    } else if (drain && s->dir == CA_OUT) {
        UInt64 left = ca_stream_latency_ns(s);
        if (left)
            ca_sleep_ns(left);
    }
    if (s->file)
        fclose(s->file);
    if (s->loopback)
        ring_reader(-1);
    ca_device_running(s->device, -1);
    free(s);
}
