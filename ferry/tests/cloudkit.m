/* Ferry test: CloudKit as a Mac with no iCloud account answers it, which is
 * what Flycut's iCloud sync meets: the account status, every database call
 * and operation failing with CKErrorNotAuthenticated, a cancelled operation,
 * records and their IDs as values (copied, compared, archived), and
 * SecTask's entitlements, which no Mac signature gives here. */
#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <stdio.h>

static dispatch_semaphore_t done;

static void wait_done(void)
{
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)))
        printf("  (timed out)\n");
}

static void records(void)
{
    CKRecordZoneID *zone = [[CKRecordZoneID alloc] initWithZoneName:@"Clippings" ownerName:CKCurrentUserDefaultName];
    CKRecordID *rid = [[CKRecordID alloc] initWithRecordName:@"clip-1" zoneID:zone];
    CKRecord *r = [[CKRecord alloc] initWithRecordType:@"Clipping" recordID:rid];
    r[@"text"] = @"hello";
    [r setObject:@3 forKey:@"index"];
    printf("record: %s %s in %s, text %s, keys %lu\n", [r.recordType UTF8String], [r.recordID.recordName UTF8String],
           [r.recordID.zoneID.zoneName UTF8String], [r[@"text"] UTF8String], (unsigned long)[[r allKeys] count]);
    CKRecord *copy = [r copy];
    copy[@"text"] = @"changed";
    printf("copy: its own values %d, same ID %d\n", [r[@"text"] isEqual:@"hello"], [copy.recordID isEqual:rid]);
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:r];
    CKRecord *back = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    printf("archived: %s, %s, index %s\n", [back.recordType UTF8String], [back.recordID.recordName UTF8String],
           [[back[@"index"] description] UTF8String]);
    CKRecord *fresh = [[CKRecord alloc] initWithRecordType:@"Clipping"];
    printf("a new record's name: %lu characters, default zone %s\n", (unsigned long)[fresh.recordID.recordName length],
           [fresh.recordID.zoneID.zoneName UTF8String]);
    CKReference *ref = [[CKReference alloc] initWithRecordID:rid action:CKReferenceActionDeleteSelf];
    printf("reference: %s, action %ld\n", [ref.recordID.recordName UTF8String], (long)ref.referenceAction);
}

static void account(void)
{
    CKContainer *c = [CKContainer defaultContainer];
    printf("default container: %s\n", [c.containerIdentifier UTF8String]);
    printf("named container: %s\n", [[CKContainer containerWithIdentifier:@"iCloud.org.example"].containerIdentifier
                                         UTF8String]);
    [c accountStatusWithCompletionHandler:^(CKAccountStatus status, NSError *error) {
        printf("account status: %ld (no account %d), error %s\n", (long)status, status == CKAccountStatusNoAccount,
               error ? "some" : "none");
        dispatch_semaphore_signal(done);
    }];
    wait_done();
    [c fetchUserRecordIDWithCompletionHandler:^(CKRecordID *rid, NSError *error) {
        printf("user record: %s, error %s %ld\n", rid ? "some" : "none", [error.domain UTF8String], (long)error.code);
        dispatch_semaphore_signal(done);
    }];
    wait_done();
}

static void databases(void)
{
    CKDatabase *db = [CKContainer defaultContainer].privateCloudDatabase;
    printf("private database scope: %ld\n", (long)db.databaseScope);
    CKRecord *r = [[CKRecord alloc] initWithRecordType:@"Clipping"];
    [db saveRecord:r completionHandler:^(CKRecord *saved, NSError *error) {
        printf("save: %s, error %ld (not authenticated %d)\n", saved ? "saved" : "nothing", (long)error.code,
               error.code == CKErrorNotAuthenticated);
        dispatch_semaphore_signal(done);
    }];
    wait_done();
    CKQuery *q = [[CKQuery alloc] initWithRecordType:@"Clipping" predicate:[NSPredicate predicateWithValue:YES]];
    [db performQuery:q inZoneWithID:nil completionHandler:^(NSArray *results, NSError *error) {
        printf("query: %lu results, error %ld\n", (unsigned long)[results count], (long)error.code);
        dispatch_semaphore_signal(done);
    }];
    wait_done();

    CKModifyRecordsOperation *op = [[CKModifyRecordsOperation alloc] initWithRecordsToSave:@[ r ] recordIDsToDelete:nil];
    __block int perRecord = 0;
    op.perRecordCompletionBlock = ^(CKRecord *record, NSError *error) {
        perRecord++;
    };
    op.modifyRecordsCompletionBlock = ^(NSArray *saved, NSArray *deleted, NSError *error) {
        printf("modify operation: %lu saved, error %s %ld\n", (unsigned long)[saved count], [error.domain UTF8String],
               (long)error.code);
        dispatch_semaphore_signal(done);
    };
    [db addOperation:op];
    wait_done();
    printf("  per-record blocks: %d\n", perRecord);

    CKFetchRecordsOperation *fetch = [[CKFetchRecordsOperation alloc] initWithRecordIDs:@[ r.recordID ]];
    fetch.fetchRecordsCompletionBlock = ^(NSDictionary *found, NSError *error) {
        printf("cancelled fetch: %lu records, error %ld (cancelled %d)\n", (unsigned long)[found count],
               (long)error.code, error.code == CKErrorOperationCancelled);
        dispatch_semaphore_signal(done);
    };
    [fetch cancel];
    [db addOperation:fetch];
    wait_done();
}

static void entitlements(void)
{
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    printf("SecTask: %s, type %d\n", task ? "some" : "none", task && CFGetTypeID(task) == SecTaskGetTypeID());
    CFErrorRef error = NULL;
    CFTypeRef v = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.developer.icloud-services"), &error);
    printf("its iCloud entitlement: %s\n", v ? "some" : "none");
    if (task)
        CFRelease(task);
}

int main(void)
{
    @autoreleasepool {
        done = dispatch_semaphore_create(0);
        records();
        account();
        databases();
        entitlements();
    }
    return 0;
}
