/* SPDX-License-Identifier: GPL-3.0-or-later
 * What the Godot engine's Mac build calls in AppKit besides
 * (sdk/include/AppKit/AppKitGodot.h; freemac Godot work). Written from
 * Apple's public documentation. */
#import "AInternal.h"

/* ---- searching the Help menu ---------------------------------------------------------------- */

static NSMutableArray *search_handlers;

@implementation NSApplication (FerryHelpSearch)
- (void)registerUserInterfaceItemSearchHandler:(id<NSUserInterfaceItemSearching>)handler
{
    if (!handler)
        return;
    if (!search_handlers)
        search_handlers = [NSMutableArray new];
    if (![search_handlers containsObject:handler])
        [search_handlers addObject:handler];
}
- (void)unregisterUserInterfaceItemSearchHandler:(id<NSUserInterfaceItemSearching>)handler
{
    if (handler)
        [search_handlers removeObject:handler];
}
/* The reference: the search string's words are looked for in the item's
 * string as a Help menu does, ignoring case and diacritics; the range of
 * the first word found comes back. */
- (BOOL)searchString:(NSString *)searchString
    inUserInterfaceItemString:(NSString *)stringToSearch
                  searchRange:(NSRange)searchRange
                   foundRange:(NSRange *)foundRange
{
    if (foundRange)
        *foundRange = NSMakeRange(NSNotFound, 0);
    if (![searchString length] || ![stringToSearch length] || NSMaxRange(searchRange) > [stringToSearch length])
        return NO;
    NSStringCompareOptions opts = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSRange r = [stringToSearch rangeOfString:searchString options:opts range:searchRange];
    if (r.location == NSNotFound)
        for (NSString *word in [searchString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
            if (![word length])
                continue;
            r = [stringToSearch rangeOfString:word options:opts range:searchRange];
            if (r.location != NSNotFound)
                break;
        }
    if (r.location == NSNotFound)
        return NO;
    if (foundRange)
        *foundRange = r;
    return YES;
}
@end

/* ---- the title bar, the screen and opening with an application ------------------------- */

@implementation NSWindow (FerryGodot)
/* Which side the close, minimize and zoom buttons sit on: the app's
 * reading direction, left to right unless the app is set the other way */
- (NSUserInterfaceLayoutDirection)windowTitlebarLayoutDirection
{
    return [NSApp userInterfaceLayoutDirection];
}
@end

@implementation NSWorkspace (FerryGodot)
/* Each URL is opened as openURL: opens it, as with the older form; the
 * desktop picks the program, so there is no Mac application to answer. */
- (void)openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)applicationURL
        configuration:(NSWorkspaceOpenConfiguration *)configuration
    completionHandler:(void (^)(NSRunningApplication *, NSError *))handler
{
    NSURL *failed = nil;
    for (NSURL *url in urls)
        if (![self openURL:url] && !failed)
            failed = url;
    if (!handler)
        return;
    void (^h)(NSRunningApplication *, NSError *) = [handler copy];
    NSError *error = failed ? [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError
                                              userInfo:@{NSURLErrorKey : failed}]
                            : nil;
    [error retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        h(nil, error);
        [h release];
        [error release];
    });
}
@end

/* ---- a menu's reading direction ------------------------------------------------------------ */

static char menu_direction_key;

@implementation NSMenu (FerryGodot)
/* The menu's own direction once set, else the application's */
- (NSUserInterfaceLayoutDirection)userInterfaceLayoutDirection
{
    NSNumber *d = objc_getAssociatedObject(self, &menu_direction_key);
    return d ? (NSUserInterfaceLayoutDirection)[d integerValue] : [NSApp userInterfaceLayoutDirection];
}
- (void)setUserInterfaceLayoutDirection:(NSUserInterfaceLayoutDirection)direction
{
    objc_setAssociatedObject(self, &menu_direction_key, @(direction), OBJC_ASSOCIATION_RETAIN);
}
@end
