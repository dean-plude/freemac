/* AVFoundation's AVAudioPlayer (freemac 1.230), as TomatoBar plays its
 * sounds: from data, with a volume, looped a number of times or until
 * stopped. FERRY_SOUND_PLAYER is tests/appkit/fake_player.sh, which notes
 * each play's volume and plays for 0.3 seconds. */
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static NSData *wav(double seconds)
{
    uint32_t rate = 8000, n = (uint32_t)(rate * seconds);
    NSMutableData *d = [NSMutableData data];
#define U32(v) do { uint32_t x = (v); [d appendBytes:&x length:4]; } while (0)
#define U16(v) do { uint16_t x = (v); [d appendBytes:&x length:2]; } while (0)
    [d appendBytes:"RIFF" length:4]; U32(36 + n); [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4]; U32(16); U16(1); U16(1); U32(rate); U32(rate); U16(1); U16(8);
    [d appendBytes:"data" length:4]; U32(n);
    [d increaseLengthBy:n];
    return d;
}

static void plays(const char *what)
{
    NSString *log = [NSString stringWithContentsOfFile:@(getenv("FERRY_FAKE_PLAYER_LOG")) encoding:NSUTF8StringEncoding
                                                 error:NULL];
    NSArray *lines = [[log stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]
        componentsSeparatedByString:@"\n"];
    printf("%s: %s\n", what, [log length] ? [[lines componentsJoinedByString:@"; "] UTF8String] : "(none)");
    [[NSFileManager defaultManager] removeItemAtPath:@(getenv("FERRY_FAKE_PLAYER_LOG")) error:NULL];
}

static void wait_for(double seconds) { [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }

@interface Listener : NSObject <AVAudioPlayerDelegate>
@end
@implementation Listener
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)p successfully:(BOOL)flag
{
    printf("delegate: finished %s\n", flag ? "successfully" : "early");
}
@end

int main(void)
{
    @autoreleasepool {
        NSError *err = nil;
        AVAudioPlayer *none = [[AVAudioPlayer alloc] initWithData:[NSData data] fileTypeHint:AVFileTypeWAVE error:&err];
        printf("no data: %s, error %s\n", none ? "a player" : "no player", [err domain] ? "given" : "missing");
        printf("file types: %s %s\n", [AVFileTypeWAVE UTF8String], [AVFileTypeMPEGLayer3 UTF8String]);

        AVAudioPlayer *ding = [[AVAudioPlayer alloc] initWithData:wav(0.25) fileTypeHint:AVFileTypeWAVE error:&err];
        Listener *listener = [Listener new];
        ding.delegate = listener;
        printf("duration %.2f, volume %.1f, loops %ld, prepared %d\n", ding.duration, ding.volume,
               (long)ding.numberOfLoops, [ding prepareToPlay]);
        [ding setVolume:0.5 fadeDuration:0];
        ding.numberOfLoops = 2;
        printf("play: %d, playing %d\n", [ding play], ding.playing);
        wait_for(2.5);
        printf("playing after three plays: %d\n", ding.playing);
        plays("played");

        AVAudioPlayer *ticking = [[AVAudioPlayer alloc] initWithData:wav(0.25) error:&err];
        ticking.numberOfLoops = -1;
        ticking.volume = 2;
        printf("volume kept between 0 and 1: %.1f\n", ticking.volume);
        [ticking play];
        wait_for(1.0);
        printf("still ticking: %d\n", ticking.playing);
        [ticking pause];
        printf("paused: playing %d\n", ticking.playing);
        [ticking play];
        printf("resumed: playing %d\n", ticking.playing);
        [ticking stop];
        printf("stopped: playing %d\n", ticking.playing);
        NSString *log = [NSString stringWithContentsOfFile:@(getenv("FERRY_FAKE_PLAYER_LOG"))
                                                  encoding:NSUTF8StringEncoding error:NULL];
        printf("ticked again: %s\n", [[log componentsSeparatedByString:@"\n"] count] > 2 ? "yes" : "no");
        [[NSFileManager defaultManager] removeItemAtPath:@(getenv("FERRY_FAKE_PLAYER_LOG")) error:NULL];
        wait_for(0.5);
        plays("after stop");
    }
    return 0;
}
