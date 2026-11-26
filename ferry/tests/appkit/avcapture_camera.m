/* SPDX-License-Identifier: GPL-3.0-or-later
 * Cameras through AVFoundation (freemac 1.257, Ferry 0.80.0), with Ferry's
 * test camera (FERRY_CAMERA_TEST=1, src/camera.c): red on its left, blue
 * on its right. The camera is listed, with its formats and rates, and read
 * with a capture session in the formats a Mac app asks for, as OBS
 * Studio's camera source does: the camera's own when the output's
 * videoSettings are nil, or 32BGRA, 420v and yuvs. Presets and the
 * device's own format and rate choose what is read; a camera the user said
 * no to gets the session a runtime error. Built as OBS's mac-avcapture
 * plugin starts, with "@import" and no -framework flags, first letting
 * screen-capture devices show through CoreMediaIO's system object. */
@import AVFoundation;
@import CoreMedia;
@import CoreMediaIO;
@import CoreVideo;
@import Foundation;
#include <stdio.h>

static NSString *fcc(FourCharCode c)
{
    char s[5] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c, 0};
    return @(s);
}

@interface Catcher : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (atomic) int wanted;
@property (atomic) int count;
@property (atomic, strong) dispatch_semaphore_t done;
@property (atomic) CMSampleBufferRef last; /* the last one, retained */
@property (atomic) double firstTime, lastTime;
@end

/* counts every picture, for a session let go of while running */
@interface Counter : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (atomic) int count;
@end
@implementation Counter
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sample
           fromConnection:(AVCaptureConnection *)connection
{
    self.count++;
}
@end

@implementation Catcher
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sample
           fromConnection:(AVCaptureConnection *)connection
{
    if (self.count >= self.wanted)
        return;
    double t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
    if (self.count == 0)
        self.firstTime = t;
    self.lastTime = t;
    if (self.last)
        CFRelease(self.last);
    self.last = (CMSampleBufferRef)CFRetain(sample);
    if (++self.count == self.wanted)
        dispatch_semaphore_signal(self.done);
}
@end

static const char *colour_of(int b, int g, int r)
{
    if (r > 230 && g < 25 && b < 25)
        return "red";
    if (b > 230 && r < 25 && g < 25)
        return "blue";
    if (r > 230 && g > 230 && b > 230)
        return "white";
    return "other";
}

/* what one picture is: its format, size and the colours on its left and right */
static void describe(CMSampleBufferRef s, const char *label)
{
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(s);
    OSType f = CVPixelBufferGetPixelFormatType(pb);
    int w = (int)CVPixelBufferGetWidth(pb), h = (int)CVPixelBufferGetHeight(pb);
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    int lx = w / 8, rx = w * 7 / 8, y = h * 3 / 4;
    NSString *left = @"?", *right = @"?";
    if (f == kCVPixelFormatType_32BGRA) {
        uint8_t *p = CVPixelBufferGetBaseAddress(pb);
        size_t stride = CVPixelBufferGetBytesPerRow(pb);
        uint8_t *a = p + y * stride + lx * 4, *b = p + y * stride + rx * 4;
        left = @(colour_of(a[0], a[1], a[2]));
        right = @(colour_of(b[0], b[1], b[2]));
    } else if (f == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        uint8_t *yp = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
        size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
        uint8_t *ua = uv + (y / 2) * uvs + (lx / 2) * 2, *ub = uv + (y / 2) * uvs + (rx / 2) * 2;
        left = [NSString stringWithFormat:@"Y %d Cb %d Cr %d", yp[y * ys + lx], ua[0], ua[1]];
        right = [NSString stringWithFormat:@"Y %d Cb %d Cr %d", yp[y * ys + rx], ub[0], ub[1]];
    } else if (f == kCVPixelFormatType_422YpCbCr8_yuvs || f == kCVPixelFormatType_422YpCbCr8) {
        uint8_t *p = CVPixelBufferGetBaseAddress(pb);
        size_t stride = CVPixelBufferGetBytesPerRow(pb);
        uint8_t *a = p + y * stride + (lx & ~1) * 2, *b = p + y * stride + (rx & ~1) * 2;
        left = [NSString stringWithFormat:@"%d %d %d %d", a[0], a[1], a[2], a[3]];
        right = [NSString stringWithFormat:@"%d %d %d %d", b[0], b[1], b[2], b[3]];
    }
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    CMFormatDescriptionRef d = CMSampleBufferGetFormatDescription(s);
    CMTime duration = CMSampleBufferGetDuration(s);
    printf("%s: %s %dx%d, IOSurface %d, described as %s, every %lld/%d s; left %s, right %s\n", label,
           [fcc(f) UTF8String], w, h, CVPixelBufferGetIOSurface(pb) != NULL,
           [fcc(CMFormatDescriptionGetMediaSubType(d)) UTF8String], duration.value, duration.timescale,
           [left UTF8String], [right UTF8String]);
}

static Catcher *catch_frames(AVCaptureSession *session, AVCaptureVideoDataOutput *out, int n)
{
    Catcher *c = [[Catcher alloc] init];
    c.wanted = n;
    c.done = dispatch_semaphore_create(0);
    [out setSampleBufferDelegate:c queue:dispatch_queue_create("test.frames", NULL)];
    [session startRunning];
    long late = dispatch_semaphore_wait(c.done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
    [session stopRunning];
    [out setSampleBufferDelegate:nil queue:nil];
    if (late)
        printf("no pictures came (%d of %d)\n", c.count, n);
    return c;
}

static void allow(BOOL allowed)
{
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".config/freemac"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *me = [[[NSBundle mainBundle] executablePath] stringByStandardizingPath];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"apps" : @{me : @{@"allowed" : @(allowed), @"name" : @"Test"}}}
                                                   options:0
                                                     error:NULL];
    [json writeToFile:[dir stringByAppendingPathComponent:@"camera.json"] atomically:YES];
}

int main(void)
{
    @autoreleasepool {
        allow(YES);

        CMIOObjectPropertyAddress prop = {kCMIOHardwarePropertyAllowScreenCaptureDevices,
                                          kCMIOObjectPropertyScopeGlobal, kCMIOObjectPropertyElementMain};
        UInt32 yes = 1, got = 0, used = 0, size = 0;
        Boolean settable = false;
        OSStatus set = CMIOObjectSetPropertyData(kCMIOObjectSystemObject, &prop, 0, NULL, sizeof(yes), &yes);
        OSStatus read = CMIOObjectGetPropertyData(kCMIOObjectSystemObject, &prop, 0, NULL, sizeof(got), &used, &got);
        CMIOObjectIsPropertySettable(kCMIOObjectSystemObject, &prop, &settable);
        prop.mSelector = kCMIOHardwarePropertyDevices;
        CMIOObjectGetPropertyDataSize(kCMIOObjectSystemObject, &prop, 0, NULL, &size);
        printf("screen capture devices allowed: set %d, read %d, now %u, settable %d; CoreMediaIO devices: %u; "
               "another object: %d\n", (int)set, (int)read, got, settable, size / 4,
               CMIOObjectGetPropertyDataSize(7, &prop, 0, NULL, &size) == kCMIOHardwareBadObjectError);

        AVCaptureDevice *cam = nil;
        for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo])
            if ([d.uniqueID isEqualToString:@"ferry-test-camera"])
                cam = d;
        if (!cam) {
            printf("no test camera\n");
            return 1;
        }
        printf("camera: %s (%s), model %s, by %s, connected %d, video %d, sound %d, %s\n", [cam.localizedName UTF8String],
               [cam.uniqueID UTF8String], [cam.modelID UTF8String], [cam.manufacturer UTF8String], cam.connected,
               [cam hasMediaType:AVMediaTypeVideo], [cam hasMediaType:AVMediaTypeAudio], [cam.deviceType UTF8String]);
        printf("effects: portrait %d, Center Stage %d, Studio Light %d, reactions %d, background %d, gestures %d\n",
               cam.portraitEffectActive, cam.centerStageActive, cam.studioLightActive, cam.canPerformReactionEffects,
               cam.backgroundReplacementActive, AVCaptureDevice.reactionEffectGesturesEnabled);
        printf("found again by its ID: %d; no microphones here: %d\n",
               [AVCaptureDevice deviceWithUniqueID:cam.uniqueID] == cam,
               [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] count] == 0);
        AVCaptureDeviceDiscoverySession *ds = [AVCaptureDeviceDiscoverySession
            discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeExternalUnknown ]
                                  mediaType:AVMediaTypeVideo
                                   position:AVCaptureDevicePositionUnspecified];
        printf("discovered: %d; as muxed: %lu\n", [ds.devices containsObject:cam],
               (unsigned long)[[AVCaptureDeviceDiscoverySession
                                   discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeExternalUnknown ]
                                                         mediaType:AVMediaTypeMuxed
                                                          position:AVCaptureDevicePositionUnspecified]
                                   .devices count]);
        for (AVCaptureDeviceFormat *f in cam.formats) {
            CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription);
            NSMutableArray *rates = [NSMutableArray array];
            for (AVFrameRateRange *r in f.videoSupportedFrameRateRanges)
                [rates addObject:[NSString stringWithFormat:@"%.0f (%lld/%d)", r.maxFrameRate, r.minFrameDuration.value,
                                                            r.minFrameDuration.timescale]];
            CFStringRef matrix = CMFormatDescriptionGetExtension(f.formatDescription, kCMFormatDescriptionExtension_YCbCrMatrix);
            printf("format: %s %s %dx%d at %s, %s\n", [fcc(CMFormatDescriptionGetMediaType(f.formatDescription)) UTF8String],
                   [fcc(CMFormatDescriptionGetMediaSubType(f.formatDescription)) UTF8String], dim.width, dim.height,
                   [[rates componentsJoinedByString:@", "] UTF8String], matrix ? [(__bridge NSString *)matrix UTF8String] : "-");
        }
        CMVideoDimensions ad = CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription);
        printf("active at first: %s %dx%d, every %lld/%d s\n",
               [fcc(CMFormatDescriptionGetMediaSubType(cam.activeFormat.formatDescription)) UTF8String], ad.width, ad.height,
               cam.activeVideoMinFrameDuration.value, cam.activeVideoMinFrameDuration.timescale);

        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:cam error:&error];
        AVCaptureVideoDataOutput *out = [[AVCaptureVideoDataOutput alloc] init];
        [session beginConfiguration];
        printf("preset %s; input %d, added %d\n", [session.sessionPreset UTF8String], input != nil, [session canAddInput:input]);
        [session addInput:input];
        printf("a second input: %d; output: %d\n", [session canAddInput:input], [session canAddOutput:out]);
        [session addOutput:out];
        [session commitConfiguration];
        out.videoSettings = nil;
        printf("the camera's own: %s; offered: %lu; connection %d\n",
               [fcc([out.videoSettings[(id)kCVPixelBufferPixelFormatTypeKey] unsignedIntValue]) UTF8String],
               (unsigned long)[out.availableVideoCVPixelFormatTypes count], [out connectionWithMediaType:AVMediaTypeVideo] != nil);

        Catcher *c = catch_frames(session, out, 3);
        describe(c.last, "own format");
        printf("running after stop: %d; times go forward: %d\n", session.running, c.lastTime > c.firstTime);

        out.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        describe(catch_frames(session, out, 3).last, "32BGRA");

        session.sessionPreset = AVCaptureSessionPreset640x480;
        ad = CMVideoFormatDescriptionGetDimensions(cam.activeFormat.formatDescription);
        printf("preset 640x480: %s %dx%d\n", [fcc(CMFormatDescriptionGetMediaSubType(cam.activeFormat.formatDescription)) UTF8String],
               ad.width, ad.height);
        out.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        describe(catch_frames(session, out, 3).last, "640x480 in 32BGRA");
        out.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)};
        describe(catch_frames(session, out, 3).last, "640x480 in 420v");

        /* the camera's three-plane 4:2:0 (YU12), described and sent as 420v */
        AVCaptureDeviceFormat *planes = [cam.formats lastObject];
        [cam lockForConfiguration:&error];
        cam.activeFormat = planes;
        [cam unlockForConfiguration];
        out.videoSettings = nil;
        describe(catch_frames(session, out, 3).last, "three planes as they are");
        out.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        describe(catch_frames(session, out, 3).last, "three planes in 32BGRA");

        AVCaptureDeviceFormat *uyvy = nil;
        for (AVCaptureDeviceFormat *f in cam.formats)
            if (CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_422YpCbCr8)
                uyvy = f;
        [cam lockForConfiguration:&error];
        cam.activeFormat = uyvy;
        [cam unlockForConfiguration];
        printf("the device's own format: preset %s\n", [session.sessionPreset UTF8String]);
        out.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_422YpCbCr8_yuvs)};
        describe(catch_frames(session, out, 3).last, "2vuy camera in yuvs");
        out.videoSettings = nil;
        describe(catch_frames(session, out, 3).last, "2vuy camera as it is");

        session.sessionPreset = AVCaptureSessionPreset640x480;
        [cam lockForConfiguration:&error];
        cam.activeVideoMinFrameDuration = CMTimeMake(1, 15);
        cam.activeVideoMaxFrameDuration = CMTimeMake(1, 15);
        [cam unlockForConfiguration];
        out.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)};
        c = catch_frames(session, out, 6);
        double each = (c.lastTime - c.firstTime) / 5;
        describe(c.last, "15 a second");
        printf("about 15 a second: %d\n", each > 0.050 && each < 0.090);

        printf("1280x720 offered: %d, 3840x2160: %d\n", [session canSetSessionPreset:AVCaptureSessionPreset1280x720],
               [session canSetSessionPreset:AVCaptureSessionPreset3840x2160]);

        /* a running session the app lets go of stops, as OBS's legacy camera
         * source counts on, and pictures queued before the stop aren't handed
         * over */
        Counter *counter = [Counter new];
        dispatch_queue_t q = dispatch_queue_create("counter", NULL);
        @autoreleasepool {
            AVCaptureSession *s2 = [AVCaptureSession new];
            AVCaptureVideoDataOutput *o2 = [AVCaptureVideoDataOutput new];
            [s2 addInput:[AVCaptureDeviceInput deviceInputWithDevice:cam error:NULL]];
            [s2 addOutput:o2];
            [o2 setSampleBufferDelegate:counter queue:q];
            [s2 startRunning];
            for (int i = 0; i < 100 && counter.count < 3; i++)
                usleep(20000);
        }
        int at_release = counter.count;
        usleep(300000);
        dispatch_sync(q, ^{});
        printf("let go of while running: had pictures %d, more after %d\n", at_release >= 3, counter.count - at_release);

        /* the user said no */
        allow(NO);
        __block NSInteger code = 0;
        id token = [[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification
                                                                     object:session
                                                                      queue:nil
                                                                 usingBlock:^(NSNotification *n) {
                                                                     code = [n.userInfo[AVCaptureSessionErrorKey] code];
                                                                 }];
        [session startRunning];
        for (int i = 0; i < 50 && !code; i++)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        printf("turned down: running %d, error %ld\n", session.running, (long)code);
        [[NSNotificationCenter defaultCenter] removeObserver:token];
    }
    return 0;
}
