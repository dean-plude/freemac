/* SPDX-License-Identifier: GPL-3.0-or-later
 * What MacVim's official download calls in AppKit besides (freemac
 * 1.NEXT). Written from Apple's public documentation and from MacVim's own
 * open-source code, which shows how it uses each call; no Apple code was
 * read. Built without ARC. */
#import "AInternal.h"

/* ---- a menu's special name ------------------------------------------------------------------- *
 * A nib gives the main menu, the Window menu, the Services menu and the
 * Open Recent menu a name ("_NSMainMenu", "_NSWindowsMenu" and so on) that
 * says what AppKit fills in. Apps that build or move those menus in code
 * name them the same way with -_setMenuName: (MacVim marks its Open Recent
 * menu "NSRecentDocumentsMenu"), so Ferry takes the name, with or without
 * the leading underscore, and gives the menu that job. */

static char menu_name_key;

@implementation NSMenu (FerryMenuName)
- (void)_setMenuName:(NSString *)name
{
    if (![name isKindOfClass:[NSString class]])
        name = nil;
    objc_setAssociatedObject(self, &menu_name_key, name, OBJC_ASSOCIATION_COPY);
    if ([name hasPrefix:@"_"])
        name = [name substringFromIndex:1];
    if ([name isEqualToString:@"NSRecentDocumentsMenu"])
        ANoteRecentDocumentsMenu(self);
    else if ([name isEqualToString:@"NSWindowsMenu"])
        [NSApp setWindowsMenu:self];
    else if ([name isEqualToString:@"NSServicesMenu"])
        [NSApp setServicesMenu:self];
}
- (NSString *)_menuName
{
    return objc_getAssociatedObject(self, &menu_name_key);
}
@end

