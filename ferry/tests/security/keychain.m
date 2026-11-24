// SPDX-License-Identifier: GPL-3.0-or-later
// Keychain items through SecItem and through the older SecKeychain calls,
// in a home of the test's own: generic and internet passwords added,
// found, changed and deleted, the documented status for each mistake, the
// folder's and files' modes, no secret in the clear on disk, and a secret
// that was tampered with refused. Run twice ("first", then "second"): what
// the first run keeps, the second finds. Every password here is made up.
// Built without ARC.
#import <Foundation/Foundation.h>
#include <Security/Security.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static NSString *folder;

static NSMutableDictionary *Q(id cls, ...)
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithObject:cls forKey:(id)kSecClass];
    va_list ap;
    va_start(ap, cls);
    for (id key; (key = va_arg(ap, id));)
        [d setObject:va_arg(ap, id) forKey:key];
    va_end(ap);
    return d;
}
#define GENP (id)kSecClassGenericPassword
#define INET (id)kSecClassInternetPassword
#define YES_ (id)kCFBooleanTrue
static NSData *D(const char *s) { return [NSData dataWithBytes:s length:strlen(s)]; }
static const char *T(id data)
{
    if (![data isKindOfClass:[NSData class]])
        return "(not data)";
    return [[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] UTF8String];
}

static OSStatus add(NSDictionary *d) { return SecItemAdd((CFDictionaryRef)d, NULL); }
static OSStatus find(NSDictionary *d, id *out)
{
    CFTypeRef r = NULL;
    OSStatus s = SecItemCopyMatching((CFDictionaryRef)d, &r);
    if (out)
        *out = [(id)r autorelease];
    else if (r)
        CFRelease(r);
    return s;
}
static const char *found_data(NSDictionary *q)
{
    NSMutableDictionary *m = [[q mutableCopy] autorelease];
    [m setObject:YES_ forKey:(id)kSecReturnData];
    id r = nil;
    OSStatus s = find(m, &r);
    return s ? [[NSString stringWithFormat:@"status %d", (int)s] UTF8String] : T(r);
}

static void modes(void)
{
    struct stat st;
    const char *names[] = {"", "/key", "/items.plist", "/lock"};
    for (int i = 0; i < 4; i++) {
        NSString *p = [folder stringByAppendingString:[NSString stringWithUTF8String:names[i]]];
        if (stat([p fileSystemRepresentation], &st) == 0)
            printf("  keychain%s: %s %o\n", names[i], S_ISDIR(st.st_mode) ? "folder" : "file", (unsigned)(st.st_mode & 0777));
        else
            printf("  keychain%s: absent\n", names[i]);
    }
}

static void first(void)
{
    printf("before anything is added\n");
    printf("  find: %d\n", (int)find(Q(GENP, kSecAttrService, @"org.example.notes", nil), NULL));
    printf("  delete: %d\n", (int)SecItemDelete((CFDictionaryRef)Q(GENP, kSecAttrService, @"org.example.notes", nil)));
    modes();

    printf("generic passwords\n");
    NSDictionary *ann = Q(GENP, kSecAttrService, @"org.example.notes", kSecAttrAccount, @"ann", kSecValueData,
                          D("made-up-1"), kSecAttrLabel, @"Notes (ann)", kSecAttrComment, @"a test item", nil);
    printf("  add ann: %d\n", (int)add(ann));
    printf("  add ann again: %d\n", (int)add(ann));
    printf("  add bob: %d\n", (int)add(Q(GENP, kSecAttrService, @"org.example.notes", kSecAttrAccount, @"bob",
                                         kSecValueData, D("made-up-2"), kSecAttrGeneric, D("extra"), nil)));
    printf("  add with only a service: %d\n", (int)add(Q(GENP, kSecAttrService, @"org.example.empty", nil)));
    modes();
    NSData *file = [NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"items.plist"]];
    BOOL clear = [file rangeOfData:D("made-up-1") options:0 range:NSMakeRange(0, [file length])].location != NSNotFound;
    printf("  a secret in the clear on disk: %s\n", clear ? "yes" : "no");

    printf("  ann's password: %s\n", found_data(Q(GENP, kSecAttrService, @"org.example.notes", kSecAttrAccount, @"ann", nil)));
    printf("  the first one's password: %s\n", found_data(Q(GENP, kSecAttrService, @"org.example.notes", nil)));
    printf("  ANN's, case-insensitively: %s\n",
           found_data(Q(GENP, kSecAttrAccount, @"ANN", kSecMatchCaseInsensitive, YES_, nil)));
    printf("  ANN's: %s\n", found_data(Q(GENP, kSecAttrAccount, @"ANN", nil)));
    printf("  found, nothing returned: %d\n", (int)find(Q(GENP, kSecAttrAccount, @"bob", nil), NULL));

    id all = nil;
    OSStatus s = find(Q(GENP, kSecAttrService, @"org.example.notes", kSecMatchLimit, kSecMatchLimitAll,
                        kSecReturnAttributes, YES_, nil), &all);
    printf("  all attributes: %d, %s of %lu\n", (int)s, [all isKindOfClass:[NSArray class]] ? "an array" : "not an array",
           (unsigned long)[all count]);
    for (NSDictionary *a in all) {
        NSMutableArray *keys = [NSMutableArray array];
        for (NSString *k in [[a allKeys] sortedArrayUsingSelector:@selector(compare:)])
            if (![k isEqual:(id)kSecAttrCreationDate] && ![k isEqual:(id)kSecAttrModificationDate])
                [keys addObject:k];
        printf("    %s: class %s, label %s, sync %d, generic %s, dates %s\n",
               [[a objectForKey:(id)kSecAttrAccount] UTF8String],
               [[a objectForKey:(id)kSecClass] isEqual:GENP] ? "generic password" : "?",
               [[a objectForKey:(id)kSecAttrLabel] UTF8String] ?: "(none)",
               [[a objectForKey:(id)kSecAttrSynchronizable] intValue],
               [a objectForKey:(id)kSecAttrGeneric] ? T([a objectForKey:(id)kSecAttrGeneric]) : "(none)",
               [[a objectForKey:(id)kSecAttrCreationDate] isKindOfClass:[NSDate class]] &&
                       [[a objectForKey:(id)kSecAttrModificationDate] isKindOfClass:[NSDate class]]
                   ? "yes"
                   : "no");
    }
    id two = nil;
    s = find(Q(GENP, kSecAttrAccount, @"bob", kSecReturnData, YES_, kSecReturnAttributes, YES_, kSecReturnRef, YES_,
               kSecReturnPersistentRef, YES_, nil), &two);
    printf("  bob, everything: %d, a dictionary %d, password %s, account %s, a ref %d, a persistent ref %d\n", (int)s,
           [two isKindOfClass:[NSDictionary class]], T([two objectForKey:(id)kSecValueData]),
           [[two objectForKey:(id)kSecAttrAccount] UTF8String], [two objectForKey:(id)kSecValueRef] != nil,
           [[two objectForKey:(id)kSecValuePersistentRef] isKindOfClass:[NSData class]]);
    printf("  bob by ref: %s\n", found_data(Q(GENP, kSecValueRef, [two objectForKey:(id)kSecValueRef], nil)));
    printf("  bob by persistent ref: %s\n",
           found_data(Q(GENP, kSecValuePersistentRef, [two objectForKey:(id)kSecValuePersistentRef], nil)));

    printf("changes\n");
    NSDictionary *annQ = Q(GENP, kSecAttrService, @"org.example.notes", kSecAttrAccount, @"ann", nil);
    printf("  update ann: %d\n", (int)SecItemUpdate((CFDictionaryRef)annQ,
                                                   (CFDictionaryRef)[NSDictionary dictionaryWithObjectsAndKeys:
                                                       D("made-up-3"), kSecValueData, @"Notes", kSecAttrLabel, nil]));
    id annA = nil;
    find(Q(GENP, kSecAttrAccount, @"ann", kSecReturnAttributes, YES_, nil), &annA);
    printf("  ann now: %s, label %s, changed after made %d\n", found_data(annQ),
           [[annA objectForKey:(id)kSecAttrLabel] UTF8String],
           [[annA objectForKey:(id)kSecAttrModificationDate] compare:[annA objectForKey:(id)kSecAttrCreationDate]] !=
               NSOrderedAscending);
    printf("  bob renamed ann: %d\n",
           (int)SecItemUpdate((CFDictionaryRef)Q(GENP, kSecAttrAccount, @"bob", nil),
                              (CFDictionaryRef)[NSDictionary dictionaryWithObject:@"ann" forKey:(id)kSecAttrAccount]));
    printf("  update nobody: %d\n",
           (int)SecItemUpdate((CFDictionaryRef)Q(GENP, kSecAttrAccount, @"nobody", nil),
                              (CFDictionaryRef)[NSDictionary dictionaryWithObject:@"x" forKey:(id)kSecAttrLabel]));
    printf("  update with a class in the changes: %d\n",
           (int)SecItemUpdate((CFDictionaryRef)annQ, (CFDictionaryRef)[NSDictionary dictionaryWithObject:GENP
                                                                                                    forKey:(id)kSecClass]));

    printf("mistakes\n");
    printf("  no class: %d\n", (int)add([NSDictionary dictionaryWithObject:@"x" forKey:(id)kSecAttrService]));
    printf("  an account that isn't text: %d\n", (int)add(Q(GENP, kSecAttrAccount, [NSNumber numberWithInt:3], nil)));
    printf("  a password that isn't data: %d\n", (int)add(Q(GENP, kSecAttrAccount, @"x", kSecValueData, @"text", nil)));
    printf("  a server on a generic password: %d\n", (int)add(Q(GENP, kSecAttrServer, @"example.invalid", nil)));
    printf("  a match limit when adding: %d\n", (int)add(Q(GENP, kSecMatchLimit, kSecMatchLimitAll, nil)));
    printf("  a bad match limit: %d\n", (int)find(Q(GENP, kSecMatchLimit, @"some", nil), NULL));
    printf("  a certificate: add %d, find %d, delete %d\n",
           (int)add(Q((id)kSecClassCertificate, kSecAttrLabel, @"x", nil)),
           (int)find(Q((id)kSecClassCertificate, nil), NULL),
           (int)SecItemDelete((CFDictionaryRef)Q((id)kSecClassCertificate, nil)));
    printf("  an unknown class: %d\n", (int)find(Q(@"nonsense", nil), NULL));

    printf("internet passwords\n");
    NSDictionary *web = Q(INET, kSecAttrServer, @"www.example.invalid", kSecAttrProtocol, kSecAttrProtocolHTTPS,
                          kSecAttrPort, [NSNumber numberWithInt:8443], kSecAttrPath, @"/login", kSecAttrAccount,
                          @"ann", kSecAttrAuthenticationType, kSecAttrAuthenticationTypeHTMLForm, nil);
    NSMutableDictionary *webAdd = [[web mutableCopy] autorelease];
    [webAdd setObject:D("made-up-4") forKey:(id)kSecValueData];
    printf("  add: %d, again %d\n", (int)add(webAdd), (int)add(webAdd));
    printf("  another path: %d\n", (int)add(Q(INET, kSecAttrServer, @"www.example.invalid", kSecAttrPath, @"/other",
                                              kSecAttrAccount, @"ann", kSecValueData, D("made-up-5"), nil)));
    printf("  by server and protocol: %s\n", found_data(Q(INET, kSecAttrServer, @"www.example.invalid",
                                                          kSecAttrProtocol, kSecAttrProtocolHTTPS, nil)));
    printf("  on port 80: %s\n", found_data(Q(INET, kSecAttrServer, @"www.example.invalid", kSecAttrPort,
                                              [NSNumber numberWithInt:80], nil)));
    printf("  a service on an internet password: %d\n", (int)find(Q(INET, kSecAttrService, @"x", nil), NULL));
    UInt32 len = 0;
    void *pw = NULL;
    SecKeychainItemRef ref = NULL;
    s = SecKeychainFindInternetPassword(NULL, 19, "www.example.invalid", 0, NULL, 3, "ann", 6, "/login", 8443,
                                        kSecProtocolTypeHTTPS, kSecAuthenticationTypeAny, &len, &pw, &ref);
    printf("  through the older call: %d, %.*s (%u bytes), a ref %d\n", (int)s, (int)len, pw ? (char *)pw : "",
           (unsigned)len, ref != NULL);
    SecKeychainItemFreeContent(NULL, pw);
    if (ref)
        CFRelease(ref);

    printf("synchronizable\n");
    printf("  add: %d\n", (int)add(Q(GENP, kSecAttrService, @"org.example.sync", kSecAttrSynchronizable, YES_,
                                     kSecValueData, D("made-up-6"), nil)));
    printf("  found by default: %s\n", found_data(Q(GENP, kSecAttrService, @"org.example.sync", nil)));
    printf("  with any: %s\n", found_data(Q(GENP, kSecAttrService, @"org.example.sync", kSecAttrSynchronizable,
                                            kSecAttrSynchronizableAny, nil)));
    printf("  with true: %s\n", found_data(Q(GENP, kSecAttrService, @"org.example.sync", kSecAttrSynchronizable,
                                             YES_, nil)));

    printf("the older calls\n");
    SecKeychainRef kc = NULL;
    printf("  default keychain: %d, %d\n", (int)SecKeychainCopyDefault(&kc), kc != NULL);
    if (kc)
        CFRelease(kc);
    s = SecKeychainAddGenericPassword(NULL, 15, "org.example.old", 5, "carol", 9, "made-up-7", &ref);
    printf("  add: %d, a ref %d\n", (int)s, ref != NULL);
    printf("  add again: %d\n", (int)SecKeychainAddGenericPassword(NULL, 15, "org.example.old", 5, "carol", 9,
                                                                    "made-up-7", NULL));
    pw = NULL;
    s = SecKeychainFindGenericPassword(NULL, 15, "org.example.old", 5, "carol", &len, &pw, NULL);
    printf("  find: %d, %.*s\n", (int)s, (int)len, pw ? (char *)pw : "");
    SecKeychainItemFreeContent(NULL, pw);
    s = SecKeychainFindGenericPassword(NULL, 15, "org.example.old", 0, NULL, NULL, NULL, NULL);
    printf("  find by service alone, nothing returned: %d\n", (int)s);
    printf("  SecItem sees it: %s, label %s\n", found_data(Q(GENP, kSecAttrAccount, @"carol", nil)), ({
               id a = nil;
               find(Q(GENP, kSecAttrAccount, @"carol", kSecReturnAttributes, YES_, nil), &a);
               [[a objectForKey:(id)kSecAttrLabel] UTF8String];
           }));
    char newAccount[] = "dave";
    SecKeychainAttribute at = {kSecAccountItemAttr, 4, newAccount};
    SecKeychainAttributeList list = {1, &at};
    printf("  change: %d\n", (int)SecKeychainItemModifyAttributesAndData(ref, &list, 9, "made-up-8"));
    printf("  now dave's: %s; carol's: %s\n", found_data(Q(GENP, kSecAttrAccount, @"dave", nil)),
           found_data(Q(GENP, kSecAttrAccount, @"carol", nil)));
    printf("  delete: %d, again %d\n", (int)SecKeychainItemDelete(ref), (int)SecKeychainItemDelete(ref));
    printf("  find: %d\n", (int)SecKeychainFindGenericPassword(NULL, 15, "org.example.old", 0, NULL, NULL, NULL, NULL));
    if (ref)
        CFRelease(ref);
    Boolean allowed = 0;
    SecKeychainSetUserInteractionAllowed(0);
    SecKeychainGetUserInteractionAllowed(&allowed);
    printf("  user interaction allowed: %d\n", allowed);

    printf("a secret tampered with\n");
    add(Q(GENP, kSecAttrService, @"org.example.tamper", kSecValueData, D("made-up-9"), nil));
    NSString *items = [folder stringByAppendingPathComponent:@"items.plist"];
    NSMutableDictionary *plist = [NSPropertyListSerialization propertyListWithData:[NSData dataWithContentsOfFile:items]
                                                                           options:NSPropertyListMutableContainers
                                                                            format:NULL error:NULL];
    for (NSMutableDictionary *item in [plist objectForKey:@"Items"])
        if ([[[item objectForKey:@"attributes"] objectForKey:(id)kSecAttrService] isEqual:@"org.example.tamper"]) {
            NSMutableData *secret = [[[item objectForKey:@"secret"] mutableCopy] autorelease];
            ((unsigned char *)[secret mutableBytes])[20] ^= 1;
            [item setObject:secret forKey:@"secret"];
        }
    [[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL]
        writeToFile:items atomically:NO];
    printf("  password: %s\n", found_data(Q(GENP, kSecAttrService, @"org.example.tamper", nil)));
    printf("  its attributes still: %d\n",
           (int)find(Q(GENP, kSecAttrService, @"org.example.tamper", kSecReturnAttributes, YES_, nil), NULL));
    printf("  delete it: %d\n", (int)SecItemDelete((CFDictionaryRef)Q(GENP, kSecAttrService, @"org.example.tamper", nil)));

    printf("delete\n");
    printf("  bob: %d\n", (int)SecItemDelete((CFDictionaryRef)Q(GENP, kSecAttrAccount, @"bob", nil)));
    printf("  bob again: %d\n", (int)SecItemDelete((CFDictionaryRef)Q(GENP, kSecAttrAccount, @"bob", nil)));
    printf("  find bob: %d\n", (int)find(Q(GENP, kSecAttrAccount, @"bob", nil), NULL));
}

static void second(void)
{
    printf("kept from the first run\n");
    modes();
    id all = nil;
    OSStatus s = find(Q(GENP, kSecMatchLimit, kSecMatchLimitAll, kSecReturnAttributes, YES_, kSecAttrSynchronizable,
                        kSecAttrSynchronizableAny, nil), &all);
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *a in all)
        [names addObject:[NSString stringWithFormat:@"%@/%@", [a objectForKey:(id)kSecAttrService],
                                                    [a objectForKey:(id)kSecAttrAccount] ?: @"-"]];
    printf("  generic passwords: %d, %s\n", (int)s,
           [[[names sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "] UTF8String]);
    printf("  ann's: %s\n", found_data(Q(GENP, kSecAttrAccount, @"ann", nil)));
    printf("  the web login: %s\n", found_data(Q(INET, kSecAttrServer, @"www.example.invalid", kSecAttrPath,
                                                 @"/login", nil)));
    printf("  delete every generic password: %d\n",
           (int)SecItemDelete((CFDictionaryRef)Q(GENP, kSecAttrSynchronizable, kSecAttrSynchronizableAny, nil)));
    printf("  delete every internet password: %d\n", (int)SecItemDelete((CFDictionaryRef)Q(INET, nil)));
    printf("  find any: %d\n", (int)find(Q(GENP, kSecAttrSynchronizable, kSecAttrSynchronizableAny, nil), NULL));

    printf("messages\n");
    OSStatus codes[] = {errSecSuccess, errSecItemNotFound, errSecDuplicateItem, errSecParam, errSecDecode, 12345};
    for (int i = 0; i < 6; i++) {
        CFStringRef m = SecCopyErrorMessageString(codes[i], NULL);
        printf("  %d: %s\n", (int)codes[i], m ? [(NSString *)m UTF8String] : "(none)");
        if (m)
            CFRelease(m);
    }
    unsigned char bytes[32] = {0}, zero[32] = {0};
    s = SecRandomCopyBytes(kSecRandomDefault, sizeof bytes, bytes);
    printf("random: %d, all zero %d\n", (int)s, !memcmp(bytes, zero, sizeof bytes));
}

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    folder = [[NSHomeDirectory() stringByAppendingPathComponent:@".local/share/ferry/keychain"] retain];
    if (argc > 1 && !strcmp(argv[1], "second"))
        second();
    else
        first();
    [pool drain];
    return 0;
}
