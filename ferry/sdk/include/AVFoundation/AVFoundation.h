/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: AVFoundation's audio player (freemac 1.230; appkit/AVAudioPlayer.m,
 * served from Ferry's AppKit file). Written for freemac from Apple's public
 * API documentation; not Apple's header. A player plays its sound through
 * NSSound, which hands the file to the system's own player (pw-play, paplay
 * or aplay). The rest of AVFoundation (capture, video, editing, the audio
 * engine) isn't here. */
#ifndef _FERRY_AVFOUNDATION_H_
#define _FERRY_AVFOUNDATION_H_
#import <Foundation/Foundation.h>

#if defined(__has_attribute) && __has_attribute(swift_name)
#define _FERRY_AV_SWIFT(n) __attribute__((swift_name(n)))
#else
#define _FERRY_AV_SWIFT(n)
#endif
#if defined(__has_attribute) && __has_attribute(swift_wrapper)
#define _FERRY_AV_STRING_ENUM __attribute__((swift_wrapper(struct)))
#else
#define _FERRY_AV_STRING_ENUM
#endif

/* The kinds of file, by their uniform type identifiers. */
typedef NSString *AVFileType _FERRY_AV_STRING_ENUM;
FOUNDATION_EXPORT AVFileType const AVFileTypeWAVE _FERRY_AV_SWIFT("wav");
FOUNDATION_EXPORT AVFileType const AVFileTypeAIFF _FERRY_AV_SWIFT("aiff");
FOUNDATION_EXPORT AVFileType const AVFileTypeAIFC _FERRY_AV_SWIFT("aifc");
FOUNDATION_EXPORT AVFileType const AVFileTypeCoreAudioFormat _FERRY_AV_SWIFT("caf");
FOUNDATION_EXPORT AVFileType const AVFileTypeMPEGLayer3 _FERRY_AV_SWIFT("mp3");
FOUNDATION_EXPORT AVFileType const AVFileTypeAppleM4A _FERRY_AV_SWIFT("m4a");
FOUNDATION_EXPORT AVFileType const AVFileTypeAC3 _FERRY_AV_SWIFT("ac3");

@class AVAudioPlayer;

@protocol AVAudioPlayerDelegate <NSObject>
@optional
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag;
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error;
@end

@interface AVAudioPlayer : NSObject
- (instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)outError;
- (instancetype)initWithData:(NSData *)data error:(NSError **)outError;
- (instancetype)initWithContentsOfURL:(NSURL *)url fileTypeHint:(NSString *)utiString error:(NSError **)outError;
- (instancetype)initWithData:(NSData *)data fileTypeHint:(NSString *)utiString error:(NSError **)outError;

- (BOOL)prepareToPlay;
- (BOOL)play;
- (BOOL)playAtTime:(NSTimeInterval)time;
- (void)pause;
- (void)stop;

@property (readonly, getter=isPlaying) BOOL playing;
@property (readonly) NSUInteger numberOfChannels;
@property (readonly) NSTimeInterval duration;
@property (readonly) NSURL *url;
@property (readonly) NSData *data;
@property (assign) id<AVAudioPlayerDelegate> delegate;

@property float pan;
@property float volume;
- (void)setVolume:(float)volume fadeDuration:(NSTimeInterval)duration _FERRY_AV_SWIFT("setVolume(_:fadeDuration:)");
@property BOOL enableRate;
@property float rate;
@property NSTimeInterval currentTime;
@property (readonly) NSTimeInterval deviceCurrentTime;
/* -1 plays the sound until it is stopped, n > 0 n times more after the first. */
@property NSInteger numberOfLoops;
@property (getter=isMeteringEnabled) BOOL meteringEnabled;
- (void)updateMeters;
- (float)peakPowerForChannel:(NSUInteger)channelNumber;
- (float)averagePowerForChannel:(NSUInteger)channelNumber;
@end

/* capture devices, listed (freemac 1.233, Ferry 0.57.0) */
#import <AVFoundation/AVCaptureDevice.h>

#endif
