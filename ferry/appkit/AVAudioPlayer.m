/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AVFoundation: AVAudioPlayer (freemac 1.230), written from
 * Apple's public API documentation, served under AVFoundation's name from
 * AppKit's file.
 *
 * A player is an NSSound (appkit/NSSound.m) with AVAudioPlayer's way of
 * looping: numberOfLoops -1 loops until stopped, and a number above 0
 * plays the sound that many times again after the first. Its volume is
 * passed to the system's player when a play starts, so a change made
 * while it plays, or a fade, is heard from the next play on. pause stops
 * the system's player where it is and play continues it. currentTime
 * counts from when a play started; setting it can't move the system's
 * player along. Rate, pan and metering are kept and reported, and don't
 * change what is heard. The duration is known for WAV files, and 0 for
 * the rest. */
#import "AInternal.h"
#import <AVFoundation/AVFoundation.h>

AVFileType const AVFileTypeWAVE = @"com.microsoft.waveform-audio";
AVFileType const AVFileTypeAIFF = @"public.aiff-audio";
AVFileType const AVFileTypeAIFC = @"public.aifc-audio";
AVFileType const AVFileTypeCoreAudioFormat = @"com.apple.coreaudio-format";
AVFileType const AVFileTypeMPEGLayer3 = @"public.mp3";
AVFileType const AVFileTypeAppleM4A = @"com.apple.m4a-audio";
AVFileType const AVFileTypeAC3 = @"public.ac3-audio";

@interface AVAudioPlayer () <NSSoundDelegate>
@end

@implementation AVAudioPlayer {
    NSSound *_sound;
    NSURL *_url;
    NSData *_data;
    id<AVAudioPlayerDelegate> _delegate;
    NSInteger _loops, _left;
    float _volume, _pan, _rate;
    BOOL _enableRate, _metering, _paused;
}

static NSError *cant_open(NSString *what)
{
    return [NSError errorWithDomain:NSOSStatusErrorDomain code:'typ?' userInfo:@{
        NSLocalizedDescriptionKey : [NSString stringWithFormat:@"The sound %@ can't be played.", what]
    }];
}

- (instancetype)_initWithSound:(NSSound *)sound error:(NSError **)outError what:(NSString *)what
{
    if (!(self = [super init]))
        return nil;
    if (!sound) {
        if (outError)
            *outError = cant_open(what);
        [self release];
        return nil;
    }
    _sound = [sound retain];
    [_sound setDelegate:self];
    _volume = 1;
    _rate = 1;
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError
{
    return [self initWithContentsOfURL:url fileTypeHint:nil error:outError];
}
- (instancetype)initWithContentsOfURL:(NSURL *)url fileTypeHint:(NSString *)uti error:(NSError **)outError
{
    NSSound *s = url ? [[[NSSound alloc] initWithContentsOfURL:url byReference:YES] autorelease] : nil;
    if ((self = [self _initWithSound:s error:outError what:[url lastPathComponent] ?: @"file"]))
        _url = [url copy];
    return self;
}
- (instancetype)initWithData:(NSData *)data error:(NSError **)outError
{
    return [self initWithData:data fileTypeHint:nil error:outError];
}
- (instancetype)initWithData:(NSData *)data fileTypeHint:(NSString *)uti error:(NSError **)outError
{
    NSSound *s = [data length] ? [[[NSSound alloc] initWithData:data] autorelease] : nil;
    if ((self = [self _initWithSound:s error:outError what:@"data"]))
        _data = [data copy];
    return self;
}
- (void)dealloc
{
    [_sound setDelegate:nil];
    [_sound stop];
    [_sound release];
    [_url release];
    [_data release];
    [super dealloc];
}

- (BOOL)prepareToPlay { return YES; }
- (BOOL)play
{
    if (_paused) {
        _paused = NO;
        return [_sound resume];
    }
    if ([_sound isPlaying])
        return YES;
    _left = _loops;
    [_sound setLoops:_loops < 0];
    [_sound setVolume:_volume];
    return [_sound play];
}
- (BOOL)playAtTime:(NSTimeInterval)time
{
    NSTimeInterval wait = time - [self deviceCurrentTime];
    if (wait <= 0)
        return [self play];
    [self performSelector:@selector(play) withObject:nil afterDelay:wait];
    return YES;
}
- (void)pause
{
    if ([_sound isPlaying] && !_paused)
        _paused = [_sound pause];
}
- (void)stop
{
    _paused = NO;
    _left = 0;
    [_sound setDelegate:nil];
    [_sound stop];
    [_sound setDelegate:self];
}

/* NSSound's end of a play: again if loops are left, else the delegate's. */
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finished
{
    if (finished && _left > 0) {
        _left--;
        [_sound setVolume:_volume];
        if ([_sound play])
            return;
    }
    if ([_delegate respondsToSelector:@selector(audioPlayerDidFinishPlaying:successfully:)])
        [_delegate audioPlayerDidFinishPlaying:self successfully:finished];
}

- (BOOL)isPlaying { return [_sound isPlaying] && !_paused; }
- (NSUInteger)numberOfChannels { return 2; }
- (NSTimeInterval)duration { return [_sound duration]; }
- (NSURL *)url { return _url; }
- (NSData *)data { return _data; }
- (id<AVAudioPlayerDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<AVAudioPlayerDelegate>)d { _delegate = d; }
- (float)pan { return _pan; }
- (void)setPan:(float)p { _pan = p < -1 ? -1 : p > 1 ? 1 : p; }
- (float)volume { return _volume; }
- (void)setVolume:(float)v { _volume = v < 0 ? 0 : v > 1 ? 1 : v; }
- (void)setVolume:(float)v fadeDuration:(NSTimeInterval)duration { [self setVolume:v]; }
- (BOOL)enableRate { return _enableRate; }
- (void)setEnableRate:(BOOL)f { _enableRate = f; }
- (float)rate { return _rate; }
- (void)setRate:(float)r { _rate = r < 0.5f ? 0.5f : r > 2 ? 2 : r; }
- (NSTimeInterval)currentTime { return [_sound currentTime]; }
- (void)setCurrentTime:(NSTimeInterval)t { [_sound setCurrentTime:t]; }
- (NSTimeInterval)deviceCurrentTime { return [[NSProcessInfo processInfo] systemUptime]; }
- (NSInteger)numberOfLoops { return _loops; }
- (void)setNumberOfLoops:(NSInteger)n { _loops = n < -1 ? -1 : n; }
- (BOOL)isMeteringEnabled { return _metering; }
- (void)setMeteringEnabled:(BOOL)f { _metering = f; }
- (void)updateMeters {}
- (float)peakPowerForChannel:(NSUInteger)channel { return -160; }
- (float)averagePowerForChannel:(NSUInteger)channel { return -160; }
- (NSString *)description
{
    return [NSString stringWithFormat:@"<AVAudioPlayer %@>", [_url lastPathComponent] ?: @"data"];
}
@end
