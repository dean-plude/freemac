/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: drawing an Icon Services icon into a Core Graphics context,
 * written from Apple's public "Icon Services and Utilities Reference"; not
 * Apple's header. The icon drawn is the desktop's own for the file or type
 * the reference names, so no Apple artwork is used. Served from AppKit's
 * file, through Carbon and ApplicationServices. */
#ifndef _FERRY_HISERVICES_ICONS_H_
#define _FERRY_HISERVICES_ICONS_H_
#include <CoreGraphics/CoreGraphics.h>
#include <CoreServices/CoreServices.h>
#include <CoreServices/IconsCore.h>

__FERRY_BEGIN

#ifndef _FERRY_RGBCOLOR_
#define _FERRY_RGBCOLOR_
/* QuickDraw's colour, each part 0 to 65535 */
typedef struct RGBColor {
    unsigned short red;
    unsigned short green;
    unsigned short blue;
} RGBColor;
#endif

typedef SInt16 IconAlignmentType;
enum {
    kAlignNone = 0x00, kAlignVerticalCenter = 0x01, kAlignTop = 0x02, kAlignBottom = 0x03,
    kAlignHorizontalCenter = 0x04, kAlignAbsoluteCenter = 0x05, kAlignCenterTop = 0x06,
    kAlignCenterBottom = 0x07, kAlignLeft = 0x08, kAlignCenterLeft = 0x09, kAlignTopLeft = 0x0a,
    kAlignBottomLeft = 0x0b, kAlignRight = 0x0c, kAlignCenterRight = 0x0d, kAlignTopRight = 0x0e,
    kAlignBottomRight = 0x0f
};
typedef SInt16 IconTransformType;
enum {
    kTransformNone = 0x00, kTransformDisabled = 0x01, kTransformOffline = 0x02, kTransformOpen = 0x03,
    kTransformLabel1 = 0x0100, kTransformSelected = 0x4000
};
typedef UInt32 PlotIconRefFlags;
enum { kPlotIconRefNormalFlags = 0, kPlotIconRefNoImage = 1u << 1, kPlotIconRefNoMask = 1u << 2 };

OSStatus PlotIconRefInContext(CGContextRef inContext, const CGRect *inRect, IconAlignmentType inAlign,
                              IconTransformType inTransform, const RGBColor *inLabelColor,
                              PlotIconRefFlags inFlags, IconRef inIconRef);
Boolean IsIconRefMaskEmpty(IconRef iconRef);

__FERRY_END
#endif
