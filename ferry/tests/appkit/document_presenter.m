/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry test (freemac 1.220, Ferry 0.44.0): NSDocument as a file
 * presenter. A document the controller holds is one of NSFileCoordinator's
 * presenters, its URL its file's; a coordinated write to its file reads it
 * again while it has no unsaved changes and leaves it alone while it has;
 * its own coordinated write isn't told back to it; a move it is told of
 * moves its fileURL; closing it takes it off the list. Files go in a
 * folder of its own under TMPDIR. */
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <stdlib.h>

@interface Note : NSDocument
@property (copy) NSString *text;
@property int reads;
@end
@implementation Note
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
    self.text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.reads++;
    return YES;
}
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
    return [self.text dataUsingEncoding:NSUTF8StringEncoding];
}
@end

static BOOL presenting(id doc)
{
    for (id p in [NSFileCoordinator filePresenters])
        if (p == doc)
            return YES;
    return NO;
}

/* another part of the program writes the file, coordinated; the date is
 * moved on so that it differs from the one the document read */
static void write_over(NSURL *url, NSString *text, id presenter, int seconds)
{
    NSFileCoordinator *fc = [[NSFileCoordinator alloc] initWithFilePresenter:presenter];
    [fc coordinateWritingItemAtURL:url options:0 error:NULL byAccessor:^(NSURL *u) {
        [text writeToURL:u atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate : [NSDate dateWithTimeIntervalSinceNow:seconds]}
                                         ofItemAtPath:[u path] error:NULL];
    }];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        char tmpl[1024];
        snprintf(tmpl, sizeof tmpl, "%s/presenter.XXXXXX", [NSTemporaryDirectory() fileSystemRepresentation]);
        if (!mkdtemp(tmpl)) {
            perror("mkdtemp");
            return 1;
        }
        NSString *dir = [NSString stringWithUTF8String:tmpl];
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"note.txt"]];
        [@"first" writeToURL:url atomically:NO encoding:NSUTF8StringEncoding error:NULL];

        NSError *e = nil;
        Note *doc = [[Note alloc] initWithContentsOfURL:url ofType:@"public.plain-text" error:&e];
        printf("read: %s (%d), a presenter before it is held %d\n", [doc.text UTF8String], doc.reads, presenting(doc));
        NSDocumentController *dc = [NSDocumentController sharedDocumentController];
        [dc addDocument:doc];
        printf("held: a presenter %d, its URL its file's %d, on the main queue %d\n", presenting(doc),
               [[doc presentedItemURL] isEqual:url], [doc presentedItemOperationQueue] == [NSOperationQueue mainQueue]);

        write_over(url, @"second", nil, 10);
        printf("written over: %s (%d), edited %d\n", [doc.text UTF8String], doc.reads, [doc isDocumentEdited]);

        /* its own coordinated write is not told back to it */
        write_over(url, @"third", doc, 20);
        printf("its own write: %s (%d)\n", [doc.text UTF8String], doc.reads);

        /* unsaved changes stay */
        doc.text = @"mine";
        [doc updateChangeCount:NSChangeDone];
        write_over(url, @"fourth", nil, 30);
        printf("written over while edited: %s (%d), edited %d\n", [doc.text UTF8String], doc.reads,
               [doc isDocumentEdited]);
        [doc updateChangeCount:NSChangeCleared];

        /* a write to another file in the folder isn't its */
        NSURL *other = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"other.txt"]];
        write_over(other, @"elsewhere", nil, 40);
        printf("another file written: %s (%d)\n", [doc.text UTF8String], doc.reads);

        /* moved; the move is a coordinated write too, and the document, with no
         * unsaved changes now, reads the file written while it had some */
        NSURL *moved = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"moved.txt"]];
        NSFileCoordinator *fc = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [fc coordinateWritingItemAtURL:url options:NSFileCoordinatorWritingForMoving writingItemAtURL:moved
                               options:NSFileCoordinatorWritingForReplacing error:NULL
                            byAccessor:^(NSURL *from, NSURL *to) {
                                [[NSFileManager defaultManager] moveItemAtURL:from toURL:to error:NULL];
                                [fc itemAtURL:from didMoveToURL:to];
                            }];
        printf("moved: follows %d, named %s, %s (%d)\n", [[doc fileURL] isEqual:moved],
               [[doc displayName] UTF8String], [doc.text UTF8String], doc.reads);
        write_over(moved, @"fifth", nil, 50);
        printf("written over where it went: %s (%d)\n", [doc.text UTF8String], doc.reads);

        /* deleted: it keeps what it has */
        [fc coordinateWritingItemAtURL:moved options:NSFileCoordinatorWritingForDeleting error:NULL
                            byAccessor:^(NSURL *u) {
                                [[NSFileManager defaultManager] removeItemAtURL:u error:NULL];
                            }];
        printf("deleted: %s (%d)\n", [doc.text UTF8String], doc.reads);

        __weak Note *weak = doc;
        [doc close];
        doc = nil;
        printf("closed: a presenter %d, held %lu\n", presenting(weak), (unsigned long)[[dc documents] count]);
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    return 0;
}
