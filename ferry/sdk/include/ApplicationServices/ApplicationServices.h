/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: ApplicationServices gathers Core Graphics and Core Text. */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
/* ImageIO comes with ApplicationServices, as on a Mac (freemac 1.225, Ferry 0.49.0). */
#include <ImageIO/ImageIO.h>
/* ApplicationServices sits on CoreServices, as on a Mac (freemac 1.219, Ferry 0.43.0). */
#include <CoreServices/CoreServices.h>
/* The Accessibility API (freemac 1.215, Ferry 0.41.0); served from AppKit's file. */
#include <HIServices/Accessibility.h>
/* The Process Manager (HIServices); served from AppKit's file. */
#include <HIServices/Processes.h>
