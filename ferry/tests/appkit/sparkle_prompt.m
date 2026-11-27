/* SPDX-License-Identifier: GPL-3.0-or-later
 * VLC's updater, Sparkle 1.16 as VLC's own Mac build ships it (freemac
 * 1.NEXT). Its "Check for updates automatically?" prompt holds the message
 * in a text field that Xcode wrote as a word-wrapping cell that neither
 * scrolls nor keeps to one line (cell flags 0x04000000, line breaking 0); a
 * Mac wraps it over two lines, and Ferry cut it off after one. Ferry's own
 * ferry-ibtool marks such cells with a further bit, which Xcode doesn't
 * write. VLC's preferences show when the updater last looked with
 * NSDate's descriptionWithLocale:. The cells are made here with a keyed
 * archiver, under the class names a nib uses. */
#import <Cocoa/Cocoa.h>

@interface NibCell : NSObject <NSCoding>
@property(copy) NSString *text;
@property unsigned flags, flags2;
@end
@implementation NibCell
- (instancetype)initWithCoder:(NSCoder *)c { return nil; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_text forKey:@"NSContents"];
    [c encodeInt64:_flags forKey:@"NSCellFlags"];
    [c encodeInt64:_flags2 forKey:@"NSCellFlags2"];
}
@end

@interface NibField : NSObject <NSCoding>
@property(strong) NibCell *cell;
@end
@implementation NibField
- (instancetype)initWithCoder:(NSCoder *)c { return nil; }
- (void)encodeWithCoder:(NSCoder *)c
{
    [c encodeObject:_cell forKey:@"NSCell"];
    [c encodeObject:@"{{0, 0}, {315, 42}}" forKey:@"NSFrame"];
    [c encodeBool:YES forKey:@"NSEnabled"];
}
@end

static id decoded(id root, NSString *cellClass, NSString *viewClass)
{
    NSKeyedArchiver *a = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    [a setClassName:cellClass forClass:[NibCell class]];
    [a setClassName:viewClass forClass:[NibField class]];
    [a encodeObject:root forKey:NSKeyedArchiveRootObjectKey];
    [a finishEncoding];
    NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:[a encodedData] error:NULL];
    [u setRequiresSecureCoding:NO];
    return [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
}

static NibCell *nib_cell(unsigned flags, unsigned flags2)
{
    NibCell *c = [NibCell new];
    c.text = @"Should VLC automatically check for updates? You can always check for updates manually "
             @"from the VLC menu.";
    c.flags = flags;
    c.flags2 = flags2;
    return c;
}

static void cell(const char *what, unsigned flags, unsigned flags2, NSString *cls)
{
    NSCell *c = decoded(nib_cell(flags, flags2), cls, @"NSTextField");
    printf("%s: wraps %d, line break %ld, single line %d\n", what, [c wraps], (long)[c lineBreakMode],
           [c usesSingleLineMode]);
}

static CGFloat lum(NSBitmapImageRep *rep, NSInteger x, NSInteger y)
{
    NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    CGFloat a = [c alphaComponent];
    return a * (0.3 * [c redComponent] + 0.59 * [c greenComponent] + 0.11 * [c blueComponent]) + (1 - a);
}

/* the bands of rows with ink in them */
static void field(void)
{
    NibField *f = [NibField new];
    f.cell = nib_cell(0x04000000, 0x10400000);
    NSTextField *t = decoded(f, @"NSTextFieldCell", @"NSTextField");
    [t setFont:[NSFont systemFontOfSize:11]];
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 315, 42) styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered defer:YES];
    [[w contentView] addSubview:t];
    NSBitmapImageRep *rep = [t bitmapImageRepForCachingDisplayInRect:[t bounds]];
    [t cacheDisplayInRect:[t bounds] toBitmapImageRep:rep];
    int bands = 0;
    BOOL was = NO;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        BOOL ink = NO;
        for (NSInteger x = 0; x < rep.pixelsWide && !ink; x++)
            ink = lum(rep, x, y) < 0.5;
        if (ink && !was)
            bands++;
        was = ink;
    }
    printf("text field: %d line%s\n", bands, bands == 1 ? "" : "s");
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        cell("multi-line label", 0x04000000, 0x10400000, @"NSTextFieldCell");
        cell("clipping label", 0x04100040, 0x10400400, @"NSTextFieldCell");
        cell("single-line label", 0x04000200, 0x10400000, @"NSTextFieldCell");
        cell("push button", 0x04000000, 0x08000000, @"NSButtonCell");
        field();

        NSDate *d = [NSDate dateWithTimeIntervalSince1970:400 * 86400];
        NSString *s = [d descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
        printf("date with locale: has 1971 %d, plain without one %d\n", [s rangeOfString:@"1971"].length > 0,
               [[d descriptionWithLocale:nil] isEqual:[d description]]);
    }
    return 0;
}
