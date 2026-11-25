/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSRunningApplication and NSWorkspace's running applications
 * (appkit/NSRunningApplication.m), imported by AppKit.h. Written for
 * freemac from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_APPKIT_NSRUNNINGAPPLICATION_H_
#define _FERRY_APPKIT_NSRUNNINGAPPLICATION_H_
#import <Foundation/Foundation.h>
#include <sys/types.h>

typedef NS_OPTIONS(NSUInteger, NSApplicationActivationOptions) {
    NSApplicationActivateAllWindows = 1 << 0,
    NSApplicationActivateIgnoringOtherApps = 1 << 1,
};

@interface NSRunningApplication : NSObject
@property (readonly, getter=isTerminated) BOOL terminated;
@property (readonly, getter=isFinishedLaunching) BOOL finishedLaunching;
@property (readonly, getter=isHidden) BOOL hidden;
@property (readonly, getter=isActive) BOOL active;
@property (readonly) BOOL ownsMenuBar;
@property (readonly) NSApplicationActivationPolicy activationPolicy;
@property (readonly, copy) NSString *localizedName;
@property (readonly, copy) NSString *bundleIdentifier;
@property (readonly, copy) NSURL *bundleURL;
@property (readonly, copy) NSURL *executableURL;
@property (readonly) pid_t processIdentifier;
@property (readonly, copy) NSDate *launchDate;
@property (readonly, retain) NSImage *icon;
@property (readonly) NSInteger executableArchitecture;
- (BOOL)hide;
- (BOOL)unhide;
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options;
- (BOOL)terminate;
- (BOOL)forceTerminate;
+ (instancetype)runningApplicationWithProcessIdentifier:(pid_t)pid;
+ (NSArray<NSRunningApplication *> *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier;
@property (class, readonly) NSRunningApplication * FERRY_SWIFT_NONNULL currentApplication;
+ (void)terminateAutomaticallyTerminableApplications;
@end

@interface NSWorkspace (NSRunningApplications)
@property (readonly, copy) NSArray<NSRunningApplication *> *runningApplications;
@property (readonly, retain) NSRunningApplication *frontmostApplication;
@property (readonly, retain) NSRunningApplication *menuBarOwningApplication;
@end

#endif
