/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry)
 * The Address Book, empty (freemac 1.NEXT, Ferry 0.NEXT): see AddressBook/AddressBook.h. */
#import <AddressBook/AddressBook.h>

NSString *const kABFirstNameProperty = @"First";
NSString *const kABLastNameProperty = @"Last";
NSString *const kABEmailProperty = @"Email";
NSString *const kABOrganizationProperty = @"Organization";

@implementation ABRecord {
    NSMutableDictionary *_values;
    NSString *_id;
}
- (void)dealloc
{
    [_values release];
    [_id release];
    [super dealloc];
}
- (id)valueForProperty:(NSString *)property { return _values[property]; }
- (BOOL)setValue:(id)value forProperty:(NSString *)property
{
    if (!property)
        return NO;
    if (!_values)
        _values = [[NSMutableDictionary alloc] init];
    if (value)
        _values[property] = value;
    else
        [_values removeObjectForKey:property];
    return YES;
}
- (NSString *)uniqueId
{
    if (!_id)
        _id = [[[NSUUID UUID] UUIDString] copy];
    return _id;
}
@end
@implementation ABPerson
@end
@implementation ABGroup
@end
@implementation ABAddressBook
+ (ABAddressBook *)sharedAddressBook
{
    static ABAddressBook *book;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ book = [[ABAddressBook alloc] init]; });
    return book;
}
+ (ABAddressBook *)addressBook { return [[[self alloc] init] autorelease]; }
- (ABPerson *)me { return nil; }
- (NSArray<ABPerson *> *)people { return @[]; }
- (NSArray<ABGroup *> *)groups { return @[]; }
- (BOOL)save { return YES; }
- (BOOL)hasUnsavedChanges { return NO; }
@end
