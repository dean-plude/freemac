/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: NSFileCoordinator and the NSFilePresenter protocol (freemac
 * 1.219, Ferry 0.43.0). Written for freemac from Apple's public
 * documentation; not Apple's header. A coordinator runs its accessor at
 * once, on the calling thread; the other presenters of the same item in this
 * program let go of it before a write and hear of it afterwards. Nothing
 * outside the program coordinates here. */
#ifndef _FERRY_FOUNDATION_NSFILECOORDINATOR_H_
#define _FERRY_FOUNDATION_NSFILECOORDINATOR_H_
#include <Foundation/Foundation.h>

@class NSOperationQueue, NSFileVersion;

@protocol NSFilePresenter <NSObject>
@property (readonly, copy) NSURL *presentedItemURL;
@property (readonly, retain) NSOperationQueue *presentedItemOperationQueue;
@optional
@property (readonly, copy) NSURL *primaryPresentedItemURL;
- (void)relinquishPresentedItemToReader:(void (^)(void (^reacquirer)(void)))reader;
- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer;
- (void)savePresentedItemChangesWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError *errorOrNil))completionHandler;
- (void)presentedItemDidMoveToURL:(NSURL *)newURL;
- (void)presentedItemDidChange;
- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
- (void)presentedSubitemDidChangeAtURL:(NSURL *)url;
- (void)presentedSubitemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;
@end

typedef NS_OPTIONS(NSUInteger, NSFileCoordinatorReadingOptions) {
    NSFileCoordinatorReadingWithoutChanges = 1 << 0,
    NSFileCoordinatorReadingResolvesSymbolicLink = 1 << 1,
    NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly = 1 << 2,
    NSFileCoordinatorReadingForUploading = 1 << 3,
};
typedef NS_OPTIONS(NSUInteger, NSFileCoordinatorWritingOptions) {
    NSFileCoordinatorWritingForDeleting = 1 << 0,
    NSFileCoordinatorWritingForMoving = 1 << 1,
    NSFileCoordinatorWritingForMerging = 1 << 2,
    NSFileCoordinatorWritingForReplacing = 1 << 3,
    NSFileCoordinatorWritingContentIndependentMetadataOnly = 1 << 4,
};

@interface NSFileCoordinator : NSObject
+ (void)addFilePresenter:(id<NSFilePresenter>)filePresenter;
+ (void)removeFilePresenter:(id<NSFilePresenter>)filePresenter;
@property (class, readonly, copy) NSArray<id<NSFilePresenter>> *filePresenters;
- (instancetype)initWithFilePresenter:(id<NSFilePresenter>)filePresenterOrNil;
@property (copy) NSString *purposeIdentifier;
- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options
                             error:(NSError **)outError byAccessor:(void (^)(NSURL *newURL))reader;
- (void)coordinateWritingItemAtURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options
                             error:(NSError **)outError byAccessor:(void (^)(NSURL *newURL))writer;
- (void)coordinateReadingItemAtURL:(NSURL *)readingURL options:(NSFileCoordinatorReadingOptions)readingOptions
                  writingItemAtURL:(NSURL *)writingURL options:(NSFileCoordinatorWritingOptions)writingOptions
                             error:(NSError **)outError
                        byAccessor:(void (^)(NSURL *newReadingURL, NSURL *newWritingURL))readerWriter;
- (void)coordinateWritingItemAtURL:(NSURL *)url1 options:(NSFileCoordinatorWritingOptions)options1
                  writingItemAtURL:(NSURL *)url2 options:(NSFileCoordinatorWritingOptions)options2
                             error:(NSError **)outError
                        byAccessor:(void (^)(NSURL *newURL1, NSURL *newURL2))writer;
- (void)prepareForReadingItemsAtURLs:(NSArray<NSURL *> *)readingURLs
                             options:(NSFileCoordinatorReadingOptions)readingOptions
                  writingItemsAtURLs:(NSArray<NSURL *> *)writingURLs
                             options:(NSFileCoordinatorWritingOptions)writingOptions
                               error:(NSError **)outError
                          byAccessor:(void (^)(void (^completionHandler)(void)))batchAccessor;
- (void)itemAtURL:(NSURL *)oldURL willMoveToURL:(NSURL *)newURL;
- (void)itemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;
- (void)cancel;
@end

#endif
