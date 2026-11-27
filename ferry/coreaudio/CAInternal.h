/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Ferry's Core Audio (freemac 1.234, Ferry 0.58.0): one Mac library,
 * CoreAudio.framework, that also serves AudioToolbox and AudioUnit. Written
 * from Apple's public documentation.
 *
 *   CABackend.m   the devices and their streams: this system's sound
 *                 server through libpulse (sinks are output devices,
 *                 sources input devices), or a null device
 *   CAHardware.m  the HAL: AudioObject properties and listeners, IO procs,
 *                 host time and the older hardware calls
 *   CAAudioUnit.m audio components and the output units (HAL output,
 *                 default and system output, generic output)
 *   CAAudioQueue.m audio queues for output and input
 *   CAMusicDevice.m the DLS and MIDI synth units, played with this system's
 *                 FluidSynth, and the peak limiter (freemac 1.NEXT)
 *   CAGraph.m     audio unit graphs (freemac 1.NEXT)
 *   CAFormat.m    linear PCM conversion, channel layouts and Audio Format
 *                 Services
 *
 * Samples move between the program and the server as 32-bit floats,
 * interleaved, at the rate and channel count the program asked for: the
 * sound server converts them to its device's own.
 */
#ifndef FERRY_COREAUDIO_INTERNAL_H
#define FERRY_COREAUDIO_INTERNAL_H
#include <AudioToolbox/AudioToolbox.h>
#include <pthread.h>

enum { CA_OUT = 0, CA_IN = 1 };
enum { CA_MAX_CHANNELS = 32 };

typedef struct ca_ioproc ca_ioproc;

typedef struct ca_device {
    AudioObjectID id;
    AudioObjectID stream[2];       /* each direction's stream, 0 without one */
    UInt32 channels[2];
    UInt32 labels[2][CA_MAX_CHANNELS]; /* each channel's AudioChannelLabel */
    Float64 rate;                  /* the nominal sample rate */
    UInt32 buffer_frames;
    UInt32 latency[2];             /* in frames */
    UInt32 transport;
    UInt32 terminal[2];
    Float32 volume[2];
    UInt32 mute[2];
    int alive;
    int listed;                    /* in kAudioHardwarePropertyDevices */
    int monitor;                   /* a sink's monitor: an input that hears an output */
    int running;                   /* streams and IO threads using it */
    SInt32 hog;
    char uid[256], name[256], manufacturer[128];
    char server_name[2][256];      /* the sink's and the source's names on the server */
    ca_ioproc *procs;
    pthread_t io_thread;
    int io_started, io_stop, io_bare;
    Float64 io_sample_time;
} ca_device;

/* ---- CABackend.m ---- */
void ca_init(void);
int ca_backend_is_null(void);
pthread_mutex_t *ca_lock(void);           /* recursive: the device table */
ca_device *ca_device_for(AudioObjectID id);  /* a device, alive or dead */
ca_device *ca_device_for_stream(AudioObjectID id, int *direction);
UInt32 ca_device_list(AudioObjectID *ids, UInt32 max);
AudioObjectID ca_default_device(int direction);
OSStatus ca_set_default_device(int direction, AudioObjectID id);
OSStatus ca_set_device_level(AudioObjectID id, int direction, int mute, Float32 value);
void ca_watch_server(void);                 /* hear the server's changes from now on */
void ca_device_running(ca_device *d, int delta);

typedef struct ca_stream ca_stream;
/* labels: the stream's channels' AudioChannelLabels, or NULL for the
 * server's own order for that many channels */
ca_stream *ca_stream_open(ca_device *d, int direction, Float64 rate, UInt32 channels, const UInt32 *labels,
                          UInt32 frames_per_buffer);
int ca_stream_write(ca_stream *s, const float *samples, UInt32 frames);
int ca_stream_read(ca_stream *s, float *samples, UInt32 frames);
UInt64 ca_stream_latency_ns(ca_stream *s);
void ca_stream_close(ca_stream *s, int drain);
const char *ca_program_name(void);

/* ---- CAHardware.m ---- */
/* listeners of an object's properties hear these addresses, on the HAL's
 * own notification queue */
void ca_notify(AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress *addresses);
void ca_notify1(AudioObjectID object, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope);
UInt64 ca_now(void);
void ca_sleep_ns(UInt64 ns);

/* ---- CAFormat.m ---- */
typedef struct ca_pcm {
    int is_float, is_signed, big_endian, non_interleaved, aligned_high;
    UInt32 bits, container; /* bits of each sample, bytes holding it */
    UInt32 channels;
    UInt32 bytes_per_frame;  /* of one buffer: all channels, or one when non-interleaved */
} ca_pcm;
/* 0 for linear PCM Ferry can convert */
int ca_pcm_parse(const AudioStreamBasicDescription *f, ca_pcm *out);
/* a float stream format: 32-bit, packed, interleaved or not */
void ca_float_format(AudioStreamBasicDescription *f, Float64 rate, UInt32 channels, int non_interleaved);
/* samples of one buffer list, or of one buffer when bytes is given, to and
 * from interleaved floats */
void ca_pcm_to_float(const ca_pcm *p, const AudioBufferList *list, UInt32 frames, float *out);
void ca_pcm_from_float(const ca_pcm *p, const float *in, UInt32 frames, AudioBufferList *list);
void ca_bytes_to_float(const ca_pcm *p, const void *bytes, UInt32 frames, float *out);
void ca_bytes_from_float(const ca_pcm *p, const float *in, UInt32 frames, void *bytes);
/* the labels Core Audio gives a device of n channels, in the server's order */
void ca_default_labels(UInt32 n, UInt32 *labels);
/* a channel layout's labels, up to max; 0 when it has none Ferry knows */
UInt32 ca_layout_labels(const AudioChannelLayout *layout, UInt32 size, UInt32 *labels, UInt32 max);
/* a layout of channel descriptions, which the caller frees */
AudioChannelLayout *ca_layout_with_labels(const UInt32 *labels, UInt32 n, UInt32 *size);
const char *ca_label_name(UInt32 label);

/* ---- CAAudioUnit.m, for CAMusicDevice.m and CAGraph.m (freemac 1.NEXT) ---- */
AudioComponentMethod ca_unit_method(AudioUnit u, SInt16 selector, void **plugin);

#endif
