/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Address Book's shared book (freemac 1.233, Ferry 0.57.0;
 * appkit/AddressBook.m, served from Ferry's AppKit file). Written for
 * freemac from Apple's public API documentation; not Apple's header.
 * freemac doesn't hand an app the user's contacts, so the book is empty:
 * it has no "me" and no people. */
#ifndef _FERRY_ADDRESSBOOK_H_
#define _FERRY_ADDRESSBOOK_H_
#import <Foundation/Foundation.h>

@class ABPerson;
@interface ABRecord : NSObject
- (id)valueForProperty:(NSString *)property;
- (BOOL)setValue:(id)value forProperty:(NSString *)property;
- (NSString *)uniqueId;
@end
@interface ABPerson : ABRecord
@end
@interface ABGroup : ABRecord
@end
@interface ABAddressBook : NSObject
+ (ABAddressBook *)sharedAddressBook;
+ (ABAddressBook *)addressBook;
- (ABPerson *)me;
- (NSArray<ABPerson *> *)people;
- (NSArray<ABGroup *> *)groups;
- (BOOL)save;
- (BOOL)hasUnsavedChanges;
@end

FOUNDATION_EXPORT NSString *const kABFirstNameProperty;
FOUNDATION_EXPORT NSString *const kABLastNameProperty;
FOUNDATION_EXPORT NSString *const kABEmailProperty;
FOUNDATION_EXPORT NSString *const kABOrganizationProperty;
#endif
