/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the app's tile in the Dock (appkit/NSDockTile.m), imported by
 * AppKit.h. The badge and attention requests reach the desktop's dock
 * through the com.canonical.Unity.LauncherEntry D-Bus signal, which
 * freemac's Dock reads. Written for freemac from Apple's public API
 * documentation; not Apple's header. */
#ifndef _FERRY_APPKIT_NSDOCKTILE_H_
#define _FERRY_APPKIT_NSDOCKTILE_H_
#import <Foundation/Foundation.h>

@class NSView;

@interface NSDockTile : NSObject
@property (readonly) NSSize size;
@property (retain) NSView *contentView;
- (void)display;
@property BOOL showsApplicationBadge;
@property (copy) NSString *badgeLabel;
@property (readonly, assign) id owner;
@end

typedef NS_ENUM(NSUInteger, NSRequestUserAttentionType) {
    NSCriticalRequest = 0,
    NSInformationalRequest = 10,
};

@interface NSApplication (NSDockTile)
@property (readonly, retain) NSDockTile *dockTile;
- (void)cancelUserAttentionRequest:(NSInteger)request;
@end

#endif
