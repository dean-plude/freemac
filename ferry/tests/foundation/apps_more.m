/* SPDX-License-Identifier: GPL-3.0-or-later
 * What Sparkle and the apps carrying it call that this round added to
 * Foundation, Core Services, IOKit and Security (freemac 1.223, Ferry
 * 0.47.0): uniform type identifiers; NSProcessInfo's activities and
 * termination counts; a bundle's localizations and the best of them for a
 * list of languages; CFBundleCopyInfoDictionaryInDirectory; base64 with
 * line lengths and ends, and the older names; FSPathCopyObjectSync; icon
 * references; IOKit's registry (empty) and power assertions; a DSA public
 * key imported from PEM and a signature checked by verify transforms, as
 * Sparkle checks an update, on the data and on its digest; an
 * authorization that grants nothing; and CF types cast to and from
 * Objective-C under ARC. Its files are in a home of the test's own. */
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <Security/Security.h>

static const char *yesno(BOOL b) { return b ? "yes" : "no"; }

static NSString *const publicKey =
    @"-----BEGIN PUBLIC KEY-----\n"
     "MIIDRDCCAjYGByqGSM44BAEwggIpAoIBAQD94wNc7uLrfmIC+XC8yy9DQ6aMEl2L\n"
     "rhYGPFTn7OWpuaEdPs35WaANmUhpyLJ32XP960QCq8+6MTeR1gwHTqa7l/w2syxL\n"
     "cHLp5YxRaQUcbtCCsJy4WtrariEdZy7igC3iO9uiIanTZZLloTJL0NlTsS8/XYfG\n"
     "KHpTyTx6wTAaNfDif1TDpkuvobqzzFaQjkzQj8YtmBG97kQhTBqVeKJGpYXKKNlW\n"
     "eiazUP4Hsjg8qQl+Jfx1UzVGtjgp52o4+ikkRna7p7x0u02/4na/nZNkeICQ7NCF\n"
     "YOli9MafekZT5Jb6WuRFeu9+SSKJllR2kv36XQZV/oj1cZEx5Wk7zYc1Ah0Ar1Wo\n"
     "fHz8VlEiE90lg8KSugQ+/SPSGzuWQ0OYYwKCAQEA5So1NJtNnvmdED5x8bg5/KoC\n"
     "7cEr11O2UF1mIuTgC/Fv+DB11lsGr0CuFxY5dsGIax7LPSZYD4pvtJVd1IygNbBM\n"
     "ww1wKvMkHH0OrqpvtqVOR5tmgVGTUf7hBZKuG5HUx3/Whyhi7ffNxPiINc08NbOe\n"
     "iSwDSzjSYMWG27/dIwjNwj6S6aX0/Dj2irVQQ54U/Wor2eZAkf5/Q+BeYKY8W20m\n"
     "DONXyKXuaKYTFy/lAkYFCNsztJWHzl+7riPvY5tTh5bgmFmTkgWypdpPUx5is9Yo\n"
     "fz5ZwfSzVNLsZBaqCVgJhhVUfHROkHcs8pIloh0scKCyo4sHM9gzGMQKrgWITwOC\n"
     "AQYAAoIBAQDjMPMY1dgo5cMOe8CiYObFKPLci+RpyqhA5CdkfCESMDYcEFFHi9Iu\n"
     "ALWr2Uwygq7iYm/gLgY7ZxHCJNw6HGIgqcMA+U4jevXKXrBlH/Y/4LNAm1tYnU5d\n"
     "9CWD2vsXWoeP3qM0tcp09xLlzRK1dwQX2NRjegj1enNyyadxHFvqiqxF6DdKqUcX\n"
     "pNobOI6LymHf9idg8I46zsfQ0P/pBwmyjquJpyhkBfPS8HOKa5urWVqJvJ3tOWH/\n"
     "fxfGh4ETK77ejz6RLSbxdrnd2xUGGQTSmmO8cKR9fV468OMRFCuEIZKsEYgdQmFa\n"
     "ZUTFAn0pa2w/Zrib6m9A0Q0Hg0VBTBQ9\n"
     "-----END PUBLIC KEY-----\n";
/* openssl dgst -sha1 -sign over the data below, with the key's private half */
static NSString *const signature =
    @"MD0CHFxNFpf+HEXdFrPkYO+t/pLn9Q27nkWX+BBD9YwCHQCMbj+GCaf7nma5kNqykA9QPN5FFcZmMo39px6D";
static NSString *const signedText = @"An update archive, as Sparkle checks it.\n";

static SecKeyRef import_key(void)
{
    NSData *pem = [publicKey dataUsingEncoding:NSUTF8StringEncoding];
    SecExternalFormat format = kSecFormatPEMSequence;
    SecExternalItemType type = kSecItemTypePublicKey;
    CFArrayRef items = NULL;
    OSStatus st = SecItemImport((__bridge CFDataRef)pem, NULL, &format, &type, 0, NULL, NULL, &items);
    printf("SecItemImport: %d, %ld item(s)\n", (int)st, items ? (long)CFArrayGetCount(items) : 0L);
    SecKeyRef key = items && CFArrayGetCount(items) ? (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0)) : NULL;
    if (items)
        CFRelease(items);
    return key;
}

/* Sparkle's way: read the file, take its SHA-1, check the signature on it */
static BOOL verify(SecKeyRef key, NSData *data, NSData *sig, BOOL throughDigest)
{
    CFErrorRef error = NULL;
    SecTransformRef verifier = SecVerifyTransformCreate(key, (__bridge CFDataRef)sig, &error);
    if (!verifier)
        return NO;
    CFTypeRef result;
    if (throughDigest) {
        NSInputStream *stream = [NSInputStream inputStreamWithData:data];
        SecTransformRef reader = SecTransformCreateReadTransformWithReadStream((__bridge CFReadStreamRef)stream);
        SecTransformRef digest = SecDigestTransformCreate(kSecDigestSHA1, 0, &error);
        SecGroupTransformRef group = SecTransformCreateGroupTransform();
        SecTransformConnectTransforms(reader, kSecTransformOutputAttributeName, digest, kSecTransformInputAttributeName,
                                      group, &error);
        SecTransformConnectTransforms(digest, kSecTransformOutputAttributeName, verifier,
                                      kSecTransformInputAttributeName, group, &error);
        result = SecTransformExecute(group, &error);
        CFRelease(group);
        CFRelease(digest);
        CFRelease(reader);
    } else {
        SecTransformSetAttribute(verifier, kSecTransformInputAttributeName, (__bridge CFDataRef)data, &error);
        result = SecTransformExecute(verifier, &error);
    }
    CFRelease(verifier);
    BOOL ok = result && CFGetTypeID(result) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)result);
    if (result)
        CFRelease(result);
    return ok;
}

static void write_text(NSString *path, NSString *text)
{
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    [text writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
}

int main(void)
{
    @autoreleasepool {
        NSString *home = NSHomeDirectory();

        /* uniform type identifiers */
        CFStringRef png = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("png"), NULL);
        printf("png: %s, an image %s, data %s, text %s\n", [(__bridge NSString *)png UTF8String],
               yesno(UTTypeConformsTo(png, kUTTypeImage)), yesno(UTTypeConformsTo(png, kUTTypeData)),
               yesno(UTTypeConformsTo(png, kUTTypeText)));
        CFStringRef mime = UTTypeCopyPreferredTagWithClass(png, kUTTagClassMIMEType);
        printf("  its MIME type %s, declared %s, dynamic %s\n", [(__bridge NSString *)mime UTF8String],
               yesno(UTTypeIsDeclared(png)), yesno(UTTypeIsDynamic(png)));
        CFRelease(mime);
        CFRelease(png);
        CFStringRef zip = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, CFSTR("application/zip"), NULL);
        printf("application/zip: %s, an archive %s\n", [(__bridge NSString *)zip UTF8String],
               yesno(UTTypeConformsTo(zip, CFSTR("public.archive"))));
        CFRelease(zip);
        CFStringRef odd = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("ferrything"), NULL);
        printf("an unknown extension: dynamic %s, data %s, equal to itself in other case %s\n",
               yesno(UTTypeIsDynamic(odd)), yesno(UTTypeConformsTo(odd, kUTTypeData)),
               yesno(UTTypeEqual(odd, (__bridge CFStringRef)[(__bridge NSString *)odd uppercaseString])));
        CFRelease(odd);
        printf("UTTypeEqual(public.PNG, public.png): %s\n", yesno(UTTypeEqual(CFSTR("public.PNG"), CFSTR("public.png"))));
        printf("OSType 'TEXT' as a string: %s\n", [(__bridge_transfer NSString *)UTCreateStringForOSType('TEXT') UTF8String]);

        /* NSProcessInfo */
        NSProcessInfo *pi = [NSProcessInfo processInfo];
        id<NSObject> activity = [pi beginActivityWithOptions:NSActivityUserInitiated reason:@"checking for updates"];
        printf("activity: %s\n", [[activity description] UTF8String]);
        [pi endActivity:activity];
        __block BOOL ran = NO;
        [pi performActivityWithOptions:NSActivityBackground reason:@"a block" usingBlock:^{ ran = YES; }];
        printf("performActivity ran its block: %s\n", yesno(ran));
        [pi disableSuddenTermination];
        [pi enableSuddenTermination];
        [pi setAutomaticTerminationSupportEnabled:YES];
        printf("automatic termination support: %s, thermal state nominal %s, low power %s\n",
               yesno([pi automaticTerminationSupportEnabled]),
               yesno([pi thermalState] == NSProcessInfoThermalStateNominal), yesno([pi isLowPowerModeEnabled]));

        /* a bundle's localizations */
        NSString *bundle = [home stringByAppendingPathComponent:@"Test.bundle"];
        write_text([bundle stringByAppendingPathComponent:@"Contents/Info.plist"],
                   @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\"><dict>"
                   @"<key>CFBundleIdentifier</key><string>org.example.test</string>"
                   @"<key>CFBundleDevelopmentRegion</key><string>English</string>"
                   @"<key>CFBundleShortVersionString</key><string>1.5</string></dict></plist>\n");
        for (NSString *l in @[ @"en", @"fr", @"pt_BR", @"Base" ])
            write_text([bundle stringByAppendingFormat:@"/Contents/Resources/%@.lproj/Localizable.strings", l],
                       @"\"Hello\" = \"Hello\";\n");
        NSBundle *b = [NSBundle bundleWithPath:bundle];
        NSArray *locs = [[b localizations] sortedArrayUsingSelector:@selector(compare:)];
        printf("localizations: %s, development %s\n", [[locs componentsJoinedByString:@" "] UTF8String],
               [[b developmentLocalization] UTF8String]);
        NSArray *offered = @[ @"en", @"fr", @"pt_BR" ];
        printf("for fr-CA: %s; for pt-PT: %s; for de: %s\n",
               [[[NSBundle preferredLocalizationsFromArray:offered forPreferences:@[ @"fr-CA" ]] firstObject] UTF8String],
               [[[NSBundle preferredLocalizationsFromArray:offered forPreferences:@[ @"pt-PT" ]] firstObject] UTF8String],
               [[[NSBundle preferredLocalizationsFromArray:offered forPreferences:@[ @"de" ]] firstObject] UTF8String]);
        CFDictionaryRef info = CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)[NSURL fileURLWithPath:bundle]);
        printf("CFBundleCopyInfoDictionaryInDirectory: %s version %s\n",
               [((__bridge NSDictionary *)info)[@"CFBundleIdentifier"] UTF8String],
               [((__bridge NSDictionary *)info)[@"CFBundleShortVersionString"] UTF8String]);
        CFRelease(info);
        printf("of a folder with no bundle: %s\n",
               yesno(CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)[NSURL fileURLWithPath:@"/nonexistent"]) ==
                     NULL));

        /* base64 */
        NSMutableData *bytes = [NSMutableData data];
        for (int i = 0; i < 60; i++) {
            unsigned char c = (unsigned char)(i * 7);
            [bytes appendBytes:&c length:1];
        }
        NSString *b64 = [bytes base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength |
                                                              NSDataBase64EncodingEndLineWithLineFeed];
        NSArray *lines = [b64 componentsSeparatedByString:@"\n"];
        printf("base64 in lines of 64: %lu lines, the first %lu long\n", (unsigned long)[lines count],
               (unsigned long)[lines[0] length]);
        NSString *crlf = [bytes base64EncodedStringWithOptions:NSDataBase64Encoding76CharacterLineLength];
        printf("in lines of 76 ended CR LF: %s\n", yesno([crlf rangeOfString:@"\r\n"].location == 76));
        NSData *back = [[NSData alloc] initWithBase64EncodedString:[b64 stringByAppendingString:@"*"]
                                                           options:NSDataBase64DecodingIgnoreUnknownCharacters];
        printf("decoded past an unknown character: %s; without the option: %s\n", yesno([back isEqualToData:bytes]),
               yesno([[NSData alloc] initWithBase64EncodedString:@"QUJD*" options:0] == nil));
        printf("the older names: %s\n",
               yesno([[[NSData alloc] initWithBase64Encoding:[bytes base64Encoding]] isEqualToData:bytes]));
        char fsbuf[8];
        printf("getFileSystemRepresentation into 8 bytes: \"short\" %s, \"much too long\" %s\n",
               yesno([@"short" getFileSystemRepresentation:fsbuf maxLength:sizeof fsbuf]),
               yesno([@"much too long" getFileSystemRepresentation:fsbuf maxLength:sizeof fsbuf]));

        /* the File Manager's copy */
        NSString *src = [home stringByAppendingPathComponent:@"from/report.txt"];
        write_text(src, @"copied");
        NSString *dest = [home stringByAppendingPathComponent:@"to"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:NULL];
        char *target = NULL;
        OSStatus st = FSPathCopyObjectSync([src fileSystemRepresentation], [dest fileSystemRepresentation],
                                           CFSTR("copy.txt"), &target, kFSFileOperationDefaultOptions);
        printf("FSPathCopyObjectSync: %d, \"%s\", to %s\n", (int)st,
               [[NSString stringWithContentsOfFile:[dest stringByAppendingPathComponent:@"copy.txt"]
                                          encoding:NSUTF8StringEncoding
                                             error:NULL] UTF8String],
               target ? [[[NSString stringWithUTF8String:target] lastPathComponent] UTF8String] : "-");
        free(target);
        printf("again, without overwriting: %d (dupFNErr %d)\n",
               (int)FSPathCopyObjectSync([src fileSystemRepresentation], [dest fileSystemRepresentation],
                                         CFSTR("copy.txt"), NULL, kFSFileOperationDefaultOptions),
               dupFNErr);
        printf("and with: %d\n", (int)FSPathCopyObjectSync([src fileSystemRepresentation], [dest fileSystemRepresentation],
                                                           CFSTR("copy.txt"), NULL, kFSFileOperationOverwrite));

        /* icon references */
        FSRef ref;
        FSPathMakeRef((const UInt8 *)[src fileSystemRepresentation], &ref, NULL);
        IconRef icon = NULL;
        st = GetIconRefFromFileInfo(&ref, 0, NULL, kFSCatInfoNone, NULL, kIconServicesNormalUsageFlag, &icon, NULL);
        printf("GetIconRefFromFileInfo: %d, an icon %s, acquired %d, released %d %d, of NULL %d\n", (int)st,
               yesno(icon != NULL), (int)AcquireIconRef(icon), (int)ReleaseIconRef(icon), (int)ReleaseIconRef(icon),
               (int)ReleaseIconRef(NULL));

        /* IOKit */
        io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
        printf("IOServiceGetMatchingService: %u\n", (unsigned)svc);
        IOPMAssertionID a1 = 0, a2 = 0;
        IOReturn r1 = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep, kIOPMAssertionLevelOn,
                                                  CFSTR("Copying"), &a1);
        IOReturn r2 = IOPMAssertionCreateWithDescription(kIOPMAssertPreventUserIdleDisplaySleep, CFSTR("Showing"),
                                                         CFSTR("details"), NULL, NULL, 0, NULL, &a2);
        CFDictionaryRef status = NULL;
        IOPMCopyAssertionsStatus(&status);
        printf("assertions: %d %d, different ids %s, no idle sleep held %s\n", r1, r2, yesno(a1 && a2 && a1 != a2),
               [[(__bridge NSDictionary *)status objectForKey:(__bridge NSString *)kIOPMAssertionTypeNoIdleSleep]
                   intValue]
                   ? "yes"
                   : "no");
        CFRelease(status);
        printf("released: %d %d, again %s\n", IOPMAssertionRelease(a1), IOPMAssertionRelease(a2),
               yesno(IOPMAssertionRelease(a1) != kIOReturnSuccess));

        /* a signature checked as Sparkle checks one */
        SecKeyRef key = import_key();
        NSData *data = [signedText dataUsingEncoding:NSUTF8StringEncoding];
        NSData *sig = [[NSData alloc] initWithBase64EncodedString:signature options:0];
        printf("verified on the data: %s, through a digest: %s\n", yesno(verify(key, data, sig, NO)),
               yesno(verify(key, data, sig, YES)));
        NSMutableData *changed = [data mutableCopy];
        ((unsigned char *)[changed mutableBytes])[0] ^= 1;
        printf("on changed data: %s, through a digest: %s\n", yesno(verify(key, changed, sig, NO)),
               yesno(verify(key, changed, sig, YES)));
        CFErrorRef error = NULL;
        printf("a signing transform: %s\n", yesno(SecSignTransformCreate(key, &error) == NULL && error != NULL));
        if (error)
            CFRelease(error);
        if (key)
            CFRelease(key);

        /* authorization */
        AuthorizationRef auth = NULL;
        st = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
        printf("AuthorizationCreate: %d\n", (int)st);
        AuthorizationItem right = {kAuthorizationRightExecute, 0, NULL, 0};
        AuthorizationRights rights = {1, &right};
        st = AuthorizationCopyRights(auth, &rights, NULL,
                                     kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights, NULL);
        printf("AuthorizationCopyRights: %d (denied %d)\n", (int)st, (int)errAuthorizationDenied);
        AuthorizationExternalForm ext;
        AuthorizationRef again = NULL;
        printf("external form: %d, back %d, same %s\n", (int)AuthorizationMakeExternalForm(auth, &ext),
               (int)AuthorizationCreateFromExternalForm(&ext, &again), yesno(again == auth));
        printf("AuthorizationFree: %d\n", (int)AuthorizationFree(auth, kAuthorizationFlagDestroyRights));

        /* ARC's casts of CF types, audited and not */
        CFStringRef made = CFStringCreateWithCString(NULL, "made by CF", kCFStringEncodingUTF8);
        NSString *owned = CFBridgingRelease(made);
        CFStringRef lent = (__bridge CFStringRef)owned;
        CFArrayRef arr = (__bridge_retained CFArrayRef) @[ owned ];
        printf("bridged: \"%s\" length %ld, array of %ld\n", [owned UTF8String], (long)CFStringGetLength(lent),
               (long)CFArrayGetCount(arr));
        CFRelease(arr);
    }
    return 0;
}
