/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSAnimation and NSViewAnimation (appkit/NSAnimation.m),
 * imported by AppKit.h. Written for freemac from Apple's public API
 * documentation; not Apple's header. */
#ifndef _FERRY_APPKIT_NSANIMATION_H_
#define _FERRY_APPKIT_NSANIMATION_H_
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, NSAnimationCurve) {
    NSAnimationEaseInOut = 0,
    NSAnimationEaseIn = 1,
    NSAnimationEaseOut = 2,
    NSAnimationLinear = 3,
};

typedef NS_ENUM(NSUInteger, NSAnimationBlockingMode) {
    NSAnimationBlocking = 0,
    NSAnimationNonblocking = 1,
    NSAnimationNonblockingThreaded = 2,
};

typedef float NSAnimationProgress;

APPKIT_EXTERN NSNotificationName const NSAnimationProgressMarkNotification;
APPKIT_EXTERN NSString *const NSAnimationProgressMark;

@protocol NSAnimationDelegate;

@interface NSAnimation : NSObject <NSCopying, NSCoding>
- (instancetype FERRY_SWIFT_NONNULL)initWithDuration:(NSTimeInterval)duration animationCurve:(NSAnimationCurve)animationCurve;
- (void)startAnimation;
- (void)stopAnimation;
@property (readonly, getter=isAnimating) BOOL animating;
@property NSAnimationProgress currentProgress;
@property NSTimeInterval duration;
@property NSAnimationBlockingMode animationBlockingMode;
@property float frameRate;
@property NSAnimationCurve animationCurve;
@property (readonly) float currentValue;
@property (assign) id<NSAnimationDelegate> delegate;
@property (copy) NSArray<NSNumber *> *progressMarks;
- (void)addProgressMark:(NSAnimationProgress)progressMark;
- (void)removeProgressMark:(NSAnimationProgress)progressMark;
- (void)startWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)startProgress;
- (void)stopWhenAnimation:(NSAnimation *)animation reachesProgress:(NSAnimationProgress)stopProgress;
- (void)clearStartAnimation;
- (void)clearStopAnimation;
@property (readonly, copy) NSArray<NSRunLoopMode> *runLoopModesForAnimating;
@end

@protocol NSAnimationDelegate <NSObject>
@optional
- (BOOL)animationShouldStart:(NSAnimation *)animation;
- (void)animationDidStop:(NSAnimation *)animation;
- (void)animationDidEnd:(NSAnimation *)animation;
- (float)animation:(NSAnimation *)animation valueForProgress:(NSAnimationProgress)progress;
- (void)animation:(NSAnimation *)animation didReachProgressMark:(NSAnimationProgress)progress;
@end

typedef NSString *NSViewAnimationKey;
APPKIT_EXTERN NSViewAnimationKey const NSViewAnimationTargetKey;
APPKIT_EXTERN NSViewAnimationKey const NSViewAnimationStartFrameKey;
APPKIT_EXTERN NSViewAnimationKey const NSViewAnimationEndFrameKey;
APPKIT_EXTERN NSViewAnimationKey const NSViewAnimationEffectKey;
typedef NSString *NSViewAnimationEffectName;
APPKIT_EXTERN NSViewAnimationEffectName const NSViewAnimationFadeInEffect;
APPKIT_EXTERN NSViewAnimationEffectName const NSViewAnimationFadeOutEffect;

@interface NSViewAnimation : NSAnimation
- (instancetype FERRY_SWIFT_NONNULL)initWithViewAnimations:(NSArray<NSDictionary<NSViewAnimationKey, id> *> *)viewAnimations;
@property (copy) NSArray<NSDictionary<NSViewAnimationKey, id> *> *viewAnimations;
@end

#endif
