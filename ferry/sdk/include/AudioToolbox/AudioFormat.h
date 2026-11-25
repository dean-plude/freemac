/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Audio Format Services (freemac 1.234, Ferry 0.58.0), written
 * from Apple's public documentation of AudioFormat. Ferry answers the
 * channel layout properties (layouts for tags and bitmaps, a layout's
 * channel count, tag and bitmap) and fills in linear PCM descriptions.
 * Not Apple's header. */
#ifndef _FERRY_AUDIOFORMAT_H_
#define _FERRY_AUDIOFORMAT_H_
#include <CoreAudioTypes/CoreAudioTypes.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef UInt32 AudioFormatPropertyID;

enum {
    kAudioFormatProperty_FormatInfo = 'fmti',
    kAudioFormatProperty_FormatName = 'fnam',
    kAudioFormatProperty_EncodeFormatIDs = 'acof',
    kAudioFormatProperty_DecodeFormatIDs = 'acif',
    kAudioFormatProperty_FormatList = 'flst',
    kAudioFormatProperty_ASBDFromESDS = 'essd',
    kAudioFormatProperty_ChannelLayoutFromESDS = 'escl',
    kAudioFormatProperty_OutputFormatList = 'ofls',
    kAudioFormatProperty_FirstPlayableFormatFromList = 'fpfl',
    kAudioFormatProperty_FormatIsVBR = 'fvbr',
    kAudioFormatProperty_FormatIsExternallyFramed = 'fexf',
    kAudioFormatProperty_FormatIsEncrypted = 'cryp',
    kAudioFormatProperty_Encoders = 'aven',
    kAudioFormatProperty_Decoders = 'avde',
    kAudioFormatProperty_AvailableEncodeBitRates = 'aebr',
    kAudioFormatProperty_AvailableEncodeSampleRates = 'aesr',
    kAudioFormatProperty_AvailableEncodeChannelLayoutTags = 'aecl',
    kAudioFormatProperty_AvailableEncodeNumberChannels = 'avnc',
    kAudioFormatProperty_AvailableDecodeNumberChannels = 'adnc',
    kAudioFormatProperty_ASBDFromMPEGPacket = 'admp',
    kAudioFormatProperty_BitmapForLayoutTag = 'bmtg',
    kAudioFormatProperty_MatrixMixMap = 'mmap',
    kAudioFormatProperty_ChannelMap = 'chmp',
    kAudioFormatProperty_NumberOfChannelsForLayout = 'nchm',
    kAudioFormatProperty_AreChannelLayoutsEquivalent = 'cheq',
    kAudioFormatProperty_ChannelLayoutHash = 'chha',
    kAudioFormatProperty_ValidateChannelLayout = 'vacl',
    kAudioFormatProperty_ChannelLayoutForTag = 'cmpl',
    kAudioFormatProperty_TagForChannelLayout = 'cmpt',
    kAudioFormatProperty_ChannelLayoutName = 'lonm',
    kAudioFormatProperty_ChannelLayoutSimpleName = 'lsnm',
    kAudioFormatProperty_ChannelLayoutForBitmap = 'cmpb',
    kAudioFormatProperty_ChannelName = 'cnam',
    kAudioFormatProperty_ChannelShortName = 'csnm',
    kAudioFormatProperty_TagsForNumberOfChannels = 'tagc',
    kAudioFormatProperty_PanningMatrix = 'panm',
    kAudioFormatProperty_BalanceFade = 'balf',
    kAudioFormatProperty_ID3TagSize = 'id3s',
    kAudioFormatProperty_ID3TagToDictionary = 'id3d',
};

enum {
    kAudioFormatUnspecifiedError = 'what',
    kAudioFormatUnsupportedPropertyError = 'prop',
    kAudioFormatBadPropertySizeError = '!siz',
    kAudioFormatBadSpecifierSizeError = '!spc',
    kAudioFormatUnsupportedDataFormatError = 'fmt?',
    kAudioFormatUnknownFormatError = '!fmt',
};

OSStatus AudioFormatGetPropertyInfo(AudioFormatPropertyID inPropertyID, UInt32 inSpecifierSize,
                                    const void *inSpecifier, UInt32 *outPropertyDataSize);
OSStatus AudioFormatGetProperty(AudioFormatPropertyID inPropertyID, UInt32 inSpecifierSize, const void *inSpecifier,
                                UInt32 *ioPropertyDataSize, void *outPropertyData);

#ifdef __cplusplus
}
#endif
#endif
