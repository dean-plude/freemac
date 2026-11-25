/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * AVFoundation's capture devices, none yet (freemac 1.NEXT, Ferry 0.NEXT):
 * see AVFoundation/AVCaptureDevice.h. */
#import <AVFoundation/AVFoundation.h>

AVMediaType const AVMediaTypeVideo = @"vide";
AVMediaType const AVMediaTypeAudio = @"soun";
AVMediaType const AVMediaTypeMuxed = @"muxx";
AVMediaType const AVMediaTypeText = @"text";
AVMediaType const AVMediaTypeSubtitle = @"sbtl";

@implementation AVCaptureDevice
+ (NSArray<AVCaptureDevice *> *)devices { return @[]; }
+ (NSArray<AVCaptureDevice *> *)devicesWithMediaType:(AVMediaType)mediaType { return @[]; }
+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType { return nil; }
+ (AVCaptureDevice *)deviceWithUniqueID:(NSString *)deviceUniqueID { return nil; }
+ (AVAuthorizationStatus)authorizationStatusForMediaType:(AVMediaType)mediaType
{
    return AVAuthorizationStatusNotDetermined;
}
+ (void)requestAccessForMediaType:(AVMediaType)mediaType completionHandler:(void (^)(BOOL))handler
{
    if (handler)
        dispatch_async(dispatch_get_main_queue(), ^{ handler(NO); });
}
- (NSString *)uniqueID { return nil; }
- (NSString *)modelID { return nil; }
- (NSString *)localizedName { return nil; }
- (NSString *)manufacturer { return nil; }
- (BOOL)isConnected { return NO; }
- (AVCaptureDevicePosition)position { return AVCaptureDevicePositionUnspecified; }
- (BOOL)hasMediaType:(AVMediaType)mediaType { return NO; }
@end
