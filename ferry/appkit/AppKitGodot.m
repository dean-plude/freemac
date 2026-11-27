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
