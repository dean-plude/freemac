/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * Screen capture's Wayland back end (freemac 1.238, Ferry 0.62.0): not
 * written yet. On Wayland (freemac's own desktop is Wayfire) an app can't
 * read the screen itself; the way is the xdg-desktop-portal's ScreenCast
 * portal over D-Bus (CreateSession, SelectSources, Start, then
 * OpenPipeWireRemote), which asks the user and hands back PipeWire
 * streams of the chosen monitors or windows, read with libpipewire. That
 * would sit behind the same interface as the X11 back end (ACapture.h):
 * the portal's streams as the displays and windows, a PipeWire stream for
 * each grabber, its buffers as the images, and the portal's cursor
 * metadata as the pointer. Until then this back end has nothing to show,
 * and says so once. Set FERRY_CAPTURE=x11 to read an X server (Xwayland
 * shows only X11 programs' windows). */
#import "ACapture.h"

static BOOL portal_available(void)
{
    ACaptureSayOnce("screen capture under Wayland needs the ScreenCast portal and PipeWire, which Ferry doesn't "
                    "speak yet; FERRY_CAPTURE=x11 reads an X server instead");
    return NO;
}
static NSArray *portal_nothing(void) { return @[]; }
static void *portal_open(void) { return NULL; }
static void portal_close(void *g) {}
static BOOL portal_grab_screen(void *g, CGRect r, ACaptureImage *out) { return NO; }
static BOOL portal_grab_window(void *g, uint64_t h, ACaptureImage *out, CGRect *f) { return NO; }
static BOOL portal_cursor(void *g, ACaptureCursor *out) { return NO; }

const ACaptureBackend ACapturePortalBackend = {
    "portal", portal_available, portal_nothing, portal_nothing, portal_open,
    portal_close, portal_grab_screen, portal_grab_window, portal_cursor,
};
