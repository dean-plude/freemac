/* SPDX-License-Identifier: GPL-3.0-or-later
 * Core Video's display links (freemac 1.235, Ferry 0.59.0), as OBS's
 * gl-cocoa and VLC's video outputs use them: about 60 callbacks a second
 * on a thread of the link's own, their time stamps, stopping (from the
 * callback too) and starting again, and a block handler. */
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <pthread.h>
#include <stdio.h>

static int check(const char *what, int ok)
{
    printf("%s: %s\n", what, ok ? "yes" : "NO");
    return ok;
}

static volatile int calls, bad_stamps, on_main, stop_after;
static uint64_t first_host, last_host;
static int64_t last_video;

static CVReturn output(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *out, CVOptionFlags in,
                       CVOptionFlags *flagsOut, void *context)
{
    if (pthread_main_np())
        on_main++;
    if (!(now->flags & kCVTimeStampHostTimeValid) || !(out->flags & kCVTimeStampVideoTimeValid) ||
        out->hostTime <= now->hostTime || now->videoTimeScale <= 0 || now->videoRefreshPeriod <= 0 ||
        (calls && now->videoTime <= last_video))
        bad_stamps++;
    if (!calls)
        first_host = now->hostTime;
    last_host = now->hostTime;
    last_video = now->videoTime;
    calls++;
    if (stop_after && calls == stop_after)
        CVDisplayLinkStop(link);
    *(int *)context += 1;
    return kCVReturnSuccess;
}

int main(void)
{
    @autoreleasepool {
        CVDisplayLinkRef link = NULL;
        check("a link for display 1", CVDisplayLinkCreateWithCGDisplay(1, &link) == kCVReturnSuccess && link);
        check("its display", CVDisplayLinkGetCurrentCGDisplay(link) == 1);
        check("its type", CFGetTypeID(link) == CVDisplayLinkGetTypeID());
        check("no start without a callback", CVDisplayLinkStart(link) == kCVReturnDisplayLinkCallbacksNotSet);
        int count = 0;
        CVDisplayLinkSetOutputCallback(link, output, &count);
        check("not running yet", !CVDisplayLinkIsRunning(link));
        CVTime period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link);
        check("nominal period a 60th of a second",
              period.timeScale > 0 && (double)period.timeValue / period.timeScale > 0.0165 &&
                  (double)period.timeValue / period.timeScale < 0.0168);

        NSDate *start = [NSDate date];
        check("started", CVDisplayLinkStart(link) == kCVReturnSuccess && CVDisplayLinkIsRunning(link));
        check("started twice refused", CVDisplayLinkStart(link) == kCVReturnDisplayLinkAlreadyRunning);
        usleep(1000000);
        CVDisplayLinkStop(link);
        double took = -[start timeIntervalSinceNow];
        int n = calls;
        double rate = n / took;
        printf("callbacks a second: %s\n", rate >= 50 && rate <= 70 ? "about 60" : "NOT about 60");
        if (rate < 50 || rate > 70)
            fprintf(stderr, "%d callbacks in %.3f s\n", n, took);
        check("stopped", !CVDisplayLinkIsRunning(link));
        usleep(100000);
        check("no callbacks after the stop", calls == n && count == n);
        check("never on the main thread", on_main == 0);
        check("time stamps in order, host and video time valid", bad_stamps == 0);
        double span = (double)(last_host - first_host) / CVGetHostClockFrequency();
        check("host times a 60th of a second apart", n > 1 && span / (n - 1) > 0.015 && span / (n - 1) < 0.019);
        double actual = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link);
        check("no actual period while stopped", actual == 0);
        CVTimeStamp ts = {0};
        check("no current time while stopped", CVDisplayLinkGetCurrentTime(link, &ts) == kCVReturnDisplayLinkNotRunning);

        /* stopped from its own callback, then started again */
        calls = 0;
        stop_after = 5;
        CVDisplayLinkStart(link);
        usleep(300000);
        check("stopped by its callback after 5", calls == 5 && !CVDisplayLinkIsRunning(link));
        stop_after = 0;
        calls = 0;
        check("started again", CVDisplayLinkStart(link) == kCVReturnSuccess);
        usleep(200000);
        ts.version = 0;
        check("the current time while running",
              CVDisplayLinkGetCurrentTime(link, &ts) == kCVReturnSuccess && (ts.flags & kCVTimeStampHostTimeValid) &&
                  ts.hostTime > 0);
        check("an actual period about a 60th", CVDisplayLinkGetActualOutputVideoRefreshPeriod(link) > 0.012 &&
                                                   CVDisplayLinkGetActualOutputVideoRefreshPeriod(link) < 0.025);
        CVDisplayLinkStop(link);
        check("about 12 callbacks in a fifth of a second", calls >= 8 && calls <= 16);
        CVDisplayLinkRelease(link);

        /* a block handler, on a link for the active displays */
        __block int blocks = 0;
        CVDisplayLinkCreateWithActiveCGDisplays(&link);
        CVDisplayLinkSetOutputHandler(link, ^CVReturn(CVDisplayLinkRef l, const CVTimeStamp *now,
                                                      const CVTimeStamp *out, CVOptionFlags in, CVOptionFlags *fo) {
            __sync_fetch_and_add(&blocks, 1);
            return kCVReturnSuccess;
        });
        CVDisplayLinkStart(link);
        usleep(150000);
        CVDisplayLinkStop(link);
        check("the block handler called", blocks >= 5 && blocks <= 14);
        check("active displays: a display", CVDisplayLinkGetCurrentCGDisplay(link) != 0);
        CVDisplayLinkRelease(link);
    }
    return 0;
}
