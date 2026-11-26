/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia's attachments (freemac 1.238, Ferry 0.62.0;
 * appkit/CMSampleBuffer.m), on sample buffers and on Core Video's buffers.
 * Written for freemac from Apple's public API documentation; not Apple's
 * header. */
#ifndef _FERRY_CMATTACHMENT_H_
#define _FERRY_CMATTACHMENT_H_
#include <CoreFoundation/CoreFoundation.h>

__FERRY_BEGIN
typedef CFTypeRef CMAttachmentBearerRef;
typedef uint32_t CMAttachmentMode;
enum { kCMAttachmentMode_ShouldNotPropagate = 0, kCMAttachmentMode_ShouldPropagate = 1 };
void CMSetAttachment(CMAttachmentBearerRef target, CFStringRef key, CFTypeRef value, CMAttachmentMode mode);
CFTypeRef CMGetAttachment(CMAttachmentBearerRef target, CFStringRef key, CMAttachmentMode *modeOut);
void CMRemoveAttachment(CMAttachmentBearerRef target, CFStringRef key);
void CMRemoveAllAttachments(CMAttachmentBearerRef target);
CFDictionaryRef CMCopyDictionaryOfAttachments(CFAllocatorRef allocator, CMAttachmentBearerRef target,
                                              CMAttachmentMode mode);
void CMSetAttachments(CMAttachmentBearerRef target, CFDictionaryRef theAttachments, CMAttachmentMode mode);
void CMPropagateAttachments(CMAttachmentBearerRef source, CMAttachmentBearerRef destination);
__FERRY_END
#endif
