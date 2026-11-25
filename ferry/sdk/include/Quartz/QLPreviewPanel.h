/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Quick Look's panel and view (freemac 1.222, Ferry 0.46.0),
 * written for freemac from Apple's public documentation; not Apple's
 * header. The shared panel shows its items one at a time: the file's icon
 * and name above, and below a picture, the start of a text file, or the
 * icon again, larger, for anything else; the arrow keys move between the
 * items and Escape or Space closes it. Its controller is the first object
 * in the responder chain of the main window (then the window's delegate,
 * the application and its delegate) that accepts to control it. Included
 * from Quartz.h. */
#import <AppKit/AppKit.h>

@protocol QLPreviewItem <NSObject>
@required
@property (readonly) NSURL *previewItemURL;
@optional
@property (readonly) NSString *previewItemTitle;
@property (readonly) id previewItemDisplayState;
@end

@interface NSURL (QLPreviewConvenienceAdditions) <QLPreviewItem>
@end

typedef NS_ENUM(NSUInteger, QLPreviewViewStyle) { QLPreviewViewStyleNormal = 0, QLPreviewViewStyleCompact = 1 };

/* one item's preview, as the panel shows it, for a window of one's own */
@interface QLPreviewView : NSView
- (instancetype)initWithFrame:(NSRect)frame style:(QLPreviewViewStyle)style;
- (instancetype)initWithFrame:(NSRect)frame;
@property (retain) id<QLPreviewItem> previewItem;
- (void)refreshPreviewItem;
@property (retain) id displayState;
- (void)close;
@property BOOL shouldCloseWithWindow;
@property BOOL autostarts;
@end

@class QLPreviewPanel;

@protocol QLPreviewPanelDataSource <NSObject>
- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel;
- (id<QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)index;
@end

@protocol QLPreviewPanelDelegate <NSWindowDelegate>
@optional
- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event;
- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id<QLPreviewItem>)item;
- (id)previewPanel:(QLPreviewPanel *)panel transitionImageForPreviewItem:(id<QLPreviewItem>)item
          contentRect:(NSRect *)contentRect;
@end

@interface QLPreviewPanel : NSPanel
+ (QLPreviewPanel *)sharedPreviewPanel;
+ (BOOL)sharedPreviewPanelExists;
@property (readonly, retain) id currentController;
- (void)updateController;
@property (assign) id<QLPreviewPanelDataSource> dataSource;
@property (assign) id<QLPreviewPanelDelegate> delegate;
- (void)reloadData;
- (void)refreshCurrentPreviewItem;
@property NSInteger currentPreviewItemIndex;
@property (readonly) id<QLPreviewItem> currentPreviewItem;
@property (retain) id displayState;
- (BOOL)enterFullScreenMode:(NSScreen *)screen withOptions:(NSDictionary *)options;
- (void)exitFullScreenModeWithOptions:(NSDictionary *)options;
@property (readonly, getter=isInFullScreenMode) BOOL inFullScreenMode;
@end

/* what a controller of the panel answers, in the responder chain */
@interface NSObject (QLPreviewPanelController)
- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel;
- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel;
- (void)endPreviewPanelControl:(QLPreviewPanel *)panel;
@end
