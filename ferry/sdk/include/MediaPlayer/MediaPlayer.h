/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: MediaPlayer's remote commands and Now Playing information
 * (freemac 1.NEXT, Ferry 0.NEXT; appkit/MediaPlayer.m, served from Ferry's
 * AppKit file). Written for freemac from Apple's public API documentation;
 * not Apple's header. The command center keeps each command's targets and
 * the Now Playing center keeps what the app says is playing; freemac has
 * no system Now Playing panel yet, so nothing outside the app sends the
 * commands. The media library (MPMediaQuery and the like) isn't here. */
#ifndef _FERRY_MEDIAPLAYER_H_
#define _FERRY_MEDIAPLAYER_H_
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class NSImage;

typedef NS_ENUM(NSInteger, MPRemoteCommandHandlerStatus) {
    MPRemoteCommandHandlerStatusSuccess = 0,
    MPRemoteCommandHandlerStatusNoSuchContent = 100,
    MPRemoteCommandHandlerStatusNoActionableNowPlayingItem = 110,
    MPRemoteCommandHandlerStatusDeviceNotFound = 120,
    MPRemoteCommandHandlerStatusCommandFailed = 200,
};
typedef NS_ENUM(NSInteger, MPRepeatType) { MPRepeatTypeOff = 0, MPRepeatTypeOne = 1, MPRepeatTypeAll = 2 };
typedef NS_ENUM(NSInteger, MPShuffleType) { MPShuffleTypeOff = 0, MPShuffleTypeItems = 1, MPShuffleTypeCollections = 2 };
typedef NS_ENUM(NSUInteger, MPNowPlayingPlaybackState) {
    MPNowPlayingPlaybackStateUnknown = 0,
    MPNowPlayingPlaybackStatePlaying = 1,
    MPNowPlayingPlaybackStatePaused = 2,
    MPNowPlayingPlaybackStateStopped = 3,
    MPNowPlayingPlaybackStateInterrupted = 4,
};

@class MPRemoteCommand;
@interface MPRemoteCommandEvent : NSObject
@property (readonly) MPRemoteCommand *command;
@property (readonly) NSTimeInterval timestamp;
@end
@interface MPChangePlaybackPositionCommandEvent : MPRemoteCommandEvent
@property (readonly) NSTimeInterval positionTime;
@end
@interface MPChangeRepeatModeCommandEvent : MPRemoteCommandEvent
@property (readonly) MPRepeatType repeatType;
@property (readonly) BOOL preservesRepeatMode;
@end
@interface MPChangeShuffleModeCommandEvent : MPRemoteCommandEvent
@property (readonly) MPShuffleType shuffleType;
@end
@interface MPSkipIntervalCommandEvent : MPRemoteCommandEvent
@property (readonly) NSTimeInterval interval;
@end

@interface MPRemoteCommand : NSObject
@property (getter=isEnabled) BOOL enabled;
- (void)addTarget:(id)target action:(SEL)action;
- (void)removeTarget:(id)target action:(SEL)action;
- (void)removeTarget:(id)target;
- (id)addTargetWithHandler:(MPRemoteCommandHandlerStatus (^)(MPRemoteCommandEvent *event))handler;
@end
@interface MPSkipIntervalCommand : MPRemoteCommand
@property (copy) NSArray<NSNumber *> *preferredIntervals;
@end
@interface MPChangePlaybackPositionCommand : MPRemoteCommand
@end
@interface MPChangeRepeatModeCommand : MPRemoteCommand
@property MPRepeatType currentRepeatType;
@end
@interface MPChangeShuffleModeCommand : MPRemoteCommand
@property MPShuffleType currentShuffleType;
@end
@interface MPFeedbackCommand : MPRemoteCommand
@property (getter=isActive) BOOL active;
@property (copy) NSString *localizedTitle;
@end
@interface MPRatingCommand : MPRemoteCommand
@property float minimumRating;
@property float maximumRating;
@end

@interface MPRemoteCommandCenter : NSObject
+ (MPRemoteCommandCenter *)sharedCommandCenter;
@property (readonly) MPRemoteCommand *pauseCommand, *playCommand, *stopCommand, *togglePlayPauseCommand;
@property (readonly) MPRemoteCommand *enableLanguageOptionCommand, *disableLanguageOptionCommand;
@property (readonly) MPRemoteCommand *nextTrackCommand, *previousTrackCommand;
@property (readonly) MPRemoteCommand *seekForwardCommand, *seekBackwardCommand;
@property (readonly) MPSkipIntervalCommand *skipForwardCommand, *skipBackwardCommand;
@property (readonly) MPChangePlaybackPositionCommand *changePlaybackPositionCommand;
@property (readonly) MPRemoteCommand *changePlaybackRateCommand;
@property (readonly) MPChangeRepeatModeCommand *changeRepeatModeCommand;
@property (readonly) MPChangeShuffleModeCommand *changeShuffleModeCommand;
@property (readonly) MPRatingCommand *ratingCommand;
@property (readonly) MPFeedbackCommand *likeCommand, *dislikeCommand, *bookmarkCommand;
@end

@interface MPMediaItemArtwork : NSObject
- (instancetype)initWithBoundsSize:(CGSize)boundsSize requestHandler:(NSImage * (^)(CGSize size))requestHandler;
- (NSImage *)imageWithSize:(CGSize)size;
@property (readonly) CGRect bounds;
@end

@interface MPNowPlayingInfoCenter : NSObject
+ (MPNowPlayingInfoCenter *)defaultCenter;
@property (copy) NSDictionary<NSString *, id> *nowPlayingInfo;
@property MPNowPlayingPlaybackState playbackState;
@end

FOUNDATION_EXPORT NSString *const MPMediaItemPropertyPersistentID;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyTitle;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyArtist;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyAlbumTitle;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyAlbumArtist;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyAlbumTrackNumber;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyAlbumTrackCount;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyGenre;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyPlaybackDuration;
FOUNDATION_EXPORT NSString *const MPMediaItemPropertyArtwork;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyElapsedPlaybackTime;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyPlaybackRate;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyDefaultPlaybackRate;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyPlaybackProgress;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyPlaybackQueueIndex;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyPlaybackQueueCount;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyIsLiveStream;
FOUNDATION_EXPORT NSString *const MPNowPlayingInfoPropertyMediaType;

#endif
