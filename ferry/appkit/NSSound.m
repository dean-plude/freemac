/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: sounds (NSSound), written from Apple's public API
 * documentation.
 *
 * A sound is a file played by the system's own player: pw-play
 * (PipeWire), else paplay (PulseAudio), else aplay (ALSA), or the program
 * FERRY_SOUND_PLAYER names. Each play starts the player on the file; the
 * sound polls it and, when it ends, plays it again if it loops or tells
 * its delegate sound:didFinishPlaying: YES. stop ends the player (the
 * delegate hears NO), pause and resume stop and continue it. The volume
 * is passed to the player when it starts. A sound made from data is
 * written to a temporary file first. The duration is read from a WAV
 * file's header; other kinds report 0. Setting currentTime while playing
 * can't move the player along, so it is only kept.
 *
 * soundNamed: finds a sound registered with setName:, then one in the
 * app's bundle, then one of the system's. A Mac's system sounds are
 * Apple's own and aren't here; their names play freemac's own sounds
 * from /usr/share/sounds/freemac (or FERRY_SOUNDS_DIR) instead, if they
 * are installed, and freemac's own names ("pop", "alert-bell") work too. */
#import "AInternal.h"
#include <signal.h>
#include <sys/wait.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static NSMutableDictionary *named_sounds(void)
{
    static NSMutableDictionary *d;
    if (!d)
        d = [[NSMutableDictionary alloc] init];
    return d;
}

static NSString *sounds_dir(void)
{
    const char *env = getenv("FERRY_SOUNDS_DIR");
    return env && *env ? [NSString stringWithUTF8String:env] : @"/usr/share/sounds/freemac";
}

/* A Mac's system sound names, and freemac's sounds that stand in for them. */
static NSString *freemac_name_for(NSString *mac)
{
    static NSDictionary *map;
    if (!map)
        map = [@{
            @"Basso" : @"alert-hum", @"Blow" : @"alert-droplet", @"Bottle" : @"alert-droplet",
            @"Frog" : @"alert-chirp", @"Funk" : @"alert-knock", @"Glass" : @"alert-bell",
            @"Hero" : @"alert-bell", @"Morse" : @"tick", @"Ping" : @"alert-bell", @"Pop" : @"pop",
            @"Purr" : @"alert-hum", @"Sosumi" : @"alert-pebble", @"Submarine" : @"alert-hum",
            @"Tink" : @"alert-pebble",
        } retain];
    return map[mac];
}

static NSArray *sound_extensions(void)
{
    return @[ @"aiff", @"aif", @"wav", @"caf", @"mp3", @"m4a", @"flac", @"ogg", @"oga", @"snd", @"au" ];
}

/* The seconds a WAV file plays for, from its header, or 0. */
static NSTimeInterval wav_duration(NSString *path)
{
    unsigned char b[4096];
    FILE *f = fopen([path fileSystemRepresentation], "rb");
    if (!f)
        return 0;
    NSUInteger n = fread(b, 1, sizeof b, f);
    fclose(f);
    if (n < 12 || memcmp(b, "RIFF", 4) || memcmp(b + 8, "WAVE", 4))
        return 0;
    uint32_t rate = 0, dataSize = 0;
    for (NSUInteger i = 12; i + 8 <= n;) {
        uint32_t size = b[i + 4] | b[i + 5] << 8 | b[i + 6] << 16 | (uint32_t)b[i + 7] << 24;
        if (!memcmp(b + i, "fmt ", 4) && i + 20 <= n)
            rate = b[i + 16] | b[i + 17] << 8 | b[i + 18] << 16 | (uint32_t)b[i + 19] << 24;   /* bytes a second */
        if (!memcmp(b + i, "data", 4)) {
            dataSize = size;
            break;
        }
        i += 8 + size + (size & 1);
    }
    return rate && dataSize ? (NSTimeInterval)dataSize / rate : 0;
}

/* The extension data should be written with. */
static NSString *extension_for_data(NSData *data)
{
    const unsigned char *b = [data bytes];
    NSUInteger n = [data length];
    if (n >= 12 && !memcmp(b, "RIFF", 4))
        return @"wav";
    if (n >= 12 && !memcmp(b, "FORM", 4))
        return @"aiff";
    if (n >= 4 && !memcmp(b, "caff", 4))
        return @"caf";
    if (n >= 4 && !memcmp(b, "OggS", 4))
        return @"ogg";
    if (n >= 4 && !memcmp(b, "fLaC", 4))
        return @"flac";
    if (n >= 3 && (!memcmp(b, "ID3", 3) || (b[0] == 0xff && (b[1] & 0xe0) == 0xe0)))
        return @"mp3";
    if (n >= 8 && !memcmp(b + 4, "ftyp", 4))
        return @"m4a";
    return @"snd";
}

@implementation NSSound {
    NSString *_path, *_name;
    BOOL _temporary;          /* our own copy of data, removed with us */
    id _delegate;
    float _volume;
    BOOL _loops, _paused, _stopping;
    int _pid;
    NSTimer *_poll;
    NSTimeInterval _startedAt, _pausedAt, _currentTime;
}

+ (NSArray *)soundUnfilteredTypes
{
    return @[
        @"com.microsoft.waveform-audio", @"public.aiff-audio", @"public.aifc-audio", @"com.apple.coreaudio-format",
        @"public.mp3", @"public.mpeg-4-audio", @"org.xiph.flac", @"org.xiph.ogg-audio", @"public.ulaw-audio",
    ];
}
+ (NSArray *)soundUnfilteredFileTypes { return sound_extensions(); }
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)pb { return NO; }

+ (NSSound *)soundNamed:(NSSoundName)name
{
    if (![name length])
        return nil;
    NSSound *s = named_sounds()[name];
    if (s)
        return s;
    NSString *path = nil;
    NSString *base = [name stringByDeletingPathExtension], *ext = [name pathExtension];
    NSBundle *bundle = [NSBundle mainBundle];
    if ([ext length])
        path = [bundle pathForResource:base ofType:ext];
    for (NSString *e in sound_extensions())
        if (!path)
            path = [bundle pathForResource:name ofType:e];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = sounds_dir();
    for (NSString *n in @[ freemac_name_for(name) ?: name, name ])
        for (NSString *e in sound_extensions()) {
            if (path)
                break;
            NSString *p = [[dir stringByAppendingPathComponent:n] stringByAppendingPathExtension:e];
            if ([fm isReadableFileAtPath:p])
                path = p;
        }
    if (!path)
        return nil;
    s = [[[NSSound alloc] initWithContentsOfFile:path byReference:YES] autorelease];
    [s setName:name];
    return s;
}

- (instancetype)initWithContentsOfFile:(NSString *)path byReference:(BOOL)byRef
{
    if (!(self = [super init]))
        return nil;
    if (![path length] || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        [self release];
        return nil;
    }
    _path = [path copy];
    _volume = 1;
    return self;
}
- (instancetype)initWithContentsOfURL:(NSURL *)url byReference:(BOOL)byRef
{
    if (![url isFileURL]) {
        NSData *d = url ? [NSData dataWithContentsOfURL:url] : nil;
        return d ? [self initWithData:d] : ([self release], nil);
    }
    return [self initWithContentsOfFile:[url path] byReference:byRef];
}
- (instancetype)initWithData:(NSData *)data
{
    if (![data length]) {
        [self release];
        return nil;
    }
    NSString *file = [NSString stringWithFormat:@"ferry-sound-%d-%p.%@", getpid(), (void *)self, extension_for_data(data)];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:file];
    if (![data writeToFile:path atomically:NO]) {
        [self release];
        return nil;
    }
    if ((self = [self initWithContentsOfFile:path byReference:NO]))
        _temporary = YES;
    return self;
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    NSData *data = [coder decodeObjectForKey:@"NSSoundData"];
    NSString *path = [coder decodeObjectForKey:@"NSSoundPath"];
    if ([data isKindOfClass:[NSData class]])
        self = [self initWithData:data];
    else if ([path isKindOfClass:[NSString class]])
        self = [self initWithContentsOfFile:path byReference:YES];
    else {
        [self release];
        return nil;
    }
    if (self && [coder containsValueForKey:@"NSVolume"])
        _volume = [coder decodeFloatForKey:@"NSVolume"];
    return self;
}
- (void)encodeWithCoder:(NSCoder *)coder
{
    if (_temporary)
        [coder encodeObject:[NSData dataWithContentsOfFile:_path] forKey:@"NSSoundData"];
    else
        [coder encodeObject:_path forKey:@"NSSoundPath"];
    [coder encodeFloat:_volume forKey:@"NSVolume"];
}
- (id)copyWithZone:(NSZone *)zone
{
    NSSound *s = _temporary ? [[NSSound alloc] initWithData:[NSData dataWithContentsOfFile:_path]]
                            : [[NSSound alloc] initWithContentsOfFile:_path byReference:YES];
    s->_volume = _volume;
    s->_loops = _loops;
    s->_delegate = _delegate;
    return s;
}
- (void)dealloc
{
    [self _endPlayer];
    if (_temporary)
        [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [_path release];
    [_name release];
    [super dealloc];
}

- (NSSoundName)name { return _name; }
- (BOOL)setName:(NSSoundName)name
{
    NSMutableDictionary *d = named_sounds();
    if (name && d[name] && d[name] != self)
        return NO;
    if (_name && d[_name] == self)
        [d removeObjectForKey:_name];
    name = [name copy];
    [_name release];
    _name = name;
    if (name)
        d[name] = self;
    return YES;
}
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)d { _delegate = d; }
- (float)volume { return _volume; }
- (void)setVolume:(float)v { _volume = v < 0 ? 0 : v > 1 ? 1 : v; }
- (BOOL)loops { return _loops; }
- (void)setLoops:(BOOL)f { _loops = f; }
- (BOOL)isPlaying { return _pid > 0; }
- (NSTimeInterval)duration { return wav_duration(_path); }
- (NSTimeInterval)currentTime
{
    if (!_pid)
        return _currentTime;
    NSTimeInterval now = _paused ? _pausedAt : [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval t = now - _startedAt, d = [self duration];
    return d > 0 && t > d ? (_loops ? fmod(t, d) : d) : t;
}
- (void)setCurrentTime:(NSTimeInterval)t { _currentTime = fmax(0, t); }
- (NSString *)description { return [NSString stringWithFormat:@"<NSSound %@>", _name ?: [_path lastPathComponent]]; }

/* ---- the player ---- */

/* The player's command line for our file. */
- (NSArray *)_command
{
    const char *env = getenv("FERRY_SOUND_PLAYER");
    NSString *player = nil;
    if (env && *env) {
        player = [NSString stringWithUTF8String:env];
    } else {
        for (NSString *p in @[ @"pw-play", @"paplay", @"aplay" ]) {
            char *found = g_find_program_in_path([p UTF8String]);
            if (found) {
                player = [NSString stringWithUTF8String:found];
                g_free(found);
                break;
            }
        }
    }
    if (!player)
        return nil;
    NSString *tool = [player lastPathComponent];
    if ([tool isEqualToString:@"aplay"])
        return @[ player, @"-q", _path ];
    if ([tool isEqualToString:@"paplay"])
        return @[ player, [NSString stringWithFormat:@"--volume=%d", (int)(_volume * 65536 + 0.5f)], _path ];
    return @[ player, [NSString stringWithFormat:@"--volume=%.2f", _volume], _path ];
}
- (BOOL)_startPlayer
{
    NSArray *cmd = [self _command];
    if (!cmd) {
        AWarnOnce("sounds (no pw-play, paplay or aplay was found to play them)");
        return NO;
    }
    char *argv[8];
    NSUInteger n = 0;
    for (NSString *a in cmd)
        argv[n++] = (char *)[a fileSystemRepresentation];
    argv[n] = NULL;
    GError *error = NULL;
    int pid = 0;
    BOOL ok = g_spawn_async(NULL, argv, NULL, G_SPAWN_DO_NOT_REAP_CHILD | G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                            NULL, NULL, &pid, &error) != 0;
    if (error)
        g_error_free(error);
    if (!ok || pid <= 0)
        return NO;
    _pid = pid;
    _startedAt = [NSDate timeIntervalSinceReferenceDate];
    return YES;
}
- (void)_endPlayer
{
    [_poll invalidate];
    [_poll release];
    _poll = nil;
    if (_pid > 0) {
        if (_paused)
            kill(_pid, SIGCONT);
        kill(_pid, SIGTERM);
        int status;
        waitpid(_pid, &status, 0);
    }
    _pid = 0;
    _paused = NO;
}
- (void)_check:(NSTimer *)t
{
    if (_pid <= 0)
        return;
    int status;
    if (waitpid(_pid, &status, WNOHANG) != _pid)
        return;
    _pid = 0;
    if (_loops && [self _startPlayer])
        return;
    [[self retain] autorelease];
    [_poll invalidate];
    [_poll release];
    _poll = nil;
    _currentTime = 0;
    if ([_delegate respondsToSelector:@selector(sound:didFinishPlaying:)])
        [_delegate sound:self didFinishPlaying:YES];
    [self release];   /* the hold play took */
}

- (BOOL)play
{
    if (_pid > 0 || ![self _startPlayer])
        return NO;
    [self retain];   /* a sound plays to its end even if nobody keeps it */
    _poll = [[NSTimer timerWithTimeInterval:0.05 target:self selector:@selector(_check:) userInfo:nil repeats:YES] retain];
    [[NSRunLoop currentRunLoop] addTimer:_poll forMode:NSRunLoopCommonModes];
    return YES;
}
- (BOOL)stop
{
    if (_pid <= 0)
        return NO;
    [[self retain] autorelease];
    [self _endPlayer];
    _currentTime = 0;
    if ([_delegate respondsToSelector:@selector(sound:didFinishPlaying:)])
        [_delegate sound:self didFinishPlaying:NO];
    [self release];
    return YES;
}
- (BOOL)pause
{
    if (_pid <= 0 || _paused)
        return NO;
    if (kill(_pid, SIGSTOP) != 0)
        return NO;
    _paused = YES;
    _pausedAt = [NSDate timeIntervalSinceReferenceDate];
    return YES;
}
- (BOOL)resume
{
    if (_pid <= 0 || !_paused)
        return NO;
    if (kill(_pid, SIGCONT) != 0)
        return NO;
    _paused = NO;
    _startedAt += [NSDate timeIntervalSinceReferenceDate] - _pausedAt;
    return YES;
}
@end
