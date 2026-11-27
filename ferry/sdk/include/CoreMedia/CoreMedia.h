/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMedia, served from Ferry's AppKit file. Written for
 * freemac from Apple's public API documentation; not Apple's header.
 * Times (freemac 1.233, Ferry 0.57.0, appkit/CoreMedia.m); from freemac
 * 1.238 (Ferry 0.62.0) the host clock, attachments, block buffers, format
 * descriptions and sample buffers (appkit/CMSampleBuffer.m), which
 * ScreenCaptureKit hands its frames and sound in. Decoders, sample buffers
 * of compressed media with packet descriptions, and timebases aren't
 * here. */
#ifndef _FERRY_COREMEDIA_H_
#define _FERRY_COREMEDIA_H_
#include <CoreMedia/CMTime.h>
#include <CoreMedia/CMSync.h>
#include <CoreMedia/CMAttachment.h>
#include <CoreMedia/CMBlockBuffer.h>
#include <CoreMedia/CMFormatDescription.h>
#include <CoreMedia/CMSampleBuffer.h>
#include <CoreMedia/CMSimpleQueue.h>
#endif
