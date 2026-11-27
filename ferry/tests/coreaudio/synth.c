/* SPDX-License-Identifier: GPL-3.0-or-later
 * MIDI synthesis (freemac 1.NEXT): the graph VLC's MIDI decoder
 * (audiotoolbox_midi) builds, a DLS synth through a peak limiter into a
 * generic output unit, pulled with AudioUnitRender in VLC's own format;
 * a note played into it, heard and then let go; MusicDeviceStartNote and
 * StopNote on a MIDI synth; a sound bank that isn't there; and a peak
 * limiter on its own, holding a sine four times full scale under it. Run
 * with this system's FluidSynth and a General MIDI SoundFont (synth.out),
 * and as if FluidSynth weren't installed (synth_missing.out), where the
 * synth opens but doesn't initialize. */
#include <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_name(OSType type, OSType subtype)
{
    AudioComponentDescription d = {type, subtype, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent c = AudioComponentFindNext(NULL, &d);
    CFStringRef name = NULL;
    char buf[128] = "none";
    if (c && !AudioComponentCopyName(c, &name) && name) {
        CFStringGetCString(name, buf, sizeof buf, kCFStringEncodingUTF8);
        CFRelease(name);
    }
    printf("component: %s\n", buf);
}

static AudioStreamBasicDescription vlc_format(void)
{
    AudioStreamBasicDescription f = {0};
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    f.mSampleRate = 44100;
    f.mFramesPerPacket = 1;
    f.mChannelsPerFrame = 2;
    f.mBytesPerFrame = f.mBytesPerPacket = 8;
    f.mBitsPerChannel = 32;
    return f;
}

/* renders seconds of sound from the output unit, as VLC does, and gives its RMS and peak */
static OSStatus pull(AudioUnit out, double *sample, double seconds, double *rms, double *peak)
{
    UInt32 total = (UInt32)(seconds * 44100), done = 0;
    float buf[1024 * 2];
    double sum = 0;
    *peak = 0;
    while (done < total) {
        UInt32 n = total - done < 1024 ? total - done : 1024;
        AudioBufferList l = {1, {{2, n * 8, buf}}};
        AudioTimeStamp t = {0};
        t.mFlags = kAudioTimeStampSampleTimeValid;
        t.mSampleTime = *sample;
        OSStatus err = AudioUnitRender(out, NULL, &t, 0, n, &l);
        if (err)
            return err;
        for (UInt32 i = 0; i < 2 * n; i++) {
            sum += (double)buf[i] * buf[i];
            *peak = fmax(*peak, fabs(buf[i]));
        }
        done += n;
        *sample += n;
    }
    *rms = sqrt(sum / (2.0 * total));
    return noErr;
}

static void vlc_graph(void)
{
    AUGraph g = NULL;
    AUNode synth_node, limiter_node, out_node;
    AudioComponentDescription synth = {kAudioUnitType_MusicDevice, kAudioUnitSubType_DLSSynth,
                                       kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponentDescription limiter = {kAudioUnitType_Effect, kAudioUnitSubType_PeakLimiter,
                                         kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponentDescription output = {kAudioUnitType_Output, kAudioUnitSubType_GenericOutput,
                                        kAudioUnitManufacturer_Apple, 0, 0};
    printf("new graph: %d\n", (int)NewAUGraph(&g));
    printf("nodes: %d %d %d\n", (int)AUGraphAddNode(g, &synth, &synth_node),
           (int)AUGraphAddNode(g, &limiter, &limiter_node), (int)AUGraphAddNode(g, &output, &out_node));
    AUNode second;
    printf("second output node: %d\n", (int)AUGraphAddNode(g, &output, &second));
    AudioUnit early = (AudioUnit)1;
    AUGraphNodeInfo(g, synth_node, NULL, &early);
    printf("unit before open: %s\n", early ? "some" : "none");
    printf("open: %d\n", (int)AUGraphOpen(g));
    printf("connect: %d %d\n", (int)AUGraphConnectNodeInput(g, synth_node, 0, limiter_node, 0),
           (int)AUGraphConnectNodeInput(g, limiter_node, 0, out_node, 0));
    UInt32 count = 0, mine = 0;
    AUGraphGetNumberOfInteractions(g, &count);
    AUGraphCountNodeInteractions(g, limiter_node, &mine);
    printf("interactions: %u, the limiter's: %u\n", (unsigned)count, (unsigned)mine);
    AudioUnit synth_unit = NULL, out_unit = NULL;
    AudioComponentDescription got;
    AUGraphNodeInfo(g, synth_node, &got, &synth_unit);
    AUGraphNodeInfo(g, out_node, NULL, &out_unit);
    printf("synth node: %s, %s\n", got.componentSubType == kAudioUnitSubType_DLSSynth ? "DLS" : "other",
           synth_unit ? "open" : "not open");

    AudioStreamBasicDescription f = vlc_format();
    printf("output format: %d\n", (int)AudioUnitSetProperty(out_unit, kAudioUnitProperty_StreamFormat,
                                                            kAudioUnitScope_Output, 0, &f, sizeof f));
    OSStatus err = AUGraphInitialize(g);
    printf("initialize: %d\n", (int)err);
    Boolean yes = 0;
    AUGraphIsInitialized(g, &yes);
    printf("initialized: %d\n", yes);
    if (!err) {
        MusicDeviceMIDIEvent(synth_unit, 0xB0, 0, 0, 0); /* bank 0, as VLC sends first */
        printf("start: %d\n", (int)AUGraphStart(g));
        AudioStreamBasicDescription lf;
        UInt32 size = sizeof lf;
        AudioUnit limiter_unit = NULL;
        AUGraphNodeInfo(g, limiter_node, NULL, &limiter_unit);
        AudioUnitGetProperty(limiter_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &lf, &size);
        printf("limiter input: %.0f Hz, %u channels, float %d, split %d\n", lf.mSampleRate,
               (unsigned)lf.mChannelsPerFrame, (lf.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
               (lf.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0);
        double sample = 0, rms, peak;
        printf("silence: %d", (int)pull(out_unit, &sample, 0.1, &rms, &peak));
        printf(", quiet %d\n", peak < 0.001);
        printf("program: %d\n", (int)MusicDeviceMIDIEvent(synth_unit, 0xC0, 0, 0, 0)); /* a piano */
        printf("note on: %d\n", (int)MusicDeviceMIDIEvent(synth_unit, 0x90, 60, 110, 0));
        err = pull(out_unit, &sample, 0.3, &rms, &peak);
        printf("playing: %d, heard %d, under full scale %d\n", (int)err, rms > 0.005, peak <= 1.0);
        printf("note off: %d\n", (int)MusicDeviceMIDIEvent(synth_unit, 0x80, 60, 0, 0));
        pull(out_unit, &sample, 3.0, &rms, &peak);
        pull(out_unit, &sample, 0.2, &rms, &peak);
        printf("let go: quiet %d\n", rms < 0.001);
        /* a note half a slice in: the first half stays quiet */
        MusicDeviceMIDIEvent(synth_unit, 0x90, 64, 110, 512);
        float buf[1024 * 2];
        AudioBufferList l = {1, {{2, sizeof buf, buf}}};
        AudioTimeStamp t = {0};
        t.mFlags = kAudioTimeStampSampleTimeValid;
        t.mSampleTime = sample;
        AudioUnitRender(out_unit, NULL, &t, 0, 1024, &l);
        double first = 0, second_half = 0;
        for (int i = 0; i < 1024; i++)
            *(i < 512 ? &first : &second_half) += fabs(buf[2 * i]) + fabs(buf[2 * i + 1]);
        printf("offset note: first half quiet %d, second half heard %d\n", first < 0.01, second_half > 0.01);
        MusicDeviceMIDIEvent(synth_unit, 0xB0, 0x78, 0, 0); /* all sound off */
        printf("stop: %d\n", (int)AUGraphStop(g));
    }
    AUGraphIsRunning(g, &yes);
    printf("running: %d\n", yes);
    printf("dispose: %d\n", (int)DisposeAUGraph(g));
}

static void midi_synth(void)
{
    AudioComponentDescription d = {kAudioUnitType_MusicDevice, kAudioUnitSubType_MIDISynth,
                                   kAudioUnitManufacturer_Apple, 0, 0};
    AudioUnit u = NULL;
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &d), &u);
    const char *nowhere = "/nonexistent/bank.sf2";
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)nowhere, strlen(nowhere), false);
    printf("missing bank: %d\n", (int)AudioUnitSetProperty(u, kMusicDeviceProperty_SoundBankURL,
                                                           kAudioUnitScope_Global, 0, &url, sizeof url));
    CFRelease(url);
    UInt32 inputs = 9, size = sizeof inputs;
    AudioUnitGetProperty(u, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &inputs, &size);
    printf("synth inputs: %u\n", (unsigned)inputs);
    OSStatus err = AudioUnitInitialize(u);
    printf("midi synth initialize: %d\n", (int)err);
    if (!err) {
        MusicDeviceNoteParams p = {2, 67, 100, {{0, 0}}};
        NoteInstanceID note = 0;
        printf("start note: %d, id %u\n",
               (int)MusicDeviceStartNote(u, kMusicNoteEvent_UseGroupInstrument, 0, &note, 0, &p), (unsigned)note);
        float l[512], r[512];
        AudioBufferList *list = malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
        list->mNumberBuffers = 2;
        list->mBuffers[0] = (AudioBuffer){1, sizeof l, l};
        list->mBuffers[1] = (AudioBuffer){1, sizeof r, r};
        AudioTimeStamp t = {0};
        t.mFlags = kAudioTimeStampSampleTimeValid;
        double sum = 0;
        for (int k = 0; k < 10; k++) {
            AudioUnitRender(u, NULL, &t, 0, 512, list);
            for (int i = 0; i < 512; i++)
                sum += fabs(l[i]) + fabs(r[i]);
            t.mSampleTime += 512;
        }
        printf("note heard: %d\n", sum > 1);
        printf("stop note: %d\n", (int)MusicDeviceStopNote(u, 0, note, 0));
        printf("sysex: %d\n", (int)MusicDeviceSysEx(u, (const UInt8[]){0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7}, 6));
        free(list);
    }
    AudioComponentInstanceDispose(u);
}

typedef struct {
    double phase;
} sine;

static OSStatus loud_sine(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 bus,
                          UInt32 frames, AudioBufferList *io)
{
    sine *s = ref;
    for (UInt32 i = 0; i < frames; i++) {
        float v = (float)(4.0 * sin(s->phase));
        s->phase += 2 * M_PI * 440 / 44100;
        for (UInt32 b = 0; b < io->mNumberBuffers; b++)
            ((float *)io->mBuffers[b].mData)[i] = v;
    }
    return noErr;
}

static void limiter_alone(void)
{
    AudioComponentDescription d = {kAudioUnitType_Effect, kAudioUnitSubType_PeakLimiter,
                                   kAudioUnitManufacturer_Apple, 0, 0};
    AudioUnit u = NULL;
    AudioComponentInstanceNew(AudioComponentFindNext(NULL, &d), &u);
    sine s = {0};
    AURenderCallbackStruct cb = {loud_sine, &s};
    printf("limiter input: %d\n", (int)AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback,
                                                            kAudioUnitScope_Input, 0, &cb, sizeof cb));
    AudioUnitParameterValue attack = 0;
    AudioUnitGetParameter(u, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, &attack);
    printf("attack: %.3f s, bad value %d\n", attack,
           (int)AudioUnitSetParameter(u, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 90, 0));
    printf("limiter initialize: %d\n", (int)AudioUnitInitialize(u));
    float l[1024], r[1024];
    AudioBufferList *list = malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer));
    list->mNumberBuffers = 2;
    AudioTimeStamp t = {0};
    t.mFlags = kAudioTimeStampSampleTimeValid;
    double peak = 0, late_peak = 0;
    for (int k = 0; k < 20; k++) {
        list->mBuffers[0] = (AudioBuffer){1, sizeof l, l};
        list->mBuffers[1] = (AudioBuffer){1, sizeof r, r};
        OSStatus err = AudioUnitRender(u, NULL, &t, 0, 1024, list);
        if (err)
            printf("limiter render: %d\n", (int)err);
        for (int i = 0; i < 1024; i++) {
            peak = fmax(peak, fabs(l[i]));
            if (k >= 10)
                late_peak = fmax(late_peak, fabs(l[i]));
        }
        t.mSampleTime += 1024;
    }
    printf("limited: under full scale %d, settled near it %d\n", peak <= 1.0, late_peak > 0.8 && late_peak <= 1.0);
    free(list);
    AudioComponentInstanceDispose(u);
}

int main(void)
{
    print_name(kAudioUnitType_MusicDevice, kAudioUnitSubType_DLSSynth);
    print_name(kAudioUnitType_MusicDevice, kAudioUnitSubType_MIDISynth);
    print_name(kAudioUnitType_Effect, kAudioUnitSubType_PeakLimiter);
    vlc_graph();
    midi_synth();
    limiter_alone();
    return 0;
}
