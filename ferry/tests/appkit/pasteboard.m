/* SPDX-License-Identifier: GPL-3.0-or-later
 * Pasteboards (M7): types, items, the old and new type names reading each
 * other, objects written and read back, data promised by an owner or a
 * provider, and cut, copy and paste in a text field, with the Edit menu's
 * items enabled to match. Runs with no display, so only Ferry's own
 * pasteboards are used, not this system's clipboard. */
#import <Cocoa/Cocoa.h>

@interface Owner : NSObject <NSPasteboardItemDataProvider>
@property int asked;
@end
@implementation Owner
- (void)pasteboard:(NSPasteboard *)pb provideDataForType:(NSPasteboardType)type
{
    self.asked++;
    [pb setString:@"made when asked" forType:type];
}
- (void)pasteboard:(NSPasteboard *)pb item:(NSPasteboardItem *)item provideDataForType:(NSPasteboardType)type
{
    self.asked++;
    [item setString:@"from the provider" forType:type];
}
@end

static void list(const char *what, NSArray *objects)
{
    printf("%s:", what);
    for (id o in objects)
        printf(" %s(%s)", [NSStringFromClass([o class]) hasPrefix:@"NSURL"] ? "NSURL"
                          : [o isKindOfClass:[NSString class]]               ? "NSString"
                                                                             : [NSStringFromClass([o class]) UTF8String],
               [[o description] UTF8String]);
    printf("\n");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        printf("general is general: %s, named: %s\n", pb == [NSPasteboard pasteboardWithName:NSPasteboardNameGeneral] ? "yes" : "no",
               pb == [NSPasteboard pasteboardWithName:NSGeneralPboard] ? "yes" : "no");

        /* strings, by either name */
        NSInteger c0 = [pb changeCount];
        NSInteger c1 = [pb clearContents];
        [pb setString:@"hello" forType:NSPasteboardTypeString];
        printf("changeCount went up: %s\n", c1 > c0 && [pb changeCount] == c1 ? "yes" : "no");
        printf("read as NSStringPboardType: %s\n", [[pb stringForType:NSStringPboardType] UTF8String]);
        printf("as data: %lu bytes\n", (unsigned long)[[pb dataForType:NSPasteboardTypeString] length]);
        printf("available from [PNG, string]: %s\n",
               [[pb availableTypeFromArray:@[ NSPasteboardTypePNG, NSPasteboardTypeString ]] UTF8String]);
        printf("no PNG: %s\n", [pb dataForType:NSPasteboardTypePNG] ? "wrong" : "nil");

        /* the old way: declareTypes then set */
        [pb declareTypes:@[ NSStringPboardType, @"com.example.private" ] owner:nil];
        [pb setString:@"old style" forType:NSStringPboardType];
        [pb setPropertyList:@{@"k" : @"v"} forType:@"com.example.private"];
        printf("types: %s\n", [[[pb types] componentsJoinedByString:@", "] UTF8String]);
        printf("string %s, plist k=%s\n", [[pb stringForType:NSPasteboardTypeString] UTF8String],
               [[[pb propertyListForType:@"com.example.private"] objectForKey:@"k"] UTF8String]);

        /* promised by the owner, made when read */
        Owner *owner = [[Owner alloc] init];
        [pb declareTypes:@[ NSPasteboardTypeString ] owner:owner];
        printf("owner asked before reading: %d\n", owner.asked);
        printf("read: %s; owner asked %d\n", [[pb stringForType:NSPasteboardTypeString] UTF8String], owner.asked);
        [pb stringForType:NSPasteboardTypeString];
        printf("read again: owner asked %d\n", owner.asked);

        /* objects: several items, read back by class */
        [pb clearContents];
        NSURL *file = [NSURL fileURLWithPath:@"/tmp/some file.txt"];
        [pb writeObjects:@[ @"plain text", file, [NSURL URLWithString:@"https://example.org/x"] ]];
        printf("items: %lu\n", (unsigned long)[[pb pasteboardItems] count]);
        list("as strings", [pb readObjectsForClasses:@[ [NSString class] ] options:nil]);
        list("as URLs", [pb readObjectsForClasses:@[ [NSURL class] ] options:nil]);
        list("file URLs only", [pb readObjectsForClasses:@[ [NSURL class] ]
                                                 options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}]);
        list("filenames", [pb propertyListForType:NSFilenamesPboardType]);
        printf("URL from pasteboard: %s\n", [[[NSURL URLFromPasteboard:pb] path] UTF8String]);

        /* NSFilenamesPboardType written: each path is an item */
        [pb declareTypes:@[ NSFilenamesPboardType ] owner:nil];
        [pb setPropertyList:@[ @"/a/one", @"/b/two" ] forType:NSFilenamesPboardType];
        list("filenames back", [pb propertyListForType:NSFilenamesPboardType]);
        list("as URLs", [pb readObjectsForClasses:@[ [NSURL class] ] options:nil]);

        /* an item with a provider */
        NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
        [item setDataProvider:owner forTypes:@[ @"com.example.lazy" ]];
        [pb clearContents];
        [pb writeObjects:@[ item ]];
        owner.asked = 0;
        printf("provider: %s (asked %d)\n", [[pb stringForType:@"com.example.lazy"] UTF8String], owner.asked);

        /* an image */
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(4, 3)];
        [img lockFocus];
        [[NSColor redColor] set];
        NSRectFill(NSMakeRect(0, 0, 4, 3));
        [img unlockFocus];
        [pb clearContents];
        [pb writeObjects:@[ img ]];
        NSImage *back = [[pb readObjectsForClasses:@[ [NSImage class] ] options:nil] firstObject];
        printf("image back: %.0fx%.0f, can init: %s\n", back.size.width, back.size.height,
               [NSImage canInitWithPasteboard:pb] ? "yes" : "no");

        /* a separate pasteboard keeps its own contents */
        NSPasteboard *mine = [NSPasteboard pasteboardWithUniqueName];
        [mine clearContents];
        [mine setString:@"mine" forType:NSPasteboardTypeString];
        printf("unique: %s; general still has an image: %s\n", [[mine stringForType:NSPasteboardTypeString] UTF8String],
               [pb availableTypeFromArray:@[ NSPasteboardTypeTIFF ]] ? "yes" : "no");

        /* cut, copy and paste in a text field */
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100) styleMask:NSWindowStyleMaskTitled
                                                    backing:NSBackingStoreBuffered defer:NO];
        NSTextField *field = [NSTextField textFieldWithString:@"Hello world"];
        field.frame = NSMakeRect(10, 40, 200, 22);
        [[w contentView] addSubview:field];
        [w makeKeyAndOrderFront:nil];
        [w makeFirstResponder:field];
        [field selectText:nil];
        NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
        NSMenuItem *pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
        printf("copy enabled with a selection: %s\n", [(id)field validateMenuItem:copyItem] ? "yes" : "no");
        [NSApp sendAction:@selector(copy:) to:nil from:copyItem];
        printf("copied: %s\n", [[pb stringForType:NSPasteboardTypeString] UTF8String]);
        [NSApp sendAction:@selector(moveToEndOfLine:) to:nil from:nil];
        printf("copy enabled with no selection: %s\n", [(id)field validateMenuItem:copyItem] ? "yes" : "no");
        [NSApp sendAction:@selector(paste:) to:nil from:pasteItem];
        printf("after paste: %s\n", [[field stringValue] UTF8String]);
        [NSApp sendAction:@selector(moveWordLeftAndModifySelection:) to:nil from:nil];
        [NSApp sendAction:@selector(cut:) to:nil from:nil];
        printf("after cutting a word: \"%s\", pasteboard \"%s\"\n", [[field stringValue] UTF8String],
               [[pb stringForType:NSPasteboardTypeString] UTF8String]);
        [pb clearContents];
        printf("paste enabled with nothing to paste: %s\n", [(id)field validateMenuItem:pasteItem] ? "yes" : "no");

        NSSecureTextField *secret = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(10, 10, 200, 22)];
        [secret setStringValue:@"hunter2"];
        [[w contentView] addSubview:secret];
        [w makeFirstResponder:secret];
        [secret selectText:nil];
        printf("copy enabled in a password field: %s\n", [(id)secret validateMenuItem:copyItem] ? "yes" : "no");
    }
    return 0;
}
