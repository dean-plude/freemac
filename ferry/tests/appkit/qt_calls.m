/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Qt's Mac platform plugin calls besides the rest (AppKitQt.m), for
 * OBS Studio: Carbon's Pasteboard Manager over NSPasteboard, with a flavor
 * promised and kept only when read; Icon Services icons drawn into a
 * bitmap; a view's text input context handing it key presses; screen
 * depths and ICC colour spaces; the window list; Handoff's user
 * activities; and the newer event types' numbers. */
#import <Cocoa/Cocoa.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>

static int kept;

static OSStatus keeper(PasteboardRef pb, PasteboardItemID item, CFStringRef flavor, void *context)
{
    kept++;
    NSString *s = [NSString stringWithFormat:@"kept %@ for item %lu (%s)", flavor, (unsigned long)item,
                                             (const char *)context];
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    return PasteboardPutItemFlavor(pb, item, flavor, (CFDataRef)d, kPasteboardFlavorNoFlags);
}

@interface TypingView : NSView <NSTextInputClient> {
@public
    NSMutableString *log;
}
@end
@implementation TypingView
- (void)insertText:(id)string replacementRange:(NSRange)r { [log appendFormat:@"[insert %@]", string]; }
- (void)doCommandBySelector:(SEL)s { [log appendFormat:@"[%s]", sel_getName(s)]; }
- (void)setMarkedText:(id)s selectedRange:(NSRange)a replacementRange:(NSRange)b { }
- (void)unmarkText { [log appendString:@"[unmark]"]; }
- (NSRange)selectedRange { return NSMakeRange(0, 0); }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return NO; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)a { return nil; }
- (NSArray *)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a { return NSZeroRect; }
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return 0; }
@end

static NSEvent *key(NSString *chars, NSEventModifierFlags flags)
{
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0
                        windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:chars
                           isARepeat:NO keyCode:0];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        /* the Pasteboard Manager */
        PasteboardRef pb = NULL;
        OSStatus r = PasteboardCreate(kPasteboardUniqueName, &pb);
        PasteboardClear(pb);
        PasteboardSetPromiseKeeper(pb, keeper, (void *)"qt");
        NSData *plain = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
        PasteboardPutItemFlavor(pb, (PasteboardItemID)1, CFSTR("public.utf8-plain-text"), (CFDataRef)plain, 0);
        PasteboardPutItemFlavor(pb, (PasteboardItemID)1, CFSTR("public.html"), NULL, 0);
        PasteboardPutItemFlavor(pb, (PasteboardItemID)2, CFSTR("public.utf8-plain-text"), NULL, 0);
        ItemCount n = 0;
        PasteboardGetItemCount(pb, &n);
        PasteboardSyncFlags sync = PasteboardSynchronize(pb);
        printf("create %d, %lu items, owner %d modified %d, nothing kept yet %d\n", (int)r, (unsigned long)n,
               (sync & kPasteboardClientIsOwner) != 0, (sync & kPasteboardModified) != 0, kept == 0);
        for (CFIndex i = 1; i <= (CFIndex)n; i++) {
            PasteboardItemID ident = NULL;
            PasteboardGetItemIdentifier(pb, i, &ident);
            CFArrayRef flavors = NULL;
            PasteboardCopyItemFlavors(pb, ident, &flavors);
            printf("item %ld is %lu: %s\n", (long)i, (unsigned long)ident,
                   [[(NSArray *)flavors componentsJoinedByString:@", "] UTF8String]);
            for (NSString *f in (NSArray *)flavors) {
                CFDataRef d = NULL;
                OSStatus e = PasteboardCopyItemFlavorData(pb, ident, (CFStringRef)f, &d);
                printf("  %s: %d \"%s\"\n", [f UTF8String], (int)e,
                       d ? [[[[NSString alloc] initWithData:(NSData *)d encoding:NSUTF8StringEncoding] autorelease]
                               UTF8String]
                         : "");
                if (d)
                    CFRelease(d);
            }
            CFRelease(flavors);
        }
        PasteboardFlavorFlags ff = 99;
        CFArrayRef noflavors = NULL;
        printf("flags %d %u, missing flavor %d, no item %d, kept %d\n",
               (int)PasteboardGetItemFlavorFlags(pb, (PasteboardItemID)1, CFSTR("public.html"), &ff), (unsigned)ff,
               (int)PasteboardGetItemFlavorFlags(pb, (PasteboardItemID)1, CFSTR("public.png"), &ff),
               (int)PasteboardCopyItemFlavors(pb, (PasteboardItemID)9, &noflavors), kept);
        /* the same pasteboard written through AppKit is news to the Carbon side */
        CFStringRef name = NULL;
        PasteboardCopyName(pb, &name);
        NSPasteboard *same = [NSPasteboard pasteboardWithName:(NSString *)name];
        [same clearContents];
        [same setString:@"from AppKit" forType:NSPasteboardTypeString];
        sync = PasteboardSynchronize(pb);
        CFDataRef d = NULL;
        PasteboardCopyItemFlavorData(pb, (PasteboardItemID)1, CFSTR("public.utf8-plain-text"), &d);
        printf("modified %d, then %d; reads \"%s\"\n", (sync & kPasteboardModified) != 0,
               (PasteboardSynchronize(pb) & kPasteboardModified) != 0,
               [[[[NSString alloc] initWithData:(NSData *)d encoding:NSUTF8StringEncoding] autorelease] UTF8String]);
        CFRelease(d);
        CFRelease(name);
        CFRelease(pb);
        PasteboardRef clip = NULL;
        PasteboardCreate(kPasteboardClipboard, &clip);
        PasteboardCopyName(clip, &name);
        printf("clipboard is the general pasteboard %d\n", [(NSString *)name isEqual:NSPasteboardNameGeneral]);
        CFRelease(name);
        CFRelease(clip);

        /* Icon Services */
        IconRef icon = NULL;
        r = GetIconRef(kOnSystemDisk, kSystemIconsCreator, kQuestionMarkIcon, &icon);
        unsigned char pixels[32 * 32 * 4] = { 0 };
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(pixels, 32, 32, 8, 32 * 4, rgb, kCGImageAlphaPremultipliedLast);
        CGRect rect = CGRectMake(0, 0, 32, 32);
        RGBColor label = { 65535, 65535, 65535 };
        OSStatus plotted =
            PlotIconRefInContext(ctx, &rect, kAlignNone, kTransformNone, &label, kPlotIconRefNormalFlags, icon);
        int painted = 0;
        for (int i = 3; i < (int)sizeof pixels; i += 4)
            painted += pixels[i] != 0;
        printf("icon %d %s, plotted %d, painted %d\n", (int)r, [(NSString *)icon UTF8String], (int)plotted,
               painted > 0);
        ReleaseIconRef(icon);
        CGContextRelease(ctx);
        CGColorSpaceRelease(rgb);

        /* text input */
        TypingView *v = [[[TypingView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        v->log = [NSMutableString string];
        NSTextInputContext *ic = [v inputContext];
        BOOL handled = [ic handleEvent:key(@"a", 0)];
        [ic handleEvent:key(@"\r", 0)];
        [ic handleEvent:key(@"c", NSEventModifierFlagCommand)];
        [ic discardMarkedText];
        printf("context %d, same %d, plain view %d; handled %d: %s\n", [ic client] == v, [v inputContext] == ic,
               [[[[NSView alloc] init] autorelease] inputContext] == nil, handled, [v->log UTF8String]);

        /* screens and colour spaces */
        NSData *icc = [[NSColorSpace sRGBColorSpace] ICCProfileData];
        NSColorSpace *back = [[[NSColorSpace alloc] initWithICCProfileData:icc] autorelease];
        printf("depth %ld bits, %ld per sample, separate spaces %d, ICC %d, back %d, no data %d\n",
               (long)NSBitsPerPixelFromDepth(NSWindowDepthTwentyfourBitRGB),
               (long)NSBitsPerSampleFromDepth(NSWindowDepthTwentyfourBitRGB), NSScreen.screensHaveSeparateSpaces,
               [icc length] > 128, back != nil, [[[NSColorSpace alloc] initWithICCProfileData:nil] autorelease] == nil);
        printf("key repeat after %.2f s, every %.3f s\n", NSEvent.keyRepeatDelay, NSEvent.keyRepeatInterval);

        /* the window list */
        NSWindow *w1 = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50) styleMask:0
                                                     backing:NSBackingStoreBuffered defer:YES];
        NSWindow *w2 = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 50, 50) styleMask:0
                                                     backing:NSBackingStoreBuffered defer:YES];
        __block int seen = 0;
        [NSApp enumerateWindowsWithOptions:NSWindowListOrderedFrontToBack
                                usingBlock:^(NSWindow *w, BOOL *stop) {
                                    seen++;
                                    *stop = YES;
                                }];
        printf("enumerated %d window and stopped\n", seen);
        [w1 release];
        [w2 release];

        /* Handoff and layers */
        NSUserActivity *act = [[[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb] autorelease];
        act.webpageURL = [NSURL URLWithString:@"https://obsproject.com"];
        [act becomeCurrent];
        CALayer *layer = [CALayer layer];
        layer.wantsExtendedDynamicRangeContent = YES;
        printf("activity %s %s, layer EDR %d\n", [act.activityType UTF8String],
               [[act.webpageURL host] UTF8String], layer.wantsExtendedDynamicRangeContent);
        printf("events: magnify %d swipe %d tablet %d gesture mask %d\n", (int)NSEventTypeMagnify,
               (int)NSEventTypeSwipe, (int)NSEventTypeTabletPoint, NSEventMaskGesture == (1ULL << 29));

        /* touches, tablets, window tabs and steps, layer placement, image spaces */
        NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                       timestamp:0 windowNumber:0 context:nil characters:@"a"
                     charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
        printf("touches %lu, device %lu, tablet %d\n",
               (unsigned long)[key touchesMatchingPhase:NSTouchPhaseAny inView:nil].count,
               (unsigned long)key.deviceID, (int)key.pointingDeviceType);
        NSWindow *w3 = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 80, 60) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:YES];
        printf("tabbing %d", (int)w3.tabbingMode);
        w3.tabbingMode = NSWindowTabbingModeDisallowed;
        w3.resizeIncrements = NSMakeSize(4, 8);
        printf(" then %d, steps %.0fx%.0f, modal %d, space is sRGB %d\n", (int)w3.tabbingMode,
               w3.resizeIncrements.width, w3.resizeIncrements.height, w3.worksWhenModal,
               [w3.colorSpace isEqual:[NSColorSpace sRGBColorSpace]]);
        NSView *v3 = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        v3.layerContentsPlacement = NSViewLayerContentsPlacementTopLeft;
        v3.allowedTouchTypes |= NSTouchTypeMaskIndirect;
        printf("placement %d, touch types %lu\n", (int)v3.layerContentsPlacement,
               (unsigned long)v3.allowedTouchTypes);
        [w3 release];
        CGColorSpaceRef rgb3 = CGColorSpaceCreateDeviceRGB(), srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
        CGContextRef bc = CGBitmapContextCreate(NULL, 4, 4, 8, 16, rgb3, kCGImageAlphaPremultipliedFirst);
        CGImageRef img = CGBitmapContextCreateImage(bc);
        CGImageRef in_srgb = CGImageCreateCopyWithColorSpace(img, srgb);
        CGImageRef in_gray = CGImageCreateCopyWithColorSpace(img, gray);
        printf("image copy %zux%zu in sRGB %d, in grey %d; enter %d return %d\n", CGImageGetWidth(in_srgb),
               CGImageGetHeight(in_srgb), CGImageGetColorSpace(in_srgb) == srgb, in_gray == NULL,
               kEnterCharCode, kReturnCharCode);
        CFPropertyListRef named = CGColorSpaceCopyPropertyList(srgb), unnamed = CGColorSpaceCopyPropertyList(rgb3);
        CGColorSpaceRef again = CGColorSpaceCreateWithPropertyList(named);
        NSMenu *bar = [[[NSMenu alloc] initWithTitle:@"bar"] autorelease];
        printf("space list %d, device space list %d, back %d; plain menu height %g; knob styles %ld %ld\n",
               CFGetTypeID(named) == CFStringGetTypeID(), unnamed != NULL,
               CGColorSpaceGetModel(again) == kCGColorSpaceModelRGB, [bar menuBarHeight],
               (long)NSScrollerKnobStyleDark, (long)NSScrollerKnobStyleLight);
        CFRelease(named);
        if (unnamed)
            CFRelease(unnamed);
        CGColorSpaceRelease(again);
        CGImageRelease(in_srgb);
        CGImageRelease(img);
        CGContextRelease(bc);
        CGColorSpaceRelease(rgb3);
        CGColorSpaceRelease(srgb);
        CGColorSpaceRelease(gray);
    }
    return 0;
}
