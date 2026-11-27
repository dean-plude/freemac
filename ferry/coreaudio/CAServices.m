/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * System sounds and audio unit event listeners (freemac 1.263, Ferry
 * 0.86.0). Written from Apple's public documentation of AudioServices.h
 * and AudioUnitUtilities.h; not Apple's header.
 *
 * A system sound is a file the program names; playing one asks the
 * desktop's sound player to play it and calls the completion when it ends.
 * An event listener hears parameter changes that a program announces with
 * AUParameterListenerNotify or AUEventListenerNotify, on the run loop it
 * was made with.
 */
#import "CAInternal.h"
#import <Foundation/Foundation.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

typedef UInt32 SystemSoundID;
typedef void (*AudioServicesSystemSoundCompletionProc)(SystemSoundID ssID, void *clientData);

enum { kAudioServicesNoError = 0, kAudioServicesBadSpecifierSizeError = 'siz?',
       kAudioServicesSystemSoundUnspecifiedError = -1500, kAudioServicesSystemSoundClientTimedOutError = -1501 };

static NSMutableDictionary *sounds;     /* SystemSoundID -> path */
static NSMutableDictionary *completions; /* SystemSoundID -> NSValue pair */
static SystemSoundID next_sound = 0x1000;

static void sounds_init(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sounds = [NSMutableDictionary new];
        completions = [NSMutableDictionary new];
    });
}

OSStatus AudioServicesCreateSystemSoundID(CFURLRef inFileURL, SystemSoundID *outSystemSoundID)
{
    if (!inFileURL || !outSystemSoundID) return paramErr;
    sounds_init();
    NSString *path = [(__bridge NSURL *)inFileURL path];
    if (!path || access(path.fileSystemRepresentation, R_OK) != 0) return kAudioServicesSystemSoundUnspecifiedError;
    @synchronized (sounds) {
        *outSystemSoundID = next_sound++;
        sounds[@(*outSystemSoundID)] = path;
    }
    return noErr;
}

OSStatus AudioServicesDisposeSystemSoundID(SystemSoundID inSystemSoundID)
{
    sounds_init();
    @synchronized (sounds) {
        [sounds removeObjectForKey:@(inSystemSoundID)];
        [completions removeObjectForKey:@(inSystemSoundID)];
    }
    return noErr;
}

OSStatus AudioServicesAddSystemSoundCompletion(SystemSoundID inSystemSoundID, CFRunLoopRef inRunLoop,
                                               CFStringRef inRunLoopMode,
                                               AudioServicesSystemSoundCompletionProc inCompletionRoutine,
                                               void *inClientData)
{
    (void)inRunLoop; (void)inRunLoopMode;
    sounds_init();
    @synchronized (sounds) {
        completions[@(inSystemSoundID)] = @[ [NSValue valueWithPointer:(void *)inCompletionRoutine],
                                             [NSValue valueWithPointer:inClientData] ];
    }
    return noErr;
}

void AudioServicesRemoveSystemSoundCompletion(SystemSoundID inSystemSoundID)
{
    sounds_init();
    @synchronized (sounds) { [completions removeObjectForKey:@(inSystemSoundID)]; }
}

/* plays the file with the desktop's player (pw-play or paplay), then
 * calls the completion on the main queue */
static void play(SystemSoundID sid, void (^done)(void))
{
    sounds_init();
    NSString *path;
    NSArray *completion;
    @synchronized (sounds) {
        path = sounds[@(sid)];
        completion = completions[@(sid)];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (path) {
            const char *players[] = { "pw-play", "paplay" };
            for (int i = 0; i < 2; i++) {
                char *argv[] = { (char *)players[i], (char *)path.fileSystemRepresentation, NULL };
                pid_t pid;
                if (posix_spawnp(&pid, players[i], NULL, NULL, argv, environ) == 0) {
                    int st;
                    waitpid(pid, &st, 0);
                    if (WIFEXITED(st) && WEXITSTATUS(st) != 127) break;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                AudioServicesSystemSoundCompletionProc proc = [completion[0] pointerValue];
                if (proc) proc(sid, [completion[1] pointerValue]);
            }
            if (done) done();
        });
    });
}

void AudioServicesPlaySystemSound(SystemSoundID inSystemSoundID) { play(inSystemSoundID, nil); }
void AudioServicesPlayAlertSound(SystemSoundID inSystemSoundID) { play(inSystemSoundID, nil); }

void AudioServicesPlaySystemSoundWithCompletion(SystemSoundID inSystemSoundID, void (^inCompletionBlock)(void))
{
    void (^copy)(void) = inCompletionBlock ? [inCompletionBlock copy] : nil;
    play(inSystemSoundID, copy);
}

void AudioServicesPlayAlertSoundWithCompletion(SystemSoundID inSystemSoundID, void (^inCompletionBlock)(void))
{
    AudioServicesPlaySystemSoundWithCompletion(inSystemSoundID, inCompletionBlock);
}

OSStatus AudioServicesGetPropertyInfo(UInt32 inPropertyID, UInt32 inSpecifierSize, const void *inSpecifier,
                                      UInt32 *outPropertyDataSize, Boolean *outWritable)
{
    (void)inPropertyID; (void)inSpecifierSize; (void)inSpecifier;
    if (outPropertyDataSize) *outPropertyDataSize = sizeof(UInt32);
    if (outWritable) *outWritable = true;
    return noErr;
}

OSStatus AudioServicesGetProperty(UInt32 inPropertyID, UInt32 inSpecifierSize, const void *inSpecifier,
                                  UInt32 *ioPropertyDataSize, void *outPropertyData)
{
    (void)inPropertyID; (void)inSpecifierSize; (void)inSpecifier;
    if (!ioPropertyDataSize || *ioPropertyDataSize < sizeof(UInt32) || !outPropertyData)
        return kAudioServicesBadSpecifierSizeError;
    *(UInt32 *)outPropertyData = 0;
    *ioPropertyDataSize = sizeof(UInt32);
    return noErr;
}

OSStatus AudioServicesSetProperty(UInt32 inPropertyID, UInt32 inSpecifierSize, const void *inSpecifier,
                                  UInt32 inPropertyDataSize, const void *inPropertyData)
{
    (void)inPropertyID; (void)inSpecifierSize; (void)inSpecifier; (void)inPropertyDataSize; (void)inPropertyData;
    return noErr;
}

/* ---- audio unit event listeners ----------------------------------------------------- */

typedef UInt32 AudioUnitEventType;
enum { kAudioUnitEvent_ParameterValueChange = 0, kAudioUnitEvent_BeginParameterChangeGesture = 1,
       kAudioUnitEvent_EndParameterChangeGesture = 2, kAudioUnitEvent_PropertyChange = 3 };

typedef struct AudioUnitEvent {
    AudioUnitEventType mEventType;
    union {
        AudioUnitParameter mParameter;
        AudioUnitProperty mProperty;
    } mArgument;
} AudioUnitEvent;

typedef void (*AUEventListenerProc)(void *inUserData, void *inObject, const AudioUnitEvent *inEvent,
                                    UInt64 inEventHostTime, AudioUnitParameterValue inParameterValue);
typedef void (*AUParameterListenerProc)(void *inUserData, void *inObject, const AudioUnitParameter *inParameter,
                                        AudioUnitParameterValue inValue);

@interface FerryAUListener : NSObject {
@public
    AUEventListenerProc eventProc;
    AUParameterListenerProc paramProc;
    void *userData;
    CFRunLoopRef runLoop;
    NSMutableArray *events; /* NSData of AudioUnitEvent, with the object as the event's key */
    NSMutableArray *objects;
}
@end
@implementation FerryAUListener
@end

static NSMutableArray *listeners;

static void listeners_init(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{ listeners = [NSMutableArray new]; });
}

static FerryAUListener *new_listener(CFRunLoopRef runLoop, void *userData)
{
    listeners_init();
    FerryAUListener *l = [FerryAUListener new];
    l->userData = userData;
    l->runLoop = runLoop ? (CFRunLoopRef)CFRetain(runLoop) : NULL;
    l->events = [NSMutableArray new];
    l->objects = [NSMutableArray new];
    @synchronized (listeners) { [listeners addObject:l]; }
    return l;
}

OSStatus AUEventListenerCreate(AUEventListenerProc inProc, void *inUserData, CFRunLoopRef inRunLoop,
                               CFStringRef inRunLoopMode, Float32 inNotificationInterval,
                               Float32 inValueChangeGranularity, void **outListener)
{
    (void)inRunLoopMode; (void)inNotificationInterval; (void)inValueChangeGranularity;
    if (!inProc || !outListener) return paramErr;
    FerryAUListener *l = new_listener(inRunLoop, inUserData);
    l->eventProc = inProc;
    *outListener = (__bridge void *)l;
    return noErr;
}

OSStatus AUListenerCreate(AUParameterListenerProc inProc, void *inUserData, CFRunLoopRef inRunLoop,
                          CFStringRef inRunLoopMode, Float32 inNotificationInterval, void **outListener)
{
    (void)inRunLoopMode; (void)inNotificationInterval;
    if (!inProc || !outListener) return paramErr;
    FerryAUListener *l = new_listener(inRunLoop, inUserData);
    l->paramProc = inProc;
    *outListener = (__bridge void *)l;
    return noErr;
}

OSStatus AUListenerDispose(void *inListener)
{
    if (!inListener) return paramErr;
    FerryAUListener *l = (__bridge FerryAUListener *)inListener;
    listeners_init();
    @synchronized (listeners) {
        if (l->runLoop) { CFRelease(l->runLoop); l->runLoop = NULL; }
        [listeners removeObjectIdenticalTo:l];
    }
    return noErr;
}

static OSStatus add_event(void *inListener, void *inObject, const AudioUnitEvent *ev)
{
    if (!inListener || !ev) return paramErr;
    FerryAUListener *l = (__bridge FerryAUListener *)inListener;
    @synchronized (listeners) {
        [l->events addObject:[NSData dataWithBytes:ev length:sizeof *ev]];
        [l->objects addObject:[NSValue valueWithPointer:inObject]];
    }
    return noErr;
}

static OSStatus remove_event(void *inListener, void *inObject, const AudioUnitEvent *ev)
{
    if (!inListener || !ev) return paramErr;
    FerryAUListener *l = (__bridge FerryAUListener *)inListener;
    NSData *key = [NSData dataWithBytes:ev length:sizeof *ev];
    @synchronized (listeners) {
        for (NSUInteger i = l->events.count; i-- > 0;)
            if ([l->events[i] isEqual:key] && [l->objects[i] pointerValue] == inObject) {
                [l->events removeObjectAtIndex:i];
                [l->objects removeObjectAtIndex:i];
            }
    }
    return noErr;
}

OSStatus AUEventListenerAddEventType(void *inListener, void *inObject, const AudioUnitEvent *inEvent)
{
    return add_event(inListener, inObject, inEvent);
}

OSStatus AUEventListenerRemoveEventType(void *inListener, void *inObject, const AudioUnitEvent *inEvent)
{
    return remove_event(inListener, inObject, inEvent);
}

OSStatus AUListenerAddParameter(void *inListener, void *inObject, const AudioUnitParameter *inParameter)
{
    if (!inParameter) return paramErr;
    AudioUnitEvent ev = { .mEventType = kAudioUnitEvent_ParameterValueChange };
    ev.mArgument.mParameter = *inParameter;
    return add_event(inListener, inObject, &ev);
}

OSStatus AUListenerRemoveParameter(void *inListener, void *inObject, const AudioUnitParameter *inParameter)
{
    if (!inParameter) return paramErr;
    AudioUnitEvent ev = { .mEventType = kAudioUnitEvent_ParameterValueChange };
    ev.mArgument.mParameter = *inParameter;
    return remove_event(inListener, inObject, &ev);
}

static BOOL same_target(const AudioUnitEvent *a, const AudioUnitEvent *b)
{
    if (a->mEventType != b->mEventType) return NO;
    if (a->mEventType == kAudioUnitEvent_PropertyChange)
        return a->mArgument.mProperty.mAudioUnit == b->mArgument.mProperty.mAudioUnit &&
               a->mArgument.mProperty.mPropertyID == b->mArgument.mProperty.mPropertyID &&
               a->mArgument.mProperty.mScope == b->mArgument.mProperty.mScope &&
               a->mArgument.mProperty.mElement == b->mArgument.mProperty.mElement;
    const AudioUnitParameter *p = &a->mArgument.mParameter, *q = &b->mArgument.mParameter;
    /* a parameter ID of 0xFFFFFFFF announces that every parameter of the unit changed */
    return p->mAudioUnit == q->mAudioUnit &&
           (p->mParameterID == q->mParameterID || q->mParameterID == 0xFFFFFFFFu) &&
           p->mScope == q->mScope && p->mElement == q->mElement;
}

/* tells every listener that asked for this event, except the one that sent it */
OSStatus AUEventListenerNotify(void *inSendingListener, void *inSendingObject, const AudioUnitEvent *inEvent)
{
    (void)inSendingObject;
    if (!inEvent) return paramErr;
    listeners_init();
    AudioUnitEvent ev = *inEvent;
    AudioUnitParameterValue value = 0;
    if (ev.mEventType == kAudioUnitEvent_ParameterValueChange && ev.mArgument.mParameter.mAudioUnit &&
        ev.mArgument.mParameter.mParameterID != 0xFFFFFFFFu)
        AudioUnitGetParameter(ev.mArgument.mParameter.mAudioUnit, ev.mArgument.mParameter.mParameterID,
                              ev.mArgument.mParameter.mScope, ev.mArgument.mParameter.mElement, &value);
    NSArray *all;
    @synchronized (listeners) { all = [listeners copy]; }
    for (FerryAUListener *l in all) {
        if ((__bridge void *)l == inSendingListener) continue;
        NSMutableArray *objs = [NSMutableArray new];
        @synchronized (listeners) {
            for (NSUInteger i = 0; i < l->events.count; i++)
                if (same_target((const AudioUnitEvent *)[l->events[i] bytes], &ev)) [objs addObject:l->objects[i]];
        }
        for (NSValue *obj in objs) {
            void *object = obj.pointerValue;
            UInt64 when = ca_now();
            void (^deliver)(void) = ^{
                if (l->eventProc) l->eventProc(l->userData, object, &ev, when, value);
                else if (l->paramProc && ev.mEventType == kAudioUnitEvent_ParameterValueChange)
                    l->paramProc(l->userData, object, &ev.mArgument.mParameter, value);
            };
            if (l->runLoop) {
                CFRunLoopPerformBlock(l->runLoop, kCFRunLoopCommonModes, deliver);
                CFRunLoopWakeUp(l->runLoop);
            } else {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), deliver);
            }
        }
    }
    return noErr;
}

OSStatus AUParameterListenerNotify(void *inSendingListener, void *inSendingObject, const AudioUnitParameter *inParameter)
{
    if (!inParameter) return paramErr;
    AudioUnitEvent ev = { .mEventType = kAudioUnitEvent_ParameterValueChange };
    ev.mArgument.mParameter = *inParameter;
    return AUEventListenerNotify(inSendingListener, inSendingObject, &ev);
}

OSStatus AUParameterSet(void *inSendingListener, void *inSendingObject, const AudioUnitParameter *inParameter,
                        AudioUnitParameterValue inValue, UInt32 inBufferOffsetInFrames)
{
    if (!inParameter) return paramErr;
    OSStatus st = AudioUnitSetParameter(inParameter->mAudioUnit, inParameter->mParameterID, inParameter->mScope,
                                        inParameter->mElement, inValue, inBufferOffsetInFrames);
    if (st == noErr) AUParameterListenerNotify(inSendingListener, inSendingObject, inParameter);
    return st;
}
