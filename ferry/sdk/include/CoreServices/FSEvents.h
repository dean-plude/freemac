/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: FSEvents (freemac 1.222, Ferry 0.46.0), the file system
 * change notifications Gas Mask and others watch folders with. Written for
 * freemac from Apple's public documentation; not Apple's header. Ferry
 * watches each folder and the folders inside it with this system's inotify
 * (foundation/FSEvents.m), so a stream hears what happens while it runs; the
 * history from before a stream started isn't kept. */
#ifndef _FERRY_FSEVENTS_H_
#define _FERRY_FSEVENTS_H_
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <sys/types.h>

__FERRY_BEGIN

typedef UInt32 FSEventStreamCreateFlags;
enum {
    kFSEventStreamCreateFlagNone = 0x00000000,
    kFSEventStreamCreateFlagUseCFTypes = 0x00000001,
    kFSEventStreamCreateFlagNoDefer = 0x00000002,
    kFSEventStreamCreateFlagWatchRoot = 0x00000004,
    kFSEventStreamCreateFlagIgnoreSelf = 0x00000008,
    kFSEventStreamCreateFlagFileEvents = 0x00000010,
    kFSEventStreamCreateFlagMarkSelf = 0x00000020,
    kFSEventStreamCreateFlagUseExtendedData = 0x00000040,
    kFSEventStreamCreateFlagFullHistory = 0x00000080,
};

typedef UInt32 FSEventStreamEventFlags;
enum {
    kFSEventStreamEventFlagNone = 0x00000000,
    kFSEventStreamEventFlagMustScanSubDirs = 0x00000001,
    kFSEventStreamEventFlagUserDropped = 0x00000002,
    kFSEventStreamEventFlagKernelDropped = 0x00000004,
    kFSEventStreamEventFlagEventIdsWrapped = 0x00000008,
    kFSEventStreamEventFlagHistoryDone = 0x00000010,
    kFSEventStreamEventFlagRootChanged = 0x00000020,
    kFSEventStreamEventFlagMount = 0x00000040,
    kFSEventStreamEventFlagUnmount = 0x00000080,
    kFSEventStreamEventFlagItemCreated = 0x00000100,
    kFSEventStreamEventFlagItemRemoved = 0x00000200,
    kFSEventStreamEventFlagItemInodeMetaMod = 0x00000400,
    kFSEventStreamEventFlagItemRenamed = 0x00000800,
    kFSEventStreamEventFlagItemModified = 0x00001000,
    kFSEventStreamEventFlagItemFinderInfoMod = 0x00002000,
    kFSEventStreamEventFlagItemChangeOwner = 0x00004000,
    kFSEventStreamEventFlagItemXattrMod = 0x00008000,
    kFSEventStreamEventFlagItemIsFile = 0x00010000,
    kFSEventStreamEventFlagItemIsDir = 0x00020000,
    kFSEventStreamEventFlagItemIsSymlink = 0x00040000,
    kFSEventStreamEventFlagOwnEvent = 0x00080000,
    kFSEventStreamEventFlagItemIsHardlink = 0x00100000,
    kFSEventStreamEventFlagItemIsLastHardlink = 0x00200000,
    kFSEventStreamEventFlagItemCloned = 0x00400000,
};

typedef UInt64 FSEventStreamEventId;
enum { kFSEventStreamEventIdSinceNow = 0xFFFFFFFFFFFFFFFFULL };

/* with kFSEventStreamCreateFlagUseExtendedData, each event is a dictionary of these */
#define kFSEventStreamEventExtendedDataPathKey CFSTR("path")
#define kFSEventStreamEventExtendedFileIDKey CFSTR("fileID")

typedef struct __FSEventStream *FSEventStreamRef;
typedef const struct __FSEventStream *ConstFSEventStreamRef;

typedef struct FSEventStreamContext {
    CFIndex version;
    void *info;
    const void *(*retain)(const void *info);
    void (*release)(const void *info);
    CFStringRef (*copyDescription)(const void *info);
} FSEventStreamContext;

/* eventPaths is a char ** array, or a CFArrayRef with kFSEventStreamCreateFlagUseCFTypes */
typedef void (*FSEventStreamCallback)(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents,
                                      void *eventPaths, const FSEventStreamEventFlags eventFlags[],
                                      const FSEventStreamEventId eventIds[]);

FSEventStreamRef FSEventStreamCreate(CFAllocatorRef allocator, FSEventStreamCallback callback,
                                     FSEventStreamContext *context, CFArrayRef pathsToWatch,
                                     FSEventStreamEventId sinceWhen, CFTimeInterval latency,
                                     FSEventStreamCreateFlags flags);
FSEventStreamRef FSEventStreamCreateRelativeToDevice(CFAllocatorRef allocator, FSEventStreamCallback callback,
                                                     FSEventStreamContext *context, dev_t deviceToWatch,
                                                     CFArrayRef pathsToWatchRelativeToDevice,
                                                     FSEventStreamEventId sinceWhen, CFTimeInterval latency,
                                                     FSEventStreamCreateFlags flags);
FSEventStreamEventId FSEventStreamGetLatestEventId(ConstFSEventStreamRef streamRef);
dev_t FSEventStreamGetDeviceBeingWatched(ConstFSEventStreamRef streamRef);
CFArrayRef FSEventStreamCopyPathsBeingWatched(ConstFSEventStreamRef streamRef);
FSEventStreamEventId FSEventsGetCurrentEventId(void);
CFUUIDRef FSEventsCopyUUIDForDevice(dev_t dev);
FSEventStreamEventId FSEventsGetLastEventIdForDeviceBeforeTime(dev_t dev, CFAbsoluteTime time);
Boolean FSEventsPurgeEventsForDeviceUpToEventId(dev_t dev, FSEventStreamEventId eventId);
void FSEventStreamRetain(FSEventStreamRef streamRef);
void FSEventStreamRelease(FSEventStreamRef streamRef);
void FSEventStreamScheduleWithRunLoop(FSEventStreamRef streamRef, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void FSEventStreamUnscheduleFromRunLoop(FSEventStreamRef streamRef, CFRunLoopRef runLoop, CFStringRef runLoopMode);
void FSEventStreamSetDispatchQueue(FSEventStreamRef streamRef, dispatch_queue_t q);
void FSEventStreamInvalidate(FSEventStreamRef streamRef);
Boolean FSEventStreamStart(FSEventStreamRef streamRef);
FSEventStreamEventId FSEventStreamFlushAsync(FSEventStreamRef streamRef);
void FSEventStreamFlushSync(FSEventStreamRef streamRef);
void FSEventStreamStop(FSEventStreamRef streamRef);
void FSEventStreamShow(ConstFSEventStreamRef streamRef);
CFStringRef FSEventStreamCopyDescription(ConstFSEventStreamRef streamRef);
Boolean FSEventStreamSetExclusionPaths(FSEventStreamRef streamRef, CFArrayRef pathsToExclude);

__FERRY_END
#endif
