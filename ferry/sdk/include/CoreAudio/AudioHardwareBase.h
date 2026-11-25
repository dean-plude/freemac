/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Core Audio HAL's object model (freemac 1.234, Ferry
 * 0.58.0), written from Apple's public documentation of AudioHardwareBase:
 * objects, property addresses, classes, and the property selectors of
 * objects, devices and streams. Not Apple's header. */
#ifndef _FERRY_AUDIOHARDWAREBASE_H_
#define _FERRY_AUDIOHARDWAREBASE_H_
#include <CoreAudioTypes/CoreAudioTypes.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef UInt32 AudioObjectID;
typedef UInt32 AudioClassID;
typedef UInt32 AudioObjectPropertySelector;
typedef UInt32 AudioObjectPropertyScope;
typedef UInt32 AudioObjectPropertyElement;

typedef struct AudioObjectPropertyAddress {
    AudioObjectPropertySelector mSelector;
    AudioObjectPropertyScope mScope;
    AudioObjectPropertyElement mElement;
} AudioObjectPropertyAddress;

enum {
    kAudioHardwareNoError = 0,
    kAudioHardwareNotRunningError = 'stop',
    kAudioHardwareUnspecifiedError = 'what',
    kAudioHardwareUnknownPropertyError = 'who?',
    kAudioHardwareBadPropertySizeError = '!siz',
    kAudioHardwareIllegalOperationError = 'nope',
    kAudioHardwareBadObjectError = '!obj',
    kAudioHardwareBadDeviceError = '!dev',
    kAudioHardwareBadStreamError = '!str',
    kAudioHardwareUnsupportedOperationError = 'unop',
    kAudioHardwareNotReadyError = 'nrdy',
    kAudioDeviceUnsupportedFormatError = '!dat',
    kAudioDevicePermissionsError = '!hog',
};

enum {
    kAudioObjectUnknown = 0,
};

enum {
    kAudioObjectPropertyScopeGlobal = 'glob',
    kAudioObjectPropertyScopeInput = 'inpt',
    kAudioObjectPropertyScopeOutput = 'outp',
    kAudioObjectPropertyScopePlayThrough = 'ptru',
    kAudioObjectPropertyElementMain = 0,
    kAudioObjectPropertyElementMaster = kAudioObjectPropertyElementMain,
};

enum {
    kAudioObjectPropertySelectorWildcard = '****',
    kAudioObjectPropertyScopeWildcard = '****',
    kAudioObjectPropertyElementWildcard = 0xFFFFFFFF,
    kAudioObjectClassIDWildcard = '****',
};

/* ---- classes ---- */
enum {
    kAudioObjectClassID = 'aobj',
    kAudioPlugInClassID = 'aplg',
    kAudioTransportManagerClassID = 'trpm',
    kAudioBoxClassID = 'abox',
    kAudioDeviceClassID = 'adev',
    kAudioClockDeviceClassID = 'aclk',
    kAudioEndPointDeviceClassID = 'edev',
    kAudioEndPointClassID = 'endp',
    kAudioStreamClassID = 'astr',
    kAudioControlClassID = 'actl',
    kAudioSliderControlClassID = 'sldr',
    kAudioLevelControlClassID = 'levl',
    kAudioVolumeControlClassID = 'vlme',
    kAudioBooleanControlClassID = 'togl',
    kAudioMuteControlClassID = 'mute',
    kAudioSelectorControlClassID = 'slct',
    kAudioDataSourceControlClassID = 'dsrc',
    kAudioStereoPanControlClassID = 'span',
};

/* ---- every object's properties ---- */
enum {
    kAudioObjectPropertyBaseClass = 'bcls',
    kAudioObjectPropertyClass = 'clas',
    kAudioObjectPropertyOwner = 'stdv',
    kAudioObjectPropertyName = 'lnam',
    kAudioObjectPropertyModelName = 'lmod',
    kAudioObjectPropertyManufacturer = 'lmak',
    kAudioObjectPropertyElementName = 'lchn',
    kAudioObjectPropertyElementCategoryName = 'lccn',
    kAudioObjectPropertyElementNumberName = 'lcnn',
    kAudioObjectPropertyOwnedObjects = 'ownd',
    kAudioObjectPropertyIdentify = 'iden',
    kAudioObjectPropertySerialNumber = 'snum',
    kAudioObjectPropertyFirmwareVersion = 'fwvn',
};

/* ---- devices ---- */
enum {
    kAudioDeviceTransportTypeUnknown = 0,
    kAudioDeviceTransportTypeBuiltIn = 'bltn',
    kAudioDeviceTransportTypeAggregate = 'grup',
    kAudioDeviceTransportTypeVirtual = 'virt',
    kAudioDeviceTransportTypePCI = 'pci ',
    kAudioDeviceTransportTypeUSB = 'usb ',
    kAudioDeviceTransportTypeFireWire = '1394',
    kAudioDeviceTransportTypeBluetooth = 'blue',
    kAudioDeviceTransportTypeBluetoothLE = 'blea',
    kAudioDeviceTransportTypeHDMI = 'hdmi',
    kAudioDeviceTransportTypeDisplayPort = 'dprt',
    kAudioDeviceTransportTypeAirPlay = 'airp',
    kAudioDeviceTransportTypeAVB = 'eavb',
    kAudioDeviceTransportTypeThunderbolt = 'thun',
    kAudioDeviceTransportTypeContinuityCaptureWired = 'ccwd',
    kAudioDeviceTransportTypeContinuityCaptureWireless = 'ccwl',
};

enum {
    kAudioDevicePropertyConfigurationApplication = 'capp',
    kAudioDevicePropertyDeviceUID = 'uid ',
    kAudioDevicePropertyModelUID = 'muid',
    kAudioDevicePropertyTransportType = 'tran',
    kAudioDevicePropertyRelatedDevices = 'akin',
    kAudioDevicePropertyClockDomain = 'clkd',
    kAudioDevicePropertyDeviceIsAlive = 'livn',
    kAudioDevicePropertyDeviceIsRunning = 'goin',
    kAudioDevicePropertyDeviceCanBeDefaultDevice = 'dflt',
    kAudioDevicePropertyDeviceCanBeDefaultSystemDevice = 'sflt',
    kAudioDevicePropertyLatency = 'ltnc',
    kAudioDevicePropertyStreams = 'stm#',
    kAudioObjectPropertyControlList = 'ctrl',
    kAudioDevicePropertySafetyOffset = 'saft',
    kAudioDevicePropertyNominalSampleRate = 'nsrt',
    kAudioDevicePropertyAvailableNominalSampleRates = 'nsr#',
    kAudioDevicePropertyIcon = 'icon',
    kAudioDevicePropertyIsHidden = 'hidn',
    kAudioDevicePropertyPreferredChannelsForStereo = 'dch2',
    kAudioDevicePropertyPreferredChannelLayout = 'srnd',
};

/* ---- streams ---- */
enum {
    kAudioStreamTerminalTypeUnknown = 0,
    kAudioStreamTerminalTypeLine = 'line',
    kAudioStreamTerminalTypeDigitalAudioInterface = 'spdf',
    kAudioStreamTerminalTypeSpeaker = 'spkr',
    kAudioStreamTerminalTypeHeadphones = 'hdph',
    kAudioStreamTerminalTypeLFESpeaker = 'lfes',
    kAudioStreamTerminalTypeReceiverSpeaker = 'rspk',
    kAudioStreamTerminalTypeMicrophone = 'micr',
    kAudioStreamTerminalTypeHeadsetMicrophone = 'hmic',
    kAudioStreamTerminalTypeReceiverMicrophone = 'rmic',
    kAudioStreamTerminalTypeTTY = 'tty_',
    kAudioStreamTerminalTypeHDMI = 'hdmi',
    kAudioStreamTerminalTypeDisplayPort = 'dprt',
};

enum {
    kAudioStreamPropertyIsActive = 'sact',
    kAudioStreamPropertyDirection = 'sdir',
    kAudioStreamPropertyTerminalType = 'term',
    kAudioStreamPropertyStartingChannel = 'schn',
    kAudioStreamPropertyLatency = kAudioDevicePropertyLatency,
    kAudioStreamPropertyVirtualFormat = 'sfmt',
    kAudioStreamPropertyAvailableVirtualFormats = 'sfma',
    kAudioStreamPropertyPhysicalFormat = 'pft ',
    kAudioStreamPropertyAvailablePhysicalFormats = 'pfta',
};

/* ---- controls ---- */
enum {
    kAudioControlPropertyScope = 'cscp',
    kAudioControlPropertyElement = 'celm',
    kAudioLevelControlPropertyScalarValue = 'lcsv',
    kAudioLevelControlPropertyDecibelValue = 'lcdv',
    kAudioLevelControlPropertyDecibelRange = 'lcdr',
    kAudioBooleanControlPropertyValue = 'bcvl',
};

#ifdef __cplusplus
}
#endif
#endif
