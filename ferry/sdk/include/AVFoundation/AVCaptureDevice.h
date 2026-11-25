/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: AVFoundation's capture devices, as a list (freemac 1.NEXT,
 * Ferry 0.NEXT; appkit/AVCaptureDevice.m). Written for freemac from Apple's
 * public API documentation; not Apple's header. Capture itself (sessions,
 * inputs, outputs) isn't here yet, so no device is listed: an app that
 * offers cameras and microphones (VLC's Open Capture Device) finds none. */
#ifndef _FERRY_AVCAPTUREDEVICE_H_
#define _FERRY_AVCAPTUREDEVICE_H_
#import <Foundation/Foundation.h>
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
@end
#endif
