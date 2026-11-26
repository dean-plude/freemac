/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * What AVCaptureDevice.m and AVCaptureSession.m share (freemac 1.257,
 * Ferry 0.80.0): a camera's own path and modes, behind the public API. */
#ifndef FERRY_AVCAPTURE_INTERNAL_H
#define FERRY_AVCAPTURE_INTERNAL_H
#import <AVFoundation/AVFoundation.h>
#include "../src/ferry_camera.h"

/* the host's calls (src/camera.c), NULL when this Ferry has none */
void *AVCameraCall(const char *name);

/* the pixel format a mode's pictures are handed over in when the app asks
 * for none: the camera's own, or 32BGRA for Motion JPEG */
OSType AVCameraNativePixelFormat(uint32_t fourcc);
/* the media subtype a mode is described with */
FourCharCode AVCameraSubtype(uint32_t fourcc);

@interface AVCaptureDeviceFormat ()
- (instancetype)_initWithMode:(const struct ferry_camera_mode *)mode;
- (const struct ferry_camera_mode *)_mode;
@end

@class AVCaptureSession;

@interface AVCaptureDevice ()
- (NSString *)_path;
/* the preset's format, set as the active one; NO when the camera has none near it */
- (AVCaptureDeviceFormat *)_formatForPreset:(NSString *)preset;
- (void)_applyFormat:(AVCaptureDeviceFormat *)format;
/* a session the device is in hears when its format or rate is changed */
- (void)_setSession:(AVCaptureSession *)session;
@end

@interface AVCaptureSession ()
- (void)_deviceChanged:(AVCaptureDevice *)device;
@end
#endif
