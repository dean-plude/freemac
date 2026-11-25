// SPDX-License-Identifier: GPL-3.0-or-later
//
// Stands in for Sparkle 1.x's binary-delta code (SUBinaryDeltaApply.m and
// SUBinaryDeltaCommon.m) when apps/recipe.sh builds Sparkle with Ferry's
// SDK (freemac 1.236, Ferry 0.60.0). That code reads delta archives with
// xar, a Mac system library this system doesn't have. A delta update then
// fails with this error, and Sparkle falls back to the full update, as it
// does whenever a delta can't be applied.
#import <Foundation/Foundation.h>

BOOL applyBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, BOOL verbose,
                      void (^progressCallback)(double), NSError *__autoreleasing *error);

BOOL applyBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, BOOL verbose,
                      void (^progressCallback)(double), NSError *__autoreleasing *error)
{
    (void)source, (void)destination, (void)patchFile, (void)verbose, (void)progressCallback;
    if (error)
        *error = [NSError errorWithDomain:@"SUSparkleErrorDomain" code:1000
                                 userInfo:@{NSLocalizedDescriptionKey :
                                                @"Delta updates can't be applied here: they need xar, which this system lacks."}];
    return NO;
}
