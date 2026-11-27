/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's Local Authentication (LAContext). Our own code, written from
 * Apple's public API documentation of LocalAuthentication; served from
 * Security's file (src/loader.c's framework aliases), built without ARC.
 *
 * A PC running freemac has no Touch ID sensor, no paired Apple Watch and
 * no Mac login password that Ferry checks, so it answers as a Mac without
 * that hardware does:
 *
 * - canEvaluatePolicy:error: says NO for every policy and always sets the
 *   error: LAErrorBiometryNotAvailable for Touch ID, LAErrorWatchNotAvailable
 *   for the watch, LAErrorPasscodeNotSet for the device password;
 * - evaluatePolicy:localizedReason:reply: calls the reply once, on another
 *   thread as a Mac does, with NO and that same error;
 * - the reuse duration and titles are kept as set; biometryType is
 *   LABiometryTypeNone and the domain state nil.
 *
 * Apps then use their own password prompt. KeePassXC (Touch ID quick
 * unlock) reads the error's code even when the call says NO without one,
 * so the error is never left unset. */
#include "SInternal.h"
#include <LocalAuthentication/LocalAuthentication.h>
#include <dispatch/dispatch.h>

S_EXPORT NSString *const LAErrorDomain = @"com.apple.LocalAuthentication";

static NSError *la_error(LAPolicy policy, BOOL invalid)
{
    NSInteger code;
    NSString *why;
    if (invalid) {
        code = LAErrorInvalidContext;
        why = @"This authentication context was invalidated.";
    } else switch (policy) {
    case LAPolicyDeviceOwnerAuthenticationWithBiometrics:
        code = LAErrorBiometryNotAvailable;
        why = @"This computer has no Touch ID sensor.";
        break;
    case LAPolicyDeviceOwnerAuthenticationWithWatch:
    case LAPolicyDeviceOwnerAuthenticationWithWristDetection:
        code = LAErrorWatchNotAvailable;
        why = @"No Apple Watch is paired with this computer.";
        break;
    case LAPolicyDeviceOwnerAuthenticationWithBiometricsOrWatch:
        code = LAErrorBiometryNotAvailable;
        why = @"This computer has no Touch ID sensor or paired Apple Watch.";
        break;
    default:
        code = LAErrorPasscodeNotSet;
        why = @"Ferry can't check this computer's login password.";
        break;
    }
    return [NSError errorWithDomain:LAErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: why}];
}

@implementation LAContext {
    BOOL invalid;
}
@synthesize localizedFallbackTitle, localizedCancelTitle, localizedReason;
@synthesize touchIDAuthenticationAllowableReuseDuration, interactionNotAllowed;

- (void)dealloc
{
    [localizedFallbackTitle release];
    [localizedCancelTitle release];
    [localizedReason release];
    [super dealloc];
}

- (BOOL)canEvaluatePolicy:(LAPolicy)policy error:(NSError **)error
{
    SVerboseOnce(@"LocalAuthentication: no Touch ID, Apple Watch or device password here; apps use their own prompt");
    if (error)
        *error = la_error(policy, invalid);
    return NO;
}

- (void)evaluatePolicy:(LAPolicy)policy localizedReason:(NSString *)reason
                 reply:(void (^)(BOOL success, NSError *error))reply
{
    if (!reply)
        return;
    NSError *e = [la_error(policy, invalid) retain];
    void (^r)(BOOL, NSError *) = [reply copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        r(NO, e);
        [r release];
        [e release];
    });
}

- (void)invalidate { invalid = YES; }
- (BOOL)setCredential:(NSData *)credential type:(LACredentialType)type { return NO; }
- (BOOL)isCredentialSet:(LACredentialType)type { return NO; }
- (LABiometryType)biometryType { return LABiometryTypeNone; }
- (NSData *)evaluatedPolicyDomainState { return nil; }
@end
