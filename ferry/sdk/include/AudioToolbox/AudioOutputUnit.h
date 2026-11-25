/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: starting and stopping an output unit (freemac 1.234, Ferry
 * 0.58.0), written from Apple's public documentation. Not Apple's
 * header. */
#ifndef _FERRY_AUDIOOUTPUTUNIT_H_
#define _FERRY_AUDIOOUTPUTUNIT_H_
#include <AudioToolbox/AUComponent.h>

#ifdef __cplusplus
extern "C" {
#endif

OSStatus AudioOutputUnitStart(AudioUnit ci);
OSStatus AudioOutputUnitStop(AudioUnit ci);

enum {
    kAudioOutputUnitRange = 0x0200,
    kAudioOutputUnitStartSelect = 0x0201,
    kAudioOutputUnitStopSelect = 0x0202,
};

#ifdef __cplusplus
}
#endif
#endif
