/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: AVFoundation's capture sessions, for cameras (freemac 1.257,
 * Ferry 0.80.0; appkit/AVCaptureSession.m). Written for freemac from
 * Apple's public API documentation; not Apple's header.
 *
 * A session takes a camera (an AVCaptureDeviceInput) to a video data
 * output, whose delegate gets each picture as a CMSampleBuffer of a
 * CVPixelBuffer, in the camera's own pixel format or the one the output's
 * videoSettings ask for (32BGRA, 420v, 420f, yuvs or 2vuy). Sound from a
 * camera, movie file outputs and photo outputs aren't here: an audio data
 * output can be added and gets nothing. */
#ifndef _FERRY_AVCAPTURESESSION_H_
#define _FERRY_AVCAPTURESESSION_H_
#import <Foundation/Foundation.h>
#import <AVFoundation/AVCaptureDevice.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <dispatch/dispatch.h>

typedef NSString *AVCaptureSessionPreset _FERRY_AV_STRING_ENUM;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetPhoto;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetHigh;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetMedium;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetLow;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset320x240;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset352x288;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset640x480;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset960x540;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset1280x720;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset1920x1080;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPreset3840x2160;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetiFrame960x540;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetiFrame1280x720;
FOUNDATION_EXPORT AVCaptureSessionPreset const AVCaptureSessionPresetInputPriority;

FOUNDATION_EXPORT NSNotificationName const AVCaptureSessionRuntimeErrorNotification;
FOUNDATION_EXPORT NSNotificationName const AVCaptureSessionDidStartRunningNotification;
FOUNDATION_EXPORT NSNotificationName const AVCaptureSessionDidStopRunningNotification;
FOUNDATION_EXPORT NSNotificationName const AVCaptureSessionWasInterruptedNotification;
FOUNDATION_EXPORT NSNotificationName const AVCaptureSessionInterruptionEndedNotification;
FOUNDATION_EXPORT NSString *const AVCaptureSessionErrorKey;
FOUNDATION_EXPORT NSString *const AVFoundationErrorDomain;

typedef NS_ENUM(NSInteger, AVError) {
    AVErrorUnknown = -11800,
    AVErrorDeviceNotConnected = -11814,
    AVErrorDeviceAlreadyUsedByAnotherSession = -11804,
    AVErrorSessionNotRunning = -11803,
    AVErrorDeviceIsNotAvailableInBackground = -11837,
    AVErrorApplicationIsNotAuthorizedToUseDevice = -11852,
};

@class AVCaptureSession, AVCaptureOutput, AVCaptureConnection;

@interface AVCaptureInputPort : NSObject
@property (readonly) AVMediaType mediaType;
@property (readonly) CMFormatDescriptionRef formatDescription;
@property (getter=isEnabled) BOOL enabled;
@end

@interface AVCaptureInput : NSObject
@property (readonly) NSArray<AVCaptureInputPort *> *ports;
@end

@interface AVCaptureDeviceInput : AVCaptureInput
+ (instancetype)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError;
- (instancetype)initWithDevice:(AVCaptureDevice *)device error:(NSError **)outError;
@property (readonly) AVCaptureDevice *device;
@end

@interface AVCaptureConnection : NSObject
@property (readonly) NSArray<AVCaptureInputPort *> *inputPorts;
@property (readonly) AVCaptureOutput *output;
@property (getter=isEnabled) BOOL enabled;
@property (readonly, getter=isActive) BOOL active;
@property (readonly, getter=isVideoMirroringSupported) BOOL supportsVideoMirroring;
@property (getter=isVideoMirrored) BOOL videoMirrored;
@property BOOL automaticallyAdjustsVideoMirroring;
@property CMTime videoMinFrameDuration;
@property CMTime videoMaxFrameDuration;
@end

@interface AVCaptureOutput : NSObject
@property (readonly) NSArray<AVCaptureConnection *> *connections;
- (AVCaptureConnection *)connectionWithMediaType:(AVMediaType)mediaType;
@end

@class AVCaptureVideoDataOutput, AVCaptureAudioDataOutput;

@protocol AVCaptureVideoDataOutputSampleBufferDelegate <NSObject>
@optional
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection;
- (void)captureOutput:(AVCaptureOutput *)output
    didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer
         fromConnection:(AVCaptureConnection *)connection;
@end

@protocol AVCaptureAudioDataOutputSampleBufferDelegate <NSObject>
@optional
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection;
@end

@interface AVCaptureVideoDataOutput : AVCaptureOutput
/* nil asks for the camera's own format; read back, it says what is sent */
@property (copy) NSDictionary<NSString *, id> *videoSettings;
@property (readonly) NSArray<NSNumber *> *availableVideoCVPixelFormatTypes;
@property BOOL alwaysDiscardsLateVideoFrames;
@property (readonly) id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleBufferDelegate;
@property (readonly) dispatch_queue_t sampleBufferCallbackQueue;
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue;
@end

@interface AVCaptureAudioDataOutput : AVCaptureOutput
@property (copy) NSDictionary<NSString *, id> *audioSettings;
@property (readonly) id<AVCaptureAudioDataOutputSampleBufferDelegate> sampleBufferDelegate;
@property (readonly) dispatch_queue_t sampleBufferCallbackQueue;
- (void)setSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)delegate
                          queue:(dispatch_queue_t)queue;
@end

@interface AVCaptureSession : NSObject
@property (copy) AVCaptureSessionPreset sessionPreset;
- (BOOL)canSetSessionPreset:(AVCaptureSessionPreset)preset;
@property (readonly) NSArray<AVCaptureInput *> *inputs;
@property (readonly) NSArray<AVCaptureOutput *> *outputs;
@property (readonly) NSArray<AVCaptureConnection *> *connections;
- (BOOL)canAddInput:(AVCaptureInput *)input;
- (void)addInput:(AVCaptureInput *)input;
- (void)removeInput:(AVCaptureInput *)input;
- (BOOL)canAddOutput:(AVCaptureOutput *)output;
- (void)addOutput:(AVCaptureOutput *)output;
- (void)removeOutput:(AVCaptureOutput *)output;
- (void)beginConfiguration;
- (void)commitConfiguration;
- (void)startRunning;
- (void)stopRunning;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly, getter=isInterrupted) BOOL interrupted;
@end

#endif
