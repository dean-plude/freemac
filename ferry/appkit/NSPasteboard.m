/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: pasteboards (M7), written from Apple's public NSPasteboard
 * documentation. A pasteboard holds items, each with its data in one or
 * more types. Every pasteboard lives inside the program, and the general
 * one is also this system's clipboard: text written to it goes to GTK's
 * clipboard, and when another app copies something, the next read finds
 * its text, files or image. Built without ARC. */
#import "AInternal.h"

A_EXPORT NSPasteboardType const NSPasteboardTypeString = @"public.utf8-plain-text";
A_EXPORT NSPasteboardType const NSPasteboardTypePDF = @"com.adobe.pdf";
A_EXPORT NSPasteboardType const NSPasteboardTypeTIFF = @"public.tiff";
A_EXPORT NSPasteboardType const NSPasteboardTypePNG = @"public.png";
A_EXPORT NSPasteboardType const NSPasteboardTypeRTF = @"public.rtf";
A_EXPORT NSPasteboardType const NSPasteboardTypeRTFD = @"com.apple.flat-rtfd";
A_EXPORT NSPasteboardType const NSPasteboardTypeHTML = @"public.html";
A_EXPORT NSPasteboardType const NSPasteboardTypeTabularText = @"public.utf8-tab-separated-values-text";
A_EXPORT NSPasteboardType const NSPasteboardTypeFont = @"com.apple.cocoa.pasteboard.character-formatting";
A_EXPORT NSPasteboardType const NSPasteboardTypeRuler = @"com.apple.cocoa.pasteboard.paragraph-formatting";
A_EXPORT NSPasteboardType const NSPasteboardTypeColor = @"com.apple.cocoa.pasteboard.color";
A_EXPORT NSPasteboardType const NSPasteboardTypeSound = @"com.apple.cocoa.pasteboard.sound";
A_EXPORT NSPasteboardType const NSPasteboardTypeMultipleTextSelection =
    @"com.apple.cocoa.pasteboard.multiple-text-selection";
A_EXPORT NSPasteboardType const NSPasteboardTypeTextFinderOptions = @"com.apple.cocoa.pasteboard.find-panel-search-options";
A_EXPORT NSPasteboardType const NSPasteboardTypeURL = @"public.url";
A_EXPORT NSPasteboardType const NSPasteboardTypeFileURL = @"public.file-url";

/* The old names are the same types, so either kind of name reads what the
 * other wrote. NSFilenamesPboardType is its own: an array of paths, made
 * from (and made into) file URL items. */
A_EXPORT NSPasteboardType const NSStringPboardType = @"public.utf8-plain-text";
A_EXPORT NSPasteboardType const NSFilenamesPboardType = @"NSFilenamesPboardType";
A_EXPORT NSPasteboardType const NSTIFFPboardType = @"public.tiff";
A_EXPORT NSPasteboardType const NSPDFPboardType = @"com.adobe.pdf";
A_EXPORT NSPasteboardType const NSRTFPboardType = @"public.rtf";
A_EXPORT NSPasteboardType const NSRTFDPboardType = @"com.apple.flat-rtfd";
A_EXPORT NSPasteboardType const NSHTMLPboardType = @"public.html";
A_EXPORT NSPasteboardType const NSTabularTextPboardType = @"public.utf8-tab-separated-values-text";
A_EXPORT NSPasteboardType const NSFontPboardType = @"com.apple.cocoa.pasteboard.character-formatting";
A_EXPORT NSPasteboardType const NSRulerPboardType = @"com.apple.cocoa.pasteboard.paragraph-formatting";
A_EXPORT NSPasteboardType const NSColorPboardType = @"com.apple.cocoa.pasteboard.color";
A_EXPORT NSPasteboardType const NSURLPboardType = @"public.url";
A_EXPORT NSPasteboardType const NSFileContentsPboardType = @"NSFileContentsPboardType";
A_EXPORT NSPasteboardType const NSMultipleTextSelectionPboardType = @"com.apple.cocoa.pasteboard.multiple-text-selection";
A_EXPORT NSPasteboardType const NSPostScriptPboardType = @"com.adobe.encapsulated-postscript";
A_EXPORT NSPasteboardType const NSVCardPboardType = @"public.vcard";
A_EXPORT NSPasteboardType const NSInkTextPboardType = @"com.apple.ink.inktext";
A_EXPORT NSPasteboardType const NSFilesPromisePboardType = @"com.apple.pasteboard.promised-file-url";
A_EXPORT NSPasteboardType const NSPICTPboardType = @"com.apple.pict";

A_EXPORT NSPasteboardName const NSPasteboardNameGeneral = @"Apple CFPasteboard general";
A_EXPORT NSPasteboardName const NSPasteboardNameFont = @"Apple CFPasteboard font";
A_EXPORT NSPasteboardName const NSPasteboardNameRuler = @"Apple CFPasteboard ruler";
A_EXPORT NSPasteboardName const NSPasteboardNameFind = @"Apple CFPasteboard find";
A_EXPORT NSPasteboardName const NSPasteboardNameDrag = @"Apple CFPasteboard drag";
A_EXPORT NSPasteboardName const NSGeneralPboard = @"Apple CFPasteboard general";
A_EXPORT NSPasteboardName const NSFontPboard = @"Apple CFPasteboard font";
A_EXPORT NSPasteboardName const NSRulerPboard = @"Apple CFPasteboard ruler";
A_EXPORT NSPasteboardName const NSFindPboard = @"Apple CFPasteboard find";
A_EXPORT NSPasteboardName const NSDragPboard = @"Apple CFPasteboard drag";
A_EXPORT NSPasteboardReadingOptionKey const NSPasteboardURLReadingFileURLsOnlyKey = @"NSPasteboardURLReadingFileURLsOnlyKey";
A_EXPORT NSPasteboardReadingOptionKey const NSPasteboardURLReadingContentsConformToTypesKey =
    @"NSPasteboardURLReadingContentsConformToTypesKey";

static BOOL is_text_type(NSString *type)
{
    return [type isEqualToString:NSPasteboardTypeString] || [type isEqualToString:@"public.plain-text"] ||
           [type isEqualToString:@"public.text"] || [type isEqualToString:NSPasteboardTypeTabularText] ||
           [type isEqualToString:NSPasteboardTypeURL] || [type isEqualToString:NSPasteboardTypeFileURL] ||
           [type isEqualToString:NSPasteboardTypeHTML];
}

/* ---- NSPasteboardItem ---------------------------------------------------------------- */

@interface NSPasteboardItem ()
- (void)_setPasteboard:(NSPasteboard *)pasteboard;
- (id)_valueForType:(NSString *)type;
@end

@implementation NSPasteboardItem {
    NSMutableArray *_types;
    NSMutableDictionary *_values;    /* type -> NSData, NSString or a property list */
    NSMutableDictionary *_providers; /* type -> provider, for data made when first asked for */
    NSPasteboard *_pasteboard;       /* not retained */
}

- (instancetype)init
{
    if ((self = [super init])) {
        _types = [[NSMutableArray alloc] init];
        _values = [[NSMutableDictionary alloc] init];
        _providers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_types release];
    [_values release];
    [_providers release];
    [super dealloc];
}

- (void)_setPasteboard:(NSPasteboard *)pasteboard { _pasteboard = pasteboard; }
- (NSArray *)types { return [[_types copy] autorelease]; }
- (NSPasteboardType)availableTypeFromArray:(NSArray *)types
{
    for (NSString *t in types)
        if ([_types containsObject:t])
            return t;
    return nil;
}

- (void)_addType:(NSString *)type
{
    if (![_types containsObject:type])
        [_types addObject:type];
}

- (BOOL)setDataProvider:(id<NSPasteboardItemDataProvider>)provider forTypes:(NSArray *)types
{
    for (NSString *t in types) {
        [self _addType:t];
        [_providers setObject:provider forKey:t];
        [_values removeObjectForKey:t];
    }
    return YES;
}

- (BOOL)_setValue:(id)value forType:(NSString *)type
{
    if (!type)
        return NO;
    [self _addType:type];
    [_providers removeObjectForKey:type];
    if (value)
        [_values setObject:value forKey:type];
    else
        [_values removeObjectForKey:type];
    return YES;
}
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type { return [self _setValue:[[data copy] autorelease] forType:type]; }
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type
{
    return [self _setValue:[[string copy] autorelease] forType:type];
}
- (BOOL)setPropertyList:(id)plist forType:(NSPasteboardType)type { return [self _setValue:plist forType:type]; }

- (id)_valueForType:(NSString *)type
{
    if (![_types containsObject:type])
        return nil;
    id provider = [_providers objectForKey:type];
    if (provider && ![_values objectForKey:type]) {
        [[provider retain] autorelease];
        [_providers removeObjectForKey:type];
        [provider pasteboard:_pasteboard item:self provideDataForType:type];
    }
    return [_values objectForKey:type];
}

- (NSData *)dataForType:(NSPasteboardType)type
{
    id v = [self _valueForType:type];
    if ([v isKindOfClass:[NSData class]])
        return v;
    if ([v isKindOfClass:[NSString class]])
        return [v dataUsingEncoding:NSUTF8StringEncoding];
    if (v)
        return [NSPropertyListSerialization dataWithPropertyList:v format:NSPropertyListXMLFormat_v1_0 options:0
                                                           error:NULL];
    return nil;
}

- (NSString *)stringForType:(NSPasteboardType)type
{
    id v = [self _valueForType:type];
    if ([v isKindOfClass:[NSString class]])
        return v;
    if ([v isKindOfClass:[NSData class]])
        return [[[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding] autorelease];
    return nil;
}

- (id)propertyListForType:(NSPasteboardType)type
{
    id v = [self _valueForType:type];
    if ([v isKindOfClass:[NSData class]]) {
        id plist = [NSPropertyListSerialization propertyListWithData:v options:0 format:NULL error:NULL];
        return plist ?: v;
    }
    return v;
}

/* An item can itself be written to a pasteboard. */
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard { return [self types]; }
- (id)pasteboardPropertyListForType:(NSPasteboardType)type { return [self _valueForType:type]; }
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard { return [pasteboard types]; }
@end

/* ---- the system clipboard -------------------------------------------------------------- */

static GtkClipboard *system_clipboard(void)
{
    if (!ADisplayAvailable())
        return NULL;
    /* a compositor with no seat (a headless one) has no clipboard, and GTK
     * fails on it */
    GdkDisplay *d = gdk_display_get_default();
    if (!d || !gdk_display_get_default_seat(d))
        return NULL;
    return gtk_clipboard_get(gdk_atom_intern("CLIPBOARD", 0));
}

/* ---- NSPasteboard ---------------------------------------------------------------------- */

@implementation NSPasteboard {
    NSString *_name;
    NSInteger _changeCount;
    NSMutableArray *_items;
    id _owner;
    BOOL _general;
    NSString *_lastSystemText; /* what we last put on, or found on, the system clipboard */
}

static NSMutableDictionary *pasteboards;

+ (NSPasteboard *)pasteboardWithName:(NSPasteboardName)name
{
    if (!pasteboards)
        pasteboards = [[NSMutableDictionary alloc] init];
    NSPasteboard *pb = [pasteboards objectForKey:name];
    if (!pb) {
        pb = [[[NSPasteboard alloc] init] autorelease];
        pb->_name = [name copy];
        pb->_items = [[NSMutableArray alloc] init];
        pb->_general = [name isEqualToString:NSPasteboardNameGeneral];
        [pasteboards setObject:pb forKey:name];
    }
    return pb;
}
+ (NSPasteboard *)generalPasteboard { return [self pasteboardWithName:NSPasteboardNameGeneral]; }
+ (NSPasteboard *)pasteboardWithUniqueName
{
    return [self pasteboardWithName:[NSString stringWithFormat:@"Ferry pasteboard %@",
                                                               [[NSProcessInfo processInfo] globallyUniqueString]]];
}

- (void)dealloc
{
    [_name release];
    [_items release];
    [_owner release];
    [_lastSystemText release];
    [super dealloc];
}

- (NSPasteboardName)name { return _name; }
- (void)releaseGlobally { [pasteboards removeObjectForKey:_name]; }

/* When another app has put something on the system clipboard since we last
 * looked, it becomes this pasteboard's contents. Only text is compared:
 * files and images copied elsewhere come with a text form too (their
 * paths), or are picked up when nothing else is here. */
- (void)_syncFromSystem
{
    GtkClipboard *cb = _general ? system_clipboard() : NULL;
    if (!cb)
        return;
    char *text = gtk_clipboard_wait_for_text(cb);
    NSString *s = text ? [NSString stringWithUTF8String:text] : nil;
    if (text)
        g_free(text);
    if ((!s && !_lastSystemText) || [s isEqualToString:_lastSystemText])
        return;
    id wasLastSystemText = _lastSystemText;
    _lastSystemText = [s copy];
    [wasLastSystemText release];
    if (s && [self _ownString:s])
        return; /* our own text, as we wrote it */
    [self _takeFromSystem:cb text:s];
}

- (BOOL)_ownString:(NSString *)s
{
    NSPasteboardItem *first = [_items firstObject];
    return first && [[first stringForType:NSPasteboardTypeString] isEqualToString:s];
}

- (void)_takeFromSystem:(GtkClipboard *)cb text:(NSString *)text
{
    [_items removeAllObjects];
    [_owner release];
    _owner = nil;
    _changeCount++;
    char **uris = gtk_clipboard_wait_for_uris(cb);
    BOOL files = NO;
    for (char **u = uris; u && *u; u++) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:*u]];
        if (!url)
            continue;
        NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
        [item setString:[url absoluteString] forType:[url isFileURL] ? NSPasteboardTypeFileURL : NSPasteboardTypeURL];
        [item setString:[url isFileURL] ? [url path] : [url absoluteString] forType:NSPasteboardTypeString];
        [item _setPasteboard:self];
        [_items addObject:item];
        files = YES;
    }
    if (uris)
        g_strfreev(uris);
    if (files)
        return;
    NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
    [item _setPasteboard:self];
    if (text)
        [item setString:text forType:NSPasteboardTypeString];
    GdkPixbuf *image = text ? NULL : gtk_clipboard_wait_for_image(cb);
    if (image) {
        char *buffer = NULL;
        size_t size = 0;
        if (gdk_pixbuf_save_to_bufferv(image, &buffer, &size, "png", NULL, NULL, NULL)) {
            [item setData:[NSData dataWithBytes:buffer length:size] forType:NSPasteboardTypePNG];
            g_free(buffer);
        }
        g_object_unref(image);
    }
    if ([[item types] count])
        [_items addObject:item];
}

/* Writes the text of the first item to the system clipboard. */
- (void)_syncToSystem
{
    GtkClipboard *cb = _general ? system_clipboard() : NULL;
    if (!cb)
        return;
    NSString *s = [[_items firstObject] stringForType:NSPasteboardTypeString];
    if (!s) {
        NSURL *u = [NSURL URLWithString:[[_items firstObject] stringForType:NSPasteboardTypeFileURL] ?: @""];
        s = [u isFileURL] ? [u path] : nil;
    }
    if (!s) {
        /* nothing for the system clipboard: remember what is there, so
         * that it isn't taken for something new */
        char *text = gtk_clipboard_wait_for_text(cb);
        [_lastSystemText release];
        _lastSystemText = text ? [[NSString alloc] initWithUTF8String:text] : nil;
        if (text)
            g_free(text);
        return;
    }
    gtk_clipboard_set_text(cb, [s UTF8String], -1);
    id wasLastSystemText = _lastSystemText;
    _lastSystemText = [s copy];
    [wasLastSystemText release];
}

- (NSInteger)changeCount
{
    [self _syncFromSystem];
    return _changeCount;
}

- (NSInteger)clearContents
{
    if (_owner && [_owner respondsToSelector:@selector(pasteboardChangedOwner:)])
        [_owner pasteboardChangedOwner:self];
    [_owner release];
    _owner = nil;
    [_items removeAllObjects];
    return ++_changeCount;
}
- (NSInteger)prepareForNewContentsWithOptions:(NSPasteboardContentsOptions)options { return [self clearContents]; }

- (NSArray *)pasteboardItems
{
    [self _syncFromSystem];
    return [[_items copy] autorelease];
}
- (NSUInteger)indexOfPasteboardItem:(NSPasteboardItem *)item { return [_items indexOfObjectIdenticalTo:item]; }

- (NSPasteboardItem *)_firstItem
{
    if (![_items count]) {
        NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
        [item _setPasteboard:self];
        [_items addObject:item];
    }
    return [_items objectAtIndex:0];
}

- (BOOL)writeObjects:(NSArray *)objects
{
    BOOL wrote = NO;
    for (id obj in objects) {
        NSPasteboardItem *item;
        if ([obj isKindOfClass:[NSPasteboardItem class]]) {
            item = obj;
        } else if ([obj respondsToSelector:@selector(writableTypesForPasteboard:)]) {
            item = [[[NSPasteboardItem alloc] init] autorelease];
            for (NSString *type in [obj writableTypesForPasteboard:self]) {
                id value = [obj pasteboardPropertyListForType:type];
                if (value)
                    [item setPropertyList:value forType:type];
            }
        } else {
            continue;
        }
        [item _setPasteboard:self];
        [_items addObject:item];
        wrote = YES;
    }
    [self _syncToSystem];
    return wrote;
}

- (NSInteger)declareTypes:(NSArray *)types owner:(id)owner
{
    [self clearContents];
    return [self addTypes:types owner:owner];
}

/* The old way of promising data: the owner is asked for it when it is read. */
- (NSInteger)addTypes:(NSArray *)types owner:(id)owner
{
    NSPasteboardItem *item = [self _firstItem];
    if (owner && owner != _owner) {
        id wasOwner = _owner;
        _owner = [owner retain];
        [wasOwner release];
    }
    for (NSString *type in types)
        if (![[item types] containsObject:type])
            [item _setValue:nil forType:type];
    return _changeCount;
}

- (NSArray *)types
{
    [self _syncFromSystem];
    NSMutableArray *all = [NSMutableArray array];
    BOOL files = NO;
    for (NSPasteboardItem *item in _items) {
        for (NSString *t in [item types])
            if (![all containsObject:t])
                [all addObject:t];
        files |= [[item types] containsObject:NSPasteboardTypeFileURL];
    }
    if (files && ![all containsObject:NSFilenamesPboardType])
        [all addObject:NSFilenamesPboardType];
    return all;
}

- (NSPasteboardType)availableTypeFromArray:(NSArray *)types
{
    NSArray *have = [self types];
    for (NSString *t in types)
        if ([have containsObject:t])
            return t;
    return nil;
}

- (BOOL)canReadItemWithDataConformingToTypes:(NSArray *)types { return [self availableTypeFromArray:types] != nil; }

- (BOOL)_setValue:(id)value forType:(NSString *)type
{
    if ([type isEqualToString:NSFilenamesPboardType] && [value isKindOfClass:[NSArray class]]) {
        /* each path becomes an item of its own */
        [_items removeAllObjects];
        for (NSString *path in value) {
            NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
            [item setString:[[NSURL fileURLWithPath:path] absoluteString] forType:NSPasteboardTypeFileURL];
            [item _setPasteboard:self];
            [_items addObject:item];
        }
        [self _syncToSystem];
        return YES;
    }
    BOOL ok = [[self _firstItem] _setValue:value forType:type];
    if (ok && is_text_type(type))
        [self _syncToSystem];
    return ok;
}
- (BOOL)setData:(NSData *)data forType:(NSPasteboardType)type { return [self _setValue:[[data copy] autorelease] forType:type]; }
- (BOOL)setString:(NSString *)string forType:(NSPasteboardType)type
{
    return [self _setValue:[[string copy] autorelease] forType:type];
}
- (BOOL)setPropertyList:(id)plist forType:(NSPasteboardType)type { return [self _setValue:plist forType:type]; }

/* The first item with the type, asking the owner first if it promised it. */
- (NSPasteboardItem *)_itemWithType:(NSString *)type
{
    [self _syncFromSystem];
    for (NSPasteboardItem *item in _items) {
        if (![[item types] containsObject:type])
            continue;
        if (_owner && ![item _valueForType:type] && [_owner respondsToSelector:@selector(pasteboard:provideDataForType:)])
            [_owner pasteboard:self provideDataForType:type];
        return item;
    }
    return nil;
}

- (NSArray *)_filenames
{
    NSMutableArray *paths = [NSMutableArray array];
    for (NSPasteboardItem *item in _items) {
        NSString *s = [item stringForType:NSPasteboardTypeFileURL];
        NSURL *u = s ? [NSURL URLWithString:s] : nil;
        if ([u isFileURL])
            [paths addObject:[u path]];
    }
    return [paths count] ? paths : nil;
}

- (NSData *)dataForType:(NSPasteboardType)type
{
    if ([type isEqualToString:NSFilenamesPboardType]) {
        NSArray *paths = [self propertyListForType:type];
        return paths ? [NSPropertyListSerialization dataWithPropertyList:paths format:NSPropertyListXMLFormat_v1_0
                                                                 options:0 error:NULL]
                     : nil;
    }
    return [[self _itemWithType:type] dataForType:type];
}
- (NSString *)stringForType:(NSPasteboardType)type { return [[self _itemWithType:type] stringForType:type]; }
- (id)propertyListForType:(NSPasteboardType)type
{
    if ([type isEqualToString:NSFilenamesPboardType]) {
        [self _syncFromSystem];
        id own = [[self _itemWithType:type] propertyListForType:type];
        return own ?: [self _filenames];
    }
    return [[self _itemWithType:type] propertyListForType:type];
}

/* Reading objects: each item becomes an object of the first class that can
 * read one of its types. */
- (id)_objectOfClasses:(NSArray *)classes fromItem:(NSPasteboardItem *)item options:(NSDictionary *)options
{
    for (Class cls in classes) {
        if (cls == [NSPasteboardItem class])
            return item;
        if (![cls respondsToSelector:@selector(readableTypesForPasteboard:)])
            continue;
        BOOL fileOnly = [[options objectForKey:NSPasteboardURLReadingFileURLsOnlyKey] boolValue];
        for (NSString *type in [cls readableTypesForPasteboard:self]) {
            if (![[item types] containsObject:type])
                continue;
            NSPasteboardReadingOptions how = NSPasteboardReadingAsData;
            if ([cls respondsToSelector:@selector(readingOptionsForType:pasteboard:)])
                how = [cls readingOptionsForType:type pasteboard:self];
            id plist = how & NSPasteboardReadingAsString ? (id)[item stringForType:type]
                       : how & NSPasteboardReadingAsPropertyList ? [item propertyListForType:type]
                                                                 : (id)[item dataForType:type];
            if (!plist)
                continue;
            id obj = [[[cls alloc] initWithPasteboardPropertyList:plist ofType:type] autorelease];
            if (obj && fileOnly && [obj isKindOfClass:[NSURL class]] && ![obj isFileURL])
                obj = nil;
            if (obj)
                return obj;
        }
    }
    return nil;
}

- (NSArray *)readObjectsForClasses:(NSArray *)classes options:(NSDictionary *)options
{
    NSMutableArray *found = [NSMutableArray array];
    for (NSPasteboardItem *item in [self pasteboardItems]) {
        id obj = [self _objectOfClasses:classes fromItem:item options:options];
        if (obj)
            [found addObject:obj];
    }
    return [found count] ? found : nil;
}

- (BOOL)canReadObjectForClasses:(NSArray *)classes options:(NSDictionary *)options
{
    return [self readObjectsForClasses:classes options:options] != nil;
}
@end

/* ---- what Foundation's and AppKit's own classes read and write ------------------------ */

@implementation NSString (NSPasteboardSupport)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard { return @[ NSPasteboardTypeString ]; }
- (id)pasteboardPropertyListForType:(NSPasteboardType)type { return self; }
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard
{
    return @[ NSPasteboardTypeString, @"public.plain-text", NSPasteboardTypeURL, NSPasteboardTypeFileURL ];
}
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard
{
    return NSPasteboardReadingAsString;
}
- (id)initWithPasteboardPropertyList:(id)plist ofType:(NSPasteboardType)type
{
    NSString *s = [plist isKindOfClass:[NSString class]] ? plist : nil;
    if ([type isEqualToString:NSPasteboardTypeFileURL] && s)
        s = [[NSURL URLWithString:s] path];
    return s ? [self initWithString:s] : ([self release], nil);
}
@end

@implementation NSURL (NSPasteboardSupport)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard
{
    return [self isFileURL] ? @[ NSPasteboardTypeFileURL, NSPasteboardTypeURL, NSPasteboardTypeString ]
                            : @[ NSPasteboardTypeURL, NSPasteboardTypeString ];
}
- (id)pasteboardPropertyListForType:(NSPasteboardType)type
{
    if ([type isEqualToString:NSPasteboardTypeString])
        return [self isFileURL] ? [self path] : [self absoluteString];
    return [self absoluteString];
}
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard
{
    return @[ NSPasteboardTypeFileURL, NSPasteboardTypeURL ];
}
+ (NSPasteboardReadingOptions)readingOptionsForType:(NSPasteboardType)type pasteboard:(NSPasteboard *)pasteboard
{
    return NSPasteboardReadingAsString;
}
- (id)initWithPasteboardPropertyList:(id)plist ofType:(NSPasteboardType)type
{
    [self release];
    return [plist isKindOfClass:[NSString class]] ? [[NSURL URLWithString:plist] retain] : nil;
}
+ (NSURL *)URLFromPasteboard:(NSPasteboard *)pasteboard
{
    return [[pasteboard readObjectsForClasses:@[ [NSURL class] ] options:nil] firstObject];
}
- (void)writeToPasteboard:(NSPasteboard *)pasteboard { [pasteboard writeObjects:@[ self ]]; }
@end

@implementation NSImage (NSPasteboardSupport)
- (NSArray *)writableTypesForPasteboard:(NSPasteboard *)pasteboard { return @[ NSPasteboardTypeTIFF, NSPasteboardTypePNG ]; }
- (id)pasteboardPropertyListForType:(NSPasteboardType)type
{
    if ([type isEqualToString:NSPasteboardTypeTIFF])
        return [self TIFFRepresentation];
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[self TIFFRepresentation]];
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}
+ (NSArray *)readableTypesForPasteboard:(NSPasteboard *)pasteboard
{
    return @[ NSPasteboardTypePNG, NSPasteboardTypeTIFF, @"public.jpeg", NSPasteboardTypePDF ];
}
- (id)initWithPasteboardPropertyList:(id)plist ofType:(NSPasteboardType)type
{
    return [plist isKindOfClass:[NSData class]] ? [self initWithData:plist] : ([self release], nil);
}
+ (BOOL)canInitWithPasteboard:(NSPasteboard *)pasteboard
{
    return [pasteboard availableTypeFromArray:[self readableTypesForPasteboard:pasteboard]] != nil;
}
- (instancetype)initWithPasteboard:(NSPasteboard *)pasteboard
{
    NSString *type = [pasteboard availableTypeFromArray:[NSImage readableTypesForPasteboard:pasteboard]];
    NSData *data = type ? [pasteboard dataForType:type] : nil;
    return data ? [self initWithData:data] : ([self release], nil);
}
@end
