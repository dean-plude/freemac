/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * AVFoundation's capture devices, none yet (freemac 1.233, Ferry 0.57.0):
 * see AVFoundation/AVCaptureDevice.h.
 *
 * Access to the microphone and the camera (freemac 1.241, Ferry 0.65.0) is
 * the user's say, as screen recording is: kept for each app in
 * ~/.config/freemac/microphone.json and camera.json, and asked once with
 * freemac-allow-control --kind microphone or camera (appkit/ACapture.m).
 * requestAccessForMediaType: answers on a queue of its own, as Apple
 * documents, once the user has: OBS Studio waits for the answer on its
 * main thread. */
#import <AVFoundation/AVFoundation.h>
#import "ACapture.h"

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
/* the file a media type's answer is kept in: video and muxed (a camera
 * with its sound) is the camera's, audio the microphone's */
static NSString *access_kind(AVMediaType mediaType)
{
    if ([mediaType isEqualToString:AVMediaTypeAudio])
        return @"microphone";
    if ([mediaType isEqualToString:AVMediaTypeVideo] || [mediaType isEqualToString:AVMediaTypeMuxed])
        return @"camera";
    return nil;
}

static AVAuthorizationStatus status_of(int answer)
{
    return answer == 1 ? AVAuthorizationStatusAuthorized
         : answer == 0 ? AVAuthorizationStatusDenied
                       : AVAuthorizationStatusNotDetermined;
}

+ (AVAuthorizationStatus)authorizationStatusForMediaType:(AVMediaType)mediaType
{
    NSString *kind = access_kind(mediaType);
    return kind ? status_of(ACaptureStoredAnswerOfKind(kind)) : AVAuthorizationStatusNotDetermined;
}
+ (void)requestAccessForMediaType:(AVMediaType)mediaType completionHandler:(void (^)(BOOL))handler
{
    NSString *kind = access_kind(mediaType);
    void (^answer)(BOOL) = [handler copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL granted = NO;
        if (kind) {
            if (ACaptureStoredAnswerOfKind(kind) < 0)
                ACaptureAskKind(kind, YES);
            granted = ACaptureStoredAnswerOfKind(kind) == 1;
        }
        if (answer)
            answer(granted);
    });
}
- (NSString *)uniqueID { return nil; }
- (NSString *)modelID { return nil; }
- (NSString *)localizedName { return nil; }
- (NSString *)manufacturer { return nil; }
- (BOOL)isConnected { return NO; }
- (AVCaptureDevicePosition)position { return AVCaptureDevicePositionUnspecified; }
- (BOOL)hasMediaType:(AVMediaType)mediaType { return NO; }
@end
