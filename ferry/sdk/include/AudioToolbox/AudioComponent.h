/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: audio components (freemac 1.234, Ferry 0.58.0), written from
 * Apple's public documentation of AudioComponent. Ferry offers Apple's
 * output units: HAL output, default output and system output. Not Apple's
 * header. */
#ifndef _FERRY_AUDIOCOMPONENT_H_
#define _FERRY_AUDIOCOMPONENT_H_
#include <CoreAudioTypes/CoreAudioTypes.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef UInt32 AudioComponentFlags;
enum {
    kAudioComponentFlag_Unsearchable = 1,
    kAudioComponentFlag_SandboxSafe = 2,
    kAudioComponentFlag_IsV3AudioUnit = 4,
    kAudioComponentFlag_RequiresAsyncInstantiation = 8,
    kAudioComponentFlag_CanLoadInProcess = 0x10,
};

typedef UInt32 AudioComponentInstantiationOptions;
enum {
    kAudioComponentInstantiation_LoadOutOfProcess = 1,
    kAudioComponentInstantiation_LoadInProcess = 2,
    kAudioComponentInstantiation_LoadedRemotely = 1U << 31,
};

typedef struct AudioComponentDescription {
    OSType componentType;
    OSType componentSubType;
    OSType componentManufacturer;
    UInt32 componentFlags;
    UInt32 componentFlagsMask;
} AudioComponentDescription;

typedef struct OpaqueAudioComponent *AudioComponent;
typedef struct ComponentInstanceRecord *AudioComponentInstance;

typedef OSStatus (*AudioComponentMethod)(void *self, ...);
typedef struct AudioComponentPlugInInterface {
    OSStatus (*Open)(void *self, AudioComponentInstance mInstance);
    OSStatus (*Close)(void *self);
    AudioComponentMethod (*Lookup)(SInt16 selector);
    void *reserved;
} AudioComponentPlugInInterface;
typedef AudioComponentPlugInInterface *(*AudioComponentFactoryFunction)(const AudioComponentDescription *inDesc);

AudioComponent AudioComponentFindNext(AudioComponent inComponent, const AudioComponentDescription *inDesc);
UInt32 AudioComponentCount(const AudioComponentDescription *inDesc);
OSStatus AudioComponentCopyName(AudioComponent inComponent, CFStringRef *outName);
OSStatus AudioComponentGetDescription(AudioComponent inComponent, AudioComponentDescription *outDesc);
OSStatus AudioComponentGetVersion(AudioComponent inComponent, UInt32 *outVersion);
OSStatus AudioComponentInstanceNew(AudioComponent inComponent, AudioComponentInstance *outInstance);
#if __BLOCKS__
void AudioComponentInstantiate(AudioComponent inComponent, AudioComponentInstantiationOptions inOptions,
                               void (^inCompletionHandler)(AudioComponentInstance, OSStatus));
#endif
OSStatus AudioComponentInstanceDispose(AudioComponentInstance inInstance);
AudioComponent AudioComponentInstanceGetComponent(AudioComponentInstance inInstance);
Boolean AudioComponentInstanceCanDo(AudioComponentInstance inInstance, SInt16 inSelectorID);
AudioComponent AudioComponentRegister(const AudioComponentDescription *inDesc, CFStringRef inName,
                                      UInt32 inVersion, AudioComponentFactoryFunction inFactory);

#ifdef __cplusplus
}
#endif
#endif
