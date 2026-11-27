/* SPDX-License-Identifier: GPL-3.0-or-later
 * VLC's videotoolbox and cvpx modules (freemac 1.NEXT), as VLC's own Mac
 * build carries them. Written in C, as cvpx is: Core Animation's header
 * gives Core Video, <sys/types.h> gives htonl, and VideoToolbox's calls
 * fail as Apple documents for a missing decoder or converter, so VLC goes
 * on with its own software decoder. */
#include <QuartzCore/QuartzCore.h>
#include <VideoToolbox/VideoToolbox.h>
#include <VideoToolbox/VTErrors.h>
#include <sys/types.h>
#include <stdio.h>

static void out(void *ref, void *frame, OSStatus s, VTDecodeInfoFlags f, CVImageBufferRef img, CMTime pts, CMTime dur) {}

int main(void)
{
    printf("htonl: %08x\n", (unsigned)htonl(0x11223344));
    printf("core video from QuartzCore: %d\n", kCVPixelFormatType_32BGRA == 'BGRA');

    CMVideoFormatDescriptionRef fmt = NULL;
    OSStatus s = CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_H264, 640, 360, NULL, &fmt);
    printf("format: %d\n", (int)s);
    VTDecompressionOutputCallbackRecord cb = {out, NULL};
    VTDecompressionSessionRef dec = (VTDecompressionSessionRef)1;
    s = VTDecompressionSessionCreate(NULL, fmt, NULL, NULL, &cb, &dec);
    printf("decoder: %d (%s), session %s\n", (int)s, s == kVTCouldNotFindVideoDecoderErr ? "no decoder" : "?",
           dec ? "set" : "none");
    printf("hardware H.264: %d, takes new format: %d\n", VTIsHardwareDecodeSupported(kCMVideoCodecType_H264),
           VTDecompressionSessionCanAcceptFormatDescription(NULL, fmt));

    VTPixelTransferSessionRef px = (VTPixelTransferSessionRef)1;
    s = VTPixelTransferSessionCreate(NULL, &px);
    printf("pixel transfer: %d (%s), session %s\n", (int)s,
           s == kVTPixelTransferNotSupportedErr ? "not supported" : "?", px ? "set" : "none");

    CFStringRef atoms = kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms;
    printf("atoms key: %d, deinterlace key: %d\n",
           CFStringCompare(atoms, CFSTR("SampleDescriptionExtensionAtoms"), 0) == kCFCompareEqualTo,
           kVTDecompressionPropertyKey_DeinterlaceMode != NULL);
    CFRelease(fmt);
    return 0;
}
