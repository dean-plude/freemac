/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * Core Audio's audio objects (freemac 1.232, Ferry 0.56.0): the system
 * object and its default output and input devices, with their names,
 * volume and mute, read and set through this system's sound server
 * (PulseAudio's pactl, or PipeWire's wpctl). Written from Apple's public
 * Core Audio documentation; not Apple's header. Implemented in
 * coreaudio/CoreAudio.c. No audio is played or recorded here. */
#ifndef _FERRY_COREAUDIO_H_
#define _FERRY_COREAUDIO_H_
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN

typedef int32_t OSStatus;
typedef UInt32 AudioObjectID;
typedef AudioObjectID AudioDeviceID;
typedef UInt32 AudioObjectPropertySelector;
typedef UInt32 AudioObjectPropertyScope;
typedef UInt32 AudioObjectPropertyElement;
typedef struct AudioObjectPropertyAddress {
    AudioObjectPropertySelector mSelector;
    AudioObjectPropertyScope mScope;
    AudioObjectPropertyElement mElement;
} AudioObjectPropertyAddress;

enum {
    kAudioObjectUnknown = 0,
    kAudioObjectSystemObject = 1,
};
enum {
    kAudioHardwareNoError = 0,
    kAudioHardwareNotRunningError = 'stop',
    kAudioHardwareUnspecifiedError = 'what',
    kAudioHardwareUnknownPropertyError = 'who?',
    kAudioHardwareBadPropertySizeError = '!siz',
    kAudioHardwareIllegalOperationError = 'nope',
    kAudioHardwareBadObjectError = '!obj',
    kAudioHardwareBadDeviceError = '!dev',
    kAudioHardwareUnsupportedOperationError = 'unop',
};
enum {
    kAudioObjectPropertyScopeGlobal = 'glob',
    kAudioObjectPropertyScopeInput = 'inpt',
    kAudioObjectPropertyScopeOutput = 'outp',
    kAudioObjectPropertyScopeWildcard = '****',
    kAudioDevicePropertyScopeInput = 'inpt',
    kAudioDevicePropertyScopeOutput = 'outp',
    kAudioObjectPropertyElementMain = 0,
    kAudioObjectPropertyElementMaster = 0,
    kAudioObjectPropertyElementWildcard = 0xFFFFFFFF,
};
enum {
    kAudioHardwarePropertyDevices = 'dev#',
    kAudioHardwarePropertyDefaultInputDevice = 'dIn ',
    kAudioHardwarePropertyDefaultOutputDevice = 'dOut',
    kAudioHardwarePropertyDefaultSystemOutputDevice = 'sOut',
    kAudioObjectPropertyName = 'lnam',
    kAudioObjectPropertyManufacturer = 'lmak',
    kAudioDevicePropertyDeviceUID = 'uid ',
    kAudioDevicePropertyVolumeScalar = 'volm',
    kAudioDevicePropertyMute = 'mute',
    kAudioHardwareServiceDeviceProperty_VirtualMainVolume = 'vmvc',
    kAudioHardwareServiceDeviceProperty_VirtualMasterVolume = 'vmvc',
};

/* The default output device is 2 and the default input device 3. */
Boolean AudioObjectHasProperty(AudioObjectID objectID, const AudioObjectPropertyAddress *address);
OSStatus AudioObjectIsPropertySettable(AudioObjectID objectID, const AudioObjectPropertyAddress *address,
                                       Boolean *outIsSettable);
OSStatus AudioObjectGetPropertyDataSize(AudioObjectID objectID, const AudioObjectPropertyAddress *address,
                                        UInt32 qualifierDataSize, const void *qualifierData, UInt32 *outDataSize);
OSStatus AudioObjectGetPropertyData(AudioObjectID objectID, const AudioObjectPropertyAddress *address,
                                    UInt32 qualifierDataSize, const void *qualifierData, UInt32 *ioDataSize,
                                    void *outData);
OSStatus AudioObjectSetPropertyData(AudioObjectID objectID, const AudioObjectPropertyAddress *address,
                                    UInt32 qualifierDataSize, const void *qualifierData, UInt32 dataSize,
                                    const void *data);

__FERRY_END

#endif
