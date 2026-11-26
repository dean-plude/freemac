/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ScreenCaptureKit's errors (freemac 1.238, Ferry 0.62.0).
 * Written for freemac from Apple's public ScreenCaptureKit reference; not
 * Apple's header. */
#import <Foundation/Foundation.h>

extern NSString *const SCStreamErrorDomain;

typedef NS_ERROR_ENUM(SCStreamErrorDomain, SCStreamErrorCode) {
    SCStreamErrorUserDeclined = -3801,
    SCStreamErrorFailedToStart = -3802,
    SCStreamErrorMissingEntitlements = -3803,
    SCStreamErrorFailedApplicationConnectionInvalid = -3804,
    SCStreamErrorFailedApplicationConnectionInterrupted = -3805,
    SCStreamErrorFailedNoMatchingApplicationContext = -3806,
    SCStreamErrorAttemptToStartStreamState = -3807,
    SCStreamErrorAttemptToStopStreamState = -3808,
    SCStreamErrorAttemptToUpdateFilterState = -3809,
    SCStreamErrorAttemptToConfigState = -3810,
    SCStreamErrorInternalError = -3811,
    SCStreamErrorInvalidParameter = -3812,
    SCStreamErrorNoWindowList = -3813,
    SCStreamErrorNoDisplayList = -3814,
    SCStreamErrorNoCaptureSource = -3815,
    SCStreamErrorRemovingStream = -3816,
    SCStreamErrorUserStopped = -3817,
    SCStreamErrorFailedToStartAudioCapture = -3818,
    SCStreamErrorFailedToStopAudioCapture = -3819,
    SCStreamErrorFailedToStartMicrophoneCapture = -3820,
    SCStreamErrorSystemStoppedStream = -3821,
};
