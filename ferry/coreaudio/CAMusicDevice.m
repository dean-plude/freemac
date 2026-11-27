/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Music devices and the peak limiter (freemac 1.NEXT), written from Apple's
 * public documentation of MusicDevice.h, AUComponent.h and
 * AudioUnitProperties.h.
 *
 * Ferry has two of Apple's synth units, the DLS synth and the MIDI synth,
 * which take MIDI events (MusicDeviceMIDIEvent, MusicDeviceSysEx, and notes
 * started and stopped by number) and render them as 32-bit float samples.
 * Both play with this system's FluidSynth (libfluidsynth, LGPL-2.1+, looked
 * up through ferry_synth_symbol() in src/host.c) from a sound bank: the
 * SoundFont or DLS file the program names with
 * kMusicDeviceProperty_SoundBankURL, or else a General MIDI SoundFont that
 * this system has, such as Debian's fluid-soundfont-gm (FluidR3_GM, MIT
 * licensed). A Mac's own bank is Apple's and isn't used. Without FluidSynth
 * or a bank the units still open, and fail to initialize, as a program
 * expects when its synth can't load its sounds. VLC's MIDI decoder
 * (audiotoolbox_midi) plays a MIDI file through a DLS or MIDI synth, a peak
 * limiter and a generic output unit in an AUGraph (CAGraph.m).
 *
 * The peak limiter keeps loud passages under full scale: it follows the
 * louder channel's peaks, after its pre-gain, and turns the gain down
 * over its attack time and back up over its decay time.
 *
 * Both are plug-in units, registered with AudioComponentRegister when Core
 * Audio loads, so a program finds them as it finds a Mac's.
 */
#import "CAInternal.h"
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void *ferry_synth_symbol(const char *name); /* src/host.c */

/* ---- FluidSynth ------------------------------------------------------------------------
 * The calls and constants of FluidSynth's published, stable C API (2.x)
 * that the synth units use, written here from its documentation. */
typedef struct fluid_settings_t fluid_settings_t;
typedef struct fluid_synth_t fluid_synth_t;
typedef void (*fluid_log_function_t)(int level, const char *message, void *data);
enum { FLUID_PANIC = 0, FLUID_ERR = 1, FLUID_WARN = 2, FLUID_INFO = 3, FLUID_DBG = 4 };
enum { FLUID_OK = 0, FLUID_FAILED = -1 };

static struct {
    fluid_settings_t *(*new_settings)(void);
    void (*delete_settings)(fluid_settings_t *);
    int (*setnum)(fluid_settings_t *, const char *, double);
    int (*setint)(fluid_settings_t *, const char *, int);
    fluid_synth_t *(*new_synth)(fluid_settings_t *);
    void (*delete_synth)(fluid_synth_t *);
    int (*sfload)(fluid_synth_t *, const char *, int);
    int (*sfunload)(fluid_synth_t *, int, int);
    int (*noteon)(fluid_synth_t *, int, int, int);
    int (*noteoff)(fluid_synth_t *, int, int);
    int (*cc)(fluid_synth_t *, int, int, int);
    int (*program_change)(fluid_synth_t *, int, int);
    int (*pitch_bend)(fluid_synth_t *, int, int);
    int (*channel_pressure)(fluid_synth_t *, int, int);
    int (*key_pressure)(fluid_synth_t *, int, int, int);
    int (*sysex)(fluid_synth_t *, const char *, int, char *, int *, int *, int);
    int (*system_reset)(fluid_synth_t *);
    int (*all_sounds_off)(fluid_synth_t *, int);
    int (*write_float)(fluid_synth_t *, int, void *, int, int, void *, int, int);
    int (*set_gain)(fluid_synth_t *, float);
    fluid_log_function_t (*set_log_function)(int, fluid_log_function_t, void *);
    int loaded;
} fs;

static void quiet_log(int level, const char *message, void *data)
{
    (void)level;
    (void)data;
    if (getenv("FERRY_VERBOSE"))
        fprintf(stderr, "ferry: FluidSynth: %s\n", message);
}

static void load_fluidsynth(void)
{
#define FS(field, name) *(void **)&fs.field = ferry_synth_symbol(name)
    FS(new_settings, "new_fluid_settings");
    FS(delete_settings, "delete_fluid_settings");
    FS(setnum, "fluid_settings_setnum");
    FS(setint, "fluid_settings_setint");
    FS(new_synth, "new_fluid_synth");
    FS(delete_synth, "delete_fluid_synth");
    FS(sfload, "fluid_synth_sfload");
    FS(sfunload, "fluid_synth_sfunload");
    FS(noteon, "fluid_synth_noteon");
    FS(noteoff, "fluid_synth_noteoff");
    FS(cc, "fluid_synth_cc");
    FS(program_change, "fluid_synth_program_change");
    FS(pitch_bend, "fluid_synth_pitch_bend");
    FS(channel_pressure, "fluid_synth_channel_pressure");
    FS(key_pressure, "fluid_synth_key_pressure");
    FS(sysex, "fluid_synth_sysex");
    FS(system_reset, "fluid_synth_system_reset");
    FS(all_sounds_off, "fluid_synth_all_sounds_off");
    FS(write_float, "fluid_synth_write_float");
    FS(set_gain, "fluid_synth_set_gain");
    FS(set_log_function, "fluid_set_log_function");
#undef FS
    fs.loaded = fs.new_settings && fs.delete_settings && fs.setnum && fs.setint && fs.new_synth && fs.delete_synth &&
                fs.sfload && fs.noteon && fs.noteoff && fs.cc && fs.program_change && fs.pitch_bend &&
                fs.channel_pressure && fs.system_reset && fs.write_float;
    if (fs.loaded && fs.set_log_function)
        for (int level = FLUID_PANIC; level <= FLUID_DBG; level++)
            fs.set_log_function(level, quiet_log, NULL);
}

static int have_fluidsynth(void)
{
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, load_fluidsynth);
    return fs.loaded;
}

/* The General MIDI banks a system may have, best first: FERRY_SOUNDFONT
 * names another (the tests use one of their own). */
static const char *const default_banks[] = {
    "/usr/share/sounds/sf2/FluidR3_GM.sf2", "/usr/share/sounds/sf2/default-GM.sf2",
    "/usr/share/soundfonts/default.sf2",    "/usr/share/soundfonts/FluidR3_GM.sf2",
    "/usr/share/sounds/sf3/default-GM.sf3", "/usr/share/sounds/sf3/MuseScore_General.sf3",
    "/usr/share/sounds/sf2/TimGM6mb.sf2",   NULL,
};

static int readable_file(const char *path)
{
    struct stat st;
    return path && *path && stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

static const char *default_bank(void)
{
    const char *other = getenv("FERRY_SOUNDFONT");
    if (other && *other)
        return readable_file(other) ? other : NULL;
    for (int i = 0; default_banks[i]; i++)
        if (readable_file(default_banks[i]))
            return default_banks[i];
    return NULL;
}

/* ---- the units -------------------------------------------------------------------------- */

enum { UNIT_SYNTH, UNIT_LIMITER };
enum { MAX_EVENTS = 1024, DEFAULT_MAX_FRAMES = 4096 };

/* the DLS synth's parameters, from Apple's documentation of AudioUnitParameters.h */
enum { kMusicDeviceParam_Tuning = 0, kMusicDeviceParam_Volume = 1, kMusicDeviceParam_ReverbVolume = 2 };

typedef struct {
    UInt32 offset;
    UInt8 status, data1, data2;
} midi_event;

typedef struct listener {
    struct listener *next;
    AudioUnitPropertyID id;
    AudioUnitPropertyListenerProc proc;
    void *ref;
} listener;

typedef struct notify {
    struct notify *next;
    AURenderCallback proc;
    void *ref;
} notify;

typedef struct {
    AudioComponentPlugInInterface iface; /* first, as a plug-in's is */
    AudioUnit unit;
    int kind;
    pthread_mutex_t lock;
    int initialized;
    AudioStreamBasicDescription format[2]; /* [0] the input scope's, [1] the output scope's */
    UInt32 max_frames;
    listener *listeners;
    notify *notifies;
    OSStatus last_error;
    /* the synth */
    char bank[PATH_MAX]; /* empty: the system's General MIDI bank */
    CFURLRef bank_url;
    fluid_settings_t *settings;
    fluid_synth_t *synth;
    int font;
    Float32 tuning, volume_db, reverb_db;
    midi_event events[MAX_EVENTS];
    UInt32 nevents;
    float *scratch; /* stereo, interleaved, for a mono or many-channel format */
    UInt32 scratch_frames;
    /* the limiter */
    AURenderCallbackStruct input;
    AudioUnitConnection connection;
    int connected;
    Float32 attack, decay, pregain_db;
    UInt32 bypass;
    double gain;
    void *own[CA_MAX_CHANNELS];
    UInt32 own_bytes;
} unit;

static void canonical(AudioStreamBasicDescription *f, Float64 rate, UInt32 channels)
{
    memset(f, 0, sizeof *f);
    f->mSampleRate = rate;
    f->mFormatID = kAudioFormatLinearPCM;
    f->mFormatFlags = kAudioFormatFlagsAudioUnitCanonical;
    f->mBitsPerChannel = 32;
    f->mChannelsPerFrame = channels;
    f->mFramesPerPacket = 1;
    f->mBytesPerFrame = f->mBytesPerPacket = 4;
}

static int is_float_format(const AudioStreamBasicDescription *f)
{
    return f->mFormatID == kAudioFormatLinearPCM && (f->mFormatFlags & kAudioFormatFlagIsFloat) &&
           f->mBitsPerChannel == 32 && f->mChannelsPerFrame >= 1 && f->mChannelsPerFrame <= CA_MAX_CHANNELS &&
           f->mSampleRate > 0 && !(f->mFormatFlags & kAudioFormatFlagIsBigEndian);
}

static void tell_listeners(unit *self, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el)
{
    for (listener *l = self->listeners; l; l = l->next)
        if (l->id == id)
            l->proc(l->ref, self->unit, id, scope, el);
}

/* ---- the synth's sound ---- */

static double db_to_gain(double db)
{
    return pow(10.0, db / 20.0);
}

static void apply_gain(unit *self)
{
    /* FluidSynth's own default is 0.2, quieter than a Mac's synth */
    if (self->synth && fs.set_gain)
        fs.set_gain(self->synth, (float)(0.5 * db_to_gain(self->volume_db)));
}

static void free_synth(unit *self)
{
    if (self->synth)
        fs.delete_synth(self->synth);
    if (self->settings)
        fs.delete_settings(self->settings);
    self->synth = NULL;
    self->settings = NULL;
    self->font = -1;
}

static OSStatus make_synth(unit *self)
{
    if (!have_fluidsynth())
        return kAudioUnitErr_FailedInitialization;
    const char *bank = self->bank[0] ? self->bank : default_bank();
    if (!bank)
        return self->bank[0] ? kAudioUnitErr_InvalidFile : kAudioUnitErr_FailedInitialization;
    fluid_settings_t *settings = fs.new_settings();
    if (!settings)
        return kAudioUnitErr_FailedInitialization;
    fs.setnum(settings, "synth.sample-rate", self->format[1].mSampleRate);
    fs.setint(settings, "synth.cpu-cores", 1);
    fluid_synth_t *synth = fs.new_synth(settings);
    if (!synth) {
        fs.delete_settings(settings);
        return kAudioUnitErr_FailedInitialization;
    }
    int font = fs.sfload(synth, bank, 1);
    if (font == FLUID_FAILED) {
        fs.delete_synth(synth);
        fs.delete_settings(settings);
        return kAudioUnitErr_InvalidFile;
    }
    self->settings = settings;
    self->synth = synth;
    self->font = font;
    apply_gain(self);
    return noErr;
}

static void play_event(unit *self, UInt32 status, UInt32 d1, UInt32 d2)
{
    fluid_synth_t *s = self->synth;
    if (!s)
        return;
    int chan = status & 0x0F;
    d1 &= 0x7F;
    d2 &= 0x7F;
    switch (status & 0xF0) {
    case 0x80: fs.noteoff(s, chan, (int)d1); break;
    case 0x90:
        if (d2)
            fs.noteon(s, chan, (int)d1, (int)d2);
        else
            fs.noteoff(s, chan, (int)d1);
        break;
    case 0xA0:
        if (fs.key_pressure)
            fs.key_pressure(s, chan, (int)d1, (int)d2);
        break;
    case 0xB0: fs.cc(s, chan, (int)d1, (int)d2); break;
    case 0xC0: fs.program_change(s, chan, (int)d1); break;
    case 0xD0: fs.channel_pressure(s, chan, (int)d1); break;
    case 0xE0: fs.pitch_bend(s, chan, (int)(d1 | d2 << 7)); break;
    case 0xF0:
        if (status == 0xFF) /* system reset */
            fs.system_reset(s);
        break;
    }
}

/* renders frames into two float runs, each sample step apart */
static void synth_write(unit *self, UInt32 frames, float *l, int lstep, float *r, int rstep)
{
    if (self->synth && frames)
        fs.write_float(self->synth, (int)frames, l, 0, lstep, r, 0, rstep);
    else
        for (UInt32 i = 0; i < frames; i++)
            l[(size_t)i * lstep] = r[(size_t)i * rstep] = 0.0f;
}

/* renders frames at frame `at` of the list, in the output format */
static void synth_render_into(unit *self, AudioBufferList *io, UInt32 at, UInt32 frames)
{
    const AudioStreamBasicDescription *f = &self->format[1];
    UInt32 ch = f->mChannelsPerFrame;
    int split = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (ch == 2 && split && io->mNumberBuffers >= 2) {
        synth_write(self, frames, (float *)io->mBuffers[0].mData + at, 1, (float *)io->mBuffers[1].mData + at, 1);
        return;
    }
    if (ch == 2 && !split) {
        float *b = (float *)io->mBuffers[0].mData + (size_t)at * 2;
        synth_write(self, frames, b, 2, b + 1, 2);
        return;
    }
    /* mono, or more than two channels: stereo in the scratch buffer, then spread */
    if (self->scratch_frames < frames) {
        float *more = realloc(self->scratch, sizeof(float) * 2 * frames);
        if (!more)
            return;
        self->scratch = more;
        self->scratch_frames = frames;
    }
    synth_write(self, frames, self->scratch, 2, self->scratch + 1, 2);
    for (UInt32 i = 0; i < frames; i++) {
        float lv = self->scratch[2 * i], rv = self->scratch[2 * i + 1];
        for (UInt32 c = 0; c < ch; c++) {
            float v = ch == 1 ? 0.5f * (lv + rv) : c == 0 ? lv : c == 1 ? rv : 0.0f;
            if (split) {
                if (c < io->mNumberBuffers)
                    ((float *)io->mBuffers[c].mData)[at + i] = v;
            } else
                ((float *)io->mBuffers[0].mData)[(size_t)(at + i) * ch + c] = v;
        }
    }
}

/* ---- buffers a caller left to the unit ---- */

static OSStatus give_buffers(unit *self, const AudioStreamBasicDescription *f, UInt32 frames, AudioBufferList *io)
{
    int split = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 n = split ? f->mChannelsPerFrame : 1;
    if (io->mNumberBuffers < n)
        return kAudio_ParamError;
    UInt32 bytes = frames * 4 * (split ? 1 : f->mChannelsPerFrame);
    int any_missing = 0;
    for (UInt32 i = 0; i < n; i++)
        any_missing |= io->mBuffers[i].mData == NULL;
    if (!any_missing)
        return noErr;
    if (self->own_bytes < bytes) {
        for (UInt32 i = 0; i < CA_MAX_CHANNELS; i++) {
            free(self->own[i]);
            self->own[i] = NULL;
        }
        self->own_bytes = 0;
        for (UInt32 i = 0; i < n; i++)
            if (!(self->own[i] = calloc(1, bytes)))
                return kAudio_MemFullError;
        self->own_bytes = bytes;
    }
    for (UInt32 i = 0; i < n; i++)
        if (!io->mBuffers[i].mData) {
            io->mBuffers[i].mData = self->own[i];
            io->mBuffers[i].mDataByteSize = bytes;
            io->mBuffers[i].mNumberChannels = split ? 1 : f->mChannelsPerFrame;
        }
    return noErr;
}

static int list_fits(const AudioStreamBasicDescription *f, UInt32 frames, const AudioBufferList *io)
{
    int split = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 n = split ? f->mChannelsPerFrame : 1;
    UInt32 bytes = frames * 4 * (split ? 1 : f->mChannelsPerFrame);
    if (io->mNumberBuffers < n)
        return 0;
    for (UInt32 i = 0; i < n; i++)
        if (io->mBuffers[i].mDataByteSize < bytes)
            return 0;
    return 1;
}

static void call_notifies(unit *self, AudioUnitRenderActionFlags flags, const AudioTimeStamp *t, UInt32 bus,
                          UInt32 frames, AudioBufferList *io)
{
    for (notify *n = self->notifies; n; n = n->next) {
        AudioUnitRenderActionFlags f = flags;
        n->proc(n->ref, &f, t, bus, frames, io);
    }
}

/* ---- the limiter's sound ---- */

static void limit(unit *self, AudioBufferList *io, UInt32 frames)
{
    const AudioStreamBasicDescription *f = &self->format[1];
    UInt32 ch = f->mChannelsPerFrame;
    int split = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    double rate = f->mSampleRate > 0 ? f->mSampleRate : 44100;
    double pre = db_to_gain(self->pregain_db);
    double up = 1.0 - exp(-1.0 / (fmax(self->attack, 0.0001) * rate));
    double down = 1.0 - exp(-1.0 / (fmax(self->decay, 0.0001) * rate));
    const double ceiling = 0.98;
    double g = self->gain;
    for (UInt32 i = 0; i < frames; i++) {
        double peak = 0;
        for (UInt32 c = 0; c < ch; c++) {
            float *s = split ? (c < io->mNumberBuffers ? (float *)io->mBuffers[c].mData + i : NULL)
                             : (float *)io->mBuffers[0].mData + (size_t)i * ch + c;
            if (s)
                peak = fmax(peak, fabs(*s * pre));
        }
        double want = peak > ceiling ? ceiling / peak : 1.0;
        g += (want - g) * (want < g ? up : down);
        for (UInt32 c = 0; c < ch; c++) {
            float *s = split ? (c < io->mNumberBuffers ? (float *)io->mBuffers[c].mData + i : NULL)
                             : (float *)io->mBuffers[0].mData + (size_t)i * ch + c;
            if (!s)
                continue;
            double v = *s * pre * g;
            /* what the gain hasn't caught up with yet stays under full scale */
            *s = (float)(v > 1.0 ? 1.0 : v < -1.0 ? -1.0 : v);
        }
    }
    self->gain = g;
}

/* ---- the calls on a unit ---- */

static OSStatus u_initialize(void *p)
{
    unit *self = p;
    pthread_mutex_lock(&self->lock);
    OSStatus err = noErr;
    if (!self->initialized) {
        if (self->kind == UNIT_SYNTH)
            err = make_synth(self);
        if (!err) {
            self->initialized = 1;
            self->gain = 1.0;
            self->nevents = 0;
        }
    }
    pthread_mutex_unlock(&self->lock);
    return err;
}

static OSStatus u_uninitialize(void *p)
{
    unit *self = p;
    pthread_mutex_lock(&self->lock);
    if (self->kind == UNIT_SYNTH)
        free_synth(self);
    self->initialized = 0;
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static int scope_side(unit *self, AudioUnitScope scope, AudioUnitElement el)
{
    if (el != 0)
        return -1;
    if (scope == kAudioUnitScope_Output)
        return 1;
    if (scope == kAudioUnitScope_Input && self->kind == UNIT_LIMITER)
        return 0;
    return -1;
}

static const AudioUnitParameterID limiter_params[] = {kLimiterParam_AttackTime, kLimiterParam_DecayTime,
                                                      kLimiterParam_PreGain};
static const AudioUnitParameterID synth_params[] = {kMusicDeviceParam_Tuning, kMusicDeviceParam_Volume,
                                                    kMusicDeviceParam_ReverbVolume};

static int param_info(unit *self, AudioUnitParameterID id, AudioUnitParameterInfo *info)
{
    memset(info, 0, sizeof *info);
    info->flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
    const char *name;
    if (self->kind == UNIT_LIMITER) {
        switch (id) {
        case kLimiterParam_AttackTime:
            name = "attack time";
            info->unit = kAudioUnitParameterUnit_Seconds;
            info->minValue = 0.001f, info->maxValue = 0.03f, info->defaultValue = 0.012f;
            break;
        case kLimiterParam_DecayTime:
            name = "decay time";
            info->unit = kAudioUnitParameterUnit_Seconds;
            info->minValue = 0.001f, info->maxValue = 0.06f, info->defaultValue = 0.024f;
            break;
        case kLimiterParam_PreGain:
            name = "pre-gain";
            info->unit = kAudioUnitParameterUnit_Decibels;
            info->minValue = -40, info->maxValue = 40, info->defaultValue = 0;
            break;
        default: return 0;
        }
    } else {
        switch (id) {
        case kMusicDeviceParam_Tuning:
            name = "Tuning";
            info->unit = kAudioUnitParameterUnit_Cents;
            info->minValue = -1200, info->maxValue = 1200, info->defaultValue = 0;
            break;
        case kMusicDeviceParam_Volume:
            name = "Volume";
            info->unit = kAudioUnitParameterUnit_Decibels;
            info->minValue = -120, info->maxValue = 40, info->defaultValue = 0;
            break;
        case kMusicDeviceParam_ReverbVolume:
            name = "Reverb Volume";
            info->unit = kAudioUnitParameterUnit_Decibels;
            info->minValue = -120, info->maxValue = 40, info->defaultValue = -120;
            break;
        default: return 0;
        }
    }
    snprintf(info->name, sizeof info->name, "%s", name);
    return 1;
}

/* copies a value out as AudioUnitGetProperty does */
static OSStatus give(const void *v, UInt32 n, void *data, UInt32 *size)
{
    if (!data) {
        *size = n;
        return noErr;
    }
    if (*size < n)
        return kAudio_ParamError;
    memcpy(data, v, n);
    *size = n;
    return noErr;
}

static OSStatus u_get(void *p, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el, void *data,
                      UInt32 *size)
{
    unit *self = p;
    if (!size)
        return kAudio_ParamError;
    OSStatus err = kAudioUnitErr_InvalidProperty;
    pthread_mutex_lock(&self->lock);
    switch (id) {
    case kAudioUnitProperty_StreamFormat: {
        int side = scope_side(self, scope, el);
        err = side < 0 ? kAudioUnitErr_InvalidScope : give(&self->format[side], sizeof self->format[side], data, size);
        break;
    }
    case kAudioUnitProperty_SampleRate: {
        int side = scope_side(self, scope, el);
        err = side < 0 ? kAudioUnitErr_InvalidScope
                       : give(&self->format[side].mSampleRate, sizeof(Float64), data, size);
        break;
    }
    case kAudioUnitProperty_ElementCount: {
        UInt32 n = scope == kAudioUnitScope_Global   ? 1
                   : scope == kAudioUnitScope_Output ? 1
                   : scope == kAudioUnitScope_Input  ? (self->kind == UNIT_LIMITER ? 1 : 0)
                                                     : 0;
        err = give(&n, sizeof n, data, size);
        break;
    }
    case kAudioUnitProperty_MaximumFramesPerSlice: err = give(&self->max_frames, sizeof(UInt32), data, size); break;
    case kAudioUnitProperty_Latency:
    case kAudioUnitProperty_TailTime: {
        Float64 zero = id == kAudioUnitProperty_TailTime && self->kind == UNIT_SYNTH ? 0.5 : 0;
        err = give(&zero, sizeof zero, data, size);
        break;
    }
    case kAudioUnitProperty_LastRenderError: err = give(&self->last_error, sizeof(OSStatus), data, size); break;
    case kAudioUnitProperty_InPlaceProcessing: {
        UInt32 yes = 1;
        err = give(&yes, sizeof yes, data, size);
        break;
    }
    case kAudioUnitProperty_SupportedNumChannels: {
        AUChannelInfo info[2] = {{self->kind == UNIT_LIMITER ? -1 : 0, -1}, {0, 2}};
        err = give(info, self->kind == UNIT_LIMITER ? sizeof info[0] : sizeof info, data, size);
        break;
    }
    case kAudioUnitProperty_BypassEffect:
        if (self->kind == UNIT_LIMITER)
            err = give(&self->bypass, sizeof(UInt32), data, size);
        break;
    case kAudioUnitProperty_ParameterList: {
        const AudioUnitParameterID *list = self->kind == UNIT_LIMITER ? limiter_params : synth_params;
        UInt32 n = scope == kAudioUnitScope_Global ? 3 : 0;
        err = give(list, n * sizeof(AudioUnitParameterID), data, size);
        break;
    }
    case kAudioUnitProperty_ParameterInfo: {
        AudioUnitParameterInfo info;
        err = scope != kAudioUnitScope_Global || !param_info(self, el, &info) ? kAudioUnitErr_InvalidParameter
                                                                            : give(&info, sizeof info, data, size);
        break;
    }
    case kMusicDeviceProperty_SoundBankURL:
        if (self->kind != UNIT_SYNTH)
            break;
        if (!self->bank_url)
            err = kAudioUnitErr_PropertyNotInUse;
        else if (!data) {
            *size = sizeof(CFURLRef);
            err = noErr;
        } else {
            CFURLRef url = (CFURLRef)CFRetain(self->bank_url);
            err = give(&url, sizeof url, data, size);
            if (err)
                CFRelease(url);
        }
        break;
    case kMusicDeviceProperty_InstrumentCount:
        if (self->kind == UNIT_SYNTH) {
            UInt32 n = 128; /* the General MIDI programs */
            err = give(&n, sizeof n, data, size);
        }
        break;
    case kAUMIDISynthProperty_EnablePreload:
        if (self->kind == UNIT_SYNTH) {
            UInt32 n = 0;
            err = give(&n, sizeof n, data, size);
        }
        break;
    }
    pthread_mutex_unlock(&self->lock);
    return err;
}

static OSStatus u_get_info(void *p, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el, UInt32 *size,
                           Boolean *writable)
{
    unit *self = p;
    UInt32 n = 0;
    OSStatus err = u_get(p, id, scope, el, NULL, &n);
    if (err)
        return err;
    if (size)
        *size = n;
    if (writable)
        *writable = id == kAudioUnitProperty_StreamFormat || id == kAudioUnitProperty_SampleRate ||
                    id == kAudioUnitProperty_MaximumFramesPerSlice || id == kAudioUnitProperty_BypassEffect ||
                    id == kMusicDeviceProperty_SoundBankURL || id == kAUMIDISynthProperty_EnablePreload;
    (void)self;
    return noErr;
}

static OSStatus set_format(unit *self, int side, const AudioStreamBasicDescription *f)
{
    if (!is_float_format(f))
        return kAudioUnitErr_FormatNotSupported;
    if (self->initialized)
        return kAudioUnitErr_Initialized;
    self->format[side] = *f;
    /* an effect in place keeps its input and output alike */
    if (self->kind == UNIT_LIMITER)
        self->format[!side] = *f;
    return noErr;
}

static OSStatus set_bank(unit *self, const void *data, UInt32 size)
{
    if (!data || size < sizeof(CFURLRef))
        return kAudio_ParamError;
    CFURLRef url = *(const CFURLRef *)data;
    char path[PATH_MAX];
    if (!url || !CFURLGetFileSystemRepresentation(url, true, (UInt8 *)path, sizeof path))
        return kAudioUnitErr_InvalidFile;
    if (!readable_file(path))
        return kAudioUnitErr_InvalidFile;
    snprintf(self->bank, sizeof self->bank, "%s", path);
    if (self->bank_url)
        CFRelease(self->bank_url);
    self->bank_url = (CFURLRef)CFRetain(url);
    if (self->synth) {
        int font = fs.sfload(self->synth, self->bank, 1);
        if (font == FLUID_FAILED)
            return kAudioUnitErr_InvalidFile;
        if (self->font >= 0 && fs.sfunload)
            fs.sfunload(self->synth, self->font, 1);
        self->font = font;
    }
    return noErr;
}

static OSStatus u_set(void *p, AudioUnitPropertyID id, AudioUnitScope scope, AudioUnitElement el, const void *data,
                      UInt32 size)
{
    unit *self = p;
    OSStatus err = kAudioUnitErr_InvalidProperty;
    int changed_format = 0;
    pthread_mutex_lock(&self->lock);
    switch (id) {
    case kAudioUnitProperty_StreamFormat: {
        int side = scope_side(self, scope, el);
        if (side < 0)
            err = kAudioUnitErr_InvalidScope;
        else if (!data || size < sizeof(AudioStreamBasicDescription))
            err = kAudio_ParamError;
        else if (!(err = set_format(self, side, data)))
            changed_format = 1;
        break;
    }
    case kAudioUnitProperty_SampleRate: {
        int side = scope_side(self, scope, el);
        if (side < 0)
            err = kAudioUnitErr_InvalidScope;
        else if (!data || size < sizeof(Float64))
            err = kAudio_ParamError;
        else {
            AudioStreamBasicDescription f = self->format[side];
            f.mSampleRate = *(const Float64 *)data;
            if (!(err = set_format(self, side, &f)))
                changed_format = 1;
        }
        break;
    }
    case kAudioUnitProperty_MaximumFramesPerSlice:
        if (!data || size < sizeof(UInt32))
            err = kAudio_ParamError;
        else if (*(const UInt32 *)data < 16 || *(const UInt32 *)data > 65536)
            err = kAudioUnitErr_InvalidPropertyValue;
        else {
            self->max_frames = *(const UInt32 *)data;
            err = noErr;
        }
        break;
    case kAudioUnitProperty_SetRenderCallback:
        if (self->kind != UNIT_LIMITER || scope != kAudioUnitScope_Input || el != 0)
            err = kAudioUnitErr_InvalidScope;
        else {
            if (!data || size < sizeof(AURenderCallbackStruct))
                memset(&self->input, 0, sizeof self->input);
            else
                self->input = *(const AURenderCallbackStruct *)data;
            self->connected = 0;
            err = noErr;
        }
        break;
    case kAudioUnitProperty_MakeConnection:
        if (self->kind != UNIT_LIMITER || scope != kAudioUnitScope_Input)
            err = kAudioUnitErr_InvalidScope;
        else if (!data || size < sizeof(AudioUnitConnection))
            err = kAudio_ParamError;
        else {
            self->connection = *(const AudioUnitConnection *)data;
            self->connected = self->connection.sourceAudioUnit != NULL;
            if (self->connected)
                memset(&self->input, 0, sizeof self->input);
            err = noErr;
        }
        break;
    case kAudioUnitProperty_BypassEffect:
        if (self->kind == UNIT_LIMITER) {
            if (!data || size < sizeof(UInt32))
                err = kAudio_ParamError;
            else {
                self->bypass = *(const UInt32 *)data;
                err = noErr;
            }
        }
        break;
    case kAudioUnitProperty_ShouldAllocateBuffer:
    case kAudioUnitProperty_RenderQuality:
    case kAudioUnitProperty_InPlaceProcessing:
    case kAudioUnitProperty_ContextName:
    case kAudioUnitProperty_NickName: err = noErr; break;
    case kMusicDeviceProperty_SoundBankURL:
        if (self->kind == UNIT_SYNTH)
            err = set_bank(self, data, size);
        break;
    case kAUMIDISynthProperty_EnablePreload:
        if (self->kind == UNIT_SYNTH)
            err = noErr; /* the whole bank is loaded when the unit initializes */
        break;
    }
    pthread_mutex_unlock(&self->lock);
    if (changed_format) {
        tell_listeners(self, kAudioUnitProperty_StreamFormat, scope, el);
        if (self->kind == UNIT_LIMITER)
            tell_listeners(self, kAudioUnitProperty_StreamFormat,
                           scope == kAudioUnitScope_Input ? kAudioUnitScope_Output : kAudioUnitScope_Input, el);
    }
    return err;
}

static Float32 *param_slot(unit *self, AudioUnitParameterID id)
{
    if (self->kind == UNIT_LIMITER)
        return id == kLimiterParam_AttackTime  ? &self->attack
               : id == kLimiterParam_DecayTime ? &self->decay
               : id == kLimiterParam_PreGain   ? &self->pregain_db
                                               : NULL;
    return id == kMusicDeviceParam_Tuning         ? &self->tuning
           : id == kMusicDeviceParam_Volume       ? &self->volume_db
           : id == kMusicDeviceParam_ReverbVolume ? &self->reverb_db
                                                  : NULL;
}

static OSStatus u_get_param(void *p, AudioUnitParameterID id, AudioUnitScope scope, AudioUnitElement el,
                            AudioUnitParameterValue *value)
{
    unit *self = p;
    (void)el;
    if (!value)
        return kAudio_ParamError;
    if (scope != kAudioUnitScope_Global)
        return kAudioUnitErr_InvalidScope;
    pthread_mutex_lock(&self->lock);
    Float32 *slot = param_slot(self, id);
    if (slot)
        *value = *slot;
    pthread_mutex_unlock(&self->lock);
    return slot ? noErr : kAudioUnitErr_InvalidParameter;
}

static OSStatus u_set_param(void *p, AudioUnitParameterID id, AudioUnitScope scope, AudioUnitElement el,
                            AudioUnitParameterValue value, UInt32 offset)
{
    unit *self = p;
    (void)el;
    (void)offset;
    if (scope != kAudioUnitScope_Global)
        return kAudioUnitErr_InvalidScope;
    AudioUnitParameterInfo info;
    if (!param_info(self, id, &info))
        return kAudioUnitErr_InvalidParameter;
    if (value < info.minValue || value > info.maxValue)
        return kAudioUnitErr_InvalidParameterValue;
    pthread_mutex_lock(&self->lock);
    *param_slot(self, id) = value;
    if (self->kind == UNIT_SYNTH && id == kMusicDeviceParam_Volume)
        apply_gain(self);
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus u_reset(void *p, AudioUnitScope scope, AudioUnitElement el)
{
    unit *self = p;
    (void)scope;
    (void)el;
    pthread_mutex_lock(&self->lock);
    self->nevents = 0;
    self->gain = 1.0;
    if (self->synth && fs.all_sounds_off)
        fs.all_sounds_off(self->synth, -1);
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus u_add_listener(void *p, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc, void *ref)
{
    unit *self = p;
    if (!proc)
        return kAudio_ParamError;
    listener *l = calloc(1, sizeof *l);
    if (!l)
        return kAudio_MemFullError;
    l->id = id, l->proc = proc, l->ref = ref;
    pthread_mutex_lock(&self->lock);
    l->next = self->listeners;
    self->listeners = l;
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus remove_listeners(unit *self, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc, void *ref,
                                 int any_ref)
{
    pthread_mutex_lock(&self->lock);
    for (listener **l = &self->listeners; *l;) {
        if ((*l)->id == id && (*l)->proc == proc && (any_ref || (*l)->ref == ref)) {
            listener *gone = *l;
            *l = gone->next;
            free(gone);
        } else
            l = &(*l)->next;
    }
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus u_remove_listener(void *p, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc)
{
    return remove_listeners(p, id, proc, NULL, 1);
}

static OSStatus u_remove_listener_ref(void *p, AudioUnitPropertyID id, AudioUnitPropertyListenerProc proc, void *ref)
{
    return remove_listeners(p, id, proc, ref, 0);
}

static OSStatus u_add_notify(void *p, AURenderCallback proc, void *ref)
{
    unit *self = p;
    if (!proc)
        return kAudio_ParamError;
    notify *n = calloc(1, sizeof *n);
    if (!n)
        return kAudio_MemFullError;
    n->proc = proc, n->ref = ref;
    pthread_mutex_lock(&self->lock);
    notify **end = &self->notifies;
    while (*end)
        end = &(*end)->next;
    *end = n;
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus u_remove_notify(void *p, AURenderCallback proc, void *ref)
{
    unit *self = p;
    pthread_mutex_lock(&self->lock);
    for (notify **n = &self->notifies; *n;) {
        if ((*n)->proc == proc && (*n)->ref == ref) {
            notify *gone = *n;
            *n = gone->next;
            free(gone);
        } else
            n = &(*n)->next;
    }
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

/* plays the events due in this slice, rendering up to each in turn */
static void synth_render(unit *self, UInt32 frames, AudioBufferList *io)
{
    UInt32 at = 0;
    UInt32 kept = 0;
    for (UInt32 i = 0; i < self->nevents; i++) {
        midi_event *e = &self->events[i];
        if (e->offset >= frames) {
            e->offset -= frames;
            self->events[kept++] = *e;
            continue;
        }
        if (e->offset > at) {
            synth_render_into(self, io, at, e->offset - at);
            at = e->offset;
        }
        play_event(self, e->status, e->data1, e->data2);
    }
    self->nevents = kept;
    if (at < frames)
        synth_render_into(self, io, at, frames - at);
}

static OSStatus u_render(void *p, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 bus,
                         UInt32 frames, AudioBufferList *io)
{
    unit *self = p;
    if (!io || !t)
        return kAudio_ParamError;
    if (bus != 0)
        return kAudioUnitErr_InvalidElement;
    pthread_mutex_lock(&self->lock);
    OSStatus err = noErr;
    if (!self->initialized)
        err = kAudioUnitErr_Uninitialized;
    else if (!(err = give_buffers(self, &self->format[1], frames, io)) && !list_fits(&self->format[1], frames, io))
        err = kAudio_ParamError;
    if (err) {
        self->last_error = err;
        pthread_mutex_unlock(&self->lock);
        return err;
    }
    AudioUnitRenderActionFlags own = 0;
    if (!flags)
        flags = &own;
    call_notifies(self, kAudioUnitRenderAction_PreRender, t, bus, frames, io);
    if (self->kind == UNIT_SYNTH)
        synth_render(self, frames, io);
    else {
        /* the limiter pulls its input into the same buffers, then works in place */
        AURenderCallbackStruct input = self->input;
        AudioUnitConnection conn = self->connection;
        int connected = self->connected;
        pthread_mutex_unlock(&self->lock);
        if (connected)
            err = AudioUnitRender(conn.sourceAudioUnit, flags, t, conn.sourceOutputNumber, frames, io);
        else if (input.inputProc)
            err = input.inputProc(input.inputProcRefCon, flags, t, 0, frames, io);
        else
            err = kAudioUnitErr_NoConnection;
        pthread_mutex_lock(&self->lock);
        if (!err && !self->bypass)
            limit(self, io, frames);
    }
    call_notifies(self, kAudioUnitRenderAction_PostRender | (err ? kAudioUnitRenderAction_PostRenderError : 0), t,
                  bus, frames, io);
    self->last_error = err;
    pthread_mutex_unlock(&self->lock);
    return err;
}

static OSStatus u_process(void *p, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 frames,
                          AudioBufferList *io)
{
    unit *self = p;
    (void)flags;
    (void)t;
    if (!io)
        return kAudio_ParamError;
    pthread_mutex_lock(&self->lock);
    OSStatus err = !self->initialized ? kAudioUnitErr_Uninitialized
                   : !list_fits(&self->format[1], frames, io) ? kAudio_ParamError
                                                               : noErr;
    if (!err && !self->bypass)
        limit(self, io, frames);
    pthread_mutex_unlock(&self->lock);
    return err;
}

static OSStatus u_midi_event(void *p, UInt32 status, UInt32 d1, UInt32 d2, UInt32 offset)
{
    unit *self = p;
    pthread_mutex_lock(&self->lock);
    if (offset == 0 || self->nevents >= MAX_EVENTS)
        play_event(self, status, d1, d2);
    else
        self->events[self->nevents++] = (midi_event){offset, (UInt8)status, (UInt8)d1, (UInt8)d2};
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus u_sysex(void *p, const UInt8 *data, UInt32 length)
{
    unit *self = p;
    if (!data && length)
        return kAudio_ParamError;
    /* FluidSynth takes the message without its F0 and F7 */
    if (length && data[0] == 0xF0)
        data++, length--;
    if (length && data[length - 1] == 0xF7)
        length--;
    pthread_mutex_lock(&self->lock);
    if (self->synth && fs.sysex && length)
        fs.sysex(self->synth, (const char *)data, (int)length, NULL, NULL, NULL, 0);
    pthread_mutex_unlock(&self->lock);
    return noErr;
}

static OSStatus u_start_note(void *p, MusicDeviceInstrumentID instrument, MusicDeviceGroupID group,
                             NoteInstanceID *note, UInt32 offset, const MusicDeviceNoteParams *params)
{
    (void)instrument; /* a General MIDI synth plays each group's own program */
    if (!params)
        return kAudio_ParamError;
    UInt32 key = (UInt32)lrintf(params->mPitch) & 0x7F;
    UInt32 velocity = (UInt32)lrintf(params->mVelocity) & 0x7F;
    if (note)
        *note = key;
    return u_midi_event(p, 0x90 | (group & 0x0F), key, velocity ? velocity : 1, offset);
}

static OSStatus u_stop_note(void *p, MusicDeviceGroupID group, NoteInstanceID note, UInt32 offset)
{
    return u_midi_event(p, 0x80 | (group & 0x0F), note & 0x7F, 0, offset);
}

static OSStatus u_prepare_instrument(void *p, MusicDeviceInstrumentID instrument)
{
    (void)p;
    (void)instrument;
    return noErr;
}

static AudioComponentMethod common_lookup(SInt16 selector)
{
    switch (selector) {
    case kAudioUnitInitializeSelect: return (AudioComponentMethod)u_initialize;
    case kAudioUnitUninitializeSelect: return (AudioComponentMethod)u_uninitialize;
    case kAudioUnitGetPropertyInfoSelect: return (AudioComponentMethod)u_get_info;
    case kAudioUnitGetPropertySelect: return (AudioComponentMethod)u_get;
    case kAudioUnitSetPropertySelect: return (AudioComponentMethod)u_set;
    case kAudioUnitGetParameterSelect: return (AudioComponentMethod)u_get_param;
    case kAudioUnitSetParameterSelect: return (AudioComponentMethod)u_set_param;
    case kAudioUnitResetSelect: return (AudioComponentMethod)u_reset;
    case kAudioUnitAddPropertyListenerSelect: return (AudioComponentMethod)u_add_listener;
    case kAudioUnitRemovePropertyListenerSelect: return (AudioComponentMethod)u_remove_listener;
    case kAudioUnitRemovePropertyListenerWithUserDataSelect: return (AudioComponentMethod)u_remove_listener_ref;
    case kAudioUnitAddRenderNotifySelect: return (AudioComponentMethod)u_add_notify;
    case kAudioUnitRemoveRenderNotifySelect: return (AudioComponentMethod)u_remove_notify;
    case kAudioUnitRenderSelect: return (AudioComponentMethod)u_render;
    default: return NULL;
    }
}

static AudioComponentMethod synth_lookup(SInt16 selector)
{
    switch (selector) {
    case kMusicDeviceMIDIEventSelect: return (AudioComponentMethod)u_midi_event;
    case kMusicDeviceSysExSelect: return (AudioComponentMethod)u_sysex;
    case kMusicDeviceStartNoteSelect: return (AudioComponentMethod)u_start_note;
    case kMusicDeviceStopNoteSelect: return (AudioComponentMethod)u_stop_note;
    case kMusicDevicePrepareInstrumentSelect:
    case kMusicDeviceReleaseInstrumentSelect: return (AudioComponentMethod)u_prepare_instrument;
    default: return common_lookup(selector);
    }
}

static AudioComponentMethod limiter_lookup(SInt16 selector)
{
    return selector == kAudioUnitProcessSelect ? (AudioComponentMethod)u_process : common_lookup(selector);
}

static OSStatus u_open(void *p, AudioComponentInstance instance)
{
    ((unit *)p)->unit = instance;
    return noErr;
}

static OSStatus u_close(void *p)
{
    unit *self = p;
    if (self->kind == UNIT_SYNTH)
        free_synth(self);
    while (self->listeners) {
        listener *l = self->listeners;
        self->listeners = l->next;
        free(l);
    }
    while (self->notifies) {
        notify *n = self->notifies;
        self->notifies = n->next;
        free(n);
    }
    if (self->bank_url)
        CFRelease(self->bank_url);
    for (UInt32 i = 0; i < CA_MAX_CHANNELS; i++)
        free(self->own[i]);
    free(self->scratch);
    pthread_mutex_destroy(&self->lock);
    free(self);
    return noErr;
}

static AudioComponentPlugInInterface *new_unit(int kind)
{
    unit *self = calloc(1, sizeof *self);
    if (!self)
        return NULL;
    self->iface.Open = u_open;
    self->iface.Close = u_close;
    self->iface.Lookup = kind == UNIT_SYNTH ? synth_lookup : limiter_lookup;
    self->kind = kind;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&self->lock, &attr);
    pthread_mutexattr_destroy(&attr);
    canonical(&self->format[0], 44100, 2);
    canonical(&self->format[1], 44100, 2);
    self->max_frames = DEFAULT_MAX_FRAMES;
    self->font = -1;
    self->reverb_db = -120;
    self->attack = 0.012f;
    self->decay = 0.024f;
    self->gain = 1.0;
    return &self->iface;
}

static AudioComponentPlugInInterface *synth_factory(const AudioComponentDescription *desc)
{
    (void)desc;
    return new_unit(UNIT_SYNTH);
}

static AudioComponentPlugInInterface *limiter_factory(const AudioComponentDescription *desc)
{
    (void)desc;
    return new_unit(UNIT_LIMITER);
}

__attribute__((constructor)) static void register_units(void)
{
    AudioComponentDescription dls = {kAudioUnitType_MusicDevice, kAudioUnitSubType_DLSSynth,
                                     kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponentDescription midi = {kAudioUnitType_MusicDevice, kAudioUnitSubType_MIDISynth,
                                      kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponentDescription limiter = {kAudioUnitType_Effect, kAudioUnitSubType_PeakLimiter,
                                         kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponentRegister(&dls, CFSTR("Apple: DLSMusicDevice"), 0x10000, synth_factory);
    AudioComponentRegister(&midi, CFSTR("Apple: AUMIDISynth"), 0x10000, synth_factory);
    AudioComponentRegister(&limiter, CFSTR("Apple: AUPeakLimiter"), 0x10000, limiter_factory);
}

/* ---- the music device calls ---------------------------------------------------------------- */

#define DEVICE_CALL(u, sel, type, ...)                                                                                \
    do {                                                                                                              \
        void *self_ = NULL;                                                                                           \
        AudioComponentMethod m_ = ca_unit_method(u, sel, &self_);                                                     \
        if (!m_)                                                                                                      \
            return u ? kAudio_UnimplementedError : kAudio_ParamError;                                                 \
        return ((type)(void *)m_)(self_, ##__VA_ARGS__);                                                              \
    } while (0)

OSStatus MusicDeviceMIDIEvent(MusicDeviceComponent u, UInt32 status, UInt32 d1, UInt32 d2, UInt32 offset)
{
    DEVICE_CALL(u, kMusicDeviceMIDIEventSelect, OSStatus (*)(void *, UInt32, UInt32, UInt32, UInt32), status, d1, d2,
                offset);
}

OSStatus MusicDeviceSysEx(MusicDeviceComponent u, const UInt8 *data, UInt32 length)
{
    DEVICE_CALL(u, kMusicDeviceSysExSelect, OSStatus (*)(void *, const UInt8 *, UInt32), data, length);
}

OSStatus MusicDeviceStartNote(MusicDeviceComponent u, MusicDeviceInstrumentID instrument, MusicDeviceGroupID group,
                              NoteInstanceID *note, UInt32 offset, const MusicDeviceNoteParams *params)
{
    DEVICE_CALL(u, kMusicDeviceStartNoteSelect,
                OSStatus (*)(void *, MusicDeviceInstrumentID, MusicDeviceGroupID, NoteInstanceID *, UInt32,
                             const MusicDeviceNoteParams *),
                instrument, group, note, offset, params);
}

OSStatus MusicDeviceStopNote(MusicDeviceComponent u, MusicDeviceGroupID group, NoteInstanceID note, UInt32 offset)
{
    DEVICE_CALL(u, kMusicDeviceStopNoteSelect, OSStatus (*)(void *, MusicDeviceGroupID, NoteInstanceID, UInt32),
                group, note, offset);
}
