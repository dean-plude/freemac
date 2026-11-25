/* SPDX-License-Identifier: GPL-3.0-or-later
 * The older keychain calls Sequel Pro's SPKeychain makes (freemac 1.226,
 * Ferry 0.50.0): adding an item from an attribute list with an access
 * list, searching by attributes, and trusted applications. Runs in a home
 * of its own. */
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <string.h>

static SecKeychainAttribute attr(SecKeychainAttrType tag, const char *value)
{
    return (SecKeychainAttribute){tag, (UInt32)strlen(value), (void *)value};
}

static void add(const char *label, const char *service, const char *account, const char *password, SecAccessRef access)
{
    SecKeychainAttribute a[] = {attr(kSecLabelItemAttr, label), attr(kSecServiceItemAttr, service),
                                attr(kSecAccountItemAttr, account)};
    SecKeychainAttributeList list = {3, a};
    SecKeychainItemRef item = NULL;
    OSStatus st = SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list, (UInt32)strlen(password),
                                                   password, NULL, access, &item);
    printf("  added %s: %d, item %s\n", label, (int)st, item ? "made" : "none");
    if (item)
        CFRelease(item);
}

int main(void)
{
    @autoreleasepool {
        printf("trusted applications and access:\n");
        SecTrustedApplicationRef me = NULL, other = NULL;
        printf("  this program: %d\n", (int)SecTrustedApplicationCreateFromPath(NULL, &me));
        CFDataRef data = NULL;
        printf("  its data: %d, names it %d\n", (int)SecTrustedApplicationCopyData(me, &data),
               data && CFDataGetLength(data) > 0);
        if (data)
            CFRelease(data);
        printf("  no such file: %d, %s\n", (int)SecTrustedApplicationCreateFromPath("/no/such/app", &other),
               other ? "made" : "none");
        SecAccessRef access = NULL;
        printf("  access: %d, %s\n",
               (int)SecAccessCreate(CFSTR("Sequel Pro : localhost"), (CFArrayRef)@[ (id)me ], &access),
               access ? "made" : "none");

        printf("adding from attribute lists:\n");
        add("Sequel Pro : one", "Sequel Pro : one (1)", "root", "first secret", access);
        add("Sequel Pro : two", "Sequel Pro : two (2)", "admin", "second secret", NULL);
        SecKeychainAttribute dup[] = {attr(kSecServiceItemAttr, "Sequel Pro : one (1)"), attr(kSecAccountItemAttr, "root")};
        SecKeychainAttributeList dupList = {2, dup};
        printf("  the same again: %d\n", (int)SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &dupList,
                                                                               3, "abc", NULL, NULL, NULL));
        printf("  no class: %d\n", (int)SecKeychainItemCreateFromContent(0, &dupList, 3, "abc", NULL, NULL, NULL));

        UInt32 len = 0;
        void *pw = NULL;
        OSStatus st = SecKeychainFindGenericPassword(NULL, 20, "Sequel Pro : one (1)", 4, "root", &len, &pw, NULL);
        printf("  found: %d, \"%.*s\"\n", (int)st, (int)len, (char *)pw);
        SecKeychainItemFreeContent(NULL, pw);

        printf("searching:\n");
        SecKeychainAttribute by[] = {attr(kSecAccountItemAttr, "admin")};
        SecKeychainAttributeList byList = {1, by};
        SecKeychainSearchRef search = NULL;
        printf("  by account: %d\n",
               (int)SecKeychainSearchCreateFromAttributes(NULL, kSecGenericPasswordItemClass, &byList, &search));
        SecKeychainItemRef item = NULL;
        int found = 0;
        while (SecKeychainSearchCopyNext(search, &item) == errSecSuccess) {
            found++;
            CFRelease(item);
        }
        printf("  items: %d, then %d\n", found, (int)SecKeychainSearchCopyNext(search, &item));
        CFRelease(search);

        printf("  everything generic: %d\n",
               (int)SecKeychainSearchCreateFromAttributes(NULL, kSecGenericPasswordItemClass, NULL, &search));
        found = 0;
        while (SecKeychainSearchCopyNext(search, &item) == errSecSuccess) {
            found++;
            SecKeychainItemDelete(item);
            CFRelease(item);
        }
        printf("  items: %d, deleted\n", found);
        CFRelease(search);
        printf("  after deleting: %d\n",
               (int)SecKeychainFindGenericPassword(NULL, 20, "Sequel Pro : one (1)", 4, "root", NULL, NULL, NULL));
        CFRelease(access);
        CFRelease(me);
    }
    return 0;
}
