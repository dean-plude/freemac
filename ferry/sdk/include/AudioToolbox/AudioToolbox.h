/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: AudioToolbox.framework's umbrella (freemac 1.232; audio
 * units, audio queues, audio converters, Audio Format Services and the
 * hardware service's properties 1.234, Ferry 0.58.0). It brings in Core
 * Audio's audio objects, and Ferry's CoreAudio.framework serves
 * AudioToolbox. Written from Apple's public documentation; not Apple's
 * header. */
#ifndef _FERRY_AUDIOTOOLBOX_H_
#define _FERRY_AUDIOTOOLBOX_H_
#include <CoreAudioTypes/CoreAudioTypes.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioUnit.h>
#include <AudioToolbox/AUGraph.h>
#include <AudioToolbox/AudioQueue.h>
#include <AudioToolbox/AudioFormat.h>
#include <AudioToolbox/AudioConverter.h>
#include <AudioToolbox/AudioServices.h>
#endif
