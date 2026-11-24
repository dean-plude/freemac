/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSTask, NSPipe and NSFileHandle (foundation/NSTask.m). Written
 * for freemac from Apple's public API documentation; not Apple's header.
 * A task runs a program of this system (/bin/sh is this system's shell);
 * a Mac program is run through Ferry. */
#ifndef _FERRY_FOUNDATION_NSTASK_H_
#define _FERRY_FOUNDATION_NSTASK_H_
#include <Foundation/Foundation.h>

/* ---- NSFileHandle ------------------------------------------------------------------- */

FOUNDATION_EXPORT NSNotificationName const NSFileHandleReadCompletionNotification;
FOUNDATION_EXPORT NSNotificationName const NSFileHandleReadToEndOfFileCompletionNotification;
FOUNDATION_EXPORT NSNotificationName const NSFileHandleConnectionAcceptedNotification;
FOUNDATION_EXPORT NSNotificationName const NSFileHandleDataAvailableNotification;
FOUNDATION_EXPORT NSString *const NSFileHandleNotificationDataItem;
FOUNDATION_EXPORT NSString *const NSFileHandleNotificationFileHandleItem;
FOUNDATION_EXPORT NSString *const NSFileHandleNotificationMonitorModes;

@interface NSFileHandle : NSObject
+ (NSFileHandle *)fileHandleWithStandardInput;
+ (NSFileHandle *)fileHandleWithStandardOutput;
+ (NSFileHandle *)fileHandleWithStandardError;
+ (NSFileHandle *)fileHandleWithNullDevice;
+ (instancetype)fileHandleForReadingAtPath:(NSString *)path;
+ (instancetype)fileHandleForWritingAtPath:(NSString *)path;
+ (instancetype)fileHandleForUpdatingAtPath:(NSString *)path;
+ (instancetype)fileHandleForReadingFromURL:(NSURL *)url error:(NSError **)error;
+ (instancetype)fileHandleForWritingToURL:(NSURL *)url error:(NSError **)error;
+ (instancetype)fileHandleForUpdatingURL:(NSURL *)url error:(NSError **)error;
- (instancetype)initWithFileDescriptor:(int)fd closeOnDealloc:(BOOL)closeopt;
- (instancetype)initWithFileDescriptor:(int)fd;
@property (readonly) int fileDescriptor;

@property (readonly, copy) NSData *availableData;
- (NSData *)readDataToEndOfFile;
- (NSData *)readDataOfLength:(NSUInteger)length;
- (NSData *)readDataToEndOfFileAndReturnError:(NSError **)error;
- (NSData *)readDataUpToLength:(NSUInteger)length error:(NSError **)error;
- (void)writeData:(NSData *)data;
- (BOOL)writeData:(NSData *)data error:(NSError **)error;

@property (readonly) unsigned long long offsetInFile;
- (unsigned long long)seekToEndOfFile;
- (void)seekToFileOffset:(unsigned long long)offset;
- (void)truncateFileAtOffset:(unsigned long long)offset;
- (void)synchronizeFile;
- (void)closeFile;
- (BOOL)getOffset:(unsigned long long *)offset error:(NSError **)error;
- (BOOL)seekToEndReturningOffset:(unsigned long long *)offset error:(NSError **)error;
- (BOOL)seekToOffset:(unsigned long long)offset error:(NSError **)error;
- (BOOL)truncateAtOffset:(unsigned long long)offset error:(NSError **)error;
- (BOOL)synchronizeAndReturnError:(NSError **)error;
- (BOOL)closeAndReturnError:(NSError **)error;

/* readabilityHandler and writeabilityHandler are called on a background
 * thread; background reads are served, and notify, from the main run loop. */
@property (copy) void (^readabilityHandler)(NSFileHandle *handle);
@property (copy) void (^writeabilityHandler)(NSFileHandle *handle);
- (void)readInBackgroundAndNotify;
- (void)readInBackgroundAndNotifyForModes:(NSArray<NSRunLoopMode> *)modes;
- (void)readToEndOfFileInBackgroundAndNotify;
- (void)readToEndOfFileInBackgroundAndNotifyForModes:(NSArray<NSRunLoopMode> *)modes;
- (void)waitForDataInBackgroundAndNotify;
- (void)waitForDataInBackgroundAndNotifyForModes:(NSArray<NSRunLoopMode> *)modes;
@end

/* ---- NSPipe ------------------------------------------------------------------------- */

@interface NSPipe : NSObject
+ (NSPipe *)pipe;
@property (readonly, retain) NSFileHandle *fileHandleForReading;
@property (readonly, retain) NSFileHandle *fileHandleForWriting;
@end

/* ---- NSTask ------------------------------------------------------------------------- */

typedef NS_ENUM(NSInteger, NSTaskTerminationReason) {
    NSTaskTerminationReasonExit = 1,
    NSTaskTerminationReasonUncaughtSignal = 2,
};

FOUNDATION_EXPORT NSNotificationName const NSTaskDidTerminateNotification;

@interface NSTask : NSObject
- (instancetype)init;
@property (copy) NSURL *executableURL;
@property (copy) NSString *launchPath;
@property (copy) NSArray<NSString *> *arguments;
@property (copy) NSDictionary<NSString *, NSString *> *environment;
@property (copy) NSURL *currentDirectoryURL;
@property (copy) NSString *currentDirectoryPath;
/* An NSPipe or an NSFileHandle; nil keeps the program's own. */
@property (retain) id standardInput;
@property (retain) id standardOutput;
@property (retain) id standardError;

- (BOOL)launchAndReturnError:(NSError **)error;
- (void)launch;
- (void)interrupt;
- (void)terminate;
- (BOOL)suspend;
- (BOOL)resume;
- (void)waitUntilExit;

@property (readonly) int processIdentifier;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly) int terminationStatus;
@property (readonly) NSTaskTerminationReason terminationReason;
@property (copy) void (^terminationHandler)(NSTask *task);
@property NSInteger qualityOfService;

+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments;
+ (NSTask *)launchedTaskWithExecutableURL:(NSURL *)url arguments:(NSArray<NSString *> *)arguments
                                    error:(NSError **)error
                       terminationHandler:(void (^)(NSTask *task))terminationHandler;
@end

#endif
