/* SPDX-License-Identifier: GPL-3.0-or-later
 * What OBS's Qt asks of a Mac for its lists and pop-up menus (freemac
 * 1.246, Ferry 0.69.0), with no display: a pop-up button cell's
 * performClickWithFrame:inView: tracks its menu until it closes before
 * it returns, the choice made or not, as on a Mac; a window that can't
 * become key (a pop-up menu) is never made key; and a number read as a
 * pointer gives its value, as OBS reads a screen's number. */
#import <Cocoa/Cocoa.h>

@interface NSWindow (FerryPeek)
- (NSView *)_overlayView;
@end
@interface NSView (FerryMenuView)   /* Ferry's in-window menu */
- (void)highlightItemAtIndex:(NSInteger)index;
- (void)chooseHighlightedItem;
- (void)dismiss;
@end

@interface Keyless : NSPanel
@end
@implementation Keyless
- (BOOL)canBecomeKeyWindow { return NO; }
@end

@interface Picker : NSObject
@property (strong) NSWindow *window;
@property NSInteger pick;   /* the item to choose, or -1 to close the menu */
@property BOOL sawOpen;
@property int fired;
@end
@implementation Picker
- (void)act:(NSTimer *)t
{
    self.fired++;
    NSView *open = [self.window _overlayView];
    self.sawOpen = [open isKindOfClass:NSClassFromString(@"AMenuView")];
    if (self.pick >= 0) {
        [open highlightItemAtIndex:self.pick];
        [open chooseHighlightedItem];
    } else
        [open dismiss];
}
@end

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 200)
                                                  styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered
                                                      defer:NO];
        [w makeKeyAndOrderFront:nil];
        NSView *content = w.contentView;

        Picker *picker = [Picker new];
        picker.window = w;
        for (NSInteger pick = 1; pick >= -1; pick -= 2) {
            NSPopUpButtonCell *cell = [[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO];
            [cell addItemsWithTitles:@[ @"Display 1", @"Display 2", @"Display 3" ]];
            cell.menu.autoenablesItems = NO;   /* as Qt's menus */
            [cell selectItemAtIndex:0];
            picker.pick = pick;
            picker.fired = 0;
            NSTimer *t = [NSTimer timerWithTimeInterval:0.05 target:picker selector:@selector(act:) userInfo:nil
                                                repeats:NO];
            [[NSRunLoop currentRunLoop] addTimer:t forMode:NSEventTrackingRunLoopMode];
            [cell performClickWithFrame:NSMakeRect(20, 20, 160, 24) inView:content];
            printf("cell click (%s): returned after the menu %s, open meanwhile %d, closed now %d, selected %s\n",
                   pick >= 0 ? "choose" : "close", picker.fired == 1 ? "closed" : "was still open", picker.sawOpen,
                   [w _overlayView] == nil, cell.titleOfSelectedItem.UTF8String);
        }

        Keyless *menu = [[Keyless alloc] initWithContentRect:NSMakeRect(20, 20, 120, 80)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered defer:NO];
        menu.level = NSPopUpMenuWindowLevel;
        [menu orderFront:nil];
        [menu makeKeyWindow];
        printf("keyless window: shown %d, key %d, the window still key %d\n", menu.isVisible, menu.isKeyWindow,
               w.isKeyWindow);

        NSNumber *screenNumber = @(1);
        printf("number as pointer: %lu, zero %p\n", (unsigned long)(uintptr_t)screenNumber.pointerValue,
               @(0).pointerValue);
    }
    return 0;
}
