/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: JavaScriptCore's JSVirtualMachine (freemac 1.222, Ferry
 * 0.46.0), from the public documentation of JavaScriptCore's Objective-C
 * API; not Apple's header. */
#ifndef _FERRY_JSVIRTUALMACHINE_H_
#define _FERRY_JSVIRTUALMACHINE_H_
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface JSVirtualMachine : NSObject
- (instancetype)init;
- (void)addManagedReference:(nullable id)object withOwner:(nullable id)owner;
- (void)removeManagedReference:(nullable id)object withOwner:(nullable id)owner;
@end
NS_ASSUME_NONNULL_END
#endif
