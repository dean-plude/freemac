/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the parameters of Apple's audio units that Ferry has
 * (freemac 1.234, Ferry 0.58.0), written from Apple's public
 * documentation. Not Apple's header. */
#ifndef _FERRY_AUDIOUNITPARAMETERS_H_
#define _FERRY_AUDIOUNITPARAMETERS_H_

enum {
    /* the HAL output unit's volume, 0 to 1, in the global scope */
    kHALOutputParam_Volume = 14,
};

enum {
    kMultiChannelMixerParam_Volume = 0,
    kMultiChannelMixerParam_Enable = 1,
    kMultiChannelMixerParam_Pan = 2,
};

/* the peak limiter (freemac 1.NEXT) */
enum {
    kLimiterParam_AttackTime = 0,
    kLimiterParam_DecayTime = 1,
    kLimiterParam_PreGain = 2,
};

#endif
