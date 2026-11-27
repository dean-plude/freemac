/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: music devices (freemac 1.NEXT), the audio units that play
 * notes: MIDI events and system-exclusive messages sent to a synth unit,
 * notes started and stopped by number, and the synth's sound bank. Written
 * from Apple's public documentation of MusicDevice.h; not Apple's header.
 * Ferry's DLS and MIDI synth units play with this system's FluidSynth and
 * a General MIDI SoundFont (coreaudio/CAMusicDevice.m). */
#ifndef _FERRY_MUSICDEVICE_H_
#define _FERRY_MUSICDEVICE_H_
#include <AudioToolbox/AUComponent.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef UInt32 MusicDeviceInstrumentID;
typedef UInt32 MusicDeviceGroupID;
typedef UInt32 NoteInstanceID;
typedef AudioComponentInstance MusicDeviceComponent;

typedef struct MusicDeviceStdNoteParams {
    UInt32 argCount;
    Float32 mPitch;
    Float32 mVelocity;
} MusicDeviceStdNoteParams;

typedef struct NoteParamsControlValue {
    AudioUnitParameterID mID;
    AudioUnitParameterValue mValue;
} NoteParamsControlValue;

typedef struct MusicDeviceNoteParams {
    UInt32 argCount;
    Float32 mPitch;
    Float32 mVelocity;
    NoteParamsControlValue mControls[1];
} MusicDeviceNoteParams;

enum {
    kMusicNoteEvent_UseGroupInstrument = 0xFFFFFFFF,
    kMusicNoteEvent_Unused = 0xFFFFFFFF,
};

/* the selectors of a music device's calls, which a plug-in's Lookup is asked for */
enum {
    kMusicDeviceRange = 0x0100,
    kMusicDeviceMIDIEventSelect = 0x0101,
    kMusicDeviceSysExSelect = 0x0102,
    kMusicDevicePrepareInstrumentSelect = 0x0103,
    kMusicDeviceReleaseInstrumentSelect = 0x0104,
    kMusicDeviceStartNoteSelect = 0x0105,
    kMusicDeviceStopNoteSelect = 0x0106,
};

/* a music device's properties */
enum {
    kMusicDeviceProperty_InstrumentCount = 1000,
    kMusicDeviceProperty_BankName = 1007,
    kMusicDeviceProperty_SoundBankURL = 1100,
    kAUMIDISynthProperty_EnablePreload = 4119,
};

OSStatus MusicDeviceMIDIEvent(MusicDeviceComponent inUnit, UInt32 inStatus, UInt32 inData1, UInt32 inData2,
                              UInt32 inOffsetSampleFrame);
OSStatus MusicDeviceSysEx(MusicDeviceComponent inUnit, const UInt8 *inData, UInt32 inLength);
OSStatus MusicDeviceStartNote(MusicDeviceComponent inUnit, MusicDeviceInstrumentID inInstrument,
                              MusicDeviceGroupID inGroupID, NoteInstanceID *outNoteInstanceID,
                              UInt32 inOffsetSampleFrame, const MusicDeviceNoteParams *inParams);
OSStatus MusicDeviceStopNote(MusicDeviceComponent inUnit, MusicDeviceGroupID inGroupID,
                             NoteInstanceID inNoteInstanceID, UInt32 inOffsetSampleFrame);

#ifdef __cplusplus
}
#endif
#endif
