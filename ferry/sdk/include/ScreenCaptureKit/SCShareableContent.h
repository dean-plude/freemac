/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ScreenCaptureKit's shareable content (freemac 1.238, Ferry
 * 0.62.0; screencapturekit/), the displays, windows and apps an app may
 * record. Written for freemac from Apple's public ScreenCaptureKit
 * reference; not Apple's header. The content is listed only once the user
 * has let the app record the screen (it is asked the first time, and the
 * completion handler gets SCStreamErrorUserDeclined meanwhile). Under X11
 * the displays are the X screen and the windows the X server's; a window's
 * ID is the window list's (CGWindowListCopyWindowInfo's kCGWindowNumber).
 * The completion handler is called on a queue of ScreenCaptureKit's own. */
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCShareableContentStyle) {
    SCShareableContentStyleNone = 0,
    SCShareableContentStyleWindow = 1,
    SCShareableContentStyleDisplay = 2,
    SCShareableContentStyleApplication = 3,
};

@interface SCRunningApplication : NSObject
@property (readonly) NSString *bundleIdentifier;
@property (readonly) NSString *applicationName;
@property (readonly) pid_t processID;
@end

@interface SCWindow : NSObject
@property (readonly) CGWindowID windowID;
@property (readonly) CGRect frame;
@property (readonly, nullable) NSString *title;
@property (readonly) NSInteger windowLayer;
@property (readonly, nullable) SCRunningApplication *owningApplication;
@property (readonly, getter=isOnScreen) BOOL onScreen;
@property (readonly, getter=isActive) BOOL active;
@end

@interface SCDisplay : NSObject
@property (readonly) CGDirectDisplayID displayID;
@property (readonly) NSInteger width;
@property (readonly) NSInteger height;
@property (readonly) CGRect frame;
@end

@class SCContentFilter;

@interface SCShareableContentInfo : NSObject
@property (readonly) SCShareableContentStyle style;
@property (readonly) float pointPixelScale;
@property (readonly) CGRect contentRect;
@end

@interface SCShareableContent : NSObject
+ (void)getShareableContentWithCompletionHandler:(void (^)(SCShareableContent *_Nullable shareableContent,
                                                           NSError *_Nullable error))completionHandler;
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                               onScreenWindowsOnly:(BOOL)onScreenWindowsOnly
                                 completionHandler:(void (^)(SCShareableContent *_Nullable shareableContent,
                                                             NSError *_Nullable error))completionHandler;
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                    onScreenWindowsOnlyBelowWindow:(SCWindow *)window
                                 completionHandler:(void (^)(SCShareableContent *_Nullable shareableContent,
                                                             NSError *_Nullable error))completionHandler;
+ (void)getShareableContentExcludingDesktopWindows:(BOOL)excludeDesktopWindows
                    onScreenWindowsOnlyAboveWindow:(SCWindow *)window
                                 completionHandler:(void (^)(SCShareableContent *_Nullable shareableContent,
                                                             NSError *_Nullable error))completionHandler;
/* the app's own windows, with no say needed */
+ (void)getCurrentProcessShareableContentWithCompletionHandler:(void (^)(SCShareableContent *_Nullable shareableContent,
                                                                         NSError *_Nullable error))completionHandler;
+ (SCShareableContentInfo *)infoForFilter:(SCContentFilter *)filter;
@property (readonly) NSArray<SCWindow *> *windows;
@property (readonly) NSArray<SCDisplay *> *displays;
@property (readonly) NSArray<SCRunningApplication *> *applications;
@end

NS_ASSUME_NONNULL_END
