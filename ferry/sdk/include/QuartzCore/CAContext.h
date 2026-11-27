/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: showing one program's layer in another's window. A context
 * (CAContext) gives a layer tree an ID; a layer host (CALayerHost) in any
 * program shows the tree of the context with that ID as its own sublayer.
 * Apple keeps these out of its public SDK; the calls here are the ones that
 * open-source Mac programs make (the Godot editor shows its running game
 * this way, Godot 4.5), written for freemac without Apple's headers. On
 * freemac a context publishes its layer's picture each time it changes
 * (ferry/quartzcore/CAContext.m) and a host shows the latest one. */
#ifndef _FERRY_QUARTZCORE_CACONTEXT_H_
#define _FERRY_QUARTZCORE_CACONTEXT_H_
#import <QuartzCore/QuartzCore.h>

__FERRY_BEGIN

typedef uint32_t CAContextID;

/* An options key: how the context treats Core Image filters (Ferry draws none) */
CA_EXTERN NSString *const kCAContextCIFilterBehavior;
/* Options keys taken and kept: whether the context shows on the display itself */
CA_EXTERN NSString *const kCAContextDisplayable;
CA_EXTERN NSString *const kCAContextIgnoresHitTest;

__FERRY_END

@interface CAContext : NSObject
/* A context to be shown in other programs ("remote"), on a window server
 * connection (any number: freemac has one window server) */
+ (instancetype)contextWithCGSConnection:(uint32_t)connection options:(NSDictionary *)options;
+ (instancetype)remoteContextWithOptions:(NSDictionary *)options;
+ (instancetype)localContextWithOptions:(NSDictionary *)options;
+ (NSArray<CAContext *> *)allContexts;
@property (readonly) CAContextID contextId;
@property (strong) CALayer *layer;
@property (readonly, copy) NSDictionary *options;
@property (readonly) BOOL valid;
/* Stops showing the layer; hosts showing it go blank */
- (void)invalidate;
@end

@interface CALayerHost : CALayer
/* The context whose layer this layer shows, 0 for none */
@property CAContextID contextId;
@end

#endif
