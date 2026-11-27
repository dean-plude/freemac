/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: IOKit's power assertions (freemac 1.223, Ferry 0.47.0),
 * written from Apple's public IOPMLib documentation; not Apple's header.
 * Assertions are kept for the program, which IOPMCopyAssertionsByProcess
 * lists, but nothing on this system is told of them yet: the screen can
 * still sleep while one is held. The calls are served from Ferry's
 * Foundation (foundation/IOKit.m). */
#ifndef _FERRY_IOKIT_IOPMLIB_H_
#define _FERRY_IOKIT_IOPMLIB_H_
#include <IOKit/IOKitLib.h>
__FERRY_BEGIN

typedef uint32_t IOPMAssertionID;
typedef uint32_t IOPMAssertionLevel;
enum { kIOPMAssertionLevelOff = 0, kIOPMAssertionLevelOn = 255 };
#define kIOPMNullAssertionID ((IOPMAssertionID)0)

#define kIOPMAssertionTypeNoDisplaySleep CFSTR("NoDisplaySleepAssertion")
#define kIOPMAssertionTypeNoIdleSleep CFSTR("NoIdleSleepAssertion")
#define kIOPMAssertionTypePreventUserIdleDisplaySleep CFSTR("PreventUserIdleDisplaySleep")
#define kIOPMAssertionTypePreventUserIdleSystemSleep CFSTR("PreventUserIdleSystemSleep")
#define kIOPMAssertionTypePreventSystemSleep CFSTR("PreventSystemSleep")
#define kIOPMAssertPreventUserIdleDisplaySleep kIOPMAssertionTypePreventUserIdleDisplaySleep
#define kIOPMAssertPreventUserIdleSystemSleep kIOPMAssertionTypePreventUserIdleSystemSleep
#define kIOPMAssertionTypeKey CFSTR("AssertType")
#define kIOPMAssertionLevelKey CFSTR("AssertLevel")
#define kIOPMAssertionNameKey CFSTR("AssertName")
#define kIOPMAssertionDetailsKey CFSTR("Details")
#define kIOPMAssertionTimeoutKey CFSTR("TimeoutSeconds")

typedef enum { kIOPMUserActiveLocal = 0, kIOPMUserActiveRemote = 1 } IOPMUserActiveType;

IOReturn IOPMAssertionCreateWithName(CFStringRef assertionType, IOPMAssertionLevel assertionLevel,
                                     CFStringRef assertionName, IOPMAssertionID *assertionID);
IOReturn IOPMAssertionCreateWithDescription(CFStringRef assertionType, CFStringRef name, CFStringRef details,
                                            CFStringRef humanReadableReason, CFStringRef localizationBundlePath,
                                            CFTimeInterval timeout, CFStringRef timeoutAction,
                                            IOPMAssertionID *assertionID);
IOReturn IOPMAssertionCreate(CFStringRef assertionType, IOPMAssertionLevel assertionLevel,
                             IOPMAssertionID *assertionID);
IOReturn IOPMAssertionRelease(IOPMAssertionID assertionID);
IOReturn IOPMAssertionRetain(IOPMAssertionID assertionID);
IOReturn IOPMAssertionDeclareUserActivity(CFStringRef assertionName, IOPMUserActiveType userType,
                                          IOPMAssertionID *assertionID);
/* The program's assertions, keyed by its pid: an array of dictionaries with
 * the type, level and name keys above. */
IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *assertionsByPID);
IOReturn IOPMCopyAssertionsStatus(CFDictionaryRef *assertionsStatus);

/* System sleep and wake (freemac 1.265): registering works, and the
 * callback is never called. */
typedef void (*IOServiceInterestCallback)(void *refcon, io_service_t service, uint32_t messageType,
                                          void *messageArgument);
io_connect_t IORegisterForSystemPower(void *refcon, IONotificationPortRef *thePortRef,
                                      IOServiceInterestCallback callback, io_object_t *notifier);
IOReturn IODeregisterForSystemPower(io_object_t *notifier);
IOReturn IOAllowPowerChange(io_connect_t kernelPort, intptr_t notificationID);
IOReturn IOCancelPowerChange(io_connect_t kernelPort, intptr_t notificationID);
IOReturn IOPMCopyCPUPowerStatus(CFDictionaryRef *cpuPowerStatus);
IOReturn IOPMGetThermalWarningLevel(uint32_t *thermalLevel);
__FERRY_END
#endif
