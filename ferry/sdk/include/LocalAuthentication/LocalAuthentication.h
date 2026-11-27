/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Local Authentication: Touch ID, Apple Watch and the device password,
 * asked for by an app before it unlocks something. Ferry's own header,
 * written from Apple's public API documentation of LAContext, LAPolicy and
 * LAError. Served from Security's file (security/LocalAuthentication.m).
 *
 * A PC running freemac has no Touch ID sensor, no paired watch and no Mac
 * login password Ferry can check, so every policy reports that it can't
 * be used here, the way a Mac without that hardware does, and apps fall
 * back to their own password prompt. */
#ifndef FERRY_LOCALAUTHENTICATION_H
#define FERRY_LOCALAUTHENTICATION_H
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LAPolicy) {
    LAPolicyDeviceOwnerAuthenticationWithBiometrics = 1,
    LAPolicyDeviceOwnerAuthentication = 2,
    LAPolicyDeviceOwnerAuthenticationWithWatch = 3,
    LAPolicyDeviceOwnerAuthenticationWithBiometricsOrWatch = 4,
    LAPolicyDeviceOwnerAuthenticationWithWristDetection = 5,
};

typedef NS_ENUM(NSInteger, LABiometryType) {
    LABiometryTypeNone = 0,
    LABiometryTypeTouchID = 1,
    LABiometryTypeFaceID = 2,
    LABiometryTypeOpticID = 4,
};

typedef NS_ENUM(NSInteger, LACredentialType) {
    LACredentialTypeApplicationPassword = 0,
};

extern NSString *const LAErrorDomain;

typedef NS_ENUM(NSInteger, LAError) {
    LAErrorAuthenticationFailed = -1,
    LAErrorUserCancel = -2,
    LAErrorUserFallback = -3,
    LAErrorSystemCancel = -4,
    LAErrorPasscodeNotSet = -5,
    LAErrorBiometryNotAvailable = -6,
    LAErrorTouchIDNotAvailable = -6,
    LAErrorBiometryNotEnrolled = -7,
    LAErrorTouchIDNotEnrolled = -7,
    LAErrorBiometryLockout = -8,
    LAErrorTouchIDLockout = -8,
    LAErrorAppCancel = -9,
    LAErrorInvalidContext = -10,
    LAErrorWatchNotAvailable = -11,
    LAErrorBiometryNotPaired = -12,
    LAErrorBiometryDisconnected = -13,
    LAErrorInvalidDimensions = -14,
    LAErrorNotInteractive = -1004,
};

@interface LAContext : NSObject
- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)error;
- (void)evaluatePolicy:(LAPolicy)policy localizedReason:(NSString *)reason
                 reply:(void (^)(BOOL success, NSError *error))reply;
- (void)invalidate;
- (BOOL)setCredential:(NSData *)credential type:(LACredentialType)type;
- (BOOL)isCredentialSet:(LACredentialType)type;
@property (copy) NSString *localizedFallbackTitle;
@property (copy) NSString *localizedCancelTitle;
@property (copy) NSString *localizedReason;
@property NSTimeInterval touchIDAuthenticationAllowableReuseDuration;
@property BOOL interactionNotAllowed;
@property (readonly) LABiometryType biometryType;
@property (readonly) NSData *evaluatedPolicyDomainState;
@end

#endif
