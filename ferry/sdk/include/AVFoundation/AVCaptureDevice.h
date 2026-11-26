/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: AVFoundation's capture devices (freemac 1.233, Ferry 0.57.0;
 * appkit/AVCaptureDevice.m). Written for freemac from Apple's public API
 * documentation; not Apple's header. From freemac 1.257 (Ferry 0.80.0)
 * this system's cameras are listed, with their formats and frame rates,
 * and read with AVCaptureSession (AVCaptureSession.h); microphones aren't
 * listed here (Core Audio has them). */
#ifndef _FERRY_AVCAPTUREDEVICE_H_
#define _FERRY_AVCAPTUREDEVICE_H_
#import <Foundation/Foundation.h>
#include <CoreMedia/CoreMedia.h>
#ifndef _FERRY_AV_STRING_ENUM
#define _FERRY_AV_STRING_ENUM
#endif

typedef NSString *AVMediaType _FERRY_AV_STRING_ENUM;
FOUNDATION_EXPORT AVMediaType const AVMediaTypeVideo;
FOUNDATION_EXPORT AVMediaType const AVMediaTypeAudio;
FOUNDATION_EXPORT AVMediaType const AVMediaTypeMuxed;
FOUNDATION_EXPORT AVMediaType const AVMediaTypeText;
FOUNDATION_EXPORT AVMediaType const AVMediaTypeSubtitle;

typedef NS_ENUM(NSInteger, AVAuthorizationStatus) {
    AVAuthorizationStatusNotDetermined = 0,
    AVAuthorizationStatusRestricted = 1,
    AVAuthorizationStatusDenied = 2,
    AVAuthorizationStatusAuthorized = 3,
};
typedef NS_ENUM(NSInteger, AVCaptureDevicePosition) {
    AVCaptureDevicePositionUnspecified = 0, AVCaptureDevicePositionBack = 1, AVCaptureDevicePositionFront = 2,
};

typedef NSString *AVCaptureDeviceType _FERRY_AV_STRING_ENUM;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeBuiltInWideAngleCamera;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeExternal;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeExternalUnknown;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeContinuityCamera;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeDeskViewCamera;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeMicrophone;
FOUNDATION_EXPORT AVCaptureDeviceType const AVCaptureDeviceTypeBuiltInMicrophone;

FOUNDATION_EXPORT NSNotificationName const AVCaptureDeviceWasConnectedNotification;
FOUNDATION_EXPORT NSNotificationName const AVCaptureDeviceWasDisconnectedNotification;

/* The rates a format can be sent at: durations are the time between pictures. */
@interface AVFrameRateRange : NSObject
@property (readonly) Float64 minFrameRate;
@property (readonly) Float64 maxFrameRate;
@property (readonly) CMTime maxFrameDuration;
@property (readonly) CMTime minFrameDuration;
@end

@interface AVCaptureDeviceFormat : NSObject
@property (readonly) AVMediaType mediaType;
@property (readonly) CMFormatDescriptionRef formatDescription;
@property (readonly) NSArray<AVFrameRateRange *> *videoSupportedFrameRateRanges;
@property (readonly) float videoFieldOfView;
@property (readonly) CMVideoDimensions highResolutionStillImageDimensions;
@property (readonly, getter=isVideoBinned) BOOL videoBinned;
@end

@interface AVCaptureDevice : NSObject
+ (NSArray<AVCaptureDevice *> *)devices;
+ (NSArray<AVCaptureDevice *> *)devicesWithMediaType:(AVMediaType)mediaType;
+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType;
+ (AVCaptureDevice *)deviceWithUniqueID:(NSString *)deviceUniqueID;
+ (AVAuthorizationStatus)authorizationStatusForMediaType:(AVMediaType)mediaType;
+ (void)requestAccessForMediaType:(AVMediaType)mediaType completionHandler:(void (^)(BOOL granted))handler;
@property (readonly) NSString *uniqueID;
@property (readonly) NSString *modelID;
@property (readonly) NSString *localizedName;
@property (readonly) NSString *manufacturer;
@property (readonly, getter=isConnected) BOOL connected;
@property (readonly) AVCaptureDevicePosition position;
- (BOOL)hasMediaType:(AVMediaType)mediaType;
@property (readonly) AVCaptureDeviceType deviceType;
@property (readonly, getter=isSuspended) BOOL suspended;
@property (readonly, getter=isInUseByAnotherApplication) BOOL inUseByAnotherApplication;
/* video effects (Portrait, Center Stage, Studio Light, reactions,
 * background replacement): none are on under Ferry */
@property (readonly, getter=isPortraitEffectActive) BOOL portraitEffectActive;
@property (readonly, getter=isCenterStageActive) BOOL centerStageActive;
@property (readonly, getter=isStudioLightActive) BOOL studioLightActive;
@property (readonly) BOOL canPerformReactionEffects;
@property (readonly, getter=isBackgroundReplacementActive) BOOL backgroundReplacementActive;
@property (class, readonly) BOOL reactionEffectGesturesEnabled;
@property (class, readonly) BOOL reactionEffectsEnabled;
@property (class, readonly, getter=isPortraitEffectEnabled) BOOL portraitEffectEnabled;
@property (class, readonly, getter=isCenterStageEnabled) BOOL centerStageEnabled;
@property (class, readonly, getter=isStudioLightEnabled) BOOL studioLightEnabled;
@property (class, readonly, getter=isBackgroundReplacementEnabled) BOOL backgroundReplacementEnabled;
@property (readonly) NSArray<AVCaptureDeviceFormat *> *formats;
/* set inside lockForConfiguration: and unlockForConfiguration */
@property (retain) AVCaptureDeviceFormat *activeFormat;
@property CMTime activeVideoMinFrameDuration;
@property CMTime activeVideoMaxFrameDuration;
- (BOOL)lockForConfiguration:(NSError **)outError;
- (void)unlockForConfiguration;
- (BOOL)supportsAVCaptureSessionPreset:(NSString *)preset;
@property (readonly) BOOL transportControlsSupported;
@property (readonly) int32_t transportType;
@end

@interface AVCaptureDeviceDiscoverySession : NSObject
+ (instancetype)discoverySessionWithDeviceTypes:(NSArray<AVCaptureDeviceType> *)deviceTypes
                                      mediaType:(AVMediaType)mediaType
                                       position:(AVCaptureDevicePosition)position;
@property (readonly) NSArray<AVCaptureDevice *> *devices;
@end
#endif
