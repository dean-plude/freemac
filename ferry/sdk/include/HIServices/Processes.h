/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Process Manager, written from Apple's public "Process
 * Manager Reference". An app sees one process, itself: GetNextProcess lists
 * it and then answers procNotFound, GetProcessInformation describes it, and
 * launching another application answers procNotFound (freemac keeps no
 * register of Mac applications). Served from AppKit's file, through
 * Carbon and ApplicationServices. */
#ifndef _FERRY_HISERVICES_PROCESSES_H_
#define _FERRY_HISERVICES_PROCESSES_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <unistd.h>

__FERRY_BEGIN
#ifndef _FERRY_PSN_DEFINED
#define _FERRY_PSN_DEFINED
typedef struct ProcessSerialNumber {
    UInt32 highLongOfPSN;
    UInt32 lowLongOfPSN;
} ProcessSerialNumber;
typedef ProcessSerialNumber *ProcessSerialNumberPtr;
enum { kNoProcess = 0, kSystemProcess = 1, kCurrentProcess = 2 };
#endif
#ifndef _FERRY_PROCNOTFOUND
#define _FERRY_PROCNOTFOUND
enum { procNotFound = -600 };
#endif
enum { appIsDaemon = -606, appMemFullErr = -108 };

typedef uint16_t LaunchFlags;
enum {
    launchContinue = 0x4000, launchNoFileFlags = 0x0800, launchUseMinimum = 0x0400, launchDontSwitch = 0x0200,
    launchAllow24Bit = 0x0100, launchInhibitDaemon = 0x0080,
};
enum { extendedBlock = 0x4C43, extendedBlockLen = 40 };
enum {
    modeReserved = 0x01000000, modeControlPanel = 0x00080000, modeLaunchDontSwitch = 0x00040000,
    modeDeskAccessory = 0x00020000, modeMultiLaunch = 0x00010000, modeNeedSuspendResume = 0x00004000,
    modeCanBackground = 0x00001000, modeDoesActivateOnFGSwitch = 0x00000800, modeOnlyBackground = 0x00000400,
    modeGetFrontClicks = 0x00000200, modeGetAppDiedMsg = 0x00000100, mode32BitCompatible = 0x00000080,
    modeHighLevelEventAware = 0x00000040, modeLocalAndRemoteHLEvents = 0x00000020,
    modeStationeryAware = 0x00000010, modeUseTextEditServices = 0x00000008, modeDisplayManagerAware = 0x00000004,
};
enum {
    kProcessTransformToForegroundApplication = 1, kProcessTransformToBackgroundApplication = 2,
    kProcessTransformToUIElementApplication = 4,
};
enum {
    kProcessDictionaryIncludeAllInformationMask = (int)0xFFFFFFFF,
};

typedef struct LaunchParamBlockRec {
    UInt32 reserved1;
    UInt16 reserved2;
    UInt16 launchBlockID;
    UInt32 launchEPBLength;
    UInt16 launchFileFlags;
    LaunchFlags launchControlFlags;
    ProcessSerialNumber launchProcessSN;
    UInt32 launchPreferredSize;
    UInt32 launchMinimumSize;
    UInt32 launchAvailableSize;
    void *launchAppParameters;
} LaunchParamBlockRec;
typedef LaunchParamBlockRec *LaunchPBPtr;

typedef struct ProcessInfoRec {
    UInt32 processInfoLength;
    StringPtr processName;
    ProcessSerialNumber processNumber;
    UInt32 processType;
    OSType processSignature;
    UInt32 processMode;
    Ptr processLocation;
    UInt32 processSize;
    UInt32 processFreeMem;
    ProcessSerialNumber processLauncher;
    UInt32 processLaunchDate;
    UInt32 processActiveTime;
    FSRef *processAppRef;
} ProcessInfoRec;
typedef ProcessInfoRec *ProcessInfoRecPtr;

OSErr GetCurrentProcess(ProcessSerialNumber *PSN);
OSErr GetFrontProcess(ProcessSerialNumber *PSN);
OSErr GetNextProcess(ProcessSerialNumber *PSN);
OSErr GetProcessInformation(const ProcessSerialNumber *PSN, ProcessInfoRec *info);
OSStatus GetProcessPID(const ProcessSerialNumber *psn, pid_t *pid);
OSStatus GetProcessForPID(pid_t pid, ProcessSerialNumber *psn);
OSErr SameProcess(const ProcessSerialNumber *PSN1, const ProcessSerialNumber *PSN2, Boolean *result);
OSErr SetFrontProcess(const ProcessSerialNumber *PSN);
OSErr SetFrontProcessWithOptions(const ProcessSerialNumber *inProcess, OptionBits inOptions);
OSErr ShowHideProcess(const ProcessSerialNumber *psn, Boolean visible);
Boolean IsProcessVisible(const ProcessSerialNumber *psn);
OSStatus TransformProcessType(const ProcessSerialNumber *psn, UInt32 transformState);
OSStatus CopyProcessName(const ProcessSerialNumber *psn, CFStringRef *name);
CFDictionaryRef ProcessInformationCopyDictionary(const ProcessSerialNumber *PSN, UInt32 infoToReturn)
    CF_RETURNS_RETAINED;
OSErr LaunchApplication(LaunchPBPtr LaunchParams);
OSErr KillProcess(const ProcessSerialNumber *inProcess);
__FERRY_END
#endif
