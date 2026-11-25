/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Audio queues (freemac 1.234, Ferry 0.58.0), written from Apple's public
 * documentation of AudioQueue.h: a program enqueues buffers of linear PCM
 * to play, or empty buffers to record into, and gets each back through its
 * callback when the queue is done with it. The callback comes on the run
 * loop the program named, on its dispatch queue, or, with neither, on the
 * queue's own thread.
 *
 * Ferry's queues take linear PCM, interleaved; compressed formats (AAC and
 * the like) are refused with kAudioFormatUnsupportedDataFormatError.
 */
#import "CAInternal.h"
#include <Block.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

/* An AudioQueueBuffer, with Ferry's own fields after it. */
typedef struct aq_buffer {
    UInt32 capacity;
    void *data;
    UInt32 size;
    void *user;
    UInt32 packet_capacity;
    AudioStreamPacketDescription *packets;
    UInt32 packet_count;
    /* Ferry's */
    AudioQueueRef queue;
    struct aq_buffer *next_all, *next_queued;
    int queued;
} aq_buffer;

typedef struct aq_listener {
    struct aq_listener *next;
    AudioQueuePropertyID id;
    AudioQueuePropertyListenerProc proc;
    void *user;
} aq_listener;

struct OpaqueAudioQueue {
    int input;
    AudioStreamBasicDescription format;
    ca_pcm pcm;
    AudioQueueOutputCallback out_proc;
    AudioQueueInputCallback in_proc;
    void *user;
    AudioQueueOutputCallbackBlock out_block;
    AudioQueueInputCallbackBlock in_block;
    dispatch_queue_t dispatch;
    CFRunLoopRef run_loop;
    CFStringRef mode;

    pthread_mutex_t lock;
    pthread_cond_t cond;
    aq_buffer *all;
    aq_buffer *head, *tail;
    int running, paused, draining, disposed, quit;
    int refs; /* the program's, the thread's, and each callback on its way */
    pthread_t thread;
    int has_thread;
    CFStringRef device_uid; /* NULL: the default device */
    AudioChannelLayout *layout;
    UInt32 layout_size;
    Float32 volume;
    UInt32 metering;
    Float32 peak[CA_MAX_CHANNELS], average[CA_MAX_CHANNELS];
    Float64 sample_time;
    aq_listener *listeners;
    int reopen;
};

static void release(AudioQueueRef q)
{
    pthread_mutex_lock(&q->lock);
    int last = --q->refs == 0;
    pthread_mutex_unlock(&q->lock);
    if (!last)
        return;
    for (aq_buffer *b = q->all; b;) {
        aq_buffer *next = b->next_all;
        free(b->data);
        free(b->packets);
        free(b);
        b = next;
    }
    while (q->listeners) {
        aq_listener *l = q->listeners;
        q->listeners = l->next;
        free(l);
    }
    if (q->out_block)
        Block_release(q->out_block);
    if (q->in_block)
        Block_release(q->in_block);
    if (q->dispatch)
        dispatch_release(q->dispatch);
    if (q->run_loop)
        CFRelease(q->run_loop);
    if (q->mode)
        CFRelease(q->mode);
    if (q->device_uid)
        CFRelease(q->device_uid);
    free(q->layout);
    pthread_mutex_destroy(&q->lock);
    pthread_cond_destroy(&q->cond);
    free(q);
}

static void tell_listeners(AudioQueueRef q, AudioQueuePropertyID id)
{
    aq_listener *ls[16];
    int n = 0;
    pthread_mutex_lock(&q->lock);
    for (aq_listener *l = q->listeners; l && n < 16; l = l->next)
        if (l->id == id)
            ls[n++] = l;
    pthread_mutex_unlock(&q->lock);
    for (int i = 0; i < n; i++)
        ls[i]->proc(ls[i]->user, q, id);
}

/* hands a buffer back to the program */
static void give_back(AudioQueueRef q, aq_buffer *b, const AudioTimeStamp *start)
{
    pthread_mutex_lock(&q->lock);
    if (q->disposed) {
        pthread_mutex_unlock(&q->lock);
        return;
    }
    q->refs++;
    pthread_mutex_unlock(&q->lock);
    AudioTimeStamp t = start ? *start : (AudioTimeStamp){0};
    void (^call)(void) = ^{
      pthread_mutex_lock(&q->lock);
      int gone = q->disposed;
      pthread_mutex_unlock(&q->lock);
      if (!gone) {
          AudioQueueBufferRef ref = (AudioQueueBufferRef)b;
          if (q->input) {
              /* linear PCM: a packet a frame, and no descriptions */
              UInt32 packets = q->pcm.bytes_per_frame ? ref->mAudioDataByteSize / q->pcm.bytes_per_frame : 0;
              if (q->in_block)
                  q->in_block(q, ref, &t, packets, NULL);
              else
                  q->in_proc(q->user, q, ref, &t, packets, NULL);
          } else if (q->out_block)
              q->out_block(q, ref);
          else
              q->out_proc(q->user, q, ref);
      }
      release(q);
    };
    if (q->dispatch)
        dispatch_async(q->dispatch, call);
    else if (q->run_loop) {
        CFRunLoopPerformBlock(q->run_loop, q->mode ? (CFTypeRef)q->mode : (CFTypeRef)kCFRunLoopCommonModes, call);
        CFRunLoopWakeUp(q->run_loop);
    } else
        call();
}

static aq_buffer *take(AudioQueueRef q)
{
    aq_buffer *b = q->head;
    if (b) {
        q->head = b->next_queued;
        if (!q->head)
            q->tail = NULL;
        b->next_queued = NULL;
        b->queued = 0;
    }
    return b;
}

static ca_device *queue_device(AudioQueueRef q)
{
    AudioObjectID id = 0;
    if (q->device_uid) {
        AudioObjectPropertyAddress a = {kAudioHardwarePropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
        UInt32 size = sizeof id;
        CFStringRef uid = q->device_uid;
        AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof uid, &uid, &size, &id);
    }
    if (!id)
        id = ca_default_device(q->input ? CA_IN : CA_OUT);
    return ca_device_for(id);
}

static ca_stream *open_stream(AudioQueueRef q)
{
    pthread_mutex_lock(&q->lock);
    ca_device *d = queue_device(q);
    UInt32 labels[CA_MAX_CHANNELS], n = 0;
    if (q->layout)
        n = ca_layout_labels(q->layout, q->layout_size, labels, CA_MAX_CHANNELS);
    if (n != q->pcm.channels)
        ca_default_labels(q->pcm.channels, labels);
    q->reopen = 0;
    pthread_mutex_unlock(&q->lock);
    int dir = q->input ? CA_IN : CA_OUT;
    if (!d || !d->alive || !d->stream[dir])
        return NULL;
    UInt32 frames = (UInt32)(q->format.mSampleRate * 0.01); /* 10 ms at a time */
    return ca_stream_open(d, dir, q->format.mSampleRate, q->pcm.channels, labels, frames < 64 ? 64 : frames);
}

static void meter(AudioQueueRef q, const float *s, UInt32 frames)
{
    if (!q->metering || !frames)
        return;
    UInt32 ch = q->pcm.channels < CA_MAX_CHANNELS ? q->pcm.channels : CA_MAX_CHANNELS;
    for (UInt32 c = 0; c < ch; c++) {
        float peak = 0;
        double sum = 0;
        for (UInt32 i = 0; i < frames; i++) {
            float v = fabsf(s[(size_t)i * q->pcm.channels + c]);
            if (v > peak)
                peak = v;
            sum += (double)v * v;
        }
        q->peak[c] = peak;
        q->average[c] = (Float32)sqrt(sum / frames);
    }
}

static void *queue_thread(void *arg)
{
    AudioQueueRef q = arg;
    ca_stream *s = NULL;
    UInt32 chunk = (UInt32)(q->format.mSampleRate * 0.01);
    if (chunk < 64)
        chunk = 64;
    float *f = calloc((size_t)chunk * q->pcm.channels, sizeof(float));
    pthread_mutex_lock(&q->lock);
    for (;;) {
        if (s && (!q->running || q->reopen)) {
            /* stopped, or moving to another device */
            pthread_mutex_unlock(&q->lock);
            ca_stream_close(s, 0);
            s = NULL;
            pthread_mutex_lock(&q->lock);
            continue;
        }
        while (!q->quit && (!q->running || q->paused || (!q->input && !q->head && !q->draining)))
            pthread_cond_wait(&q->cond, &q->lock);
        if (q->quit)
            break;
        if (!q->input && !q->head) {
            /* stopping once played out */
            q->draining = 0;
            q->running = 0;
            pthread_mutex_unlock(&q->lock);
            ca_stream_close(s, 1);
            s = NULL;
            tell_listeners(q, kAudioQueueProperty_IsRunning);
            pthread_mutex_lock(&q->lock);
            continue;
        }
        if (!s) {
            pthread_mutex_unlock(&q->lock);
            ca_stream_close(s, 0);
            s = open_stream(q);
            pthread_mutex_lock(&q->lock);
            if (!s) {
                /* no device: wait for one */
                struct timespec t;
                clock_gettime(CLOCK_REALTIME, &t);
                t.tv_nsec += 200000000;
                if (t.tv_nsec >= 1000000000) {
                    t.tv_sec++;
                    t.tv_nsec -= 1000000000;
                }
                pthread_cond_timedwait(&q->cond, &q->lock, &t);
                continue;
            }
        }
        aq_buffer *b = q->head; /* stays queued while it plays or records */
        UInt32 bpf = q->pcm.bytes_per_frame;
        if (q->input) {
            UInt32 frames = b ? b->capacity / bpf : chunk;
            UInt32 done = 0;
            AudioTimeStamp start;
            memset(&start, 0, sizeof start);
            start.mSampleTime = q->sample_time;
            start.mHostTime = ca_now();
            start.mRateScalar = 1;
            start.mFlags = kAudioTimeStampSampleHostTimeValid | kAudioTimeStampRateScalarValid;
            int failed = 0;
            while (done < frames) {
                UInt32 n = frames - done < chunk ? frames - done : chunk;
                pthread_mutex_unlock(&q->lock);
                failed = ca_stream_read(s, f, n) < 0;
                pthread_mutex_lock(&q->lock);
                if (failed || q->quit || !q->running || q->paused || (b && b != q->head))
                    break;
                meter(q, f, n);
                if (b)
                    ca_bytes_from_float(&q->pcm, f, n, (unsigned char *)b->data + (size_t)done * bpf);
                done += n;
                q->sample_time += n;
            }
            if (failed)
                q->reopen = 1;
            if (b && b == q->head && done) {
                take(q);
                b->size = done * bpf;
                pthread_mutex_unlock(&q->lock);
                give_back(q, b, &start);
                pthread_mutex_lock(&q->lock);
            }
            continue;
        }
        UInt32 frames = b->size / bpf, done = 0;
        int failed = 0;
        while (done < frames) {
            UInt32 n = frames - done < chunk ? frames - done : chunk;
            ca_bytes_to_float(&q->pcm, (unsigned char *)b->data + (size_t)done * bpf, n, f);
            Float32 v = q->volume;
            if (v != 1.0f)
                for (UInt32 i = 0; i < n * q->pcm.channels; i++)
                    f[i] *= v;
            meter(q, f, n);
            pthread_mutex_unlock(&q->lock);
            failed = ca_stream_write(s, f, n) < 0;
            pthread_mutex_lock(&q->lock);
            if (failed || q->quit || !q->running || b != q->head)
                break;
            done += n;
            q->sample_time += n;
        }
        if (failed) {
            q->reopen = 1;
            continue;
        }
        if (b == q->head && done == frames && q->running) {
            take(q);
            pthread_mutex_unlock(&q->lock);
            give_back(q, b, NULL);
            pthread_mutex_lock(&q->lock);
        }
    }
    pthread_mutex_unlock(&q->lock);
    ca_stream_close(s, 0);
    free(f);
    release(q);
    return NULL;
}

static OSStatus new_queue(int input, const AudioStreamBasicDescription *format, AudioQueueRef *out)
{
    if (!format || !out)
        return kAudio_ParamError;
    *out = NULL;
    ca_pcm p;
    if (format->mFormatID != kAudioFormatLinearPCM)
        return kAudioFormatUnsupportedDataFormatError;
    if (ca_pcm_parse(format, &p) || p.non_interleaved || format->mSampleRate <= 0 || format->mSampleRate > 384000)
        return kAudioFormatUnsupportedDataFormatError;
    ca_init();
    AudioQueueRef q = calloc(1, sizeof *q);
    if (!q)
        return kAudio_MemFullError;
    q->input = input;
    q->format = *format;
    q->pcm = p;
    q->volume = 1.0f;
    q->refs = 1;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&q->lock, &attr);
    pthread_mutexattr_destroy(&attr);
    pthread_cond_init(&q->cond, NULL);
    *out = q;
    return noErr;
}

static OSStatus start_thread(AudioQueueRef q)
{
    q->refs++;
    if (pthread_create(&q->thread, NULL, queue_thread, q)) {
        q->refs--;
        return kAudioQueueErr_CannotStart;
    }
    q->has_thread = 1;
    return noErr;
}

static OSStatus finish_new(AudioQueueRef q, CFRunLoopRef rl, CFStringRef mode, AudioQueueRef *out)
{
    if (rl) {
        q->run_loop = (CFRunLoopRef)CFRetain(rl);
        if (mode)
            q->mode = CFRetain(mode);
    }
    pthread_mutex_lock(&q->lock);
    OSStatus err = start_thread(q);
    pthread_mutex_unlock(&q->lock);
    if (err) {
        release(q);
        *out = NULL;
    }
    return err;
}

OSStatus AudioQueueNewOutput(const AudioStreamBasicDescription *format, AudioQueueOutputCallback proc, void *user,
                             CFRunLoopRef rl, CFStringRef mode, UInt32 flags, AudioQueueRef *out)
{
    if (!proc)
        return kAudio_ParamError;
    OSStatus err = new_queue(0, format, out);
    if (err)
        return err;
    (*out)->out_proc = proc;
    (*out)->user = user;
    return finish_new(*out, rl, mode, out);
}

OSStatus AudioQueueNewInput(const AudioStreamBasicDescription *format, AudioQueueInputCallback proc, void *user,
                            CFRunLoopRef rl, CFStringRef mode, UInt32 flags, AudioQueueRef *out)
{
    if (!proc)
        return kAudio_ParamError;
    OSStatus err = new_queue(1, format, out);
    if (err)
        return err;
    (*out)->in_proc = proc;
    (*out)->user = user;
    return finish_new(*out, rl, mode, out);
}

static void set_dispatch(AudioQueueRef q, dispatch_queue_t dq)
{
    if (!dq)
        dq = dispatch_get_global_queue(0, 0);
    dispatch_retain(dq);
    q->dispatch = dq;
}

OSStatus AudioQueueNewOutputWithDispatchQueue(AudioQueueRef *out, const AudioStreamBasicDescription *format,
                                              UInt32 flags, dispatch_queue_t dq, AudioQueueOutputCallbackBlock block)
{
    if (!block)
        return kAudio_ParamError;
    OSStatus err = new_queue(0, format, out);
    if (err)
        return err;
    (*out)->out_block = Block_copy(block);
    set_dispatch(*out, dq);
    return finish_new(*out, NULL, NULL, out);
}

OSStatus AudioQueueNewInputWithDispatchQueue(AudioQueueRef *out, const AudioStreamBasicDescription *format,
                                             UInt32 flags, dispatch_queue_t dq, AudioQueueInputCallbackBlock block)
{
    if (!block)
        return kAudio_ParamError;
    OSStatus err = new_queue(1, format, out);
    if (err)
        return err;
    (*out)->in_block = Block_copy(block);
    set_dispatch(*out, dq);
    return finish_new(*out, NULL, NULL, out);
}

OSStatus AudioQueueDispose(AudioQueueRef q, Boolean immediate)
{
    if (!q)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    if (q->disposed) {
        pthread_mutex_unlock(&q->lock);
        return kAudioQueueErr_DisposalPending;
    }
    int was_running = q->running;
    q->disposed = 1;
    q->quit = 1;
    q->running = 0;
    pthread_cond_broadcast(&q->cond);
    pthread_t t = q->thread;
    int join = q->has_thread && !pthread_equal(t, pthread_self());
    pthread_mutex_unlock(&q->lock);
    if (join)
        pthread_join(t, NULL);
    else if (q->has_thread)
        pthread_detach(t);
    if (was_running)
        tell_listeners(q, kAudioQueueProperty_IsRunning);
    release(q);
    return noErr;
}

OSStatus AudioQueueAllocateBufferWithPacketDescriptions(AudioQueueRef q, UInt32 bytes, UInt32 packets,
                                                        AudioQueueBufferRef *out)
{
    if (!q || !out || !bytes)
        return kAudio_ParamError;
    aq_buffer *b = calloc(1, sizeof *b);
    if (!b)
        return kAudio_MemFullError;
    b->capacity = bytes;
    b->data = calloc(1, bytes);
    b->packet_capacity = packets;
    b->packets = packets ? calloc(packets, sizeof *b->packets) : NULL;
    if (!b->data || (packets && !b->packets)) {
        free(b->data);
        free(b->packets);
        free(b);
        return kAudio_MemFullError;
    }
    b->queue = q;
    pthread_mutex_lock(&q->lock);
    b->next_all = q->all;
    q->all = b;
    pthread_mutex_unlock(&q->lock);
    *out = (AudioQueueBufferRef)b;
    return noErr;
}

OSStatus AudioQueueAllocateBuffer(AudioQueueRef q, UInt32 bytes, AudioQueueBufferRef *out)
{
    return AudioQueueAllocateBufferWithPacketDescriptions(q, bytes, 0, out);
}

static aq_buffer *buffer_of(AudioQueueRef q, AudioQueueBufferRef ref)
{
    for (aq_buffer *b = q->all; b; b = b->next_all)
        if ((AudioQueueBufferRef)b == ref)
            return b;
    return NULL;
}

OSStatus AudioQueueFreeBuffer(AudioQueueRef q, AudioQueueBufferRef ref)
{
    if (!q || !ref)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    aq_buffer *b = buffer_of(q, ref);
    if (!b) {
        pthread_mutex_unlock(&q->lock);
        return kAudioQueueErr_InvalidBuffer;
    }
    if (b->queued) {
        pthread_mutex_unlock(&q->lock);
        return kAudioQueueErr_BufferInQueue;
    }
    for (aq_buffer **p = &q->all; *p; p = &(*p)->next_all)
        if (*p == b) {
            *p = b->next_all;
            break;
        }
    pthread_mutex_unlock(&q->lock);
    free(b->data);
    free(b->packets);
    free(b);
    return noErr;
}

OSStatus AudioQueueEnqueueBuffer(AudioQueueRef q, AudioQueueBufferRef ref, UInt32 npackets,
                                 const AudioStreamPacketDescription *packets)
{
    if (!q || !ref)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    aq_buffer *b = buffer_of(q, ref);
    OSStatus err = noErr;
    if (q->disposed)
        err = kAudioQueueErr_DisposalPending;
    else if (!b)
        err = kAudioQueueErr_InvalidBuffer;
    else if (b->queued)
        err = kAudioQueueErr_BufferEnqueuedTwice;
    else if (!q->input && (b->size > b->capacity || b->size % q->pcm.bytes_per_frame))
        err = kAudioQueueErr_InvalidBuffer;
    else if (!q->input && !b->size)
        err = kAudioQueueErr_BufferEmpty;
    else {
        b->queued = 1;
        b->next_queued = NULL;
        if (q->tail)
            q->tail->next_queued = b;
        else
            q->head = b;
        q->tail = b;
        pthread_cond_broadcast(&q->cond);
    }
    pthread_mutex_unlock(&q->lock);
    return err;
}

OSStatus AudioQueueEnqueueBufferWithParameters(AudioQueueRef q, AudioQueueBufferRef ref, UInt32 npackets,
                                               const AudioStreamPacketDescription *packets, UInt32 trim_start,
                                               UInt32 trim_end, UInt32 nparams,
                                               const AudioQueueParameterEvent *params, const AudioTimeStamp *start,
                                               AudioTimeStamp *actual)
{
    for (UInt32 i = 0; params && i < nparams; i++)
        AudioQueueSetParameter(q, params[i].mID, params[i].mValue);
    if (q && ref && !q->input && (trim_start || trim_end)) {
        UInt32 bpf = q->pcm.bytes_per_frame, frames = ref->mAudioDataByteSize / bpf;
        if (trim_start + trim_end >= frames)
            return kAudio_ParamError;
        memmove(ref->mAudioData, (unsigned char *)ref->mAudioData + (size_t)trim_start * bpf,
                (size_t)(frames - trim_start - trim_end) * bpf);
        ref->mAudioDataByteSize = (frames - trim_start - trim_end) * bpf;
    }
    OSStatus err = AudioQueueEnqueueBuffer(q, ref, npackets, packets);
    if (!err && actual) {
        memset(actual, 0, sizeof *actual);
        actual->mSampleTime = q->sample_time;
        actual->mFlags = kAudioTimeStampSampleTimeValid;
    }
    return err;
}

OSStatus AudioQueueStart(AudioQueueRef q, const AudioTimeStamp *when)
{
    if (!q)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    if (q->disposed) {
        pthread_mutex_unlock(&q->lock);
        return kAudioQueueErr_DisposalPending;
    }
    int was = q->running && !q->paused;
    q->running = 1;
    q->paused = 0;
    q->draining = 0;
    pthread_cond_broadcast(&q->cond);
    pthread_mutex_unlock(&q->lock);
    if (!was)
        tell_listeners(q, kAudioQueueProperty_IsRunning);
    return noErr;
}

OSStatus AudioQueuePrime(AudioQueueRef q, UInt32 frames, UInt32 *prepared)
{
    if (!q)
        return kAudio_ParamError;
    if (prepared) {
        UInt32 n = 0;
        pthread_mutex_lock(&q->lock);
        for (aq_buffer *b = q->head; b; b = b->next_queued)
            n += b->size / q->pcm.bytes_per_frame;
        pthread_mutex_unlock(&q->lock);
        *prepared = frames && n > frames ? frames : n;
    }
    return noErr;
}

/* removes the queued buffers; an output queue's are given back unplayed */
static void unqueue_all(AudioQueueRef q)
{
    pthread_mutex_lock(&q->lock);
    while (take(q))
        ;
    pthread_mutex_unlock(&q->lock);
}

OSStatus AudioQueueStop(AudioQueueRef q, Boolean immediate)
{
    if (!q)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    if (!q->running) {
        pthread_mutex_unlock(&q->lock);
        return noErr;
    }
    if (!immediate && !q->input) {
        /* plays what is queued, then stops */
        q->draining = 1;
        q->paused = 0;
        pthread_cond_broadcast(&q->cond);
        pthread_mutex_unlock(&q->lock);
        return noErr;
    }
    q->running = 0;
    q->paused = 0;
    q->draining = 0;
    q->reopen = 1; /* the stream closes; the next start opens a new one */
    pthread_cond_broadcast(&q->cond);
    pthread_mutex_unlock(&q->lock);
    unqueue_all(q);
    tell_listeners(q, kAudioQueueProperty_IsRunning);
    return noErr;
}

OSStatus AudioQueuePause(AudioQueueRef q)
{
    if (!q)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    q->paused = 1;
    pthread_cond_broadcast(&q->cond);
    pthread_mutex_unlock(&q->lock);
    return noErr;
}

OSStatus AudioQueueFlush(AudioQueueRef q)
{
    return q ? noErr : kAudio_ParamError;
}

OSStatus AudioQueueReset(AudioQueueRef q)
{
    if (!q)
        return kAudio_ParamError;
    unqueue_all(q);
    pthread_mutex_lock(&q->lock);
    q->sample_time = 0;
    pthread_mutex_unlock(&q->lock);
    return noErr;
}

static void now_time(AudioQueueRef q, AudioTimeStamp *t)
{
    memset(t, 0, sizeof *t);
    pthread_mutex_lock(&q->lock);
    t->mSampleTime = q->sample_time;
    pthread_mutex_unlock(&q->lock);
    t->mHostTime = ca_now();
    t->mRateScalar = 1;
    t->mFlags = kAudioTimeStampSampleHostTimeValid | kAudioTimeStampRateScalarValid;
}

OSStatus AudioQueueGetCurrentTime(AudioQueueRef q, AudioQueueTimelineRef timeline, AudioTimeStamp *out,
                                  Boolean *discontinuity)
{
    if (!q)
        return kAudio_ParamError;
    if (out)
        now_time(q, out);
    if (discontinuity)
        *discontinuity = 0;
    return noErr;
}

OSStatus AudioQueueDeviceGetCurrentTime(AudioQueueRef q, AudioTimeStamp *out)
{
    if (!q || !out)
        return kAudio_ParamError;
    now_time(q, out);
    out->mFlags = kAudioTimeStampSampleHostTimeValid;
    return noErr;
}

OSStatus AudioQueueCreateTimeline(AudioQueueRef q, AudioQueueTimelineRef *out)
{
    if (!q || !out)
        return kAudio_ParamError;
    *out = (AudioQueueTimelineRef)(void *)q;
    return noErr;
}

OSStatus AudioQueueDisposeTimeline(AudioQueueRef q, AudioQueueTimelineRef timeline)
{
    return q ? noErr : kAudio_ParamError;
}

OSStatus AudioQueueGetParameter(AudioQueueRef q, AudioQueueParameterID id, AudioQueueParameterValue *out)
{
    if (!q || !out)
        return kAudio_ParamError;
    switch (id) {
    case kAudioQueueParam_Volume: *out = q->volume; return noErr;
    case kAudioQueueParam_PlayRate:
    case kAudioQueueParam_Pitch:
    case kAudioQueueParam_VolumeRampTime:
    case kAudioQueueParam_Pan: *out = id == kAudioQueueParam_PlayRate ? 1.0f : 0.0f; return noErr;
    default: return kAudioQueueErr_InvalidParameter;
    }
}

OSStatus AudioQueueSetParameter(AudioQueueRef q, AudioQueueParameterID id, AudioQueueParameterValue value)
{
    if (!q)
        return kAudio_ParamError;
    switch (id) {
    case kAudioQueueParam_Volume:
        if (!(value >= 0.0f))
            value = 0.0f;
        if (value > 1.0f)
            value = 1.0f;
        pthread_mutex_lock(&q->lock);
        q->volume = value;
        pthread_mutex_unlock(&q->lock);
        return noErr;
    case kAudioQueueParam_PlayRate:
    case kAudioQueueParam_Pitch:
    case kAudioQueueParam_VolumeRampTime:
    case kAudioQueueParam_Pan: return noErr; /* taken, not applied */
    default: return kAudioQueueErr_InvalidParameter;
    }
}

/* ---- properties ---------------------------------------------------------------------------- */

static OSStatus queue_property(AudioQueueRef q, AudioQueuePropertyID id, void *data, UInt32 *size, int sizing)
{
    UInt32 need;
    unsigned char tmp[sizeof(AudioQueueLevelMeterState) * CA_MAX_CHANNELS];
    const void *from = tmp;
    void *heap = NULL;
    pthread_mutex_lock(&q->lock);
    switch (id) {
    case kAudioQueueProperty_IsRunning:
        need = 4;
        *(UInt32 *)tmp = (UInt32)(q->running && !q->paused);
        break;
    case kAudioQueueProperty_StreamDescription:
        need = sizeof q->format;
        from = &q->format;
        break;
    case kAudioQueueDeviceProperty_SampleRate:
    case kAudioQueueDeviceProperty_NumberChannels: {
        ca_device *d = queue_device(q);
        int dir = q->input ? CA_IN : CA_OUT;
        if (id == kAudioQueueDeviceProperty_SampleRate) {
            need = sizeof(Float64);
            *(Float64 *)tmp = d ? d->rate : q->format.mSampleRate;
        } else {
            need = 4;
            *(UInt32 *)tmp = d ? d->channels[dir] : q->pcm.channels;
        }
        break;
    }
    case kAudioQueueProperty_CurrentDevice:
        need = sizeof(CFStringRef);
        *(CFStringRef *)tmp = sizing || !q->device_uid ? NULL : CFRetain(q->device_uid);
        break;
    case kAudioQueueProperty_ChannelLayout:
        if (!q->layout) {
            UInt32 labels[CA_MAX_CHANNELS];
            ca_default_labels(q->pcm.channels, labels);
            heap = ca_layout_with_labels(labels, q->pcm.channels, &need);
            from = heap;
        } else {
            need = q->layout_size;
            from = q->layout;
        }
        break;
    case kAudioQueueProperty_EnableLevelMetering:
        need = 4;
        *(UInt32 *)tmp = q->metering;
        break;
    case kAudioQueueProperty_CurrentLevelMeter:
    case kAudioQueueProperty_CurrentLevelMeterDB: {
        UInt32 ch = q->pcm.channels < CA_MAX_CHANNELS ? q->pcm.channels : CA_MAX_CHANNELS;
        AudioQueueLevelMeterState *m = (AudioQueueLevelMeterState *)tmp;
        for (UInt32 c = 0; c < ch; c++) {
            Float32 a = q->average[c], p = q->peak[c];
            if (id == kAudioQueueProperty_CurrentLevelMeterDB) {
                a = a > 0 ? 20.0f * log10f(a) : -120.0f;
                p = p > 0 ? 20.0f * log10f(p) : -120.0f;
            }
            m[c].mAveragePower = a;
            m[c].mPeakPower = p;
        }
        need = ch * sizeof *m;
        if (!sizing && data && *size < need)
            need = *size / sizeof *m * sizeof *m;
        break;
    }
    case kAudioQueueProperty_MagicCookie: need = 0; break;
    case kAudioQueueProperty_MaximumOutputPacketSize:
        need = 4;
        *(UInt32 *)tmp = q->pcm.bytes_per_frame;
        break;
    case kAudioQueueProperty_DecodeBufferSizeFrames:
        need = 4;
        *(UInt32 *)tmp = 0;
        break;
    case kAudioQueueProperty_ConverterError:
        need = 4;
        *(UInt32 *)tmp = 0;
        break;
    default: pthread_mutex_unlock(&q->lock); return kAudioQueueErr_InvalidProperty;
    }
    pthread_mutex_unlock(&q->lock);
    OSStatus err = noErr;
    if (!sizing) {
        if (*size < need)
            err = kAudioQueueErr_InvalidPropertySize;
        else
            memcpy(data, from, need);
    }
    if (!err)
        *size = need;
    free(heap);
    return err;
}

OSStatus AudioQueueGetProperty(AudioQueueRef q, AudioQueuePropertyID id, void *data, UInt32 *size)
{
    if (!q || !size || !data)
        return kAudio_ParamError;
    return queue_property(q, id, data, size, 0);
}

OSStatus AudioQueueGetPropertySize(AudioQueueRef q, AudioQueuePropertyID id, UInt32 *size)
{
    if (!q || !size)
        return kAudio_ParamError;
    return queue_property(q, id, NULL, size, 1);
}

OSStatus AudioQueueSetProperty(AudioQueueRef q, AudioQueuePropertyID id, const void *data, UInt32 size)
{
    if (!q)
        return kAudio_ParamError;
    OSStatus err = noErr;
    pthread_mutex_lock(&q->lock);
    switch (id) {
    case kAudioQueueProperty_CurrentDevice: {
        if (size < sizeof(CFStringRef) || !data) {
            err = kAudioQueueErr_InvalidPropertySize;
            break;
        }
        CFStringRef uid = *(CFStringRef const *)data;
        if (uid) {
            AudioObjectPropertyAddress a = {kAudioHardwarePropertyTranslateUIDToDevice,
                                            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
            AudioObjectID dev = 0;
            UInt32 n = sizeof dev;
            AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof uid, &uid, &n, &dev);
            ca_device *d = ca_device_for(dev);
            if (!d || !d->stream[q->input ? CA_IN : CA_OUT]) {
                err = kAudioQueueErr_InvalidDevice;
                break;
            }
        }
        if (q->device_uid)
            CFRelease(q->device_uid);
        q->device_uid = uid ? CFRetain(uid) : NULL;
        q->reopen = 1;
        break;
    }
    case kAudioQueueProperty_ChannelLayout:
        if (size < offsetof(AudioChannelLayout, mChannelDescriptions) || !data) {
            err = kAudioQueueErr_InvalidPropertySize;
            break;
        }
        free(q->layout);
        q->layout = malloc(size);
        memcpy(q->layout, data, size);
        q->layout_size = size;
        q->reopen = 1;
        break;
    case kAudioQueueProperty_EnableLevelMetering:
        if (size < 4 || !data) {
            err = kAudioQueueErr_InvalidPropertySize;
            break;
        }
        q->metering = *(const UInt32 *)data;
        break;
    case kAudioQueueProperty_MagicCookie:
    case kAudioQueueProperty_DecodeBufferSizeFrames:
    case kAudioQueueProperty_EnableTimePitch:
    case kAudioQueueProperty_TimePitchAlgorithm:
    case kAudioQueueProperty_TimePitchBypass: break; /* taken, not used */
    default: err = kAudioQueueErr_InvalidProperty;
    }
    pthread_cond_broadcast(&q->cond);
    pthread_mutex_unlock(&q->lock);
    return err;
}

OSStatus AudioQueueAddPropertyListener(AudioQueueRef q, AudioQueuePropertyID id, AudioQueuePropertyListenerProc proc,
                                       void *user)
{
    if (!q || !proc)
        return kAudio_ParamError;
    if (id != kAudioQueueProperty_IsRunning && id != kAudioQueueProperty_CurrentDevice)
        return kAudioQueueErr_InvalidProperty;
    aq_listener *l = calloc(1, sizeof *l);
    if (!l)
        return kAudio_MemFullError;
    l->id = id;
    l->proc = proc;
    l->user = user;
    pthread_mutex_lock(&q->lock);
    l->next = q->listeners;
    q->listeners = l;
    pthread_mutex_unlock(&q->lock);
    return noErr;
}

OSStatus AudioQueueRemovePropertyListener(AudioQueueRef q, AudioQueuePropertyID id,
                                          AudioQueuePropertyListenerProc proc, void *user)
{
    if (!q)
        return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    for (aq_listener **p = &q->listeners; *p; p = &(*p)->next)
        if ((*p)->id == id && (*p)->proc == proc && (*p)->user == user) {
            /* a call to it may be on its way, so it's kept */
            *p = (*p)->next;
            break;
        }
    pthread_mutex_unlock(&q->lock);
    return noErr;
}
