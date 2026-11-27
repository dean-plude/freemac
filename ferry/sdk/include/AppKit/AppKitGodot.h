/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * What the Godot engine's Mac build calls in AppKit besides (freemac Godot
 * work), written from Apple's public documentation; not Apple's header.
 * Implemented in appkit/AppKitGodot.m. Imported by AppKit.h. */
#ifndef _FERRY_APPKIT_GODOT_H_
#define _FERRY_APPKIT_GODOT_H_

/* ---- searching the Help menu ------------------------------------------------------------
 * A program's search handlers are kept. Ferry's Help menu has no search
 * field yet, so a handler is never asked to search; the string search the
 * handlers use works. */
@protocol NSUserInterfaceItemSearching <NSObject>
@required
- (void)searchForItemsWithSearchString:(NSString *)searchString
                           resultLimit:(NSInteger)resultLimit
                    matchedItemHandler:(void (^)(NSArray *items))handleMatchedItems;
- (NSArray<NSString *> *)localizedTitlesForItem:(id)item;
@optional
- (void)performActionForItem:(id)item;
- (void)showAllHelpTopicsForSearchString:(NSString *)searchString;
@end
@interface NSApplication (FerryHelpSearch)
- (void)registerUserInterfaceItemSearchHandler:(id<NSUserInterfaceItemSearching>)handler;
- (void)unregisterUserInterfaceItemSearchHandler:(id<NSUserInterfaceItemSearching>)handler;
- (BOOL)searchString:(NSString *)searchString
    inUserInterfaceItemString:(NSString *)stringToSearch
                  searchRange:(NSRange)searchRange
                   foundRange:(NSRange *)foundRange;
@end

/* ---- the title bar, the screen and opening with an application ------------------------- */
@interface NSWindow (FerryGodot)
@property (readonly) NSUserInterfaceLayoutDirection windowTitlebarLayoutDirection;
@end
@interface NSScreen (FerryGodot)
@property (readonly) NSInteger maximumFramesPerSecond;
@end
@interface NSWorkspace (FerryGodot)
- (void)openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)applicationURL
        configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^)(NSRunningApplication *app, NSError *error))handler;
@end

@interface NSMenu (FerryGodot)
@property NSUserInterfaceLayoutDirection userInterfaceLayoutDirection;
@end

#endif
