/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: the Security framework subset Ferry provides. Written for
 * freemac from Apple's public API documentation; not Apple's header.
 * Every call declared here is implemented in ferry/security:
 *
 * - random bytes (SecRandomCopyBytes);
 * - keychain items: generic and internet passwords, through SecItem and
 *   the older SecKeychain calls, kept for the user in a file under
 *   ~/.local/share/ferry/keychain (see security/SecItem.m for how, and how
 *   little the file's encryption protects);
 * - code signing (SecCode, SecStaticCode, SecRequirement): Ferry can't
 *   check Apple's signatures; see security/SecCode.m for what it answers;
 * - certificates, policies and trust (SecCertificate, SecPolicy, SecTrust),
 *   checked by this system's OpenSSL against its certificate authorities.
 *
 * In Ferry every Security object is also an Objective-C object, so
 * CFRetain, CFRelease and CFEqual work on them. */
#ifndef _FERRY_SECURITY_H_
#define _FERRY_SECURITY_H_
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <stdbool.h>

__FERRY_BEGIN

/* ---- basics (SecBase.h) ------------------------------------------------------------ */

typedef int32_t OSStatus;
typedef uint32_t FourCharCode;
typedef FourCharCode OSType;
typedef uint16_t UInt16;

#ifndef _FERRY_SECURITY_TYPES_
#define _FERRY_SECURITY_TYPES_
typedef struct __SecTrust *SecTrustRef;
typedef struct __SecIdentity *SecIdentityRef;
#endif
typedef struct __SecCertificate *SecCertificateRef;
typedef struct __SecPolicy *SecPolicyRef;
typedef struct __SecKeychain *SecKeychainRef;
typedef struct __SecKeychainItem *SecKeychainItemRef;
typedef struct __SecKey *SecKeyRef;
typedef struct __SecAccess *SecAccessRef;

enum {
    errSecSuccess = 0,
    errSecUnimplemented = -4,
    errSecDiskFull = -34,
    errSecIO = -36,
    errSecOpWr = -49,
    errSecParam = -50,
    errSecWrPerm = -61,
    errSecAllocate = -108,
    errSecUserCanceled = -128,
    errSecBadReq = -909,
    errSecInternalComponent = -2070,
    errSecCoreFoundationUnknown = -4960,
    errSecNotAvailable = -25291,
    errSecReadOnly = -25292,
    errSecAuthFailed = -25293,
    errSecNoSuchKeychain = -25294,
    errSecInvalidKeychain = -25295,
    errSecDuplicateKeychain = -25296,
    errSecDuplicateCallback = -25297,
    errSecInvalidCallback = -25298,
    errSecDuplicateItem = -25299,
    errSecItemNotFound = -25300,
    errSecBufferTooSmall = -25301,
    errSecDataTooLarge = -25302,
    errSecNoSuchAttr = -25303,
    errSecInvalidItemRef = -25304,
    errSecInvalidSearchRef = -25305,
    errSecNoSuchClass = -25306,
    errSecNoDefaultKeychain = -25307,
    errSecInteractionNotAllowed = -25308,
    errSecReadOnlyAttr = -25309,
    errSecWrongSecVersion = -25310,
    errSecKeySizeNotAllowed = -25311,
    errSecNoStorageModule = -25312,
    errSecNoCertificateModule = -25313,
    errSecNoPolicyModule = -25314,
    errSecInteractionRequired = -25315,
    errSecDataNotAvailable = -25316,
    errSecDataNotModifiable = -25317,
    errSecCreateChainFailed = -25318,
    errSecInvalidPrefsDomain = -25319,
    errSecInDarkWake = -25320,
    errSecACLNotSimple = -25240,
    errSecPolicyNotFound = -25241,
    errSecInvalidTrustSetting = -25242,
    errSecNoAccessForItem = -25243,
    errSecInvalidOwnerEdit = -25244,
    errSecTrustNotAvailable = -25245,
    errSecUnsupportedFormat = -25256,
    errSecUnknownFormat = -25257,
    errSecKeyIsSensitive = -25258,
    errSecMultiplePrivKeys = -25259,
    errSecPassphraseRequired = -25260,
    errSecInvalidPasswordRef = -25261,
    errSecInvalidTrustSettings = -25262,
    errSecNoTrustSettings = -25263,
    errSecPkcs12VerifyFailure = -25264,
    errSecDecode = -26275,
    errSecMissingEntitlement = -34018,
    errSecHostNameMismatch = -67602,
    errSecCertificateExpired = -67818,
    errSecCertificateNotValidYet = -67819,
    errSecNotTrusted = -67843,
};

/* A message for a status, or NULL if there is none. */
CFStringRef SecCopyErrorMessageString(OSStatus status, void *reserved) CF_RETURNS_RETAINED;

/* ---- random bytes (SecRandom.h) ------------------------------------------------------ */

typedef const struct __SecRandom *SecRandomRef;
extern const SecRandomRef kSecRandomDefault;
/* errSecSuccess, from this system's kernel */
int SecRandomCopyBytes(SecRandomRef rnd, size_t count, void *bytes);

/* ---- keychain items (SecItem.h) ------------------------------------------------------
 * Generic passwords (kSecClassGenericPassword) and internet passwords
 * (kSecClassInternetPassword). Certificates, keys and identities are never
 * found, and can't be added (errSecUnimplemented). */

extern const CFStringRef kSecClass;
extern const CFStringRef kSecClassGenericPassword;
extern const CFStringRef kSecClassInternetPassword;
extern const CFStringRef kSecClassCertificate;
extern const CFStringRef kSecClassKey;
extern const CFStringRef kSecClassIdentity;

extern const CFStringRef kSecAttrAccessible;
extern const CFStringRef kSecAttrAccessGroup;
extern const CFStringRef kSecAttrSynchronizable;
extern const CFStringRef kSecAttrSynchronizableAny;
extern const CFStringRef kSecAttrCreationDate;
extern const CFStringRef kSecAttrModificationDate;
extern const CFStringRef kSecAttrDescription;
extern const CFStringRef kSecAttrComment;
extern const CFStringRef kSecAttrCreator;
extern const CFStringRef kSecAttrType;
extern const CFStringRef kSecAttrLabel;
extern const CFStringRef kSecAttrIsInvisible;
extern const CFStringRef kSecAttrIsNegative;
extern const CFStringRef kSecAttrAccount;
extern const CFStringRef kSecAttrService;
extern const CFStringRef kSecAttrGeneric;
extern const CFStringRef kSecAttrSecurityDomain;
extern const CFStringRef kSecAttrServer;
extern const CFStringRef kSecAttrProtocol;
extern const CFStringRef kSecAttrAuthenticationType;
extern const CFStringRef kSecAttrPort;
extern const CFStringRef kSecAttrPath;

extern const CFStringRef kSecAttrAccessibleWhenUnlocked;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlock;
extern const CFStringRef kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
extern const CFStringRef kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly;

extern const CFStringRef kSecAttrProtocolFTP;
extern const CFStringRef kSecAttrProtocolHTTP;
extern const CFStringRef kSecAttrProtocolHTTPS;
extern const CFStringRef kSecAttrProtocolHTTPProxy;
extern const CFStringRef kSecAttrProtocolHTTPSProxy;
extern const CFStringRef kSecAttrProtocolSSH;
extern const CFStringRef kSecAttrProtocolSMTP;
extern const CFStringRef kSecAttrProtocolIMAP;
extern const CFStringRef kSecAttrProtocolIMAPS;
extern const CFStringRef kSecAttrProtocolPOP3;
extern const CFStringRef kSecAttrProtocolLDAP;
extern const CFStringRef kSecAttrProtocolSOCKS;
extern const CFStringRef kSecAttrProtocolAFP;
extern const CFStringRef kSecAttrProtocolSMB;

extern const CFStringRef kSecAttrAuthenticationTypeDefault;
extern const CFStringRef kSecAttrAuthenticationTypeHTTPBasic;
extern const CFStringRef kSecAttrAuthenticationTypeHTTPDigest;
extern const CFStringRef kSecAttrAuthenticationTypeHTMLForm;
extern const CFStringRef kSecAttrAuthenticationTypeNTLM;

extern const CFStringRef kSecMatchLimit;
extern const CFStringRef kSecMatchLimitOne;
extern const CFStringRef kSecMatchLimitAll;
extern const CFStringRef kSecMatchCaseInsensitive;

extern const CFStringRef kSecReturnData;
extern const CFStringRef kSecReturnAttributes;
extern const CFStringRef kSecReturnRef;
extern const CFStringRef kSecReturnPersistentRef;

extern const CFStringRef kSecValueData;
extern const CFStringRef kSecValueRef;
extern const CFStringRef kSecValuePersistentRef;

extern const CFStringRef kSecUseDataProtectionKeychain;
extern const CFStringRef kSecUseKeychain;
extern const CFStringRef kSecUseAuthenticationUI;
extern const CFStringRef kSecUseOperationPrompt;

OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result);
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result);
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
OSStatus SecItemDelete(CFDictionaryRef query);

/* ---- the older keychain calls (SecKeychain.h, SecKeychainItem.h) ---------------------- */

typedef FourCharCode SecProtocolType;
typedef FourCharCode SecAuthenticationType;
typedef FourCharCode SecItemClass;
typedef FourCharCode SecKeychainAttrType;

enum {
    kSecProtocolTypeAny = 0,
    kSecProtocolTypeFTP = 'ftp ',
    kSecProtocolTypeHTTP = 'http',
    kSecProtocolTypeHTTPS = 'htps',
    kSecProtocolTypeHTTPProxy = 'htpx',
    kSecProtocolTypeHTTPSProxy = 'htsx',
    kSecProtocolTypeSSH = 'ssh ',
    kSecProtocolTypeSMTP = 'smtp',
    kSecProtocolTypeIMAP = 'imap',
    kSecProtocolTypeIMAPS = 'imps',
    kSecProtocolTypePOP3 = 'pop3',
    kSecProtocolTypeLDAP = 'ldap',
    kSecProtocolTypeSOCKS = 'sox ',
    kSecProtocolTypeAFP = 'afp ',
    kSecProtocolTypeSMB = 'smb ',
};
enum {
    kSecAuthenticationTypeAny = 0,
    kSecAuthenticationTypeNTLM = 'ntlm',
    kSecAuthenticationTypeHTTPBasic = 'http',
    kSecAuthenticationTypeHTTPDigest = 'httd',
    kSecAuthenticationTypeHTMLForm = 'form',
    kSecAuthenticationTypeDefault = 'dflt',
};
enum {
    kSecInternetPasswordItemClass = 'inet',
    kSecGenericPasswordItemClass = 'genp',
};
enum {
    kSecCreationDateItemAttr = 'cdat',
    kSecModDateItemAttr = 'mdat',
    kSecDescriptionItemAttr = 'desc',
    kSecCommentItemAttr = 'icmt',
    kSecCreatorItemAttr = 'crtr',
    kSecTypeItemAttr = 'type',
    kSecLabelItemAttr = 'labl',
    kSecInvisibleItemAttr = 'invi',
    kSecNegativeItemAttr = 'nega',
    kSecAccountItemAttr = 'acct',
    kSecServiceItemAttr = 'svce',
    kSecGenericItemAttr = 'gena',
    kSecSecurityDomainItemAttr = 'sdmn',
    kSecServerItemAttr = 'srvr',
    kSecAuthenticationTypeItemAttr = 'atyp',
    kSecPortItemAttr = 'port',
    kSecPathItemAttr = 'path',
    kSecProtocolItemAttr = 'ptcl',
};

typedef struct SecKeychainAttribute {
    SecKeychainAttrType tag;
    UInt32 length;
    void *data;
} SecKeychainAttribute;
typedef struct SecKeychainAttributeList {
    UInt32 count;
    SecKeychainAttribute *attr;
} SecKeychainAttributeList;

/* The user's one keychain; a keychain argument may be NULL for it. */
OSStatus SecKeychainCopyDefault(SecKeychainRef *keychain);
OSStatus SecKeychainSetUserInteractionAllowed(Boolean state);
OSStatus SecKeychainGetUserInteractionAllowed(Boolean *state);

OSStatus SecKeychainAddGenericPassword(SecKeychainRef keychain, UInt32 serviceNameLength, const char *serviceName,
                                      UInt32 accountNameLength, const char *accountName, UInt32 passwordLength,
                                      const void *passwordData, SecKeychainItemRef *itemRef);
/* A NULL (or empty) service or account matches any; *passwordData is
 * freed with SecKeychainItemFreeContent. */
OSStatus SecKeychainFindGenericPassword(CFTypeRef keychainOrArray, UInt32 serviceNameLength, const char *serviceName,
                                       UInt32 accountNameLength, const char *accountName, UInt32 *passwordLength,
                                       void **passwordData, SecKeychainItemRef *itemRef);
OSStatus SecKeychainAddInternetPassword(SecKeychainRef keychain, UInt32 serverNameLength, const char *serverName,
                                       UInt32 securityDomainLength, const char *securityDomain,
                                       UInt32 accountNameLength, const char *accountName, UInt32 pathLength,
                                       const char *path, UInt16 port, SecProtocolType protocol,
                                       SecAuthenticationType authenticationType, UInt32 passwordLength,
                                       const void *passwordData, SecKeychainItemRef *itemRef);
OSStatus SecKeychainFindInternetPassword(CFTypeRef keychainOrArray, UInt32 serverNameLength, const char *serverName,
                                        UInt32 securityDomainLength, const char *securityDomain,
                                        UInt32 accountNameLength, const char *accountName, UInt32 pathLength,
                                        const char *path, UInt16 port, SecProtocolType protocol,
                                        SecAuthenticationType authenticationType, UInt32 *passwordLength,
                                        void **passwordData, SecKeychainItemRef *itemRef);
OSStatus SecKeychainItemModifyAttributesAndData(SecKeychainItemRef itemRef, const SecKeychainAttributeList *attrList,
                                                UInt32 length, const void *data);
OSStatus SecKeychainItemDelete(SecKeychainItemRef itemRef);
OSStatus SecKeychainItemFreeContent(SecKeychainAttributeList *attrList, void *data);

/* ---- code signing (CSCommon.h, SecCode.h, SecStaticCode.h, SecRequirement.h) -------------
 * Ferry can't check Apple's code signatures. It answers the same way every
 * time: every piece of code reads as unsigned (its signing information has
 * no identifier, team or certificates, and it has no designated
 * requirement: errSecCSUnsigned), except that a validity check of the
 * running program's own code, with or without a requirement, passes. */

typedef struct __SecCode *SecCodeRef;
typedef struct __SecCode const *SecStaticCodeRef;
typedef struct __SecRequirement *SecRequirementRef;
typedef uint32_t SecCSFlags;

enum {
    kSecCSDefaultFlags = 0,
    kSecCSConsiderExpiration = 1u << 31,
    kSecCSEnforceRevocationChecks = 1u << 30,
    kSecCSNoNetworkAccess = 1u << 29,
    kSecCSReportProgress = 1u << 28,
    kSecCSCheckTrustedAnchors = 1u << 27,
    kSecCSQuickCheck = 1u << 26,
    kSecCSApplyEmbeddedPolicy = 1u << 25,
};
enum {
    kSecCSInternalInformation = 1 << 0,
    kSecCSSigningInformation = 1 << 1,
    kSecCSRequirementInformation = 1 << 2,
    kSecCSDynamicInformation = 1 << 3,
    kSecCSContentInformation = 1 << 4,
    kSecCSSkipResourceDirectory = 1 << 5,
    kSecCSCalculateCMSDigest = 1 << 6,
};
enum {
    kSecCSCheckAllArchitectures = 1 << 0,
    kSecCSDoNotValidateExecutable = 1 << 1,
    kSecCSDoNotValidateResources = 1 << 2,
    kSecCSBasicValidateOnly = kSecCSDoNotValidateExecutable | kSecCSDoNotValidateResources,
    kSecCSCheckNestedCode = 1 << 3,
    kSecCSStrictValidate = 1 << 4,
    kSecCSFullReport = 1 << 5,
    kSecCSCheckGatekeeperArchitectures = (1 << 6) | kSecCSCheckAllArchitectures,
    kSecCSRestrictSymlinks = 1 << 7,
    kSecCSRestrictToAppLike = 1 << 8,
    kSecCSRestrictSidebandData = 1 << 9,
    kSecCSUseSoftwareSigningCert = 1 << 10,
    kSecCSValidatePEH = 1 << 11,
    kSecCSSingleThreaded = 1 << 12,
};

enum {
    errSecCSUnimplemented = -67072,
    errSecCSInvalidObjectRef = -67071,
    errSecCSInvalidFlags = -67070,
    errSecCSObjectRequired = -67069,
    errSecCSStaticCodeNotFound = -67068,
    errSecCSUnsupportedGuestAttributes = -67067,
    errSecCSInvalidAttributeValues = -67066,
    errSecCSNoSuchCode = -67065,
    errSecCSMultipleGuests = -67064,
    errSecCSGuestInvalid = -67063,
    errSecCSUnsigned = -67062,
    errSecCSSignatureFailed = -67061,
    errSecCSSignatureNotVerifiable = -67060,
    errSecCSSignatureUnsupported = -67059,
    errSecCSBadDictionaryFormat = -67058,
    errSecCSResourcesNotSealed = -67057,
    errSecCSResourcesNotFound = -67056,
    errSecCSResourcesInvalid = -67055,
    errSecCSBadResource = -67054,
    errSecCSResourceRulesInvalid = -67053,
    errSecCSReqInvalid = -67052,
    errSecCSReqUnsupported = -67051,
    errSecCSReqFailed = -67050,
    errSecCSBadObjectFormat = -67049,
    errSecCSInternalError = -67048,
    errSecCSHostReject = -67047,
    errSecCSNotAHost = -67046,
    errSecCSSignatureInvalid = -67045,
};

extern const CFStringRef kSecCodeInfoCertificates;
extern const CFStringRef kSecCodeInfoChangedFiles;
extern const CFStringRef kSecCodeInfoCMS;
extern const CFStringRef kSecCodeInfoDesignatedRequirement;
extern const CFStringRef kSecCodeInfoEntitlements;
extern const CFStringRef kSecCodeInfoEntitlementsDict;
extern const CFStringRef kSecCodeInfoFlags;
extern const CFStringRef kSecCodeInfoFormat;
extern const CFStringRef kSecCodeInfoDigestAlgorithm;
extern const CFStringRef kSecCodeInfoIdentifier;
extern const CFStringRef kSecCodeInfoImplicitDesignatedRequirement;
extern const CFStringRef kSecCodeInfoMainExecutable;
extern const CFStringRef kSecCodeInfoPList;
extern const CFStringRef kSecCodeInfoRequirements;
extern const CFStringRef kSecCodeInfoRequirementData;
extern const CFStringRef kSecCodeInfoSource;
extern const CFStringRef kSecCodeInfoStatus;
extern const CFStringRef kSecCodeInfoTeamIdentifier;
extern const CFStringRef kSecCodeInfoTime;
extern const CFStringRef kSecCodeInfoTimestamp;
extern const CFStringRef kSecCodeInfoTrust;
extern const CFStringRef kSecCodeInfoUnique;
extern const CFStringRef kSecGuestAttributePid;

OSStatus SecCodeCopySelf(SecCSFlags flags, SecCodeRef *self);
OSStatus SecCodeCopyStaticCode(SecCodeRef code, SecCSFlags flags, SecStaticCodeRef *staticCode);
OSStatus SecCodeCopyGuestWithAttributes(SecCodeRef host, CFDictionaryRef attributes, SecCSFlags flags,
                                        SecCodeRef *guest);
OSStatus SecCodeCopyPath(SecStaticCodeRef staticCode, SecCSFlags flags, CFURLRef *path);
OSStatus SecStaticCodeCreateWithPath(CFURLRef path, SecCSFlags flags, SecStaticCodeRef *staticCode);
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes,
                                                  SecStaticCodeRef *staticCode);
OSStatus SecCodeCheckValidity(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement);
OSStatus SecCodeCheckValidityWithErrors(SecCodeRef code, SecCSFlags flags, SecRequirementRef requirement,
                                        CFErrorRef *errors);
OSStatus SecStaticCodeCheckValidity(SecStaticCodeRef staticCode, SecCSFlags flags, SecRequirementRef requirement);
OSStatus SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef staticCode, SecCSFlags flags,
                                              SecRequirementRef requirement, CFErrorRef *errors);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef *information);
OSStatus SecCodeCopyDesignatedRequirement(SecStaticCodeRef code, SecCSFlags flags, SecRequirementRef *requirement);
OSStatus SecRequirementCreateWithString(CFStringRef text, SecCSFlags flags, SecRequirementRef *requirement);
OSStatus SecRequirementCreateWithStringAndErrors(CFStringRef text, SecCSFlags flags, CFErrorRef *errors,
                                                 SecRequirementRef *requirement);
OSStatus SecRequirementCopyString(SecRequirementRef requirement, SecCSFlags flags, CFStringRef *text);

/* ---- certificates, policies and trust (SecCertificate.h, SecPolicy.h, SecTrust.h) -------- */

SecCertificateRef SecCertificateCreateWithData(CFAllocatorRef allocator, CFDataRef data) CF_RETURNS_RETAINED;
CFDataRef SecCertificateCopyData(SecCertificateRef certificate) CF_RETURNS_RETAINED;
CFStringRef SecCertificateCopySubjectSummary(SecCertificateRef certificate) CF_RETURNS_RETAINED;
OSStatus SecCertificateCopyCommonName(SecCertificateRef certificate, CFStringRef *commonName);

SecPolicyRef SecPolicyCreateBasicX509(void) CF_RETURNS_RETAINED;
SecPolicyRef SecPolicyCreateSSL(Boolean server, CFStringRef hostname) CF_RETURNS_RETAINED;

typedef uint32_t SecTrustResultType;
enum {
    kSecTrustResultInvalid = 0,
    kSecTrustResultProceed = 1,
    kSecTrustResultConfirm = 2,
    kSecTrustResultDeny = 3,
    kSecTrustResultUnspecified = 4,
    kSecTrustResultRecoverableTrustFailure = 5,
    kSecTrustResultFatalTrustFailure = 6,
    kSecTrustResultOtherError = 7,
};

/* certificates: one certificate or an array, the server's own first;
 * policies: one policy, an array of them, or NULL (basic X.509) */
OSStatus SecTrustCreateWithCertificates(CFTypeRef certificates, CFTypeRef policies, SecTrustRef *trust);
OSStatus SecTrustSetPolicies(SecTrustRef trust, CFTypeRef policies);
OSStatus SecTrustCopyPolicies(SecTrustRef trust, CFArrayRef *policies);
/* Only these are trusted from then on, unless SecTrustSetAnchorCertificatesOnly(trust, false). */
OSStatus SecTrustSetAnchorCertificates(SecTrustRef trust, CFArrayRef anchorCertificates);
OSStatus SecTrustSetAnchorCertificatesOnly(SecTrustRef trust, Boolean anchorCertificatesOnly);
OSStatus SecTrustSetVerifyDate(SecTrustRef trust, CFDateRef verifyDate);
bool SecTrustEvaluateWithError(SecTrustRef trust, CFErrorRef *error);
OSStatus SecTrustEvaluate(SecTrustRef trust, SecTrustResultType *result);
OSStatus SecTrustEvaluateAsyncWithError(SecTrustRef trust, dispatch_queue_t queue,
                                        void (^result)(SecTrustRef trust, bool trusted, CFErrorRef error));
OSStatus SecTrustGetTrustResult(SecTrustRef trust, SecTrustResultType *result);
/* The chain after evaluation (evaluated first if need be), the server's own first. */
CFIndex SecTrustGetCertificateCount(SecTrustRef trust);
SecCertificateRef SecTrustGetCertificateAtIndex(SecTrustRef trust, CFIndex ix);
CFArrayRef SecTrustCopyCertificateChain(SecTrustRef trust) CF_RETURNS_RETAINED;

__FERRY_END
#endif
