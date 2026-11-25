// SPDX-License-Identifier: GPL-3.0-or-later
//
// The Objective-C half of an app written in both languages: it uses the
// Swift classes in mixed.swift through the header ferry-swiftc wrote for
// them, as an Xcode project's code imports "App-Swift.h".

#import <Foundation/Foundation.h>
#import "Mixed-Swift.h"

int main(void)
{
    @autoreleasepool {
        FGreeter *g = [FGreeter shared];
        printf("%s\n", [[g greeting] UTF8String]);
        g.name = @"Ferry";
        printf("%s\n", [[g greeting] UTF8String]);
        printf("names %s\n", [[g.names componentsJoinedByString:@", "] UTF8String]);
        printf("letters %ld\n", (long)[g countOfLettersIn:@"Hex Fiend 2.18"]);
        printf("class %s, kind of NSObject %d\n", object_getClassName(g), [g isKindOfClass:[NSObject class]]);

        FPoint *p = [[FPoint alloc] initWithX:3 y:4];
        printf("point %s, x %ld\n", [[NSString stringWithFormat:@"%@", p] UTF8String], (long)p.x);
        NSArray *points = @[p, [[FPoint alloc] initWithX:-1 y:0]];
        printf("points %s\n", [[[points valueForKey:@"description"] componentsJoinedByString:@" "] UTF8String]);
    }
    return 0;
}
