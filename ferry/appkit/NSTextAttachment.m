/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry's AppKit: NSTextAttachment and NSTextAttachmentCell, an image (or a
 * cell) standing in a line of text at an NSAttachmentCharacter.
 *
 * Core Text does the work (graphics/CoreText.m): a run with an attachment
 * under its U+FFFC gets a box of the attachment's size in the line, which
 * moves the text after it along and raises the line to the box's height,
 * and once the line's text is drawn the attachment draws itself in that box.
 * The two private messages below are what Core Text asks of it. So the
 * attachment shows wherever Ferry draws an attributed string: NSString
 * drawing, controls and NSTextView.
 *
 * Written from Apple's public documentation of these classes; no Apple code
 * was used. */
#import "AInternal.h"
#import <AppKit/NSTextAttachment.h>

NSAttributedStringKey const NSAttachmentAttributeName = @"NSAttachment";

@implementation NSTextAttachment {
    NSData *_contents;
    NSString *_fileType;
    NSImage *_image, *_madeImage;
    CGRect _bounds;
    NSFileWrapper *_fileWrapper;
    id<NSTextAttachmentCell> _cell;
    CGFloat _lineLayoutPadding;
}

- (instancetype)initWithData:(NSData *)contentData ofType:(NSString *)uti
{
    if ((self = [super init])) {
        _contents = [contentData retain];
        _fileType = [uti copy];
    }
    return self;
}
- (instancetype)init { return [self initWithData:nil ofType:nil]; }
- (instancetype)initWithFileWrapper:(NSFileWrapper *)fileWrapper
{
    if ((self = [self initWithData:nil ofType:nil]))
        _fileWrapper = [fileWrapper retain];
    return self;
}
- (void)dealloc
{
    [_contents release];
    [_fileType release];
    [_image release];
    [_madeImage release];
    [_fileWrapper release];
    if ([_cell attachment] == self)
        [_cell setAttachment:nil];
    [(id)_cell release];
    [super dealloc];
}

- (NSData *)contents
{
    if (!_contents && _fileWrapper && [_fileWrapper isRegularFile])
        return [_fileWrapper regularFileContents];
    return _contents;
}
- (void)setContents:(NSData *)contents
{
    id wasContents = _contents;
    _contents = [contents retain];
    [wasContents release];
    [_madeImage release];
    _madeImage = nil;
}
- (NSString *)fileType { return _fileType; }
- (void)setFileType:(NSString *)type
{
    id wasFileType = _fileType;
    _fileType = [type copy];
    [wasFileType release];
}
- (NSImage *)image { return _image; }
- (void)setImage:(NSImage *)image
{
    id wasImage = _image;
    _image = [image retain];
    [wasImage release];
}
- (CGRect)bounds { return _bounds; }
- (void)setBounds:(CGRect)bounds { _bounds = bounds; }
- (NSFileWrapper *)fileWrapper { return _fileWrapper; }
- (void)setFileWrapper:(NSFileWrapper *)wrapper
{
    id wasFileWrapper = _fileWrapper;
    _fileWrapper = [wrapper retain];
    [wasFileWrapper release];
    [_madeImage release];
    _madeImage = nil;
}
- (id<NSTextAttachmentCell>)attachmentCell { return _cell; }
- (void)setAttachmentCell:(id<NSTextAttachmentCell>)cell
{
    [(id)cell retain];
    [(id)_cell release];
    _cell = cell;
    [_cell setAttachment:self];
}
- (CGFloat)lineLayoutPadding { return _lineLayoutPadding; }
- (void)setLineLayoutPadding:(CGFloat)padding { _lineLayoutPadding = padding; }

/* The image drawn: the one set, or one read from the contents. */
- (NSImage *)_ferryDrawnImage
{
    if (_image)
        return _image;
    if (!_madeImage) {
        NSData *d = [self contents];
        if ([d length])
            _madeImage = [[NSImage alloc] initWithData:d];
    }
    return _madeImage;
}

/* What Core Text asks: the box, with its origin on the baseline (up), and
 * the drawing in it. */
- (CGRect)_ferryAttachmentBounds
{
    if (_bounds.size.width > 0 || _bounds.size.height > 0)
        return _bounds;
    NSImage *im = [self _ferryDrawnImage];
    if (im) {
        NSSize s = [im size];
        return CGRectMake(0, 0, s.width, s.height);
    }
    if (_cell) {
        NSSize s = [_cell cellSize];
        NSPoint o = [_cell cellBaselineOffset];
        return CGRectMake(o.x, o.y, s.width, s.height);
    }
    return CGRectZero;
}
- (void)_ferryDrawAttachmentInRect:(CGRect)rect context:(CGContextRef)context
{
    NSImage *im = [self _ferryDrawnImage];
    if (im) {
        CGImageRef cg = [im CGImageForProposedRect:NULL context:nil hints:nil];
        if (cg)
            CGContextDrawImage(context, rect, cg);
        return;
    }
    if (_cell) {
        NSGraphicsContext *saved = [[NSGraphicsContext currentContext] retain];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
        [_cell drawWithFrame:rect inView:nil];
        [NSGraphicsContext setCurrentContext:saved];
        [saved release];
    }
}

/* Keyed archives, under keys of Ferry's own. */
- (void)encodeWithCoder:(NSCoder *)coder
{
    if ([self contents])
        [coder encodeObject:[self contents] forKey:@"FerryAttachmentContents"];
    if (_fileType)
        [coder encodeObject:_fileType forKey:@"FerryAttachmentFileType"];
    if (_image)
        [coder encodeObject:_image forKey:@"FerryAttachmentImage"];
    [coder encodeRect:_bounds forKey:@"FerryAttachmentBounds"];
}
- (instancetype)initWithCoder:(NSCoder *)coder
{
    if ((self = [self initWithData:[coder decodeObjectForKey:@"FerryAttachmentContents"]
                            ofType:[coder decodeObjectForKey:@"FerryAttachmentFileType"]])) {
        _image = [[coder decodeObjectForKey:@"FerryAttachmentImage"] retain];
        _bounds = [coder decodeRectForKey:@"FerryAttachmentBounds"];
    }
    return self;
}
@end

@implementation NSTextAttachmentCell {
    NSTextAttachment *_attachment; /* not retained: the attachment holds the cell */
}
- (NSTextAttachment *)attachment { return _attachment; }
- (void)setAttachment:(NSTextAttachment *)attachment { _attachment = attachment; }
- (NSImage *)image { return [super image] ?: [_attachment _ferryDrawnImage]; }
- (NSSize)cellSize
{
    NSImage *im = [self image];
    return im ? [im size] : NSZeroSize;
}
- (NSPoint)cellBaselineOffset { return NSZeroPoint; }
- (BOOL)wantsToTrackMouse { return NO; }
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [self setHighlighted:flag];
}
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [[self image] drawInRect:cellFrame];
}
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView characterIndex:(NSUInteger)charIndex
{
    [self drawWithFrame:cellFrame inView:controlView];
}
@end

@implementation NSAttributedString (NSAttributedStringAttachmentConveniences)
+ (NSAttributedString *)attributedStringWithAttachment:(NSTextAttachment *)attachment
{
    unichar c = NSAttachmentCharacter;
    NSString *s = [NSString stringWithCharacters:&c length:1];
    NSDictionary *attrs = attachment ? @{NSAttachmentAttributeName : attachment} : @{};
    return [[[self alloc] initWithString:s attributes:attrs] autorelease];
}
@end
