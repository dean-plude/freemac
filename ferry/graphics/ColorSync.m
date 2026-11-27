/* SPDX-License-Identifier: GPL-3.0-or-later
 * The corner of ColorSync and CoreDisplay that video players link (freemac
 * 1.262, Ferry 0.85.0, for IINA), written from Apple's public ColorSync
 * documentation. freemac keeps no colour profiles for its displays, so a
 * program that walks them finds none and draws in sRGB, which is what this
 * system's screens show. */
#import "GInternal.h"
#include <CoreGraphics/CGDirectDisplay.h>
#include <stdbool.h>

typedef bool (*ColorSyncDeviceProfileIterateCallback)(CFDictionaryRef profileInfo, void *userInfo);

/* Every display's profile, one call each: there are none. */
void ColorSyncIterateDeviceProfiles(ColorSyncDeviceProfileIterateCallback callBack, void *userInfo)
{
    (void)callBack;
    (void)userInfo;
}

/* A display's details, which CoreDisplay keeps; freemac's displays have
 * none to give. */
CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID display)
{
    (void)display;
    return NULL;
}
