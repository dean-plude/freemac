/* SPDX-License-Identifier: GPL-3.0-or-later
 * setFrame:display: takes the frame as asked (freemac 1.NEXT). A Mac asks
 * the delegate's windowWillResize:toSize: only while the user resizes the
 * window. VLC works out its window's frame to fit a video, top left where
 * the window's top left was, and its delegate's windowWillResize:toSize:
 * keeps the video's shape; when Ferry asked the delegate here too, the
 * window grew to another height under the top VLC had worked out and went
 * off the top of the screen. */
#import <Cocoa/Cocoa.h>

@interface Shape : NSObject <NSWindowDelegate>
@property int asked;
@end
@implementation Shape
- (NSSize)windowWillResize:(NSWindow *)w toSize:(NSSize)size
{
    self.asked++;
    return NSMakeSize(size.width, size.width * 3 / 4);   /* keeps 4:3 */
}
@end

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(50, 300, 640, 400)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:YES];
        Shape *d = [Shape new];
        [w setDelegate:d];
        CGFloat top = NSMaxY([w frame]);
        NSRect want = NSMakeRect(50, top - 276, 604, 276);
        [w setFrame:want display:NO];
        printf("set to 604x276 under the same top: got %s, top %s, delegate asked %d times\n",
               NSEqualRects([w frame], want) ? "the frame asked" : [NSStringFromRect([w frame]) UTF8String],
               NSMaxY([w frame]) == top ? "kept" : "moved", d.asked);
    }
    return 0;
}
