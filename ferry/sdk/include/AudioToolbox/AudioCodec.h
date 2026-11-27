/* SPDX-License-Identifier: GPL-3.0-or-later
 * The audio codec properties an AudioConverter that encodes takes
 * (freemac 1.264), as Apple's AudioCodec.h reference names them. Ferry's
 * converters encode AAC, ALAC, FLAC and Opus with this system's FFmpeg. */
#ifndef _FERRY_AUDIOTOOLBOX_AUDIOCODEC_H_
#define _FERRY_AUDIOTOOLBOX_AUDIOCODEC_H_
#include <CoreAudioTypes/CoreAudioTypes.h>

enum {
    kAudioCodecPropertyBitRateControlMode = 'acbf',
    kAudioCodecPropertySoundQualityForVBR = 'vbrq',
    kAudioCodecPropertyBitRateForVBR = 'vbrb',
    kAudioCodecPropertyQualitySetting = 'srcq',
    kAudioCodecPropertyCurrentTargetBitRate = 'brat',
    kAudioCodecPropertyMaximumPacketByteSize = 'maxp',
    kAudioCodecPropertyPacketFrameSize = 'pakf',
    kAudioCodecPropertyPrimeInfo = 'prim',
};

enum {
    kAudioCodecBitRateControlMode_Constant = 0,
    kAudioCodecBitRateControlMode_LongTermAverage = 1,
    kAudioCodecBitRateControlMode_VariableConstrained = 2,
    kAudioCodecBitRateControlMode_Variable = 3,
};

#endif
