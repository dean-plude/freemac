/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Picture in picture (freemac 1.262, Ferry 0.85.0): a small floating window
 * that keeps showing a view controller's view, such as a video, while its
 * own window is hidden. A Mac keeps this in a private framework with no
 * public documentation; these names are the ones apps such as IINA (whose
 * source is GPL) call, and Ferry's version is its own, written from that
 * use. No Apple code or header was read. Served from AppKit's file. */
#ifndef FERRY_PIP_H
#define FERRY_PIP_H
#import <AppKit/AppKit.h>

@class PIPViewController;

@protocol PIPViewControllerDelegate <NSObject>
@optional
- (BOOL)pipShouldClose:(PIPViewController *)pip;   /* the close button: may it close? */
- (void)pipWillClose:(PIPViewController *)pip;     /* the view is about to go back */
- (void)pipDidClose:(PIPViewController *)pip;      /* the floating window is gone */
- (void)pipActionPlay:(PIPViewController *)pip;
- (void)pipActionPause:(PIPViewController *)pip;
- (void)pipActionStop:(PIPViewController *)pip;
@end

@interface PIPViewController : NSViewController <NSWindowDelegate>
@property (assign) id<PIPViewControllerDelegate> delegate;
@property (copy) NSString *name;
@property (nonatomic) NSSize aspectRatio;         /* of the floating window's content */
@property NSSize minSize, maxSize;
@property BOOL playing;                /* which of play and pause the window offers */
@property BOOL userCanResize;
@property NSRect replacementRect;      /* where the view goes back to, in its window */
@property (assign) NSWindow *replacementWindow;
@property (assign) NSView *replacementView;
- (void)presentViewControllerAsPictureInPicture:(NSViewController *)viewController;
- (void)dismissViewController:(NSViewController *)viewController;
@end

#endif
