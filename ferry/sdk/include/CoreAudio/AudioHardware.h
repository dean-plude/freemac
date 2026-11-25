/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core Audio HAL (freemac 1.234, Ferry 0.58.0), written
 * from Apple's public documentation of AudioHardware: the AudioObject
 * property calls and listeners, the system object's and devices'
 * properties, and the IO procs that move a device's samples. Ferry's
 * CoreAudio.framework answers them with this system's sound server's
 * devices (or a null device). Not Apple's header. */
#ifndef _FERRY_AUDIOHARDWARE_H_
#define _FERRY_AUDIOHARDWARE_H_
#include <CoreAudio/AudioHardwareBase.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef AudioObjectID AudioDeviceID;
typedef AudioObjectID AudioStreamID;
typedef AudioObjectID AudioAggregateDeviceID;

enum {
    kAudioObjectSystemObject = 1,
};

/* ---- listeners ---- */
typedef OSStatus (*AudioObjectPropertyListenerProc)(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                                                    const AudioObjectPropertyAddress *inAddresses,
                                                    void *inClientData);
#if __BLOCKS__
typedef void (^AudioObjectPropertyListenerBlock)(UInt32 inNumberAddresses,
                                                 const AudioObjectPropertyAddress *inAddresses);
#endif

enum {
    kAudioObjectPropertyCreator = 'oplg',
    kAudioObjectPropertyListenerAdded = 'lisa',
    kAudioObjectPropertyListenerRemoved = 'lisr',
};

void AudioObjectShow(AudioObjectID inObjectID);
Boolean AudioObjectHasProperty(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress);
OSStatus AudioObjectIsPropertySettable(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                       Boolean *outIsSettable);
OSStatus AudioObjectGetPropertyDataSize(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                        UInt32 inQualifierDataSize, const void *inQualifierData,
                                        UInt32 *outDataSize);
OSStatus AudioObjectGetPropertyData(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                    UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 *ioDataSize,
                                    void *outData);
OSStatus AudioObjectSetPropertyData(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                    UInt32 inQualifierDataSize, const void *inQualifierData, UInt32 inDataSize,
                                    const void *inData);
OSStatus AudioObjectAddPropertyListener(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                        AudioObjectPropertyListenerProc inListener, void *inClientData);
OSStatus AudioObjectRemovePropertyListener(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                           AudioObjectPropertyListenerProc inListener, void *inClientData);
#if __BLOCKS__
OSStatus AudioObjectAddPropertyListenerBlock(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                             dispatch_queue_t inDispatchQueue,
                                             AudioObjectPropertyListenerBlock inListener);
OSStatus AudioObjectRemovePropertyListenerBlock(AudioObjectID inObjectID,
                                                const AudioObjectPropertyAddress *inAddress,
                                                dispatch_queue_t inDispatchQueue,
                                                AudioObjectPropertyListenerBlock inListener);
#endif

/* ---- the system object ---- */
enum {
    kAudioSystemObjectClassID = 'asys',
};

typedef UInt32 AudioHardwarePowerHint;
enum {
    kAudioHardwarePowerHintNone = 0,
    kAudioHardwarePowerHintFavorSavingPower = 1,
};

enum {
    kAudioHardwarePropertyDevices = 'dev#',
    kAudioHardwarePropertyDefaultInputDevice = 'dIn ',
    kAudioHardwarePropertyDefaultOutputDevice = 'dOut',
    kAudioHardwarePropertyDefaultSystemOutputDevice = 'sOut',
    kAudioHardwarePropertyTranslateUIDToDevice = 'uidd',
    kAudioHardwarePropertyMixStereoToMono = 'stmo',
    kAudioHardwarePropertyPlugInList = 'plg#',
    kAudioHardwarePropertyTranslateBundleIDToPlugIn = 'bidp',
    kAudioHardwarePropertyTransportManagerList = 'tmg#',
    kAudioHardwarePropertyTranslateBundleIDToTransportManager = 'tmbi',
    kAudioHardwarePropertyBoxList = 'box#',
    kAudioHardwarePropertyTranslateUIDToBox = 'uidb',
    kAudioHardwarePropertyClockDeviceList = 'clk#',
    kAudioHardwarePropertyTranslateUIDToClockDevice = 'uidc',
    kAudioHardwarePropertyProcessIsMain = 'main',
    kAudioHardwarePropertyIsInitingOrExiting = 'inot',
    kAudioHardwarePropertyUserIDChanged = 'euid',
    kAudioHardwarePropertyProcessInputMute = 'pmin',
    kAudioHardwarePropertyProcessIsAudible = 'pmut',
    kAudioHardwarePropertySleepingIsAllowed = 'slep',
    kAudioHardwarePropertyUnloadingIsAllowed = 'unld',
    kAudioHardwarePropertyHogModeIsAllowed = 'hogr',
    kAudioHardwarePropertyUserSessionIsActiveOrHeadless = 'user',
    kAudioHardwarePropertyServiceRestarted = 'srst',
    kAudioHardwarePropertyPowerHint = 'powh',
    kAudioHardwarePropertyProcessObjectList = 'prs#',
    kAudioHardwarePropertyTranslatePIDToProcessObject = 'id2p',
    kAudioHardwarePropertyTapList = 'tps#',
    kAudioHardwarePropertyTranslateUIDToTap = 'uidt',
    /* older names, still answered */
    kAudioHardwarePropertyProcessIsMaster = 'mast',
    kAudioHardwarePropertyDeviceForUID = 'duid',
    kAudioHardwarePropertyRunLoop = 'rnlp',
    kAudioHardwarePropertyPlugInForBundleID = 'pibi',
};

OSStatus AudioHardwareUnload(void);

/* ---- devices ---- */
typedef OSStatus (*AudioDeviceIOProc)(AudioObjectID inDevice, const AudioTimeStamp *inNow,
                                      const AudioBufferList *inInputData, const AudioTimeStamp *inInputTime,
                                      AudioBufferList *outOutputData, const AudioTimeStamp *inOutputTime,
                                      void *inClientData);
#if __BLOCKS__
typedef void (^AudioDeviceIOBlock)(const AudioTimeStamp *inNow, const AudioBufferList *inInputData,
                                   const AudioTimeStamp *inInputTime, AudioBufferList *outOutputData,
                                   const AudioTimeStamp *inOutputTime);
#endif
typedef AudioDeviceIOProc AudioDeviceIOProcID;

typedef struct AudioHardwareIOProcStreamUsage {
    void *mIOProc;
    UInt32 mNumberStreams;
    UInt32 mStreamIsOn[1];
} AudioHardwareIOProcStreamUsage;

enum {
    kAudioDeviceStartTimeIsInputFlag = (1U << 0),
    kAudioDeviceStartTimeDontConsultDeviceFlag = (1U << 1),
    kAudioDeviceStartTimeDontConsultHALFlag = (1U << 2),
};

enum {
    kAudioDevicePropertyScopeInput = kAudioObjectPropertyScopeInput,
    kAudioDevicePropertyScopeOutput = kAudioObjectPropertyScopeOutput,
    kAudioDevicePropertyScopePlayThrough = kAudioObjectPropertyScopePlayThrough,
};

enum {
    kAudioDevicePropertyPlugIn = 'plug',
    kAudioDevicePropertyDeviceHasChanged = 'diff',
    kAudioDevicePropertyDeviceIsRunningSomewhere = 'gone',
    kAudioDeviceProcessorOverload = 'over',
    kAudioDevicePropertyIOStoppedAbnormally = 'stpd',
    kAudioDevicePropertyHogMode = 'oink',
    kAudioDevicePropertyBufferFrameSize = 'fsiz',
    kAudioDevicePropertyBufferFrameSizeRange = 'fsz#',
    kAudioDevicePropertyUsesVariableBufferFrameSizes = 'vfsz',
    kAudioDevicePropertyIOCycleUsage = 'ncyc',
    kAudioDevicePropertyStreamConfiguration = 'slay',
    kAudioDevicePropertyIOProcStreamUsage = 'suse',
    kAudioDevicePropertyActualSampleRate = 'asrt',
    kAudioDevicePropertyClockDevice = 'apcd',
    kAudioDevicePropertyIOThreadOSWorkgroup = 'oswg',
    kAudioDevicePropertyProcessMute = 'appm',
    kAudioDevicePropertyJackIsConnected = 'jack',
    kAudioDevicePropertyVolumeScalar = 'volm',
    kAudioDevicePropertyVolumeDecibels = 'vold',
    kAudioDevicePropertyVolumeRangeDecibels = 'vdb#',
    kAudioDevicePropertyVolumeScalarToDecibels = 'v2db',
    kAudioDevicePropertyVolumeDecibelsToScalar = 'db2v',
    kAudioDevicePropertyStereoPan = 'span',
    kAudioDevicePropertyStereoPanChannels = 'spn#',
    kAudioDevicePropertyMute = 'mute',
    kAudioDevicePropertySolo = 'solo',
    kAudioDevicePropertyPhantomPower = 'phan',
    kAudioDevicePropertyPhaseInvert = 'phsi',
    kAudioDevicePropertyClipLight = 'clip',
    kAudioDevicePropertyTalkback = 'talb',
    kAudioDevicePropertyListenback = 'lsnb',
    kAudioDevicePropertyDataSource = 'ssrc',
    kAudioDevicePropertyDataSources = 'ssc#',
    kAudioDevicePropertyDataSourceNameForIDCFString = 'lscn',
    kAudioDevicePropertyDataSourceKindForID = 'ssck',
    kAudioDevicePropertyClockSource = 'csrc',
    kAudioDevicePropertyClockSources = 'csc#',
    kAudioDevicePropertyClockSourceNameForIDCFString = 'lcsn',
    kAudioDevicePropertyClockSourceKindForID = 'csck',
    kAudioDevicePropertyPlayThru = 'thru',
    kAudioDevicePropertySubVolumeScalar = 'svlm',
    kAudioDevicePropertySubMute = 'smut',
    kAudioDevicePropertyVoiceActivityDetectionEnable = 'vAd+',
    kAudioDevicePropertyVoiceActivityDetectionState = 'vAdS',
};

/* older device names, still answered */
enum {
    kAudioDevicePropertyDeviceName = 'name',
    kAudioDevicePropertyDeviceNameCFString = kAudioObjectPropertyName,
    kAudioDevicePropertyDeviceManufacturer = 'makr',
    kAudioDevicePropertyDeviceManufacturerCFString = kAudioObjectPropertyManufacturer,
    kAudioDevicePropertyRegisterBufferList = 'rbuf',
    kAudioDevicePropertyBufferSize = 'bsiz',
    kAudioDevicePropertyBufferSizeRange = 'bsz#',
    kAudioDevicePropertyChannelName = 'chnm',
    kAudioDevicePropertyChannelNameCFString = kAudioObjectPropertyElementName,
    kAudioDevicePropertyChannelCategoryName = 'ccnm',
    kAudioDevicePropertyChannelCategoryNameCFString = kAudioObjectPropertyElementCategoryName,
    kAudioDevicePropertyChannelNumberName = 'cnnm',
    kAudioDevicePropertyChannelNumberNameCFString = kAudioObjectPropertyElementNumberName,
    kAudioDevicePropertySupportsMixing = 'mix?',
    kAudioDevicePropertyStreamFormat = 'sfmt',
    kAudioDevicePropertyStreamFormats = 'sfm#',
    kAudioDevicePropertyStreamFormatSupported = 'sfm?',
    kAudioDevicePropertyStreamFormatMatch = 'sfmm',
    kAudioDevicePropertyDataSourceNameForID = 'sscn',
    kAudioDevicePropertyClockSourceNameForID = 'cscn',
    kAudioDevicePropertyPlayThruDestinationNameForID = 'mddn',
    kAudioDevicePropertyChannelNominalLineLevelNameForID = 'cnlv',
    kAudioDevicePropertyHighPassFilterSettingNameForID = 'chip',
};

OSStatus AudioDeviceCreateIOProcID(AudioObjectID inDevice, AudioDeviceIOProc inProc, void *inClientData,
                                   AudioDeviceIOProcID *outIOProcID);
#if __BLOCKS__
OSStatus AudioDeviceCreateIOProcIDWithBlock(AudioDeviceIOProcID *outIOProcID, AudioObjectID inDevice,
                                            dispatch_queue_t inDispatchQueue, AudioDeviceIOBlock inIOBlock);
#endif
OSStatus AudioDeviceDestroyIOProcID(AudioObjectID inDevice, AudioDeviceIOProcID inIOProcID);
OSStatus AudioDeviceStart(AudioObjectID inDevice, AudioDeviceIOProcID inProcID);
OSStatus AudioDeviceStartAtTime(AudioObjectID inDevice, AudioDeviceIOProcID inProcID,
                                AudioTimeStamp *ioRequestedStartTime, UInt32 inFlags);
OSStatus AudioDeviceStop(AudioObjectID inDevice, AudioDeviceIOProcID inProcID);
OSStatus AudioDeviceGetCurrentTime(AudioObjectID inDevice, AudioTimeStamp *outTime);
OSStatus AudioDeviceTranslateTime(AudioObjectID inDevice, const AudioTimeStamp *inTime, AudioTimeStamp *outTime);
OSStatus AudioDeviceGetNearestStartTime(AudioObjectID inDevice, AudioTimeStamp *ioRequestedStartTime,
                                        UInt32 inFlags);
/* the older calls */
OSStatus AudioDeviceAddIOProc(AudioDeviceID inDevice, AudioDeviceIOProc inProc, void *inClientData);
OSStatus AudioDeviceRemoveIOProc(AudioDeviceID inDevice, AudioDeviceIOProc inProc);

/* ---- streams ---- */
enum {
    kAudioStreamPropertyOwningDevice = kAudioObjectPropertyOwner,
    kAudioStreamPropertyPhysicalFormats = 'pft#',
    kAudioStreamPropertyPhysicalFormatSupported = 'pft?',
    kAudioStreamPropertyPhysicalFormatMatch = 'pftm',
};

/* ---- the older hardware calls ---- */
typedef AudioObjectPropertySelector AudioHardwarePropertyID;
typedef AudioObjectPropertySelector AudioDevicePropertyID;
typedef OSStatus (*AudioHardwarePropertyListenerProc)(AudioHardwarePropertyID inPropertyID, void *inClientData);
OSStatus AudioHardwareGetPropertyInfo(AudioHardwarePropertyID inPropertyID, UInt32 *outSize, Boolean *outWritable);
OSStatus AudioHardwareGetProperty(AudioHardwarePropertyID inPropertyID, UInt32 *ioPropertyDataSize,
                                  void *outPropertyData);
OSStatus AudioHardwareSetProperty(AudioHardwarePropertyID inPropertyID, UInt32 inPropertyDataSize,
                                  const void *inPropertyData);
OSStatus AudioDeviceGetPropertyInfo(AudioDeviceID inDevice, UInt32 inChannel, Boolean isInput,
                                    AudioDevicePropertyID inPropertyID, UInt32 *outSize, Boolean *outWritable);
OSStatus AudioDeviceGetProperty(AudioDeviceID inDevice, UInt32 inChannel, Boolean isInput,
                                AudioDevicePropertyID inPropertyID, UInt32 *ioPropertyDataSize,
                                void *outPropertyData);
OSStatus AudioDeviceSetProperty(AudioDeviceID inDevice, const AudioTimeStamp *inWhen, UInt32 inChannel,
                                Boolean isInput, AudioDevicePropertyID inPropertyID, UInt32 inPropertyDataSize,
                                const void *inPropertyData);

#ifdef __cplusplus
}
#endif
#endif
