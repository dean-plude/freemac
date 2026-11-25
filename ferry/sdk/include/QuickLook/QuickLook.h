/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: QuickLook (freemac 1.222, Ferry 0.46.0), written for freemac
 * from Apple's public documentation; not Apple's header. The calls a Quick
 * Look generator answers its requests with, as Sequel Pro's generator
 * does, the keys of a preview's properties, and QLThumbnailImageCreate.
 * Ferry has no Finder to ask a generator for previews, so no request ever
 * reaches one; the panel that shows previews, QLPreviewPanel, is in
 * <Quartz/Quartz.h>. Served from AppKit's file. */
#ifndef _FERRY_QUICKLOOK_H_
#define _FERRY_QUICKLOOK_H_
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreServices/CoreServices.h>

__FERRY_BEGIN

#define QL_EXPORT extern

enum { kQLReturnNoError = noErr, kQLReturnMask = 0xaf00, kQLReturnHasMore = kQLReturnMask | 10 };

/* ---- what a generator is asked for ---- */
typedef struct __QLPreviewRequest *QLPreviewRequestRef;
typedef struct __QLThumbnailRequest *QLThumbnailRequestRef;

/* the keys of a preview's properties */
QL_EXPORT const CFStringRef kQLPreviewPropertyDisplayNameKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyWidthKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyHeightKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyBaseBundlePathKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyStringEncodingKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyMIMETypeKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyTextEncodingNameKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyAttachmentDataKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyAttachmentsKey;
QL_EXPORT const CFStringRef kQLPreviewPropertyPDFStyleKey;
QL_EXPORT const CFStringRef kQLPreviewContentIDScheme;
QL_EXPORT const CFStringRef kQLPreviewOptionCursorKey;
/* and of a thumbnail's options and properties */
QL_EXPORT const CFStringRef kQLThumbnailOptionIconModeKey;
QL_EXPORT const CFStringRef kQLThumbnailOptionScaleFactorKey;
QL_EXPORT const CFStringRef kQLThumbnailOptionContentTypeUTI;
QL_EXPORT const CFStringRef kQLThumbnailPropertyExtensionKey;
QL_EXPORT const CFStringRef kQLThumbnailPropertyBadgeImageKey;
QL_EXPORT const CFStringRef kQLThumbnailPropertyIconFlavorKey;

typedef enum {
    kQLPreviewPDFStandardStyle = 0,
    kQLPreviewPDFPagesWithThumbnailsOnRightStyle = 3,
    kQLPreviewPDFPagesWithThumbnailsOnLeftStyle = 4,
} QLPreviewPDFStyle;

CFTypeID QLPreviewRequestGetTypeID(void);
CFURLRef QLPreviewRequestCopyURL(QLPreviewRequestRef preview);
CFDictionaryRef QLPreviewRequestCopyOptions(QLPreviewRequestRef preview);
CFStringRef QLPreviewRequestCopyContentUTI(QLPreviewRequestRef preview);
CFBundleRef QLPreviewRequestGetGeneratorBundle(QLPreviewRequestRef preview);
Boolean QLPreviewRequestIsCancelled(QLPreviewRequestRef preview);
void QLPreviewRequestSetDataRepresentation(QLPreviewRequestRef preview, CFDataRef data, CFStringRef contentTypeUTI,
                                           CFDictionaryRef properties);
void QLPreviewRequestSetURLRepresentation(QLPreviewRequestRef preview, CFURLRef url, CFStringRef contentTypeUTI,
                                          CFDictionaryRef properties);
CGContextRef QLPreviewRequestCreateContext(QLPreviewRequestRef preview, CGSize size, Boolean isBitmap,
                                           CFDictionaryRef properties);
CGContextRef QLPreviewRequestCreatePDFContext(QLPreviewRequestRef preview, const CGRect *mediaBox,
                                              CFDictionaryRef auxiliaryInfo, CFDictionaryRef properties);
void QLPreviewRequestFlushContext(QLPreviewRequestRef preview, CGContextRef context);

CFTypeID QLThumbnailRequestGetTypeID(void);
CFURLRef QLThumbnailRequestCopyURL(QLThumbnailRequestRef thumbnail);
CFDictionaryRef QLThumbnailRequestCopyOptions(QLThumbnailRequestRef thumbnail);
CFStringRef QLThumbnailRequestCopyContentUTI(QLThumbnailRequestRef thumbnail);
CGSize QLThumbnailRequestGetMaximumSize(QLThumbnailRequestRef thumbnail);
CFBundleRef QLThumbnailRequestGetGeneratorBundle(QLThumbnailRequestRef thumbnail);
Boolean QLThumbnailRequestIsCancelled(QLThumbnailRequestRef thumbnail);
void QLThumbnailRequestSetImage(QLThumbnailRequestRef thumbnail, CGImageRef image, CFDictionaryRef properties);
void QLThumbnailRequestSetImageWithData(QLThumbnailRequestRef thumbnail, CFDataRef data, CFDictionaryRef properties);
void QLThumbnailRequestSetImageAtURL(QLThumbnailRequestRef thumbnail, CFURLRef url, CFDictionaryRef properties);
CGContextRef QLThumbnailRequestCreateContext(QLThumbnailRequestRef thumbnail, CGSize size, Boolean isBitmap,
                                             CFDictionaryRef properties);
void QLThumbnailRequestFlushContext(QLThumbnailRequestRef thumbnail, CGContextRef context);
void QLThumbnailRequestSetThumbnailWithDataRepresentation(QLThumbnailRequestRef thumbnail, CFDataRef data,
                                                          CFStringRef contentTypeUTI, CFDictionaryRef previewProperties,
                                                          CFDictionaryRef properties);
void QLThumbnailRequestSetThumbnailWithURLRepresentation(QLThumbnailRequestRef thumbnail, CFURLRef url,
                                                         CFStringRef contentTypeUTI, CFDictionaryRef previewProperties,
                                                         CFDictionaryRef properties);

/* A thumbnail of a file, no larger than maxThumbnailSize: a picture made
 * smaller, or with kQLThumbnailOptionIconModeKey true the file's icon;
 * NULL for a file that isn't there, or isn't a picture when no icon is
 * asked for. */
CGImageRef QLThumbnailImageCreate(CFAllocatorRef allocator, CFURLRef url, CGSize maxThumbnailSize,
                                  CFDictionaryRef options);

__FERRY_END
#endif
