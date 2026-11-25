/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Touch Bar's classes (appkit/NSTouchBar.m), imported by
 * AppKit.h (freemac 1.223, Ferry 0.47.0). A PC has no Touch Bar, so a bar
 * is never shown: it holds its items, asks its delegate for them and
 * answers visible NO, which is what a Mac without one does. Apps (Sparkle's
 * windows among them) build their bars this way. Written for freemac from
 * Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_APPKIT_NSTOUCHBAR_H_
#define _FERRY_APPKIT_NSTOUCHBAR_H_
#import <Foundation/Foundation.h>

@class NSView, NSViewController, NSTouchBar, NSTouchBarItem, NSImage;

typedef NSString *NSTouchBarItemIdentifier;
typedef NSString *NSTouchBarCustomizationIdentifier;
typedef float NSTouchBarItemPriority;

static const NSTouchBarItemPriority NSTouchBarItemPriorityHigh = 1000;
static const NSTouchBarItemPriority NSTouchBarItemPriorityNormal = 0;
static const NSTouchBarItemPriority NSTouchBarItemPriorityLow = -1000;

APPKIT_EXTERN NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFixedSpaceSmall;
APPKIT_EXTERN NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFixedSpaceLarge;
APPKIT_EXTERN NSTouchBarItemIdentifier const NSTouchBarItemIdentifierFlexibleSpace;
APPKIT_EXTERN NSTouchBarItemIdentifier const NSTouchBarItemIdentifierOtherItemsProxy;

@protocol NSTouchBarDelegate <NSObject>
@optional
- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier;
@end

@protocol NSTouchBarProvider <NSObject>
@property (readonly, strong) NSTouchBar *touchBar;
@end

@interface NSTouchBar : NSObject <NSCoding>
- (instancetype)init;
- (instancetype)initWithCoder:(NSCoder *)coder;
@property (copy) NSTouchBarCustomizationIdentifier customizationIdentifier;
@property (copy) NSArray<NSTouchBarItemIdentifier> *customizationAllowedItemIdentifiers;
@property (copy) NSArray<NSTouchBarItemIdentifier> *customizationRequiredItemIdentifiers;
@property (copy) NSArray<NSTouchBarItemIdentifier> *defaultItemIdentifiers;
@property (copy, readonly) NSArray<NSTouchBarItemIdentifier> *itemIdentifiers;
@property (copy) NSTouchBarItemIdentifier principalItemIdentifier;
@property (copy) NSTouchBarItemIdentifier escapeKeyReplacementItemIdentifier;
@property (copy) NSSet<NSTouchBarItem *> *templateItems;
@property (weak) id<NSTouchBarDelegate> delegate;
- (__kindof NSTouchBarItem *)itemForIdentifier:(NSTouchBarItemIdentifier)identifier;
@property (readonly, getter=isVisible) BOOL visible;
@property (class, getter=isAutomaticCustomizeTouchBarMenuItemEnabled) BOOL automaticCustomizeTouchBarMenuItemEnabled;
@end

@interface NSTouchBarItem : NSObject <NSCoding>
- (instancetype)initWithIdentifier:(NSTouchBarItemIdentifier)identifier;
- (instancetype)initWithCoder:(NSCoder *)coder;
@property (readonly, copy) NSTouchBarItemIdentifier identifier;
@property NSTouchBarItemPriority visibilityPriority;
@property (readonly) NSView *view;
@property (readonly) NSViewController *viewController;
@property (readonly, copy) NSString *customizationLabel;
@property (readonly, getter=isVisible) BOOL visible;
@end

@interface NSCustomTouchBarItem : NSTouchBarItem
@property (readwrite, strong) NSView *view;
@property (readwrite, strong) NSViewController *viewController;
@property (readwrite, copy) NSString *customizationLabel;
@end

@interface NSGroupTouchBarItem : NSTouchBarItem
+ (instancetype)groupItemWithIdentifier:(NSTouchBarItemIdentifier)identifier items:(NSArray<NSTouchBarItem *> *)items;
@property (strong) NSTouchBar *groupTouchBar;
@property (readwrite, copy) NSString *customizationLabel;
@end

@interface NSResponder (NSTouchBarProvider) <NSTouchBarProvider>
/* the responder's bar, made by makeTouchBar the first time it is asked for */
@property (strong) NSTouchBar *touchBar;
- (NSTouchBar *)makeTouchBar;
@end

#endif
