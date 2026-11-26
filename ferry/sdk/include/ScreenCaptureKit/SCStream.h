/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ScreenCaptureKit's streams (freemac 1.238, Ferry 0.62.0;
 * screencapturekit/). Written for freemac from Apple's public
 * ScreenCaptureKit reference; not Apple's header.
 *
 * A stream grabs what its content filter shows at most once each
 * minimumFrameInterval (1/60 s when zero) and hands each frame to its
 * screen outputs, on the queue each was added with, as a CMSampleBuffer
 * whose image buffer is an IOSurface-backed CVPixelBuffer of the
 * configuration's width, height and pixel format ('BGRA', 'l10r', '420v'
 * or '420f'). The sample's attachments (CMSampleBufferGetSampleAttachmentsArray)
 * carry the SCStreamFrameInfo keys: Status, DisplayTime (mach time),
 * ScaleFactor, ContentScale, ContentRect (in points of the frame, a
 * CGRect dictionary) and ScreenRect. Under X11 the cursor is drawn in when
 * showsCursor is set. With capturesAudio the audio outputs get what the
 * computer plays (the default output's monitor), as non-interleaved
 * 32-bit float samples at sampleRate and channelCount; the app's own sound
 * is in it whatever excludesCurrentProcessAudio says, and the microphone
 * output gets nothing (Ferry 0.62.0). */
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <dispatch/dispatch.h>
#import <ScreenCaptureKit/SCShareableContent.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCStreamOutputType) {
    SCStreamOutputTypeScreen = 0,
    SCStreamOutputTypeAudio = 1,
    SCStreamOutputTypeMicrophone = 2,
};

typedef NS_ENUM(NSInteger, SCFrameStatus) {
    SCFrameStatusComplete = 0,
    SCFrameStatusIdle = 1,
    SCFrameStatusBlank = 2,
    SCFrameStatusSuspended = 3,
    SCFrameStatusStarted = 4,
    SCFrameStatusStopped = 5,
};

typedef NS_ENUM(NSInteger, SCCaptureResolutionType) {
    SCCaptureResolutionAutomatic = 0,
    SCCaptureResolutionBest = 1,
    SCCaptureResolutionNominal = 2,
};

typedef NS_ENUM(NSInteger, SCPresenterOverlayAlertSetting) {
    SCPresenterOverlayAlertSettingSystem = 0,
    SCPresenterOverlayAlertSettingNever = 1,
    SCPresenterOverlayAlertSettingAlways = 2,
};

typedef NSString *SCStreamFrameInfo NS_TYPED_ENUM;
extern SCStreamFrameInfo const SCStreamFrameInfoStatus;
extern SCStreamFrameInfo const SCStreamFrameInfoDisplayTime;
extern SCStreamFrameInfo const SCStreamFrameInfoScaleFactor;
extern SCStreamFrameInfo const SCStreamFrameInfoContentScale;
extern SCStreamFrameInfo const SCStreamFrameInfoContentRect;
extern SCStreamFrameInfo const SCStreamFrameInfoDirtyRects;
extern SCStreamFrameInfo const SCStreamFrameInfoScreenRect;
extern SCStreamFrameInfo const SCStreamFrameInfoBoundingRect;
extern SCStreamFrameInfo const SCStreamFrameInfoPresenterOverlayContentRect;

@interface SCContentFilter : NSObject
- (instancetype)initWithDesktopIndependentWindow:(SCWindow *)window;
- (instancetype)initWithDisplay:(SCDisplay *)display excludingWindows:(NSArray<SCWindow *> *)excluded;
- (instancetype)initWithDisplay:(SCDisplay *)display includingWindows:(NSArray<SCWindow *> *)includedWindows;
- (instancetype)initWithDisplay:(SCDisplay *)display
          includingApplications:(NSArray<SCRunningApplication *> *)applications
               exceptingWindows:(NSArray<SCWindow *> *)exceptingWindows;
- (instancetype)initWithDisplay:(SCDisplay *)display
          excludingApplications:(NSArray<SCRunningApplication *> *)applications
               exceptingWindows:(NSArray<SCWindow *> *)exceptingWindows;
@property (readonly) SCShareableContentStyle style;
@property (readonly) float pointPixelScale;
@property (readonly) CGRect contentRect;
@property BOOL includeMenuBar;
@end

@interface SCStreamConfiguration : NSObject
@property size_t width;
@property size_t height;
@property CMTime minimumFrameInterval;
@property OSType pixelFormat;
@property BOOL scalesToFit;
@property BOOL preservesAspectRatio;
@property (nullable, copy) NSString *streamName;
@property BOOL shouldBeOpaque;
@property BOOL ignoreShadowsDisplay;
@property BOOL ignoreShadowsSingleWindow;
@property BOOL ignoreGlobalClipDisplay;
@property BOOL ignoreGlobalClipSingleWindow;
@property BOOL includeChildWindows;
@property SCCaptureResolutionType captureResolution;
@property CGRect sourceRect;
@property CGRect destinationRect;
@property NSInteger queueDepth;
@property CFStringRef colorMatrix;
@property CFStringRef colorSpaceName;
@property CGColorRef backgroundColor;
@property BOOL showsCursor;
@property BOOL showMouseClicks;
@property SCPresenterOverlayAlertSetting presenterOverlayPrivacyAlertSetting;
@property BOOL capturesAudio;
@property NSInteger sampleRate;
@property NSInteger channelCount;
@property BOOL excludesCurrentProcessAudio;
@property BOOL captureMicrophone;
@property (nullable, copy) NSString *microphoneCaptureDeviceID;
@end

@class SCStream;

@protocol SCStreamOutput <NSObject>
@optional
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
        ofType:(SCStreamOutputType)type;
@end

@protocol SCStreamDelegate <NSObject>
@optional
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error;
- (void)outputVideoEffectDidStartForStream:(SCStream *)stream;
- (void)outputVideoEffectDidStopForStream:(SCStream *)stream;
@end

@interface SCStream : NSObject
- (instancetype)initWithFilter:(SCContentFilter *)contentFilter
                 configuration:(SCStreamConfiguration *)streamConfig
                      delegate:(nullable id<SCStreamDelegate>)delegate;
- (BOOL)addStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type
     sampleHandlerQueue:(nullable dispatch_queue_t)sampleHandlerQueue error:(NSError **)error;
- (BOOL)removeStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type error:(NSError **)error;
- (void)updateContentFilter:(SCContentFilter *)contentFilter
          completionHandler:(nullable void (^)(NSError *_Nullable error))completionHandler;
- (void)updateConfiguration:(SCStreamConfiguration *)streamConfig
          completionHandler:(nullable void (^)(NSError *_Nullable error))completionHandler;
- (void)startCaptureWithCompletionHandler:(nullable void (^)(NSError *_Nullable error))completionHandler;
- (void)stopCaptureWithCompletionHandler:(nullable void (^)(NSError *_Nullable error))completionHandler;
@property (nullable, readonly) CMClockRef synchronizationClock;
@end

NS_ASSUME_NONNULL_END
