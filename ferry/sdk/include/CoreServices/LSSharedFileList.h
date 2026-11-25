/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: Launch Services' shared file lists, as far as apps use them to
 * start at login (freemac 1.219, Ferry 0.43.0). Written for freemac from
 * Apple's public documentation of LSSharedFileList; not Apple's header.
 * Ferry keeps the session's login items as freedesktop autostart entries,
 * $XDG_CONFIG_HOME/autostart/ferry-NAME.desktop (~/.config/autostart when
 * XDG_CONFIG_HOME isn't set), each running "ferry APP.app"; the desktop's
 * own startup settings can switch one off (Hidden=true), and the list then
 * leaves it out. The other lists (recent items, favourites, the global login
 * items) live only as long as the program does. Served from Foundation's file. */
#ifndef _FERRY_CORESERVICES_LSSHAREDFILELIST_H_
#define _FERRY_CORESERVICES_LSSHAREDFILELIST_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef struct OpaqueLSSharedFileListRef *LSSharedFileListRef;
typedef struct OpaqueLSSharedFileListItemRef *LSSharedFileListItemRef;
typedef struct OpaqueIconRef *IconRef;
#ifndef _FERRY_FSREF_DEFINED
#define _FERRY_FSREF_DEFINED
struct FSRef { uint8_t hidden[80]; };
typedef struct FSRef FSRef;
#endif
typedef void (*LSSharedFileListChangedProcPtr)(LSSharedFileListRef inList, void *context);
typedef UInt32 LSSharedFileListResolutionFlags;
enum { kLSSharedFileListNoUserInteraction = 1, kLSSharedFileListDoNotMountVolumes = 2 };

/* List types. */
extern const CFStringRef kLSSharedFileListSessionLoginItems;
extern const CFStringRef kLSSharedFileListGlobalLoginItems;
extern const CFStringRef kLSSharedFileListRecentApplicationItems;
extern const CFStringRef kLSSharedFileListRecentDocumentItems;
extern const CFStringRef kLSSharedFileListRecentServerItems;
extern const CFStringRef kLSSharedFileListFavoriteItems;
extern const CFStringRef kLSSharedFileListFavoriteVolumes;
/* Item properties. */
extern const CFStringRef kLSSharedFileListItemHidden;
extern const CFStringRef kLSSharedFileListLoginItemHidden;
/* Places to insert at. */
extern const LSSharedFileListItemRef kLSSharedFileListItemBeforeFirst;
extern const LSSharedFileListItemRef kLSSharedFileListItemLast;

LSSharedFileListRef LSSharedFileListCreate(CFAllocatorRef allocator, CFStringRef listType, CFTypeRef options);
CFArrayRef LSSharedFileListCopySnapshot(LSSharedFileListRef list, UInt32 *outSnapshotSeed);
UInt32 LSSharedFileListGetSeedValue(LSSharedFileListRef list);
LSSharedFileListItemRef LSSharedFileListInsertItemURL(LSSharedFileListRef list, LSSharedFileListItemRef insertAfter,
                                                      CFStringRef displayName, IconRef icon, CFURLRef url,
                                                      CFDictionaryRef propertiesToSet, CFArrayRef propertiesToClear);
OSStatus LSSharedFileListItemRemove(LSSharedFileListRef list, LSSharedFileListItemRef item);
OSStatus LSSharedFileListRemoveAllItems(LSSharedFileListRef list);
OSStatus LSSharedFileListItemMove(LSSharedFileListRef list, LSSharedFileListItemRef item,
                                  LSSharedFileListItemRef moveAfter);
void LSSharedFileListAddObserver(LSSharedFileListRef list, CFRunLoopRef runloop, CFStringRef runloopMode,
                                 LSSharedFileListChangedProcPtr callback, void *context);
void LSSharedFileListRemoveObserver(LSSharedFileListRef list, CFRunLoopRef runloop, CFStringRef runloopMode,
                                    LSSharedFileListChangedProcPtr callback, void *context);
CFTypeRef LSSharedFileListCopyProperty(LSSharedFileListRef list, CFStringRef name);
OSStatus LSSharedFileListSetProperty(LSSharedFileListRef list, CFStringRef name, CFTypeRef value);

UInt32 LSSharedFileListItemGetID(LSSharedFileListItemRef item);
CFStringRef LSSharedFileListItemCopyDisplayName(LSSharedFileListItemRef item);
IconRef LSSharedFileListItemCopyIconRef(LSSharedFileListItemRef item); /* always NULL here */
OSStatus LSSharedFileListItemResolve(LSSharedFileListItemRef item, LSSharedFileListResolutionFlags flags,
                                     CFURLRef *outURL, FSRef *outRef);
CFURLRef LSSharedFileListItemCopyResolvedURL(LSSharedFileListItemRef item, LSSharedFileListResolutionFlags flags,
                                             CFErrorRef *outError);
CFTypeRef LSSharedFileListItemCopyProperty(LSSharedFileListItemRef item, CFStringRef name);
OSStatus LSSharedFileListItemSetProperty(LSSharedFileListItemRef item, CFStringRef name, CFTypeRef value);
__FERRY_END
#endif
