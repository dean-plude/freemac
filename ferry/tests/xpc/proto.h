/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <Foundation/Foundation.h>
@protocol Echo
- (void)shout:(NSString *)word times:(NSInteger)n reply:(void (^)(NSString *, NSInteger))reply;
- (void)describe:(NSDictionary *)job reply:(void (^)(NSDictionary *))reply;
- (void)quit;
@end
