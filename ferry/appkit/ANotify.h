/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: what the notification classes (NSUserNotification.m,
 * UNUserNotificationCenter.m) and the Dock (NSDockTile.m) share. Written
 * from the freedesktop.org Desktop Notifications specification and Apple's
 * public API documentation. Everything here is for the main thread. */
#ifndef FERRY_APPKIT_NOTIFY_H
#define FERRY_APPKIT_NOTIFY_H
#import "AInternal.h"
#import <UserNotifications/UserNotifications.h>

/* The program's connection to the session bus, made the first time it is
 * asked for (with GLib's main context then waited on by the run loop, so
 * signals arrive there); NULL when there is no session bus. */
GDBusConnection *ANotifyBus(void);

/* Says what on standard error once, when FERRY_VERBOSE is set. */
void ANotifyVerboseOnce(const char *what);

/* The app as the desktop knows it: its name, its desktop file names (the
 * one Ferry writes, named after the bundle identifier, and the one
 * freemac-mac-app writes when it installed the app) and its icon's name,
 * or "" when it has none. */
NSString *ANotifyAppName(void);
NSArray<NSString *> *ANotifyDesktopIDs(void);
NSString *ANotifyAppIcon(void);

/* What a notification's owner hears back from the server. Keys are those
 * given in ANotifyMessage's actions; "default" is a click on the
 * notification itself. Reasons are the specification's: 1 expired, 2
 * dismissed by the user, 3 closed by the program, 4 anything else. */
@protocol ANotifyOwner <NSObject>
- (void)_notifyInvoked:(NSString *)key;
- (void)_notifyReplied:(NSString *)text;
- (void)_notifyClosed:(unsigned)reason;
@end

/* One notification as the server is asked to show it. */
@interface ANotifyMessage : NSObject
@property (copy) NSString *summary, *body;
/* the sound: a file's path, a sound theme name, or neither for the
 * server's own; none at all when silent */
@property (copy) NSString *soundFile, *soundName;
@property BOOL silent;
@property int urgency;                        /* 0 low, 1 normal, 2 critical */
@property (retain) NSArray *actions;          /* @[key, label] pairs */
/* an inline reply, where the server takes one: its key, button and
 * placeholder */
@property (copy) NSString *replyKey, *replyButton, *replyPlaceholder;
@end

/* Whether the server says it can do something ("actions", "inline-reply",
 * "body-markup"...); asked once a server is there. */
BOOL ANotifyServerCan(NSString *capability);

/* Asks the server to show a message, in place of the one shown for
 * `replaces` (0 for none). Returns a handle for ANotifyClose, or 0 when
 * nothing could be shown (no bus or no server); the owner, retained until
 * the notification closes, is told what the user does with it. */
unsigned ANotifyShow(ANotifyMessage *message, id<ANotifyOwner> owner, unsigned replaces);
/* Takes a notification off the screen; its owner hears nothing more. */
void ANotifyClose(unsigned handle);

/* The Dock (NSDockTile.m): a badge set by a notification's content, the
 * app's launch (for the Dock menu), and NSApplication's attention
 * requests. */
void ADockSetBadge(NSString *label);
void ADockLaunched(void);
NSInteger ADockRequestAttention(NSInteger type);

/* The Dock's menu (NSStatusBar.m), served over dbusmenu at path as a menu
 * bar item's is, but never offered to the menu bar; refresh gives the menu
 * to show each time the dock opens it. Returns an object to keep. */
id AMenuServe(const char *path, NSMenu *(^refresh)(void));
#endif
