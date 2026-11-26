/* SPDX-License-Identifier: GPL-3.0-or-later
 * Access to the microphone and the camera (freemac 1.241, Ferry 0.65.0):
 * AVCaptureDevice's authorization status read from
 * ~/.config/freemac/microphone.json and camera.json, and
 * requestAccessForMediaType: asking once with freemac-allow-control
 * (appkit/fake_asker.sh here, answering Allow) and answering on a queue of
 * its own, while the main thread waits for it as OBS Studio's does. */
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static void status(const char *label)
{
    printf("%s: microphone %ld, camera %ld\n", label,
           (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio],
           (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]);
}

static void request(AVMediaType type, const char *label)
{
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block BOOL granted = NO, onMain = YES;
    [AVCaptureDevice requestAccessForMediaType:type completionHandler:^(BOOL g) {
        granted = g;
        onMain = [NSThread isMainThread];
        dispatch_semaphore_signal(done);
    }];
    long late = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    printf("%s: %s, granted %d, on the main thread %d\n", label, late ? "no answer" : "answered", granted, onMain);
}

int main(void)
{
    @autoreleasepool {
        status("at first");

        /* the camera turned down before (in Dials, say): kept, not asked */
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".config/freemac"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil
                                                        error:NULL];
        NSString *me = [[[NSBundle mainBundle] executablePath] stringByStandardizingPath];
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"apps" : @{me : @{@"allowed" : @NO, @"name" : @"Test"}}}
                                                       options:0
                                                         error:NULL];
        [json writeToFile:[dir stringByAppendingPathComponent:@"camera.json"] atomically:YES];
        status("camera turned down");

        request(AVMediaTypeAudio, "microphone");
        status("after asking");
        request(AVMediaTypeAudio, "microphone again");
        request(AVMediaTypeVideo, "camera");
        request(AVMediaTypeMuxed, "camera with sound");
        request(AVMediaTypeText, "text");

        NSString *log = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"asker.log"]
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
        printf("asked:\n%s", log ? [log UTF8String] : "(never)\n");
    }
    return 0;
}
