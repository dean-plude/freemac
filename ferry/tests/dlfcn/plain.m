/* SPDX-License-Identifier: GPL-3.0-or-later
 * The program of a plug-in bundle with no NSPrincipalClass (Plain.bundle),
 * whose principal class is then the first class it defines. */
#import <Foundation/Foundation.h>

@interface PlainThing : NSObject
@end
@implementation PlainThing
@end

@interface PlainOther : PlainThing
@end
@implementation PlainOther
@end
