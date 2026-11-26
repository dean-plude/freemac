/* SPDX-License-Identifier: GPL-3.0-or-later
 * The Foundation and Security calls OBS makes (freemac OBS work): the
 * system's certificate authorities for its RTMP output, checked against
 * noErr as Security.h brings it in, and a volume's free space for its
 * recording warnings. */
#include <Foundation/Foundation.h>
#include <Security/Security.h>
#include <stdio.h>

int main(void)
{
    @autoreleasepool {
        CFArrayRef anchors = NULL;
        OSStatus code = SecTrustCopyAnchorCertificates(&anchors);
        int certs = 1;
        CFIndex n = anchors ? CFArrayGetCount(anchors) : -1;
        for (CFIndex i = 0; i < n; i++) {
            SecCertificateRef c = (SecCertificateRef)CFArrayGetValueAtIndex(anchors, i);
            CFDataRef der = SecCertificateCopyData(c);
            /* DER: a SEQUENCE */
            if (!der || CFDataGetLength(der) < 64 || CFDataGetBytePtr(der)[0] != 0x30)
                certs = 0;
            if (der)
                CFRelease(der);
        }
        printf("anchors %s, %s, all DER certificates %d, no pointer %d\n", code == noErr ? "noErr" : "error",
               n > 0 ? "some" : "none", certs, (int)SecTrustCopyAnchorCertificates(NULL));
        if (anchors)
            CFRelease(anchors);

        NSURL *url = [NSURL fileURLWithPath:NSTemporaryDirectory()];
        NSArray *keys = @[
            NSURLVolumeAvailableCapacityKey, NSURLVolumeAvailableCapacityForImportantUsageKey,
            NSURLVolumeAvailableCapacityForOpportunisticUsageKey, NSURLVolumeTotalCapacityKey
        ];
        NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
        NSNumber *avail = values[NSURLVolumeAvailableCapacityKey];
        NSNumber *important = values[NSURLVolumeAvailableCapacityForImportantUsageKey];
        NSNumber *opportunistic = values[NSURLVolumeAvailableCapacityForOpportunisticUsageKey];
        NSNumber *total = values[NSURLVolumeTotalCapacityKey];
        printf("volume: %lu values, free > 0 %d, same for important use %d and opportunistic %d, total >= free %d\n",
               (unsigned long)[values count], avail.longLongValue > 0,
               important.longLongValue == avail.longLongValue, opportunistic.longLongValue == avail.longLongValue,
               total.unsignedLongLongValue >= avail.unsignedLongLongValue);
    }
    return 0;
}
