/* SPDX-License-Identifier: GPL-3.0-or-later
 * The calls KeePassXC's official download makes that Ferry lacked
 * (freemac 1.NEXT):
 * - Local Authentication (Touch ID quick unlock): with no Touch ID sensor,
 *   paired watch or device password here, every policy says NO and always
 *   sets the error, which KeePassXC reads even when it set none itself;
 *   evaluatePolicy's reply comes once, on another thread;
 * - kSecUseAuthenticationUIAllow, a keychain query value;
 * - ptrace(PT_DENY_ATTACH), its anti-debugger call, which does nothing here;
 * - PC/SC smart cards (YubiKey challenge-response) through this system's
 *   pcsc-lite, in the Mac's 32-bit layout; run with FERRY_PCSC naming a
 *   library that isn't there, so the answer is "no smart card service".
 * Declarations are written here from Apple's public documentation. */
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>

int ptrace(int request, int pid, void *addr, int data);

typedef int32_t LONG;
typedef uint32_t DWORD;
typedef int32_t SCARDCONTEXT;
typedef struct { DWORD dwProtocol, cbPciLength; } SCARD_IO_REQUEST;
extern const SCARD_IO_REQUEST g_rgSCardT0Pci, g_rgSCardT1Pci, g_rgSCardRawPci;
LONG SCardEstablishContext(DWORD scope, const void *r1, const void *r2, SCARDCONTEXT *context);
LONG SCardIsValidContext(SCARDCONTEXT context);

static void policy(LAContext *c, LAPolicy p, const char *name)
{
    NSError *error = (NSError *)(uintptr_t)0x1;   /* as an uninitialised out parameter */
    BOOL ok = [c canEvaluatePolicy:p error:&error];
    printf("%s: %s, %s %ld\n", name, ok ? "yes" : "no",
           [error.domain isEqualToString:LAErrorDomain] ? "LAErrorDomain" : "other domain", (long)error.code);
}

int main(void)
{
    @autoreleasepool {
        LAContext *c = [[LAContext alloc] init];
        printf("LAContext: %s, biometry type %ld\n", c ? "made" : "nil", (long)c.biometryType);
        policy(c, LAPolicyDeviceOwnerAuthenticationWithBiometrics, "Touch ID");
        policy(c, LAPolicyDeviceOwnerAuthenticationWithWatch, "watch");
        policy(c, LAPolicyDeviceOwnerAuthenticationWithBiometricsOrWatch, "Touch ID or watch");
        policy(c, LAPolicyDeviceOwnerAuthentication, "device password");
        c.touchIDAuthenticationAllowableReuseDuration = 30;
        c.localizedFallbackTitle = @"Use password";
        printf("kept: %.0f, %s\n", c.touchIDAuthenticationAllowableReuseDuration, c.localizedFallbackTitle.UTF8String);

        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block int calls = 0;
        __block BOOL success = YES, mainThread = YES;
        __block long code = 0;
        [c evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"unlock the test"
                    reply:^(BOOL s, NSError *e) {
                        calls++; success = s; code = (long)e.code; mainThread = pthread_main_np() != 0;
                        dispatch_semaphore_signal(done);
                    }];
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        [NSThread sleepForTimeInterval:0.2];
        printf("evaluate: %d reply, %s, code %ld, %s\n", calls, success ? "yes" : "no", code,
               mainThread ? "on the main thread" : "on another thread");
        [c invalidate];
        policy(c, LAPolicyDeviceOwnerAuthenticationWithBiometrics, "after invalidate");
        [c release];

        printf("kSecUseAuthenticationUIAllow: %s\n", kSecUseAuthenticationUIAllow ? "set" : "missing");

        printf("ptrace(PT_DENY_ATTACH): %d\n", ptrace(31, 0, 0, 0));
        errno = 0;
        int r = ptrace(0, 0, 0, 0);
        printf("ptrace(PT_TRACE_ME): %d, %s\n", r, errno ? "errno set" : "no errno");

        printf("T0 %u/%u, T1 %u/%u, raw %u/%u\n", g_rgSCardT0Pci.dwProtocol, g_rgSCardT0Pci.cbPciLength,
               g_rgSCardT1Pci.dwProtocol, g_rgSCardT1Pci.cbPciLength, g_rgSCardRawPci.dwProtocol,
               g_rgSCardRawPci.cbPciLength);
        SCARDCONTEXT ctx = 0;
        LONG rv = SCardEstablishContext(2, NULL, NULL, &ctx);
        printf("SCardEstablishContext: 0x%08x\n", (unsigned)rv);
        printf("SCardIsValidContext: 0x%08x\n", (unsigned)SCardIsValidContext(ctx));
    }
    return 0;
}
