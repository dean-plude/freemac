/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: audio units (freemac 1.234, Ferry 0.58.0), written from
 * Apple's public documentation of AUComponent: the unit types, scopes,
 * render callbacks and the calls on a unit. Not Apple's header. */
#ifndef _FERRY_AUCOMPONENT_H_
#define _FERRY_AUCOMPONENT_H_
#include <AudioToolbox/AudioComponent.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef AudioComponentInstance AudioUnit;

enum {
    kAudioUnitType_Output = 'auou',
    kAudioUnitType_MusicDevice = 'aumu',
    kAudioUnitType_MusicEffect = 'aumf',
    kAudioUnitType_FormatConverter = 'aufc',
    kAudioUnitType_Effect = 'aufx',
    kAudioUnitType_Mixer = 'aumx',
    kAudioUnitType_Panner = 'aupn',
    kAudioUnitType_Generator = 'augn',
    kAudioUnitType_OfflineEffect = 'auol',
    kAudioUnitType_MIDIProcessor = 'aumi',
    kAudioUnitType_SpeechSynthesizer = 'ausp',
};

enum {
    kAudioUnitManufacturer_Apple = 'appl',
};

enum {
    kAudioUnitSubType_GenericOutput = 'genr',
    kAudioUnitSubType_VoiceProcessingIO = 'vpio',
    kAudioUnitSubType_HALOutput = 'ahal',
    kAudioUnitSubType_DefaultOutput = 'def ',
    kAudioUnitSubType_SystemOutput = 'sys ',
    kAudioUnitSubType_AUConverter = 'conv',
    kAudioUnitSubType_NewTimePitch = 'nutp',
    kAudioUnitSubType_TimePitch = 'tmpt',
    kAudioUnitSubType_Varispeed = 'vari',
    kAudioUnitSubType_DeferredRenderer = 'defr',
    kAudioUnitSubType_Splitter = 'splt',
    kAudioUnitSubType_Merger = 'merg',
    kAudioUnitSubType_MultiChannelMixer = 'mcmx',
    kAudioUnitSubType_MatrixMixer = 'mxmx',
    kAudioUnitSubType_StereoMixer = 'smxr',
    kAudioUnitSubType_SpatialMixer = '3dem',
    kAudioUnitSubType_DLSSynth = 'dls ',
    kAudioUnitSubType_MIDISynth = 'msyn',
    kAudioUnitSubType_PeakLimiter = 'lmtr',
    kAudioUnitSubType_Sampler = 'samp',
    kAudioUnitSubType_AudioFilePlayer = 'afpl',
    kAudioUnitSubType_ScheduledSoundPlayer = 'sspl',
};

/* the selectors of the calls on an audio unit, which a plug-in's Lookup is
 * asked for (freemac 1.NEXT) */
enum {
    kAudioUnitRange = 0x0000,
    kAudioUnitInitializeSelect = 0x0001,
    kAudioUnitUninitializeSelect = 0x0002,
    kAudioUnitGetPropertyInfoSelect = 0x0003,
    kAudioUnitGetPropertySelect = 0x0004,
    kAudioUnitSetPropertySelect = 0x0005,
    kAudioUnitGetParameterSelect = 0x0006,
    kAudioUnitSetParameterSelect = 0x0007,
    kAudioUnitResetSelect = 0x0009,
    kAudioUnitAddPropertyListenerSelect = 0x000A,
    kAudioUnitRemovePropertyListenerSelect = 0x000B,
    kAudioUnitRenderSelect = 0x000E,
    kAudioUnitAddRenderNotifySelect = 0x000F,
    kAudioUnitRemoveRenderNotifySelect = 0x0010,
    kAudioUnitScheduleParametersSelect = 0x0011,
    kAudioUnitRemovePropertyListenerWithUserDataSelect = 0x0012,
    kAudioUnitProcessSelect = 0x0014,
};

typedef UInt32 AudioUnitRenderActionFlags;
enum {
    kAudioUnitRenderAction_PreRender = (1U << 2),
    kAudioUnitRenderAction_PostRender = (1U << 3),
    kAudioUnitRenderAction_OutputIsSilence = (1U << 4),
    kAudioOfflineUnitRenderAction_Preflight = (1U << 5),
    kAudioOfflineUnitRenderAction_Render = (1U << 6),
    kAudioOfflineUnitRenderAction_Complete = (1U << 7),
    kAudioUnitRenderAction_PostRenderError = (1U << 8),
    kAudioUnitRenderAction_DoNotCheckRenderArgs = (1U << 9),
};

enum {
    kAudioUnitErr_InvalidProperty = -10879,
    kAudioUnitErr_InvalidParameter = -10878,
    kAudioUnitErr_InvalidElement = -10877,
    kAudioUnitErr_NoConnection = -10876,
    kAudioUnitErr_FailedInitialization = -10875,
    kAudioUnitErr_TooManyFramesToProcess = -10874,
    kAudioUnitErr_InvalidFile = -10871,
    kAudioUnitErr_UnknownFileType = -10870,
    kAudioUnitErr_FileNotSpecified = -10869,
    kAudioUnitErr_FormatNotSupported = -10868,
    kAudioUnitErr_Uninitialized = -10867,
    kAudioUnitErr_InvalidScope = -10866,
    kAudioUnitErr_PropertyNotWritable = -10865,
    kAudioUnitErr_CannotDoInCurrentContext = -10863,
    kAudioUnitErr_InvalidPropertyValue = -10851,
    kAudioUnitErr_PropertyNotInUse = -10850,
    kAudioUnitErr_Initialized = -10849,
    kAudioUnitErr_InvalidOfflineRender = -10848,
    kAudioUnitErr_Unauthorized = -10847,
    kAudioUnitErr_MIDIOutputBufferFull = -66753,
    kAudioComponentErr_InstanceTimedOut = -66754,
    kAudioComponentErr_InstanceInvalidated = -66749,
    kAudioUnitErr_RenderTimeout = -66745,
    kAudioUnitErr_ExtensionNotFound = -66744,
    kAudioUnitErr_InvalidParameterValue = -66743,
    kAudioUnitErr_InvalidFilePath = -66742,
    kAudioUnitErr_MissingKey = -66741,
    kAudioComponentErr_DuplicateDescription = -66752,
    kAudioComponentErr_UnsupportedType = -66751,
    kAudioComponentErr_TooManyInstances = -66750,
    kAudioComponentErr_NotPermitted = -66748,
    kAudioComponentErr_InitializationTimedOut = -66747,
    kAudioComponentErr_InvalidFormat = -66746,
};

typedef UInt32 AudioUnitPropertyID;
typedef UInt32 AudioUnitScope;
typedef UInt32 AudioUnitElement;
typedef UInt32 AudioUnitParameterID;
typedef Float32 AudioUnitParameterValue;

typedef UInt32 AUParameterEventType;
enum {
    kParameterEvent_Immediate = 1,
    kParameterEvent_Ramped = 2,
};
typedef struct AudioUnitParameterEvent {
    AudioUnitScope scope;
    AudioUnitElement element;
    AudioUnitParameterID parameter;
    AUParameterEventType eventType;
    union {
        struct {
            SInt32 startBufferOffset;
            UInt32 durationInFrames;
            AudioUnitParameterValue startValue;
            AudioUnitParameterValue endValue;
        } ramp;
        struct {
            UInt32 bufferOffset;
            AudioUnitParameterValue value;
        } immediate;
    } eventValues;
} AudioUnitParameterEvent;

typedef struct AudioUnitParameter {
    AudioUnit mAudioUnit;
    AudioUnitParameterID mParameterID;
    AudioUnitScope mScope;
    AudioUnitElement mElement;
} AudioUnitParameter;

typedef struct AudioUnitProperty {
    AudioUnit mAudioUnit;
    AudioUnitPropertyID mPropertyID;
    AudioUnitScope mScope;
    AudioUnitElement mElement;
} AudioUnitProperty;

typedef OSStatus (*AURenderCallback)(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
                                     const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames,
                                     AudioBufferList *ioData);
typedef void (*AudioUnitPropertyListenerProc)(void *inRefCon, AudioUnit inUnit, AudioUnitPropertyID inID,
                                              AudioUnitScope inScope, AudioUnitElement inElement);
typedef void (*AUInputSamplesInOutputCallback)(void *inRefCon, const AudioTimeStamp *inOutputTimeStamp,
                                               Float64 inInputSample, Float64 inNumberInputSamples);

OSStatus AudioUnitInitialize(AudioUnit inUnit);
OSStatus AudioUnitUninitialize(AudioUnit inUnit);
OSStatus AudioUnitGetPropertyInfo(AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope,
                                  AudioUnitElement inElement, UInt32 *outDataSize, Boolean *outWritable);
OSStatus AudioUnitGetProperty(AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope,
                              AudioUnitElement inElement, void *outData, UInt32 *ioDataSize);
OSStatus AudioUnitSetProperty(AudioUnit inUnit, AudioUnitPropertyID inID, AudioUnitScope inScope,
                              AudioUnitElement inElement, const void *inData, UInt32 inDataSize);
OSStatus AudioUnitAddPropertyListener(AudioUnit inUnit, AudioUnitPropertyID inID,
                                      AudioUnitPropertyListenerProc inProc, void *inProcUserData);
OSStatus AudioUnitRemovePropertyListenerWithUserData(AudioUnit inUnit, AudioUnitPropertyID inID,
                                                     AudioUnitPropertyListenerProc inProc, void *inProcUserData);
OSStatus AudioUnitRemovePropertyListener(AudioUnit inUnit, AudioUnitPropertyID inID,
                                         AudioUnitPropertyListenerProc inProc);
OSStatus AudioUnitAddRenderNotify(AudioUnit inUnit, AURenderCallback inProc, void *inProcUserData);
OSStatus AudioUnitRemoveRenderNotify(AudioUnit inUnit, AURenderCallback inProc, void *inProcUserData);
OSStatus AudioUnitGetParameter(AudioUnit inUnit, AudioUnitParameterID inID, AudioUnitScope inScope,
                               AudioUnitElement inElement, AudioUnitParameterValue *outValue);
OSStatus AudioUnitSetParameter(AudioUnit inUnit, AudioUnitParameterID inID, AudioUnitScope inScope,
                               AudioUnitElement inElement, AudioUnitParameterValue inValue,
                               UInt32 inBufferOffsetInFrames);
OSStatus AudioUnitScheduleParameters(AudioUnit inUnit, const AudioUnitParameterEvent *inParameterEvent,
                                     UInt32 inNumParamEvents);
OSStatus AudioUnitRender(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                         const AudioTimeStamp *inTimeStamp, UInt32 inOutputBusNumber, UInt32 inNumberFrames,
                         AudioBufferList *ioData);
OSStatus AudioUnitProcess(AudioUnit inUnit, AudioUnitRenderActionFlags *ioActionFlags,
                          const AudioTimeStamp *inTimeStamp, UInt32 inNumberFrames, AudioBufferList *ioData);
OSStatus AudioUnitReset(AudioUnit inUnit, AudioUnitScope inScope, AudioUnitElement inElement);

#ifdef __cplusplus
}
#endif
#endif
