/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Quartz Composer's view (freemac 1.222, Ferry 0.46.0),
 * written for freemac from Apple's public documentation; not Apple's
 * header. A composition's patches are Apple's own and undocumented, so
 * Ferry can't run one: loading one fails, with a note the first time, and
 * the view shows its erase colour. Included from Quartz.h. */
#import <AppKit/AppKit.h>

@class QCComposition;

APPKIT_EXTERN NSString *const QCViewDidStartRenderingNotification;
APPKIT_EXTERN NSString *const QCViewDidStopRenderingNotification;
APPKIT_EXTERN NSString *const QCCompositionInputXKey;
APPKIT_EXTERN NSString *const QCCompositionInputYKey;

@interface QCView : NSView
- (BOOL)loadCompositionFromFile:(NSString *)path;
- (BOOL)loadComposition:(QCComposition *)composition;
- (QCComposition *)loadedComposition;
- (void)unloadComposition;
@property BOOL autostartsRendering;
- (BOOL)startRendering;
- (void)stopRendering;
- (BOOL)isRendering;
- (void)pauseRendering;
- (void)resumeRendering;
- (BOOL)isPausedRendering;
- (IBAction)start:(id)sender;
- (IBAction)stop:(id)sender;
- (IBAction)play:(id)sender;
@property (retain) NSColor *eraseColor;
- (void)erase;
@property float maxRenderingFrameRate;
- (NSImage *)snapshotImage;
- (id)createSnapshotImageOfType:(NSString *)type;
- (BOOL)setValue:(id)value forInputKey:(NSString *)key;
- (id)valueForInputKey:(NSString *)key;
- (id)valueForOutputKey:(NSString *)key;
@end
