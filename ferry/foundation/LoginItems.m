/* SPDX-License-Identifier: GPL-3.0-or-later
 * Login items (freemac 1.219, Ferry 0.43.0): Launch Services' shared file
 * lists (LSSharedFileList) and ServiceManagement's SMLoginItemSetEnabled,
 * written for freemac from Apple's public documentation of both. A Mac starts
 * the session's login items when the user logs in; here they are freedesktop
 * autostart entries, which every Linux desktop starts at login:
 *
 *   $XDG_CONFIG_HOME/autostart/ferry-NAME.desktop         (a shared-file-list item)
 *   $XDG_CONFIG_HOME/autostart/ferry-login-ID.desktop     (an SMLoginItemSetEnabled helper)
 *
 * (~/.config when XDG_CONFIG_HOME isn't set), the folder freemac's own
 * login items are kept in, so Dials > Login Items lists them and takes them
 * off. Each runs "FERRY APP.app" with the absolute path of the ferry
 * program that wrote it. An entry the desktop's
 * startup settings switched off (Hidden=true, or X-GNOME-Autostart-enabled=
 * false) is left out of the list, as a Mac leaves out an item the user
 * removed. The other lists (recent items, favourites, the global login items,
 * which would need root here) are kept for as long as the program runs. */
#import "FInternal.h"
#include <CoreServices/CoreServices.h>
#include <ServiceManagement/ServiceManagement.h>
#include <unistd.h>
#include <errno.h>

const CFStringRef kLSSharedFileListSessionLoginItems = (CFStringRef)@"com.apple.LSSharedFileList.SessionLoginItems";
const CFStringRef kLSSharedFileListGlobalLoginItems = (CFStringRef)@"com.apple.LSSharedFileList.GlobalLoginItems";
const CFStringRef kLSSharedFileListRecentApplicationItems =
    (CFStringRef)@"com.apple.LSSharedFileList.RecentApplications";
const CFStringRef kLSSharedFileListRecentDocumentItems = (CFStringRef)@"com.apple.LSSharedFileList.RecentDocuments";
const CFStringRef kLSSharedFileListRecentServerItems = (CFStringRef)@"com.apple.LSSharedFileList.RecentServers";
const CFStringRef kLSSharedFileListFavoriteItems = (CFStringRef)@"com.apple.LSSharedFileList.FavoriteItems";
const CFStringRef kLSSharedFileListFavoriteVolumes = (CFStringRef)@"com.apple.LSSharedFileList.FavoriteVolumes";
const CFStringRef kLSSharedFileListItemHidden = (CFStringRef)@"com.apple.LSSharedFileList.ItemIsHidden";
const CFStringRef kLSSharedFileListLoginItemHidden = (CFStringRef)@"com.apple.loginitem.HideOnLaunch";
static struct { int unused; } before_first_place, last_place;
const LSSharedFileListItemRef kLSSharedFileListItemBeforeFirst = (LSSharedFileListItemRef)&before_first_place;
const LSSharedFileListItemRef kLSSharedFileListItemLast = (LSSharedFileListItemRef)&last_place;

/* ---- autostart entries ------------------------------------------------------ */

static NSString *autostart_dir(void)
{
    const char *cfg = getenv("XDG_CONFIG_HOME"), *home = getenv("HOME");
    NSString *base = cfg && cfg[0] == '/' ? [NSString stringWithUTF8String:cfg]
                     : home && *home      ? [[NSString stringWithUTF8String:home] stringByAppendingPathComponent:@".config"]
                                          : nil;
    return [base stringByAppendingPathComponent:@"autostart"];
}

/* The desktop-entry string escapes (\s \n \t \r \\), both ways. */
static NSString *entry_escaped(NSString *s)
{
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\')
            [m appendString:@"\\\\"];
        else if (c == '\n')
            [m appendString:@"\\n"];
        else if (c == '\t')
            [m appendString:@"\\t"];
        else if (c == '\r')
            [m appendString:@"\\r"];
        else
            [m appendFormat:@"%C", c];
    }
    return m;
}
static NSString *entry_unescaped(NSString *s)
{
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\' && i + 1 < [s length]) {
            unichar d = [s characterAtIndex:++i];
            c = d == 's' ? ' ' : d == 'n' ? '\n' : d == 't' ? '\t' : d == 'r' ? '\r' : d;
        }
        [m appendFormat:@"%C", c];
    }
    return m;
}
/* One argument of Exec, quoted as the Desktop Entry Specification says: in
 * double quotes, with " ` $ and \ escaped, and % doubled. */
static NSString *exec_arg(NSString *s)
{
    NSMutableString *m = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '`' || c == '$' || c == '\\')
            [m appendFormat:@"\\%C", c];
        else if (c == '%')
            [m appendString:@"%%"];
        else
            [m appendFormat:@"%C", c];
    }
    [m appendString:@"\""];
    return m;
}
static NSString *ferry_program(void)
{
    char buf[4096];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
    if (n <= 0)
        return @"ferry";
    buf[n] = 0;
    return [NSString stringWithUTF8String:buf];
}
static NSDictionary *read_entry(NSString *path)
{
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (!text)
        return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    BOOL inMain = NO;
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line hasPrefix:@"["]) {
            inMain = [line isEqualToString:@"[Desktop Entry]"];
            continue;
        }
        if (!inMain || [line hasPrefix:@"#"])
            continue;
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound)
            continue;
        NSString *key = [[line substringToIndex:eq.location]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [[line substringFromIndex:NSMaxRange(eq)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![d objectForKey:key])
            [d setObject:entry_unescaped(value) forKey:key];
    }
    return d;
}
static BOOL entry_switched_off(NSDictionary *e)
{
    return [[e objectForKey:@"Hidden"] isEqualToString:@"true"] ||
           [[e objectForKey:@"X-GNOME-Autostart-enabled"] isEqualToString:@"false"];
}
static BOOL write_entry(NSString *path, NSString *name, NSString *app, NSString *kindKey, NSString *kindValue,
                        long order, BOOL hideAtLaunch)
{
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *exec = [NSString stringWithFormat:@"%@ %@", exec_arg(ferry_program()), exec_arg(app)];
    NSMutableString *e = [NSMutableString stringWithString:@"[Desktop Entry]\nType=Application\n"];
    [e appendFormat:@"Name=%@\n", entry_escaped(name)];
    [e appendString:@"Comment=A Mac app, run by Ferry at login\n"];
    [e appendFormat:@"Exec=%@\n", entry_escaped(exec)];
    [e appendString:@"X-GNOME-Autostart-enabled=true\n"];
    [e appendFormat:@"%@=%@\n", kindKey, entry_escaped(kindValue)];
    [e appendFormat:@"X-Ferry-App=%@\n", entry_escaped(app)];
    if (order)
        [e appendFormat:@"X-Ferry-Order=%ld\n", order];
    if (hideAtLaunch)
        [e appendString:@"X-Ferry-Hide-At-Launch=true\n"];
    /* A helper opens at login like the rest, but isn't listed among the apps
     * in Dials > Login Items, as a Mac lists it apart. */
    if ([kindKey isEqualToString:@"X-Ferry-Login-Helper"])
        [e appendString:@"NoDisplay=true\n"];
    return [[e dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES];
}
/* A file name from the app's bundle identifier, or its name: letters, digits,
 * dots, dashes and underscores only. */
static NSString *safe_name(NSString *s)
{
    NSMutableString *m = [NSMutableString string];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' ||
                  c == '-' || c == '_';
        unichar out = ok ? c : (unichar)'_';
        [m appendFormat:@"%C", out];
    }
    return [m length] ? m : @"app";
}

/* ---- the items -------------------------------------------------------------- */

@interface FSharedFileListItem : NSObject {
@public
    NSURL *_url;
    NSString *_name, *_file;
    UInt32 _uid;
    long _order;
    NSMutableDictionary *_props;
}
@end
@implementation FSharedFileListItem
- (void)dealloc
{
    [_url release];
    [_name release];
    [_file release];
    [_props release];
    [super dealloc];
}
- (NSString *)description
{
    return [NSString stringWithFormat:@"<LSSharedFileListItem %u %@ %@>", (unsigned)_uid, _name, [_url path]];
}
@end

/* Item IDs stay the same for the same entry (or URL) while the program runs. */
static UInt32 item_id(NSString *key)
{
    static NSMutableDictionary *ids;
    static UInt32 next = 1;
    @synchronized([FSharedFileListItem class]) {
        if (!ids)
            ids = [[NSMutableDictionary alloc] init];
        NSNumber *n = [ids objectForKey:key];
        if (!n) {
            n = [NSNumber numberWithUnsignedInt:next++];
            [ids setObject:n forKey:key];
        }
        return [n unsignedIntValue];
    }
}

/* ---- the lists -------------------------------------------------------------- */

@interface FSharedFileList : NSObject {
@public
    NSString *_type;
    NSMutableArray *_observers;
}
@end

static NSMutableDictionary *memory_lists;   /* type -> NSMutableArray of items */
static NSMutableDictionary *seeds;          /* type -> NSNumber */
static NSMutableArray *all_lists;           /* weak: the live list objects, for observers */

static BOOL on_disk(NSString *type) { return [type isEqualToString:(NSString *)kLSSharedFileListSessionLoginItems]; }

static void bump(NSString *type)
{
    @synchronized([FSharedFileList class]) {
        if (!seeds)
            seeds = [[NSMutableDictionary alloc] init];
        UInt32 s = [[seeds objectForKey:type] unsignedIntValue] + 1;
        [seeds setObject:[NSNumber numberWithUnsignedInt:s] forKey:type];
    }
    /* Observers hear of each change made in this program, at once rather than
     * from the run loop. */
    NSArray *lists;
    @synchronized([FSharedFileList class]) {
        lists = [[all_lists copy] autorelease];
    }
    for (NSValue *v in lists) {
        FSharedFileList *l = [v nonretainedObjectValue];
        if (![l->_type isEqualToString:type])
            continue;
        for (NSArray *o in [[l->_observers copy] autorelease]) {
            LSSharedFileListChangedProcPtr fn = (LSSharedFileListChangedProcPtr)[[o objectAtIndex:0] pointerValue];
            fn((LSSharedFileListRef)l, [[o objectAtIndex:1] pointerValue]);
        }
    }
}

@implementation FSharedFileList
- (void)dealloc
{
    @synchronized([FSharedFileList class]) {
        for (NSUInteger i = 0; i < [all_lists count]; i++)
            if ([[all_lists objectAtIndex:i] nonretainedObjectValue] == self) {
                [all_lists removeObjectAtIndex:i];
                break;
            }
    }
    [_type release];
    [_observers release];
    [super dealloc];
}
/* The items, in order. */
- (NSArray *)items
{
    if (!on_disk(_type)) {
        @synchronized([FSharedFileList class]) {
            return [[[memory_lists objectForKey:_type] copy] autorelease] ?: [NSArray array];
        }
    }
    NSString *dir = autostart_dir();
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
             sortedArrayUsingSelector:@selector(compare:)]) {
        if (![f hasPrefix:@"ferry-"] || ![f hasSuffix:@".desktop"])
            continue;
        NSString *path = [dir stringByAppendingPathComponent:f];
        NSDictionary *e = read_entry(path);
        NSString *app = [e objectForKey:@"X-Ferry-App"];
        if (!app || ![e objectForKey:@"X-Ferry-Login-Item"] || entry_switched_off(e))
            continue;
        FSharedFileListItem *it = [[[FSharedFileListItem alloc] init] autorelease];
        it->_url = [[NSURL fileURLWithPath:app] retain];
        it->_name = [([e objectForKey:@"Name"] ?: [[app lastPathComponent] stringByDeletingPathExtension]) copy];
        it->_file = [path copy];
        it->_uid = item_id(path);
        it->_order = [[e objectForKey:@"X-Ferry-Order"] intValue];
        it->_props = [[NSMutableDictionary alloc] init];
        if ([[e objectForKey:@"X-Ferry-Hide-At-Launch"] isEqualToString:@"true"])
            [it->_props setObject:(id)kCFBooleanTrue forKey:(NSString *)kLSSharedFileListLoginItemHidden];
        [out addObject:it];
    }
    /* By order, keeping the file-name order among equals. */
    for (NSUInteger i = 1; i < [out count]; i++)
        for (NSUInteger j = i; j > 0 && ((FSharedFileListItem *)[out objectAtIndex:j - 1])->_order >
                                            ((FSharedFileListItem *)[out objectAtIndex:j])->_order;
             j--)
            [out exchangeObjectAtIndex:j withObjectAtIndex:j - 1];
    return out;
}
- (void)writeItem:(FSharedFileListItem *)it
{
    BOOL hide = [[it->_props objectForKey:(NSString *)kLSSharedFileListLoginItemHidden] boolValue];
    write_entry(it->_file, it->_name, [it->_url path], @"X-Ferry-Login-Item", @"true", it->_order, hide);
}
@end

static FSharedFileList *as_list(LSSharedFileListRef l) { return (FSharedFileList *)l; }
static FSharedFileListItem *as_item(LSSharedFileListItemRef i)
{
    if (!i || i == kLSSharedFileListItemBeforeFirst || i == kLSSharedFileListItemLast)
        return nil;
    return (FSharedFileListItem *)i;
}

LSSharedFileListRef LSSharedFileListCreate(CFAllocatorRef allocator, CFStringRef listType, CFTypeRef options)
{
    if (!listType)
        return NULL;
    FSharedFileList *l = [[FSharedFileList alloc] init];
    l->_type = [(NSString *)listType copy];
    l->_observers = [[NSMutableArray alloc] init];
    @synchronized([FSharedFileList class]) {
        if (!all_lists)
            all_lists = [[NSMutableArray alloc] init];
        [all_lists addObject:[NSValue valueWithNonretainedObject:l]];
        if (!on_disk(l->_type)) {
            if (!memory_lists)
                memory_lists = [[NSMutableDictionary alloc] init];
            if (![memory_lists objectForKey:l->_type])
                [memory_lists setObject:[NSMutableArray array] forKey:l->_type];
        }
    }
    return (LSSharedFileListRef)l;
}

UInt32 LSSharedFileListGetSeedValue(LSSharedFileListRef list)
{
    if (!list)
        return 0;
    @synchronized([FSharedFileList class]) {
        return [[seeds objectForKey:as_list(list)->_type] unsignedIntValue] + 1;
    }
}

CFArrayRef LSSharedFileListCopySnapshot(LSSharedFileListRef list, UInt32 *outSeed)
{
    if (outSeed)
        *outSeed = LSSharedFileListGetSeedValue(list);
    if (!list)
        return NULL;
    return (CFArrayRef)[[as_list(list) items] copy];
}

/* Where an item goes: after insertAfter, first, or last; the order numbers
 * leave room on both sides. */
static long order_after(NSArray *items, LSSharedFileListItemRef after, FSharedFileListItem *moving)
{
    NSMutableArray *rest = [NSMutableArray array];
    for (FSharedFileListItem *it in items)
        if (!moving || ![[it->_url path] isEqualToString:[moving->_url path]])
            [rest addObject:it];
    if (![rest count])
        return 0;
    if (after == kLSSharedFileListItemBeforeFirst)
        return ((FSharedFileListItem *)[rest objectAtIndex:0])->_order - 1024;
    FSharedFileListItem *a = as_item(after);
    NSUInteger at = NSNotFound;
    if (a)
        for (NSUInteger i = 0; i < [rest count]; i++)
            if (((FSharedFileListItem *)[rest objectAtIndex:i])->_uid == a->_uid)
                at = i;
    if (at == NSNotFound || at + 1 == [rest count])
        return ((FSharedFileListItem *)[rest lastObject])->_order + 1024;
    long lo = ((FSharedFileListItem *)[rest objectAtIndex:at])->_order;
    long hi = ((FSharedFileListItem *)[rest objectAtIndex:at + 1])->_order;
    return lo + (hi - lo) / 2;
}

static void place_in_memory(NSString *type, FSharedFileListItem *it, LSSharedFileListItemRef after)
{
    @synchronized([FSharedFileList class]) {
        NSMutableArray *a = [memory_lists objectForKey:type];
        for (NSUInteger i = 0; i < [a count]; i++)
            if (((FSharedFileListItem *)[a objectAtIndex:i])->_uid == it->_uid) {
                [a removeObjectAtIndex:i];
                break;
            }
        NSUInteger at = [a count];
        if (after == kLSSharedFileListItemBeforeFirst)
            at = 0;
        else if (as_item(after))
            for (NSUInteger i = 0; i < [a count]; i++)
                if (((FSharedFileListItem *)[a objectAtIndex:i])->_uid == as_item(after)->_uid)
                    at = i + 1;
        [a insertObject:it atIndex:at];
    }
}

LSSharedFileListItemRef LSSharedFileListInsertItemURL(LSSharedFileListRef list, LSSharedFileListItemRef insertAfter,
                                                      CFStringRef displayName, IconRef icon, CFURLRef url,
                                                      CFDictionaryRef propertiesToSet, CFArrayRef propertiesToClear)
{
    FSharedFileList *l = as_list(list);
    NSURL *u = (NSURL *)url;
    if (!l || ![u isFileURL])
        return NULL;
    NSString *path = [[u path] stringByStandardizingPath];
    NSArray *items = [l items];
    FSharedFileListItem *it = nil;
    /* The same URL again moves the item that is there, as documented. */
    for (FSharedFileListItem *x in items)
        if ([[x->_url path] isEqualToString:path])
            it = [[x retain] autorelease];
    if (!it) {
        it = [[[FSharedFileListItem alloc] init] autorelease];
        it->_url = [[NSURL fileURLWithPath:path] retain];
        it->_props = [[NSMutableDictionary alloc] init];
    }
    [it->_name release];
    NSString *bundleName = [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleName"];
    it->_name = [((NSString *)displayName ?: bundleName ?: [[path lastPathComponent] stringByDeletingPathExtension])
        copy];
    for (id k in (NSArray *)propertiesToClear)
        [it->_props removeObjectForKey:k];
    if (propertiesToSet)
        [it->_props addEntriesFromDictionary:(NSDictionary *)propertiesToSet];
    if (on_disk(l->_type)) {
        if (!it->_file) {
            NSString *ident = [[NSBundle bundleWithPath:path] bundleIdentifier];
            NSString *base = safe_name(ident ?: [[path lastPathComponent] stringByDeletingPathExtension]);
            NSString *dir = autostart_dir();
            if (!dir)
                return NULL;
            /* Another app's entry under the same name keeps its file. */
            NSString *file = nil;
            for (int n = 1; n < 100; n++) {
                NSString *f = [dir stringByAppendingPathComponent:
                                       n == 1 ? [NSString stringWithFormat:@"ferry-%@.desktop", base]
                                              : [NSString stringWithFormat:@"ferry-%@-%d.desktop", base, n]];
                NSDictionary *e = read_entry(f);
                if (!e || [[e objectForKey:@"X-Ferry-App"] isEqualToString:path]) {
                    file = f;
                    break;
                }
            }
            if (!file)
                return NULL;
            it->_file = [file copy];
            it->_uid = item_id(file);
        }
        it->_order = order_after(items, insertAfter, it);
        [l writeItem:it];
    } else {
        if (!it->_uid)
            it->_uid = item_id([NSString stringWithFormat:@"%@\n%@", l->_type, path]);
        place_in_memory(l->_type, it, insertAfter);
    }
    bump(l->_type);
    return (LSSharedFileListItemRef)[it retain];
}

OSStatus LSSharedFileListItemRemove(LSSharedFileListRef list, LSSharedFileListItemRef item)
{
    FSharedFileList *l = as_list(list);
    FSharedFileListItem *it = as_item(item);
    if (!l || !it)
        return paramErr;
    if (on_disk(l->_type)) {
        if (!it->_file || unlink([it->_file fileSystemRepresentation]) != 0)
            return fnfErr;
    } else {
        BOOL found = NO;
        @synchronized([FSharedFileList class]) {
            NSMutableArray *a = [memory_lists objectForKey:l->_type];
            for (NSUInteger i = 0; i < [a count]; i++)
                if (((FSharedFileListItem *)[a objectAtIndex:i])->_uid == it->_uid) {
                    [a removeObjectAtIndex:i];
                    found = YES;
                    break;
                }
        }
        if (!found)
            return fnfErr;
    }
    bump(l->_type);
    return noErr;
}

OSStatus LSSharedFileListRemoveAllItems(LSSharedFileListRef list)
{
    FSharedFileList *l = as_list(list);
    if (!l)
        return paramErr;
    for (FSharedFileListItem *it in [l items]) {
        if (on_disk(l->_type))
            unlink([it->_file fileSystemRepresentation]);
    }
    if (!on_disk(l->_type)) {
        @synchronized([FSharedFileList class]) {
            [[memory_lists objectForKey:l->_type] removeAllObjects];
        }
    }
    bump(l->_type);
    return noErr;
}

OSStatus LSSharedFileListItemMove(LSSharedFileListRef list, LSSharedFileListItemRef item,
                                  LSSharedFileListItemRef moveAfter)
{
    FSharedFileList *l = as_list(list);
    FSharedFileListItem *it = as_item(item);
    if (!l || !it)
        return paramErr;
    if (on_disk(l->_type)) {
        it->_order = order_after([l items], moveAfter, it);
        [l writeItem:it];
    } else
        place_in_memory(l->_type, it, moveAfter);
    bump(l->_type);
    return noErr;
}

void LSSharedFileListAddObserver(LSSharedFileListRef list, CFRunLoopRef runloop, CFStringRef mode,
                                 LSSharedFileListChangedProcPtr callback, void *context)
{
    if (!list || !callback)
        return;
    [as_list(list)->_observers addObject:[NSArray arrayWithObjects:[NSValue valueWithPointer:(void *)callback],
                                                                   [NSValue valueWithPointer:context], nil]];
}
void LSSharedFileListRemoveObserver(LSSharedFileListRef list, CFRunLoopRef runloop, CFStringRef mode,
                                    LSSharedFileListChangedProcPtr callback, void *context)
{
    if (!list)
        return;
    NSMutableArray *o = as_list(list)->_observers;
    for (NSUInteger i = [o count]; i-- > 0;)
        if ([[[o objectAtIndex:i] objectAtIndex:0] pointerValue] == (void *)callback &&
            [[[o objectAtIndex:i] objectAtIndex:1] pointerValue] == context)
            [o removeObjectAtIndex:i];
}
CFTypeRef LSSharedFileListCopyProperty(LSSharedFileListRef list, CFStringRef name) { return NULL; }
OSStatus LSSharedFileListSetProperty(LSSharedFileListRef list, CFStringRef name, CFTypeRef value) { return noErr; }

UInt32 LSSharedFileListItemGetID(LSSharedFileListItemRef item)
{
    FSharedFileListItem *it = as_item(item);
    return it ? it->_uid : 0;
}
CFStringRef LSSharedFileListItemCopyDisplayName(LSSharedFileListItemRef item)
{
    FSharedFileListItem *it = as_item(item);
    return it ? (CFStringRef)[it->_name copy] : NULL;
}
IconRef LSSharedFileListItemCopyIconRef(LSSharedFileListItemRef item) { return NULL; }

/* Resolving fails with fnfErr when the app is no longer where the item says. */
OSStatus LSSharedFileListItemResolve(LSSharedFileListItemRef item, LSSharedFileListResolutionFlags flags,
                                     CFURLRef *outURL, FSRef *outRef)
{
    FSharedFileListItem *it = as_item(item);
    if (outURL)
        *outURL = NULL;
    if (outRef)
        memset(outRef, 0, sizeof *outRef);
    if (!it)
        return paramErr;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[it->_url path]])
        return fnfErr;
    if (outURL)
        *outURL = (CFURLRef)[it->_url copy];
    return noErr;
}
CFURLRef LSSharedFileListItemCopyResolvedURL(LSSharedFileListItemRef item, LSSharedFileListResolutionFlags flags,
                                             CFErrorRef *outError)
{
    CFURLRef url = NULL;
    OSStatus err = LSSharedFileListItemResolve(item, flags, &url, NULL);
    if (err && outError)
        *outError = (CFErrorRef)[[NSError alloc] initWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
    return url;
}
CFTypeRef LSSharedFileListItemCopyProperty(LSSharedFileListItemRef item, CFStringRef name)
{
    FSharedFileListItem *it = as_item(item);
    if (!it || !name)
        return NULL;
    id v = [it->_props objectForKey:(NSString *)name];
    if (!v && [(NSString *)name isEqualToString:(NSString *)kLSSharedFileListItemHidden])
        v = (id)kCFBooleanFalse;
    return (CFTypeRef)[v retain];
}
OSStatus LSSharedFileListItemSetProperty(LSSharedFileListItemRef item, CFStringRef name, CFTypeRef value)
{
    FSharedFileListItem *it = as_item(item);
    if (!it || !name)
        return paramErr;
    if (value)
        [it->_props setObject:(id)value forKey:(NSString *)name];
    else
        [it->_props removeObjectForKey:(NSString *)name];
    if (it->_file)
        write_entry(it->_file, it->_name, [it->_url path], @"X-Ferry-Login-Item", @"true", it->_order,
                    [[it->_props objectForKey:(NSString *)kLSSharedFileListLoginItemHidden] boolValue]);
    return noErr;
}

/* ---- ServiceManagement -------------------------------------------------------- */

Boolean SMLoginItemSetEnabled(CFStringRef identifier, Boolean enabled)
{
    NSString *ident = (NSString *)identifier;
    NSString *dir = autostart_dir();
    if (![ident length] || !dir)
        return false;
    NSString *file = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"ferry-login-%@.desktop",
                                                                                     safe_name(ident)]];
    if (!enabled) {
        if (unlink([file fileSystemRepresentation]) != 0 && errno != ENOENT)
            return false;
        return true;
    }
    NSString *items = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Library/LoginItems"];
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:items error:NULL]
             sortedArrayUsingSelector:@selector(compare:)]) {
        if (![[f pathExtension] isEqualToString:@"app"])
            continue;
        NSString *helper = [items stringByAppendingPathComponent:f];
        if (![[[NSBundle bundleWithPath:helper] bundleIdentifier] isEqualToString:ident])
            continue;
        NSString *name = [[NSBundle bundleWithPath:helper] objectForInfoDictionaryKey:@"CFBundleName"]
                             ?: [f stringByDeletingPathExtension];
        return write_entry(file, name, helper, @"X-Ferry-Login-Helper", ident, 0, NO);
    }
    return false;
}

/* Launchd jobs, which there is no launchd to run (freemac 1.224, Ferry 0.48.0). */
const CFStringRef kSMDomainSystemLaunchd = (CFStringRef)@"kSMDomainSystemLaunchd";
const CFStringRef kSMDomainUserLaunchd = (CFStringRef)@"kSMDomainUserLaunchd";
const CFStringRef kSMErrorDomainIPC = (CFStringRef)@"kSMErrorDomainIPC";
const CFStringRef kSMErrorDomainFramework = (CFStringRef)@"kSMErrorDomainFramework";
const CFStringRef kSMErrorDomainLaunchd = (CFStringRef)@"kSMErrorDomainLaunchd";

static Boolean no_launchd(CFErrorRef *outError, CFIndex code)
{
    if (outError)
        *outError = (CFErrorRef)[[NSError alloc] initWithDomain:(NSString *)kSMErrorDomainLaunchd code:code userInfo:nil];
    return false;
}
Boolean SMJobSubmit(CFStringRef domain, CFDictionaryRef job, AuthorizationRef auth, CFErrorRef *outError)
{
    return no_launchd(outError, kSMErrorServiceUnavailable);
}
Boolean SMJobRemove(CFStringRef domain, CFStringRef label, AuthorizationRef auth, Boolean wait, CFErrorRef *outError)
{
    return no_launchd(outError, kSMErrorJobNotFound);
}
Boolean SMJobBless(CFStringRef domain, CFStringRef label, AuthorizationRef auth, CFErrorRef *outError)
{
    return no_launchd(outError, kSMErrorServiceUnavailable);
}
CFDictionaryRef SMJobCopyDictionary(CFStringRef domain, CFStringRef label) { return NULL; }

/* The helpers SMLoginItemSetEnabled turned on, as the user's launchd jobs a
 * Mac would list for them (freemac 1.230): each labelled with the
 * helper's identifier and started on demand. The system domain has none. */
CFArrayRef SMCopyAllJobDictionaries(CFStringRef domain)
{
    NSMutableArray *jobs = [[NSMutableArray alloc] init];
    NSString *dir = autostart_dir();
    if (domain && [(NSString *)domain isEqualToString:(NSString *)kSMDomainUserLaunchd] && dir) {
        for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
                 sortedArrayUsingSelector:@selector(compare:)]) {
            if (![f hasPrefix:@"ferry-login-"] || ![f hasSuffix:@".desktop"])
                continue;
            NSDictionary *e = read_entry([dir stringByAppendingPathComponent:f]);
            NSString *ident = [e objectForKey:@"X-Ferry-Login-Helper"], *app = [e objectForKey:@"X-Ferry-App"];
            if (!ident || entry_switched_off(e))
                continue;
            [jobs addObject:[NSDictionary dictionaryWithObjectsAndKeys:ident, @"Label", (id)kCFBooleanTrue, @"OnDemand",
                                                                       app ?: @"", @"Program", nil]];
        }
    }
    return (CFArrayRef)jobs;
}

/* ---- SMAppService (freemac 1.230) ---------------------------------------------
 *
 * The main app registers as one of the session's login items, the list
 * LSSharedFileList keeps above, so it is the same entry an older app would
 * add and Dials > Login Items lists it. A login item is a helper in the
 * bundle's Contents/Library/LoginItems, turned on as SMLoginItemSetEnabled
 * turns one on. Agents and daemons are launchd jobs, which this system
 * doesn't have, so they are never found. Nothing needs the user's approval
 * here. */

NSString *const SMAppServiceErrorDomain = @"SMAppServiceErrorDomain";

enum { SERVICE_MAIN, SERVICE_LOGIN_ITEM, SERVICE_AGENT, SERVICE_DAEMON };

static NSString *main_app_path(void) { return [[[NSBundle mainBundle] bundlePath] stringByStandardizingPath]; }

/* The session's login item for the main app, if there is one. */
static FSharedFileListItem *main_app_item(FSharedFileList *l)
{
    NSString *path = main_app_path();
    for (FSharedFileListItem *it in [l items])
        if ([[[it->_url path] stringByStandardizingPath] isEqualToString:path])
            return it;
    return nil;
}

/* The helper in the main bundle with this identifier. */
static BOOL has_helper(NSString *ident)
{
    NSString *items = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Library/LoginItems"];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:items error:NULL])
        if ([[f pathExtension] isEqualToString:@"app"] &&
            [[[NSBundle bundleWithPath:[items stringByAppendingPathComponent:f]] bundleIdentifier] isEqualToString:ident])
            return YES;
    return NO;
}

static BOOL service_error(NSError **error, NSInteger code)
{
    if (error)
        *error = [NSError errorWithDomain:SMAppServiceErrorDomain code:code userInfo:nil];
    return NO;
}

@implementation SMAppService {
    int _kind;
    NSString *_name;
}
static SMAppService *service(int kind, NSString *name)
{
    SMAppService *s = [[[SMAppService alloc] init] autorelease];
    s->_kind = kind;
    s->_name = [name copy];
    return s;
}
+ (SMAppService *)mainAppService { return service(SERVICE_MAIN, nil); }
+ (SMAppService *)loginItemServiceWithIdentifier:(NSString *)identifier
{
    return service(SERVICE_LOGIN_ITEM, identifier);
}
+ (SMAppService *)agentServiceWithPlistName:(NSString *)plistName { return service(SERVICE_AGENT, plistName); }
+ (SMAppService *)daemonServiceWithPlistName:(NSString *)plistName { return service(SERVICE_DAEMON, plistName); }
+ (SMAppServiceStatus)statusForLegacyURL:(NSURL *)url { return SMAppServiceStatusNotFound; }
+ (void)openSystemSettingsLoginItems {}
- (void)dealloc
{
    [_name release];
    [super dealloc];
}
- (SMAppServiceStatus)status
{
    switch (_kind) {
    case SERVICE_MAIN: {
        LSSharedFileListRef l = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        BOOL on = main_app_item(as_list(l)) != nil;
        CFRelease(l);
        return on ? SMAppServiceStatusEnabled : SMAppServiceStatusNotRegistered;
    }
    case SERVICE_LOGIN_ITEM: {
        for (NSDictionary *job in [(NSArray *)SMCopyAllJobDictionaries(kSMDomainUserLaunchd) autorelease])
            if ([[job objectForKey:@"Label"] isEqualToString:_name])
                return SMAppServiceStatusEnabled;
        return has_helper(_name) ? SMAppServiceStatusNotRegistered : SMAppServiceStatusNotFound;
    }
    default:
        return SMAppServiceStatusNotFound;
    }
}
- (BOOL)registerAndReturnError:(NSError **)error
{
    switch (_kind) {
    case SERVICE_MAIN: {
        NSURL *app = [NSURL fileURLWithPath:main_app_path()];
        LSSharedFileListRef l = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        LSSharedFileListItemRef it =
            main_app_item(as_list(l)) ? NULL
                                      : LSSharedFileListInsertItemURL(l, kLSSharedFileListItemLast, NULL, NULL,
                                                                      (CFURLRef)app, NULL, NULL);
        BOOL ok = it || main_app_item(as_list(l));
        if (it)
            CFRelease(it);
        CFRelease(l);
        return ok ? YES : service_error(error, kSMErrorInternalFailure);
    }
    case SERVICE_LOGIN_ITEM:
        if (!has_helper(_name))
            return service_error(error, kSMErrorJobNotFound);
        return SMLoginItemSetEnabled((CFStringRef)_name, true) ? YES : service_error(error, kSMErrorInternalFailure);
    default:
        return service_error(error, kSMErrorJobNotFound);
    }
}
- (BOOL)unregisterAndReturnError:(NSError **)error
{
    switch (_kind) {
    case SERVICE_MAIN: {
        LSSharedFileListRef l = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
        FSharedFileListItem *it = main_app_item(as_list(l));
        OSStatus st = it ? LSSharedFileListItemRemove(l, (LSSharedFileListItemRef)it) : fnfErr;
        CFRelease(l);
        return st == noErr ? YES : service_error(error, kSMErrorJobNotFound);
    }
    case SERVICE_LOGIN_ITEM:
        if ([self status] != SMAppServiceStatusEnabled)
            return service_error(error, kSMErrorJobNotFound);
        return SMLoginItemSetEnabled((CFStringRef)_name, false) ? YES : service_error(error, kSMErrorInternalFailure);
    default:
        return service_error(error, kSMErrorJobNotFound);
    }
}
- (NSString *)description
{
    static const char *kinds[] = {"main app", "login item", "agent", "daemon"};
    return [NSString stringWithFormat:@"<SMAppService %s%@%@: %ld>", kinds[_kind], _name ? @" " : @"", _name ?: @"",
                                      (long)[self status]];
}
@end
