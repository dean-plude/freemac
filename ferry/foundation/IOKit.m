/* SPDX-License-Identifier: GPL-3.0-or-later
 * The corner of IOKit that Cocoa apps and their frameworks link (freemac
 * 1.223, Ferry 0.47.0), served from Foundation as CoreServices is, and
 * written from Apple's public IOKit documentation: the registry, which
 * Ferry doesn't have (a search finds nothing), and power assertions, kept
 * for the program and listed back to it, but not passed on to this
 * system. The HID Manager and Force Feedback find no devices (freemac Godot
 * work). */
#import "FInternal.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/hid/IOHIDManager.h>
#include <string.h>
#include <unistd.h>
#include <ForceFeedback/ForceFeedback.h>

const mach_port_t kIOMasterPortDefault = 0;
const mach_port_t kIOMainPortDefault = 0;

/* ---- the registry ----------------------------------------------------------------- */

CFMutableDictionaryRef IOServiceMatching(const char *name)
{
    if (!name)
        return NULL;
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] initWithObjectsAndKeys:@(name), @"IOProviderClass", nil];
}
CFMutableDictionaryRef IOServiceNameMatching(const char *name)
{
    if (!name)
        return NULL;
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] initWithObjectsAndKeys:@(name), @"IONameMatch", nil];
}
/* Both consume the matching dictionary, as on a Mac. */
io_service_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching)
{
    if (matching)
        CFRelease(matching);
    return IO_OBJECT_NULL;
}
kern_return_t IOServiceGetMatchingServices(mach_port_t mainPort, CFDictionaryRef matching, io_iterator_t *existing)
{
    if (matching)
        CFRelease(matching);
    if (existing)
        *existing = IO_OBJECT_NULL;
    return kIOReturnSuccess;
}
io_object_t IOIteratorNext(io_iterator_t iterator) { return IO_OBJECT_NULL; }
boolean_t IOIteratorIsValid(io_iterator_t iterator) { return iterator == IO_OBJECT_NULL; }
kern_return_t IOObjectRelease(io_object_t object) { return object == IO_OBJECT_NULL ? kIOReturnSuccess : kIOReturnBadArgument; }
kern_return_t IOObjectRetain(io_object_t object) { return IOObjectRelease(object); }
io_registry_entry_t IORegistryEntryFromPath(mach_port_t mainPort, const io_string_t path) { return IO_OBJECT_NULL; }
io_registry_entry_t IORegistryGetRootEntry(mach_port_t mainPort) { return IO_OBJECT_NULL; }
CFTypeRef IORegistryEntryCreateCFProperty(io_registry_entry_t entry, CFStringRef key, CFAllocatorRef allocator,
                                          IOOptionBits options)
{
    return NULL;
}
CFTypeRef IORegistryEntrySearchCFProperty(io_registry_entry_t entry, const io_name_t plane, CFStringRef key,
                                          CFAllocatorRef allocator, IOOptionBits options)
{
    return NULL;
}

/* the null object has no class and conforms to none; there is no service
 * to open, so no connection to call (freemac 1.233, Ferry 0.57.0) */
boolean_t IOObjectConformsTo(io_object_t object, const io_name_t className) { return 0; }
kern_return_t IOObjectGetClass(io_object_t object, io_name_t className)
{
    if (!className)
        return kIOReturnBadArgument;
    className[0] = 0;
    return object == IO_OBJECT_NULL ? kIOReturnBadArgument : kIOReturnSuccess;
}
kern_return_t IOServiceOpen(io_service_t service, task_t owningTask, uint32_t type, io_connect_t *connect)
{
    if (connect)
        *connect = IO_OBJECT_NULL;
    return kIOReturnBadArgument;
}
kern_return_t IOServiceClose(io_connect_t connect) { return connect == IO_OBJECT_NULL ? kIOReturnBadArgument : kIOReturnSuccess; }
kern_return_t IOConnectCallScalarMethod(mach_port_t connection, uint32_t selector, const uint64_t *input,
                                        uint32_t inputCnt, uint64_t *output, uint32_t *outputCnt)
{
    if (outputCnt)
        *outputCnt = 0;
    return kIOReturnBadArgument;
}
CFMutableDictionaryRef IOBSDNameMatching(mach_port_t mainPort, uint32_t options, const char *bsdName)
{
    if (!bsdName)
        return NULL;
    return (CFMutableDictionaryRef)[[NSMutableDictionary alloc] initWithObjectsAndKeys:@(bsdName), @"BSD Name", nil];
}

/* ---- plug-ins: no service has one ------------------------------------------------- */

kern_return_t IOCreatePlugInInterfaceForService(io_service_t service, CFUUIDRef pluginType, CFUUIDRef interfaceType,
                                                IOCFPlugInInterface ***theInterface, SInt32 *theScore)
{
    if (theInterface)
        *theInterface = NULL;
    if (theScore)
        *theScore = 0;
    return kIOReturnUnsupported;
}
kern_return_t IODestroyPlugInInterface(IOCFPlugInInterface **interface)
{
    return interface ? kIOReturnSuccess : kIOReturnBadArgument;
}

/* ---- power assertions ------------------------------------------------------------- */

static NSMutableDictionary *assertions; /* id -> {type, level, name, count} */
static IOPMAssertionID next_id;

static IOReturn create(CFStringRef type, IOPMAssertionLevel level, CFStringRef name, IOPMAssertionID *out)
{
    if (!type || !out)
        return kIOReturnBadArgument;
    @synchronized([NSProcessInfo class]) {
        if (!assertions)
            assertions = [[NSMutableDictionary alloc] init];
        IOPMAssertionID n = ++next_id;
        assertions[@(n)] = [NSMutableDictionary dictionaryWithObjectsAndKeys:(id)type, (id)kIOPMAssertionTypeKey,
                                                @(level), (id)kIOPMAssertionLevelKey,
                                                (id)name ?: @"", (id)kIOPMAssertionNameKey, @1, @"count", nil];
        *out = n;
    }
    return kIOReturnSuccess;
}

IOReturn IOPMAssertionCreateWithName(CFStringRef type, IOPMAssertionLevel level, CFStringRef name, IOPMAssertionID *out)
{
    return create(type, level, name, out);
}
IOReturn IOPMAssertionCreateWithDescription(CFStringRef type, CFStringRef name, CFStringRef details,
                                            CFStringRef reason, CFStringRef bundlePath, CFTimeInterval timeout,
                                            CFStringRef timeoutAction, IOPMAssertionID *out)
{
    return create(type, kIOPMAssertionLevelOn, name, out);
}
IOReturn IOPMAssertionCreate(CFStringRef type, IOPMAssertionLevel level, IOPMAssertionID *out)
{
    return create(type, level, NULL, out);
}
IOReturn IOPMAssertionRetain(IOPMAssertionID n)
{
    @synchronized([NSProcessInfo class]) {
        NSMutableDictionary *a = assertions[@(n)];
        if (!a)
            return kIOReturnNotFound;
        a[@"count"] = @([a[@"count"] intValue] + 1);
    }
    return kIOReturnSuccess;
}
IOReturn IOPMAssertionRelease(IOPMAssertionID n)
{
    @synchronized([NSProcessInfo class]) {
        NSMutableDictionary *a = assertions[@(n)];
        if (!a)
            return kIOReturnNotFound;
        int count = [a[@"count"] intValue] - 1;
        if (count <= 0)
            [assertions removeObjectForKey:@(n)];
        else
            a[@"count"] = @(count);
    }
    return kIOReturnSuccess;
}
IOReturn IOPMAssertionDeclareUserActivity(CFStringRef name, IOPMUserActiveType userType, IOPMAssertionID *out)
{
    if (!out)
        return kIOReturnBadArgument;
    if (*out == kIOPMNullAssertionID)
        return create(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, name, out);
    return kIOReturnSuccess;
}
IOReturn IOPMCopyAssertionsByProcess(CFDictionaryRef *byPID)
{
    if (!byPID)
        return kIOReturnBadArgument;
    NSMutableArray *list = [NSMutableArray array];
    @synchronized([NSProcessInfo class]) {
        for (NSNumber *n in [[assertions allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
            NSMutableDictionary *a = [[assertions[n] mutableCopy] autorelease];
            [a removeObjectForKey:@"count"];
            [list addObject:a];
        }
    }
    *byPID = (CFDictionaryRef)[[NSDictionary alloc] initWithObjectsAndKeys:list, @(getpid()), nil];
    return kIOReturnSuccess;
}
IOReturn IOPMCopyAssertionsStatus(CFDictionaryRef *status)
{
    if (!status)
        return kIOReturnBadArgument;
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    @synchronized([NSProcessInfo class]) {
        for (NSDictionary *a in [assertions allValues]) {
            id type = a[(id)kIOPMAssertionTypeKey];
            if ([a[(id)kIOPMAssertionLevelKey] intValue] == kIOPMAssertionLevelOn)
                s[type] = @(kIOPMAssertionLevelOn);
            else if (!s[type])
                s[type] = @(kIOPMAssertionLevelOff);
        }
    }
    *status = (CFDictionaryRef)[s copy];
    return kIOReturnSuccess;
}

/* freemac's displays aren't IOKit services, so there is nothing to tell. */
CFDictionaryRef IODisplayCreateInfoDictionary(io_service_t framebuffer, IOOptionBits options)
{
    (void)framebuffer;
    (void)options;
    return NULL;
}

/* ---- power sources (freemac 1.262, for IINA) -------------------------------------- */

/* The batteries this system reports under /sys/class/power_supply, each
 * described with the keys Apple's IOPowerSources.h documents. */
static NSString *read_sys(NSString *dir, NSString *name)
{
    NSString *s = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:name]
                                            encoding:NSUTF8StringEncoding error:NULL];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL on_ac_power(void)
{
    NSString *base = @"/sys/class/power_supply";
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:NULL];
    BOOL battery = NO;
    for (NSString *n in names) {
        NSString *dir = [base stringByAppendingPathComponent:n];
        NSString *type = read_sys(dir, @"type");
        if ([type isEqualToString:@"Mains"] && [read_sys(dir, @"online") isEqualToString:@"1"])
            return YES;
        if ([type isEqualToString:@"Battery"])
            battery = YES;
    }
    return !battery;
}

CFTypeRef IOPSCopyPowerSourcesInfo(void)
{
    NSMutableArray *list = [NSMutableArray array];
    NSString *base = @"/sys/class/power_supply";
    BOOL ac = on_ac_power();
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:base error:NULL]) {
        NSString *dir = [base stringByAppendingPathComponent:n];
        if (![read_sys(dir, @"type") isEqualToString:@"Battery"])
            continue;
        NSString *cap = read_sys(dir, @"capacity");
        NSString *status = read_sys(dir, @"status");
        [list addObject:@{
            @"Name": n,
            @"Type": @"InternalBattery",
            @"Transport Type": @"Internal",
            @"Is Present": @YES,
            @"Current Capacity": @(cap ? [cap intValue] : 100),
            @"Max Capacity": @100,
            @"Is Charging": @([status isEqualToString:@"Charging"]),
            @"Power Source State": ac ? @"AC Power" : @"Battery Power",
        }];
    }
    return (CFTypeRef)[[NSDictionary alloc] initWithObjectsAndKeys:list, @"Sources", @(ac), @"AC", nil];
}

CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob)
{
    NSArray *list = [(NSDictionary *)blob objectForKey:@"Sources"];
    return (CFArrayRef)[(list ? list : @[]) copy];
}

CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps)
{
    (void)blob;
    return [(id)ps isKindOfClass:[NSDictionary class]] ? (CFDictionaryRef)ps : NULL;
}

CFStringRef IOPSGetProvidingPowerSourceType(CFTypeRef blob)
{
    BOOL ac = blob ? [[(NSDictionary *)blob objectForKey:@"AC"] boolValue] : on_ac_power();
    return (CFStringRef)(ac ? @"AC Power" : @"Battery Power");
}

/* ---- notification ports and user clients: freemac has no IOKit services to
 * send notices or take calls, so none come and calls aren't supported. */

typedef struct IONotificationPort *IONotificationPortRef;
struct IONotificationPort { int unused; };

IONotificationPortRef IONotificationPortCreate(mach_port_t mainPort)
{
    (void)mainPort;
    return calloc(1, sizeof(struct IONotificationPort));
}

void IONotificationPortDestroy(IONotificationPortRef notify) { free(notify); }

void IONotificationPortSetDispatchQueue(IONotificationPortRef notify, void *queue)
{
    (void)notify;
    (void)queue;
}

void *IONotificationPortGetRunLoopSource(IONotificationPortRef notify)
{
    (void)notify;
    return NULL;
}

mach_port_t IONotificationPortGetMachPort(IONotificationPortRef notify)
{
    (void)notify;
    return 0;
}

kern_return_t IOServiceAddInterestNotification(IONotificationPortRef notifyPort, io_service_t service,
                                               const char *interestType, void *callback, void *refCon,
                                               io_object_t *notification)
{
    (void)notifyPort; (void)service; (void)interestType; (void)callback; (void)refCon;
    if (notification)
        *notification = IO_OBJECT_NULL;
    return kIOReturnUnsupported;
}

kern_return_t IOServiceAddMatchingNotification(IONotificationPortRef notifyPort, const char *notificationType,
                                               CFDictionaryRef matching, void *callback, void *refCon,
                                               io_iterator_t *notification)
{
    (void)notifyPort; (void)notificationType; (void)callback; (void)refCon;
    if (matching)
        CFRelease(matching);
    if (notification)
        *notification = IO_OBJECT_NULL;
    return kIOReturnSuccess;
}

kern_return_t IOConnectCallMethod(io_connect_t connection, uint32_t selector, const uint64_t *input,
                                  uint32_t inputCnt, const void *inputStruct, size_t inputStructCnt,
                                  uint64_t *output, uint32_t *outputCnt, void *outputStruct,
                                  size_t *outputStructCnt)
{
    (void)connection; (void)selector; (void)input; (void)inputCnt; (void)inputStruct;
    (void)inputStructCnt; (void)output; (void)outputStruct;
    if (outputCnt)
        *outputCnt = 0;
    if (outputStructCnt)
        *outputStructCnt = 0;
    return kIOReturnUnsupported;
}

/* the old names of the main port call and a whole entry's properties (freemac
 * 1.263, Audacity): there is no registry entry, so no properties */
kern_return_t IOMasterPort(mach_port_t bootstrapPort, mach_port_t *mainPort)
{
    if (mainPort)
        *mainPort = 0;
    return kIOReturnSuccess;
}
kern_return_t IOMainPort(mach_port_t bootstrapPort, mach_port_t *mainPort) { return IOMasterPort(bootstrapPort, mainPort); }
kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry, CFMutableDictionaryRef *properties,
                                                CFAllocatorRef allocator, IOOptionBits options)
{
    if (properties)
        *properties = NULL;
    return kIOReturnBadArgument;
}

/* comparing objects, a parent and registry entry IDs (freemac Godot work):
 * with no registry the only object is the null one */
boolean_t IOObjectIsEqualTo(io_object_t object, io_object_t anObject) { return object == anObject; }
kern_return_t IORegistryEntryGetParentEntry(io_registry_entry_t entry, const io_name_t plane,
                                            io_registry_entry_t *parent)
{
    if (parent)
        *parent = IO_OBJECT_NULL;
    return kIOReturnNoDevice;
}
kern_return_t IORegistryEntryGetRegistryEntryID(io_registry_entry_t entry, uint64_t *entryID)
{
    if (entryID)
        *entryID = 0;
    return kIOReturnBadArgument;
}
CFMutableDictionaryRef IORegistryEntryIDMatching(uint64_t entryID)
{
    CFMutableDictionaryRef d =
        CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberSInt64Type, &entryID);
    CFDictionarySetValue(d, CFSTR("IORegistryEntryID"), n);
    CFRelease(n);
    return d;
}

/* ---- the HID Manager (freemac Godot work) -----------------------------------------
 * Written from Apple's IOHIDManager, IOHIDDevice, IOHIDElement and IOHIDValue
 * references. This system's game controllers, keyboards and mice reach a
 * program through its windows, not the I/O Kit, so a manager is a real
 * object (a dictionary of the properties it is given, which CFRetain and
 * CFRelease work on) that matches no devices: opening it succeeds, it
 * lists no devices and its callbacks never run. A program can only hand
 * the device, element and value calls an object that doesn't exist, so
 * they answer as for none. */

CFTypeID IOHIDManagerGetTypeID(void) { return CFDictionaryGetTypeID(); }
IOHIDManagerRef IOHIDManagerCreate(CFAllocatorRef allocator, IOOptionBits options)
{
    return (IOHIDManagerRef)CFDictionaryCreateMutable(allocator, 0, &kCFTypeDictionaryKeyCallBacks,
                                                      &kCFTypeDictionaryValueCallBacks);
}
IOReturn IOHIDManagerOpen(IOHIDManagerRef manager, IOOptionBits options)
{
    return manager ? kIOReturnSuccess : kIOReturnBadArgument;
}
IOReturn IOHIDManagerClose(IOHIDManagerRef manager, IOOptionBits options)
{
    return manager ? kIOReturnSuccess : kIOReturnBadArgument;
}
CFTypeRef IOHIDManagerGetProperty(IOHIDManagerRef manager, CFStringRef key)
{
    return manager && key ? CFDictionaryGetValue((CFDictionaryRef)manager, key) : NULL;
}
Boolean IOHIDManagerSetProperty(IOHIDManagerRef manager, CFStringRef key, CFTypeRef value)
{
    if (!manager || !key)
        return false;
    if (value)
        CFDictionarySetValue((CFMutableDictionaryRef)manager, key, value);
    else
        CFDictionaryRemoveValue((CFMutableDictionaryRef)manager, key);
    return true;
}
void IOHIDManagerScheduleWithRunLoop(IOHIDManagerRef manager, CFRunLoopRef runLoop, CFStringRef runLoopMode) {}
void IOHIDManagerUnscheduleFromRunLoop(IOHIDManagerRef manager, CFRunLoopRef runLoop, CFStringRef runLoopMode) {}
void IOHIDManagerSetDispatchQueue(IOHIDManagerRef manager, void *queue) {}
void IOHIDManagerActivate(IOHIDManagerRef manager) {}
void IOHIDManagerCancel(IOHIDManagerRef manager) {}
void IOHIDManagerSetDeviceMatching(IOHIDManagerRef manager, CFDictionaryRef matching) {}
void IOHIDManagerSetDeviceMatchingMultiple(IOHIDManagerRef manager, CFArrayRef multiple) {}
/* the reference: NULL when no devices match */
CFSetRef IOHIDManagerCopyDevices(IOHIDManagerRef manager) { return NULL; }
void IOHIDManagerRegisterDeviceMatchingCallback(IOHIDManagerRef manager, IOHIDDeviceCallback callback, void *context) {}
void IOHIDManagerRegisterDeviceRemovalCallback(IOHIDManagerRef manager, IOHIDDeviceCallback callback, void *context) {}
void IOHIDManagerRegisterInputValueCallback(IOHIDManagerRef manager, IOHIDValueCallback callback, void *context) {}
void IOHIDManagerRegisterInputReportCallback(IOHIDManagerRef manager, IOHIDReportCallback callback, void *context) {}
void IOHIDManagerSetInputValueMatching(IOHIDManagerRef manager, CFDictionaryRef matching) {}
void IOHIDManagerSetInputValueMatchingMultiple(IOHIDManagerRef manager, CFArrayRef multiple) {}

/* these type IDs belong to no object, as no device, element or value exists */
CFTypeID IOHIDDeviceGetTypeID(void) { return (CFTypeID)-3; }
CFTypeID IOHIDElementGetTypeID(void) { return (CFTypeID)-4; }
CFTypeID IOHIDValueGetTypeID(void) { return (CFTypeID)-5; }

IOHIDDeviceRef IOHIDDeviceCreate(CFAllocatorRef allocator, io_service_t service) { return NULL; }
io_service_t IOHIDDeviceGetService(IOHIDDeviceRef device) { return IO_OBJECT_NULL; }
IOReturn IOHIDDeviceOpen(IOHIDDeviceRef device, IOOptionBits options) { return kIOReturnNoDevice; }
IOReturn IOHIDDeviceClose(IOHIDDeviceRef device, IOOptionBits options) { return kIOReturnNoDevice; }
Boolean IOHIDDeviceConformsTo(IOHIDDeviceRef device, uint32_t usagePage, uint32_t usage) { return false; }
CFTypeRef IOHIDDeviceGetProperty(IOHIDDeviceRef device, CFStringRef key) { return NULL; }
Boolean IOHIDDeviceSetProperty(IOHIDDeviceRef device, CFStringRef key, CFTypeRef property) { return false; }
CFArrayRef IOHIDDeviceCopyMatchingElements(IOHIDDeviceRef device, CFDictionaryRef matching, IOOptionBits options)
{
    return NULL;
}
void IOHIDDeviceScheduleWithRunLoop(IOHIDDeviceRef device, CFRunLoopRef runLoop, CFStringRef runLoopMode) {}
void IOHIDDeviceUnscheduleFromRunLoop(IOHIDDeviceRef device, CFRunLoopRef runLoop, CFStringRef runLoopMode) {}
void IOHIDDeviceRegisterRemovalCallback(IOHIDDeviceRef device, IOHIDCallback callback, void *context) {}
void IOHIDDeviceRegisterInputValueCallback(IOHIDDeviceRef device, IOHIDValueCallback callback, void *context) {}
void IOHIDDeviceRegisterInputReportCallback(IOHIDDeviceRef device, uint8_t *report, CFIndex reportLength,
                                            IOHIDReportCallback callback, void *context)
{
}
IOReturn IOHIDDeviceSetValue(IOHIDDeviceRef device, IOHIDElementRef element, IOHIDValueRef value)
{
    return kIOReturnNoDevice;
}
IOReturn IOHIDDeviceGetValue(IOHIDDeviceRef device, IOHIDElementRef element, IOHIDValueRef *pValue)
{
    if (pValue)
        *pValue = NULL;
    return kIOReturnNoDevice;
}
IOReturn IOHIDDeviceSetReport(IOHIDDeviceRef device, IOHIDReportType reportType, CFIndex reportID,
                              const uint8_t *report, CFIndex reportLength)
{
    return kIOReturnNoDevice;
}
IOReturn IOHIDDeviceGetReport(IOHIDDeviceRef device, IOHIDReportType reportType, CFIndex reportID,
                              uint8_t *report, CFIndex *pReportLength)
{
    if (pReportLength)
        *pReportLength = 0;
    return kIOReturnNoDevice;
}

IOHIDDeviceRef IOHIDElementGetDevice(IOHIDElementRef element) { return NULL; }
IOHIDElementRef IOHIDElementGetParent(IOHIDElementRef element) { return NULL; }
CFArrayRef IOHIDElementGetChildren(IOHIDElementRef element) { return NULL; }
IOHIDElementCookie IOHIDElementGetCookie(IOHIDElementRef element) { return 0; }
IOHIDElementType IOHIDElementGetType(IOHIDElementRef element) { return 0; }
uint32_t IOHIDElementGetUsagePage(IOHIDElementRef element) { return 0; }
uint32_t IOHIDElementGetUsage(IOHIDElementRef element) { return 0; }
CFIndex IOHIDElementGetLogicalMin(IOHIDElementRef element) { return 0; }
CFIndex IOHIDElementGetLogicalMax(IOHIDElementRef element) { return 0; }
CFIndex IOHIDElementGetPhysicalMin(IOHIDElementRef element) { return 0; }
CFIndex IOHIDElementGetPhysicalMax(IOHIDElementRef element) { return 0; }
CFStringRef IOHIDElementGetName(IOHIDElementRef element) { return NULL; }

IOHIDElementRef IOHIDValueGetElement(IOHIDValueRef value) { return NULL; }
uint64_t IOHIDValueGetTimeStamp(IOHIDValueRef value) { return 0; }
CFIndex IOHIDValueGetIntegerValue(IOHIDValueRef value) { return 0; }
double IOHIDValueGetScaledValue(IOHIDValueRef value, uint32_t type) { return 0; }
CFIndex IOHIDValueGetLength(IOHIDValueRef value) { return 0; }
const uint8_t *IOHIDValueGetBytePtr(IOHIDValueRef value) { return NULL; }

/* ---- Force Feedback (freemac Godot work) -------------------------------------------
 * Written from Apple's ForceFeedback framework reference. A device comes
 * from an I/O Kit service, and with no registry there is none, so no
 * service is a force feedback device and the calls on a device or an
 * effect are refused. */

HRESULT FFIsForceFeedback(io_service_t hidDevice) { return FFERR_NOINTERFACE; }
HRESULT FFCreateDevice(io_service_t hidDevice, FFDeviceObjectReference *pDeviceReference)
{
    if (pDeviceReference)
        *pDeviceReference = NULL;
    return FFERR_NOINTERFACE;
}
HRESULT FFReleaseDevice(FFDeviceObjectReference deviceReference) { return FFERR_INVALIDPARAM; }
HRESULT FFDeviceCreateEffect(FFDeviceObjectReference deviceReference, CFUUIDRef uuidRef, FFEFFECT *pEffectDefinition,
                             FFEffectObjectReference *pEffectReference)
{
    if (pEffectReference)
        *pEffectReference = NULL;
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceReleaseEffect(FFDeviceObjectReference deviceReference, FFEffectObjectReference effectReference)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceGetForceFeedbackCapabilities(FFDeviceObjectReference deviceReference, FFCAPABILITIES *pFFCapabilities)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceGetForceFeedbackProperty(FFDeviceObjectReference deviceReference, FFProperty property, void *pValue,
                                         IOByteCount valueSize)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceSetForceFeedbackProperty(FFDeviceObjectReference deviceReference, FFProperty property, void *pValue)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceSendForceFeedbackCommand(FFDeviceObjectReference deviceReference, FFCommandFlag flags)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceGetForceFeedbackState(FFDeviceObjectReference deviceReference, FFState *pFFState)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceEscape(FFDeviceObjectReference deviceReference, FFEFFESCAPE *pFFEffectEscape)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFDeviceSetCooperativeLevel(FFDeviceObjectReference deviceReference, void *taskIdentifier, FFCooperativeLevelFlag flags)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFEffectDownload(FFEffectObjectReference effectReference) { return FFERR_INVALIDPARAM; }
HRESULT FFEffectEscape(FFEffectObjectReference effectReference, FFEFFESCAPE *pFFEffectEscape) { return FFERR_INVALIDPARAM; }
HRESULT FFEffectGetEffectStatus(FFEffectObjectReference effectReference, FFEffectStatusFlag *pFlags)
{
    if (pFlags)
        *pFlags = 0;
    return FFERR_INVALIDPARAM;
}
HRESULT FFEffectGetParameters(FFEffectObjectReference effectReference, FFEFFECT *pFFEffect, FFEffectParameterFlag flags)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFEffectSetParameters(FFEffectObjectReference effectReference, FFEFFECT *pFFEffect, FFEffectParameterFlag flags)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFEffectStart(FFEffectObjectReference effectReference, UInt32 iterations, FFEffectStartFlag flags)
{
    return FFERR_INVALIDPARAM;
}
HRESULT FFEffectStop(FFEffectObjectReference effectReference) { return FFERR_INVALIDPARAM; }
HRESULT FFEffectUnload(FFEffectObjectReference effectReference) { return FFERR_INVALIDPARAM; }
