/* Ferry submodule: CAMetalLayer.h takes only this from Metal, so importing
 * QuartzCore or AppKit doesn't bring in all of Metal's names. */
/* SPDX-License-Identifier: GPL-3.0-or-later
 * Metal: the pixel formats, from Apple's public Metal documentation. Metal/Metal.h
 * includes it; QuartzCore's CAMetalLayer.h includes only this, as on a Mac. */
/* Ferry submodule: MTLPixelFormat (freemac 1.262), so that a header that brings in
 * only this one (CAMetalLayer.h) doesn't bring in all of Metal.h with it. */
#ifndef FERRY_MTLPIXELFORMAT_H
#define FERRY_MTLPIXELFORMAT_H
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, MTLPixelFormat) {
    MTLPixelFormatInvalid = 0,
    MTLPixelFormatA8Unorm = 1,
    MTLPixelFormatR8Unorm = 10, MTLPixelFormatR8Unorm_sRGB = 11, MTLPixelFormatR8Snorm = 12,
    MTLPixelFormatR8Uint = 13, MTLPixelFormatR8Sint = 14,
    MTLPixelFormatR16Unorm = 20, MTLPixelFormatR16Snorm = 22, MTLPixelFormatR16Uint = 23,
    MTLPixelFormatR16Sint = 24, MTLPixelFormatR16Float = 25,
    MTLPixelFormatRG8Unorm = 30, MTLPixelFormatRG8Unorm_sRGB = 31, MTLPixelFormatRG8Snorm = 32,
    MTLPixelFormatRG8Uint = 33, MTLPixelFormatRG8Sint = 34,
    MTLPixelFormatB5G6R5Unorm = 40, MTLPixelFormatA1BGR5Unorm = 41, MTLPixelFormatABGR4Unorm = 42,
    MTLPixelFormatBGR5A1Unorm = 43,
    MTLPixelFormatR32Uint = 53, MTLPixelFormatR32Sint = 54, MTLPixelFormatR32Float = 55,
    MTLPixelFormatRG16Unorm = 60, MTLPixelFormatRG16Snorm = 62, MTLPixelFormatRG16Uint = 63,
    MTLPixelFormatRG16Sint = 64, MTLPixelFormatRG16Float = 65,
    MTLPixelFormatRGBA8Unorm = 70, MTLPixelFormatRGBA8Unorm_sRGB = 71, MTLPixelFormatRGBA8Snorm = 72,
    MTLPixelFormatRGBA8Uint = 73, MTLPixelFormatRGBA8Sint = 74,
    MTLPixelFormatBGRA8Unorm = 80, MTLPixelFormatBGRA8Unorm_sRGB = 81,
    MTLPixelFormatRGB10A2Unorm = 90, MTLPixelFormatRGB10A2Uint = 91, MTLPixelFormatRG11B10Float = 92,
    MTLPixelFormatRGB9E5Float = 93, MTLPixelFormatBGR10A2Unorm = 94,
    MTLPixelFormatBGR10_XR = 554, MTLPixelFormatBGR10_XR_sRGB = 555,
    MTLPixelFormatRG32Uint = 103, MTLPixelFormatRG32Sint = 104, MTLPixelFormatRG32Float = 105,
    MTLPixelFormatRGBA16Unorm = 110, MTLPixelFormatRGBA16Snorm = 112, MTLPixelFormatRGBA16Uint = 113,
    MTLPixelFormatRGBA16Sint = 114, MTLPixelFormatRGBA16Float = 115,
    MTLPixelFormatBGRA10_XR = 552, MTLPixelFormatBGRA10_XR_sRGB = 553,
    MTLPixelFormatRGBA32Uint = 123, MTLPixelFormatRGBA32Sint = 124, MTLPixelFormatRGBA32Float = 125,
    MTLPixelFormatBC1_RGBA = 130, MTLPixelFormatBC1_RGBA_sRGB = 131, MTLPixelFormatBC2_RGBA = 132,
    MTLPixelFormatBC2_RGBA_sRGB = 133, MTLPixelFormatBC3_RGBA = 134, MTLPixelFormatBC3_RGBA_sRGB = 135,
    MTLPixelFormatBC4_RUnorm = 140, MTLPixelFormatBC4_RSnorm = 141, MTLPixelFormatBC5_RGUnorm = 142,
    MTLPixelFormatBC5_RGSnorm = 143, MTLPixelFormatBC6H_RGBFloat = 150, MTLPixelFormatBC6H_RGBUfloat = 151,
    MTLPixelFormatBC7_RGBAUnorm = 152, MTLPixelFormatBC7_RGBAUnorm_sRGB = 153,
    MTLPixelFormatGBGR422 = 240, MTLPixelFormatBGRG422 = 241,
    MTLPixelFormatDepth16Unorm = 250, MTLPixelFormatDepth32Float = 252, MTLPixelFormatStencil8 = 253,
    MTLPixelFormatDepth24Unorm_Stencil8 = 255, MTLPixelFormatDepth32Float_Stencil8 = 260,
    MTLPixelFormatX32_Stencil8 = 261, MTLPixelFormatX24_Stencil8 = 262,
};

#endif
