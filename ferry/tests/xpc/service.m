/* SPDX-License-Identifier: GPL-3.0-or-later
 * The XPC service of tests/xpc/app.m. */
#import <Foundation/Foundation.h>
#import "proto.h"

@interface EchoService : NSObject <Echo, NSXPCListenerDelegate>
@end
@implementation EchoService
- (BOOL)listener:(NSXPCListener *)l shouldAcceptNewConnection:(NSXPCConnection *)c
{
    c.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(Echo)];
    c.exportedObject = self;
    [c resume];
    return YES;
}
- (void)shout:(NSString *)word times:(NSInteger)n reply:(void (^)(NSString *, NSInteger))reply
{
    NSMutableArray *a = [NSMutableArray array];
    for (NSInteger i = 0; i < n; i++)
        [a addObject:word.uppercaseString];
    reply([a componentsJoinedByString:@" "], getpid());
}
- (void)describe:(NSDictionary *)job reply:(void (^)(NSDictionary *))reply
{
    NSInteger sum = 0;
    for (NSNumber *t in job[@"tracks"])
        sum += t.integerValue;
    reply(@{@"name" : job[@"name"], @"sum" : @(sum)});
}
- (void)quit { exit(0); }
@end

int main(void)
{
    static EchoService *s;
    s = [EchoService new];
    NSXPCListener *l = [NSXPCListener serviceListener];
    l.delegate = s;
    [l resume];
    return 0;
}
