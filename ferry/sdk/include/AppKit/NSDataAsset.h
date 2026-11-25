/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSDataAsset, data from an app's asset catalogue, imported by
 * AppKit.h (freemac 1.224, Ferry 0.48.0). The catalogue is the one
 * ferry-actool compiled into the bundle's Assets.ferryassets
 * (appkit/NSAssets.m). Written for freemac from Apple's public API
 * documentation; not Apple's header. */
#ifndef _FERRY_APPKIT_NSDATAASSET_H_
#define _FERRY_APPKIT_NSDATAASSET_H_
#import <Foundation/Foundation.h>

typedef NSString *NSDataAssetName;

@interface NSDataAsset : NSObject <NSCopying>
- (instancetype)initWithName:(NSDataAssetName)name;
- (instancetype)initWithName:(NSDataAssetName)name bundle:(NSBundle *)bundle;
@property (readonly, copy) NSDataAssetName name;
@property (readonly, copy) NSData *data;
@property (readonly, copy) NSString *typeIdentifier;
@end

#endif
