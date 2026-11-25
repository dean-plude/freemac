/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * MediaPlayer's remote commands and Now Playing information (freemac
 * 1.233, Ferry 0.57.0): see MediaPlayer/MediaPlayer.h. */
#import "AInternal.h"
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>

NSString *const MPMediaItemPropertyPersistentID = @"persistentID";
NSString *const MPMediaItemPropertyTitle = @"title";
NSString *const MPMediaItemPropertyArtist = @"artist";
NSString *const MPMediaItemPropertyAlbumTitle = @"albumTitle";
NSString *const MPMediaItemPropertyAlbumArtist = @"albumArtist";
NSString *const MPMediaItemPropertyAlbumTrackNumber = @"albumTrackNumber";
NSString *const MPMediaItemPropertyAlbumTrackCount = @"albumTrackCount";
NSString *const MPMediaItemPropertyGenre = @"genre";
NSString *const MPMediaItemPropertyPlaybackDuration = @"playbackDuration";
NSString *const MPMediaItemPropertyArtwork = @"artwork";
NSString *const MPNowPlayingInfoPropertyElapsedPlaybackTime = @"MPNowPlayingInfoPropertyElapsedPlaybackTime";
NSString *const MPNowPlayingInfoPropertyPlaybackRate = @"MPNowPlayingInfoPropertyPlaybackRate";
NSString *const MPNowPlayingInfoPropertyDefaultPlaybackRate = @"MPNowPlayingInfoPropertyDefaultPlaybackRate";
NSString *const MPNowPlayingInfoPropertyPlaybackProgress = @"MPNowPlayingInfoPropertyPlaybackProgress";
NSString *const MPNowPlayingInfoPropertyPlaybackQueueIndex = @"MPNowPlayingInfoPropertyPlaybackQueueIndex";
NSString *const MPNowPlayingInfoPropertyPlaybackQueueCount = @"MPNowPlayingInfoPropertyPlaybackQueueCount";
NSString *const MPNowPlayingInfoPropertyIsLiveStream = @"MPNowPlayingInfoPropertyIsLiveStream";
NSString *const MPNowPlayingInfoPropertyMediaType = @"MPNowPlayingInfoPropertyMediaType";

/* ---- events ------------------------------------------------------------------------- */

@implementation MPRemoteCommandEvent {
@package
    MPRemoteCommand *_command;
    NSTimeInterval _timestamp;
}
- (MPRemoteCommand *)command { return _command; }
- (NSTimeInterval)timestamp { return _timestamp; }
- (void)dealloc
{
    [_command release];
    [super dealloc];
}
@end
@implementation MPChangePlaybackPositionCommandEvent {
@package
    NSTimeInterval _position;
}
- (NSTimeInterval)positionTime { return _position; }
@end
@implementation MPChangeRepeatModeCommandEvent {
@package
    MPRepeatType _repeat;
}
- (MPRepeatType)repeatType { return _repeat; }
- (BOOL)preservesRepeatMode { return NO; }
@end
@implementation MPChangeShuffleModeCommandEvent {
@package
    MPShuffleType _shuffle;
}
- (MPShuffleType)shuffleType { return _shuffle; }
@end
@implementation MPSkipIntervalCommandEvent {
@package
    NSTimeInterval _interval;
}
- (NSTimeInterval)interval { return _interval; }
@end

/* ---- commands ----------------------------------------------------------------------- */

@interface FerryMPTarget : NSObject {
@public
    id target; /* not retained, as on a Mac */
    SEL action;
    MPRemoteCommandHandlerStatus (^handler)(MPRemoteCommandEvent *);
}
@end
@implementation FerryMPTarget
- (void)dealloc
{
    [handler release];
    [super dealloc];
}
@end

@implementation MPRemoteCommand {
    BOOL _enabled;
    NSMutableArray<FerryMPTarget *> *_targets;
}
- (instancetype)init
{
    if ((self = [super init])) {
        _enabled = YES;
        _targets = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_targets release];
    [super dealloc];
}
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)f { _enabled = f; }
- (void)addTarget:(id)target action:(SEL)action
{
    FerryMPTarget *t = [[[FerryMPTarget alloc] init] autorelease];
    t->target = target;
    t->action = action;
    [_targets addObject:t];
}
- (void)removeTarget:(id)target action:(SEL)action
{
    for (NSInteger i = (NSInteger)[_targets count] - 1; i >= 0; i--) {
        FerryMPTarget *t = _targets[(NSUInteger)i];
        if (t == target || (t->target == target && (action == NULL || t->action == action)))
            [_targets removeObjectAtIndex:(NSUInteger)i];
    }
}
- (void)removeTarget:(id)target { [self removeTarget:target action:NULL]; }
- (id)addTargetWithHandler:(MPRemoteCommandHandlerStatus (^)(MPRemoteCommandEvent *))handler
{
    FerryMPTarget *t = [[[FerryMPTarget alloc] init] autorelease];
    t->handler = [handler copy];
    [_targets addObject:t];
    return t;
}
- (Class)_ferryEventClass { return [MPRemoteCommandEvent class]; }
/* sends the command to its targets, as the system would; Ferry's own
 * media keys and tests use it */
- (MPRemoteCommandHandlerStatus)_ferrySend:(MPRemoteCommandEvent *)event
{
    if (!_enabled || ![_targets count])
        return MPRemoteCommandHandlerStatusCommandFailed;
    MPRemoteCommandHandlerStatus status = MPRemoteCommandHandlerStatusSuccess;
    for (FerryMPTarget *t in [[_targets copy] autorelease]) {
        if (t->handler)
            status = t->handler(event);
        else if (t->target && t->action)
            status = ((MPRemoteCommandHandlerStatus (*)(id, SEL, id))objc_msgSend)(t->target, t->action, event);
    }
    return status;
}
- (MPRemoteCommandHandlerStatus)_ferrySend
{
    MPRemoteCommandEvent *e = [[[[self _ferryEventClass] alloc] init] autorelease];
    e->_command = [self retain];
    e->_timestamp = [[NSProcessInfo processInfo] systemUptime];
    return [self _ferrySend:e];
}
@end
@implementation MPSkipIntervalCommand {
    NSArray *_intervals;
}
- (void)dealloc
{
    [_intervals release];
    [super dealloc];
}
- (NSArray<NSNumber *> *)preferredIntervals { return _intervals ?: @[]; }
- (void)setPreferredIntervals:(NSArray<NSNumber *> *)a
{
    [_intervals autorelease];
    _intervals = [a copy];
}
- (Class)_ferryEventClass { return [MPSkipIntervalCommandEvent class]; }
@end
@implementation MPChangePlaybackPositionCommand
- (Class)_ferryEventClass { return [MPChangePlaybackPositionCommandEvent class]; }
@end
@implementation MPChangeRepeatModeCommand
@synthesize currentRepeatType;
- (Class)_ferryEventClass { return [MPChangeRepeatModeCommandEvent class]; }
@end
@implementation MPChangeShuffleModeCommand
@synthesize currentShuffleType;
- (Class)_ferryEventClass { return [MPChangeShuffleModeCommandEvent class]; }
@end
@implementation MPFeedbackCommand {
    NSString *_title;
}
@synthesize active;
- (void)dealloc
{
    [_title release];
    [super dealloc];
}
- (NSString *)localizedTitle { return _title; }
- (void)setLocalizedTitle:(NSString *)s
{
    [_title autorelease];
    _title = [s copy];
}
@end
@implementation MPRatingCommand
@synthesize minimumRating, maximumRating;
@end

@implementation MPRemoteCommandCenter {
    NSMutableDictionary<NSString *, MPRemoteCommand *> *_commands;
}
+ (MPRemoteCommandCenter *)sharedCommandCenter
{
    static MPRemoteCommandCenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[MPRemoteCommandCenter alloc] init]; });
    return shared;
}
- (instancetype)init
{
    if ((self = [super init]))
        _commands = [[NSMutableDictionary alloc] init];
    return self;
}
- (id)_ferryCommand:(NSString *)name class:(Class)c
{
    @synchronized(self) {
        MPRemoteCommand *cmd = _commands[name];
        if (!cmd) {
            cmd = [[[c alloc] init] autorelease];
            _commands[name] = cmd;
        }
        return cmd;
    }
}
#define COMMAND(getter, cls) \
    - (cls *)getter { return [self _ferryCommand:@#getter class:[cls class]]; }
COMMAND(pauseCommand, MPRemoteCommand)
COMMAND(playCommand, MPRemoteCommand)
COMMAND(stopCommand, MPRemoteCommand)
COMMAND(togglePlayPauseCommand, MPRemoteCommand)
COMMAND(enableLanguageOptionCommand, MPRemoteCommand)
COMMAND(disableLanguageOptionCommand, MPRemoteCommand)
COMMAND(nextTrackCommand, MPRemoteCommand)
COMMAND(previousTrackCommand, MPRemoteCommand)
COMMAND(seekForwardCommand, MPRemoteCommand)
COMMAND(seekBackwardCommand, MPRemoteCommand)
COMMAND(skipForwardCommand, MPSkipIntervalCommand)
COMMAND(skipBackwardCommand, MPSkipIntervalCommand)
COMMAND(changePlaybackPositionCommand, MPChangePlaybackPositionCommand)
COMMAND(changePlaybackRateCommand, MPRemoteCommand)
COMMAND(changeRepeatModeCommand, MPChangeRepeatModeCommand)
COMMAND(changeShuffleModeCommand, MPChangeShuffleModeCommand)
COMMAND(ratingCommand, MPRatingCommand)
COMMAND(likeCommand, MPFeedbackCommand)
COMMAND(dislikeCommand, MPFeedbackCommand)
COMMAND(bookmarkCommand, MPFeedbackCommand)
@end

/* ---- artwork and Now Playing ---------------------------------------------------------- */

@implementation MPMediaItemArtwork {
    CGSize _size;
    NSImage * (^_handler)(CGSize);
}
- (instancetype)initWithBoundsSize:(CGSize)size requestHandler:(NSImage * (^)(CGSize))handler
{
    if ((self = [super init])) {
        _size = size;
        _handler = [handler copy];
    }
    return self;
}
- (void)dealloc
{
    [_handler release];
    [super dealloc];
}
- (CGRect)bounds { return CGRectMake(0, 0, _size.width, _size.height); }
- (NSImage *)imageWithSize:(CGSize)size { return _handler ? _handler(size) : nil; }
@end

@implementation MPNowPlayingInfoCenter {
    NSDictionary *_info;
    MPNowPlayingPlaybackState _state;
}
+ (MPNowPlayingInfoCenter *)defaultCenter
{
    static MPNowPlayingInfoCenter *center;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ center = [[MPNowPlayingInfoCenter alloc] init]; });
    return center;
}
- (NSDictionary<NSString *, id> *)nowPlayingInfo
{
    @synchronized(self) {
        return [[_info retain] autorelease];
    }
}
- (void)setNowPlayingInfo:(NSDictionary<NSString *, id> *)info
{
    @synchronized(self) {
        [_info autorelease];
        _info = [info copy];
    }
}
- (MPNowPlayingPlaybackState)playbackState { return _state; }
- (void)setPlaybackState:(MPNowPlayingPlaybackState)s { _state = s; }
@end
