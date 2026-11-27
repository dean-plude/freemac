/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * The Force Feedback framework's calls and the types they take (freemac
 * Godot work), written from Apple's public ForceFeedback reference; not
 * Apple's header. Ferry finds no force feedback devices (foundation/IOKit.m
 * serves the framework): FFIsForceFeedback answers no for every service. */
#ifndef _FERRY_FORCEFEEDBACK_H_
#define _FERRY_FORCEFEEDBACK_H_
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFPlugInCOM.h>

__FERRY_BEGIN
typedef void *FFDeviceObjectReference;
typedef void *FFEffectObjectReference;
typedef uint32_t FFCommandFlag, FFCooperativeLevelFlag, FFEffectStartFlag, FFEffectParameterFlag, FFState,
    FFEffectStatusFlag, FFProperty;
#ifndef _FERRY_IOBYTECOUNT_
#define _FERRY_IOBYTECOUNT_
typedef uintptr_t IOByteCount;
#endif

#define FF_OK ((HRESULT)0x00000000)
#define FFERR_UNSUPPORTED ((HRESULT)0x80004001)
#define FFERR_NOINTERFACE ((HRESULT)0x80000004)
#define FFERR_INVALIDPARAM ((HRESULT)0x80070057)
#define FFERR_OUTOFMEMORY ((HRESULT)0x80000002)
#define FFERR_GENERIC ((HRESULT)0x80000008)

typedef struct FFENVELOPE {
    uint32_t dwSize, dwAttackLevel, dwAttackTime, dwFadeLevel, dwFadeTime;
} FFENVELOPE;
typedef struct FFEFFECT {
    uint32_t dwSize, dwFlags, dwDuration, dwSamplePeriod, dwGain, dwTriggerButton, dwTriggerRepeatInterval, cAxes;
    uint32_t *rgdwAxes;
    int32_t *rglDirection;
    FFENVELOPE *lpEnvelope;
    uint32_t cbTypeSpecificParams;
    void *lpvTypeSpecificParams;
    uint32_t dwStartDelay;
} FFEFFECT;
typedef struct FFCAPABILITIES {
    struct { uint32_t major, minor, revision, build; } ffSpecVer;
    uint32_t supportedEffects, emulatedEffects, subType, numFfAxes;
    uint8_t ffAxes[32];
    uint32_t storageCapacity, playbackCapacity;
    struct { uint32_t major, minor, revision, build; } firmwareVer, hardwareVer, driverVer;
} FFCAPABILITIES;
typedef struct FFEFFESCAPE {
    uint32_t dwSize, dwCommand;
    void *lpvInBuffer;
    uint32_t cbInBuffer;
    void *lpvOutBuffer;
    uint32_t cbOutBuffer;
} FFEFFESCAPE;

HRESULT FFIsForceFeedback(io_service_t hidDevice);
HRESULT FFCreateDevice(io_service_t hidDevice, FFDeviceObjectReference *pDeviceReference);
HRESULT FFReleaseDevice(FFDeviceObjectReference deviceReference);
HRESULT FFDeviceCreateEffect(FFDeviceObjectReference deviceReference, CFUUIDRef uuidRef, FFEFFECT *pEffectDefinition,
                             FFEffectObjectReference *pEffectReference);
HRESULT FFDeviceReleaseEffect(FFDeviceObjectReference deviceReference, FFEffectObjectReference effectReference);
HRESULT FFDeviceGetForceFeedbackCapabilities(FFDeviceObjectReference deviceReference, FFCAPABILITIES *pFFCapabilities);
HRESULT FFDeviceGetForceFeedbackProperty(FFDeviceObjectReference deviceReference, FFProperty property, void *pValue,
                                         IOByteCount valueSize);
HRESULT FFDeviceSetForceFeedbackProperty(FFDeviceObjectReference deviceReference, FFProperty property, void *pValue);
HRESULT FFDeviceSendForceFeedbackCommand(FFDeviceObjectReference deviceReference, FFCommandFlag flags);
HRESULT FFDeviceGetForceFeedbackState(FFDeviceObjectReference deviceReference, FFState *pFFState);
HRESULT FFDeviceEscape(FFDeviceObjectReference deviceReference, FFEFFESCAPE *pFFEffectEscape);
HRESULT FFDeviceSetCooperativeLevel(FFDeviceObjectReference deviceReference, void *taskIdentifier,
                                    FFCooperativeLevelFlag flags);
HRESULT FFEffectDownload(FFEffectObjectReference effectReference);
HRESULT FFEffectEscape(FFEffectObjectReference effectReference, FFEFFESCAPE *pFFEffectEscape);
HRESULT FFEffectGetEffectStatus(FFEffectObjectReference effectReference, FFEffectStatusFlag *pFlags);
HRESULT FFEffectGetParameters(FFEffectObjectReference effectReference, FFEFFECT *pFFEffect, FFEffectParameterFlag flags);
HRESULT FFEffectSetParameters(FFEffectObjectReference effectReference, FFEFFECT *pFFEffect, FFEffectParameterFlag flags);
HRESULT FFEffectStart(FFEffectObjectReference effectReference, UInt32 iterations, FFEffectStartFlag flags);
HRESULT FFEffectStop(FFEffectObjectReference effectReference);
HRESULT FFEffectUnload(FFEffectObjectReference effectReference);
__FERRY_END
#endif
