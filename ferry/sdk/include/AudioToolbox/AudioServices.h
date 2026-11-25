/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Audio Hardware Services (freemac 1.234, Ferry 0.58.0), the
 * part of Audio Services that reads and sets a device's volume as one
 * control (its "virtual main volume"), whatever its channels. Written from
 * Apple's public documentation of AudioServices; not Apple's header.
 * Ferry's devices answer these properties through AudioObject's calls too. */
#ifndef _FERRY_AUDIOSERVICES_H_
#define _FERRY_AUDIOSERVICES_H_
#include <CoreAudio/CoreAudio.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    kAudioHardwareServiceProperty_ServiceRestarted = 'srst',
    kAudioHardwareServiceDeviceProperty_VirtualMainVolume = 'vmvc',
    kAudioHardwareServiceDeviceProperty_VirtualMasterVolume = 'vmvc',
    kAudioHardwareServiceDeviceProperty_VirtualMainBalance = 'vmbc',
    kAudioHardwareServiceDeviceProperty_VirtualMasterBalance = 'vmbc',
};

Boolean AudioHardwareServiceHasProperty(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress);
OSStatus AudioHardwareServiceIsPropertySettable(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                                Boolean *outIsSettable);
OSStatus AudioHardwareServiceGetPropertyDataSize(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                                 UInt32 inQualifierDataSize, const void *inQualifierData,
                                                 UInt32 *outDataSize);
OSStatus AudioHardwareServiceGetPropertyData(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                             UInt32 inQualifierDataSize, const void *inQualifierData,
                                             UInt32 *ioDataSize, void *outData);
OSStatus AudioHardwareServiceSetPropertyData(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                             UInt32 inQualifierDataSize, const void *inQualifierData,
                                             UInt32 inDataSize, const void *inData);
OSStatus AudioHardwareServiceAddPropertyListener(AudioObjectID inObjectID, const AudioObjectPropertyAddress *inAddress,
                                                 AudioObjectPropertyListenerProc inListener, void *inClientData);
OSStatus AudioHardwareServiceRemovePropertyListener(AudioObjectID inObjectID,
                                                    const AudioObjectPropertyAddress *inAddress,
                                                    AudioObjectPropertyListenerProc inListener, void *inClientData);

#ifdef __cplusplus
}
#endif
#endif
