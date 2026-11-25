/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: audio units' properties (freemac 1.234, Ferry 0.58.0),
 * written from Apple's public documentation of AudioUnitProperties: the
 * scopes, the general properties and the output units' own. Not Apple's
 * header. */
#ifndef _FERRY_AUDIOUNITPROPERTIES_H_
#define _FERRY_AUDIOUNITPROPERTIES_H_
#include <AudioToolbox/AUComponent.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kAudioUnitScope_Global = 0,
    kAudioUnitScope_Input = 1,
    kAudioUnitScope_Output = 2,
    kAudioUnitScope_Group = 3,
    kAudioUnitScope_Part = 4,
    kAudioUnitScope_Note = 5,
    kAudioUnitScope_Layer = 6,
    kAudioUnitScope_LayerItem = 7,
};

enum {
    kAudioUnitProperty_ClassInfo = 0,
    kAudioUnitProperty_MakeConnection = 1,
    kAudioUnitProperty_SampleRate = 2,
    kAudioUnitProperty_ParameterList = 3,
    kAudioUnitProperty_ParameterInfo = 4,
    kAudioUnitProperty_CPULoad = 6,
    kAudioUnitProperty_StreamFormat = 8,
    kAudioUnitProperty_ElementCount = 11,
    kAudioUnitProperty_Latency = 12,
    kAudioUnitProperty_SupportedNumChannels = 13,
    kAudioUnitProperty_MaximumFramesPerSlice = 14,
    kAudioUnitProperty_ParameterValueStrings = 16,
    kAudioUnitProperty_AudioChannelLayout = 19,
    kAudioUnitProperty_TailTime = 20,
    kAudioUnitProperty_BypassEffect = 21,
    kAudioUnitProperty_LastRenderError = 22,
    kAudioUnitProperty_SetRenderCallback = 23,
    kAudioUnitProperty_FactoryPresets = 24,
    kAudioUnitProperty_RenderQuality = 26,
    kAudioUnitProperty_HostCallbacks = 27,
    kAudioUnitProperty_InPlaceProcessing = 29,
    kAudioUnitProperty_ElementName = 30,
    kAudioUnitProperty_SupportedChannelLayoutTags = 32,
    kAudioUnitProperty_PresentPreset = 36,
    kAudioUnitProperty_DependentParameters = 45,
    kAudioUnitProperty_InputSamplesInOutput = 49,
    kAudioUnitProperty_ShouldAllocateBuffer = 51,
    kAudioUnitProperty_FrequencyResponse = 52,
    kAudioUnitProperty_ParameterHistoryInfo = 53,
    kAudioUnitProperty_NickName = 54,
    kAudioUnitProperty_OfflineRender = 37,
    kAudioUnitProperty_ParameterIDName = 34,
    kAudioUnitProperty_ParameterStringFromValue = 33,
    kAudioUnitProperty_ParameterClumpName = 35,
    kAudioUnitProperty_ParameterValueFromString = 38,
    kAudioUnitProperty_ContextName = 25,
    kAudioUnitProperty_PresentationLatency = 40,
    kAudioUnitProperty_ClassInfoFromDocument = 50,
    kAudioUnitProperty_RequestViewController = 56,
    kAudioUnitProperty_ParametersForOverview = 57,
    kAudioUnitProperty_SupportsMPE = 58,
    kAudioUnitProperty_RenderContextObserver = 60,
    kAudioUnitProperty_LastRenderSampleTime = 61,
    kAudioUnitProperty_LoadedOutOfProcess = 62,
    kAudioUnitProperty_FastDispatch = 5,
    kAudioUnitProperty_SetExternalBuffer = 15,
    kAudioUnitProperty_GetUIComponentList = 18,
    kAudioUnitProperty_CocoaUI = 31,
    kAudioUnitProperty_IconLocation = 39,
    kAudioUnitProperty_AUHostIdentifier = 46,
    kAudioUnitProperty_MIDIOutputCallbackInfo = 47,
    kAudioUnitProperty_MIDIOutputCallback = 48,
};

typedef struct AURenderCallbackStruct {
    AURenderCallback inputProc;
    void *inputProcRefCon;
} AURenderCallbackStruct;

typedef struct AudioUnitConnection {
    AudioUnit sourceAudioUnit;
    UInt32 sourceOutputNumber;
    UInt32 destInputNumber;
} AudioUnitConnection;

typedef struct AUChannelInfo {
    SInt16 inChannels;
    SInt16 outChannels;
} AUChannelInfo;

typedef struct AudioUnitExternalBuffer {
    Byte *buffer;
    UInt32 size;
} AudioUnitExternalBuffer;

typedef struct AUPreset {
    SInt32 presetNumber;
    CFStringRef presetName;
} AUPreset;

enum {
    kRenderQuality_Max = 127,
    kRenderQuality_High = 96,
    kRenderQuality_Medium = 64,
    kRenderQuality_Low = 32,
    kRenderQuality_Min = 0,
};

/* ---- output units ---- */
enum {
    kAudioOutputUnitProperty_CurrentDevice = 2000,
    kAudioOutputUnitProperty_IsRunning = 2001,
    kAudioOutputUnitProperty_ChannelMap = 2002,
    kAudioOutputUnitProperty_EnableIO = 2003,
    kAudioOutputUnitProperty_StartTime = 2004,
    kAudioOutputUnitProperty_SetInputCallback = 2005,
    kAudioOutputUnitProperty_HasIO = 2006,
    kAudioOutputUnitProperty_StartTimestampsAtZero = 2007,
    kAudioOutputUnitProperty_OSWorkgroup = 2015,
};

typedef struct AudioOutputUnitStartAtTimeParams {
    AudioTimeStamp mTimestamp;
    UInt32 mFlags;
} AudioOutputUnitStartAtTimeParams;

/* ---- the format converter ---- */
enum {
    kAudioUnitProperty_SampleRateConverterComplexity = 3014,
};

/* ---- parameters' descriptions ---- */
typedef UInt32 AudioUnitParameterUnit;
enum {
    kAudioUnitParameterUnit_Generic = 0,
    kAudioUnitParameterUnit_Indexed = 1,
    kAudioUnitParameterUnit_Boolean = 2,
    kAudioUnitParameterUnit_Percent = 3,
    kAudioUnitParameterUnit_Seconds = 4,
    kAudioUnitParameterUnit_SampleFrames = 5,
    kAudioUnitParameterUnit_Phase = 6,
    kAudioUnitParameterUnit_Rate = 7,
    kAudioUnitParameterUnit_Hertz = 8,
    kAudioUnitParameterUnit_Cents = 9,
    kAudioUnitParameterUnit_RelativeSemiTones = 10,
    kAudioUnitParameterUnit_MIDINoteNumber = 11,
    kAudioUnitParameterUnit_MIDIController = 12,
    kAudioUnitParameterUnit_Decibels = 13,
    kAudioUnitParameterUnit_LinearGain = 14,
    kAudioUnitParameterUnit_Degrees = 15,
    kAudioUnitParameterUnit_EqualPowerCrossfade = 16,
    kAudioUnitParameterUnit_MixerFaderCurve1 = 17,
    kAudioUnitParameterUnit_Pan = 18,
    kAudioUnitParameterUnit_Meters = 19,
    kAudioUnitParameterUnit_AbsoluteCents = 20,
    kAudioUnitParameterUnit_Octaves = 21,
    kAudioUnitParameterUnit_BPM = 22,
    kAudioUnitParameterUnit_Beats = 23,
    kAudioUnitParameterUnit_Milliseconds = 24,
    kAudioUnitParameterUnit_Ratio = 25,
    kAudioUnitParameterUnit_CustomUnit = 26,
    kAudioUnitParameterUnit_MIDI2Controller = 27,
};

typedef UInt32 AudioUnitParameterOptions;
enum {
    kAudioUnitParameterFlag_IsReadable = (1UL << 30),
    kAudioUnitParameterFlag_IsWritable = (1UL << 31),
};

typedef struct AudioUnitParameterInfo {
    char name[52];
    CFStringRef unitName;
    UInt32 clumpID;
    CFStringRef cfNameString;
    AudioUnitParameterUnit unit;
    AudioUnitParameterValue minValue;
    AudioUnitParameterValue maxValue;
    AudioUnitParameterValue defaultValue;
    AudioUnitParameterOptions flags;
} AudioUnitParameterInfo;

#ifdef __cplusplus
}
#endif
#endif
