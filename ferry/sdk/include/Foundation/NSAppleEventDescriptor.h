/* SPDX-License-Identifier: GPL-3.0-or-later  (Ferry SDK)
 * NSAppleEventDescriptor and NSAppleEventManager (freemac 1.225, Ferry
 * 0.49.0): an Apple event descriptor as an object, over the Apple Event
 * Manager's descriptors (CoreServices/AppleEvents.h), and the table of an
 * app's Apple event handlers. As that header says, no other program on
 * freemac sends Apple events, so a handler is kept, and called when the
 * program itself dispatches an event to it with dispatchRawAppleEvent:.
 * Written from Apple's public documentation; not Apple's header.
 * Implemented in foundation/NSAppleEvents.m. */
#ifndef _FERRY_FOUNDATION_NSAPPLEEVENTDESCRIPTOR_H_
#define _FERRY_FOUNDATION_NSAPPLEEVENTDESCRIPTOR_H_
#include <CoreServices/CoreServices.h>

@interface NSAppleEventDescriptor : NSObject <NSCopying, NSSecureCoding>
+ (NSAppleEventDescriptor *)nullDescriptor;
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type bytes:(const void *)bytes length:(NSUInteger)length;
+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type data:(NSData *)data;
+ (NSAppleEventDescriptor *)descriptorWithBoolean:(Boolean)boolean;
+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)enumerator;
+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)signedInt;
+ (NSAppleEventDescriptor *)descriptorWithDouble:(double)doubleValue;
+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)typeCode;
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)string;
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)fileURL;
+ (NSAppleEventDescriptor *)descriptorWithBundleIdentifier:(NSString *)bundleIdentifier;
+ (NSAppleEventDescriptor *)descriptorWithProcessIdentifier:(pid_t)processIdentifier;
@property (class, readonly, strong) NSAppleEventDescriptor * FERRY_SWIFT_NONNULL currentProcessDescriptor;
+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                                    targetDescriptor:(NSAppleEventDescriptor *)target
                                            returnID:(AEReturnID)returnID
                                       transactionID:(AETransactionID)transactionID;
+ (NSAppleEventDescriptor *)listDescriptor;
+ (NSAppleEventDescriptor *)recordDescriptor;

- (instancetype FERRY_SWIFT_NONNULL)initWithAEDescNoCopy:(const AEDesc *)aeDesc;   /* takes the descriptor over */
- (instancetype)initWithDescriptorType:(DescType)type bytes:(const void *)bytes length:(NSUInteger)length;
- (instancetype)initWithDescriptorType:(DescType)type data:(NSData *)data;
- (instancetype)initListDescriptor;
- (instancetype)initRecordDescriptor;
- (instancetype)initWithEventClass:(AEEventClass)eventClass eventID:(AEEventID)eventID
                  targetDescriptor:(NSAppleEventDescriptor *)target
                          returnID:(AEReturnID)returnID
                     transactionID:(AETransactionID)transactionID;

@property (readonly) const AEDesc *aeDesc;
@property (readonly) DescType descriptorType;
@property (readonly, copy) NSData *data;
@property (readonly) Boolean booleanValue;
@property (readonly) OSType enumCodeValue;
@property (readonly) SInt32 int32Value;
@property (readonly) double doubleValue;
@property (readonly) OSType typeCodeValue;
@property (readonly, copy) NSString *stringValue;
@property (readonly, copy) NSURL *fileURLValue;
@property (readonly) AEEventClass eventClass;
@property (readonly) AEEventID eventID;
@property (readonly) AEReturnID returnID;
@property (readonly) AETransactionID transactionID;
@property (readonly) BOOL isRecordDescriptor;
@property (readonly) NSInteger numberOfItems;

- (void)setParamDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword;
- (void)removeParamDescriptorWithKeyword:(AEKeyword)keyword;
- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword;
/* lists count from 1, as the Apple Event Manager does */
- (void)insertDescriptor:(NSAppleEventDescriptor *)descriptor atIndex:(NSInteger)index;
- (NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index;
- (void)removeDescriptorAtIndex:(NSInteger)index;
- (void)setDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (NSAppleEventDescriptor *)descriptorForKeyword:(AEKeyword)keyword;
- (void)removeDescriptorWithKeyword:(AEKeyword)keyword;
- (AEKeyword)keywordForDescriptorAtIndex:(NSInteger)index;
- (NSAppleEventDescriptor *)coerceToDescriptorType:(DescType)descriptorType;
@end

@interface NSAppleEventManager : NSObject
+ (NSAppleEventManager * FERRY_SWIFT_NONNULL)sharedAppleEventManager;
/* handler is sent handleSelector with the event and its reply, each an
 * NSAppleEventDescriptor */
- (void)setEventHandler:(id)handler andSelector:(SEL)handleEventSelector forEventClass:(AEEventClass)eventClass
             andEventID:(AEEventID)eventID;
- (void)removeEventHandlerForEventClass:(AEEventClass)eventClass andEventID:(AEEventID)eventID;
/* the event being handled, while its handler runs */
@property (readonly, retain) NSAppleEventDescriptor *currentAppleEvent;
@property (readonly, retain) NSAppleEventDescriptor *currentReplyAppleEvent;
/* the event, to its handler: noErr when one handled it, errAEEventNotHandled otherwise */
- (OSErr)dispatchRawAppleEvent:(const AppleEvent *)theAppleEvent withRawReply:(AppleEvent *)theReply
                 handlerRefCon:(SRefCon)handlerRefCon;
@end

#endif
