/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: CoreMediaIO, served from Ferry's AppKit file (freemac 1.257,
 * Ferry 0.80.0; appkit/CoreMediaIO.m). Written for freemac from Apple's
 * public API documentation; not Apple's header. Only the system object's
 * property calls are here, which camera code such as OBS's calls to let
 * screen-capture devices show among AVFoundation's cameras; the cameras
 * themselves come through AVCaptureDevice. DAL plug-ins, streams and
 * camera extensions aren't here. */
#ifndef _FERRY_COREMEDIAIO_H_
#define _FERRY_COREMEDIAIO_H_
#include <CoreMediaIO/CMIOHardware.h>
#endif
