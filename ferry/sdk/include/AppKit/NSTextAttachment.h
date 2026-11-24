/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSTextAttachment and NSTextAttachmentCell
 * (appkit/NSTextAttachment.m), imported by AppKit.h. Written for freemac
 * from Apple's public API documentation; not Apple's header. */
#ifndef _FERRY_APPKIT_NSTEXTATTACHMENT_H_
#define _FERRY_APPKIT_NSTEXTATTACHMENT_H_
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

enum { NSAttachmentCharacter = 0xFFFC };

APPKIT_EXTERN NSAttributedStringKey const NSAttachmentAttributeName;

@class NSTextAttachment, NSImage, NSView, NSTextContainer;

@protocol NSTextAttachmentCell <NSObject>
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (BOOL)wantsToTrackMouse;
- (void)highlight:(BOOL)flag withFrame:(NSRect)cellFrame inView:(NSView *)controlView;
- (NSSize)cellSize;
- (NSPoint)cellBaselineOffset;
@property (assign) NSTextAttachment *attachment;
@optional
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView characterIndex:(NSUInteger)charIndex;
@end

@interface NSTextAttachment : NSObject <NSCoding>
- (instancetype)initWithData:(NSData *)contentData ofType:(NSString *)uti;
- (instancetype)initWithFileWrapper:(NSFileWrapper *)fileWrapper;
@property (retain) NSData *contents;
@property (retain) NSString *fileType;
@property (retain) NSImage *image;
@property CGRect bounds;
@property (retain) NSFileWrapper *fileWrapper;
@property (retain) id<NSTextAttachmentCell> attachmentCell;
@property CGFloat lineLayoutPadding;
@end

@interface NSTextAttachmentCell : NSCell <NSTextAttachmentCell>
@end

@interface NSAttributedString (NSAttributedStringAttachmentConveniences)
+ (NSAttributedString *)attributedStringWithAttachment:(NSTextAttachment *)attachment;
@end

#endif
